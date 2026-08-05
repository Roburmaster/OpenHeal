-- cct/cast.lua
-- .toc: ## SavedVariables: OpenHealBindingsDB
--
-- OpenHeal (12.0 Safe & Optimized)
-- - Click-casting on unit frames (mouse buttons + modifiers)  [SHIFT OK on mouse]
-- - Keyboard hover-casting via SecureHandlerEnterLeaveTemplate (CTRL/ALT only recommended; SHIFT may be blocked for keys)
-- - Named secure overlays (fixes Invalid click target name in Restricted env)
-- - Wizard UI: Drag skill -> hold modifier -> press key / or click
--
-- IMPORTANT (12.0):
--   DO NOT hook CompactUnitFrame_* (taints Blizzard CUF -> secret values -> crashes)

-- Take the addon name and shared namespace from the loader vararg, like every
-- other module, so this file always uses the real addon namespace.
local ADDON, ns = ...
ns = _G[ADDON] or ns or {}
_G[ADDON] = ns

OpenHealBindingsDB = OpenHealBindingsDB or {}

-- CONFIG
local KEY_MOUSEOVER_ONLY = true -- true = macro targets @mouseover only (safer for healing)

-- RUNTIME VARS
local registered   = setmetatable({}, { __mode = "k" }) -- [frame] = unitToken
local overlays     = setmetatable({}, { __mode = "k" }) -- [hostFrame] = overlayButton
local pendingWork  = false
local pendingSpell = nil

-- UI VARS
local mainFrame, listScroll, listContent, infoLabel, inputListener, spellPicker
local rowPool = {} -- Reusable UI rows

-- HELPERS
local function OH_Print(msg) print("|cff00ff00[OpenHeal]|r " .. tostring(msg)) end
local function OH_Error(msg) print("|cffff0000[OpenHeal]|r " .. tostring(msg)) end

-- =========================================================================
--  0. DB HANDLING
-- =========================================================================
local function EnsureDB()
    OpenHealBindingsDB = OpenHealBindingsDB or {}
    if type(OpenHealBindingsDB.clicks) ~= "table" then OpenHealBindingsDB.clicks = {} end
    if type(OpenHealBindingsDB.keys)   ~= "table" then OpenHealBindingsDB.keys   = {} end
end

local function ClickDB() EnsureDB(); return OpenHealBindingsDB.clicks end
local function KeyDB()   EnsureDB(); return OpenHealBindingsDB.keys end

-- =========================================================================
--  1. SPELL RESOLVE
-- =========================================================================
local function SpellNameFromID(spellID)
    if type(spellID) ~= "number" or spellID <= 0 then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local si = C_Spell.GetSpellInfo(spellID)
        return si and si.name
    end
    return nil
end

local function SpellNameFromCursor()
    local infoType, info1, _, info3 = GetCursorInfo()
    if not infoType then return nil end

    if infoType == "spell" then
        if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
            local info = C_SpellBook.GetSpellBookItemInfo(info1, Enum.SpellBookSpellBank.Player)
            if info and info.spellID then
                return SpellNameFromID(info.spellID)
            end
        end
        return SpellNameFromID(info1) or SpellNameFromID(info3)

    elseif infoType == "action" then
        local at, aid = GetActionInfo(info1)
        if at == "spell" then
            return SpellNameFromID(aid)
        end
    end

    return nil
end

-- =========================================================================
--  2. KEY / BUTTON HELPERS
-- =========================================================================
local function GetReadableKey(k) return tostring(k or ""):upper() end

-- MOUSE click attribute key builder (SHIFT OK here)
local function GetClickAttrKey(button)
    local prefix = ""
    if IsAltKeyDown()     then prefix = prefix .. "alt-"   end
    if IsControlKeyDown() then prefix = prefix .. "ctrl-"  end
    if IsShiftKeyDown()   then prefix = prefix .. "shift-" end

    local btnID = "type1"
    if button == "RightButton" then
        btnID = "type2"
    elseif button == "MiddleButton" then
        btnID = "type3"
    else
        local n = button:match("Button(%d+)")
        if n then btnID = "type" .. n end
    end

    return prefix .. btnID
end

local function GetReadableClick(attrKey)
    local s = tostring(attrKey or "")
        :gsub("type1","Left")
        :gsub("type2","Right")
        :gsub("type3","Middle")
        :gsub("type(%d+)","Btn%1")
    return s:upper():gsub("-", " + ")
