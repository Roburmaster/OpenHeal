-- ============================================================================
-- dispel.lua (OpenHeal) - WoW 12.0 / Midnight secret-safe
-- Dispel overlay for OUR party frames using Blizzard's secure dispel color API:
--   C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, curve)
--
-- Key: We do NOT rely on aura.dispelName strings (often nil/secret).
-- We scan auras and ask Blizzard for the dispel color. If it returns a color,
-- the aura is dispel-typed and we show a colored border/glow.
--
-- Rendering: StatusBars (their textures handle secret colors safely).
-- ============================================================================

local _, ns = ...
ns.Dispel = ns.Dispel or {}
local D = ns.Dispel

local UnitExists = UnitExists
local CUA = C_UnitAuras
local CCU = C_CurveUtil

local TEX = "Interface\\Buttons\\WHITE8x8"

-- Dispel enum values (common retail): 0=None 1=Magic 2=Curse 3=Disease 4=Poison
-- Extra (some builds): 9=Enrage 11=Bleed (shown as red if present)
local DISPEL_ENUMS = { 0, 1, 2, 3, 4, 9, 11 }

-- Default colors (tweak here if you want)
local COLORS = {
    [1]  = {0.20, 0.60, 1.00}, -- Magic
    [2]  = {0.70, 0.30, 1.00}, -- Curse
    [3]  = {1.00, 0.85, 0.20}, -- Disease
    [4]  = {0.20, 1.00, 0.20}, -- Poison
    [9]  = {1.00, 0.20, 0.20}, -- Enrage (red)
    [11] = {1.00, 0.20, 0.20}, -- Bleed  (red)
}

-- Cached curves
local borderCurve = nil
local glowCurve   = nil

