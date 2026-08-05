local ADDON, ns = ...
ns = _G[ADDON] or ns or {}
_G[ADDON] = ns

ns.BindView = ns.BindView or {}

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON then return end
    if ns.BindView.Init then ns.BindView:Init() end
    if ns.BindView.InitBindings then ns.BindView:InitBindings() end
end)
