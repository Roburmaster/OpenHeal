-- V1
-- ============================================================================
-- friendlybuffs.lua (OpenHeal) - WoW 12.0 / Midnight
-- Shows selected helpful auras (HoTs / Shields / Defensives) as icons on frames.
--
-- CPU FIX (IMPORTANT):
--   - Removed per-frame OnUpdate polling (20Hz). Updates are event-driven now.
--   - FB:Update(frame, unit) is still safe to call anytime (UNIT_AURA, roster, etc.)
--
-- 12.0 SAFE:
--   - NO math/compares on expirationTime/duration (Secret Values)
--   - Uses AuraInstanceID + C_UnitAuras.GetAuraDuration() -> DurationObject
--   - Uses Cooldown:SetCooldownFromDurationObject() for swipe + countdown
--   - Styles built-in countdown via Cooldown:GetCountdownFontString()
--
-- API:
--   ns.FriendlyBuffs:Attach(frame)
--   ns.FriendlyBuffs:Update(frame, unit)   -- safe to call any time
--   ns.FriendlyBuffs:Place(frame)
-- ============================================================================

local _, ns = ...
ns.FriendlyBuffs = ns.FriendlyBuffs or {}
local FB = ns.FriendlyBuffs

-- NOTE: ns.AuraFilters is resolved lazily. Load order is not guaranteed to put
-- aura_filters.lua before this file, and caching a nil upvalue here is what
-- used to silently fall back to the hardcoded list below.
local function GetAF()
    return ns.AuraFilters
end

-- Hard cap on icon slots. All slots are created up front so raising maxIcons
-- in the Settings UI can never index a nil icon (it used to error).
local MAX_ICONS = 8

local CUA = C_UnitAuras
local UnitExists = UnitExists
local GetTime = GetTime
local pcall = pcall
local type = type
local tonumber = tonumber
local wipe = wipe
local ipairs = ipairs
local pairs = pairs
local math_floor = math.floor
local math_max = math.max
local table_sort = table.sort
local tostring = tostring

local GetAuraDataByIndex = CUA and CUA.GetAuraDataByIndex or nil
local GetAuraDuration    = CUA and CUA.GetAuraDuration or nil

local scrubsecretvalues  = _G.scrubsecretvalues

-- ------------------------------------------------------------
-- DEBUG (PTR TOOL) - default OFF
-- Logs helpful auras that are NOT whitelisted (rate-limited per spellId)
-- ------------------------------------------------------------
local DEBUG_CAPTURE = false
local debugPrinted = {}
local DEBUG_THROTTLE = 10

local function DebugAura(spellId, name)
    if not DEBUG_CAPTURE then return end
    if not spellId then return end

    local now = GetTime()
    if debugPrinted[spellId] and (now - debugPrinted[spellId] < DEBUG_THROTTLE) then
        return
    end

    debugPrinted[spellId] = now
    print("|cff33ff99OpenHeal|r New helpful aura:", spellId, name or "unknown")
end

function FB:SetDebugCapture(enabled)
    DEBUG_CAPTURE = (enabled and true or false)
end

-- ------------------------------------------------------------
-- Defaults (if db is missing keys)
-- ------------------------------------------------------------
local FALLBACK = {
    enabled  = true,
    maxIcons = 3,
    size     = 16,
    spacing  = 2,

    anchor   = "TOP",
    relTo    = "hp",
    relPoint = "TOP",
    x        = 0,
    y        = 2,

    showStacks = true,
    showTimers = true,      -- controls cooldown countdown numbers (not custom text)
    timerFont = "GameFontNormalSmall", -- kept for compatibility, not used directly
    timerScale = 0.85,      -- kept for compatibility, not used directly

    onlyMine = false,
}

-- ------------------------------------------------------------
-- Secret-safe scrub helpers
-- ------------------------------------------------------------
local function ScrubNumber(v)
    if v == nil then return nil end
    if scrubsecretvalues then
        local sv = scrubsecretvalues(v)
        if type(sv) == "number" then return sv end
        return nil
    end
    if type(v) == "number" then return v end
    return nil
end

local function SafeNumber(v)
    return ScrubNumber(v) or 0
end

local function SafeID(v)
    local n = ScrubNumber(v)
    if n and n > 0 then return n end
    return nil
end

