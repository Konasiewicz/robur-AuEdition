if Player.CharName ~= "Nami" then return end


local scriptName = "AuNami"
local scriptCreator = "AURUM"
local credits = "Orietto & Thorn"
local patchNotesPrevUpdate = "11/27/2021"
local patchNotesPreVersion, patchNotesVersion, scriptVersionUpdater = "1.2.5", "1.2.7", "1.2.7"
local scriptVersion = scriptVersionUpdater
local scriptLastUpdated = "2/18/2022"
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

SDK.AutoUpdate("https://raw.githubusercontent.com/roburAURUM/robur-AuEdition/main/AuNami.lua", scriptVersionUpdater)

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
        Base = {75, 130, 185, 240, 295},
        TotalAP = 0.5,
        Type = dmgTypes.Magical
    },
    W = {
        Base = {70, 110, 150, 190, 230},
        TotalAP  = 0.5,
        Type = dmgTypes.Magical
    },
    E = {
        Base = {25, 40, 55, 70, 85},
        TotalAP  = 0.2,
        Type = dmgTypes.Magical
    },
    R = {
        Base = {150, 250, 350},
        TotalAP = 0.6,
        Type = dmgTypes.Magical
    }
}

local spells = {
    Q = Spell.Skillshot({
        Slot = slots.Q,
        Delay = 0.25 + 1.0,
        Speed = huge,
        Range = 875,
        Radius = 135,
        Type = "Circular",
        Collisions = {Windwall = true}
    }),
    W = Spell.Targeted({
        Slot = slots.W,
        Delay = 0.25,
        Range = 725,
        Collisions = {Windwall = true}
    }),
    E = Spell.Targeted({
        Slot = slots.E,
        Range = 800,
    }),
    R = Spell.Skillshot({
        Slot = slots.R,
        Delay = 0.5,
        Speed = 860,
        Range = 2600,
        Radius = 500 / 2,
        Type = "Linear",
        Collisions = {Windwall = true}
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

    Menu.Checkbox(cacheName .. ".draw." .. "comboDamage", "Draw combo damage on healthbar", false)
    Menu.Checkbox("Nami.drawMenu.AlwaysDraw", "Always show Drawings", false)
    Menu.Checkbox("Nami.Draw.R.Minimap",   "Draw [R] Tidal Wave on Minimap")
    Menu.ColorPicker("Draw.R.ColorMinimap", "Draw [R] Color", scriptColor)
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
    {slot = slots.Q, id = "Q", displayText = "[Q] Aqua Prison", range = spells.Q.Range},
    {slot = slots.W, id = "W", displayText = "[W] Ebb and Flow", range = spells.W.Range},
    {slot = slots.E, id = "E", displayText = "[E] Tidecaller's Blessing", range = spells.E.Range},
    {slot = slots.R, id = "R", displayText = "[R] Tidal Wave", range = spells.R.Range}
}



local ASCIIArt = "                 _   _                 _  "	 
local ASCIIArt2 = "      /\\        | \\ | |               (_) "
local ASCIIArt3 = "     /  \\  _   _|  \\| | __ _ _ __ ___  _  "
local ASCIIArt4 = "    / /\\ \\| | | | . ` |/ _` | '_ ` _ \\| | "
local ASCIIArt5 = "   / ____ \\ |_| | |\\  | (_| | | | | | | | "
local ASCIIArt6 = "  /_/    \\_\\__,_|_| \\_|\\__,_|_| |_| |_|_| "

local Nami = {}

Nami.baseAADamage = Player.BaseAttackDamage
Nami.AD = Nami.baseAADamage + Player.FlatPhysicalDamageMod

local slotToDamageTable = {
    [slots.Q] = damages.Q,
    [slots.W] = damages.W,
    [slots.E] = damages.E,
    [slots.R] = damages.R
}

---@param target AIBaseClient
---@param slot slut
function Nami.GetDamage(target, slot)
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


function Nami.forceW()
    local getAllies = ObjManager.GetNearby("ally", "heroes")
    ---@param objA GameObject
    ---@param objB GameObject
    local function allyComparator(objA, objB)

        local mousePos = Renderer.GetMousePos()

        return mousePos:Distance(objA) < mousePos:Distance(objB)
    end
    sort(getAllies, allyComparator)
    if OriUtils.MGet("misc.forceW") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(nil), false)
        for iForce, objForce in ipairs(getAllies) do
            local heroForce = objForce.AsHero
            if not heroForce.IsMe and not heroForce.IsDead and spells.W:IsInRange(heroForce) then
                if OriUtils.MGet("misc.wWL") then
                    if OriUtils.MGet("combo.wWL." .. heroForce.CharName, true) then
                        if heroForce.HealthPercent * 100 <= Player.HealthPercent * 100 then
                            if spells.W:Cast(heroForce) then
                                return
                            end
                        else
                            if spells.W:Cast(Player) then
                                return
                            end
                        end
                    end
                else
                    if heroForce.HealthPercent * 100 <= Player.HealthPercent * 100 then
                        if spells.W:Cast(heroForce) then
                            return
                        end
                    else
                        if spells.W:Cast(Player) then
                            return
                        end
                    end
                end
            end
        end
        if spells.W:Cast(Player) then
            return
        end
    end
end

function Nami.forceR()
    if OriUtils.MGet("misc.forceR") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)
        local enemyPositions = {}
        
        for iR, objR in ipairs(TS:GetTargets(spells.R.Range)) do
            local pred = spells.R:GetPrediction(objR)
            if pred and pred.HitChance >= (OriUtils.MGet("hcNew.R") / 100) then
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

