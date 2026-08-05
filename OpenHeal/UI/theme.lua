-- ============================================================================
-- ui/theme.lua (OpenHeal)
-- Single source of truth for colours, fonts and bar textures.
--
-- WHY:
--   The addon had three visual languages: hardcoded WHITE8X8 + GameFontNormalSmall
--   on the frames, a custom "modern" look in the settings panel, and Blizzard's
--   BasicFrameTemplateWithInset in the click-cast window. Changing the look meant
--   hunting literals across a dozen files.
--
-- LibSharedMedia:
--   Support is OPTIONAL and detected at runtime. LSM is not embedded here - any
--   of ElvUI / WeakAuras / Details / Plater already provides it, and embedding a
--   copy would just add a version to keep in sync. Without LSM the built-in
--   textures below are used, so the addon is fully standalone either way.
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns or {}
_G[ADDON] = ns

ns.Theme = ns.Theme or {}
local T = ns.Theme

local type = type
local pcall = pcall
local ipairs = ipairs
local tonumber = tonumber

-- ---------------------------------------------------------------------------
-- Built-in media (always available, no dependencies)
-- ---------------------------------------------------------------------------
T.FLAT = "Interface\\Buttons\\WHITE8X8"

T.BUILTIN_TEXTURES = {
    { name = "Flat",    path = "Interface\\Buttons\\WHITE8X8" },
    { name = "Blizzard", path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { name = "Raid",    path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { name = "Smooth",  path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
}

T.BUILTIN_FONTS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { name = "Skurri",        path = "Fonts\\SKURRI.TTF" },
    { name = "Morpheus",      path = "Fonts\\MORPHEUS.TTF" },
}

-- ---------------------------------------------------------------------------
-- Palette
-- ---------------------------------------------------------------------------
T.colors = {
    frameBG      = { 0.06, 0.06, 0.06, 0.85 },
    frameBorder  = { 0.00, 0.00, 0.00, 0.85 },
    barBG        = { 0.02, 0.02, 0.02, 0.90 },
    nameBarBG    = { 0.03, 0.03, 0.03, 0.92 },

    health       = { 0.20, 0.80, 0.20 },
    power        = { 0.12, 0.42, 1.00 },

    text         = { 1.00, 1.00, 1.00, 1.00 },
    textDim      = { 0.75, 0.75, 0.75, 1.00 },

    selected     = { 1.00, 1.00, 0.00, 0.14 },
    selectedEdge = { 1.00, 1.00, 0.00, 0.55 },

    aggroTank    = { 0.30, 0.60, 1.00 },
    aggroPulling = { 1.00, 0.70, 0.20 },
    aggroAggro   = { 1.00, 0.20, 0.20 },

    incoming     = { 0.20, 1.00, 0.20, 0.55 },
    shield       = { 0.00, 0.60, 1.00, 0.45 },
    healAbsorb   = { 1.00, 0.00, 0.00, 0.55 },

    panelBG      = { 0.12, 0.12, 0.12, 0.95 },
    panelEdge    = { 0.00, 0.00, 0.00, 1.00 },
}

function T:Color(key)
    local c = self.colors[key]
    if not c then return 1, 1, 1, 1 end
    return c[1], c[2], c[3], c[4]
end

-- ---------------------------------------------------------------------------
-- LibSharedMedia (optional)
-- ---------------------------------------------------------------------------
local LSM

local function GetLSM()
    if LSM ~= nil then return LSM or nil end
    if type(_G.LibStub) ~= "function" then
        LSM = false
        return nil
    end
    local ok, lib = pcall(_G.LibStub, "LibSharedMedia-3.0", true)
    LSM = (ok and lib) or false
    return LSM or nil
end

function T:HasLSM()
    return GetLSM() ~= nil
end

-- Returns { {name=, path=}, ... } merging built-ins with anything LSM knows.
function T:ListTextures()
    local out = {}
    local seen = {}

    for _, e in ipairs(self.BUILTIN_TEXTURES) do
        out[#out + 1] = { name = e.name, path = e.path }
        seen[e.name] = true
    end

    local lsm = GetLSM()
    if lsm then
        local ok, names = pcall(lsm.List, lsm, "statusbar")
        if ok and names then
            for _, name in ipairs(names) do
                if not seen[name] then
                    seen[name] = true
                    local okF, path = pcall(lsm.Fetch, lsm, "statusbar", name)
                    if okF and path then
                        out[#out + 1] = { name = name, path = path }
                    end
                end
            end
        end
    end

    return out
end

function T:ListFonts()
    local out = {}
    local seen = {}

    for _, e in ipairs(self.BUILTIN_FONTS) do
        out[#out + 1] = { name = e.name, path = e.path }
        seen[e.name] = true
    end

    local lsm = GetLSM()
    if lsm then
        local ok, names = pcall(lsm.List, lsm, "font")
        if ok and names then
            for _, name in ipairs(names) do
                if not seen[name] then
                    seen[name] = true
                    local okF, path = pcall(lsm.Fetch, lsm, "font", name)
                    if okF and path then
                        out[#out + 1] = { name = name, path = path }
                    end
                end
            end
        end
    end

    return out
end

-- ---------------------------------------------------------------------------
-- Resolution: profile setting -> real file path, with a guaranteed fallback.
-- ---------------------------------------------------------------------------
local function ResolveMedia(kind, name, builtins, fallback)
    if not name or name == "" then return fallback end

    for _, e in ipairs(builtins) do
        if e.name == name then return e.path end
    end

    local lsm = GetLSM()
    if lsm then
        local ok, path = pcall(lsm.Fetch, lsm, kind, name, true)
        if ok and path then return path end
    end

    return fallback
end

local function StyleDB()
    if ns.GetStyleDB then
        return ns:GetStyleDB()
    end
    return nil
end

function T:GetBarTexture()
    local db = StyleDB()
    return ResolveMedia("statusbar", db and db.barTexture, self.BUILTIN_TEXTURES, self.FLAT)
end

function T:GetFontPath()
    local db = StyleDB()
    return ResolveMedia("font", db and db.font, self.BUILTIN_FONTS,
        _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
end

function T:GetFontSize()
    local db = StyleDB()
    return tonumber(db and db.fontSize) or 11
end

function T:GetFontOutline()
    local db = StyleDB()
    local o = db and db.fontOutline
    if o == "NONE" then return "" end
    return o or "OUTLINE"
end

-- ---------------------------------------------------------------------------
-- Applying
-- ---------------------------------------------------------------------------
-- sizeDelta shifts a specific string relative to the configured size (raid
-- group tags sit a point smaller, for instance) instead of hardcoding a value
-- that would ignore the user's Font Size slider entirely.
function T:ApplyFont(fs, sizeDelta)
    if not (fs and fs.SetFont) then return end

    if sizeDelta ~= nil then
        fs._ohSizeDelta = tonumber(sizeDelta) or 0
    end

    local path = self:GetFontPath()
    local size = self:GetFontSize() + (fs._ohSizeDelta or 0)
    if size < 6 then size = 6 end
    local outline = self:GetFontOutline()

    local ok = pcall(fs.SetFont, fs, path, size, outline)
    if not ok then
        pcall(fs.SetFont, fs, _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, outline)
    end
end

function T:ApplyBarTexture(bar)
    if not (bar and bar.SetStatusBarTexture) then return end
    pcall(bar.SetStatusBarTexture, bar, self:GetBarTexture())
end

-- Bumped whenever the style config changes, so frames know to restyle.
T.revision = 1

function T:Bump()
    self.revision = self.revision + 1
end

-- ---------------------------------------------------------------------------
-- Restyle an existing unit button.
--
-- This is the piece that was missing: ApplyBarTexture/ApplyFont were only ever
-- called from CreateUnitButton, but Build() REUSES frames. Changing the bar
-- texture or font therefore did nothing to any frame that already existed -
-- which is every frame, unless you happened to change group size at the same
-- moment. Every Apply() path now calls this; the revision check makes it a
-- single integer compare when nothing has changed.
-- ---------------------------------------------------------------------------
local FONT_FIELDS = {
    "nameText", "roleText", "groupText", "_hpPctText", "statusText",
}

function T:ApplyToUnitButton(btn)
    if not btn then return end
    if btn._themeRev == self.revision then return end
    btn._themeRev = self.revision

    self:ApplyBarTexture(btn.hp)
    self:ApplyBarTexture(btn.power)

    for i = 1, #FONT_FIELDS do
        local fs = btn[FONT_FIELDS[i]]
        if fs then self:ApplyFont(fs) end
    end

    -- Aura icon countdowns live on child frames and size themselves off the
    -- icon, so they only need the font face refreshed.
    if btn._ohFBuffs and btn._ohFBuffs.icons then
        for _, icon in ipairs(btn._ohFBuffs.icons) do
            if icon and icon.cd and icon.cd.GetCountdownFontString then
                local fs = icon.cd:GetCountdownFontString()
                if fs then self:ApplyFont(fs) end
            end
        end
    end

    if btn._ohDebuffs and btn._ohDebuffs.normal then
        for _, slot in ipairs(btn._ohDebuffs.normal.icons or {}) do
            if slot and slot.cd and slot.cd.GetCountdownFontString then
                local fs = slot.cd:GetCountdownFontString()
                if fs then self:ApplyFont(fs) end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Panel helper for new UI code, so future panels match without copy-paste.
-- ---------------------------------------------------------------------------
function T:StylePanel(frame)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = self.FLAT,
        edgeFile = self.FLAT,
        edgeSize = 1,
    })
    frame:SetBackdropColor(self:Color("panelBG"))
    frame:SetBackdropBorderColor(self:Color("panelEdge"))
end
