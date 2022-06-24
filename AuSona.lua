if Player.CharName ~= "Sona" then return end

local scriptName = "AuSona"
local scriptCreator = "AURUM"
local credits = "Orietto"
local patchNotesPrevUpdate = "11/20/2021"
local patchNotesPreVersion, patchNotesVersion, scriptVersionUpdater = "1.0.5", "1.0.7", "1.0.7"
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

SDK.AutoUpdate("https://raw.githubusercontent.com/roburAURUM/robur-AuEdition/main/AuSona.lua", scriptVersionUpdater)

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
        Base = {40, 70, 100, 130, 160},
        TotalAP = 0.4,
        Type = dmgTypes.Magical
    },
    R = {
        Base = {150, 250, 350},
        TotalAP = 0.5,
        Type = dmgTypes.Magical
    }
}

local spells = {
    Q = Spell.Active({
        Slot = slots.Q,
        Delay = 0.0,
        Speed = 0.0,
        Range = 820,
    }),
    W = Spell.Active({
        Slot = slots.W,
        Delay = 0.0,
        Speed = 0.0,
        Range = 1000,
    }),
    E = Spell.Active({
        Slot = slots.E,
        Delay = 0.0,
        Speed = 0.0,
        Range = 430,
    }),
    R = Spell.Skillshot({
        Slot = slots.R,
        Delay = 0.25,
        Speed = huge,
        Range = 1000,
        Radius = 280 / 2,
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

    for slot, Sonaold in pairs(data) do
        if curTime < lastCastT[slot] + Sonaold then
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

        Menu.Checkbox(cacheName .. ".draw." .. id, "Draw " .. displayText .. " range", false)
        Menu.Indent(function()
            Menu.ColorPicker(cacheName .. ".draw." .. id .. ".color", "Color", scriptColor)
        end)
    end

    Menu.Separator()

    --Menu.Checkbox(cacheName .. ".draw." .. "comboDamage", "Draw combo damage on healthbar", false)
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

local ASCIIArt = "                  _____                     "	 
local ASCIIArt2 = "      /\\         / ____|                   "
local ASCIIArt3 = "     /  \\  _   _| (___   ___  _ __   __ _  "
local ASCIIArt4 = "    / /\\ \\| | | |\\___ \\ / _ \\| '_ \\ / _` | "
local ASCIIArt5 = "   / ____ \\ |_| |____) | (_) | | | | (_| | "
local ASCIIArt6 = "  /_/    \\_\\__,_|_____/ \\___/|_| |_|\\__,_| "

local Sona = {}

function Sona.forceR()
    if OriUtils.MGet("misc.forceR") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(nil), false)
        if spells.R:IsReady() then
            local rTarget = spells.R:GetTarget()
            if rTarget then
                if spells.R:Cast(rTarget) then
                    return
                end
            end
        end
    end
end

function Sona.allyW()
    if OriUtils.MGet("misc.useW") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(nil), false)
        if spells.W:IsReady() then
            local alliesHP = ObjManager.GetNearby("ally", "heroes")
            for i, obj in ipairs(alliesHP) do
                local hero = obj.AsHero
            if not hero.IsDead and not hero.IsMe and spells.W:IsInRange(hero) then
                    if spells.W:Cast() then
                        return
                    end
                end
            end
        end
    end
end

function Sona.FountainHeal()
    if Player.IsInFountain then
        if Player.HealthPercent <= 0.5 then
            if spells.W:Cast() then
                return
            end
        end
    end
end

function Sona.PassiveEStack()
    if OriUtils.MGet("misc.EPassiveStack") then
        if not Sona.HasPassiveQ() and not Sona.HasPassiveW() and not Sona.HasPassiveE() then
            if OriUtils.MGet("misc.EPassiveStack.options") == 1 then
                if not TS:GetTarget(2000) then
                    if Player.ManaPercent * 100 > OriUtils.MGet("misc.EPassiveMana") then
                        if spells.E:Cast() then
                            return
                        end
                    end
                end
            else
                if Player.ManaPercent * 100 > OriUtils.MGet("misc.EPassiveMana") then
                    if spells.E:Cast() then
                        return
                    end
                end
            end
        end
    end
end

function Sona.rCases()
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

function Sona.flashR()
    if OriUtils.MGet("misc.flashR") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)
        if spells.R:IsReady() then
            local flashReady = spells.Flash.Slot and OriUtils.IsSpellReady(spells.Flash.Slot)
            if not flashReady then
                return
            end

            local spellInput = {
                Slot = slots.R,
                Delay = 0.25,
                Speed = huge,
                Range = 1000,
                Radius = 300 / 2,
                Type = "Linear",
            }
            local rFlashRange = (spells.R.Range) + spells.Flash.Range
            local rFlashTarget = TS:GetTarget(rFlashRange, false)
            

            if rFlashTarget and spells.R:IsInRange(rFlashTarget) then
                if OriUtils.MGet("misc.flashRInside") then
                    local flashPos = Player.ServerPos:Extended(rFlashTarget, spells.Flash.Range) 
                    local enemyPositions = {}
                    for i, obj in ipairs(TS:GetTargets(spells.R.Range)) do
                        local pred = spells.R:GetPrediction(obj)
                        if pred and pred.HitChance >= (OriUtils.MGet("hcNew.R") / 100) then
                            table.insert(enemyPositions, pred.TargetPosition)
                        end
                    end
                    local nonFbestPos, noFnumberOfHits = Geometry.BestCoveringRectangle(enemyPositions, Player.Position, spells.R.Radius * 2)
                    local bestPos, numberOfHits = Geometry.BestCoveringRectangle(enemyPositions, flashPos, spells.R.Radius * 2)
                    if numberOfHits > OriUtils.MGet("combo.useR.minEnemies") or numberOfHits > noFnumberOfHits or numberOfHits == 5 then
                        if Input.Cast(spells.Flash.Slot, flashPos) then
                            delay(100, function() spells.R:Cast(bestPos) end)
                            return
                        end
                    end
                end
            elseif rFlashTarget and not spells.R:IsInRange(rFlashTarget) then
                local flashPos = Player.ServerPos:Extended(rFlashTarget, spells.Flash.Range) 
                local pred = Prediction.GetPredictedPosition(rFlashTarget, spellInput, flashPos)
                if pred and pred.HitChanceEnum >= Enums.HitChance.Medium then
                    if Input.Cast(spells.Flash.Slot, flashPos) then
                        delay(100, function() spells.R:Cast(rFlashTarget) end)
                        return
                    end
                end
            end
        end
    end