end

local function IsPureModifier(k)
    k = tostring(k or ""):upper()
    return (k == "SHIFT" or k == "CTRL" or k == "ALT")
end

-- For KEY binds: user holds modifiers while pressing key.
local function BuildHeldKeyString(key)
    local prefix = ""
    if IsAltKeyDown()     then prefix = prefix .. "ALT-"  end
    if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
    if IsShiftKeyDown()   then prefix = prefix .. "SHIFT-" end
    return prefix .. tostring(key or ""):upper()
end

local function BuildMacro(spellName)
    local s = tostring(spellName or "")
    if KEY_MOUSEOVER_ONLY then
        return "/cast [@mouseover,help,nodead] " .. s
    end
    return "/cast [@mouseover,help,nodead] " .. s .. "; [help,nodead] " .. s .. "; [@player] " .. s
end

-- =========================================================================
--  3. SECURE OVERLAY SYSTEM (12.0 RESTRICTED SAFE)
-- =========================================================================
-- SetBindingClick in restricted env requires a NAMED click target.
-- Therefore overlays MUST have a unique global name.

local OH_OVERLAY_ID = 0

local function EnsureOverlay(hostFrame)
    if not hostFrame then return nil end
    local existing = overlays[hostFrame]
    if existing then return existing end
    if InCombatLockdown() then pendingWork = true return nil end

    OH_OVERLAY_ID = OH_OVERLAY_ID + 1
    local overlayName = "OpenHealOverlay" .. OH_OVERLAY_ID

    local overlay = CreateFrame(
        "Button",
        overlayName,
        hostFrame,
        "SecureActionButtonTemplate,SecureHandlerEnterLeaveTemplate"
    )

    overlay:SetAllPoints(hostFrame)
    overlay:SetFrameLevel((hostFrame:GetFrameLevel() or 0) + 10)
    overlay:EnableMouse(true)
    overlay:RegisterForClicks("AnyUp", "AnyDown")

    -- Secure enter: bind keys ONLY while hovering this overlay
    overlay:SetAttribute("_onenter", [[
        self:ClearBindings()
        local target = self:GetName()
        if not target or target == "" then return end

        local n = self:GetAttribute("oh_num") or 0
        for i = 1, n do
            local k = self:GetAttribute("oh_key"..i)
            local b = self:GetAttribute("oh_btn"..i)
            if k and b then
                self:SetBindingClick(true, k, target, b)
            end
        end
    ]])

    overlay:SetAttribute("_onleave", [[
        self:ClearBindings()
    ]])

    overlays[hostFrame] = overlay

    -- Let host frames hook overlay clicks/visuals (hostFrame won't receive clicks).
    -- This is NOT secure code; it's a normal callback, safe in 12.0.
    if hostFrame and type(hostFrame.OpenHeal_OnOverlayCreated) == "function" then
        pcall(hostFrame.OpenHeal_OnOverlayCreated, hostFrame, overlay)
    end

    return overlay
end

-- =========================================================================
--  4. APPLY BINDINGS
-- =========================================================================
-- Attributes we set on each overlay last time round, so they can be cleared
-- before re-applying. Without this, deleting a binding left the old
-- type/spell/macrotext attribute on the secure button and the spell kept
-- firing until the next /reload.
local appliedAttrs = setmetatable({}, { __mode = "k" })

local function ClearAppliedAttributes(overlay)
    local prev = appliedAttrs[overlay]
    if not prev then return end
    for attr in pairs(prev) do
        overlay:SetAttribute(attr, nil)
    end
    wipe(prev)
end

local function ApplyToOverlay(overlay, unit)
    if not overlay then return end
    if InCombatLockdown() then pendingWork = true return end

    if unit and unit ~= "" then
        overlay:SetAttribute("unit", unit)
    end

    ClearAppliedAttributes(overlay)

    local applied = appliedAttrs[overlay]
    if not applied then
        applied = {}
        appliedAttrs[overlay] = applied
    end

    local function Set(attr, value)
        overlay:SetAttribute(attr, value)
        applied[attr] = true
    end

    -- Default left click targets (so Blizzard target frame updates)
    -- SHIFT is left alone so it can be used for healing binds (shift-type1 spell)
    overlay:SetAttribute("type1", "target")
    overlay:SetAttribute("spell1", nil)
    overlay:SetAttribute("macrotext1", nil)

    -- 1) CLICK CASTS (mouse) - supports shift/ctrl/alt through attribute keys
    local clicks = ClickDB()
    for attrKey, spellName in pairs(clicks) do
        if spellName and spellName ~= "" then
            local spellAttr = attrKey:gsub("type", "spell") -- shift-type1 -> shift-spell1
            Set(attrKey, "spell")
            Set(spellAttr, spellName)
        end
    end

    -- 2) KEY CASTS (hover keys)
    local keys = KeyDB()

    local i = 0
    for keyStr, spellName in pairs(keys) do
        if spellName and spellName ~= "" then
            i = i + 1

            local cleanKey   = tostring(keyStr):gsub("[^A-Za-z0-9]", "")
            local virtualBtn = "OH_" .. cleanKey .. "_" .. i

            Set("type-" .. virtualBtn, "macro")
            Set("macrotext-" .. virtualBtn, BuildMacro(spellName))

            Set("oh_key"..i, keyStr)
            Set("oh_btn"..i, virtualBtn)
        end
    end

    overlay:SetAttribute("oh_num", i)
