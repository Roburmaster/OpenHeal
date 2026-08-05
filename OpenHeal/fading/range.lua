-- ============================================================================
-- range.lua (OpenHeal)
--
-- Goal
-- ----
-- Party/Raid range fading that works in WoW Midnight.
--
-- Rules
-- -----
-- 1) Classes with a friendly spell use spell range.
-- 2) Classes without a friendly spell use UnitInRange.
-- 3) Secret booleans are NEVER tested in Lua.
-- 4) Secret booleans are passed directly to SetAlphaFromBoolean.
-- 5) Dead/offline/missing units use plain SetAlpha.
--
-- Notes
-- -----
-- This version removes latching/smoothing logic to avoid "stuck out of range"
-- behavior. Each tick applies the current state directly.
-- ============================================================================

local ADDON, ns = ...
ns.Range = ns.Range or {}
local Range = ns.Range

-- ============================================================================
-- FRIENDLY SPELL RANGE TABLE
-- ----------------------------------------------------------------------------
-- We pick the first spell the player actually knows.
-- ============================================================================
local CLASS_FRIENDLY = {
    PRIEST  = { 2061, 2050, 17 },
    DRUID   = { 8936, 774, 33763 },
    PALADIN = { 19750, 82326 },
    SHAMAN  = { 8004, 77472, 61295 },
    MONK    = { 116670, 124682, 115175 },
    EVOKER  = { 361469, 355913, 360995 },
    WARLOCK = { 20707 },
}

-- ============================================================================
-- API UPVALUES
-- ============================================================================
local C_Spell_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange

local UnitInRange        = UnitInRange
local UnitExists         = UnitExists
local UnitClass          = UnitClass
local UnitIsUnit         = UnitIsUnit
local UnitIsConnected    = UnitIsConnected
local UnitIsDeadOrGhost  = UnitIsDeadOrGhost
local IsInGroup          = IsInGroup
local IsInRaid           = IsInRaid
local IsPlayerSpell      = IsPlayerSpell
local CreateFrame        = CreateFrame

local type     = type
local tonumber = tonumber
local ipairs   = ipairs
local pcall    = pcall

local friendlySpellID

-- ============================================================================
-- SAFE DB HELPERS
-- ============================================================================
local function Clamp01(x)
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
end

local function SafeNumber(v, fallback)
    if type(v) == "number" then
        if v ~= v then return fallback end
        return v
    end

    local n = tonumber(v)
    if type(n) ~= "number" or n ~= n then
        return fallback
    end

    return n
end

local function SafeAlpha(v, fallback)
    return Clamp01(SafeNumber(v, fallback))
end

local function SafeUpdateRate(v)
    local n = SafeNumber(v, 0.20)
    if n < 0.05 then n = 0.05 end
    if n > 1.00 then n = 1.00 end
    return n
end

local function GetRangeDB()
    return ns.GetRangeDB and ns:GetRangeDB() or nil
end

-- ============================================================================
-- SPELL PICKING
-- ============================================================================
local function PickSpell(list)
    if not list or not IsPlayerSpell then
        return nil
    end

    for _, id in ipairs(list) do
        if IsPlayerSpell(id) then
            return id
        end
    end

    return nil
end

local function RefreshSpells()
    local _, class = UnitClass("player")
    friendlySpellID = PickSpell(CLASS_FRIENDLY[class])
end