end

function Sona.alliesWithinW()
    local allyCount = 0
    local alliesInRange = ObjManager.GetNearby("ally", "heroes")
    for i, obj in ipairs(alliesInRange) do
        if not obj.IsDead and not obj.IsMe then
        local hero = obj.AsHero
            if OriUtils.IsValidTarget(hero, spells.W.Range) then
                allyCount = allyCount + 1
            end
        end
    end
    return allyCount
end

-- Passivename = SonaQ/W/EPassiveAttack aka. SonaQPassiveAttack

function Sona.HasPassiveQ()
    return Player:GetBuff("SonaQPassiveAttack")
end

function Sona.HasPassiveW()
    return Player:GetBuff("SonaWPassiveAttack")
end

function Sona.HasPassiveE()
    return Player:GetBuff("SonaEPassiveAttack")
end

function events.OnPreAttack(args)   
    if OriUtils.MGet("combo.passiveQ") and OriUtils.MGet("combo.useQ") then
        if (spells.Q:IsReady() or spells.Q:GetSpellData().RemainingCooldown < OriUtils.MGet("combo.QSlider")) then
            if (Sona.HasPassiveW() or Sona.HasPassiveE()) and spells.Q:GetManaCost() < Player.Mana then
                args.Process = false
            end
        end
    end