end

local function RefreshAll()
    if InCombatLockdown() then
        pendingWork = true
        return
    end

    for hostFrame, unit in pairs(registered) do
        local overlay = EnsureOverlay(hostFrame)
        if overlay then
            ApplyToOverlay(overlay, unit)
        end
    end
end

-- =========================================================================
--  5. UI SYSTEM (Optimized)
-- =========================================================================
local function UpdateList()
    if not listContent then return end

    for _, row in pairs(rowPool) do row:Hide() end

    local data = {}
    for k, v in pairs(ClickDB()) do table.insert(data, { type="CLICK", key=k, spell=v }) end
    for k, v in pairs(KeyDB())   do table.insert(data, { type="KEY",   key=k, spell=v }) end
    table.sort(data, function(a,b) return (a.type..a.key) < (b.type..b.key) end)

    local y = 0
    for idx, item in ipairs(data) do
        local row = rowPool[idx]
        if not row then
            row = CreateFrame("Frame", nil, listContent, "BackdropTemplate")
            row:SetSize(395, 30)
            row:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8x8" })
            row:SetBackdropColor(0.1, 0.1, 0.1, 0.5)

            row.tSpell = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.tSpell:SetPoint("LEFT", 5, 0)

            row.tKey = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.tKey:SetPoint("RIGHT", -30, 0)

            row.btnDel = CreateFrame("Button", nil, row, "UIPanelCloseButton")
            row.btnDel:SetSize(24, 24)
            row.btnDel:SetPoint("RIGHT", 0, 0)

            rowPool[idx] = row
        end

        row:SetPoint("TOPLEFT", 5, y)
        row:Show()

        row.tSpell:SetText(item.spell or "")
        row.tKey:SetText(item.type == "CLICK" and GetReadableClick(item.key) or GetReadableKey(item.key))

        row.btnDel:SetScript("OnClick", function()
            if InCombatLockdown() then OH_Error("Combat error") return end

            if item.type == "CLICK" then
                ClickDB()[item.key] = nil
            else
                KeyDB()[item.key] = nil
            end

            UpdateList()
            RefreshAll()
            OH_Print("Bindings refreshed.")
        end)

        y = y - 32
    end
end

