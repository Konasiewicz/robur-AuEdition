if Player.CharName ~= "Blitzcrank" then return end

local scriptName = "AuBlitzcrank"
local scriptCreator = "AURUM"
local credits = "Orietto"
local patchNotesPrevUpdate = "02/19/2022"
local patchNotesPreVersion = "1.3.0"
local patchNotesVersion, scriptVersionUpdater = "1.3.2", "1.3.2"
local scriptVersion = scriptVersionUpdater
local scriptLastUpdated = "03/24/2022"
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

SDK.AutoUpdate("https://raw.githubusercontent.com/roburAURUM/robur-AuEdition/main/AuBlitzcrank.lua", scriptVersionUpdater)

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
        Base = {90, 140, 190, 240, 290},
        TotalAP = 1.2,
        Type = dmgTypes.Magical
    },
    E = {
        Base = {},
        TotalAD  = 1.0,
        Type = dmgTypes.Physical
    },
    R = {
        Base = {250, 375, 500},
        TotalAP = 1.0,
        Type = dmgTypes.Magical
    }
}

local spells = {
    Q = Spell.Skillshot({
        Slot = slots.Q,
        Delay = 0.25,
        Speed = 1800,
        Range = 1075,
        Radius = 140 / 2,
        Collisions = {Windwall = true, Minions = true, Heroes = true},
        Type = "Linear",
    }),
    W = Spell.Active({
        Delay = 0.0,
        Slot = slots.W,
        Range = 1500,
    }),
    E = Spell.Active({
        Slot = slots.E,
        Delay = 0.0,
        Speed = huge,
        Range = Orbwalker.GetTrueAutoAttackRange(Player),
    }),
    R = Spell.Active({
        Slot = slots.R,
        Delay = 0.25,
        Speed = huge,
        Range = 600,
        Radius = 600,
        Type = "Circular",
    }),
    Flash = {
        Slot = nil,
        LastCastT = 0,
        LastCheckT = 0,
        Range = 400
    }
}

local lastCastT = {
    [slots.Q] = 0,
    [slots.W] = 0,
    [slots.E] = 0,
    [slots.R] = 0
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

    for slot, Blitzcrankold in pairs(data) do
        if curTime < lastCastT[slot] + Blitzcrankold then
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
    Menu.Checkbox("Blitzcrank.drawMenu.AlwaysDraw", "Always show Drawings", false)
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
    {slot = slots.Q, id = "Q", displayText = "[Q] Rocket Grab", range = function () return OriUtils.MGet("misc.QRange") end},
    {slot = slots.W, id = "W", displayText = "[W] Overdrive Min", range = function () return OriUtils.MGet("combo.useW.CloseRange") end},
    {slot = slots.W, id = "W2", displayText = "[W] Overdrive Max", range = function () return OriUtils.MGet("combo.useW.FarRange") end},
    {slot = slots.E, id = "E", displayText = "[E] Power Fist", range = spells.E.Range},
    {slot = slots.R, id = "R", displayText = "[R] Static Field", range = spells.R.Range}
}

local ASCIIArt = "                 ____  _ _ _                           _     "
local ASCIIArt2 = "      /\\        |  _ \\| (_) |                         | |    "
local ASCIIArt3 = "     /  \\  _   _| |_) | |_| |_ _______ _ __ __ _ _ __ | | __ "
local ASCIIArt4 = "    / /\\ \\| | | |  _ <| | | __|_  / __| '__/ _` | '_ \\| |/ / "
local ASCIIArt5 = "   / ____ \\ |_| | |_) | | | |_ / / (__| | | (_| | | | |   <  "
local ASCIIArt6 = "  /_/    \\_\\__,_|____/|_|_|\\__/___\\___|_|  \\__,_|_| |_|_|\\_\\ "

local Blitzcrank = {}

function Blitzcrank.RelicShield3()
    return Player:GetBuff("talentreaperstacksthree")
end

function Blitzcrank.RelicShield2()
    return Player:GetBuff("talentreaperstackstwo")