local function SafeBool(v)
    if scrubsecretvalues then
        local sv = scrubsecretvalues(v)
        if type(sv) == "boolean" then return sv end
        return false
    end
    if type(v) == "boolean" then return v end
    return false
end

-- ------------------------------------------------------------
-- DB helpers
-- ------------------------------------------------------------
local function GetCfg(frame)
    local kind = frame and frame._ohKind
    if kind == "RAID" and ns.GetRaidDB then
        local db = ns:GetRaidDB()
        return db and db.fbuff
    end
    if ns.GetPartyDB then
        local db = ns:GetPartyDB()
        return db and db.fbuff
    end
    return nil
end

local function ClampIcons(v)
    local n = tonumber(v)
    if n == nil then n = FALLBACK.maxIcons end
    n = math_floor(n + 0.5)
    if n < 0 then n = 0 end
    if n > MAX_ICONS then n = MAX_ICONS end
    return n
end

local function MergeFallback(cfg)
    if not cfg then
        local t = {}
        for k, v in pairs(FALLBACK) do t[k] = v end
        return t
    end
    for k, v in pairs(FALLBACK) do
        if cfg[k] == nil then cfg[k] = v end
    end
    return cfg
end

-- ------------------------------------------------------------
-- FILTER LIST
--   Resolved from cfg.mode / cfg.custom via aura_filters.lua, so the Settings
--   UI's "Buff Filter" dropdown and CUSTOM list actually drive what is shown.
--     OFF       -> nothing
--     IMPORTANT -> curated preset
--     CUSTOM    -> cfg.custom
--     ALL       -> no whitelist (everything helpful)
-- ------------------------------------------------------------
local HARD_FALLBACK = {
    53563, 156910, 1244893, 156322,
    17, 974, 1022, 6940, 47788, 33206, 102342, 116849, 204018, 1044,
    774, 8936, 33763, 139, 61295, 119611,
    194384,
}

local fallbackWL, fallbackPrio
local function BuildHardFallback()
    if fallbackWL then return end
    fallbackWL, fallbackPrio = {}, {}
    local p = 1
    for _, id in ipairs(HARD_FALLBACK) do
        if not fallbackWL[id] then
            fallbackWL[id] = true
            fallbackPrio[id] = p
            p = p + 1
        end
    end
end

-- Current filter state. whitelist == nil means "show everything" (mode ALL).
local whitelist, prio
local whitelistActive = true

-- AF:ResolveMaps memoizes on a cheap signature, so this is safe to call on
-- every update for every frame - it only rebuilds when the config changes.
local function RebuildFromCfg(cfg)
    local AF = GetAF()
    if AF and AF.ResolveMaps then
        local wl, pr, key = AF:ResolveMaps("FRIENDLYBUFFS", cfg)
        whitelist, prio = wl, pr
        whitelistActive = (wl ~= nil)
        return key
    end

    BuildHardFallback()
    whitelist, prio = fallbackWL, fallbackPrio
    whitelistActive = true
    return "FALLBACK"
end

-- ------------------------------------------------------------
-- UI helpers
-- ------------------------------------------------------------
local function Icon_OnEnter(self)
    if not self or not self._ohSpellID then return end
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(self._ohSpellID)
    GameTooltip:Show()
end

local function Icon_OnLeave(self)
    if GameTooltip then GameTooltip:Hide() end
end

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
    local fsz  = math_max(9, math_floor((tonumber(iconSize) or 16) * 0.62))

    SafeSetFont(fs, font, fsz, "OUTLINE")
    fs:SetShadowOffset(0, 0)
    fs:SetDrawLayer("OVERLAY", 7)
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", cd, "CENTER", 0, 0)
    fs:Show()
end

local function SetCountdownVisible(cd, show)
    if not cd then return end
    if cd.SetHideCountdownNumbers then
        pcall(cd.SetHideCountdownNumbers, cd, not show)
    end
    if cd.GetCountdownFontString then
        local fs = cd:GetCountdownFontString()
        if fs then
            if show then fs:Show() else fs:Hide() end
        end
    end
end

