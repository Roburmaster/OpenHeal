-- ============================================================================
-- bindview_core.lua (OpenHeal)
-- Focus/BindView: 5-slot secure click-cast panel (Midnight-safe)
--
-- 1:1 Party button style + same attachments:
--  - Dispel, Debuffs, FriendlyBuffs, TargetedSpells
--  - IncomingHeals, HealAbsorb, ShieldAbsorb
--  - Optional ClickCastingFrame registration
--  - Optional OpenHeal_RegisterFrame(unit) integration
--
-- Select/Remove:
--  - Shift+Q (keybinding) calls BV:SelectOrRemove()
--  - OOC only (secure unit changes forbidden in combat)
--
-- Layout:
--  - mover + saved position
--  - orientation: VERTICAL / HORIZONTAL
--
-- RANGE + FADING:
--  - Uses SAME system as the rest of addon: ns.Range:Apply(frame, unit, dt)
--    (range.lua uses C_Spell.IsSpellInRange + latch + smoothing, no secret bool)
--  - BindView runs its own small OnUpdate accumulator to call Range:Apply
--
-- MIDNIGHT / 12.0 SECRET SAFETY:
--  - NEVER compare strings from WoW API (no s == "", no guid == guid, etc.)
--  - NEVER use ":" string methods on values from WoW API (no name:match, etc.)
--  - Use pcall(string.len/match/sub) and compare NUMBERS only.
--
-- COMBAT LOCKDOWN SAFETY (IMPORTANT):
--  - Never call EnableMouse/Show/Hide/SetAttribute(unit) in combat on secure buttons.
--  - Build is deferred while in combat (RequestBuild + pending flags).
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns or {}
_G[ADDON] = ns

ns.BindView = ns.BindView or {}
local BV = ns.BindView

-- Modules (same as party.lua)
local Dispel         = ns.Dispel
local Debuffs        = ns.Debuffs
local FriendlyBuffs  = ns.FriendlyBuffs
local TargetedSpells = ns.TargetedSpells
local Range          = ns.Range

local TEX     = "Interface\\Buttons\\WHITE8X8"
local POWER_H = 3

local CreateFrame        = CreateFrame
local InCombatLockdown   = InCombatLockdown
local UnitExists         = UnitExists
local UnitGUID           = UnitGUID
local UnitName           = UnitName
local UnitClass          = UnitClass
local UnitHealth         = UnitHealth
local UnitHealthMax      = UnitHealthMax
local UnitPower          = UnitPower
local UnitPowerMax       = UnitPowerMax
local IsInRaid           = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local GetMouseFoci       = GetMouseFoci
local GetTime            = GetTime

-- -----------------------------------------------------------------------------
-- DB (fallback until you wire into db.lua properly)
-- -----------------------------------------------------------------------------
local DEFAULT_DB = {
    enabled = true,
    locked = false,
    showMover = true,

    point = "CENTER",
    relPoint = "CENTER",
    x = -420,
    y = 40,

    w = 180,
    h = 30,
    spacing = 6,
    orientation = "VERTICAL", -- or "HORIZONTAL"

    showPower = false,
    classColor = true,
}

local function DeepCopyDefaults(dst, src)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = DeepCopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

local function GetDB()
    if ns.GetBindViewDB then
        return ns:GetBindViewDB()
    end

    _G.OpenHealDB = _G.OpenHealDB or {}
    _G.OpenHealDB.bindview = _G.OpenHealDB.bindview or {}
    _G.OpenHealDB.bindview = DeepCopyDefaults(_G.OpenHealDB.bindview, DEFAULT_DB)
    return _G.OpenHealDB.bindview
end

-- -----------------------------------------------------------------------------
-- Range DB comes from range.lua system
-- -----------------------------------------------------------------------------
local function GetRangeDB()
    return (ns.GetRangeDB and ns:GetRangeDB()) or nil
end

-- -----------------------------------------------------------------------------
-- Click-casting registration (Blizzard system)
-- -----------------------------------------------------------------------------
local function IsClickableCastingAvailable()
    return _G.ClickCastingFrame and type(_G.ClickCastingFrame) == "table"
end

