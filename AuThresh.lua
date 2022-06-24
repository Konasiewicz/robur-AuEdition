if Player.CharName ~= "Thresh" then return end

local scriptName = "AuThresh"
local scriptCreator = "AURUM"
local credits = "Orietto"
local patchNotesPrevUpdate = "11/26/2021"
local patchNotesPreVersion = "1.1.5"
local patchNotesVersion, scriptVersionUpdater = "1.1.7", "1.1.7"
local scriptVersion = scriptVersionUpdater
local scriptLastUpdated = "02/19/2021"
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

SDK.AutoUpdate("https://raw.githubusercontent.com/roburAURUM/robur-AuEdition/main/AuThresh.lua", scriptVersionUpdater)

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
    Q1 = {
        Base = {80, 120, 160, 200, 240},
        TotalAP = 0.5,
        Type = dmgTypes.Magical
    },
    E = {
        Base = {65, 95, 125, 155, 185},
        TotalAP  = 0.4,
        Type = dmgTypes.Magical
    },
    R = {
        Base = {250, 400, 550},
        TotalAP = 1.0,
        Type = dmgTypes.Magical
    }
}

local spells = {
    Q1 = Spell.Skillshot({
        Slot = slots.Q,
        Delay = 0.5,
        Speed = 1900,
        Range = 1075,
        Radius = 125 / 2,
        Collisions = {Heroes = true, Minions = true, WindWall = true},
        Type = "Linear",
    }),
    Q2 = Spell.Active({
        Slot = slots.Q,
    }),
    W = Spell.Skillshot({
        Slot = slots.W,
        Delay = 0.0,
        Speed = 800,
        Range = 950,
        Type = "Circular",
    }),
    E = Spell.Skillshot({
        Slot = slots.E,
        Delay = 0.0,
        Speed = 2000,
        Range = 490,
        Radius = 225 / 2, --300 / 2,
        Type = "Linear",
        Key = "E",
    }),
    R = Spell.Active({
        Slot = slots.R,
        Delay = 0.45,
        Speed = 3000,
        Range = 400,
    }),
    Flash = {
        Slot = nil,
        LastCastT = 0,
        LastCheckT = 0,
        Range = 400,
    }
}

local events = {}

local combatVariants = {}

local OriUtils = {} 
local AuTils = {}

local cacheName = Player.CharName

---@param unit AIBaseClient
---@param radius number|nil
---@param fromPos Vector|nil
function OriUtils.IsValidTarget(unit, radius, fromPos)
    fromPos = fromPos or Player.ServerPos
    radius = radius or huge

    return unit and unit.MaxHealth > 6 and fromPos:DistanceSqr(unit.ServerPos) < pow(radius, 2) and TS:IsValidTarget(unit)
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

function OriUtils.AddDrawMenu(data)
    for _, element in ipairs(data) do
        local id = element.id
        local displayText = element.displayText

        Menu.Checkbox(cacheName .. ".draw." .. id, "Draw " .. displayText .. " range", true)
        Menu.Indent(function()
            Menu.ColorPicker(cacheName .. ".draw." .. id .. ".color", "Color", scriptColor)
        end)
    end

    --Menu.Separator()

    Menu.Checkbox(cacheName .. ".draw." .. "comboDamage", "Draw combo damage on healthbar", false)
    Menu.Checkbox("Thresh.draw.AlwaysDraw", "Always show Drawings", false)
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

---@param pos Vector
---@param enemy AIHeroClient
function OriUtils.IsPosUnderAllyTurret(pos, enemy)
    local allyTurrets = ObjManager.GetNearby("ally", "turrets")

    local boundingRadius = enemy.BoundingRadius

    for _, obj in ipairs(allyTurrets) do
        local turret = obj.AsTurret

        if turret and turret.IsValid and not turret.IsDead and pos:DistanceSqr(turret) <= pow(900 + boundingRadius, 2) then
            return true
        end
    end

    return false
end

local drawData = {
    {slot = slots.Q, id = "Q", displayText = "[Q] Death Sentence", range = function () return OriUtils.MGet("misc.QRange") end},
    {slot = slots.W, id = "W", displayText = "[W] Dark Passage", range = spells.W.Range},
    {slot = slots.E, id = "E", displayText = "[E] Flay", range = spells.E.Range},
    {slot = slots.R, id = "R", displayText = "[R] The Box", range = spells.R.Range}
}



local ASCIIArt = "             _______ _                   _     "
local ASCIIArt2 = "    /\\     |__   __| |                 | |   " 
local ASCIIArt3 = "    /  \\  _   _| |  | |__  _ __ ___  ___| |__  "
local ASCIIArt4 = "   / /\\ \\| | | | |  | '_ \\| '__/ _ \\/ __| '_ \\ "
local ASCIIArt5 = "  / ____ \\ |_| | |  | | | | | |  __/\\__ \\ | | |"
local ASCIIArt6 = " /_/    \\_\\__,_|_|  |_| |_|_|  \\___||___/_| |_|"

