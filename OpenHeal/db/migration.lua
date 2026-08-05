-- ============================================================================
-- db/migration.lua
-- One-time import from the addon's previous SavedVariables names.
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns or {}
_G[ADDON] = ns

local previousPrefix = "Rob" .. "Heal"
local previousAddon = "Rob" .. "UI" .. "Heal"

local mappings = {
    { "OpenHealGlobalDB",    previousPrefix .. "GlobalDB" },
    { "OpenHealDB",          previousPrefix .. "DB" },
    { "OpenHealCharDB",      previousPrefix .. "CharDB" },
    { "OpenHealBindingsDB",  "Heal" .. "DB" },
    { "OpenHealBindHelpDB",  previousPrefix .. "BindHelpDB" },
    { "OpenHealMinimapDB",   previousAddon .. "DB" },
}

-- Remember which new databases were restored by WoW before any OpenHeal file
-- can create runtime defaults. A late-loading previous addon may then safely
-- replace only databases that had no real OpenHeal data of their own.
local hadOpenHealData = {}
local imported = {}

for _, names in ipairs(mappings) do
    local value = _G[names[1]]
    hadOpenHealData[names[1]] = type(value) == "table" and next(value) ~= nil
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end

    seen = seen or {}
    if seen[value] then return seen[value] end

    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[DeepCopy(key, seen)] = DeepCopy(child, seen)
    end
    return copy
end

local function HasPreviousAddonData()
    if C_AddOns and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded(previousAddon)
    then
        return true
    end

    if IsAddOnLoaded and IsAddOnLoaded(previousAddon) then
        return true
    end

    -- Ignore the old generic bindings table unless at least one uniquely named
    -- database proves that it belongs to the previous addon.
    for index, names in ipairs(mappings) do
        if index ~= 4 then
            local value = _G[names[2]]
            if type(value) == "table" and next(value) ~= nil then
                return true
            end
        end
    end

    return false
end

local function CopyInto(destination, source)
    local copy = DeepCopy(source)
    if type(destination) ~= "table" then return copy end

    -- Keep the table identity intact for modules that captured a reference
    -- before the previous addon finished loading.
    for key in pairs(destination) do
        destination[key] = nil
    end
    for key, value in pairs(copy) do
        destination[key] = value
    end
    return destination
end

local function ImportPreviousSavedVariables()
    if not HasPreviousAddonData() then return false end

    local changed = false

    for _, names in ipairs(mappings) do
        local newName, previousName = names[1], names[2]
        local previousValue = _G[previousName]

        if not imported[newName]
            and not hadOpenHealData[newName]
            and type(previousValue) == "table"
            and next(previousValue) ~= nil
        then
            _G[newName] = CopyInto(_G[newName], previousValue)
            imported[newName] = true
            changed = true
        end
    end

    if changed then
        ns.LegacySavedVariablesImported = true
    end

    return changed
end

ns.ImportPreviousSavedVariables = ImportPreviousSavedVariables
ImportPreviousSavedVariables()

-- The previous addon may load before or after OpenHeal. Recheck on both addon
-- load notifications and once more before PLAYER_LOGIN consumers initialise.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:SetScript("OnEvent", function(self, event, addonName)
    if event == "PLAYER_LOGIN" then
        ImportPreviousSavedVariables()
        self:UnregisterAllEvents()
    elseif addonName == ADDON or addonName == previousAddon then
        ImportPreviousSavedVariables()
    end
end)