local function RegisterForClickCasting(frame)
    if IsClickableCastingAvailable() and _G.ClickCastingFrame.RegisterFrame then
        pcall(_G.ClickCastingFrame.RegisterFrame, _G.ClickCastingFrame, frame)
    end
end

-- -----------------------------------------------------------------------------
-- Safe helpers (Midnight-safe)
-- -----------------------------------------------------------------------------
local function SafeCall(fn, ...)
    local ok, a,b,c,d,e,f,g,h,i,j = pcall(fn, ...)
    if not ok then return nil end
    return a,b,c,d,e,f,g,h,i,j
end

local function SafeNum(fn, ...)
    local v = SafeCall(fn, ...)
    v = tonumber(v)
    return v
end

local function StrLen(v)
    local okT, s = pcall(tostring, v)
    if not okT then return 0, "" end
    local okL, ln = pcall(string.len, s)
    if not okL or not ln then return 0, s end
    return ln, s
end

local function SafeSetMinMax(bar, mn, mx)
    if not bar then return end
    if mx == nil then mx = 1 end
    if mn == nil then mn = 0 end
    local ok = pcall(bar.SetMinMaxValues, bar, mn, mx)
    if not ok then
        pcall(bar.SetMinMaxValues, bar, 0, 1)
    end
end

local function SafeSetValue(bar, v)
    if not bar then return end
    if v == nil then v = 0 end
    local ok = pcall(bar.SetValue, bar, v)
    if not ok then
        pcall(bar.SetValue, bar, 0)
    end
end

-- -----------------------------------------------------------------------------
-- State
-- -----------------------------------------------------------------------------
BV.NUM_SLOTS = 5

BV.frames     = BV.frames or {}
BV.mover      = BV.mover or nil
BV.eventFrame = BV.eventFrame or nil

BV.slotData           = BV.slotData or {}
BV._rosterGuidToToken = BV._rosterGuidToToken or {}

BV.simulation  = BV.simulation or false
BV._hintNext   = BV._hintNext or 0

-- Range OnUpdate accumulator
BV._rangeAcc   = BV._rangeAcc or 0

-- Combat-safe build deferral
BV._pendingBuild   = BV._pendingBuild or false
BV._pendingDisable = BV._pendingDisable or false

-- -----------------------------------------------------------------------------
-- Helpers (party-like)  (MIDNIGHT SAFE: no string compares on API strings)
-- -----------------------------------------------------------------------------
local function ShortName(name, maxChars)
    local ln, s = StrLen(name)
    if ln <= 0 then return "" end

    local base = s
    local okM, m = pcall(string.match, s, "^([^%-]+)")
    if okM and m then
        local lnM = select(1, StrLen(m))
        if lnM > 0 then
            base = m
        end
    end

    if not maxChars or maxChars <= 0 then
        return base
    end

    local lnB = select(1, StrLen(base))
    if lnB > maxChars then
        local okSub, cut = pcall(string.sub, base, 1, maxChars)
        if okSub and cut then
            return cut
        end
    end

    return base
end

local function NameMaxCharsFromWidth(w)
    local ww = tonumber(w) or 180
    local maxChars = math.floor((ww - 50) / 7)
    if maxChars < 4 then maxChars = 4 end
    if maxChars > 16 then maxChars = 16 end
    return maxChars
end

-- IMPORTANT:
-- SecureUnitButtonTemplate + combat lockdown:
-- Never call EnableMouse in combat. Only OOC.
--
-- The shared versions in core/util.lua carry exactly that guard - it was
-- adopted from this file, because this was the only one of the four copies
-- that had it right.
local SoftHide = ns.UnitUtil.SoftHide
local SoftShow = ns.UnitUtil.SoftShow

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

local function ApplyMoverPosition(m)
    local db = GetDB()
    m:ClearAllPoints()
    m:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
end