local Thresh = {}

local slotToDamageTable = {
    [slots.Q] = damages.Q,
    [slots.W] = damages.Q,
    [slots.E] = damages.E,
    [slots.R] = damages.R
}

---@param target AIBaseClient
---@param slot slut
function Thresh.GetDamage(target, slot)
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

    if spells.Q1:IsReady() and OriUtils.MGet("combo.useQ1") then
        damageToDeal = damageToDeal + Thresh.GetDamage(target, slots.Q)
    end

    if spells.E:IsReady() and OriUtils.MGet("combo.useE") then
        damageToDeal = damageToDeal + Thresh.GetDamage(target, slots.E)
    end
    if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
        damageToDeal = damageToDeal + Thresh.GetDamage(target, slots.R)
    end

    insert(dmgList, damageToDeal)
end

function Thresh.WEnabled()
    return Player:GetBuff("AuraofDespair")
end

function Thresh.HasQ2()

    return Player:GetSpell(slots.Q).Name == "ThreshQLeap"
end

function Thresh.GetEnemyHooked()
    for handle, isHooked in pairs(Thresh.MiscData.HookedEnemies) do
        if isHooked then
            return ObjManager.GetObjectByHandle(handle)
        end
    end

    return nil
end

Thresh.MiscData = {}

Thresh.MiscData.HookedEnemies = {}

---@param exceptUnit AIHeroClient
function Thresh.GetAllEnemyHandlesExcept(exceptUnit)
        local result = {}

        local exceptHandle = exceptUnit.Handle

        for handle, obj in pairs(ObjManager.Get("enemy", "heroes")) do
            if handle ~= exceptHandle then
                result[handle] = true
            end
        end

    return result
end

---@param fromPos Vector
function Thresh.GetClosestAllyTurret(fromPos)
        local valid = {}

        local turrets = ObjManager.GetNearby("ally", "turrets")
        for _, obj in ipairs(turrets) do
            local turret = obj.AsTurret

            if turret and not turret.IsDead then
                valid[#valid+1] = turret
            end
        end

        sort(valid, function(elemA, elemB)
            return fromPos:Distance(elemA) < fromPos:Distance(elemB)
        end)

    return valid[1]
end

function Thresh.flashQ()
    if OriUtils.MGet("misc.flashQ") and not Thresh.HasQ2() then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)

        local flashReady = spells.Flash.Slot and OriUtils.IsSpellReady(spells.Flash.Slot)
        if not flashReady then
            Renderer.DrawTextOnPlayer("Flash Not Ready!", 0xFF0000FF)
            return
        end

        if not spells.Q1:IsReady() then
            Renderer.DrawTextOnPlayer("Q (Hook) Not Ready!", 0xFF0000FF)
            return
        end

        local qFlashRange = spells.Q1.Range + spells.Flash.Range
        local qFlashTarget = TS:GetTarget(qFlashRange, false)
        if qFlashTarget then
            local flashPos = Player.ServerPos:Extended(qFlashTarget, spells.Flash.Range) 

            local spellInput = {
                Slot = slots.Q,
                Delay = 0.5,
                Speed = 1900,
                Range = 1075,
                Radius = 150 / 2,
                Collisions = {Heroes = true, Minions = true, WindWall = true},
                Type = "Linear",
            }
            local pred = Prediction.GetPredictedPosition(qFlashTarget, spellInput, flashPos)
            if pred and pred.HitChanceEnum >= Enums.HitChance.High then
                if Input.Cast(spells.Flash.Slot, flashPos) then
                    delay(70, function() spells.Q1:Cast(pred.CastPosition) end)

                    return
                end
            end
        end
    end
end

function Thresh.flashE()
    if OriUtils.MGet("misc.flashE") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)

        local flashReady = spells.Flash.Slot and OriUtils.IsSpellReady(spells.Flash.Slot)
        if not flashReady then
            Renderer.DrawTextOnPlayer("Flash Not Ready!", 0xFF0000FF)
            return
        end

        if not spells.E:IsReady() then
            Renderer.DrawTextOnPlayer("E (Flay) Not Ready!", 0xFF0000FF)
            return
        end

        local eFlashRange = spells.E.Range + spells.Flash.Range
        local eFlashTarget = TS:GetTarget(eFlashRange, false)
        if eFlashTarget and not spells.E:IsInRange(eFlashTarget) then
            local flashPos = Player.ServerPos:Extended(eFlashTarget, spells.Flash.Range) 

            local spellInput = {
                Slot = slots.E,
                Delay = 0.0,
                Speed = 2000,
                Range = 525,
                Radius = 290 / 2,
                Type = "Linear",
            }
            local pred = Prediction.GetPredictedPosition(eFlashTarget, spellInput, flashPos)
            local endPos = Player.ServerPos:Extended(eFlashTarget.ServerPos, -400)
            if pred and pred.HitChanceEnum >= Enums.HitChance.High then
                if Input.Cast(spells.Flash.Slot, flashPos) then
                    delay(70, function() spells.E:Cast(endPos) end)
                    return
                end
            end
        end
    end
