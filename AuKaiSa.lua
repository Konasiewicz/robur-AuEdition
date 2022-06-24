if Player.CharName ~= "Kaisa" then return end

local scriptName = "AuKaiSa"
local scriptCreator = "AURUM"
local credits = "Orietto"
local patchNotesPrevUpdate = "03/04/2022"
local patchNotesPreVersion = "1.0.1"
local patchNotesVersion, scriptVersionUpdater = "1.4.2", "1.4.2"
local scriptVersion = scriptVersionUpdater
local scriptLastUpdated = "05/07/2022"
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

SDK.AutoUpdate("https://raw.githubusercontent.com/roburAURUM/robur-AuEdition/main/AuKaisa.lua", scriptVersionUpdater)

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
        Base = {40, 55, 70, 85, 100},
        BonusAD = 0.5,
        TotalAP = 0.25,
        Type = dmgTypes.Physical
    },
    W = {
        Base = {30, 55, 80, 105, 130},
        TotalAP = 0.7,
        TotalAD = 1.3,
        Type = dmgTypes.Magical
    },
}

local spells = {
    Q = Spell.Active({
        Slot = slots.Q,
        Delay = 0.0,
        Speed = 1800,
        Range = 600,
        Collisions = {Windwall = true}
    }),
    W = Spell.Skillshot({
        Slot = slots.W,
        Delay = 0.4,
        Speed = 1750,
        Range = 3000,
        Radius = 200 / 2,
        Type = "Linear",
        Collisions = {Windwall = true, Heroes = true, Minions = true}
    }),
    E = Spell.Active({
        Slot = slots.E,
    }),
    R = Spell.Skillshot({
        Slot = slots.R,
        Delay = 0.0,
        Speed = huge,
        Range = 1500,
        Radius = 525,
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

local jungleCamps = {

    [1] = {name = "SRU_Blue", dName = "Blue Buff", default = true},
    [2] = {name = "SRU_Gromp", dName = "Gromp", default = true},
    [3] = {name = "SRU_Murkwolf", dName = "Big Wolf", default = true}, -- Big Wolf
    [4] = {name = "SRU_MurkwolfMini", dName = "Small Wolf", default = false}, -- Small Wolf
}

local jungleCamps2 = {

    [1] = {name = "SRU_Red", dName = "Red Buff", default = true},
    [2] = {name = "SRU_Razorbeak", dName = "Big Raptor", default = true}, -- Big Raptor
    [3] = {name = "SRU_RazorbeakMini", dName = "Small Raptor", default = false}, -- Big Raptor
    [4] = {name = "SRU_Krug", dName = "Big Krug", default = true}, -- Big Krug
    [5] = {name = "SRU_KrugMini", dName = "Medium Krug", default = true}, -- Medium Krug
}

local jungleCamps3 = {
    [2] = {name = "SRU_RiftHerald", dName = "Rift Herald", default = true},
    [1] = {name = "SRU_Baron", dName = "Baron Nashor", default = true},
    [3] = {name = "SRU_Dragon_Elder", dName = "Elder Drake", default = true},
    [4] = {name = "Sru_Crab", dName = "Scuttle Crab", default = true},
    
}

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

    for slot, Kaisaold in pairs(data) do
        if curTime < lastCastT[slot] + Kaisaold then
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
    Menu.Checkbox("Kaisa.Draw.W.Minimap",   "Draw [W] Void Seeker on Minimap")
    Menu.Indent(function()
        Menu.ColorPicker("Draw.W.ColorMinimap", "Color", 0xFFFF00FF)
    end)
    Menu.Checkbox("Kaisa.Draw.R.Minimap",   "Draw [R] Killer Instinct on Minimap")
    Menu.Indent(function()
        Menu.ColorPicker("Draw.R.ColorMinimap", "Color", 0x00FF00FF)
    end)
    Menu.Separator()
    Menu.Checkbox(cacheName .. ".draw." .. "comboDamage", "Draw combo damage on healthbar", true)
    Menu.Checkbox("Kaisa.drawMenu.AlwaysDraw", "Always show Drawings", false)

    Menu.Checkbox("Kaisa.drawMenu.EnableAA", "Show AA Damage", false)
    Menu.Slider("Kaisa.drawMenu.AASlider", "AA's", 1, 1, 10, 1)
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
    {slot = slots.Q, id = "Q", displayText = "[Q] Icathian Rain", range = spells.Q.Range},
    {slot = slots.W, id = "W", displayText = "[W] Void Seeker",  range = function () return OriUtils.MGet("misc.WRange") end},
    {slot = slots.E, id = "E", displayText = "[E] Supercharge", range = function () return OriUtils.MGet("combo.ESlider") end},
    {slot = slots.R, id = "R", displayText = "[R] Killer Instinct", range = function() return spells.R.Range end}
}

local ASCIIArt = "                 _  __     _  _____        "
local ASCIIArt1 = "      /\\        | |/ /    (_)/ ____|       "
local ASCIIArt2 = "     /  \\  _   _| ' / __ _ _| (___   __ _  "
local ASCIIArt3 = "    / /\\ \\| | | |  < / _` | |\\___ \\ / _` | "
local ASCIIArt4 = "   / ____ \\ |_| | . \\ (_| | |____) | (_| | "
local ASCIIArt5 = "  /_/    \\_\\__,_|_|\\_\\__,_|_|_____/ \\__,_| "

local Kaisa = {}

Kaisa.baseAADamage = Player.BaseAttackDamage
Kaisa.AD = Kaisa.baseAADamage + Player.FlatPhysicalDamageMod

local slotToDamageTable = {
    [slots.Q] = damages.Q,
    [slots.W] = damages.W,
}

---@param target AIBaseClient
---@param slot slut
function Kaisa.GetDamage(target, slot)
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

function Kaisa.KS()
    if OriUtils.CanCastSpell(slots.Q, "ks.useQ") then
        local allyHeroes = ObjManager.GetNearby("ally", "heroes")
        local qReady = OriUtils.CanCastSpell(slots.Q, "ks.useQ")
        local qTargets = spells.Q:GetTargets()
        local IsWindingUp = Orbwalker.IsWindingUp()
        local qCases = Kaisa.qCases()
        local qEvolved = Kaisa.QEvolved()
        for iKSA, objKSA in ipairs(allyHeroes) do
            local ally = objKSA.AsHero
            if not ally.IsMe and not ally.IsDead then
                if qTargets then
                    for iKS, objKS in ipairs(qTargets) do
                        local enemyHero = objKS.AsHero
                        local qDamage = Kaisa.GetDamage(enemyHero, slots.Q)
                        local healthPredQ = spells.Q:GetHealthPred(objKS)
                        if OriUtils.MGet("ks.qWL." .. enemyHero.CharName, true) then
                            if qEvolved then
                                if qCases == 1 then
                                    if healthPredQ > 0 and healthPredQ < floor(qDamage + ((qDamage / 4) * 11)) then
                                        if not IsWindingUp then
                                            if spells.Q:Cast() then
                                                return
                                            end
                                        end
                                    end
                                elseif qCases == 2 then
                                    if healthPredQ > 0 and healthPredQ < floor(qDamage + ((qDamage / 4) * 5)) then
                                        if not IsWindingUp then
                                            if spells.Q:Cast() then
                                                return
                                            end
                                        end
                                    end
                                elseif qCases == 3 then
                                    if healthPredQ > 0 and healthPredQ < floor(qDamage + ((qDamage / 4) * 3)) then
                                        if not IsWindingUp then
                                            if spells.Q:Cast() then
                                                return
                                            end
                                        end
                                    end
                                elseif qCases == 4 then
                                    if healthPredQ > 0 and healthPredQ < floor(qDamage + ((qDamage / 4) * 2)) then
                                        if not IsWindingUp then
                                            if spells.Q:Cast() then
                                                return
                                            end
                                        end
                                    end
                                elseif qCases == 5 then
                                    if healthPredQ > 0 and healthPredQ < floor(qDamage + ((qDamage / 4) * 1)) then
                                        if not IsWindingUp then
                                            if spells.Q:Cast() then
                                                return
                                            end
                                        end
                                    end
                                end
                            else
                                if qCases == 1 then
                                    if healthPredQ > 0 and healthPredQ < floor(qDamage + ((qDamage / 4) * 5)) then
                                        if not IsWindingUp then
                                            if spells.Q:Cast() then
                                                return
                                            end
                                        end
                                    end
                                elseif qCases == 2 then
                                    if healthPredQ > 0 and healthPredQ < floor(qDamage + ((qDamage / 4) * 2)) then
                                        if not IsWindingUp then
                                            if spells.Q:Cast() then
                                                return
                                            end
                                        end
                                    end
                                elseif qCases == 3 then
                                    if healthPredQ > 0 and healthPredQ < floor(qDamage + ((qDamage / 4) * 1)) then
                                        if not IsWindingUp then
                                            if spells.Q:Cast() then
                                                return
                                            end
                                        end
                                    end
                                elseif qCases == 4 or qCases == 5 then
                                    if healthPredQ > 0 and healthPredQ < floor(qDamage) then
                                        if not IsWindingUp then
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
    end

    if OriUtils.CanCastSpell(slots.W, "ks.useW") then
        local allyHeroes = ObjManager.GetNearby("ally", "heroes")
        local wTargets = spells.W:GetTargets()
        local wEvolved = Kaisa.WEvolved()
        local IsWindingUp = Orbwalker.IsWindingUp()
        for iKSA, objKSA in ipairs(allyHeroes) do
            local ally = objKSA.AsHero
            if not ally.IsMe and not ally.IsDead then
                if wTargets then
                    for iKS, objKS in ipairs(wTargets) do
                        local target = objKS.AsHero
                        local wDamage = Kaisa.GetDamage(target, slots.W)
                        local healthPredW = spells.W:GetHealthPred(objKS)
                        local missingHP = target.MaxHealth - target.Health
                        local passiveDamage = (0.15 + 0.025) * missingHP
                        if OriUtils.MGet("ks.wWL." .. target.CharName, true) then
                            if target:GetBuff("kaisapassivemarker") and (target:GetBuff("kaisapassivemarker").Count >= 3 or wEvolved and target:GetBuff("kaisapassivemarker").Count >= 2) then
                                if healthPredW > 0 and healthPredW < floor(wDamage + passiveDamage) then
                                    if not IsWindingUp then
                                        if spells.W:CastOnHitChance(target, Enums.HitChance.Low) then
                                            return
                                        end
                                    end
                                end
                            else
                                if healthPredW > 0 and healthPredW < floor(wDamage) then
                                    if not IsWindingUp then
                                        if spells.W:CastOnHitChance(target, Enums.HitChance.Low) then
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

function Kaisa.DrakeSteal()
    if OriUtils.CanCastSpell(slots.Q, "steal.useQ") then 
        local heroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        local qCases = Kaisa.qCases()
        local qEvolved = Kaisa.QEvolved()
        local IsWindingUp = Orbwalker.IsWindingUp()
        if heroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.Q.Range) then
                    local qDamage = Kaisa.GetDamage(minion, slots.Q)
                    local healthPredDrakeQ = spells.Q:GetHealthPred(minion)
                    if minion.IsDragon then
                        if qEvolved then
                            if qCases == 0 then
                                if healthPredDrakeQ > 0 and healthPredDrakeQ < floor(qDamage + ((qDamage / 4) * 11)) then
                                    if not IsWindingUp then
                                        if spells.Q:Cast() then
                                            return
                                        end
                                    end
                                end
                            elseif qCases == 1 then
                                if healthPredDrakeQ > 0 and healthPredDrakeQ < floor(qDamage + ((qDamage / 4) * 5)) then
                                    if not IsWindingUp then
                                        if spells.Q:Cast() then
                                            return
                                        end
                                    end
                                end
                            elseif qCases == 2 then
                                if healthPredDrakeQ > 0 and healthPredDrakeQ < floor(qDamage + ((qDamage / 4) * 3)) then
                                    if not IsWindingUp then
                                        if spells.Q:Cast() then
                                            return
                                        end
                                    end
                                end
                            elseif qCases == 3 then
                                if healthPredDrakeQ > 0 and healthPredDrakeQ < floor(qDamage + ((qDamage / 4) * 2)) then
                                    if not IsWindingUp then
                                        if spells.Q:Cast() then
                                            return
                                        end
                                    end
                                end
                            elseif qCases == 4 or qCases == 5 then
                                if healthPredDrakeQ > 0 and healthPredDrakeQ < floor(qDamage + ((qDamage / 4) * 1)) then
                                    if not IsWindingUp then
                                        if spells.Q:Cast() then
                                            return
                                        end
                                    end
                                end
                            end
                        else
                            if qCases == 0 then
                                if healthPredDrakeQ > 0 and healthPredDrakeQ < floor(qDamage + ((qDamage / 4) * 5)) then
                                    if not IsWindingUp then
                                        if spells.Q:Cast() then
                                            return
                                        end
                                    end
                                end
                            elseif qCases == 1 then
                                if healthPredDrakeQ > 0 and healthPredDrakeQ < floor(qDamage + ((qDamage / 4) * 2)) then
                                    if not IsWindingUp then
                                        if spells.Q:Cast() then
                                            return
                                        end
                                    end
                                end
                            elseif qCases == 2 or qCases == 3 or qCases == 4 then
                                if healthPredDrakeQ > 0 and healthPredDrakeQ < floor(qDamage + ((qDamage / 4) * 1)) then
                                    if not IsWindingUp then
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

    if OriUtils.CanCastSpell(slots.W, "steal.useW") then 
        local heroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        local wEvolved = Kaisa.WEvolved()
        local IsWindingUp = Orbwalker.IsWindingUp()
        if heroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.W.Range) then
                    local wDamage = Kaisa.GetDamage(minion, slots.W)
                    local healthPredDrakeW = spells.W:GetHealthPred(minion)
                    local missingHP = minion.MaxHealth - minion.Health
                    local passiveDamage = (0.15 + 0.025) * missingHP
                    if wDamage + passiveDamage > 400 then
                        wDamage = 400
                        passiveDamage = 0
                    end
                    if minion.IsDragon then
                        if minion:GetBuff("kaisapassivemarker") and (minion:GetBuff("kaisapassivemarker").Count >= 3 or wEvolved and minion:GetBuff("kaisapassivemarker").Count >= 2) then
                            if healthPredDrakeW > 0 and healthPredDrakeW < floor(wDamage + passiveDamage - 50) then
                                if not IsWindingUp then
                                    if spells.W:CastOnHitChance(minion, Enums.HitChance.Low) then
                                        return
                                    end
                                end
                            end
                        else
                            if healthPredDrakeW > 0 and healthPredDrakeW < floor(wDamage - 50) then
                                if not IsWindingUp then
                                    if spells.W:CastOnHitChance(minion, Enums.HitChance.Low) then
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

