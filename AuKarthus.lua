if Player.CharName ~= "Karthus" then return end

local scriptName = "AuKarthus"
local scriptCreator = "AURUM"
local credits = "Orietto"
local patchNotesPrevUpdate = "30/04/2022"
local patchNotesPreVersion = "1.0.5"
local patchNotesVersion, scriptVersionUpdater = "1.0.6", "1.0.6"
local scriptVersion = scriptVersionUpdater
local scriptLastUpdated = "01/05/2022"
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

SDK.AutoUpdate("https://github.com/roburAURUM/robur-AuEdition/raw/main/AuKarthus.lua", scriptVersionUpdater)

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
        Base = {90, 125, 160, 195, 230},
        TotalAP = 0.7,
        Type = dmgTypes.Magical
    },
    E = {
        Base = {30, 50, 70, 90, 110},
        TotalAP  = 0.2,
        Type = dmgTypes.Magical
    },
    R = {
        Base = {200, 350, 500},
        TotalAP = 0.75,
        Type = dmgTypes.Magical
    }
}

local spells = {
    Q = Spell.Skillshot({
        Slot = slots.Q,
        Delay = 0.90,
        Speed = huge,
        Range = 875,
        Radius = 160,
        Type = "Circular",
    }),
    W = Spell.Skillshot({
        Slot = slots.W,
        Delay = 0.25,
        Speed = huge,
        Range = 1000,
        Radius = 40,
        Type = "Circular",
    }),
    E = Spell.Active({
        Slot = slots.E,
        Range = 550,
        Type = "Circular",
    }),
    R = Spell.Active({
        Slot = slots.R,
        Delay = 0.25,
        Range = huge,
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
    [3] = {name = "SRU_Krug", dName = "Big Krug", default = true},
    [4] = {name = "SRU_KrugMini", dName = "Medium Krug", default = true},
}

local jungleCamps2 = {

    [1] = {name = "SRU_Red", dName = "Red Buff", default = true},
    [2] = {name = "SRU_Razorbeak", dName = "Big Raptor", default = true},
    [3] = {name = "SRU_RazorbeakMini", dName = "Small Raptor", default = true},
    [4] = {name = "SRU_Murkwolf", dName = "Big Wolf", default = true},
    [5] = {name = "SRU_MurkwolfMini", dName = "Small Wolf", default = true},
}

local jungleCamps3 = {
    [2] = {name = "SRU_RiftHerald", dName = "Rift Herald", default = true},
    [1] = {name = "SRU_Baron", dName = "Baron Nashor", default = true},
    [3] = {name = "SRU_Dragon_Elder", dName = "Elder Drake", default = true},
    [4] = {name = "Sru_Crab", dName = "Scuttle Crab", default = false},
    
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

    Menu.Separator()

    Menu.Checkbox(cacheName .. ".draw." .. "comboDamage", "Draw combo damage on healthbar", true)
    Menu.Checkbox("Karthus.drawMenu.addRDamage", "Include R Damage", true)
    Menu.Checkbox("Karthus.drawMenu.AlwaysDraw", "Always show Drawings", false)
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
    {slot = slots.Q, id = "Q", displayText = "[Q] Lay Waste", range = spells.Q.Range},
    {slot = slots.W, id = "W", displayText = "[W] Wall of Pain", range = spells.W.Range},
    {slot = slots.E, id = "E", displayText = "[E] Defile", range = spells.E.Range},
    {slot = slots.R, id = "R", displayText = "[R] Requiem", range = spells.R.Range}
}

local ASCIIArt = "                 _  __          _   _                "
local ASCIIArt1 = "      /\\        | |/ /         | | | |               "
local ASCIIArt2 = "     /  \\  _   _| ' / __ _ _ __| |_| |__  _   _ ___  "
local ASCIIArt3 = "    / /\\ \\| | | |  < / _` | '__| __| '_ \\| | | / __| "
local ASCIIArt4 = "   / ____ \\ |_| | . \\ (_| | |  | |_| | | | |_| \\__ \\ "
local ASCIIArt5 = "  /_/    \\_\\__,_|_|\\_\\__,_|_|   \\__|_| |_|\\__,_|___/ "

local Karthus = {}

local slotToDamageTable = {
    [slots.Q] = damages.Q,
    [slots.E] = damages.E,
    [slots.R] = damages.R
}

---@param target AIBaseClient
---@param slot slut
function Karthus.GetDamage(target, slot)
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

function Karthus.forceR()
    if OriUtils.MGet("misc.forceR") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(nil), false)
        if spells.R:Cast() then
            return
        end
    end
end


function Karthus.KS()
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
                        local qDamage = Karthus.GetDamage(enemyHero, slots.Q)
                        local healthPredQ = spells.Q:GetHealthPred(objKS)
                        if OriUtils.MGet("ks.qWL." .. enemyHero.CharName, true) then
                            if healthPredQ > 0 and healthPredQ < floor(qDamage - 10) then
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
        local rReady = OriUtils.CanCastSpell(slots.R, "ks.useR")
        local rTargets = spells.R:GetTargets()
        local IsWindingUp = Orbwalker.IsWindingUp()
        for iKSAR, objKSAR in ipairs(allyHeroesR) do
            local ally = objKSAR.AsHero
            if not ally.IsMe and not ally.IsDead then
                if rTargets then
                    for iKS, objKS in ipairs(rTargets) do
                        local enemyHero = objKS.AsHero
                        local rDamage = Karthus.GetDamage(enemyHero, slots.R)
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

function Karthus.DrakeSteal()
    if OriUtils.CanCastSpell(slots.Q, "steal.useQ") then 
        local heroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        if heroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.Q.Range) then
                    local qStats = Karthus.GetDamage(minion, slots.Q)
                    local qDamage = (qStats / 100) * 95
                    local healthPredDrakeQ = spells.Q:GetHealthPred(minion)
                    if minion.IsDragon then
                        if healthPredDrakeQ > 0 and healthPredDrakeQ < floor(qDamage - 5) then
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

