-- OpenHeal/bindview.lua
-- Sleek Grid-based Bind Viewer for OpenHealBindingsDB (Midnight-safe)
-- Grid with always-visible key text + Settings UI to override display key text per spell

-- Take the addon vararg so this file can reach the shared secret-value helpers
-- in core/util.lua. Without it there was no way to tell a secret number from a
-- plain one here, which is exactly how the SetCooldown error storm happened.
local ADDON, ns = ...
ns = _G[ADDON] or ns or {}
_G[ADDON] = ns

OpenHealBindingsDB = OpenHealBindingsDB or {}

-- =========================
-- DB
-- =========================
local function EnsureDB()
    if type(OpenHealBindingsDB.clicks) ~= "table" then OpenHealBindingsDB.clicks = {} end
    if type(OpenHealBindingsDB.keys)   ~= "table" then OpenHealBindingsDB.keys   = {} end
    if type(OpenHealBindingsDB.bindsViewer) ~= "table" then
        OpenHealBindingsDB.bindsViewer = { w = 240, x = nil, y = nil, shown = false }
    end
    if type(OpenHealBindingsDB.bindsViewerOverrides) ~= "table" then
        -- overrides[spellKey] = "TEXT"
        OpenHealBindingsDB.bindsViewerOverrides = {}
    end
    if type(OpenHealBindingsDB.bindsViewerSettings) ~= "table" then
        OpenHealBindingsDB.bindsViewerSettings = { w = 420, h = 360, x = nil, y = nil, shown = false }
    end
end

local function ClickDB() EnsureDB(); return OpenHealBindingsDB.clicks end
local function KeyDB()   EnsureDB(); return OpenHealBindingsDB.keys end
local function ViewDB()  EnsureDB(); return OpenHealBindingsDB.bindsViewer end
local function OvrDB()   EnsureDB(); return OpenHealBindingsDB.bindsViewerOverrides end
local function SetDB()   EnsureDB(); return OpenHealBindingsDB.bindsViewerSettings end

-- =========================
-- Helpers
-- =========================
local function GetReadableKey(k)
    return tostring(k or ""):upper()
end

local function GetReadableClick(attrKey)
    local s = tostring(attrKey or "")
        :gsub("type1","L")
        :gsub("type2","R")
        :gsub("type3","M")
        :gsub("type(%d+)","B%1")
    return s:upper():gsub("-", "")
end

local function GetSpellIcon(spellName)
    if not spellName or spellName == "" then return 134400 end
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellName) or 134400
    elseif GetSpellTexture then
        return GetSpellTexture(spellName) or 134400
    end
    return 134400
end

local function GetSpellNameSafe(spell)
    if not spell or spell == "" then return "" end
    local id = tonumber(spell)
    if id and C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(id) or tostring(spell)
    end
    if C_Spell and C_Spell.GetSpellName then
        -- spell identifier / name might resolve
        return C_Spell.GetSpellName(spell) or tostring(spell)
    end
    if GetSpellInfo then
        local name = GetSpellInfo(spell)
        return name or tostring(spell)
    end
    return tostring(spell)
end

local function GetSpellKey(spell)
    -- Stable key in overrides table. Prefer numeric ID if possible.
    local n = tonumber(spell)
    if n then return tostring(n) end

    -- If API can resolve ID, use it
    if C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
        local id = C_Spell.GetSpellIDForSpellIdentifier(spell)
        if id then return tostring(id) end
    end

    -- Fallback to name string
    return tostring(spell)
end

