if Player.CharName ~= "Volibear" then return end

local scriptName = "AuVolibear"
local scriptCreator = "AURUM"
local credits = "Orietto"
local patchNotesPrevUpdate = "03/31/2022"
local patchNotesPreVersion = "1.0.0"
local patchNotesVersion, scriptVersionUpdater = "1.0.1", "1.0.1"
local scriptVersion = scriptVersionUpdater
local scriptLastUpdated = "03/31/2022"
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

SDK.AutoUpdate("https://github.com/roburAURUM/robur-AuEdition/raw/main/AuVolibear.lua", scriptVersionUpdater)

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
        Base = {20, 40, 60, 80, 100},
        TotalAD = 1.0,
        BonusAD = 1.2,
        Type = dmgTypes.Physical
    },
    W = {
        Base = {10, 35, 60, 85, 110},
        TotalAD = 1.0,
        BonusHealth = 0.06,
        Type = dmgTypes.Physical
    },
    E = {
        Base = {80, 110, 140, 170, 200},
        TotalAP  = 0.8,
        Type = dmgTypes.Magical
    },
    R = {
        Base = {300, 500, 700},
        TotalAP = 1.25,
        BonusAD = 2.50,
        Type = dmgTypes.Physical
    }
}

local spells = {
    Q = Spell.Active({
        Slot = slots.Q,
        Delay = 0.0,
        Range = 265,
    }),
    W = Spell.Targeted({
        Slot = slots.W,
        Delay = 0.25,
        Range = 325,
    }),
    E = Spell.Skillshot({
        Slot = slots.E,
        Delay = 0.0 + 2.0,
        Speed = huge,
        Range = 1200,
        Radius = 325,
        Type = "Circular",
    }),
    R = Spell.Skillshot({
        Slot = slots.R,
        Delay = 1.0,
        Speed = huge,
        Range = 700,
        Radius = 300,
        Type = "Circular",
    }),
    R2 = Spell.Skillshot({
        Slot = slots.R,
        Delay = 1.0,
        Speed = huge,
        Range = 700,
        Radius = 500,
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

function OriUtils.CheckCastTimers(data)
    local curTime = Game.GetTime()

    for slot, Volibearold in pairs(data) do
        if curTime < lastCastT[slot] + Volibearold then
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
    Menu.Checkbox("Volibear.drawMenu.AlwaysDraw", "Always show Drawings", false)
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
    {slot = slots.Q, id = "Q", displayText = "[Q] Thundering Smash", range = function () return OriUtils.MGet("combo.qRange") end},
    {slot = slots.W, id = "W", displayText = "[W] Frenzied Maul", range = spells.W.Range},
    {slot = slots.E, id = "E", displayText = "[E] Sky Splitter", range = spells.E.Range},
    {slot = slots.R, id = "R", displayText = "[R] Stormbringer", range = spells.R.Range}
}

local ASCIIArt = "              __      __   _ _ _                      "
local ASCIIArt2 = "      /\\      \\ \\    / /  | (_) |                     "
local ASCIIArt3 = "     /  \\  _   \\ \\  / /__ | |_| |__   ___  __ _ _ __  "
local ASCIIArt4 = "    / /\\ \\| | | \\ \\/ / _ \\| | | '_ \\ / _ \\/ _` | '__| "
local ASCIIArt5 = "   / ____ \\ |_| |\\  / (_) | | | |_) |  __/ (_| | |    "
local ASCIIArt6 = "  /_/    \\_\\__,_| \\/ \\___/|_|_|_.__/ \\___|\\__,_|_|   "


local Volibear = {}

local slotToDamageTable = {
    [slots.Q] = damages.Q,
    [slots.W] = damages.W,
    [slots.E] = damages.E,
    [slots.R] = damages.R
}

---@param target AIBaseClient
---@param slot slut
function Volibear.GetDamage(target, slot)
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

            if data.BonusHealth then
                rawDamage = rawDamage + (data.BonusHealth * me.BonusHealth)
            end

            if slot == slots.E then
                local eLevel = spells.E:GetLevel()
                if eLevel == 1 then
                    rawDamage = rawDamage + 0.11 * target.MaxHealth
                elseif eLevel == 2 then
                    rawDamage = rawDamage + 0.12 * target.MaxHealth
                elseif eLevel == 3 then
                    rawDamage = rawDamage + 0.13 * target.MaxHealth
                elseif eLevel == 4 then
                    rawDamage = rawDamage + 0.14 * target.MaxHealth
                elseif eLevel == 5 then
                    rawDamage = rawDamage + 0.15 * target.MaxHealth
                end
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

function Volibear.forceR()
    if OriUtils.MGet("misc.forceR") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)
        local enemyPositions = {}
        local hcR = OriUtils.MGet("hc.R") / 100
        
        for i, obj in ipairs(TS:GetTargets(spells.R.Range)) do
            local pred = spells.R:GetPrediction(obj)
            if pred and pred.HitChance >= hcR then
                table.insert(enemyPositions, pred.TargetPosition)
            end
        end
        local bestPos, numberOfHits = Geometry.BestCoveringCircle(enemyPositions, spells.R.Radius)
        if numberOfHits >= 1 then
            if spells.R:Cast(bestPos) then
                return
            end
        end
    end
end

function Volibear.forceE()
    if OriUtils.MGet("misc.forceE") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)
        local mousePos = Renderer.GetMousePos()
        if spells.E:Cast(mousePos) then
            return
        end
    end
