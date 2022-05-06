if Player.CharName ~= "Annie" then return end

local scriptName = "AuAnnie"
local scriptCreator = "AURUM"
local credits = "Orietto"
local patchNotesPrevUpdate = "03/16/2022"
local patchNotesPreVersion = "1.0.1"
local patchNotesVersion, scriptVersionUpdater = "1.0.2", "1.0.2"
local scriptVersion = scriptVersionUpdater
local scriptLastUpdated = "03/17/2022"
local scriptIsBeta = false

if scriptIsBeta then
    scriptVersion = scriptVersion .. " Beta"
else
    scriptVersion = scriptVersion .. " Release"
end

local scriptColor = 0x3C9BF0FF

module(scriptName, package.seeall, log.setup)
clean.module(scriptName, clean.seeall, log.setup)

local insert, sort = table.insert, table.sort
local huge, pow, min, max, floor, pi = math.huge, math.pow, math.min, math.max, math.floor, math.pi

local SDK = _G.CoreEx

SDK.AutoUpdate("https://github.com/roburAURUM/robur-AuEdition/raw/main/AuAnnie.lua", scriptVersionUpdater)

local ObjManager = SDK.ObjectManager
local EventManager = SDK.EventManager
local Geometry = SDK.Geometry
local Renderer = SDK.Renderer
local Enums = SDK.Enums
local Game = SDK.Game
local Input = SDK.Input

local Vector = Geometry.Vector

local Libs = _G.Libs

local Menu = Libs.NewMenu
local Orbwalker = Libs.Orbwalker
local Collision = Libs.CollisionLib
local Prediction = Libs.Prediction
local Spell = Libs.Spell
local DmgLib = Libs.DamageLib
local TS = Libs.TargetSelector()

local Profiler = Libs.Profiler

local slots = {
    Q = Enums.SpellSlots.Q,
    W = Enums.SpellSlots.W,
    E = Enums.SpellSlots.E,
    R = Enums.SpellSlots.R
}

local dmgTypes = {
    Physical = Enums.DamageTypes.Physical,
    Magical = Enums.DamageTypes.Magical,
    True = Enums.DamageTypes.True
}

local damages = {
    Q = {
        Base = {80, 115, 150, 185, 220},
        TotalAP = 0.75,
        Type = dmgTypes.Magical
    },
    W = {
        Base = {70, 115, 160, 205, 250},
        TotalAP  = 0.85,
        Type = dmgTypes.Magical
    },
    R = {
        Base = {150, 275, 400},
        TotalAP = 0.75,
        Type = dmgTypes.Magical
    }
}

local spells = {
    Q = Spell.Targeted({
        Slot = slots.Q,
        Delay = 0.25,
        Speed = 1400,
        Range = 622.5,
    }),
    W = Spell.Skillshot({
        Slot = slots.W,
        Delay = 0.25,
        Speed = huge,
        Range = 600,
        ConeAngleRad = 49.5 * (pi / 180),
        Type = "Cone",
    }),
    E = Spell.Targeted({
        Slot = slots.E,
        Delay = 0.0,
        Speed = huge,
        Range = 800,
    }),
    R = Spell.Skillshot({
        Slot = slots.R,
        Delay = 0.25,
        Speed = huge,
        Range = 600,
        Radius = 185,
        Type = "Circular",
    }),
    Flash = {
        Slot = nil,
        LastCastT = 0,
        LastCheckT = 0,
        Range = 400
    }
}

local events = {}

local combatVariants = {}

local OriUtils = {}

local cacheName = Player.CharName

local jungleCamps = {

    [1] = {name = "SRU_Blue", dName = "Blue Buff", default = true},
    [2] = {name = "SRU_Gromp", dName = "Gromp", default = true},
    [3] = {name = "SRU_Murkwolf", dName = "Big Wolf", default = true},
    [4] = {name = "SRU_MurkwolfMini", dName = "Small Wolf", default = false},
}

local jungleCamps2 = {

    [1] = {name = "SRU_Red", dName = "Red Buff", default = true},
    [2] = {name = "SRU_Razorbeak", dName = "Big Raptor", default = true},
    [3] = {name = "SRU_RazorbeakMini", dName = "Small Raptor", default = false}, 
    [4] = {name = "SRU_Krug", dName = "Big Krug", default = true}, 
    [5] = {name = "SRU_KrugMini", dName = "Medium Krug", default = true}, 
}

local jungleCamps3 = {
    [2] = {name = "SRU_RiftHerald", dName = "Rift Herald", default = true},
    [1] = {name = "SRU_Baron", dName = "Baron Nashor", default = true},
    [3] = {name = "SRU_Dragon_Elder", dName = "Elder Drake", default = true},
    [4] = {name = "Sru_Crab", dName = "Scuttle Crab", default = true},
    
}

---@param unit AIBaseClient
---@param radius number|nil
---@param fromPos Vector|nil
function OriUtils.IsValidTarget(unit, radius, fromPos)
    fromPos = fromPos or Player.ServerPos
    radius = radius or huge

    return unit and unit.MaxHealth > 6 and fromPos:DistanceSqr(unit.ServerPos) < pow(radius, 2) and TS:IsValidTarget(unit)
end

function OriUtils.CastSpell(slot, pos_unit)
    return Input.Cast(slot, pos_unit)
end

function OriUtils.CastFlash(pos)
    if not spells.Flash.Slot then return false end

    local curTime = Game.GetTime()
    if curTime < spells.Flash.LastCastT + 0.25 then return false end

    return OriUtils.CastSpell(spells.Flash.Slot, pos)
end


---@param unit AIBaseClient
function OriUtils.IsDashing(unit)
    unit = unit or Player

    return unit.Pathing.IsDashing
end

---@param unit AIBaseClient
---@return Vector
function OriUtils.GetDashEndPos(unit)
    unit = unit or Player

    --return OriUtils.IsDashing(unit) and unit.Pathing.EndPos
    return unit.Pathing.EndPos
end

function OriUtils.IsSpellReady(slot)
    return Player:GetSpellState(slot) == Enums.SpellStates.Ready
end

function OriUtils.ShouldRunLogic()
    return not (Game.IsChatOpen() or Game.IsMinimized() or Player.IsDead or Player.IsRecalling)
end

function OriUtils.MGet(menuId, nothrow)
    return Menu.Get(cacheName .. "." .. menuId, nothrow)
end

local summSlots = {Enums.SpellSlots.Summoner1, Enums.SpellSlots.Summoner2}
function OriUtils.CheckFlashSlot()
    local curTime = Game.GetTime()

    if curTime < spells.Flash.LastCheckT + 1 then return end

    spells.Flash.LastCheckT = curTime

    local function IsFlash(slot)
        return Player:GetSpell(slot).Name == "SummonerFlash"
    end

    for _, slot in ipairs(summSlots) do
        if IsFlash(slot) then
            if spells.Flash.Slot ~= slot then
                INFO("Flash was found on %d", slot)
                
                spells.Flash.Slot = slot
            end

            return
        end
    end

    if spells.Flash.Slot ~= nil then
        INFO("Flash was lost")

        spells.Flash.Slot = nil
    end
end

