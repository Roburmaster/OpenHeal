-- ============================================================================
-- framefunctions/aggro.lua (OpenHeal)
-- Threat border on party/raid/pet frames.
--
-- WHY:
--   This is the single most useful thing a healing frame can tell you that
--   OpenHeal did not: who is about to take a hit they were not built for.
--   A dps pulling off the tank needs an external NOW, not after the health bar
--   has already moved.
--
-- COLOURS (Blizzard's threat situation scale):
--   1 = higher threat than tank, not tanking   -> orange  "pulling"
--   2 = tanking, but lower threat than someone -> orange  "pulling"
--   3 = tanking securely                       -> blue    (tanks only)
--   0 = not tanking, low threat                -> nothing
--
--   For a healer the interesting case is 1/2 on a non-tank. "onlyHigh" hides
--   everything except real aggro so tanks do not permanently glow.
--
-- 12.0 safety:
--   UnitThreatSituation can hand back a secret value. It is scrubbed to a plain
--   number before any comparison; if it cannot be scrubbed, the border is
--   hidden rather than guessed at.
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns or {}
_G[ADDON] = ns

ns.Aggro = ns.Aggro or {}
local A = ns.Aggro

local U = ns.UnitUtil
local T = ns.Theme

local CreateFrame = CreateFrame
local UnitExists  = UnitExists
local pcall       = pcall
local tonumber    = tonumber
local ipairs      = ipairs

local function Cfg()
    if ns.GetAggroDB then return ns:GetAggroDB() end
    return { enabled = true, size = 2, onlyHigh = false }
end

-- What a healer actually needs to know depends on whether the unit is supposed
-- to be tanking:
--
--   non-tank, status 1     -> climbing the threat table, about to pull  (orange)
--   non-tank, status 2 / 3 -> is being hit right now                    (red)
--   tank,     status 3     -> holding it, the normal state              (blue)
--   tank,     status 1 / 2 -> losing or regaining threat                (orange)
--
-- The old mapping painted status 3 blue for everyone, so a clothie who had
-- fully taken the boss got the same calm blue as the tank.
local function ThreatColor(status, isTank)
    if isTank then
        if status == 3 then return T:Color("aggroTank") end
        return T:Color("aggroPulling")
    end

    if status >= 2 then return T:Color("aggroAggro") end
    return T:Color("aggroPulling")
end

-- ---------------------------------------------------------------------------
-- Four textures rather than a backdrop: no BackdropTemplate dependency, and it
-- sits cleanly outside the frame edge without fighting the existing 1px border.
-- ---------------------------------------------------------------------------
function A:Attach(frame)
    if not frame or frame._ohAggro then return frame and frame._ohAggro end

    local holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints(frame)
    holder:SetFrameLevel((frame:GetFrameLevel() or 0) + 55)
    holder:SetIgnoreParentAlpha(false)
    holder:Hide()

    local function Edge()
        local t = holder:CreateTexture(nil, "OVERLAY")
        t:SetTexture(T.FLAT)
        return t
    end

    holder.top    = Edge()
    holder.bottom = Edge()
    holder.left   = Edge()
    holder.right  = Edge()

    frame._ohAggro = holder
    self:Place(frame)
    return holder
end

function A:Place(frame)
    local h = frame and frame._ohAggro
    if not h then return end

    local size = tonumber(Cfg().size) or 2
    if size < 1 then size = 1 end
    if size > 6 then size = 6 end

    h.top:ClearAllPoints()
    h.top:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
    h.top:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, 0)
    h.top:SetHeight(size)

    h.bottom:ClearAllPoints()
    h.bottom:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
    h.bottom:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    h.bottom:SetHeight(size)

    h.left:ClearAllPoints()
    h.left:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -size)
    h.left:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, size)
    h.left:SetWidth(size)

    h.right:ClearAllPoints()
    h.right:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, -size)
    h.right:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, size)
    h.right:SetWidth(size)
end

local function SetColor(h, r, g, b)
    h.top:SetColorTexture(r, g, b, 1)
    h.bottom:SetColorTexture(r, g, b, 1)
    h.left:SetColorTexture(r, g, b, 1)
    h.right:SetColorTexture(r, g, b, 1)
end

function A:Update(frame, unit)
    local h = frame and frame._ohAggro
    if not h then return end

    local cfg = Cfg()

    if cfg.enabled == false or not unit or not UnitExists(unit) then
        h:Hide()
        return
    end

    if not UnitThreatSituation then
        h:Hide()
        return
    end

    local ok, raw = pcall(UnitThreatSituation, unit)
    if not ok then
        h:Hide()
        return
    end

    local status = U.ScrubNumber(raw)
    if status == nil or status <= 0 then
        h:Hide()
        return
    end

    -- onlyHigh drops the "climbing the threat table" warning and keeps only
    -- the states where the unit is actually being hit.
    if cfg.onlyHigh and status < 2 then
        h:Hide()
        return
    end

    local isTank = U.IsTank(unit)

    -- A tank holding threat securely is the normal state, not a warning.
    if isTank and status == 3 and not cfg.showTankSecure then
        h:Hide()
        return
    end

    local r, g, b = ThreatColor(status, isTank)

    -- Cache on both inputs: the same status means a different colour depending
    -- on whether the unit is tanking, and roles change between pulls.
    local key = status .. (isTank and "T" or "-")
    if h._lastKey ~= key then
        h._lastKey = key
        SetColor(h, r, g, b)
    end

    h:Show()
end

-- ---------------------------------------------------------------------------
-- Threat changes for many units at once, so refresh the whole visible set
-- rather than making every UI module route a per-unit event.
-- ---------------------------------------------------------------------------
local function RefreshAll()
    local lists = {
        ns.Party and ns.Party.frames,
        ns.Raid and ns.Raid.frames,
        ns.Pet and ns.Pet.frames,
        ns.Tanks and ns.Tanks.frames,
    }

    for _, list in ipairs(lists) do
        if list then
            for i = 1, #list do
                local f = list[i]
                if f and f:IsShown() then
                    A:Update(f, f.unit)
                end
            end
        end
    end
end

A.RefreshAll = RefreshAll

local ef = CreateFrame("Frame")
ef:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
ef:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
ef:RegisterEvent("PLAYER_REGEN_DISABLED")
ef:RegisterEvent("PLAYER_REGEN_ENABLED")
ef:SetScript("OnEvent", RefreshAll)