function combatVariants.Combo()
    if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
        local enemyPositions = {}
        for i, obj in ipairs(TS:GetTargets(spells.R.Range)) do
            local pred = spells.R:GetPrediction(obj)
            if pred and pred.HitChance >= OriUtils.MGet("hcNew.R") / 100 then
                table.insert(enemyPositions, pred.CastPosition)
            end
        end
        local bestPos, numberOfHits = Geometry.BestCoveringRectangle(enemyPositions, Player.Position, spells.R.Radius * 2)
        if numberOfHits >= OriUtils.MGet("combo.useR.minEnemies") then
            if spells.R:Cast(bestPos) then
                return
            end
        end
    end

    if spells.E:IsReady() then
        if OriUtils.MGet("combo.allyE") then
            local alliesNearby = ObjManager.GetNearby("ally", "heroes")
            for iAllyC, objAllyC in ipairs(alliesNearby) do
                local hero = objAllyC.AsHero
                if not hero.IsMe and not hero.IsDead and spells.E:IsInRange(hero) then
                    local enemiesNearby = ObjManager.GetNearby("enemy", "heroes")
                    for iE, objE in ipairs(enemiesNearby) do
                        local enemyH = objE.AsHero
                        local teammateAA = Orbwalker.GetTrueAutoAttackRange(hero)
                        if OriUtils.IsValidTarget(objE, spells.E.Range) then
                            if teammateAA >= hero:Distance(enemyH) then
                                if OriUtils.MGet("combo.eWL." .. hero.CharName, true) then
                                    if spells.E:Cast(hero) then
                                        return
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        if OriUtils.MGet("combo.selfE") then
            local eTarget = spells.E:GetTarget()
            if eTarget then
                if spells.E:Cast(Player) then
                    return
                end
            else
                local enemysNearby = ObjManager.GetNearby("enemy", "heroes")
                for iSelfE, objSelfE in ipairs(enemysNearby) do
                    local enemyH = objSelfE.AsHero
                    if OriUtils.IsValidTarget(objSelfE) then
                        if enemyH.IsFleeing then
                            if spells.Q:IsInRange(enemyH) then
                                if spells.E:Cast(Player) then
                                    return
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
        local qTarget = spells.Q:GetTarget()
        if qTarget and not Orbwalker.IsWindingUp() then
            if spells.Q:CastOnHitChance(qTarget, OriUtils.MGet("hcNew.Q") / 100) then
                return
            end
        end
    end

    local wTarget = spells.W:GetTarget()
    if spells.W:IsReady() then
        if OriUtils.MGet("combo.allyW") then
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
                if not hero.IsDead and not hero.IsMe and spells.W:IsInRange(hero) then
                    if hero.HealthPercent * 100 <= OriUtils.MGet("combo.allyWSlider") then
                        local enemyForW = ObjManager.GetNearby("enemy", "heroes")
                        for iE, objE in ipairs(enemyForW) do
                            local enemyAround = objE.AsHero
                            if OriUtils.IsValidTarget(objE) then
                                if OriUtils.MGet("combo.wWL." .. hero.CharName, true) then
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

        if OriUtils.MGet("combo.selfW") then
            if Player.HealthPercent * 100 <= OriUtils.MGet("combo.selfWSlider") then
                if wTarget then
                    local enemysNearby = ObjManager.GetNearby("enemy", "heroes")
                    for iSelfW, objSelfW in ipairs(enemysNearby) do
                        local enemyW = objSelfW.AsHero
                        if not enemyW.IsDead and spells.W:IsInRange(enemyW) then
                            if spells.W:Cast(Player) then
                                return
                            end
                        end
                    end
                end
            end
        end

        if OriUtils.MGet("combo.useW") then
            if wTarget and not Orbwalker.IsWindingUp() then
                if spells.W:Cast(wTarget) then
                    return
                end
            end
        end

        if OriUtils.MGet("combo.extendedW") then
            if not wTarget then
                local alliesNearby = ObjManager.GetNearby("ally", "heroes")
                for iExt, objExt in ipairs(alliesNearby) do
                    local heroExt = objExt.AsHero
                    if not heroExt.IsDead and not heroExt.IsMe and spells.W:IsInRange(heroExt) then
                        local enemysNearby = ObjManager.GetNearby("enemy", "heroes")
                        for iE, objExtE in ipairs(enemysNearby) do
                            local enemyExt = objExtE.AsHero
                            if OriUtils.IsValidTarget(objExtE) then
                                if heroExt:Distance(enemyExt) < 650 then
                                    if Player.ManaPercent * 100 >= OriUtils.MGet("combo.extendedWSlider") then
                                        if spells.W:Cast(heroExt) then
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

