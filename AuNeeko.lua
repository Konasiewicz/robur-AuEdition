if Player.CharName ~= "Neeko" then return end

local scriptName = "AuNeeko"
local scriptCreator = "AURUM"
local credits = "Orietto"
local patchNotesPrevUpdate = "02/17/2022"
local patchNotesPreVersion = "1.0.5"
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
local scriptColor2 = 0x00FF00FF

module(scriptName, package.seeall, log.setup)
clean.module(scriptName, clean.seeall, log.setup)

local insert, sort = table.insert, table.sort
local huge, pow, min, max, floor = math.huge, math.pow, math.min, math.max, math.floor

local SDK = _G.CoreEx

SDK.AutoUpdate("https://github.com/roburAURUM/robur-AuEdition/raw/main/AuNeeko.lua", scriptVersionUpdater)

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
        Base = {80, 125, 170, 215, 260},
        TotalAP = 0.5,
        Type = dmgTypes.Magical
    },
    Q2 = {
        Base = {40, 65, 90, 115, 140},
        TotalAP = 0.2,
        Type = dmgTypes.Magical
    },
    E = {
        Base = {80, 115, 150, 185, 220},
        TotalAP  = 0.6,
        Type = dmgTypes.Magical
    },
    R = {
        Base = {200, 425, 650},
        TotalAP = 1.3,
        Type = dmgTypes.Magical
    }
}