end

function Thresh.forceR()
    if OriUtils.MGet("misc.forceR") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(),nil)
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
function Thresh.AutoETurret()
    if spells.E:IsReady() and OriUtils.MGet("combo.AutoETurret") then
        local eTargets = spells.E:GetTargets()
        local eTarget = spells.E:GetTarget()
        local myPos = Player.ServerPos
        
        local closestTurret = Thresh.GetClosestAllyTurret(myPos)
        if closestTurret then
            local turretPos = closestTurret.ServerPos
            local eRange = spells.E.Range
            local eWidth = spells.E.Radius * 2 - 75
            local eSpeed = spells.E.Speed
            local eDelayMS = spells.E.Delay * 1000

            local possiblePosData = {}
            
            local spTurret = myPos:Extended(turretPos, -eRange)
            local epTurret = myPos:Extended(turretPos, eRange)

            insert(possiblePosData, {sp = spTurret, ep = epTurret, dir = (epTurret - spTurret):Normalized()})

            for i, hero in ipairs(eTargets) do
                local heroBRadius = hero.BoundingRadius

                local p1Target = myPos:Extended(hero, -eRange)
                local p2Target = myPos:Extended(hero, eRange)

                insert(possiblePosData, {sp = p2Target, ep = p1Target, dir = (p1Target - p2Target):Normalized()}) --Pull
                insert(possiblePosData, {sp = p1Target, ep = p2Target, dir = (p2Target - p1Target):Normalized()}) --Push

                local otherHandles = Thresh.GetAllEnemyHandlesExcept(hero)

                for _, posData in ipairs(possiblePosData) do
                    local col = Collision.SearchHeroes(posData.sp, posData.ep, eWidth, eSpeed, eDelayMS, 1, "enemy", otherHandles)
                    if col and col.Result then
                        local colPoint = col.Positions[1]

                        local targetEndPos = colPoint + posData.dir * 200

                        local distBefore = colPoint:Distance(turretPos)
                        local distAfter = targetEndPos:Distance(turretPos)

                        if distAfter < distBefore then
                            if turretPos:Distance(targetEndPos) < 900 + heroBRadius then
                                if OriUtils.MGet("combo.AutoETurret.options") == 0 then
                                    if Orbwalker.HasTurretTargetting(eTarget) then
                                        if spells.E:Cast(posData.ep) then
                                            return
                                        end
                                    end
                                else
                                    if spells.E:Cast(posData.ep) then
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

function Thresh.rCases()
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

function Thresh.forceW()
    if OriUtils.MGet("misc.useW") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(),nil)
        if spells.W:IsReady() then
            local getAllies = ObjManager.GetNearby("ally", "heroes")
                        ---@param objA GameObject
                        ---@param objB GameObject
                        local function allyComparator(objA, objB)
                            local mousePos = Renderer.GetMousePos()

                            return mousePos:Distance(objA) < mousePos:Distance(objB)
                        end

                        sort(getAllies, allyComparator)

            for i, obj in ipairs(getAllies) do
                if not obj.IsDead and not obj.IsMe and OriUtils.IsValidTarget(obj) then
                    if OriUtils.MGet("wlMenu.WLMisc") then
                        if OriUtils.MGet("wlMenu.wWL." .. obj.CharName, true) then
                            local playerDistance = obj:Distance(Player)
                            if OriUtils.MGet("misc.extendWCombo") then
                                if playerDistance <= spells.W.Range + 450 then
                                    if playerDistance <= spells.W.Range then
                                        local castPos = obj.Position
                                        if spells.W:Cast(castPos) then
                                            return
                                        end
                                    else
                                        local castPosExtended = Player.ServerPos:Extended(obj, spells.W.Range)
                                        if spells.W:Cast(castPosExtended) then
                                            return
                                        end
                                    end
                                end
                            else
                                if playerDistance <= spells.W.Range then
                                    local castPos = obj.Position
                                    if spells.W:Cast(castPos) then
                                        return
                                    end
                                end
                            end
                        else
                        end
                    else
                        local playerDistance = obj:Distance(Player)
                        if OriUtils.MGet("misc.extendWCombo") then
                            if playerDistance <= spells.W.Range + 450 then
                                if playerDistance <= spells.W.Range then
                                    local castPos = obj.Position
                                    if spells.W:Cast(castPos) then
                                        return
                                    end
                                else
                                    local castPosExtended = Player.ServerPos:Extended(obj, spells.W.Range)
                                    if spells.W:Cast(castPosExtended) then
                                        return
                                    end
                                end
                            end
                        else
                            if playerDistance <= spells.W.Range then
                                local castPos = obj.Position
                                if spells.W:Cast(castPos) then
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

