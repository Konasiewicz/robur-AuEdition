if Player.CharName ~= "Kassadin" then return end

local scriptName = "AuKassadin"
local scriptCreator = "AURUM"
local credits = "Orietto"
local patchNotesPrevUpdate = "12/24/2021"
local patchNotesPreVersion = "1.2.5"
local patchNotesVersion, scriptVersionUpdater = "1.2.7", "1.2.8"
local scriptVersion = scriptVersionUpdater
local scriptLastUpdated = "02/19/2022"
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

SDK.AutoUpdate("https://raw.githubusercontent.com/roburAURUM/robur-AuEdition/main/AuKassadin.lua", scriptVersionUpdater)

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
        Base = {65, 95, 125, 155, 185},
        TotalAP = 0.7,
        Type = dmgTypes.Magical
    },
    W = {
        Base = {50, 75, 100, 125, 150},
        TotalAP  = 0.8,
        Type = dmgTypes.Magical
    },
    E = {
        Base = {80, 105, 130, 155, 180},
        TotalAP  = 0.8,
        Type = dmgTypes.Magical
    },
    R = {
        Base = {80, 100, 120},
        TotalAP = 0.4,
        Type = dmgTypes.Magical
    }
}

local spells = {
    Q = Spell.Targeted({
        Slot = slots.Q,
        Delay = 0.25,
        Speed = 1400,
        Range = 650,
        Collisions = {Windwall = true}
    }),
    W = Spell.Active({
        Slot = slots.W,
        Delay = 0,0,
        Speed = huge,
        Range = 300,
    }),
    E = Spell.Skillshot({
        Slot = slots.E,
        Delay = 0.25,
        Speed = huge,
        Range = 590,
        ConeAngleRad = 80 * (pi / 180),
        Type = "Cone",
    }),
    R = Spell.Skillshot({
        Slot = slots.R,
        Delay = 0.25,
        Speed = huge,
        Range = 500,
        Radius = 205,
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

    Menu.Checkbox(cacheName .. ".draw." .. "comboDamage", "Draw combo damage on healthbar", true)
    Menu.Checkbox(cacheName .. ".drawMenu.AlwaysDraw", "Always show Drawings", false)

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
    {slot = slots.Q, id = "Q", displayText = "[Q] Null Sphere", range = spells.Q.Range},
    {slot = slots.W, id = "W", displayText = "[W] Nether Blade", range = spells.W.Range},
    {slot = slots.E, id = "E", displayText = "[E] Force Pulse", range = spells.E.Range},
    {slot = slots.R, id = "R", displayText = "[R] Riftwalk", range = spells.R.Range}
}

--ASCIIArt
local ASCIIArt = "                 _  __                       _ _        "
local ASCIIArt2 = "      /\\        | |/ /                      | (_)       "
local ASCIIArt3 = "     /  \\  _   _| ' / __ _ ___ ___  __ _  __| |_ _ __   "
local ASCIIArt4 = "    / /\\ \\| | | |  < / _` / __/ __|/ _` |/ _` | | '_ \\  "
local ASCIIArt5 = "   / ____ \\ |_| | . \\ (_| \\__ \\__ \\ (_| | (_| | | | | | "
local ASCIIArt6 = "  /_/    \\_\\__,_|_|\\_\\__,_|___/___/\\__,_|\\__,_|_|_| |_| "

local Kassadin = {}

function Kassadin.flashR()
    if OriUtils.CanCastSpell(slots.R, "misc.flashR") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)

        local flashReady = spells.Flash.Slot and OriUtils.IsSpellReady(spells.Flash.Slot)
        if not flashReady then
            return
        end

        local rFlashRange = (spells.R.Range) + spells.Flash.Range
        local rFlashTarget = TS:GetTarget(rFlashRange, false)
        if rFlashTarget and not spells.R:IsInRange(rFlashTarget) then
            local flashPos = Player.ServerPos:Extended(rFlashTarget, spells.Flash.Range) 

            local spellInput = {
                Slot = slots.R,
                Delay = 0.25,
                Speed = huge,
                Range = 600,
                Radius = 270,
                Type = "Circular",
            }
            local pred = Prediction.GetPredictedPosition(rFlashTarget, spellInput, flashPos)
            if pred and pred.HitChanceEnum >= Enums.HitChance.Medium then

                if OriUtils.MGet("misc.flashR.options") == 0 then
                    if spells.R:Cast(rFlashTarget) then
                        delay(70, function() Input.Cast(spells.Flash.Slot, flashPos) end)
                        return
                    end
                else
                    if Input.Cast(spells.Flash.Slot, flashPos) then
                        delay(90, function()spells.R:Cast(rFlashTarget) end)
                        return
                    end
                end
            end
        end
    end
end

function Kassadin.KS()
    if OriUtils.MGet("ks.useQ") or OriUtils.MGet("ks.useW") or OriUtils.MGet("ks.useE") or  OriUtils.MGet("ks.useR") then
        local allyHeroes = ObjManager.GetNearby("ally", "heroes")
        for iKSA, objKSA in ipairs(allyHeroes) do
            local ally = objKSA.AsHero
            if not ally.IsMe and not ally.IsDead then
            local nearbyEnemiesKS = ObjManager.GetNearby("enemy", "heroes")
                for iKS, objKS in ipairs(nearbyEnemiesKS) do
                    local enemyHero = objKS.AsHero
                    local qDamage = Kassadin.GetDamage(enemyHero, slots.Q)
                    local healthPredQ = spells.Q:GetHealthPred(objKS)
                    local wDamage = Kassadin.GetDamage(enemyHero, slots.W)
                    local healthPredW = spells.W:GetHealthPred(objKS)
                    local eDamage = Kassadin.GetDamage(enemyHero, slots.E)
                    local healthPredE = spells.E:GetHealthPred(objKS)
                    local rDamage = Kassadin.GetDamage(enemyHero, slots.R)
                    local healthPredR = spells.R:GetHealthPred(objKS)
                    if not enemyHero.IsDead and enemyHero.IsVisible and enemyHero.IsTargetable then
                        if OriUtils.CanCastSpell(slots.Q, "ks.useQ") and spells.Q:IsInRange(objKS) then
                            if OriUtils.MGet("ks.qWL." .. enemyHero.CharName, true) then
                                if healthPredQ > 0 and healthPredQ < floor(qDamage - 50) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.Q:Cast(enemyHero) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.W, "ks.useW") and spells.W:IsInRange(objKS) then
                            if OriUtils.MGet("ks.wWL." .. enemyHero.CharName, true) then
                                if healthPredE > 0 and healthPredE < floor(eDamage - 50) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.W:Cast() then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.E, "ks.useE") and spells.E:IsInRange(objKS) then
                            if OriUtils.MGet("ks.eWL." .. enemyHero.CharName, true) then
                                if healthPredE > 0 and healthPredE < floor(eDamage - 50) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.E:Cast(enemyHero) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.R, "ks.useR") and spells.R:IsInRange(objKS) then
                            if OriUtils.MGet("ks.rWL." .. enemyHero.CharName, true) then
                                if healthPredR > 0 and healthPredR < floor(rDamage - 50) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.R:Cast(enemyHero) then
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