function Kaisa.BaronSteal()
    if OriUtils.CanCastSpell(slots.Q, "steal.useQ") then 
        local heroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        local qCases = Kaisa.qCases()
        local qEvolved = Kaisa.QEvolved()
        local IsWindingUp = Orbwalker.IsWindingUp()
        if heroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.Q.Range) then
                    local qDamage = Kaisa.GetDamage(minion, slots.Q)
                    local healthPredBaronQ = spells.Q:GetHealthPred(minion)
                    if minion.IsBaron then
                        if qEvolved then
                            if qCases == 0 then
                                if healthPredBaronQ > 0 and healthPredBaronQ < floor(qDamage + ((qDamage / 4) * 11)) then
                                    if not IsWindingUp then
                                        if spells.Q:Cast() then
                                            return
                                        end
                                    end
                                end
                            elseif qCases == 1 then
                                if healthPredBaronQ > 0 and healthPredBaronQ < floor(qDamage + ((qDamage / 4) * 5)) then
                                    if not IsWindingUp then
                                        if spells.Q:Cast() then
                                            return
                                        end
                                    end
                                end
                            elseif qCases == 2 then
                                if healthPredBaronQ > 0 and healthPredBaronQ < floor(qDamage + ((qDamage / 4) * 3)) then
                                    if not IsWindingUp then
                                        if spells.Q:Cast() then
                                            return
                                        end
                                    end
                                end
                            elseif qCases == 3 then
                                if healthPredBaronQ > 0 and healthPredBaronQ < floor(qDamage + ((qDamage / 4) * 2)) then
                                    if not IsWindingUp then
                                        if spells.Q:Cast() then
                                            return
                                        end
                                    end
                                end
                            elseif qCases == 4 or qCases == 5 then
                                if healthPredBaronQ > 0 and healthPredBaronQ < floor(qDamage + ((qDamage / 4) * 1)) then
                                    if not IsWindingUp then
                                        if spells.Q:Cast() then
                                            return
                                        end
                                    end
                                end
                            end
                        else
                            if qCases == 0 then
                                if healthPredBaronQ > 0 and healthPredBaronQ < floor(qDamage + ((qDamage / 4) * 5)) then
                                    if not IsWindingUp then
                                        if spells.Q:Cast() then
                                            return
                                        end
                                    end
                                end
                            elseif qCases == 1 then
                                if healthPredBaronQ > 0 and healthPredBaronQ < floor(qDamage + ((qDamage / 4) * 2)) then
                                    if not IsWindingUp then
                                        if spells.Q:Cast() then
                                            return
                                        end
                                    end
                                end
                            elseif qCases == 2 or qCases == 3 or qCases == 4 then
                                if healthPredBaronQ > 0 and healthPredBaronQ < floor(qDamage + ((qDamage / 4) * 1)) then
                                    if not IsWindingUp then
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

    if OriUtils.CanCastSpell(slots.W, "steal.useW") then 
        local heroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        local wEvolved = Kaisa.WEvolved()
        local IsWindingUp = Orbwalker.IsWindingUp()
        if heroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.W.Range) then
                    local wDamage = Kaisa.GetDamage(minion, slots.W)
                    local healthPredBaronW = spells.W:GetHealthPred(minion)
                    local missingHP = minion.MaxHealth - minion.Health
                    local passiveDamage = (0.15 + 0.025) * missingHP
                    if wDamage + passiveDamage > 400 then
                        wDamage = 400
                        passiveDamage = 0
                    end
                    if minion.IsBaron then
                        if minion:GetBuff("kaisapassivemarker") and (minion:GetBuff("kaisapassivemarker").Count >= 3 or wEvolved and minion:GetBuff("kaisapassivemarker").Count >= 2) then
                            if healthPredBaronW > 0 and healthPredBaronW < floor(wDamage + passiveDamage - 50) then
                                if not IsWindingUp then
                                    if spells.W:CastOnHitChance(minion, Enums.HitChance.Low) then
                                        return
                                    end
                                end
                            end
                        else
                            if healthPredBaronW > 0 and healthPredBaronW < floor(wDamage - 50) then
                                if not IsWindingUp then
                                    if spells.W:CastOnHitChance(minion, Enums.HitChance.Low) then
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

