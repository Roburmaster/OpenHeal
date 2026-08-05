-- ============================================================================
-- db/db.lua (OpenHeal)
-- SavedVariables + Defaults + Accessors (profile-aware) - CPU SAFE
-- ============================================================================
local ADDON, ns = ...
ns = _G[ADDON] or ns or {}
_G[ADDON] = ns

-- Using new global name to avoid overwriting from old character specific files.
--
-- NOTE: do NOT default these to {} here. DB:Ensure() needs to see whether
-- OpenHealGlobalDB was actually restored from SavedVariables in order to decide
-- if the legacy OpenHealDB migration should run. Creating the table at file
-- scope made that check permanently false, so upgrading users silently lost
-- every profile they had.
local SV     = _G.OpenHealGlobalDB
local CharSV = _G.OpenHealCharDB

ns.DB = ns.DB or {}
local DB = ns.DB

local type = type
local pairs = pairs
local tonumber = tonumber

-- ------------------------------------------------------------
-- Profile payload defaults (per profile)
-- ------------------------------------------------------------
local DEFAULTS_PROFILE = {
    -- Look and feel, shared by every frame type.
    -- barTexture/font are LibSharedMedia *names*; ui/theme.lua resolves them to
    -- paths and falls back to a built-in if LSM is absent or the name is gone.
    style = {
        barTexture   = "Flat",
        font         = "Friz Quadrata",
        fontSize     = 11,
        fontOutline  = "OUTLINE",

        -- Animate health changes instead of snapping. Only possible when the
        -- game hands us a readable number; secret health snaps regardless.
        smoothing    = true,
        smoothRate   = 0.25,

        -- Colour the background by class and the bar by health, rather than
        -- the bar by class. Reads "how hurt" first, "who" second.
        classBG      = false,
    },

    aggro = {
        enabled  = true,
        size     = 2,
        onlyHigh = false,   -- true = only show real aggro, not "pulling"
        -- A tank holding threat is the normal state, so it is not flagged by
        -- default; turn this on if you want a positive "tank is fine" signal.
        showTankSecure = false,
    },

    pet = {
        enabled     = false,
        w           = 90,
        h           = 24,
        spacing     = 3,
        orientation = "VERTICAL",
        point       = "CENTER",
        relPoint    = "CENTER",
        x           = 320,
        y           = -140,
        locked      = false,
        classColor  = false,
        showParty   = true,
        showRaid    = false,
    },

    range = {
        enabled   = true,
        alphaIn   = 1.0,
        alphaOut  = 0.5,
        update    = 0.20,
        smoothing = 10,
    },

    targetedSpells = {
        enabled = true,
        maxIcons = 1,
        size     = 18,
        scale    = 1.0,
        spacing  = 2,
        anchor   = "TOPRIGHT",
        x        = -2,
        y        = -2,
        ignoreParentAlpha = true,
        showSwipe = true,
        showText  = true,
        watchNameplates = true,
    },

    party = {
        enabled = true,
        orientation = "HORIZONTAL",
        w = 210,
        h = 70,
        spacing = 6,
        point = "CENTER",
        relPoint = "CENTER",
        x = 0,
        y = -140,
        locked = false,
        showRole = true,
        showPower = true,
        sort = "NONE",
        classColor = true,
        showMover = true,
        allowDrag = true,

        showRaidMarker = true,
        raidMarkerSize = 16,

        fbuff = {
            enabled    = true,
            onlyMine   = false,
            maxIcons   = 3,
            size       = 16,
            spacing    = 2,
            anchor     = "TOP",
            relTo      = "hp",
            relPoint   = "TOP",
            x          = 0,
            y          = 2,
            showTimers = true,
            showStacks = true,
            mode       = "IMPORTANT",
            custom     = {},
        },

        debuff = {
            enabled = true,
            mode = "IMPORTANT",
            maxIcons = 3,
            size = 16,
            customOnlyDispellable = false,
            custom = {},
        },
    },

    raid = {
        enabled = true,
        orientation = "VERTICAL",
        w = 160,
        h = 46,
        spacing = 4,

        columns = 8,
        max = 40,

        point = "CENTER",
        relPoint = "CENTER",
        x = 0,
        y = 120,

        locked = false,

        showRole = false,
        showPower = false,
        sort = "NONE",
        classColor = true,

        showGroup = false,
        groupGap = nil,

        showRaidMarker = true,
        raidMarkerSize = 14,

        fbuff = {
            enabled    = true,
            onlyMine   = false,
            maxIcons   = 3,
            size       = 14,
            spacing    = 2,
            anchor     = "TOP",
            relTo      = "hp",
            relPoint   = "TOP",
            x          = 0,
            y          = 2,
            showTimers = true,
            showStacks = true,
            mode       = "IMPORTANT",
            custom     = {},
        },

        debuff = {
            enabled = true,
            mode = "IMPORTANT",
            maxIcons = 3,
            size = 14,
            customOnlyDispellable = false,
            custom = {},
        },

        tankFrames = false,
        tankAlsoInRaid = true,
        tankSide = "LEFT",
        tankW = nil,
        tankH = nil,
        tankSpacing = nil,
        tankOffsetX = nil,
        tankOffsetY = nil,

        _settingsRaid = {
            point = "CENTER",
            relPoint = "CENTER",
            x = 0,
            y = 0,
        },

        _simOn = false,
    },
}

