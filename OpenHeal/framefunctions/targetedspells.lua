-- ============================================================================
-- targetedspells.lua (OpenHeal)
-- "Incoming / targeted spell" indicator on party/raid frames.
--
-- VISUAL:
--   - Shows a SMALL RED SQUARE ABOVE the OpenHeal unit button
--   - Uses hostile caster tracking from nameplates + target swap updates
--
-- CPU:
--   - Reuses frame list
--   - UNIT_TARGET early-bails unless unit is tracked
--   - GROUP_ROSTER_UPDATE reapplies instead of rescanning everything
--
-- WoW 12.0 / secret rules:
--   - Never boolean-test UnitIsUnit() results in Lua
--   - Even SetAlphaFromBoolean(UnitIsUnit(...)) can fail in some cases, so guard it
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns

ns.TargetedSpells = ns.TargetedSpells or {}
local TS = ns.TargetedSpells

local wipe = wipe
local pairs = pairs
local type = type
local pcall = pcall
local string_match = string.match

local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitIsUnit = UnitIsUnit
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local UnitCastingDuration = UnitCastingDuration
local UnitChannelDuration = UnitChannelDuration

-- ---------------------------------------------------------------------------
-- DB (cached)
-- ---------------------------------------------------------------------------
local function GetDB_Fallback()
    local db = ns:GetDB()
    db.targetedSpells = db.targetedSpells or {
        enabled = true,
        maxIcons = 1,
        watchNameplates = true,
    }
    return db.targetedSpells
end

local function GetDB()
    if ns.GetTargetedSpellsDB then
        return ns:GetTargetedSpellsDB()
    end
    return GetDB_Fallback()
end

local function GetDBCached()
    if TS._db then
        return TS._db
    end
    TS._db = GetDB()
    return TS._db
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function IsNameplateUnit(unit)
    return type(unit) == "string" and string_match(unit, "^nameplate%d+$") ~= nil
end

local function IsValidHostileCaster(unit, db)
    if not unit or not UnitExists(unit) then
        return false
    end

    if db.watchNameplates ~= false and not IsNameplateUnit(unit) then
        return false
    end

    return UnitCanAttack("player", unit)
end

local function GetCasterTargetUnit(casterUnit)
    if not casterUnit then
        return nil
    end

    local targetUnit = casterUnit .. "target"
    if not UnitExists(targetUnit) then
        return nil
    end

    return targetUnit
end

local function SafeSetIconFromTargetMatch(ic, targetUnit, frameUnit)
    if not ic then
        return
    end

    ic:SetShown(true)

    if not targetUnit or not frameUnit then
        ic:SetAlpha(0)
        return
    end

    if not UnitExists(targetUnit) or not UnitExists(frameUnit) then
        ic:SetAlpha(0)
        return
    end

    local ok = pcall(function()
        ic:SetAlphaFromBoolean(UnitIsUnit(targetUnit, frameUnit), 1, 0)
    end)

    if not ok then
        ic:SetAlpha(0)
    end
end

local function ApplyIconTargetState(ic, casterUnit, frameUnit)
    if not ic then
        return
    end

    local targetUnit = GetCasterTargetUnit(casterUnit)
    SafeSetIconFromTargetMatch(ic, targetUnit, frameUnit)
end

local function FrameHasAnyActiveCasters(frame)
    if not frame or not frame._ohTSActive then
        return false
    end

    for _ in pairs(frame._ohTSActive) do
        return true
    end

    return false
end

local function RefreshContainerVisibility(frame)
    if not frame or not frame._ohTSContainer then
        return
    end

    if FrameHasAnyActiveCasters(frame) then
        frame._ohTSContainer:Show()
        frame._ohTSContainer:SetAlpha(1)
    else
        frame._ohTSContainer:SetAlpha(0)
        frame._ohTSContainer:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Frame list cache (no alloc per call)
-- ---------------------------------------------------------------------------
TS._frames = TS._frames or {}

