if Player.CharName ~= "KogMaw" then return end

local scriptName = "AuKogMaw"
local scriptCreator = "AURUM"
local credits = "Orietto"
local patchNotesPrevUpdate = "02/19/2022"
local patchNotesPreVersion = "1.3.0"
local patchNotesVersion, scriptVersionUpdater = "1.3.2", "1.3.2"
local scriptVersion = scriptVersionUpdater
local scriptLastUpdated = "02/20/2022"
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

SDK.AutoUpdate("https://raw.githubusercontent.com/roburAURUM/robur-AuEdition/main/AuKogMaw.lua", scriptVersionUpdater)

local ObjManager = SDK.ObjectManager
local EventManager = SDK.EventManager
local Geometry = SDK.Geometry
local Renderer = SDK.Renderer
local Enums = SDK.Enums
local Game = SDK.Game
local Input = SDK.Input

local Libs = _G.Libs

local Menu = Libs.NewMenu
local Orbwalker = Libs.Orbwalker
local Collision = Libs.CollisionLib
local Prediction = Libs.Prediction
local Spell = Libs.Spell
local DmgLib = Libs.DamageLib
local TS = Libs.TargetSelector()

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
        Base = {90, 140, 190, 240, 290},
        TotalAP = 0.70,
        Type = dmgTypes.Magical
    },
    E = {
        Base = {75, 120, 165, 210, 255},
        TotalAP  = 0.7,
        Type = dmgTypes.Magical
    },
    R = {
        Base = {100, 140, 180},
        TotalAP = 0.35,
        Type = dmgTypes.Magical
    }
}

