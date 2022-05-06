if Player.CharName ~= "Amumu" then return end


local scriptName = "AuAmumu"
local scriptCreator = "AURUM"
local credits = "Orietto"
local patchNotesPrevUpdate = "11/19/2021"
local patchNotesPreVersion = "1.1.0"
local patchNotesVersion, scriptVersionUpdater = "1.1.5", "1.1.5"
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
local huge, pow, min, max, floor = math.huge, math.pow, math.min, math.max, math.floor

local SDK = _G.CoreEx

SDK.AutoUpdate("https://raw.githubusercontent.com/roburAURUM/robur-AuEdition/main/AuAmumu.lua", scriptVersionUpdater)

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
        Base = {70, 95, 120, 145, 170},
        TotalAP = 0.85,
        Type = dmgTypes.Magicalm,
    },
    W = {
        Base = {12, 16, 20, 24, 28},
        TotalAP  = 0.005,
        Type = dmgTypes.Magical
    },
    E = {
        Base = {75, 100, 125, 150, 175},
        TotalAP  = 0.5,
        Type = dmgTypes.Magical
    },
    R = {
        Base = {100, 150, 200},
        TotalAP = 0.8,
        Type = dmgTypes.Magical
    }
}

local spells = {
    Q = Spell.Skillshot({
        Slot = slots.Q,
        Delay = 0.25,
        Speed = 2000,
        Range = 1080,
        Radius = 160 / 2,
        Type = "Linear",
        Collisions = {Heroes = true, Minions = true, Windwall = true, Wall = false}
    }),
    W = Spell.Active({
        Slot = slots.W,
        Delay = 0.0,
        Range = 320,
    }),
    E = Spell.Active({
        Slot = slots.E,
        Delay = 0.25,
        Range = 350,
        Radius = 350,
    }),
    R = Spell.Active({
        Slot = slots.R,
        Delay = 0.25,
        Range = 480,
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

function OriUtils.CheckCastTimers(data)
    local curTime = Game.GetTime()

    for slot, Amumuold in pairs(data) do
        if curTime < lastCastT[slot] + Amumuold then
            return false
        end
    end

    return true
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

    Menu.Checkbox(cacheName .. ".draw." .. "comboDamage", "Draw combo damage on healthbar", false)
    Menu.Checkbox("Amumu.drawMenu.AlwaysDraw", "Always show Drawings", false)
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

local drawData = {
    {slot = slots.Q, id = "Q", displayText = "[Q] Bandage Toss", range = spells.Q.Range},
    {slot = slots.W, id = "W", displayText = "[W] Despair", range = spells.W.Range},
    {slot = slots.E, id = "E", displayText = "[E] Tantrum", range = spells.E.Range},
    {slot = slots.R, id = "R", displayText = "[R] Curse of the Sad Mummy", range = spells.R.Range}
}


local ASCIIArt = "      /\\            /\\                                     "
local ASCIIArt2 = "     /  \\  _   _   /  \\   _ __ ___  _   _ _ __ ___  _   _  "
local ASCIIArt3 = "    / /\\ \\| | | | / /\\ \\ | '_ ` _ \\| | | | '_ ` _ \\| | | | "
local ASCIIArt4 = "   / ____ \\ |_| |/ ____ \\| | | | | | |_| | | | | | | |_| | "
local ASCIIArt5 = "  /_/    \\_\\__,_/_/    \\_\\_| |_| |_|\\__,_|_| |_| |_|\\__,_| "


local Amumu = {}

local slotToDamageTable = {
    [slots.Q] = damages.Q,
    [slots.W] = damages.Q,
    [slots.E] = damages.E,
    [slots.R] = damages.R
}

---@param target AIBaseClient
---@param slot slut
function Amumu.GetDamage(target, slot)
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
        damageToDeal = damageToDeal + Amumu.GetDamage(target, slots.Q)
    end

    if spells.W:IsReady() and OriUtils.MGet("combo.useW") then
        damageToDeal = damageToDeal + Amumu.GetDamage(target, slots.W)
    end

    if spells.E:IsReady() and OriUtils.MGet("combo.useE") then
        damageToDeal = damageToDeal + Amumu.GetDamage(target, slots.E)
    end
    if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
        damageToDeal = damageToDeal + Amumu.GetDamage(target, slots.R)
    end

    insert(dmgList, damageToDeal)
end

function Amumu.WEnabled()
    return Player:GetBuff("AuraofDespair")
end

function Amumu.BigDickOriettoEnergy(minionTable, range)
    for _, minion in ipairs(minionTable) do
        if OriUtils.IsValidTarget(minion, range) then
            return true
        end
    end

    return false
end

function Amumu.AutoR()
    if OriUtils.CanCastSpell(slots.R,"misc.AutoR") then
        if Amumu.rCases() >= OriUtils.MGet("misc.AutoRSlider") then
            if spells.R:Cast() then
                return
            end
        end
    end
end

function Amumu.forceR()
    if OriUtils.CanCastSpell(slots.R,"misc.forceR") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(nil), false)
        if Amumu.rCases() >= OriUtils.MGet("misc.forceRSlider") then
            if spells.R:Cast() then
                return
            end
        end
    end
end

function Amumu.flashR()
    if OriUtils.CanCastSpell(slots.R, "misc.flashR") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)

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
                Delay = 0.25,
                Speed = huge,
                Range = 550,
                Radius = 550,
                Type = "Circular",
            }
            local pred = Prediction.GetPredictedPosition(rFlashTarget, spellInput, flashPos)
            if pred and pred.HitChanceEnum >= Enums.HitChance.Medium then

                if OriUtils.MGet("misc.flashR.options") == 0 then
                    if spells.R:Cast() then
                        delay(52, function() Input.Cast(spells.Flash.Slot, flashPos) end)
                        return
                    end
                else
                    if Input.Cast(spells.Flash.Slot, flashPos) then
                        delay(100, function()spells.R:Cast() end)
                        return
                    end
                end
            end
        end
    end
