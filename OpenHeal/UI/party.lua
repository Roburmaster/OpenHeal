-- ============================================================================
-- party.lua (OpenHeal)
-- Party frames (no SecureHeader). Uses db.lua: ns:GetPartyDB() (role-profile aware).
-- Midnight-safe / secret-safe hardened for hostile/charm/takeover states.
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns

ns.Party = ns.Party or {}
local Party = ns.Party

local Range   = ns.Range
local Dispel  = ns.Dispel
local Debuffs = ns.Debuffs

local POWER_H = 3

-- Shared helpers live in core/util.lua. These used to be byte-identical copies
-- in this file and in raid.lua; pulling them into locals keeps the call sites
-- and the upvalue lookups exactly as they were.
local U = ns.UnitUtil
local T = ns.Theme

local IsSecretValue        = U.IsSecretValue
local SafeSetText          = U.SafeSetText
local SafeSetFormattedText = U.SafeSetFormattedText
local SafeSetMinMax        = U.SafeSetMinMax
local SafeSetValue         = U.SafeSetValue
local RoleRank             = U.RoleRank
local RoleLetter           = U.RoleLetter
local SoftHide             = U.SoftHide
local SoftShow             = U.SoftShow
local GetHealthValues      = U.GetHealthValues
local GetPowerValues       = U.GetPowerValues
local GetSortName          = U.GetSortName

Party.frames       = Party.frames or {}
Party.eventFrame   = Party.eventFrame or nil
Party.mover        = Party.mover or nil
Party.selectedUnit = Party.selectedUnit or nil

local pcall        = pcall
local type         = type
local ipairs       = ipairs
local pairs        = pairs
local tostring     = tostring
local math_floor   = math.floor
local table_sort   = table.sort

local function GetDB()
    return ns:GetPartyDB()
end

local function IsSafeUnitForHP(unit)
    return U.IsSafeUnit(unit) and true or false
end

local function GetDisplayName(unit, frame)
    return U.GetDisplayName(unit, frame, 18, false)
end

local function UpdatePowerLayout(btn, showPower)
    btn.hp:ClearAllPoints()
    btn.hp:SetPoint("TOPLEFT", 1, -1)

    if showPower then
        btn.power:SetHeight(POWER_H)
        btn.power:Show()
        btn.hp:SetPoint("BOTTOMRIGHT", -1, 1 + POWER_H)
    else
        btn.power:Hide()
        btn.hp:SetPoint("BOTTOMRIGHT", -1, 1)
    end
end

local function PlaceDebuffs(frame)
    if not frame or not frame.hp or not frame._ohDebuffs or not frame._ohDebuffs.holder then return end
    local holder = frame._ohDebuffs.holder
    holder:ClearAllPoints()
    holder:SetPoint("BOTTOM", frame.hp, "BOTTOM", 0, 2)
    holder:SetIgnoreParentAlpha(true)
    holder:SetAlpha(1)
end

local function EnsureTargetedSquare(btn)
    if btn._ohTargetedSquare then return end

    local sq = CreateFrame("Frame", nil, btn)
    sq:SetSize(10, 10)
    sq:SetPoint("BOTTOM", btn, "TOP", 0, 2)
    sq:SetFrameLevel(btn:GetFrameLevel() + 80)
    sq:SetIgnoreParentAlpha(true)
    sq:SetAlpha(0)
    sq:Hide()

    local t = sq:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetColorTexture(1, 0, 0, 1)
    sq.tex = t

    btn._ohTargetedSquare = sq
end

local function EnsureSelectedHighlight(btn)
    if btn._ohSelected then return end

    local sel = btn:CreateTexture(nil, "OVERLAY")
    sel:SetAllPoints(btn)
    sel:SetColorTexture(1, 1, 0, 0.14)
    sel:SetIgnoreParentAlpha(true)
    sel:Hide()
    btn._ohSelected = sel

    local b = btn:CreateTexture(nil, "OVERLAY")
    b:SetPoint("TOPLEFT", -1, 1)
    b:SetPoint("BOTTOMRIGHT", 1, -1)
    b:SetTexture("Interface\\Buttons\\WHITE8x8")
    b:SetVertexColor(1, 1, 0, 0.55)
    b:SetIgnoreParentAlpha(true)
    b:Hide()
    btn._ohSelectedBorder = b