end


function Volibear.KS()
    if OriUtils.CanCastSpell(slots.Q, "ks.useQ") then
        local allyHeroes = ObjManager.GetNearby("ally", "heroes")
        local qTargets = spells.Q:GetTargets()
        local IsWindingUp = Orbwalker.IsWindingUp()
        for iKSA, objKSA in ipairs(allyHeroes) do
            local ally = objKSA.AsHero
            if not ally.IsMe and not ally.IsDead then
                if qTargets then
                    for iKS, objKS in ipairs(qTargets) do
                        local enemyHero = objKS.AsHero
                        local qDamage = Volibear.GetDamage(enemyHero, slots.Q)
                        local healthPredQ = spells.Q:GetHealthPred(objKS)
                        if OriUtils.MGet("ks.qWL." .. enemyHero.CharName, true) then
                            if healthPredQ > 0 and healthPredQ < floor(qDamage - 5) then
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

    if OriUtils.CanCastSpell(slots.W, "ks.useW") then
        local allyHeroes = ObjManager.GetNearby("ally", "heroes")
        local wReady = OriUtils.CanCastSpell(slots.W, "ks.useW")
        local wTargets = spells.W:GetTargets()
        local IsWindingUp = Orbwalker.IsWindingUp()
        for iKSA, objKSA in ipairs(allyHeroes) do
            local ally = objKSA.AsHero
            if not ally.IsMe and not ally.IsDead then
                if wTargets then
                    for iKS, objKS in ipairs(wTargets) do
                        local enemyHero = objKS.AsHero
                        local wDamage = Volibear.GetDamage(enemyHero, slots.W)
                        local healthPredW = spells.W:GetHealthPred(objKS)
                        if OriUtils.MGet("ks.wWL." .. enemyHero.CharName, true) then
                            if healthPredW > 0 and healthPredW < floor(wDamage - 5) then
                                if not IsWindingUp then
                                    if spells.W:Cast(enemyHero) then
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
                        local rDamage = Volibear.GetDamage(enemyHero, slots.R)
                        local healthPredR = spells.R:GetHealthPred(objKS)
                        if OriUtils.MGet("ks.rWL." .. enemyHero.CharName, true) then
                            if healthPredR > 0 and healthPredR < floor(rDamage - 50) then
                                if not IsWindingUp then
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

