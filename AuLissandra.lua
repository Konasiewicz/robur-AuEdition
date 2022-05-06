if Player.CharName ~= "Lissandra" then return end

local scriptName = "AuLissandra"
local scriptCreator = "AURUM"
local credits = "Orietto"
local patchNotesPrevUpdate = "03/13/2022"
local patchNotesPreVersion = "1.0.0"
local patchNotesVersion, scriptVersionUpdater = "1.0.1", "1.0.1"
local scriptVersion = scriptVersionUpdater
local scriptLastUpdated = "03/14/2022"
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
local huge, pow, min, max, floor = math.huge, math.pow, math.min, math.max, math.floor

local SDK = _G.CoreEx

SDK.AutoUpdate("https://robur.site/AURUM/AuEdition/raw/branch/master/AuLissandra.lua", scriptVersionUpdater)

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
        Base = {80, 110, 140, 170, 200},
        TotalAP = 0.8,
        Type = dmgTypes.Magical
    },

    W = {
        Base = {70, 105, 140, 175, 210},
        TotalAP  = 0.7,
        Type = dmgTypes.Magical
    },
    E = {
        Base = {70, 105, 140, 175, 210},
        TotalAP  = 0.6,
        Type = dmgTypes.Magical
    },
    R = {
        Base = {150, 250, 350},
        TotalAP = 0.75,
        Type = dmgTypes.Magical
    }
}

local spells = {
    Q = Spell.Skillshot({
        Slot = slots.Q,
        Delay = 0.0,
        Speed = 2200,
        Range = 750,
        Radius = 150 / 2,
        Collisions = {Windwall = true}
    }),
    W = Spell.Active({
        Slot = slots.W,
        Delay = 0.0,
        Speed = huge,
        Range = 385,
    }),
    E = Spell.Skillshot({
        Slot = slots.E,
        Delay = 0.0,
        Speed = 1450,
        Range = 1050,
        Radius = 250 / 2,
        Type = "Linear",
        Collisions = {Windwall = true}
    }),
    E2 = Spell.Active({
        Slot = slots.E,
        Delay = 0.0,
    }),
    R = Spell.Targeted({
        Slot = slots.R,
        Delay = 0.38,
        Speed = huge,
        Range = 485 ,
        Radius = 485,
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
    [4] = {name = "SRU_MurkwolfMini", dName = "Small Wolf", default = true},
}

local jungleCamps2 = {

    [1] = {name = "SRU_Red", dName = "Red Buff", default = true},
    [2] = {name = "SRU_Razorbeak", dName = "Big Raptor", default = true},
    [3] = {name = "SRU_RazorbeakMini", dName = "Small Raptor", default = true},
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

function OriUtils.CheckCastTimers(data)
    local curTime = Game.GetTime()

    for slot, Lissandraold in pairs(data) do
        if curTime < lastCastT[slot] + Lissandraold then
            return false
        end
    end

    return true
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

    Menu.Checkbox(cacheName .. ".draw." .. "comboDamage", "Draw combo damage on healthbar", true)
    Menu.Checkbox("Lissandra.drawMenu.AlwaysDraw", "Always show Drawings", false)
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
    {slot = slots.Q, id = "Q", displayText = "[Q] Ice Shard", range = spells.Q.Range},
    {slot = slots.W, id = "W", displayText = "[W] Ring of Frost", range = spells.W.Range},
    {slot = slots.E, id = "E", displayText = "[E] Glacial Path", range = spells.E.Range},
    {slot = slots.R, id = "R", displayText = "[R] Frozen Tomb", range = spells.R.Range}
}

local ASCIIArt = "                 _      _                         _            "
local ASCIIArt2 = "      /\\        | |    (_)                       | |           "
local ASCIIArt3 = "     /  \\  _   _| |     _ ___ ___  __ _ _ __   __| |_ __ __ _  "
local ASCIIArt4 = "    / /\\ \\| | | | |    | / __/ __|/ _` | '_ \\ / _` | '__/ _` | "
local ASCIIArt5 = "   / ____ \\ |_| | |____| \\__ \\__ \\ (_| | | | | (_| | | | (_| | "
local ASCIIArt6 = "  /_/    \\_\\__,_|______|_|___/___/\\__,_|_| |_|\\__,_|_|  \\__,_| "


local Lissandra = {}

local slotToDamageTable = {
    [slots.Q] = damages.Q,
    [slots.W] = damages.W,
    [slots.E] = damages.E,
    [slots.R] = damages.R
}

---@param target AIBaseClient
---@param slot slut
function Lissandra.GetDamage(target, slot)
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

function Lissandra.WCount()
    local count = 0
    local myPos = Player.Position
    local enemyMinions = OriUtils.GetEnemyAndJungleMinions(spells.W.Range, myPos)
    for index, obj in ipairs(enemyMinions) do
        if OriUtils.IsValidTarget(obj, spells.W.Range) then
            count = count + 1    
        end 
    end

    return count
end

function Lissandra.forceR()
    if OriUtils.MGet("misc.forceR") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)
        if spells.R:IsReady() then        
            local rTarget = spells.R:GetTarget()
            if rTarget then
                if spells.R:Cast(rTarget) then
                    return
                end
            end
        end
    end
end

function Lissandra.flashR()
    if OriUtils.MGet("misc.flashR") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)

        if spells.R:IsReady() then
            
            local flashReady = spells.Flash.Slot and OriUtils.IsSpellReady(spells.Flash.Slot)
            if not flashReady then
                return
            end

            local rFlashRange = (spells.R.Range - 10) + spells.Flash.Range
            local rFlashTarget = TS:GetTarget(rFlashRange, false)
            if rFlashTarget and not spells.R:IsInRange(rFlashTarget) then
                local flashPos = Player.ServerPos:Extended(rFlashTarget, spells.Flash.Range) 

                local spellInput = {
                    Slot = slots.R,
                    Delay = 0.38,
                    Speed = huge,
                    Range = 485 ,
                    Radius = 485,
                    Type = "Circular",
                }
                local pred = Prediction.GetPredictedPosition(rFlashTarget, spellInput, flashPos)
                if pred and pred.HitChanceEnum >= Enums.HitChance.Medium then
                    if Input.Cast(spells.Flash.Slot, flashPos) then
                        delay(100, function()spells.R:Cast(rFlashTarget) end)
                        return
                    end
                end
            end
        end
    end