-- ============================================================================
-- TARGET CACHE
-- ----------------------------------------------------------------------------
-- Prefer holder/container if available.
-- Otherwise use known visual elements.
-- ============================================================================
local function CacheTargets(frame)
    if frame._rangeTargets then
        return frame._rangeTargets
    end

    local t = {}

    if frame.rangeHolder and frame.rangeHolder.SetAlphaFromBoolean then
        t[#t+1] = frame.rangeHolder
    elseif frame.holder and frame.holder.SetAlphaFromBoolean then
        t[#t+1] = frame.holder
    elseif frame.container and frame.container.SetAlphaFromBoolean then
        t[#t+1] = frame.container
    else
        if frame.bg and frame.bg.SetAlpha then t[#t+1] = frame.bg end
        if frame.hp and frame.hp.SetAlpha then t[#t+1] = frame.hp end
        if frame.hpbg and frame.hpbg.SetAlpha then t[#t+1] = frame.hpbg end
        if frame.power and frame.power.SetAlpha then t[#t+1] = frame.power end
        if frame.nameText and frame.nameText.SetAlpha then t[#t+1] = frame.nameText end
        if frame.roleText and frame.roleText.SetAlpha then t[#t+1] = frame.roleText end
        if frame.groupText and frame.groupText.SetAlpha then t[#t+1] = frame.groupText end

        -- The health % overlay is parented to UIParent (not to the button) so
        -- it is not covered by the button's own alpha. Fade it explicitly,
        -- otherwise out-of-range frames kept a full-brightness % on top of a
        -- dimmed bar.
        if frame._hpPctOverlay and frame._hpPctOverlay.SetAlpha then
            t[#t+1] = frame._hpPctOverlay
        end

        if #t == 0 and frame.SetAlpha then
            t[#t+1] = frame
        end
    end

    frame._rangeTargets = t
    return t
end

-- ============================================================================
-- PLAIN ALPHA
-- ----------------------------------------------------------------------------
-- Used only for normal, non-secret states:
--   missing / dead / offline / self / no-group
-- ============================================================================
local function ApplyPlainAlpha(frame, alpha)
    if not frame then return end
    alpha = SafeAlpha(alpha, 1.0)

    local targets = CacheTargets(frame)
    if not targets then return end

    for i = 1, #targets do
        local obj = targets[i]
        if obj and obj.SetAlpha then
            obj:SetAlpha(alpha)
        end
    end
end

-- ============================================================================
-- SECRET ALPHA
-- ----------------------------------------------------------------------------
-- Passes secret boolean directly to SetAlphaFromBoolean.
-- Never inspect the value in Lua.
-- If an object lacks SetAlphaFromBoolean, it is skipped.
-- ============================================================================
local function ApplySecretAlpha(frame, secretValue, alphaIn, alphaOut)
    if not frame then return end

    alphaIn = SafeAlpha(alphaIn, 1.0)
    alphaOut = SafeAlpha(alphaOut, 0.5)

    local targets = CacheTargets(frame)
    if not targets then return end

    for i = 1, #targets do
        local obj = targets[i]
        if obj and obj.SetAlphaFromBoolean then
            obj:SetAlphaFromBoolean(secretValue, alphaIn, alphaOut)
        end
    end
end

-- ============================================================================
-- SECRET RANGE SOURCES
-- ----------------------------------------------------------------------------
-- Classes with friendly spell:
--   use spell range
--
-- Classes without friendly spell:
--   use UnitInRange
--
-- Return value is opaque/secret and must NOT be tested in Lua.
-- ============================================================================
local function GetSecretRangeValue(unit)
    if friendlySpellID and C_Spell_IsSpellInRange then
        local ok, r = pcall(C_Spell_IsSpellInRange, friendlySpellID, unit)
        if ok then
            return r
        end
        return nil
    end

    local ok, r = pcall(UnitInRange, unit)
    if ok then
        return r
    end

    return nil
end

-- ============================================================================
-- MAIN FRAME UPDATE
-- ----------------------------------------------------------------------------
-- Plain states:
--   missing/dead/offline  -> out alpha
--   self                  -> in alpha
--   not in group/raid     -> in alpha
--
-- Secret state:
--   use spell range or UnitInRange directly
-- ============================================================================
function Range:UpdateFrame(frame, alphaIn, alphaOut)
    if not frame or not frame.unit then return end
    if frame.IsShown and not frame:IsShown() then return end

    alphaIn = SafeAlpha(alphaIn, 1.0)
    alphaOut = SafeAlpha(alphaOut, 0.5)

    local unit = frame.unit

    if not UnitExists(unit) then
        ApplyPlainAlpha(frame, alphaOut)
        return
    end

    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
        ApplyPlainAlpha(frame, alphaOut)
        return
    end

    if UnitIsConnected and not UnitIsConnected(unit) then
        ApplyPlainAlpha(frame, alphaOut)
        return
    end

    if UnitIsUnit and UnitIsUnit(unit, "player") then
        ApplyPlainAlpha(frame, alphaIn)
        return
    end

    if not (IsInGroup() or IsInRaid()) then
        ApplyPlainAlpha(frame, alphaIn)
        return
    end

    local secretRange = GetSecretRangeValue(unit)

    -- Do not test secretRange in Lua.
    -- Pass it directly to the engine helper.
    if secretRange ~= nil then
        ApplySecretAlpha(frame, secretRange, alphaIn, alphaOut)
    else
        -- If range API failed, prefer visible over stuck faded.
        ApplyPlainAlpha(frame, alphaIn)
    end
end

-- ============================================================================
-- PET FRAME UPDATE
-- ----------------------------------------------------------------------------
-- Pets inherit owner range.
-- ============================================================================
function Range:UpdatePetFrame(frame, alphaIn, alphaOut)
    if not frame or not frame.unit then return end
    if frame.IsShown and not frame:IsShown() then return end

    if not UnitExists(frame.unit) then
        ApplyPlainAlpha(frame, alphaOut)
        return
    end

    local ownerUnit = frame.ownerUnit
    if not ownerUnit then
        ApplyPlainAlpha(frame, alphaIn)
        return
    end

    alphaIn = SafeAlpha(alphaIn, 1.0)
    alphaOut = SafeAlpha(alphaOut, 0.5)

    if not UnitExists(ownerUnit) then
        ApplyPlainAlpha(frame, alphaOut)
        return
    end

    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(ownerUnit) then
        ApplyPlainAlpha(frame, alphaOut)
        return
    end

    if UnitIsConnected and not UnitIsConnected(ownerUnit) then
        ApplyPlainAlpha(frame, alphaOut)
        return
    end

    if UnitIsUnit and UnitIsUnit(ownerUnit, "player") then
        ApplyPlainAlpha(frame, alphaIn)
        return
    end

    if not (IsInGroup() or IsInRaid()) then
        ApplyPlainAlpha(frame, alphaIn)
        return
    end

    local secretRange = GetSecretRangeValue(ownerUnit)

    if secretRange ~= nil then
        ApplySecretAlpha(frame, secretRange, alphaIn, alphaOut)
    else
        ApplyPlainAlpha(frame, alphaIn)
    end
end

-- ============================================================================
-- DRIVER
-- ----------------------------------------------------------------------------
-- Simple ticker. No latching, no smoothing.
-- ============================================================================
local tickerFrame = CreateFrame("Frame")
local tickerGroup = tickerFrame:CreateAnimationGroup()
local tickerAnim = tickerGroup:CreateAnimation()
tickerAnim:SetDuration(0.20)
tickerGroup:SetLooping("REPEAT")

-- Set once when range fading gets turned off, so frames that were mid-fade are
-- restored to full alpha instead of being left dimmed until the next reload.
local wasEnabled = true

local function ResetAllToFullAlpha()
    local function ResetList(list)
        if not list then return end
        for i = 1, #list do
            local frame = list[i]
            if frame then ApplyPlainAlpha(frame, 1.0) end
        end
    end

    ResetList(ns.Party and ns.Party.frames)
    ResetList(ns.Raid and ns.Raid.frames)
    ResetList(ns.Pet and ns.Pet.partyFrames)
    ResetList(ns.Pet and ns.Pet.raidFrames)

    if ns.Pet and ns.Pet.playerFrame then
        ApplyPlainAlpha(ns.Pet.playerFrame, 1.0)
    end
end

tickerGroup:SetScript("OnLoop", function()
    local rdb = GetRangeDB()
    local enabled = (rdb == nil) and true or (rdb.enabled ~= false)
    if not enabled then
        if wasEnabled then
            wasEnabled = false
            ResetAllToFullAlpha()
        end
        return
    end
    wasEnabled = true

    local rate = SafeUpdateRate(rdb and rdb.update)
    if tickerAnim:GetDuration() ~= rate then
        tickerAnim:SetDuration(rate)
    end

    local alphaIn = SafeAlpha(rdb and rdb.alphaIn, 1.0)
    local alphaOut = SafeAlpha(rdb and rdb.alphaOut, 0.5)

    -- Party
    local partyFrames = ns.Party and ns.Party.frames
    if partyFrames then
        for i = 1, #partyFrames do
            local frame = partyFrames[i]
            if frame and frame.IsShown and frame:IsShown() then
                Range:UpdateFrame(frame, alphaIn, alphaOut)
            end
        end
    end

    -- Raid
    local raidFrames = ns.Raid and ns.Raid.frames
    if raidFrames then
        for i = 1, #raidFrames do
            local frame = raidFrames[i]
            if frame and frame.IsShown and frame:IsShown() then
                Range:UpdateFrame(frame, alphaIn, alphaOut)
            end
        end
    end

    -- Player pet
    if ns.Pet and ns.Pet.playerFrame and ns.Pet.playerFrame.IsShown and ns.Pet.playerFrame:IsShown() then
        Range:UpdatePetFrame(ns.Pet.playerFrame, alphaIn, alphaOut)
    end

    -- Party pets
    local partyPetFrames = ns.Pet and ns.Pet.partyFrames
    if partyPetFrames then
        for i = 1, #partyPetFrames do
            local frame = partyPetFrames[i]
            if frame and frame.IsShown and frame:IsShown() then
                Range:UpdatePetFrame(frame, alphaIn, alphaOut)
            end
        end
    end

    -- Raid pets
    local raidPetFrames = ns.Pet and ns.Pet.raidFrames
    if raidPetFrames then
        for i = 1, #raidPetFrames do
            local frame = raidPetFrames[i]
            if frame and frame.IsShown and frame:IsShown() then
                Range:UpdatePetFrame(frame, alphaIn, alphaOut)
            end
        end
    end
end)

function Range:Start()
    if not tickerGroup:IsPlaying() then
        local rdb = GetRangeDB()
        tickerAnim:SetDuration(SafeUpdateRate(rdb and rdb.update))
        tickerGroup:Play()
    end
end

function Range:Stop()
    if tickerGroup:IsPlaying() then
        tickerGroup:Stop()
    end
end

function Range:RefreshRate()
    local rdb = GetRangeDB()
    local rate = SafeUpdateRate(rdb and rdb.update)
    tickerAnim:SetDuration(rate)

    if tickerGroup:IsPlaying() then
        tickerGroup:Stop()
        tickerGroup:Play()
    end
end

local starter = CreateFrame("Frame")
starter:RegisterEvent("PLAYER_LOGIN")
starter:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    RefreshSpells()
    Range:Start()
end)