function Kassadin.DrakeSteal()
    if OriUtils.MGet("steal.useQ") or OriUtils.MGet("steal.useW") or OriUtils.MGet("steal.useE") or OriUtils.MGet("steal.useR") then 
        local enemiesAround = ObjManager.GetNearby("enemy", "heroes")
        for iSteal, objSteal in ipairs(enemiesAround) do
            local enemy = objSteal.AsHero
            if OriUtils.IsValidTarget(objSteal) then
                local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
                for iM, minion in ipairs(nearbyMinions) do
                    local minion = minion.AsMinion
                    local qDamage = Kassadin.GetDamage(minion, slots.Q)
                    local healthPredDrakeQ = spells.Q:GetHealthPred(minion)
                    local wDamage = Kassadin.GetDamage(minion, slots.W)
                    local healthPredDrakeW = spells.W:GetHealthPred(minion)
                    local eDamage = Kassadin.GetDamage(minion, slots.E)
                    local healthPredDrakeE = spells.E:GetHealthPred(minion)
                    local rDamage = Kassadin.GetDamage(minion, slots.R)
                    local healthPredDrakeR = spells.R:GetHealthPred(minion)
                    local AADmg = Orbwalker.GetAutoAttackDamage(minion)
                    if not minion.IsDead and minion.IsDragon and minion:Distance(enemy) < 1800 or enemy.IsInDragonPit then
                        if OriUtils.CanCastSpell(slots.Q, "steal.useQ") and spells.Q:IsInRange(minion) then
                            if healthPredDrakeQ > 0 and healthPredDrakeQ < floor(qDamage) then
                                if spells.Q:Cast(minion) then
                                    return
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.W, "steal.useW") and spells.W:IsInRange(minion)then
                            if healthPredDrakeW > 0 and healthPredDrakeW < floor(wDamage + AADmg) then
                                if spells.W:Cast() then
                                    return
                                end
                            end
                        end                        
                        if OriUtils.CanCastSpell(slots.E, "steal.useE") and spells.E:IsInRange(minion)then
                            if healthPredDrakeE > 0 and healthPredDrakeE < floor(eDamage) then
                                if spells.E:Cast(minion) then
                                    return
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.R, "steal.useR") and spells.R:IsInRange(minion)then
                            if healthPredDrakeR > 0 and healthPredDrakeR < floor(rDamage) then
                                if spells.R:Cast(minion) then
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