-- -----------------------------------------------------------------------------
-- Robust hover detection (child frames -> parent button)
-- -----------------------------------------------------------------------------
local function GetHoveredSlotIndex()
    local function climbToIndex(f)
        local guard = 0
        while f and guard < 30 do
            if f._bvIndex and type(f._bvIndex) == "number" then
                return f._bvIndex
            end
            f = f.GetParent and f:GetParent() or nil
            guard = guard + 1
        end
        return nil
    end

    if GetMouseFoci then
        local foci = GetMouseFoci()
        if foci then
            for i = 1, #foci do
                local idx = climbToIndex(foci[i])
                if idx then return idx end
            end
        end
    end

    if _G.GetMouseFocus then
        local f = _G.GetMouseFocus()
        local idx = climbToIndex(f)
        if idx then return idx end
    end

    return nil
end

-- -----------------------------------------------------------------------------
-- Range apply using addon-wide system (range.lua)
-- -----------------------------------------------------------------------------
function BV:ApplyRange(frame, unit, dt)
    if not frame then return end
    if self.simulation then
        frame:SetAlpha(1)
        return
    end
    if Range and Range.Apply and unit then
        Range:Apply(frame, unit, dt)
        return
    end
end

function BV:UpdateRanges(dt)
    if self.simulation then
        for i = 1, self.NUM_SLOTS do
            local f = self.frames[i]
            if f and f.IsShown and f:IsShown() then
                f:SetAlpha(1)
            end
        end
        return
    end

    for i = 1, self.NUM_SLOTS do
        local f = self.frames[i]
        if f and f.IsShown and f:IsShown() and f.unit then
            self:ApplyRange(f, f.unit, dt)
        end
    end
end

function BV:RangeOnUpdate(dt)
    local db = GetDB()
    if not db.enabled then return end

    local rdb = GetRangeDB()
    local update = (rdb and rdb.update) or 0.20

    self._rangeAcc = (self._rangeAcc or 0) + (dt or 0)
    if self._rangeAcc < update then return end
    self._rangeAcc = 0

    self:UpdateRanges(update)
end

-- -----------------------------------------------------------------------------
-- Hint: show what Shift+Q will do
-- -----------------------------------------------------------------------------
function BV:UpdateHint(force)
    if not self.mover or not self.mover.hint then return end

    local t = GetTime and GetTime() or 0
    if not force and t < (self._hintNext or 0) then return end
    self._hintNext = t + 0.05

    if InCombatLockdown() then
        self.mover.hint:SetText("Shift+Q: (combat) locked")
        return
    end

    local idx = GetHoveredSlotIndex()
    if idx then
        local d = self.slotData[idx]
        local db = GetDB()
        local maxChars = NameMaxCharsFromWidth(db.w)
        local nm = (d and d.name) and ShortName(d.name, maxChars) or "Empty"
        self.mover.hint:SetText(("Shift+Q: Remove slot %d (%s)"):format(idx, nm))
        return
    end

    if UnitExists("mouseover") then
        local db = GetDB()
        local maxChars = NameMaxCharsFromWidth(db.w)
        local nm = UnitName("mouseover")
        nm = (nm and ShortName(nm, maxChars)) or "Unknown"
        self.mover.hint:SetText("Shift+Q: Add " .. nm)
        return
    end

    self.mover.hint:SetText("Shift+Q: add/remove (OOC)")
end

-- -----------------------------------------------------------------------------
-- Roster mapping: GUID -> unit token (raidX/partyX/player)
-- -----------------------------------------------------------------------------
function BV:RebuildRosterMap()
    wipe(self._rosterGuidToToken)

    if UnitExists("player") then
        local g = UnitGUID("player")
        if g then self._rosterGuidToToken[g] = "player" end
    end

    if IsInRaid() then
        local n = GetNumGroupMembers() or 0
        for i = 1, n do
            local unit = "raid" .. i
            if UnitExists(unit) then
                local g = UnitGUID(unit)
                if g then self._rosterGuidToToken[g] = unit end
            end
        end
    else
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local g = UnitGUID(unit)
                if g then self._rosterGuidToToken[g] = unit end
            end
        end
    end
end

function BV:ResolveSlotTokens_OOC()
    if InCombatLockdown() then return end
    if self.simulation then return end

    self:RebuildRosterMap()

    for i = 1, self.NUM_SLOTS do
        local data = self.slotData[i]
        local btn = self.frames[i]
        if btn then
            local token = (data and data.guid) and self._rosterGuidToToken[data.guid] or nil
            if data then data.token = token end

            if token then
                btn:SetAttribute("unit", token)
                btn.unit = token

                if _G.OpenHeal_RegisterFrame then
                    _G.OpenHeal_RegisterFrame(btn, token)
                end
            else
                btn:SetAttribute("unit", nil)
                btn.unit = nil
            end
        end
    end
