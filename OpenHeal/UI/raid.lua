-- ============================================================================
-- raid.lua (OpenHeal)
-- Raid frames (stable unit-token model for secure click-casting).
-- Uses db.lua: ns:GetRaidDB() (role-profile aware).
--
-- IMPORTANT FIX:
--  - Frames are now permanently tied to fixed unit tokens: raid1..raid40
--  - Sorting/layout only changes VISUAL POSITION, never which unit token a frame owns
--  - This keeps OpenHeal secure overlays stable and fixes raid click-healing
--
-- UPDATED:
--  - Real raid respects:
--      * db.orientation
--      * db.columns
--      * db.groupGap
--      * db.spacing
--  - Shared layout engine:
--      * Raid:ComputeLayout(entries)
--  - Sim/settings mode supported:
--      * entries without .unit no longer break layout
--
-- BEHAVIOR:
--  - allowDrag support
--  - mover visibility honors allowDrag + locked + combat
--  - selection, targeted square, incoming heals, dispels, debuffs preserved
--
-- VISUAL:
--  - Name/Role/Group in nameBar above HP
--  - Short names (strip realm + max chars)
--
-- NOTE (12.0 / secret-safety):
--  - No manual comparisons/math on secret health values.
--  - No string ops on secret names.
--  - % text only shown through safe handling.
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns
_G[ADDON] = ns

ns.Raid = ns.Raid or {}
local Raid = ns.Raid

local Dispel  = ns.Dispel
local Debuffs = ns.Debuffs

local POWER_H = 3
local NAME_H  = 14
local NAME_MAX_CHARS = 10
local MAX_RAID_UNITS = 40

-- Shared helpers live in core/util.lua; see the note in party.lua.
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

Raid.frames       = Raid.frames or {}
Raid.framesByUnit = Raid.framesByUnit or {}
Raid.eventFrame   = Raid.eventFrame or nil
Raid.mover        = Raid.mover or nil
Raid.selectedUnit = Raid.selectedUnit or nil

local max      = math.max
local floor    = math.floor
local tinsert  = table.insert
local tsort    = table.sort
local ipairs   = ipairs
local pairs    = pairs
local tostring = tostring
local tonumber = tonumber
local type     = type
local pcall    = pcall

local function GetDB()
    return ns:GetRaidDB()
end

local function IsSafeUnitForHP(unit)
    return U.IsSafeUnit(unit) and true or false
end

-- Raid frames are narrow: strip the realm and cap harder than party does.
local function GetDisplayName(unit, frame)
    return U.GetDisplayName(unit, frame, NAME_MAX_CHARS, true)
end

local function UpdatePowerLayout(btn, showPower)
    btn.hp:ClearAllPoints()
    btn.hp:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -(1 + NAME_H))

    if showPower then
        btn.power:SetHeight(POWER_H)
        btn.power:Show()
        btn.hp:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1 + POWER_H)
    else
        btn.power:Hide()
        btn.hp:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    end
end

local function SetHPColor(frame, r, g, b)
    frame.hp:SetStatusBarColor(r, g, b)
    if frame.hpbg then
        frame.hpbg:SetColorTexture(r * 0.22, g * 0.22, b * 0.22, 0.90)
    end
end

local function SetHealthValue(frame, value)
    if ns.Smoothing then
        ns.Smoothing:SetValue(frame.hp, value)
    else
        SafeSetValue(frame.hp, value)
    end
end

-- See the note in party.lua: classBG swaps which element carries class colour.
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
        SetHPColor(frame, cr, cg, cb)
    else
        SetHPColor(frame, T:Color("health"))
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
    sq:Hide()

    local t = sq:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetColorTexture(1, 0, 0, 1)
    sq.tex = t

    btn._ohTargetedSquare = sq
end