local spells = {
    Q = Spell.Skillshot({
        Slot = slots.Q,
        Delay = 0.25,
        Speed = 500,
        Range = 800,
        Radius = 160,
        Type = "Circular",
    }),
    W = Spell.Skillshot({
        Slot = slots.W,
        Range = 900,
    }),
    E = Spell.Skillshot({
        Slot = slots.E,
        Delay = 0.25,
        Range = 1000,
        Speed = 1300,
        Radius = 140 / 2,
        Type = "Linear",
    }),
    R = Spell.Active({
        Slot = slots.R,
        Delay = 0.00 + 1.25,
        Speed = 5000,
        Range = 535,
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

function OriUtils.CheckCastTimers(data)
    local curTime = Game.GetTime()

    for slot, Neekoold in pairs(data) do
        if curTime < lastCastT[slot] + Neekoold then
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
    Menu.Checkbox(cacheName .. ".draw." .. "AlwaysDraw", "Always show Drawings", false)
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


 
local ASCIIArt = "                _   _           _         "	 
local ASCIIArt2 = "     /\\        | \\ | |         | |         "
local ASCIIArt3 = "    /  \\  _   _|  \\| | ___  ___| | _____  "
local ASCIIArt4 = "   / /\\ \\| | | | . ` |/ _ \\/ _ \\ |/ / _ \\  "
local ASCIIArt5 = "  / ____ \\ |_| | |\\  |  __/  __/   < (_) | "
local ASCIIArt6 = " /_/    \\_\\__,_|_| \\_|\\___|\\___|_|\\_\\___/  "

local Neeko = {}

local BaseMoveSpeeds = {
	["Aatrox"] = 345,
	["Ahri"] = 330,
	["Akali"] = 345,
	["Akshan"] = 330,
	["Alistar"] = 330,
	["Amumu"] = 335,
	["Anivia"] = 325,
	["Annie"] = 335,
	["Aphelios"] = 325,
	["Ashe"] = 325,
	["AurelionSol"] = 325,
	["Azir"] = 335,
	["Bard"] = 330,
	["Blitzcrank"] = 325,
	["Brand"] = 340,
	["Braum"] = 335,
	["Caitlyn"] = 325,
	["Camille"] = 340,
	["Cassiopeia"] = 328,
	["Chogath"] = 345,
	["Corki"] = 325,
	["Darius"] = 340,
	["Diana"] = 345,
	["DrMundo"] = 345,
	["Draven"] = 330,
	["Ekko"] = 340,
	["Elise"] = 330,
	["Evelynn"] = 335,
	["Ezreal"] = 325,
	["Fiddlesticks"] = 335,
	["Fiora"] = 345,
	["Fizz"] = 335,
	["Galio"] = 335,
	["Gangplank"] = 345,
	["Garen"] = 340,
	["Gnar"] = 335,
	["Gragas"] = 330,
	["Graves"] = 340,
	["Gwen"] = 340,
	["Hecarim"] = 345,
	["Heimerdinger"] = 340,
	["Illaoi"] = 350,
	["Irelia"] = 335,
	["Ivern"] = 330,
	["Janna"] = 315,
	["JarvanIV"] = 340,
	["Jax"] = 350,
	["Jayce"] = 335,
	["Jhin"] = 330,
	["Jinx"] = 325,
	["Kaisa"] = 335,
	["Kalista"] = 325,
	["Karma"] = 335,
	["Karthus"] = 335,
	["Kassadin"] = 335,
	["Katarina"] = 335,
	["Kayle"] = 335,
	["Kayn"] = 340,
	["Kennen"] = 335,
	["Khazix"] = 350,
	["Kindred"] = 325,
	["Kled"] = 345,
	["KogMaw"] = 330,
	["Leblanc"] = 340,
	["LeeSin"] = 345,
	["Leona"] = 335,
	["Lillia"] = 330,
	["Lissandra"] = 325,
	["Lucian"] = 335,
	["Lulu"] = 330,
	["Lux"] = 330,
	["Malphite"] = 335,
	["Malzahar"] = 335,
	["Maokai"] = 335,
	["MasterYi"] = 355,
	["MissFortune"] = 325,
	["MonkeyKing"] = 345,
	["Mordekaiser"] = 335,
	["Morgana"] = 335,
	["Nami"] = 335,
	["Nasus"] = 350,
	["Nautilus"] = 325,
	["Neeko"] = 340,
	["Nidalee"] = 335,
	["Nocturne"] = 345,
	["Nunu"] = 345,
	["Olaf"] = 350,
	["Orianna"] = 325,
	["Ornn"] = 335,
	["Pantheon"] = 345,
	["Poppy"] = 345,
	["Pyke"] = 330,
	["Qiyana"] = 335,
	["Quinn"] = 335,
	["Rakan"] = 335,
	["Rammus"] = 335,
	["RekSai"] = 335,
	["Rell"] = 335,
	["Renekton"] = 345,
	["Rengar"] = 345,
	["Riven"] = 340,
	["Rumble"] = 345,
	["Ryze"] = 340,
	["Samira"] = 335,
	["Sejuani"] = 340,
	["Senna"] = 330,
	["Seraphine"] = 325,
	["Sett"] = 340,
	["Shaco"] = 345,
	["Shen"] = 340,
	["Shyvana"] = 350,
	["Singed"] = 345,
	["Sion"] = 345,
	["Sivir"] = 335,
	["Skarner"] = 335,
	["Sona"] = 325,
	["Soraka"] = 325,
	["Swain"] = 325,
	["Sylas"] = 340,
	["Syndra"] = 330,
	["TahmKench"] = 335,
	["Taliyah"] = 335,
	["Talon"] = 335,
	["Taric"] = 340,
	["Teemo"] = 330,
	["Thresh"] = 330,
	["Tristana"] = 325,
	["Trundle"] = 350,
	["Tryndamere"] = 345,
	["TwistedFate"] = 330,
	["Twitch"] = 330,
	["Udyr"] = 350,
	["Urgot"] = 330,
	["Varus"] = 330,
	["Vayne"] = 330,
	["Veigar"] = 340,
	["Velkoz"] = 340,
	["Vex"] = 335,
	["Vi"] = 340,
	["Viego"] = 345,
	["Viktor"] = 335,
	["Vladimir"] = 330,
	["Volibear"] = 340,
	["Warwick"] = 335,
	["Xayah"] = 330,
	["Xerath"] = 340,
	["XinZhao"] = 345,
	["Yasuo"] = 345,
	["Yone"] = 345,
	["Yorick"] = 340,
	["Yuumi"] = 330,
	["Zac"] = 340,
	["Zed"] = 345,
	["Ziggs"] = 325,
	["Zilean"] = 335,
	["Zoe"] = 340,
	["Zyra"] = 340,
    ["Zeri"] = 325,
}

local slotToDamageTable = {
    [slots.Q] = damages.Q,
    [slots.E] = damages.E,
    [slots.R] = damages.R
}

---@param target AIBaseClient
---@param slot slut
function Neeko.GetDamage(target, slot)
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

---@param target AIBaseClient
function Neeko.GetQ2Damage(target)
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

        return DmgLib.CalculateMagicalDamage(me, target, rawDamage)
    end

    return 0
end

function Neeko.flashE()
    if OriUtils.CanCastSpell(slots.E, "misc.flashE") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)

        local flashReady = spells.Flash.Slot and OriUtils.IsSpellReady(spells.Flash.Slot)
        if not flashReady then
            return
        end

        local eFlashRange = (spells.E.Range - 5) + spells.Flash.Range
        local eFlashTarget = TS:GetTarget(eFlashRange, false)
        if eFlashTarget and not spells.E:IsInRange(eFlashTarget) then
            local flashPos = Player.ServerPos:Extended(eFlashTarget, spells.Flash.Range) 

            local spellInput = {
                Slot = slots.E,
                Delay = 0.25,
                Speed = 1300,
                Range = 1000,
                Radius = 180 / 2,
                Type = "Linear",
            }
            local pred = Prediction.GetPredictedPosition(eFlashTarget, spellInput, flashPos)
            if pred and pred.HitChanceEnum >= Enums.HitChance.Medium then

                if OriUtils.MGet("misc.flashE.options") == 0 then
                    if spells.E:Cast(flashPos) then
                        delay(60, function() Input.Cast(spells.Flash.Slot, flashPos) end)
                        return
                    end
                else
                    if Input.Cast(spells.Flash.Slot, flashPos) then
                        delay(80, function()spells.E:Cast(eFlashTarget) end)
                        return
                    end
                end
            end
        end
    end
end

function Neeko.KS()
    if OriUtils.MGet("ks.useQ") or OriUtils.MGet("ks.useE")then
        local allyHeroes = ObjManager.GetNearby("ally", "heroes")
        for iKSA, objKSA in ipairs(allyHeroes) do
            local ally = objKSA.AsHero
            if not ally.IsMe and not ally.IsDead then
            local nearbyEnemiesKS = ObjManager.GetNearby("enemy", "heroes")
                for iKS, objKS in ipairs(nearbyEnemiesKS) do
                    local enemyHero = objKS.AsHero
                    local qDamage = Neeko.GetDamage(enemyHero, slots.Q)
                    local healthPredQ = spells.Q:GetHealthPred(objKS)
                    local eDamage = Neeko.GetDamage(enemyHero, slots.E)
                    local healthPredE = spells.E:GetHealthPred(objKS)
                    if not enemyHero.IsDead and enemyHero.IsVisible and enemyHero.IsTargetable then
                        if OriUtils.CanCastSpell(slots.Q, "ks.useQ") and spells.Q:IsInRange(objKS) then
                            if OriUtils.MGet("ks.qWL." .. enemyHero.CharName, true) then
                                if healthPredQ > 0 and healthPredQ < floor(qDamage - 10) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.Q:Cast(enemyHero) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.E, "ks.useE") and spells.E:IsInRange(objKS) then
                            if OriUtils.MGet("ks.eWL." .. enemyHero.CharName, true) then
                                if healthPredE > 0 and healthPredE < floor(eDamage - 10) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.E:Cast(enemyHero) then
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

function Neeko.DrakeSteal()
    if OriUtils.MGet("steal.useQ") or OriUtils.MGet("steal.useE") then 
        local enemiesAround = ObjManager.GetNearby("enemy", "heroes")
        for iSteal, objSteal in ipairs(enemiesAround) do
            local enemy = objSteal.AsHero
            if OriUtils.IsValidTarget(objSteal) then
                local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
                for iM, minion in ipairs(nearbyMinions) do
                    local minion = minion.AsMinion
                    local qDamage = Neeko.GetDamage(minion, slots.Q)
                    local healthPredDrakeQ = spells.Q:GetHealthPred(minion)
                    local eDamage = Neeko.GetDamage(minion, slots.E)
                    local healthPredDrakeE = spells.E:GetHealthPred(minion)
                    local AADmg = Orbwalker.GetAutoAttackDamage(minion)
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
                                if spells.E:Cast(minion) then
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

function Neeko.BaronSteal()
    if OriUtils.MGet("steal.useQ") or OriUtils.MGet("steal.useE") then 
        local enemiesAround = ObjManager.GetNearby("enemy", "heroes")
        for iSteal2, objSteal2 in ipairs(enemiesAround) do
            local enemy = objSteal2.AsHero
            if OriUtils.IsValidTarget(objSteal2) then
                local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
                for iM2, minion in ipairs(nearbyMinions) do
                    local minion = minion.AsMinion
                    local qDamage = Neeko.GetDamage(minion, slots.Q)
                    local healthPredBaronQ = spells.Q:GetHealthPred(minion)
                    local eDamage = Neeko.GetDamage(minion, slots.E)
                    local healthPredBaronE = spells.E:GetHealthPred(minion)
                    local AADmg = Orbwalker.GetAutoAttackDamage(minion)
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
                                if spells.E:Cast(minion) then
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

---@return number|nil, AIHeroClient|nil
function Neeko.PassiveSpeed()
    local allyHeroes = ObjManager.Get("ally", "heroes")

    local highestSpeed = nil
    local highestSpeedHero = nil

    for _, obj in pairs(allyHeroes) do
        local hero = obj.AsHero
        local baseMS = BaseMoveSpeeds[hero.CharName]

        if highestSpeed == nil then
            highestSpeed = baseMS
            highestSpeedHero = hero
        else
            if baseMS > highestSpeed then
                highestSpeed = baseMS
                highestSpeedHero = hero
            end
        end
    end

    if OriUtils.MGet("misc.SpeedAlly.options") == 0 then
        Renderer.DrawTextOnPlayer("Fastest Ally: " .. highestSpeedHero.CharName, scriptColor)
    elseif OriUtils.MGet("misc.SpeedAlly.options") == 1 then
        if Player.IsInFountain then
            Renderer.DrawTextOnPlayer("Fastest Ally: " .. highestSpeedHero.CharName, scriptColor)
        end
    elseif OriUtils.MGet("misc.SpeedAlly.options") == 2 then
        if OriUtils.MGet("misc.SpeedAlly.Key2") then
            Renderer.DrawTextOnPlayer("Fastest Ally: " .. highestSpeedHero.CharName, scriptColor)
        elseif Player.IsInFountain then
            Renderer.DrawTextOnPlayer("Fastest Ally: " .. highestSpeedHero.CharName, scriptColor)
        end
    elseif OriUtils.MGet("misc.SpeedAlly.options") == 3 then
        if OriUtils.MGet("misc.SpeedAlly.Key3") then
            Renderer.DrawTextOnPlayer("Fastest Ally: " .. highestSpeedHero.CharName, scriptColor)
        elseif Player.IsInFountain then
            Renderer.DrawTextOnPlayer("Fastest Ally: " .. highestSpeedHero.CharName, scriptColor)
        end
    else
    end
end

function Neeko.PassiveAlly()
    local allyHeroesHP = ObjManager.Get("ally", "heroes")

    for _, obj in pairs(allyHeroesHP) do
        local hero = obj.AsHero
        if OriUtils.MGet("misc.deadAlly") then
            if not hero.IsDead then
                if OriUtils.MGet("misc.PassiveAllyHP.options") == 0 and not hero.IsMe then
                    if hero.Health <= OriUtils.MGet("misc.passiveHealthSlider." .. hero.CharName) then
                        Renderer.DrawTextOnPlayer("LowHP Ally: " .. hero.CharName, scriptColor2)
                    end
                end
                if OriUtils.MGet("misc.PassiveAllyHP.options") == 1 and not hero.IsMe then
                    if hero.HealthPercent * 100 <= OriUtils.MGet("misc.passivePercentSlider." .. hero.CharName) then
                        Renderer.DrawTextOnPlayer("LowHP Ally: " .. hero.CharName, scriptColor2)
                    end
                end
            end
        else
            if OriUtils.MGet("misc.PassiveAllyHP.options") == 0 and not hero.IsMe then
                if hero.Health <= OriUtils.MGet("misc.passiveHealthSlider." .. hero.CharName) then
                    Renderer.DrawTextOnPlayer("LowHP Ally: " .. hero.CharName, scriptColor2)
                end
            end
            if OriUtils.MGet("misc.PassiveAllyHP.options") == 1 and not hero.IsMe then
                if hero.HealthPercent * 100 <= OriUtils.MGet("misc.passivePercentSlider." .. hero.CharName) then
                    Renderer.DrawTextOnPlayer("LowHP Ally: " .. hero.CharName, scriptColor2)
                end
            end
        end
    end

end

function Neeko.forceR()
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


function Neeko.rCases()
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
    if OriUtils.CanCastSpell(slots.E, "combo.useE") then
        local eRange = OriUtils.MGet("misc.ERange")
        local eTarget = TS:GetTarget(eRange, false)
        if eTarget then
            if spells.E:CastOnHitChance(eTarget, OriUtils.MGet("hcNew.E") / 100) then
                return
            end
        end
    end
    if OriUtils.CanCastSpell(slots.Q, "combo.useQ") then
        local qTarget = spells.Q:GetTarget()
        if qTarget then
            if spells.Q:CastOnHitChance(qTarget, OriUtils.MGet("hcNew.Q") / 100) then
                return
            end
        end
    end

    if OriUtils.CanCastSpell(slots.R, "combo.useR") then
        if OriUtils.MGet("combo.useR.CminEnemies") and OriUtils.MGet("combo.useR.CminHP") then
            if Neeko.rCases() >= OriUtils.MGet("combo.useR.minEnemies") then
                if spells.W:IsReady() then
                    if spells.W:Cast(Player) then
                        delay(20, function() spells.R:Cast() end)
                    end
                else
                    if spells.R:Cast() then
                        return
                    end
                end
            end
            local rTarget = spells.R:GetTarget()
            if rTarget then
                if Player.HealthPercent * 100 <= OriUtils.MGet("combo.useR.minHP") then
                    if spells.W:IsReady() then
                        if spells.W:Cast(Player) then
                            delay(20, function() spells.R:Cast() end)
                        end
                    else
                        if spells.R:Cast() then
                            return
                        end
                    end
                end
            end
        end
        if OriUtils.MGet("combo.useR.CminEnemies") and not OriUtils.MGet("combo.useR.CminHP") then
            if Neeko.rCases() >= OriUtils.MGet("combo.useR.minEnemies") then
                if spells.W:IsReady() then
                    if spells.W:Cast(Player) then
                        delay(20, function() spells.R:Cast() end)
                    end
                else
                    if spells.R:Cast() then
                        return
                    end
                end
            end
        end
        if OriUtils.MGet("combo.useR.CminHP") and not OriUtils.MGet("combo.useR.CminEnemies") then
            local rTarget = spells.R:GetTarget()
            if rTarget then
                if Player.HealthPercent * 100 <= OriUtils.MGet("combo.useR.minHP") then
                    if spells.W:IsReady() then
                        if spells.W:Cast(Player) then
                            delay(20, function() spells.R:Cast() end)
                        end
                    else
                        if spells.R:Cast() then
                            return
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "combo.useW") then
        if OriUtils.MGet("combo.useW.CRange") and OriUtils.MGet("combo.useW.CHP") then
            local wRange = OriUtils.MGet("combo.useW.Range")
            local wTarget = TS:GetTarget(wRange, false)
            if wTarget then
                if Player.HealthPercent * 100 <= OriUtils.MGet("combo.useW.HP") then
                    if not Orbwalker.IsWindingUp() then
                        if spells.W:Cast(Player) then
                            return
                        end
                    end
                end
            end
        end
        if OriUtils.MGet("combo.useW.CRange") and not OriUtils.MGet("combo.useW.CHP") then
            local wRange = OriUtils.MGet("combo.useW.Range")
            local wTarget = TS:GetTarget(wRange, false)
            if wTarget then
                if not Orbwalker.IsWindingUp() then
                    if spells.W:Cast(Player) then
                        return
                    end
                end
            end
        end
        if OriUtils.MGet("combo.useW.CHP") and not OriUtils.MGet("combo.useW.CRange") then
            local wTarget = spells.W:GetTarget()
            if wTarget then
                if Player.HealthPercent * 100 <= OriUtils.MGet("combo.useW.HP") then
                    if not Orbwalker.IsWindingUp() then
                        if spells.W:Cast(Player) then
                            return
                        end
                    end
                end
            end
        end
    end     
