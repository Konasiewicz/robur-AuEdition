if Player.CharName ~= "Soraka" then return end

local scriptName = "AuSoraka"
local scriptCreator = "AURUM"
local credits = "Orietto"
local patchNotesPrevUpdate = "12/04/2021"
local patchNotesPreVersion = "1.1.5"
local patchNotesVersion, scriptVersionUpdater = "1.1.7", "1.1.8"
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
local huge, pow, min, max = math.huge, math.pow, math.min, math.max

local SDK = _G.CoreEx

SDK.AutoUpdate("https://raw.githubusercontent.com/roburAURUM/robur-AuEdition/main/AuSoraka.lua", scriptVersionUpdater)

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
local HPPred = Libs.HealthPred
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
        Base = {85, 120, 155, 190, 225},
        TotalAP = 0.35,
        Type = dmgTypes.Magical
    },
    E = {
        Base = {70, 95, 120, 145, 170},
        TotalAP = 0.4,
        Type = dmgTypes.Magical
    }
}

local spells = {
    Q = Spell.Skillshot({
        Slot = slots.Q,
        Delay = 0.25,
        Speed = 1150,
        Range = 800,
        Radius = 200,
        Type = "Circular",
    }),
    W = Spell.Targeted({
        Slot = slots.W,
        Delay = 0.25,
        Speed = 0.0,
        Range = 550,
    }),
    E = Spell.Skillshot({
        Slot = slots.E,
        Delay = 0.25 + 0.625,
        Speed = huge,
        Range = 925,
        Radius = 195,
        Type = "Circular",
    }),
    R = Spell.Active({
        Slot = slots.R,
        Delay = 0.25,
        Speed = huge,
        Range = huge,
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

    for slot, Sorakaold in pairs(data) do
        if curTime < lastCastT[slot] + Sorakaold then
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

    --Menu.Checkbox(cacheName .. ".draw." .. "comboDamage", "Draw combo damage on healthbar", true)
    Menu.Checkbox("Soraka.drawMenu.AlwaysDraw", "Always show Drawings", false)
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

function OriUtils.CountChamps(team, position, range)
    local champs = ObjManager.Get(team, "heroes")
    local num = 0
    for _R, objR in pairs(champs) do
        local hero = objR.AsHero
        if hero.IsValid and not hero.IsDead and hero.IsTargetable then
            if hero:Distance(position) < range then
                num = num + 1
            end
        end
    end
    return num
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
    {slot = slots.Q, id = "Q", displayText = "[Q] Hymn of Valor", range = spells.Q.Range},
    {slot = slots.W, id = "W", displayText = "[W] Aria of Perseverance", range = spells.W.Range},
    {slot = slots.E, id = "E", displayText = "[E] Equinox", range = spells.E.Range},
}

local ASCIIArt = "                  _____                 _          "	 
local ASCIIArt2 = "      /\\         / ____|               | |         "
local ASCIIArt3 = "     /  \\  _   _| (___   ___  _ __ __ _| | ____ _  "
local ASCIIArt4 = "    / /\\ \\| | | |\\___ \\ / _ \\| '__/ _` | |/ / _` | "
local ASCIIArt5 = "   / ____ \\ |_| |____) | (_) | | | (_| |   < (_| | "
local ASCIIArt6 = "  /_/    \\_\\__,_|_____/ \\___/|_|  \\__,_|_|\\_\\__,_| "

local Soraka = {}

---@param estPos Vector
---@return number
function Soraka.GetQDelayForEstPos(estPos)
    local baseDelay = 0.25

    local dist = Player:Distance(estPos)

    if dist <= 50 then
        return baseDelay
    end

    local extraDist = math.min(dist - 50, 750)
    local timesToMultiply = math.floor(extraDist / 50)
    local extraDelay = timesToMultiply * 0.05

    return baseDelay + extraDelay
end

---@param target AIHeroClient
---@return PredictionResult
function Soraka.GetSorakaQPrediction(target)
    local estimatedPos = target:FastPrediction(250)

    local predInput = {
        Range = spells.Q.Range,
        Delay = Soraka.GetQDelayForEstPos(estimatedPos),
        Speed = 1150,
        Radius = 235,
        Type = "Circular",
    }

    local pred = Prediction.GetPredictedPosition(target, predInput, Player.ServerPos)

    return pred
end

function Soraka.autoR()
    if OriUtils.CanCastSpell(slots.R, "misc.globalR") then
        local autoR = ObjManager.Get("ally", "heroes")
        for i, obj in pairs(autoR) do
            local heroR = obj.AsHero
            local aTD = HPPred.GetDamagePrediction(heroR, 1, true)
            local dTD = HPPred.GetHealthPrediction(heroR, 2, true)
            if not heroR.IsDead then
                if OriUtils.MGet("wlMenu.rWL." .. heroR.CharName, true) then
                    if heroR.Health > 0 then
                        local rCalcs = (dTD / heroR.MaxHealth) * 100
                        if rCalcs < OriUtils.MGet("misc.globalRSlider") then
                            if OriUtils.CountChamps("enemy", heroR.Position, 1150) >= 1 then
                                Renderer.DrawTextOnPlayer(heroR.CharName .. " IS ABOUT TO DIE", 0xFF0000FF)
                                Renderer.DrawTextOnPlayer("PRESS HOTKEY (Default: 'G') TO INTERRUPT", 0x00FF00FF)
                                if not OriUtils.MGet("misc.stopR") then
                                    delay(OriUtils.MGet("misc.globalRDelay"), function() spells.R:Cast()end)
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

function Soraka.allyW()
    if OriUtils.MGet("misc.useW") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)
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
                local hero = obj.AsHero
                local PMana = Player.ManaPercent * 100
                if not hero.IsDead and not hero.IsMe and spells.W:IsInRange(hero) then
                    if OriUtils.MGet("wlMenu.WLMisc") then
                        if OriUtils.MGet("wlMenu.wWL." .. hero.CharName, true) then
                            if PMana >= OriUtils.MGet("misc.wMana") then
                                if spells.W:Cast(hero) then
                                    return
                                end
                            end
                        end
                    else
                        if PMana >= OriUtils.MGet("misc.wMana") then
                            if spells.W:Cast(hero) then
                                return
                            end
                        end
                    end
                end
            end
        end
    end
end



function combatVariants.Combo()

    if OriUtils.CanCastSpell(slots.R, "combo.useR") then
        if OriUtils.MGet("combo.useRGlobal") then
            local alliesMap = ObjManager.Get("ally", "heroes")

            for _, objM in pairs(alliesMap) do
                local allyM = objM.AsHero
                if not allyM.IsDead and not allyM.IsRecalling then
                    if not allyM.IsInFountain and not allyM.IsInvulnerable then
                        if OriUtils.CountChamps("enemy", allyM.Position, 1250) >= 1 then
                            local allyHP = allyM.HealthPercent * 100
                            local allyName = allyM.CharName
                            if OriUtils.MGet("combo.R.options") == 0 then
                                if OriUtils.MGet("combo.globalWL") then
                                    if OriUtils.MGet("wlMenu.rWL." .. allyName, true) then
                                        if allyHP <= OriUtils.MGet("combo.allyRSlider") then
                                            if spells.R:Cast() then
                                                return
                                            end
                                        end
                                    end
                                else
                                    if OriUtils.MGet("combo.rWL." .. allyName, true) then
                                        if allyHP <= OriUtils.MGet("combo.allyRSlider") then
                                            if spells.R:Cast() then
                                                return
                                            end
                                        end
                                    end
                                end
                            else
                                if OriUtils.MGet("combo.rCustom." .. allyName, true) then
                                    if allyHP <= OriUtils.MGet("combo.rCustomSlider." .. allyName) then
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
        else
            local alliesNearby = ObjManager.GetNearby("ally", "heroes")
            for i, objN in ipairs(alliesNearby) do
                local allyN = objN.AsHero
                if not allyN.IsDead and not allyN.IsRecalling then
                    if not allyN.IsInFountain and not allyN.IsInvulnerable then
                        if OriUtils.CountChamps("enemy", allyN.Position, 1250) >= 1 then
                            local allyHPN = allyN.HealthPercent * 100
                            local allyNameN = allyN.CharName
                            if OriUtils.MGet("combo.R.options") == 0 then
                                if OriUtils.MGet("combo.globalWL") then
                                    if OriUtils.MGet("wlMenu.rWL." .. allyNameN, true) then
                                        if allyHPN <= OriUtils.MGet("combo.allyRSlider") then
                                            if spells.R:Cast() then
                                                return
                                            end
                                        end
                                    end
                                else
                                    if OriUtils.MGet("combo.rWL." .. allyNameN, true) then
                                        if allyHPN <= OriUtils.MGet("combo.allyRSlider") then
                                            if spells.R:Cast() then
                                                return
                                            end
                                        end
                                    end
                                end
                            else
                                if OriUtils.MGet("combo.rCustom." .. allyNameN, true) then
                                    if allyHPN <= OriUtils.MGet("combo.rCustomSlider." .. allyNameN) then
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

    if OriUtils.CanCastSpell(slots.W, "combo.useW") then
        local getAlliesW = ObjManager.GetNearby("ally", "heroes")
            ---@param objA GameObject
            ---@param objB GameObject
            local function allyComparator(objA, objB)

                local mousePos = Renderer.GetMousePos()

                return mousePos:Distance(objA) < mousePos:Distance(objB)
            end
            sort(getAlliesW, allyComparator)
        for iW, objW in ipairs(getAlliesW) do
            local hero = objW.AsHero
            if not hero.IsDead and not hero.IsMe and spells.W:IsInRange(hero) then
                if OriUtils.CountChamps("enemy", hero.Position, 1250) >= 1 then
                    local hpAlly = hero.HealthPercent * 100
                    if OriUtils.MGet("combo.useWWL")then
                        if OriUtils.MGet("wlMenu.wWL." .. hero.CharName, true) then
                            if hpAlly <= OriUtils.MGet("combo.wSlider") then
                                if spells.W:Cast(hero) then
                                    return
                                end
                            end
                        end
                    else
                        if hpAlly <= OriUtils.MGet("combo.wSlider") then
                            if spells.W:Cast(hero) then
                                return
                            end
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.Q, "combo.useQ") then

        local qEnemy = ObjManager.GetNearby("enemy", "heroes")

        for iEQ, objEQ in ipairs(qEnemy) do
            if OriUtils.IsValidTarget(objEQ, spells.Q.Range) then
                local enemy = objEQ.AsHero
                if OriUtils.MGet("combo.qWL." .. enemy.CharName, true) then
                    if not Orbwalker.IsWindingUp() then
                        local pred = Soraka.GetSorakaQPrediction(enemy)
                        if pred and pred.HitChance > OriUtils.MGet("hcNew.Q") / 100 then
                            if spells.Q:Cast(pred.CastPosition) then
                                return
                            end
                        end
                    end
                end
            end
        end
    end
    
    if OriUtils.CanCastSpell(slots.E, "combo.useE") then

        local eEnemy = ObjManager.GetNearby("enemy", "heroes")

        for iEE, objEE in ipairs(eEnemy) do
            if OriUtils.IsValidTarget(objEE, spells.E.Range) then
                local enemy = objEE.AsHero
                if OriUtils.MGet("combo.eWL." .. enemy.CharName, true) then
                    if not Orbwalker.IsWindingUp() then
                        if spells.E:CastOnHitChance(enemy, OriUtils.MGet("hcNew.E") / 100) then
                            return
                        end
                    end
                end
            end
        end
    end