end

function Blitzcrank.RelicShield1()
    return Player:GetBuff("talentreaperstacksone")
end

local slotToDamageTable = {
    [slots.Q] = damages.Q,
    [slots.E] = damages.E,
    [slots.R] = damages.R
}

---@param target AIBaseClient
---@param slot slut
function Blitzcrank.GetDamage(target, slot)
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

            if data.TotalAD then
                rawDamage = rawDamage + (data.TotalAD * me.TotalAD)
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

function Blitzcrank.QSteal()
    if OriUtils.MGet("jglclear.buffSteal") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)
        if spells.Q:IsReady() then
            local jungleBuffs = ObjManager.GetNearby("neutral", "minions")
            local qHeroCheck = TS:GetTarget(1500)
            for i, minion in ipairs(jungleBuffs) do
                if OriUtils.IsValidTarget(minion, spells.Q.Range) then
                    local minion = minion.AsMinion
                    if minion.IsRedBuff or minion.IsBlueBuff then
                        if qHeroCheck then
                            local qDamage = Blitzcrank.GetDamage(minion, slots.Q)
                            local healthPredBuffQ = spells.Q:GetHealthPred(minion)
                            if healthPredBuffQ > 0 and healthPredBuffQ < floor(qDamage) then
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


function Blitzcrank.QGrab()
    local enemyBuffs = ObjManager.GetNearby("enemy", "heroes")
    
    for i, obj in ipairs(enemyBuffs) do
        return obj:GetBuff("rocketgrab2")
    end
end

function Blitzcrank.forceR()
    if OriUtils.MGet("misc.forceR") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)
        if spells.R:IsReady() then
            local rTarget = spells.R:GetTarget()
            if rTarget then
                if spells.R:Cast() then
                    return
                end
            end
        end
    end
end

function Blitzcrank.flashQ()
    if OriUtils.MGet("misc.flashQ") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)
        if spells.Q:IsReady() then
            local flashReady = spells.Flash.Slot and OriUtils.IsSpellReady(spells.Flash.Slot)
            if not flashReady then
                return
            end

            local qFlashRange = spells.Q.Range + spells.Flash.Range
            local qFlashTarget = TS:GetTarget(qFlashRange, false)
            if qFlashTarget and not spells.Q:IsInRange(qFlashTarget) then
                local flashPos = Player.ServerPos:Extended(qFlashTarget, spells.Flash.Range) 

                local spellInput = {
                    Slot = slots.Q,
                    Delay = 0.25,
                    Speed = 1800,
                    Range = 1075,
                    Radius = 200 / 2,
                    Collisions = {Windwall = true, Minions = true, Heroes = true},
                    Type = "Linear",
                }
                local pred = Prediction.GetPredictedPosition(qFlashTarget, spellInput, flashPos)
                if pred and pred.HitChanceEnum >= Enums.HitChance.High then
                    if Input.Cast(spells.Flash.Slot, flashPos) then
                        delay(80, function() spells.Q:Cast(pred.CastPosition) end)
                        return
                    end
                end
            end
        end
    end
end

