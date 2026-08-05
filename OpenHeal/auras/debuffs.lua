-- ============================================================================
-- debuffs.lua (OpenHeal) - WoW 12.0 / Midnight
-- TWO-ROW SOLUTION (COMBAT-SAFE / SECURE-RAID SAFE):
--   - Row 1 (TOP):   BOSS/PRIVATE AURAS via C_UnitAuras.AddPrivateAuraAnchor
--   - Row 2 (BOTTOM):NORMAL debuffs via C_UnitAuras.GetAuraDataByIndex
--
-- FIXES:
--   - Never rebuild private aura anchors in combat
--   - Prefer stable raid token (frame._stableUnit) for private anchors
--   - Private anchors are treated as persistent bindings, not rebuilt every Update()
--   - Reattach only out of combat if the anchor token actually changes
--
-- CONFIG (this is what the Settings UI writes to):
--   db.party.debuff / db.raid.debuff:
--     enabled, mode ("OFF"/"IMPORTANT"/"CUSTOM"/"ALL"), maxIcons, size,
--     custom = { [spellID] = true }, customOnlyDispellable
--   Filtering + priority order come from ns.AuraFilters, so the settings
--   preview and the live frames always agree.
--
-- Hard rules:
--   - NO IsAddOnLoaded / LoadAddOn
--   - NO secret value math/comparisons
--   - Private auras are NOT readable; Blizzard draws them into our "priv" frames.
-- ============================================================================

local _, ns = ...
ns.Debuffs = ns.Debuffs or {}
local Debuffs = ns.Debuffs

local UnitExists         = UnitExists
local UnitAura           = UnitAura
local GameTooltip        = GameTooltip
local InCombatLockdown   = InCombatLockdown
local CreateFrame        = CreateFrame
local pcall              = pcall
local select             = select
local floor              = math.floor
local max                = math.max
local min                = math.min
local tonumber           = tonumber
local type               = type
local ipairs             = ipairs
local pairs              = pairs
local rawget             = rawget
local tsort              = table.sort
local format             = string.format

local CUA = C_UnitAuras
local C_Spell = C_Spell
local GetAuraDataByIndex = CUA and CUA.GetAuraDataByIndex or nil
local GetAuraDuration    = CUA and CUA.GetAuraDuration or nil

local scrubsecretvalues  = _G.scrubsecretvalues

-- ============================================================
-- CONFIG
-- ============================================================
local MAX_PRIVATE = 6
local MAX_NORMAL  = 8            -- hard cap; the DB slider tops out at 8

local PRIVATE_SIZE = 20
local DEFAULT_SIZE = 16
local MIN_SIZE     = 10
local MAX_SIZE     = 24
local GAP          = 2
local ROW_GAP      = 2

local PRIVATE_SCAN_TICK = 0.25
local PRIVATE_COVER_INSET = 2

Debuffs.DEFAULT_ANCHOR = "BOTTOM"

local FALLBACK_CFG = {
    enabled  = true,
    mode     = "IMPORTANT",
    maxIcons = 3,
    size     = DEFAULT_SIZE,
    customOnlyDispellable = false,
}

-- ============================================================
-- DEBUG
-- ============================================================
local OH_DEBUFF_DEBUG = false

local function dprint(...)
    if OH_DEBUFF_DEBUG then
        print("|cff00ff00[OpenHeal Debuffs]|r", ...)
    end
end

SLASH_OPENHEALDEBUFFDBG1 = "/ohdebuffdbg"
SlashCmdList.OPENHEALDEBUFFDBG = function()
    OH_DEBUFF_DEBUG = not OH_DEBUFF_DEBUG
    print("|cff00ff00[OpenHeal Debuffs]|r debug:", OH_DEBUFF_DEBUG and "ON" or "OFF")
end