end

-- ----------------------------------------------------------------------------
-- Centre text: health %, or a status word when the unit cannot be healed.
--
-- "0%" for a corpse is ambiguous - every other raid frame addon calls out
-- dead / ghost / disconnected explicitly, because those three need completely
-- different reactions from a healer.
-- ----------------------------------------------------------------------------
local function SetStatusText(fs, text)
    SafeSetText(fs, text)
    fs:SetTextColor(T:Color("textDim"))
end

-- Health writes go through the smoothing driver, which falls back to a direct
-- set whenever the value is secret or smoothing is off.
local function SetHealthValue(frame, value)
    if ns.Smoothing then
        ns.Smoothing:SetValue(frame.hp, value)
    else
        SafeSetValue(frame.hp, value)
    end
end

-- Two colour schemes:
--   classBG off - bar is class coloured (the original look)
--   classBG on  - background is class coloured, bar shows health
--                 Reads "how hurt" first and "who" second, which is the order
--                 you actually need under pressure.
local function ApplyHealthColor(frame, unit, db)
    local cr, cg, cb = U.GetClassColor(unit)
    local style = ns.GetStyleDB and ns:GetStyleDB() or nil

    if style and style.classBG then
        frame.hp:SetStatusBarColor(T:Color("health"))
        if frame.hpbg then
            if cr then
                frame.hpbg:SetColorTexture(cr * 0.55, cg * 0.55, cb * 0.55, 0.95)
            else
                frame.hpbg:SetColorTexture(T:Color("barBG"))
            end
        end
        return
    end

    if db.classColor and cr then
        frame.hp:SetStatusBarColor(cr, cg, cb)
    else
        frame.hp:SetStatusBarColor(T:Color("health"))
    end

    if frame.hpbg then
        frame.hpbg:SetColorTexture(T:Color("barBG"))
    end
end

local function UpdateHealthText(frame, unit)
    local fs = frame._hpPctText
    if not fs then return end

    if UnitIsConnected and not UnitIsConnected(unit) then
        SetStatusText(fs, "DC")
    elseif UnitIsGhost and UnitIsGhost(unit) then
        SetStatusText(fs, "GHOST")
    elseif UnitIsDeadOrGhost(unit) then
        SetStatusText(fs, "DEAD")
    elseif not IsSafeUnitForHP(unit) then
        SafeSetText(fs, "")
    else
        fs:SetTextColor(1, 1, 1, 1)

        local percentValue = nil

        if UnitHealthPercent then
            local ok = pcall(function()
                local scaling = (CurveConstants and CurveConstants.ScaleTo100) or 1
                percentValue = UnitHealthPercent(unit, true, scaling)
            end)
            if not ok then
                percentValue = nil
            end
        else
            local ok = pcall(function()
                local maxH = UnitHealthMax(unit)
                local curH = UnitHealth(unit, true)
                if maxH and curH then
                    percentValue = (curH / maxH) * 100
                end
            end)
            if not ok then
                percentValue = nil
            end
        end

        if percentValue == nil then
            SafeSetText(fs, "")
        elseif IsSecretValue(percentValue) then
            if not SafeSetFormattedText(fs, "%d%%", percentValue) then
                SafeSetText(fs, "")
            end
        else
            local n = tonumber(percentValue)
            SafeSetText(fs, n and string.format("%d%%", n) or "")
        end
    end

    fs:Show()
    if frame._hpPctOverlay then
        frame._hpPctOverlay:Show()
    end
end

function Party:SetSelectedUnit(unit)
    self.selectedUnit = unit
    self:UpdateSelectionHighlights()
end