function OriUtils.CanCastSpell(slot, menuId)
    return OriUtils.IsSpellReady(slot) and OriUtils.MGet(menuId)
end

---@return AIMinionClient[]
function OriUtils.GetEnemyAndJungleMinions(radius, fromPos)
    fromPos = fromPos or Player.ServerPos

    local result = {}

    ---@param group GameObject[]
    local function AddIfValid(group)
        for _, unit in ipairs(group) do
            local minion = unit.AsMinion

            if OriUtils.IsValidTarget(minion, radius, fromPos) then
                result[#result+1] = minion
            end
        end
    end

    local enemyMinions = ObjManager.GetNearby("enemy", "minions")
    local jungleMinions = ObjManager.GetNearby("neutral", "minions")

    AddIfValid(enemyMinions)
    AddIfValid(jungleMinions)

    return result
end

function OriUtils.GetFirstElementSort(tbl, compareFunc)
    local first = nil

    for i, v in ipairs(tbl) do
        if first == nil then
            first = v
        else
            if compareFunc(v, first) then
                first = v
            end
        end
    end

    return first
end

function OriUtils.AddDrawMenu(data)
    for _, element in ipairs(data) do
        local id = element.id
        local displayText = element.displayText

        Menu.Checkbox(cacheName .. ".draw." .. id, "Draw " .. displayText .. " range", true)
        Menu.Indent(function()
            Menu.ColorPicker(cacheName .. ".draw." .. id .. ".color", "Color", scriptColor)
        end)
    end

    Menu.Separator()

    Menu.Checkbox(cacheName .. ".draw." .. "comboDamage", "Draw combo damage on healthbar", true)Menu.SameLine()
    Menu.Checkbox(cacheName .. ".draw." .. "electorcute", "Include Electrocute if available", true)
    Menu.Checkbox("Annie.drawMenu.AlwaysDraw", "Always show Drawings", false)
end

---@param forcedTarget AIHeroClient
---@param ranges number[]
---@return AIHeroClient|nil
function OriUtils.ChooseTarget(forcedTarget, ranges)
    if forcedTarget and OriUtils.IsValidTarget(forcedTarget) then
        return forcedTarget
    elseif not forcedTarget then
        for _, range in ipairs(ranges) do
            local target = TS:GetTarget(range)

            if target then
                return target
            end
        end
    end

    return nil
end

---@param pos Vector
---@return boolean
function OriUtils.IsPosUnderTurret(pos)
    local enemyTurrets = ObjManager.GetNearby("enemy", "turrets")

    local boundingRadius = Player.BoundingRadius

    for _, obj in ipairs(enemyTurrets) do
        local turret = obj.AsTurret

        if turret and turret.IsValid and not turret.IsDead and pos:DistanceSqr(turret) <= pow(900 + boundingRadius, 2) then
            return true
        end
    end

    return false
end

local drawData = {
    {slot = slots.Q, id = "Q", displayText = "[Q] Disintegrate", range = spells.Q.Range},
    {slot = slots.W, id = "W", displayText = "[W] Incinerate", range = spells.W.Range},
    {slot = slots.E, id = "E", displayText = "[E] Molten Shield", range = spells.E.Range},
    {slot = slots.R, id = "R", displayText = "[R] Summon: Tibbers", range = spells.R.Range}
}

local ASCIIArt = "      /\\            /\\               (_)      "
local ASCIIArt2 = "     /  \\  _   _   /  \\   _ __  _ __  _  ___  "
local ASCIIArt3 = "    / /\\ \\| | | | / /\\ \\ | '_ \\| '_ \\|_|/ _ \\ "
local ASCIIArt4 = "   / ____ \\ |_| |/ ____ \\| | | | | | | |  __/ "
local ASCIIArt5 = "  /_/    \\_\\__,_/_/    \\_\\_| |_|_| |_|_|\\___| "

local Annie = {}

local slotToDamageTable = {
    [slots.Q] = damages.Q,
    [slots.W] = damages.W,
    [slots.R] = damages.R
}

---@param target AIBaseClient
---@param slot slut
function Annie.GetDamage(target, slot)
    local me = Player 
    local rawDamage = 0
    local damageType = nil

    local spellLevel = me:GetSpell(slot).Level

    if spellLevel >= 1 then
        local data = slotToDamageTable[slot]

        if data then
            damageType = data.Type

            rawDamage = rawDamage + data.Base[spellLevel]

            if data.TotalAP then
                rawDamage = rawDamage + (data.TotalAP * me.TotalAP)
            end

            if data.BonusAD then
                rawDamage = rawDamage + (data.BonusAD * me.BonusAD)
            end

            if damageType == dmgTypes.Physical then
                return DmgLib.CalculatePhysicalDamage(me, target, rawDamage)
            elseif damageType == dmgTypes.Magical then
                return DmgLib.CalculateMagicalDamage(me, target, rawDamage)
            else
                return rawDamage
            end
        end
    end

    return 0
end


function OriUtils.GetElectrocuteDamage(target)
    local me = Player

    local bonusAD = me.BonusAD
    local bonusAP = me.BonusAP

    local dmgType = dmgTypes.Physical
    if bonusAP > bonusAD then
        dmgType = dmgTypes.Magical
    end

    local rawDamage = (30 + 150 / 17 * (min(18, me.Level) - 1)) + (0.4 * bonusAD) + (0.25 * me.TotalAP)

    return dmgType == dmgTypes.Physical and DmgLib.CalculatePhysicalDamage(me, target, rawDamage) or DmgLib.CalculateMagicalDamage(me, target, rawDamage)
end


function Annie.flashQ()
    if OriUtils.MGet("misc.flashQ") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)

        if spells.Q:IsReady() and Annie.HasPassive() then
            
            local flashReady = spells.Flash.Slot and OriUtils.IsSpellReady(spells.Flash.Slot)
            if not flashReady then
                return
            end

            local qFlashRange = (spells.Q.Range - 10) + spells.Flash.Range
            local qFlashTarget = TS:GetTarget(qFlashRange, false)
            if qFlashTarget and not spells.Q:IsInRange(qFlashTarget) then
                local flashPos = Player.ServerPos:Extended(qFlashTarget, spells.Flash.Range) 

                local spellInput = {
                    Slot = slots.Q,
                    Delay = 0.25,
                    Speed = 1400,
                    Range = 622.5,
                    Radius = 622.5,
                    Type = "Linear",
                }
                local pred = Prediction.GetPredictedPosition(qFlashTarget, spellInput, flashPos)
                if pred and pred.HitChanceEnum >= Enums.HitChance.Medium then
                    if Input.Cast(spells.Flash.Slot, flashPos) then
                        delay(90, function()spells.Q:Cast(qFlashTarget) end)
                        return
                    end
                end
            end
        end
    end
end

