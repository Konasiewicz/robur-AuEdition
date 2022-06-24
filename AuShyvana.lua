if Player.CharName ~= "Shyvana" then return end

local scriptName = "AuShyvana"
local scriptCreator = "AURUM"
local credits = "Orietto"
local patchNotesPrevUpdate = "03/27/2022"
local patchNotesPreVersion = "1.0.0"
local patchNotesVersion, scriptVersionUpdater = "1.0.2", "1.0.2"
local scriptVersion = scriptVersionUpdater
local scriptLastUpdated = "03/27/2022"
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

SDK.AutoUpdate("https://raw.githubusercontent.com/roburAURUM/robur-AuEdition/main/AuShyvana.lua", scriptVersionUpdater)

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
        Base = {Player.TotalAD, Player.TotalAD, Player.TotalAD, Player.TotalAD, Player.TotalAD},
        TotalAP = 0.35,
        Type = dmgTypes.Physical
    },
    Q2 = {
        Base = {Player.TotalAD * 0.2, Player.TotalAD * 0.35, Player.TotalAD * 0.5, Player.TotalAD * 0.65, Player.TotalAD * 0.8},
        TotalAP  = 0.25,
        Type = dmgTypes.Physical
    },
    W = {
        Base = {20, 32, 45, 57, 70},
        BonusAD  = 0.2,
        Type = dmgTypes.Magical
    },
    E = {
        Base = {60, 100, 140, 180, 220},
        TotalAD = 0.3,
        TotalAP  = 0.7,
        Type = dmgTypes.Magical
    },
    E2 = {
        Base = {0, 0, 0, 0, 0, 100, 105, 110, 115, 120, 125, 130, 135, 140, 145, 150, 155, 160},
        TotalAD  = 0.3,
        TotalAP  = 0.3,
        Type = dmgTypes.Magical
    },
    R = {
        Base = {150, 250, 350},
        TotalAP = 1.0,
        Type = dmgTypes.Magical
    }
}

