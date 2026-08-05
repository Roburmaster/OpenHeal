-- ============================================================================
-- db/profile.lua (OpenHeal)
-- Profile engine:
--  - list/create/copy/delete/reset
--  - bind-to-spec
--  - auto-load on spec change
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns or {}
_G[ADDON] = ns

ns.Profile = ns.Profile or {}
local P = ns.Profile

local type = type
local pairs = pairs
local tinsert = table.insert
local sort = table.sort
local tonumber = tonumber
local InCombatLockdown = InCombatLockdown

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function GetCurrentSpecID()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex then return nil end
    local specID = GetSpecializationInfo and GetSpecializationInfo(specIndex)
    return specID
end

local function InvalidateCache()
    if ns and ns.InvalidateProfileCache then
        ns:InvalidateProfileCache()
    end
end

local function FireRebuildIfPossible()
    if InCombat() then return end

    if ns.RequestPartyRebuild then ns:RequestPartyRebuild()
    elseif ns.Party and ns.Party.Build then ns.Party:Build()
    end

    if ns.RequestRaidRebuild then ns:RequestRaidRebuild()
    elseif ns.Raid and ns.Raid.Build then ns.Raid:Build()
    end

    if ns.RequestPetRebuild then ns:RequestPetRebuild()
    elseif ns.Pet and ns.Pet.Build then ns.Pet:Build()
    end

    if ns.RequestTankRebuild then ns:RequestTankRebuild()
    elseif ns.Tanks and ns.Tanks.Build then ns.Tanks:Build()
    end

    local BV = ns.BindView
    if BV and BV.Build then BV:Build() end
end

local function Normalize(name)
    return ns.DB and ns.DB._NormalizeProfileName and ns.DB._NormalizeProfileName(name) or name
end

-- ------------------------------------------------------------
-- Core getters
-- ------------------------------------------------------------
function P:GetGlobalDB()
    return ns:GetGlobalDB()
end

function P:GetCharDB()
    return ns:GetCharDB()
end

function P:GetActive()
    return ns:GetActiveProfileKey()
end

function P:IsAutoLoadEnabled()
    local cdb = self:GetCharDB()
    cdb.profileOpts = cdb.profileOpts or {}
    if cdb.profileOpts.autoLoadOnSpecChange == nil then
        cdb.profileOpts.autoLoadOnSpecChange = true
    end
    return cdb.profileOpts.autoLoadOnSpecChange and true or false
end

function P:SetAutoLoadEnabled(v)
    local cdb = self:GetCharDB()
    cdb.profileOpts = cdb.profileOpts or {}
    cdb.profileOpts.autoLoadOnSpecChange = v and true or false
end

function P:GetBoundProfileForSpec(specID)
    local cdb = self:GetCharDB()
    local gdb = self:GetGlobalDB()
    specID = tonumber(specID)
    if not specID then return nil end

    local name = cdb.specProfile and cdb.specProfile[specID]
    name = Normalize(name)

    if name and gdb.profiles and type(gdb.profiles[name]) == "table" then
        return name
    end
    return nil
end

function P:IsCurrentSpecBound()
    local specID = GetCurrentSpecID()
    if not specID then return false end
    return self:GetBoundProfileForSpec(specID) ~= nil
end

-- ------------------------------------------------------------
-- List/Create/Copy/Delete/Reset
-- ------------------------------------------------------------
function P:List()
    local gdb = self:GetGlobalDB()
    local out = {}
    for name, tbl in pairs(gdb.profiles or {}) do
        if type(tbl) == "table" then
            tinsert(out, name)
        end
    end
    sort(out)
    return out
end

function P:EnsureProfile(name)
    local gdb = self:GetGlobalDB()
    name = Normalize(name)
    if not name then return nil end
    gdb.profiles = gdb.profiles or {}
    if type(gdb.profiles[name]) ~= "table" then
        gdb.profiles[name] = {}
    end
    if ns.DB and ns.DB._MergeMissing and ns.DB._DEFAULTS_PROFILE then
        ns.DB._MergeMissing(gdb.profiles[name], ns.DB._DEFAULTS_PROFILE)
    end
    return name
end