local function CreateIcon(holder, i, cfg)
    local b = CreateFrame("Frame", nil, holder)
    b:SetSize(cfg.size, cfg.size)

    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    b.cd:SetDrawBling(false)
    b.cd:SetDrawEdge(false)
    b.cd:SetDrawSwipe(true)
    SetCountdownVisible(b.cd, cfg.showTimers ~= false)
    StyleCooldownCountdown(b.cd, cfg.size or 16)

    b.count = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
    b.count:SetJustifyH("RIGHT")
    b.count:SetText("")

    -- kept for backwards compatibility (not used anymore)
    b.timeText = b:CreateFontString(nil, "OVERLAY", cfg.timerFont or "GameFontNormalSmall")
    b.timeText:SetPoint("TOP", b, "BOTTOM", 0, -1)
    b.timeText:SetJustifyH("CENTER")
    b.timeText:SetScale(cfg.timerScale or 0.85)
    b.timeText:SetText("")
    b.timeText:Hide()

    b:EnableMouse(true)
    b:SetScript("OnEnter", Icon_OnEnter)
    b:SetScript("OnLeave", Icon_OnLeave)

    b._ohSpellID = nil
    b._ohAuraIndex = nil
    b._ohAuraInstanceID = nil

    b:Hide()
    return b
end

-- ------------------------------------------------------------
-- UI creation
-- CPU FIX: No per-frame OnUpdate polling anymore.
-- ------------------------------------------------------------
local function EnsureUI(frame, cfg)
    if frame._ohFBuffs then return end

    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetFrameStrata("TOOLTIP")
    holder:SetFrameLevel(9990)
    holder:SetClampedToScreen(true)
    holder:SetIgnoreParentAlpha(true)
    holder:SetAlpha(1)

    frame._ohFBuffs = {
        holder   = holder,
        icons    = {},
        nextScan = 0,
        lastUnit = nil,
        listKey  = nil,
    }

    -- Always build the full cap, not cfg.maxIcons: the slider is live, and
    -- raising it later must not have to create frames (or index nil slots).
    for i = 1, MAX_ICONS do
        frame._ohFBuffs.icons[i] = CreateIcon(holder, i, cfg)
    end

    -- IMPORTANT:
    -- Updates must be driven externally (UNIT_AURA / roster / Apply / layout refresh).
    -- FB:Update(frame, unit) is safe to call any time.
end

function FB:Place(frame)
    if not frame or not frame._ohFBuffs then return end

    local cfg = MergeFallback(GetCfg(frame))
    local fb = frame._ohFBuffs
    local holder = fb.holder
    if not holder then return end

    local rel = frame
    if cfg.relTo == "hp" and frame.hp then rel = frame.hp end

    holder:ClearAllPoints()
    holder:SetPoint(cfg.anchor or "TOP", rel, cfg.relPoint or "TOP", cfg.x or 0, cfg.y or 2)

    local size = cfg.size or 16
    local spacing = cfg.spacing or 2
    local maxIcons = ClampIcons(cfg.maxIcons)

    local totalW = math_max(1, (maxIcons * size) + math_max(0, maxIcons - 1) * spacing)
    holder:SetSize(totalW, size)

    for i = 1, MAX_ICONS do
        local icon = fb.icons[i]
        icon:ClearAllPoints()
        if i == 1 then
            icon:SetPoint("LEFT", holder, "LEFT", 0, 0)
        else
            icon:SetPoint("LEFT", fb.icons[i - 1], "RIGHT", spacing, 0)
        end
        icon:SetSize(size, size)
        if icon.cd then
            StyleCooldownCountdown(icon.cd, size)
            SetCountdownVisible(icon.cd, cfg.showTimers ~= false)
        end
        if i > maxIcons then
            icon:Hide()
        end
    end
end

function FB:Attach(frame)
    if not frame then return end
    local cfg = MergeFallback(GetCfg(frame))
    EnsureUI(frame, cfg)
    self:Place(frame)

    -- Optional: show correct initial state immediately (no polling now)
    local unit = frame.unit
    if unit and UnitExists(unit) then
        self:Update(frame, unit)
    else
        self:Update(frame, nil)
    end
end

