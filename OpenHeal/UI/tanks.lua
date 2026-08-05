-- ============================================================================
-- UI/tanks.lua (OpenHeal)
-- Dedicated tank frames beside the raid grid.
--
-- WHY:
--   db.raid.tankFrames / tankSide / tankW / tankH / tankSpacing / tankOffsetX /
--   tankOffsetY have had a full settings UI - a checkbox, a dropdown and five
--   sliders - since before this file existed, wired to nothing. Ticking
--   "Show Tank Frames" did nothing at all. This implements them.
--
-- COMBAT SAFETY (the hard part):
--   Unlike raid.lua, a tank frame cannot own a fixed unit token: which raidN is
--   a tank changes with the roster. Changing a secure button's unit attribute in
--   combat is blocked, so token assignment happens OUT OF COMBAT ONLY and is
--   deferred to PLAYER_REGEN_ENABLED otherwise.
--
--   Practical effect: if someone respecs to tank mid-pull, their dedicated frame
--   appears when combat ends. Their normal raid frame is unaffected. That is the
--   correct trade - the alternative is a blocked action and broken click-casting.
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns or {}
_G[ADDON] = ns

ns.Tanks = ns.Tanks or {}
local Tanks = ns.Tanks

local U = ns.UnitUtil
local T = ns.Theme

local SafeSetText   = U.SafeSetText
local SafeSetMinMax = U.SafeSetMinMax
local SafeSetValue  = U.SafeSetValue

local CreateFrame        = CreateFrame
local UnitExists         = UnitExists
local InCombatLockdown   = InCombatLockdown
local ipairs             = ipairs
local tonumber           = tonumber

local MAX_TANKS = 8
local POWER_H   = 3
local NAME_H    = 14

Tanks.frames     = Tanks.frames or {}
Tanks.mover      = Tanks.mover or nil
Tanks.eventFrame = Tanks.eventFrame or nil
Tanks._pending   = false

local function GetDB()
    return ns:GetRaidDB()
end