function Party:UpdateSelectionHighlights()
    local sel = self.selectedUnit
    for _, f in ipairs(self.frames) do
        if f and f.unit and f._ohSelected then
            local isSel = (sel ~= nil and f.unit == sel)
            f._ohSelected:SetShown(isSel)
            f._ohSelectedBorder:SetShown(isSel)
        end
    end
end

function Party:HookOverlayClicks(host, overlay)
    if not overlay or overlay._ohPartyHooked then return end
    overlay._ohPartyHooked = true

    overlay:HookScript("OnClick", function(self, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        if not IsShiftKeyDown() then return end

        local unit = self:GetAttribute("unit") or (host and host.unit)
        if unit and unit ~= "" then
            Party:SetSelectedUnit(unit)
        end
    end)
end

local function CreateMover()
    local m = CreateFrame("Frame", "OpenHealPartyMover", UIParent)
    m:SetSize(180, 18)
    m:SetFrameStrata("DIALOG")
    m:Hide()

    m.bg = m:CreateTexture(nil, "BACKGROUND")
    m.bg:SetAllPoints()
    m.bg:SetColorTexture(0, 0, 0, 0.35)

    m.text = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    m.text:SetPoint("CENTER")
    m.text:SetText("Party (drag)")

    m:EnableMouse(true)
    m:SetMovable(true)
    m:RegisterForDrag("LeftButton")

    m:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        self:StartMoving()
    end)

    m:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()

        local db = GetDB()
        local p, _, rp, x, y = self:GetPoint()

        db.point    = p or db.point
        db.relPoint = rp or db.relPoint
        db.x        = math_floor((x or 0) + 0.5)
        db.y        = math_floor((y or 0) + 0.5)

        if ns.RequestPartyRebuild then ns:RequestPartyRebuild() else Party:Build() end
    end)

    return m
end

local function ApplyMoverPosition(m)
    local db = GetDB()
    m:ClearAllPoints()
    m:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
end