local function EnsureUI()
    if mainFrame then return mainFrame end

    mainFrame = CreateFrame("Frame", "OpenHealFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame:SetSize(460, 520)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame.TitleText:SetText("OpenHeal Config")
    mainFrame:Hide()

    listScroll = CreateFrame("ScrollFrame", nil, mainFrame, "UIPanelScrollFrameTemplate")
    listScroll:SetSize(420, 320)
    listScroll:SetPoint("TOP", 0, -40)

    listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(420, 1000)
    listScroll:SetScrollChild(listContent)

    infoLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoLabel:SetPoint("BOTTOM", 0, 140)
    infoLabel:SetJustifyH("CENTER")
    infoLabel:SetText("")

    local warn = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    warn:SetPoint("BOTTOM", 0, 118)
    warn:SetJustifyH("CENTER")
    warn:SetText("|cffffaa00Warning: Using SHIFT + keyboard may not work for mouseover healing.|r")

    local help = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("BOTTOM", 0, 98)
    help:SetJustifyH("CENTER")
    help:SetText("Drag skill to button. Hold modifier then press desired key. Mouse can be used with no modifier.")

    -- INPUT LISTENER
    inputListener = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    inputListener:SetSize(420, 420)
    inputListener:SetPoint("CENTER")
    inputListener:SetFrameStrata("DIALOG")
    inputListener:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background-Dark" })
    inputListener:Hide()
    inputListener:EnableMouse(true)

    local lText = inputListener:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    lText:SetPoint("CENTER", 0, 20)
    lText:SetText("HOLD MODIFIER + PRESS KEY OR CLICK")

    local keyBox = CreateFrame("EditBox", nil, inputListener)
    keyBox:SetSize(1,1)
    keyBox:SetAutoFocus(false)
    keyBox:EnableKeyboard(true)

    local function SaveBind(bindType, key)
        if InCombatLockdown() then OH_Error("Combat error") return end
        if not pendingSpell or pendingSpell == "" then return end

        if bindType == "CLICK" then
            ClickDB()[key] = pendingSpell
        else
            KeyDB()[key] = pendingSpell
        end

        pendingSpell = nil
        inputListener:Hide()
        keyBox:ClearFocus()
        UpdateList()
        RefreshAll()
        OH_Print("Bindings refreshed.")
    end

    inputListener:SetScript("OnMouseDown", function(_, btn)
        if not pendingSpell then return end
        local k = GetClickAttrKey(btn)
        SaveBind("CLICK", k)
    end)

    keyBox:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then
            pendingSpell = nil
            inputListener:Hide()
            return
        end
        if not pendingSpell or IsPureModifier(key) then return end

        local k = BuildHeldKeyString(key)
        SaveBind("KEY", k)
    end)

    inputListener:SetScript("OnShow", function() keyBox:SetFocus() end)
    inputListener:SetScript("OnHide", function() keyBox:ClearFocus() end)

    -- SPELL PICKER
    spellPicker = CreateFrame("Frame")
    spellPicker:Hide()
    spellPicker:SetScript("OnUpdate", function(self)
        local name = SpellNameFromCursor()
        if name then
            pendingSpell = name
            ClearCursor()
            self:Hide()
            infoLabel:SetText("Selected: "..name..". Now hold modifier and press key, or click.")
            inputListener:Show()
        end
    end)

    -- BUTTONS
    local btnAdd = CreateFrame("Button", nil, mainFrame, "GameMenuButtonTemplate")
    btnAdd:SetSize(220, 40)
    btnAdd:SetPoint("BOTTOMLEFT", 12, 50)
    btnAdd:SetText("Drag skill here!")
    btnAdd:SetScript("OnClick", function()
        if InCombatLockdown() then OH_Error("Can't edit in combat.") return end
        infoLabel:SetText("DRAG A SPELL FROM SPELLBOOK NOW")
        spellPicker:Show()
    end)

    local btnClear = CreateFrame("Button", nil, mainFrame, "GameMenuButtonTemplate")
    btnClear:SetSize(160, 40)
    btnClear:SetPoint("BOTTOMRIGHT", -12, 50)
    btnClear:SetText("Clear All")
    btnClear:SetScript("OnClick", function()
        if InCombatLockdown() then OH_Error("Can't edit in combat.") return end
        wipe(ClickDB()); wipe(KeyDB())
        UpdateList()
        RefreshAll()
        OH_Print("Bindings refreshed.")
    end)

    UpdateList()
    return mainFrame
end

-- =========================================================================
--  6. PUBLIC API
-- =========================================================================
_G.OpenHeal_RegisterFrame = function(frame, unit)
    if not frame or not unit then return end
    registered[frame] = unit
    RefreshAll()
end

_G.OpenHeal_RefreshBindings = function()
    RefreshAll()
    OH_Print("Bindings refreshed.")
end

-- -------------------------------------------------------------------------
-- ns.ClickCast - the binding model, decoupled from the window that used to be
-- the only way to reach it.
--
-- The Settings "Mouseover" tab renders this. Previously that tab held nothing
-- but a button that opened a second, differently-styled window, which is how
-- this addon ended up with five separate surfaces for one set of bindings.
-- -------------------------------------------------------------------------
ns.ClickCast = ns.ClickCast or {}
local CC = ns.ClickCast