end

function Amumu.EFarm()
    if spells.E:IsReady() and OriUtils.MGet("clear.useE") then
        local count = 0

        local enemyMinions = ObjManager.GetNearby("enemy", "minions")
        for iE, objE in ipairs(enemyMinions) do
            local minion = objE.AsMinion

            if OriUtils.IsValidTarget(minion, spells.E.Range) then
                count = count + 1
            end        
        end

        return count
    end
end

function Amumu.rCases()
    local count = 0

    local enemyHeroes = ObjManager.GetNearby("enemy", "heroes")
    for index, obj in ipairs(enemyHeroes) do
        local hero = obj.AsHero

        if OriUtils.IsValidTarget(hero, spells.R.Range) then
            count = count + 1
        end        
    end

    return count
end


function Amumu.KS()
    if OriUtils.MGet("ks.useQ") or OriUtils.MGet("ks.useE") or  OriUtils.MGet("ks.useR") then
        local allyHeroes = ObjManager.GetNearby("ally", "heroes")
        for iKSA, objKSA in ipairs(allyHeroes) do
            local ally = objKSA.AsHero
            if not ally.IsMe and not ally.IsDead then
            local nearbyEnemiesKS = ObjManager.GetNearby("enemy", "heroes")
                for iKS, objKS in ipairs(nearbyEnemiesKS) do
                    local enemyHero = objKS.AsHero
                    local qDamage = Amumu.GetDamage(enemyHero, slots.Q)
                    local healthPredQ = spells.Q:GetHealthPred(objKS)
                    local eDamage = Amumu.GetDamage(enemyHero, slots.E)
                    local healthPredE = spells.E:GetHealthPred(objKS)
                    local rDamage = Amumu.GetDamage(enemyHero, slots.R)
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
                        if OriUtils.CanCastSpell(slots.E, "ks.useE") and spells.E:IsInRange(objKS) then
                            if OriUtils.MGet("ks.eWL." .. enemyHero.CharName, true) then
                                if healthPredE > 0 and healthPredE < floor(eDamage - 50) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.E:Cast() then
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
                                        if spells.R:Cast() then
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

