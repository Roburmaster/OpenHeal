-- ============================================================================
-- core/util.lua (OpenHeal)
-- Shared secret-safe helpers for every unit-frame module.
--
-- WHY THIS EXISTS:
--   party.lua and raid.lua used to carry byte-identical copies of every helper
--   below. That meant every fix had to be made twice, and the two files had
--   already drifted apart (raid checked allowDrag on drag start, party did not;
--   raid had UpdateTargetedSquare, party did not). Pet and tank frames would
--   have made it four copies.
--
--   Modules pull these into locals at file scope:
--       local U = ns.UnitUtil
--       local SafeSetText = U.SafeSetText
--   so call sites stay identical and the hot paths keep their upvalues.
--
-- MIDNIGHT / 12.0 RULES ENCODED HERE:
--   - Never do math or comparisons on a value that might be secret.
--   - Never call string methods on a name straight from the API.
--   - Route every set through pcall: a secret value reaching a setter that
--     cannot take one raises, and one raise must not kill the whole update.
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns or {}
_G[ADDON] = ns

ns.UnitUtil = ns.UnitUtil or {}
local U = ns.UnitUtil

local pcall    = pcall
local type     = type
local tostring = tostring
local tonumber = tonumber

local UnitExists        = UnitExists
local UnitName          = UnitName
local UnitHealth        = UnitHealth
local UnitHealthMax     = UnitHealthMax
local UnitPower         = UnitPower
local UnitPowerMax      = UnitPowerMax
local UnitIsUnit        = UnitIsUnit
local UnitIsPlayer      = UnitIsPlayer
local UnitCanAttack     = UnitCanAttack
local UnitIsCharmed     = UnitIsCharmed

-- ---------------------------------------------------------------------------
-- Secret values
-- ---------------------------------------------------------------------------
function U.IsSecretValue(v)
    local f = _G.issecretvalue
    if type(f) == "function" then
        local ok, ret = pcall(f, v)
        if ok and ret then
            return true
        end
    end
    return false
end

local IsSecretValue = U.IsSecretValue

-- Pull a plain number out of a possibly-secret value, or nil if impossible.
function U.ScrubNumber(v)
    if v == nil then return nil end

    local scrub = _G.scrubsecretvalues
    if scrub then
        local ok, sv = pcall(scrub, v)
        if ok and type(sv) == "number" then return sv end
        return nil
    end

    if type(v) == "number" then return v end
    return nil
end

function U.ScrubBool(v)
    if v == nil then return false end

    local scrub = _G.scrubsecretvalues
    if scrub then
        local ok, sv = pcall(scrub, v)
        if ok and type(sv) == "boolean" then return sv end
        return false
    end

    if type(v) == "boolean" then return v end
    return false
end

-- ---------------------------------------------------------------------------
-- Cache keys built from API values
--
-- string.format and ".." PROPAGATE secrecy: feed them one secret number and the
-- resulting string is a secret string, and comparing it with == or ~= raises
-- "attempt to compare ... while execution tainted". Caches keyed on colours,
-- aura instance IDs or health values must therefore reduce every component to a
-- plain value FIRST, and give up if they cannot.
--
-- Returns a plain string, or nil meaning "not cacheable - just do the work".
-- ---------------------------------------------------------------------------
function U.SafeCacheKey(...)
    local n = select("#", ...)
    if n == 0 then return nil end

    local parts = {}
    for i = 1, n do
        local v = select(i, ...)

        if v == nil then
            parts[i] = "nil"
        else
            local plain = U.ScrubNumber(v)
            if plain ~= nil then
                parts[i] = string.format("%.4f", plain)
            elseif type(v) == "string" and not IsSecretValue(v) then
                parts[i] = v
            elseif type(v) == "boolean" then
                parts[i] = v and "t" or "f"
            else
                -- Secret and not reducible: no usable key.
                return nil
            end
        end
    end

    return table.concat(parts, ":")
end

-- ---------------------------------------------------------------------------
-- Safe setters
-- ---------------------------------------------------------------------------
function U.SafeSetText(fs, text)
    if not fs then return end
    if text == nil then text = "" end
    pcall(fs.SetText, fs, text)