function Blitzcrank.KS()
    if OriUtils.CanCastSpell(slots.Q, "ks.useQ") then
        local allyHeroes = ObjManager.GetNearby("ally", "heroes")
        local qReady = OriUtils.CanCastSpell(slots.Q, "ks.useQ")
        local qTargets = spells.Q:GetTargets()
        local IsWindingUp = Orbwalker.IsWindingUp()
        for iKSA, objKSA in ipairs(allyHeroes) do
            local ally = objKSA.AsHero
            if not ally.IsMe and not ally.IsDead then
                if qTargets then
                    for iKS, objKS in ipairs(qTargets) do
                        local enemyHero = objKS.AsHero
                        local qDamage = Blitzcrank.GetDamage(enemyHero, slots.Q)
                        local healthPredQ = spells.Q:GetHealthPred(objKS)
                        if OriUtils.MGet("ks.qWL." .. enemyHero.CharName, true) then
                            if healthPredQ > 0 and healthPredQ < floor(qDamage - 5) then
                                if not IsWindingUp then
                                    if spells.Q:Cast(enemyHero) then
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

    if OriUtils.CanCastSpell(slots.R, "ks.useR") then
        local allyHeroesR = ObjManager.GetNearby("ally", "heroes")
        local rReady = OriUtils.CanCastSpell(slots.Q, "ks.useQ")
        local rTargets = spells.R:GetTargets()
        local IsWindingUp = Orbwalker.IsWindingUp()
        for iKSAR, objKSAR in ipairs(allyHeroesR) do
            local ally = objKSAR.AsHero
            if not ally.IsMe and not ally.IsDead then
                if rTargets then
                    for iKS, objKS in ipairs(rTargets) do
                        local enemyHero = objKS.AsHero
                        local rDamage = Blitzcrank.GetDamage(enemyHero, slots.R)
                        local healthPredR = spells.R:GetHealthPred(objKS)
                        if OriUtils.MGet("ks.rWL." .. enemyHero.CharName, true) then
                            if healthPredR > 0 and healthPredR < floor(rDamage - 50) then
                                if not IsWindingUp then
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

function Blitzcrank.DrakeSteal()
    if OriUtils.CanCastSpell(slots.Q, "steal.useQ") then 
        local qHeroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        if qHeroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.Q.Range) then
                    local qDamage = Blitzcrank.GetDamage(minion, slots.Q)
                    local healthPredDrakeQ = spells.Q:GetHealthPred(minion)
                    local rDamage = Blitzcrank.GetDamage(minion, slots.R)
                    local healthPredDrakeR = spells.R:GetHealthPred(minion)
                    if minion.IsDragon then
                        if healthPredDrakeQ > 0 and healthPredDrakeQ < floor(qDamage - 20) then
                            if spells.Q:Cast(minion) then
                                return
                            end
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.R, "steal.useR") then 
        local rHeroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        if rHeroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.R.Range) then
                    local rDamage = Blitzcrank.GetDamage(minion, slots.R)
                    local healthPredDrakeR = spells.R:GetHealthPred(minion)
                    if minion.IsDragon then
                        if healthPredDrakeR > 0 and healthPredDrakeR < floor(rDamage - 20) then
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

function Blitzcrank.BaronSteal()

    if OriUtils.CanCastSpell(slots.Q, "steal.useQ") then 
        local qHeroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        if qHeroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.Q.Range) then
                    local qDamage = Blitzcrank.GetDamage(minion, slots.Q)
                    local healthPredBaronQ = spells.Q:GetHealthPred(minion)
                    local rDamage = Blitzcrank.GetDamage(minion, slots.R)
                    local healthPredBaronR = spells.R:GetHealthPred(minion)
                    if minion.IsBaron then
                        if healthPredBaronQ > 0 and healthPredBaronQ < floor(qDamage - 20) then
                            if spells.Q:Cast(minion) then
                                return
                            end
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.R, "steal.useR") then 
        local rHeroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        if rHeroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.R.Range) then
                    local rDamage = Blitzcrank.GetDamage(minion, slots.R)
                    local healthPredDrakeR = spells.R:GetHealthPred(minion)
                    if minion.IsBaron then
                        if healthPredDrakeR > 0 and healthPredDrakeR < floor(rDamage - 20) then
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


function Blitzcrank.rCases()
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