local function CreateUnitButton()
    local btn = CreateFrame("Button", nil, UIParent)
    btn:SetClampedToScreen(true)
    btn:RegisterForClicks("AnyUp", "AnyDown")

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(T:Color("frameBG"))

    local function Border()
        local t = btn:CreateTexture(nil, "BORDER")
        t:SetColorTexture(T:Color("frameBorder"))
        return t
    end

    btn.btop = Border(); btn.bbot = Border(); btn.blef = Border(); btn.brig = Border()
    btn.btop:SetPoint("TOPLEFT");     btn.btop:SetPoint("TOPRIGHT");     btn.btop:SetHeight(1)
    btn.bbot:SetPoint("BOTTOMLEFT");  btn.bbot:SetPoint("BOTTOMRIGHT");  btn.bbot:SetHeight(1)
    btn.blef:SetPoint("TOPLEFT");     btn.blef:SetPoint("BOTTOMLEFT");   btn.blef:SetWidth(1)
    btn.brig:SetPoint("TOPRIGHT");    btn.brig:SetPoint("BOTTOMRIGHT");  btn.brig:SetWidth(1)

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
    T:ApplyBarTexture(btn.hp)
    SafeSetMinMax(btn.hp, 0, 1)
    SafeSetValue(btn.hp, 1)

    if ns.Smoothing then ns.Smoothing:Register(btn.hp) end

    btn.hpbg = btn.hp:CreateTexture(nil, "BACKGROUND")
    btn.hpbg:SetAllPoints()
    btn.hpbg:SetColorTexture(T:Color("barBG"))

    btn.nameText = btn.hp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    T:ApplyFont(btn.nameText)
    btn.nameText:SetTextColor(T:Color("text"))
    btn.nameText:SetPoint("TOPLEFT", btn.hp, "TOPLEFT", 4, -2)
    btn.nameText:SetJustifyH("LEFT")
    btn.nameText:SetText("")

    btn.roleText = btn.hp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    T:ApplyFont(btn.roleText)
    btn.roleText:ClearAllPoints()
    btn.roleText:SetPoint("TOPRIGHT", btn.hp, "TOPRIGHT", -4, -2)
    btn.roleText:SetJustifyH("RIGHT")
    btn.roleText:SetText("")

    EnsureSelectedHighlight(btn)

    -- Set the kind before any module attaches: several of them (debuffs,
    -- friendly buffs, raid markers) pick their config block from it.
    btn._ohKind = "PARTY"

    btn.OpenHeal_OnOverlayCreated = function(host, overlay)
        Party:HookOverlayClicks(host, overlay)
    end

    if not btn._hpPctOverlay then
        local o = CreateFrame("Frame", nil, UIParent)
        o:SetFrameStrata("MEDIUM")
        o:SetFrameLevel(btn:GetFrameLevel() + 2)
        o:SetClampedToScreen(true)
        o:Show()

        o:ClearAllPoints()
        o:SetPoint("CENTER", btn, "CENTER", 0, 0)
        o:SetSize(80, 18)

        local fs = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER", o, "CENTER", 0, 0)
        fs:SetJustifyH("CENTER")
        fs:SetTextColor(1, 1, 1, 1)
        fs:SetText("")
        fs:Show()

        btn._hpPctOverlay = o
        btn._hpPctText = fs
    end

    UpdatePowerLayout(btn, GetDB().showPower)

    if Dispel and Dispel.Attach then Dispel:Attach(btn) end
    if Debuffs and Debuffs.Attach then
        Debuffs:Attach(btn)
        PlaceDebuffs(btn)
    end

    if ns.IncomingHeals and ns.IncomingHeals.Attach then ns.IncomingHeals:Attach(btn) end
    if ns.HealAbsorb   and ns.HealAbsorb.Attach   then ns.HealAbsorb:Attach(btn) end
    if ns.ShieldAbsorb and ns.ShieldAbsorb.Attach then ns.ShieldAbsorb:Attach(btn) end

    local FriendlyBuffs = ns.FriendlyBuffs
    if FriendlyBuffs and FriendlyBuffs.Attach then
        FriendlyBuffs:Attach(btn)
    end

    if ns.RaidMarker and ns.RaidMarker.Attach then ns.RaidMarker:Attach(btn) end
    if ns.Aggro and ns.Aggro.Attach then ns.Aggro:Attach(btn) end
    if ns.Resurrect and ns.Resurrect.Attach then ns.Resurrect:Attach(btn) end

    EnsureTargetedSquare(btn)
    local TargetedSpells = ns.TargetedSpells
    if TargetedSpells and TargetedSpells.Attach then
        TargetedSpells:Attach(btn)
    end

    return btn
end