local function UpdateTargetedSquare(frame, unit)
    if not frame or not frame._ohTargetedSquare then return end
    if not unit or not UnitExists(unit) then
        frame._ohTargetedSquare:Hide()
        return
    end

    local ts = ns.TargetedSpells
    local targeted = false

    if ts then
        if type(ts.IsUnitTargeted) == "function" then
            local ok, v = pcall(ts.IsUnitTargeted, ts, unit)
            targeted = ok and v and true or false

        elseif type(ts.IsTargeted) == "function" then
            local ok, v = pcall(ts.IsTargeted, ts, unit)
            targeted = ok and v and true or false

        elseif type(ts.GetUnitTargetedCount) == "function" then
            local ok, v = pcall(ts.GetUnitTargetedCount, ts, unit)
            if ok and v ~= nil then
                if IsSecretValue(v) then
                    targeted = true
                else
                    targeted = (tonumber(v) or 0) > 0
                end
            else
                targeted = false
            end
        end
    end

    if targeted then
        frame._ohTargetedSquare:Show()
        frame._ohTargetedSquare:SetAlpha(1)
    else
        frame._ohTargetedSquare:Hide()
    end
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

local function GetSubgroup(unit)
    if not unit or not UnitExists(unit) then return nil end
    local idx = UnitInRaid(unit)
    if not idx then return nil end
    local _, _, subgroup = GetRaidRosterInfo(idx)
    subgroup = tonumber(subgroup)
    if subgroup and subgroup >= 1 and subgroup <= 8 then
        return subgroup
    end
    return nil
end

local function GetEntrySubgroup(entry)
    if not entry then return 1 end

    local sg = tonumber(entry.subgroup)
    if sg and sg >= 1 and sg <= 8 then
        return sg
    end

    local u = entry.unit
    if u then
        sg = GetSubgroup(u)
        if sg then return sg end
    end

    return 1
end

local function UpdateGroupText(frame, unit, db)
    if not frame.groupText then return end
    if not db.showGroup then
        frame.groupText:SetText("")
        frame.groupText:Hide()
        return
    end

    local sg = GetSubgroup(unit)
    if sg then
        frame.groupText:SetText(("G%d"):format(sg))
        frame.groupText:Show()
    else
        frame.groupText:SetText("")
        frame.groupText:Hide()
    end
end

local function NormalizeOrientation(v)
    v = tostring(v or "VERTICAL"):upper()
    if v ~= "VERTICAL" and v ~= "HORIZONTAL" then
        v = "VERTICAL"
    end
    return v
end

local function NormalizeColumns(v)
    v = tonumber(v) or 8
    v = floor(v + 0.5)
    if v < 1 then v = 1 end
    if v > 8 then v = 8 end
    return v
end

local function GetGroupOrder(groups)
    local order = {}
    for sg in pairs(groups) do
        tinsert(order, sg)
    end
    tsort(order)
    return order
end

-- ----------------------------------------------------------------------------
-- Centre text: health %, or a status word when the unit cannot be healed.
-- ----------------------------------------------------------------------------
local STATUS_COLOR = { r = 0.75, g = 0.75, b = 0.75 }

local function SetStatusText(fs, text)
    SafeSetText(fs, text)
    fs:SetTextColor(STATUS_COLOR.r, STATUS_COLOR.g, STATUS_COLOR.b, 1)
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

-- ----------------------------------------------------------------------------
-- Lightweight health/power refresh - see the note in party.lua. A 20-man pull
-- fires UNIT_HEALTH thousands of times a minute; none of it can change a name,
-- a role or an aura, so none of that work belongs on this path.
-- ----------------------------------------------------------------------------
function Raid:UpdateHealth(frame)
    local u = frame.unit
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

    if ns.IncomingHeals and ns.IncomingHeals.Update then ns.IncomingHeals:Update(frame, u, cur, mx) end
    if ns.HealAbsorb   and ns.HealAbsorb.Update   then ns.HealAbsorb:Update(frame, u, cur, mx) end
    if ns.ShieldAbsorb and ns.ShieldAbsorb.Update then ns.ShieldAbsorb:Update(frame, u, cur, mx) end
end