end

function Lissandra.KS()
    if OriUtils.CanCastSpell(slots.Q, "ks.useQ") or OriUtils.CanCastSpell(slots.W, "ks.useW") or OriUtils.CanCastSpell(slots.R, "ks.useR") then
        local allyHeroes = ObjManager.GetNearby("ally", "heroes")
        for iKSA, objKSA in ipairs(allyHeroes) do
            local ally = objKSA.AsHero
            if not ally.IsMe and not ally.IsDead then
                local nearbyEnemiesKS = ObjManager.GetNearby("enemy", "heroes")
                for iKS, objKS in ipairs(nearbyEnemiesKS) do
                    local target = objKS.AsHero
                    local qDamage = Lissandra.GetDamage(target, slots.Q)
                    local healthPredQ = spells.Q:GetHealthPred(objKS)
                    local wDamage = Lissandra.GetDamage(target, slots.W)
                    local healthPredW = spells.W:GetHealthPred(objKS)
                    local rDamage = Lissandra.GetDamage(target, slots.R)
                    local healthPredR = spells.W:GetHealthPred(objKS)
                    if OriUtils.MGet("ks.useQ") then
                        if OriUtils.IsValidTarget(objKS, spells.Q.Range) then
                            if OriUtils.MGet("ks.qWL." .. target.CharName, true) then
                                if healthPredQ > 0 and healthPredQ < floor(qDamage) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.Q:CastOnHitChance(target, Enums.HitChance.Medium) then
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
                                        if spells.W:Cast() then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                    end
                    if OriUtils.MGet("ks.useR") then
                        if OriUtils.IsValidTarget(objKS, spells.R.Range) then
                            if OriUtils.MGet("ks.rWL." .. target.CharName, true) then
                                if healthPredR > 0 and healthPredR < floor(rDamage) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.R:Cast(target) then
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

function Lissandra.DrakeSteal()
    if OriUtils.MGet("steal.useQ") or OriUtils.MGet("steal.useW") then 
        local enemiesAround = ObjManager.GetNearby("enemy", "heroes")
        for iSteal, objSteal in ipairs(enemiesAround) do
            local enemy = objSteal.AsHero
            if not enemy.IsDead then
                local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
                for iM, minion in ipairs(nearbyMinions) do
                    local minion = minion.AsMinion
                    local qDamage = Lissandra.GetDamage(minion, slots.Q)
                    local healthPredDrakeQ = spells.Q:GetHealthPred(minion)
                    local wDamage = Lissandra.GetDamage(minion, slots.W)
                    local healthPredDrakeW = spells.W:GetHealthPred(minion)
                    if not minion.IsDead and minion.IsDragon and minion:Distance(enemy) < 1800 or enemy.IsInDragonPit then
                        if OriUtils.CanCastSpell(slots.Q, "steal.useQ") then
                            if OriUtils.IsValidTarget(minion, spells.Q.Range) then
                                if healthPredDrakeQ > 0 and healthPredDrakeQ < floor(qDamage - 15) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.Q:CastOnHitChance(minion, Enums.HitChance.Medium) then
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
                                        if spells.W:Cast() then
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