function Karthus.BaronSteal()
    if OriUtils.CanCastSpell(slots.Q, "steal.useQ") then 
        local heroCheck = TS:GetTarget(1500)
        local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
        if heroCheck then
            for iM, minion in ipairs(nearbyMinions) do
                local minion = minion.AsMinion
                if OriUtils.IsValidTarget(minion, spells.Q.Range) then
                    local qStats = Karthus.GetDamage(minion, slots.Q)
                    local qDamage = (qStats / 100) * 95
                    local healthPredBaronQ = spells.Q:GetHealthPred(minion)
                    if minion.IsBaron then
                        if healthPredBaronQ > 0 and healthPredBaronQ < floor(qDamage - 5) then
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

function Karthus.BigDickOriettoEnergy(minionTable, range)
    for _, minion in ipairs(minionTable) do
        if OriUtils.IsValidTarget(minion, range) then
            return true
        end
    end

    return false
end

function Karthus.HasE()
    return Player:GetBuff("KarthusDefile")
end

function Karthus.HasPassive()
    return Player:GetSpell(slots.E).Name == "KarthusDefile2"
end

function Karthus.DeadSpam()
    if OriUtils.MGet("misc.isDead") and Karthus.HasPassive() then
        local qTarget = spells.Q:GetTarget()
        local wTarget = spells.W:GetTarget()
        if wTarget then
            if spells.W:Cast(wTarget) then
                return
            end
        end
        if qTarget then
            if spells.Q:CastOnHitChance(qTarget, OriUtils.MGet("hc.Q") / 100) then
                return
            end
        end
    end
end

function Karthus.QToggle()
    if OriUtils.CanCastSpell(slots.Q, "misc.qToggle") then
        local qTarget = spells.Q:GetTarget()
        if qTarget then
            if spells.Q:CastOnHitChance(qTarget, OriUtils.MGet("hc.Q") / 100) then
                return
            end
        end
    end
end

function Karthus.CanKill()
    local target = ObjManager.Get("enemy", "heroes")
    if OriUtils.CanCastSpell(slots.R, "misc.canKill") then
        for _, obj in pairs(target) do
            if not obj.IsDead and obj.IsHero and not obj.IsZombie and not obj.IsInvulnerable then
                local enemyHero = obj.AsHero
                local rDamage = Karthus.GetDamage(enemyHero, slots.R)
                local healthPredR = spells.R:GetHealthPred(obj)
                if healthPredR > 0 and healthPredR < floor(rDamage - 50) then
                    return Renderer.DrawTextOnPlayer("Can Kill: " .. enemyHero.CharName, 0xFF00FFFF)
                end
            end
        end
    end