function Raid:SetSelectedUnit(unit)
    self.selectedUnit = unit
    self:UpdateSelectionHighlights()
end

function Raid:UpdateSelectionHighlights()
    local sel = self.selectedUnit
    for _, f in ipairs(self.frames) do
        if f and f.unit and f._ohSelected then
            local isSel = (sel ~= nil and f.unit == sel)
            f._ohSelected:SetShown(isSel)
            f._ohSelectedBorder:SetShown(isSel)
        end
    end
end

function Raid:HookOverlayClicks(host, overlay)
    if not overlay or overlay._ohRaidHooked then return end
    overlay._ohRaidHooked = true

    overlay:HookScript("OnClick", function(self, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        if not IsShiftKeyDown() then return end

        local unit = self:GetAttribute("unit") or (host and host.unit)
        if unit and unit ~= "" then
            Raid:SetSelectedUnit(unit)
        end
    end)
end

local function CreateMover()
    local m = CreateFrame("Frame", "OpenHealRaidMover", UIParent)
    m:SetSize(180, 18)
    m:SetFrameStrata("DIALOG")
    m:Hide()

    m.bg = m:CreateTexture(nil, "BACKGROUND")
    m.bg:SetAllPoints()
    m.bg:SetColorTexture(0, 0, 0, 0.35)

    m.text = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    m.text:SetPoint("CENTER")
    m.text:SetText("Raid (drag)")

    m:EnableMouse(true)
    m:SetMovable(true)
    m:RegisterForDrag("LeftButton")

    m:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        local db = GetDB()
        if db.allowDrag == false then return end
        self:StartMoving()
    end)

    m:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()

        local db = GetDB()
        local p, _, rp, x, y = self:GetPoint()

        db.point    = p or db.point
        db.relPoint = rp or db.relPoint
        db.x        = floor((tonumber(x) or 0) + 0.5)
        db.y        = floor((tonumber(y) or 0) + 0.5)

        if ns.RequestRaidRebuild then
            ns:RequestRaidRebuild()
        else
            Raid:Build()
        end
    end)

    return m
end

local function ApplyMoverPosition(m)
    local db = GetDB()
    m:ClearAllPoints()
    m:SetPoint(db.point or "CENTER", UIParent, db.relPoint or "CENTER", db.x or 0, db.y or 120)
end