function Lissandra.BaronSteal()
    if OriUtils.MGet("steal.useQ") or OriUtils.MGet("steal.useW") then 
        local enemiesAround = ObjManager.GetNearby("enemy", "heroes")
        for iSteal, objSteal in ipairs(enemiesAround) do
            local enemy = objSteal.AsHero
            if not enemy.IsDead then
                local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
                for iM, minion in ipairs(nearbyMinions) do
                    local minion = minion.AsMinion
                    local qDamage = Lissandra.GetDamage(minion, slots.Q)
                    local healthPredBaronQ = spells.Q:GetHealthPred(minion)
                    local wDamage = Lissandra.GetDamage(minion, slots.W)
                    local healthPredBaronW = spells.W:GetHealthPred(minion)
                    if not minion.IsDead and minion.IsBaron or minion.IsHerald and minion:Distance(enemy) < 1800 or enemy.IsInBaronPit then
                        if OriUtils.CanCastSpell(slots.Q, "steal.useQ") then
                            if OriUtils.IsValidTarget(minion, spells.Q.Range) then
                                if healthPredBaronQ > 0 and healthPredBaronQ < floor(qDamage - 15) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.Q:CastOnHitChance(minion, Enums.HitChance.Medium) then
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
                                        if spells.W:Cast() then
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

function Lissandra.IsInE()
    return Player:GetBuff("LissandraE")
end

local LisEData = {
    Object = nil,
    LastCreationTime = 0
}

function combatVariants.Combo()

    if OriUtils.CanCastSpell(slots.R, "combo.useR") then
        
        local enemiesAroundSR = ObjManager.GetNearby("enemy", "heroes")
        
        for iSR, objSR in ipairs(enemiesAroundSR) do
            local eHeroR = objSR.AsHero
            if OriUtils.MGet("combo.useR.enemy") then
                if OriUtils.IsValidTarget(objSR, spells.R.Range) then
                    if OriUtils.MGet("combo.useR.enemySettings") == 0 then
                        if eHeroR.HealthPercent * 100 <= OriUtils.MGet("combo.useR.enemyHP") then
                            if spells.R:Cast(eHeroR) then
                                return
                            end
                        end
                    else
                        local healthPredR = spells.R:GetHealthPred(objSR)
                        
                        if OriUtils.MGet("combo.eModes") then
                            local currentDamage = 0

                            if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
                                currentDamage = currentDamage + Lissandra.GetDamage(eHeroR, slots.Q)
                            end
                            if spells.W:IsReady() and OriUtils.MGet("combo.useW") then
                                currentDamage = currentDamage + Lissandra.GetDamage(eHeroR, slots.W)
                            end                    
                            if spells.E:IsReady() and OriUtils.MGet("combo.useE") then
                                currentDamage = currentDamage + Lissandra.GetDamage(eHeroR, slots.E)
                            end
                            if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
                                currentDamage = currentDamage + Lissandra.GetDamage(eHeroR, slots.R)
                            end
                            if healthPredR > 0 and healthPredR < floor(currentDamage) then
                                if spells.R:Cast(eHeroR) then
                                    return
                                end
                            end
                        else
                            
                            local currentDamage = 0

                            if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
                                currentDamage = currentDamage + Lissandra.GetDamage(eHeroR, slots.Q)
                            end
                            if spells.W:IsReady() and OriUtils.MGet("combo.useW") then
                                currentDamage = currentDamage + Lissandra.GetDamage(eHeroR, slots.W)
                            end
                            if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
                                currentDamage = currentDamage + Lissandra.GetDamage(eHeroR, slots.R)
                            end
                            if healthPredR > 0 and healthPredR < floor(currentDamage) then
                                if spells.R:Cast(eHeroR) then
                                    return
                                end
                            end
                        end
                    end
                end
            end
            if OriUtils.MGet("combo.useR.self") then
                if OriUtils.IsValidTarget(objSR, 1000) then
                    if Player.HealthPercent * 100 <= OriUtils.MGet("combo.useR.selfHP") then
                        if spells.R:Cast(Player) then
                            return
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.Q, "combo.useQ") then
        if Player.ManaPercent * 100 >= OriUtils.MGet("combo.qManaSlider") then
            local qTarget = spells.Q:GetTarget()
            if qTarget then
                if spells.Q:CastOnHitChance(qTarget, OriUtils.MGet("hc.Q") / 100) then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "combo.useW") then
        if Player.ManaPercent * 100 >= OriUtils.MGet("combo.wManaSlider") then
            local wTarget = spells.W:GetTarget()
            if wTarget then
                if spells.W:Cast() then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "combo.useE") then
        if Player.ManaPercent * 100 >= OriUtils.MGet("combo.eManaSlider") then
            if not Lissandra.IsInE() then
                local eTarget = spells.E:GetTarget()
                if eTarget then
                    if spells.E:CastOnHitChance(eTarget, OriUtils.MGet("hc.E") / 100) then
                        return
                    end
                end
            end
        end
        local enemiesNearblyE = ObjManager.GetNearby("enemy", "heroes")
        if LisEData.Object then
            local LissE = LisEData.Object
            if not OriUtils.MGet("combo.eModes") then
                for iE, objE in ipairs(enemiesNearblyE) do
                local target = objE.AsHero
                    if OriUtils.IsValidTarget(objE, 1500) then
                        if target:Distance(LissE) < OriUtils.MGet("combo.useE.EngageSlider") then
                            if spells.E2:Cast() then
                                return
                            end
                        end
                    end
                end
            else
                if LissE:Distance(LissE.EndPos) < 10 then
                    if spells.E2:Cast() then
                        return
                    end
                end
            end
        end
    end