end

function combatVariants.Harass()
    if OriUtils.CanCastSpell(slots.Q, "harass.useQ") then
        local qTarget = spells.Q:GetTarget()
        if qTarget and Player.ManaPercent * 100 > OriUtils.MGet("harass.qMana") then
            if not Orbwalker.IsWindingUp() then
                if spells.Q:CastOnHitChance(qTarget, OriUtils.MGet("hcNew.Q") / 100) then
                    return
                end
            end
        end
    end
    
    if OriUtils.CanCastSpell(slots.E, "harass.useE") then
        local eTarget = spells.E:GetTarget()
        if eTarget and Player.ManaPercent * 100 > OriUtils.MGet("harass.eMana") then
            if not Orbwalker.IsWindingUp() then
                if spells.E:CastOnHitChance(eTarget, OriUtils.MGet("hcNew.E") / 100) then
                    return
                end
            end
        end
    end
end

function combatVariants.Waveclear()

    local PMana = Player.ManaPercent * 100
    if OriUtils.CanCastSpell(slots.Q, "jglclear.useQ") then
        local jglMinionsQ = ObjManager.GetNearby("neutral", "minions")
        local jglminionPositions = {}
        for iJGLQ, objJGLQ in ipairs(jglMinionsQ) do
            if OriUtils.IsValidTarget(objJGLQ, spells.Q.Range) then
                insert(jglminionPositions, objJGLQ.Position)
            end
        end
        local bestPos, numberOfHits = Geometry.BestCoveringCircle(jglminionPositions, spells.Q.Radius) 
        if numberOfHits >= 1 and PMana > OriUtils.MGet("jglclear.qManaSlider") then
            if spells.Q:Cast(bestPos) then
                return
            end
        end
    end


    if OriUtils.MGet("clear.enemiesAround") and TS:GetTarget(1800) then
        return
    end

    if OriUtils.CanCastSpell(slots.Q, "clear.useQ") then
        local minionsQ = ObjManager.GetNearby("enemy", "minions")
        local minionsPositions = {}
        for iQ, objQ in ipairs(minionsQ) do
            if OriUtils.IsValidTarget(objQ, spells.Q.Range) then
                insert(minionsPositions, objQ.Position)
            end
        end
        local bestPos, numberOfHits = Geometry.BestCoveringCircle(minionsPositions, spells.Q.Radius) 
        if numberOfHits >= OriUtils.MGet("clear.xMinions") then
            if PMana > OriUtils.MGet("clear.qManaSlider") then
                if spells.Q:Cast(bestPos) then
                    return
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

    Soraka.autoR()
    Soraka.allyW()