end

-- -----------------------------------------------------------------------------
-- UI: mover
-- -----------------------------------------------------------------------------
local function CreateMover()
    local m = CreateFrame("Frame", "OpenHealBindViewMover", UIParent)
    m:SetSize(180, 18)
    m:SetFrameStrata("DIALOG")
    m:Hide()

    m.bg = m:CreateTexture(nil, "BACKGROUND")
    m.bg:SetAllPoints()
    m.bg:SetColorTexture(0, 0, 0, 0.35)

    m.text = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    m.text:SetPoint("CENTER")
    m.text:SetText("BindView (drag)")

    m.hint = m:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    m.hint:SetPoint("TOP", m, "BOTTOM", 0, -2)
    m.hint:SetJustifyH("CENTER")
    m.hint:SetText("Shift+Q: add/remove (OOC)")

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
        db.x        = math.floor((x or 0) + 0.5)
        db.y        = math.floor((y or 0) + 0.5)

        BV:RequestBuild()
    end)

    return m
end

-- -----------------------------------------------------------------------------
-- UI: create secure unit button (party.lua-like visuals + same attachments)
-- -----------------------------------------------------------------------------
local function CreateUnitButton(i)
    local btn = CreateFrame("Button", "OpenHealBindViewSlot" .. i, UIParent, "SecureUnitButtonTemplate")
    btn:SetClampedToScreen(true)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn._bvIndex = i

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0.06, 0.06, 0.06, 0.85)

    btn.btop = btn:CreateTexture(nil, "BORDER"); btn.btop:SetColorTexture(0,0,0,0.85)
    btn.bbot = btn:CreateTexture(nil, "BORDER"); btn.bbot:SetColorTexture(0,0,0,0.85)
    btn.blef = btn:CreateTexture(nil, "BORDER"); btn.blef:SetColorTexture(0,0,0,0.85)
    btn.brig = btn:CreateTexture(nil, "BORDER"); btn.brig:SetColorTexture(0,0,0,0.85)
    btn.btop:SetPoint("TOPLEFT");     btn.btop:SetPoint("TOPRIGHT");     btn.btop:SetHeight(1)
    btn.bbot:SetPoint("BOTTOMLEFT");  btn.bbot:SetPoint("BOTTOMRIGHT");  btn.bbot:SetHeight(1)
    btn.blef:SetPoint("TOPLEFT");     btn.blef:SetPoint("BOTTOMLEFT");   btn.blef:SetWidth(1)
    btn.brig:SetPoint("TOPRIGHT");    btn.brig:SetPoint("BOTTOMRIGHT");  btn.brig:SetWidth(1)

    btn:SetAttribute("type1", "target")
    btn:SetAttribute("type2", "togglemenu")

    btn.power = CreateFrame("StatusBar", nil, btn)
    btn.power:SetPoint("BOTTOMLEFT", 1, 1)
    btn.power:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.power:SetHeight(POWER_H)
    btn.power:SetStatusBarTexture(TEX)
    btn.power:SetStatusBarColor(0.12, 0.42, 1.0)
    SafeSetMinMax(btn.power, 0, 1)
    SafeSetValue(btn.power, 1)
    btn.power:Hide()

    btn.hp = CreateFrame("StatusBar", nil, btn)
    btn.hp:SetStatusBarTexture(TEX)
    SafeSetMinMax(btn.hp, 0, 1)
    SafeSetValue(btn.hp, 1)

    btn.hpbg = btn.hp:CreateTexture(nil, "BACKGROUND")
    btn.hpbg:SetAllPoints()
    btn.hpbg:SetColorTexture(0.02, 0.02, 0.02, 0.90)

    btn.nameText = btn.hp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.nameText:SetTextColor(1, 1, 1, 1)
    btn.nameText:SetPoint("TOPLEFT", btn.hp, "TOPLEFT", 4, -2)
    btn.nameText:SetJustifyH("LEFT")
    btn.nameText:SetText("")

    btn.roleText = btn.hp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.roleText:SetPoint("TOPRIGHT", btn.hp, "TOPRIGHT", -4, -2)
    btn.roleText:SetJustifyH("RIGHT")
    btn.roleText:SetText("")
    btn.roleText:Hide()

    local hi = btn:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints(btn)
    hi:SetColorTexture(1, 1, 1, 0.07)

    btn._ohKind = "BINDVIEW"

    if Dispel and Dispel.Attach then Dispel:Attach(btn) end

    if Debuffs and Debuffs.Attach then
        Debuffs:Attach(btn)
        PlaceDebuffs(btn)
    end

    if ns.IncomingHeals and ns.IncomingHeals.Attach then ns.IncomingHeals:Attach(btn) end
    if ns.HealAbsorb   and ns.HealAbsorb.Attach   then ns.HealAbsorb:Attach(btn) end
    if ns.ShieldAbsorb and ns.ShieldAbsorb.Attach then ns.ShieldAbsorb:Attach(btn) end

    if FriendlyBuffs and FriendlyBuffs.Attach then
        FriendlyBuffs:Attach(btn)
        if FriendlyBuffs.Place then FriendlyBuffs:Place(btn) end
    end

    EnsureTargetedSquare(btn)

    if TargetedSpells and TargetedSpells.Attach then
        TargetedSpells:Attach(btn)
    end

    RegisterForClickCasting(btn)

    return btn