local spells = {
    Q = Spell.Skillshot({
        Slot = slots.Q,
        Delay = 0.25,
        Speed = 1650,
        Range = 1185,
        Radius = 140 / 2,
        Collisions = {Heroes = true, Minions = true, Windwall = true}
    }),
    W = Spell.Active({
        Slot = slots.W,
        Delay = 0.0,
        Range = 730,
    }),
    E = Spell.Skillshot({
        Slot = slots.E,
        Delay = 0.0,
        Speed = 1400,
        Range = 1200,
        Radius = 240 / 2,
        Type = "Linear",
        Collisions = {Windwall = true}
    }),
    R = Spell.Skillshot({
        Slot = slots.R,
        Delay = 0.25 + 1.0,
        Speed = huge,
        Range = 1300,
        Radius = 175,
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

function OriUtils.IsSpellReady(slot)
    return Player:GetSpellState(slot) == Enums.SpellStates.Ready
end

function OriUtils.ShouldRunLogic()
    return not (Game.IsChatOpen() or Game.IsMinimized() or Player.IsDead or Player.IsRecalling)
end

function OriUtils.MGet(menuId, nothrow)
    return Menu.Get(cacheName .. "." .. menuId, nothrow)
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

    Menu.Checkbox("KogMaw.drawMenu.wPassiveTimer", "Show W Duration Timer", true)
    Menu.Checkbox(cacheName .. ".draw." .. "comboDamage", "Draw combo damage on healthbar", true)
    Menu.Checkbox("KogMaw.drawMenu.EnableAA", "Show AA Damage", true)
    Menu.Slider("KogMaw.drawMenu.AASlider", "AA's", 2, 1, 10, 1)
    Menu.Slider("KogMaw.drawMenu.RSlider", "R's", 1, 0, 5, 1)
    Menu.Checkbox("KogMaw.drawMenu.AlwaysDraw", "Always show Drawings", false)

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
    {slot = slots.Q, id = "Q", displayText = "[Q] Caustic Spittle", range = spells.Q.Range},
    {slot = slots.W, id = "W", displayText = "[W] Bio-Arcane Barrage", range = function () return spells.W.Range end},
    {slot = slots.E, id = "E", displayText = "[E] void Ooze", range = spells.E.Range},
    {slot = slots.R, id = "R", displayText = "[R] Living Artillery", range = function() return spells.R.Range end}
}

local ASCIIArt = "                 _  __           __  __                 "
local ASCIIArt2 = "      /\\        | |/ /          |  \\/  |                "
local ASCIIArt3 = "     /  \\  _   _| ' / ___   __ _| \\  / | __ ___      __ "
local ASCIIArt4 = "    / /\\ \\| | | |  < / _ \\ / _` | |\\/| |/ _` \\ \\ /\\ / / "
local ASCIIArt5 = "   / ____ \\ |_| | . \\ (_) | (_| | |  | | (_| |\\ V  V /  "
local ASCIIArt6 = "  /_/    \\_\\__,_|_|\\_\\___/ \\__, |_|  |_|\\__,_| \\_/\\_/   "
local ASCIIArt7 = "                            __/ |                       "
local ASCIIArt8 = "	                          |___/                        "

local KogMaw = {}

KogMaw.baseAADamage = Player.BaseAttackDamage
KogMaw.AD = KogMaw.baseAADamage + Player.FlatPhysicalDamageMod

local slotToDamageTable = {
    [slots.Q] = damages.Q,
    [slots.W] = damages.W,
    [slots.E] = damages.E,
    [slots.R] = damages.R
}

---@param target AIBaseClient
---@param slot slut
function KogMaw.GetDamage(target, slot)
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
        damageToDeal = damageToDeal + KogMaw.GetDamage(target, slots.Q)
    end

    if spells.W:IsReady() and OriUtils.MGet("combo.useW") then
        damageToDeal = damageToDeal + KogMaw.GetDamage(target, slots.W)
    end

    if spells.E:IsReady() and OriUtils.MGet("combo.useE") then
        damageToDeal = damageToDeal + KogMaw.GetDamage(target, slots.E)
    end
    if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
        damageToDeal = damageToDeal + (KogMaw.GetDamage(target, slots.R) * OriUtils.MGet("drawMenu.RSlider"))
    end

    if OriUtils.MGet("drawMenu.EnableAA") then
        damageToDeal = damageToDeal + (KogMaw.AD * OriUtils.MGet("drawMenu.AASlider"))
    end

    insert(dmgList, damageToDeal)
end

KogMaw.LatestW = 0
KogMaw.LatestR = 0

local WLevelRanges = {
    [1] = 730,
    [2] = 750,
    [3] = 770,
    [4] = 790,
    [5] = 810,
}

local RLevelRanges = {
    [1] = 1300,
    [2] = 1550,
    [3] = 1800
}

function KogMaw.UpdateWRange()
    local curLevel = spells.W:GetLevel()
    if curLevel ~= KogMaw.LatestW then
        spells.W.Range = WLevelRanges[curLevel]

        KogMaw.LatestW = curLevel
    end
end

function KogMaw.UpdateRRange()
    local curLevel = spells.R:GetLevel()
    if curLevel ~= KogMaw.LatestR then
        spells.R.Range = RLevelRanges[curLevel]

        KogMaw.LatestR = curLevel
    end
end

function KogMaw.BigDickOriettoEnergy(minionTable, range)
    for _, minion in ipairs(minionTable) do
        if OriUtils.IsValidTarget(minion, range) then
            return true
        end
    end

    return false
end

function KogMaw.wTime()
    local wPassive = Player:GetBuff("KogMawBioArcaneBarrage")
    if wPassive then
        local wPassiveRounded = math.floor(wPassive.DurationLeft * 10) / 10
        return Renderer.DrawTextOnPlayer("Time left: " .. wPassiveRounded, scriptColor)
    end
end

function KogMaw.KS()
    if OriUtils.MGet("ks.useQ") or  OriUtils.MGet("ks.useR") then
        local allyHeroes = ObjManager.GetNearby("ally", "heroes")
        for iKSA, objKSA in ipairs(allyHeroes) do
            local ally = objKSA.AsHero
            if not ally.IsMe and not ally.IsDead then
            local nearbyEnemiesKS = ObjManager.GetNearby("enemy", "heroes")
                for iKS, objKS in ipairs(nearbyEnemiesKS) do
                    local enemyHero = objKS.AsHero
                    local qDamage = KogMaw.GetDamage(enemyHero, slots.Q)
                    local healthPredQ = spells.Q:GetHealthPred(objKS)
                    local rDamage = KogMaw.GetDamage(enemyHero, slots.R)
                    local healthPredR = spells.R:GetHealthPred(objKS)
                    if not enemyHero.IsDead and enemyHero.IsVisible and enemyHero.IsTargetable then
                        if OriUtils.CanCastSpell(slots.Q, "ks.useQ") and spells.Q:IsInRange(objKS) then
                            if OriUtils.MGet("ks.qWL." .. enemyHero.CharName, true) then
                                if healthPredQ > 0 and healthPredQ < floor(qDamage - 50) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.Q:CastOnHitChance(enemyHero, Enums.HitChance.Medium) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.R, "ks.useR") and spells.R:IsInRange(objKS) then
                            if enemyHero.HealthPercent < 40 then
                                if OriUtils.MGet("ks.rWL." .. enemyHero.CharName, true) then
                                    if healthPredR > 0 and healthPredR < floor(rDamage * 1.99) then
                                        if not Orbwalker.IsWindingUp() then
                                            if spells.R:CastOnHitChance(enemyHero, Enums.HitChance.Low) then
                                                return
                                            end
                                        end
                                    end
                                end
                            else
                                if healthPredR > 0 and healthPredR < floor(rDamage) then
                                    if OriUtils.MGet("ks.rWL." .. enemyHero.CharName, true) then
                                        if not Orbwalker.IsWindingUp() then
                                            if spells.R:CastOnHitChance(enemyHero, Enums.HitChance.Low) then
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

end

function KogMaw.DrakeSteal()
    if OriUtils.MGet("steal.useQ") or OriUtils.MGet("steal.useE") or OriUtils.MGet("steal.useR") then 
        local enemiesAround = ObjManager.GetNearby("enemy", "heroes")
        for iSteal, objSteal in ipairs(enemiesAround) do
            local enemy = objSteal.AsHero
            if not enemy.IsDead then
                local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
                for iM, minion in ipairs(nearbyMinions) do
                    local minion = minion.AsMinion
                    local qDamage = KogMaw.GetDamage(minion, slots.Q)
                    local healthPredDrakeQ = spells.Q:GetHealthPred(minion)
                    local eDamage = KogMaw.GetDamage(minion, slots.E)
                    local healthPredDrakeE = spells.E:GetHealthPred(minion)
                    local rDamage = KogMaw.GetDamage(minion, slots.R)
                    local healthPredDrakeR = spells.R:GetHealthPred(minion)
                    if not minion.IsDead and minion.IsDragon and minion:Distance(enemy) < 1800 or enemy.IsInDragonPit then
                        if OriUtils.CanCastSpell(slots.Q, "steal.useQ") then
                            if OriUtils.IsValidTarget(minion, spells.Q.Range) then
                                if healthPredDrakeQ > 0 and healthPredDrakeQ < floor(qDamage) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.Q:Cast(minion) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.E, "steal.useE") then
                            if OriUtils.IsValidTarget(minion, spells.E.Range) then
                                if healthPredDrakeE > 0 and healthPredDrakeE < floor(eDamage) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.E:Cast(minion) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.R, "steal.useR") then
                            if OriUtils.IsValidTarget(minion, spells.R.Range) then
                                if healthPredDrakeR > 0 and healthPredDrakeR < floor(rDamage) then
                                    if not Orbwalker.IsWindingUp() then
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
    end