end


function combatVariants.Combo()

    if OriUtils.CanCastSpell(slots.E, "combo.useE") then
        local playerMana = Player.ManaPercent * 100
        if playerMana >= OriUtils.MGet("combo.EManaSlider") then
            local eTarget = spells.E:GetTarget()
            if not Karthus.HasE() then
                if eTarget then
                    if spells.E:Cast() then
                        return
                    end
                end
            else
                if not eTarget then
                    if spells.E:Cast() then
                        return
                    end
                end
            end
        end
    end
    
    if OriUtils.CanCastSpell(slots.W, "combo.useW") then
        local playerMana = Player.ManaPercent * 100
        if playerMana >= OriUtils.MGet("combo.WManaSlider") then
            local wTarget = spells.W:GetTarget()
            if wTarget then
                if spells.W:CastOnHitChance(wTarget, OriUtils.MGet("hc.W") / 100) then
                    return
                end
            end
            
        end
    end

    if OriUtils.CanCastSpell(slots.Q, "combo.useQ") then
        local playerMana = Player.ManaPercent * 100
        local isWindingUp = Orbwalker.IsWindingUp()
        if playerMana >= OriUtils.MGet("combo.QManaSlider") then
            local qTarget = spells.Q:GetTarget()
            if qTarget and not isWindingUp then
                if spells.Q:CastOnHitChance(qTarget, OriUtils.MGet("hc.Q") / 100) then
                    return
                end
            end
        end
    end
end

function combatVariants.Harass()
    if OriUtils.CanCastSpell(slots.Q, "harass.useQ") then
        local qTarget = spells.Q:GetTarget()
        if qTarget then
            if spells.Q:CastOnHitChance(qTarget, OriUtils.MGet("hc.Q") / 100) then
                return
            end
        end
    end
end

function combatVariants.Waveclear()


    if OriUtils.CanCastSpell(slots.E, "jglclear.useE") then
        local jglminionsE = ObjManager.GetNearby("neutral", "minions")
        local playerMana = Player.ManaPercent * 100
        if playerMana >= OriUtils.MGet("jglclear.EManaSlider") and not Orbwalker.IsFastClearEnabled() then
            local jglminionsE = ObjManager.GetNearby("neutral", "minions")
            local eDrake = OriUtils.MGet("jgl.eDrake")
            for iJGLE, objJGLE in ipairs(jglminionsE) do
                if Karthus.BigDickOriettoEnergy(jglminionsE, spells.E.Range) then
                    if not Karthus.HasE() then
                        local minionName = objJGLE.CharName
                        if OriUtils.MGet("jgl.eWL." .. minionName, true) or objJGLE.IsDragon and eDrake then
                            local aaDamage = Orbwalker.GetAutoAttackDamage(objJGLE)
                            if objJGLE.Health > aaDamage then
                                if spells.E:Cast() then
                                    return
                                end
                            end
                        end
                    end
                else
                    if Karthus.HasE() then
                        if spells.E:Cast() then
                            return
                        end
                    end
                end            
            end
        end
    end

    if OriUtils.CanCastSpell(slots.Q, "jglclear.useQ") then
        local jglminionsQ = ObjManager.Get("neutral", "minions")
        local minionsPositions = {}
        local qDrake = OriUtils.MGet("jgl.qDrake")
        local qMana = OriUtils.MGet("jglclear.QManaSlider")
        local playerMana = Player.ManaPercent * 100
        local IsWindingUp = Orbwalker.IsWindingUp()
        local hcQ = OriUtils.MGet("hc.Q") / 100


        if playerMana >= qMana then
            for iJGLQ, objJGLQ in pairs(jglminionsQ) do
                local minion = objJGLQ.AsMinion
                local minionName = objJGLQ.CharName
                if OriUtils.IsValidTarget(objJGLQ, spells.Q.Range) then
                    if OriUtils.MGet("jgl.qWL." .. minionName, true) or objJGLQ.IsDragon and qDrake then
                        if OriUtils.MGet("jglclear.useQPred") then
                            local pred = spells.Q:GetPrediction(objJGLQ)
                            if pred and pred.HitChance >= hcQ then
                                insert(minionsPositions, pred.TargetPosition)
                            end
                        else
                            insert(minionsPositions, minion.Position)
                        end
                    end
                end
            end
            local bestPos, numberOfHits = Geometry.BestCoveringCircle(minionsPositions, spells.Q.Radius)
            
            if numberOfHits >= 1 and not IsWindingUp then
                if spells.Q:Cast(bestPos) then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "clear.useE") then
        local minionsE = ObjManager.GetNearby("enemy", "minions")
        local isFastClear = Orbwalker.IsFastClearEnabled()
        local isWindingUp
        for iclearE, objclearE in ipairs(minionsE) do
            if isFastClear then
                if Karthus.BigDickOriettoEnergy(minionsE, spells.E.Range) then
                    if not Karthus.HasE() then
                        if spells.E:Cast() then
                            return
                        end
                    end
                else
                    if Karthus.HasE() then
                        if spells.E:Cast() then
                            return
                        end
                    end
                end
            else
                if Karthus.HasE() then
                    if spells.E:Cast() then
                        return
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.Q, "clear.useQ") then
        local minionsQ = ObjManager.GetNearby("enemy", "minions")
        local minionsPositions = {}
        local hcQ = OriUtils.MGet("hc.Q") / 100

        for iQ, objQ in ipairs(minionsQ) do
            local minion = objQ.AsMinion
            local minionName = objQ.CharName
            if OriUtils.IsValidTarget(objQ, spells.Q.Range) then
                if OriUtils.MGet("clear.useQPred") then
                    local pred = spells.Q:GetPrediction(objQ)
                    if pred and pred.HitChance >= hcQ then
                        insert(minionsPositions, pred.TargetPosition)
                    end
                else
                    insert(minionsPositions, minion.Position)
                end
            end
        end
        local bestPos, numberOfHits = Geometry.BestCoveringCircle(minionsPositions, spells.Q.Radius)
        local qMana = OriUtils.MGet("clear.QManaSlider")
        if Orbwalker.IsFastClearEnabled() then
            if numberOfHits >= 1 then
                if spells.Q:Cast(bestPos) then
                    return
                end
            end
        else
            if Player.ManaPercent * 100 >= qMana then
                if numberOfHits >= 1 then
                    if spells.Q:Cast(bestPos) then
                        return
                    end
                end
            end
        end
    end