function Annie.flashR()
    if OriUtils.MGet("misc.flashR") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)

        if spells.R:IsReady() and not Annie.TibbersAlive() and Annie.HasPassive() then
            
            local flashReady = spells.Flash.Slot and OriUtils.IsSpellReady(spells.Flash.Slot)
            if not flashReady then
                return
            end

            local rTarget = spells.R:GetTarget()
            local rFlashRange = (spells.R.Range - 10) + spells.Flash.Range
            local rFlashTarget = TS:GetTarget(rFlashRange, false)
            if rFlashTarget and not spells.R:IsInRange(rFlashTarget) then
                local flashPos = Player.ServerPos:Extended(rFlashTarget, spells.Flash.Range)
                local rPos = Player.ServerPos:Extended(rFlashTarget, spells.R.Range)

                local spellInput = {
                    Slot = slots.R,
                    Delay = 0.25,
                    Speed = huge,
                    Range = 600,
                    Radius = 200,
                    Type = "Circular",
                }
                local pred = Prediction.GetPredictedPosition(rFlashTarget, spellInput, flashPos)
                if pred and pred.HitChanceEnum >= Enums.HitChance.Low then
                    if Input.Cast(spells.Flash.Slot, flashPos) then
                        delay(OriUtils.MGet("misc.flashR.delay"), function()spells.R:Cast(rFlashTarget) end)
                        return
                    end
                end
            end
        end
    end
end

function Annie.KS()
    if OriUtils.CanCastSpell(slots.Q, "ks.useQ") or OriUtils.CanCastSpell(slots.W, "ks.useW") or OriUtils.CanCastSpell(slots.R, "ks.useR") then
        local allyHeroes = ObjManager.GetNearby("ally", "heroes")
        for iKSA, objKSA in ipairs(allyHeroes) do
            local ally = objKSA.AsHero
            if not ally.IsMe and not ally.IsDead then
                local nearbyEnemiesKS = ObjManager.GetNearby("enemy", "heroes")
                for iKS, objKS in ipairs(nearbyEnemiesKS) do
                    local target = objKS.AsHero
                    local qDamage = Annie.GetDamage(target, slots.Q)
                    local healthPredQ = spells.Q:GetHealthPred(objKS)
                    local wDamage = Annie.GetDamage(target, slots.W)
                    local healthPredW = spells.W:GetHealthPred(objKS)
                    local rDamage = Annie.GetDamage(target, slots.R)
                    local healthPredR = spells.W:GetHealthPred(objKS)
                    if OriUtils.MGet("ks.useQ") then
                        if OriUtils.IsValidTarget(objKS, spells.Q.Range) then
                            if OriUtils.MGet("ks.qWL." .. target.CharName, true) then
                                if healthPredQ > 0 and healthPredQ < floor(qDamage) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.Q:Cast(target) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                    end      
                    if OriUtils.MGet("ks.useW") then
                        if OriUtils.IsValidTarget(objKS, spells.W.Range) then
                            if OriUtils.MGet("ks.wWL." .. target.CharName, true) then
                                if healthPredW > 0 and healthPredW < floor(wDamage) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.W:CastOnHitChance(target, Enums.HitChance.Medium) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                    end
                    if OriUtils.MGet("ks.useR") and not Annie.TibbersAlive() then
                        if OriUtils.IsValidTarget(objKS, spells.R.Range) then
                            if OriUtils.MGet("ks.rWL." .. target.CharName, true) then
                                if healthPredR > 0 and healthPredR < floor(rDamage) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.R:CastOnHitChance(target, Enums.HitChance.Medium) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function Annie.DrakeSteal()
    if OriUtils.MGet("steal.useQ") or OriUtils.MGet("steal.useW") or OriUtils.MGet("steal.useR") then 
        local enemiesAround = ObjManager.GetNearby("enemy", "heroes")
        for iSteal, objSteal in ipairs(enemiesAround) do
            local enemy = objSteal.AsHero
            if not enemy.IsDead then
                local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
                for iM, minion in ipairs(nearbyMinions) do
                    local minion = minion.AsMinion
                    local qDamage = Annie.GetDamage(minion, slots.Q)
                    local healthPredDrakeQ = spells.Q:GetHealthPred(minion)
                    local wDamage = Annie.GetDamage(minion, slots.W)
                    local healthPredDrakeW = spells.W:GetHealthPred(minion)
                    local rDamage = Annie.GetDamage(minion, slots.R)
                    local healthPredDrakeR = spells.R:GetHealthPred(minion)
                    if not minion.IsDead and minion.IsDragon and minion:Distance(enemy) < 1800 or enemy.IsInDragonPit then
                        if OriUtils.CanCastSpell(slots.Q, "steal.useQ") then
                            if OriUtils.IsValidTarget(minion, spells.Q.Range) then
                                if healthPredDrakeQ > 0 and healthPredDrakeQ < floor(qDamage - 15) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.Q:Cast(minion) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.W, "steal.useW") then
                            if OriUtils.IsValidTarget(minion, spells.W.Range) then
                                if healthPredDrakeW > 0 and healthPredDrakeW < floor(wDamage - 15) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.W:CastOnHitChance(minion, Enums.HitChance.Medium) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.R, "steal.useR") and not Annie.TibbersAlive() then
                            if OriUtils.IsValidTarget(minion, spells.R.Range) then
                                if healthPredDrakeR > 0 and healthPredDrakeR < floor(rDamage - 15) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.R:CastOnHitChance(minion, Enums.HitChance.Medium) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function Annie.BaronSteal()
    if OriUtils.MGet("steal.useQ") or OriUtils.MGet("steal.useW") or OriUtils.MGet("steal.useR") then 
        local enemiesAround = ObjManager.GetNearby("enemy", "heroes")
        for iSteal, objSteal in ipairs(enemiesAround) do
            local enemy = objSteal.AsHero
            if not enemy.IsDead then
                local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
                for iM, minion in ipairs(nearbyMinions) do
                    local minion = minion.AsMinion
                    local qDamage = Annie.GetDamage(minion, slots.Q)
                    local healthPredBaronQ = spells.Q:GetHealthPred(minion)
                    local wDamage = Annie.GetDamage(minion, slots.W)
                    local healthPredBaronW = spells.W:GetHealthPred(minion)
                    local rDamage = Annie.GetDamage(minion, slots.R)
                    local healthPredBaronR = spells.R:GetHealthPred(minion)
                    if not minion.IsDead and minion.IsBaron or minion.IsHerald and minion:Distance(enemy) < 1800 or enemy.IsInBaronPit then
                        if OriUtils.CanCastSpell(slots.Q, "steal.useQ") then
                            if OriUtils.IsValidTarget(minion, spells.Q.Range) then
                                if healthPredBaronQ > 0 and healthPredBaronQ < floor(qDamage - 15) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.Q:Cast(minion) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.W, "steal.useW") then
                            if OriUtils.IsValidTarget(minion, spells.W.Range) then
                                if healthPredBaronW > 0 and healthPredBaronW < floor(wDamage - 15) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.W:CastOnHitChance(minion, Enums.HitChance.Medium) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.R, "steal.useR") and not Annie.TibbersAlive() then
                            if OriUtils.IsValidTarget(minion, spells.R.Range) then
                                if healthPredBaronR > 0 and healthPredBaronR < floor(rDamage - 15) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.R:CastOnHitChance(minion, Enums.HitChance.Medium) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function Annie.HasPassive()
    return Player:GetBuff("anniepassiveprimed")
end