local function CreateUnitButton(stableUnit)
    local btn = CreateFrame("Button", nil, UIParent)
    btn:SetClampedToScreen(true)
    btn:RegisterForClicks("AnyUp", "AnyDown")

    btn.unit = stableUnit
    btn._stableUnit = stableUnit

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0.06, 0.06, 0.06, 0.85)

    btn.btop = btn:CreateTexture(nil, "BORDER"); btn.btop:SetColorTexture(0, 0, 0, 0.85)
    btn.bbot = btn:CreateTexture(nil, "BORDER"); btn.bbot:SetColorTexture(0, 0, 0, 0.85)
    btn.blef = btn:CreateTexture(nil, "BORDER"); btn.blef:SetColorTexture(0, 0, 0, 0.85)
    btn.brig = btn:CreateTexture(nil, "BORDER"); btn.brig:SetColorTexture(0, 0, 0, 0.85)
    btn.btop:SetPoint("TOPLEFT");     btn.btop:SetPoint("TOPRIGHT");     btn.btop:SetHeight(1)
    btn.bbot:SetPoint("BOTTOMLEFT");  btn.bbot:SetPoint("BOTTOMRIGHT");  btn.bbot:SetHeight(1)
    btn.blef:SetPoint("TOPLEFT");     btn.blef:SetPoint("BOTTOMLEFT");   btn.blef:SetWidth(1)
    btn.brig:SetPoint("TOPRIGHT");    btn.brig:SetPoint("BOTTOMRIGHT");  btn.brig:SetWidth(1)

    btn.nameBar = CreateFrame("Frame", nil, btn)
    btn.nameBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    btn.nameBar:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
    btn.nameBar:SetHeight(NAME_H)

    btn.nameBar.bg = btn.nameBar:CreateTexture(nil, "BACKGROUND")
    btn.nameBar.bg:SetAllPoints()
    btn.nameBar.bg:SetColorTexture(T:Color("nameBarBG"))

    btn.nameBar.line = btn.nameBar:CreateTexture(nil, "BORDER")
    btn.nameBar.line:SetPoint("BOTTOMLEFT", btn.nameBar, "BOTTOMLEFT", 0, 0)
    btn.nameBar.line:SetPoint("BOTTOMRIGHT", btn.nameBar, "BOTTOMRIGHT", 0, 0)
    btn.nameBar.line:SetHeight(1)
    btn.nameBar.line:SetColorTexture(0, 0, 0, 0.90)

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

    btn.groupText = btn.nameBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    T:ApplyFont(btn.groupText)
    btn.groupText:SetPoint("LEFT", btn.nameBar, "LEFT", 4, 0)
    btn.groupText:SetJustifyH("LEFT")
    btn.groupText:SetTextColor(1, 1, 1, 0.85)
    btn.groupText:SetText("")
    btn.groupText:Hide()

    btn.roleText = btn.nameBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    T:ApplyFont(btn.roleText)
    btn.roleText:SetPoint("RIGHT", btn.nameBar, "RIGHT", -4, 0)
    btn.roleText:SetJustifyH("RIGHT")
    btn.roleText:SetText("")

    btn.nameText = btn.nameBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    T:ApplyFont(btn.nameText)
    btn.nameText:SetPoint("CENTER", btn.nameBar, "CENTER", 0, 0)
    btn.nameText:SetJustifyH("CENTER")
    btn.nameText:SetText("")

    EnsureSelectedHighlight(btn)

    -- Set the kind before any module attaches: several of them (debuffs,
    -- friendly buffs, raid markers) pick their config block from it.
    btn._ohKind = "RAID"

    btn.OpenHeal_OnOverlayCreated = function(host, overlay)
        Raid:HookOverlayClicks(host, overlay)
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