end


function combatVariants.Harass()
    if OriUtils.CanCastSpell(slots.E, "harass.useE") then
        if OriUtils.MGet("misc.ERangeHarass") then
            local eRange = OriUtils.MGet("misc.ERange")
            local eTarget = TS:GetTarget(eRange, false)
            if eTarget then
                if spells.E:CastOnHitChance(eTarget, OriUtils.MGet("hcNew.Q") / 100) then
                    return
                end
            end
        else
            local eTarget = spells.E:GetTarget()
            if eTarget then
                if spells.E:CastOnHitChance(eTarget, Enums.HitChance.Low) then
                    return
                end
            end
        end
    end
    if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
        local qTarget = spells.Q:GetTarget()
        if qTarget then
            if spells.Q:CastOnHitChance(qTarget, OriUtils.MGet("hcNew.Q") / 100) then
                return
            end
        end
    end
end

function combatVariants.Waveclear()

    if OriUtils.CanCastSpell(slots.E, "jglclear.useE") then
        local jglminionsE = ObjManager.GetNearby("neutral", "minions")
        local minionsPositionsE = {}
        local myPos = Player.Position
            for iJGLE, objJGLE in ipairs (jglminionsE) do
                local minion = objJGLE.AsMinion
                if OriUtils.IsValidTarget(objJGLE, spells.E.Range) then
                    insert(minionsPositionsE, minion.Position)
                end
            end
    
        local bestPos, numberOfHits = Geometry.BestCoveringRectangle(minionsPositionsE, myPos, spells.E.Radius) 
        if numberOfHits >= 1 and Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.EManaSlider") then
            if not Orbwalker.IsWindingUp() then
                if spells.E:Cast(bestPos) then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.Q, "jglclear.useQ") then
        local jglminionsQ = ObjManager.GetNearby("neutral", "minions")
        local minionsPositionsQ = {}
            for iJGLQ, objJGLQ in ipairs (jglminionsQ) do
                local minion = objJGLQ.AsMinion
                if OriUtils.IsValidTarget(objJGLQ, spells.Q.Range) then
                    insert(minionsPositionsQ, minion.Position)
                end
            end
    
        local bestPos, numberOfHits = Geometry.BestCoveringCircle(minionsPositionsQ, spells.Q.Radius) 
        if numberOfHits >= 1 and Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.QManaSlider") then
            if not Orbwalker.IsWindingUp() then
                if spells.Q:Cast(bestPos) then
                    return
                end
            end
        end
    end



    if OriUtils.MGet("clear.enemiesAround") and TS:GetTarget(1800) then
        return
    end

    if OriUtils.CanCastSpell(slots.E, "clear.useE") then
        local minionsInERange = ObjManager.GetNearby("enemy", "minions")
        local minionsPositions = {}
        local myPos = Player.Position

        for _, minion in ipairs(minionsInERange) do
            if spells.Q:IsInRange(minion) then
                insert(minionsPositions, minion.Position)
            end
        end

        local bestPos, numberOfHits = Geometry.BestCoveringRectangle(minionsPositions, myPos, spells.E.Radius * 2)
        if Orbwalker.IsFastClearEnabled() then
            if numberOfHits >= 1 then
                if not Orbwalker.IsWindingUp() then
                    if spells.E:Cast(bestPos) then
                        return
                    end
                end
            end
        else
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
    end

    if OriUtils.CanCastSpell(slots.Q, "clear.useQ") then
        local minionsInQRange = ObjManager.GetNearby("enemy", "minions")
        local minionsPositions = {}

        for _, minion in ipairs(minionsInQRange) do
            if spells.Q:IsInRange(minion) then
                insert(minionsPositions, minion.Position)
            end
        end

        local bestPos, numberOfHits = Geometry.BestCoveringCircle(minionsPositions, spells.Q.Radius) 
        if Orbwalker.IsFastClearEnabled() then
            if numberOfHits >= 1 then
                if not Orbwalker.IsWindingUp() then
                    if spells.Q:Cast(bestPos) then
                        return
                    end
                end
            end
        else
            if numberOfHits >= OriUtils.MGet("clear.qMinions") then
                if Player.ManaPercent * 100 >= OriUtils.MGet("clear.QManaSlider") then
                    if not Orbwalker.IsWindingUp() then
                        if spells.Q:Cast(bestPos) then
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
if spells.W:IsReady() and OriUtils.MGet("misc.Flee") then
        if spells.W:Cast(Player) then
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

    Neeko.flashE()
    Neeko.forceR()
    Neeko.KS()
    Neeko.BaronSteal()
    Neeko.DrakeSteal()