function Annie.TibbersAlive()
    return Player:GetSpell(slots.R).Name == "AnnieRController"
end

function Annie.StackPassiveW()
    if spells.W:IsReady() and (not spells.E:IsReady() or OriUtils.MGet("misc.eStack.options") == 0) and not Annie.HasPassive() then
        if OriUtils.MGet("misc.wStack.options") == 1 then
            if Player.IsInFountain then
                local randomness = math.random(1000, 1700)
                delay(randomness, function()spells.W:Cast(Player) end)
                return
            end
        elseif OriUtils.MGet("misc.wStack.options") == 2 then
            if not Player.IsRecalling then
                if not TS:GetTarget(2000) then
                    if Player.ManaPercent * 100 >= OriUtils.MGet("misc.wStack.ManaSlider") then
                        if spells.W:Cast(Player) then
                            return
                        end
                    end
                end
            end
        end
    end
end

function Annie.StackPassiveE()
    if spells.E:IsReady() and not Annie.HasPassive() then
        if OriUtils.MGet("misc.eStack.options") == 1 then
            if Player.IsInFountain then
                local randomness = math.random(200, 900)
                delay(randomness, function()spells.E:Cast(Player) end)
                return
            end
        elseif OriUtils.MGet("misc.eStack.options") == 2 then
            if not Player.IsRecalling then
                if not TS:GetTarget(2000) then
                    if Player.ManaPercent * 100 >= OriUtils.MGet("misc.eStack.ManaSlider") then
                        if spells.E:Cast(Player) then
                            return
                        end
                    end
                end
            end
        end
    end
end

function events.OnProcessSpell(obj, spellcast)

    if OriUtils.CanCastSpell(slots.E, "misc.useE.Turret") then
        local turret = obj.AsTurret
        if turret and turret.IsValid and not turret.IsDead then
            local target = spellcast.Target
            if target and target.IsAlly and target.IsHero and not target.IsDead then
                if spells.E:IsInRange(target) then
                    if spells.E:Cast(target) then
                        return
                    end
                end
            end
        end
    end
end

function Annie.forceR()
    if OriUtils.MGet("misc.forceR") and not Annie.TibbersAlive() then
        Orbwalker.Orbwalk(Renderer.GetMousePos(nil), false)
        local rTarget = spells.R:GetTarget()
        if rTarget then
            if spells.R:CastOnHitChance(rTarget, Enums.HitChance.Medium) then
                return
            end
        end
    end
end

function combatVariants.Combo()

    if OriUtils.CanCastSpell(slots.R, "combo.useR") and not Annie.TibbersAlive() then
        
        local enemiesAroundSR = ObjManager.GetNearby("enemy", "heroes")
        
        for iSR, objSR in ipairs(enemiesAroundSR) do
            local eHeroR = objSR.AsHero
            if OriUtils.MGet("combo.useR") then
                if OriUtils.IsValidTarget(objSR, spells.R.Range) then
                    if OriUtils.MGet("combo.useR.enemySettings") == 0 then
                        if OriUtils.MGet("combo.useR.stunToggle") then
                            if Annie.HasPassive() or eHeroR:GetBuff("anniepassivestun") then
                                if eHeroR.HealthPercent * 100 <= OriUtils.MGet("combo.useR.enemyHP") then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.R:CastOnHitChance(eHeroR, OriUtils.MGet("hc.R") / 100) then
                                            return
                                        end
                                    end
                                end
                            end
                        else
                            if eHeroR.HealthPercent * 100 <= OriUtils.MGet("combo.useR.enemyHP") then
                                if not Orbwalker.IsWindingUp() then
                                    if spells.R:CastOnHitChance(eHeroR, OriUtils.MGet("hc.R") / 100) then
                                        return
                                    end
                                end
                            end
                        end
                    else
                        local healthPredR = spells.R:GetHealthPred(objSR)

                        if OriUtils.MGet("combo.useR.stunToggle") then
                            if Annie.HasPassive() or eHeroR:GetBuff("anniepassivestun") then
                                local currentDamage = 0

                                if Player:GetBuff("ASSETS/Perks/Styles/Domination/Electrocute/Electrocute.lua") and OriUtils.MGet("draw.electorcute") then
                                    currentDamage = currentDamage + OriUtils.GetElectrocuteDamage(eHeroR)
                                end

                                if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
                                    currentDamage = currentDamage + Annie.GetDamage(eHeroR, slots.Q)
                                end
                                if spells.W:IsReady() and OriUtils.MGet("combo.useW") then
                                    currentDamage = currentDamage + Annie.GetDamage(eHeroR, slots.W)
                                end
                                if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
                                    currentDamage = currentDamage + Annie.GetDamage(eHeroR, slots.R)
                                end
                                if healthPredR > 0 and healthPredR < floor(currentDamage) then
                                    if spells.R:CastOnHitChance(eHeroR, OriUtils.MGet("hc.R") / 100) then
                                        return
                                    end
                                end
                            end
                        else
                            local currentDamage = 0

                            if Player:GetBuff("ASSETS/Perks/Styles/Domination/Electrocute/Electrocute.lua") and OriUtils.MGet("draw.electorcute") then
                                currentDamage = currentDamage + OriUtils.GetElectrocuteDamage(eHeroR)
                            end
                    
                            if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
                                currentDamage = currentDamage + Annie.GetDamage(eHeroR, slots.Q)
                            end

                            if spells.W:IsReady() and OriUtils.MGet("combo.useW") then
                                currentDamage = currentDamage + Annie.GetDamage(eHeroR, slots.W)
                            end

                            if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
                                currentDamage = currentDamage + Annie.GetDamage(eHeroR, slots.R)
                            end
                            if healthPredR > 0 and healthPredR < floor(currentDamage) then
                                if not Orbwalker.IsWindingUp() then
                                    if spells.R:CastOnHitChance(eHeroR, OriUtils.MGet("hc.R") / 100) then
                                        return
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "combo.useE") then
        local eTarget = spells.E:GetTarget()
        if eTarget then
            if spells.E:Cast(Player) then
                return
            end
        else
            local enemysNearby = ObjManager.GetNearby("enemy", "heroes")
            for iSelfE, objSelfE in ipairs(enemysNearby) do
                local enemyH = objSelfE.AsHero
                if OriUtils.IsValidTarget(objSelfE) then
                    if enemyH.IsFleeing then
                        local extendedERange = spells.E.Range + 100
                        local extendedETarget = TS:GetTarget(extendedERange, false)
                        if extendedETarget then
                            if spells.E:Cast(Player) then
                                return
                            end
                        end
                    end
                end
            end
        end
    end


    if OriUtils.CanCastSpell(slots.Q, "combo.useQ") then
        local qTarget = spells.Q:GetTarget()
        if qTarget then
            if spells.Q:Cast(qTarget) then
                return
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "combo.useW") then
        local wTarget = spells.W:GetTarget()
        if wTarget then
            if spells.W:CastOnHitChance(wTarget, OriUtils.MGet("hc.W") / 100) then
                return
            end
        end
    end
end

