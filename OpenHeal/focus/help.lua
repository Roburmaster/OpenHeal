-- ============================================================================
-- bindview_tutorial.lua (OpenHeal)
-- Stable tutorial window with working text + scroll + per-char save
--
-- ADD TO .TOC:
--   ## SavedVariablesPerCharacter: OpenHealBindHelpDB
--
-- AUTO:
--   Shows once per character on first load, then only via /ohbindhelp
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns or {}
_G[ADDON] = ns

ns.BindViewTutorial = ns.BindViewTutorial or {}
local T = ns.BindViewTutorial

local CreateFrame = CreateFrame
local UIParent = UIParent

-- ============================================================================
-- Per Character SavedVariable
-- ============================================================================
local function GetDB()
    _G.OpenHealBindHelpDB = _G.OpenHealBindHelpDB or {}
    return _G.OpenHealBindHelpDB
end

-- ============================================================================
-- Slash command list (first page)
-- - If you later add ns.SlashCommands = { "/cmd - desc", ... } we’ll show those.
-- ============================================================================
local function GetSlashCommandsText()
    -- Optional dynamic list if you build one elsewhere
    if ns.SlashCommands and type(ns.SlashCommands) == "table" then
        local out = {}
        for i = 1, #ns.SlashCommands do
            local line = ns.SlashCommands[i]
            if type(line) == "string" and line ~= "" then
                out[#out + 1] = line
            end
        end
        if #out > 0 then
            return table.concat(out, "\n")
        end
    end

    -- Fallback: known commands (edit this list if you add more)
    return table.concat({
        "/openheal  - Open main OpenHeal panel (mouse-over healing / settings)",
        "/ohsettings - Open settings window",
        "/ohparty  - Open Party tab (settings)",
        "/ohraid   - Open Raid tab (settings)",
        "/ohbindview sim     - Toggle BindView simulation",
        "/ohbindview rebuild - Rebuild BindView",
        "/ohbindhelp - Open this tutorial again",
    }, "\n")
end

-- ============================================================================
-- Tutorial Pages
-- ============================================================================
local PAGES = {

{
title = "Start Here (Commands + What This Is)",
body = function()
    return ([[BindView is a 5-slot healing panel.

It lets you pin specific players into fixed slots so you can react faster.
BindView does NOT auto-pick targets — you choose who goes into each slot.

Addon slash commands:
%s

Click NEXT to continue.]]):format(GetSlashCommandsText())
end,
},

{
title = "IMPORTANT – You Must Bind A Key",
body = [[BindView WILL NOT work until you bind the Select/Remove key.

Why?
Because secure unit changes are restricted in combat.
This system is designed to be safe and stable.

Go to:
Game Menu → Options → Keybindings → OpenHeal

Bind:
BindView: Select/Remove

Recommended:
SHIFT + Q

Without this keybind:
• You cannot add players
• You cannot remove players
• The panel will appear empty]],
},

{
title = "How To Add A Player",
body = [[OUT OF COMBAT ONLY

Step 1:
Hover your mouse over a unit frame (raid or party frame).

Step 2:
Press your BindView key (example: SHIFT+Q).

Result:
The player is added to the first empty slot.

If all slots are full, remove one first.]],
},

{
title = "How To Remove A Player",
body = [[OUT OF COMBAT ONLY

Step 1:
Hover your mouse over the BindView slot itself.

Step 2:
Press your BindView key.

Result:
That slot clears immediately.

Tip:
Hovering the HP bar area still counts as hovering the slot.]],
},

{
title = "Combat Behavior",
body = [[During combat:

• Healing works normally
• Click-casting works normally
• Slot changes are LOCKED

If you attempt to change slots during combat,
you will see a warning message.

This is required by Blizzard's secure system.]],
},

{
title = "Final Notes",
body = [[BindView is meant for priority targets.

Best practice:
• Slot 1–2: Tanks
• Slot 3–5: Utility / critical targets

You can reopen this guide anytime with:
/ohbindhelp]],
},

}

-- ============================================================================
-- UI
-- ============================================================================
local function MakeBackdrop(frame)
    frame:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8X8",
        edgeFile="Interface\\Buttons\\WHITE8X8",
        edgeSize=1,
        insets={left=1,right=1,top=1,bottom=1}
    })
    frame:SetBackdropColor(0.05,0.05,0.05,0.95)
    frame:SetBackdropBorderColor(0,0,0,1)
end

function T:Build()
    if self.frame then return end

    local f = CreateFrame("Frame","OpenHealBindViewTutorial",UIParent,"BackdropTemplate")
    f:SetSize(560,420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    MakeBackdrop(f)
    f:Hide()

    -- Big title
    local header = f:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge")
    header:SetPoint("TOP",0,-18)
    header:SetText("OpenHeal – BindView Guide")

    -- Page Title
    local pageTitle = f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    pageTitle:SetPoint("TOPLEFT",20,-58)
    pageTitle:SetJustifyH("LEFT")
    pageTitle:SetWidth(520)

    -- ScrollFrame
    local scroll = CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",20,-88)
    scroll:SetPoint("BOTTOMRIGHT",-40,64)

    local content = CreateFrame("Frame",nil,scroll)
    content:SetSize(1,1)
    scroll:SetScrollChild(content)

    local body = content:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    body:SetPoint("TOPLEFT",0,0)
    body:SetWidth(500)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetSpacing(4)
    body:SetWordWrap(true)

    -- Buttons
    local back = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    back:SetSize(100,24)
    back:SetPoint("BOTTOMLEFT",20,22)
    back:SetText("Back")

    local nextb = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    nextb:SetSize(100,24)
    nextb:SetPoint("BOTTOMRIGHT",-20,22)
    nextb:SetText("Next")

    -- EXIT button (your requirement)
    local exit = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    exit:SetSize(120,24)
    exit:SetPoint("BOTTOM",0,22)
    exit:SetText("Exit")
    exit:SetScript("OnClick", function()
        f:Hide()
    end)

    -- Store refs
    self.frame = f
    self.pageTitle = pageTitle
    self.body = body
    self.scroll = scroll
    self.content = content
    self.page = 1
    self.back = back
    self.next = nextb

    -- Page setter
    function T:SetPage(n)
        if n < 1 then n = 1 end
        if n > #PAGES then n = #PAGES end
        self.page = n

        local p = PAGES[n]
        local title = p.title
        local txt = p.body
        if type(txt) == "function" then
            txt = txt()
        end

        self.pageTitle:SetText(title or "")
        self.body:SetText(txt or "")

        -- Critical: update child height so text always shows + scroll works
        local h = self.body:GetStringHeight() or 1
        self.content:SetHeight(h + 12)
        self.scroll:SetVerticalScroll(0)

        back:SetEnabled(n > 1)
        nextb:SetEnabled(n < #PAGES)
    end

    back:SetScript("OnClick", function()
        T:SetPage((T.page or 1) - 1)
    end)

    nextb:SetScript("OnClick", function()
        T:SetPage((T.page or 1) + 1)
    end)

    -- Persist last page (nice UX)
    f:SetScript("OnHide", function()
        local db = GetDB()
        db.lastPage = tonumber(T.page) or 1
    end)

    f:SetScript("OnShow", function()
        local db = GetDB()
        local p = tonumber(db.lastPage) or 1
        T:SetPage(p)
    end)
end

function T:Show()
    self:Build()
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER")
    self.frame:Show()
end

-- ============================================================================
-- Auto Show Once Per Character
-- ============================================================================
local ef = CreateFrame("Frame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_LOGIN")

local pending = false

ef:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        local db = GetDB()
        if not db.seen then
            db.seen = true
            db.lastPage = 1
            pending = true
        end
        return
    end

    if event == "PLAYER_LOGIN" and pending then
        pending = false
        T:Show()
        return
    end
end)

-- ============================================================================
-- Slash Command
-- ============================================================================
SLASH_OPENHEAL_BINDHELP1 = "/ohbindhelp"
SlashCmdList.OPENHEAL_BINDHELP = function()
    T:Show()
end