end

function U.SafeSetFormattedText(fs, fmt, ...)
    if not fs then return false end
    local ok = pcall(fs.SetFormattedText, fs, fmt, ...)
    return ok and true or false
end

function U.SafeSetMinMax(bar, mn, mx)
    if not bar then return end
    pcall(bar.SetMinMaxValues, bar, mn, mx)
end

function U.SafeSetValue(bar, v)
    if not bar then return end
    pcall(bar.SetValue, bar, v)
end

-- ---------------------------------------------------------------------------
-- Unit safety
--
-- A unit that is hostile, charmed or otherwise taken over can report secret
-- health. Reading a % off it is meaningless and can raise, so callers blank
-- the text instead.
-- ---------------------------------------------------------------------------
function U.IsSafeUnit(unit)
    if not unit or not UnitExists(unit) then return false end

    local ok, hostile = pcall(UnitCanAttack, "player", unit)
    if ok and hostile then return false end

    local okC, charmed = pcall(UnitIsCharmed, unit)
    if okC and charmed then return false end

    return true
end

-- ---------------------------------------------------------------------------
-- Vehicles
--
-- When a group member takes a vehicle or is possessed, their health lives on
-- the vehicle token, not the player token. Without this the frame goes blank
-- or freezes at the value from the moment they mounted.
-- ---------------------------------------------------------------------------
local VEHICLE_MAP = {
    player = "vehicle",
}

function U.ResolveVehicleUnit(unit)
    if not unit then return unit end
    if not UnitHasVehicleUI then return unit end

    local ok, inVehicle = pcall(UnitHasVehicleUI, unit)
    if not ok or not inVehicle then return unit end

    local mapped = VEHICLE_MAP[unit]
    if not mapped then
        local index = unit:match("^party(%d+)$")
        if index then
            mapped = "partypet" .. index
        else
            index = unit:match("^raid(%d+)$")
            if index then
                mapped = "raidpet" .. index
            end
        end
    end

    if mapped and UnitExists(mapped) then
        return mapped
    end
    return unit
end

-- ---------------------------------------------------------------------------
-- Roles
-- ---------------------------------------------------------------------------
function U.RoleRank(role)
    if role == "TANK" then return 1 end
    if role == "HEALER" then return 2 end
    return 3
end

function U.RoleLetter(role)
    if role == "TANK" then return "T" end
    if role == "HEALER" then return "H" end
    if role == "DAMAGER" then return "D" end
    return ""
end

local ROLE_COLORS = {
    TANK    = { 0.20, 0.60, 1.00 },
    HEALER  = { 0.20, 1.00, 0.20 },
    DAMAGER = { 1.00, 0.30, 0.30 },
}

function U.RoleColor(role)
    local c = ROLE_COLORS[role]
    if c then return c[1], c[2], c[3] end
    return 0.8, 0.8, 0.8
end

function U.IsTank(unit)
    if not unit or not UnitExists(unit) then return false end
    local ok, role = pcall(UnitGroupRolesAssigned, unit)
    return (ok and role == "TANK") or false
end

-- ---------------------------------------------------------------------------
-- Names
--
-- Names from the API can be secret. Never run string methods on one without
-- proving it is a plain string first. Frames cache the last readable name so a
-- unit that goes secret mid-fight keeps a label instead of blanking.
-- ---------------------------------------------------------------------------
function U.ShortName(full, maxChars, stripRealm)
    if full == nil then return "" end
    if IsSecretValue(full) then return full end

    if type(full) ~= "string" then
        full = tostring(full or "")
    end

    local name = full
    if stripRealm then
        name = full:match("^[^-]+") or full
    end

    maxChars = tonumber(maxChars) or 0
    if maxChars > 0 and #name > maxChars then
        return name:sub(1, maxChars) .. "…"
    end
    return name
end

function U.GetDisplayName(unit, frame, maxChars, stripRealm)
    local name = UnitName(unit)

    if name == nil then
        if frame and frame._ohCachedName then
            return frame._ohCachedName
        end
        return ""
    end

    if IsSecretValue(name) then
        if frame and frame._ohCachedName and frame._ohCachedName ~= "" then
            return frame._ohCachedName
        end
        return name
    end

    local short = U.ShortName(name, maxChars, stripRealm)

    if frame then
        frame._ohCachedName = short
    end

    return short