function combatVariants.Harass()
    if OriUtils.MGet("harass.useE") then
        local eTarget = spells.E:GetTarget()
        if eTarget then
            if spells.E:Cast(Player) then
                return
            end
        end
    end

    if OriUtils.MGet("harass.useW") then
        local wTarget = spells.W:GetTarget()
        if wTarget then
            if spells.W:Cast(wTarget) then
                return
            end
        end
    end

end


function combatVariants.Waveclear()
    if OriUtils.MGet("clear.enemiesAround") and TS:GetTarget(1800) then
        return
    end

    if spells.Q:IsReady() and OriUtils.MGet("clear.useQ") then
        local minionsInERange = OriUtils.GetEnemyAndJungleMinions(spells.Q.Range)
        local minionsPositions = {}
        for _, minion in ipairs(minionsInERange) do
            insert(minionsPositions, minion.Position)
        end
        local bestPos, numberOfHits = Geometry.BestCoveringCircle(minionsPositions, spells.Q.Radius) 
        if numberOfHits >= OriUtils.MGet("clear.QSlider") then
            if spells.Q:Cast(bestPos) then
                return
            end
        end
    end

    if OriUtils.MGet("clear.useE") then
        local alliesWave = ObjManager.GetNearby("ally", "heroes")
        for iWave, objWave in ipairs(alliesWave) do
            local ally = objWave.AsHero
            if not ally.IsMe and not ally.IsDead then
                if spells.E:IsInRange(ally) then
                    if not Orbwalker.IsWindingUp() then
                        if spells.E:Cast(ally) then
                            return
                        end
                    end
                end
            end
        if spells.E:Cast(Player) then
                return
            end
        end
    end
end

function combatVariants.Lasthit()
end

function combatVariants.Flee()
    if spells.W:IsReady() and spells.E:IsReady() then
        local alliesF = ObjManager.GetNearby("ally", "heroes")
        for iAlly, objAlly in ipairs(alliesF) do
            local ally = objAlly.AsHero
            if not ally.IsMe and not ally.IsDead and Player.Health > ally.Health then
                if spells.W:IsInRange(ally) then
                    if spells.W:Cast(ally) then
                        if spells.E:Cast(Player) then
                            return
                        end
                    end
                end
            elseif not ally.IsMe and Player.Health < ally.Health then
                if spells.E:IsInRange(ally) then
                    if spells.E:Cast(ally) then
                        if spells.W:Cast(Player) then
                            return
                        end
                    end
                end
            end
        end
    end
    if spells.E:IsReady() then
        if spells.E:Cast(Player) then
            return
        end
    end
end

function events.OnTick()

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

    Nami.forceW()
    Nami.forceR()
end

function events.OnDrawDamage(target, dmgList)
    if not OriUtils.MGet("draw.comboDamage") then
        return
    end

    local damageToDeal = 0

    if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
        damageToDeal = damageToDeal + Nami.GetDamage(target, slots.Q)
    end

    if spells.W:IsReady() and OriUtils.MGet("combo.useW") then
        damageToDeal = damageToDeal + Nami.GetDamage(target, slots.W)
    end

    if spells.E:IsReady() and OriUtils.MGet("combo.selfE") then
        damageToDeal = damageToDeal + ((Nami.GetDamage(target, slots.E) + Nami.AD) * 3)
    end
    if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
        damageToDeal = damageToDeal + Nami.GetDamage(target, slots.R)
    end

    insert(dmgList, damageToDeal)
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
            if OriUtils.CanCastSpell(slots.R, "Draw.R.Minimap") then
                Renderer.DrawCircleMM(myPos, spells.R.Range, 2, Menu.Get("Draw.R.ColorMinimap"))
            end
        else
            if Player:GetSpell(slot).IsLearned then
                Renderer.DrawCircle3D(myPos, range, 30, 2, OriUtils.MGet("draw." .. id .. ".color"))
            end
            if Player:GetSpell(slot).IsLearned then
                Renderer.DrawCircleMM(myPos, spells.R.Range, 2, Menu.Get("Draw.R.ColorMinimap"))
            end
        end
    end