end

function combatVariants.Combo()
    if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
        local enemyPositions = {}
        
        for i, obj in ipairs(TS:GetTargets(spells.R.Range)) do
            local pred = spells.R:GetPrediction(obj)
            if pred and pred.HitChance >= (OriUtils.MGet("hcNew.R") / 100) then
                table.insert(enemyPositions, pred.TargetPosition)
            end
        end
        local bestPos, numberOfHits = Geometry.BestCoveringRectangle(enemyPositions, Player.Position, spells.R.Radius * 2)
        if numberOfHits >= OriUtils.MGet("combo.useR.minEnemies") then
            if spells.R:Cast(bestPos) then
                return
            end
        end
    end

    if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
    local qTarget = spells.Q:GetTarget()
        if qTarget then
            if spells.Q:Cast() then
                return
            end
        end
    end

    if spells.W:IsReady() then
        if Sona.HasPassiveQ() and OriUtils.MGet("combo.passiveQ") then
            return
        elseif OriUtils.MGet("combo.allyW") then
            local enemiesW = ObjManager.GetNearby("enemy", "heroes")
            for iE, objE in ipairs(enemiesW) do
                local enemy = objE.AsHero
                if not enemy.IsDead and enemy.IsVisible then
                    local alliesHP = ObjManager.GetNearby("ally", "heroes")
                    for i, obj in ipairs(alliesHP) do
                        local hero = obj.AsHero
                        if not hero.IsDead and not hero.IsMe and spells.W:IsInRange(hero) then
                            if OriUtils.MGet("combo.wWL." .. hero.CharName, true) then
                                local healthPercentAlly = hero.HealthPercent * 100
                                if healthPercentAlly <= OriUtils.MGet("combo.allyWSlider") then
                                    if spells.W:Cast() then
                                        return
                                    end
                                end
                            end
                        end
                    end
                    if OriUtils.MGet("combo.selfW") then
                        local healthPercentSelf = Player.HealthPercent * 100
                        if healthPercentSelf <= OriUtils.MGet("combo.selfWSlider") then
                            if spells.W:Cast() then
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
    if spells.Q:IsReady() and OriUtils.MGet("harass.useQ") then
        local qTarget = spells.Q:GetTarget()
        if qTarget then
            if spells.Q:Cast() then
                return
            end
        end 
    end
end

function combatVariants.Waveclear()
end


function combatVariants.Lasthit()
end

function combatVariants.Flee()
    if spells.E:IsReady() then
        if spells.E:Cast() then
            return
        end
    end
    if spells.W:IsReady() and OriUtils.MGet("misc.useWInFlee") then
        local healthPercentSelf = Player.HealthPercent * 100
        if healthPercentSelf < OriUtils.MGet("misc.WSlider") then
            if spells.W:Cast() then
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
    elseif OrbwalkerState == "Lasthit" then
        combatVariants.Lasthit()
    elseif OrbwalkerState == "Flee" then
        combatVariants.Flee()
    end

    Sona.flashR()
    Sona.forceR()
    Sona.PassiveEStack()
    Sona.allyW()
    Sona.FountainHeal()
end

function events.OnInterruptibleSpell(source, spellCast, danger, endTime, canMoveDuringChannel)
    if spells.R:IsReady() and OriUtils.MGet("interrupt.R") then
        if danger >= 5 and spells.R:IsInRange(source) then
            if OriUtils.MGet("interrupt.rWL." .. source.CharName, true) then
                local pred = spells.R:GetPrediction(source)
                if pred and pred.HitChanceEnum >= Enums.HitChance.Medium then
                    delay(200, function() spells.R:Cast(pred.CastPosition) end)
                        return
                end
            end
        end
    end
end

