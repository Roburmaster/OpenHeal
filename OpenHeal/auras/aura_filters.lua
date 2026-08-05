-- ============================================================================
-- aura_filters.lua (OpenHeal) - WoW 12.0 / Midnight
-- Central place for aura spell lists + priorities.
--
-- Goal:
--  - One source of truth for tracked auras (friendly buffs, debuffs)
--  - Settings UI, the live frames and the settings preview all read the SAME
--    list, so what you configure is what you see in game.
--  - Avoid duplicates, keep stable priority order
--
-- API:
--   local AF = ns.AuraFilters
--   AF:GetList("FRIENDLYBUFFS")       -> array of spellIDs (priority order)
--   AF:GetList("DEBUFFS")             -> array of spellIDs (priority order)
--   AF:BuildMaps(list)                -> whitelistSet, prioMap
--   AF:ResolveList(which, cfg)        -> list resolved from cfg.mode/cfg.custom
--   AF:ResolveMaps(which, cfg)        -> whitelistSet, prioMap, listKey
--
-- cfg.mode:
--   "OFF"       -> {}            (nothing whitelisted)
--   "IMPORTANT" -> curated preset (default)
--   "CUSTOM"    -> cfg.custom    (map of [spellID] = true/false)
--   "ALL"       -> nil whitelist (caller shows everything it finds)
-- ============================================================================

local _, ns = ...
ns.AuraFilters = ns.AuraFilters or {}
local AF = ns.AuraFilters

local type = type
local ipairs = ipairs
local pairs = pairs
local tonumber = tonumber
local tostring = tostring
local tsort = table.sort

-- ---------------------------------------------------------------------------
-- FRIENDLY BUFFS (HoTs / Shields / Externals / Defensives)
-- Priority order matters: earlier = more important.
-- ---------------------------------------------------------------------------
AF.DEFAULT_FRIENDLYBUFFS = {
    -- Holy Paladin
    53563,    -- Beacon of Light
    156910,   -- Beacon of Faith
    1244893,  -- Beacon of the Savior
    156322,   -- Eternal Flame

    -- Shields / Externals
    17,      -- Power Word: Shield
    974,     -- Earth Shield
    1022,    -- Blessing of Protection
    6940,    -- Blessing of Sacrifice
    47788,   -- Guardian Spirit
    33206,   -- Pain Suppression
    102342,  -- Ironbark
    116849,  -- Life Cocoon
    204018,  -- Blessing of Spellwarding (if exists)
    1044,    -- Blessing of Freedom

    -- HoTs
    774,     -- Rejuvenation
    155777,  -- Rejuvenation (Germination)
    8936,    -- Regrowth
    33763,   -- Lifebloom
    139,     -- Renew
    61295,   -- Riptide
    119611,  -- Renewing Mist
    124682,  -- Enveloping Mist
    364343,  -- Echo (Evoker)
    355941,  -- Dream Breath
    157982,  -- Tranquility (hot ticks, sometimes useful) - optional

    -- Utility / class mechanics
    194384,  -- Atonement
}

-- ---------------------------------------------------------------------------
-- IMPORTANT DEBUFFS (baseline preset)
-- Kept deliberately short: this is a "must not miss" list, not a dump of every
-- debuff in the game. Use mode = "CUSTOM" or "ALL" for wider coverage.
-- ---------------------------------------------------------------------------
AF.DEFAULT_DEBUFFS = {
    -- Dungeon/raid mechanics worth a dedicated slot
    209858,  -- Necrotic Wound
    240559,  -- Grievous Wound
    255371,  -- Terrifying Screech
    240443,  -- Burst
    -- Crowd control / healing-relevant
    25771,   -- Forbearance
    33786,   -- Cyclone
    605,     -- Mind Control
    853,     -- Hammer of Justice
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function Dedup(list)
    local out = {}
    local seen = {}
    for _, id in ipairs(list or {}) do
        if type(id) == "number" and id > 0 and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end

local PRESETS = {
    FRIENDLYBUFFS = "DEFAULT_FRIENDLYBUFFS",
    DEBUFFS       = "DEFAULT_DEBUFFS",
}

function AF:GetList(which)
    local key = PRESETS[which]
    if not key then return {} end
    return Dedup(self[key])
end

-- Build whitelist set + priority map from list
function AF:BuildMaps(list)
    local wl = {}
    local pr = {}
    local p = 1
    for _, id in ipairs(list or {}) do
        if type(id) == "number" and id > 0 then
            if not wl[id] then
                wl[id] = true
                pr[id] = p
                p = p + 1
            end
        end
    end
    return wl, pr
end

-- ---------------------------------------------------------------------------
-- Custom list -> array (sorted, so priority order is stable across sessions)
-- ---------------------------------------------------------------------------
local function CustomToList(customTable)
    local out = {}
    for spellID, enabled in pairs(customTable or {}) do
        if enabled then
            local id = tonumber(spellID)
            if id and id > 0 then
                out[#out + 1] = id
            end
        end
    end
    tsort(out)
    return out
end

-- ---------------------------------------------------------------------------
-- Resolve the effective list for a config block.
-- Returns list, mode. A nil list means "ALL" (no whitelist filtering).
-- ---------------------------------------------------------------------------
function AF:ResolveList(which, cfg)
    local mode = cfg and cfg.mode or "IMPORTANT"

    if mode == "OFF" then
        return {}, "OFF"
    end

    if mode == "ALL" then
        return nil, "ALL"
    end

    if mode == "CUSTOM" then
        return CustomToList(cfg and cfg.custom), "CUSTOM"
    end

    return self:GetList(which), "IMPORTANT"
end

-- ---------------------------------------------------------------------------
-- Cheap change signature for a config block.
-- Used to decide whether the resolved maps need rebuilding at all. This runs
-- per frame per update, so it must not allocate or sort.
-- ---------------------------------------------------------------------------
function AF:Signature(which, cfg)
    local mode = cfg and cfg.mode or "IMPORTANT"
    if mode ~= "CUSTOM" then
        return which .. "|" .. mode
    end

    -- Fold the enabled custom IDs into an order-independent checksum so that
    -- adding, removing or toggling an entry always changes the signature.
    -- Count + sum + sum-of-squares makes a collision between two real spell-ID
    -- sets effectively impossible.
    local count, sum, sum2 = 0, 0, 0
    for spellID, enabled in pairs(cfg and cfg.custom or {}) do
        if enabled then
            local id = tonumber(spellID)
            if id and id > 0 then
                count = count + 1
                sum = sum + id
                sum2 = sum2 + id * id
            end
        end
    end

    return which .. "|CUSTOM|" .. count .. "|" .. sum .. "|" .. sum2
end

-- ---------------------------------------------------------------------------
-- Resolve to lookup maps + a cache key so callers can skip rebuilds.
-- whitelist == nil means "show everything" (mode ALL).
--
-- Results are memoized on the signature: every unit frame in the raid resolves
-- the same config, so this must not rebuild 40x per update tick.
-- ---------------------------------------------------------------------------
local resolveCache = {}

function AF:ResolveMaps(which, cfg)
    local key = self:Signature(which, cfg)

    local cached = resolveCache[key]
    if cached then
        return cached.wl, cached.pr, key
    end

    local list = self:ResolveList(which, cfg)

    if list == nil then
        resolveCache[key] = { wl = nil, pr = nil }
        return nil, nil, key
    end

    local wl, pr = self:BuildMaps(list)
    resolveCache[key] = { wl = wl, pr = pr }

    return wl, pr, key
end

function AF:ClearCache()
    resolveCache = {}
end
