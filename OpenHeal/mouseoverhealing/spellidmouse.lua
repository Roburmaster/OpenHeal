-- ============================================================================
-- Tooltip IDs (WoW 12.0+ / Midnight safe)
-- Adds SpellID (spells + auras) and ItemID to tooltips via TooltipDataProcessor
-- Combat-guarded to reduce taint risk
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns or {}

local InCombatLockdown = InCombatLockdown
local type = type
local tonumber = tonumber
local pcall = pcall

-- type(v) == "number" is TRUE for a secret number, so it proves nothing about
-- whether a value can be concatenated or printed. Reduce to a plain number
-- first, and drop the line entirely if that is not possible.
-- (Same trap that produced the SetCooldown error storm in bindview.lua.)
local function PlainNumber(v)
    if v == nil then return nil end

    local U = ns and ns.UnitUtil
    if U and U.ScrubNumber then
        return U.ScrubNumber(v)
    end

    local scrub = _G.scrubsecretvalues
    if scrub then
        local ok, sv = pcall(scrub, v)
        if ok and type(sv) == "number" then return sv end
        return nil
    end

    if type(v) == "number" then return v end
    return nil
end

local function SafeAddLine(tooltip, left, value)
    if not tooltip or value == nil then return end
    pcall(tooltip.AddLine, tooltip, " ")
    pcall(tooltip.AddLine, tooltip, left .. tostring(value))
end

local function AddSpellID(tooltip, data)
    if InCombatLockdown and InCombatLockdown() then return end
    if not tooltip or not data then return end

    local spellID = PlainNumber(data.id)
    if spellID then
        SafeAddLine(tooltip, "|cffffcc00SpellID:|r ", spellID)
    end
end

local function AddAuraSpellID(tooltip, data)
    if InCombatLockdown and InCombatLockdown() then return end
    if not tooltip or not data then return end
    if not data.auraInstanceID or not data.unit then return end
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByAuraInstanceID then return end

    local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, data.unit, data.auraInstanceID)
    if not ok or not aura then return end

    local spellID = PlainNumber(aura.spellId)
    if spellID then
        SafeAddLine(tooltip, "|cffffcc00SpellID:|r ", spellID)
    end
end

local function AddItemID(tooltip, data)
    if InCombatLockdown and InCombatLockdown() then return end
    if not tooltip or not data then return end

    local itemID = PlainNumber(data.id)

    if not itemID and type(data.hyperlink) == "string" then
        itemID = tonumber(data.hyperlink:match("item:(%d+)"))
    end

    if itemID then
        SafeAddLine(tooltip, "|cffffcc00ItemID:|r ", itemID)
    end
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, AddSpellID)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.UnitAura, AddAuraSpellID)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddItemID)
end