local drawData = {
    {slot = slots.Q, id = "Q", displayText = "[Q] Hymn of Valor", range = spells.Q.Range},
    {slot = slots.W, id = "W", displayText = "[W] Aria of Perseverance", range = spells.W.Range},
    {slot = slots.E, id = "E", displayText = "[E] Song of Celerity", range = spells.E.Range},
    {slot = slots.R, id = "R", displayText = "[R] Crescendo", range = spells.R.Range}
}

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

---@param obj GameObject
---@param buffInst BuffInst
function events.OnBuffGain(obj, buffInst)
    if obj and buffInst then
        if not obj.IsEnemy and obj.IsHero then
            --INFO("An enemy hero gained the buff: " .. buffInst.Name)
        end
    end
end

---@param obj GameObject
---@param buffInst BuffInst
function events.OnBuffLost(obj, buffInst)
    if obj and buffInst then
        if not obj.IsEnemy and obj.IsHero then
            --INFO("An enemy hero lost the buff: " .. buffInst.Name)
        end
    end
end

function Sona.RegisterEvents()
    for eventName, eventId in pairs(Enums.Events) do
        if events[eventName] then
            EventManager.RegisterCallback(eventId, events[eventName])
        end
    end
end

function Sona.InitMenu()
    local function QHeader()
        Menu.ColoredText(drawData[1].displayText, scriptColor, true)
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
    local function RHeaderHit()
        Menu.ColoredText(drawData[4].displayText .. " Hitchance", scriptColor, true)
    end

    local function WSelf()
        Menu.ColoredText("[W] Use on Self", scriptColor, true)
    end
    local function WAlly()
        Menu.ColoredText("[W] Use on Ally", scriptColor, true)
    end

    local function SonaMenu()
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

        if Menu.Checkbox("Sona.Updates105", "Don't show updates") == false then
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. scriptLastUpdated .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesVersion, 0XFFFF00FF, true)
            Menu.Text("- Adjusted Hitchance for new Prediction", true)
            Menu.Text("- Fixed Q Passive Bug", true)
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. patchNotesPrevUpdate .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesPreVersion, 0XFFFF00FF, true)
            Menu.Text("- Fixed R Flash with Combo R Slider", true)
        end
        Menu.Separator()

        Menu.NewTree("Sona.comboMenu", "Combo Settings", function()
            Menu.ColumnLayout("Sona.comboMenu.QE", "Sona.comboMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Sona.combo.useQ", "Enable Q", true)
                Menu.Checkbox("Sona.combo.passiveQ", "", true)Menu.SameLine()
                Menu.Text("Don't AA, if not Q Passive and Q less than X")
                Menu.Text("Requires 'Enable Q' to be active", false)
                    local cbResultInbuilt1 = OriUtils.MGet("combo.passiveQ")
                    if cbResultInbuilt1 then
                        Menu.Slider("Sona.combo.QSlider", "Sec CD", 1.1, 0.1, 8, 0.1)
                    end
                
                Menu.Text("")
                RHeader()
                Menu.Checkbox("Sona.combo.useR", "Enable R", true)
                Menu.Slider("Sona.combo.useR.minEnemies", "Use if X enemy(s)", 3, 1, 5)
                Menu.NextColumn()
                Menu.Text("")
                WAlly()
                Menu.Checkbox("Sona.combo.allyW", "Enable W", false)
                local cbResult = OriUtils.MGet("combo.allyW")
                if cbResult then
                    Menu.Indent(function()
                        Menu.Slider("Sona.combo.allyWSlider", "if < %HP", 35, 1, 100, 1)
                        Menu.NewTree("Sona.combo.wWhitelist", "W Whitelist", function()
                            local allyHeroes = ObjManager.Get("ally", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(allyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if not hero.IsMe and hero and not addedWL[heroName] then
                                    Menu.Checkbox("Sona.combo.wWL." .. heroName, "Use W on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Text("")
                WSelf()
                Menu.Checkbox("Sona.combo.selfW", "Enable W", false)
                    local cbResult2 = OriUtils.MGet("combo.selfW")
                    if cbResult2 then
                        Menu.Slider("Sona.combo.selfWSlider", "if < %HP", 30, 1, 100, 1)
                    end
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Sona.harassMenu", "Harass Settings", function()
            Menu.ColumnLayout("Sona.harassMenu.QE", "Sona.harassMenu.QE", 1, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Sona.harass.useQ", "Enable Q", true)
            end)
        end)
        Menu.Separator()

        --[[Menu.NewTree("Sona.ksMenu", "Killsteal Settings", function()
            Menu.ColumnLayout("Sona.ksMenu.QE", "Sona.ksMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Sona.ks.useQ", "Killsteal with Q", true)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Sona.ks.useE", "Killsteal with E", true)
            end)
            Menu.ColumnLayout("Sona.ksMenu.WR", "Sona.ksMenu.WR", 2, true, function()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Sona.ks.useW", "Enable W", true)
                Menu.NextColumn()
                RHeader()
                Menu.Checkbox("Sona.ks.useR", "Enable R", true)
            end)
        end)
        Menu.Separator()]]--

        Menu.NewTree("Sona.miscMenu", "Misc Settings", function()
            Menu.ColumnLayout("Sona.miscMenu.R", "Sona.miscMenu.R", 2, true, function()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Sona.misc.useWInFlee", "Use W in Flee", true)
                local cbResult10 = OriUtils.MGet("misc.useWInFlee")
                if cbResult10 then
                    Menu.Slider("Sona.misc.WSlider", "if < %HP", 30, 1, 100, 1)
                end
                Menu.Keybind("Sona.misc.useW", "Force W on Ally", string.byte("Z"), false, false,  true)
                EHeader()
                Menu.ColoredText("Use E to Stack Passive if", scriptColor, true)
                Menu.Checkbox("Sona.misc.EPassiveStack", "", true)Menu.SameLine()
                Menu.Dropdown("Sona.misc.EPassiveStack.options", "Mode", 1, {"Always", "Only when no Enemy around (Range 2000)"})
                local cbResult9 = OriUtils.MGet("misc.EPassiveStack")
                if cbResult9 then
                    Menu.Slider("Sona.misc.EPassiveMana", "Mana > %", 60, 1, 100, 1)
                end
                Menu.NextColumn()
                Menu.Text("")
                RHeader()
                Menu.Keybind("Sona.misc.forceR", "Force R", string.byte("T"), false, false,  true)
                Menu.Keybind("Sona.misc.flashR", "Flash R", string.byte("G"), false, false, true)
                Menu.Checkbox("Sona.misc.flashRInside", "Use Flash inside R Range, if Hit > ComboHit", true)Menu.SameLine()
                Menu.ColoredText("|EXPERIMENTAL|", 0xFF0000FF)
                Menu.Checkbox("Sona.interrupt.R", "Interrupt with R", true)
                local cbResult3 = OriUtils.MGet("interrupt.R")
                if cbResult3 then
                    Menu.Indent(function()
                        Menu.NewTree("Sona.miscMenu.interruptR", "interrupt R Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Sona.interrupt.rWL." .. heroName, "Use R interrupt on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Sona.hcMenu", "Hitchance Settings", function()
            Menu.ColumnLayout("Sona.hcMenu.R", "Sona.hcMenu.R", 1, true, function()
                Menu.Text("")
                RHeaderHit()
                Menu.Text("")
                Menu.Slider("Sona.hcNew.R", "%", 50, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Sona.drawMenu", "Draw Settings", function()
            OriUtils.AddDrawMenu(drawData)
        end)
    end

    Menu.RegisterMenu(scriptName, scriptName, SonaMenu)
end

function OnLoad()
    Sona.InitMenu()
    
    Sona.RegisterEvents()
    return true
end