function Volibear.DrakeSteal()
    if OriUtils.CanCastSpell(slots.Q, "steal.useQ") then 
        local heroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        if heroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.Q.Range) then
                    local qDamage = Volibear.GetDamage(minion, slots.Q)
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

    if OriUtils.CanCastSpell(slots.W, "steal.useW") then 
        local heroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        if heroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.W.Range) then
                    local wDamage = Volibear.GetDamage(minion, slots.W)
                    local healthPredDrakeW = spells.W:GetHealthPred(minion)
                    if minion.IsDragon then
                        if healthPredDrakeW > 0 and healthPredDrakeW < floor(wDamage - 20) then
                            if spells.W:Cast(minion) then
                                return
                            end
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.R, "steal.useR") then 
        local heroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        if heroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.R.Range) then
                    local rDamage = Volibear.GetDamage(minion, slots.R)
                    local healthPredDrakeR = spells.R:GetHealthPred(minion)
                    if minion.IsDragon then
                        if healthPredDrakeR > 0 and healthPredDrakeR < floor(rDamage - 20) then
                            if spells.R:CastOnHitChance(minion, Enums.HitChance.VeryLow) then
                                return
                            end
                        end
                    end
                end
            end
        end
    end
end

function Volibear.BaronSteal()
    if OriUtils.CanCastSpell(slots.Q, "steal.useQ") then 
        local heroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        if heroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.Q.Range) then
                    local qDamage = Volibear.GetDamage(minion, slots.Q)
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

    if OriUtils.CanCastSpell(slots.W, "steal.useW") then 
        local heroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        if heroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.W.Range) then
                    local wDamage = Volibear.GetDamage(minion, slots.W)
                    local healthPredBaronW = spells.W:GetHealthPred(minion)
                    if minion.IsBaron then
                        if healthPredBaronW > 0 and healthPredBaronW < floor(wDamage - 20) then
                            if spells.W:Cast(minion) then
                                return
                            end
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.R, "steal.useR") then 
        local heroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        if heroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.R.Range) then
                    local rDamage = Volibear.GetDamage(minion, slots.R)
                    local healthPredDrakeR = spells.R:GetHealthPred(minion)
                    if minion.IsBaron then
                        if healthPredDrakeR > 0 and healthPredDrakeR < floor(rDamage - 20) then
                            if spells.R:CastOnHitChance(minion, Enums.HitChance.VeryLow) then
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
        local enemyPositions = {}
        local hcR = OriUtils.MGet("hc.R") / 100
        local PlayerMana = Player.ManaPercent * 100
        local rMana = OriUtils.MGet("combo.rMana")
        
        if PlayerMana >= rMana then
            for i, obj in ipairs(TS:GetTargets(spells.R.Range)) do
                local pred = spells.R:GetPrediction(obj)
                if pred and pred.HitChance >= hcR then
                    table.insert(enemyPositions, pred.TargetPosition)
                end
            end
            local bestPos, numberOfHits = Geometry.BestCoveringCircle(enemyPositions, spells.R.Radius)
            local minEnemies = OriUtils.MGet("combo.useR.minEnemies")
            if numberOfHits >= minEnemies then
                if spells.R:Cast(bestPos) then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "combo.useE") then
        local PlayerMana = Player.ManaPercent * 100
        local eMana = OriUtils.MGet("combo.eMana")
        local eToggleM = OriUtils.MGet("combo.eToggle")
        local eTarget = spells.E:GetTarget()
        local isWindingUp = Orbwalker.IsWindingUp()

        if eToggleM and PlayerMana >= eMana then
            if eTarget and not isWindingUp then
                if spells.E:CastOnHitChance(eTarget, OriUtils.MGet("hc.E") / 100) then
                    return
                end
            end
        end        
    end

    if OriUtils.CanCastSpell(slots.Q, "combo.useQ") then
        local qRange = OriUtils.MGet("combo.qRange")
        local qTarget = TS:GetTarget(qRange, false)
        local isWindingUp = Orbwalker.IsWindingUp()
        local PlayerMana = Player.ManaPercent * 100
        local qMana = OriUtils.MGet("combo.qMana")
        if PlayerMana >= qMana then
            if qTarget and not isWindingUp then
                if spells.Q:Cast() then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "combo.useW") then
        local wTarget = spells.W:GetTarget()
        local isWindingUp = Orbwalker.IsWindingUp()
        local PlayerMana = Player.ManaPercent * 100
        local wMana = OriUtils.MGet("combo.wMana")
        if PlayerMana >= wMana then
            if wTarget and not isWindingUp then
                if spells.W:Cast(wTarget) then
                    return
                end
            end
        end
    end