local spells = {
    Q = Spell.Active({
        Slot = slots.Q,
        Delay = 0.0,
        Range = 250,
    }),
    Q2 = Spell.Active({
        Slot = slots.Q,
        Delay = 0.0,
        Range = 310,
    }),
    W = Spell.Active({
        Slot = slots.W,
        Delay = 0.0,
        Range = 322.5,
        Type = "Circular",
    }),
    E = Spell.Skillshot({
        Slot = slots.E,
        Delay = 0.25,
        Speed = 1575,
        Range = 925,
        Radius = 120 / 2,
        Type = "Linear",
        Collisions = {Windwall = true, Heroes = true}
    }),
    E2 = Spell.Skillshot({
        Slot = slots.E,
        Delay = 0.33 + 0.40,
        Speed = 1575,
        Range = 1000,
        Radius = 345,
        Type = "Circular",
        Collisions = {Windwall = true, Heroes = true}
    }),
    R = Spell.Skillshot({
        Slot = slots.R,
        Delay = 0.25,
        Speed = 1100,
        Range = 850,
        Radius = 270 / 2,
        Type = "Linear",
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

function OriUtils.CheckCastTimers(data)
    local curTime = Game.GetTime()

    for slot, Shyvanaold in pairs(data) do
        if curTime < lastCastT[slot] + Shyvanaold then
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
    Menu.Checkbox("Shyvana.drawMenu.AlwaysDraw", "Always show Drawings", false)
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
    {slot = slots.Q, id = "Q", displayText = "[Q] Twin Bite", range = spells.Q.Range},
    {slot = slots.Q, id = "Q2", displayText = "[Q2] Twin Bite", range = spells.Q2.Range},
    {slot = slots.W, id = "W", displayText = "[W] Burnout", range = function () return OriUtils.MGet("combo.wRange") end},
    {slot = slots.E, id = "E", displayText = "[E] Flame Breath", range = spells.E.Range},
    {slot = slots.E, id = "E2", displayText = "[E2] Flame Breath", range = spells.E2.Range},
    {slot = slots.R, id = "R", displayText = "[R] Dragon's Descent", range = spells.R.Range}
}

local ASCIIArt = "                  _____ _                                   "
local ASCIIArt2 = "      /\\         / ____| |                                  "
local ASCIIArt3 = "     /  \\  _   _| (___ | |__  _   ___   ____ _ _ __   __ _  "
local ASCIIArt4 = "    / /\\ \\| | | |\\___ \\| '_ \\| | | \\ \\ / / _` | '_ \\ / _` | "
local ASCIIArt5 = "   / ____ \\ |_| |____) | | | | |_| |\\ V / (_| | | | | (_| | "
local ASCIIArt6 = "  /_/    \\_\\__,_|_____/|_| |_|\\__, | \\_/ \\__,_|_| |_|\\__,_| "
local ASCIIArt7 = "                               __/ |                        "
local ASCIIArt8 = "                                |___/                          "



local Shyvana = {}

function Shyvana.IsMassive()
    return Player:GetBuff("ShyvanaTransform")
end

local slotToDamageTable = {
    [slots.Q] = damages.Q,
    [slots.W] = damages.W,
    [slots.E] = damages.E,
    [slots.R] = damages.R
}

---@param target AIBaseClient
---@param slot slut
function Shyvana.GetDamage(target, slot)
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

---@param target AIBaseClient
function Shyvana.GetQ2Damage(target)
    local me = Player
    local rawDamage = 0
    local damageType = nil

    local spellLevel = me:GetSpell(slots.Q).Level

    if spellLevel >= 1 then
        local data = damages.Q2
        damageType = data.Type

        rawDamage = rawDamage + data.Base[spellLevel]

        if data.TotalAP then
            rawDamage = rawDamage + (data.TotalAP * me.TotalAP)
        end

        if data.TotalAD then
            rawDamage = rawDamage + (data.TotalAD * me.TotalAD)
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

    return 0
end

---@param target AIBaseClient
function Shyvana.GetE2Damage(target)
    local me = Player
    local rawDamage = 0
    local damageType = nil

    local spellLevel = me:GetSpell(slots.E).Level

    if spellLevel >= 1 then
        local data = damages.E2
        damageType = data.Type

        rawDamage = rawDamage + data.Base[Player.Level]


        if data.TotalAP then
            rawDamage = rawDamage + (data.TotalAP * me.TotalAP)
        end

        if data.TotalAD then
            rawDamage = rawDamage + (data.TotalAD * me.TotalAD)
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

    return 0
end

function Shyvana.forceR()
    if OriUtils.MGet("misc.forceR") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)
        local enemyPositions = {}
        local rTargets = spells.R:GetTargets()
        local hcR = OriUtils.MGet("hc.R") / 100
        
        for i, obj in ipairs(rTargets) do
            local pred = spells.R:GetPrediction(obj)
            if pred and pred.HitChance >= hcR then
                table.insert(enemyPositions, pred.TargetPosition)
            end
        end
        local bestPos, numberOfHits = Geometry.BestCoveringRectangle(enemyPositions, Player.Position, spells.R.Radius * 2)
        if numberOfHits >= 1 then
            if spells.R:Cast(bestPos) then
                return
            end
        end
    end
end


function Shyvana.KS()
    if OriUtils.CanCastSpell(slots.Q, "ks.useQ") then
        local allyHeroes = ObjManager.GetNearby("ally", "heroes")
        local qTargets = spells.Q:GetTargets()
        local q2Targets = spells.Q2:GetTargets()
        local isWindingUp = Orbwalker.IsWindingUp()
        local isMassive = Shyvana.IsMassive()
        for iKSA, objKSA in ipairs(allyHeroes) do
            local ally = objKSA.AsHero
            if not ally.IsMe and not ally.IsDead then
                if isMassive then
                    if q2Targets then
                        for iKS, objKS in ipairs(q2Targets) do
                            local enemyHero = objKS.AsHero
                            local qDamage = Shyvana.GetDamage(enemyHero, slots.Q)
                            local healthPredQ = spells.Q:GetHealthPred(objKS)
                            if OriUtils.MGet("ks.qWL." .. enemyHero.CharName, true) then
                                if healthPredQ > 0 and healthPredQ < floor(qDamage - 5) then
                                    if not isWindingUp then
                                        if spells.Q2:Cast() then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                    end
                else
                    if qTargets then
                        for iKS, objKS in ipairs(qTargets) do
                            local enemyHero = objKS.AsHero
                            local qDamage = Shyvana.GetDamage(enemyHero, slots.Q)
                            local healthPredQ = spells.Q:GetHealthPred(objKS)
                            if OriUtils.MGet("ks.qWL." .. enemyHero.CharName, true) then
                                if healthPredQ > 0 and healthPredQ < floor(qDamage - 5) then
                                    if not isWindingUp then
                                        if spells.Q:Cast() then
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

    if OriUtils.CanCastSpell(slots.E, "ks.useE") then
        local allyHeroes = ObjManager.GetNearby("ally", "heroes")
        local eTargets = spells.E:GetTargets()
        local isWindingUp = Orbwalker.IsWindingUp()
        local isMassive = Shyvana.IsMassive()
        for iKSA, objKSA in ipairs(allyHeroes) do
            local ally = objKSA.AsHero
            if not ally.IsMe and not ally.IsDead then
                if eTargets then
                    for iKS, objKS in ipairs(eTargets) do
                        local enemyHero = objKS.AsHero
                        local healthPredE = spells.E:GetHealthPred(objKS)
                        local healthPredE2 = spells.E2:GetHealthPred(objKS)
                        local eDamage = Shyvana.GetDamage(enemyHero, slots.E)
                        if OriUtils.MGet("ks.eWL." .. enemyHero.CharName, true) then
                            if isMassive then
                                if healthPredE2 > 0 and healthPredE2 < floor(eDamage + 145) then
                                    if not isWindingUp then
                                        if spells.E2:CastOnHitChance(enemyHero, Enums.HitChance.Low) then
                                            return
                                        end
                                    end
                                end
                            else
                                if healthPredE > 0 and healthPredE < floor(eDamage - 5) then
                                    if not isWindingUp then
                                        if spells.E:CastOnHitChance(enemyHero, Enums.HitChance.Low) then
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

    if OriUtils.CanCastSpell(slots.R, "ks.useR") then
        local allyHeroesR = ObjManager.GetNearby("ally", "heroes")
        local rTargets = spells.R:GetTargets()
        local isWindingUp = Orbwalker.IsWindingUp()
        for iKSAR, objKSAR in ipairs(allyHeroesR) do
            local ally = objKSAR.AsHero
            if not ally.IsMe and not ally.IsDead then
                if rTargets then
                    for iKS, objKS in ipairs(rTargets) do
                        local enemyHero = objKS.AsHero
                        local rDamage = Shyvana.GetDamage(enemyHero, slots.R)
                        local healthPredR = spells.R:GetHealthPred(objKS)
                        if OriUtils.MGet("ks.rWL." .. enemyHero.CharName, true) then
                            if healthPredR > 0 and healthPredR < floor(rDamage - 50) then
                                if not isWindingUp then
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

function Shyvana.DrakeSteal()
    if OriUtils.CanCastSpell(slots.Q, "steal.useQ") then 
        local heroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        if heroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.Q.Range) then
                    local qDamage = Shyvana.GetDamage(minion, slots.Q)
                    local healthPredDrakeQ = spells.Q:GetHealthPred(minion)
                    if minion.IsDragon then
                        if healthPredDrakeQ > 0 and healthPredDrakeQ < floor(qDamage - 20) then
                            if spells.Q:Cast() then
                                return
                            end
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "steal.useE") then 
        local heroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        local isMassive = Shyvana.IsMassive()
        if heroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.E.Range) then
                    local eDamage = Shyvana.GetDamage(minion, slots.E)
                    local healthPredDrakeE = spells.E:GetHealthPred(minion)
                    if minion.IsDragon then
                        if healthPredDrakeE > 0 and healthPredDrakeE < floor(eDamage - 20) then
                            if isMassive then
                                if spells.E2:CastOnHitChance(minion, Enums.HitChance.Low) then
                                    return
                                end
                            else
                                if spells.E:CastOnHitChance(minion, Enums.HitChance.Low) then
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