function combatVariants.Harass()
    if OriUtils.CanCastSpell(slots.Q, "harass.useQ") then
        local qTarget = spells.Q:GetTarget()
        if qTarget then
            if spells.Q:Cast(qTarget) then
                return
            end
        end
    end
    if OriUtils.CanCastSpell(slots.W, "harass.useW") then
        local wTarget = spells.W:GetTarget()
        if wTarget then
            if spells.W:CastOnHitChance(wTarget, OriUtils.MGet("hc.W") / 100) then
                return
            end
        end
    end
end

function combatVariants.Waveclear()

    if OriUtils.CanCastSpell(slots.Q, "jglclear.useQ") then
        if Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.QManaSlider") then
            local jglminionsQ = ObjManager.GetNearby("neutral", "minions")
            for iJGLQ, objJGLQ in ipairs(jglminionsQ) do
                if OriUtils.IsValidTarget(objJGLQ, spells.Q.Range) then
                    local minionName = objJGLQ.CharName
                    if OriUtils.MGet("jgl.qWL." .. minionName, true) or objJGLQ.IsDragon and OriUtils.MGet("jgl.wDrake") then
                        local aaDamage = Orbwalker.GetAutoAttackDamage(objJGLQ)
                        if objJGLQ.Health > (aaDamage * 2) then
                            if not Orbwalker.IsWindingUp() then
                                if spells.Q:Cast(objJGLQ) then
                                    return
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "jglclear.useW") then
        if Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.WManaSlider") then
            local jglminionsW = ObjManager.GetNearby("neutral", "minions")
            local minionsPositions = {}

            for iJGLW, objJGLW in ipairs(jglminionsW) do
                local minion = objJGLW.AsMinion
                if OriUtils.IsValidTarget(objJGLW, spells.W.Range) then
                    local aaDamage = Orbwalker.GetAutoAttackDamage(objJGLW)
                    if objJGLW.Health > (aaDamage * 2) then
                        insert(minionsPositions, minion.Position)
                    end
                end
            end
            
            local myPos = Player.Position
            local bestPos, numberOfHits = Geometry.BestCoveringCone(minionsPositions, myPos, spells.W.ConeAngleRad) 
            if numberOfHits >= 1 then
                if not Orbwalker.IsWindingUp() then
                    if spells.W:Cast(bestPos) then
                        return
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "jglclear.useE") then
        if Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.EManaSlider") then
            local jglminionsE = ObjManager.GetNearby("neutral", "minions")
            for iJGLE, objJGLE in ipairs(jglminionsE) do
                if OriUtils.IsValidTarget(objJGLE, spells.E.Range) then
                    local minionName = objJGLE.CharName
                    if OriUtils.MGet("jgl.eWL." .. minionName, true) or objJGLE.IsDragon and OriUtils.MGet("jgl.eDrake") then
                        local aaDamage = Orbwalker.GetAutoAttackDamage(objJGLE)
                        if objJGLE.Health > (aaDamage * 2) then
                            if not Orbwalker.IsWindingUp() then
                                if spells.E:Cast(Player) then
                                    return
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.Q, "clear.useQ") then
        local qMinions = ObjManager.GetNearby("enemy", "minions")
        for iQ, minionQ in ipairs(qMinions) do 
            local healthPred = spells.Q:GetHealthPred(minionQ)
            local minion = minionQ.AsMinion
            local qDamage = Annie.GetDamage(minion, slots.Q)
            if OriUtils.IsValidTarget(minionQ, spells.Q.Range) then
                if Orbwalker.IsFastClearEnabled() then
                    if healthPred > 0 and healthPred < floor(qDamage) then
                        if not Orbwalker.IsWindingUp() then
                            if not Orbwalker.IsWindingUp() then
                                if spells.Q:Cast(minion) then
                                    return
                                end
                            end
                        end
                    end
                else
                    if not Annie.HasPassive() then
                        if healthPred > 0 and healthPred < floor(qDamage) then
                            if not Orbwalker.IsWindingUp() then
                                if spells.Q:Cast(minion) then
                                    return
                                end
                            end
                        end
                    end
                end
                if OriUtils.MGet("clear.useQ.Minions") == 1 then
                    if minion.IsSiegeMinion then
                        if healthPred > 0 and healthPred < floor(qDamage) then
                            if not Orbwalker.IsWindingUp() then
                                if spells.Q:Cast(minion) then
                                    return
                                end
                            end
                        end
                    end
                else
                    if healthPred > 0 and healthPred < floor(qDamage) then
                        if not Orbwalker.IsWindingUp() then
                            if spells.Q:Cast(minion) then
                                return
                            end
                        end
                    end
                end
            end
        end
    end

    if OriUtils.MGet("clear.enemiesAround") and TS:GetTarget(1800) and not Orbwalker.IsFastClearEnabled() then
        return
    end

    if OriUtils.CanCastSpell(slots.W, "clear.useW") then
        local minionsW = ObjManager.GetNearby("enemy", "minions")
        local minionsPositions = {}

        for iW, objW in ipairs(minionsW) do
            local minion = objW.AsMinion
            if OriUtils.IsValidTarget(objW, spells.W.Range) then
                insert(minionsPositions, minion.Position)
            end
        end

        local myPos = Player.Position
        local bestPos, numberOfHits = Geometry.BestCoveringCone(minionsPositions, myPos, spells.W.ConeAngleRad) 
        if Orbwalker.IsFastClearEnabled() then
            if numberOfHits >= 1 then
                if spells.W:Cast(bestPos) then
                    return
                end
            end
        else
            if numberOfHits >= OriUtils.MGet("clear.wMinions") and Player.ManaPercent * 100 >= OriUtils.MGet("clear.WManaSlider") then
                if not Orbwalker.IsWindingUp() then
                    if spells.W:Cast(bestPos) then
                        return
                    end
                end
            end
        end
    end
end

function combatVariants.Lasthit()
    if OriUtils.CanCastSpell(slots.Q, "lasthit.useQ") then
        local qMinions = ObjManager.GetNearby("enemy", "minions")
        for iQ, minionQ in ipairs(qMinions) do 
            local healthPred = spells.Q:GetHealthPred(minionQ)
            local minion = minionQ.AsMinion
            local qDamage = Annie.GetDamage(minion, slots.Q)
            if OriUtils.IsValidTarget(minionQ, spells.Q.Range) then
                if not Annie.HasPassive() then
                    if healthPred > 0 and healthPred < floor(qDamage) then
                        if spells.Q:Cast(minion) then
                            return
                        end
                    end
                end
            end
        end
    end
end

function combatVariants.Flee()
    if OriUtils.CanCastSpell(slots.E, "misc.useE.Flee") then
        if spells.E:Cast(Player) then
            return
        end
    end
end

print(" |> Welcome - " .. scriptName .. " by " .. scriptCreator .. " loaded! <|")

function events.OnTick()
    OriUtils.CheckFlashSlot()
    if not OriUtils.ShouldRunLogic() then
        return
    end
    local OrbwalkerState = Orbwalker.GetMode()
    if OrbwalkerState == "Combo" then
        combatVariants.Combo()
    elseif OrbwalkerState == "Harass" then
        combatVariants.Harass()
    elseif OrbwalkerState == "Waveclear" then
        combatVariants.Waveclear()
    elseif OrbwalkerState == "Lasthit" then
        combatVariants.Lasthit()
    elseif OrbwalkerState == "Flee" then
        combatVariants.Flee()
    end
    
    Annie.StackPassiveW()
    Annie.StackPassiveE()
    Annie.forceR()
    Annie.KS()
    Annie.flashR()
    Annie.flashQ()
    Annie.BaronSteal()
    Annie.DrakeSteal()