Kaisa.LatestR = 0

local RLevelRanges = {
    [1] = 1500,
    [2] = 2250,
    [3] = 3000
}

function Kaisa.UpdateRRange()
    local curLevel = spells.R:GetLevel()
    if curLevel ~= Kaisa.LatestR then
        spells.R.Range = RLevelRanges[curLevel]

        Kaisa.LatestR = curLevel
    end
end

function Kaisa.QEvolved()
    return Player:GetBuff("KaisaQEvolved")
end

function Kaisa.WEvolved()
    return Player:GetBuff("KaisaWEvolved")
end

function Kaisa.EEvolved()
    return Player:GetBuff("KaisaEEvolved")
end

function Kaisa.qCases()
    local count = 0

    local enemyHeroes = ObjManager.GetNearby("enemy", "heroes")
    for index, obj in ipairs(enemyHeroes) do
        local hero = obj.AsHero

        if OriUtils.IsValidTarget(hero, spells.Q.Range) then
            count = count + 1
        end        
    end

    return count
end

function Kaisa.QCount()
    local count = 0
    local myPos = Player.Position
    local enemyMinions = OriUtils.GetEnemyAndJungleMinions(spells.Q.Range, myPos)
    for index, obj in ipairs(enemyMinions) do
        if OriUtils.IsValidTarget(obj, spells.Q.Range) then
            count = count + 1    
        end 
    end

    return count