function Shyvana.BaronSteal()
    if OriUtils.CanCastSpell(slots.Q, "steal.useQ") then 
        local heroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        if heroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.Q.Range) then
                    local qDamage = Shyvana.GetDamage(minion, slots.Q)
                    local healthPredBaronQ = spells.Q:GetHealthPred(minion)
                    if minion.IsBaron then
                        if healthPredBaronQ > 0 and healthPredBaronQ < floor(qDamage - 20) then
                            if spells.Q:Cast() then
                                return
                            end
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "steal.useE") then 
        local heroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        local isMassive = Shyvana.IsMassive()
        if heroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.E.Range) then
                    local eDamage = Shyvana.GetDamage(minion, slots.E)
                    local healthPredBaronE = spells.E:GetHealthPred(minion)
                    if minion.IsBaron then
                        if healthPredBaronE > 0 and healthPredBaronE < floor(eDamage - 20) then
                            if isMassive then
                                if spells.E2:CastOnHitChance(minion, Enums.HitChance.Low) then
                                    return
                                end
                            else
                                if spells.E:CastOnHitChance(minion, Enums.HitChance.Low) then
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

    if OriUtils.CanCastSpell(slots.R, "combo.useR") then
        local rTargets = spells.R:GetTargets()
        local rTargetpositions = {}
        local rAmountsM = OriUtils.MGet("combo.useR.minEnemies")
        local PlayerHP = Player.HealthPercent * 100
        local hcR = OriUtils.MGet("hc.R") / 100
        local rHPM = OriUtils.MGet("combo.rHP")
        if PlayerHP >= rHPM then
            for i, obj in ipairs(rTargets) do
                local pred = spells.R:GetPrediction(obj)
                if pred and pred.HitChance >= hcR then
                    table.insert(rTargetpositions, pred.TargetPosition)
                end
            end
            local bestPos, numberOfHits = Geometry.BestCoveringRectangle(rTargetpositions, Player.Position, spells.R.Radius * 2)
            if numberOfHits >= rAmountsM then
                if spells.R:Cast(bestPos) then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.Q, "combo.useQ") then
        local qTarget = spells.Q:GetTarget()
        local q2Target = spells.Q2:GetTarget()
        local isMassive = Shyvana.IsMassive()
        if isMassive then
            if q2Target then
                if spells.Q2:Cast() then
                    return
                end
            end
        else
            if qTarget then
                if spells.Q:Cast() then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "combo.useW") then
        local wRange = OriUtils.MGet("combo.wRange")
        local wTarget = TS:GetTarget(wRange, false)
        if wTarget then
            if spells.W:Cast() then
                return
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "combo.useE") then
        local isWindingUp = Orbwalker.IsWindingUp()
        if Shyvana.IsMassive() then
            local e2Target = spells.E2:GetTarget()
            if e2Target and not isWindingUp then
                if spells.E2:CastOnHitChance(e2Target, OriUtils.MGet("hc.E2") / 100) then
                    return
                end
            end
        else
            local eTarget = spells.E:GetTarget()
            if eTarget and not isWindingUp then
                if spells.E:CastOnHitChance(eTarget, OriUtils.MGet("hc.E") / 100) then
                    return
                end
            end
        end
    end