end

function KogMaw.BaronSteal()
    if OriUtils.MGet("steal.useQ") or  OriUtils.MGet("steal.useR") then 
        local enemiesAround = ObjManager.GetNearby("enemy", "heroes")
        for iSteal2, objSteal2 in ipairs(enemiesAround) do
            local enemy = objSteal2.AsHero
            if not enemy.IsDead then
                local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
                for iM2, minion in ipairs(nearbyMinions) do
                    local minion = minion.AsMinion
                    local qDamage = KogMaw.GetDamage(minion, slots.Q)
                    local healthPredBaronQ = spells.Q:GetHealthPred(minion)
                    local eDamage = KogMaw.GetDamage(minion, slots.E)
                    local healthPredBaronE = spells.E:GetHealthPred(minion)
                    local rDamage = KogMaw.GetDamage(minion, slots.R)
                    local healthPredBaronR = spells.R:GetHealthPred(minion)
                    if not minion.IsDead and minion.IsBaron and minion:Distance(enemy) < 1800 or enemy.IsInBaronPit then
                        if OriUtils.CanCastSpell(slots.Q, "steal.useQ") then
                            if OriUtils.IsValidTarget(minion, spells.Q.Range) then
                                if healthPredBaronQ > 0 and healthPredBaronQ < floor(qDamage) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.Q:Cast(minion) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.E, "steal.useE") then
                            if OriUtils.IsValidTarget(minion, spells.E.Range) then
                                if healthPredBaronE > 0 and healthPredBaronE < floor(eDamage) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.E:Cast(minion) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.R, "steal.useR") then
                            if OriUtils.IsValidTarget(minion, spells.R.Range) then
                                if healthPredBaronR > 0 and healthPredBaronR < floor(rDamage) then
                                    if not Orbwalker.IsWindingUp() then
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
    end