local function ShowSpellTooltip(frame, spell)
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    local spellID = tonumber(spell)

    if spellID then
        GameTooltip:SetSpellByID(spellID)
    else
        if C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
            local id = C_Spell.GetSpellIDForSpellIdentifier(spell)
            if id then
                GameTooltip:SetSpellByID(id)
            else
                GameTooltip:SetText(tostring(spell), 1, 1, 1)
            end
        else
            GameTooltip:SetText(tostring(spell), 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

-- =========================
-- UI Constants & State
-- =========================
local ICON_SIZE = 36
local GAP = 4
local PADDING = 10
local HEADER_H = 10 -- slim drag bar (no text)

local UI = {
    frame = nil,
    buttons = {},
    data = {},
    _sizing = false,

    settings = nil,
    settingsRows = {},
    _settingsSizing = false,
}

-- =========================
-- Cooldown (12.0 SAFE)
-- =========================
local function GetSpellCooldownInfo(spell)
    if C_Spell and C_Spell.GetSpellCooldown then
        local cdInfo = C_Spell.GetSpellCooldown(spell)
        if cdInfo then
            return cdInfo.startTime, cdInfo.duration, cdInfo.isEnabled
        end
    elseif GetSpellCooldown then
        return GetSpellCooldown(spell)
    end
    return nil, nil, nil
end

-- ---------------------------------------------------------------------------
-- THE BUG THIS FIXES:
--   The old guard was `if type(start) == "number" and type(duration) == "number"`.
--   type() returns "number" for a SECRET number too, so that check passed and
--   SetCooldown was handed secret values, which it refuses during tainted
--   execution. Every SPELL_UPDATE_COOLDOWN fired the error again - hundreds of
--   times per session.
--
--   type() is not a secrecy test. issecretvalue() is.
--
-- Order of preference:
--   1. Duration object      - built for secret values, no unwrapping needed
--   2. Cooldown info struct - the engine reads the secrets itself
--   3. Plain numbers        - only when provably not secret
--   4. Clear the swirl      - better than an error every tick
--
-- Every call is wrapped: a future API shape change must degrade to "no swirl",
-- never to an error storm.
-- ---------------------------------------------------------------------------
local function IsSecret(v)
    local U = ns and ns.UnitUtil
    if U and U.IsSecretValue then
        return U.IsSecretValue(v)
    end
    local f = _G.issecretvalue
    if type(f) == "function" then
        local ok, ret = pcall(f, v)
        return (ok and ret) and true or false
    end
    return false
end

local function ApplyCooldown(btn, spell)
    local cd = btn and btn.cd
    if not cd then return end

    local function Clear()
        if cd.Clear then
            pcall(cd.Clear, cd)
        else
            pcall(cd.SetCooldown, cd, 0, 0)
        end
    end

    -- 1) Duration object
    if cd.SetCooldownFromDurationObject and C_Spell then
        local getter = C_Spell.GetSpellCooldownDuration
                    or C_Spell.GetSpellCooldownDurationObject
        if getter then
            local ok, durObj = pcall(getter, spell)
            if ok and durObj then
                if pcall(cd.SetCooldownFromDurationObject, cd, durObj, true) then
                    return
                end
            end
        end
    end

    -- 2) Cooldown info struct
    if cd.SetCooldownFromCooldownInfo and C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spell)
        if ok and info then
            if pcall(cd.SetCooldownFromCooldownInfo, cd, info) then
                return
            end
        end
    end

    -- 3) Plain numbers only
    local okInfo, start, duration = pcall(GetSpellCooldownInfo, spell)
    if okInfo
        and start ~= nil and duration ~= nil
        and not IsSecret(start) and not IsSecret(duration)
        and type(start) == "number" and type(duration) == "number"
    then
        if pcall(cd.SetCooldown, cd, start, duration) then
            return
        end
    end

    -- 4) Give up quietly
    Clear()
end

-- =========================
-- Data build
-- =========================
local function BuildData()
    local data = {}
    for k, v in pairs(ClickDB()) do
        if v and v ~= "" then
            data[#data+1] = {
                keyText = GetReadableClick(k),
                spell = tostring(v),
            }
        end
    end
    for k, v in pairs(KeyDB()) do
        if v and v ~= "" then
            data[#data+1] = {
                keyText = GetReadableKey(k),
                spell = tostring(v),
            }
        end
    end

    table.sort(data, function(a,b)
        return tostring(a.spell) < tostring(b.spell)
    end)

    -- enrich
    for i = 1, #data do
        local item = data[i]
        item.spellKey  = GetSpellKey(item.spell)
        item.spellName = GetSpellNameSafe(item.spell)
    end

    return data