function Kassadin.BaronSteal()
    if OriUtils.MGet("steal.useQ") or OriUtils.MGet("steal.useW") or OriUtils.MGet("steal.useE") or  OriUtils.MGet("steal.useR") then 
        local enemiesAround = ObjManager.GetNearby("enemy", "heroes")
        for iSteal2, objSteal2 in ipairs(enemiesAround) do
            local enemy = objSteal2.AsHero
            if OriUtils.IsValidTarget(objSteal2) then
                local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
                for iM2, minion in ipairs(nearbyMinions) do
                    local minion = minion.AsMinion
                    local qDamage = Kassadin.GetDamage(minion, slots.Q)
                    local healthPredBaronQ = spells.Q:GetHealthPred(minion)
                    local wDamage = Kassadin.GetDamage(minion, slots.W)
                    local healthPredBaronW = spells.W:GetHealthPred(minion)
                    local eDamage = Kassadin.GetDamage(minion, slots.E)
                    local healthPredBaronE = spells.E:GetHealthPred(minion)
                    local rDamage = Kassadin.GetDamage(minion, slots.R)
                    local healthPredBaronR = spells.R:GetHealthPred(minion)
                    local AADmg = Orbwalker.GetAutoAttackDamage(minion)
                    if not minion.IsDead and minion.IsBaron and minion:Distance(enemy) < 1800 or enemy.IsInBaronPit then
                        if OriUtils.CanCastSpell(slots.Q, "steal.useQ") and spells.Q:IsInRange(minion) then
                            if healthPredBaronQ > 0 and healthPredBaronQ < floor(qDamage) then
                                if spells.Q:Cast(minion) then
                                    return
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.W, "steal.useW") and spells.W:IsInRange(minion)then
                            if healthPredBaronW > 0 and healthPredBaronW < floor(wDamage + AADmg) then
                                if spells.W:Cast() then
                                    return
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.E, "steal.useE") and spells.E:IsInRange(minion)then
                            if healthPredBaronE > 0 and healthPredBaronE < floor(eDamage) then
                                if spells.E:Cast(minion) then
                                    return
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.R, "steal.useR") and spells.R:IsInRange(minion)then
                            if healthPredBaronR > 0 and healthPredBaronR < floor(rDamage) then
                                if spells.R:Cast(minion) then
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

local slotToDamageTable = {
    [slots.Q] = damages.Q,
    [slots.W] = damages.W,
    [slots.E] = damages.E,
    [slots.R] = damages.R
}

---@param target AIBaseClient
---@param slot slut
function Kassadin.GetDamage(target, slot)
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

function events.OnDrawDamage(target, dmgList)
    if not OriUtils.MGet("draw.comboDamage") then
        return
    end

    local damageToDeal = 0

    if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
        damageToDeal = damageToDeal + Kassadin.GetDamage(target, slots.Q)
    end

    if spells.W:IsReady() and OriUtils.MGet("combo.useW") then
        damageToDeal = damageToDeal + Kassadin.GetDamage(target, slots.E)
    end

    if spells.E:IsReady() and OriUtils.MGet("combo.useE") then
        damageToDeal = damageToDeal + Kassadin.GetDamage(target, slots.E)
    end
    if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
        damageToDeal = damageToDeal + Kassadin.GetDamage(target, slots.R)
    end

    insert(dmgList, damageToDeal)
end