function Thresh.alliesWithinW()
    local allyCount = 0
    local alliesInRange = ObjManager.GetNearby("ally", "heroes")
    for i, obj in ipairs(alliesInRange) do
        if not obj.IsDead and not obj.IsMe then
        local hero = obj.AsHero
            if OriUtils.IsValidTarget(hero, spells.W.Range + OriUtils.MGet("misc.extendWSlider")) then
                allyCount = allyCount + 1
            end
        end
    end
    return allyCount
end

function combatVariants.Combo()
    if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
        if Thresh.rCases() >= OriUtils.MGet("combo.useR.minEnemies") then
            local eTarget = spells.E:GetTarget()
            if Thresh.HasQ2() then
                if not spells.R:Cast() then
                    return
                end
            else
                if spells.R:Cast() then
                    delay(60, function()spells.E:Cast(eTarget) end)
                    return
                end
            end
        end        
    end

    if spells.E:IsReady() and OriUtils.MGet("combo.useE") then
        local eTarget = spells.E:GetTarget()
        if eTarget then
            local endPos = Player.ServerPos:Extended(eTarget.ServerPos, -400)
            if OriUtils.MGet("combo.useE.options") == 0 then
                if not Thresh.HasQ2() then
                    if spells.E:Cast(endPos) then
                        return
                    end
                end
            elseif OriUtils.MGet("combo.useE.options") == 1 then
                if spells.E:Cast(eTarget) then
                    return
                end
            elseif OriUtils.MGet("combo.useE.options") == 2 then
                local enemiesAroundE = ObjManager.GetNearby("enemy", "heroes")
                for i, obj in ipairs(enemiesAroundE) do
                local hero = obj.AsHero
                local heroName = hero.CharName
                    if OriUtils.MGet("combo.eWL." .. heroName, true) then
                        if OriUtils.MGet("combo.eOpt." .. heroName) == 0 then
                            if spells.E:Cast(endPos) then
                                return
                            end
                        else
                            if spells.E:Cast(eTarget) then
                                return
                            end
                        end
                    end
                end
            end
        end
    end

    if spells.W:IsReady() and OriUtils.MGet("combo.EW") then
        local eTarget = spells.E:GetTarget()
        if eTarget then
            local allyDistance = ObjManager.GetNearby("ally", "heroes")
            ---@param objA GameObject
            ---@param objB GameObject
            local function allyComparator(objA, objB)
                local mousePos = Renderer.GetMousePos()

                return mousePos:Distance(objA) < mousePos:Distance(objB)
            end

            sort(allyDistance, allyComparator)

            for iAllies, objAllies in ipairs(allyDistance) do
                local hero = objAllies.AsHero
                if not hero.IsDead and not hero.IsMe and OriUtils.IsValidTarget(hero) then
                    local playerDistance = hero:Distance(Player)
                    if playerDistance > OriUtils.MGet("combo.EWSlider") then
                        if OriUtils.MGet("wlMenu.wWL." .. hero.CharName, true) then
                            if OriUtils.MGet("misc.extendWCombo") then
                                if playerDistance <= spells.W.Range + OriUtils.MGet("misc.extendWSlider") then
                                    if playerDistance <= spells.W.Range then
                                        local castPos = hero.Position
                                        if spells.W:Cast(castPos) then
                                            return
                                        end
                                    else
                                        local castPosExtended = Player.ServerPos:Extended(hero, spells.W.Range)
                                        if spells.W:Cast(castPosExtended) then
                                            return
                                        end
                                    end
                                end
                            else
                                if playerDistance <= spells.W.Range then
                                    local castPos = hero.Position
                                    if spells.W:Cast(castPos) then
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

    if Thresh.HasQ2() then
        if spells.Q2:IsReady() and OriUtils.MGet("combo.useQ2") then
            if Thresh.GetEnemyHooked() then
                if spells.W:IsReady() and OriUtils.MGet("combo.useQWQ") then
                    local getAllies = ObjManager.GetNearby("ally", "heroes")
                    ---@param objA GameObject
                    ---@param objB GameObject
                    local function allyComparator(objA, objB)
                        local mousePos = Renderer.GetMousePos()

                        return mousePos:Distance(objA) < mousePos:Distance(objB)
                    end

                    sort(getAllies, allyComparator)
                    
                    for i, obj in ipairs(getAllies) do
                        if not obj.IsDead and not obj.IsMe and OriUtils.IsValidTarget(obj) then
                            local playerDistance = obj:Distance(Player)
                            if playerDistance >= OriUtils.MGet("combo.QWSlider") then
                                if OriUtils.MGet("misc.extendWCombo") then
                                    if playerDistance <= spells.W.Range + OriUtils.MGet("misc.extendWSlider") then
                                        if playerDistance <= spells.W.Range then
                                            local castPos = obj.Position
                                            if spells.W:Cast(castPos) then
                                                return
                                            end
                                        else
                                            local castPosExtended = Player.ServerPos:Extended(obj, spells.W.Range)
                                            if spells.W:Cast(castPosExtended) then
                                                return
                                            end
                                        end
                                    end
                                else
                                    if playerDistance <= spells.W.Range then
                                        local castPos = obj.Position
                                        if spells.W:Cast(castPos) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                if spells.Q2:Cast() then
                    return
                end
            end
        end
    else
        if spells.Q1:IsReady() and OriUtils.MGet("combo.useQ1") then
            local enemyQ = ObjManager.GetNearby("enemy", "heroes")
            for i, obj in ipairs(enemyQ) do
                local hero = obj.AsHero
                if OriUtils.MGet("combo.qWL." .. hero.CharName, true) then
                    local qRange = OriUtils.MGet("misc.QRange")
                    local qTarget = TS:GetTarget(qRange, false)
                    if qTarget then
                        if spells.Q1:CastOnHitChance(qTarget, OriUtils.MGet("hcNew.Q") / 100) then
                            return
                        end
                    end
                end
            end
        end
    end
    if spells.W:IsReady() then
        if OriUtils.MGet("combo.allyW") then
            local alliesHP = ObjManager.GetNearby("ally", "heroes")
            for i, obj in ipairs(alliesHP) do
                local hero = obj.AsHero
                if not hero.IsDead and not hero.IsMe then
                    if spells.W:IsInRange(hero) and OriUtils.IsValidTarget(hero) then
                        local healthPercentAlly = hero.HealthPercent * 100
                        if healthPercentAlly <= OriUtils.MGet("combo.allyWSlider") then
                            local castPos = hero.Position
                            if spells.W:Cast(castPos) then
                                return
                            end
                        end
                    end
                end
            end
        end

        if OriUtils.MGet("combo.selfW") then
            local healthPercentSelf = Player.HealthPercent * 100
            if Thresh.alliesWithinW() == 0 and healthPercentSelf < OriUtils.MGet("combo.selfWSlider") then
                local castPos = Player.Position
                if spells.W:Cast(castPos) then
                    return
                end
            end
        end        
    end
