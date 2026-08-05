-- ============================================================================
-- readycheck.lua (OpenHeal)
-- Ready Check visuals using COLORED SQUARES.
-- Yellow = waiting, Green = ready, Red = not ready
-- Starter of ready check is marked GREEN immediately.
-- Placement: OUTSIDE LEFT of each unit frame (UIParent overlay).
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns
_G[ADDON] = ns

ns.ReadyCheck = ns.ReadyCheck or {}
local RC = ns.ReadyCheck

local UnitExists = UnitExists
local UnitGUID   = UnitGUID
local UnitName   = UnitName

-- Placement / size
local BOX_SIZE = 14
local XOFF = -6
local YOFF = 0

RC.active = false

-- ------------------------------------------------------------
-- Overlay box
-- ------------------------------------------------------------
local function EnsureBox(btn)
    if not btn or btn._ohReadyBox then return end

    local box = CreateFrame("Frame", nil, UIParent)
    box:SetFrameStrata("TOOLTIP")
    box:SetFrameLevel(9999)
    box:SetSize(BOX_SIZE, BOX_SIZE)
    box:SetClampedToScreen(true)
    box:SetPoint("RIGHT", btn, "LEFT", XOFF, YOFF)
    box:Hide()

    local t = box:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    box.tex = t

    btn._ohReadyBox = box
end

local function AnchorBox(btn)
    if not (btn and btn._ohReadyBox) then return end
    btn._ohReadyBox:ClearAllPoints()
    btn._ohReadyBox:SetPoint("RIGHT", btn, "LEFT", XOFF, YOFF)
end

local function SetBox(btn, state)
    local box = btn and btn._ohReadyBox
    if not (box and box.tex) then return end

    if state == "waiting" then
        box.tex:SetColorTexture(1, 1, 0, 1) -- yellow
        box:Show()
    elseif state == "ready" then
        box.tex:SetColorTexture(0, 1, 0, 1) -- green
        box:Show()
    elseif state == "notready" then
        box.tex:SetColorTexture(1, 0, 0, 1) -- red
        box:Show()
    else
        box:Hide()
    end
end

local function UpdateIdentity(btn)
    local u = btn and btn.unit
    if u and UnitExists(u) then
        btn._ohRC_GUID = UnitGUID(u)
        local n = UnitName(u)
        btn._ohRC_Name = (type(n) == "string") and n or nil
    else
        btn._ohRC_GUID = nil
        btn._ohRC_Name = nil
    end
end

local function NormalizeName(n)
    if type(n) ~= "string" then return nil end
    return (n:match("^([^%-]+)")) or n
end

local function Match(unitOrName, btn)
    if not unitOrName or not btn then return false end

    if type(unitOrName) == "string" and UnitExists(unitOrName) then
        local g = UnitGUID(unitOrName)
        if g and btn._ohRC_GUID and g == btn._ohRC_GUID then
            return true
        end
        local en = NormalizeName(UnitName(unitOrName))
        local bn = NormalizeName(btn._ohRC_Name)
        return en and bn and en == bn
    end

    local en = NormalizeName(unitOrName)
    local bn = NormalizeName(btn._ohRC_Name)
    return en and bn and en == bn
end

-- ------------------------------------------------------------
-- Iterate Party + Raid buttons
-- ------------------------------------------------------------
local function EachButton(fn)
    local Party = ns.Party
    if Party and Party.frames then
        for _, btn in pairs(Party.frames) do
            if btn then fn(btn) end
        end
    end

    local Raid = ns.Raid
    if Raid and Raid.frames then
        for _, btn in pairs(Raid.frames) do
            if btn then fn(btn) end
        end
    end
end

local function ForceBuild()
    if ns.RequestPartyRebuild then
        ns:RequestPartyRebuild()
    elseif ns.Party and ns.Party.Build then
        ns.Party:Build()
    end

    if ns.RequestRaidRebuild then
        ns:RequestRaidRebuild()
    elseif ns.Raid and ns.Raid.Build then
        ns.Raid:Build()
    end
end

local function ScanPrepare()
    ForceBuild()
    EachButton(function(btn)
        EnsureBox(btn)
        UpdateIdentity(btn)
        AnchorBox(btn)
    end)
end

local function ClearAll()
    EachButton(function(btn)
        if btn._ohReadyBox then
            SetBox(btn, nil)
        end
    end)
end

local function MarkAllWaiting()
    ScanPrepare()
    EachButton(function(btn)
        UpdateIdentity(btn)
        SetBox(btn, "waiting")
    end)
end

local function MarkStarterGreen(starterName)
    starterName = NormalizeName(starterName)
    if not starterName then return end

    EachButton(function(btn)
        UpdateIdentity(btn)
        local bn = NormalizeName(btn._ohRC_Name)
        if bn and bn == starterName then
            SetBox(btn, "ready")
        end
    end)
end

-- ------------------------------------------------------------
-- Events
-- ------------------------------------------------------------
local evt = CreateFrame("Frame")
evt:RegisterEvent("PLAYER_ENTERING_WORLD")
evt:RegisterEvent("GROUP_ROSTER_UPDATE")
evt:RegisterEvent("READY_CHECK")
evt:RegisterEvent("READY_CHECK_CONFIRM")
evt:RegisterEvent("READY_CHECK_FINISHED")

evt:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
        ScanPrepare()
        if not RC.active then
            ClearAll()
        else
            MarkAllWaiting()
        end
        return
    end

    if event == "READY_CHECK" then
        RC.active = true
        MarkAllWaiting()
        MarkStarterGreen(a1)
        return
    end

    if event == "READY_CHECK_CONFIRM" then
        ScanPrepare()
        EachButton(function(btn)
            UpdateIdentity(btn)
            if Match(a1, btn) then
                SetBox(btn, (a2 == true) and "ready" or "notready")
            end
        end)
        return
    end

    if event == "READY_CHECK_FINISHED" then
        RC.active = false
        if C_Timer and C_Timer.After then
            C_Timer.After(5, ClearAll)
        else
            ClearAll()
        end
        return
    end
end)