function Kassadin.RiftWalk() 
    if Player then
		local rUsage = Player:GetBuff("RiftWalk")
		if rUsage then 
			return rUsage.Count
		end
	end

	return 0
end

function combatVariants.Combo()
    if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
        local rTarget = spells.R:GetTarget()
        if rTarget then
            if Kassadin.RiftWalk() and OriUtils.MGet("combo.RSlider") == 4 then
                if spells.R:CastOnHitChance(rTarget, OriUtils.MGet("hc.R") / 100) then
                    return
                end
            elseif Kassadin.RiftWalk() < OriUtils.MGet("combo.RSlider") or Player.ManaPercent * 100 > OriUtils.MGet("combo.RManaSlider") then
                if spells.R:CastOnHitChance(rTarget, OriUtils.MGet("hc.R") / 100) then
                    return
                end
            end
        end
    end

    if spells.E:IsReady() and OriUtils.MGet("combo.useE") then
        local eTarget = spells.E:GetTarget()
        if eTarget then
            if spells.E:CastOnHitChance(eTarget, OriUtils.MGet("hc.E") / 100) then
                return
            end
        end
    end
    
    if spells.W:IsReady() and OriUtils.MGet("combo.useW") then
        local wTarget = spells.W:GetTarget()
        if wTarget then
            if spells.W:Cast() then
                return
            end
        end
    end

    if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
        local qTarget = spells.Q:GetTarget()
        if qTarget then
            if spells.Q:Cast(qTarget) then
                return
            end
        end
    end
end

function combatVariants.Harass()
    if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
        local qTarget = spells.Q:GetTarget()
        if qTarget then
            if spells.Q:Cast(qTarget) then
                return
            end
        end
    end

    if spells.E:IsReady() and OriUtils.MGet("combo.useE") then
        local eTarget = spells.E:GetTarget()
        if eTarget then
            if spells.E:CastOnHitChance(eTarget, OriUtils.MGet("hc.E") / 100) then
                return
            end
        end
    end    
end

