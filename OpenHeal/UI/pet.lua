-- ============================================================================
-- UI/pet.lua (OpenHeal)
-- Pet frames for the player, party pets and (optionally) raid pets.
--
-- WHY:
--   fading/range.lua has been driving ns.Pet.playerFrame, ns.Pet.partyFrames and
--   ns.Pet.raidFrames since before this file existed - the module it was calling
--   into simply was not there. This implements the contract range.lua already
--   expects, including frame.ownerUnit so pets inherit their owner's range.
--
-- STABLE TOKENS:
--   Same model as raid.lua. Each frame permanently owns one pet token, so the
--   secure click-cast overlay never has to change its unit attribute. Sorting
--   and layout move frames around; they never reassign units.
--
-- SCOPE:
--   Deliberately a simpler widget than the party/raid button: no role letter,
--   no group number, no debuff rows, no private aura anchors. You heal a pet
--   reactively; you do not track HoTs on it.
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns or {}
_G[ADDON] = ns

ns.Pet = ns.Pet or {}
local Pet = ns.Pet

local U = ns.UnitUtil
local T = ns.Theme

local SafeSetText   = U.SafeSetText
local SafeSetMinMax = U.SafeSetMinMax
local SafeSetValue  = U.SafeSetValue

local CreateFrame      = CreateFrame
local UnitExists       = UnitExists
local InCombatLockdown = InCombatLockdown
local ipairs           = ipairs
local pairs            = pairs
local floor            = math.floor
local tonumber         = tonumber

local MAX_PARTY_PETS = 4
local MAX_RAID_PETS  = 40
local POWER_H = 2

Pet.frames        = Pet.frames or {}          -- every frame, for bulk refresh
Pet.framesByUnit  = Pet.framesByUnit or {}
Pet.partyFrames   = Pet.partyFrames or {}     -- contract with range.lua
Pet.raidFrames    = Pet.raidFrames or {}
Pet.playerFrame   = Pet.playerFrame or nil
Pet.mover         = Pet.mover or nil
Pet.eventFrame    = Pet.eventFrame or nil

local function GetDB()
    return ns:GetPetDB()
end

-- ---------------------------------------------------------------------------
-- Owner resolution: a pet's range and relevance follow its owner.
-- ---------------------------------------------------------------------------
local function OwnerOf(petUnit)
    if petUnit == "pet" then return "player" end

    local i = petUnit:match("^partypet(%d+)$")
    if i then return "party" .. i end

    i = petUnit:match("^raidpet(%d+)$")
    if i then return "raid" .. i end

    return nil
end

-- ---------------------------------------------------------------------------
-- Button
-- ---------------------------------------------------------------------------
local function CreatePetButton(stableUnit)
    local btn = CreateFrame("Button", nil, UIParent)
    btn:SetClampedToScreen(true)
    btn:RegisterForClicks("AnyUp", "AnyDown")

    btn.unit        = stableUnit
    btn._stableUnit = stableUnit
    btn.ownerUnit   = OwnerOf(stableUnit)
    btn._ohKind     = "PET"

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
    btn.hp:SetPoint("TOPLEFT", 1, -1)
    btn.hp:SetPoint("BOTTOMRIGHT", -1, 1)
    T:ApplyBarTexture(btn.hp)
    SafeSetMinMax(btn.hp, 0, 1)
    SafeSetValue(btn.hp, 1)

    if ns.Smoothing then ns.Smoothing:Register(btn.hp) end

    btn.hpbg = btn.hp:CreateTexture(nil, "BACKGROUND")
    btn.hpbg:SetAllPoints()
    btn.hpbg:SetColorTexture(T:Color("barBG"))

    btn.nameText = btn.hp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- Pet frames are short: one point under the configured size, not a fixed
    -- value that would ignore the Font Size slider.
    T:ApplyFont(btn.nameText, -1)
    btn.nameText:SetPoint("LEFT", btn.hp, "LEFT", 3, 0)
    btn.nameText:SetJustifyH("LEFT")
    btn.nameText:SetTextColor(T:Color("text"))
    btn.nameText:SetText("")

    -- Click-casting: same registration path as party/raid frames.
    if _G.OpenHeal_RegisterFrame then
        _G.OpenHeal_RegisterFrame(btn, stableUnit)
    end

    if ns.Aggro and ns.Aggro.Attach then ns.Aggro:Attach(btn) end
    if ns.RaidMarker and ns.RaidMarker.Attach then ns.RaidMarker:Attach(btn) end

    btn:Hide()
    return btn
end