-- ------------------------------------------------------------
-- DB Root defaults
-- ------------------------------------------------------------
local CURRENT_DB_VERSION = 1

-- GLOBAL (Account-wide)
local DEFAULTS_GLOBAL = {
    dbVersion = CURRENT_DB_VERSION,
    profiles = {
        ["Default"] = {},
    },
}

-- LOCAL (Per-character)
local DEFAULTS_CHAR = {
    activeProfile = "Default",
    specProfile = {},
    profileOpts = {
        autoLoadOnSpecChange = true,
    },
}

-- ------------------------------------------------------------
-- Deep copy + merge-missing
-- ------------------------------------------------------------
local function DeepCopy(src)
    local t = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            t[k] = DeepCopy(v)
        else
            t[k] = v
        end
    end
    return t
end

local function MergeMissing(dst, defaults)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(defaults) do
        local cur = dst[k]
        if cur == nil then
            dst[k] = (type(v) == "table") and DeepCopy(v) or v
        elseif type(cur) == "table" and type(v) == "table" then
            MergeMissing(cur, v)
        end
    end
    return dst
end

local function NormalizeProfileName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    return name
end

-- ------------------------------------------------------------
-- Internal state (CPU guards + cache)
-- ------------------------------------------------------------
DB._ensured   = DB._ensured or false
DB._activeKey = DB._activeKey or nil
DB._activeTbl = DB._activeTbl or nil

function ns:InvalidateProfileCache()
    if ns.DB then
        ns.DB._activeKey = nil
        ns.DB._activeTbl = nil
    end
end

local function EnsureProfileExistsAndDefaults(profileKey)
    profileKey = NormalizeProfileName(profileKey) or "Default"
    SV.profiles = SV.profiles or {}
    SV.profiles[profileKey] = SV.profiles[profileKey] or {}
    SV.profiles[profileKey] = MergeMissing(SV.profiles[profileKey], DEFAULTS_PROFILE)
    return profileKey, SV.profiles[profileKey]
end