end

--[[function Kaisa.forceR()
    if OriUtils.MGet("misc.forceR") then
        local mousePos = Renderer.GetMousePos()
        Orbwalker.Orbwalk(mousePos, nil)

        if spells.R:IsReady() then
            local markedEnemyForce = ObjManager.Get("enemy", "heroes")
                ---@param objA GameObject
                ---@param objB GameObject
                local function enemyComparator(objA, objB)
                    return mousePos:Distance(objA) < mousePos:Distance(objB)
                end

            sort(markedEnemyForce, enemyComparator)
            for k, v in pairs(markedEnemyForce) do
                if OriUtils.IsValidTarget(v, spells.R.Range) then
                    local target = v.AsHero
                    if target:GetBuff("kaisapassivemarkerr") then
                        local endPos = target.ServerPos:Extended(mousePos, 525)
                        if not IsWindingUp then
                            if spells.R:Cast(endPos) then
                                return
                            end
                        end
                    end
                end
            end
        end
    end
end]]--

function Kaisa.AutoQ()
    if spells.Q:IsReady() and OriUtils.MGet("misc.autoQ.options") == 1 or OriUtils.MGet("misc.autoQ.options") == 2 then
        local qTarget = spells.Q:GetTarget()
        local IsWindingUp = Orbwalker.IsWindingUp()
        if qTarget then
            if OriUtils.MGet("misc.autoQ.options") == 2 then
                if Kaisa.QEvolved() then
                    if Kaisa.QCount() <= OriUtils.MGet("misc.autoQ.MinionsEvolved") and not IsWindingUp then
                        if spells.Q:Cast() then
                            return
                        end
                    end
                end
            elseif OriUtils.MGet("misc.autoQ.options") == 1 then
                if Kaisa.QCount() <= OriUtils.MGet("misc.autoQ.Minions") and not IsWindingUp then
                    if spells.Q:Cast() then
                        return
                    end
                end
            end
        end
    end
end

function Kaisa.WToggle()
    if spells.W:IsReady() then
        if OriUtils.MGet("misc.wToggle.options") == 0 then
            if OriUtils.MGet("misc.wToggle") then
                
                local testObj = ObjManager.Get("enemy", "heroes")
                for iWT, objWT in pairs(testObj) do
                    local hero = objWT.AsHero
                    if OriUtils.IsValidTarget(objWT, spells.W.Range) then
                        if not hero.IsDead and hero:Distance(Player) > 150 then
                            if spells.W:CastOnHitChance(hero, OriUtils.MGet("misc.wToggle.Hitchance") / 100) then
                                return
                            end
                        end
                    end
                end
            end
        else
            if OriUtils.MGet("misc.wToggle") then
                local test = OriUtils.MGet("misc.wToggle")
                local testObj = ObjManager.Get("enemy", "heroes")
                for iWT, objWT in pairs(testObj) do
                    local hero = objWT.AsHero
                    if OriUtils.IsValidTarget(objWT, spells.W.Range) then
                        if not hero.IsDead and hero:Distance(Player) > OriUtils.MGet("misc.wToggleRangeMin") and hero:Distance(Player) < OriUtils.MGet("misc.wToggleRangeMax") then
                            if spells.W:CastOnHitChance(hero, OriUtils.MGet("misc.wToggle.Hitchance") / 100) then
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
        local mousePos = Renderer.GetMousePos()
        local markedEnemy = ObjManager.Get("enemy", "heroes")
        local rEnemyHP = OriUtils.MGet("combo.rEnemyHP")
        local rSelfHP = OriUtils.MGet("combo.rSelfHP")
        local IsWindingUp = Orbwalker.IsWindingUp()
        local rOption0 = OriUtils.MGet("combo.useR.options") == 0
        local rOption1 = OriUtils.MGet("combo.useR.options") == 1
        ---@param objA GameObject
        ---@param objB GameObject
        local function enemyComparator(objA, objB)
            return mousePos:Distance(objA) < mousePos:Distance(objB)
        end
    sort(markedEnemy, enemyComparator)
        for kR, vR in pairs(markedEnemy) do
            if OriUtils.IsValidTarget(vR, 650) then
                local target = vR.AsHero
                if target:GetBuff("kaisapassivemarkerr") then
                    if target.HealthPercent * 100 >= rEnemyHP and Player.HealthPercent * 100 <= rSelfHP then
                        --if Player.ManaPercent * 100 < 100 then
                            local endPos = target.ServerPos:Extended(mousePos, 525)
                            if not IsWindingUp then
                                if rOption1 then
                                    if spells.R:Cast(endPos) then
                                        return
                                    end
                                else
                                    if spells.R:Cast(Player.Position) then
                                        return
                                    end
                                end
                            end
                        --end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "combo.useW") then
        if Player.ManaPercent * 100 >= OriUtils.MGet("combo.wManaSlider") then
            local enemiesW = TS:GetTargets(1500)
            local IsWindingUp = Orbwalker.IsWindingUp()
            for i, obj in ipairs(enemiesW) do
                local enemy = obj.AsHero
                local passiveStack = enemy:GetBuff("kaisapassivemarker") and enemy:GetBuff("kaisapassivemarker").Count or 0
                if passiveStack >= OriUtils.MGet("combo.wPassiveCount") then
                    local wRange = OriUtils.MGet("misc.WRange")
                    local wTarget = TS:GetTarget(wRange, false)
                    if wTarget and not IsWindingUp then
                        if spells.W:CastOnHitChance(enemy, OriUtils.MGet("hc.W") / 100) then
                            return
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.Q, "combo.useQ") then
        local qTarget = spells.Q:GetTarget()
        local IsWindingUp = Orbwalker.IsWindingUp()
        if OriUtils.MGet("combo.qMinionCountDouble") and Kaisa.QEvolved() then
            if qTarget and Kaisa.QCount() < (OriUtils.MGet("combo.qMinionCount") * 2) then
                if not IsWindingUp then
                    if spells.Q:Cast() then
                        return
                    end
                end
            end
        else
            if qTarget and Kaisa.QCount() < OriUtils.MGet("combo.qMinionCount") then
                if not IsWindingUp then
                    if spells.Q:Cast() then
                        return
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "combo.useE") then
        local eRange = Orbwalker.GetTrueAutoAttackRange(Player)
        local eTarget = TS:GetTarget(eRange - 30)
        local IsWindingUp = Orbwalker.IsWindingUp()
        if OriUtils.MGet("combo.useE.options") == 1 then
            if eTarget then
                if not IsWindingUp then
                    if spells.E:Cast() then
                        return
                    end
                end
            end
        elseif OriUtils.MGet("combo.useE.options") == 2 then
            if Kaisa.EEvolved() then
                if eTarget then
                    if not IsWindingUp then
                        if spells.E:Cast() then
                            return
                        end
                    end
                end
            end
        end                
    end
    
    if OriUtils.MGet("combo.eEngage.options") == 1 then
        local eRange = OriUtils.MGet("combo.ESlider")
        local engangeEnemyE1 = ObjManager.GetNearby("enemy", "heroes")
        local IsWindingUp = Orbwalker.IsWindingUp()
        for iE, objE in ipairs(engangeEnemyE1) do
            local target = objE.AsHero
            if OriUtils.IsValidTarget(target, eRange) then
                if Player:Distance(target) > Orbwalker.GetTrueAutoAttackRange(Player) then
                    if not IsWindingUp then
                        if spells.E:Cast() then
                            return
                        end
                    end
                end
            end
        end
    elseif OriUtils.MGet("combo.eEngage.options") == 2 then
        local eRange = OriUtils.MGet("combo.ESlider")
        local engangeEnemyE2 = ObjManager.GetNearby("enemy", "heroes")
        local IsWindingUp = Orbwalker.IsWindingUp()
        if Kaisa.EEvolved() then
            for iE, objE in ipairs(engangeEnemyE2) do
                local target = objE.AsHero
                if OriUtils.IsValidTarget(target, eRange) then
                    if Player:Distance(target) > Orbwalker.GetTrueAutoAttackRange(Player) then
                        if not IsWindingUp then
                            if spells.E:Cast() then
                                return
                            end
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
        local IsWindingUp = Orbwalker.IsWindingUp()
        if qTarget then
            if not IsWindingUp then
                if spells.Q:Cast() then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "harass.useW") then
        local wTarget = spells.W:GetTarget()
        local IsWindingUp = Orbwalker.IsWindingUp()
        if wTarget then
            if not IsWindingUp then
                if spells.W:CastOnHitChance(wTarget, OriUtils.MGet("hc.WC") / 100) then
                    return
                end
            end
        end
    end