end

function combatVariants.Harass()
    if OriUtils.CanCastSpell(slots.E, "harass.useE") then
        local isWindingUp = Orbwalker.IsWindingUp()
        if Shyvana.IsMassive() then
            local e2Target = spells.E2:GetTarget()
            if e2Target and not isWindingUp then
                if spells.E2:CastOnHitChance(e2Target, OriUtils.MGet("hc.E2") / 100) then
                    return
                end
            end
        else
            local eTarget = spells.E:GetTarget()
            if eTarget and not isWindingUp then
                if spells.E:CastOnHitChance(eTarget, OriUtils.MGet("hc.E") / 100) then
                    return
                end
            end
        end
    end
end

function combatVariants.Waveclear()

    if OriUtils.CanCastSpell(slots.Q, "jglclear.useQ") then
        local jglminionsQ = ObjManager.GetNearby("neutral", "minions")
        local isWindingUp = Orbwalker.IsWindingUp()
        local qDrake = OriUtils.MGet("jgl.qDrake")
        for iJGLQ, objJGLQ in ipairs(jglminionsQ) do
            if OriUtils.IsValidTarget(objJGLQ, spells.Q.Range) then
                local minionName = objJGLQ.CharName
                if OriUtils.MGet("jgl.qWL." .. minionName, true) or objJGLQ.IsDragon and qDrake then
                    local aaDamage = Orbwalker.GetAutoAttackDamage(objJGLQ)
                    if objJGLQ.Health > (aaDamage * 2) then
                        if not isWindingUp then
                            if spells.Q:Cast() then
                                return
                            end
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "jglclear.useW") then
        local jglminionsW = ObjManager.GetNearby("neutral", "minions")
        local isWindingUp = Orbwalker.IsWindingUp()
        local wDrake = OriUtils.MGet("jgl.wDrake")
        for iJGLW, objJGLW in ipairs(jglminionsW) do
            if OriUtils.IsValidTarget(objJGLW, spells.W.Range) then
                local minionName = objJGLW.CharName
                if OriUtils.MGet("jgl.wWL." .. minionName, true) or objJGLW.IsDragon and wDrake then
                    local aaDamage = Orbwalker.GetAutoAttackDamage(objJGLW)
                    if objJGLW.Health > (aaDamage * 2) then
                        if not isWindingUp then
                            if spells.W:Cast() then
                                return
                            end
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "jglclear.useE") then
        local jglminionsE = ObjManager.GetNearby("neutral", "minions")
        local minionsPositions = {}
        local eDrake = OriUtils.MGet("jgl.eDrake")
        local isMassive = Shyvana.IsMassive()

        for iJGLE, objJGLE in ipairs(jglminionsE) do
            local minion = objJGLE.AsMinion
            local minionName = objJGLE.CharName
            if OriUtils.IsValidTarget(objJGLE, spells.E.Range) then
                if OriUtils.MGet("jgl.eWL." .. minionName, true) or objJGLE.IsDragon and eDrake then
                    insert(minionsPositions, minion.Position)
                end
            end
        end
        if isMassive then
            local bestPos, numberOfHits = Geometry.BestCoveringCircle(minionsPositions, spells.E.Radius)
            if numberOfHits >= 1 then
                if spells.E2:Cast(bestPos) then
                    return
                end
            end
        else
            local bestPos, numberOfHits = Geometry.BestCoveringRectangle(minionsPositions, Player.Position, spells.E.Radius * 2)
            if numberOfHits >= 1 then
                if spells.E:Cast(bestPos) then
                    return
                end
            end
        end
    end


    if OriUtils.MGet("clear.enemiesAround") and TS:GetTarget(1800) and not Orbwalker.IsFastClearEnabled() then
        return
    end

    if OriUtils.CanCastSpell(slots.Q, "clear.useQ") then
        local minionsQ = ObjManager.GetNearby("enemy", "minions")
        local isFastClear = Orbwalker.IsFastClearEnabled()
        local isWindingUp = Orbwalker.IsWindingUp()
        local qMenuM = OriUtils.MGet("clear.qMenu")
        for iclearQ, objclearQ in ipairs(minionsQ) do
            local minion = objclearQ.AsMinion
            if OriUtils.IsValidTarget(objclearQ, spells.Q.Range) then
                if isFastClear then
                    if not isWindingUp then
                        if spells.Q:Cast() then
                            return
                        end
                    end
                else
                    if qMenuM == 0 then
                        if minion.IsSiegeMinion and not isWindingUp then
                            local healthPred = spells.Q:GetHealthPred(minion)
                            local qDamage = Shyvana.GetDamage(minion, slots.Q)
                            local q2Damage = Shyvana.GetQ2Damage(minion)
                            if healthPred > 0 and healthPred < floor(qDamage) then
                                if spells.Q:Cast() then
                                    return
                                end
                            end
                        end
                    else
                        if not isWindingUp then
                            local healthPred = spells.Q:GetHealthPred(minion)
                            local qDamage = Shyvana.GetDamage(minion, slots.Q)
                            local q2Damage = Shyvana.GetQ2Damage(minion)
                            if healthPred > 0 and healthPred < floor(qDamage + q2Damage) then
                                if spells.Q:Cast() then
                                    return
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "clear.useW") then
        local minionsW = ObjManager.GetNearby("enemy", "minions")
        local isFastClear = Orbwalker.IsFastClearEnabled()

        for iclearW, objclearW in ipairs(minionsW) do
            local minion = objclearW.AsMinion
            if OriUtils.IsValidTarget(objclearW, spells.W.Range) then
                if isFastClear then
                    if spells.W:Cast() then
                        return
                    end
                end
            end
        end
    end


    if OriUtils.CanCastSpell(slots.E, "clear.useE") then
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

        local eMinions = OriUtils.MGet("clear.eMinions")
        if Orbwalker.IsFastClearEnabled() then
            if numberOfHits >= 1 then
                if spells.E:Cast(bestPos) then
                    return
                end
            end
        else
            if numberOfHits >= eMinions then
                if spells.E:Cast(bestPos) then
                    return
                end
            end
        end
    end