end

function combatVariants.Harass()
    if OriUtils.CanCastSpell(slots.E, "harass.useE") then
        local isWindingUp = Orbwalker.IsWindingUp()
        local eTarget = spells.E:GetTarget()
        if eTarget and not isWindingUp then
            if spells.E:CastOnHitChance(eTarget, OriUtils.MGet("hc.E") / 100) then
                return
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
                if OriUtils.IsValidTarget(objJGLQ, spells.Q.Range + 200) then
                    local minionName = objJGLQ.CharName
                    if OriUtils.MGet("jgl.qWL." .. minionName, true) or objJGLQ.IsDragon and qDrake then
                        local aaDamage = Orbwalker.GetAutoAttackDamage(objJGLQ)
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
                if OriUtils.IsValidTarget(objJGLW, spells.W.Range) then
                    local minionName = objJGLW.CharName
                    if OriUtils.MGet("jgl.wWL." .. minionName, true) or objJGLW.IsDragon and wDrake then
                        local aaDamage = Orbwalker.GetAutoAttackDamage(objJGLW)
                        if objJGLW.Health > (aaDamage * 2) then
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
        local jglminionsE = ObjManager.GetNearby("neutral", "minions")
        local minionsPositions = {}
        local eDrake = OriUtils.MGet("jgl.eDrake")
        local eMana = OriUtils.MGet("jglclear.EManaSlider")

        if Player.ManaPercent * 100 >= eMana then
            for iJGLE, objJGLE in ipairs(jglminionsE) do
                local minion = objJGLE.AsMinion
                local minionName = objJGLE.CharName
                local aaDamage = Orbwalker.GetAutoAttackDamage(objJGLE)
                if minion.Health > (aaDamage * 2) then
                    if OriUtils.IsValidTarget(objJGLE, 700) then
                        if OriUtils.MGet("jgl.eWL." .. minionName, true) or objJGLE.IsDragon and eDrake then
                            insert(minionsPositions, minion.Position)
                        end
                    end
                end
            end
            local bestPos, numberOfHits = Geometry.BestCoveringCircle(minionsPositions, spells.E.Radius)
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
        local bestPos, numberOfHits = Geometry.BestCoveringCircle(minionsPositions, spells.E.Radius)
        local eMana = OriUtils.MGet("clear.eMana")
        local eMinions = OriUtils.MGet("clear.eMinions")
        if Orbwalker.IsFastClearEnabled() then
            if numberOfHits >= 1 then
                if spells.E:Cast(bestPos) then
                    return
                end
            end
        else
            if Player.ManaPercent * 100 >= eMana then
                if numberOfHits >= eMinions then
                    if spells.E:Cast(bestPos) then
                        return
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.Q, "clear.useQ") then
        local minionsQ = ObjManager.GetNearby("enemy", "minions")
        local isFastClear = Orbwalker.IsFastClearEnabled()
        local IsWindingUp = Orbwalker.IsWindingUp()
        for iclearQ, objclearQ in ipairs(minionsQ) do
            if OriUtils.IsValidTarget(objclearQ, spells.Q.Range) then
                if isFastClear then
                    if not IsWindingUp then
                        if spells.Q:Cast() then
                            return
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "clear.useW") then
        local minionsW = ObjManager.GetNearby("enemy", "minions")
        local isFastClear = Orbwalker.IsFastClearEnabled()
        local IsWindingUp = Orbwalker.IsWindingUp()
        for iclearW, objclearW in ipairs(minionsW) do
            if OriUtils.IsValidTarget(objclearW, spells.W.Range) then
                if isFastClear then
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
    if OriUtils.CanCastSpell(slots.Q, "misc.fleeQ") then
        if spells.Q:Cast() then
            return
        end
    end