end

-- -----------------------------------------------------------------------------
-- Layout
-- -----------------------------------------------------------------------------
function BV:Layout()
    local db = GetDB()
    if not self.mover then return end

    for i = 1, self.NUM_SLOTS do
        local f = self.frames[i]
        if f then
            f:SetSize(db.w, db.h)
            f:ClearAllPoints()

            if i == 1 then
                f:SetPoint("TOPLEFT", self.mover, "TOPLEFT", 0, 0)
            else
                local prev = self.frames[i - 1]
                if db.orientation == "HORIZONTAL" then
                    f:SetPoint("LEFT", prev, "RIGHT", db.spacing, 0)
                else
                    f:SetPoint("TOP", prev, "BOTTOM", 0, -db.spacing)
                end
            end

            UpdatePowerLayout(f, db.showPower)

            if f._ohDebuffs then PlaceDebuffs(f) end
            if FriendlyBuffs and FriendlyBuffs.Place then FriendlyBuffs:Place(f) end
            EnsureTargetedSquare(f)
        end
    end
end

-- -----------------------------------------------------------------------------
-- Apply visuals + module updates (Midnight-safe)
-- -----------------------------------------------------------------------------
function BV:Apply(btn)
    local db = GetDB()
    UpdatePowerLayout(btn, db.showPower)

    local maxChars = NameMaxCharsFromWidth(db.w)
    local u = btn.unit
    local data = self.slotData[btn._bvIndex]

    if self.simulation then
        local nm = (data and data.simName) or ("SimHealer" .. btn._bvIndex)
        btn.nameText:SetText(ShortName(nm, maxChars))

        local cur = (data and tonumber(data.simHP)) or 0
        local mx  = (data and tonumber(data.simHPMax)) or 1
        SafeSetMinMax(btn.hp, 0, mx)
        SafeSetValue(btn.hp, cur)
        btn.hp:SetStatusBarColor(0.2, 0.8, 0.2, 1)

        if db.showPower then
            local p  = (data and tonumber(data.simP)) or 0
            local pm = (data and tonumber(data.simPM)) or 1
            SafeSetMinMax(btn.power, 0, pm)
            SafeSetValue(btn.power, p)
        end

        btn:SetAlpha(1)
        return
    end

    if not u or not UnitExists(u) then
        local nm = (data and data.name) and (ShortName(data.name, maxChars) .. " (missing)") or "Empty"
        btn.nameText:SetText(nm)

        SafeSetMinMax(btn.hp, 0, 1)
        SafeSetValue(btn.hp, 0)
        btn.hp:SetStatusBarColor(0.25, 0.25, 0.25, 1)

        if db.showPower then
            SafeSetMinMax(btn.power, 0, 1)
            SafeSetValue(btn.power, 0)
        end

        if btn._ohTargetedSquare then btn._ohTargetedSquare:Hide() end
        return
    end

    -- Name
    local name = UnitName(u)
    btn.nameText:SetText(ShortName(name, maxChars))

    -- HP
    local cur = SafeNum(UnitHealth, u) or 0
    local mx  = SafeNum(UnitHealthMax, u) or 1
    SafeSetMinMax(btn.hp, 0, mx)
    SafeSetValue(btn.hp, cur)

    -- Class color
    if db.classColor then
        local _, class = UnitClass(u)
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then
            btn.hp:SetStatusBarColor(c.r, c.g, c.b, 1)
        else
            btn.hp:SetStatusBarColor(0.2, 0.8, 0.2, 1)
        end
    else
        btn.hp:SetStatusBarColor(0.2, 0.8, 0.2, 1)
    end

    -- Power
    if db.showPower then
        local p  = SafeNum(UnitPower, u) or 0
        local pm = SafeNum(UnitPowerMax, u) or 1
        SafeSetMinMax(btn.power, 0, pm)
        SafeSetValue(btn.power, p)
    end

    -- Module updates
    if Dispel and Dispel.Update then Dispel:Update(btn, u) end
    if Debuffs and Debuffs.Update then Debuffs:Update(btn, u) end

    if ns.IncomingHeals and ns.IncomingHeals.Update then ns.IncomingHeals:Update(btn, u, cur, mx) end
    if ns.HealAbsorb   and ns.HealAbsorb.Update   then ns.HealAbsorb:Update(btn, u, cur, mx) end
    if ns.ShieldAbsorb and ns.ShieldAbsorb.Update then ns.ShieldAbsorb:Update(btn, u, cur, mx) end

    if FriendlyBuffs and FriendlyBuffs.Update then FriendlyBuffs:Update(btn, u) end

    if TargetedSpells and TargetedSpells.UpdateFrame then
        TargetedSpells:UpdateFrame(btn, u)
    end