function Amumu.DrakeSteal()
    if OriUtils.MGet("steal.useQ") or OriUtils.MGet("steal.useE") or  OriUtils.MGet("steal.useR") then 
        local enemiesAround = ObjManager.GetNearby("enemy", "heroes")
        for iSteal, objSteal in ipairs(enemiesAround) do
            local enemy = objSteal.AsHero
            if not enemy.IsDead then
                local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
                for iM, minion in ipairs(nearbyMinions) do
                    local minion = minion.AsMinion
                    local qDamage = Amumu.GetDamage(minion, slots.Q)
                    local healthPredDrakeQ = spells.Q:GetHealthPred(minion)
                    local eDamage = Amumu.GetDamage(minion, slots.E)
                    local healthPredDrakeE = spells.E:GetHealthPred(minion)
                    local rDamage = Amumu.GetDamage(minion, slots.R)
                    local healthPredDrakeR = spells.R:GetHealthPred(minion)
                    if not minion.IsDead and minion.IsDragon and minion:Distance(enemy) < 1800 or enemy.IsInDragonPit then
                        if OriUtils.CanCastSpell(slots.Q, "steal.useQ") and spells.Q:IsInRange(minion) then
                            if healthPredDrakeQ > 0 and healthPredDrakeQ < floor(qDamage) then
                                if spells.Q:Cast(minion) then
                                    return
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.E, "steal.useE") and spells.E:IsInRange(minion)then
                            if healthPredDrakeE > 0 and healthPredDrakeE < floor(eDamage) then
                                if spells.E:Cast() then
                                    return
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.R, "steal.useR") and spells.R:IsInRange(minion)then
                            if healthPredDrakeR > 0 and healthPredDrakeR < floor(rDamage) then
                                if spells.R:Cast() then
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

function Amumu.BaronSteal()
    if OriUtils.MGet("steal.useQ") or OriUtils.MGet("steal.useE") or  OriUtils.MGet("steal.useR") then 
        local enemiesAround = ObjManager.GetNearby("enemy", "heroes")
        for iSteal2, objSteal2 in ipairs(enemiesAround) do
            local enemy = objSteal2.AsHero
            if not enemy.IsDead then
                local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
                for iM2, minion in ipairs(nearbyMinions) do
                    local minion = minion.AsMinion
                    local qDamage = Amumu.GetDamage(minion, slots.Q)
                    local healthPredBaronQ = spells.Q:GetHealthPred(minion)
                    local eDamage = Amumu.GetDamage(minion, slots.E)
                    local healthPredBaronE = spells.E:GetHealthPred(minion)
                    local rDamage = Amumu.GetDamage(minion, slots.R)
                    local healthPredBaronR = spells.R:GetHealthPred(minion)
                    if not minion.IsDead and minion.IsBaron and minion:Distance(enemy) < 1800 or enemy.IsInBaronPit then
                        if OriUtils.CanCastSpell(slots.Q, "steal.useQ") and spells.Q:IsInRange(minion) then
                            if healthPredBaronQ > 0 and healthPredBaronQ < floor(qDamage) then
                                if spells.Q:Cast(minion) then
                                    return
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.E, "steal.useE") and spells.E:IsInRange(minion)then
                            if healthPredBaronE > 0 and healthPredBaronE < floor(eDamage) then
                                if spells.E:Cast() then
                                    return
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.R, "steal.useR") and spells.R:IsInRange(minion)then
                            if healthPredBaronR > 0 and healthPredBaronR < floor(rDamage) then
                                if spells.R:Cast() then
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

function combatVariants.Combo()
    if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
        if Amumu.rCases() >= OriUtils.MGet("combo.useR.minEnemies") then
            if spells.R:Cast() then
                return
            end
        end        
    end
    
    local qTarget = spells.Q:GetTarget()
    if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
        
        if qTarget then
            if spells.Q:CastOnHitChance(qTarget, OriUtils.MGet("hc.Q") / 100) then
                return
            end
        end
    end

    if spells.W:IsReady() and OriUtils.MGet("combo.useW") then
        local wTarget = spells.W:GetTarget()
        if wTarget and not Amumu.WEnabled() then
            if spells.W:Cast() then
                return
            end
        end
        local qTarget2 = spells.Q.Range / 2
        local wTarget2 = TS:GetTarget(qTarget2)
        if not wTarget2 and Amumu.WEnabled() and OriUtils.MGet("combo.disableW") then
            if spells.W:Cast() then
                return
            end
        end
    end

    if spells.E:IsReady() and OriUtils.MGet("combo.useE") then
        local eTarget = spells.E:GetTarget()
        if eTarget then
            if spells.E:Cast() then
                return
            end
        end
    end
