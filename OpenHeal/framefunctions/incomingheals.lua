-- incomingheals.lua (OpenHeal) - WoW 12.0 / Midnight secret-safe (HIGH VISIBILITY)
-- Predicted incoming heals overlay for party frames.
-- Improvements:
--   - Stronger color/alpha
--   - Bright edge line (glow) at the end of incoming area
--   - Minimum visible width (pixels) for tiny incoming heals

local ADDON, ns = ...
ns = _G[ADDON] or ns

ns.IncomingHeals = ns.IncomingHeals or {}
local IH = ns.IncomingHeals

local pcall = pcall

-- Tuning
local MIN_PX = 6          -- minimum visible width in pixels
local EDGE_PX = 2         -- edge line width
local BAR_A  = 0.55       -- main bar alpha (was 0.35)

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

                                function IH:Attach(frame)
                                if frame._ohIncoming then return end

                                    local clip = EnsureClip(frame)
                                    if not clip then return end

                                        local bar = CreateFrame("StatusBar", nil, clip)
                                        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
                                        -- Stronger, more visible green
                                        bar:SetStatusBarColor(0.2, 1.0, 0.2, BAR_A)
                                        bar:SetMinMaxValues(0, 1)
                                        bar:SetValue(0)
                                        bar:SetFrameLevel((clip:GetFrameLevel() or 0) + 1)
                                        bar:Hide()

                                        -- Bright edge line at the end of incoming region
                                        local edge = bar:CreateTexture(nil, "OVERLAY")
                                        edge:SetColorTexture(0.65, 1.0, 0.65, 0.95)
                                        edge:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
                                        edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
                                        edge:SetWidth(EDGE_PX)
                                        edge:Hide()

                                        -- Min-width visual helper (a small overlay block) when incoming is tiny
                                        local minblk = bar:CreateTexture(nil, "OVERLAY")
                                        minblk:SetColorTexture(0.65, 1.0, 0.65, 0.75)
                                        minblk:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
                                        minblk:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
                                        minblk:SetWidth(MIN_PX)
                                        minblk:Hide()

                                        frame._ohIncoming = bar
                                        bar._edge = edge
                                        bar._minblk = minblk
                                        end

                                        function IH:Update(frame, unit, hCur, hMax)
                                        local bar = frame and frame._ohIncoming
                                        if not bar or not unit or not frame.hp then return end

                                            local db = ns.GetPartyDB and ns:GetPartyDB() or nil
                                            if db and db.showIncomingHeals == false then
                                                bar:Hide()
                                                if bar._edge then bar._edge:Hide() end
                                                    if bar._minblk then bar._minblk:Hide() end
                                                        return
                                                        end

                                                        local calc = EnsureCalc()
                                                        if not calc then
                                                            bar:Hide()
                                                            if bar._edge then bar._edge:Hide() end
                                                                if bar._minblk then bar._minblk:Hide() end
                                                                    return
                                                                    end

                                                                    local ok = pcall(function()
                                                                    UnitGetDetailedHealPrediction(unit, unit, calc)
                                                                    end)
                                                                    if not ok then
                                                                        bar:Hide()
                                                                        if bar._edge then bar._edge:Hide() end
                                                                            if bar._minblk then bar._minblk:Hide() end
                                                                                return
                                                                                end

                                                                                local incoming = calc:GetIncomingHeals()
                                                                                if not NumGT0(incoming) then
                                                                                    bar:Hide()
                                                                                    if bar._edge then bar._edge:Hide() end
                                                                                        if bar._minblk then bar._minblk:Hide() end
                                                                                            return
                                                                                            end

                                                                                            local hp = frame.hp
                                                                                            local hpTex = hp:GetStatusBarTexture()

                                                                                            local maxHP = hMax
                                                                                            if maxHP == nil or (not issecret(maxHP) and (type(maxHP) ~= "number" or maxHP <= 0)) then
                                                                                                -- fallback: show something
                                                                                                bar:SetMinMaxValues(0, 1)
                                                                                                pcall(bar.SetValue, bar, 1)
                                                                                                bar:ClearAllPoints()
                                                                                                bar:SetAllPoints(hp)
                                                                                                bar:Show()
                                                                                                if bar._edge then bar._edge:Show() end
                                                                                                    if bar._minblk then bar._minblk:Hide() end
                                                                                                        return
                                                                                                        end

                                                                                                        -- Clamp only when safe
                                                                                                        if not issecret(incoming) and not issecret(hCur) and not issecret(maxHP)
                                                                                                            and type(hCur) == "number" and type(maxHP) == "number" and maxHP > 0 then
                                                                                                            local missing = maxHP - hCur
                                                                                                            if missing < 0 then missing = 0 end
                                                                                                                if incoming > missing then incoming = missing end
                                                                                                                    if incoming <= 0 then
                                                                                                                        bar:Hide()
                                                                                                                        if bar._edge then bar._edge:Hide() end
                                                                                                                            if bar._minblk then bar._minblk:Hide() end
                                                                                                                                return
                                                                                                                                end
                                                                                                                                end

                                                                                                                                bar:SetMinMaxValues(0, maxHP)
                                                                                                                                pcall(bar.SetValue, bar, incoming)

                                                                                                                                -- Anchor from current HP edge to the right (missing area)
                                                                                                                                bar:ClearAllPoints()
                                                                                                                                if hpTex then
                                                                                                                                    bar:SetPoint("TOPLEFT", hpTex, "TOPRIGHT")
                                                                                                                                    bar:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMRIGHT")
                                                                                                                                    bar:SetPoint("TOPRIGHT", hp, "TOPRIGHT")
                                                                                                                                    bar:SetPoint("BOTTOMRIGHT", hp, "BOTTOMRIGHT")
                                                                                                                                    else
                                                                                                                                        bar:SetAllPoints(hp)
                                                                                                                                        end

                                                                                                                                        bar:Show()
                                                                                                                                        if bar._edge then bar._edge:Show() end

                                                                                                                                            -- Minimum visible width (only when we can safely compute pixels)
                                                                                                                                            if bar._minblk and hpTex and not issecret(incoming) and not issecret(maxHP) and type(incoming) == "number" and type(maxHP) == "number" and maxHP > 0 then
                                                                                                                                                local w = hp:GetWidth() or 0
                                                                                                                                                local px = (incoming / maxHP) * w
                                                                                                                                                if px > 0 and px < MIN_PX then
                                                                                                                                                    bar._minblk:Show()
                                                                                                                                                    else
                                                                                                                                                        bar._minblk:Hide()
                                                                                                                                                        end
                                                                                                                                                        elseif bar._minblk then
                                                                                                                                                            bar._minblk:Hide()
                                                                                                                                                            end
                                                                                                                                                            end