function combatVariants.Waveclear()
    local myPos = Player.Position

    if OriUtils.CanCastSpell(slots.R, "jglclear.useR") then
    local jglminionsR = ObjManager.GetNearby("neutral", "minions")
    local minionsPositionsR = {}
        for iJGLR, objJGLR in ipairs (jglminionsR) do
            local minion = objJGLR.AsMinion
            if OriUtils.IsValidTarget(objJGLR, spells.R.Range) then
                insert(minionsPositionsR, minion.Position)
            end
        end

        local bestPos, numberOfHits = Geometry.BestCoveringCircle(minionsPositionsR, spells.R.Radius) 
        if numberOfHits >= 1 and Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.rManaSlider") then
            if Kassadin.RiftWalk() < OriUtils.MGet("jglclear.RSlider") then
                if not Orbwalker.IsWindingUp() then
                    if spells.R:Cast(bestPos) then
                        return
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.Q, "jglclear.useQ") then
        local jglminionsQ = ObjManager.GetNearby("neutral", "minions")
        for iJGLQ, objJGLQ in ipairs(jglminionsQ) do
            if OriUtils.IsValidTarget(objJGLQ, spells.Q.Range) then
                if Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.QManaSlider") then
                    if not Orbwalker.IsWindingUp() then
                        if spells.Q:Cast(objJGLQ) then
                            return
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "jglclear.useW") then
        local jglminionsW = ObjManager.GetNearby("neutral", "minions")
        for iJGLW, objJGLW in ipairs(jglminionsW) do
            if OriUtils.IsValidTarget(objJGLW, spells.W.Range) then
                if Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.WManaSlider") then
                    if not Orbwalker.IsWindingUp() then
                        if spells.W:Cast() then
                            return
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "jglclear.useE") then
        local jglminionsE = ObjManager.GetNearby("neutral", "minions")
        local minionsPositions = {}

        for iJGLE, objJGLE in ipairs(jglminionsE) do
            local minion = objJGLE.AsMinion
            if OriUtils.IsValidTarget(objJGLE, spells.E.Range) then
                insert(minionsPositions, minion.Position)
            end
        end
        
        local bestPos, numberOfHits = Geometry.BestCoveringCone(minionsPositions, myPos, spells.E.ConeAngleRad) 
        if numberOfHits >= 1 and Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.EManaSlider") then
            if not Orbwalker.IsWindingUp() then
                if spells.E:Cast(bestPos) then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.Q, "clear.pokeQ") then
        if Orbwalker.IsWindingUp() then
            return
        else
            local qTarget = spells.Q:GetTarget()
            if qTarget and not Orbwalker.IsWindingUp() then
                if spells.Q:Cast(qTarget) then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "clear.useW") then
        local nearbyMinions = ObjManager.GetNearby("enemy", "minions")
        for i, minion in ipairs(nearbyMinions) do
            local healthPred = spells.W:GetHealthPred(minion)
            local minion = minion.AsMinion
            local wDamage = Kassadin.GetDamage(minion, slots.W)
            local AADmg = Orbwalker.GetAutoAttackDamage(minion)
            if not minion.IsDead and spells.W:IsInRange(minion) then
                if healthPred > 0 and healthPred < floor(wDamage + AADmg) then
                    if spells.W:Cast() then
                        return
                    end
                end
            end
        end
    end

    if OriUtils.MGet("clear.enemiesAround") and TS:GetTarget(1800) then
        return
    end

    if OriUtils.CanCastSpell(slots.Q, "clear.useQ") then
        local qMinions = ObjManager.GetNearby("enemy", "minions")
        for iQ, minionQ in ipairs(qMinions) do 
            local healthPred = spells.Q:GetHealthPred(minionQ)
            local minion = minionQ.AsMinion
            local qDamage = Kassadin.GetDamage(minion, slots.Q)
            local AARange = Orbwalker.GetTrueAutoAttackRange(Player)
            if Player.ManaPercent * 100 >= OriUtils.MGet("clear.QManaSlider") then
                if OriUtils.MGet("clear.useQ.options") == 0 then
                    if not minion.IsDead and minion.IsSiegeMinion then
                        if spells.Q:IsInRange(minion) and Player:Distance(minion) > AARange + 100 then
                            if healthPred > 0 and healthPred < floor(qDamage) then
                                if spells.Q:Cast(minion) then
                                    return
                                end
                            end
                        end
                    end
                else
                    if not minion.IsDead and spells.Q:IsInRange(minion) and Player:Distance(minion) > AARange + 100 then
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
    end

    if OriUtils.CanCastSpell(slots.E, "clear.useE") then
        local minionsInERange = ObjManager.GetNearby("enemy", "minions")
        local minionsPositions = {}

        for _, minion in ipairs(minionsInERange) do
            if spells.E:IsInRange(minion) then
                insert(minionsPositions, minion.Position)
            end
        end

        local bestPos, numberOfHits = Geometry.BestCoveringCone(minionsPositions, myPos, spells.E.ConeAngleRad) 
        if numberOfHits >= OriUtils.MGet("clear.eMinions") then
            if Player.ManaPercent * 100 >= OriUtils.MGet("clear.EManaSlider") then
                if not Orbwalker.IsWindingUp() then
                    if spells.E:Cast(bestPos) then
                        return
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.R, "clear.useR") then
        local minionsInRRange = ObjManager.GetNearby("enemy", "minions")
        local minionsPositionsR = {}

        for _, minion in ipairs(minionsInRRange) do
            if spells.R:IsInRange(minion) then
                insert(minionsPositionsR, minion.Position)
            end
        end
    
        local bestPos, numberOfHits = Geometry.BestCoveringCircle(minionsPositionsR, spells.R.Radius) 
        if numberOfHits >= OriUtils.MGet("clear.rMinions") and Player.ManaPercent * 100 >= OriUtils.MGet("clear.rManaSlider") then
            if Kassadin.RiftWalk() < OriUtils.MGet("clear.RSlider") then
                if not Orbwalker.IsWindingUp() then
                    if spells.R:Cast(bestPos) then
                        return
                    end
                end
            end
        end
    end
end

