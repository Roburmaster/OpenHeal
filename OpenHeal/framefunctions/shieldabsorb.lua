-- shieldabsorb.lua (OpenHeal) - WoW 12.0 / Midnight secret-safe
-- Total absorb (shields) overlay for party frames.
-- Same visual behavior as your player frame: SetAllPoints(hp) + ReverseFill(true)
-- => visible even when HP is full.

local ADDON, ns = ...
ns = _G[ADDON] or ns

ns.ShieldAbsorb = ns.ShieldAbsorb or {}
local SA = ns.ShieldAbsorb

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

                        function SA:Attach(frame)
                        if frame._ohShieldAbs then return end

                            local clip = EnsureClip(frame)
                            if not clip then return end

                                local bar = CreateFrame("StatusBar", nil, clip)
                                bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
                                bar:SetStatusBarColor(0.0, 0.6, 1.0, 0.45)
                                bar:SetMinMaxValues(0, 1)
                                bar:SetValue(0)

                                -- Important: makes it visible even at full HP
                                if bar.SetReverseFill then bar:SetReverseFill(true) end

                                    bar:SetFrameLevel((clip:GetFrameLevel() or 0) + 3)
                                    bar:ClearAllPoints()
                                    bar:SetAllPoints(frame.hp)
                                    bar:Hide()

                                    frame._ohShieldAbs = bar
                                    end

                                    function SA:Update(frame, unit, hCur, hMax)
                                    local bar = frame and frame._ohShieldAbs
                                    if not bar or not unit then return end

                                        local db = ns.GetPartyDB and ns:GetPartyDB() or nil
                                        if db and db.showAbsorb == false then
                                            bar:Hide()
                                            return
                                            end

                                            local shields = UnitGetTotalAbsorbs(unit)
                                            if not NumGT0(shields) then
                                                bar:Hide()
                                                return
                                                end

                                                local maxHP = hMax
                                                if maxHP == nil or (not issecret(maxHP) and (type(maxHP) ~= "number" or maxHP <= 0)) then
                                                    bar:SetMinMaxValues(0, 1)
                                                    pcall(bar.SetValue, bar, 1)
                                                    bar:Show()
                                                    return
                                                    end

                                                    bar:SetMinMaxValues(0, maxHP)
                                                    pcall(bar.SetValue, bar, shields)
                                                    bar:Show()
                                                    end