-- ---------------------------------------------------------------------------
-- Button - mirrors the raid button so the two sets look like one UI
-- ---------------------------------------------------------------------------
local function CreateTankButton()
    local btn = CreateFrame("Button", nil, UIParent)
    btn:SetClampedToScreen(true)
    btn:RegisterForClicks("AnyUp", "AnyDown")

    btn._ohKind = "RAID"   -- shares the raid profile's aura/marker config

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(T:Color("frameBG"))

    local function Border()
        local t = btn:CreateTexture(nil, "BORDER")
        t:SetColorTexture(T:Color("frameBorder"))
        return t
    end

    btn.btop = Border(); btn.btop:SetPoint("TOPLEFT");    btn.btop:SetPoint("TOPRIGHT");    btn.btop:SetHeight(1)
    btn.bbot = Border(); btn.bbot:SetPoint("BOTTOMLEFT"); btn.bbot:SetPoint("BOTTOMRIGHT"); btn.bbot:SetHeight(1)
    btn.blef = Border(); btn.blef:SetPoint("TOPLEFT");    btn.blef:SetPoint("BOTTOMLEFT");  btn.blef:SetWidth(1)
    btn.brig = Border(); btn.brig:SetPoint("TOPRIGHT");   btn.brig:SetPoint("BOTTOMRIGHT"); btn.brig:SetWidth(1)

    btn.nameBar = CreateFrame("Frame", nil, btn)
    btn.nameBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    btn.nameBar:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
    btn.nameBar:SetHeight(NAME_H)

    btn.nameBar.bg = btn.nameBar:CreateTexture(nil, "BACKGROUND")
    btn.nameBar.bg:SetAllPoints()
    btn.nameBar.bg:SetColorTexture(T:Color("nameBarBG"))

    btn.power = CreateFrame("StatusBar", nil, btn)
    btn.power:SetPoint("BOTTOMLEFT", 1, 1)
    btn.power:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.power:SetHeight(POWER_H)
    T:ApplyBarTexture(btn.power)
    btn.power:SetStatusBarColor(T:Color("power"))
    SafeSetMinMax(btn.power, 0, 1)
    SafeSetValue(btn.power, 1)
    btn.power:Hide()

    btn.hp = CreateFrame("StatusBar", nil, btn)
    btn.hp:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -(1 + NAME_H))
    btn.hp:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    T:ApplyBarTexture(btn.hp)
    SafeSetMinMax(btn.hp, 0, 1)
    SafeSetValue(btn.hp, 1)

    if ns.Smoothing then ns.Smoothing:Register(btn.hp) end

    btn.hpbg = btn.hp:CreateTexture(nil, "BACKGROUND")
    btn.hpbg:SetAllPoints()
    btn.hpbg:SetColorTexture(T:Color("barBG"))

    btn.nameText = btn.nameBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    T:ApplyFont(btn.nameText)
    btn.nameText:SetPoint("CENTER", btn.nameBar, "CENTER", 0, 0)
    btn.nameText:SetText("")

    btn._hpPctOverlay = CreateFrame("Frame", nil, UIParent)
    btn._hpPctOverlay:SetSize(80, 18)
    btn._hpPctOverlay:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn._hpPctText = btn._hpPctOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    T:ApplyFont(btn._hpPctText)
    btn._hpPctText:SetPoint("CENTER")
    btn._hpPctText:SetTextColor(T:Color("text"))

    -- Same module stack as a raid frame, so tanks get dispel borders, debuffs,
    -- HoT icons and absorb overlays rather than being second-class frames.
    if ns.Dispel and ns.Dispel.Attach then ns.Dispel:Attach(btn) end
    if ns.Debuffs and ns.Debuffs.Attach then ns.Debuffs:Attach(btn) end
    if ns.IncomingHeals and ns.IncomingHeals.Attach then ns.IncomingHeals:Attach(btn) end
    if ns.HealAbsorb and ns.HealAbsorb.Attach then ns.HealAbsorb:Attach(btn) end
    if ns.ShieldAbsorb and ns.ShieldAbsorb.Attach then ns.ShieldAbsorb:Attach(btn) end
    if ns.FriendlyBuffs and ns.FriendlyBuffs.Attach then ns.FriendlyBuffs:Attach(btn) end
    if ns.RaidMarker and ns.RaidMarker.Attach then ns.RaidMarker:Attach(btn) end
    if ns.Aggro and ns.Aggro.Attach then ns.Aggro:Attach(btn) end
    if ns.Resurrect and ns.Resurrect.Attach then ns.Resurrect:Attach(btn) end

    btn:Hide()
    return btn
end