function combatVariants.Lasthit()
    if OriUtils.CanCastSpell(slots.W, "lasthit.useW") then 
        local nearbyMinions = ObjManager.GetNearby("enemy", "minions")
        for i, minion in ipairs(nearbyMinions) do
            local healthPred = spells.W:GetHealthPred(minion)
            local minion = minion.AsMinion
            local wDamage = Kassadin.GetDamage(minion, slots.W)
            local AADmg = Orbwalker.GetAutoAttackDamage(minion)
            if not minion.IsDead and spells.W:IsInRange(minion) then
                if healthPred > 0 and healthPred < floor(wDamage + AADmg) then
                    if spells.W:Cast() then
                        return
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.Q, "lasthit.useQ") then
    local nearbyMinionsQ = ObjManager.GetNearby("enemy", "minions")
        for iQ, minionQ in ipairs(nearbyMinionsQ) do
            local healthPred = spells.Q:GetHealthPred(minionQ)
            local minion = minionQ.AsMinion
            local qDamage = Kassadin.GetDamage(minion, slots.Q)
            local AARange = Orbwalker.GetTrueAutoAttackRange(Player)
            if not minion.IsDead and spells.Q:IsInRange(minion) then
                if Player:Distance(minion) > AARange then
                    if not spells.W:IsReady() or not spells.W:IsInRange(minion) then
                        if OriUtils.MGet("lasthit.useQ.options") == 0 then
                            if minion.IsSiegeMinion then
                                if Player.ManaPercent * 100 > OriUtils.MGet("lasthit.useQ.0.ManaSlider") then
                                    if healthPred > 0 and healthPred < floor(qDamage) then
                                        if spells.Q:Cast(minion) then
                                            return
                                        end
                                    end
                                end
                            end
                        else
                            if minion.IsSiegeMinion and OriUtils.MGet("lasthit.useQ.alwaysCanon") then
                                if healthPred > 0 and healthPred < floor(qDamage) then
                                    if spells.Q:Cast(minion) then
                                        return
                                    end
                                end
                            else
                                if Player.ManaPercent * 100 > OriUtils.MGet("lasthit.useQ.1.ManaSlider") then
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
            end
        end
    end
end

function combatVariants.Flee()
    local mousePos = Player.Position:Extended(Renderer.GetMousePos(), 1500)
    if spells.R:IsReady() and OriUtils.MGet("misc.useR") then
        if OriUtils.MGet("misc.useRNoSlider") then
            if spells.R:Cast(mousePos) then
                return
            end
        else
            if Kassadin.RiftWalk() < OriUtils.MGet("misc.RSlider") then
                if spells.R:Cast(mousePos) then
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

    Kassadin.flashR()
    Kassadin.KS()
    Kassadin.BaronSteal()
    Kassadin.DrakeSteal()
end


-- Register Events

function events.OnDraw()
    if Player.IsDead then
        return
    end

    local myPos = Player.Position

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

    if OriUtils.MGet("misc.flashR") then
        local flashReady = spells.Flash.Slot and OriUtils.IsSpellReady(spells.Flash.Slot)
        if spells.R:IsReady() then
            if not flashReady then
                return Renderer.DrawTextOnPlayer("Flash not Ready", 0xFF0000FF)
            else
                if OriUtils.MGet("misc.flashR.options") == 1 then
                    local rRange = spells.Flash.Range + spells.R.Range
                    return Renderer.DrawCircle3D(myPos, rRange, 30, 5, 0xFF0000FF)
                else
                    local rRange = spells.Flash.Range - 120 + spells.R.Range
                    return Renderer.DrawCircle3D(myPos, rRange, 30, 5, 0xFF0000FF)
                end
            end
        else
            if flashReady then
                return Renderer.DrawTextOnPlayer("R not Ready", scriptColor)
            else
                return Renderer.DrawTextOnPlayer("R and Flash not Ready", 0xFFFF00FF)
            end
        end
    end
end

-- debug buffgain and bufflost
---@param obj GameObject
---@param buffInst BuffInst
function events.OnBuffGain(obj, buffInst)
    if obj and buffInst then
        if --obj.IsEnemy and 
        obj.IsHero then
            --INFO("An enemy hero gained the buff: " .. buffInst.Name)
        end
    end
end
-- debug buffgain and bufflost
---@param obj GameObject
---@param buffInst BuffInst
function events.OnBuffLost(obj, buffInst)
    if obj and buffInst then
        if --obj.IsEnemy and 
        obj.IsHero then
            --INFO("An enemy hero lost the buff: " .. buffInst.Name)
        end
    end
end

function Kassadin.RegisterEvents()
    for eventName, eventId in pairs(Enums.Events) do
        if events[eventName] then
            EventManager.RegisterCallback(eventId, events[eventName])
        end
    end
end

-- Menu