end

function combatVariants.Harass()
    if Thresh.HasQ2() then
        if spells.Q2:IsReady() and OriUtils.MGet("harass.useQ2") then
            if spells.Q2:Cast() then
                return
            end
        end
    else
        if spells.Q1:IsReady() and OriUtils.MGet("harass.useQ1") then
            if OriUtils.MGet("miscQRangeHarass") then
                local qRange = OriUtils.MGet("misc.QRange")
                local qTarget = TS:GetTarget(qRange, false)
                if qTarget then
                    if spells.Q1:CastOnHitChance(qTarget, OriUtils.MGet("hcNew.Q") / 100) then
                        return
                    end
                end
            else
                local qTarget = spells.Q1:GetTarget()
                if qTarget then
                    if spells.Q1:CastOnHitChance(qTarget, Enums.HitChance.Low) then
                        return
                    end
                end
            end
        end

        if spells.E:IsReady() and OriUtils.MGet("harass.useE") then
            local eTarget = spells.E:GetTarget()
            if eTarget then
                local endPos = Player.ServerPos:Extended(eTarget.ServerPos, -400)
                if spells.E:Cast(endPos) then
                    return
                end
            end
        end
    end
end

function combatVariants.Waveclear()
    if OriUtils.MGet("clear.enemiesAround") and TS:GetTarget(1800) then
        return
    end
    
    if spells.E:IsReady() and OriUtils.MGet("clear.useE") then
        local minionsInERange = OriUtils.GetEnemyAndJungleMinions(spells.E.Range)
        local minionsPositions = {}

        for _, minion in ipairs(minionsInERange) do
            insert(minionsPositions, minion.Position)
        end

        local bestPos, numberOfHits = Geometry.BestCoveringRectangle(minionsPositions, Player.Position, spells.E.Radius * 2) 
        if numberOfHits >= OriUtils.MGet("clear.xMinions") then
            if spells.E:Cast(bestPos) then
                return
            end
        end
    end
end

function combatVariants.Flee()
    if spells.E:IsReady() and OriUtils.MGet("flee.useE") then
        local miscETarget = spells.E:GetTarget()
        if miscETarget then
            if spells.E:Cast(miscETarget) then
                return
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
    elseif OrbwalkerState == "Flee" then
        combatVariants.Flee()
    end

    Thresh.flashQ()

    Thresh.flashE()

    Thresh.forceW()

    Thresh.AutoETurret()

    Thresh.forceR()
end