function combatVariants.Combo()

    if OriUtils.CanCastSpell(slots.R, "combo.useR.lasthit") then
        local rTarget = spells.R:GetTargets()
        local allyAround = ObjManager.GetNearby("ally", "heroes")
        local lasthitAmount = OriUtils.MGet("combo.useR.lasthitSlider")

        if rTarget then
            for iR, objR in ipairs(rTarget) do
                local enemyH = objR.AsHero
                if not enemyH.IsDead and enemyH.IsVisible and enemyH.IsTargetable and spells.R:IsInRange(enemyH) then
                    local rDamage = Blitzcrank.GetDamage(enemyH, slots.Q)
                    local healthPredR = spells.R:GetHealthPred(objR)

                    for iAR, objAR in ipairs(allyAround) do
                        local ally = objAR.AsHero
                        if not ally.IsMe and not ally.IsDead and enemyH:Distance(ally) < 950 then
                            if healthPredR > 0 and healthPredR < floor(rDamage - lasthitAmount) then
                                if spells.R:Cast() then
                                    return
                                end
                            end
                        end
                    end
                    if healthPredR > 0 and healthPredR < floor(rDamage) then
                        if spells.R:Cast() then
                            return
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.R, "combo.useR") then
        local isWindingUp = Orbwalker.IsWindingUp()
        local rCases = Blitzcrank.rCases()
        local rCasesM = OriUtils.MGet("combo.useR.minEnemies")
        if rCases >= rCasesM then
            if not isWindingUp then
                if spells.R:Cast() then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.Q, "combo.useQ") then
        local qRange = OriUtils.MGet("misc.QRange")
        local qTarget = TS:GetTarget(qRange, false)
        local isWindingUp = Orbwalker.IsWindingUp()
        local morgE = nil
        if qTarget then
            local morgE = qTarget:GetBuff("MorganaE")
        end
        if qTarget and not morgE then
            if not isWindingUp then
                if spells.Q:CastOnHitChance(qTarget, OriUtils.MGet("hcNew.Q") / 100) then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "combo.useE") then
        local eTarget = spells.E:GetTarget()
        local qGrab = Blitzcrank.QGrab()
        local isWindingUp = Orbwalker.IsWindingUp()
        if qGrab or eTarget then
            if not isWindingUp then
                if spells.E:Cast() then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "combo.useW") then
        local cRange = OriUtils.MGet("combo.useW.CRange")
        local wClose = OriUtils.MGet("combo.useW.CloseRange")
        local wFar = OriUtils.MGet("combo.useW.FarRange")
        local wTarget = spells.W:GetTarget()
        if OriUtils.MGet("combo.useW.CMana") and Player.ManaPercent * 100 <= OriUtils.MGet("combo.useW.Mana") then
            return
        end
        if wTarget then
            if not cRange then
                if wTarget:Distance(Player) <= 1500 then
                    spells.W:Cast()
                end
            else
                if wTarget:Distance(Player) >= wClose and wTarget:Distance(Player) <= wFar then
                    if spells.W:Cast() then
                        return
                    end
                end
            end
        end
    end
end

function combatVariants.Harass()

    if OriUtils.CanCastSpell(slots.Q, "harass.useQ") then
        local qRange = OriUtils.MGet("misc.QRange")
        local qTarget = TS:GetTarget(qRange, false)
        local nqTarget = spells.Q:GetTarget()
        local isWindingUp = Orbwalker.IsWindingUp()
        if OriUtils.MGet("misc.QRangeHarass") then
            if qTarget then
                if not isWindingUp then
                    if spells.Q:CastOnHitChance(qTarget, OriUtils.MGet("hcNew.Q") / 100) then
                        return
                    end
                end
            end
        else
            if nqTarget then
                if spells.Q:CastOnHitChance(nqTarget, OriUtils.MGet("hcNew.Q") / 100) then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "harass.useE") then
        local eTarget = spells.E:GetTarget()
        local isWindingUp = Orbwalker.IsWindingUp()
        if Blitzcrank.QGrab() or eTarget then
            if not isWindingUp then
                if spells.E:Cast() then
                    return
                end
            end
        end
    end
end