end

local function GetDisplayKeyText(item)
    local ovr = OvrDB()
    local k = item and item.spellKey
    if k and ovr[k] and ovr[k] ~= "" then
        return tostring(ovr[k])
    end
    return tostring(item and item.keyText or "")
end

-- =========================
-- Grid Buttons
-- =========================
local function CreateGridButton(parent)
    local btn = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    btn:SetBackdropBorderColor(0, 0, 0, 0.8)

    btn.icon = btn:CreateTexture(nil, "BACKGROUND")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cd:SetAllPoints()
    btn.cd:SetDrawEdge(false)
    btn.cd:SetHideCountdownNumbers(false)

    -- Always-visible key text (top layer)
    btn.bindText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    btn.bindText:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.bindText:SetJustifyH("RIGHT")
    btn.bindText:SetTextColor(1, 1, 1)
    btn.bindText:SetText("")

    btn:EnableMouse(true)
    btn:SetScript("OnEnter", function(self)
        if self.spell then ShowSpellTooltip(self, self.spell) end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

local function UpdateCooldowns()
    if not UI.frame or not UI.frame:IsShown() then return end
    for i = 1, #UI.data do
        local btn = UI.buttons[i]
        local item = UI.data[i]
        if btn and btn:IsShown() and item and item.spell then
            ApplyCooldown(btn, item.spell)
            -- keep keybind text always visible
            btn.bindText:SetText(GetDisplayKeyText(item))
        end
    end
end

local function LayoutGrid()
    if not UI.frame then return end

    local contentWidth = UI.frame:GetWidth() - (PADDING * 2)
    local cols = math.floor((contentWidth + GAP) / (ICON_SIZE + GAP))
    if cols < 1 then cols = 1 end

    local rows = math.ceil(#UI.data / cols)
    local frameHeight = HEADER_H + PADDING + (rows * ICON_SIZE) + ((rows - 1) * GAP) + PADDING
    UI.frame:SetHeight(math.max(HEADER_H + PADDING * 2 + ICON_SIZE, frameHeight))

    for i = 1, #UI.data do
        local btn = UI.buttons[i]
        if not btn then
            btn = CreateGridButton(UI.frame)
            UI.buttons[i] = btn
        end

        local item = UI.data[i]
        btn.spell = item.spell
        btn.icon:SetTexture(GetSpellIcon(item.spell))

        -- Always-visible key text (override aware)
        btn.bindText:SetText(GetDisplayKeyText(item))

        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)

        local x = PADDING + (col * (ICON_SIZE + GAP))
        local y = -HEADER_H - PADDING - (row * (ICON_SIZE + GAP))

        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", UI.frame, "TOPLEFT", x, y)
        btn:Show()
    end

    for i = #UI.data + 1, #UI.buttons do
        UI.buttons[i]:Hide()
    end

    UpdateCooldowns()
end

local function RefreshData()
    UI.data = BuildData()
    LayoutGrid()
    if UI.settings and UI.settings:IsShown() then
        -- keep settings list synced
        if UI.BuildSettingsRows then UI.BuildSettingsRows() end
    end
end

-- =========================
-- Save/Apply state (Grid)
-- =========================
local function SaveState()
    if not UI.frame then return end
    local db = ViewDB()
    db.w = math.floor(UI.frame:GetWidth() + 0.5)
    db.shown = UI.frame:IsShown() and true or false
    local cx, cy = UI.frame:GetCenter()
    if cx and cy then
        db.x = math.floor(cx + 0.5)
        db.y = math.floor(cy + 0.5)
    end
end

local function ApplyState()
    if not UI.frame then return end
    local db = ViewDB()
    UI.frame:SetWidth(math.max(100, db.w or 240))

    UI.frame:ClearAllPoints()
    if db.x and db.y then
        UI.frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.x, db.y)
    else
        UI.frame:SetPoint("CENTER")
    end