function events.OnDraw()
    if Player.IsDead then
        return
    end

    Thresh.flashQ()

    Thresh.flashE()

    local myPos = Player.Position

    for _, drawInfo in ipairs(drawData) do
        local slot = drawInfo.slot
        local id = drawInfo.id
        local range = drawInfo.range

        if type(range) == "function" then
            range = range()
        end

        if not OriUtils.MGet("draw.AlwaysDraw") then
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

---@param source GameObject
---@param dashInstance DashInstance
function events.OnGapclose(source, dashInstance)
    if source.IsHero and source.IsEnemy then
        if spells.E:IsReady() and not Thresh.HasQ2() and OriUtils.MGet("gapclose.E") then
            if OriUtils.MGet("gapclose.eWL." .. source.CharName, true) then
                local pred = spells.E:GetPrediction(source)
                if pred and pred.HitChanceEnum >= Enums.HitChance.Dashing then
                    if spells.E:Cast(pred.CastPosition) then
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
        if spells.Q1:IsReady() and OriUtils.MGet("interrupt.Q") then
            if danger >= 3 then
                if OriUtils.MGet("interrupt.qWL." .. source.CharName, true) then
                    local pred = spells.Q1:GetPrediction(source)
                    if pred and pred.HitChanceEnum >= Enums.HitChance.Medium then
                        if spells.Q1:Cast(pred.CastPosition) then
                            return
                        end
                    end
                end
            end
        end
            
        if spells.E:IsReady() and OriUtils.MGet("interrupt.E") then
            if danger >= 3 and spells.E:IsInRange(source) then
                if OriUtils.MGet("interrupt.eWL." .. source.CharName, true) then
                    local endPos = Player.ServerPos:Extended(source.ServerPos, -400)
                    if spells.E:Cast(endPos) then
                        return
                    end
                end
            end
        end
    end
end

---@param obj GameObject
---@param buffInst BuffInst
function events.OnBuffGain(obj, buffInst)
    if obj and buffInst then
        if obj.IsEnemy and obj.IsHero then
            if buffInst.Name == "ThreshQ" then
                Thresh.MiscData.HookedEnemies[obj.Handle] = true
            end
        end
    end
end

---@param obj GameObject
---@param buffInst BuffInst
function events.OnBuffLost(obj, buffInst)
    if obj and buffInst then
        if obj.IsEnemy and obj.IsHero then
            if buffInst.Name == "ThreshQ" then
                Thresh.MiscData.HookedEnemies[obj.Handle] = false
            end
        end
    end
end


function Thresh.RegisterEvents()
    for eventName, eventId in pairs(Enums.Events) do
        if events[eventName] then
            EventManager.RegisterCallback(eventId, events[eventName])
        end
    end
end