end


function events.OnDraw()
    if Player.IsDead then
        return
    end

    Soraka.autoR()

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

---@param source GameObject
---@param dashInstance DashInstance
function events.OnGapclose(source, dashInstance)
    if source.IsHero and source.IsEnemy then
        if spells.Q:IsReady() and OriUtils.MGet("gapclose.Q") then
            if OriUtils.MGet("gapclose.qWL." .. source.CharName, true) then
                local pred = spells.Q:GetPrediction(source)
                if pred and pred.HitChanceEnum >= Enums.HitChance.Dashing then
                    if spells.Q:Cast(pred.CastPosition) then
                        return
                    end
                end
            end
        end
        if spells.E:IsReady() and OriUtils.MGet("gapclose.E") then
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
        if spells.E:IsReady() and OriUtils.MGet("interrupt.E") then
            if danger >= 3 and spells.E:IsInRange(source) then
                if OriUtils.MGet("interrupt.eWL." .. source.CharName, true) then
                    local pred = spells.E:GetPrediction(source)
                    if pred and pred.HitChanceEnum >= Enums.HitChance.Medium then
                        if spells.E:Cast(source) then
                            return
                        end
                    end
                end
            end
        end
    end
end


function Soraka.RegisterEvents()
    for eventName, eventId in pairs(Enums.Events) do
        if events[eventName] then
            EventManager.RegisterCallback(eventId, events[eventName])
        end
    end