end

function BV:UpdateAll()
    for i = 1, self.NUM_SLOTS do
        local f = self.frames[i]
        if f and f:IsShown() then
            self:Apply(f)
        end
    end
    self:UpdateHint(false)
end

-- -----------------------------------------------------------------------------
-- Build deferral (combat-safe)
-- -----------------------------------------------------------------------------
function BV:RequestBuild()
    if InCombatLockdown() then
        self._pendingBuild = true
        return
    end
    self._pendingBuild = false
    self:Build()
end

-- -----------------------------------------------------------------------------
-- Build (OOC only; never called directly from events during combat)
-- -----------------------------------------------------------------------------
function BV:Build()
    if InCombatLockdown() then
        self._pendingBuild = true
        return
    end

    local db = GetDB()

    if not self.mover then
        self.mover = CreateMover()
    end
    ApplyMoverPosition(self.mover)

    for i = 1, self.NUM_SLOTS do
        if not self.frames[i] then
            self.frames[i] = CreateUnitButton(i)
            self.slotData[i] = self.slotData[i] or {}
        end
    end

    local showMover = (db.showMover ~= false) and (not db.locked) and true
    self.mover:SetShown(showMover)

    -- If disabled: do real hide/disable OOC only
    if not db.enabled then
        self._pendingDisable = false
        for i = 1, self.NUM_SLOTS do
            local f = self.frames[i]
            if f then
                f:Hide()
                f:EnableMouse(false)
            end
        end
        self:UpdateHint(true)
        return
    end

    -- Enabled: show + enable mouse OOC
    for i = 1, self.NUM_SLOTS do
        local f = self.frames[i]
        if f then
            f:Show()
            SoftShow(f) -- OOC safe: enables mouse here
        end
    end

    self:Layout()

    self:ResolveSlotTokens_OOC()

    self:UpdateAll()
    self:UpdateHint(true)

    -- Force one range pass immediately (no blink)
    self:UpdateRanges((GetRangeDB() and GetRangeDB().update) or 0.20)
end