end


function combatVariants.Harass()
    if spells.W:IsReady() and OriUtils.MGet("harass.useW") then
        local wTarget = spells.W:GetTarget()
        if wTarget and not Amumu.WEnabled() then
            if spells.W:Cast() then
                return
            end
        end
        local qTarget2 = spells.Q.Range / 2
        local wTarget2 = TS:GetTarget(qTarget2)
        if not wTarget2 and Amumu.WEnabled() and OriUtils.MGet("combo.disableW") then
            if spells.W:Cast() then
                return
            end
        end
    end

    if spells.E:IsReady() and OriUtils.MGet("harass.useE") then
        local eTarget = spells.E:GetTarget()
        if eTarget then
            if spells.E:Cast() then
                return
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

        if Amumu.BigDickOriettoEnergy(jglminionsW, spells.W.Range + 280) then
            if not Amumu.WEnabled() then
                if spells.W:Cast() then
                    return
                end
            end
        else
            if Amumu.WEnabled() then
                if spells.W:Cast() then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "jglclear.useE") then
        local jglminionsE = ObjManager.GetNearby("neutral", "minions")

        for iJGLE, objJGLE in ipairs(jglminionsE) do
            if OriUtils.IsValidTarget(objJGLE, spells.E.Range) then
                if spells.E:Cast() then
                    return
                end
            end
        end
    end

    if OriUtils.MGet("clear.enemiesAround") and TS:GetTarget(1800) then
        return

    else 
        if OriUtils.CanCastSpell(slots.Q, "clear.useQ") then
            local qMinions = ObjManager.GetNearby("enemy", "minions")
            for iQ, objQ in ipairs(qMinions) do
                local minion = objQ.AsMinion
                if OriUtils.MGet("clear.useQCanon") then
                    if minion.IsSiegeMinion and not minion.IsDead then
                         if spells.Q:Cast(objQ) then
                            return
                        end
                    end
                else 
                    if not minion.IsDead then
                        if spells.Q:Cast(objQ) then
                            return
                        end
                    end
                end
            end
        end
        if OriUtils.CanCastSpell(slots.E, "clear.useE") then
            if Amumu.EFarm() >= OriUtils.MGet("clear.eMinions") then
                if Player.ManaPercent * 100 >= OriUtils.MGet("clear.eManaSlider") then
                    if spells.E:Cast() then
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
end

function events.OnTick()
    Amumu.KS()
    Amumu.DrakeSteal()
    Amumu.BaronSteal()
    OriUtils.CheckFlashSlot()

    -- Start by defining the ShouldRunLogic for the OnTick
    if not OriUtils.ShouldRunLogic() then
        return
    end
    -- Get State of Orbwaler by Orbwalker.GetMode()
    local OrbwalkerState = Orbwalker.GetMode()
    -- Check OrbwalkerState (Combo,Harass,Flee,Waveclear,Lasthit) and apply combatVariants Logic
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
    
    Amumu.AutoR()
    Amumu.flashR()
    Amumu.forceR()
    
end

---@param source GameObject
---@param dashInstance DashInstance
function events.OnGapclose(source, dashInstance)
    if source.IsHero and source.IsEnemy then
        if spells.Q:IsReady() and OriUtils.MGet("gapclose.Q") then
            local pred = spells.Q:GetPrediction(source)
            if OriUtils.MGet("gapclose.qWL." .. source.CharName, true) then
                if pred and pred.HitChanceEnum >= Enums.HitChance.Dashing then
                    if spells.Q:Cast(pred.CastPosition) then
                        return
                    end
                end
            end
        end
    end
end


---@param source GameObject
function events.OnInterruptibleSpell(source, spellCast, danger, endTime, canMoveDuringChannel)
    if source.IsHero and source.IsEnemy then
        if spells.Q:IsReady() and OriUtils.MGet("interrupt.Q") then
            if danger < 5 then
                if OriUtils.MGet("interrupt.qWL." .. source.CharName, true) then
                    local pred = spells.Q:GetPrediction(source)
                    if pred and pred.HitChanceEnum >= Enums.HitChance.Medium then
                        if spells.Q:Cast(pred.CastPosition) then
                            return
                        end
                    end
                end
            end
        end
            
        if spells.R:IsReady() and OriUtils.MGet("interrupt.R") then
            if OriUtils.MGet("interrupt.rWL." .. source.CharName, true) then
                if danger >= 5 and spells.R:IsInRange(source) then
                    if spells.R:Cast() then
                        return
                    end
                end
            end
        end
    end