end

function KogMaw.SpellCostTest()
    local WMana = spells.W:GetManaCost()
end

function KogMaw.forceR()
    if OriUtils.MGet("misc.forceR") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)
        if spells.R:IsReady() then        
            local rTarget = spells.R:GetTarget()
            if rTarget then
                if spells.R:CastOnHitChance(rTarget, OriUtils.MGet("hcNew.R") / 100) then
                    return
                end
            end
        end
    end
end

function KogMaw.ArtilleryStacks() 
    if Player then
		local rUsage = Player:GetBuff("kogmawlivingartillerycost")
		if rUsage then 
			return rUsage.Count
		end
	end

	return 0
end

function combatVariants.Combo()
    if OriUtils.CanCastSpell(slots.Q, "combo.useQ") then
        local qTarget = spells.Q:GetTarget()
        if qTarget and not Orbwalker.IsWindingUp() then
            if spells.Q:CastOnHitChance(qTarget, OriUtils.MGet("hcNew.Q") / 100) then
                return
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "combo.useW") then
        local wTarget = spells.W:GetTarget()
        if wTarget and not Orbwalker.IsWindingUp() then
            if spells.W:Cast() then
                return
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "combo.useE") then
        local eTarget = spells.E:GetTarget()
        if eTarget and not Orbwalker.IsWindingUp() then
            if spells.E:CastOnHitChance(eTarget, OriUtils.MGet("hcNew.E") / 100) then
                return
            end
        end
    end

    if OriUtils.CanCastSpell(slots.R, "combo.useR") then
        local rTarget = spells.R:GetTarget()
        local AARange = Orbwalker.GetTrueAutoAttackRange(Player)
        local baseAASpeed = 0.665
        local AASpeed = baseAASpeed * Player.AttackSpeedMod
        local AABase = TS:GetTarget(AARange, false)
        
        if rTarget then
            if AASpeed >= OriUtils.MGet("AdvancedR.AASpeed") then
                return
            end
            if AABase then
                if Player.ManaPercent * 100 >= OriUtils.MGet("combo.RManaSlider") then
                    if KogMaw.ArtilleryStacks() < OriUtils.MGet("combo.RSlider") then
                        local enemiesHP = ObjManager.GetNearby("enemy", "heroes")
                        for i, obj in ipairs (enemiesHP) do
                        local enemyHP = obj.AsHero
                            if not enemyHP.IsDead then
                                if enemyHP.HealthPercent * 100 <= OriUtils.MGet("AdvancedR.TargetHP") then
                                    if AASpeed <= OriUtils.MGet("AdvancedR.AASpeed3") then
                                        if (Player.Level >= OriUtils.MGet("AdvancedR.Level2")) or (KogMaw.AD > OriUtils.MGet("AdvancedR.AD2")) then
                                            if not Orbwalker.IsWindingUp() then
                                                if spells.R:CastOnHitChance(rTarget, OriUtils.MGet("hcNew.R") / 100) then
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
            if AABase then
                if Player.ManaPercent * 100 >= OriUtils.MGet("combo.RManaSlider") then
                    if KogMaw.ArtilleryStacks() < OriUtils.MGet("combo.RSlider") then
                        if AASpeed < OriUtils.MGet("AdvancedR.AASpeed2") then
                            if (Player.Level < OriUtils.MGet("AdvancedR.Level")) or (KogMaw.AD < OriUtils.MGet("AdvancedR.AD")) then
                                if not Orbwalker.IsWindingUp() then
                                    if spells.R:CastOnHitChance(rTarget, OriUtils.MGet("hcNew.R") / 100) then
                                        return
                                    end
                                end
                            end
                        end
                    end
                end
            elseif Player.ManaPercent * 100 >= OriUtils.MGet("combo.RManaSlider") then
                if KogMaw.ArtilleryStacks() < OriUtils.MGet("combo.RSlider") then
                    if spells.R:CastOnHitChance(rTarget, OriUtils.MGet("hcNew.R") / 100) then
                        return
                    end
                end
            end

        end
    end
