-- ============================================================================
-- bindview_bindings.lua (OpenHeal)
-- Hidden binding button that Shift+Q will CLICK via Bindings.xml
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns or {}
_G[ADDON] = ns

local BV = ns.BindView
if not BV then
    ns.BindView = ns.BindView or {}
    BV = ns.BindView
end

local CreateFrame = CreateFrame

function BV:InitBindings()
    if self._bindingBtn then return end

    local btn = CreateFrame("Button", "OpenHeal_BindViewKeyButton", UIParent, "SecureActionButtonTemplate")
    btn:Hide()

    btn:SetScript("OnClick", function()
        if ns.BindView and ns.BindView.SelectOrRemove then
            ns.BindView:SelectOrRemove()
        end
    end)

    self._bindingBtn = btn
end
