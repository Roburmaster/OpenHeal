-- ============================================================================
-- blizzardframes.lua (OpenHeal)
-- Hide Blizzard Party & Raid Frames WITHOUT taint / protected-call blocks (Retail 12.0)
-- - Never calls Hide/Show/SetShown in combat on protected frames
-- - Uses hooksecurefunc + OnShow hook, but bails in combat
-- - Re-applies after combat (PLAYER_REGEN_ENABLED)
-- ============================================================================

local ADDON, ns = ...

local f = CreateFrame("Frame")

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

-- Track which frames we already hooked so we don't hook 500 times
local hooked = {}
local pending = false

-- Hide ONLY out of combat
local function TryHide(frame)
    if not frame then return end
    if InCombat() then
        pending = true
        return
    end

    -- Never call SetShown here. Use Hide only.
    -- No pcall needed normally, but keep it defensive.
    pcall(frame.Hide, frame)
end

local function EnsureHooks(frame)
    if not frame or hooked[frame] then return end
    hooked[frame] = true

    -- If Blizzard calls :Show(), we counter-hide (but NOT in combat)
    if frame.Show and type(frame.Show) == "function" then
        pcall(hooksecurefunc, frame, "Show", function(self)
            -- If combat, do nothing (avoid protected call blocks)
            if InCombat() then
                pending = true
                return
            end
            pcall(self.Hide, self)
        end)
    end

    -- If Blizzard triggers OnShow, also counter-hide (but NOT in combat)
    if frame.HookScript then
        pcall(frame.HookScript, frame, "OnShow", function(self)
            if InCombat() then
                pending = true
                return
            end
            pcall(self.Hide, self)
        end)
    end
end

local function SoftHide(frame)
    if not frame then return end
    EnsureHooks(frame)
    TryHide(frame)
end

local function HideCompactFrames()
    -- Always set up hooks (hooks are safe in combat; the *Hide* is not)
    EnsureHooks(_G.CompactPartyFrame)
    EnsureHooks(_G.CompactRaidFrameContainer)
    EnsureHooks(_G.CompactRaidFrameManager)
    EnsureHooks(_G.CompactRaidFrameManagerToggleButton)

    for i = 1, 4 do
        EnsureHooks(_G["PartyMemberFrame"..i])
    end

    -- Now try to hide (will defer automatically if combat)
    SoftHide(_G.CompactPartyFrame)
    SoftHide(_G.CompactRaidFrameContainer)
    SoftHide(_G.CompactRaidFrameManager)
    SoftHide(_G.CompactRaidFrameManagerToggleButton)

    for i = 1, 4 do
        SoftHide(_G["PartyMemberFrame"..i])
    end
end

local function SafeHookGlobal(funcName)
    local fn = _G[funcName]
    if type(fn) == "function" then
        -- hooksecurefunc with global name is correct here
        pcall(hooksecurefunc, funcName, function()
            HideCompactFrames()
        end)
    end
end

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_REGEN_ENABLED")

f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then
            pending = false
            HideCompactFrames()
        end
        return
    end

    HideCompactFrames()
end)

-- Blizzard likes to re-show these when entering Edit Mode or applying profiles
SafeHookGlobal("CompactRaidFrameManager_UpdateShown")
SafeHookGlobal("EditModeManagerFrame_OnEditModeEnter")
SafeHookGlobal("EditModeManagerFrame_OnEditModeExit")
SafeHookGlobal("CompactUnitFrameProfiles_ApplyCurrentProfile")
SafeHookGlobal("CompactUnitFrameProfiles_ApplyProfile")
SafeHookGlobal("CompactUnitFrameProfiles_ActivateRaidProfile")

ns.HideBlizzardFrames = HideCompactFrames