end

---@param source GameObject
---@param dashInstance DashInstance
function events.OnGapclose(source, dashInstance)
    if source.IsHero and source.IsEnemy and spells.Q:IsInRange(source) then
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

        --[[if spells.R:IsReady() and OriUtils.MGet("gapclose.R") then
            local pred = spells.R:GetPrediction(source)
            if pred and pred.HitChanceEnum >= Enums.HitChance.Dashing then
                if spells.R:Cast(pred.CastPosition) then
                    return
                end
            end
        end]]--
    end
end


---@param source GameObject
function events.OnInterruptibleSpell(source, spellCast, danger, endTime, canMoveDuringChannel)
    if source.IsHero and source.IsEnemy and spells.Q:IsInRange(source) then
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
            if danger >= 5 and spells.R:IsInRange(source) then
                if OriUtils.MGet("interrupt.rWL." .. source.CharName, true) then
                    local pred = spells.R:GetPrediction(source)
                    if pred and pred.HitChanceEnum >= Enums.HitChance.Medium then
                        if spells.R:Cast(pred.CastPosition) then
                            return
                        end
                    end
                end
            end
        end
    end
end



function Nami.RegisterEvents()
    for eventName, eventId in pairs(Enums.Events) do
        if events[eventName] then
            EventManager.RegisterCallback(eventId, events[eventName])
        end
    end
end

-- Menu