end

-- Sorting must never compare secret strings; fall back to the unit token.
function U.GetSortName(unit)
    local name = UnitName(unit)
    if not name or IsSecretValue(name) or type(name) ~= "string" then
        return unit or ""
    end
    return name
end

-- ---------------------------------------------------------------------------
-- Health / power
-- ---------------------------------------------------------------------------
function U.GetHealthValues(unit)
    local cur = UnitHealth(unit)
    local mx  = UnitHealthMax(unit)

    if cur == nil then cur = 0 end
    if mx  == nil then mx  = 1 end

    return cur, mx
end

function U.GetPowerValues(unit)
    local cur = UnitPower(unit)
    local mx  = UnitPowerMax(unit)

    if cur == nil then cur = 0 end
    if mx  == nil then mx  = 1 end

    return cur, mx
end

-- Returns a plain 0-100 number, a secret value, or nil.
-- Callers must check IsSecretValue before formatting with %d.
function U.GetHealthPercent(unit)
    local percentValue

    if UnitHealthPercent then
        local ok = pcall(function()
            local scaling = (CurveConstants and CurveConstants.ScaleTo100) or 1
            percentValue = UnitHealthPercent(unit, true, scaling)
        end)
        if not ok then return nil end
        return percentValue
    end

    local ok = pcall(function()
        local maxH = UnitHealthMax(unit)
        local curH = UnitHealth(unit, true)
        if maxH and curH then
            percentValue = (curH / maxH) * 100
        end
    end)
    if not ok then return nil end
    return percentValue
end

-- ---------------------------------------------------------------------------
-- Class colouring
-- ---------------------------------------------------------------------------
function U.GetClassColor(unit)
    local ok, _, class = pcall(UnitClass, unit)
    if not ok or not class then return nil end

    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return nil end

    return c.r, c.g, c.b
end

-- ---------------------------------------------------------------------------
-- Combat-safe show/hide
--
-- Hide() on a frame that owns a secure overlay is blocked in combat. Dropping
-- alpha to zero and disabling the mouse achieves the same visual result and is
-- always allowed.
-- ---------------------------------------------------------------------------
-- EnableMouse is blocked in combat on anything built from a secure template.
-- The party/raid buttons are plain frames so it would be allowed there, but the
-- focus panel uses SecureUnitButtonTemplate and must not call it. Guarding
-- unconditionally costs nothing and makes one implementation correct for both.
function U.SoftHide(frame)
    if not frame then return end
    frame:SetAlpha(0)
    if not InCombatLockdown() then
        frame:EnableMouse(false)
    end
    if frame._hpPctOverlay then frame._hpPctOverlay:Hide() end
    if frame._ohTargetedSquare then frame._ohTargetedSquare:Hide() end
    if frame._ohSelected then frame._ohSelected:Hide() end
    if frame._ohSelectedBorder then frame._ohSelectedBorder:Hide() end
    if frame._ohMarker then frame._ohMarker:Hide() end
    if frame._ohAggro then frame._ohAggro:Hide() end
    if frame._ohRes then frame._ohRes:Hide() end
end

function U.SoftShow(frame)
    if not frame then return end
    frame:SetAlpha(1)
    if not InCombatLockdown() then
        frame:EnableMouse(true)
    end
    if frame._hpPctOverlay then frame._hpPctOverlay:Show() end
end

function U.HideFrame(frame)
    if not InCombatLockdown() then
        frame:Hide()
        if frame._hpPctOverlay then frame._hpPctOverlay:Hide() end
    else
        U.SoftHide(frame)
    end
end

-- ---------------------------------------------------------------------------
-- Back-compat: party.lua and raid.lua probed ns.util.IsSafeUnit, which never
-- existed. Provide it so that path finally resolves.
-- ---------------------------------------------------------------------------
ns.util = ns.util or {}
ns.util.IsSafeUnit = U.IsSafeUnit