SLASH_OPENHEALDEBUFFDUMP1 = "/ohdebuffdump"
SlashCmdList.OPENHEALDEBUFFDUMP = function()
    print("|cff00ff00[OpenHeal Debuffs]|r",
        "UnitAura:", UnitAura and "YES" or "NO",
        "CUA:", CUA and "YES" or "NO",
        "GetAuraDataByIndex:", GetAuraDataByIndex and "YES" or "NO",
        "GetAuraDuration:", GetAuraDuration and "YES" or "NO",
        "AddPrivateAuraAnchor:", (CUA and CUA.AddPrivateAuraAnchor) and "YES" or "NO",
        "RemovePrivateAuraAnchor:", (CUA and CUA.RemovePrivateAuraAnchor) and "YES" or "NO",
        "InCombatLockdown:", InCombatLockdown and "YES" or "NO"
    )
end

-- ============================================================
-- HELPERS
-- ============================================================
local function SafeToNumber(v)
    if v == nil then return 0 end
    if scrubsecretvalues then
        local sv = select(1, scrubsecretvalues(v))
        if type(sv) == "number" then return sv end
        return 0
    end
    if type(v) == "number" then return v end
    return 0
end

local function SafeToID(v)
    local n = SafeToNumber(v)
    if n > 0 then return n end
    return nil
end

local function SafeToBool(v)
    if v == nil then return false end
    if scrubsecretvalues then
        local sv = select(1, scrubsecretvalues(v))
        if type(sv) == "boolean" then return sv end
        return false
    end
    if type(v) == "boolean" then return v end
    return false
end

local function GetSpellTextureSafe(spellId)
    if not spellId or not (C_Spell and C_Spell.GetSpellTexture) then return nil end
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellId)
    if ok then return tex end
    return nil
end

local function ResolveAnchorUnit(frame, unit)
    if frame and frame._stableUnit then
        return frame._stableUnit
    end
    return unit
end

-- ============================================================
-- CONFIG RESOLUTION
-- ------------------------------------------------------------
-- Raid buttons carry a stable unit token (_stableUnit); party buttons do not.
-- _ohKind is also set by the UI modules, so use whichever is available.
-- ============================================================
local function IsRaidFrame(frame)
    if not frame then return false end
    if frame._ohKind == "RAID" then return true end
    if frame._ohKind == "PARTY" then return false end
    return frame._stableUnit ~= nil
end

local function GetCfg(frame)
    local db
    if IsRaidFrame(frame) then
        db = ns.GetRaidDB and ns:GetRaidDB() or nil
    else
        db = ns.GetPartyDB and ns:GetPartyDB() or nil
    end

    local cfg = db and db.debuff
    if not cfg then return FALLBACK_CFG end

    for k, v in pairs(FALLBACK_CFG) do
        if cfg[k] == nil then cfg[k] = v end
    end
    return cfg
end

local function CfgMaxIcons(cfg)
    local n = tonumber(cfg.maxIcons)
    if n == nil then n = FALLBACK_CFG.maxIcons end
    n = floor(n + 0.5)
    if n < 0 then n = 0 end
    if n > MAX_NORMAL then n = MAX_NORMAL end
    return n
end

local function CfgSize(cfg)
    local s = tonumber(cfg.size) or DEFAULT_SIZE
    s = floor(s + 0.5)
    if s < MIN_SIZE then s = MIN_SIZE end
    if s > MAX_SIZE then s = MAX_SIZE end
    return s
end

-- ============================================================
-- SAFE UI CALLS
-- ============================================================
local function SafeShown(obj)
    if not obj then return false end
    local ok, v = pcall(obj.IsShown, obj)
    return ok and v or false
end

local function SafeAlpha(obj)
    if not obj or not obj.GetAlpha then return 0 end
    local ok, v = pcall(obj.GetAlpha, obj)
    if ok and type(v) == "number" then return v end
    return 0
end

local function SafeTexture(texObj)
    if not texObj or not texObj.GetTexture then return nil end
    local ok, v = pcall(texObj.GetTexture, texObj)
    if ok then return v end
    return nil
end

-- ============================================================
-- HP BAR COLOR PICKER
-- ============================================================
local HP_CANDIDATE_KEYS = {
    "health", "hp", "healthBar", "hpBar",
    "Health", "HP", "HealthBar", "HPBar",
    "statusBar", "status", "bar",
}