end

function events.OnPreAttack(args)
    local OrbwalkerState = Orbwalker.GetMode()
    if OriUtils.MGet("misc.disableAA") == 1 then
        if OrbwalkerState == "Combo" and OriUtils.CanCastSpell(slots.Q, "combo.useQ") then
            args.Process = false
        end
    else
        if OriUtils.MGet("misc.disableAA") == 2 then
            if (OrbwalkerState == "Combo" or OrbwalkerState == "Harass" or OrbwalkerState == "Lasthit") and spells.Q:IsReady() then
                args.Process = false
            end
        end
    end
end

---@param source GameObject
---@param dashInstance DashInstance
function events.OnGapclose(source, dashInstance)
    if source.IsHero and source.IsEnemy then
        if spells.Q:IsReady() and OriUtils.MGet("gapclose.Q") and Annie.HasPassive() and spells.Q:IsInRange(source) then
            if OriUtils.MGet("gapclose.qWL." .. source.CharName, true) then
                delay(OriUtils.MGet("gapclose.qDelay." .. source.CharName, true), function()spells.Q:Cast(source) end)
                return
            end
        end
    end
end

---@param source GameObject
function events.OnInterruptibleSpell(source, spellCast, danger, endTime, canMoveDuringChannel)
    if source.IsHero and source.IsEnemy then
        if spells.Q:IsReady() and OriUtils.MGet("interrupt.Q") and Annie.HasPassive() and spells.Q:IsInRange(source) then
            if danger >= 3 and spells.Q:IsInRange(source) then
                delay(OriUtils.MGet("interrupt.qDelay." .. source.CharName, true), function()spells.Q:Cast(source) end)
                return
            end
        end
    end
end

function events.OnDraw()
    if Player.IsDead then
        return
    end

    local myPos = Player.Position

    if scriptIsBeta == true then
        Renderer.DrawTextOnPlayer(scriptName .. " " .. scriptVersion, 0xFF00FFFF)
    end

    for _, drawInfo in ipairs(drawData) do
        local slot = drawInfo.slot
        local id = drawInfo.id
        local range = drawInfo.range

        if type(range) == "function" then
            range = range()
        end

        if not OriUtils.MGet("drawMenu.AlwaysDraw") then
            if OriUtils.CanCastSpell(slot, "draw." .. id) then
                Renderer.DrawCircle3D(myPos, range, 30, 2, OriUtils.MGet("draw." .. id .. ".color"))
            end
        else
            if Player:GetSpell(slot).IsLearned then
                Renderer.DrawCircle3D(myPos, range, 30, 2, OriUtils.MGet("draw." .. id .. ".color"))
            end
        end
    end

    if OriUtils.MGet("combo.useR") then
        if OriUtils.MGet("combo.useR.stunToggle") and OriUtils.MGet("combo.useR.enemySettings") == 0 then
            Renderer.DrawTextOnPlayer("R Mode: Stun + if enemy " .. OriUtils.MGet("combo.useR.enemyHP") .. " %HP", 0xFF0000FF)
        elseif OriUtils.MGet("combo.useR.stunToggle") and OriUtils.MGet("combo.useR.enemySettings") == 1 then
            Renderer.DrawTextOnPlayer("R Mode: Stun + if enemy killable", 0xFF0000FF)
        elseif not OriUtils.MGet("combo.useR.stunToggle") and OriUtils.MGet("combo.useR.enemySettings") == 0 then
            Renderer.DrawTextOnPlayer("R Mode: if enemy " .. OriUtils.MGet("combo.useR.enemyHP") .. " %HP", scriptColor)
        else
            Renderer.DrawTextOnPlayer("R Mode: if enemy killable", 0xFF0000FF)
        end
    end

    if OriUtils.MGet("misc.flashQ") then
        local flashReady = spells.Flash.Slot and OriUtils.IsSpellReady(spells.Flash.Slot)
        if spells.Q:IsReady() then
            if not flashReady then
                return Renderer.DrawTextOnPlayer("Flash not Ready", 0xFF0000FF)
            else
                local qRange = spells.Flash.Range + spells.Q.Range
                return Renderer.DrawCircle3D(myPos, qRange, 30, 5, 0xFF0000FF)
            end
        else
            if flashReady then
                return Renderer.DrawTextOnPlayer("Q not Ready", 0xFF00FFFF)
            else
                return Renderer.DrawTextOnPlayer("Q and Flash not Ready", 0xFFFF00FF)
            end
        end
    end

    if OriUtils.MGet("misc.flashR") then
        local flashReady = spells.Flash.Slot and OriUtils.IsSpellReady(spells.Flash.Slot)
        if spells.R:IsReady() then
            if not flashReady then
                return Renderer.DrawTextOnPlayer("Flash not Ready", 0xFF0000FF)
            else
                local rRange = spells.Flash.Range + spells.R.Range
                return Renderer.DrawCircle3D(myPos, rRange, 30, 5, 0xFF0000FF)
            end
        else
            if flashReady then
                return Renderer.DrawTextOnPlayer("R not Ready", 0xFF00FFFF)
            else
                return Renderer.DrawTextOnPlayer("R and Flash not Ready", 0xFFFF00FF)
            end
        end
    end
end

function events.OnDrawDamage(target, dmgList)
    if not OriUtils.MGet("draw.comboDamage") then
        return
    end

    local damageToDeal = 0

    if Player:GetBuff("ASSETS/Perks/Styles/Domination/Electrocute/Electrocute.lua") and OriUtils.MGet("draw.electorcute") then
        damageToDeal = damageToDeal + OriUtils.GetElectrocuteDamage(target)
    end

    if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
        damageToDeal = damageToDeal + Annie.GetDamage(target, slots.Q)
    end

    if spells.W:IsReady() and OriUtils.MGet("combo.useW") then
        damageToDeal = damageToDeal + Annie.GetDamage(target, slots.W)
    end

    if spells.R:IsReady() and OriUtils.MGet("combo.useR") and not Annie.TibbersAlive() then
        damageToDeal = damageToDeal + Annie.GetDamage(target, slots.R)
    end



    insert(dmgList, damageToDeal)
end

---@param obj GameObject
---@param buffInst BuffInst
function events.OnBuffGain(obj, buffInst)
    if obj and buffInst then
        if obj.IsEnemy and obj.IsHero then
            --INFO("An enemy hero gained the buff: " .. buffInst.Name)
        end
    end
end

---@param obj GameObject
---@param buffInst BuffInst
function events.OnBuffLost(obj, buffInst)
    if obj and buffInst then
        if obj.IsEnemy and obj.IsHero then
            --INFO("An enemy hero lost the buff: " .. buffInst.Name)
        end
    end
end