end

function combatVariants.Lasthit()
end

function combatVariants.Flee()
    if OriUtils.CanCastSpell(slots.W, "misc.fleeW") then
        if spells.W:Cast() then
            return
        end
    end
end

print(" |> Welcome - " .. scriptName .. " by " .. scriptCreator .. " loaded! <|")
function events.OnTick()
    if not OriUtils.ShouldRunLogic() then
        return
    end
    local modeToExecute = combatVariants[Orbwalker.GetMode()]
    if modeToExecute then
        modeToExecute()
    end

    Shyvana.forceR()
    Shyvana.KS()
    Shyvana.BaronSteal()
    Shyvana.DrakeSteal()
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
end

function events.OnDrawDamage(target, dmgList)
    if not OriUtils.MGet("draw.comboDamage") then
        return
    end

    local damageToDeal = 0
    local damageToDeal2 = 0

    if OriUtils.CanCastSpell(slots.Q, "combo.useQ") then
        damageToDeal = damageToDeal + Shyvana.GetDamage(target, slots.Q)
        damageToDeal = damageToDeal + Shyvana.GetQ2Damage(target)
    end

    if OriUtils.CanCastSpell(slots.W, "combo.useW") then
        damageToDeal = damageToDeal + Shyvana.GetDamage(target, slots.W)
    end

    if OriUtils.CanCastSpell(slots.E, "combo.useE") then
        if Shyvana.IsMassive() then
            damageToDeal = damageToDeal + Shyvana.GetDamage(target, slots.E)
            damageToDeal2 = damageToDeal2 + Shyvana.GetE2Damage(target)
        else
            damageToDeal = damageToDeal + Shyvana.GetDamage(target, slots.E)
        end
    end

    if OriUtils.CanCastSpell(slots.R, "combo.useR") then
        damageToDeal = damageToDeal + Shyvana.GetDamage(target, slots.R)
    end

    insert(dmgList, damageToDeal)