end

function combatVariants.Waveclear()
    
    if OriUtils.CanCastSpell(slots.Q, "jglclear.useQ") then
        if Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.QManaSlider") then
            local jglminionsQ = ObjManager.GetNearby("neutral", "minions")
            local IsWindingUp = Orbwalker.IsWindingUp()
            local qDrake = OriUtils.MGet("jgl.qDrake")
            for iJGLQ, objJGLQ in ipairs(jglminionsQ) do
                if OriUtils.IsValidTarget(objJGLQ, spells.Q.Range) then
                    local minionName = objJGLQ.CharName
                    local aaDamage = Orbwalker.GetAutoAttackDamage(objJGLQ)
                    if OriUtils.MGet("jgl.qWL." .. minionName, true) or objJGLQ.IsDragon and qDrake then
                        if objJGLQ.Health > (aaDamage * 2) then
                            if not IsWindingUp then
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

    if OriUtils.CanCastSpell(slots.W, "jglclear.useW") then
        if Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.WManaSlider") then
            local jglminionsW = ObjManager.GetNearby("neutral", "minions")
            local IsWindingUp = Orbwalker.IsWindingUp()
            local wDrake = OriUtils.MGet("jgl.wDrake")
            for iJGLW, objJGLW in ipairs(jglminionsW) do
                if OriUtils.IsValidTarget(objJGLW, 700) then
                    local minionName = objJGLW.CharName
                    if OriUtils.MGet("jgl.wWL." .. minionName, true) or objJGLW.IsDragon and wDrake then
                        local jglStacks = objJGLW:GetBuff("kaisapassivemarker") and objJGLW:GetBuff("kaisapassivemarker").Count or 0
                        local aaDamage = Orbwalker.GetAutoAttackDamage(objJGLW)
                        if jglStacks >= OriUtils.MGet("jglclear.Stacks") and objJGLW.Health > (aaDamage * 2) then
                            if not IsWindingUp then
                                if spells.W:Cast(objJGLW) then
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
            local jglminionsE = ObjManager.GetNearby("neutral", "minions")
            local IsWindingUp = Orbwalker.IsWindingUp()
            local eDrake = OriUtils.MGet("jgl.eDrake")
            for iJGLE, objJGLE in ipairs(jglminionsE) do
                if OriUtils.IsValidTarget(objJGLE, 700) then
                    local minionName = objJGLE.CharName
                    if OriUtils.MGet("jgl.eWL." .. minionName, true) or objJGLE.IsDragon and eDrake then
                        local aaDamage = Orbwalker.GetAutoAttackDamage(objJGLE)
                        if objJGLE.Health > (aaDamage * 2) then
                            if not IsWindingUp then
                                if spells.E:Cast() then
                                    return
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
        local IsWindingUp = Orbwalker.IsWindingUp()
        for iclearQ, objclearQ in ipairs(minionsQ) do
            if OriUtils.IsValidTarget(objclearQ, spells.Q.Range) then
                if Orbwalker.IsFastClearEnabled() then
                    if Kaisa.QCount() >= 1 then
                        if not IsWindingUp then
                            if spells.Q:Cast() then
                                return
                            end
                        end
                    end
                else
                    if Kaisa.QCount() >= OriUtils.MGet("clear.qMinions") then
                        if Player.ManaPercent * 100 >= OriUtils.MGet("clear.qManaSlider") then
                            if not IsWindingUp then
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

    if OriUtils.CanCastSpell(slots.E, "clear.useE") and Orbwalker.IsFastClearEnabled() then
        local minionE = ObjManager.GetNearby("enemy", "minions")
        local IsWindingUp = Orbwalker.IsWindingUp()
        for iclearE, objclearE in ipairs(minionE) do
            if OriUtils.IsValidTarget(objclearE, 700) then
                if not IsWindingUp then
                    if spells.E:Cast() then
                        return
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "clear.useW") and Orbwalker.IsFastClearEnabled() then
        local minionW = ObjManager.GetNearby("enemy", "minions")
        local IsWindingUp = Orbwalker.IsWindingUp()
        for iclearW, objclearW in ipairs(minionW) do
            if OriUtils.IsValidTarget(objclearW, 700) then
                local aaDamage = Orbwalker.GetAutoAttackDamage(objclearW)
                if objclearW.Health > (aaDamage * 2) then
                    if not IsWindingUp then
                        if spells.W:Cast(objclearW) then
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
    if OriUtils.CanCastSpell(slots.E, "misc.fleeE") then
        if spells.E:Cast() then
            return
        end
    end