-- ------------------------------------------------------------
-- Aura scan (12.0 SAFE)
-- ------------------------------------------------------------
local function Scan(unit, cfg, out)
    wipe(out)
    if not (CUA and GetAuraDataByIndex) then return end

    local onlyMine = SafeBool(cfg.onlyMine)

    for i = 1, 40 do
        local a = nil
        local ok = pcall(function()
            a = GetAuraDataByIndex(unit, i, "HELPFUL")
        end)
        if (not ok) or (not a) then break end

        -- Midnight: do NOT break on missing icon

        local spellId = SafeID(a.spellId)
        if spellId then
            -- whitelistActive == false means mode "ALL": take everything.
            if (not whitelistActive) or whitelist[spellId] then
                if (not onlyMine) or SafeBool(a.isFromPlayerOrPlayerPet) then
                    out[#out + 1] = {
                        auraIndex = i,
                        auraInstanceID = a.auraInstanceID,
                        spellId = spellId,
                        icon = a.icon,
                        applications = a.applications,
                    }
                end
            else
                DebugAura(spellId, a.name)
            end
        end
    end

    -- No priority map in mode "ALL": keep the game's own aura order.
    if not prio then return end

    table_sort(out, function(a, b)
        local pa = prio[a.spellId] or 9999
        local pb = prio[b.spellId] or 9999
        if pa ~= pb then return pa < pb end
        return (a.auraIndex or 0) < (b.auraIndex or 0)
    end)
end

local scratch = {}

function FB:Update(frame, unit)
    if not frame or not frame._ohFBuffs then return end

    local cfg = MergeFallback(GetCfg(frame))
    local fb = frame._ohFBuffs
    local holder = fb.holder
    if not holder then return end

    local maxIcons = ClampIcons(cfg.maxIcons)

    -- Point at the filter maps for the current mode/custom list. A CUSTOM list
    -- edit in the Settings UI takes effect on the next update, no reload.
    fb.listKey = RebuildFromCfg(cfg)

    local function HideAll()
        for i = 1, MAX_ICONS do fb.icons[i]:Hide() end
        if holder:IsShown() then holder:Hide() end
    end

    -- EARLY OUT (CPU): disabled -> hide once
    if not cfg.enabled or maxIcons == 0 then
        HideAll()
        return
    end

    -- mode "OFF" resolves to an empty whitelist: nothing to show.
    if whitelistActive and next(whitelist) == nil then
        HideAll()
        return
    end

    if not unit or not UnitExists(unit) then
        HideAll()
        return
    end

    if not holder:IsShown() then holder:Show() end
    holder:SetAlpha(1)
    holder:SetIgnoreParentAlpha(true)

    local now = GetTime()
    if (fb.nextScan or 0) <= now or fb.lastUnit ~= unit then
        fb.nextScan = now + 0.20
        fb.lastUnit = unit

        Scan(unit, cfg, scratch)

        for i = 1, MAX_ICONS do
            local icon = fb.icons[i]
            local a = (i <= maxIcons) and scratch[i] or nil

            if a then
                icon._ohSpellID = a.spellId
                icon._ohAuraIndex = a.auraIndex
                icon._ohAuraInstanceID = a.auraInstanceID

                if a.icon then
                    icon.tex:SetTexture(a.icon)
                    icon.tex:Show()
                else
                    icon.tex:SetTexture(nil)
                    icon.tex:Hide()
                end

                local stacks = SafeNumber(a.applications)
                if cfg.showStacks and stacks > 1 then
                    icon.count:SetText(tostring(stacks))
                else
                    icon.count:SetText("")
                end

                SetCountdownVisible(icon.cd, cfg.showTimers ~= false)

                if GetAuraDuration and icon._ohAuraInstanceID and icon.cd and icon.cd.SetCooldownFromDurationObject then
                    local durObj
                    local okDur = pcall(function()
                        durObj = GetAuraDuration(unit, icon._ohAuraInstanceID)
                    end)
                    if okDur and durObj then
                        pcall(icon.cd.SetCooldownFromDurationObject, icon.cd, durObj, true)
                        icon.cd:Show()
                        StyleCooldownCountdown(icon.cd, cfg.size or 16)
                    else
                        icon.cd:Hide()
                    end
                else
                    if icon.cd then icon.cd:Hide() end
                end

                if icon.timeText then icon.timeText:SetText(""); icon.timeText:Hide() end
                icon:Show()
            else
                icon._ohSpellID = nil
                icon._ohAuraIndex = nil
                icon._ohAuraInstanceID = nil

                icon.count:SetText("")
                if icon.cd then icon.cd:Hide() end
                if icon.timeText then icon.timeText:SetText(""); icon.timeText:Hide() end
                icon:Hide()
            end
        end
    end
end