-- ------------------------------------------------------------
-- Ensure root structure + defaults + MIGRATION (RUN ONCE)
-- ------------------------------------------------------------
function DB:Ensure()
    if self._ensured then
        return _G.OpenHealGlobalDB, _G.OpenHealCharDB
    end

    -- MIGRATION: legacy OpenHealDB -> new global/char split.
    -- Runs only when OpenHealGlobalDB was never written, i.e. the first login
    -- after upgrading from a pre-split version.
    local legacy = _G.OpenHealDB
    if type(legacy) == "table" and not _G.OpenHealGlobalDB then
        _G.OpenHealGlobalDB = {}
        _G.OpenHealCharDB = _G.OpenHealCharDB or {}

        if legacy.profiles then
            _G.OpenHealGlobalDB.profiles = DeepCopy(legacy.profiles)
        end

        if legacy.activeProfile then
            _G.OpenHealCharDB.activeProfile = legacy.activeProfile
        end
        if legacy.specProfile then
            _G.OpenHealCharDB.specProfile = DeepCopy(legacy.specProfile)
        end
        if legacy.profileOpts then
            _G.OpenHealCharDB.profileOpts = DeepCopy(legacy.profileOpts)
        end

        -- Drop only the migrated keys. OpenHealDB itself must survive: BindView
        -- still stores its panel settings in OpenHealDB.bindview.
        legacy.profiles = nil
        legacy.activeProfile = nil
        legacy.specProfile = nil
        legacy.profileOpts = nil
        legacy.migratedTo = "OpenHealGlobalDB/OpenHealCharDB"
    end

    SV = _G.OpenHealGlobalDB or {}
    _G.OpenHealGlobalDB = SV

    CharSV = _G.OpenHealCharDB or {}
    _G.OpenHealCharDB = CharSV

    -- Root defaults (cheap)
    MergeMissing(SV, DEFAULTS_GLOBAL)
    MergeMissing(CharSV, DEFAULTS_CHAR)

    if type(SV.profiles) ~= "table" then SV.profiles = {} end
    if type(CharSV.specProfile) ~= "table" then CharSV.specProfile = {} end
    if type(CharSV.profileOpts) ~= "table" then CharSV.profileOpts = {} end
    if CharSV.profileOpts.autoLoadOnSpecChange == nil then
        CharSV.profileOpts.autoLoadOnSpecChange = true
    end

    -- Normalize active profile
    local ap = NormalizeProfileName(CharSV.activeProfile) or "Default"
    CharSV.activeProfile = ap

    -- Ensure Default + Active profile exist and have defaults merged (ONLY THESE)
    EnsureProfileExistsAndDefaults("Default")
    EnsureProfileExistsAndDefaults(ap)

    SV.dbVersion = tonumber(SV.dbVersion) or CURRENT_DB_VERSION
    if SV.dbVersion < CURRENT_DB_VERSION then SV.dbVersion = CURRENT_DB_VERSION end

    self._ensured = true
    return SV, CharSV
end

-- ------------------------------------------------------------
-- Public accessors used by the addon
-- ------------------------------------------------------------
function ns:GetGlobalDB()
    local g, _ = DB:Ensure()
    return g
end

function ns:GetCharDB()
    local _, c = DB:Ensure()
    return c
end

-- Backwards compatibility mapping
function ns:GetDB()
    return ns:GetGlobalDB()
end

function ns:GetActiveProfileKey()
    DB:Ensure()
    local g = SV
    local c = CharSV

    local ap = NormalizeProfileName(c.activeProfile) or "Default"
    if type(g.profiles[ap]) ~= "table" then
        ap = "Default"
        c.activeProfile = ap
        EnsureProfileExistsAndDefaults(ap)
        ns:InvalidateProfileCache()
    end
    return ap
end

function ns:GetProfileDB()
    DB:Ensure()
    local ap = ns:GetActiveProfileKey()

    if DB._activeKey == ap and DB._activeTbl then
        return DB._activeTbl
    end

    local _, tbl = EnsureProfileExistsAndDefaults(ap)
    DB._activeKey = ap
    DB._activeTbl = tbl
    return tbl
end

function ns:GetPartyDB()
    local p = ns:GetProfileDB()
    p.party = MergeMissing(p.party or {}, DEFAULTS_PROFILE.party)
    return p.party
end

function ns:GetRaidDB()
    local p = ns:GetProfileDB()
    p.raid = MergeMissing(p.raid or {}, DEFAULTS_PROFILE.raid)
    return p.raid
end

function ns:GetRangeDB()
    local p = ns:GetProfileDB()
    p.range = MergeMissing(p.range or {}, DEFAULTS_PROFILE.range)
    return p.range
end

function ns:GetTargetedSpellsDB()
    local p = ns:GetProfileDB()
    p.targetedSpells = MergeMissing(p.targetedSpells or {}, DEFAULTS_PROFILE.targetedSpells)
    return p.targetedSpells
end

function ns:GetStyleDB()
    local p = ns:GetProfileDB()
    p.style = MergeMissing(p.style or {}, DEFAULTS_PROFILE.style)
    return p.style
end

function ns:GetAggroDB()
    local p = ns:GetProfileDB()
    p.aggro = MergeMissing(p.aggro or {}, DEFAULTS_PROFILE.aggro)
    return p.aggro
end

function ns:GetPetDB()
    local p = ns:GetProfileDB()
    p.pet = MergeMissing(p.pet or {}, DEFAULTS_PROFILE.pet)
    return p.pet
end

-- Give Profile module access to helpers
DB._MergeMissing = MergeMissing
DB._NormalizeProfileName = NormalizeProfileName
DB._DEFAULTS_PROFILE = DEFAULTS_PROFILE