function Thresh.InitMenu()
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

    -- Special Headers
    local function WSelf()
        Menu.ColoredText("Use on Self", scriptColor, true)
    end
    local function WAlly()
        Menu.ColoredText("Use on Ally", scriptColor, true)
    end
    local function WRange()
        Menu.ColoredText("Use if in E Range and Thresh", scriptColor, true)
    end

    local function ThreshMenu()


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
            Menu.Text("")
            Menu.ColoredText("This script is in an early stage!", 0xFFFF00FF, true)
            Menu.ColoredText("Please keep in mind, that you might encounter bugs/issues.", 0xFFFF00FF, true)
            Menu.ColoredText("If you find any, please contact " .. scriptCreator .. " via robur.lol", 0xFF0000FF, true)
        end

        if Menu.Checkbox("Thresh.Updates115", "Don't show updates") == false then
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. scriptLastUpdated .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesVersion, 0XFFFF00FF, true)
            Menu.Text("- Adjusted Hitchance for new Prediction", true)
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. patchNotesPrevUpdate .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesPreVersion, 0XFFFF00FF, true)
            Menu.Text("- Added Q Range Slider under Misc to improve Q Usage", true)
            Menu.ColoredText("-- Default: 1025 | Min: 1 | Max 1075", 0xFF8800FF, true)
        end

        Menu.Separator()

        Menu.NewTree("Thresh.comboMenu", "Combo Settings", function()
            Menu.ColumnLayout("Thresh.comboMenu.QE", "Thresh.comboMenu.QE", 3, true, function()
                Menu.Text("")
                QHeader()
				Menu.Text("")
                Menu.Checkbox("Thresh.combo.useQ1", "Enable Q1", true)
                Menu.Checkbox("Thresh.combo.useQ2", "Enable Q2", true)
                local cbResult = OriUtils.MGet("combo.useQ2")
                if cbResult then
                    Menu.Checkbox("Thresh.combo.useQWQ", "Use W after Q1 if", true)
                    local cbResult2 = OriUtils.MGet("combo.useQWQ")
                    if cbResult2 then
                        Menu.Slider("Thresh.combo.QWSlider", "Dist. >= Ally ", 700, 1, 950, 1)
                    end
                end
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Text("")
                Menu.Checkbox("Thresh.combo.useE", "Enable E", true)
                Menu.Dropdown("Thresh.combo.useE.options", "E Pos", 0, {"Yourself", "Away", "Custom"})
                local ddInfo = OriUtils.MGet("combo.useE.options") == 2
                if ddInfo then
                    Menu.ColoredText("Check Whitelist E Settings to set Custom E Pos", 0xFF0000FF)
                end
                Menu.Checkbox("Thresh.combo.AutoETurret", "Auto E under Turret", true)
                local cbResultAutoE = OriUtils.MGet("combo.AutoETurret")
                if cbResultAutoE then
                    Menu.Dropdown("Thresh.combo.AutoETurret.options", " ", 0, {"When Turret is Attacking Enemy", "Always"})
                end
                Menu.NextColumn()
                Menu.Text("")
                RHeader()
                Menu.Separator()
                Menu.Text("")
                Menu.Checkbox("Thresh.combo.useR", "Enable R", true)
                Menu.Slider("Thresh.combo.useR.minEnemies", "Min Enemies", 2, 1, 5, 1)
            end)
            Menu.Separator()
            WHeader()
            Menu.Separator()
            --Menu.Text("")
            Menu.ColumnLayout("Thresh.comboMenu.W", "Thresh.comboMenu.W", 3, true, function()
                WRange()
                Menu.Text("")
                Menu.Checkbox("Thresh.combo.EW", "Enable", false)
                local cbResult3 = OriUtils.MGet("combo.EW")
                if cbResult3 then
                    Menu.Slider("Thresh.combo.EWSlider", "Dist. >= Ally ", 700, 1, 950, 1)
                end
                Menu.NextColumn()
                WAlly()
                Menu.Text("")
                Menu.Checkbox("Thresh.combo.allyW", "Enable", true)
                    local cbResult4 = OriUtils.MGet("combo.allyW")
                    if cbResult4 then
                        Menu.Slider("Thresh.combo.allyWSlider", "if < %HP", 30, 1, 100, 1)
                    end
                Menu.NextColumn()
                WSelf()
                Menu.Separator()
                Menu.Text("")
                Menu.Checkbox("Thresh.combo.selfW", "Enable", true)
                    local cbResult5 = OriUtils.MGet("combo.selfW")
                    if cbResult5 then
                        Menu.Slider("Thresh.combo.selfWSlider", "if < %HP", 25, 1, 100, 1)
                    end
            end)
        end)

        Menu.Separator()

        Menu.NewTree("Thresh.harassMenu", "Harass Settings", function()
            Menu.ColumnLayout("Thresh.harassMenu.QE", "Thresh.harassMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Thresh.harass.useQ1", "Enable Q1", true)
                Menu.Checkbox("Thresh.harass.useQ2", "Enable Q2", false)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Thresh.harass.useE", "Enable E", false)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Thresh.clearMenu", "Clear Settings", function()
        Menu.Checkbox("Thresh.clear.enemiesAround", "Don't clear while enemies around", true)
        Menu.Separator()
            Menu.ColumnLayout("Thresh.clearMenu.W", "Thresh.clearMenu.W", 1, true, function()
                EHeader()
                Menu.Checkbox("Thresh.clear.useE", "Enable E", true)
                Menu.Slider("Thresh.clear.xMinions", "if X Minions", 3, 1, 6, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Thresh.miscMenu", "Misc Settings", function()
            Menu.ColumnLayout("Thresh.miscMenu.QWER", "Thresh.miscMenu.QWER", 4, true, function()
                Menu.Text("")
                QHeader()
                Menu.Keybind("Thresh.misc.flashQ", "Flash Q", string.byte("G"), false, false, true)
                Menu.Checkbox("Thresh.interrupt.Q", "Use Interrupt Q ", true)
                Menu.Slider("Thresh.misc.QRange", "Q Range", 1025, 1, 1075, 1)
                Menu.Checkbox("Thresh.miscQRangeHarass", "Use above Q Range for Harass", false)
                Menu.NextColumn()
                Menu.Text("")
                WHeader()
                Menu.Keybind("Thresh.misc.useW", "W to Ally", string.byte("Z"), false, false,  true)
                Menu.Slider("Thresh.misc.extendWSlider", "Added W Range ", 1200, 0, 1500, 1)
                Menu.Checkbox("Thresh.misc.extendWCombo", "Extend W for Combo", true)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Keybind("Thresh.misc.flashE", "Flash E", string.byte("H"), false, false, true)
                Menu.Checkbox("Thresh.flee.useE", "Use E in Flee Mode", true)
                Menu.Checkbox("Thresh.interrupt.E", "Use Interrupt E ", true)
                Menu.Checkbox("Thresh.gapclose.E", "Use Gapclose E ", true)
                Menu.NextColumn()
                Menu.Text("")
                RHeader()
                Menu.Keybind("Thresh.misc.forceR", "Force R", string.byte("T"), false, false,  true)
            end)
        end)
        Menu.Separator()
        Menu.NewTree("Thresh.wlMenu", "Whitelist Settings", function()
            Menu.ColumnLayout("Thresh.wlMenu.QWE", "Thresh.wlMenu.QWE", 3, true, function()
                Menu.Text("")
                QHeader()
                Menu.NewTree("Thresh.wlMenu.interruptQ", "Interrupt Q Whitelist", function()
                    local enemyHeroes = ObjManager.Get("enemy", "heroes")

                    local addedWL = {}

                    for _, obj in pairs(enemyHeroes) do
                        local hero = obj.AsHero
                        local heroName = hero.CharName

                        if hero and not addedWL[heroName] then
                            Menu.Checkbox("Thresh.interrupt.qWL." .. heroName, "Use Q Interrupt on " .. heroName, true)

                            addedWL[heroName] = true
                        end
                    end
                end)
                Menu.NewTree("Thresh.wlMenu.comboQ", "Combo Q Whitelist", function()
                    local enemyHeroes = ObjManager.Get("enemy", "heroes")

                    local addedWL = {}

                    for _, obj in pairs(enemyHeroes) do
                        local hero = obj.AsHero
                        local heroName = hero.CharName

                        if hero and not addedWL[heroName] then
                            Menu.Checkbox("Thresh.combo.qWL." .. heroName, "Use Q on " .. heroName, true)

                            addedWL[heroName] = true
                        end
                    end
                end)
                Menu.NextColumn()
                Menu.Text("")
                WHeader()
                Menu.NewTree("Thresh.wlMenu.W", "Combo W Whitelist", function()
                    local allyHeroes = ObjManager.Get("ally", "heroes")

                    local addedWL = {}

                    for _, obj in pairs(allyHeroes) do
                        local hero = obj.AsHero
                        local heroName = hero.CharName

                        if not hero.IsMe and hero and not addedWL[heroName] then
                            Menu.Checkbox("Thresh.wlMenu.wWL." .. heroName, "Use W on " .. heroName, true)

                            addedWL[heroName] = true
                        end
                    end
                end)
                Menu.Checkbox("Thresh.wlMenu.WLMisc", "Use Whitelist for Misc W", false)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.NewTree("Thresh.wlMenu.gapcloseE", "Gapclose E Whitelist", function()
                    local enemyHeroes = ObjManager.Get("enemy", "heroes")

                    local addedWL = {}

                    for _, obj in pairs(enemyHeroes) do
                        local hero = obj.AsHero
                        local heroName = hero.CharName

                        if hero and not addedWL[heroName] then
                            Menu.Checkbox("Thresh.gapclose.eWL." .. heroName, "Use E Gapclose on " .. heroName, true)

                            addedWL[heroName] = true
                        end
                    end
                end)
                Menu.NewTree("Thresh.wlMenu.interruptE", "Interrupt E Whitelist", function()
                    local enemyHeroes = ObjManager.Get("enemy", "heroes")

                    local addedWL = {}

                    for _, obj in pairs(enemyHeroes) do
                        local hero = obj.AsHero
                        local heroName = hero.CharName

                        if hero and not addedWL[heroName] then
                            Menu.Checkbox("Thresh.interrupt.eWL." .. heroName, "Use E Interrupt on " .. heroName, true)

                            addedWL[heroName] = true
                        end
                    end
                end)
                Menu.NewTree("Thresh.wlMenu.ETest", "E Whitelist and Custom Position", function()
                    local enemyHeroes = ObjManager.Get("enemy", "heroes")

                    local addedWL = {}

                    for _, obj in pairs(enemyHeroes) do
                        local hero = obj.AsHero
                        local heroName = hero.CharName

                        if hero and not addedWL[heroName] then
                            Menu.Checkbox("Thresh.combo.eWL." .. heroName, "Use E on " .. heroName .. " to", true)
                            addedWL[heroName] = true
                            local cbResult = OriUtils.MGet("combo.eWL." .. heroName)
                            if cbResult then Menu.SameLine()
                                Menu.Dropdown("Thresh.combo.eOpt." .. heroName, " ", 0, {"Yourself", "Away"})
                            end
                        end
                    end
                end)
            end)
        end)
        Menu.Separator()
        Menu.NewTree("Thresh.hcMenu", "Hitchance Settings", function()
            Menu.ColumnLayout("Thresh.hcMenu.Q", "Thresh.hcMenu.Q", 1, true, function()
                Menu.Text("")
                QHeaderHit()
                Menu.Text("")
                Menu.Slider("Thresh.hcNew.Q", "%", 50, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Thresh.drawMenu", "Draw Settings", function()
            OriUtils.AddDrawMenu(drawData)
        end)
    end

    Menu.RegisterMenu(scriptName, scriptName, ThreshMenu)
end
    
function OnLoad()
    Thresh.InitMenu()
    Thresh.RegisterEvents()
    return true
end