local function GetHPBarColor(frame)
    if not frame then return nil end

    for _, key in ipairs(HP_CANDIDATE_KEYS) do
        local sb = frame[key]
        if sb and sb.GetObjectType then
            local okType, t = pcall(sb.GetObjectType, sb)
            if okType and t == "StatusBar" then
                local ok, r, g, b = pcall(sb.GetStatusBarColor, sb)
                if ok and r and g and b then
                    local a = 1
                    if sb.GetAlpha then
                        local okA, aa = pcall(sb.GetAlpha, sb)
                        if okA and type(aa) == "number" then a = aa end
                    end
                    return r, g, b, a
                end
            end
        end
    end

    return nil
end

-- ============================================================
-- TOOLTIP (NORMAL row only)
-- ============================================================
local function ShowAuraTooltip(self)
    if not self or not SafeShown(self) then return end
    if not self._unit then return end
    if not self._auraIndex then return end

    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT", -2, -2)

    local ok = pcall(GameTooltip.SetUnitAura, GameTooltip, self._unit, self._auraIndex, "HARMFUL")

    if ok and GameTooltip:NumLines() > 0 then
        GameTooltip:Show()
    else
        GameTooltip:Hide()
    end
end

-- ============================================================
-- COUNTDOWN STYLING
-- ============================================================
local function SafeSetFont(fs, path, size, flags)
    if not (fs and fs.SetFont) then return end
    size  = tonumber(size) or 12
    flags = flags or ""
    local ok = pcall(fs.SetFont, fs, path, size, flags)
    if not ok then
        pcall(fs.SetFont, fs, (_G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"), size, flags)
    end
end

local function StyleCooldownCountdown(cd, iconSize)
    if not (cd and cd.GetCountdownFontString) then return end
    local fs = cd:GetCountdownFontString()
    if not fs then return end

    local font = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local fsz  = max(9, floor((tonumber(iconSize) or DEFAULT_SIZE) * 0.62))

    SafeSetFont(fs, font, fsz, "OUTLINE")
    fs:SetShadowOffset(0, 0)
    fs:SetDrawLayer("OVERLAY", 7)
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", cd, "CENTER", 0, 0)
    fs:Show()
end

-- ============================================================
-- PRIVATE AURA ANCHORS
-- ============================================================
local function RemovePrivateAnchors(ui)
    if not ui or not ui.private or not ui.private.icons then return end
    if not (CUA and CUA.RemovePrivateAuraAnchor) then return end

    for _, b in ipairs(ui.private.icons) do
        if b._paID then
            pcall(CUA.RemovePrivateAuraAnchor, b._paID)
            b._paID = nil
        end
        if b._cover then b._cover:Hide() end
        b._hasDraw = false
    end

    ui._paUnit = nil
end

local function ApplyPrivateAnchors(ui, anchorUnit)
    if not ui or not anchorUnit then return false end
    if not (CUA and CUA.AddPrivateAuraAnchor) then return false end
    if ui._paUnit == anchorUnit then return true end
    if InCombatLockdown and InCombatLockdown() then return false end

    RemovePrivateAnchors(ui)

    ui._paUnit = anchorUnit
    ui._pendingPAUnit = nil

    for idx = 1, MAX_PRIVATE do
        local b = ui.private.icons[idx]
        if b and b.priv then
            local ok, id = pcall(CUA.AddPrivateAuraAnchor, {
                unitToken = anchorUnit,
                auraIndex = idx,
                parent = b.priv,

                showCountdownFrame = true,
                showCountdownNumbers = true,

                iconInfo = {
                    iconWidth = PRIVATE_SIZE,
                    iconHeight = PRIVATE_SIZE,
                    iconAnchor = {
                        point = "CENTER",
                        relativeTo = b.priv,
                        relativePoint = "CENTER",
                        offsetX = 0,
                        offsetY = 0,
                    },
                },
            })

            b._paID = (ok and id) or nil

            if b._cover then b._cover:Hide() end
            b._hasDraw = false
        end
    end

    dprint("Private anchors set for", anchorUnit)
    return true
end

local function EnsurePrivateAnchors(ui, anchorUnit)
    if not ui or not anchorUnit then return end
    if ui._paUnit == anchorUnit then return end

    if InCombatLockdown and InCombatLockdown() then
        ui._pendingPAUnit = anchorUnit
        dprint("Deferred private anchors for", anchorUnit)
        return
    end

    ApplyPrivateAnchors(ui, anchorUnit)
end

-- ============================================================
-- PRIVATE DRAW DETECTION
-- ------------------------------------------------------------
-- Called on a shared ticker for every tracked frame, so it must not allocate.
-- Taking the children as a vararg avoids the `{ f:GetChildren() }` table that
-- the old per-frame OnUpdate churned through ~1200x/second in a full raid.
-- ============================================================
local function AnyChildDrawn(...)
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        if child and SafeAlpha(child) > 0.01 then
            local icon = rawget(child, "Icon")
            if SafeTexture(icon) then return true end

            local cd = rawget(child, "Cooldown")
            if cd and SafeShown(cd) then return true end

            local border = rawget(child, "DebuffBorder") or rawget(child, "TempEnchantBorder")
            if border and SafeShown(border) then return true end
        end
    end
    return false
end

local function PrivateSlotHasDraw(priv)
    if not priv then return false end
    local ok, res = pcall(function() return AnyChildDrawn(priv:GetChildren()) end)
    return (ok and res) or false
end

-- ============================================================
-- UI CREATION
-- ============================================================
local function CreatePrivateSlot(parent, index)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(PRIVATE_SIZE, PRIVATE_SIZE)
    f:SetPoint("LEFT", (index - 1) * (PRIVATE_SIZE + GAP), 0)
    f:Show()

    local priv = CreateFrame("Frame", nil, f)
    priv:SetAllPoints()
    priv:SetFrameLevel(f:GetFrameLevel() + 20)

    local cover = priv:CreateTexture(nil, "OVERLAY")
    cover:SetTexture("Interface\\Buttons\\WHITE8X8")
    cover:SetPoint("TOPLEFT", PRIVATE_COVER_INSET, -PRIVATE_COVER_INSET)
    cover:SetPoint("BOTTOMRIGHT", -PRIVATE_COVER_INSET, PRIVATE_COVER_INSET)
    cover:SetDrawLayer("OVERLAY", 7)
    cover:Hide()

    f.priv = priv
    f._cover = cover
    f._paID = nil
    f._hasDraw = false

    return f
end

local function CreateNormalSlot(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(DEFAULT_SIZE, DEFAULT_SIZE)
    f:Hide()

    f:EnableMouse(true)

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints(tex)
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetHideCountdownNumbers(false)
    cd:Hide()

    StyleCooldownCountdown(cd, DEFAULT_SIZE)

    local count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", 2, 0)
    count:SetText("")
    count:Hide()

    f.icon  = tex
    f.cd    = cd
    f.count = count

    f._unit = nil
    f._auraIndex = nil
    f._spellId = nil
    f._auraInstanceID = nil

    f:SetScript("OnEnter", ShowAuraTooltip)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return f
end

-- Re-lay-out the normal row when maxIcons / size change in the Settings UI.
local function ApplyNormalLayout(ui, maxIcons, size)
    local key = maxIcons .. ":" .. size
    if ui._layoutKey == key then return end
    ui._layoutKey = key

    local icons = ui.normal.icons
    local rowW = max(1, maxIcons * size + max(0, maxIcons - 1) * GAP)

    ui.normal.row:SetSize(rowW, size)

    for i = 1, MAX_NORMAL do
        local b = icons[i]
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("LEFT", ui.normal.row, "LEFT", (i - 1) * (size + GAP), 0)
        StyleCooldownCountdown(b.cd, size)
        if i > maxIcons then
            b:Hide()
        end
    end

    local w = max(MAX_PRIVATE * PRIVATE_SIZE + (MAX_PRIVATE - 1) * GAP, rowW)
    ui.holder:SetSize(w, PRIVATE_SIZE + ROW_GAP + size)
end

local function Ensure(frame)
    if frame._ohDebuffs then return frame._ohDebuffs end

    local holder = CreateFrame("Frame", nil, frame)

    local w_private = MAX_PRIVATE * PRIVATE_SIZE + (MAX_PRIVATE - 1) * GAP
    local w_normal  = MAX_NORMAL  * DEFAULT_SIZE + (MAX_NORMAL  - 1) * GAP
    local w = max(w_private, w_normal)
    local h = PRIVATE_SIZE + ROW_GAP + DEFAULT_SIZE

    holder:SetSize(w, h)

    if Debuffs.DEFAULT_ANCHOR == "BOTTOM" then
        holder:SetPoint("BOTTOM", frame, "BOTTOM", 0, 4)
    else
        holder:SetPoint("TOP", frame, "TOP", 0, -4)
    end

    holder:SetFrameLevel((frame:GetFrameLevel() or 0) + 50)
    holder:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
    holder:SetIgnoreParentAlpha(true)
    holder:SetAlpha(1)
    holder:Hide()

    local privRow = CreateFrame("Frame", nil, holder)
    privRow:SetSize(w_private, PRIVATE_SIZE)
    privRow:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    privRow:Show()

    local privIcons = {}
    for i = 1, MAX_PRIVATE do
        privIcons[i] = CreatePrivateSlot(privRow, i)
        privIcons[i]:SetFrameLevel(privRow:GetFrameLevel() + 1)
    end

    local normRow = CreateFrame("Frame", nil, holder)
    normRow:SetSize(w_normal, DEFAULT_SIZE)
    normRow:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
    normRow:Show()

    -- All slots are created up front (cap is 8) so raising maxIcons in the
    -- Settings UI never has to build frames - and never indexes a nil slot.
    local normIcons = {}
    for i = 1, MAX_NORMAL do
        normIcons[i] = CreateNormalSlot(normRow)
        normIcons[i]:SetFrameLevel(normRow:GetFrameLevel() + 1)
    end

    frame._ohDebuffs = {
        holder = holder,
        owner = frame,
        private = { row = privRow, icons = privIcons },
        normal  = { row = normRow, icons = normIcons },
        _paUnit = nil,
        _pendingPAUnit = nil,
        _coverKey = nil,
        _layoutKey = nil,
        _filterKey = nil,
        _whitelist = nil,
        _prio = nil,
    }

    ApplyNormalLayout(frame._ohDebuffs, FALLBACK_CFG.maxIcons, DEFAULT_SIZE)

    Debuffs._tracked = Debuffs._tracked or setmetatable({}, { __mode = "k" })
    Debuffs._tracked[frame] = true

    return frame._ohDebuffs
end

-- ============================================================
-- SHARED PRIVATE-AURA COVER TICKER
-- ------------------------------------------------------------
-- One ticker for the whole addon instead of one OnUpdate per unit button.
-- ============================================================
if not Debuffs._coverTicker then
    local t = CreateFrame("Frame")
    t._accum = 0
    t:SetScript("OnUpdate", function(self, elapsed)
        self._accum = self._accum + (elapsed or 0)
        if self._accum < PRIVATE_SCAN_TICK then return end
        self._accum = 0

        local tracked = Debuffs._tracked
        if not tracked then return end

        for frame in pairs(tracked) do
            local ui = frame and frame._ohDebuffs
            if ui and ui.holder:IsShown() then
                for _, p in ipairs(ui.private.icons) do
                    -- Only slots with a live anchor can ever draw something.
                    if p._paID and p._cover then
                        local has = PrivateSlotHasDraw(p.priv)
                        if has ~= p._hasDraw then
                            p._hasDraw = has
                            if has then p._cover:Show() else p._cover:Hide() end
                        end
                    end
                end
            end
        end
    end)
    Debuffs._coverTicker = t
end

-- ============================================================
-- NORMAL DEBUFF COLLECTION (12.0 SAFE)
-- ------------------------------------------------------------
-- whitelist == nil means "no filtering" (mode ALL).
-- ============================================================
local function CollectNormal(unit, whitelist, prio, wantCount, onlyDispellable)
    if not unit or not UnitExists(unit) then return nil end
    if wantCount <= 0 then return nil end

    local list = {}

    local function Consider(entry)
        if whitelist and not whitelist[entry.spellId or 0] then return end
        if onlyDispellable and not entry.canDispel then return end
        list[#list + 1] = entry
    end

    if GetAuraDataByIndex then
        for i = 1, 40 do
            local aura
            local ok = pcall(function()
                aura = GetAuraDataByIndex(unit, i, "HARMFUL")
            end)
            if (not ok) or (not aura) then break end

            if aura.icon then
                Consider({
                    auraIndex      = i,
                    auraInstanceID = aura.auraInstanceID,
                    icon           = aura.icon,
                    count          = aura.applications,
                    spellId        = SafeToID(aura.spellId),
                    canDispel      = SafeToBool(aura.canActivePlayerDispel),
                })

                -- With no priority map (mode "ALL") the game's own order is
                -- final, so stop as soon as the visible slots are filled.
                -- Filtered modes must see every aura before sorting.
                if not prio and #list >= wantCount then break end
            end
        end

        if #list > 0 then
            -- Priority order first, then aura index for a stable tie-break.
            if prio then
                tsort(list, function(a, b)
                    local pa = prio[a.spellId or 0] or 9999
                    local pb = prio[b.spellId or 0] or 9999
                    if pa ~= pb then return pa < pb end
                    return a.auraIndex < b.auraIndex
                end)
            end
            return list
        end

        -- Nothing matched the filter; do not fall through to the legacy path.
        if whitelist or onlyDispellable then return nil end
    end

    if UnitAura then
        for i = 1, 40 do
            local name, texture, count, _, _, _, _, _, _, spellId = UnitAura(unit, i, "HARMFUL")
            if not name then break end

            Consider({
                auraIndex      = i,
                auraInstanceID = nil,
                icon           = texture,
                count          = count,
                spellId        = SafeToID(spellId),
                canDispel      = false,
            })

            if #list >= wantCount and not prio then break end
        end
    end

    if #list == 0 then return nil end
    return list
end

-- ============================================================
-- REGEN HANDLER
-- ============================================================
if not Debuffs._regenFrame then
    Debuffs._regenFrame = CreateFrame("Frame")
    Debuffs._regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    Debuffs._regenFrame:SetScript("OnEvent", function()
        if not Debuffs._tracked then return end

        for frame in pairs(Debuffs._tracked) do
            local ui = frame and frame._ohDebuffs
            if ui and ui._pendingPAUnit then
                ApplyPrivateAnchors(ui, ui._pendingPAUnit)
            end
        end
    end)
end

-- ============================================================
-- PUBLIC API
-- ============================================================
function Debuffs:Attach(frame)
    local ui = Ensure(frame)

    local anchorUnit = ResolveAnchorUnit(frame, frame.unit)
    if anchorUnit and not (InCombatLockdown and InCombatLockdown()) then
        EnsurePrivateAnchors(ui, anchorUnit)
    end

    return ui
end

local function HideAllNormal(ui)
    for i = 1, MAX_NORMAL do
        local b = ui.normal.icons[i]
        b._unit = nil
        b._auraIndex = nil
        b._spellId = nil
        b._auraInstanceID = nil
        b.icon:SetTexture(nil)
        b.count:SetText("")
        b.count:Hide()
        b.cd:Hide()
        b:Hide()
    end
end

function Debuffs:Update(frame, unit)
    local ui = Ensure(frame)
    local holder = ui.holder

    local anchorUnit = ResolveAnchorUnit(frame, unit)

    if not unit or not UnitExists(unit) then
        holder:Hide()

        -- IMPORTANT:
        -- Do NOT remove private anchors here.
        -- They are persistent and bound to stable unit tokens.
        -- Rebuilding/removing these during combat is what caused the blocked action.
        return
    end

    holder:Show()

    if anchorUnit then
        EnsurePrivateAnchors(ui, anchorUnit)
    end

    do
        local r, g, b, a = GetHPBarColor(frame)
        if not r then r, g, b, a = 0, 0, 0, 0.85 end

        -- GetStatusBarColor can return secret numbers. format() propagates that
        -- into a secret STRING, and comparing it with the cached key raised
        -- "attempt to compare local 'key' (a secret string value)" on every
        -- UNIT_AURA. Build the key only from values we can reduce; a nil key
        -- means "cannot cache", so just re-apply.
        --
        -- The colours themselves are still passed through untouched -
        -- SetVertexColor is an engine setter and takes secrets fine.
        local key = ns.UnitUtil and ns.UnitUtil.SafeCacheKey(r, g, b, a) or nil

        if key == nil or ui._coverKey ~= key then
            ui._coverKey = key
            for _, icon in ipairs(ui.private.icons) do
                if icon._cover then
                    pcall(icon._cover.SetVertexColor, icon._cover, r, g, b, a)
                end
            end
        end
    end

    -- ------------------------------------------------------------
    -- Normal row: fully driven by the profile config
    -- ------------------------------------------------------------
    local cfg = GetCfg(frame)
    local maxIcons = CfgMaxIcons(cfg)
    local size = CfgSize(cfg)

    ApplyNormalLayout(ui, maxIcons, size)

    if cfg.enabled == false or maxIcons == 0 then
        HideAllNormal(ui)
        return
    end

    local AF = ns.AuraFilters
    if AF and AF.ResolveMaps then
        local wl, pr, key = AF:ResolveMaps("DEBUFFS", cfg)
        if ui._filterKey ~= key then
            ui._filterKey = key
            ui._whitelist = wl
            ui._prio = pr
        end
    else
        ui._whitelist = nil
        ui._prio = nil
    end

    -- mode OFF resolves to an empty whitelist: nothing to show.
    if ui._whitelist and next(ui._whitelist) == nil then
        HideAllNormal(ui)
        return
    end

    local onlyDispellable = (cfg.mode == "CUSTOM") and (cfg.customOnlyDispellable == true)

    local list = CollectNormal(unit, ui._whitelist, ui._prio, maxIcons, onlyDispellable)
    local icons = ui.normal.icons

    for slot = 1, MAX_NORMAL do
        local b = icons[slot]
        local a = (slot <= maxIcons) and list and list[slot] or nil

        if a then
            b._unit = unit
            b._auraIndex = a.auraIndex
            b._spellId = a.spellId
            b._auraInstanceID = a.auraInstanceID

            local okSet = pcall(b.icon.SetTexture, b.icon, a.icon)
            if (not okSet) or (not b.icon:GetTexture()) then
                local tex = GetSpellTextureSafe(a.spellId)
                if tex then
                    pcall(b.icon.SetTexture, b.icon, tex)
                end
            end

            local c = SafeToNumber(a.count)
            if c > 1 then
                b.count:SetText(c)
                b.count:Show()
            else
                b.count:SetText("")
                b.count:Hide()
            end

            if GetAuraDuration and b._auraInstanceID and b.cd.SetCooldownFromDurationObject then
                local durObj
                local okDur = pcall(function()
                    durObj = GetAuraDuration(unit, b._auraInstanceID)
                end)

                if okDur and durObj then
                    pcall(b.cd.SetCooldownFromDurationObject, b.cd, durObj, true)
                    b.cd:Show()
                else
                    b.cd:Hide()
                end
            else
                b.cd:Hide()
            end

            b:Show()
        else
            b._unit = nil
            b._auraIndex = nil
            b._spellId = nil
            b._auraInstanceID = nil

            b.icon:SetTexture(nil)
            b.count:SetText("")
            b.count:Hide()
            b.cd:Hide()
            b:Hide()
        end
    end
end