end

function combatVariants.Lasthit()
    if OriUtils.CanCastSpell(slots.Q, "lasthit.useQ") then
        local qMinions = ObjManager.GetNearby("enemy", "minions")
        for iQ, minionQ in ipairs(qMinions) do 
            local healthPred = spells.Q:GetHealthPred(minionQ)
            local minion = minionQ.AsMinion
            local qDamage = Karthus.GetDamage(minion, slots.Q)
            if OriUtils.IsValidTarget(minionQ, spells.Q.Range) then
                if healthPred > 0 and healthPred < floor(qDamage / 2) then
                    if spells.Q:Cast(minion) then
                        return
                    end
                end
            end
        end
    end
end

function combatVariants.Flee()
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

    Karthus.CanKill()
    Karthus.QToggle()
    Karthus.DeadSpam()
    Karthus.forceR()
    Karthus.KS()
    Karthus.BaronSteal()
    Karthus.DrakeSteal()
end

---@param source GameObject
---@param dashInstance DashInstance
function events.OnGapclose(source, dashInstance)
    if source.IsHero and source.IsEnemy then
        if spells.W:IsReady() and OriUtils.MGet("gapclose.W") and spells.W:IsInRange(source) then
            if OriUtils.MGet("gapclose.wWL." .. source.CharName, true) then
                delay(OriUtils.MGet("gapclose.wDelay." .. source.CharName, true), function()spells.W:Cast(source) end)
                return
            end
        end
    end
end

function events.OnDraw()
    if Player.IsDead then
        return
    end

    Karthus.CanKill()

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

    --DrawUnderPlayer
    if OriUtils.MGet("misc.qToggle") then
        Renderer.DrawTextOnPlayer("Q Toggle: ACTIVE", 0x00FF00FF)
    
    end
end