end

function combatVariants.Harass()
    if OriUtils.CanCastSpell(slots.Q, "harass.useQ") then
        if Orbwalker.IsWindingUp() then
            return
        else
            local qTarget = spells.Q:GetTarget()
            if qTarget then
                if spells.Q:CastOnHitChance(qTarget, OriUtils.MGet("hcNew.Q") / 100) then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "harass.useW") then
        if Orbwalker.IsWindingUp() then
            return
        else
            local wTarget = spells.W:GetTarget()
            if wTarget then
                if spells.W:Cast() then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "harass.useE") then
        if Orbwalker.IsWindingUp() then
            return
        else
            local eTarget = spells.E:GetTarget()
            if eTarget then
                if spells.E:CastOnHitChance(eTarget, OriUtils.MGet("hcNew.E") / 100) then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.R, "harass.useR") then
        if Orbwalker.IsWindingUp() then
            return
        else
            local rTarget = spells.R:GetTarget()
            local AARange = Orbwalker.GetTrueAutoAttackRange(Player)
            local AABase = TS:GetTarget(AARange, false)
            if rTarget then
                if AABase then
                    return
                elseif Player.ManaPercent * 100 >= OriUtils.MGet("harass.RManaSlider") then
                    if KogMaw.ArtilleryStacks() < OriUtils.MGet("harass.RSlider") then
                        if spells.R:CastOnHitChance(rTarget, OriUtils.MGet("hcNew.R") / 100) then
                            return
                        end
                    end
                end
            end
        end
    end
end