function P:Create(name, copyFrom)
    local gdb = self:GetGlobalDB()
    name = Normalize(name)
    if not name then return false end
    if type(gdb.profiles[name]) == "table" then return true end

    local newT = {}
    copyFrom = Normalize(copyFrom)
    if copyFrom and type(gdb.profiles[copyFrom]) == "table" then
        local function DeepCopy(src)
            local t = {}
            for k, v in pairs(src) do
                if type(v) == "table" then
                    t[k] = DeepCopy(v)
                else
                    t[k] = v
                end
            end
            return t
        end
        newT = DeepCopy(gdb.profiles[copyFrom])
    end

    gdb.profiles[name] = newT
    self:EnsureProfile(name)

    -- If UI is open, lists can refresh from cache; safe to invalidate.
    InvalidateCache()
    return true
end

function P:Copy(fromName, toName)
    fromName = Normalize(fromName)
    toName = Normalize(toName)
    if not fromName or not toName then return false end
    local gdb = self:GetGlobalDB()
    if type(gdb.profiles[fromName]) ~= "table" then return false end
    gdb.profiles[toName] = nil
    local ok = self:Create(toName, fromName)
    InvalidateCache()
    return ok
end

function P:Delete(name)
    name = Normalize(name)
    if not name then return false end
    local gdb = self:GetGlobalDB()
    local cdb = self:GetCharDB()

    if name == "Default" then return false end
    if name == self:GetActive() then return false end
    if type(gdb.profiles[name]) ~= "table" then return false end

    gdb.profiles[name] = nil

    -- Clear spec bindings on this char pointing to deleted profile
    cdb.specProfile = cdb.specProfile or {}
    for specID, prof in pairs(cdb.specProfile) do
        if prof == name then
            cdb.specProfile[specID] = nil
        end
    end

    InvalidateCache()
    return true
end

function P:Reset(name)
    local gdb = self:GetGlobalDB()
    name = Normalize(name) or self:GetActive()
    if type(gdb.profiles[name]) ~= "table" then return false end

    for k in pairs(gdb.profiles[name]) do
        gdb.profiles[name][k] = nil
    end

    if ns.DB and ns.DB._MergeMissing and ns.DB._DEFAULTS_PROFILE then
        ns.DB._MergeMissing(gdb.profiles[name], ns.DB._DEFAULTS_PROFILE)
    end

    InvalidateCache()

    if name == self:GetActive() then
        FireRebuildIfPossible()
    end
    return true
end

-- ------------------------------------------------------------
-- Activation + binding
-- ------------------------------------------------------------
function P:SetActive(name, bindToCurrentSpec)
    name = self:EnsureProfile(name)
    if not name then return false end

    local cdb = self:GetCharDB()
    local prev = self:GetActive()

    cdb.activeProfile = name

    if bindToCurrentSpec then
        local specID = GetCurrentSpecID()
        if specID then
            cdb.specProfile = cdb.specProfile or {}
            cdb.specProfile[specID] = name
        end
    end

    if prev ~= name then
        InvalidateCache()
        FireRebuildIfPossible()
    else
        -- Still invalidate in case something changed while ensuring/merging.
        InvalidateCache()
    end
    return true
end

function P:BindActiveToCurrentSpec()
    local cdb = self:GetCharDB()
    local specID = GetCurrentSpecID()
    if not specID then return false end
    local ap = self:GetActive()
    cdb.specProfile = cdb.specProfile or {}
    cdb.specProfile[specID] = ap
    return true
end

function P:ClearBindingForCurrentSpec()
    local cdb = self:GetCharDB()
    local specID = GetCurrentSpecID()
    if not specID then return false end
    cdb.specProfile = cdb.specProfile or {}
    cdb.specProfile[specID] = nil
    return true
end

-- ------------------------------------------------------------
-- Auto-load on spec change
-- ------------------------------------------------------------
function P:ApplySpecAuto(force)
    local cdb = self:GetCharDB()
    if not self:IsAutoLoadEnabled() and not force then
        return false
    end

    local specID = GetCurrentSpecID()
    if not specID then return false end

    local bound = self:GetBoundProfileForSpec(specID)
    if not bound then return false end

    local cur = self:GetActive()
    if cur == bound and not force then return false end

    cdb.activeProfile = bound
    InvalidateCache()
    FireRebuildIfPossible()
    return true
end

-- ------------------------------------------------------------
-- Hook into events
-- ------------------------------------------------------------
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    f:RegisterEvent("SPELLS_CHANGED")

    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 and arg1 ~= "player" then
            return
        end
        if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            P:ApplySpecAuto(true)
            return
        end
        if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELLS_CHANGED" then
            P:ApplySpecAuto(false)
            return
        end
    end)
end

function ns:UpdateActiveProfile(force)
    if ns.Profile and ns.Profile.ApplySpecAuto then
        return ns.Profile:ApplySpecAuto(force and true or false)
    end
    return false
end