-- ---------------------------------------------------------------------------
-- Roster
-- ---------------------------------------------------------------------------
function Tanks:GetUnits()
    local list = {}

    if IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) and U.IsTank(u) then
                list[#list + 1] = u
                if #list >= MAX_TANKS then break end
            end
        end
    else
        if UnitExists("player") and U.IsTank("player") then
            list[#list + 1] = "player"
        end
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) and U.IsTank(u) then
                list[#list + 1] = u
            end
        end
    end

    return list
end

-- ---------------------------------------------------------------------------
-- Update
-- ---------------------------------------------------------------------------
local function UpdateHealthText(frame, unit)
    local fs = frame._hpPctText
    if not fs then return end

    if UnitIsConnected and not UnitIsConnected(unit) then
        SafeSetText(fs, "DC")
        fs:SetTextColor(T:Color("textDim"))
        return
    end
    if UnitIsDeadOrGhost(unit) then
        SafeSetText(fs, "DEAD")
        fs:SetTextColor(T:Color("textDim"))
        return
    end
    if not U.IsSafeUnit(unit) then
        SafeSetText(fs, "")
        return
    end

    fs:SetTextColor(T:Color("text"))

    local pct = U.GetHealthPercent(unit)
    if pct == nil then
        SafeSetText(fs, "")
    elseif U.IsSecretValue(pct) then
        if not U.SafeSetFormattedText(fs, "%d%%", pct) then
            SafeSetText(fs, "")
        end
    else
        local n = tonumber(pct)
        SafeSetText(fs, n and string.format("%d%%", n) or "")
    end
end

function Tanks:Apply(frame)
    local u = frame.unit
    if not u or not UnitExists(u) then return end

    local db = GetDB()

    T:ApplyToUnitButton(frame)

    SafeSetText(frame.nameText, U.GetDisplayName(u, frame, 12, true))

    local cur, mx = U.GetHealthValues(u)
    SafeSetMinMax(frame.hp, 0, mx)
    if ns.Smoothing then ns.Smoothing:SetValue(frame.hp, cur) else SafeSetValue(frame.hp, cur) end

    UpdateHealthText(frame, u)

    local r, g, b
    if db.classColor then r, g, b = U.GetClassColor(u) end
    if not r then r, g, b = T:Color("health") end
    frame.hp:SetStatusBarColor(r, g, b)

    if ns.Dispel then ns.Dispel:Update(frame, u) end
    if ns.Debuffs then ns.Debuffs:Update(frame, u) end
    if ns.IncomingHeals then ns.IncomingHeals:Update(frame, u, cur, mx) end
    if ns.HealAbsorb then ns.HealAbsorb:Update(frame, u, cur, mx) end
    if ns.ShieldAbsorb then ns.ShieldAbsorb:Update(frame, u, cur, mx) end
    if ns.FriendlyBuffs then ns.FriendlyBuffs:Update(frame, u) end
    if ns.RaidMarker then ns.RaidMarker:Update(frame, u) end
    if ns.Aggro then ns.Aggro:Update(frame, u) end
    if ns.Resurrect then ns.Resurrect:Update(frame, u) end
end

function Tanks:UpdateHealth(frame)
    local u = frame.unit
    if not u or not UnitExists(u) then return end

    local cur, mx = U.GetHealthValues(u)
    SafeSetMinMax(frame.hp, 0, mx)
    if ns.Smoothing then ns.Smoothing:SetValue(frame.hp, cur) else SafeSetValue(frame.hp, cur) end

    UpdateHealthText(frame, u)

    if ns.IncomingHeals then ns.IncomingHeals:Update(frame, u, cur, mx) end
    if ns.HealAbsorb then ns.HealAbsorb:Update(frame, u, cur, mx) end
    if ns.ShieldAbsorb then ns.ShieldAbsorb:Update(frame, u, cur, mx) end
end

-- ---------------------------------------------------------------------------
-- Mover + layout
-- ---------------------------------------------------------------------------
local function CreateMover()
    local m = CreateFrame("Frame", "OpenHealTankMover", UIParent)
    m:SetSize(140, 16)
    m:SetFrameStrata("DIALOG")
    m:Hide()

    m.bg = m:CreateTexture(nil, "BACKGROUND")
    m.bg:SetAllPoints()
    m.bg:SetColorTexture(0, 0, 0, 0.35)

    m.text = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    m.text:SetPoint("CENTER")
    m.text:SetText("Tanks (drag)")

    m:EnableMouse(true)
    m:SetMovable(true)
    m:RegisterForDrag("LeftButton")

    m:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        if GetDB().locked then return end
        self:StartMoving()
    end)

    m:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db = GetDB()
        local _, _, _, x, y = self:GetPoint()
        db.tankOffsetX = math.floor((tonumber(x) or 0) + 0.5)
        db.tankOffsetY = math.floor((tonumber(y) or 0) + 0.5)
        Tanks:Build()
    end)

    return m
end