local function EnsureFrame(unit, bucket)
    local f = Pet.framesByUnit[unit]
    if f then return f end

    f = CreatePetButton(unit)
    Pet.framesByUnit[unit] = f
    Pet.frames[#Pet.frames + 1] = f
    bucket[#bucket + 1] = f
    return f
end

-- ---------------------------------------------------------------------------
-- Mover
-- ---------------------------------------------------------------------------
local function CreateMover()
    local m = CreateFrame("Frame", "OpenHealPetMover", UIParent)
    m:SetSize(120, 16)
    m:SetFrameStrata("DIALOG")
    m:Hide()

    m.bg = m:CreateTexture(nil, "BACKGROUND")
    m.bg:SetAllPoints()
    m.bg:SetColorTexture(0, 0, 0, 0.35)

    m.text = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    m.text:SetPoint("CENTER")
    m.text:SetText("Pets (drag)")

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
        local p, _, rp, x, y = self:GetPoint()

        db.point    = p or db.point
        db.relPoint = rp or db.relPoint
        db.x        = floor((tonumber(x) or 0) + 0.5)
        db.y        = floor((tonumber(y) or 0) + 0.5)

        Pet:Build()
    end)

    return m
end

-- ---------------------------------------------------------------------------
-- Update
-- ---------------------------------------------------------------------------
function Pet:Apply(frame)
    local u = frame.unit
    if not u or not UnitExists(u) then return end

    local db = GetDB()

    T:ApplyToUnitButton(frame)

    SafeSetText(frame.nameText, U.GetDisplayName(u, frame, 10, true))

    local cur, mx = U.GetHealthValues(u)
    SafeSetMinMax(frame.hp, 0, mx)

    if ns.Smoothing then
        ns.Smoothing:SetValue(frame.hp, cur)
    else
        SafeSetValue(frame.hp, cur)
    end

    if db.classColor then
        local r, g, b = U.GetClassColor(frame.ownerUnit or u)
        if r then
            frame.hp:SetStatusBarColor(r, g, b)
        else
            frame.hp:SetStatusBarColor(T:Color("health"))
        end
    else
        frame.hp:SetStatusBarColor(T:Color("health"))
    end

    if ns.Aggro then ns.Aggro:Update(frame, u) end
    if ns.RaidMarker then ns.RaidMarker:Update(frame, u) end
end

function Pet:UpdateHealth(frame)
    local u = frame.unit
    if not u or not UnitExists(u) then return end

    local cur, mx = U.GetHealthValues(u)
    SafeSetMinMax(frame.hp, 0, mx)

    if ns.Smoothing then
        ns.Smoothing:SetValue(frame.hp, cur)
    else
        SafeSetValue(frame.hp, cur)
    end
end

-- ---------------------------------------------------------------------------
-- Which pets exist right now
-- ---------------------------------------------------------------------------
function Pet:GetUnits()
    local db = GetDB()
    local list = {}

    if UnitExists("pet") then list[#list + 1] = "pet" end

    if db.showParty ~= false and not IsInRaid() then
        for i = 1, MAX_PARTY_PETS do
            local u = "partypet" .. i
            if UnitExists(u) then list[#list + 1] = u end
        end
    end

    if db.showRaid and IsInRaid() then
        for i = 1, MAX_RAID_PETS do
            local u = "raidpet" .. i
            if UnitExists(u) then list[#list + 1] = u end
        end
    end

    return list
end

function Pet:EnsureFramesFor(units)
    for _, u in ipairs(units) do
        if u == "pet" then
            if not self.playerFrame then
                self.playerFrame = CreatePetButton("pet")
                self.framesByUnit["pet"] = self.playerFrame
                self.frames[#self.frames + 1] = self.playerFrame
            end
        elseif u:match("^partypet") then
            EnsureFrame(u, self.partyFrames)
        else
            EnsureFrame(u, self.raidFrames)
        end
    end
end

function Pet:Build()
    local db = GetDB()

    if not self.mover then
        self.mover = CreateMover()
    end

    self.mover:ClearAllPoints()
    self.mover:SetPoint(db.point or "CENTER", UIParent, db.relPoint or "CENTER", db.x or 0, db.y or 0)

    if not db.enabled then
        for _, f in ipairs(self.frames) do
            U.HideFrame(f)
        end
        self.mover:Hide()
        return
    end

    local units = self:GetUnits()
    self:EnsureFramesFor(units)

    self.mover:SetShown(not db.locked and not InCombatLockdown())

    local active = {}
    local shown = {}

    for _, u in ipairs(units) do
        local f = self.framesByUnit[u]
        if f then
            active[u] = true
            if not InCombatLockdown() then f:Show() end
            U.SoftShow(f)
            self:Apply(f)
            shown[#shown + 1] = f
        end
    end

    for u, f in pairs(self.framesByUnit) do
        if not active[u] then
            U.HideFrame(f)
        end
    end

    self:Layout(shown)
end

function Pet:Layout(frames)
    local db = GetDB()
    local w = tonumber(db.w) or 90
    local h = tonumber(db.h) or 24
    local spacing = tonumber(db.spacing) or 3
    local horizontal = (db.orientation == "HORIZONTAL")

    for i, f in ipairs(frames) do
        f:SetSize(w, h)
        f:ClearAllPoints()

        if i == 1 then
            f:SetPoint("TOPLEFT", self.mover, "TOPLEFT", 0, 0)
        elseif horizontal then
            f:SetPoint("LEFT", frames[i - 1], "RIGHT", spacing, 0)
        else
            f:SetPoint("TOP", frames[i - 1], "BOTTOM", 0, -spacing)
        end

        if ns.Aggro then ns.Aggro:Place(f) end
        if ns.RaidMarker then ns.RaidMarker:Place(f) end
    end
end

function Pet:OnUnit(unit, event)
    local f = self.framesByUnit[unit]
    if not f or not f:IsShown() then return end

    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        self:UpdateHealth(f)
        return
    end

    self:Apply(f)
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------
function Pet:Init()
    if self.eventFrame then return end

    local ef = CreateFrame("Frame")
    self.eventFrame = ef

    ef:RegisterEvent("GROUP_ROSTER_UPDATE")
    ef:RegisterEvent("PLAYER_ENTERING_WORLD")
    ef:RegisterEvent("UNIT_PET")
    ef:RegisterEvent("UNIT_HEALTH")
    ef:RegisterEvent("UNIT_MAXHEALTH")
    ef:RegisterEvent("UNIT_NAME_UPDATE")

    ef:SetScript("OnEvent", function(_, event, unit)
        if event == "GROUP_ROSTER_UPDATE"
        or event == "PLAYER_ENTERING_WORLD"
        or event == "UNIT_PET" then
            if ns.RequestPetRebuild then ns:RequestPetRebuild() else Pet:Build() end
            return
        end

        if unit then
            Pet:OnUnit(unit, event)
        end
    end)

    self:Build()
end