function Annie.RegisterEvents()
    for eventName, eventId in pairs(Enums.Events) do
        if events[eventName] then
            EventManager.RegisterCallback(eventId, events[eventName])
        end
    end
end

function Annie.InitMenu()
    local function QHeader()
        Menu.ColoredText(drawData[1].displayText, scriptColor, true)
    end
    local function QHeaderHit()
        Menu.ColoredText(drawData[1].displayText .. " Hitchance", scriptColor, true)
    end

    local function WHeader()
        Menu.ColoredText(drawData[2].displayText, scriptColor, true)
    end
    local function WHeaderHit()
        Menu.ColoredText(drawData[2].displayText .. " Hitchance", scriptColor, true)
    end

    local function EHeader()
        Menu.ColoredText(drawData[3].displayText, scriptColor, true)
    end
    local function EHeaderHit()
        Menu.ColoredText(drawData[3].displayText .. " Hitchance", scriptColor, true)
    end

    local function RHeader()
        Menu.ColoredText(drawData[4].displayText, scriptColor, true)
    end
    local function RHeaderHit()
        Menu.ColoredText(drawData[4].displayText .. " Hitchance", scriptColor, true)
    end

    local function AnnieMenu()
        Menu.Text("" .. ASCIIArt, true)
        Menu.Text("" .. ASCIIArt2, true)
        Menu.Text("" .. ASCIIArt3, true)
        Menu.Text("" .. ASCIIArt4, true)
        Menu.Text("" .. ASCIIArt5, true)
        Menu.Separator()

        Menu.Text("", true)
        Menu.Text("Version:", true) Menu.SameLine()
        Menu.ColoredText(scriptVersion, scriptColor, false)
        Menu.Text("Last Updated:", true) Menu.SameLine()
        Menu.ColoredText(scriptLastUpdated, scriptColor, false)
        Menu.Text("Creator:", true) Menu.SameLine()
        Menu.ColoredText(scriptCreator, 0x6EFF26FF, false)
        Menu.Text("Credits to:", true) Menu.SameLine()
        Menu.ColoredText(credits, 0x6EFF26FF, false)

        if scriptIsBeta then
            Menu.ColoredText("This script is in an early stage , which means you'll have to redownload the final version once it's done!", 0xFFFF00FF, true)
            Menu.ColoredText("Please keep in mind, that you might encounter bugs/issues.", 0xFFFF00FF, true)
            Menu.ColoredText("If you find any, please contact " .. scriptCreator .. " via robur.lol", 0xFF0000FF, true)
        end
        
        if Menu.Checkbox("Annie.Updates101", "Don't show updates") == false then
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. scriptLastUpdated .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesVersion, 0XFFFF00FF, true)
            Menu.Text("- Small bugfixes", true)
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. patchNotesPrevUpdate .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesPreVersion, 0XFFFF00FF, true)
            Menu.Text("- Initial Release of AuAnnie 1.0.0", true)
        end

        Menu.Separator()

        Menu.NewTree("Annie.comboMenu", "Combo Settings", function()
            Menu.ColumnLayout("Annie.comboMenu.QE", "Annie.comboMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Annie.combo.useQ", "Enable Q", true)
                Menu.Slider("Annie.combo.QManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Annie.combo.useE", "Enable E", true)
                Menu.Slider("Annie.combo.EManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
            end)

            Menu.ColumnLayout("Annie.comboMenu.WR", "Annie.comboMenu.WR", 2, true, function()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Annie.combo.useW", "Enable W", true)
                Menu.Slider("Annie.combo.WManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.NextColumn()
                Menu.Text("")
                RHeader()
                Menu.Checkbox("Annie.combo.useR", "Enable R", true)
                Menu.Dropdown("Annie.combo.useR.enemySettings", "", 1, {"based on HP%", "if Killable"})
                local ddResult = OriUtils.MGet("combo.useR.enemySettings") == 0
                if ddResult then
                    Menu.Slider("Annie.combo.useR.enemyHP", "Use R on enemy if <", 25, 1, 100, 1)
                else
                    Menu.ColoredText("'if Killable' takes other spells and their cooldown into account", scriptColor, true)
                end
                Menu.Keybind("Annie.combo.useR.stunToggle", "Only use R if Passive active", string.byte("Z"), true, true, true)               
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Annie.harassMenu", "Harass Settings", function()
            Menu.ColumnLayout("Annie.harassMenu.QW", "Annie.harassMenu.QW", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Annie.harass.useQ", "Enable Q", true)
                Menu.NextColumn()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Annie.harass.useW", "Enable W", true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Annie.clearMenu", "Clear Settings", function()
            Menu.NewTree("Annie.waveMenu", "Waveclear", function()

                Menu.Checkbox("Annie.clear.enemiesAround", "Don't clear while enemies around", true)
                Menu.Separator()
                Menu.ColoredText("Holding LMB (Fast Clear) during Waveclear will ignore Mana and Minionamount for W", scriptColor)
                Menu.Checkbox("Annie.clear.useQ", "Use Q", true)
                Menu.Dropdown("Annie.clear.useQ.Minions", "Minions", 0, {"All", "Canon"})
                Menu.Checkbox("Annie.clear.useW", "Use W", true)
                Menu.Slider("Annie.clear.wMinions", "if X Minions", 5, 1, 6, 1)
                Menu.Slider("Annie.clear.WManaSlider", "Don't use if Mana < %", 40, 1, 100, 1)
            end)
            Menu.NewTree("Annie.jglMenu", "Jungleclear", function()
                Menu.Checkbox("Annie.jglclear.useQ", "Use Q", true)
                Menu.ColumnLayout("Annie.jglclear.qWhitelist", "Annie.jglclear.qWhitelist", 3, true, function()
                    Menu.Indent(function()
                        Menu.NewTree("Annie.jglclear.qlist", "Jungle Camps 1", function()
                            for i, v in ipairs(jungleCamps) do
                                Menu.Checkbox("Annie.jgl.qWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Annie.jglclear.qlist2", "Jungle Camps 2", function()
                            for i, v in ipairs(jungleCamps2) do
                                Menu.Checkbox("Annie.jgl.qWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Annie.jglclear.qlist3", "Jungle Camps 3", function()
                            for i, v in ipairs(jungleCamps3) do
                                Menu.Checkbox("Annie.jgl.qWL." .. v.name, v.dName, v.default)
                            end
                            Menu.Checkbox("Annie.jgl.qDrake", "Other Drakes", true)
                        end)
                    end)
                end)
                Menu.Slider("Annie.jglclear.QManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Separator()
                Menu.Checkbox("Annie.jglclear.useW", "Use W", true)
                Menu.ColumnLayout("Annie.jglclear.wWhitelist", "Annie.jglclear.wWhitelist", 3, true, function()
                    Menu.Indent(function()
                        Menu.NewTree("Annie.jglclear.wlist", "Jungle Camps 1", function()
                            for i, v in ipairs(jungleCamps) do
                                Menu.Checkbox("Annie.jgl.wWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Annie.jglclear.wlist2", "Jungle Camps 2", function()
                            for i, v in ipairs(jungleCamps2) do
                                Menu.Checkbox("Annie.jgl.wWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Annie.jglclear.wlist3", "Jungle Camps 3", function()
                            for i, v in ipairs(jungleCamps3) do
                                Menu.Checkbox("Annie.jgl.wWL." .. v.name, v.dName, v.default)
                            end
                            Menu.Checkbox("Annie.jgl.wDrake", "Other Drakes", true)
                        end)
                    end)
                end)
                Menu.Slider("Annie.jglclear.WManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Separator()
                Menu.Checkbox("Annie.jglclear.useE", "Use E", true)
                Menu.ColumnLayout("Annie.jglclear.eWhitelist", "Annie.jglclear.eWhitelist", 3, true, function()
                    Menu.Indent(function()
                        Menu.NewTree("Annie.jglclear.elist", "Jungle Camps 1", function()
                            for i, v in ipairs(jungleCamps) do
                                Menu.Checkbox("Annie.jgl.eWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Annie.jglclear.elist2", "Jungle Camps 2", function()
                            for i, v in ipairs(jungleCamps2) do
                                Menu.Checkbox("Annie.jgl.eWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Annie.jglclear.elist3", "Jungle Camps 3", function()
                            for i, v in ipairs(jungleCamps3) do
                                Menu.Checkbox("Annie.jgl.eWL." .. v.name, v.dName, v.default)
                            end
                            Menu.Checkbox("Annie.jgl.eDrake", "Other Drakes", true)
                        end)
                    end)
                end)
                Menu.Slider("Annie.jglclear.EManaSlider", "Don't use if Mana < %", 20, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Annie.lasthitMenu", "Lasthit Settings", function()
            Menu.ColumnLayout("Annie.lasthitMenu.Q", "Annie.lasthitMenu.Q", 1, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Annie.lasthit.useQ", "Enable Q", true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Annie.stealMenu", "Steal Settings", function()
            Menu.NewTree("Annie.ksMenu", "Killsteal", function()
                Menu.Checkbox("Annie.ks.useQ", "Killsteal with Q", true)
                local cbResult = OriUtils.MGet("ks.useQ")
                if cbResult then
                    Menu.Indent(function()
                        Menu.NewTree("Annie.ksMenu.qWhitelist", "KS Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Annie.ks.qWL." .. heroName, "Q KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Annie.ks.useW", "Killsteal with W", true)
                local cbResultW = OriUtils.MGet("ks.useW")
                if cbResultW then
                    Menu.Indent(function()
                        Menu.NewTree("Annie.ksMenu.wWhitelist", "KS W Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Annie.ks.wWL." .. heroName, "W KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Annie.ks.useR", "Killsteal with R", false)
                local cbResult3 = OriUtils.MGet("ks.useR")
                if cbResult3 then
                    Menu.Indent(function()
                        Menu.NewTree("Annie.ksMenu.rWhitelist", "KS R Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Annie.ks.rWL." .. heroName, "R KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
            end)
            Menu.NewTree("Annie.jglstealMenu", "Junglesteal (Drake/Baron) | BETA", function()
                Menu.Checkbox("Annie.steal.useQ", "Junglesteal with Q", true)
                Menu.Checkbox("Annie.steal.useW", "Junglesteal with W", true)
                Menu.Checkbox("Annie.steal.useR", "Junglesteal with R", false)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Annie.miscMenu", "Misc Settings", function()
            Menu.ColumnLayout("Annie.miscMenu.Q", "Annie.miscMenu.Q", 1, true, function()
                Menu.Text("")
                QHeader()
                Menu.Keybind("Annie.misc.flashQ", "Flash Q if stun ready", string.byte("H"), false, false, true)  
                Menu.Text("Disable AA for")Menu.SameLine()
                Menu.Dropdown("Annie.misc.disableAA", "if Q is ready", 1, {"Never", "Combo", "Combo and Lasthit"})
                Menu.Checkbox("Annie.gapclose.Q", "Gapclose with Q", true)
                local cbResult4 = OriUtils.MGet("gapclose.Q")
                if cbResult4 then
                    Menu.Indent(function()
                        Menu.NewTree("Annie.miscMenu.gapcloseQ", "Gapclose Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Annie.gapclose.qWL." .. heroName, "Use Q Gapclose on " .. heroName, true)
                                    Menu.Slider("Annie.gapclose.qDelay." .. heroName, "Delay", 110, 0, 500, 1)
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Annie.interrupt.Q", "Interrupt with Q", true)
                local cbResult4 = OriUtils.MGet("interrupt.Q")
                if cbResult4 then
                    Menu.Indent(function()
                        Menu.NewTree("Annie.miscMenu.interruptQ", "Interrupt Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Annie.interrupt.qWL." .. heroName, "Use Q Interrupt on " .. heroName, true)
                                    Menu.Slider("Annie.interrupt.qDelay." .. heroName, "Delay", 110, 0, 500, 1)
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
            end)
            Menu.Separator()
            Menu.ColumnLayout("Annie.miscMenu.WER", "Annie.miscMenu.WER", 3, true, function()
                Menu.Text("")
                WHeader()
                Menu.Text("Use W to Stack passive")Menu.SameLine()
                Menu.Dropdown("Annie.misc.wStack.options", " ", 1, {"Never", "if in Fountain", "if Mana above X% and no enemies around"})
                local ddResult = OriUtils.MGet("misc.wStack.options") == 2
                if ddResult then
                    Menu.Slider("Annie.misc.wStack.ManaSlider", "%", 70, 1, 100)
                end
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Annie.misc.useE.Flee", "Use E for Flee", true)
                Menu.Checkbox("Annie.misc.useE.Turret", "Auto Shield Turret Attacks", true)
                Menu.Text("Use E to Stack passive")Menu.SameLine()
                Menu.Dropdown("Annie.misc.eStack.options", " ", 1, {"Never", "if in Fountain", "if Mana above X% and no enemies around"})
                local ddResult = OriUtils.MGet("misc.eStack.options") == 2
                if ddResult then
                    Menu.Slider("Annie.misc.eStack.ManaSlider", "%", 70, 1, 100)
                end
                Menu.NextColumn()
                Menu.Text("")
                RHeader()
                Menu.Keybind("Annie.misc.forceR", "Force R", string.byte("T"), false, false, true)
                Menu.Keybind("Annie.misc.flashR", "Flash R if stun ready", string.byte("G"), false, false, true)
                Menu.Slider("Annie.misc.flashR.delay", "Delay", 77, 75, 90, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Annie.hcMenu", "Hitchance Settings", function()
            Menu.ColumnLayout("Annie.hcMenu.WR", "Annie.hcMenu.WR", 2, true, function()
                Menu.Text("")
                WHeaderHit()
                Menu.Text("")
                Menu.Slider("Annie.hc.W", "%", 30, 1, 100, 1)
                Menu.NextColumn()
                Menu.Text("")
                RHeaderHit()
                Menu.Text("")
                Menu.Slider("Annie.hc.R", "%", 40, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Annie.drawMenu", "Draw Settings", function()
            OriUtils.AddDrawMenu(drawData)
        end)
    end

    Menu.RegisterMenu(scriptName, scriptName, AnnieMenu)
end

function OnLoad()
    Annie.InitMenu()
    
    Annie.RegisterEvents()
    return true
end