end

-- =========================
-- Settings UI
-- =========================
local function SaveSettingsState()
    if not UI.settings then return end
    local db = SetDB()
    db.w = math.floor(UI.settings:GetWidth() + 0.5)
    db.h = math.floor(UI.settings:GetHeight() + 0.5)
    db.shown = UI.settings:IsShown() and true or false
    local cx, cy = UI.settings:GetCenter()
    if cx and cy then
        db.x = math.floor(cx + 0.5)
        db.y = math.floor(cy + 0.5)
    end
end

local function ApplySettingsState()
    if not UI.settings then return end
    local db = SetDB()
    UI.settings:SetSize(math.max(260, db.w or 420), math.max(220, db.h or 360))
    UI.settings:ClearAllPoints()
    if db.x and db.y then
        UI.settings:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.x, db.y)
    else
        UI.settings:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
    end
end

local function CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(28)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", 6, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetJustifyH("LEFT")

    row.detected = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detected:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
    row.detected:SetJustifyH("LEFT")

    row.edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.edit:SetAutoFocus(false)
    row.edit:SetHeight(20)
    row.edit:SetPoint("RIGHT", -8, 0)
    row.edit:SetWidth(110)

    row.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    row.edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if self._spell then ShowSpellTooltip(self, self._spell) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row
end

function UI.BuildSettingsRows()
    if not UI.settings or not UI.settings.scrollChild then return end

    local child = UI.settings.scrollChild
    local rows = UI.settingsRows
    local data = UI.data or {}

    local y = -6
    local rowH = 28
    local ovr = OvrDB()

    for i = 1, #data do
        local item = data[i]
        local row = rows[i]
        if not row then
            row = CreateRow(child)
            rows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", 0, y)
        y = y - rowH

        row._spell = item.spell
        row._spellKey = item.spellKey

        row.icon:SetTexture(GetSpellIcon(item.spell))
        row.name:SetText(item.spellName ~= "" and item.spellName or tostring(item.spell))

        -- show detected bind (always)
        row.detected:SetText("[" .. tostring(item.keyText or "") .. "]")

        -- fill override
        local cur = ovr[item.spellKey]
        if cur == nil then cur = "" end
        row.edit:SetText(tostring(cur))

        row.edit:SetScript("OnTextChanged", function(edit)
            if edit:IsUserInput() then
                local txt = edit:GetText() or ""
                -- store override (empty string clears)
                if txt == "" then
                    ovr[item.spellKey] = nil
                else
                    ovr[item.spellKey] = txt
                end

                -- live update grid text
                if UI.frame and UI.frame:IsShown() then
                    LayoutGrid()
                end
            end
        end)

        row:Show()
    end

    for i = #data + 1, #rows do
        rows[i]:Hide()
    end

    -- extend scroll child height
    child:SetHeight(math.max(1, (#data * rowH) + 12))
end

local function EnsureSettingsUI()
    if UI.settings then return UI.settings end
    EnsureDB()

    local f = CreateFrame("Frame", "OpenHealBindsSettings", UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1 })
    f:SetBackdropColor(0.04, 0.04, 0.04, 0.90)
    f:SetBackdropBorderColor(0, 0, 0, 1)

    -- Dragging (whole frame)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveSettingsState()
    end)

    -- Scroll
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetPoint("TOPLEFT")
    child:SetPoint("TOPRIGHT")
    child:SetHeight(1)

    scroll:SetScrollChild(child)
    f.scrollChild = child
    f.scroll = scroll

    -- Resize (both directions)
    f:SetResizable(true)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:EnableMouse(true)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    grip:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then
            UI._settingsSizing = true
            f:StartSizing("BOTTOMRIGHT")
        end
    end)

    grip:SetScript("OnMouseUp", function(_, btn)
        if btn == "LeftButton" then
            f:StopMovingOrSizing()
            UI._settingsSizing = false
            SaveSettingsState()
        end
    end)

    f:SetScript("OnSizeChanged", function()
        if UI._settingsSizing then
            -- nothing special; scroll auto
        end
    end)

    f:SetScript("OnShow", function()
        RefreshData()
        UI.BuildSettingsRows()
    end)

    UI.settings = f
    ApplySettingsState()
    f:Hide()

    return f