end

function Shyvana.RegisterEvents()
    for eventName, eventId in pairs(Enums.Events) do
        if events[eventName] then
            EventManager.RegisterCallback(eventId, events[eventName])
        end
    end
end

function Shyvana.InitMenu()
    local function QHeader()
        Menu.ColoredText(drawData[1].displayText, scriptColor, true)
    end

    local function WHeader()
        Menu.ColoredText(drawData[3].displayText, scriptColor, true)
    end

    local function EHeader()
        Menu.ColoredText(drawData[4].displayText, scriptColor, true)
    end
    local function EHeaderHit()
        Menu.ColoredText(drawData[4].displayText .. " Hitchance", scriptColor, true)
    end

    local function E2HeaderHit()
        Menu.ColoredText(drawData[5].displayText .. " Dragon Hitchance", scriptColor, true)
    end

    local function RHeader()
        Menu.ColoredText(drawData[6].displayText, scriptColor, true)
    end
    local function RHeaderHit()
        Menu.ColoredText(drawData[6].displayText .. " Hitchance", scriptColor, true)
    end

    local function ShyvanaMenu()
        Menu.Text("" .. ASCIIArt, true)
        Menu.Text("" .. ASCIIArt2, true)
        Menu.Text("" .. ASCIIArt3, true)
        Menu.Text("" .. ASCIIArt4, true)
        Menu.Text("" .. ASCIIArt5, true)
        Menu.Text("" .. ASCIIArt6, true)
        Menu.Text("" .. ASCIIArt7, true)
        Menu.Text("" .. ASCIIArt8, true)
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
        
        if Menu.Checkbox("Shyvana.Updates000", "Don't show updates") == false then
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. scriptLastUpdated .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesVersion, 0XFFFF00FF, true)
            Menu.Text("- Initial Release of AuShyvana", true)
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. patchNotesPrevUpdate .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesPreVersion, 0XFFFF00FF, true)
            Menu.Text("- XXXXXXXXXXXXXXXX", true)
        end

        Menu.Separator()

        Menu.NewTree("Shyvana.comboMenu", "Combo Settings", function()
            Menu.ColumnLayout("Shyvana.comboMenu.QE", "Shyvana.comboMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Shyvana.combo.useQ", "Enable Q", true)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Shyvana.combo.useE", "Enable E", true)
            end)

            Menu.ColumnLayout("Shyvana.comboMenu.WR", "Shyvana.comboMenu.WR", 2, true, function()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Shyvana.combo.useW", "Enable W", true)
                Menu.Slider("Shyvana.combo.wRange", "W Range", 375, 320, 800, 1)
                Menu.NextColumn()
                RHeader()
                Menu.Checkbox("Shyvana.combo.useR", "Enable R", true)
                Menu.Slider("Shyvana.combo.rHP", "Don't use if HP < %", 20, 1, 100, 1)
                Menu.Slider("Shyvana.combo.useR.minEnemies", "Use if X enemy(s)", 3, 1, 5)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Shyvana.harassMenu", "Harass Settings", function()
            Menu.ColumnLayout("Shyvana.harassMenu.QE", "Shyvana.harassMenu.QE", 1, true, function()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Shyvana.harass.useE", "Enable E", true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Shyvana.clearMenu", "Clear Settings", function()
            Menu.NewTree("Shyvana.waveMenu", "Waveclear", function()
                Menu.Checkbox("Shyvana.clear.enemiesAround", "Don't clear while enemies around", true)
                Menu.Separator()
                Menu.ColoredText("Holding LMB (Fast Clear) will ignore Minioncount and enemies around\nFast Clear is required for W", scriptColor, true)
                Menu.Checkbox("Shyvana.clear.useQ", "Use Q", false)
                Menu.Dropdown("Shyvana.clear.qMenu", "Lasthit", 0, {"Canon", "All Minion"})
                Menu.Checkbox("Shyvana.clear.useW", "Enable W", true)
                Menu.Checkbox("Shyvana.clear.useE", "Enable E", true)
                Menu.Slider("Shyvana.clear.eMinions", "if X Minions", 5, 1, 6, 1)
            end)
            Menu.NewTree("Shyvana.jglMenu", "Jungleclear", function()
                Menu.Checkbox("Shyvana.jglclear.useQ", "Use Q", true)
                Menu.ColumnLayout("Shyvana.jglclear.qWhitelist", "Shyvana.jglclear.qWhitelist", 3, true, function()
                    Menu.Indent(function()
                        Menu.NewTree("Shyvana.jglclear.qlist", "Jungle Camps 1", function()
                            for i, v in ipairs(jungleCamps) do
                                Menu.Checkbox("Shyvana.jgl.qWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Shyvana.jglclear.qlist2", "Jungle Camps 2", function()
                            for i, v in ipairs(jungleCamps2) do
                                Menu.Checkbox("Shyvana.jgl.qWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Shyvana.jglclear.qlist3", "Jungle Camps 3", function()
                            for i, v in ipairs(jungleCamps3) do
                                Menu.Checkbox("Shyvana.jgl.qWL." .. v.name, v.dName, v.default)
                            end
                            Menu.Checkbox("Shyvana.jgl.qDrake", "Other Drakes", true)
                        end)
                    end)
                end)
                Menu.Separator()
                Menu.Checkbox("Shyvana.jglclear.useW", "Use W", true)
                Menu.ColumnLayout("Shyvana.jglclear.wWhitelist", "Shyvana.jglclear.wWhitelist", 3, true, function()
                    Menu.Indent(function()
                        Menu.NewTree("Shyvana.jglclear.wlist", "Jungle Camps 1", function()
                            for i, v in ipairs(jungleCamps) do
                                Menu.Checkbox("Shyvana.jgl.wWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Shyvana.jglclear.wlist2", "Jungle Camps 2", function()
                            for i, v in ipairs(jungleCamps2) do
                                Menu.Checkbox("Shyvana.jgl.wWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Shyvana.jglclear.wlist3", "Jungle Camps 3", function()
                            for i, v in ipairs(jungleCamps3) do
                                Menu.Checkbox("Shyvana.jgl.wWL." .. v.name, v.dName, v.default)
                            end
                            Menu.Checkbox("Shyvana.jgl.wDrake", "Other Drakes", true)
                        end)
                    end)
                end)
                Menu.Separator()
                Menu.Checkbox("Shyvana.jglclear.useE", "Use E", true)
                Menu.ColumnLayout("Shyvana.jglclear.eWhitelist", "Shyvana.jglclear.eWhitelist", 3, true, function()
                    Menu.Indent(function()
                        Menu.NewTree("Shyvana.jglclear.elist", "Jungle Camps 1", function()
                            for i, v in ipairs(jungleCamps) do
                                Menu.Checkbox("Shyvana.jgl.eWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Shyvana.jglclear.elist2", "Jungle Camps 2", function()
                            for i, v in ipairs(jungleCamps2) do
                                Menu.Checkbox("Shyvana.jgl.eWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Shyvana.jglclear.elist3", "Jungle Camps 3", function()
                            for i, v in ipairs(jungleCamps3) do
                                Menu.Checkbox("Shyvana.jgl.eWL." .. v.name, v.dName, v.default)
                            end
                            Menu.Checkbox("Shyvana.jgl.eDrake", "Other Drakes", true)
                        end)
                    end)
                end)
            end)
        end)
        
        Menu.Separator()

        Menu.NewTree("Shyvana.stealMenu", "Steal Settings", function()
            Menu.NewTree("Shyvana.ksMenu", "Killsteal", function()
                Menu.Checkbox("Shyvana.ks.useQ", "Killsteal with Q", true)
                local cbResult = OriUtils.MGet("ks.useQ")
                if cbResult then
                    Menu.Indent(function()
                        Menu.NewTree("Shyvana.ksMenu.qWhitelist", "KS Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Shyvana.ks.qWL." .. heroName, "Q KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Shyvana.ks.useE", "Killsteal with E", true)
                local cbResult2 = OriUtils.MGet("ks.useE")
                if cbResult2 then
                    Menu.Indent(function()
                        Menu.NewTree("Shyvana.ksMenu.eWhitelist", "KS E Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Shyvana.ks.eWL." .. heroName, "E KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Shyvana.ks.useR", "Killsteal with R", false)
                local cbResult3 = OriUtils.MGet("ks.useR")
                if cbResult3 then
                    Menu.Indent(function()
                        Menu.NewTree("Shyvana.ksMenu.rWhitelist", "KS R Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Shyvana.ks.rWL." .. heroName, "R KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
            end)
            Menu.NewTree("Shyvana.jglstealMenu", "Junglesteal (Drake/Baron) | BETA", function()
                Menu.Checkbox("Shyvana.steal.useQ", "Junglesteal with Q", true)
                Menu.Checkbox("Shyvana.steal.useE", "Junglesteal with E", true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Shyvana.miscMenu", "Misc Settings", function()
            Menu.ColumnLayout("Shyvana.miscMenu.R", "Shyvana.miscMenu.R", 2, true, function()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Shyvana.misc.fleeW", "Use W for Flee", true)
                Menu.NextColumn()
                Menu.Text("")
                RHeader()
                Menu.Keybind("Shyvana.misc.forceR", "Force R", string.byte("T"), false, false, true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Shyvana.hcMenu", "Hitchance Settings", function()
            Menu.ColumnLayout("Shyvana.hcMenu.E", "Shyvana.hcMenu.E", 2, true, function()
                Menu.Text("")
                EHeaderHit()
                Menu.Text("")
                Menu.Slider("Shyvana.hc.E", "%", 30, 1, 100, 1)
                Menu.NextColumn()
                Menu.Text("")
                E2HeaderHit()
                Menu.Text("")
                Menu.Slider("Shyvana.hc.E2", "%", 15, 1, 100, 1)
            end)
            Menu.Separator()
            Menu.ColumnLayout("Shyvana.hcMenu.R", "Shyvana.hcMenu.R", 1, true, function()
                Menu.Text("")
                RHeaderHit()
                Menu.Text("")
                Menu.Slider("Shyvana.hc.R", "%", 20, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Shyvana.drawMenu", "Draw Settings", function()
            OriUtils.AddDrawMenu(drawData)
        end)
    end

    Menu.RegisterMenu(scriptName, scriptName, ShyvanaMenu)
end

function OnLoad()
    Shyvana.InitMenu()
    
    Shyvana.RegisterEvents()
    return true
end