function combatVariants.Waveclear()
    if OriUtils.CanCastSpell(slots.Q, "jglclear.useQ") then
        local jglminionsQ = ObjManager.GetNearby("neutral", "minions")
        for iJGLQ, objJGLQ in ipairs(jglminionsQ) do
            if OriUtils.IsValidTarget(objJGLQ, spells.Q.Range) then
                if spells.Q:Cast(objJGLQ) then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "jglclear.useW") then
        local jglminionsW = ObjManager.GetNearby("neutral", "minions")
        for iJGLW, objJGLW in ipairs(jglminionsW) do
            if OriUtils.IsValidTarget(objJGLW, spells.W.Range) then
                if spells.W:Cast() then
                    return
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
        local bestPos, numberOfHits = Geometry.BestCoveringRectangle(minionsPositions, Player.Position, spells.E.Radius * 2) 
        if numberOfHits >= 1 and Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.EManaSlider") then
            if spells.E:Cast(bestPos) then
                return
            end
        end
    end

    if OriUtils.CanCastSpell(slots.R, "jglclear.useR") then
        local jglminionsR = ObjManager.GetNearby("neutral", "minions")
        local minionsPositions = {}

        for iJGLR, objJGLR in ipairs(jglminionsR) do
            local minion = objJGLR.AsMinion
            if OriUtils.IsValidTarget(objJGLR, 900) then
                insert(minionsPositions, minion.Position)
            end
        end
        local bestPos, numberOfHits = Geometry.BestCoveringCircle(minionsPositions, spells.R.Radius) 
        if numberOfHits >= 1 and Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.RManaSlider") then
            if KogMaw.ArtilleryStacks() < OriUtils.MGet("jglclear.RSlider") then
                if spells.R:Cast(bestPos) then
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
                if spells.Q:CastOnHitChance(qTarget, OriUtils.MGet("hcNew.Q") / 100) then
                    return
                end
            end
        end
    end

    if OriUtils.MGet("clear.enemiesAround") and TS:GetTarget(1800) then
        return
    end
    
    if spells.E:IsReady() and OriUtils.MGet("clear.useE") then
        local minionsInERange = ObjManager.GetNearby("enemy", "minions")
        local minionsPositions = {}

        for _, minion in ipairs(minionsInERange) do
            if spells.E:IsInRange(minion) then
                insert(minionsPositions, minion.Position)
            end
        end

        local bestPos, numberOfHits = Geometry.BestCoveringRectangle(minionsPositions, Player.Position, spells.E.Radius * 2) 
        if numberOfHits >= OriUtils.MGet("clear.wMinions") then
            if Player.ManaPercent * 100 >= OriUtils.MGet("clear.EManaSlider") then
                if spells.E:Cast(bestPos) then
                    return
                end
            end
        end
    end
    if spells.R:IsReady() and OriUtils.MGet("clear.useR") then
        local minionsInRRange = ObjManager.GetNearby("enemy", "minions")
        local minionsPositions = {}
        for _, minion in ipairs(minionsInRRange) do
            insert(minionsPositions, minion.Position)
        end
        local bestPos, numberOfHits = Geometry.BestCoveringCircle(minionsPositions, spells.R.Radius) 
        if numberOfHits >= OriUtils.MGet("clear.rMinions") then
            if KogMaw.ArtilleryStacks() < OriUtils.MGet("clear.RSlider") then
                if Player.ManaPercent * 100 >= OriUtils.MGet("clear.RManaSlider") then
                    if spells.R:Cast(bestPos) then
                        return
                    end
                end
            end
        end
    end
end

function combatVariants.Lasthit()
end

function combatVariants.Flee()
    if OriUtils.MGet("misc.fleeE") then
        local eTarget = spells.E:GetTarget()
        if eTarget then
            if spells.E:CastOnHitChance(eTarget, Enums.HitChance.Low) then
                return
            end
        end
    end
end

function events.OnTick()
    KogMaw.UpdateWRange()
    KogMaw.UpdateRRange()

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

    KogMaw.BaronSteal()
    KogMaw.DrakeSteal()
    KogMaw.forceR()
    KogMaw.KS()
    --KogMaw.KSR()
    --KogMaw.KSQ()
end

function events.OnDraw()
    if Player.IsDead then
        return
    end

    if OriUtils.MGet("drawMenu.wPassiveTimer") then
        KogMaw.wTime()
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
end

function KogMaw.RegisterEvents()
    for eventName, eventId in pairs(Enums.Events) do
        if events[eventName] then
            EventManager.RegisterCallback(eventId, events[eventName])
        end
    end
end

