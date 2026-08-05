-- ============================================================================
-- settings.lua (OpenHeal)
-- Unified Settings UI with Tabs: Party + Raid + Mouseover + Multi Focus + Profiles
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns
_G[ADDON] = ns

ns.Settings = ns.Settings or {}
local S = ns.Settings

local TEX     = "Interface\\Buttons\\WHITE8X8"
local POWER_H = 3
local NAME_H  = 14

local TAB_PARTY    = 1
local TAB_RAID     = 2
local TAB_STYLE    = 3
local TAB_MOVER    = 4
local TAB_BINDVIEW = 5
local TAB_PROFILES = 6
local TAB_COUNT    = 6

-- ------------------------------------------------------------
-- helpers & DB
-- ------------------------------------------------------------
local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function SafeFloor(v)
    v = tonumber(v) or 0
    return math.floor(v + 0.5)
end

local function SafeColumns(v)
    v = tonumber(v) or 8
    v = math.floor(v + 0.5)
    if v < 1 then v = 1 end
    if v > 8 then v = 8 end
    return v
end

local function GetPartyDB()
    if ns and ns.GetPartyDB then return ns:GetPartyDB() end
    ns._partyFallbackDB = ns._partyFallbackDB or {}
    return ns._partyFallbackDB
end

local function GetRaidDB()
    if ns and ns.GetRaidDB then return ns:GetRaidDB() end
    ns._raidFallbackDB = ns._raidFallbackDB or {}
    return ns._raidFallbackDB
end

local DEFAULT_BINDVIEW_DB = {
    enabled = true,
    locked = false,
    showMover = true,
    point = "CENTER",
    relPoint = "CENTER",
    x = -420,
    y = 40,
    w = 180,
    h = 30,
    spacing = 6,
    orientation = "VERTICAL",
    showPower = false,
    classColor = true,
}

local function DeepCopyDefaults(dst, src)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = DeepCopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

local function GetBindViewDB()
    if ns.GetBindViewDB then
        return ns:GetBindViewDB()
    end
    _G.OpenHealDB = _G.OpenHealDB or {}
    _G.OpenHealDB.bindview = _G.OpenHealDB.bindview or {}
    _G.OpenHealDB.bindview = DeepCopyDefaults(_G.OpenHealDB.bindview, DEFAULT_BINDVIEW_DB)
    return _G.OpenHealDB.bindview
end

local function CallPartyRebuild()
    if ns and ns.RequestPartyRebuild then
        ns:RequestPartyRebuild()
    elseif ns and ns.Party and ns.Party.Build then
        ns.Party:Build()
    end
end

local function CallRaidRebuild()
    if ns and ns.RequestRaidRebuild then
        ns:RequestRaidRebuild()
    elseif ns and ns.Raid and ns.Raid.Build then
        ns.Raid:Build()
    end
end

local function CallBindViewRebuild()
    local BV = ns.BindView
    if not BV then return end
    if BV.Build then BV:Build() end
end

-- ============================================================================
-- MODERN UI COMPONENT FACTORIES
-- ============================================================================
local function ApplyMainBackdrop(frame)
    frame:SetBackdrop({ bgFile=TEX, edgeFile=TEX, edgeSize=1 })
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.98)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
end

local function ApplySoftPanel(frame)
    frame:SetBackdrop({ bgFile=TEX, edgeFile=TEX, edgeSize=1 })
    frame:SetBackdropColor(0.15, 0.15, 0.15, 0.5)
    frame:SetBackdropBorderColor(0, 0, 0, 0.5)
end

local function CreateTitleBar(parent, title)
    local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(32)
    bar:SetBackdrop({ bgFile=TEX })
    bar:SetBackdropColor(0.15, 0.15, 0.15, 1)

    local line = bar:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    line:SetColorTexture(0, 0, 0, 1)

    local t = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("CENTER", 0, 0)
    t:SetText(title or "Settings")
    t:SetTextColor(1, 0.82, 0, 1)

    return bar
end