end

function combatVariants.Harass()
    if OriUtils.CanCastSpell(slots.Q, "harass.useQ") then
        local qTarget = spells.Q:GetTarget()
        if qTarget then
            if spells.Q:CastOnHitChance(qTarget, OriUtils.MGet("hc.Q") / 100) then
                return
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "harass.useW") then
        local wTarget = spells.W:GetTarget()
        if wTarget then
            if spells.W:Cast() then
                return
            end
        end
    end
    
    if OriUtils.CanCastSpell(slots.E, "harass.useE1") then
        local eTarget = spells.E:GetTarget()
        if eTarget and not Lissandra.IsInE() then
            if spells.E:CastOnHitChance(eTarget, OriUtils.MGet("hc.E") / 100) then
                return
            end
        end
    end
    if LisEData.Object and OriUtils.CanCastSpell(slots.E, "harass.useE2") then
        local LissE = LisEData.Object
        if LissE:Distance(LissE.EndPos) < 10 then
            if spells.E2:Cast() then
                return
            end
        end
    end
end

function combatVariants.Waveclear()
    if OriUtils.CanCastSpell(slots.Q, "jglclear.useQ") then
        local jglminionsQ = ObjManager.GetNearby("neutral", "minions")
        local minionsPositions = {}

        for iJGLE, objJGLQ in ipairs(jglminionsQ) do
            local minion = objJGLQ.AsMinion
            local minionName = objJGLQ.CharName
            if OriUtils.IsValidTarget(objJGLQ, spells.Q.Range) then
                if minion.ShieldAll < 1 then
                    if OriUtils.MGet("jgl.qWL." .. minionName, true) or objJGLQ.IsDragon and OriUtils.MGet("jgl.qDrake") then
                        insert(minionsPositions, minion.Position)
                    end
                end
            end
        end
        local bestPos, numberOfHits = Geometry.BestCoveringRectangle(minionsPositions, Player.Position, spells.Q.Radius * 2) 
        if numberOfHits >= 1 and Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.EManaSlider") then
            if spells.Q:Cast(bestPos) then
                return
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "jglclear.useW") then
        if Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.WManaSlider") then
            local jglminionsW = ObjManager.GetNearby("neutral", "minions")
            for iJGLW, objJGLW in ipairs(jglminionsW) do
                if OriUtils.IsValidTarget(objJGLW, spells.W.Range) then
                    local minionName = objJGLW.CharName
                    if OriUtils.MGet("jgl.wWL." .. minionName, true) or objJGLW.IsDragon and OriUtils.MGet("jgl.wDrake") then
                        local aaDamage = Orbwalker.GetAutoAttackDamage(objJGLW)
                        if objJGLW.Health > (aaDamage * 2) then
                            if not Orbwalker.IsWindingUp() then
                                if spells.W:Cast() then
                                    return
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    if OriUtils.CanCastSpell(slots.E, "jglclear.useE") then
        if Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.EManaSlider") then
            if Orbwalker.IsFastClearEnabled() then
                local jglminionsE = ObjManager.GetNearby("neutral", "minions")
                if not Lissandra.IsInE() then
                    for iJGLE, objJGLE in ipairs(jglminionsE) do
                        if OriUtils.IsValidTarget(objJGLE, 700) then
                            local minionName = objJGLE.CharName
                            if OriUtils.MGet("jgl.eWL." .. minionName, true) or objJGLE.IsDragon and OriUtils.MGet("jgl.eDrake") then
                                local aaDamage = Orbwalker.GetAutoAttackDamage(objJGLE)
                                if objJGLE.Health > (aaDamage * 2) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.E:Cast(objJGLE) then
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

    if OriUtils.MGet("clear.enemiesAround") and TS:GetTarget(1800) and not Orbwalker.IsFastClearEnabled() then
        return
    end

    if OriUtils.CanCastSpell(slots.Q, "clear.useQ") then
        local minionsQ = ObjManager.GetNearby("enemy", "minions")
        local minionsPositions = {}

        for iQ, objQ in ipairs(minionsQ) do
            local minion = objQ.AsMinion
            local minionName = objQ.CharName
            if OriUtils.IsValidTarget(objQ, spells.Q.Range) then
                insert(minionsPositions, minion.Position)
            end
        end
        local bestPos, numberOfHits = Geometry.BestCoveringRectangle(minionsPositions, Player.Position, spells.Q.Radius * 2)
        if Orbwalker.IsFastClearEnabled() then
            if numberOfHits >= 1 then
                if spells.Q:Cast(bestPos) then
                    return
                end
            end
        else
            if Player.ManaPercent * 100 >= OriUtils.MGet("clear.qManaSlider") then
                if numberOfHits >= OriUtils.MGet("clear.qMinions") then
                    if spells.Q:Cast(bestPos) then
                        return
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "clear.useW") then
        local minionsW = ObjManager.GetNearby("enemy", "minions")
        for iW, objW in ipairs(minionsW) do
            if OriUtils.IsValidTarget(objW, spells.W.Range) then
                if Orbwalker.IsFastClearEnabled() then
                    if Lissandra.WCount() >= 1 then
                        if spells.W:Cast() then
                            return
                        end
                    end
                else
                    if Player.ManaPercent * 100 >= OriUtils.MGet("clear.WManaSlider") then
                        if Lissandra.WCount() >= OriUtils.MGet("clear.wMinions") then
                            if spells.W:Cast() then
                                return
                            end
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "clear.useE") then
        if not Lissandra.IsInE() then
            local minionsE = ObjManager.GetNearby("enemy", "minions")
            local minionsPositions = {}

            for iE, objE in ipairs(minionsE) do
                local minion = objE.AsMinion
                local minionName = objE.CharName
                if OriUtils.IsValidTarget(objE, spells.E.Range) then
                    insert(minionsPositions, minion.Position)
                end
            end
            local bestPos, numberOfHits = Geometry.BestCoveringRectangle(minionsPositions, Player.Position, spells.E.Radius * 2)
            if Orbwalker.IsFastClearEnabled() then
                if numberOfHits >= 1 then
                    if spells.E:Cast(bestPos) then
                        return
                    end
                end
            else
                if Player.ManaPercent * 100 >= OriUtils.MGet("clear.eManaSlider") then
                    if numberOfHits >= OriUtils.MGet("clear.eMinions") then
                        if spells.E:Cast(bestPos) then
                            return
                        end
                    end
                end
            end
        end
    end