-- -----------------------------------------------------------------------------
-- Select / Remove (keybind)
-- -----------------------------------------------------------------------------
function BV:FindFirstEmptySlot()
    for i = 1, self.NUM_SLOTS do
        local d = self.slotData[i]
        if not d or not d.guid then
            return i
        end
    end
    return nil
end

function BV:ClearSlot(i)
    local d = self.slotData[i]
    if d then wipe(d) end

    local btn = self.frames[i]
    if btn and not InCombatLockdown() then
        btn:SetAttribute("unit", nil)
        btn.unit = nil
    end
end

function BV:AddGUIDToSlot(i, guid, name, class)
    local d = self.slotData[i]
    if not d then return end
    wipe(d)

    -- Store a sanitized display name (avoid keeping raw API secret-string around)
    local db = GetDB()
    local maxChars = NameMaxCharsFromWidth(db.w)
    local safeName = ShortName(name, maxChars)
    if select(1, StrLen(safeName)) <= 0 then
        safeName = "Unknown"
    end

    d.guid  = guid
    d.name  = safeName
    d.class = class

    self:ResolveSlotTokens_OOC()
end

function BV:SelectOrRemove()
    local db = GetDB()
    if not db.enabled then return end

    if InCombatLockdown() then
        UIErrorsFrame:AddMessage("BindView: Cannot change slots in combat.", 1, 0.2, 0.2)
        return
    end

    local idx = GetHoveredSlotIndex()
    if idx then
        self:ClearSlot(idx)
        self:ResolveSlotTokens_OOC()
        self:UpdateAll()
        self:UpdateHint(true)
        return
    end

    if not UnitExists("mouseover") then
        UIErrorsFrame:AddMessage("BindView: Mouseover a raid/party unit frame to add.", 1, 1, 0.2)
        self:UpdateHint(true)
        return
    end

    local guid = UnitGUID("mouseover")
    if not guid then
        UIErrorsFrame:AddMessage("BindView: No GUID on mouseover.", 1, 1, 0.2)
        self:UpdateHint(true)
        return
    end

    -- NOTE: DO NOT compare guid strings (secret string rules). We avoid "already added" check here.

    local name = UnitName("mouseover")
    local _, class = UnitClass("mouseover")

    local slotIndex = self:FindFirstEmptySlot()
    if not slotIndex then
        UIErrorsFrame:AddMessage("BindView: No empty slots.", 1, 0.6, 0.2)
        self:UpdateHint(true)
        return
    end

    self:AddGUIDToSlot(slotIndex, guid, name, class)
    self:UpdateAll()
    self:UpdateHint(true)

    -- Re-run range right away after changing slots
    self:UpdateRanges((GetRangeDB() and GetRangeDB().update) or 0.20)
end

-- -----------------------------------------------------------------------------
-- Simulation
-- -----------------------------------------------------------------------------
function BV:SetSimulation(on)
    on = not not on
    self.simulation = on

    if on then
        for i = 1, self.NUM_SLOTS do
            local d = self.slotData[i]
            wipe(d)
            d.simName  = ("SimHealer%d"):format(i)
            d.simHPMax = 100000
            d.simHP    = 100000 - (i * 9000)
            d.simPM    = 100
            d.simP     = 100 - (i * 10)

            local btn = self.frames[i]
            if btn and not InCombatLockdown() then
                btn:SetAttribute("unit", nil)
                btn.unit = nil
            end
        end
        UIErrorsFrame:AddMessage("BindView: Simulation ON", 0.2, 1, 0.2)
    else
        for i = 1, self.NUM_SLOTS do
            local d = self.slotData[i]
            if d then
                d.simName, d.simHP, d.simHPMax, d.simP, d.simPM = nil, nil, nil, nil, nil
            end
        end
        UIErrorsFrame:AddMessage("BindView: Simulation OFF", 0.2, 1, 0.2)
        self:ResolveSlotTokens_OOC()
    end

    self:UpdateAll()
    self:UpdateHint(true)
    self:UpdateRanges((GetRangeDB() and GetRangeDB().update) or 0.20)
end