local function BuildCurve(alpha)
if not (CCU and CCU.CreateColorCurve) then return nil end

    local curve = CCU.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)

    -- None => invisible
    curve:AddPoint(0, CreateColor(0, 0, 0, 0))

    for _, enumVal in ipairs(DISPEL_ENUMS) do
        if enumVal ~= 0 then
            local c = COLORS[enumVal]
            if c then
                curve:AddPoint(enumVal, CreateColor(c[1], c[2], c[3], alpha))
                end
                end
                end

                return curve
                end

                local function GetBorderCurve()
                if not borderCurve then
                    borderCurve = BuildCurve(0.95)
                    end
                    return borderCurve
                    end

                    local function GetGlowCurve()
                    if not glowCurve then
                        glowCurve = BuildCurve(0.30)
                        end
                        return glowCurve
                        end

                        local function MakeBorderSB(parent)
                        -- Four StatusBars as borders (secret color safe)
                        local b = {}

                        local function SB()
                        local s = CreateFrame("StatusBar", nil, parent)
                        s:SetStatusBarTexture(TEX)
                        s:SetMinMaxValues(0, 1)
                        s:SetValue(1)
                        s:Hide()
                        if s.SetIgnoreParentAlpha then s:SetIgnoreParentAlpha(true) end
                            return s
                            end

                            b.top    = SB()
                            b.bottom = SB()
                            b.left   = SB()
                            b.right  = SB()

                            return b
                            end

                            local function LayoutBorder(b, parent, size, inset)
                            size  = size or 2
                            inset = inset or 0

                            b.left:ClearAllPoints()
                            b.left:SetPoint("TOPLEFT", parent, "TOPLEFT", -inset, inset)
                            b.left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -inset, -inset)
                            b.left:SetWidth(size)

                            b.right:ClearAllPoints()
                            b.right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", inset, inset)
                            b.right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", inset, -inset)
                            b.right:SetWidth(size)

                            b.top:ClearAllPoints()
                            b.top:SetPoint("TOPLEFT", parent, "TOPLEFT", -inset + size, inset)
                            b.top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", inset - size, inset)
                            b.top:SetHeight(size)

                            b.bottom:ClearAllPoints()
                            b.bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -inset + size, -inset)
                            b.bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", inset - size, -inset)
                            b.bottom:SetHeight(size)
                            end

                            local function ApplyColorToBorder(b, colorObj)
                            -- colorObj is a Color (secure safe); use GetRGBA
                            local r, g, bl, a = colorObj:GetRGBA()

                            local function Set(sb)
                            local tex = sb:GetStatusBarTexture()
                            tex:SetVertexColor(r, g, bl, a)
                            end

                            Set(b.top); Set(b.bottom); Set(b.left); Set(b.right)
                            end

                            local function ShowBorder(b, show)
                            if show then
                                b.top:Show(); b.bottom:Show(); b.left:Show(); b.right:Show()
                                else
                                    b.top:Hide(); b.bottom:Hide(); b.left:Hide(); b.right:Hide()
                                    end
                                    end

                                    local function EnsureGlow(parent)
                                    -- Optional: a soft glow/statusbar overlay (also secret color safe)
                                    local g = CreateFrame("StatusBar", nil, parent)
                                    g:SetStatusBarTexture(TEX)
                                    g:SetMinMaxValues(0, 1)
                                    g:SetValue(1)
                                    g:SetAllPoints(parent)
                                    g:Hide()
                                    g:GetStatusBarTexture():SetBlendMode("ADD")
                                    if g.SetIgnoreParentAlpha then g:SetIgnoreParentAlpha(true) end
                                        return g
                                        end

                                        -- Ask Blizzard for dispel-type color for this auraInstanceID via curve.
                                        -- If not dispel-typed, returns nil.
                                        local function GetAuraColor(unit, auraInstanceID, curve)
                                        if not (CUA and CUA.GetAuraDispelTypeColor) then return nil end
                                            return CUA.GetAuraDispelTypeColor(unit, auraInstanceID, curve)
                                            end

                                            -- Scan auras and return first dispel color (border+glow can use different curves)
                                            local function FindDispelColor(unit)
                                            if not unit or not UnitExists(unit) then return nil end
                                                if not (CUA and CUA.GetAuraDataByIndex) then return nil end

                                                    local bCurve = GetBorderCurve()
                                                    if not bCurve then return nil end

                                                        for i = 1, 40 do
                                                            local aura = CUA.GetAuraDataByIndex(unit, i, "HARMFUL")
                                                            if not aura then break end

                                                                local id = aura.auraInstanceID
                                                                if id then
                                                                    local c = GetAuraColor(unit, id, bCurve)
                                                                    if c then
                                                                        return c, id
                                                                        end
                                                                        end
                                                                        end

                                                                        return nil
                                                                        end

                                                                        -- ------------------------------------------------------------
                                                                        -- Public API
                                                                        -- ------------------------------------------------------------
                                                                        function D:Attach(frame)
                                                                        if frame._ohDispel then return end
                                                                            if not frame.hp then return end

                                                                                local parent = frame.hp

                                                                                local ui = {}
                                                                                ui.parent = parent

                                                                                ui.border = MakeBorderSB(parent)
                                                                                LayoutBorder(ui.border, parent, 2, 0)

                                                                                ui.glow = EnsureGlow(parent)

                                                                                ui.lastOn = nil
                                                                                ui.lastKey = nil

                                                                                frame._ohDispel = ui
                                                                                end

                                                                                function D:Update(frame, unit)
                                                                                if not frame or not frame._ohDispel then return end
                                                                                    local ui = frame._ohDispel

                                                                                    local colorObj, auraInstanceID = FindDispelColor(unit)

                                                                                    if not colorObj then
                                                                                        if ui.lastOn ~= false then
                                                                                            ui.glow:Hide()
                                                                                            ShowBorder(ui.border, false)
                                                                                            ui.lastOn = false
                                                                                            ui.lastKey = nil
                                                                                            end
                                                                                            return
                                                                                            end

                                                                                            -- Re-color only when auraInstanceID changes (cheap cache)
                                                                                            -- auraInstanceID can be a SECRET number; comparing it
                                                                                            -- with the cached key raises. Reduce to a plain value
                                                                                            -- first; nil means "cannot cache", so re-colour every time.
                                                                                            local key = ns.UnitUtil and ns.UnitUtil.ScrubNumber(auraInstanceID) or nil
                                                                                            if key == nil or ui.lastOn ~= true or ui.lastKey ~= key then
                                                                                                -- Border
                                                                                                ApplyColorToBorder(ui.border, colorObj)

                                                                                                -- Glow uses separate curve alpha, so re-query with glow curve
                                                                                                local gCurve = GetGlowCurve()
                                                                                                if gCurve and auraInstanceID then
                                                                                                    local glowColor = GetAuraColor(unit, auraInstanceID, gCurve)
                                                                                                    if glowColor then
                                                                                                        local r, g, bl, a = glowColor:GetRGBA()
                                                                                                        ui.glow:GetStatusBarTexture():SetVertexColor(r, g, bl, a)
                                                                                                        end
                                                                                                        end

                                                                                                        ui.lastOn = true
                                                                                                        ui.lastKey = key
                                                                                                        end

                                                                                                        ui.glow:Show()
                                                                                                        ShowBorder(ui.border, true)
                                                                                                        end

                                                                                                        function D:Init()
                                                                                                        -- nothing needed
                                                                                                        end