function KogMaw.InitMenu()
    local function QHeader()
        Menu.ColoredText(drawData[1].displayText, scriptColor, true)
    end
    local function QHeaderHit()
        Menu.ColoredText(drawData[1].displayText .. " Hitchance", scriptColor, true)
    end

    local function WHeader()
        Menu.ColoredText(drawData[2].displayText, scriptColor, true)
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

    local function KogMawMenu()
        Menu.Text("" .. ASCIIArt, true)
        Menu.Text("" .. ASCIIArt2, true)
        Menu.Text("" .. ASCIIArt3, true)
        Menu.Text("" .. ASCIIArt4, true)
        Menu.Text("" .. ASCIIArt5, true)
        Menu.Text("" .. ASCIIArt6, true)
        Menu.Text("" .. ASCIIArt7, true)
        Menu.Text("" .. ASCIIArt8, true)
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
            Menu.ColoredText("This script is in an early stage , which means you'll have to redownload the final version once it's done!", 0xFFFF00FF, true)
            Menu.ColoredText("Please keep in mind, that you might encounter bugs/issues.", 0xFFFF00FF, true)
            Menu.ColoredText("If you find any, please contact " .. scriptCreator .. " via robur.lol", 0xFF0000FF, true)
        end
        
        if Menu.Checkbox("KogMaw.Updates130", "Don't show updates") == false then
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. scriptLastUpdated .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesVersion, 0XFFFF00FF, true)
            Menu.Text("- Fixed Minion validity for Baron KS", true)
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. patchNotesPrevUpdate .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesPreVersion, 0XFFFF00FF, true)
            Menu.Text("- Adjusted Hitchance for new Prediction", true)
        end

        Menu.Separator()

        Menu.NewTree("KogMaw.comboMenu", "Combo Settings", function()
            Menu.ColumnLayout("KogMaw.comboMenu.QE", "KogMaw.comboMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("KogMaw.combo.useQ", "Enable Q", true)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("KogMaw.combo.useE", "Enable E", true)
            end)

            Menu.ColumnLayout("KogMaw.comboMenu.WR", "KogMaw.comboMenu.WR", 2, true, function()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("KogMaw.combo.useW", "Enable W", true)
                Menu.NextColumn()
                RHeader()
                Menu.Checkbox("KogMaw.combo.useR", "Enable R", true)
                Menu.Slider("KogMaw.combo.RManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Slider("KogMaw.combo.RSlider", "Use R X times", 3, 1, 10)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("KogMaw.AdvancedRMenu", "Advanced R Settings (Don't change, unless experienced)", function()
            Menu.ColumnLayout("KogMaw.AdvancedRMenu.R1", "KogMaw.AdvancedRMenu.R1", 1, true, function()
                Menu.ColoredText("Don't use, if AA above", 0x3C9BF0FF, true)
                Menu.Slider("KogMaw.AdvancedR.AASpeed", "Speed", 2.15, 0.1, 4, 0.01)
            Menu.Separator()
                Menu.ColoredText("Use R inside AA Range, if AA Speed below and AD or Level below", 0x3C9BF0FF, true)
                Menu.Slider("KogMaw.AdvancedR.AASpeed2", "Speed", 2.15, 0.1, 4, 0.01)
                Menu.Slider("KogMaw.AdvancedR.AD", "AD", 200, 61, 560, 1)
                Menu.Slider("KogMaw.AdvancedR.Level", "Level", 9, 1, 18, 1)
            Menu.Separator()
                Menu.ColoredText("Use R inside AA Range, if Target below and AA Speed below and AD OR Level above", 0x3C9BF0FF, true)
                Menu.Slider("KogMaw.AdvancedR.TargetHP", "% HP", 40, 1, 100, 1)
                Menu.Slider("KogMaw.AdvancedR.AASpeed3", "Speed", 2.15, 0.1, 4, 0.01)
                Menu.Slider("KogMaw.AdvancedR.AD2", "AD", 200, 61, 560, 1)
                Menu.Slider("KogMaw.AdvancedR.Level2", "Level", 9, 1, 18, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("KogMaw.harassMenu", "Harass Settings", function()
            Menu.ColumnLayout("KogMaw.harassMenu.QE", "KogMaw.harassMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("KogMaw.harass.useQ", "Enable Q", true)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("KogMaw.harass.useE", "Enable E", false)
            end)
            Menu.ColumnLayout("KogMaw.harass.WR", "KogMaw.harassMenu.WR", 2, true, function()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("KogMaw.harass.useW", "Enable W", true)
                Menu.NextColumn()
                RHeader()
                Menu.Checkbox("KogMaw.harass.useR", "Enable R", true)
                Menu.Slider("KogMaw.harass.RManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Slider("KogMaw.harass.RSlider", "Use R X times", 4, 1, 10)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("KogMaw.clearMenu", "Clear Settings", function()
            Menu.NewTree("KogMaw.jglMenu", "Jungleclear", function()
                Menu.Checkbox("KogMaw.jglclear.useQ", "Use Q", true)
                Menu.Checkbox("KogMaw.jglclear.useW", "Use W", true)
                Menu.Checkbox("KogMaw.jglclear.useE", "Use E", true)
                Menu.Slider("KogMaw.jglclear.EManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Checkbox("KogMaw.jglclear.useR", "Use R", false)
                Menu.Slider("KogMaw.jglclear.RManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Slider("KogMaw.jglclear.RSlider", "Use Max X Stacks", 2, 1, 10)
            end)
            Menu.NewTree("KogMaw.waveMenu", "Waveclear", function()
                Menu.Checkbox("KogMaw.clear.enemiesAround", "Don't clear while enemies around", true)
                Menu.Separator()
                Menu.Checkbox("KogMaw.clear.pokeQ", "Enable Q Poke on Enemy", true)
                Menu.Checkbox("KogMaw.clear.useE", "Enable E", false)
                Menu.Slider("KogMaw.clear.wMinions", "if X Minions", 5, 1, 6, 1)
                Menu.Slider("KogMaw.clear.EManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Checkbox("KogMaw.clear.useR", "Enable R", true)
                Menu.Slider("KogMaw.clear.rMinions", "if X Minions", 4, 1, 6, 1)
                Menu.Slider("KogMaw.clear.RManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Slider("KogMaw.clear.RSlider", "Use Max X Stacks", 2, 1, 10)
            end)
        end)

        Menu.Separator()

        Menu.NewTree("KogMaw.stealMenu", "Steal Settings", function()
            Menu.NewTree("KogMaw.ksMenu", "Killsteal", function()
                Menu.Checkbox("KogMaw.ks.useQ", "Killsteal with Q", true)
                local cbResult = OriUtils.MGet("ks.useQ")
                if cbResult then
                    Menu.Indent(function()
                        Menu.NewTree("KogMaw.ksMenu.qWhitelist", "KS Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("KogMaw.ks.qWL." .. heroName, "Q KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("KogMaw.ks.useR", "Killsteal with R", false)
                local cbResult3 = OriUtils.MGet("ks.useR")
                if cbResult3 then
                    Menu.Indent(function()
                        Menu.NewTree("KogMaw.ksMenu.rWhitelist", "KS R Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("KogMaw.ks.rWL." .. heroName, "R KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
            end)
            Menu.NewTree("KogMaw.jglstealMenu", "Junglesteal (Drake/Baron) | BETA", function()
                Menu.Checkbox("KogMaw.steal.useQ", "Junglesteal with Q", true)
                Menu.Checkbox("KogMaw.steal.useE", "Junglesteal with E", true)
                Menu.Checkbox("KogMaw.steal.useR", "Junglesteal with R", false)
            end)
        end)
        
        Menu.Separator()

        Menu.NewTree("KogMaw.miscMenu", "Misc Settings", function()
            Menu.ColumnLayout("KogMaw.miscMenu.R", "KogMaw.miscMenu.R", 2, true, function()
                Menu.Text("")
                RHeader()
                Menu.Keybind("KogMaw.misc.forceR", "Force R", string.byte("T"), false, false, true)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("KogMaw.misc.fleeE", "Use E during fleee", true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("KogMaw.hcMenu", "Hitchance Settings", function()
            Menu.ColumnLayout("KogMaw.hcMenu.QE", "KogMaw.hcMenu.QE", 2, true, function()
                Menu.Text("")
                QHeaderHit()
                Menu.Text("")
                Menu.Slider("KogMaw.hcNew.Q", "%", 40, 1, 100, 1)
                Menu.NextColumn()
                Menu.Text("")
                EHeaderHit()
                Menu.Text("")
                Menu.Slider("KogMaw.hcNew.E", "%", 40, 1, 100, 1)
            end)
            Menu.ColumnLayout("KogMaw.hcMenu.WR", "KogMaw.hcMenu.WR", 1, true, function()
                Menu.Text("")
                RHeaderHit()
                Menu.Text("")
                Menu.Slider("KogMaw.hcNew.R", "%", 35, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("KogMaw.drawMenu", "Draw Settings", function()
            OriUtils.AddDrawMenu(drawData)
        end)
    end

    Menu.RegisterMenu(scriptName, scriptName, KogMawMenu)
end

function OnLoad()
    KogMaw.InitMenu()
    
    KogMaw.RegisterEvents()
    return true
end