function Tanks:Layout(frames)
    local db = GetDB()

    local raidW = tonumber(db.w) or 160
    local raidH = tonumber(db.h) or 46

    local w = tonumber(db.tankW) or (raidW + 20)
    local h = tonumber(db.tankH) or (raidH + 10)
    local spacing = tonumber(db.tankSpacing) or (tonumber(db.spacing) or 4)

    for i, f in ipairs(frames) do
        f:SetSize(w, h)
        f:ClearAllPoints()

        if i == 1 then
            f:SetPoint("TOPLEFT", self.mover, "TOPLEFT", 0, 0)
        else
            f:SetPoint("TOP", frames[i - 1], "BOTTOM", 0, -spacing)
        end

        if ns.Aggro then ns.Aggro:Place(f) end
        if ns.RaidMarker then ns.RaidMarker:Place(f) end
        if ns.Resurrect then ns.Resurrect:Place(f) end
        if ns.FriendlyBuffs then ns.FriendlyBuffs:Place(f) end

        if f._hpPctOverlay then
            f._hpPctOverlay:ClearAllPoints()
            f._hpPctOverlay:SetPoint("CENTER", f, "CENTER", 0, 0)
        end
    end

    if self.mover then
        self.mover:SetSize(math.max(140, w), math.max(16, h))
    end
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
function Tanks:Build()
    local db = GetDB()

    if not db.tankFrames then
        for _, f in ipairs(self.frames) do
            U.HideFrame(f)
        end
        if self.mover then self.mover:Hide() end
        return
    end

    -- Unit assignment touches secure attributes; defer it out of combat.
    if InCombatLockdown() then
        self._pending = true
        return
    end
    self._pending = false

    if not self.mover then
        self.mover = CreateMover()
    end

    -- Anchored relative to the raid grid so the two move together.
    local raidMover = ns.Raid and ns.Raid.mover
    local side = (db.tankSide == "RIGHT") and "RIGHT" or "LEFT"
    local ox = tonumber(db.tankOffsetX) or 0
    local oy = tonumber(db.tankOffsetY) or 0

    self.mover:ClearAllPoints()
    if raidMover then
        if side == "LEFT" then
            self.mover:SetPoint("TOPRIGHT", raidMover, "TOPLEFT", ox - 12, oy)
        else
            self.mover:SetPoint("TOPLEFT", raidMover, "TOPRIGHT", ox + 12, oy)
        end
    else
        self.mover:SetPoint("CENTER", UIParent, "CENTER", ox - 300, oy)
    end

    self.mover:SetShown(not db.locked)

    local units = self:GetUnits()
    local shown = {}

    for i = 1, MAX_TANKS do
        local f = self.frames[i]
        local u = units[i]

        if u then
            if not f then
                f = CreateTankButton()
                self.frames[i] = f
            end

            -- Re-point the secure overlay only when the token actually changes.
            if f.unit ~= u then
                f.unit = u
                f._stableUnit = u
                if _G.OpenHeal_RegisterFrame then
                    _G.OpenHeal_RegisterFrame(f, u)
                end
            end

            f:Show()
            U.SoftShow(f)
            self:Apply(f)
            shown[#shown + 1] = f

        elseif f then
            U.HideFrame(f)
        end
    end

    self:Layout(shown)
end

function Tanks:OnUnit(unit, event)
    for _, f in ipairs(self.frames) do
        if f and f:IsShown() and f.unit == unit then
            if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
                self:UpdateHealth(f)
            else
                self:Apply(f)
            end
            return
        end
    end
end

function Tanks:Init()
    if self.eventFrame then return end

    local ef = CreateFrame("Frame")
    self.eventFrame = ef

    ef:RegisterEvent("GROUP_ROSTER_UPDATE")
    ef:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    ef:RegisterEvent("PLAYER_ENTERING_WORLD")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")

    ef:RegisterEvent("UNIT_HEALTH")
    ef:RegisterEvent("UNIT_MAXHEALTH")
    ef:RegisterEvent("UNIT_AURA")
    ef:RegisterEvent("UNIT_NAME_UPDATE")
    ef:RegisterEvent("UNIT_CONNECTION")

    ef:SetScript("OnEvent", function(_, event, unit)
        if event == "GROUP_ROSTER_UPDATE"
        or event == "PLAYER_ROLES_ASSIGNED"
        or event == "PLAYER_ENTERING_WORLD" then
            Tanks:Build()
            return
        end

        if event == "PLAYER_REGEN_ENABLED" then
            if Tanks._pending then Tanks:Build() end
            return
        end

        if unit then
            Tanks:OnUnit(unit, event)
        end
    end)

    self:Build()
end