function events.OnDrawDamage(target, dmgList)
    if not OriUtils.MGet("draw.comboDamage") then
        return
    end

    local damageToDeal = 0

    if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
        damageToDeal = damageToDeal + Karthus.GetDamage(target, slots.Q)
    end

    if spells.W:IsReady() and OriUtils.MGet("combo.useW") then
        damageToDeal = damageToDeal + Karthus.GetDamage(target, slots.W)
    end

    if spells.E:IsReady() and OriUtils.MGet("combo.useE") then
        damageToDeal = damageToDeal + Karthus.GetDamage(target, slots.E)
    end

    if spells.R:IsReady() and OriUtils.MGet("drawMenu.addRDamage") then
        damageToDeal = damageToDeal + Karthus.GetDamage(target, slots.R)
    end

    insert(dmgList, damageToDeal)
end

function Karthus.RegisterEvents()
    for eventName, eventId in pairs(Enums.Events) do
        if events[eventName] then
            EventManager.RegisterCallback(eventId, events[eventName])
        end
    end
end

function Karthus.InitMenu()
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

    local function KarthusMenu()
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
        
        if Menu.Checkbox("Karthus.Updates105", "Don't show updates") == false then
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. scriptLastUpdated .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesVersion, 0XFFFF00FF, true)
            Menu.Text("- Added Lasthit Q", true)
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. patchNotesPrevUpdate .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesPreVersion, 0XFFFF00FF, true)
            Menu.Text("- Initial Release of AuKarthus 1.0.0", true)
        end

        Menu.Separator()

        Menu.NewTree("Karthus.comboMenu", "Combo Settings", function()
            Menu.ColumnLayout("Karthus.comboMenu.QE", "Karthus.comboMenu.QE", 3, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Karthus.combo.useQ", "Enable Q", true)
                Menu.Slider("Karthus.combo.QManaSlider", "Don't use if Mana < %", 5, 1, 100, 1)
                Menu.NextColumn()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Karthus.combo.useW", "Enable W", true)
                Menu.Slider("Karthus.combo.WManaSlider", "Don't use if Mana < %", 10, 1, 100, 1)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Karthus.combo.useE", "Enable E", true)
                Menu.Slider("Karthus.combo.EManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Karthus.harassMenu", "Harass Settings", function()
            Menu.ColumnLayout("Karthus.harassMenu.Q", "Karthus.harassMenu.Q", 1, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Karthus.harass.useQ", "Enable Q", true)
            end)

        end)
        Menu.Separator()

        Menu.NewTree("Karthus.clearMenu", "Clear Settings", function()
            Menu.NewTree("Karthus.waveMenu", "Waveclear", function()
                Menu.ColoredText("Holding LMB (Fast Clear) is required for E", scriptColor, true)
                Menu.Checkbox("Karthus.clear.useQ", "Use Q", false)
                Menu.Checkbox("Karthus.clear.useQPred", "Use Prediction for Waveclear", true)
                Menu.Slider("Karthus.clear.QManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Checkbox("Karthus.clear.useE", "Enable E", true)
            end)
            Menu.NewTree("Karthus.jglMenu", "Jungleclear", function()
                Menu.Checkbox("Karthus.jglclear.useQ", "Use Q", true)
                Menu.Checkbox("Karthus.jglclear.useQPred", "Use Prediction for Junglecamps", true)
                Menu.ColumnLayout("Karthus.jglclear.qWhitelist", "Karthus.jglclear.qWhitelist", 3, true, function()
                    Menu.Indent(function()
                        Menu.NewTree("Karthus.jglclear.qlist", "Jungle Camps 1", function()
                            for i, v in ipairs(jungleCamps) do
                                Menu.Checkbox("Karthus.jgl.qWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Karthus.jglclear.qlist2", "Jungle Camps 2", function()
                            for i, v in ipairs(jungleCamps2) do
                                Menu.Checkbox("Karthus.jgl.qWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Karthus.jglclear.qlist3", "Jungle Camps 3", function()
                            for i, v in ipairs(jungleCamps3) do
                                Menu.Checkbox("Karthus.jgl.qWL." .. v.name, v.dName, v.default)
                            end
                            Menu.Checkbox("Karthus.jgl.qDrake", "Other Drakes", true)
                        end)
                    end)
                end)
                Menu.Slider("Karthus.jglclear.QManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Separator()
                Menu.Checkbox("Karthus.jglclear.useE", "Use E", true)
                Menu.ColumnLayout("Karthus.jglclear.eWhitelist", "Karthus.jglclear.eWhitelist", 3, true, function()
                    Menu.Indent(function()
                        Menu.NewTree("Karthus.jglclear.elist", "Jungle Camps 1", function()
                            for i, v in ipairs(jungleCamps) do
                                Menu.Checkbox("Karthus.jgl.eWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Karthus.jglclear.elist2", "Jungle Camps 2", function()
                            for i, v in ipairs(jungleCamps2) do
                                Menu.Checkbox("Karthus.jgl.eWL." .. v.name, v.dName, v.default)
                            end
                        end)
                        Menu.NextColumn()
                        Menu.NewTree("Karthus.jglclear.elist3", "Jungle Camps 3", function()
                            for i, v in ipairs(jungleCamps3) do
                                Menu.Checkbox("Karthus.jgl.eWL." .. v.name, v.dName, v.default)
                            end
                            Menu.Checkbox("Karthus.jgl.eDrake", "Other Drakes", true)
                        end)
                    end)
                end)
                Menu.Slider("Karthus.jglclear.EManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
            end)
        end)

        Menu.Separator()

        Menu.NewTree("Karthus.lasthitMenu", "Lasthit Settings", function()
            Menu.ColumnLayout("Karthus.lasthitMenu.Q", "Karthus.lasthitMenu.Q", 1, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Karthus.lasthit.useQ", "Enable Q", true)
            end)
        end)

        Menu.Separator()

        Menu.NewTree("Karthus.stealMenu", "Steal Settings", function()
            Menu.NewTree("Karthus.ksMenu", "Killsteal", function()
                Menu.Checkbox("Karthus.ks.useQ", "Killsteal with Q", true)
                local cbResult = OriUtils.MGet("ks.useQ")
                if cbResult then
                    Menu.Indent(function()
                        Menu.NewTree("Karthus.ksMenu.qWhitelist", "KS Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Karthus.ks.qWL." .. heroName, "Q KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Karthus.ks.useR", "Killsteal with R", false)
                local cbResult3 = OriUtils.MGet("ks.useR")
                if cbResult3 then
                    Menu.Indent(function()
                        Menu.NewTree("Karthus.ksMenu.rWhitelist", "KS R Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Karthus.ks.rWL." .. heroName, "R KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
            end)
            Menu.NewTree("Karthus.jglstealMenu", "Junglesteal (Drake/Baron) | BETA", function()
                Menu.Checkbox("Karthus.steal.useQ", "Junglesteal with Q", true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Karthus.miscMenu", "Misc Settings", function()
            Menu.ColumnLayout("Karthus.miscMenu.R", "Karthus.miscMenu.R", 3, true, function()
                QHeader()
                Menu.Checkbox("Karthus.misc.isDead", "Use Spells when in Passive (Dead)", true)
                Menu.Keybind("Karthus.misc.qToggle", "Toggle Q", string.byte("G"), true, false, true)
                Menu.NextColumn()
                WHeader()
                Menu.Checkbox("Karthus.gapclose.W", "Gapclose with W", true)
                local cbResult4 = OriUtils.MGet("gapclose.W")
                if cbResult4 then
                    Menu.Indent(function()
                        Menu.NewTree("Karthus.miscMenu.gapcloseQ", "Gapclose W Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Karthus.gapclose.wWL." .. heroName, "Use W Gapclose on " .. heroName, true)
                                    Menu.Slider("Karthus.gapclose.wDelay." .. heroName, "Delay", 110, 0, 500, 1)
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.NextColumn()
                Menu.Text("")
                RHeader()
                Menu.Keybind("Karthus.misc.forceR", "Force R", string.byte("T"), false, false, true)
                Menu.Checkbox("Karthus.misc.canKill", "Show if Champion can be killed", true)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Karthus.hcMenu", "Hitchance Settings", function()
            Menu.ColumnLayout("Karthus.hcMenu.QW", "Karthus.hcMenu.QW", 2, true, function()
                Menu.Text("")
                QHeaderHit()
                Menu.Text("")
                Menu.Slider("Karthus.hc.Q", "%", 20, 1, 100, 1)
                Menu.NextColumn()
                Menu.Text("")
                WHeaderHit()
                Menu.Text("")
                Menu.Slider("Karthus.hc.W", "%", 10, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Karthus.drawMenu", "Draw Settings", function()
            OriUtils.AddDrawMenu(drawData)
        end)
    end

    Menu.RegisterMenu(scriptName, scriptName, KarthusMenu)
end

function OnLoad()
    Karthus.InitMenu()
    
    Karthus.RegisterEvents()
    return true
end