-- Sorted list of { kind = "CLICK"|"KEY", key = rawKey, label = readable, spell = name }
function CC:GetBindings()
    local out = {}

    for k, v in pairs(ClickDB()) do
        if v and v ~= "" then
            out[#out + 1] = { kind = "CLICK", key = k, label = GetReadableClick(k), spell = v }
        end
    end

    for k, v in pairs(KeyDB()) do
        if v and v ~= "" then
            out[#out + 1] = { kind = "KEY", key = k, label = GetReadableKey(k), spell = v }
        end
    end

    table.sort(out, function(a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.key < b.key
    end)

    return out
end

function CC:Delete(kind, key)
    if InCombatLockdown() then return false, "Cannot edit bindings in combat." end
    if kind == "CLICK" then
        ClickDB()[key] = nil
    else
        KeyDB()[key] = nil
    end
    RefreshAll()
    return true
end

function CC:ClearAll()
    if InCombatLockdown() then return false, "Cannot edit bindings in combat." end
    wipe(ClickDB())
    wipe(KeyDB())
    RefreshAll()
    return true
end

function CC:Set(kind, key, spellName)
    if InCombatLockdown() then return false, "Cannot edit bindings in combat." end
    if not spellName or spellName == "" then return false, "No spell selected." end

    if kind == "CLICK" then
        ClickDB()[key] = spellName
    else
        KeyDB()[key] = spellName
    end
    RefreshAll()
    return true
end

function CC:Refresh()
    RefreshAll()
end

-- Capture flow, driven by the caller's UI.
--   1. WatchCursor(cb)  - poll for a spell dragged onto the cursor
--   2. caller shows its own "press a key or click" prompt
--   3. KeyFromEvent / ClickFromEvent turn the raw input into a binding key
local cursorWatcher

function CC:WatchCursor(callback)
    if not cursorWatcher then
        cursorWatcher = CreateFrame("Frame")
        cursorWatcher:Hide()
        cursorWatcher:SetScript("OnUpdate", function(self)
            local name = SpellNameFromCursor()
            if name then
                ClearCursor()
                self:Hide()
                if self._cb then self._cb(name) end
            end
        end)
    end
    cursorWatcher._cb = callback
    cursorWatcher:Show()
end

function CC:StopWatchCursor()
    if cursorWatcher then
        cursorWatcher._cb = nil
        cursorWatcher:Hide()
    end
end

function CC:IsPureModifier(key)
    return IsPureModifier(key)
end

-- Raw key + currently-held modifiers -> binding key, e.g. "SHIFT-F"
function CC:KeyFromEvent(key)
    return BuildHeldKeyString(key)
end

-- Mouse button + currently-held modifiers -> attribute key, e.g. "ctrl-type2"
function CC:ClickFromEvent(button)
    return GetClickAttrKey(button)
end

function CC:ReadableClick(attrKey)
    return GetReadableClick(attrKey)
end

-- =========================================================================
--  7. INIT
-- =========================================================================
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        EnsureDB()

        -- DO NOT hook CompactUnitFrame_* in 12.0.
        -- Party/Raid modules must call OpenHeal_RegisterFrame() for their own frames.

        RefreshAll()
        OH_Print("Loaded.")

    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingWork then
            pendingWork = false
            RefreshAll()
            OH_Print("Bindings refreshed.")
        end
    end
end)

-- =========================================================================
--  8. SLASH COMMANDS
-- =========================================================================
-- Binding config used to live in its own BasicFrameTemplateWithInset window
-- here, which meant five separate places could edit or display the same
-- bindings: this window, the settings Mouseover tab, the settings Multi Focus
-- tab, the bind grid viewer, and the focus panel. /openheal now opens the
-- unified settings on the Mouseover tab; the standalone window is only used
-- as a fallback if the settings module failed to load.
local function OpenBindingConfig()
    if ns and ns.Settings and ns.Settings.Open then
        ns.Settings:Open(4)   -- TAB_MOVER
        return true
    end
    return false
end

SLASH_OPENHEAL1 = "/openheal"
SLASH_OPENHEAL2 = "/oh"
SlashCmdList.OPENHEAL = function(msg)
    msg = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "legacy" then
        local f = EnsureUI()
        if f:IsShown() then f:Hide() else f:Show() end
        return
    end

    if not OpenBindingConfig() then
        local f = EnsureUI()
        if f:IsShown() then f:Hide() else f:Show() end
    end
end