local function CreateSectionTitle(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetTextColor(1, 0.82, 0, 1)
    fs:SetText(text or "")
    return fs
end

local function CreateModernButton(parent, text, x, y, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(w or 120, h or 24)
    b:SetBackdrop({ bgFile=TEX, edgeFile=TEX, edgeSize=1 })
    b:SetBackdropColor(0.2, 0.2, 0.2, 1)
    b:SetBackdropBorderColor(0, 0, 0, 1)

    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", 0, 0)
    fs:SetText(text or "Button")
    fs:SetTextColor(0.9, 0.9, 0.9, 1)

    b:SetScript("OnEnter", function() 
        b:SetBackdropColor(0.28, 0.28, 0.28, 1) 
        fs:SetTextColor(1, 1, 1, 1)
    end)
    b:SetScript("OnLeave", function() 
        b:SetBackdropColor(0.2, 0.2, 0.2, 1) 
        fs:SetTextColor(0.9, 0.9, 0.9, 1)
    end)
    b:SetScript("OnMouseDown", function() b:SetBackdropColor(0.15, 0.15, 0.15, 1) end)
    b:SetScript("OnMouseUp", function() b:SetBackdropColor(0.28, 0.28, 0.28, 1) end)
    
    b:SetScript("OnClick", function() if onClick then onClick() end end)
    return b
end

local function CreateModernCheck(parent, label, x, y, get, set, onChanged, combatLock)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(14, 14)
    b:SetBackdrop({ bgFile=TEX, edgeFile=TEX, edgeSize=1 })
    b:SetBackdropColor(0.1, 0.1, 0.1, 1)
    b:SetBackdropBorderColor(0, 0, 0, 1)

    local inner = b:CreateTexture(nil, "OVERLAY")
    inner:SetPoint("CENTER", 0, 0)
    inner:SetSize(8, 8)
    inner:SetColorTexture(1, 0.82, 0, 1)
    inner:Hide()

    local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", b, "RIGHT", 8, 0)
    text:SetText(label or "")
    text:SetTextColor(0.85, 0.85, 0.85, 1)

    local function UpdateVisuals()
        if get() then inner:Show() else inner:Hide() end
    end

    b:SetScript("OnEnter", function() b:SetBackdropColor(0.18, 0.18, 0.18, 1) end)
    b:SetScript("OnLeave", function() b:SetBackdropColor(0.1, 0.1, 0.1, 1) end)

    b:SetScript("OnClick", function()
        if combatLock and InCombat() then
            UpdateVisuals()
            return
        end
        local current = get()
        set(not current)
        UpdateVisuals()
        if onChanged then onChanged() end
    end)

    b.Refresh = UpdateVisuals
    b:Refresh()
    return b
end

local function CreateModernSlider(parent, labelText, x, y, w, minv, maxv, step, get, set, onChanged, combatLock, decimals)
    local wrapper = CreateFrame("Frame", nil, parent)
    wrapper:SetPoint("TOPLEFT", x, y)
    wrapper:SetSize(w or 240, 32)

    local text = wrapper:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetText(labelText or "")
    text:SetTextColor(0.85, 0.85, 0.85, 1)

    local valText = wrapper:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valText:SetPoint("TOPRIGHT", 0, 0)
    valText:SetText("")

    local s = CreateFrame("Slider", nil, wrapper)
    s:SetPoint("BOTTOMLEFT", 0, 0)
    s:SetPoint("BOTTOMRIGHT", 0, 0)
    s:SetHeight(8)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(minv, maxv)
    s:SetValueStep(step or 1)
    s:SetObeyStepOnDrag(true)

    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0.15, 0.15, 0.15, 1)

    local progress = s:CreateTexture(nil, "ARTWORK")
    progress:SetPoint("LEFT", track, "LEFT")
    progress:SetPoint("BOTTOM", track, "BOTTOM")
    progress:SetHeight(8)
    progress:SetColorTexture(1, 0.82, 0, 1) 

    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(8, 16)
    thumb:SetColorTexture(0.8, 0.8, 0.8, 1)
    s:SetThumbTexture(thumb)

    -- `decimals` is optional. Without it the slider snaps to whole numbers,
    -- which is what almost every setting here wants. Fractional settings
    -- (smoothing rate, range alpha) pass a precision so they are not floored
    -- to 0 or 1 the moment the user touches them.
    local places = tonumber(decimals) or 0
    local quantum = 10 ^ places

    local function Quantize(v)
        if places <= 0 then return SafeFloor(v) end
        return math.floor((tonumber(v) or 0) * quantum + 0.5) / quantum
    end

    local function UpdateVisuals(val)
        local percent = (val - minv) / (maxv - minv)
        if percent < 0 then percent = 0 end
        if percent > 1 then percent = 1 end

        progress:SetWidth(math.max(0.001, (w or 240) * percent))

        if places > 0 then
            valText:SetText(string.format("%." .. places .. "f", val))
        else
            valText:SetText(tostring(math.floor(val + 0.5)))
        end
    end

    s._ignore = false
    s._userChange = false

    s:SetScript("OnValueChanged", function(self, v)
        if s._ignore then return end
        v = Quantize(v)

        UpdateVisuals(v)

        if not s._userChange then return end
        if combatLock and InCombat() then return end
        
        set(v)
    end)

    s:SetScript("OnMouseDown", function()
        s._userChange = true
    end)

    s:SetScript("OnMouseUp", function()
        s._userChange = false
        
        if combatLock and InCombat() then
            s._ignore = true
            local cur = get() or minv
            s:SetValue(cur)
            UpdateVisuals(cur)
            s._ignore = false
            return
        end
        
        if onChanged then onChanged() end
    end)

    s:SetScript("OnEnter", function()
        thumb:SetColorTexture(1, 1, 1, 1)
    end)
    s:SetScript("OnLeave", function()
        thumb:SetColorTexture(0.8, 0.8, 0.8, 1)
    end)

    wrapper.Refresh = function()
        s._ignore = true
        s._userChange = false
        local cur = get() or minv
        s:SetValue(cur)
        UpdateVisuals(cur)
        s._ignore = false
    end

    wrapper.slider = s
    UpdateVisuals(get() or minv) 

    return wrapper
end

local function CreateModernDropdown(parent, label, x, y, width, items, get, set, onChanged, combatLock)
    local wrapper = CreateFrame("Frame", nil, parent)
    wrapper:SetPoint("TOPLEFT", x, y)
    wrapper:SetSize(width or 180, 42)

    local text = wrapper:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetText(label or "")
    text:SetTextColor(0.85, 0.85, 0.85, 1)

    local btn = CreateFrame("Button", nil, wrapper, "BackdropTemplate")
    btn:SetPoint("BOTTOMLEFT", 0, 0)
    btn:SetSize(width or 180, 22)
    btn:SetBackdrop({ bgFile=TEX, edgeFile=TEX, edgeSize=1 })
    btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
    btn:SetBackdropBorderColor(0, 0, 0, 1)

    local valText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valText:SetPoint("LEFT", 6, 0)
    valText:SetJustifyH("LEFT")

    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetText("V")
    arrow:SetTextColor(1, 0.82, 0)

    local list = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    list:SetBackdrop({ bgFile=TEX, edgeFile=TEX, edgeSize=1 })
    list:SetBackdropColor(0.12, 0.12, 0.12, 0.98)
    list:SetBackdropBorderColor(0, 0, 0, 1)
    list:SetFrameStrata("TOOLTIP")
    list:Hide()

    wrapper.buttons = {}

    local function RebuildList()
        list:SetSize(width or 180, (#wrapper.items * 20) + 4)
        
        for _, b in ipairs(wrapper.buttons) do
            b:Hide()
        end

        for i, it in ipairs(wrapper.items) do
            local b = wrapper.buttons[i]
            if not b then
                b = CreateFrame("Button", nil, list, "BackdropTemplate")
                b:SetSize((width or 180) - 4, 20)
                b:SetBackdrop({ bgFile=TEX })
                b:SetBackdropColor(0,0,0,0)
                
                local bt = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                bt:SetPoint("LEFT", 6, 0)
                b.textString = bt

                b:SetScript("OnEnter", function() b:SetBackdropColor(1, 1, 1, 0.1) end)
                b:SetScript("OnLeave", function() b:SetBackdropColor(0, 0, 0, 0) end)
                
                wrapper.buttons[i] = b
            end
            
            b:SetPoint("TOP", 0, -2 - ((i-1)*20))
            b.textString:SetText(it.text)
            
            b:SetScript("OnClick", function()
                if combatLock and InCombat() then return end
                set(it.value)
                valText:SetText(it.text)
                list:Hide()
                if onChanged then onChanged() end
            end)
            
            b:Show()
        end
    end

    wrapper.items = items
    RebuildList()

    btn:SetScript("OnClick", function()
        if list:IsShown() then list:Hide() else list:Show() end
    end)

    wrapper.Refresh = function()
        local v = get()
        local txt = "Select..."
        for _, it in ipairs(wrapper.items) do
            if it.value == v then txt = it.text; break end
        end
        valText:SetText(txt)
        RebuildList()
    end

    wrapper:Refresh()
    return wrapper
end

-- ============================================================================
-- STABLE COMMAND EXECUTION
-- ============================================================================
local function ExecuteSlash(command)
    if InCombat() then return end
    if type(command) ~= "string" or command == "" then return end
    
    if command:sub(1, 1) ~= "/" then command = "/" .. command end
    local lowerCmd = command:lower()

    for k, v in pairs(_G) do
        if type(k) == "string" and k:sub(1, 6) == "SLASH_" then
            if type(v) == "string" and v:lower() == lowerCmd then
                local baseName = k:match("^SLASH_(.-)%d+$")
                if baseName and _G.SlashCmdList[baseName] then
                    _G.SlashCmdList[baseName]("")
                    return
                end
            end
        end
    end

    if ChatFrame_OpenChat then
        ChatFrame_OpenChat(command)
    end
end

local function RunOpenHealSlash()
    if _G.SlashCmdList and _G.SlashCmdList.OPENHEAL then
        _G.SlashCmdList.OPENHEAL("")
        return
    end
end

local function ParseSpellID(text)
    if not text or text == "" then return nil end
    local id = tostring(text):match("Hspell:(%d+)")
    if not id then id = tostring(text):match("spell:(%d+)") end
    if not id then id = tostring(text):match("(%d+)") end
    id = tonumber(id)
    if id and id > 0 then return id end
    return nil
end

local function GetUIStateDB()
    local db = GetPartyDB()
    db._settingsUI = db._settingsUI or {}
    return db._settingsUI
end

local function ApplyMainPos(frame)
    local sdb = GetUIStateDB()
    if not sdb.point then return end
    frame:ClearAllPoints()
    frame:SetPoint(sdb.point or "CENTER", UIParent, sdb.relPoint or "CENTER", sdb.x or 0, sdb.y or 0)
end

local function SaveMainPos(frame)
    local sdb = GetUIStateDB()
    local p, _, rp, x, y = frame:GetPoint()
    sdb.point = p or "CENTER"
    sdb.relPoint = rp or "CENTER"
    sdb.x = SafeFloor(x or 0)
    sdb.y = SafeFloor(y or 0)
end

-- ============================================================================
-- MODERN TABS
-- ============================================================================
local function CreateModernTab(parent, text, width)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 120, 26)
    
    btn:SetBackdrop({ bgFile = TEX })
    btn:SetBackdropColor(0, 0, 0, 0)
    
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    
    local line = btn:CreateTexture(nil, "OVERLAY")
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetHeight(2)
    line:SetColorTexture(1, 0.82, 0, 1) 
    line:Hide()
    btn.activeLine = line
    
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER", 0, 1)
    fs:SetText(text)
    btn.fs = fs
    
    return btn
end

local function Tab_SetSelected(btn, selected)
    btn._selected = selected and true or false
    
    if btn._selected then
        btn.fs:SetTextColor(1, 0.82, 0, 1)
        btn.activeLine:Show()
        btn:SetBackdropColor(1, 1, 1, 0.08)
    else
        btn.fs:SetTextColor(0.65, 0.65, 0.65, 1)
        btn.activeLine:Hide()
        btn:SetBackdropColor(0, 0, 0, 0)
    end
end

-- ============================================================================
-- IMPORTANT lists (baseline presets)
-- ============================================================================
-- The preview must resolve its icons exactly the way the live frames do,
-- otherwise the settings panel shows you one thing and the game shows another.
-- Both now go through ns.AuraFilters.
local function AF()
    return ns.AuraFilters
end

local function ImportantFriendly()
    local af = AF()
    return af and af:GetList("FRIENDLYBUFFS") or {}
end

local function ImportantDebuffs()
    local af = AF()
    return af and af:GetList("DEBUFFS") or {}
end

local function EnsureAuraDB(db)
    db.fbuff = db.fbuff or {}
    db.debuff = db.debuff or {}

    local fb = db.fbuff
    if fb.enabled == nil then fb.enabled = true end
    if fb.mode == nil then fb.mode = "IMPORTANT" end 
    if fb.onlyMine == nil then fb.onlyMine = true end
    if fb.maxIcons == nil then fb.maxIcons = 4 end
    if fb.size == nil then fb.size = 14 end
    if fb.showTimers == nil then fb.showTimers = true end
    if fb.showStacks == nil then fb.showStacks = true end
    fb.custom = fb.custom or {}  

    local dbf = db.debuff
    if dbf.enabled == nil then dbf.enabled = true end
    if dbf.mode == nil then dbf.mode = "IMPORTANT" end 
    if dbf.maxIcons == nil then dbf.maxIcons = 3 end
    if dbf.size == nil then dbf.size = 14 end
    if dbf.customOnlyDispellable == nil then dbf.customOnlyDispellable = false end
    dbf.custom = dbf.custom or {} 
end

-- which = "FRIENDLYBUFFS" | "DEBUFFS"
local function BuildListFromMode(which, mode, customTable, importantList)
    local af = AF()
    if af and af.ResolveList then
        local list = af:ResolveList(which, { mode = mode, custom = customTable })
        -- mode "ALL" has no whitelist; the preview has nothing real to show,
        -- so fall back to the curated preset just for the mock icons.
        if list == nil then return importantList or {} end
        return list
    end

    if mode == "OFF" then return {} end
    if mode == "CUSTOM" then
        local out = {}
        for spellID, enabled in pairs(customTable or {}) do
            if enabled then out[#out+1] = tonumber(spellID) end
        end
        table.sort(out)
        return out
    end

    local out = {}
    for i = 1, #(importantList or {}) do out[#out+1] = importantList[i] end
    return out
end

local function CreateModernSpellListEditor(parent, x, y, w, h, title, getTable, onChanged)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetPoint("TOPLEFT", x, y)
    box:SetSize(w, h)
    box:SetBackdrop({ bgFile=TEX, edgeFile=TEX, edgeSize=1 })
    box:SetBackdropColor(0.12, 0.12, 0.12, 0.95)
    box:SetBackdropBorderColor(0, 0, 0, 1)

    local t = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetPoint("TOPLEFT", 8, -8)
    t:SetText(title or "Custom List")
    t:SetTextColor(0.85, 0.85, 0.85)

    local eb = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
    eb:SetSize(w - 70, 20)
    eb:SetPoint("TOPLEFT", 12, -26)
    eb:SetAutoFocus(false)
    eb.Left:Hide(); eb.Middle:Hide(); eb.Right:Hide()
    local ebBG = eb:CreateTexture(nil, "BACKGROUND")
    ebBG:SetAllPoints()
    ebBG:SetColorTexture(0.05, 0.05, 0.05, 1)

    local bAdd = CreateModernButton(box, "Add", 0, 0, 50, 20)
    bAdd:ClearAllPoints()
    bAdd:SetPoint("LEFT", eb, "RIGHT", 8, 0)

    local listBG = CreateFrame("Frame", nil, box, "BackdropTemplate")
    listBG:SetPoint("TOPLEFT", 8, -52)
    listBG:SetPoint("BOTTOMRIGHT", -8, 8)
    listBG:SetBackdrop({ bgFile=TEX, edgeFile=TEX, edgeSize=1 })
    listBG:SetBackdropColor(0.08, 0.08, 0.08, 1)
    listBG:SetBackdropBorderColor(0, 0, 0, 1)

    local sf = CreateFrame("ScrollFrame", nil, listBG, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", -26, 4)

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)

    local rows = {}

    local function GetSortedKeys()
        local tbl = getTable()
        local keys = {}
        for k,_ in pairs(tbl) do
            local id = tonumber(k)
            if id then keys[#keys+1] = id end
        end
        table.sort(keys)
        return keys
    end

    local function Row(i)
        local r = rows[i]
        if r then return r end

        r = CreateFrame("Frame", nil, content)
        r:SetHeight(20)
        r:SetPoint("TOPLEFT", 0, -(i-1)*20)
        r:SetPoint("TOPRIGHT", 0, -(i-1)*20)

        local cb = CreateModernCheck(r, "", 0, -3, function() return true end, function() end)

        local icon = r:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14,14)
        icon:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        name:SetJustifyH("LEFT")
        name:SetText("")

        local bRem = CreateModernButton(r, "Del", 0, 0, 40, 16)
        bRem:ClearAllPoints()
        bRem:SetPoint("RIGHT", -2, 0)

        r.cb = cb
        r.icon = icon
        r.name = name
        r.del = bRem
        rows[i] = r
        return r
    end

    local function Refresh()
        local tbl = getTable()
        local keys = GetSortedKeys()
        local totalH = #keys * 20
        if totalH < 1 then totalH = 1 end
        content:SetHeight(totalH)

        for i=1, #keys do
            local id = keys[i]
            local r = Row(i)
            r:Show()

            local spellName = GetSpellInfo and GetSpellInfo(id) or nil
            local tex = GetSpellTexture and GetSpellTexture(id) or nil
            r.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
            r.name:SetText(("%s (%d)"):format(spellName or "Spell", id))

            r.cb.Refresh = function() r.cb:SetChecked(tbl[id] and true or false) end
            
            r.cb:SetScript("OnClick", function()
                tbl[id] = not tbl[id]
                if onChanged then onChanged() end
                Refresh()
            end)

            r.del:SetScript("OnClick", function()
                tbl[id] = nil
                if onChanged then onChanged() end
                Refresh()
            end)
            
            local isChecked = tbl[id] and true or false
            if isChecked then r.cb.inner:Show() else r.cb.inner:Hide() end
        end

        for i = #keys + 1, #rows do
            rows[i]:Hide()
        end
    end

    bAdd:SetScript("OnClick", function()
        if InCombat() then return end
        local id = ParseSpellID(eb:GetText())
        if not id then return end
        local tbl = getTable()
        tbl[id] = true
        eb:SetText("")
        if onChanged then onChanged() end
        Refresh()
    end)

    eb:SetScript("OnEnterPressed", function()
        bAdd:Click()
    end)

    box.Refresh = Refresh
    return box
end

-- ============================================================================
-- Raid Simulation Preview
-- ============================================================================
local Sim = { frames = {}, tankFrames = {}, anchor = nil, enabled = false }

local function Sim_SetHPColor(frame, r, g, b)
    frame.hp:SetStatusBarColor(r, g, b)
    if frame.hpbg then
        frame.hpbg:SetColorTexture(r * 0.22, g * 0.22, b * 0.22, 0.90)
    end
end

local function Sim_UpdatePowerLayout(btn, showPower)
    btn.hp:ClearAllPoints()
    btn.hp:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -(1 + NAME_H))
    if showPower then
        btn.power:Show()
        btn.power:SetHeight(POWER_H)
        btn.hp:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1 + POWER_H)
    else
        btn.power:Hide()
        btn.hp:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    end
end

local function Sim_EnsureAuraIcons(btn)
    if btn._ohAuraInit then return end
    btn._ohAuraInit = true

    btn.buffHolder = CreateFrame("Frame", nil, btn)
    btn.buffHolder:SetSize(1,1)
    btn.buffHolder:SetPoint("TOPRIGHT", btn.hp, "TOPRIGHT", -2, -2)
    btn.buffIcons = {}

    btn.debuffHolder = CreateFrame("Frame", nil, btn)
    btn.debuffHolder:SetSize(1,1)
    btn.debuffHolder:SetPoint("TOPLEFT", btn.hp, "TOPLEFT", 2, -2)
    btn.debuffIcons = {}

    local function MakeIcon(parent)
        local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        f:SetSize(14,14)
        f:SetBackdrop({ bgFile=TEX, edgeFile=TEX, edgeSize=1 })
        f:SetBackdropColor(0,0,0,0.35)
        f:SetBackdropBorderColor(0,0,0,0.9)

        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexCoord(0.07,0.93,0.07,0.93)
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

        f.tex = tex
        f:Hide()
        return f
    end

    for i=1, 8 do
        btn.buffIcons[i] = MakeIcon(btn.buffHolder)
        btn.debuffIcons[i] = MakeIcon(btn.debuffHolder)
    end
end

local function Sim_ApplyAuraPreview(btn)
    local db = GetRaidDB()
    EnsureAuraDB(db)
    Sim_EnsureAuraIcons(btn)

    local fb = db.fbuff
    local buffIDs = {}
    if fb.enabled and fb.mode ~= "OFF" then
        buffIDs = BuildListFromMode("FRIENDLYBUFFS", fb.mode, fb.custom, ImportantFriendly())
    end

    local bSize = tonumber(fb.size) or 14
    local bMax  = tonumber(fb.maxIcons) or 4
    if bMax < 0 then bMax = 0 end
    if bMax > 8 then bMax = 8 end

    for i=1, 8 do
        local icon = btn.buffIcons[i]
        icon:Hide()
        icon:SetSize(bSize, bSize)
        icon:ClearAllPoints()
        icon:SetPoint("TOPRIGHT", btn.buffHolder, "TOPRIGHT", -((i-1)*(bSize+2)), 0)
    end

    for i=1, math.min(#buffIDs, bMax) do
        local id = buffIDs[i]
        local tex = GetSpellTexture and GetSpellTexture(id) or nil
        local icon = btn.buffIcons[i]
        icon.tex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
        icon:Show()
    end

    local dbf = db.debuff
    local debuffIDs = {}
    if dbf.enabled and dbf.mode ~= "OFF" then
        debuffIDs = BuildListFromMode("DEBUFFS", dbf.mode, dbf.custom, ImportantDebuffs())
    end

    local dSize = tonumber(dbf.size) or 14
    local dMax  = tonumber(dbf.maxIcons) or 3
    if dMax < 0 then dMax = 0 end
    if dMax > 8 then dMax = 8 end

    for i=1, 8 do
        local icon = btn.debuffIcons[i]
        icon:Hide()
        icon:SetSize(dSize, dSize)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", btn.debuffHolder, "TOPLEFT", ((i-1)*(dSize+2)), 0)
        icon:SetBackdropColor(0.20, 0.05, 0.05, 0.35)
        icon:SetBackdropBorderColor(0.2, 0, 0, 0.9)
    end

    for i=1, math.min(#debuffIDs, dMax) do
        local id = debuffIDs[i]
        local tex = GetSpellTexture and GetSpellTexture(id) or nil
        local icon = btn.debuffIcons[i]
        icon.tex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
        icon:Show()
    end
end

local function Sim_CreateUnit(parent)
    local btn = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    btn:SetBackdrop({ bgFile=TEX, edgeFile=TEX, edgeSize=1 })
    btn:SetBackdropColor(0.06, 0.06, 0.06, 0.85)
    btn:SetBackdropBorderColor(0, 0, 0, 0.85)

    btn.nameBar = CreateFrame("Frame", nil, btn)
    btn.nameBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    btn.nameBar:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
    btn.nameBar:SetHeight(NAME_H)

    btn.nameBar.bg = btn.nameBar:CreateTexture(nil, "BACKGROUND")
    btn.nameBar.bg:SetAllPoints()
    btn.nameBar.bg:SetColorTexture(0.03, 0.03, 0.03, 0.92)

    btn.nameBar.line = btn.nameBar:CreateTexture(nil, "BORDER")
    btn.nameBar.line:SetPoint("BOTTOMLEFT", btn.nameBar, "BOTTOMLEFT", 0, 0)
    btn.nameBar.line:SetPoint("BOTTOMRIGHT", btn.nameBar, "BOTTOMRIGHT", 0, 0)
    btn.nameBar.line:SetHeight(1)
    btn.nameBar.line:SetColorTexture(0, 0, 0, 0.90)

    btn.groupText = btn.nameBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.groupText:SetPoint("LEFT", btn.nameBar, "LEFT", 4, 0)
    btn.groupText:SetJustifyH("LEFT")
    btn.groupText:SetTextColor(1,1,1,0.85)
    btn.groupText:SetText("")
    btn.groupText:Hide()

    btn.roleText = btn.nameBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.roleText:SetPoint("RIGHT", btn.nameBar, "RIGHT", -4, 0)
    btn.roleText:SetJustifyH("RIGHT")
    btn.roleText:SetText("")
    btn.roleText:Hide()

    btn.nameText = btn.nameBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.nameText:SetPoint("CENTER", btn.nameBar, "CENTER", 0, 0)
    btn.nameText:SetJustifyH("CENTER")
    btn.nameText:SetText("Member")

    btn.power = CreateFrame("StatusBar", nil, btn)
    btn.power:SetPoint("BOTTOMLEFT", 1, 1)
    btn.power:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.power:SetStatusBarTexture(TEX)
    btn.power:SetStatusBarColor(0.12, 0.42, 1.0)
    btn.power:SetMinMaxValues(0, 100)
    btn.power:SetValue(60)
    btn.power:Hide()

    btn.hp = CreateFrame("StatusBar", nil, btn)
    btn.hp:SetStatusBarTexture(TEX)
    btn.hp:SetMinMaxValues(0, 100)
    btn.hp:SetValue(100)

    btn.hpbg = btn.hp:CreateTexture(nil, "BACKGROUND")
    btn.hpbg:SetAllPoints()
    btn.hpbg:SetColorTexture(0.02, 0.02, 0.02, 0.90)

    Sim_EnsureAuraIcons(btn)

    return btn
end

function Sim:EnsureAnchor()
    if self.anchor then return end

    local a = CreateFrame("Frame", "OpenHealRaidSimAnchor", UIParent, "BackdropTemplate")
    self.anchor = a
    a:SetSize(220, 18)
    a:SetFrameStrata("DIALOG")
    a:SetClampedToScreen(true)
    a:SetBackdrop({ bgFile=TEX, edgeFile=TEX, edgeSize=1 })
    a:SetBackdropColor(0,0,0,0.40)
    a:SetBackdropBorderColor(0,0,0,0.95)

    local t = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetPoint("CENTER")
    t:SetText("Raid Preview Anchor (drag)")

    a:EnableMouse(true)
    a:SetMovable(true)
    a:RegisterForDrag("LeftButton")
    a:SetScript("OnDragStart", function(self)
        if InCombat() then return end
        self:StartMoving()
    end)
    a:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if InCombat() then return end
        local db = GetRaidDB()
        local p, _, rp, x, y = self:GetPoint()
        db.point    = p or db.point
        db.relPoint = rp or db.relPoint
        db.x        = SafeFloor(x or 0)
        db.y        = SafeFloor(y or 0)
        CallRaidRebuild()
    end)
end

function Sim:ApplyAnchorFromDB()
    if not self.anchor then return end
    local db = GetRaidDB()
    self.anchor:ClearAllPoints()
    self.anchor:SetPoint(db.point or "CENTER", UIParent, db.relPoint or "CENTER", db.x or 0, db.y or 120)
end

function Sim:SetEnabled(on)
    self.enabled = on and true or false
    self:EnsureAnchor()
    self:ApplyAnchorFromDB()
    self.anchor:SetShown(self.enabled)

    if not self.enabled then
        for _, f in ipairs(self.frames) do f:Hide() end
        for _, f in ipairs(self.tankFrames) do f:Hide() end
        return
    end

    self:Build()
end

function Sim:Build()
    if not self.enabled then return end
    local db = GetRaidDB()
    EnsureAuraDB(db)

    local count = tonumber(db.max) or 40
    if count < 1 then count = 1 end
    if count > 40 then count = 40 end

    for i = 1, count do
        local f = self.frames[i]
        if not f then
            f = Sim_CreateUnit(UIParent)
            f:SetFrameStrata("DIALOG")
            f:SetClampedToScreen(true)
            self.frames[i] = f
        end
        f:Show()
    end
    for i = count + 1, #self.frames do
        self.frames[i]:Hide()
    end

    local tankCount = 8
    for i = 1, tankCount do
        local f = self.tankFrames[i]
        if not f then
            f = Sim_CreateUnit(UIParent)
            f:SetFrameStrata("DIALOG")
            f:SetClampedToScreen(true)
            self.tankFrames[i] = f
        end
        f:Hide()
    end

    self:Layout()
end

function Sim:Layout()
    if not self.enabled then return end
    local db = GetRaidDB()
    EnsureAuraDB(db)

    local w = tonumber(db.w) or 160
    local h = tonumber(db.h) or 46
    local spacing = tonumber(db.spacing) or 4

    local groupGap = tonumber(db.groupGap)
    if not groupGap then
        groupGap = spacing + 10
    end

    local showPower = db.showPower and true or false
    local showRole  = db.showRole and true or false
    local showGroup = db.showGroup and true or false

    local count = tonumber(db.max) or 40
    if count < 1 then count = 1 end
    if count > 40 then count = 40 end

    db.columns = SafeColumns(db.columns)

    self:ApplyAnchorFromDB()

    local usedW, usedH = 220, 18

    if ns and ns.Raid and ns.Raid.ComputeLayout then
        local entries = {}
        for i = 1, count do
            local grp = math.ceil(i / 5)
            if grp < 1 then grp = 1 end
            if grp > 8 then grp = 8 end
            entries[#entries + 1] = {
                index = i,
                frame = self.frames[i],
                subgroup = grp,
            }
        end

        local layout = ns.Raid:ComputeLayout(entries)
        usedW = math.max(220, tonumber(layout.totalWidth) or 0)
        usedH = math.max(18, tonumber(layout.totalHeight) or 0)

        for _, entry in ipairs(entries) do
            local i = entry.index
            local f = entry.frame
            local pos = layout.positions[entry]
            local grp = entry.subgroup

            if f and pos then
                f:SetSize(pos.width, pos.height)
                f:ClearAllPoints()

                Sim_UpdatePowerLayout(f, showPower)
                f.hp:SetValue(100)

                f:SetPoint("TOPLEFT", self.anchor, "TOPLEFT", pos.x, -(pos.y + 22))
                f.nameText:SetText(("Member %02d"):format(i))

                if showRole then
                    local r = (i % 5 == 0) and "T" or ((i % 3 == 0) and "H" or "D")
                    f.roleText:SetText(r)
                    f.roleText:Show()
                else
                    f.roleText:SetText("")
                    f.roleText:Hide()
                end

                if showGroup then
                    f.groupText:SetText(("G%d"):format(grp))
                    f.groupText:Show()
                    f.nameText:ClearAllPoints()
                    f.nameText:SetPoint("CENTER", f.nameBar, "CENTER", 8, 0)
                else
                    f.groupText:SetText("")
                    f.groupText:Hide()
                    f.nameText:ClearAllPoints()
                    f.nameText:SetPoint("CENTER", f.nameBar, "CENTER", 0, 0)
                end

                if db.classColor then
                    local k = i % 6
                    if k == 0 then Sim_SetHPColor(f, 0.78, 0.61, 0.43)
                    elseif k == 1 then Sim_SetHPColor(f, 0.25, 0.78, 0.92)
                    elseif k == 2 then Sim_SetHPColor(f, 0.67, 0.83, 0.45)
                    elseif k == 3 then Sim_SetHPColor(f, 0.96, 0.55, 0.73)
                    elseif k == 4 then Sim_SetHPColor(f, 1.00, 0.96, 0.41)
                    else Sim_SetHPColor(f, 0.20, 0.80, 0.20)
                    end
                else
                    Sim_SetHPColor(f, 0.20, 0.80, 0.20)
                end

                Sim_ApplyAuraPreview(f)
            end
        end
    else
        local perGroupCount = {}

        for i = 1, count do
            local f = self.frames[i]
            f:SetSize(w, h)
            f:ClearAllPoints()

            Sim_UpdatePowerLayout(f, showPower)
            f.hp:SetValue(100)

            local grp = math.ceil(i / 5)
            if grp < 1 then grp = 1 end
            if grp > 8 then grp = 8 end

            local used = (perGroupCount[grp] or 0) + 1
            perGroupCount[grp] = used

            local xOff = (grp - 1) * (w + groupGap)
            local yOff = -((used - 1) * (h + spacing))

            f:SetPoint("TOPLEFT", self.anchor, "TOPLEFT", xOff, yOff - 22)

            f.nameText:SetText(("Member %02d"):format(i))

            if showRole then
                local r = (i % 5 == 0) and "T" or ((i % 3 == 0) and "H" or "D")
                f.roleText:SetText(r)
                f.roleText:Show()
            else
                f.roleText:SetText("")
                f.roleText:Hide()
            end

            if showGroup then
                f.groupText:SetText(("G%d"):format(grp))
                f.groupText:Show()
                f.nameText:ClearAllPoints()
                f.nameText:SetPoint("CENTER", f.nameBar, "CENTER", 8, 0)
            else
                f.groupText:SetText("")
                f.groupText:Hide()
                f.nameText:ClearAllPoints()
                f.nameText:SetPoint("CENTER", f.nameBar, "CENTER", 0, 0)
            end

            if db.classColor then
                local k = i % 6
                if k == 0 then Sim_SetHPColor(f, 0.78, 0.61, 0.43)
                elseif k == 1 then Sim_SetHPColor(f, 0.25, 0.78, 0.92)
                elseif k == 2 then Sim_SetHPColor(f, 0.67, 0.83, 0.45)
                elseif k == 3 then Sim_SetHPColor(f, 0.96, 0.55, 0.73)
                elseif k == 4 then Sim_SetHPColor(f, 1.00, 0.96, 0.41)
                else Sim_SetHPColor(f, 0.20, 0.80, 0.20)
                end
            else
                Sim_SetHPColor(f, 0.20, 0.80, 0.20)
            end

            Sim_ApplyAuraPreview(f)
        end

        usedW = math.max(220, (8 * w) + (7 * groupGap))
        usedH = math.max(18, (5 * h) + (4 * spacing))
    end

    if self.anchor then
        self.anchor:SetSize(usedW, usedH + 22)
    end

    local showTanks = (db.tankFrames == true)
    if showTanks then
        local raidW = w
        local raidH = h

        local tw = tonumber(db.tankW)
        local th = tonumber(db.tankH)
        local tSpacing = tonumber(db.tankSpacing) or spacing

        if not tw then tw = raidW + 20 end
        if not th then th = raidH + 6 end

        local side = db.tankSide or "LEFT"
        local offX = tonumber(db.tankOffsetX)
        local offY = tonumber(db.tankOffsetY)

        if offX == nil then
            offX = (side == "RIGHT") and (raidW + 20) or -(tw + 12)
        end
        if offY == nil then offY = 0 end

        local tankCount = 2
        for i = 1, tankCount do
            local f = self.tankFrames[i]
            f:Show()
            f:SetSize(tw, th)
            f:ClearAllPoints()
            Sim_UpdatePowerLayout(f, showPower)
            f.hp:SetValue(100)

            f.nameText:SetText(("Tank %d"):format(i))
            if showRole then
                f.roleText:SetText("T")
                f.roleText:Show()
            else
                f.roleText:SetText("")
                f.roleText:Hide()
            end
            if showGroup then
                f.groupText:SetText("")
                f.groupText:Hide()
                f.nameText:ClearAllPoints()
                f.nameText:SetPoint("CENTER", f.nameBar, "CENTER", 0, 0)
            end

            local x = offX
            local y = offY - ((i - 1) * (th + tSpacing))
            f:SetPoint("TOPLEFT", self.anchor, "TOPLEFT", x, (y - 22))
            Sim_SetHPColor(f, 0.20, 0.80, 0.20)

            Sim_ApplyAuraPreview(f)
        end
        for i = tankCount + 1, #self.tankFrames do
            self.tankFrames[i]:Hide()
        end
    else
        for i = 1, #self.tankFrames do
            self.tankFrames[i]:Hide()
        end
    end
end

-- ============================================================================
-- Panels
-- ============================================================================
local function BuildPartyPanel(parent, ownerFrame)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    local widgets = {}

    local function Refresh()
        if ownerFrame and ownerFrame.combatText then
            ownerFrame.combatText:SetText(InCombat() and "In combat: changes locked." or "")
        end
        for _, w in ipairs(widgets) do
            if w.Refresh then w:Refresh() end
        end
    end

    local function Changed()
        Refresh()
        CallPartyRebuild()
    end

    local plate = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    plate:SetPoint("TOPLEFT", 8, -8)
    plate:SetPoint("BOTTOMRIGHT", -8, 8)
    ApplySoftPanel(plate)

    local x = 16
    local y = -16

    CreateSectionTitle(plate, "Party", x, y); y = y - 28

    do
        local db = GetPartyDB()
        if db.allowDrag == nil then db.allowDrag = true end
    end

    table.insert(widgets, CreateModernCheck(plate, "Enabled", x, y,
        function() return GetPartyDB().enabled end,
        function(v) GetPartyDB().enabled = v end,
        Changed, true)); y = y - 24

    table.insert(widgets, CreateModernCheck(plate, "Locked (hide mover)", x, y,
        function() return GetPartyDB().locked end,
        function(v) GetPartyDB().locked = v end,
        Changed, true)); y = y - 24

    table.insert(widgets, CreateModernCheck(plate, "Enable Drag (party mover)", x, y,
        function() return GetPartyDB().allowDrag end,
        function(v) GetPartyDB().allowDrag = v end,
        Changed, true)); y = y - 24

    table.insert(widgets, CreateModernCheck(plate, "Show Role (T/H/D)", x, y,
        function() return GetPartyDB().showRole end,
        function(v) GetPartyDB().showRole = v end,
        Changed, true)); y = y - 24

    table.insert(widgets, CreateModernCheck(plate, "Show Power", x, y,
        function() return GetPartyDB().showPower end,
        function(v) GetPartyDB().showPower = v end,
        Changed, true)); y = y - 24

    table.insert(widgets, CreateModernCheck(plate, "Show Raid Marker", x, y,
        function() return GetPartyDB().showRaidMarker end,
        function(v) GetPartyDB().showRaidMarker = v end,
        Changed, true)); y = y - 26

    table.insert(widgets, CreateModernSlider(plate, "Raid Marker Size", x, y, 260, 8, 32, 1,
        function() return GetPartyDB().raidMarkerSize or 16 end,
        function(v) GetPartyDB().raidMarkerSize = v end,
        Changed, true)); y = y - 48

    table.insert(widgets, CreateModernSlider(plate, "Width", x, y, 260, 90, 360, 1,
        function() return GetPartyDB().w end,
        function(v) GetPartyDB().w = v end,
        Changed, true)); y = y - 48

    table.insert(widgets, CreateModernSlider(plate, "Height", x, y, 260, 18, 120, 1,
        function() return GetPartyDB().h end,
        function(v) GetPartyDB().h = v end,
        Changed, true)); y = y - 48

    table.insert(widgets, CreateModernSlider(plate, "Spacing", x, y, 260, 0, 24, 1,
        function() return GetPartyDB().spacing end,
        function(v) GetPartyDB().spacing = v end,
        Changed, true)); y = y - 56

    local ddOrient = CreateModernDropdown(plate, "Orientation", x, y, 200, {
        { text="Horizontal", value="HORIZONTAL" },
        { text="Vertical",   value="VERTICAL" },
    },
    function() return GetPartyDB().orientation end,
    function(v) GetPartyDB().orientation = v end,
    Changed, true)
    table.insert(widgets, ddOrient)
    y = y - 56

    local ddSort = CreateModernDropdown(plate, "Sort", x, y, 200, {
        { text="None (Blizzard)",      value="NONE" },
        { text="Role (Tank/Heal/DPS)", value="ROLE" },
    },
    function() return GetPartyDB().sort end,
    function(v) GetPartyDB().sort = v end,
    Changed, true)
    table.insert(widgets, ddSort)
    y = y - 56

    CreateModernButton(plate, "Reset Party Layout", x, y, 150, 24, function()
        if InCombat() then return end
        local db = GetPartyDB()
        db.orientation = "HORIZONTAL"
        db.w = 210
        db.h = 70
        db.spacing = 6
        db.sort = "NONE"
        db.showRole = true
        db.showPower = true
        db.classColor = true
        if db.allowDrag == nil then db.allowDrag = true end
        Changed()
    end)

    panel.Refresh = Refresh
    return panel
end

local function BuildRaidPanel(parent, ownerFrame)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    local widgets = {}
    local db = GetRaidDB()

    EnsureAuraDB(db)

    if db.tankFrames == nil then db.tankFrames = false end
    if db.tankAlsoInRaid == nil then db.tankAlsoInRaid = true end
    if db.tankSide == nil then db.tankSide = "LEFT" end

    local function RefreshCombatText()
        if ownerFrame and ownerFrame.combatText then
            ownerFrame.combatText:SetText(InCombat() and "In combat: changes locked." or "")
        end
    end

    local function Refresh()
        RefreshCombatText()
        for _, w in ipairs(widgets) do
            if w.Refresh then w:Refresh() end
        end
        if db._simOn then
            Sim:SetEnabled(true)
            Sim:Build()
            Sim:Layout()
        else
            Sim:SetEnabled(false)
        end
    end

    local function OnChanged()
        EnsureAuraDB(db)
        Refresh()
        CallRaidRebuild()
    end

    local plate = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    plate:SetPoint("TOPLEFT", 8, -8)
    plate:SetPoint("BOTTOMRIGHT", -8, 8)
    ApplySoftPanel(plate)

    local colWidth = 270

    local leftCol = CreateFrame("Frame", nil, plate)
    leftCol:SetPoint("TOPLEFT", 12, -12)
    leftCol:SetPoint("BOTTOMLEFT", 12, 12)
    leftCol:SetWidth(colWidth)

    local midCol = CreateFrame("Frame", nil, plate)
    midCol:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", 16, 0)
    midCol:SetPoint("BOTTOMLEFT", leftCol, "BOTTOMRIGHT", 16, 0)
    midCol:SetWidth(colWidth)

    local rightCol = CreateFrame("Frame", nil, plate)
    rightCol:SetPoint("TOPLEFT", midCol, "TOPRIGHT", 16, 0)
    rightCol:SetPoint("BOTTOMRIGHT", -12, 12)

    local function NewCursor(startY) return { y = startY or -8 } end
    local function NextY(cur, dy) cur.y = cur.y - (dy or 24) return cur.y end

    local L = NewCursor(-6)
    local M = NewCursor(-6)
    local R = NewCursor(-6)

    -- ============================================================
    -- LEFT COLUMN
    -- ============================================================
    CreateSectionTitle(leftCol, "General", 0, L.y); NextY(L, 28)

    table.insert(widgets, CreateModernCheck(leftCol, "Enabled (real raid frames)", 0, L.y,
        function() return db.enabled end, function(v) db.enabled = v end, OnChanged, false)); NextY(L, 24)

    table.insert(widgets, CreateModernCheck(leftCol, "Locked (hide mover)", 0, L.y,
        function() return db.locked end, function(v) db.locked = v end, OnChanged, true)); NextY(L, 24)

    table.insert(widgets, CreateModernCheck(leftCol, "Simulation Mode (preview)", 0, L.y,
        function() return db._simOn end, function(v) db._simOn = v end,
        function()
            Sim:SetEnabled(db._simOn)
            Refresh()
        end, false)); NextY(L, 34)

    CreateSectionTitle(leftCol, "Tools", 0, L.y); NextY(L, 24)

    CreateModernButton(leftCol, "Open /ohbinds", 0, L.y, 110, 24, function()
        ExecuteSlash("/ohbinds")
    end)

    CreateModernButton(leftCol, "Open /ohbindview", 120, L.y, 120, 24, function()
        ExecuteSlash("/ohbindview")
    end)
    NextY(L, 34)

    CreateSectionTitle(leftCol, "Layout", 0, L.y); NextY(L, 28)

    local ddOrient = CreateModernDropdown(leftCol, "Orientation", 0, L.y, 200, {
        { text="VERTICAL",   value="VERTICAL" },
        { text="HORIZONTAL", value="HORIZONTAL" },
    }, function() return db.orientation end,
       function(v) db.orientation = v end, OnChanged, true)
    table.insert(widgets, ddOrient)
    NextY(L, 48)

    local ddSort = CreateModernDropdown(leftCol, "Sort", 0, L.y, 200, {
        { text="NONE (Blizzard)", value="NONE" },
        { text="ROLE (T/H/D)",    value="ROLE" },
    }, function() return db.sort end,
       function(v) db.sort = v end, OnChanged, true)
    table.insert(widgets, ddSort)
    NextY(L, 48)

    table.insert(widgets, CreateModernSlider(leftCol, "Width", 0, L.y, 240, 70, 260, 1,
        function() return db.w end, function(v) db.w = v end, OnChanged, true)); NextY(L, 40)

    table.insert(widgets, CreateModernSlider(leftCol, "Height", 0, L.y, 240, 16, 80, 1,
        function() return db.h end, function(v) db.h = v end, OnChanged, true)); NextY(L, 40)

    table.insert(widgets, CreateModernSlider(leftCol, "Spacing (within group)", 0, L.y, 240, 0, 16, 1,
        function() return db.spacing end, function(v) db.spacing = v end, OnChanged, true)); NextY(L, 40)

    table.insert(widgets, CreateModernSlider(leftCol, "Group Gap (between groups)", 0, L.y, 240, 0, 40, 1,
        function() return db.groupGap end,
        function(v) db.groupGap = v end,
        OnChanged, true)); NextY(L, 40)

    table.insert(widgets, CreateModernSlider(leftCol, "Group Columns", 0, L.y, 240, 1, 8, 1,
        function() return SafeColumns(db.columns) end,
        function(v) db.columns = SafeColumns(v) end,
        OnChanged, true)); NextY(L, 40)

    table.insert(widgets, CreateModernSlider(leftCol, "Max shown", 0, L.y, 240, 5, 40, 1,
        function() return db.max end, function(v) db.max = v end, OnChanged, true)); NextY(L, 44)

    CreateSectionTitle(leftCol, "Elements", 0, L.y); NextY(L, 28)

    table.insert(widgets, CreateModernCheck(leftCol, "Show Role Letter", 0, L.y,
        function() return db.showRole end, function(v) db.showRole = v end, OnChanged, true)); NextY(L, 22)

    table.insert(widgets, CreateModernCheck(leftCol, "Show Power Bar", 0, L.y,
        function() return db.showPower end, function(v) db.showPower = v end, OnChanged, true)); NextY(L, 22)

    table.insert(widgets, CreateModernCheck(leftCol, "Class Colors", 0, L.y,
        function() return db.classColor end, function(v) db.classColor = v end, OnChanged, true)); NextY(L, 22)

    table.insert(widgets, CreateModernCheck(leftCol, "Show Group # (G1..)", 0, L.y,
        function() return db.showGroup end, function(v) db.showGroup = v end, OnChanged, true)); NextY(L, 22)

    table.insert(widgets, CreateModernCheck(leftCol, "Show Raid Marker", 0, L.y,
        function() return db.showRaidMarker end,
        function(v) db.showRaidMarker = v end, OnChanged, true)); NextY(L, 24)

    table.insert(widgets, CreateModernSlider(leftCol, "Raid Marker Size", 0, L.y, 240, 8, 32, 1,
        function() return db.raidMarkerSize or 14 end,
        function(v) db.raidMarkerSize = v end, OnChanged, true)); NextY(L, 40)

    CreateModernButton(leftCol, "Reset Layout", 0, L.y, 110, 24, function()
        if InCombat() then return end
        db.orientation = "VERTICAL"
        db.w = 160
        db.h = 46
        db.spacing = 4
        db.groupGap = nil
        db.columns = 8
        db.max = 40
        db.sort = "NONE"
        db.showRole = false
        db.showPower = false
        db.classColor = true
        db.showGroup = false

        EnsureAuraDB(db)

        db.tankFrames = false
        db.tankAlsoInRaid = true
        db.tankSide = "LEFT"
        db.tankW = nil
        db.tankH = nil
        db.tankSpacing = nil
        db.tankOffsetX = nil
        db.tankOffsetY = nil
        OnChanged()
    end)

    CreateModernButton(leftCol, "Reset Pos", 120, L.y, 110, 24, function()
        if InCombat() then return end
        db.point = "CENTER"
        db.relPoint = "CENTER"
        db.x = 0
        db.y = 120
        OnChanged()
    end)

    -- ============================================================
    -- MID COLUMN
    -- ============================================================
    local function FB() db.fbuff = db.fbuff or {} return db.fbuff end
    local function DBF() db.debuff = db.debuff or {} return db.debuff end

    CreateSectionTitle(midCol, "Friendly Buffs (icons)", 0, M.y); NextY(M, 28)

    table.insert(widgets, CreateModernCheck(midCol, "Enable Buff Icons", 0, M.y,
        function() return FB().enabled end, function(v) FB().enabled = v end, OnChanged, true)); NextY(M, 24)

    local ddFBMode = CreateModernDropdown(midCol, "Buff Filter", 0, M.y, 200, {
        { text="IMPORTANT", value="IMPORTANT" },
        { text="CUSTOM",    value="CUSTOM" },
        { text="ALL",       value="ALL" },
        { text="OFF",       value="OFF" },
    }, function() return FB().mode end,
       function(v) FB().mode = v end, OnChanged, true)
    table.insert(widgets, ddFBMode)
    NextY(M, 48)

    table.insert(widgets, CreateModernCheck(midCol, "Only mine", 0, M.y,
        function() return FB().onlyMine end, function(v) FB().onlyMine = v end, OnChanged, true)); NextY(M, 26)

    table.insert(widgets, CreateModernSlider(midCol, "Buff Max Icons", 0, M.y, 240, 0, 8, 1,
        function() return FB().maxIcons end, function(v) FB().maxIcons = v end, OnChanged, true)); NextY(M, 42)

    table.insert(widgets, CreateModernSlider(midCol, "Buff Icon Size", 0, M.y, 240, 10, 24, 1,
        function() return FB().size end, function(v) FB().size = v end, OnChanged, true)); NextY(M, 42)

    table.insert(widgets, CreateModernCheck(midCol, "Show timers", 0, M.y,
        function() return FB().showTimers end, function(v) FB().showTimers = v end, OnChanged, true)); NextY(M, 22)

    table.insert(widgets, CreateModernCheck(midCol, "Show stacks", 0, M.y,
        function() return FB().showStacks end, function(v) FB().showStacks = v end, OnChanged, true)); NextY(M, 28)

    local fbEditor = CreateModernSpellListEditor(midCol, 0, M.y, 240, 160,
        "CUSTOM Buffs",
        function() FB().custom = FB().custom or {} return FB().custom end,
        function() OnChanged() end
    )
    table.insert(widgets, fbEditor)
    NextY(M, 170)

    -- ============================================================
    -- RIGHT COLUMN
    -- ============================================================
    CreateSectionTitle(rightCol, "Debuffs (icons)", 0, R.y); NextY(R, 26)

    table.insert(widgets, CreateModernCheck(rightCol, "Enable Debuff Icons", 0, R.y,
        function() return DBF().enabled end, function(v) DBF().enabled = v end, OnChanged, true)); NextY(R, 22)

    local ddDBFMode = CreateModernDropdown(rightCol, "Debuff Filter", 0, R.y, 200, {
        { text="IMPORTANT", value="IMPORTANT" },
        { text="CUSTOM",    value="CUSTOM" },
        { text="ALL",       value="ALL" },
        { text="OFF",       value="OFF" },
    }, function() return DBF().mode end,
       function(v) DBF().mode = v end, OnChanged, true)
    table.insert(widgets, ddDBFMode)
    NextY(R, 44)

    table.insert(widgets, CreateModernSlider(rightCol, "Debuff Max Icons", 0, R.y, 240, 0, 8, 1,
        function() return DBF().maxIcons end, function(v) DBF().maxIcons = v end, OnChanged, true)); NextY(R, 38)

    table.insert(widgets, CreateModernSlider(rightCol, "Debuff Icon Size", 0, R.y, 240, 10, 24, 1,
        function() return DBF().size end, function(v) DBF().size = v end, OnChanged, true)); NextY(R, 38)

    table.insert(widgets, CreateModernCheck(rightCol, "Custom: only dispellable", 0, R.y,
        function() return DBF().customOnlyDispellable end,
        function(v) DBF().customOnlyDispellable = v end,
        OnChanged, true)); NextY(R, 26)

    local dbfEditor = CreateModernSpellListEditor(rightCol, 0, R.y, 240, 140,
        "CUSTOM Debuffs",
        function() DBF().custom = DBF().custom or {} return DBF().custom end,
        function() OnChanged() end
    )
    table.insert(widgets, dbfEditor)
    NextY(R, 146)

    CreateSectionTitle(rightCol, "Tank Frames", 0, R.y); NextY(R, 26)

    table.insert(widgets, CreateModernCheck(rightCol, "Show Tank Frames", 0, R.y,
        function() return db.tankFrames end,
        function(v) db.tankFrames = v end,
        OnChanged, true)); NextY(R, 22)

    table.insert(widgets, CreateModernCheck(rightCol, "Keep tanks in Raid Grid", 0, R.y,
        function() return db.tankAlsoInRaid end,
        function(v) db.tankAlsoInRaid = v end,
        OnChanged, true)); NextY(R, 22)

    local ddTankSide = CreateModernDropdown(rightCol, "Tank Side", 0, R.y, 200, {
        { text="LEFT",  value="LEFT" },
        { text="RIGHT", value="RIGHT" },
    }, function() return db.tankSide end,
       function(v) db.tankSide = v end, OnChanged, true)
    table.insert(widgets, ddTankSide)
    NextY(R, 44)

    table.insert(widgets, CreateModernSlider(rightCol, "Tank Width", 0, R.y, 240, 70, 320, 1,
        function()
            local raidW = tonumber(db.w) or 160
            return tonumber(db.tankW) or (raidW + 20)
        end,
        function(v) db.tankW = v end,
        OnChanged, true)); NextY(R, 38)

    table.insert(widgets, CreateModernSlider(rightCol, "Tank Height", 0, R.y, 240, 16, 120, 1,
        function()
            local raidH = tonumber(db.h) or 46
            return tonumber(db.tankH) or (raidH + 6)
        end,
        function(v) db.tankH = v end,
        OnChanged, true)); NextY(R, 38)

    table.insert(widgets, CreateModernSlider(rightCol, "Tank Spacing", 0, R.y, 240, 0, 30, 1,
        function()
            local s = tonumber(db.tankSpacing)
            if s == nil then s = tonumber(db.spacing) or 4 end
            return s
        end,
        function(v) db.tankSpacing = v end,
        OnChanged, true)); NextY(R, 38)

    table.insert(widgets, CreateModernSlider(rightCol, "Tank Offset X", 0, R.y, 240, -800, 800, 1,
        function()
            local raidW = tonumber(db.w) or 160
            local tw = tonumber(db.tankW) or (raidW + 20)
            local off = tonumber(db.tankOffsetX)
            if off == nil then
                if (db.tankSide or "LEFT") == "RIGHT" then
                    off = raidW + 20
                else
                    off = -(tw + 12)
                end
            end
            return off
        end,
        function(v) db.tankOffsetX = v end,
        OnChanged, true)); NextY(R, 38)

    table.insert(widgets, CreateModernSlider(rightCol, "Tank Offset Y", 0, R.y, 240, -400, 400, 1,
        function()
            local off = tonumber(db.tankOffsetY)
            if off == nil then off = 0 end
            return off
        end,
        function(v) db.tankOffsetY = v end,
        OnChanged, true)); NextY(R, 38)

    panel.Refresh = Refresh

    local ef = CreateFrame("Frame", nil, panel)
    ef:RegisterEvent("PLAYER_REGEN_DISABLED")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:SetScript("OnEvent", function()
        if ownerFrame and ownerFrame.IsShown and ownerFrame:IsShown() and panel:IsShown() then
            Refresh()
        end
    end)

    return panel
end

-- ============================================================================
-- Mouseover / click-cast bindings.
--
-- This tab used to contain a title, one line of text and a button that opened
-- a second window in a completely different visual style. The bindings now live
-- here directly, which is the whole point of having a settings panel.
-- ============================================================================
local function BuildMouseoverPanel(parent, ownerFrame)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    local plate = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    plate:SetPoint("TOPLEFT", 8, -8)
    plate:SetPoint("BOTTOMRIGHT", -8, 8)
    ApplySoftPanel(plate)

    CreateSectionTitle(plate, "Mouseover / Click Healing", 16, -16)

    local info = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", 16, -42)
    info:SetWidth(560)
    info:SetJustifyH("LEFT")
    info:SetText("Press |cffffd100Add Binding|r, drag a spell from your spellbook, then hold any modifier and press a key or click a mouse button.")

    local warn = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    warn:SetPoint("TOPLEFT", 16, -76)
    warn:SetWidth(560)
    warn:SetJustifyH("LEFT")
    warn:SetText("|cffffaa00SHIFT + keyboard may not work for hover casting. SHIFT with the mouse is fine.|r")

    -- ------------------------------------------------------------
    -- Binding list
    -- ------------------------------------------------------------
    local listBG = CreateFrame("Frame", nil, plate, "BackdropTemplate")
    listBG:SetPoint("TOPLEFT", 16, -106)
    listBG:SetSize(560, 380)
    listBG:SetBackdrop({ bgFile = TEX, edgeFile = TEX, edgeSize = 1 })
    listBG:SetBackdropColor(0.08, 0.08, 0.08, 1)
    listBG:SetBackdropBorderColor(0, 0, 0, 1)

    local sf = CreateFrame("ScrollFrame", nil, listBG, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -28, 6)

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)

    local emptyText = listBG:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyText:SetPoint("CENTER", listBG, "CENTER", 0, 0)
    emptyText:SetText("|cff888888No bindings yet.|r")
    emptyText:Hide()

    local rows = {}

    local function Row(i)
        local r = rows[i]
        if r then return r end

        r = CreateFrame("Frame", nil, content, "BackdropTemplate")
        r:SetHeight(26)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 28)
        r:SetPoint("TOPRIGHT", 0, -(i - 1) * 28)
        r:SetBackdrop({ bgFile = TEX })
        r:SetBackdropColor(0.12, 0.12, 0.12, 0.6)

        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(20, 20)
        r.icon:SetPoint("LEFT", 4, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        r.spell = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        r.spell:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.spell:SetJustifyH("LEFT")

        r.kind = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.kind:SetPoint("RIGHT", r, "RIGHT", -190, 0)
        r.kind:SetJustifyH("RIGHT")

        r.key = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.key:SetPoint("RIGHT", r, "RIGHT", -70, 0)
        r.key:SetJustifyH("RIGHT")

        r.del = CreateModernButton(r, "Remove", 0, 0, 60, 20)
        r.del:ClearAllPoints()
        r.del:SetPoint("RIGHT", -4, 0)

        rows[i] = r
        return r
    end

    local RefreshList

    -- ------------------------------------------------------------
    -- Capture overlay: drag a spell, then press a key or click
    -- ------------------------------------------------------------
    local capture = CreateFrame("Frame", nil, plate, "BackdropTemplate")
    capture:SetPoint("TOPLEFT", 16, -106)
    capture:SetSize(560, 380)
    capture:SetFrameStrata("DIALOG")
    capture:SetBackdrop({ bgFile = TEX, edgeFile = TEX, edgeSize = 1 })
    capture:SetBackdropColor(0.04, 0.04, 0.04, 0.97)
    capture:SetBackdropBorderColor(1, 0.82, 0, 0.8)
    capture:EnableMouse(true)
    capture:Hide()

    local capTitle = capture:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    capTitle:SetPoint("CENTER", capture, "CENTER", 0, 40)
    capTitle:SetText("")

    local capSub = capture:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    capSub:SetPoint("CENTER", capture, "CENTER", 0, 6)
    capSub:SetWidth(460)
    capSub:SetJustifyH("CENTER")
    capSub:SetText("")

    local capKeyBox = CreateFrame("EditBox", nil, capture)
    capKeyBox:SetSize(1, 1)
    capKeyBox:SetAutoFocus(false)
    capKeyBox:EnableKeyboard(true)

    local pendingSpell = nil

    local function EndCapture()
        pendingSpell = nil
        if ns.ClickCast then ns.ClickCast:StopWatchCursor() end
        capKeyBox:ClearFocus()
        capture:Hide()
        if RefreshList then RefreshList() end
    end

    local function CommitBinding(kind, key)
        local CC = ns.ClickCast
        if not CC or not pendingSpell then EndCapture() return end

        local ok, err = CC:Set(kind, key, pendingSpell)
        if not ok then
            capSub:SetText("|cffff6666" .. tostring(err) .. "|r")
            return
        end
        EndCapture()
    end

    capture:SetScript("OnMouseDown", function(_, button)
        if not pendingSpell then return end
        local CC = ns.ClickCast
        if not CC then return end
        CommitBinding("CLICK", CC:ClickFromEvent(button))
    end)

    capKeyBox:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then EndCapture() return end
        if not pendingSpell then return end

        local CC = ns.ClickCast
        if not CC or CC:IsPureModifier(key) then return end

        CommitBinding("KEY", CC:KeyFromEvent(key))
    end)

    capture:SetScript("OnHide", function() capKeyBox:ClearFocus() end)

    local function BeginCapture()
        local CC = ns.ClickCast
        if not CC then return end
        if InCombat() then return end

        pendingSpell = nil
        capTitle:SetText("Drag a spell here")
        capSub:SetText("Open your spellbook and drag a spell onto this panel.\n|cff888888Escape to cancel.|r")
        capture:Show()

        CC:WatchCursor(function(spellName)
            pendingSpell = spellName
            capTitle:SetText(spellName)
            capSub:SetText("Now hold any modifier and |cffffd100press a key|r, or |cffffd100click a mouse button|r.\n|cff888888Escape to cancel.|r")
            capKeyBox:SetFocus()
        end)
    end

    -- ------------------------------------------------------------
    -- List refresh
    -- ------------------------------------------------------------
    RefreshList = function()
        local CC = ns.ClickCast
        local list = CC and CC:GetBindings() or {}

        content:SetHeight(math.max(1, #list * 28))
        emptyText:SetShown(#list == 0)

        for i, b in ipairs(list) do
            local r = Row(i)
            r:Show()

            r.icon:SetTexture(GetSpellTexture and GetSpellTexture(b.spell) or 134400)
            r.spell:SetText(b.spell)
            r.kind:SetText(b.kind == "CLICK" and "mouse" or "key")
            r.key:SetText("|cffffd100" .. tostring(b.label) .. "|r")

            r.del:SetScript("OnClick", function()
                if InCombat() then return end
                if CC then CC:Delete(b.kind, b.key) end
                RefreshList()
            end)
        end

        for i = #list + 1, #rows do
            rows[i]:Hide()
        end
    end

    -- ------------------------------------------------------------
    -- Buttons
    -- ------------------------------------------------------------
    CreateModernButton(plate, "Add Binding", 16, -496, 140, 26, function()
        if InCombat() then return end
        BeginCapture()
    end)

    CreateModernButton(plate, "Clear All", 166, -496, 110, 26, function()
        if InCombat() then return end
        if ns.ClickCast then ns.ClickCast:ClearAll() end
        RefreshList()
    end)

    CreateModernButton(plate, "Bind Viewer", 286, -496, 120, 26, function()
        ExecuteSlash("/ohbinds")
    end)

    CreateModernButton(plate, "Legacy Window", 416, -496, 130, 26, function()
        if InCombat() then return end
        if _G.SlashCmdList and _G.SlashCmdList.OPENHEAL then
            _G.SlashCmdList.OPENHEAL("legacy")
        end
    end)

    local function Refresh()
        if ownerFrame and ownerFrame.combatText then
            ownerFrame.combatText:SetText(InCombat() and "In combat: changes locked." or "")
        end
        RefreshList()
    end

    panel.Refresh = Refresh
    RefreshList()
    return panel
end

local function BuildBindViewPanel(parent, ownerFrame)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    local widgets = {}

    local function Refresh()
        if ownerFrame and ownerFrame.combatText then
            ownerFrame.combatText:SetText(InCombat() and "In combat: changes locked." or "")
        end
        for _, w in ipairs(widgets) do
            if w.Refresh then w:Refresh() end
        end
    end

    local function Changed()
        Refresh()
        CallBindViewRebuild()
    end

    local plate = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    plate:SetPoint("TOPLEFT", 8, -8)
    plate:SetPoint("BOTTOMRIGHT", -8, 8)
    ApplySoftPanel(plate)

    local leftCol = CreateFrame("Frame", nil, plate)
    leftCol:SetPoint("TOPLEFT", 16, -16)
    leftCol:SetPoint("BOTTOMLEFT", 16, 16)
    leftCol:SetWidth(300)

    local midCol = CreateFrame("Frame", nil, plate)
    midCol:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", 24, 0)
    midCol:SetPoint("BOTTOMLEFT", leftCol, "BOTTOMRIGHT", 24, 0)
    midCol:SetWidth(300)

    local function NewCursor(startY) return { y = startY or -8 } end
    local function NextY(cur, dy) cur.y = cur.y - (dy or 24) return cur.y end

    local L = NewCursor(0)
    local M = NewCursor(0)

    -- LEFT COLUMN
    CreateSectionTitle(leftCol, "Multi Focus General", 0, L.y); NextY(L, 28)

    table.insert(widgets, CreateModernCheck(leftCol, "Enabled", 0, L.y,
        function() return GetBindViewDB().enabled end, function(v) GetBindViewDB().enabled = v end, Changed, true)); NextY(L, 24)

    table.insert(widgets, CreateModernCheck(leftCol, "Locked (hides mover)", 0, L.y,
        function() return GetBindViewDB().locked end, function(v) GetBindViewDB().locked = v end, Changed, true)); NextY(L, 24)

    table.insert(widgets, CreateModernCheck(leftCol, "Show Mover", 0, L.y,
        function() return GetBindViewDB().showMover end, function(v) GetBindViewDB().showMover = v end, Changed, true)); NextY(L, 24)

    table.insert(widgets, CreateModernCheck(leftCol, "Show Power Bar", 0, L.y,
        function() return GetBindViewDB().showPower end, function(v) GetBindViewDB().showPower = v end, Changed, true)); NextY(L, 24)

    table.insert(widgets, CreateModernCheck(leftCol, "Class Color HP", 0, L.y,
        function() return GetBindViewDB().classColor end, function(v) GetBindViewDB().classColor = v end, Changed, true)); NextY(L, 34)

    CreateSectionTitle(leftCol, "Layout", 0, L.y); NextY(L, 28)

    local ddOrient = CreateModernDropdown(leftCol, "Orientation", 0, L.y, 220, {
        { text="VERTICAL",   value="VERTICAL" },
        { text="HORIZONTAL", value="HORIZONTAL" },
    }, function() return GetBindViewDB().orientation end, function(v) GetBindViewDB().orientation = v end, Changed, true)
    table.insert(widgets, ddOrient); NextY(L, 48)

    -- MID COLUMN
    CreateSectionTitle(midCol, "Sizing & Tools", 0, M.y); NextY(M, 28)

    table.insert(widgets, CreateModernSlider(midCol, "Width", 0, M.y, 260, 80, 420, 1,
        function() return GetBindViewDB().w end, function(v) GetBindViewDB().w = v end, Changed, true)); NextY(M, 48)

    table.insert(widgets, CreateModernSlider(midCol, "Height", 0, M.y, 260, 18, 80, 1,
        function() return GetBindViewDB().h end, function(v) GetBindViewDB().h = v end, Changed, true)); NextY(M, 48)

    table.insert(widgets, CreateModernSlider(midCol, "Spacing", 0, M.y, 260, 0, 30, 1,
        function() return GetBindViewDB().spacing end, function(v) GetBindViewDB().spacing = v end, Changed, true)); NextY(M, 56)

    CreateModernButton(midCol, "Toggle Simulation", 0, M.y, 140, 24, function()
        if InCombat() then return end
        local BV = ns.BindView
        if BV and BV.SetSimulation then
            BV:SetSimulation(not BV.simulation)
        end
    end)
    NextY(M, 34)

    CreateModernButton(midCol, "Reset Defaults", 0, M.y, 140, 24, function()
        if InCombat() then return end
        local db = GetBindViewDB()
        wipe(db)
        DeepCopyDefaults(db, DEFAULT_BINDVIEW_DB)
        Changed()
    end)

    panel.Refresh = Refresh
    return panel
end

-- ============================================================================
-- NEW: Profiles Panel & Helpers
-- ============================================================================
local function Profiles()
    return ns and ns.Profile or nil
end

local function BuildProfileItems()
    local P = Profiles()
    local items = {}
    if not P or not P.List then
        items[1] = { text = "Default", value = "Default" }
        return items
    end

    local list = P:List()
    for i = 1, #list do
        local name = list[i]
        items[#items+1] = { text = name, value = name }
    end
    if #items == 0 then
        items[1] = { text = "Default", value = "Default" }
    end
    return items
end

local function BuildProfilePanel(parent, ownerFrame)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    local plate = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    plate:SetPoint("TOPLEFT", 8, -8)
    plate:SetPoint("BOTTOMRIGHT", -8, 8)
    ApplySoftPanel(plate)

    local x = 16
    local y = -16

    CreateSectionTitle(plate, "Profile Management", x, y); y = y - 28

    local currentLabel = plate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    currentLabel:SetPoint("TOPLEFT", x, y)
    currentLabel:SetText("Active Profile: |cFFFFD100...|r")
    y = y - 30

    local specLabel = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    specLabel:SetPoint("TOPLEFT", x, y)
    specLabel:SetText("")
    specLabel:SetTextColor(0.85, 0.85, 0.85, 1)
    y = y - 26

    local nameEB = CreateFrame("EditBox", nil, plate, "InputBoxTemplate")
    nameEB:SetSize(225, 22)
    nameEB:SetPoint("TOPLEFT", x, y)
    nameEB:SetAutoFocus(false)
    nameEB.Left:Hide(); nameEB.Middle:Hide(); nameEB.Right:Hide()
    local ebBG = nameEB:CreateTexture(nil, "BACKGROUND")
    ebBG:SetAllPoints()
    ebBG:SetColorTexture(0.05, 0.05, 0.05, 1)
    nameEB:SetText("")

    local nameHint = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameHint:SetPoint("LEFT", nameEB, "RIGHT", 10, 0)
    nameHint:SetText("Name for New/Copy")
    nameHint:SetTextColor(0.7, 0.7, 0.7, 1)

    y = y - 44

    local ddProfile
    local ddItems = BuildProfileItems()

    ddProfile = CreateModernDropdown(plate, "Select Profile", x, y, 225, ddItems,
        function()
            local P = Profiles()
            if P and P.GetActive then return P:GetActive() end
            if ns and ns.GetActiveProfileKey then return ns:GetActiveProfileKey() end
            return "Default"
        end,
        function(v)
            if InCombat() then return end
            local P = Profiles()
            if P and P.SetActive then
                P:SetActive(v, false)
            elseif ns and ns.SetActiveProfile then
                ns:SetActiveProfile(v, false)
            end
            if panel.Refresh then panel:Refresh() end
        end,
        function()
            if panel.Refresh then panel:Refresh() end
        end,
        true
    )

    y = y - 62

    -- Auto-load toggle
    local autoCheck = CreateModernCheck(plate, "Auto load profile on spec change", x, y,
        function()
            local P = Profiles()
            if P and P.IsAutoLoadEnabled then return P:IsAutoLoadEnabled() end
            local db = ns:GetDB()
            if not db then return false end
            db.profileOpts = db.profileOpts or {}
            return db.profileOpts.autoLoadOnSpecChange and true or false
        end,
        function(v)
            local P = Profiles()
            if P and P.SetAutoLoadEnabled then
                P:SetAutoLoadEnabled(v)
            else
                local db = ns:GetDB()
                if not db then return end
                db.profileOpts = db.profileOpts or {}
                db.profileOpts.autoLoadOnSpecChange = v and true or false
            end
            if panel.Refresh then panel:Refresh() end
        end,
        nil,
        false
    )
    y = y - 28

    -- Bind/Clear bind buttons
    CreateModernButton(plate, "Bind active to spec", x, y, 150, 24, function()
        if InCombat() then return end
        local P = Profiles()
        if P and P.BindActiveToCurrentSpec then
            P:BindActiveToCurrentSpec()
            if panel.Refresh then panel:Refresh() end
        end
    end)

    CreateModernButton(plate, "Clear spec bind", x + 170, y, 130, 24, function()
        if InCombat() then return end
        local P = Profiles()
        if P and P.ClearBindingForCurrentSpec then
            P:ClearBindingForCurrentSpec()
            if panel.Refresh then panel:Refresh() end
        end
    end)

    y = y - 40

    -- CRUD buttons
    CreateModernButton(plate, "New Profile", x, y, 105, 24, function()
        if InCombat() then return end
        local P = Profiles()
        local name = nameEB:GetText()
        if P and P.Create then
            if P:Create(name, nil) then
                P:SetActive(name, false)
            end
        end
        nameEB:SetText("")
        if panel.Refresh then panel:Refresh() end
    end)

    CreateModernButton(plate, "Copy Active", x + 120, y, 105, 24, function()
        if InCombat() then return end
        local P = Profiles()
        local newName = nameEB:GetText()
        if P and P.Copy and P.GetActive then
            local current = P:GetActive()
            if P:Copy(current, newName) then
                P:SetActive(newName, false)
            end
        end
        nameEB:SetText("")
        if panel.Refresh then panel:Refresh() end
    end)

    y = y - 36

    CreateModernButton(plate, "Delete", x, y, 105, 24, function()
        if InCombat() then return end
        local P = Profiles()
        if P and P.Delete and P.GetActive then
            P:Delete(P:GetActive())
        end
        if panel.Refresh then panel:Refresh() end
    end)

    CreateModernButton(plate, "Reset Defaults", x + 120, y, 105, 24, function()
        if InCombat() then return end
        local P = Profiles()
        if P and P.Reset and P.GetActive then
            P:Reset(P:GetActive())
        end
        if panel.Refresh then panel:Refresh() end
    end)

    local function RefreshTexts()
        local P = Profiles()
        local active = "Default"
        if P and P.GetActive then active = P:GetActive()
        elseif ns and ns.GetActiveProfileKey then active = ns:GetActiveProfileKey()
        end
        currentLabel:SetText("Active Profile: |cFFFFD100" .. tostring(active) .. "|r")

        local bound = nil
        if P and P.GetBoundProfileForSpec then
            local specIndex = GetSpecialization and GetSpecialization()
            local specID = specIndex and GetSpecializationInfo and GetSpecializationInfo(specIndex) or nil
            if specID then
                bound = P:GetBoundProfileForSpec(specID)
            end
        end

        if bound then
            specLabel:SetText("Spec binding: |cFFFFD100" .. tostring(bound) .. "|r")
        else
            specLabel:SetText("Spec binding: |cFF888888none|r")
        end
    end

    -- ------------------------------------------------------------
    -- Import / Export
    --
    -- Worth having for sharing, but the real reason is backup: this is the
    -- only way to get a layout back after a corrupted SavedVariables file.
    -- ------------------------------------------------------------
    local ioX = 470
    local ioY = -16

    CreateSectionTitle(plate, "Import / Export", ioX, ioY); ioY = ioY - 28

    local ioHelp = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ioHelp:SetPoint("TOPLEFT", ioX, ioY)
    ioHelp:SetWidth(360)
    ioHelp:SetJustifyH("LEFT")
    ioHelp:SetText("|cffaaaaaaExport writes the ACTIVE profile into the box below. Copy it somewhere safe before a patch. To import, paste a string and press Import.|r")
    ioY = ioY - 44

    local ioBoxBG = CreateFrame("Frame", nil, plate, "BackdropTemplate")
    ioBoxBG:SetPoint("TOPLEFT", ioX, ioY)
    ioBoxBG:SetSize(360, 150)
    ioBoxBG:SetBackdrop({ bgFile = TEX, edgeFile = TEX, edgeSize = 1 })
    ioBoxBG:SetBackdropColor(0.05, 0.05, 0.05, 1)
    ioBoxBG:SetBackdropBorderColor(0, 0, 0, 1)

    local ioScroll = CreateFrame("ScrollFrame", nil, ioBoxBG, "UIPanelScrollFrameTemplate")
    ioScroll:SetPoint("TOPLEFT", 6, -6)
    ioScroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local ioEdit = CreateFrame("EditBox", nil, ioScroll)
    ioEdit:SetMultiLine(true)
    ioEdit:SetAutoFocus(false)
    ioEdit:SetFontObject("GameFontHighlightSmall")
    ioEdit:SetWidth(320)
    ioEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ioScroll:SetScrollChild(ioEdit)

    ioY = ioY - 158

    local ioStatus = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ioStatus:SetPoint("TOPLEFT", ioX, ioY)
    ioStatus:SetWidth(360)
    ioStatus:SetJustifyH("LEFT")
    ioStatus:SetText("")
    ioY = ioY - 26

    local function Status(msg, isError)
        if isError then
            ioStatus:SetText("|cffff6666" .. tostring(msg) .. "|r")
        else
            ioStatus:SetText("|cff66ff66" .. tostring(msg) .. "|r")
        end
    end

    CreateModernButton(plate, "Export Active", ioX, ioY, 120, 24, function()
        local X = ns.Transfer
        if not X then Status("export module not loaded", true) return end

        local str, err = X:ExportProfile(ns:GetActiveProfileKey())
        if not str then
            Status(err or "export failed", true)
            return
        end

        ioEdit:SetText(str)
        ioEdit:HighlightText()
        ioEdit:SetFocus()
        Status("Exported. Press Ctrl+C to copy.", false)
    end)

    CreateModernButton(plate, "Import", ioX + 130, ioY, 100, 24, function()
        if InCombat() then Status("cannot import in combat", true) return end

        local X = ns.Transfer
        if not X then Status("import module not loaded", true) return end

        local text = ioEdit:GetText()
        if not text or text == "" then
            Status("paste a profile string first", true)
            return
        end

        -- Decode first so we can report a useful name and refuse junk early.
        local name, _, derr = X:DecodeProfile(text)
        if not name then
            Status(derr or "could not read that string", true)
            return
        end

        -- Never silently overwrite: import under a free name.
        local gdb = ns:GetGlobalDB()
        local target = name
        local n = 2
        while gdb.profiles and gdb.profiles[target] do
            target = name .. " (" .. n .. ")"
            n = n + 1
            if n > 50 then break end
        end

        local ok, res = X:ImportProfile(text, target, false)
        if not ok then
            Status(res or "import failed", true)
            return
        end

        Status("Imported as '" .. tostring(res) .. "'. Select it above to use it.", false)
        if panel.Refresh then panel:Refresh() end
    end)

    CreateModernButton(plate, "Clear", ioX + 240, ioY, 80, 24, function()
        ioEdit:SetText("")
        ioStatus:SetText("")
    end)

    panel.Refresh = function()
        if ownerFrame and ownerFrame.combatText then
            ownerFrame.combatText:SetText(InCombat() and "In combat: changes locked." or "")
        end

        -- Update dropdown items efficiently
        if ddProfile then
            ddProfile.items = BuildProfileItems()
            if ddProfile.Refresh then ddProfile:Refresh() end
        end

        RefreshTexts()
        if autoCheck and autoCheck.Refresh then autoCheck:Refresh() end
    end

    -- initial
    panel:Refresh()
    return panel
end

-- ============================================================================
-- Style panel: look and feel shared by every frame set, plus pets and aggro.
-- ============================================================================
local function BuildStylePanel(parent, ownerFrame)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel:Hide()

    local widgets = {}

    local function Refresh()
        if ownerFrame and ownerFrame.combatText then
            ownerFrame.combatText:SetText(InCombat() and "In combat: changes locked." or "")
        end
        for _, w in ipairs(widgets) do
            if w.Refresh then w:Refresh() end
        end
    end

    -- A style change affects party, raid, pet and tank frames at once.
    local function Changed()
        if ns.Theme then ns.Theme:Bump() end
        Refresh()
        if ns.RequestAllRebuild then ns:RequestAllRebuild() end
    end

    local plate = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    plate:SetPoint("TOPLEFT", 8, -8)
    plate:SetPoint("BOTTOMRIGHT", -8, 8)
    ApplySoftPanel(plate)

    local leftCol = CreateFrame("Frame", nil, plate)
    leftCol:SetPoint("TOPLEFT", 16, -16)
    leftCol:SetSize(260, 700)

    local midCol = CreateFrame("Frame", nil, plate)
    midCol:SetPoint("TOPLEFT", 300, -16)
    midCol:SetSize(260, 700)

    local rightCol = CreateFrame("Frame", nil, plate)
    rightCol:SetPoint("TOPLEFT", 584, -16)
    rightCol:SetSize(260, 700)

    local L, M, R = { y = 0 }, { y = 0 }, { y = 0 }
    local function NextY(col, d) col.y = col.y - d end

    local function StyleDB()
        return ns:GetStyleDB()
    end

    -- ------------------------------------------------------------
    -- LEFT: bars and text
    -- ------------------------------------------------------------
    CreateSectionTitle(leftCol, "Bars & Text", 0, L.y); NextY(L, 28)

    local function TextureItems()
        local out = {}
        for _, e in ipairs(ns.Theme:ListTextures()) do
            out[#out + 1] = { text = e.name, value = e.name }
        end
        return out
    end

    local function FontItems()
        local out = {}
        for _, e in ipairs(ns.Theme:ListFonts()) do
            out[#out + 1] = { text = e.name, value = e.name }
        end
        return out
    end

    table.insert(widgets, CreateModernDropdown(leftCol, "Bar Texture", 0, L.y, 230, TextureItems(),
        function() return StyleDB().barTexture end,
        function(v) StyleDB().barTexture = v end, Changed, true)); NextY(L, 48)

    table.insert(widgets, CreateModernDropdown(leftCol, "Font", 0, L.y, 230, FontItems(),
        function() return StyleDB().font end,
        function(v) StyleDB().font = v end, Changed, true)); NextY(L, 48)

    table.insert(widgets, CreateModernSlider(leftCol, "Font Size", 0, L.y, 230, 8, 18, 1,
        function() return StyleDB().fontSize end,
        function(v) StyleDB().fontSize = v end, Changed, true)); NextY(L, 42)

    table.insert(widgets, CreateModernDropdown(leftCol, "Font Outline", 0, L.y, 230, {
        { text = "Outline",       value = "OUTLINE" },
        { text = "Thick Outline", value = "THICKOUTLINE" },
        { text = "None",          value = "NONE" },
    },
        function() return StyleDB().fontOutline end,
        function(v) StyleDB().fontOutline = v end, Changed, true)); NextY(L, 52)

    local lsmNote = leftCol:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lsmNote:SetPoint("TOPLEFT", 0, L.y)
    lsmNote:SetWidth(230)
    lsmNote:SetJustifyH("LEFT")
    if ns.Theme:HasLSM() then
        lsmNote:SetText("|cff66ff66LibSharedMedia detected|r - extra textures and fonts from your other addons are listed above.")
    else
        lsmNote:SetText("|cffaaaaaaNo LibSharedMedia found. Built-in media only. Any addon that provides LSM (ElvUI, WeakAuras, Details) adds more choices here automatically.|r")
    end
    NextY(L, 60)

    CreateSectionTitle(leftCol, "Colour", 0, L.y); NextY(L, 28)

    table.insert(widgets, CreateModernCheck(leftCol, "Class colour on background", 0, L.y,
        function() return StyleDB().classBG end,
        function(v) StyleDB().classBG = v end, Changed, true)); NextY(L, 22)

    local cbNote = leftCol:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cbNote:SetPoint("TOPLEFT", 0, L.y)
    cbNote:SetWidth(230)
    cbNote:SetJustifyH("LEFT")
    cbNote:SetText("|cffaaaaaaOff: the bar is class coloured. On: the background is, and the bar shows health - easier to read 'how hurt' at a glance.|r")
    NextY(L, 50)

    -- ------------------------------------------------------------
    -- MID: smoothing + aggro
    -- ------------------------------------------------------------
    CreateSectionTitle(midCol, "Health Smoothing", 0, M.y); NextY(M, 28)

    table.insert(widgets, CreateModernCheck(midCol, "Animate health changes", 0, M.y,
        function() return StyleDB().smoothing end,
        function(v) StyleDB().smoothing = v end, Changed, true)); NextY(M, 24)

    table.insert(widgets, CreateModernSlider(midCol, "Smoothing speed (lower = snappier)", 0, M.y, 230, 0.05, 1.0, 0.05,
        function() return StyleDB().smoothRate end,
        function(v) StyleDB().smoothRate = v end, Changed, true, 2)); NextY(M, 44)

    local smNote = midCol:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    smNote:SetPoint("TOPLEFT", 0, M.y)
    smNote:SetWidth(230)
    smNote:SetJustifyH("LEFT")
    smNote:SetText("|cffaaaaaaSmoothing needs a readable health number. Where the game hides health behind a secret value, bars snap instead - no addon can interpolate what it cannot read.|r")
    NextY(M, 62)

    CreateSectionTitle(midCol, "Threat / Aggro", 0, M.y); NextY(M, 28)

    local function AggroDB() return ns:GetAggroDB() end

    table.insert(widgets, CreateModernCheck(midCol, "Show aggro border", 0, M.y,
        function() return AggroDB().enabled end,
        function(v) AggroDB().enabled = v end, Changed, true)); NextY(M, 24)

    table.insert(widgets, CreateModernSlider(midCol, "Border thickness", 0, M.y, 230, 1, 6, 1,
        function() return AggroDB().size end,
        function(v) AggroDB().size = v end, Changed, true)); NextY(M, 42)

    table.insert(widgets, CreateModernCheck(midCol, "Only real aggro", 0, M.y,
        function() return AggroDB().onlyHigh end,
        function(v) AggroDB().onlyHigh = v end, Changed, true)); NextY(M, 24)

    table.insert(widgets, CreateModernCheck(midCol, "Also mark tanks holding threat", 0, M.y,
        function() return AggroDB().showTankSecure end,
        function(v) AggroDB().showTankSecure = v end, Changed, true)); NextY(M, 28)

    CreateSectionTitle(midCol, "Resurrection", 0, M.y); NextY(M, 26)

    local resNote = midCol:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    resNote:SetPoint("TOPLEFT", 0, M.y)
    resNote:SetWidth(230)
    resNote:SetJustifyH("LEFT")
    resNote:SetText("|cffaaaaaaIncoming-res and pending-summon icons are always on. They stop two healers casting on the same corpse.|r")
    NextY(M, 46)

    -- ------------------------------------------------------------
    -- RIGHT: pet frames
    -- ------------------------------------------------------------
    CreateSectionTitle(rightCol, "Pet Frames", 0, R.y); NextY(R, 28)

    local function PetDB() return ns:GetPetDB() end

    local function PetChanged()
        Refresh()
        if ns.RequestPetRebuild then ns:RequestPetRebuild() end
    end

    table.insert(widgets, CreateModernCheck(rightCol, "Enabled", 0, R.y,
        function() return PetDB().enabled end,
        function(v) PetDB().enabled = v end, PetChanged, true)); NextY(R, 24)

    table.insert(widgets, CreateModernCheck(rightCol, "Locked (hide mover)", 0, R.y,
        function() return PetDB().locked end,
        function(v) PetDB().locked = v end, PetChanged, true)); NextY(R, 24)

    table.insert(widgets, CreateModernCheck(rightCol, "Show party pets", 0, R.y,
        function() return PetDB().showParty end,
        function(v) PetDB().showParty = v end, PetChanged, true)); NextY(R, 24)

    table.insert(widgets, CreateModernCheck(rightCol, "Show raid pets", 0, R.y,
        function() return PetDB().showRaid end,
        function(v) PetDB().showRaid = v end, PetChanged, true)); NextY(R, 24)

    table.insert(widgets, CreateModernCheck(rightCol, "Class colour (owner)", 0, R.y,
        function() return PetDB().classColor end,
        function(v) PetDB().classColor = v end, PetChanged, true)); NextY(R, 28)

    table.insert(widgets, CreateModernSlider(rightCol, "Width", 0, R.y, 230, 50, 200, 1,
        function() return PetDB().w end,
        function(v) PetDB().w = v end, PetChanged, true)); NextY(R, 42)

    table.insert(widgets, CreateModernSlider(rightCol, "Height", 0, R.y, 230, 12, 60, 1,
        function() return PetDB().h end,
        function(v) PetDB().h = v end, PetChanged, true)); NextY(R, 42)

    table.insert(widgets, CreateModernSlider(rightCol, "Spacing", 0, R.y, 230, 0, 16, 1,
        function() return PetDB().spacing end,
        function(v) PetDB().spacing = v end, PetChanged, true)); NextY(R, 44)

    table.insert(widgets, CreateModernDropdown(rightCol, "Orientation", 0, R.y, 200, {
        { text = "Vertical",   value = "VERTICAL" },
        { text = "Horizontal", value = "HORIZONTAL" },
    },
        function() return PetDB().orientation end,
        function(v) PetDB().orientation = v end, PetChanged, true)); NextY(R, 50)

    CreateModernButton(rightCol, "Reset Pet Pos", 0, R.y, 130, 24, function()
        if InCombat() then return end
        local p = PetDB()
        p.point = "CENTER"; p.relPoint = "CENTER"; p.x = 320; p.y = -140
        PetChanged()
    end)

    panel.Refresh = Refresh
    Refresh()
    return panel
end

-- ============================================================================
-- Tab switching
-- ============================================================================
local function SelectTab(frame, idx)
    frame._selectedTab = idx
    local sdb = GetUIStateDB()
    sdb.lastTab = idx

    if frame._tabs then
        Tab_SetSelected(frame._tabs[1], idx == TAB_PARTY)
        Tab_SetSelected(frame._tabs[2], idx == TAB_RAID)
        Tab_SetSelected(frame._tabs[3], idx == TAB_STYLE)
        Tab_SetSelected(frame._tabs[4], idx == TAB_MOVER)
        Tab_SetSelected(frame._tabs[5], idx == TAB_BINDVIEW)
        Tab_SetSelected(frame._tabs[6], idx == TAB_PROFILES)
    end

    if frame.partyPanel then frame.partyPanel:SetShown(idx == TAB_PARTY) end
    if frame.raidPanel  then frame.raidPanel:SetShown(idx == TAB_RAID)  end
    if frame.stylePanel then frame.stylePanel:SetShown(idx == TAB_STYLE) end
    if frame.mousePanel then frame.mousePanel:SetShown(idx == TAB_MOVER) end
    if frame.bindPanel  then frame.bindPanel:SetShown(idx == TAB_BINDVIEW) end
    if frame.profilePanel then frame.profilePanel:SetShown(idx == TAB_PROFILES) end

    if frame.combatText then
        frame.combatText:SetText(InCombat() and "In combat: changes locked." or "")
    end

    if idx == TAB_RAID then
        local rdb = GetRaidDB()
        EnsureAuraDB(rdb)
        if rdb._simOn then
            Sim:SetEnabled(true)
            Sim:Build()
            Sim:Layout()
        else
            Sim:SetEnabled(false)
        end
    else
        Sim:SetEnabled(false)
    end

    if frame.partyPanel and frame.partyPanel.Refresh then frame.partyPanel:Refresh() end
    if frame.raidPanel  and frame.raidPanel.Refresh  then frame.raidPanel:Refresh() end
    if frame.stylePanel and frame.stylePanel.Refresh then frame.stylePanel:Refresh() end
    if frame.mousePanel and frame.mousePanel.Refresh then frame.mousePanel:Refresh() end
    if frame.bindPanel  and frame.bindPanel.Refresh  then frame.bindPanel:Refresh() end
    if frame.profilePanel and frame.profilePanel.Refresh then frame.profilePanel:Refresh() end
end

-- ============================================================================
-- Public: EnsureUI / Open / Init  
-- ============================================================================
function S:EnsureUI()
    if self.frame then return end

    local f = CreateFrame("Frame", "OpenHealSettings", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(900, 820)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    ApplyMainBackdrop(f)
    f:Hide()

    local titleBar = CreateTitleBar(f, "OpenHeal – Settings")
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    f:SetMovable(true)

    titleBar:SetScript("OnDragStart", function()
        if InCombat() then return end
        f:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if InCombat() then return end
        SaveMainPos(f)
    end)

    local combat = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    combat:SetPoint("TOP", titleBar, "BOTTOM", 0, -6)
    combat:SetTextColor(1, 0.3, 0.3, 1)
    combat:SetText("")
    f.combatText = combat

    local tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -38)
    tabBar:SetSize(500, 26)

    local tabLine = tabBar:CreateTexture(nil, "BACKGROUND")
    tabLine:SetPoint("BOTTOMLEFT", tabBar, "BOTTOMLEFT", 0, 0)
    tabLine:SetPoint("BOTTOMRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
    tabLine:SetHeight(1)
    tabLine:SetColorTexture(1, 1, 1, 0.15)

    local tab1 = CreateModernTab(tabBar, "Party", 95)
    tab1:SetPoint("LEFT", tabBar, "LEFT", 0, 0)
    tab1:SetScript("OnClick", function() SelectTab(f, TAB_PARTY) end)

    local tab2 = CreateModernTab(tabBar, "Raid", 95)
    tab2:SetPoint("LEFT", tab1, "RIGHT", 4, 0)
    tab2:SetScript("OnClick", function() SelectTab(f, TAB_RAID) end)

    local tab3 = CreateModernTab(tabBar, "Style", 95)
    tab3:SetPoint("LEFT", tab2, "RIGHT", 4, 0)
    tab3:SetScript("OnClick", function() SelectTab(f, TAB_STYLE) end)

    local tab4 = CreateModernTab(tabBar, "Mouseover", 95)
    tab4:SetPoint("LEFT", tab3, "RIGHT", 4, 0)
    tab4:SetScript("OnClick", function() SelectTab(f, TAB_MOVER) end)

    local tab5 = CreateModernTab(tabBar, "Multi Focus", 95)
    tab5:SetPoint("LEFT", tab4, "RIGHT", 4, 0)
    tab5:SetScript("OnClick", function() SelectTab(f, TAB_BINDVIEW) end)

    local tab6 = CreateModernTab(tabBar, "Profiles", 95)
    tab6:SetPoint("LEFT", tab5, "RIGHT", 4, 0)
    tab6:SetScript("OnClick", function() SelectTab(f, TAB_PROFILES) end)

    f._tabs = { tab1, tab2, tab3, tab4, tab5, tab6 }
    tabBar:SetSize(600, 26)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 12, -70)
    content:SetPoint("BOTTOMRIGHT", -12, 50)

    f.partyPanel = BuildPartyPanel(content, f)
    f.raidPanel  = BuildRaidPanel(content, f)
    f.stylePanel = BuildStylePanel(content, f)
    f.mousePanel = BuildMouseoverPanel(content, f)
    f.bindPanel  = BuildBindViewPanel(content, f)
    f.profilePanel = BuildProfilePanel(content, f)

    local btnClose = CreateModernButton(f, "Close", 0, 0, 90, 24, function() f:Hide() end)
    btnClose:ClearAllPoints()
    btnClose:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)

    local btnApply = CreateModernButton(f, "Apply/Rebuild", 0, 0, 120, 24, function()
        if InCombat() then return end
        if f._selectedTab == TAB_RAID then 
            CallRaidRebuild() 
        elseif f._selectedTab == TAB_BINDVIEW then
            CallBindViewRebuild()
        else 
            CallPartyRebuild() 
        end
        if f.partyPanel.Refresh then f.partyPanel:Refresh() end
        if f.raidPanel.Refresh then f.raidPanel:Refresh() end
        if f.stylePanel.Refresh then f.stylePanel:Refresh() end
        if f.mousePanel.Refresh then f.mousePanel:Refresh() end
        if f.bindPanel.Refresh then f.bindPanel:Refresh() end
        if f.profilePanel.Refresh then f.profilePanel:Refresh() end
    end)
    btnApply:ClearAllPoints()
    btnApply:SetPoint("RIGHT", btnClose, "LEFT", -10, 0)

    local ef = CreateFrame("Frame", nil, f)
    ef:RegisterEvent("PLAYER_REGEN_DISABLED")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:SetScript("OnEvent", function()
        if f:IsShown() then
            f.combatText:SetText(InCombat() and "In combat: changes locked." or "")
            if f._selectedTab == TAB_RAID and f.raidPanel.Refresh then f.raidPanel:Refresh() end
            if f._selectedTab == TAB_PARTY and f.partyPanel.Refresh then f.partyPanel:Refresh() end
            if f._selectedTab == TAB_STYLE and f.stylePanel.Refresh then f.stylePanel:Refresh() end
            if f._selectedTab == TAB_MOVER and f.mousePanel.Refresh then f.mousePanel:Refresh() end
            if f._selectedTab == TAB_BINDVIEW and f.bindPanel.Refresh then f.bindPanel:Refresh() end
            if f._selectedTab == TAB_PROFILES and f.profilePanel.Refresh then f.profilePanel:Refresh() end
        end
    end)

    f:SetScript("OnShow", function()
        ApplyMainPos(f)
        local sdb = GetUIStateDB()
        local last = tonumber(sdb.lastTab) or TAB_PARTY
        if last < 1 or last > TAB_COUNT then last = TAB_PARTY end
        SelectTab(f, last)
    end)
end

function S:Open(tabIndex)
    self:EnsureUI()
    local f = self.frame
    if not f:IsShown() then f:Show() end
    -- This was hardcoded to 5. Adding the Style tab made TAB_PROFILES = 6,
    -- so /ohprofiles silently opened the window without switching tab.
    if tabIndex and tabIndex >= 1 and tabIndex <= TAB_COUNT then
        SelectTab(f, tabIndex)
    end
end

function S:Init()
    SLASH_OPENHEALSETTINGS1 = "/ohsettings"
    SlashCmdList.OPENHEALSETTINGS = function()
        S:Open(nil)
    end

    SLASH_OPENHEALPARTY1 = "/ohparty"
    SlashCmdList.OPENHEALPARTY = function()
        S:Open(TAB_PARTY)
    end

    SLASH_OPENHEALRAID1 = "/ohraid"
    SlashCmdList.OPENHEALRAID = function()
        S:Open(TAB_RAID)
    end

    SLASH_OPENHEALBINDVIEW1 = "/ohs"
    SlashCmdList.OPENHEALBINDVIEW = function()
        S:Open(TAB_BINDVIEW)
    end
    
    SLASH_OPENHEALPROFILES1 = "/ohprofiles"
    SlashCmdList.OPENHEALPROFILES = function()
        S:Open(TAB_PROFILES)
    end
end

-- ============================================================================
-- Embedded settings build
-- ============================================================================
function S:BuildOpenHeal(parent)
    if not parent then return nil end

    if parent._openhealRoot then
        parent._openhealRoot:Hide()
        parent._openhealRoot:SetParent(nil)
        parent._openhealRoot = nil
    end

    local root = CreateFrame("Frame", nil, parent)
    parent._openhealRoot = root
    root:SetAllPoints()

    local title = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText("OpenHeal – Settings")
    title:SetTextColor(1, 0.82, 0, 1)

    local combat = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    combat:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    combat:SetTextColor(1, 0.3, 0.3, 1)
    combat:SetText("")
    root.combatText = combat

    local tabBar = CreateFrame("Frame", nil, root)
    tabBar:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -54)
    tabBar:SetSize(500, 26)

    local tabLine = tabBar:CreateTexture(nil, "BACKGROUND")
    tabLine:SetPoint("BOTTOMLEFT", tabBar, "BOTTOMLEFT", 0, 0)
    tabLine:SetPoint("BOTTOMRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
    tabLine:SetHeight(1)
    tabLine:SetColorTexture(1, 1, 1, 0.15)

    local tab1 = CreateModernTab(tabBar, "Party", 95)
    tab1:SetPoint("LEFT", tabBar, "LEFT", 0, 0)
    
    local tab2 = CreateModernTab(tabBar, "Raid", 95)
    tab2:SetPoint("LEFT", tab1, "RIGHT", 4, 0)
    
    local tab3 = CreateModernTab(tabBar, "Style", 95)
    tab3:SetPoint("LEFT", tab2, "RIGHT", 4, 0)

    local tab4 = CreateModernTab(tabBar, "Mouseover", 95)
    tab4:SetPoint("LEFT", tab3, "RIGHT", 4, 0)

    local tab5 = CreateModernTab(tabBar, "Multi Focus", 95)
    tab5:SetPoint("LEFT", tab4, "RIGHT", 4, 0)

    local tab6 = CreateModernTab(tabBar, "Profiles", 95)
    tab6:SetPoint("LEFT", tab5, "RIGHT", 4, 0)

    root._tabs = { tab1, tab2, tab3, tab4, tab5, tab6 }
    tabBar:SetSize(600, 26)

    local content = CreateFrame("Frame", nil, root)
    content:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -84)
    content:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, 46)

    root.partyPanel = BuildPartyPanel(content, root)
    root.raidPanel  = BuildRaidPanel(content, root)
    root.stylePanel = BuildStylePanel(content, root)
    root.mousePanel = BuildMouseoverPanel(content, root)
    root.bindPanel  = BuildBindViewPanel(content, root)
    root.profilePanel = BuildProfilePanel(content, root)

    tab1:SetScript("OnClick", function() SelectTab(root, TAB_PARTY) end)
    tab2:SetScript("OnClick", function() SelectTab(root, TAB_RAID) end)
    tab3:SetScript("OnClick", function() SelectTab(root, TAB_STYLE) end)
    tab4:SetScript("OnClick", function() SelectTab(root, TAB_MOVER) end)
    tab5:SetScript("OnClick", function() SelectTab(root, TAB_BINDVIEW) end)
    tab6:SetScript("OnClick", function() SelectTab(root, TAB_PROFILES) end)

    local bApply = CreateModernButton(root, "Apply/Rebuild", 0, 0, 120, 24)
    bApply:ClearAllPoints()
    bApply:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -14, 14)
    bApply:SetScript("OnClick", function()
        if InCombat() then return end
        if root._selectedTab == TAB_RAID then 
            CallRaidRebuild() 
        elseif root._selectedTab == TAB_BINDVIEW then
            CallBindViewRebuild()
        else 
            CallPartyRebuild() 
        end
        if root.partyPanel and root.partyPanel.Refresh then root.partyPanel:Refresh() end
        if root.raidPanel  and root.raidPanel.Refresh  then root.raidPanel:Refresh()  end
        if root.mousePanel and root.mousePanel.Refresh then root.mousePanel:Refresh() end
        if root.bindPanel  and root.bindPanel.Refresh  then root.bindPanel:Refresh() end
        if root.profilePanel  and root.profilePanel.Refresh  then root.profilePanel:Refresh() end
    end)

    local ef = CreateFrame("Frame", nil, root)
    ef:RegisterEvent("PLAYER_REGEN_DISABLED")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:SetScript("OnEvent", function()
        if root:IsShown() then
            if root.combatText then
                root.combatText:SetText(InCombat() and "In combat: changes locked." or "")
            end
            if root._selectedTab == TAB_RAID and root.raidPanel and root.raidPanel.Refresh then root.raidPanel:Refresh() end
            if root._selectedTab == TAB_PARTY and root.partyPanel and root.partyPanel.Refresh then root.partyPanel:Refresh() end
            if root._selectedTab == TAB_MOVER and root.mousePanel and root.mousePanel.Refresh then root.mousePanel:Refresh() end
            if root._selectedTab == TAB_BINDVIEW and root.bindPanel and root.bindPanel.Refresh then root.bindPanel:Refresh() end
            if root._selectedTab == TAB_PROFILES and root.profilePanel and root.profilePanel.Refresh then root.profilePanel:Refresh() end
        end
    end)

    local function SelectLastTab()
        local sdb = GetUIStateDB()
        local last = tonumber(sdb.lastTab) or TAB_PARTY
        if last < 1 or last > TAB_COUNT then last = TAB_PARTY end
        SelectTab(root, last)
    end

    root:SetScript("OnShow", function()
        SelectLastTab()
    end)

    SelectLastTab()

    return root
end