end

-- =========================
-- Main UI
-- =========================
local function EnsureUI()
    if UI.frame then return UI.frame end
    EnsureDB()

    local f = CreateFrame("Frame", "OpenHealBindsGrid", UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1 })
    f:SetBackdropColor(0.04, 0.04, 0.04, 0.85)
    f:SetBackdropBorderColor(0, 0, 0, 1)

    -- Dragging on a slim top bar (no text, no close)
    local dragBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    dragBar:SetPoint("TOPLEFT", 1, -1)
    dragBar:SetPoint("TOPRIGHT", -1, -1)
    dragBar:SetHeight(HEADER_H)
    dragBar:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8x8" })
    dragBar:SetBackdropColor(0.08, 0.08, 0.08, 0.70)
    dragBar:EnableMouse(true)

    f:SetMovable(true)
    f:EnableMouse(true)

    dragBar:RegisterForDrag("LeftButton")
    dragBar:SetScript("OnDragStart", function() f:StartMoving() end)
    dragBar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        SaveState()
    end)

    -- Horizontal Resize only (Height auto)
    f:SetResizable(true)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:EnableMouse(true)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    grip:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then
            UI._sizing = true
            f:StartSizing("BOTTOMRIGHT")
        end
    end)

    grip:SetScript("OnMouseUp", function(_, btn)
        if btn == "LeftButton" then
            f:StopMovingOrSizing()
            UI._sizing = false
            SaveState()
            LayoutGrid()
        end
    end)

    f:SetScript("OnSizeChanged", function()
        if UI._sizing then LayoutGrid() end
    end)

    -- Cooldown updates
    f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    f:SetScript("OnEvent", function(_, event)
        if event == "SPELL_UPDATE_COOLDOWN" then
            UpdateCooldowns()
        end
    end)

    f:SetScript("OnShow", function()
        RefreshData()
    end)

    f:SetScript("OnHide", function()
        SaveState()
    end)

    UI.frame = f
    ApplyState()
    f:Hide()

    return f
end

-- =========================
-- Public API + Slash
-- =========================
_G.OpenHeal_BindsUI = _G.OpenHeal_BindsUI or {}

function _G.OpenHeal_BindsUI:Toggle()
    local f = EnsureUI()
    if f:IsShown() then f:Hide() else f:Show() end
    SaveState()
end

function _G.OpenHeal_BindsUI:ToggleSettings()
    local s = EnsureSettingsUI()
    if s:IsShown() then s:Hide() else s:Show() end
    SaveSettingsState()
end

function _G.OpenHeal_BindsUI:Refresh()
    if UI.frame and UI.frame:IsShown() then
        RefreshData()
    else
        UI.data = BuildData()
    end
    if UI.settings and UI.settings:IsShown() then
        UI.BuildSettingsRows()
    end
end

-- /ohbinds          -> toggle grid
-- /ohbinds config   -> toggle settings
SLASH_OPENHEALBINDS1 = "/ohbinds"
SLASH_OPENHEALBINDS2 = "/openhealbinds"
SlashCmdList.OPENHEALBINDS = function(msg)
    msg = tostring(msg or ""):lower()
    if msg == "config" or msg == "settings" or msg == "set" then
        _G.OpenHeal_BindsUI:ToggleSettings()
    else
        _G.OpenHeal_BindsUI:Toggle()
    end
end

-- Boot
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    EnsureDB()

    -- restore shown states
    local v = ViewDB()
    if v.shown then
        EnsureUI():Show()
    end

    local s = SetDB()
    if s.shown then
        EnsureSettingsUI():Show()
    end
end)