end

local drawData = {
    {slot = slots.Q, id = "Q", displayText = "[Q] Blooming Burst", range = spells.Q.Range},
    {slot = slots.W, id = "W", displayText = "[W] Shapesplitter", range = function () return OriUtils.MGet("combo.useW.Range") end},
    {slot = slots.E, id = "E", displayText = "[E] Tangle-Barbs", range = function () return OriUtils.MGet("misc.ERange") end},
    {slot = slots.R, id = "R", displayText = "[R] Pop Blossom", range = spells.R.Range}
}

---@param source GameObject
---@param dashInstance DashInstance
function events.OnGapclose(source, dashInstance)
    if source.IsHero and source.IsEnemy then
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

function events.OnDraw()
    if Player.IsDead then
        return
    end

    Neeko.PassiveSpeed()
    Neeko.PassiveAlly()

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
    if OriUtils.MGet("misc.flashE") then
        local flashReady = spells.Flash.Slot and OriUtils.IsSpellReady(spells.Flash.Slot)
        if spells.E:IsReady() then
            if not flashReady then
                return Renderer.DrawTextOnPlayer("Flash not Ready", 0xFF0000FF)
            else
                local rRange = spells.Flash.Range + spells.E.Range
                return Renderer.DrawCircle3D(myPos, rRange, 30, 5, 0xFF0000FF)
            end
        else
            if flashReady then
                return Renderer.DrawTextOnPlayer("E not Ready", scriptColor)
            else
                return Renderer.DrawTextOnPlayer("E and Flash not Ready", 0xFFFF00FF)
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
        if spells.E:IsReady() and OriUtils.MGet("combo.useE") then
            damageToDeal = damageToDeal + Neeko.GetDamage(target, slots.Q)
            damageToDeal = damageToDeal + Neeko.GetQ2Damage(target) * 2
        else
            damageToDeal = damageToDeal + Neeko.GetDamage(target, slots.Q)
        end
    end

    if spells.E:IsReady() and OriUtils.MGet("combo.useE") then
        damageToDeal = damageToDeal + Neeko.GetDamage(target, slots.E)
    end
    if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
        damageToDeal = damageToDeal + Neeko.GetDamage(target, slots.R)
    end

    insert(dmgList, damageToDeal)
