-- ============================================================================
-- framefunctions/smoothing.lua (OpenHeal)
-- Animated interpolation for health bars.
--
-- WHY:
--   A bar that snaps between values is hard to read. Smoothing turns a burst of
--   damage into a visible slide, which is how you notice "this one is dropping
--   fast" out of the corner of your eye instead of by staring at numbers.
--
-- MIDNIGHT CAVEAT (important, and it is a real limitation):
--   Interpolation needs to READ the current value and compute a step toward the
--   target. Secret health values cannot be read or compared in Lua at all. So:
--
--     readable value -> smooth
--     secret value   -> set directly, no smoothing
--
--   There is no way around this from an addon. In content where Blizzard makes
--   health secret, bars behave exactly as they did before this module existed.
--   Everywhere else they animate.
--
-- API:
--   ns.Smoothing:Register(bar)             -- make a StatusBar smoothable
--   ns.Smoothing:SetValue(bar, value)      -- use instead of bar:SetValue()
--   ns.Smoothing:Reset(bar, value)         -- jump, no animation (unit changed)
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns or {}
_G[ADDON] = ns

ns.Smoothing = ns.Smoothing or {}
local S = ns.Smoothing

local U = ns.UnitUtil

local pcall  = pcall
local abs    = math.abs
local pairs  = pairs
local type   = type

-- Bars currently mid-animation. Weak keys so hidden/GC'd frames drop out.
local active = setmetatable({}, { __mode = "k" })
local activeCount = 0

local driver

local function StyleDB()
    return ns.GetStyleDB and ns:GetStyleDB() or nil
end

local function IsEnabled()
    local db = StyleDB()
    if not db then return true end
    return db.smoothing ~= false
end

-- Fraction of the remaining distance covered per second, expressed as the
-- time constant the user configures. Lower = snappier.
local function Rate()
    local db = StyleDB()
    local r = tonumber(db and db.smoothRate) or 0.25
    if r < 0.05 then r = 0.05 end
    if r > 1.00 then r = 1.00 end
    return r
end

function S:Register(bar)
    if not bar or bar._ohSmooth then return end
    bar._ohSmooth = { target = nil, current = nil }
end

local function StopBar(bar)
    if active[bar] then
        active[bar] = nil
        activeCount = activeCount - 1
        if activeCount < 0 then activeCount = 0 end
    end
end

local function StartBar(bar)
    if not active[bar] then
        active[bar] = true
        activeCount = activeCount + 1
        if driver then driver:Show() end
    end
end

-- Hard set, no animation. Used when the frame changes unit, or on first show.
function S:Reset(bar, value)
    if not bar then return end
    StopBar(bar)

    local st = bar._ohSmooth
    if st then
        st.target = nil
        st.current = nil
    end

    U.SafeSetValue(bar, value)
end

function S:SetValue(bar, value)
    if not bar then return end

    local st = bar._ohSmooth
    if not st then
        U.SafeSetValue(bar, value)
        return
    end

    -- Secret or disabled: straight through, and make sure we are not left
    -- animating toward a stale target.
    if not IsEnabled() or value == nil or U.IsSecretValue(value) then
        StopBar(bar)
        st.target = nil
        st.current = nil
        U.SafeSetValue(bar, value)
        return
    end

    local target = tonumber(value)
    if not target then
        U.SafeSetValue(bar, value)
        return
    end

    -- No readable starting point (first set, or coming off a secret value):
    -- jump there so we do not animate up from zero on every roster change.
    if st.current == nil then
        st.current = target
        st.target = target
        U.SafeSetValue(bar, target)
        return
    end

    st.target = target

    if abs(st.target - st.current) < 0.5 then
        st.current = st.target
        StopBar(bar)
        U.SafeSetValue(bar, st.target)
        return
    end

    StartBar(bar)
end

-- ---------------------------------------------------------------------------
-- One driver for every bar. Hides itself when nothing is animating, so idle
-- cost is zero rather than 40 OnUpdate handlers doing nothing.
-- ---------------------------------------------------------------------------
driver = CreateFrame("Frame")
driver:Hide()

driver:SetScript("OnUpdate", function(self, elapsed)
    if activeCount == 0 then
        self:Hide()
        return
    end

    elapsed = elapsed or 0

    -- Exponential approach, frame-rate independent.
    local rate = Rate()
    local t = elapsed / rate
    if t > 1 then t = 1 end

    for bar in pairs(active) do
        local st = bar._ohSmooth

        if not st or st.target == nil or st.current == nil then
            StopBar(bar)
        elseif not bar:IsShown() then
            -- Do not burn cycles animating something nobody can see.
            st.current = st.target
            StopBar(bar)
            U.SafeSetValue(bar, st.target)
        else
            local delta = st.target - st.current
            st.current = st.current + delta * t

            if abs(st.target - st.current) < 0.5 then
                st.current = st.target
                StopBar(bar)
            end

            U.SafeSetValue(bar, st.current)
        end
    end
end)

S._driver = driver
