-- healabsorb.lua (OpenHeal) - WoW 12.0 / Midnight secret-safe
-- Heal absorb overlay for party frames (reverse fill from right edge of current HP).
-- Secret-safe: never tonumber secret values; show if secret or >0.

local ADDON, ns = ...
ns = _G[ADDON] or ns

ns.HealAbsorb = ns.HealAbsorb or {}
local HA = ns.HealAbsorb

local pcall = pcall

local function issecret(v)
if type(_G.issecretvalue) == "function" then
    local ok, r = pcall(_G.issecretvalue, v)
    if ok and r then return true end
        end
        return false
        end

        local function NumGT0(v)
        if v == nil then return false end
            if issecret(v) then return true end
                local ok, r = pcall(function() return v > 0 end)
                return ok and r or false
                end

                local function EnsureClip(frame)
                if frame._ohPredClip then return frame._ohPredClip end
                    if not frame.hp then return nil end

                        local clip = CreateFrame("Frame", nil, frame.hp)
                        clip:SetAllPoints(frame.hp)
                        clip:SetClipsChildren(true)
                        clip:SetFrameLevel((frame.hp:GetFrameLevel() or 0) + 10)

                        frame._ohPredClip = clip
                        return clip
                        end

                        local healCalc
                        local function EnsureCalc()
                        if healCalc then return healCalc end
                            if type(CreateUnitHealPredictionCalculator) == "function" then
                                healCalc = CreateUnitHealPredictionCalculator()
                                end
                                return healCalc
                                end

                                function HA:Attach(frame)
                                if frame._ohHealAbs then return end

                                    local clip = EnsureClip(frame)
                                    if not clip then return end

                                        local bar = CreateFrame("StatusBar", nil, clip)
                                        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
                                        bar:SetStatusBarColor(1.0, 0.0, 0.0, 0.55)
                                        bar:SetMinMaxValues(0, 1)
                                        bar:SetValue(0)

                                        -- Important: heal-absorb is typically shown from the right
                                        if bar.SetReverseFill then bar:SetReverseFill(true) end

                                            bar:SetFrameLevel((clip:GetFrameLevel() or 0) + 2)
                                            bar:Hide()

                                            frame._ohHealAbs = bar
                                            end

                                            function HA:Update(frame, unit, hCur, hMax)
                                            local bar = frame and frame._ohHealAbs
                                            if not bar or not unit or not frame.hp then return end

                                                local db = ns.GetPartyDB and ns:GetPartyDB() or nil
                                                if db and db.showHealAbsorb == false then
                                                    bar:Hide()
                                                    return
                                                    end

                                                    local calc = EnsureCalc()
                                                    if not calc then
                                                        bar:Hide()
                                                        return
                                                        end

                                                        local ok = pcall(function()
                                                        UnitGetDetailedHealPrediction(unit, unit, calc)
                                                        end)
                                                        if not ok then
                                                            bar:Hide()
                                                            return
                                                            end

                                                            local healAbs = calc:GetHealAbsorbs()
                                                            if not NumGT0(healAbs) then
                                                                bar:Hide()
                                                                return
                                                                end

                                                                local maxHP = hMax
                                                                if maxHP == nil or (not issecret(maxHP) and (type(maxHP) ~= "number" or maxHP <= 0)) then
                                                                    -- Fallback: show as "some heal absorb"
                                                                    bar:SetMinMaxValues(0, 1)
                                                                    pcall(bar.SetValue, bar, 1)
                                                                    bar:ClearAllPoints()
                                                                    bar:SetAllPoints(frame.hp)
                                                                    bar:Show()
                                                                    return
                                                                    end

                                                                    bar:SetMinMaxValues(0, maxHP)
                                                                    pcall(bar.SetValue, bar, healAbs)

                                                                    -- Anchor to current HP edge, but reverse fill so it "bites" into the bar from the right side
                                                                    local hp = frame.hp
                                                                    local hpTex = hp:GetStatusBarTexture()

                                                                    bar:ClearAllPoints()
                                                                    if hpTex then
                                                                        bar:SetPoint("TOPRIGHT", hpTex, "TOPRIGHT")
                                                                        bar:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT")
                                                                        bar:SetPoint("TOPLEFT", hp, "TOPLEFT")
                                                                        bar:SetPoint("BOTTOMLEFT", hp, "BOTTOMLEFT")
                                                                        else
                                                                            bar:SetAllPoints(hp)
                                                                            end

                                                                            bar:Show()
                                                                            end
