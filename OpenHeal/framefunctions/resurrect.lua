-- ============================================================================
-- framefunctions/resurrect.lua (OpenHeal)
-- Incoming-resurrection and pending-summon icon.
--
-- WHY:
--   Without it, two healers burn a 10-second cast on the same corpse while a
--   third body stays down. It is a small icon that prevents a very common and
--   very expensive mistake.
--
--   Also covers pending summons (warlock gateway/summon, meeting stone), which
--   is the "why is this person still not here" case.
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns or {}
_G[ADDON] = ns

ns.Resurrect = ns.Resurrect or {}
local R = ns.Resurrect

local CreateFrame = CreateFrame
local UnitExists  = UnitExists
local pcall       = pcall
local ipairs      = ipairs

local ICON_RES     = "Interface\\RaidFrame\\Raid-Icon-Rez"
local ICON_SUMMON  = "Interface\\RaidFrame\\Raid-Icon-SummonPending"
local ICON_ACCEPTED = "Interface\\RaidFrame\\Raid-Icon-SummonAccepted"

local DEFAULT_SIZE = 20

function R:Attach(frame)
    if not frame or frame._ohRes then return frame and frame._ohRes end

    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(DEFAULT_SIZE, DEFAULT_SIZE)
    holder:SetFrameLevel((frame:GetFrameLevel() or 0) + 65)
    holder:Hide()

    local tex = holder:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    holder.tex = tex

    frame._ohRes = holder
    self:Place(frame)
    return holder
end

function R:Place(frame)
    local h = frame and frame._ohRes
    if not h then return end

    -- Centred on the frame: this is a "stop what you are doing" indicator, so
    -- it deliberately sits where the health % is rather than in a corner.
    h:ClearAllPoints()
    h:SetPoint("CENTER", frame, "CENTER", 0, 0)

    local height = frame:GetHeight() or DEFAULT_SIZE
    local size = height * 0.6
    if size < 12 then size = 12 end
    if size > 28 then size = 28 end
    h:SetSize(size, size)
end

function R:Update(frame, unit)
    local h = frame and frame._ohRes
    if not h then return end

    if not unit or not UnitExists(unit) then
        h:Hide()
        return
    end

    -- Incoming res takes priority: it is time-critical and overlaps summons.
    if UnitHasIncomingResurrection then
        local ok, incoming = pcall(UnitHasIncomingResurrection, unit)
        if ok and incoming then
            h.tex:SetTexture(ICON_RES)
            h:Show()
            return
        end
    end

    if C_IncomingSummon and C_IncomingSummon.HasIncomingSummon then
        local ok, has = pcall(C_IncomingSummon.HasIncomingSummon, unit)
        if ok and has then
            local status
            local okS, s = pcall(C_IncomingSummon.IncomingSummonStatus, unit)
            -- Reduce before comparing: == on a secret value raises, same class
            -- of bug as indexing a table with a secret key.
            if okS then
                status = ns.UnitUtil and ns.UnitUtil.ScrubNumber(s) or nil
            end

            -- Enum.SummonStatus is not guaranteed to exist on every build;
            -- reading a field off a nil table here would error inside an
            -- event handler and take the whole refresh down with it.
            local accepted = Enum and Enum.SummonStatus and Enum.SummonStatus.Accepted

            if accepted ~= nil and status ~= nil and status == accepted then
                h.tex:SetTexture(ICON_ACCEPTED)
            else
                h.tex:SetTexture(ICON_SUMMON)
            end
            h:Show()
            return
        end
    end

    h:Hide()
end

-- ---------------------------------------------------------------------------
-- Both events are group-wide, so refresh everything visible.
-- ---------------------------------------------------------------------------
local function RefreshAll()
    local lists = {
        ns.Party and ns.Party.frames,
        ns.Raid and ns.Raid.frames,
        ns.Tanks and ns.Tanks.frames,
    }

    for _, list in ipairs(lists) do
        if list then
            for i = 1, #list do
                local f = list[i]
                if f and f:IsShown() then
                    R:Update(f, f.unit)
                end
            end
        end
    end
end

R.RefreshAll = RefreshAll

local ef = CreateFrame("Frame")
ef:RegisterEvent("INCOMING_RESURRECT_CHANGED")
ef:RegisterEvent("INCOMING_SUMMON_CHANGED")
ef:SetScript("OnEvent", RefreshAll)