function Nami.InitMenu()
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

    local function NamiMenu()
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
            Menu.ColoredText("This script is in an early stage!", 0xFFFF00FF, true)
            Menu.ColoredText("Please keep in mind, that you might encounter bugs/issues.", 0xFFFF00FF, true)
            Menu.ColoredText("If you find any, please contact " .. scriptCreator .. " via robur.lol", 0xFF0000FF, true)
        end

        if Menu.Checkbox("Nami.Updates125", "Don't show updates") == false then
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. scriptLastUpdated .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesVersion, 0XFFFF00FF, true)
            Menu.Text("- Adjusted Hitchance for new Prediction", true)
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. patchNotesPrevUpdate .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesPreVersion, 0XFFFF00FF, true)
            Menu.Text("- Tried different Method of W E Usage Enemy FOW Fix", true)
            Menu.Text("- Fixed other minor Bugs", true)
        end

        Menu.Separator()

        Menu.NewTree("Nami.comboMenu", "Combo Settings", function()

            Menu.ColumnLayout("Nami.comboMenu.Q", "Nami.comboMenu.Q", 1, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Nami.combo.useQ", "Enable Q", true)
                Menu.Separator()
            end)

            Menu.ColumnLayout("Nami.comboMenu.WR", "Nami.comboMenu.WR", 2, true, function()
                WHeader()
                Menu.Checkbox("Nami.combo.useW", "Enable W vs Enemy", true)
                Menu.Checkbox("Nami.combo.extendedW", "Enable Extended W", true)
                local cbResult = OriUtils.MGet("combo.extendedW")
                if cbResult then
                    Menu.Slider("Nami.combo.extendedWSlider", "if Mana above X%", 30, 1, 100, 1)
                end
                Menu.Checkbox("Nami.combo.allyW", "Enable W Ally", true)
                local cbResult2 = OriUtils.MGet("combo.allyW")
                if cbResult2 then
                    Menu.Indent(function()
                        Menu.Slider("Nami.combo.allyWSlider", "if < %HP", 30, 1, 100, 1)
                        Menu.NewTree("Nami.combo.wWhitelist", "W Whitelist", function()
                            local allyHeroes = ObjManager.Get("ally", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(allyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if not hero.IsMe and hero and not addedWL[heroName] then
                                    Menu.Checkbox("Nami.combo.wWL." .. heroName, "Use W on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Nami.combo.selfW", "Enable W Self", true)
                local cbResult4 = OriUtils.MGet("combo.selfW")
                if cbResult4 then
                    Menu.Slider("Nami.combo.selfWSlider", "if < %HP", 30, 1, 100, 1)
                end                
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Nami.combo.allyE", "Enable E for Ally", true)
                local cbResult3 = OriUtils.MGet("combo.allyE")
                if cbResult3 then
                    Menu.Indent(function()
                        Menu.NewTree("Nami.combo.eWhitelist", "E Whitelist", function()
                            local allyHeroes = ObjManager.Get("ally", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(allyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if not hero.IsMe and hero and not addedWL[heroName] then
                                    Menu.Checkbox("Nami.combo.eWL." .. heroName, "Use E on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Nami.combo.selfE", "Enable E for Self", true)
                Menu.Text("")
                RHeader()
                Menu.Checkbox("Nami.combo.useR", "Enable R", true)
                local cbResult5 = OriUtils.MGet("combo.useR")
                if cbResult5 then
                    Menu.Slider("Nami.combo.useR.minEnemies", "Use if X enemy(s)", 3, 1, 5)
                end
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Nami.harassMenu", "Harass Settings", function()
            Menu.ColumnLayout("Nami.harassMenu.WE", "Nami.harassMenu.WE", 2, true, function()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Nami.harass.useW", "Enable W", true)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Nami.harass.useE", "Enable E", false)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Nami.clearMenu", "Clear Settings", function()
            Menu.Checkbox("Nami.clear.enemiesAround", "Don't clear while enemies around", true)
            Menu.Separator()
            Menu.ColumnLayout("Nami.clearMenu.QE", "Nami.clearMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Nami.clear.useQ", "Enable Q", true)
                Menu.Slider("Nami.clear.QSlider", "Use on X Minions", 4, 1, 6, 1)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.ColoredText("E will prioritize ally, if ally is in E Range", scriptColor, true)
                Menu.Checkbox("Nami.clear.useE", "Enable E", true)               
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Nami.miscMenu", "Misc Settings", function()
            Menu.ColumnLayout("Nami.miscMenu.R", "Nami.miscMenu.R", 2, true, function()
                Menu.Text("")
                RHeader()
                Menu.Keybind("Nami.misc.forceR", "Force R", string.byte("T"), false, false, true)
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Nami.gapclose.Q", "Use Gapclose Q", true)
                local cbResult6 = OriUtils.MGet("gapclose.Q")
                if cbResult6 then
                    Menu.Indent(function()
                        Menu.NewTree("Nami.gapcloseMenu.gapcloseQ", "Gapclose Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Nami.gapclose.qWL." .. heroName, "Use Q Gapclose on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                --[[RHeader()
                Menu.Checkbox("Nami.gapclose.R", "Use Gapclose R", true)]]--
                Menu.NextColumn()
                Menu.Text("")
                WHeader()
                Menu.Keybind("Nami.misc.forceW", "Force W on Ally/Self", string.byte("Z"), false, false, true)
                Menu.Checkbox("Nami.misc.wWL", "Use Whitelist from Combo", true)
                QHeader()
                Menu.Checkbox("Nami.interrupt.Q", "Use Interrupt Q", true)
                local cbResult7 = OriUtils.MGet("interrupt.Q")
                if cbResult7 then
                    Menu.Indent(function()
                        Menu.NewTree("Nami.miscMenu.interruptQ", "Interrupt Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Nami.interrupt.qWL." .. heroName, "Use Q Interrupt on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                RHeader()
                Menu.Checkbox("Nami.interrupt.R", "Use Interrupt R", true)
                local cbResult8 = OriUtils.MGet("interrupt.R")
                if cbResult8 then
                    Menu.Indent(function()
                        Menu.NewTree("Nami.miscMenu.interruptR", "Interrupt R Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Nami.interrupt.rWL." .. heroName, "Use R Interrupt on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Nami.hcMenu", "Hitchance Settings", function()
            Menu.ColumnLayout("Nami.hcMenu.QR", "Nami.hcMenu.QR", 2, true, function()
                Menu.Text("")
                QHeaderHit()
                Menu.Text("")
                Menu.Slider("Nami.hcNew.Q", "%", 25, 1, 100, 1)
                Menu.NextColumn()
                Menu.Text("")
                RHeaderHit()
                Menu.Text("")
                Menu.Slider("Nami.hcNew.R", "%", 50, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Nami.drawMenu", "Draw Settings", function()
            OriUtils.AddDrawMenu(drawData)
        end)
    end

    Menu.RegisterMenu(scriptName, scriptName, NamiMenu)
end

function OnLoad()
    Nami.InitMenu()
    
    Nami.RegisterEvents()
    return true
end