end

WARN("Welcome! " .. scriptName .. " by " .. scriptCreator .. " loaded!")
function events.OnTick()
    Kaisa.UpdateRRange()
    if not OriUtils.ShouldRunLogic() then
        return
    end
    local modeToExecute = combatVariants[Orbwalker.GetMode()]
    if modeToExecute then
        modeToExecute()
    end

    Kaisa.AutoQ()
    Kaisa.BaronSteal()
    Kaisa.DrakeSteal()
    Kaisa.KS()
    --Kaisa.forceR()
    Kaisa.WToggle()
end

function events.OnDrawDamage(target, dmgList)
    if not OriUtils.MGet("draw.comboDamage") then
        return
    end

    local damageToDeal = 0
    local missingHP = target.MaxHealth - target.Health
    local passiveDamage = (0.15 + 0.025) * missingHP

    if OriUtils.CanCastSpell(slots.Q, "combo.useQ") then
        if Kaisa.QEvolved() then
            if Kaisa.qCases() == 1 then
                damageToDeal = damageToDeal + Kaisa.GetDamage(target, slots.Q) + ((Kaisa.GetDamage(target, slots.Q) / 4) * 11)
            elseif Kaisa.qCases() == 2 then
                damageToDeal = damageToDeal + Kaisa.GetDamage(target, slots.Q) + ((Kaisa.GetDamage(target, slots.Q) / 4) * 5)
            elseif Kaisa.qCases() == 3 then
                damageToDeal = damageToDeal + Kaisa.GetDamage(target, slots.Q) + ((Kaisa.GetDamage(target, slots.Q) / 4) * 3)
            elseif Kaisa.qCases() == 4 then
                damageToDeal = damageToDeal + Kaisa.GetDamage(target, slots.Q) + ((Kaisa.GetDamage(target, slots.Q) / 4) * 2)
            elseif Kaisa.qCases() == 5 then
                damageToDeal = damageToDeal + Kaisa.GetDamage(target, slots.Q) + ((Kaisa.GetDamage(target, slots.Q) / 4) * 1)
            end
        else
            if Kaisa.qCases() == 1 then
                damageToDeal = damageToDeal + Kaisa.GetDamage(target, slots.Q) + ((Kaisa.GetDamage(target, slots.Q) / 4) * 5)
            elseif Kaisa.qCases() == 2 then
                damageToDeal = damageToDeal + Kaisa.GetDamage(target, slots.Q) + ((Kaisa.GetDamage(target, slots.Q) / 4) * 2)
            elseif Kaisa.qCases() == 3 then
                damageToDeal = damageToDeal + Kaisa.GetDamage(target, slots.Q) + ((Kaisa.GetDamage(target, slots.Q) / 4) * 1)
            elseif Kaisa.qCases() == 4 or Kaisa.qCases() == 5 then
                damageToDeal = damageToDeal + Kaisa.GetDamage(target, slots.Q)
            end
        end
    end

    if spells.W:IsReady() and OriUtils.MGet("combo.useW") then
        if target:GetBuff("kaisapassivemarker") and (target:GetBuff("kaisapassivemarker").Count >= 3 or Kaisa.WEvolved() and target:GetBuff("kaisapassivemarker").Count >= 2) then
            damageToDeal = damageToDeal + Kaisa.GetDamage(target, slots.W) + passiveDamage
        else
            damageToDeal = damageToDeal + Kaisa.GetDamage(target, slots.W)
        end
    end

    if OriUtils.MGet("drawMenu.EnableAA") then
        damageToDeal = damageToDeal + (Kaisa.AD * OriUtils.MGet("drawMenu.AASlider"))
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
            if OriUtils.CanCastSpell(slots.W, "Draw.W.Minimap") then
                Renderer.DrawCircleMM(myPos, spells.W.Range, 1, Menu.Get("Draw.W.ColorMinimap"))
            end
            if OriUtils.CanCastSpell(slots.R, "Draw.R.Minimap") and spells.R.Range >= 2250 then
                Renderer.DrawCircleMM(myPos, spells.R.Range, 1, Menu.Get("Draw.R.ColorMinimap"))
            end
        else
            if Player:GetSpell(slot).IsLearned then
                Renderer.DrawCircle3D(myPos, range, 30, 2, OriUtils.MGet("draw." .. id .. ".color"))
            end
            if Player:GetSpell(slot).IsLearned then
                Renderer.DrawCircleMM(myPos, spells.W.Range, 1, Menu.Get("Draw.W.ColorMinimap"))
            end
            if Player:GetSpell(slot).IsLearned and spells.R.Range >= 2250 then
                Renderer.DrawCircleMM(myPos, spells.R.Range, 1, Menu.Get("Draw.R.ColorMinimap"))
            end
        end
    end

    if OriUtils.MGet("misc.wToggle") then
        return Renderer.DrawTextOnPlayer("Auto W Harass: ACTIVE", 0xFF00FFFF)
    end

    if OriUtils.MGet("misc.autoQ.options") == 1 or OriUtils.MGet("misc.autoQ.options") == 2 and Kaisa.QEvolved() then
        return Renderer.DrawTextOnPlayer("Auto Q: ACTIVE", 0xFFFF00FF)
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


function Kaisa.RegisterEvents()
    for eventName, eventId in pairs(Enums.Events) do
        if events[eventName] then
            EventManager.RegisterCallback(eventId, events[eventName])
        end
    end
end