end

print(" |> Welcome - " .. scriptName .. " by " .. scriptCreator .. " loaded! <|")
function events.OnTick()
    --OriUtils.CheckFlashSlot()
    if not OriUtils.ShouldRunLogic() then
        return
    end
    local modeToExecute = combatVariants[Orbwalker.GetMode()]
    if modeToExecute then
        modeToExecute()
    end

    Volibear.forceE()
    Volibear.forceR()
    Volibear.KS()
    Volibear.BaronSteal()
    Volibear.DrakeSteal()
end


---@param source GameObject
function events.OnInterruptibleSpell(source, spellCast, danger, endTime, canMoveDuringChannel)
    if source.IsHero and source.IsEnemy then
        if spells.Q:IsReady() and OriUtils.MGet("interrupt.Q") and spells.Q:IsInRange(source) then
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

    if OriUtils.MGet("combo.useE") then
        if OriUtils.MGet("combo.eToggle") then
            Renderer.DrawTextOnPlayer("E: ACTIVE", scriptColor)
        else
            Renderer.DrawTextOnPlayer("E: DISABLED", 0xFF0000FF)
        end
    end
end

function events.OnDrawDamage(target, dmgList)
    if not OriUtils.MGet("draw.comboDamage") then
        return
    end

    local damageToDeal = 0


    if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
        damageToDeal = damageToDeal + Volibear.GetDamage(target, slots.Q)
    end

    if spells.W:IsReady() and OriUtils.MGet("combo.useW") then
        damageToDeal = damageToDeal + Volibear.GetDamage(target, slots.W)
    end

    if spells.E:IsReady() and OriUtils.MGet("combo.useE") then
        damageToDeal = damageToDeal + Volibear.GetDamage(target, slots.E)
    end

    if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
        damageToDeal = damageToDeal + Volibear.GetDamage(target, slots.R)
    end

    insert(dmgList, damageToDeal)
end

function Volibear.RegisterEvents()
    for eventName, eventId in pairs(Enums.Events) do
        if events[eventName] then
            EventManager.RegisterCallback(eventId, events[eventName])
        end
    end
end