local function FramesIter()
    local out = TS._frames
    wipe(out)

    if ns.Party and ns.Party.frames then
        for _, f in pairs(ns.Party.frames) do
            if f and f.unit then
                out[#out + 1] = f
            end
        end
    end

    if ns.Raid and ns.Raid.frames then
        for _, f in pairs(ns.Raid.frames) do
            if f and f.unit then
                out[#out + 1] = f
            end
        end
    end

    return out
end

-- ---------------------------------------------------------------------------
-- UI: small red square ABOVE frame
-- ---------------------------------------------------------------------------
local function EnsureContainer(frame)
    if frame._ohTSContainer then
        return frame._ohTSContainer
    end

    local c = CreateFrame("Frame", nil, frame)
    c:SetSize(10, 10)
    c:ClearAllPoints()
    c:SetPoint("BOTTOM", frame, "TOP", 0, 2)
    c:SetFrameLevel(frame:GetFrameLevel() + 80)
    c:EnableMouse(false)
    c:SetIgnoreParentAlpha(true)
    c:SetAlpha(1)
    c:Hide()

    local t = c:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetColorTexture(1, 0, 0, 1)
    c.tex = t

    frame._ohTSContainer = c
    frame._ohTSIcons = frame._ohTSIcons or {}
    frame._ohTSActive = frame._ohTSActive or {}

    frame._ohTSIcons[1] = c

    return c
end

local function EnsurePool(frame)
    EnsureContainer(frame)
end

local function AcquireIcon(frame)
    EnsurePool(frame)
    return frame._ohTSIcons[1], 1
end

local function PositionIcons(frame)
    if not frame or not frame._ohTSContainer then
        return
    end

    frame._ohTSContainer:ClearAllPoints()
    frame._ohTSContainer:SetPoint("BOTTOM", frame, "TOP", 0, 2)
end

-- ---------------------------------------------------------------------------
-- Public API: Attach / UpdateFrame
-- ---------------------------------------------------------------------------
function TS:Attach(frame)
    if not frame or frame._ohTSApplied then
        return
    end

    frame._ohTSApplied = true
    EnsureContainer(frame)
    EnsurePool(frame)
    PositionIcons(frame)
end

function TS:UpdateFrame(frame, unit)
    if not frame or not frame._ohTSContainer then
        return
    end

    frame.unit = unit or frame.unit

    if not frame._ohTSActive then
        return
    end

    for casterUnit, idx in pairs(frame._ohTSActive) do
        local ic = frame._ohTSIcons and frame._ohTSIcons[idx]
        if ic and frame.unit and UnitExists(casterUnit) then
            ApplyIconTargetState(ic, casterUnit, frame.unit)
        end
    end

    RefreshContainerVisibility(frame)
    PositionIcons(frame)
end

function TS:HideAll(frame)
    if not frame then
        return
    end

    if frame._ohTSContainer then
        frame._ohTSContainer:SetAlpha(0)
        frame._ohTSContainer:Hide()
    end

    if frame._ohTSIcons then
        for i = 1, #frame._ohTSIcons do
            local ic = frame._ohTSIcons[i]
            if ic then
                ic:SetAlpha(0)
                ic:Hide()
            end
        end
    end

    if frame._ohTSActive then
        wipe(frame._ohTSActive)
    end
end

-- ---------------------------------------------------------------------------
-- Cast tracking
-- ---------------------------------------------------------------------------
TS.activeCasters = TS.activeCasters or {} -- [casterUnitToken] = { durObj=, texture=, isChannel=, spellID= }

local function ShowOnAllFramesForCaster(casterUnit)
    local db = GetDBCached()
    if not db.enabled then
        return
    end

    local frames = FramesIter()
    for i = 1, #frames do
        local frame = frames[i]
        if frame and frame.unit and UnitExists(frame.unit) then
            TS:Attach(frame)

            local ic, iconIndex = AcquireIcon(frame)
            frame._ohTSActive[casterUnit] = iconIndex

            ApplyIconTargetState(ic, casterUnit, frame.unit)
            RefreshContainerVisibility(frame)
        end
    end
end

local function HideOnAllFramesForCaster(casterUnit)
    local frames = FramesIter()
    for i = 1, #frames do
        local frame = frames[i]
        if frame and frame._ohTSActive and frame._ohTSActive[casterUnit] then
            local idx = frame._ohTSActive[casterUnit]
            local ic = frame._ohTSIcons and frame._ohTSIcons[idx]

            if ic then
                ic:SetAlpha(0)
                ic:Hide()
            end

            frame._ohTSActive[casterUnit] = nil
            RefreshContainerVisibility(frame)
        end
    end
end

local function ProcessCast(casterUnit, isChannel)
    local db = GetDBCached()
    if not IsValidHostileCaster(casterUnit, db) then
        return
    end

    local name, _, texture, _, _, _, _, _, _, spellID
    local durObj

    if isChannel then
        name, _, texture, _, _, _, _, spellID = UnitChannelInfo(casterUnit)
        durObj = UnitChannelDuration(casterUnit)
    else
        name, _, texture, _, _, _, _, _, _, spellID = UnitCastingInfo(casterUnit)
        durObj = UnitCastingDuration(casterUnit)
    end

    if not name or not durObj then
        return
    end

    local t = TS.activeCasters[casterUnit]
    if not t then
        t = {}
        TS.activeCasters[casterUnit] = t
    end

    t.spellID = spellID
    t.texture = texture
    t.durObj = durObj
    t.isChannel = isChannel

    ShowOnAllFramesForCaster(casterUnit)
end

local function TargetChanged(casterUnit)
    if not UnitExists(casterUnit) then
        TS.activeCasters[casterUnit] = nil
        HideOnAllFramesForCaster(casterUnit)
        return
    end

    local frames = FramesIter()
    for i = 1, #frames do
        local frame = frames[i]
        if frame and frame.unit and frame._ohTSActive then
            local idx = frame._ohTSActive[casterUnit]
            local ic = idx and frame._ohTSIcons and frame._ohTSIcons[idx]
            if ic then
                ApplyIconTargetState(ic, casterUnit, frame.unit)
            end
        end
    end
end

local function CastStopped(casterUnit)
    TS.activeCasters[casterUnit] = nil
    HideOnAllFramesForCaster(casterUnit)
end

local function ReapplyAllActiveCasters()
    local frames = FramesIter()

    for i = 1, #frames do
        TS:HideAll(frames[i])
    end

    for casterUnit in pairs(TS.activeCasters) do
        if UnitExists(casterUnit) then
            ShowOnAllFramesForCaster(casterUnit)
        else
            TS.activeCasters[casterUnit] = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
TS.eventFrame = TS.eventFrame or CreateFrame("Frame")
TS.eventFrame:Hide()

local function OnEvent(_, event, unit)
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_EMPOWER_START" then
        ProcessCast(unit, false)

    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        ProcessCast(unit, true)

    elseif event == "UNIT_TARGET" then
        if not unit or not TS.activeCasters[unit] then
            return
        end
        TargetChanged(unit)

    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_SUCCEEDED"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_EMPOWER_STOP"
    then
        if unit and TS.activeCasters[unit] then
            CastStopped(unit)
        end

    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local db = GetDBCached()
        if IsValidHostileCaster(unit, db) then
            if UnitCastingInfo(unit) then
                ProcessCast(unit, false)
            elseif UnitChannelInfo(unit) then
                ProcessCast(unit, true)
            end
        end

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if unit and TS.activeCasters[unit] then
            CastStopped(unit)
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        ReapplyAllActiveCasters()

    elseif event == "PLAYER_ENTERING_WORLD" then
        wipe(TS.activeCasters)

        local frames = FramesIter()
        for i = 1, #frames do
            TS:HideAll(frames[i])
        end

        local db = GetDBCached()
        for i = 1, 40 do
            local np = "nameplate" .. i
            if UnitExists(np) and IsValidHostileCaster(np, db) then
                if UnitCastingInfo(np) then
                    ProcessCast(np, false)
                elseif UnitChannelInfo(np) then
                    ProcessCast(np, true)
                end
            end
        end
    end
end

TS.eventFrame:SetScript("OnEvent", OnEvent)

-- ---------------------------------------------------------------------------
-- Enable / Disable / Init
-- ---------------------------------------------------------------------------
function TS:Enable()
    self._db = GetDB()

    local db = self._db
    if not db.enabled then
        return
    end

    local ef = self.eventFrame
    ef:UnregisterAllEvents()

    ef:RegisterEvent("UNIT_SPELLCAST_START")
    ef:RegisterEvent("UNIT_SPELLCAST_STOP")
    ef:RegisterEvent("UNIT_SPELLCAST_FAILED")
    ef:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    ef:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    ef:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    ef:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    ef:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START")
    ef:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
    ef:RegisterEvent("UNIT_TARGET")
    ef:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    ef:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    ef:RegisterEvent("GROUP_ROSTER_UPDATE")
    ef:RegisterEvent("PLAYER_ENTERING_WORLD")

    ef:Show()

    OnEvent(nil, "PLAYER_ENTERING_WORLD")
end

function TS:Disable()
    local ef = self.eventFrame
    ef:UnregisterAllEvents()
    ef:Hide()

    local frames = FramesIter()
    for i = 1, #frames do
        TS:HideAll(frames[i])
    end

    wipe(self.activeCasters)
end

function TS:Init()
    self._db = GetDB()
    if self._db.enabled then
        self:Enable()
    else
        self:Disable()
    end
end