function Kaisa.InitMenu()
    local function QHeader()
        Menu.ColoredText(drawData[1].displayText, scriptColor, true)
    end
    local function QHeaderHit()
        Menu.ColoredText(drawData[1].displayText .. " Hitchance", scriptColor, true)
    end

    local function WHeader()
        Menu.ColoredText(drawData[2].displayText, scriptColor, true)
    end
    local function WHeaderHitCombo()
        Menu.ColoredText(drawData[2].displayText .. " Hitchance Combo", scriptColor, true)
    end
    local function WHeaderHitHarass()
        Menu.ColoredText(drawData[2].displayText .. " Hitchance Harass", scriptColor, true)
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

    local function KaisaMenu()
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
            Menu.Text("")
            Menu.ColoredText("This script is in an early stage , which means you'll have to redownload the final version once it's done!", 0xFFFF00FF, true)
            Menu.ColoredText("Please keep in mind, that you might encounter bugs/issues.", 0xFFFF00FF, true)
            Menu.ColoredText("If you find any, please contact " .. scriptCreator, 0xFF0000FF, true)
        end
        
        if Menu.Checkbox("Kaisa.Updates141", "Don't show updates") == false then
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. scriptLastUpdated .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesVersion, 0XFFFF00FF, true)
            Menu.Text("- Code Rework", true)
            Menu.Text("- Added different E Modes inside AA Range (Never, Always, Only Evolved)", true)
            Menu.Text("- Added R Positions (MousePos and On Spot)", true)
            Menu.Text("- Changed enemy R value to 'above' instead of 'below'", true)
            Menu.Text("- Added Auto Q Options (Never, Always, Only Evolved) inside Misc", true)
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. patchNotesPrevUpdate .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesPreVersion, 0XFFFF00FF, true)
            Menu.Text("- Initital Release of AuKaisa 1.0.0", true)
        end

        Menu.Separator()

        Menu.NewTree("Kaisa.comboMenu", "Combo Settings", function()
            Menu.ColumnLayout("Kaisa.comboMenu.QE", "Kaisa.comboMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Kaisa.combo.useQ", "Enable Q", true)
                Menu.Slider("Kaisa.combo.qMinionCount", "Don't cast if X Minions", 5, 1, 6, 1)
                Menu.Checkbox("Kaisa.combo.qMinionCountDouble", "Double Minions, if Q evolved", true)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Kaisa.combo.useE", "Enable E", true)
                Menu.Dropdown("Kaisa.combo.useE.options", "E in AA Range", 1, {"Never", "Always", "Use only Evolved E"})
                Menu.Dropdown("Kaisa.combo.eEngage.options", "Engage Mode", 2, {"Never", "Use E To Engage", "Use only Evolved E to Engage"})
                local ddResultE = OriUtils.MGet("combo.eEngage.options") == 0
                if not ddResultE then
                    Menu.Slider("Kaisa.combo.ESlider", "Engage E Range", 975, 750, 1300, 1)
                end
                if ddResultE then
                    Menu.Slider("Kaisa.combo.ESlider", "Engage E Range", 595, 595, 595, 595)
                end
            end)

            Menu.ColumnLayout("Kaisa.comboMenu.WR", "Kaisa.comboMenu.WR", 2, true, function()
                WHeader()
                Menu.Checkbox("Kaisa.combo.useW", "Enable W", true)
                Menu.Slider("Kaisa.combo.wPassiveCount", "Use if enemy has X Stacks", 3, 0, 4, 1)
                Menu.Slider("Kaisa.combo.wManaSlider", "Don't use if Mana < %", 15, 1, 100, 1)
                Menu.NextColumn()
                RHeader()
                Menu.Checkbox("Kaisa.combo.useR", "Enable R", true)
                Menu.Dropdown("Kaisa.combo.useR.options", "Position", 1, {"On Spot", "On MousePos"})
                Menu.Slider("Kaisa.combo.rSelfHP", "If own HP below X%", 25, 1, 100, 1)
                Menu.Slider("Kaisa.combo.rEnemyHP", "and if Enemy HP above X%", 40, 1, 100, 1)
                Menu.ColoredText("Will only cast R inside AA Range, for longer ranges use Force R", scriptColor, true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Kaisa.harassMenu", "Harass Settings", function()
            Menu.ColumnLayout("Kaisa.harassMenu.QE", "Kaisa.harassMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Kaisa.harass.useQ", "Enable Q", true)
                Menu.NextColumn()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Kaisa.harass.useW", "Enable W", true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Kaisa.clearMenu", "Clear Settings", function()
            Menu.NewTree("Kaisa.waveMenu", "Waveclear", function()
                Menu.Checkbox("Kaisa.clear.enemiesAround", "Don't clear while enemies around", true)
                Menu.Separator()
                Menu.Checkbox("Kaisa.clear.useQ", "Use Q", true)
                Menu.Slider("Kaisa.clear.qMinions", "if X Minions", 5, 1, 6, 1)
                Menu.Slider("Kaisa.clear.qManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.ColoredText("Holding LMB (Fast Clear) is required for W and E\nand will ignore Mana and Minioncount for Q", scriptColor, true)
                Menu.Checkbox("Kaisa.clear.useW", "Enable W", true)
                Menu.Checkbox("Kaisa.clear.useE", "Enable E", true)
            end)
            Menu.NewTree("Kaisa.jglMenu", "Jungleclear", function()
                Menu.Checkbox("Kaisa.jglclear.useQ", "Use Q", true)
                Menu.ColumnLayout("Kaisa.jglclear.qWhitelist", "Kaisa.jglclear.qWhitelist", 3, true, function()
                    Menu.Indent(function()
                        Menu.NewTree("Kaisa.jglclear.qlist", "Jungle Camps 1", function()
                            for i, v in ipairs(jungleCamps) do
                                Menu.Checkbox("Kaisa.jgl.qWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Kaisa.jglclear.qlist2", "Jungle Camps 2", function()
                            for i, v in ipairs(jungleCamps2) do
                                Menu.Checkbox("Kaisa.jgl.qWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Kaisa.jglclear.qlist3", "Jungle Camps 3", function()
                            for i, v in ipairs(jungleCamps3) do
                                Menu.Checkbox("Kaisa.jgl.qWL." .. v.name, v.dName, v.default)
                            end
                            Menu.Checkbox("Kaisa.jgl.qDrake", "Other Drakes", true)
                        end)
                    end)
                end)
                Menu.Slider("Kaisa.jglclear.QManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Separator()
                Menu.Checkbox("Kaisa.jglclear.useW", "Use W", true)
                Menu.ColumnLayout("Kaisa.jglclear.wWhitelist", "Kaisa.jglclear.wWhitelist", 3, true, function()
                    Menu.Indent(function()
                        Menu.NewTree("Kaisa.jglclear.wlist", "Jungle Camps 1", function()
                            for i, v in ipairs(jungleCamps) do
                                Menu.Checkbox("Kaisa.jgl.wWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Kaisa.jglclear.wlist2", "Jungle Camps 2", function()
                            for i, v in ipairs(jungleCamps2) do
                                Menu.Checkbox("Kaisa.jgl.wWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Kaisa.jglclear.wlist3", "Jungle Camps 3", function()
                            for i, v in ipairs(jungleCamps3) do
                                Menu.Checkbox("Kaisa.jgl.wWL." .. v.name, v.dName, v.default)
                            end
                            Menu.Checkbox("Kaisa.jgl.wDrake", "Other Drakes", true)
                        end)
                    end)
                end)
                Menu.Slider("Kaisa.jglclear.Stacks", "Use if minion has X Stacks", 3, 0, 4, 1)
                Menu.Slider("Kaisa.jglclear.WManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Separator()
                Menu.Checkbox("Kaisa.jglclear.useE", "Use E", true)
                Menu.ColumnLayout("Kaisa.jglclear.eWhitelist", "Kaisa.jglclear.eWhitelist", 3, true, function()
                    Menu.Indent(function()
                        Menu.NewTree("Kaisa.jglclear.elist", "Jungle Camps 1", function()
                            for i, v in ipairs(jungleCamps) do
                                Menu.Checkbox("Kaisa.jgl.eWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Kaisa.jglclear.elist2", "Jungle Camps 2", function()
                            for i, v in ipairs(jungleCamps2) do
                                Menu.Checkbox("Kaisa.jgl.eWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Kaisa.jglclear.elist3", "Jungle Camps 3", function()
                            for i, v in ipairs(jungleCamps3) do
                                Menu.Checkbox("Kaisa.jgl.eWL." .. v.name, v.dName, v.default)
                            end
                            Menu.Checkbox("Kaisa.jgl.eDrake", "Other Drakes", true)
                        end)
                    end)
                end)
                Menu.Slider("Kaisa.jglclear.EManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Kaisa.stealMenu", "Steal Settings", function()
            Menu.NewTree("Kaisa.ksMenu", "Killsteal", function()
                Menu.Checkbox("Kaisa.ks.useQ", "Killsteal with Q", true)
                local cbResult = OriUtils.MGet("ks.useQ")
                if cbResult then
                    Menu.Indent(function()
                        Menu.NewTree("Kaisa.ksMenu.qWhitelist", "KS Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Kaisa.ks.qWL." .. heroName, "Q KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Kaisa.ks.useW", "Killsteal with W", true)
                local cbResultW = OriUtils.MGet("ks.useW")
                if cbResultW then
                    Menu.Indent(function()
                        Menu.NewTree("Kaisa.ksMenu.wWhitelist", "KS W Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Kaisa.ks.wWL." .. heroName, "W KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
            end)
            Menu.NewTree("Kaisa.jglstealMenu", "Junglesteal (Drake/Baron) | BETA", function()
                Menu.Checkbox("Kaisa.steal.useQ", "Junglesteal with Q", true)
                Menu.Checkbox("Kaisa.steal.useW", "Junglesteal with W", true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Kaisa.miscMenu", "Misc Settings", function()
            Menu.ColumnLayout("Kaisa.miscMenu.R", "Kaisa.miscMenu.R", 3, true, function()
                Menu.Text("")
                QHeader()
                Menu.Dropdown("Kaisa.misc.autoQ.options", "Auto Q", 0, {"Never", "Always", "Only if evolved"})
                local ddResultQ1 = OriUtils.MGet("misc.autoQ.options") == 1
                local ddResultQ2 = OriUtils.MGet("misc.autoQ.options") == 2
                if ddResultQ1 then
                    Menu.Slider("Kaisa.misc.autoQ.Minions", "<= than X Minions", 1, 0, 5)
                end
                if ddResultQ2 then
                    Menu.Slider("Kaisa.misc.autoQ.MinionsEvolved", "<= than X Minions", 6, 0, 11)
                end
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Kaisa.misc.fleeE", "Flee E", true)
                Menu.NextColumn()
                Menu.Text("")
                RHeader()
                --Menu.Keybind("Kaisa.misc.forceR", "Force R", string.byte("T"), false, false, true)
                Menu.ColoredText("Force R has been temporarily disabled \nand will be reenabled in a future update", 0xFF0000FF, true)
            end)
            Menu.Separator()
            Menu.ColumnLayout("Kaisa.miscMenu.E", "Kaisa.miscMenu.E", 1, true, function()
                Menu.Text("")
                WHeader()
                Menu.Slider("Kaisa.misc.WRange", "W Range for Combo", 900, 1, 1500, 1)
                Menu.Separator()
                Menu.Dropdown("Kaisa.misc.wToggle.options", "Options", 1, {"W Toggle", "W Toggle + Custom Range"})
                local ddResult = OriUtils.MGet("misc.wToggle.options") == 0
                local ddResult1 = OriUtils.MGet("misc.wToggle.options") == 1
                if ddResult then
                    Menu.Keybind("Kaisa.misc.wToggle", "Toggle W", string.byte("J"), true, false, true)
                    Menu.Slider("Kaisa.misc.wToggle.Hitchance", "Hitchance", 35, 1, 100, 1)
                end
                if ddResult1 then
                    Menu.Keybind("Kaisa.misc.wToggle", "Toggle W", string.byte("J"), true, false, true)
                    Menu.Slider("Kaisa.misc.wToggle.Hitchance", "Hitchance", 35, 1, 100, 1)
                    Menu.Slider("Kaisa.misc.wToggleRangeMin", "Min W Range", 1600, 1, 3000, 1)
                    Menu.Slider("Kaisa.misc.wToggleRangeMax", "Max W Range", 2500, 1, 3000, 1)
                end
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Kaisa.hcMenu", "Hitchance Settings", function()
            Menu.ColumnLayout("Kaisa.hcMenu.QE", "Kaisa.hcMenu.QE", 2, true, function()
                Menu.Text("")
                WHeaderHitCombo()
                Menu.Text("")
                Menu.Slider("Kaisa.hc.W", "%", 30, 1, 100, 1)
                Menu.NextColumn()
                Menu.Text("")
                WHeaderHitHarass()
                Menu.Text("")
                Menu.Slider("Kaisa.hc.WC", "%", 15, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Kaisa.drawMenu", "Draw Settings", function()
            OriUtils.AddDrawMenu(drawData)
        end)
    end

    Menu.RegisterMenu(scriptName, scriptName, KaisaMenu)
end

function OnLoad()
    Kaisa.InitMenu()
    
    Kaisa.RegisterEvents()
    return true
end
