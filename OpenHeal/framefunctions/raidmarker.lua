-- ============================================================================
-- raidmarker.lua (OpenHeal) - WoW 12.0 / Midnight
-- Raid target icon (star / circle / diamond / triangle / moon / square /
-- cross / skull) on party and raid unit buttons.
--
-- Why this exists:
--   Every other healing frame addon shows these, and healers get assigned by
--   marker constantly ("dispel the skull", "external on the star"). Without it
--   you have to look away from the frames to find the marked unit.
--
-- 12.0 notes:
--   - GetRaidTargetIndex() returns a SECRET number. An earlier version of this
--     file claimed otherwise and used the result directly as a table key, which
--     raised "attempted to index a table that cannot be indexed with secret
--     keys" on every party rebuild. The index must be reduced to a plain number
--     before it touches TEXCOORDS.
--   - If it cannot be reduced, the marker is hidden. A missing icon is a far
--     better outcome than an error on every roster update.
--   - This is a pure texture overlay: no secure attributes, nothing that can
--     taint or be blocked in combat.
--
-- API:
--   ns.RaidMarker:Attach(frame)
--   ns.RaidMarker:Place(frame)
--   ns.RaidMarker:Update(frame, unit)
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns
ns.RaidMarker = ns.RaidMarker or {}
local RM = ns.RaidMarker

local CreateFrame        = CreateFrame
local UnitExists         = UnitExists
local GetRaidTargetIndex = GetRaidTargetIndex
local tonumber           = tonumber
local type               = type
local pcall              = pcall
local floor              = math.floor

local ICON_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

-- 4x2 grid of 64px icons in a 256px texture.
local TEXCOORDS = {
    [1] = { 0.00, 0.25, 0.00, 0.25 }, -- star
    [2] = { 0.25, 0.50, 0.00, 0.25 }, -- circle
    [3] = { 0.50, 0.75, 0.00, 0.25 }, -- diamond
    [4] = { 0.75, 1.00, 0.00, 0.25 }, -- triangle
    [5] = { 0.00, 0.25, 0.25, 0.50 }, -- moon
    [6] = { 0.25, 0.50, 0.25, 0.50 }, -- square
    [7] = { 0.50, 0.75, 0.25, 0.50 }, -- cross
    [8] = { 0.75, 1.00, 0.25, 0.50 }, -- skull
}

local DEFAULT_SIZE = 14
local MIN_SIZE, MAX_SIZE = 8, 32

-- ----------------------------------------------------------------------------
-- Config
-- ----------------------------------------------------------------------------
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
    if not db then return true, DEFAULT_SIZE end

    if db.showRaidMarker == nil then db.showRaidMarker = true end

    local size = tonumber(db.raidMarkerSize) or DEFAULT_SIZE
    size = floor(size + 0.5)
    if size < MIN_SIZE then size = MIN_SIZE end
    if size > MAX_SIZE then size = MAX_SIZE end

    return db.showRaidMarker ~= false, size
end

-- ----------------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------------
function RM:Attach(frame)
    if not frame or frame._ohMarker then return frame and frame._ohMarker end

    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(DEFAULT_SIZE, DEFAULT_SIZE)
    holder:SetFrameLevel((frame:GetFrameLevel() or 0) + 60)
    holder:SetIgnoreParentAlpha(false)
    holder:Hide()

    local tex = holder:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(ICON_TEXTURE)

    holder.tex = tex
    frame._ohMarker = holder

    self:Place(frame)
    return holder
end

function RM:Place(frame)
    local holder = frame and frame._ohMarker
    if not holder then return end

    local _, size = GetCfg(frame)
    holder:SetSize(size, size)

    -- Left edge of the health bar: the name sits top-left, role top-right and
    -- debuffs along the bottom, so this corner is free on both layouts.
    local anchorTo = frame.hp or frame
    holder:ClearAllPoints()
    holder:SetPoint("LEFT", anchorTo, "LEFT", 2, 0)
end

function RM:Update(frame, unit)
    local holder = frame and frame._ohMarker
    if not holder then return end

    local enabled, size = GetCfg(frame)

    if not enabled or not unit or not UnitExists(unit) then
        holder:Hide()
        return
    end

    if not GetRaidTargetIndex then
        holder:Hide()
        return
    end

    local okGet, raw = pcall(GetRaidTargetIndex, unit)
    if not okGet or raw == nil then
        holder:Hide()
        return
    end

    -- Reduce to a plain integer BEFORE it is used as a table key.
    local index = ns.UnitUtil and ns.UnitUtil.ScrubNumber(raw) or nil
    if type(index) ~= "number" then
        holder:Hide()
        return
    end

    local coords = TEXCOORDS[index]
    if not coords then
        holder:Hide()
        return
    end

    if holder:GetWidth() ~= size then
        holder:SetSize(size, size)
    end

    holder.tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    holder:Show()
end

-- ----------------------------------------------------------------------------
-- Marker changes are broadcast for the whole group at once, so refresh every
-- visible frame rather than making party.lua/raid.lua route a per-unit event.
-- ----------------------------------------------------------------------------
local function RefreshAll()
    local party = ns.Party and ns.Party.frames
    if party then
        for i = 1, #party do
            local f = party[i]
            if f and f:IsShown() then RM:Update(f, f.unit) end
        end
    end

    local raid = ns.Raid and ns.Raid.frames
    if raid then
        for i = 1, #raid do
            local f = raid[i]
            if f and f:IsShown() then RM:Update(f, f.unit) end
        end
    end
end

RM.RefreshAll = RefreshAll

local ef = CreateFrame("Frame")
ef:RegisterEvent("RAID_TARGET_UPDATE")
ef:SetScript("OnEvent", RefreshAll)