function combatVariants.Waveclear()
    if OriUtils.CanCastSpell(slots.E, "jglclear.useE") then
        local scuttleCamp = ObjManager.GetNearby("neutral", "minions")

        for i, minion in ipairs(scuttleCamp) do
            local minion = minion.AsMinion
            if OriUtils.IsValidTarget(minion, spells.Q.Range) then
                if minion.IsScuttler and minion.ShieldAll > 0 and spells.E:IsInRange(minion) then
                    if spells.E:Cast() then
                        return
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.R, "clear.useR") then
        if Orbwalker.IsFastClearEnabled() then
            local minionsInQRange = ObjManager.GetNearby("enemy", "minions")
            local minionsPositions = {}

            for _, minion in ipairs(minionsInQRange) do
                if spells.R:IsInRange(minion) then
                    insert(minionsPositions, minion.Position)
                end
            end

            local bestPos, numberOfHits = Geometry.BestCoveringCircle(minionsPositions, spells.R.Radius)
            local rMinions = OriUtils.MGet("clear.rMinions")
            local rMinionsMana = OriUtils.MGet("clear.rManaSlider")
            local isWindingUp = Orbwalker.IsWindingUp()
                if numberOfHits >= rMinions then
                if Player.ManaPercent * 100 >= rMinionsMana then
                    if not isWindingUp then
                        if spells.R:Cast() then
                            return
                        end
                    end
                end
            end
        end
    end
end

function combatVariants.Lasthit()
    if OriUtils.CanCastSpell(slots.Q, "lasthit.useQ") then
        if Blitzcrank.RelicShield1() or Blitzcrank.RelicShield2() or Blitzcrank.RelicShield3() then
            local nearbyAllies = ObjManager.GetNearby("ally", "heroes")
            for iA, allyH in ipairs(nearbyAllies) do
                if not allyH.IsDead then
                    local canonMinions = ObjManager.GetNearby("enemy", "minions")
                    for iEM, eMinions in ipairs(canonMinions) do
                        if OriUtils.IsValidTarget(eMinions, spells.Q.Range) then
                            local minion = eMinions.AsMinion
                            local healthPredCanonQ = spells.Q:GetHealthPred(eMinions)
                            local qDamage = Blitzcrank.GetDamage(minion, slots.Q)
                            if minion.IsSiegeMinion then
                                if Player:Distance(minion) > 750 then
                                    if allyH:Distance(minion) < 1200 then
                                        if healthPredCanonQ > 0 and healthPredCanonQ < floor(qDamage) then
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
end

function combatVariants.Flee()
    if OriUtils.CanCastSpell(slots.W, "misc.fleeW") then
        if spells.W:Cast() then
            return
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

    Blitzcrank.KS()
    Blitzcrank.BaronSteal()
    Blitzcrank.DrakeSteal()
    Blitzcrank.QSteal()
    Blitzcrank.flashQ()
    Blitzcrank.forceR()

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
                return Renderer.DrawTextOnPlayer("Q not Ready", scriptColor)
            else
                return Renderer.DrawTextOnPlayer("Q and Flash not Ready", 0xFFFF00FF)
            end
        end
    end
end

function events.OnDrawDamage(target, dmgList)
    if not OriUtils.MGet("draw.comboDamage") then
        return
    end

    local damageToDeal = 0

    if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
        damageToDeal = damageToDeal + Blitzcrank.GetDamage(target, slots.Q)
    end

    if spells.E:IsReady() and OriUtils.MGet("combo.useE") then
        damageToDeal = damageToDeal + ((Player.BaseAttackDamage + Player.FlatPhysicalDamageMod) * 2)
        
    end
    if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
        damageToDeal = damageToDeal + Blitzcrank.GetDamage(target, slots.R)
    end

    insert(dmgList, damageToDeal)
end

function Blitzcrank.RegisterEvents()
    for eventName, eventId in pairs(Enums.Events) do
        if events[eventName] then
            EventManager.RegisterCallback(eventId, events[eventName])
        end
    end
end