function Volibear.InitMenu()
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

    local function VolibearMenu()
        Menu.Text("" .. ASCIIArt, true)
        Menu.Text("" .. ASCIIArt2, true)
        Menu.Text("" .. ASCIIArt3, true)
        Menu.Text("" .. ASCIIArt4, true)
        Menu.Text("" .. ASCIIArt5, true)
        Menu.Text("" .. ASCIIArt6, true)
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
        
        if Menu.Checkbox("Volibear.Updates100", "Don't show updates") == false then
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. scriptLastUpdated .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesVersion, 0XFFFF00FF, true)
            Menu.Text("- Initial Release of AuVolibear 1.0.0", true)
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. patchNotesPrevUpdate .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesPreVersion, 0XFFFF00FF, true)
            Menu.Text("- XXXXXXXXXXXX", true)
        end

        Menu.Separator()

        Menu.NewTree("Volibear.comboMenu", "Combo Settings", function()
            Menu.ColumnLayout("Volibear.comboMenu.QE", "Volibear.comboMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Volibear.combo.useQ", "Enable Q", true)
                Menu.Slider("Volibear.combo.qMana", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Slider("Volibear.combo.qRange", "Q Range", 400, 265, 600, 1)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Volibear.combo.useE", "Enable E", false)
                Menu.Slider("Volibear.combo.eMana", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Keybind("Volibear.combo.eToggle", "Toggle E", string.byte("Z"), true, false, true)
                Menu.ColoredText("Please be aware that because of the way Volibears E is built, its very likely that \nit wont cast often/good. Please use the manual E inside Misc (Default 'G')", scriptColor, true)
                Menu.Text("")
            end)

            Menu.ColumnLayout("Volibear.comboMenu.WR", "Volibear.comboMenu.WR", 2, true, function()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Volibear.combo.useW", "Enable W", true)
                Menu.Slider("Volibear.combo.wMana", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.NextColumn()
                RHeader()
                Menu.Checkbox("Volibear.combo.useR", "Enable R", true)
                Menu.Slider("Volibear.combo.rMana", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Slider("Volibear.combo.useR.minEnemies", "Use if X enemy(s)", 2, 1, 5)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Volibear.harassMenu", "Harass Settings", function()
            Menu.ColumnLayout("Volibear.harassMenu.E", "Volibear.harassMenu.E", 1, true, function()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Volibear.harass.useE", "Enable E", true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Volibear.clearMenu", "Clear Settings", function()
            Menu.NewTree("Volibear.waveMenu", "Waveclear", function()
                Menu.Checkbox("Volibear.clear.enemiesAround", "Don't clear while enemies around", true)
                Menu.Separator()
                Menu.ColoredText("Holding LMB (Fast Clear) will ignore Mana, Minioncount\n enemies around and is required for Q and W", scriptColor, true)
                Menu.Checkbox("Volibear.clear.useQ", "Use Q", true)
                Menu.Checkbox("Volibear.clear.useW", "Use W", true)
                Menu.Checkbox("Volibear.clear.useE", "Use E", true)
                Menu.Slider("Volibear.clear.eMinions", "if X Minions", 5, 1, 6, 1)
                Menu.Slider("Volibear.clear.eMana", "Don't use if Mana < %", 35, 1, 100, 1)
            end)
            Menu.NewTree("Volibear.jglMenu", "Jungleclear", function()
                Menu.Checkbox("Volibear.jglclear.useQ", "Use Q", true)
                Menu.ColumnLayout("Volibear.jglclear.qWhitelist", "Volibear.jglclear.qWhitelist", 3, true, function()
                    Menu.Indent(function()
                        Menu.NewTree("Volibear.jglclear.qlist", "Jungle Camps 1", function()
                            for i, v in ipairs(jungleCamps) do
                                Menu.Checkbox("Volibear.jgl.qWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Volibear.jglclear.qlist2", "Jungle Camps 2", function()
                            for i, v in ipairs(jungleCamps2) do
                                Menu.Checkbox("Volibear.jgl.qWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Volibear.jglclear.qlist3", "Jungle Camps 3", function()
                            for i, v in ipairs(jungleCamps3) do
                                Menu.Checkbox("Volibear.jgl.qWL." .. v.name, v.dName, v.default)
                            end
                            Menu.Checkbox("Volibear.jgl.qDrake", "Other Drakes", true)
                        end)
                    end)
                end)
                Menu.Slider("Volibear.jglclear.QManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Separator()
                Menu.Checkbox("Volibear.jglclear.useW", "Use W", true)
                Menu.ColumnLayout("Volibear.jglclear.wWhitelist", "Volibear.jglclear.wWhitelist", 3, true, function()
                    Menu.Indent(function()
                        Menu.NewTree("Volibear.jglclear.wlist", "Jungle Camps 1", function()
                            for i, v in ipairs(jungleCamps) do
                                Menu.Checkbox("Volibear.jgl.wWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Volibear.jglclear.wlist2", "Jungle Camps 2", function()
                            for i, v in ipairs(jungleCamps2) do
                                Menu.Checkbox("Volibear.jgl.wWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Volibear.jglclear.wlist3", "Jungle Camps 3", function()
                            for i, v in ipairs(jungleCamps3) do
                                Menu.Checkbox("Volibear.jgl.wWL." .. v.name, v.dName, v.default)
                            end
                            Menu.Checkbox("Volibear.jgl.wDrake", "Other Drakes", true)
                        end)
                    end)
                end)
                Menu.Slider("Volibear.jglclear.WManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Separator()
                Menu.Checkbox("Volibear.jglclear.useE", "Use E", true)
                Menu.ColumnLayout("Volibear.jglclear.eWhitelist", "Volibear.jglclear.eWhitelist", 3, true, function()
                    Menu.Indent(function()
                        Menu.NewTree("Volibear.jglclear.elist", "Jungle Camps 1", function()
                            for i, v in ipairs(jungleCamps) do
                                Menu.Checkbox("Volibear.jgl.eWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Volibear.jglclear.elist2", "Jungle Camps 2", function()
                            for i, v in ipairs(jungleCamps2) do
                                Menu.Checkbox("Volibear.jgl.eWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Volibear.jglclear.elist3", "Jungle Camps 3", function()
                            for i, v in ipairs(jungleCamps3) do
                                Menu.Checkbox("Volibear.jgl.eWL." .. v.name, v.dName, v.default)
                            end
                            Menu.Checkbox("Volibear.jgl.eDrake", "Other Drakes", true)
                        end)
                    end)
                end)
                Menu.Slider("Volibear.jglclear.EManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Volibear.stealMenu", "Steal Settings", function()
            Menu.NewTree("Volibear.ksMenu", "Killsteal", function()
                Menu.Checkbox("Volibear.ks.useQ", "Killsteal with Q", true)
                local cbResult = OriUtils.MGet("ks.useQ")
                if cbResult then
                    Menu.Indent(function()
                        Menu.NewTree("Volibear.ksMenu.qWhitelist", "KS Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Volibear.ks.qWL." .. heroName, "Q KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Volibear.ks.useW", "Killsteal with W", true)
                local cbResultW = OriUtils.MGet("ks.useW")
                if cbResultW then
                    Menu.Indent(function()
                        Menu.NewTree("Volibear.ksMenu.wWhitelist", "KS W Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Volibear.ks.wWL." .. heroName, "W KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Volibear.ks.useR", "Killsteal with R", false)
                local cbResult3 = OriUtils.MGet("ks.useR")
                if cbResult3 then
                    Menu.Indent(function()
                        Menu.NewTree("Volibear.ksMenu.rWhitelist", "KS R Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Volibear.ks.rWL." .. heroName, "R KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
            end)
            Menu.NewTree("Volibear.jglstealMenu", "Junglesteal (Drake/Baron) | BETA", function()
                Menu.Checkbox("Volibear.steal.useQ", "Junglesteal with Q", true)
                Menu.Checkbox("Volibear.steal.useW", "Junglesteal with W", true)
                Menu.Checkbox("Volibear.steal.useR", "Junglesteal with R", false)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Volibear.miscMenu", "Misc Settings", function()
            Menu.ColumnLayout("Volibear.miscMenu.R", "Volibear.miscMenu.R", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Volibear.interrupt.Q", "Interrupt with Q", true)
                local cbResult4 = OriUtils.MGet("interrupt.Q")
                if cbResult4 then
                    Menu.Indent(function()
                        Menu.NewTree("Volibear.miscMenu.interruptQ", "Interrupt Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Volibear.interrupt.qWL." .. heroName, "Use Q Interrupt on " .. heroName, true)
                                    Menu.Slider("Volibear.interrupt.qDelay." .. heroName, "Delay", 110, 0, 500, 1)
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end

                Menu.Checkbox("Volibear.misc.fleeQ", "Use Q for Flee", true)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Keybind("Volibear.misc.forceE", "Force E", string.byte("G"), false, false, true)
                Menu.Text("")
                RHeader()
                Menu.Keybind("Volibear.misc.forceR", "Force R", string.byte("T"), false, false, true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Volibear.hcMenu", "Hitchance Settings", function()
            Menu.ColumnLayout("Volibear.hcMenu.ER", "Volibear.hcMenu.ER", 2, true, function()
                Menu.Text("")
                EHeaderHit()
                Menu.Text("")
                Menu.Slider("Volibear.hc.E", "%", 10, 1, 100, 1)
                Menu.NextColumn()
                Menu.Text("")
                RHeaderHit()
                Menu.Text("")
                Menu.Slider("Volibear.hc.R", "%", 30, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Volibear.drawMenu", "Draw Settings", function()
            OriUtils.AddDrawMenu(drawData)
        end)
    end

    Menu.RegisterMenu(scriptName, scriptName, VolibearMenu)
end

function OnLoad()
    Volibear.InitMenu()
    
    Volibear.RegisterEvents()
    return true
end