end

function Soraka.InitMenu()
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
        Menu.ColoredText("[R] Wish", scriptColor, true)
    end

    local function WAlly()
        Menu.ColoredText("Use on Ally", scriptColor, true)
    end

    local function RGeneral()
        Menu.ColoredText("[R] General", scriptColor, true)
    end

    local function RCustom()
        Menu.ColoredText("[R] Custom", scriptColor, true)
    end

    local function SorakaMenu()
        Menu.NewTree("Soraka.comboMenu", "Combo Settings", function()
            Menu.ColumnLayout("Soraka.comboMenu.QWE", "Soraka.comboMenu.QWE", 2, true, function()
                QHeader()
                Menu.Checkbox("Soraka.combo.useQ", "Enable Q", true)
                Menu.Slider("Soraka.combo.qMana", "If Mana > X%", 25, 1, 100, 1)
                EHeader()
                Menu.Checkbox("Soraka.combo.useE", "Enable E", true)
                Menu.Slider("Soraka.combo.eMana", "If Mana > X%", 30, 1, 100, 1)
                Menu.NextColumn()
                WHeader()
                Menu.ColoredText("Will Cast W closest to Mouse Pos", scriptColor, true)
                Menu.Checkbox("Soraka.combo.useW", "Enable W", true)
                Menu.Slider("Soraka.combo.wSlider", "if < %HP", 30, 1, 100, 1)
                Menu.Checkbox("Soraka.combo.useWWL", "Use Global W Whitelist", true)
            end)
            Menu.ColumnLayout("Soraka.comboMenu.R", "Soraka.comboMenu.R", 2, true, function()
                RHeader()
                Menu.Checkbox("Soraka.combo.useR", "Enable", true)Menu.SameLine()
                Menu.Dropdown("Soraka.combo.R.options", " ", 0, {"General", "Custom"})
                local ddResultG = OriUtils.MGet("combo.R.options") == 0
                local ddResultC = OriUtils.MGet("combo.R.options") == 1
                if ddResultG then
                    Menu.Checkbox("Soraka.combo.useRGlobal", "Use R Global", false)
                    local cbResultRG = OriUtils.MGet("combo.useRGlobal")
                    if not cbResultRG then Menu.SameLine()
                        Menu.ColoredText("Won't cast if ally not within 1500 Range", 0xFF0000FF, false)
                    end
                    Menu.Checkbox("Soraka.combo.globalWL", "Use Global R Whitelist", false)
                    Menu.NextColumn()
                    RGeneral()
                    Menu.Slider("Soraka.combo.allyRSlider",  "if < %HP", 30, 1, 100, 1)

                    local cbResultRWL = OriUtils.MGet("combo.globalWL")
                    if not cbResultRWL then
                        Menu.NewTree("Soraka.combo.rWhitelist", "R Whitelist", function()
                            local allyHeroes = ObjManager.Get("ally", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(allyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Soraka.combo.rWL." .. heroName, "Use R on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end
                end
                if ddResultC then
                    Menu.Checkbox("Soraka.combo.useRGlobal", "Use R Global", false)
                    local cbResultRG2 = OriUtils.MGet("combo.useRGlobal")
                    if not cbResultRG2 then Menu.SameLine()
                        Menu.ColoredText("Won't cast if ally not within 1500 Range", 0xFF0000FF, false)
                    end
                    Menu.NextColumn()
                    RCustom()
                    local allyHeroes = ObjManager.Get("ally", "heroes")

                    local addedWL = {}

                    for _, obj in pairs(allyHeroes) do
                        local hero = obj.AsHero
                        local heroName = hero.CharName

                        if hero and not addedWL[heroName] then
                            Menu.Checkbox("Soraka.combo.rCustom." .. heroName, "R " .. heroName, true)
                            local allyRSliderCustom = OriUtils.MGet("combo.rCustom." .. heroName)
                            if allyRSliderCustom then Menu.SameLine()
                                Menu.Slider("Soraka.combo.rCustomSlider." .. heroName, "Use if < %HP", 35, 1, 100, 1)
                            end
                        end
                    end
                end
            end)
        end)        

        Menu.NewTree("Soraka.harassMenu", "Harass Settings", function()
            Menu.ColumnLayout("Soraka.harassMenu.QE", "Soraka.harassMenu.QE", 2, true, function()
                QHeader()
                Menu.Checkbox("Soraka.harass.useQ", "Enable Q", true)
                Menu.Slider("Soraka.harass.qMana", "If Mana > X%", 30, 1, 100, 1)
                Menu.NextColumn()
                EHeader()
                Menu.Checkbox("Soraka.harass.useE", "Enable E", false)
                Menu.Slider("Soraka.harass.eMana", "If Mana > X%", 30, 1, 100, 1)
            end)
        end)

        Menu.NewTree("Soraka.clearMenu", "Clear Settings", function()
            Menu.NewTree("Soraka.waveMenu", "Waveclear", function()
                Menu.Checkbox("Soraka.clear.enemiesAround", "Don't clear while enemies around", true)
                Menu.Checkbox("Soraka.clear.useQ", "Use Q", true)
                Menu.Slider("Soraka.clear.xMinions", "if X Minions", 3, 1, 6, 1)
                Menu.Slider("Soraka.clear.qManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
            end)
            Menu.NewTree("Soraka.jglMenu", "Jungleclear", function()
                Menu.Checkbox("Soraka.jglclear.useQ", "Use Q", true)
                Menu.Slider("Soraka.jglclear.qManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
            end)
        end)

        Menu.NewTree("Soraka.miscMenu", "Misc Settings", function()
            Menu.ColumnLayout("Soraka.miscMenu.QWER", "Soraka.miscMenu.QWER", 4, true, function()
                QHeader()
                Menu.Checkbox("Soraka.gapclose.Q", "Use Gapclose Q ", true)
                Menu.NextColumn()
                WHeader()
                Menu.Keybind("Soraka.misc.useW", "Force W on Ally", string.byte("Z"), false, false,  true)
                Menu.Slider("Soraka.misc.wMana", "If Mana > X%", 30, 1, 100, 1)
                Menu.NextColumn()
                EHeader()
                Menu.Checkbox("Soraka.gapclose.E", "Use Gapclose E ", true)
                Menu.Checkbox("Soraka.interrupt.E", "Use Interrupt E ", true)
                Menu.NextColumn()
                RHeader()
                Menu.Checkbox("Soraka.misc.globalR", "Enable Global R", true)
                Menu.Slider("Soraka.misc.globalRSlider", "%HP", 200, 1, 100, 1)
                Menu.Slider("Soraka.misc.globalRDelay", "ms Delay", 500, 1, 2000, 1)
                Menu.Keybind("Soraka.misc.stopR", "Stop Auto R", string.byte("G"), false, false, true)
            end)
        end)
        Menu.NewTree("Soraka.wlMenu", "Whitelist Settings", function()
            Menu.ColumnLayout("Soraka.wlMenu.QWE", "Soraka.wlMenu.QWE", 4, true, function()
                QHeader()
                Menu.NewTree("Soraka.wlMenu.gapcloseQ", "Gapclose Q Whitelist", function()
                    local enemyHeroes = ObjManager.Get("enemy", "heroes")

                    local addedWL = {}

                    for _, obj in pairs(enemyHeroes) do
                        local hero = obj.AsHero
                        local heroName = hero.CharName

                        if hero and not addedWL[heroName] then
                            Menu.Checkbox("Soraka.gapclose.qWL." .. heroName, "Use Q Gapclose on " .. heroName, true)

                            addedWL[heroName] = true
                        end
                    end
                end)
                Menu.NewTree("Soraka.wlMenu.comboQ", "Combo Q Whitelist", function()
                    local enemyHeroes = ObjManager.Get("enemy", "heroes")

                    local addedWL = {}

                    for _, obj in pairs(enemyHeroes) do
                        local hero = obj.AsHero
                        local heroName = hero.CharName

                        if hero and not addedWL[heroName] then
                            Menu.Checkbox("Soraka.combo.qWL." .. heroName, "Use Q on " .. heroName, true)

                            addedWL[heroName] = true
                        end
                    end
                end)
                Menu.NextColumn()
                WHeader()
                Menu.NewTree("Soraka.wlMenu.W", "Global W Whitelist", function()
                    local allyHeroes = ObjManager.Get("ally", "heroes")

                    local addedWL = {}

                    for _, obj in pairs(allyHeroes) do
                        local hero = obj.AsHero
                        local heroName = hero.CharName

                        if not hero.IsMe and hero and not addedWL[heroName] then
                            Menu.Checkbox("Soraka.wlMenu.wWL." .. heroName, "Use W on " .. heroName, true)

                            addedWL[heroName] = true
                        end
                    end
                end)
                Menu.Checkbox("Soraka.wlMenu.WLMisc", "Use Whitelist for Misc W", true)
                Menu.NextColumn()
                EHeader()
                Menu.NewTree("Soraka.wlMenu.gapcloseE", "Gapclose E Whitelist", function()
                    local enemyHeroes = ObjManager.Get("enemy", "heroes")

                    local addedWL = {}

                    for _, obj in pairs(enemyHeroes) do
                        local hero = obj.AsHero
                        local heroName = hero.CharName

                        if hero and not addedWL[heroName] then
                            Menu.Checkbox("Soraka.gapclose.eWL." .. heroName, "Use E Gapclose on " .. heroName, false)

                            addedWL[heroName] = true
                        end
                    end
                end)
                Menu.NewTree("Soraka.wlMenu.interruptE", "Interrupt E Whitelist", function()
                    local enemyHeroes = ObjManager.Get("enemy", "heroes")

                    local addedWL = {}

                    for _, obj in pairs(enemyHeroes) do
                        local hero = obj.AsHero
                        local heroName = hero.CharName

                        if hero and not addedWL[heroName] then
                            Menu.Checkbox("Soraka.interrupt.eWL." .. heroName, "Use E Interrupt on " .. heroName, true)

                            addedWL[heroName] = true
                        end
                    end
                end)
                Menu.NewTree("Soraka.wlMenu.ETest", "E Whitelist", function()
                    local enemyHeroes = ObjManager.Get("enemy", "heroes")

                    local addedWL = {}

                    for _, obj in pairs(enemyHeroes) do
                        local hero = obj.AsHero
                        local heroName = hero.CharName

                        if hero and not addedWL[heroName] then
                            Menu.Checkbox("Soraka.combo.eWL." .. heroName, "Use E on " .. heroName, true)
                            addedWL[heroName] = true
                        end
                    end
                end)
                Menu.NextColumn()
                RHeader()
                Menu.NewTree("Soraka.wlMenu.R", "Global R Whitelist", function()
                    local allyHeroes = ObjManager.Get("ally", "heroes")

                    local addedWL = {}

                    for _, obj in pairs(allyHeroes) do
                        local hero = obj.AsHero
                        local heroName = hero.CharName

                        if hero and not addedWL[heroName] then
                            Menu.Checkbox("Soraka.wlMenu.rWL." .. heroName, "Use R on " .. heroName, true)
                            addedWL[heroName] = true
                        end
                    end
                end)
            end)
        end)

        Menu.NewTree("Soraka.hcMenu", "Hitchance Settings", function()
            Menu.ColumnLayout("Soraka.hcMenu.QE", "Soraka.hcMenu.QE", 2, true, function()
                QHeaderHit()
                Menu.Slider("Soraka.hcNew.Q", "%", 30, 1, 100, 1)
                Menu.NextColumn()
                EHeaderHit()
                Menu.Slider("Soraka.hcNew.E", "%", 45, 1, 100, 1)
            end)
        end)

        Menu.NewTree("Soraka.drawMenu", "Draw Settings", function()
            OriUtils.AddDrawMenu(drawData)
        end)
    end

    Menu.RegisterMenu(scriptName, scriptName, SorakaMenu)
end

function OnLoad()
    Soraka.InitMenu()
    
    Soraka.RegisterEvents()
    return true
end