function Blitzcrank.InitMenu()
    local function QHeader()
        Menu.ColoredText(drawData[1].displayText, scriptColor, true)
    end
    local function QHeaderHit()
        Menu.ColoredText(drawData[1].displayText .. " Hitchance", scriptColor, true)
    end

    local function WHeader()
        Menu.ColoredText("[W] Overdrive", scriptColor, true)
    end
    local function WHeaderHit()
        Menu.ColoredText(drawData[2].displayText .. " Hitchance", scriptColor, true)
    end

    local function EHeader()
        Menu.ColoredText(drawData[4].displayText, scriptColor, true)
    end
    local function EHeaderHit()
        Menu.ColoredText(drawData[4].displayText .. " Hitchance", scriptColor, true)
    end

    local function RHeader()
        Menu.ColoredText(drawData[5].displayText, scriptColor, true)
    end
    local function RHeaderHit()
        Menu.ColoredText(drawData[5].displayText .. " Hitchance", scriptColor, true)
    end

    local function BlitzcrankMenu()
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
            Menu.ColoredText("This script is in an early stage , which means you'll have to redownload the final version once it's done!", 0xFFFF00FF, true)
            Menu.ColoredText("Please keep in mind, that you might encounter bugs/issues.", 0xFFFF00FF, true)
            Menu.ColoredText("If you find any, please contact " .. scriptCreator .. " via robur.lol", 0xFF0000FF, true)
        end
        
        if Menu.Checkbox("Blitzcrank.Updates130", "Don't show updates") == false then
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. scriptLastUpdated .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesVersion, 0XFFFF00FF, true)
            Menu.Text("- Added Morgana E Check in Combo", true)
            Menu.Text("- Removed 'Enemies Around'-Check inside Waveclear", true)
            Menu.Text("- Fixed Harass Q Range", true)
            Menu.Text("- Code optimization", true)
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. patchNotesPrevUpdate .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesPreVersion, 0XFFFF00FF, true)
            Menu.Text("- Adjusted Hitchance for new Prediction", true)
        end

        Menu.Separator()

        Menu.NewTree("Blitzcrank.comboMenu", "Combo Settings", function()
            Menu.ColumnLayout("Blitzcrank.comboMenu.QE", "Blitzcrank.comboMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Blitzcrank.combo.useQ", "Enable Q", true)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Blitzcrank.combo.useE", "Enable E", true)
            end)

            Menu.ColumnLayout("Blitzcrank.comboMenu.WR", "Blitzcrank.comboMenu.WR", 2, true, function()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Blitzcrank.combo.useW", "Enable W", true)
                Menu.Checkbox("Blitzcrank.combo.useW.CRange", "", true)Menu.SameLine()
                Menu.Slider("Blitzcrank.combo.useW.CloseRange", "Min W Range", 1150, 1, 1500, 1)
                Menu.Slider("Blitzcrank.combo.useW.FarRange", "Max W Range", 1500, 1, 1500, 1)
                Menu.Checkbox("Blitzcrank.combo.useW.CMana", "", true)Menu.SameLine()
                Menu.Slider("Blitzcrank.combo.useW.Mana", "If Mana above %", 40, 1, 100, 1)
                if OriUtils.MGet("combo.useW.CRange") == false and OriUtils.MGet("combo.useW.CMana") then
                    Menu.ColoredText("W will use 1500 Range", scriptColor, true)
                end
                Menu.NextColumn()
                RHeader()
                Menu.Checkbox("Blitzcrank.combo.useR", "Enable R", true)
                Menu.Slider("Blitzcrank.combo.useR.minEnemies", "Use if X enemy(ies)", 2, 1, 5)
                Menu.Checkbox("Blitzcrank.combo.useR.lasthit", "Kill with R", true)
                Menu.Slider("Blitzcrank.combo.useR.lasthitSlider", "Reduce R Damage", -225, -800, 0, 1)
                Menu.ColoredText("Reducing R damage can be good if you don't wanna \nsteal kills from your teammates. The damage will only be\nreduced if an ally is around", scriptColor, true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Blitzcrank.harassMenu", "Harass Settings", function()
            Menu.ColumnLayout("Blitzcrank.harassMenu.QE", "Blitzcrank.harassMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Blitzcrank.harass.useQ", "Enable Q", true)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Blitzcrank.harass.useE", "Enable E", false)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Blitzcrank.clearMenu", "Clear Settings", function()
            Menu.NewTree("Blitzcrank.waveMenu", "Waveclear", function()
                Menu.Checkbox("Blitzcrank.clear.useR", "Enable R Fast Clear (Requires holding Waveclear and Left Mouse Button)", true)
                Menu.Slider("Blitzcrank.clear.rMinions", "if X Minions", 5, 1, 6, 1)
                Menu.Slider("Blitzcrank.clear.rManaSlider", "Don't use if Mana < %", 50, 1, 100, 1)
            end)
            Menu.NewTree("Blitzcrank.jglMenu", "Jungleclear", function()
                Menu.Keybind("Blitzcrank.jglclear.buffSteal", "Hold to Steal Buff with Q (Only if enemy is around)", string.byte("Z"), false, false, true)
                Menu.Checkbox("Blitzcrank.jglclear.useE", "Use E on Scuttle", true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Blitzcrank.lasthitMenu", "Lasthit Settings", function()
            Menu.ColumnLayout("Blitzcrank.lasthitMenu.QE", "Blitzcrank.lasthitMenu.QE", 1, true, function()
                Menu.Text("")
                QHeader()
                Menu.ColoredText("Will lasthit Canon Minions with Q, if you are not in AA Range (Distance 750 or more)\n and if an Ally is near you - One or more Relic Shield Stack(s) is required", scriptColor, true)
                Menu.Checkbox("Blitzcrank.lasthit.useQ", "Enable Q for Canon Minions", true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Blitzcrank.stealMenu", "Steal Settings", function()
            Menu.NewTree("Blitzcrank.ksMenu", "Killsteal", function()
                Menu.Checkbox("Blitzcrank.ks.useQ", "Killsteal with Q", true)
                local cbResult = OriUtils.MGet("ks.useQ")
                if cbResult then
                    Menu.Indent(function()
                        Menu.NewTree("Blitzcrank.ksMenu.qWhitelist", "KS Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Blitzcrank.ks.qWL." .. heroName, "Q KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Blitzcrank.ks.useR", "Killsteal with R", false)
                local cbResult3 = OriUtils.MGet("ks.useR")
                if cbResult3 then
                    Menu.Indent(function()
                        Menu.NewTree("Blitzcrank.ksMenu.rWhitelist", "KS R Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Blitzcrank.ks.rWL." .. heroName, "R KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
            end)
            Menu.NewTree("Blitzcrank.jglstealMenu", "Junglesteal (Drake/Baron) | BETA", function()
                Menu.Checkbox("Blitzcrank.steal.useQ", "Junglesteal with Q", true)
                Menu.Checkbox("Blitzcrank.steal.useR", "Junglesteal with R", false)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Blitzcrank.miscMenu", "Misc Settings", function()
            Menu.ColumnLayout("Blitzcrank.miscMenu.R", "Blitzcrank.miscMenu.R", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Slider("Blitzcrank.misc.QRange", "Q Range", 980, 1, 1075, 1)
                Menu.Checkbox("Blitzcrank.misc.QRangeHarass", "Use Q Range above for Harass too", false)
                Menu.Keybind("Blitzcrank.misc.flashQ", "Flash Q (Hold)", string.byte("G"), false, false, true)
                Menu.NextColumn()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Blitzcrank.misc.fleeW", "Flee with W", true)
                RHeader()
                Menu.Keybind("Blitzcrank.misc.forceR", "Force R", string.byte("T"), false, false, true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Blitzcrank.hcMenu", "Hitchance Settings", function()
            Menu.ColumnLayout("Blitzcrank.hcMenu.QE", "Blitzcrank.hcMenu.QE", 1, true, function()
                Menu.Text("")
                QHeaderHit()
                Menu.Text("")
                Menu.Slider("Blitzcrank.hcNew.Q", "%", 45, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Blitzcrank.drawMenu", "Draw Settings", function()
            OriUtils.AddDrawMenu(drawData)
        end)
    end

    Menu.RegisterMenu(scriptName, scriptName, BlitzcrankMenu)
end

function OnLoad()
    Blitzcrank.InitMenu()
    
    Blitzcrank.RegisterEvents()
    return true
end