end

function combatVariants.Lasthit()
end

function combatVariants.Flee()
    if OriUtils.CanCastSpell(slots.E, "misc.FleeE") then
        if not Lissandra.IsInE() then
            local mousePos = Player.Position:Extended(Renderer.GetMousePos(), 1500)
            if spells.E:Cast(mousePos) then
                return
            end
        end
        local LissE = LisEData.Object
        if LissE then
            if LissE:Distance(LissE.EndPos) < 50 then
                if spells.E2:Cast() then
                    return
                end
            end
        end
    end
end

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

    Lissandra.forceR()
    Lissandra.flashR()
    Lissandra.KS()
    Lissandra.BaronSteal()
    Lissandra.DrakeSteal()
end

function events.OnDrawDamage(target, dmgList)
    if not OriUtils.MGet("draw.comboDamage") then
        return
    end

    local damageToDeal = 0

    if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
        damageToDeal = damageToDeal + Lissandra.GetDamage(target, slots.Q)
    end

    if spells.W:IsReady() and OriUtils.MGet("combo.useW") then
        damageToDeal = damageToDeal + Lissandra.GetDamage(target, slots.W)
    end

    if spells.E:IsReady() and OriUtils.MGet("combo.useE") then
        if OriUtils.MGet("combo.eModes") then
            damageToDeal = damageToDeal + Lissandra.GetDamage(target, slots.E)
        else
        end
    end

    if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
        damageToDeal = damageToDeal + Lissandra.GetDamage(target, slots.R)
    end

    insert(dmgList, damageToDeal)
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

    if OriUtils.MGet("combo.useE") then
        if OriUtils.MGet("combo.eModes") then
            Renderer.DrawTextOnPlayer("E Mode: Max Range", 0xFF0000FF)
        else
            Renderer.DrawTextOnPlayer("E Mode: Custom", scriptColor)
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