end

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
end

function Amumu.RegisterEvents()
    for eventName, eventId in pairs(Enums.Events) do
        if events[eventName] then
            EventManager.RegisterCallback(eventId, events[eventName])
        end
    end
end

function Amumu.InitMenu()
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

    local function RHeader()
        Menu.ColoredText(drawData[4].displayText, scriptColor, true)
    end

    local function AmumuMenu()
        Menu.Text("" .. ASCIIArt, true)
        Menu.Text("" .. ASCIIArt2, true)
        Menu.Text("" .. ASCIIArt3, true)
        Menu.Text("" .. ASCIIArt4, true)
        Menu.Text("" .. ASCIIArt5, true)
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
        
        if Menu.Checkbox("Amumu.Updates115", "Don't show updates") == false then
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. scriptLastUpdated .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesVersion, 0XFFFF00FF, true)
            Menu.Text("- Adjusted Hitchance for new Prediction", true)
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. patchNotesPrevUpdate .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesPreVersion, 0XFFFF00FF, true)
            Menu.Text("- Fixed KS with Q E R", true)
            Menu.Text("- Uploaded correct version with Gapclose/Interrupt (incl. Whitelist)", true)
            Menu.Text("- Added AutoR on X Enemies (Default 4) as requested", true)
        end

        Menu.Separator()

        Menu.NewTree("Amumu.comboMenu", "Combo Settings", function()
            Menu.ColumnLayout("Amumu.comboMenu.QE", "Amumu.comboMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Amumu.combo.useQ", "Enable Q", true)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Amumu.combo.useE", "Enable E", true)
            end)

            Menu.ColumnLayout("Amumu.comboMenu.WR", "Amumu.comboMenu.WR", 2, true, function()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Amumu.combo.useW", "Enable W", true)
                Menu.Checkbox("Amumu.combo.disableW", "Automatically disable W, if enemy is not in Range", true)
                Menu.NextColumn()
                RHeader()
                Menu.Checkbox("Amumu.combo.useR", "Enable R", true)
                Menu.Slider("Amumu.combo.useR.minEnemies", "Min Enemies", 3, 1, 5, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Amumu.harassMenu", "Harass Settings", function()
            Menu.ColumnLayout("Amumu.harassMenu.QE", "Amumu.harassMenu.QE", 2, true, function()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Amumu.harass.useW", "Enable W", false)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Amumu.harass.useE", "Enable E", true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Amumu.clearMenu", "Clear Settings", function()
            Menu.NewTree("Amumu.jglMenu", "Jungleclear", function()
                Menu.Checkbox("Amumu.jglclear.useQ", "Use Q", true)
                Menu.Checkbox("Amumu.jglclear.useW", "Use W", true)
                Menu.Checkbox("Amumu.jglclear.useE", "Use E", true)
            end)
            Menu.NewTree("Amumu.waveMenu", "Waveclear", function()
                Menu.Checkbox("Amumu.clear.enemiesAround", "Don't clear while enemies around", true)
                Menu.Checkbox("Amumu.clear.useQ", "Use Q", true)
                Menu.Checkbox("Amumu.clear.useQCanon", "Use Q only on Canon", true)
                Menu.Checkbox("Amumu.clear.useE", "Use E", true)
                Menu.Slider("Amumu.clear.eMinions", "if X Minions", 5, 1, 6, 1)
                Menu.Slider("Amumu.clear.eManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)

            end)
        end)
        Menu.Separator()

        Menu.NewTree("Amumu.stealMenu", "Steal Settings", function()
            Menu.NewTree("Amumu.ksMenu", "Killsteal", function()
                Menu.Checkbox("Amumu.ks.useQ", "Killsteal with Q", true)
                local cbResult = OriUtils.MGet("ks.useQ")
                if cbResult then
                    Menu.Indent(function()
                        Menu.NewTree("Amumu.ksMenu.qWhitelist", "KS Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Amumu.ks.qWL." .. heroName, "Q KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Amumu.ks.useE", "Killsteal with E", true)
                local cbResult2 = OriUtils.MGet("ks.useE")
                if cbResult2 then
                    Menu.Indent(function()
                        Menu.NewTree("Amumu.ksMenu.wWhitelist", "KS E Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Amumu.ks.eWL." .. heroName, "E KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Amumu.ks.useR", "Killsteal with R", false)
                local cbResult3 = OriUtils.MGet("ks.useR")
                if cbResult3 then
                    Menu.Indent(function()
                        Menu.NewTree("Amumu.ksMenu.rWhitelist", "KS R Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Amumu.ks.rWL." .. heroName, "R KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
            end)
            Menu.NewTree("Amumu.jglstealMenu", "Junglesteal (Drake/Baron) | BETA", function()
                Menu.Checkbox("Amumu.steal.useQ", "Junglesteal with Q", true)
                Menu.Checkbox("Amumu.steal.useE", "Junglesteal with E", true)
                Menu.Checkbox("Amumu.steal.useR", "Junglesteal with R", false)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Amumu.miscMenu", "Misc Settings", function()
            Menu.ColumnLayout("Amumu.miscMenu.R", "Amumu.miscMenu.R", 2, true, function()
                Menu.Text("")
                RHeader()
                Menu.Keybind("Amumu.misc.forceR", "Force R", string.byte("T"), false, false, true)
                Menu.Slider("Amumu.misc.forceRSlider", "Force R if it can hit >=", 1, 1, 5, 1)
                Menu.NextColumn()
                Menu.Text("")
                RHeader()
                Menu.Keybind("Amumu.misc.flashR", "Flash R", string.byte("G"), false, false, true)
                Menu.Dropdown("Amumu.misc.flashR.options", "Mode", 1, {"R > Flash (Experimental)", "Flash > R (Slower)"})
                --Menu.Checkbox("Amumu.misc.flashR.Inside", "Flash Inside if hit > than combo", true)
            end)
            Menu.Separator()
            Menu.ColumnLayout("Amumu.miscMenu.gapclose", "Amumu.miscMenu.Q", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Amumu.gapclose.Q", "Gapclose with Q", true)
                local cbResult4 = OriUtils.MGet("gapclose.Q")
                if cbResult4 then
                    Menu.Indent(function()
                        Menu.NewTree("Amumu.miscMenu.gapcloseQ", "Gapclose Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Amumu.gapclose.qWL." .. heroName, "Use Q Gapclose on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.NextColumn()
                Menu.Text("")
                RHeader()
                Menu.Checkbox("Amumu.misc.AutoR", "Enable Auto R", true)
                Menu.Slider("Amumu.misc.AutoRSlider", "If can hit X Enmies", 4, 1, 5, 1)
            end)
            Menu.Separator()
            Menu.ColumnLayout("Amumu.miscMenu.interrupt", "Amumu.miscMenu2.Q", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Amumu.interrupt.Q", "Interrupt with Q", true)
                local cbResult4 = OriUtils.MGet("interrupt.Q")
                if cbResult4 then
                    Menu.Indent(function()
                        Menu.NewTree("Amumu.miscMenu.interruptQ", "Interrupt Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Amumu.interrupt.qWL." .. heroName, "Use Q Interrupt on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.NextColumn()
                Menu.Text("")
                RHeader()
                Menu.Checkbox("Amumu.interrupt.R", "Interrupt with R", true)
                local cbResult4 = OriUtils.MGet("interrupt.R")
                if cbResult4 then
                    Menu.Indent(function()
                        Menu.NewTree("Amumu.miscMenu.interruptR", "interrupt R Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Amumu.interrupt.rWL." .. heroName, "Use R interrupt on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Amumu.hcMenu", "Hitchance Settings", function()
            Menu.ColumnLayout("Amumu.hcMenu.QE", "Amumu.hcMenu.QE", 1, true, function()
                Menu.Text("")
                QHeaderHit()
                Menu.Slider("Amumu.hc.Q", "%", 45, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Amumu.drawMenu", "Draw Settings", function()
            OriUtils.AddDrawMenu(drawData)
        end)
    end

    Menu.RegisterMenu(scriptName, scriptName, AmumuMenu)
end

function OnLoad()
    Amumu.InitMenu()
    
    Amumu.RegisterEvents()
    return true
end