function Kassadin.InitMenu()
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

    local function KassadinMenu()
        Menu.NewTree("Kassadin.comboMenu", "Combo Settings", function()
            Menu.ColumnLayout("Kassadin.comboMenu.QE", "Kassadin.comboMenu.QE", 2, true, function()
                QHeader()
                Menu.Checkbox("Kassadin.combo.useQ", "Enable Q", true)
                Menu.NextColumn()
                EHeader()
                Menu.Checkbox("Kassadin.combo.useE", "Enable E", true)
            end)

            Menu.ColumnLayout("Kassadin.comboMenu.WR", "Kassadin.comboMenu.WR", 2, true, function()
                WHeader()
                Menu.Checkbox("Kassadin.combo.useW", "Enable W", true)
                Menu.NextColumn()
                RHeader()
                Menu.Checkbox("Kassadin.combo.useR", "Enable R", true)
                Menu.Slider("Kassadin.combo.RSlider", "Use R X Times", 3, 1, 4)
                Menu.ColoredText("Will ignore Stacks, if Mana is above below Value", scriptColor, true)
                Menu.Slider("Kassadin.combo.RManaSlider", "Use R if Mana is above x %", 35, 1, 100, 1)
            end)
        end)

        Menu.NewTree("Kassadin.harassMenu", "Harass Settings", function()
            Menu.ColumnLayout("Kassadin.harassMenu.QE", "Kassadin.harassMenu.QE", 2, true, function()
                QHeader()
                Menu.Checkbox("Kassadin.harass.useQ", "Enable Q", true)
                Menu.NextColumn()
                EHeader()
                Menu.Checkbox("Kassadin.harass.useE", "Enable E", false)
            end)
        end)

        Menu.NewTree("Kassadin.clearMenu", "Clear Settings", function()
            Menu.NewTree("Kassadin.waveMenu", "Waveclear", function()
                Menu.Checkbox("Kassadin.clear.enemiesAround", "Don't clear while enemies around", true)
                Menu.Checkbox("Kassadin.clear.pokeQ", "Enable Q Poke on Enemy", true)
                Menu.Checkbox("Kassadin.clear.useQ", "Use Q if not in Range for W", false)
                Menu.Dropdown("Kassadin.clear.useQ.options", "Use Q for", 0, {"Canon", "All"})
                Menu.Slider("Kassadin.clear.QManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Checkbox("Kassadin.clear.useW", "Enable W", true)
                Menu.Checkbox("Kassadin.clear.useE", "Enable E", true)
                Menu.Slider("Kassadin.clear.eMinions", "if X Minions", 5, 1, 6, 1)
                Menu.Slider("Kassadin.clear.EManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Checkbox("Kassadin.clear.useR", "Use R", true)
                Menu.Slider("Kassadin.clear.rMinions", "if X Minions", 5, 1, 6, 1)
                Menu.Slider("Kassadin.clear.rManaSlider", "Don't use if Mana < %", 45, 1, 100, 1)
                Menu.Slider("Kassadin.clear.RSlider", "Use R X Times", 2, 1, 5)
            end)
            Menu.NewTree("Kassadin.jglMenu", "Jungleclear", function()
                Menu.Checkbox("Kassadin.jglclear.useQ", "Use Q", true)
                Menu.Slider("Kassadin.jglclear.QManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Checkbox("Kassadin.jglclear.useW", "Use W", true)
                Menu.Slider("Kassadin.jglclear.WManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Checkbox("Kassadin.jglclear.useE", "Use E", true)
                Menu.Slider("Kassadin.jglclear.EManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Checkbox("Kassadin.jglclear.useR", "Use R", true)
                Menu.Slider("Kassadin.jglclear.rManaSlider", "Don't use if Mana < %", 45, 1, 100, 1)
                Menu.Slider("Kassadin.jglclear.RSlider", "Use R X Times", 2, 1, 5)
            end)
        end)

        Menu.NewTree("Kassadin.lasthitMenu", "Lasthit Settings", function()
            Menu.ColumnLayout("Kassadin.lasthitMenu.W", "Kassadin.lasthitMenu.W", 1, true, function()
                QHeader()
                Menu.Checkbox("Kassadin.lasthit.useQ", "Use Q if not in Range for W", true)
                Menu.Dropdown("Kassadin.lasthit.useQ.options", "Use Q on", 0, {"Canon", "All"})
                local ddResultW = OriUtils.MGet("lasthit.useQ.options") == 0
                if ddResultW then
                    Menu.Slider("Kassadin.lasthit.useQ.0.ManaSlider", "Only use if Mana above X", 40, 1, 100, 1)
                end
                local ddResultW1 = OriUtils.MGet("lasthit.useQ.options") == 1
                if ddResultW1 then
                    Menu.Slider("Kassadin.lasthit.useQ.1.ManaSlider", "Only use if Mana above X", 40, 1, 100, 1)
                    Menu.Checkbox("Kassadin.lasthit.useQ.alwaysCanon", "Always use for Canon", true)
                end
                WHeader()
                Menu.Checkbox("Kassadin.lasthit.useW", "Enable W", true)
            end)
        end)

        Menu.NewTree("Kassadin.stealMenu", "Steal Settings", function()
            Menu.NewTree("Kassadin.ksMenu", "Killsteal", function()
                Menu.Checkbox("Kassadin.ks.useQ", "Killsteal with Q", true)
                local cbResult = OriUtils.MGet("ks.useQ")
                if cbResult then
                    Menu.Indent(function()
                        Menu.NewTree("Kassadin.ksMenu.qWhitelist", "KS Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Kassadin.ks.qWL." .. heroName, "Q KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Kassadin.ks.useW", "Killsteal with W", true)
                local cbResultW = OriUtils.MGet("ks.useW")
                if cbResultW then
                    Menu.Indent(function()
                        Menu.NewTree("Kassadin.ksMenu.wWhitelist", "KS W Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Kassadin.ks.wWL." .. heroName, "W KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Kassadin.ks.useE", "Killsteal with E", true)
                local cbResult2 = OriUtils.MGet("ks.useE")
                if cbResult2 then
                    Menu.Indent(function()
                        Menu.NewTree("Kassadin.ksMenu.eWhitelist", "KS E Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Kassadin.ks.eWL." .. heroName, "E KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Kassadin.ks.useR", "Killsteal with R", false)
                local cbResult3 = OriUtils.MGet("ks.useR")
                if cbResult3 then
                    Menu.Indent(function()
                        Menu.NewTree("Kassadin.ksMenu.rWhitelist", "KS R Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Kassadin.ks.rWL." .. heroName, "R KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
            end)
            Menu.NewTree("Kassadin.jglstealMenu", "Junglesteal (Drake/Baron) | BETA", function()
                Menu.Checkbox("Kassadin.steal.useQ", "Junglesteal with Q", true)
                Menu.Checkbox("Kassadin.steal.useW", "Junglesteal with W", true)
                Menu.Checkbox("Kassadin.steal.useE", "Junglesteal with E", true)
                Menu.Checkbox("Kassadin.steal.useR", "Junglesteal with R", false)
            end)
        end)

        Menu.NewTree("Kassadin.miscMenu", "Misc Settings", function()
            Menu.ColumnLayout("Kassadin.miscMenu.R", "Kassadin.miscMenu.R", 2, true, function()
                RHeader()
                Menu.Keybind("Kassadin.misc.flashR", "Flash R", string.byte("G"), false, false, true)
                Menu.Dropdown("Kassadin.misc.flashR.options", "Mode", 1, {"R > Flash (Experimental)", "Flash > R (Slower)"})
                Menu.NextColumn()
                RHeader()
                Menu.Checkbox("Kassadin.misc.useR", "Use R for Flee", true)
                Menu.Slider("Kassadin.misc.RSlider", "Use R only if < Stacks", 4, 1, 4)
                Menu.Checkbox("Kassadin.misc.useRNoSlider", "Ignore R Stacks", true)
            end)
        end)

        Menu.NewTree("Kassadin.hcMenu", "Hitchance Settings", function()
            Menu.ColumnLayout("Kassadin.hcMenu.QE", "Kassadin.hcMenu.QE", 2, true, function()
                EHeaderHit()
                Menu.Slider("Kassadin.hc.E", "%", 60, 1, 100, 1)
                Menu.NextColumn()
                RHeaderHit()
                Menu.Slider("Kassadin.hc.R", "%", 60, 1, 100, 1)
            end)
        end)

        Menu.NewTree("Kassadin.drawMenu", "Draw Settings", function()
            OriUtils.AddDrawMenu(drawData)
        end)
    end

    Menu.RegisterMenu(scriptName, scriptName, KassadinMenu)
end

function OnLoad()
    Kassadin.InitMenu()
    
    Kassadin.RegisterEvents()
    return true
end