---@param obj GameObject
function events.OnCreateObject(obj)
    if obj then
        if obj.IsMissile then
            local missile = obj.AsMissile

            if missile.Caster and missile.Caster.IsMe and missile.Name == "LissandraEMissile" then
                LisEData.Object = missile
                LisEData.LastCreationTime = Game.GetTime()
            end
        end
    end
end

---@param obj GameObject
function events.OnDeleteObject(obj)
    if obj then
        if LisEData.Object and LisEData.Object.Handle == obj.Handle then
            LisEData.Object = nil
        end
    end
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


function Lissandra.RegisterEvents()
    for eventName, eventId in pairs(Enums.Events) do
        if events[eventName] then
            EventManager.RegisterCallback(eventId, events[eventName])
        end
    end
end

function Lissandra.InitMenu()
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

    local function LissandraMenu()
        Menu.Text("" .. ASCIIArt, true)
        Menu.Text("" .. ASCIIArt2, true)
        Menu.Text("" .. ASCIIArt3, true)
        Menu.Text("" .. ASCIIArt4, true)
        Menu.Text("" .. ASCIIArt5, true)
        Menu.Text("" .. ASCIIArt6, true)
        Menu.Text("", true)
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
            Menu.ColoredText("This scripts version is in an early stage", 0xFFFF00FF, true)
            Menu.ColoredText("Please keep in mind, that you might encounter bugs/issues.", 0xFFFF00FF, true)
            Menu.ColoredText("If you find any, please contact " .. scriptCreator .. " via robur.lol", 0xFF0000FF, true)
        end
        
        if Menu.Checkbox("Lissandra.Updates101", "Don't show updates") == false then
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. scriptLastUpdated .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesVersion, 0XFFFF00FF, true)
            Menu.Text("- Fixed Force R", true)
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. patchNotesPrevUpdate .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesPreVersion, 0XFFFF00FF, true)
            Menu.Text("- Initial Release of AuLissandra 1.0.0", true)
        end

        Menu.Separator()

        Menu.NewTree("Lissandra.comboMenu", "Combo Settings", function()
            Menu.ColumnLayout("Lissandra.comboMenu.QE", "Lissandra.comboMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Lissandra.combo.useQ", "Enable Q", true)
                Menu.Slider("Lissandra.combo.qManaSlider", "Don't use if Mana below X%", 25, 1, 100, 1)
                Menu.NextColumn()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Lissandra.combo.useW", "Enable W", true)
                Menu.Slider("Lissandra.combo.wManaSlider", "Don't use if Mana below X%", 15, 1, 100, 1)
                Menu.NextColumn()
                Menu.Text("")
                
            end)

            Menu.ColumnLayout("Lissandra.comboMenu.WR", "Lissandra.comboMenu.WR", 2, true, function()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Lissandra.combo.useE", "Enable E", true)
                Menu.Slider("Lissandra.combo.eManaSlider", "Don't use if Mana below X%", 30, 1, 100, 1)
                Menu.ColoredText("Custom E Range", scriptColor, true)
                Menu.Slider("Lissandra.combo.useE.EngageSlider", "Recast if E within X Range", 385, 1, 1025, 1)
                Menu.Keybind("Lissandra.combo.eModes", "Max Range E Toggle", string.byte("Z"), true, false, true)
                Menu.NextColumn()
                RHeader()
                Menu.Checkbox("Lissandra.combo.useR", "Enable R", true)
                Menu.Checkbox("Lissandra.combo.useR.self", "Enable R on self if HP below", true)Menu.SameLine()
                Menu.Slider("Lissandra.combo.useR.selfHP", "%", 15, 1, 100, 1)
                Menu.Checkbox("Lissandra.combo.useR.enemy", "Enable R on enemy", true)Menu.SameLine()
                Menu.Dropdown("Lissandra.combo.useR.enemySettings", "", 1, {"based on HP%", "if Killable"})
                local ddResult = OriUtils.MGet("combo.useR.enemySettings") == 0
                if ddResult then
                    Menu.Slider("Lissandra.combo.useR.enemyHP", "Use R on enemy if <", 25, 1, 100, 1)
                else
                    Menu.ColoredText("'if Killable' takes other spells and their cooldown into account", scriptColor, true)
                end

            end)
        end)
        Menu.Separator()

        Menu.NewTree("Lissandra.harassMenu", "Harass Settings", function()
            Menu.ColumnLayout("Lissandra.harassMenu.QW", "Lissandra.harassMenu.QW", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Lissandra.harass.useQ", "Enable Q", true)
                Menu.NextColumn()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Lissandra.harass.useW", "Enable W", true)
            end)
            Menu.Separator()
            Menu.ColumnLayout("Lissandra.harass.E", "Lissandra.harassMenu.E", 1, true, function()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Lissandra.harass.useE1", "Enable E1", false)
                Menu.Checkbox("Lissandra.harass.useE2", "Enable E2 (Max Range E)", false)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Lissandra.clearMenu", "Clear Settings", function()
            Menu.NewTree("Lissandra.waveMenu", "Waveclear", function()
                Menu.Checkbox("Lissandra.clear.enemiesAround", "Don't clear while enemies around", true)
                Menu.Separator()
                Menu.Checkbox("Lissandra.clear.useQ", "Use Q", true)
                Menu.Slider("Lissandra.clear.qMinions", "if X Minions", 5, 1, 6, 1)
                Menu.Slider("Lissandra.clear.qManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Checkbox("Lissandra.clear.useW", "Enable W", true)
                Menu.Slider("Lissandra.clear.wMinions", "if X Minions", 5, 1, 6, 1)
                Menu.Slider("Lissandra.clear.WManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Checkbox("Lissandra.clear.useE", "Enable E", false)
                Menu.Slider("Lissandra.clear.eMinions", "if X Minions", 5, 1, 6, 1)
                Menu.Slider("Lissandra.clear.eManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
            end)
            Menu.NewTree("Lissandra.jglMenu", "Jungleclear", function()
                Menu.Checkbox("Lissandra.jglclear.useQ", "Use Q", true)
                Menu.ColumnLayout("Lissandra.jglclear.qWhitelist", "Lissandra.jglclear.qWhitelist", 3, true, function()
                    Menu.Indent(function()
                        Menu.NewTree("Lissandra.jglclear.qlist", "Jungle Camps 1", function()
                            for i, v in ipairs(jungleCamps) do
                                Menu.Checkbox("Lissandra.jgl.qWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Lissandra.jglclear.qlist2", "Jungle Camps 2", function()
                            for i, v in ipairs(jungleCamps2) do
                                Menu.Checkbox("Lissandra.jgl.qWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Lissandra.jglclear.qlist3", "Jungle Camps 3", function()
                            for i, v in ipairs(jungleCamps3) do
                                Menu.Checkbox("Lissandra.jgl.qWL." .. v.name, v.dName, v.default)
                            end
                            Menu.Checkbox("Lissandra.jgl.qDrake", "Other Drakes", true)
                        end)
                    end)
                end)
                Menu.Slider("Lissandra.jglclear.QManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Separator()
                Menu.Checkbox("Lissandra.jglclear.useW", "Use W", true)
                Menu.ColumnLayout("Lissandra.jglclear.wWhitelist", "Lissandra.jglclear.wWhitelist", 3, true, function()
                    Menu.Indent(function()
                        Menu.NewTree("Lissandra.jglclear.wlist", "Jungle Camps 1", function()
                            for i, v in ipairs(jungleCamps) do
                                Menu.Checkbox("Lissandra.jgl.wWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Lissandra.jglclear.wlist2", "Jungle Camps 2", function()
                            for i, v in ipairs(jungleCamps2) do
                                Menu.Checkbox("Lissandra.jgl.wWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Lissandra.jglclear.wlist3", "Jungle Camps 3", function()
                            for i, v in ipairs(jungleCamps3) do
                                Menu.Checkbox("Lissandra.jgl.wWL." .. v.name, v.dName, v.default)
                            end
                            Menu.Checkbox("Lissandra.jgl.wDrake", "Other Drakes", true)
                        end)
                    end)
                end)
                Menu.Slider("Lissandra.jglclear.WManaSlider", "Don't use if Mana < %", 20, 1, 100, 1)
                Menu.Separator()
                Menu.ColoredText("Holding LMB (Fast Clear) is required for E", scriptColor, true)
                Menu.Checkbox("Lissandra.jglclear.useE", "Use E", true)
                Menu.ColumnLayout("Lissandra.jglclear.eWhitelist", "Lissandra.jglclear.eWhitelist", 3, true, function()
                    Menu.Indent(function()
                        Menu.NewTree("Lissandra.jglclear.elist", "Jungle Camps 1", function()
                            for i, v in ipairs(jungleCamps) do
                                Menu.Checkbox("Lissandra.jgl.eWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Lissandra.jglclear.elist2", "Jungle Camps 2", function()
                            for i, v in ipairs(jungleCamps2) do
                                Menu.Checkbox("Lissandra.jgl.eWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Lissandra.jglclear.elist3", "Jungle Camps 3", function()
                            for i, v in ipairs(jungleCamps3) do
                                Menu.Checkbox("Lissandra.jgl.eWL." .. v.name, v.dName, v.default)
                            end
                            Menu.Checkbox("Lissandra.jgl.eDrake", "Other Drakes", true)
                        end)
                    end)
                end)
                Menu.Slider("Lissandra.jglclear.EManaSlider", "Don't use if Mana < %", 50, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Lissandra.stealMenu", "Steal Settings", function()
            Menu.NewTree("Lissandra.ksMenu", "Killsteal", function()
                Menu.Checkbox("Lissandra.ks.useQ", "Killsteal with Q", true)
                local cbResult = OriUtils.MGet("ks.useQ")
                if cbResult then
                    Menu.Indent(function()
                        Menu.NewTree("Lissandra.ksMenu.qWhitelist", "KS Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Lissandra.ks.qWL." .. heroName, "Q KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Lissandra.ks.useW", "Killsteal with W", true)
                local cbResultW = OriUtils.MGet("ks.useW")
                if cbResultW then
                    Menu.Indent(function()
                        Menu.NewTree("Lissandra.ksMenu.wWhitelist", "KS W Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Lissandra.ks.wWL." .. heroName, "W KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Lissandra.ks.useR", "Killsteal with R", false)
                local cbResult3 = OriUtils.MGet("ks.useR")
                if cbResult3 then
                    Menu.Indent(function()
                        Menu.NewTree("Lissandra.ksMenu.rWhitelist", "KS R Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Lissandra.ks.rWL." .. heroName, "R KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
            end)
            Menu.NewTree("Lissandra.jglstealMenu", "Junglesteal (Drake/Baron) | BETA", function()
                Menu.Checkbox("Lissandra.steal.useQ", "Junglesteal with Q", true)
                Menu.Checkbox("Lissandra.steal.useW", "Junglesteal with W", true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Lissandra.miscMenu", "Misc Settings", function()
            Menu.ColumnLayout("Lissandra.miscMenu.R", "Lissandra.miscMenu.R", 2, true, function()
                Menu.Text("")
                EHeader()  
                Menu.Checkbox("Lissandra.misc.FleeE", "Use E for Flee (HOLD Flee)", true)
                Menu.NextColumn()
                Menu.Text("")
                RHeader()
                Menu.Keybind("Lissandra.misc.forceR", "Force R", string.byte("T"), false, false, true)
                Menu.Keybind("Lissandra.misc.flashR", "Flash R", string.byte("G"), false, false, true)                
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Lissandra.hcMenu", "Hitchance Settings", function()
            Menu.ColumnLayout("Lissandra.hcMenu.QE", "Lissandra.hcMenu.QE", 2, true, function()
                Menu.Text("")
                QHeaderHit()
                Menu.Text("")
                Menu.Slider("Lissandra.hc.Q", "%", 60, 1, 100, 1)
                Menu.NextColumn()
                Menu.Text("")
                EHeaderHit()
                Menu.Text("")
                Menu.Slider("Lissandra.hc.E", "%", 60, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Lissandra.drawMenu", "Draw Settings", function()
            OriUtils.AddDrawMenu(drawData)
        end)
    end

    Menu.RegisterMenu(scriptName, scriptName, LissandraMenu)
end

function OnLoad()
    Lissandra.InitMenu()
    
    Lissandra.RegisterEvents()
    return true
end