end

function Neeko.RegisterEvents()
    for eventName, eventId in pairs(Enums.Events) do
        if events[eventName] then
            EventManager.RegisterCallback(eventId, events[eventName])
        end
    end
end

function Neeko.InitMenu()
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

    local function NeekoMenu()
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
        
        if Menu.Checkbox("Neeko.Updates115", "Don't show updates") == false then
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. scriptLastUpdated .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesVersion, 0XFFFF00FF, true)
            Menu.Text("- Adjusted Hitchance for new Prediction", true)
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. patchNotesPrevUpdate .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesPreVersion, 0XFFFF00FF, true)
            Menu.Text("- Updated Q2 Damage for Patch 12.4", true)
        end
        Menu.Separator()

        Menu.NewTree("Neeko.comboMenu", "Combo Settings", function()
            Menu.ColumnLayout("Neeko.comboMenu.QE", "Neeko.comboMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Neeko.combo.useQ", "Enable Q", true)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Neeko.combo.useE", "Enable E", true)
            end)

            Menu.ColumnLayout("Neeko.comboMenu.WR", "Neeko.comboMenu.WR", 2, true, function()
                WHeader()
                Menu.Checkbox("Neeko.combo.useW", "Enable W", true)
                Menu.Checkbox("Neeko.combo.useW.CRange", "", false)Menu.SameLine()
                Menu.Slider("Neeko.combo.useW.Range", "W Range", 725, 1, 900, 1)
                Menu.Checkbox("Neeko.combo.useW.CHP", "",  true)Menu.SameLine()
                Menu.Slider("Neeko.combo.useW.HP", "%HP", 30, 1, 100, 1)
                if OriUtils.MGet("combo.useW.CRange") == false and OriUtils.MGet("combo.useW.CHP") then
                    Menu.ColoredText("W will use 900 Range", scriptColor, true)
                end
                Menu.NextColumn()
                RHeader()
                Menu.Checkbox("Neeko.combo.useR", "Enable R", true)
                Menu.Checkbox("Neeko.combo.useR.CminEnemies", "", true)Menu.SameLine()
                Menu.Slider("Neeko.combo.useR.minEnemies", "Use on X enemys", 2, 1, 5, 1)
                Menu.Checkbox("Neeko.combo.useR.CminHP", "",  true)Menu.SameLine()
                Menu.Slider("Neeko.combo.useR.minHP", "Use if HP under X%", 30, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Neeko.harassMenu", "Harass Settings", function()
            Menu.ColumnLayout("Neeko.harassMenu.QE", "Neeko.harassMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Neeko.harass.useQ", "Enable Q", true)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Neeko.harass.useE", "Enable E", false)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Neeko.clearMenu", "Clear Settings", function()
            Menu.NewTree("Neeko.waveMenu", "Waveclear", function()
                Menu.Checkbox("Neeko.clear.enemiesAround", "Don't clear while enemies around", true)
                Menu.Separator()
                Menu.ColoredText("Holding LMB (Fast Clear) during Waveclear will ignore Mana and Minionamount", scriptColor)
                Menu.Checkbox("Neeko.clear.useQ", "Enable Q", true)
                Menu.Slider("Neeko.clear.qMinions", "if X Minions", 4, 1, 6, 1)
                Menu.Slider("Neeko.clear.QManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Checkbox("Neeko.clear.useE", "Enable E", true)
                Menu.Slider("Neeko.clear.eMinions", "if X Minions", 5, 1, 6, 1)
                Menu.Slider("Neeko.clear.EManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
            end)
            Menu.NewTree("Neeko.jglMenu", "Jungleclear", function()
                Menu.Checkbox("Neeko.jglclear.useQ", "Use Q", true)
                Menu.Slider("Neeko.jglclear.QManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Checkbox("Neeko.jglclear.useE", "Use E", true)
                Menu.Slider("Neeko.jglclear.EManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Neeko.stealMenu", "Steal Settings", function()
            Menu.NewTree("Neeko.ksMenu", "Killsteal", function()
                Menu.Checkbox("Neeko.ks.useQ", "Killsteal with Q", true)
                local cbResult = OriUtils.MGet("ks.useQ")
                if cbResult then
                    Menu.Indent(function()
                        Menu.NewTree("Neeko.ksMenu.qWhitelist", "KS Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Neeko.ks.qWL." .. heroName, "Q KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Neeko.ks.useE", "Killsteal with E", true)
                local cbResult2 = OriUtils.MGet("ks.useE")
                if cbResult2 then
                    Menu.Indent(function()
                        Menu.NewTree("Neeko.ksMenu.eWhitelist", "KS E Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Neeko.ks.eWL." .. heroName, "E KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
            end)
            Menu.NewTree("Neeko.jglstealMenu", "Junglesteal (Drake/Baron) | BETA", function()
                Menu.Checkbox("Neeko.steal.useQ", "Junglesteal with Q", true)
                Menu.Checkbox("Neeko.steal.useE", "Junglesteal with E", true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Neeko.miscMenu", "Misc Settings", function()
            Menu.ColumnLayout("Neeko.miscMenu.WR", "Neeko.miscMenu.R", 2, true, function()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Neeko.misc.Flee", "Enable W for Flee", true)
                RHeader()
                Menu.Keybind("Neeko.misc.forceR", "Force R (Hold)", string.byte("T"), false, false,  true)
                EHeader()
                Menu.Keybind("Neeko.misc.flashE", "Flash E (Hold)", string.byte("G"), false, false, true)
                Menu.Dropdown("Neeko.misc.flashE.options", "Mode", 1, {"E > Flash (Experimental)", "Flash > E (Slower)"})
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Slider("Neeko.misc.ERange", "E Range", 900, 1, 1000, 1)
                Menu.Checkbox("Neeko.misc.ERangeHarass", "Use E Range above for Harass too", false)
                Menu.Checkbox("Neeko.gapclose.E", "Use Gapclose E ", true)
                Menu.Checkbox("Neeko.interrupt.E", "Use Interrupt E ", true)
               
            end)
            Menu.Separator()
            Menu.ColumnLayout("Neeko.miscMenu.Passive", "Neeko.miscMenu.Passive", 1, true, function()
                Menu.Text("")
                Menu.ColoredText("Passive Logic Speed", scriptColor, true)
                Menu.Dropdown("Neeko.misc.SpeedAlly.options", "Show fastest Ally", 2, {"Always", "Only in Fountain", "On Hold + Fountain", "On Toggle + Fountain", "Never"})
                local ddResultP = OriUtils.MGet("misc.SpeedAlly.options") == 0
                local ddResultP2 = OriUtils.MGet("misc.SpeedAlly.options") == 1
                local ddResultP3 = OriUtils.MGet("misc.SpeedAlly.options") == 2
                local ddResultP4 = OriUtils.MGet("misc.SpeedAlly.options") == 3
                if ddResultP3 then
                    Menu.Keybind("Neeko.misc.SpeedAlly.Key2", "Hold Key to show fastest Ally", string.byte("H"), false, false, true)
                end
                if ddResultP4 then
                    Menu.Keybind("Neeko.misc.SpeedAlly.Key3", "Hold Key to show fastest Ally", string.byte("H"), true, false, true)
                end
                Menu.ColoredText("Passive Logic HP", scriptColor, true)
                Menu.Dropdown("Neeko.misc.PassiveAllyHP.options", " ", 1, {"Show Ally HP", "Show Ally HP in %", "Don't Show lowest Ally"})
                local ddResult = OriUtils.MGet("misc.PassiveAllyHP.options") == 0
                local ddResult1 = OriUtils.MGet("misc.PassiveAllyHP.options") == 1
                if ddResult1 then
                    local allyHeroes = ObjManager.Get("ally", "heroes")

                    local addedWL = {}

                    for _, obj in pairs(allyHeroes) do
                        local hero = obj.AsHero
                        local heroName = hero.CharName

                        if hero and not hero.IsMe and not addedWL[heroName] then
                            Menu.Checkbox("Neeko.misc.passivePercent." .. heroName, "", true)
                            local allyRSliderCustom = OriUtils.MGet("misc.passivePercent." .. heroName)
                            if allyRSliderCustom then Menu.SameLine()
                                Menu.Slider("Neeko.misc.passivePercentSlider." .. heroName, "Show if < %HP for " .. heroName, 20, 1, 100, 1)
                            end
                        end
                    end
                end
                if ddResult then
                    local allyHeroes = ObjManager.Get("ally", "heroes")

                    local addedWL = {}

                    for _, obj in pairs(allyHeroes) do
                        local hero = obj.AsHero
                        local heroName = hero.CharName

                        if hero and not hero.IsMe and not addedWL[heroName] then
                            Menu.Checkbox("Neeko.misc.passiveHealth." .. heroName, "", true)
                            local allyRSliderCustom = OriUtils.MGet("misc.passiveHealth." .. heroName)
                            local allyHP = hero.BaseHealth + hero.BonusHealth
                            if allyRSliderCustom then Menu.SameLine()
                                Menu.Slider("Neeko.misc.passiveHealthSlider." .. heroName, "Show if < HP for " .. heroName, 300, 1, allyHP, 1)
                            end
                        end
                    end
                end
                Menu.Checkbox("Neeko.misc.deadAlly", "Don't show dead Allies", false)
            end)
        end)
        Menu.Separator()
        Menu.NewTree("Neeko.wlMenu", "Whitelist Settings", function()
            Menu.Text("")
            EHeader()
            Menu.Text("")
            Menu.ColumnLayout("Neeko.wlMenu.WE", "Neeko.wlMenu.E", 2, true, function()
                Menu.NewTree("Neeko.wlMenu.gapcloseE", "Gapclose E Whitelist", function()
                    local enemyHeroes = ObjManager.Get("enemy", "heroes")

                    local addedWL = {}

                    for _, obj in pairs(enemyHeroes) do
                        local hero = obj.AsHero
                        local heroName = hero.CharName

                        if hero and not addedWL[heroName] then
                            Menu.Checkbox("Neeko.gapclose.eWL." .. heroName, "Use E Gapclose on " .. heroName, true)

                            addedWL[heroName] = true
                        end
                    end
                end)
            Menu.NextColumn()
                Menu.NewTree("Neeko.wlMenu.interruptE", "Interrupt E Whitelist", function()
                    local enemyHeroes = ObjManager.Get("enemy", "heroes")

                    local addedWL = {}

                    for _, obj in pairs(enemyHeroes) do
                        local hero = obj.AsHero
                        local heroName = hero.CharName

                        if hero and not addedWL[heroName] then
                            Menu.Checkbox("Neeko.interrupt.eWL." .. heroName, "Use E Interrupt on " .. heroName, true)

                            addedWL[heroName] = true
                        end
                    end
                end)
            end)
        end)

        Menu.Separator()
        Menu.NewTree("Neeko.hcMenu", "Hitchance Settings", function()
            Menu.ColumnLayout("Neeko.hcMenu.QE", "Neeko.hcMenu.QE", 2, true, function()
                Menu.Text("")
                QHeaderHit()
                Menu.Text("")
                Menu.Slider("Neeko.hcNew.Q", "%", 30, 1, 100, 1)
                Menu.NextColumn()
                Menu.Text("")
                EHeaderHit()
                Menu.Text("")
                Menu.Slider("Neeko.hcNew.E", "%", 45, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Neeko.drawMenu", "Draw Settings", function()
            OriUtils.AddDrawMenu(drawData)
        end)
    end

    Menu.RegisterMenu(scriptName, scriptName, NeekoMenu)
end

function OnLoad()
    Neeko.InitMenu()
    
    Neeko.RegisterEvents()
    return true
end