-- -----------------------------------------------------------------------------
-- Events (party-like update strategy)
-- -----------------------------------------------------------------------------
function BV:OnUnit(unit, event)
    if not unit then return end

    if event == "UNIT_AURA" then
        for i = 1, self.NUM_SLOTS do
            local f = self.frames[i]
            if f and f.unit == unit and f:IsShown() then
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
        for i = 1, self.NUM_SLOTS do
            local f = self.frames[i]
            if f and f.unit == unit and f:IsShown() then
                local cur = SafeNum(UnitHealth, unit) or 0
                local mx  = SafeNum(UnitHealthMax, unit) or 1
                if ns.IncomingHeals and ns.IncomingHeals.Update then ns.IncomingHeals:Update(f, unit, cur, mx) end
                if ns.HealAbsorb   and ns.HealAbsorb.Update   then ns.HealAbsorb:Update(f, unit, cur, mx) end
                if ns.ShieldAbsorb and ns.ShieldAbsorb.Update then ns.ShieldAbsorb:Update(f, unit, cur, mx) end
                return
            end
        end
        return
    end

    for i = 1, self.NUM_SLOTS do
        local f = self.frames[i]
        if f and f.unit == unit and f:IsShown() then
            self:Apply(f)
            return
        end
    end
end

function BV:Init()
    if self.eventFrame then return end

    local ef = CreateFrame("Frame")
    self.eventFrame = ef

    ef:RegisterEvent("PLAYER_ENTERING_WORLD")
    ef:RegisterEvent("GROUP_ROSTER_UPDATE")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")

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

    ef:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
            BV:RequestBuild()
            return
        end

        if event == "PLAYER_REGEN_ENABLED" then
            -- Apply any deferred build/disable safely OOC
            if BV._pendingBuild or BV._pendingDisable then
                BV._pendingBuild = false
                BV._pendingDisable = false
                BV:Build()
                return
            end

            BV:ResolveSlotTokens_OOC()
            BV:UpdateAll()
            BV:UpdateHint(true)
            BV:UpdateRanges((GetRangeDB() and GetRangeDB().update) or 0.20)
            return
        end

        if unit then
            BV:OnUnit(unit, event)
        end
    end)

    -- IMPORTANT: range has no events; use OnUpdate accumulator like range.lua
    ef:SetScript("OnUpdate", function(_, dt)
        BV:RangeOnUpdate(dt)
    end)

    BV:RequestBuild()
    BV:UpdateHint(true)
    BV:UpdateRanges((GetRangeDB() and GetRangeDB().update) or 0.20)

    -- ------------------------------------------------------------------
    -- Slash command.
    --
    -- This used to accept only "sim" and "rebuild" and print a usage line for
    -- everything else - including the bare command, which is what anyone
    -- actually types. Bare /ohbindview now opens the settings tab that
    -- configures this panel; the debug subcommands still work.
    -- ------------------------------------------------------------------
    SLASH_OPENHEAL_BINDVIEW1 = "/ohbindview"
    SLASH_OPENHEAL_BINDVIEW2 = "/ohfocus"
    SlashCmdList.OPENHEAL_BINDVIEW = function(msg)
        msg = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

        if msg == "" then
            -- Multi Focus tab in the unified settings.
            if ns.Settings and ns.Settings.Open then
                ns.Settings:Open(5)
            else
                print("|cff33ff99OpenHeal|r settings not loaded; try /ohsettings")
            end
            return
        end

        if msg == "sim" or msg == "simulation" then
            BV:SetSimulation(not BV.simulation)
            return
        end

        if msg == "rebuild" then
            BV:RequestBuild()
            return
        end

        if msg == "show" or msg == "hide" or msg == "toggle" then
            if InCombatLockdown() then
                print("|cff33ff99OpenHeal|r cannot change the focus panel in combat.")
                return
            end

            local db = GetDB()
            if msg == "show" then
                db.enabled = true
            elseif msg == "hide" then
                db.enabled = false
            else
                db.enabled = not db.enabled
            end

            BV:RequestBuild()
            print("|cff33ff99OpenHeal|r focus panel " .. (db.enabled and "shown" or "hidden"))
            return
        end

        print("|cff33ff99OpenHeal|r /ohbindview - open settings | show | hide | toggle | sim | rebuild")
    end
end