function Raid:EnsureStableFrames()
    for i = 1, MAX_RAID_UNITS do
        local unit = "raid" .. i
        local f = self.framesByUnit[unit]
        if not f then
            f = CreateUnitButton(unit)
            self.framesByUnit[unit] = f
            self.frames[#self.frames + 1] = f

            if _G.OpenHeal_RegisterFrame then
                _G.OpenHeal_RegisterFrame(f, unit)
            end
        end
    end
end

function Raid:GetUnits()
    local db = GetDB()
    local list = {}

    local maxUnits = tonumber(db.max) or 40
    if maxUnits < 1 then maxUnits = 1 end
    if maxUnits > 40 then maxUnits = 40 end

    -- With dedicated tank frames on, "Keep tanks in Raid Grid" decides whether
    -- tanks also occupy a slot in the main grid or move out of it entirely.
    local excludeTanks = (db.tankFrames == true) and (db.tankAlsoInRaid == false)

    for i = 1, maxUnits do
        local u = "raid" .. i
        if UnitExists(u) and not (excludeTanks and U.IsTank(u)) then
            list[#list + 1] = u
        end
    end

    if db.sort == "ROLE" then
        tsort(list, function(a, b)
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

function Raid:GetLayoutEntriesFromUnits(units)
    local entries = {}
    for _, unit in ipairs(units or {}) do
        local f = self.framesByUnit[unit]
        if f then
            entries[#entries + 1] = {
                frame = f,
                unit = unit,
                subgroup = GetSubgroup(unit) or 1,
            }
        end
    end
    return entries
end

function Raid:ComputeLayout(entries)
    local db = GetDB()

    local orientation = NormalizeOrientation(db.orientation)
    local groupColumns = NormalizeColumns(db.columns)

    local w = tonumber(db.w) or 160
    local h = tonumber(db.h) or 46
    local spacing = tonumber(db.spacing) or 4

    local groupGap = tonumber(db.groupGap)
    if groupGap == nil then
        groupGap = spacing + 10
    end

    local groups = {}
    for _, entry in ipairs(entries or {}) do
        local sg = GetEntrySubgroup(entry)
        groups[sg] = groups[sg] or {}
        tinsert(groups[sg], entry)
    end

    local groupOrder = GetGroupOrder(groups)
    local groupBlocks = {}
    local positions = {}
    local totalW, totalH = 0, 0

    for orderIndex, sg in ipairs(groupOrder) do
        local members = groups[sg]
        local count = #members

        local gCol = ((orderIndex - 1) % groupColumns) + 1
        local gRow = floor((orderIndex - 1) / groupColumns) + 1

        local blockW, blockH
        if orientation == "HORIZONTAL" then
            blockW = max(1, count) * w + max(0, count - 1) * spacing
            blockH = h
        else
            blockW = w
            blockH = max(1, count) * h + max(0, count - 1) * spacing
        end

        groupBlocks[sg] = {
            orderIndex = orderIndex,
            row = gRow,
            col = gCol,
            members = members,
            width = blockW,
            height = blockH,
            x = 0,
            y = 0,
        }
    end

    local rowHeights = {}
    local colWidths = {}

    for _, sg in ipairs(groupOrder) do
        local b = groupBlocks[sg]
        rowHeights[b.row] = max(rowHeights[b.row] or 0, b.height)
        colWidths[b.col] = max(colWidths[b.col] or 0, b.width)
    end

    local rowOffsets = {}
    local colOffsets = {}

    do
        local run = 0
        local maxCol = 0
        for _, sg in ipairs(groupOrder) do
            local c = groupBlocks[sg].col
            if c > maxCol then maxCol = c end
        end
        for c = 1, maxCol do
            colOffsets[c] = run
            run = run + (colWidths[c] or 0) + groupGap
        end
        if maxCol > 0 then
            totalW = run - groupGap
        end
    end

    do
        local run = 0
        local maxRow = 0
        for _, sg in ipairs(groupOrder) do
            local r = groupBlocks[sg].row
            if r > maxRow then maxRow = r end
        end
        for r = 1, maxRow do
            rowOffsets[r] = run
            run = run + (rowHeights[r] or 0) + groupGap
        end
        if maxRow > 0 then
            totalH = run - groupGap
        end
    end

    for _, sg in ipairs(groupOrder) do
        local block = groupBlocks[sg]
        block.x = colOffsets[block.col] or 0
        block.y = rowOffsets[block.row] or 0

        for i, entry in ipairs(block.members) do
            local localX, localY
            if orientation == "HORIZONTAL" then
                localX = (i - 1) * (w + spacing)
                localY = 0
            else
                localX = 0
                localY = (i - 1) * (h + spacing)
            end

            local key = entry.unit or entry

            positions[key] = {
                x = block.x + localX,
                y = block.y + localY,
                width = w,
                height = h,
                subgroup = sg,
            }
        end
    end

    return {
        positions = positions,
        groups = groups,
        groupBlocks = groupBlocks,
        order = groupOrder,
        totalWidth = totalW,
        totalHeight = totalH,
        frameWidth = w,
        frameHeight = h,
        spacing = spacing,
        groupGap = groupGap,
        orientation = orientation,
        columns = groupColumns,
    }
end

function Raid:Apply(frame)
    local db = GetDB()
    local u = frame.unit
    if not u or not UnitExists(u) then return end

    -- Pick up bar texture / font changes on frames that already exist.
    T:ApplyToUnitButton(frame)

    UpdatePowerLayout(frame, db.showPower)

    if frame._ohDebuffs then
        PlaceDebuffs(frame)
    end

    local FriendlyBuffs = ns.FriendlyBuffs
    if FriendlyBuffs and FriendlyBuffs.Place then
        FriendlyBuffs:Place(frame)
    end

    local displayName = GetDisplayName(u, frame)
    SafeSetText(frame.nameText, displayName)

    if db.showRole then
        SafeSetText(frame.roleText, RoleLetter(UnitGroupRolesAssigned(u)))
        frame.roleText:Show()
    else
        SafeSetText(frame.roleText, "")
        frame.roleText:Hide()
    end

    UpdateGroupText(frame, u, db)

    if db.showGroup and frame.groupText and frame.groupText:IsShown() then
        frame.nameText:ClearAllPoints()
        frame.nameText:SetPoint("CENTER", frame.nameBar, "CENTER", 8, 0)
    else
        frame.nameText:ClearAllPoints()
        frame.nameText:SetPoint("CENTER", frame.nameBar, "CENTER", 0, 0)
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

    EnsureTargetedSquare(frame)
    UpdateTargetedSquare(frame, u)

    local TargetedSpells = ns.TargetedSpells
    if TargetedSpells and TargetedSpells.UpdateFrame then
        TargetedSpells:UpdateFrame(frame, u)
    end

    self:UpdateSelectionHighlights()
end

function Raid:Layout(unitsOrEntries)
    local FriendlyBuffs = ns.FriendlyBuffs
    local entries = {}

    if not unitsOrEntries or #unitsOrEntries == 0 then
        entries = {}
    else
        local first = unitsOrEntries[1]
        if type(first) == "string" then
            entries = self:GetLayoutEntriesFromUnits(unitsOrEntries)
        else
            entries = unitsOrEntries
        end
    end

    local layout = self:ComputeLayout(entries)

    for _, entry in ipairs(entries) do
        local f = entry.frame
        if not f and entry.unit then
            f = self.framesByUnit[entry.unit]
        end

        local key = entry.unit or entry
        local pos = layout.positions[key]

        if f and pos then
            f:SetSize(pos.width, pos.height)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", self.mover, "TOPLEFT", pos.x, -pos.y)

            if f._ohDebuffs then PlaceDebuffs(f) end
            if FriendlyBuffs and FriendlyBuffs.Place then FriendlyBuffs:Place(f) end

            EnsureTargetedSquare(f)
            EnsureSelectedHighlight(f)
            UpdateTargetedSquare(f, f.unit)

            if f._hpPctOverlay then
                f._hpPctOverlay:ClearAllPoints()
                f._hpPctOverlay:SetPoint("CENTER", f, "CENTER", 0, 0)
            end
        end
    end

    if self.mover then
        local moverW = max(180, (layout.totalWidth or 0))
        local moverH = max(18,  (layout.totalHeight or 0))
        self.mover:SetSize(moverW, moverH)
    end

    self:UpdateSelectionHighlights()
end

function Raid:HideAllFrames()
    for _, f in ipairs(self.frames) do
        if not InCombatLockdown() then
            f:Hide()
            if f._hpPctOverlay then f._hpPctOverlay:Hide() end
        else
            SoftHide(f)
        end
    end
end

function Raid:Build()
    local db = GetDB()

    if db.allowDrag == nil then db.allowDrag = true end
    if db.enabled == nil then db.enabled = true end
    if db.locked == nil then db.locked = false end
    if not db.point then db.point = "CENTER" end
    if not db.relPoint then db.relPoint = "CENTER" end
    if db.x == nil then db.x = 0 end
    if db.y == nil then db.y = 120 end
    if not db.orientation then db.orientation = "VERTICAL" end
    if not db.sort then db.sort = "NONE" end
    if db.w == nil then db.w = 160 end
    if db.h == nil then db.h = 46 end
    if db.spacing == nil then db.spacing = 4 end
    if db.groupGap == nil then db.groupGap = (tonumber(db.spacing) or 4) + 10 end
    if db.columns == nil then db.columns = 8 end
    if db.max == nil then db.max = 40 end

    db.orientation = NormalizeOrientation(db.orientation)
    db.columns = NormalizeColumns(db.columns)

    self:EnsureStableFrames()

    if not (IsInRaid and IsInRaid()) then
        self:HideAllFrames()
        if self.mover then self.mover:Hide() end
        return
    end

    if not self.mover then
        self.mover = CreateMover()
    end

    ApplyMoverPosition(self.mover)

    local showMover = (db.enabled ~= false) and (db.locked ~= true) and (db.allowDrag ~= false) and (not InCombatLockdown())
    self.mover:SetShown(showMover)

    if not db.enabled then
        self:HideAllFrames()
        return
    end

    local units = self:GetUnits()
    local active = {}

    for _, unit in ipairs(units) do
        active[unit] = true
        local f = self.framesByUnit[unit]
        if f then
            f.unit = f._stableUnit or unit

            if not InCombatLockdown() then
                f:Show()
            end
            SoftShow(f)

            self:Apply(f)
        end
    end

    for unit, f in pairs(self.framesByUnit) do
        if not active[unit] then
            if not InCombatLockdown() then
                f:Hide()
                if f._hpPctOverlay then f._hpPctOverlay:Hide() end
            else
                SoftHide(f)
            end
        end
    end

    self:Layout(units)
end

function Raid:OnUnit(unit, event)
    if not unit then return end

    local f = self.framesByUnit[unit]
    if not f then return end
    if not UnitExists(unit) then return end

    if event == "UNIT_AURA" then
        local FriendlyBuffs = ns.FriendlyBuffs
        local TargetedSpells = ns.TargetedSpells

        if Dispel and Dispel.Update then Dispel:Update(f, unit) end
        if Debuffs and Debuffs.Update then Debuffs:Update(f, unit) end
        if FriendlyBuffs and FriendlyBuffs.Update then FriendlyBuffs:Update(f, unit) end

        EnsureTargetedSquare(f)
        UpdateTargetedSquare(f, unit)

        if TargetedSpells and TargetedSpells.UpdateFrame then
            TargetedSpells:UpdateFrame(f, unit)
        end

        self:UpdateSelectionHighlights()
        return
    end

    if event == "UNIT_HEAL_PREDICTION" or event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
        local cur, mx = GetHealthValues(unit)
        if ns.IncomingHeals and ns.IncomingHeals.Update then ns.IncomingHeals:Update(f, unit, cur, mx) end
        if ns.HealAbsorb   and ns.HealAbsorb.Update   then ns.HealAbsorb:Update(f, unit, cur, mx) end
        if ns.ShieldAbsorb and ns.ShieldAbsorb.Update then ns.ShieldAbsorb:Update(f, unit, cur, mx) end
        self:UpdateSelectionHighlights()
        return
    end

    -- Health/power churn constantly. Bars + text only - no aura rescans.
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
    or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
        self:UpdateHealth(f)
        return
    end

    self:Apply(f)
end

function Raid:Init()
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

    ef:RegisterEvent("PLAYER_TARGET_CHANGED")

    ef:SetScript("OnEvent", function(_, event, unit)
        if event == "GROUP_ROSTER_UPDATE"
        or event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_ROLES_ASSIGNED"
        or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "SPELLS_CHANGED" then
            if ns.UpdateActiveProfile then ns:UpdateActiveProfile(false) end
            if ns.RequestRaidRebuild then
                ns:RequestRaidRebuild()
            else
                Raid:Build()
            end

        elseif event == "PLAYER_TARGET_CHANGED" then
            Raid.selectedUnit = nil
            if UnitExists("target") then
                for _, f in ipairs(Raid.frames) do
                    if f and f.unit and UnitExists(f.unit) and UnitIsUnit("target", f.unit) then
                        Raid.selectedUnit = f.unit
                        break
                    end
                end
            end
            Raid:UpdateSelectionHighlights()

        elseif unit and tostring(unit):match("^raid%d+$") then
            Raid:OnUnit(unit, event)
        end
    end)

    if ns.UpdateActiveProfile then ns:UpdateActiveProfile(true) end
    if ns.RequestRaidRebuild then
        ns:RequestRaidRebuild()
    else
        Raid:Build()
    end
end