function Party:GetUnits()
    local list = {}

    if UnitExists("player") then list[#list + 1] = "player" end

    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then list[#list + 1] = u end
    end

    local db = GetDB()
    if db.sort == "ROLE" then
        table_sort(list, function(a, b)
            local ra = UnitGroupRolesAssigned(a)
            local rb = UnitGroupRolesAssigned(b)
            local da = RoleRank(ra)
            local dbb = RoleRank(rb)
            if da ~= dbb then
                return da < dbb
            end

            local na = GetSortName(a)
            local nb = GetSortName(b)
            return na < nb
        end)
    end

    return list
end

-- The unit we READ from. When a member is in a vehicle their health lives on
-- the vehicle token, so displays must follow it. frame.unit (what the secure
-- overlay casts at) deliberately does NOT move: changing a secure unit
-- attribute is blocked in combat, and vehicle entry happens mid-combat.
local function DisplayUnit(frame)
    local u = frame.unit
    if not u then return nil end

    local du = U.ResolveVehicleUnit(u)
    frame.displayUnit = du
    return du
end

function Party:Apply(frame)
    local db = GetDB()
    local u = DisplayUnit(frame)
    if not u or not UnitExists(u) then return end

    -- Pick up bar texture / font changes on frames that already exist.
    T:ApplyToUnitButton(frame)

    UpdatePowerLayout(frame, db.showPower)

    if frame._ohDebuffs then PlaceDebuffs(frame) end

    local FriendlyBuffs = ns.FriendlyBuffs
    if FriendlyBuffs and FriendlyBuffs.Place then
        FriendlyBuffs:Place(frame)
    end

    local displayName = GetDisplayName(u, frame)
    SafeSetText(frame.nameText, displayName)

    if db.showRole then
        local role = UnitGroupRolesAssigned(u)
        SafeSetText(frame.roleText, RoleLetter(role))

        if role == "TANK" then
            frame.roleText:SetTextColor(0.2, 0.6, 1.0, 1)
        elseif role == "HEALER" then
            frame.roleText:SetTextColor(0.2, 1.0, 0.2, 1)
        else
            frame.roleText:SetTextColor(1.0, 0.2, 0.2, 1)
        end

        frame.roleText:Show()
    else
        SafeSetText(frame.roleText, "")
        frame.roleText:Hide()
    end

    local cur, mx = GetHealthValues(u)
    SafeSetMinMax(frame.hp, 0, mx)
    SetHealthValue(frame, cur)

    UpdateHealthText(frame, u)

    ApplyHealthColor(frame, u, db)

    if db.showPower then
        local p, pm = GetPowerValues(u)
        SafeSetMinMax(frame.power, 0, pm)
        SafeSetValue(frame.power, p)
    end

    if Dispel and Dispel.Update then Dispel:Update(frame, u) end
    if Debuffs and Debuffs.Update then Debuffs:Update(frame, u) end

    if ns.IncomingHeals and ns.IncomingHeals.Update then ns.IncomingHeals:Update(frame, u, cur, mx) end
    if ns.HealAbsorb   and ns.HealAbsorb.Update   then ns.HealAbsorb:Update(frame, u, cur, mx) end
    if ns.ShieldAbsorb and ns.ShieldAbsorb.Update then ns.ShieldAbsorb:Update(frame, u, cur, mx) end

    if FriendlyBuffs and FriendlyBuffs.Update then
        FriendlyBuffs:Update(frame, u)
    end

    if ns.RaidMarker then
        ns.RaidMarker:Place(frame)
        ns.RaidMarker:Update(frame, u)
    end

    if ns.Aggro then
        ns.Aggro:Place(frame)
        ns.Aggro:Update(frame, u)
    end

    if ns.Resurrect then
        ns.Resurrect:Place(frame)
        ns.Resurrect:Update(frame, u)
    end

    local TargetedSpells = ns.TargetedSpells
    if TargetedSpells and TargetedSpells.UpdateFrame then
        TargetedSpells:UpdateFrame(frame, u)
    end

    self:UpdateSelectionHighlights()
end

-- ----------------------------------------------------------------------------
-- Lightweight health/power refresh.
--
-- UNIT_HEALTH fires constantly for every unit in combat. Running the full
-- Apply() there meant re-reading names and roles, re-resolving class colours and
-- re-scanning up to 40 auras per unit per health tick - three aura scans deep
-- (dispel + debuffs + friendly buffs) on top. In a 20-man pull that is the
-- single most expensive thing the addon does, and none of it can change as a
-- result of a health event. Only the bars and the % text can.
-- ----------------------------------------------------------------------------
function Party:UpdateHealth(frame)
    local u = DisplayUnit(frame)
    if not u or not UnitExists(u) then return end

    local db = GetDB()
    local cur, mx = GetHealthValues(u)

    SafeSetMinMax(frame.hp, 0, mx)
    SetHealthValue(frame, cur)

    UpdateHealthText(frame, u)

    if db.showPower then
        local p, pm = GetPowerValues(u)
        SafeSetMinMax(frame.power, 0, pm)
        SafeSetValue(frame.power, p)
    end

    -- Absorb/prediction overlays are sized against current HP, so they do have
    -- to follow health. They are cheap: no aura iteration.
    if ns.IncomingHeals and ns.IncomingHeals.Update then ns.IncomingHeals:Update(frame, u, cur, mx) end
    if ns.HealAbsorb   and ns.HealAbsorb.Update   then ns.HealAbsorb:Update(frame, u, cur, mx) end
    if ns.ShieldAbsorb and ns.ShieldAbsorb.Update then ns.ShieldAbsorb:Update(frame, u, cur, mx) end
end

function Party:Layout(frames)
    local db = GetDB()
    local FriendlyBuffs = ns.FriendlyBuffs

    for i, f in ipairs(frames) do
        f:SetSize(db.w, db.h)
        f:ClearAllPoints()

        if i == 1 then
            f:SetPoint("TOPLEFT", self.mover, "TOPLEFT", 0, 0)
        else
            local prev = frames[i - 1]
            if db.orientation == "HORIZONTAL" then
                f:SetPoint("LEFT", prev, "RIGHT", db.spacing, 0)
            else
                f:SetPoint("TOP", prev, "BOTTOM", 0, -db.spacing)
            end
        end

        if f._ohDebuffs then PlaceDebuffs(f) end
        if FriendlyBuffs and FriendlyBuffs.Place then FriendlyBuffs:Place(f) end

        EnsureTargetedSquare(f)
        EnsureSelectedHighlight(f)

        if f._hpPctOverlay then
            f._hpPctOverlay:ClearAllPoints()
            f._hpPctOverlay:SetPoint("CENTER", f, "CENTER", 0, 0)
        end
    end

    self:UpdateSelectionHighlights()
end

function Party:Build()
    local db = GetDB()

    if db.showMover == nil then db.showMover = true end

    if not self.mover then
        self.mover = CreateMover()
    end

    ApplyMoverPosition(self.mover)

    if IsInRaid and IsInRaid() then
        if not InCombatLockdown() then
            for _, f in ipairs(self.frames) do
                f:Hide()
                if f._hpPctOverlay then f._hpPctOverlay:Hide() end
            end
        else
            for _, f in ipairs(self.frames) do
                SoftHide(f)
            end
        end
        if self.mover then self.mover:Hide() end
        return
    end

    local showMover = (db.showMover ~= false) and (not db.locked) and (not InCombatLockdown())
    self.mover:SetShown(showMover)

    if not db.enabled then
        if not InCombatLockdown() then
            for _, f in ipairs(self.frames) do
                f:Hide()
                if f._hpPctOverlay then f._hpPctOverlay:Hide() end
            end
        else
            for _, f in ipairs(self.frames) do
                SoftHide(f)
            end
        end
        return
    end

    local units = self:GetUnits()
    local shown = {}

    for i = 1, #units do
        local f = self.frames[i]
        if not f then
            f = CreateUnitButton()
            self.frames[i] = f
        end

        f.unit = units[i]

        if not InCombatLockdown() then
            f:Show()
        end
        SoftShow(f)

        if _G.OpenHeal_RegisterFrame then
            _G.OpenHeal_RegisterFrame(f, f.unit)
        end

        self:Apply(f)
        shown[#shown + 1] = f
    end

    for i = #units + 1, #self.frames do
        local f = self.frames[i]
        if not InCombatLockdown() then
            f:Hide()
            if f._hpPctOverlay then f._hpPctOverlay:Hide() end
        else
            SoftHide(f)
        end
    end

    self:Layout(shown)
    self:UpdateSelectionHighlights()
end

-- A frame owns an event if it matches either the real unit token or the
-- vehicle token we are currently reading from. Without the second test, a
-- member in a vehicle emits UNIT_HEALTH for "partypet1" while the frame still
-- says "party1", and the bar stops updating entirely.
local function FrameOwnsUnit(f, unit)
    return f.unit == unit or f.displayUnit == unit
end

function Party:OnUnit(unit, event)
    if event == "UNIT_AURA" then
        local FriendlyBuffs = ns.FriendlyBuffs
        local TargetedSpells = ns.TargetedSpells

        for _, f in ipairs(self.frames) do
            if f:IsShown() and FrameOwnsUnit(f, unit) then
                if Dispel and Dispel.Update then Dispel:Update(f, unit) end
                if Debuffs and Debuffs.Update then Debuffs:Update(f, unit) end
                if FriendlyBuffs and FriendlyBuffs.Update then FriendlyBuffs:Update(f, unit) end
                if TargetedSpells and TargetedSpells.UpdateFrame then TargetedSpells:UpdateFrame(f, unit) end
                return
            end
        end
        return
    end

    if event == "UNIT_HEAL_PREDICTION" or event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
        for _, f in ipairs(self.frames) do
            if f:IsShown() and FrameOwnsUnit(f, unit) then
                local cur, mx = GetHealthValues(unit)
                if ns.IncomingHeals and ns.IncomingHeals.Update then ns.IncomingHeals:Update(f, unit, cur, mx) end
                if ns.HealAbsorb   and ns.HealAbsorb.Update   then ns.HealAbsorb:Update(f, unit, cur, mx) end
                if ns.ShieldAbsorb and ns.ShieldAbsorb.Update then ns.ShieldAbsorb:Update(f, unit, cur, mx) end
                return
            end
        end
        return
    end

    -- Health/power churn constantly. Bars + text only - no aura rescans.
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
    or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
        for _, f in ipairs(self.frames) do
            if f:IsShown() and FrameOwnsUnit(f, unit) then
                self:UpdateHealth(f)
                return
            end
        end
        return
    end

    for _, f in ipairs(self.frames) do
        if f:IsShown() and FrameOwnsUnit(f, unit) then
            self:Apply(f)
            return
        end
    end
end

function Party:Init()
    if self.eventFrame then return end

    local ef = CreateFrame("Frame")
    self.eventFrame = ef

    ef:RegisterEvent("GROUP_ROSTER_UPDATE")
    ef:RegisterEvent("PLAYER_ENTERING_WORLD")
    ef:RegisterEvent("PLAYER_ROLES_ASSIGNED")

    ef:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    ef:RegisterEvent("SPELLS_CHANGED")

    ef:RegisterEvent("UNIT_HEALTH")
    ef:RegisterEvent("UNIT_MAXHEALTH")
    ef:RegisterEvent("UNIT_POWER_UPDATE")
    ef:RegisterEvent("UNIT_MAXPOWER")
    ef:RegisterEvent("UNIT_NAME_UPDATE")
    ef:RegisterEvent("UNIT_CONNECTION")
    ef:RegisterEvent("UNIT_PHASE")
    ef:RegisterEvent("UNIT_AURA")

    ef:RegisterEvent("UNIT_HEAL_PREDICTION")
    ef:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    ef:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")

    -- A member entering or leaving a vehicle moves their health to a different
    -- unit token. Without this the frame freezes at the value from the moment
    -- they mounted.
    ef:RegisterEvent("UNIT_ENTERED_VEHICLE")
    ef:RegisterEvent("UNIT_EXITED_VEHICLE")
    ef:RegisterEvent("UNIT_PET")

    ef:RegisterEvent("PLAYER_TARGET_CHANGED")

    ef:SetScript("OnEvent", function(_, event, unit)
        if event == "GROUP_ROSTER_UPDATE"
        or event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_ROLES_ASSIGNED"
        or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "SPELLS_CHANGED"
        or event == "UNIT_ENTERED_VEHICLE"
        or event == "UNIT_EXITED_VEHICLE" then
            if ns.UpdateActiveProfile then ns:UpdateActiveProfile(false) end
            if ns.RequestPartyRebuild then ns:RequestPartyRebuild() else Party:Build() end

        elseif event == "PLAYER_TARGET_CHANGED" then
            Party.selectedUnit = nil
            if UnitExists("target") then
                for _, f in ipairs(Party.frames) do
                    if f and f.unit and UnitExists(f.unit) and UnitIsUnit("target", f.unit) then
                        Party.selectedUnit = f.unit
                        break
                    end
                end
            end
            Party:UpdateSelectionHighlights()

        elseif unit then
            Party:OnUnit(unit, event)
        end
    end)

    if ns.UpdateActiveProfile then ns:UpdateActiveProfile(true) end
    if ns.RequestPartyRebuild then ns:RequestPartyRebuild() else Party:Build() end
end
