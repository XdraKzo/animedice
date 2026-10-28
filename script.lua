-- ANIME DICE SIMULATOR KAITUN (v1.5)
-- Always running: auto roll, plot equip best + sell weaker units (RAW = level 1 income), level up plot units
-- to MaxLevel, collect plot money, buy + equip better dice, candy upgrades, boosts, claims, trick or treat.
-- Towers (step by step): Dragon -> Cursed -> Pirate -> Hidden Leaf -> Slayer -> Shadow. A tower that cannot be
-- cleared yet: farm the previous tower a few runs, try again. All cleared -> Halloween tower (Haunted House).
-- To stop: run the script again or in F9: getgenv().AdKaitunId = 0

local Config = {
    -- ROLL
    AutoRoll = true,

    -- PLOT UNITS
    EquipBestEvery = 10,       -- seconds
    -- RAW PLOT: the script fills the plot itself with the highest RAW units (instead of the game's equip best,
    -- which looks at the current income and keeps weak but levelled units over a strong new level 1 unit)
    RawPlot = true,
    SellWeaker = true,         -- sell units whose RAW income is not better than the worst unit on the plot
    ReplaceWorst = false,      -- (off: the game cannot sell a unit that is on the plot)
    -- SAFE MODE: true = main account (the strict rules below), false = alt account
    -- (only the RAW value decides; locked and NeverSell units are still kept)
    SafeMode = true,
    SellEvery = 3,             -- seconds between sell checks
    StorageFree = 25,          -- keep at least this many free backpack slots (sells the weakest sellable units)
    -- SAFETY (SafeMode = true): a unit is only sold when ALL of these allow it
    SellRarities = {"Common", "Uncommon", "Rare", "Epic", "Legendary"},   -- only these rarities are ever sold
    KeepVariants = {"Huge", "Titanic"},   -- never sold
    KeepMutations = {"Gold", "Silver", "Diamond", "Emerald", "Ruby", "Rainbow", "Haunted"},   -- never sold (all of them)
    KeepGrades = true,         -- units with a grade are never sold
    KeepTraits = true,         -- units with a trait are never sold
    NeverSell = {},            -- unit names (or parts of names) never sold, e.g. {"Jin-woo"}
    SellDryRun = false,        -- true = only print what WOULD be sold, sell nothing (try this first on a main account)
    MaxLevel = 40,             -- level plot units up to this
    LevelUpEvery = 2,          -- seconds between level up rounds
    CollectEvery = 15,         -- seconds between collecting plot money

    -- REBIRTH: rebirth as soon as the money reaches the cost (it resets the money)
    AutoRebirth = true,
    RebirthStat = "Luck",      -- rebirth point goes to: Luck / Money / Damage / Health / Trait Luck / Grade Luck

    -- CUTSCENES: skip roll cutscenes, clover reveal and drop popups
    SkipCutscenes = true,

    -- DICE: buy the best dice you can afford (with at most this share of your money) and equip the best one
    AutoDice = true,
    DiceMaxSpend = 1,          -- share of your money a dice may cost (1 = all of it)
    DiceFirst = true,          -- a better dice you can afford is bought BEFORE upgrades / rebirth spend the money

    -- GAME UPGRADES (upgrade tree): buys nodes whose parent is owned, priority words first, cheapest first
    AutoUpgrades = true,
    UpgradePriority = {"Luck", "Money", "Roll Speed", "Damage", "Health", "Sell", "Unit Storage"},

    -- HALLOWEEN
    CandyUpgrades = {"Luck", "Money", "Damage", "Pumpkins", "PumpkinLuck"},   -- order, each up to its max level
    TrickOrTreat = true,
    DoorStandTime = 0.5,
    HalloweenClaims = true,    -- pumpkin path + Halloween quests

    -- BOOSTS: use every boost in the inventory that is not active (names here are skipped)
    AutoBoosts = true,
    BoostRefill = 30,          -- a boost is used again when its time left is below this (seconds)
    BoostSkip = {},

    -- OTHER CLAIMS
    Claims = true,             -- daily reward, offline earnings, quests
    ClaimEvery = 60,

    -- TOWERS
    Towers = true,
    TowerOrder = {"Dragon Tower", "Cursed Tower", "Pirate Tower", "Hidden Leaf Tower", "Slayer Tower", "Shadow Tower"},
    FarmRuns = 2,              -- runs on the previous tower after a failed try on a new one
    AlreadyCleared = {},       -- towers you cleared before (skipped), e.g. {"Dragon Tower", "Cursed Tower"}
    SkipEasyTowers = true,     -- one hit kills the last floor's enemy -> tower counted as cleared at once
    SkipMargin = 2,            -- ...with this much extra (2 = the hit must be 2x the last floor's health)
    HalloweenTower = true,     -- after the last tower: the Haunted House wings

    -- CPU / RAM SAVER
    Saver = true,
    FPSCap = 10,               -- frames per second limit (needs setfpscap in the executor)
    WhiteScreen = true,        -- no 3D drawing; with the panel off a plain white screen is shown
    LowGraphics = true,        -- lowest quality, no shadows / particles / textures / sounds

    Panel = true,              -- full screen status panel (button top right: show game / show panel)
    HideWorld = true,          -- while the panel is shown the 3D world is not drawn (more FPS)
    Debug = true,
}

getgenv().AdKaitunId = (rawget(getgenv(), "AdKaitunId") or 0) + 1
local RunId = getgenv().AdKaitunId
local function IsActive() return getgenv().AdKaitunId == RunId end

local S = {}   -- services / modules (one table: keeps the local count low)
S.Players = game:GetService("Players")
S.RS = game:GetService("ReplicatedStorage")
S.Http = game:GetService("HttpService")
S.VU = game:GetService("VirtualUser")
local LP = S.Players.LocalPlayer

if not game:IsLoaded() then game.Loaded:Wait() end
repeat task.wait() until LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")

-- session totals + last actions (for the panel)
local Session = {Start = os.clock(), Feed = {}, Count = {Upgrades = 0, Rebirths = 0, Dice = 0, Candy = 0, Boosts = 0,
    Sold = 0, Levels = 0, Floors = 0, Doors = 0}}
local function Log(...)
    local Parts = {}
    for I, V in ipairs({...}) do Parts[I] = tostring(V) end
    local Text = table.concat(Parts, " ")
    local C = Session.Count
    if Text:find("^upgrade bought") then C.Upgrades += 1
    elseif Text:find("^rebirth %d+ done") then C.Rebirths += 1
    elseif Text:find("^bought dice") then C.Dice += 1
    elseif Text:find("^candy upgrade") then C.Candy += 1
    elseif Text:find("^boost used") then C.Boosts += 1 end
    table.insert(Session.Feed, 1, os.date("%H:%M:%S") .. "  " .. Text)
    if #Session.Feed > 12 then table.remove(Session.Feed) end
    if Config.Debug then print("[AD]", Text) end
end

local function Short(N)
    N = tonumber(N) or 0
    local Suf = {"", "K", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No", "De", "Ud", "Dd", "Td", "Qdd", "Qnd"}
    local I = 1
    while math.abs(N) >= 1000 and I < #Suf do N /= 1000; I += 1 end
    return (I == 1 and "%d%s" or "%.2f%s"):format(N, Suf[I])
end

----------------------------------------------------------------
-- NETWORK
----------------------------------------------------------------
local Net = S.RS:WaitForChild("Network", 30)
local function R(Path)
    local O = Net
    for P in Path:gmatch("[^%.]+") do O = O and O:WaitForChild(P, 10) end
    if not O then warn("[AD] remote not found: " .. Path) end
    return O
end
local Fire = function(Rem, ...)
    if not Rem then return false end
    local A = table.pack(...)
    return pcall(function() Rem:FireServer(table.unpack(A, 1, A.n)) end)
end
-- InvokeServer that gives up after Timeout seconds (a server that never answers would freeze the loop)
local function InvokeT(Timeout, Rem, ...)
    if not Rem then return false end
    local A = table.pack(...)
    local Done, Ok, Res = false, false, nil
    task.spawn(function()
        Ok, Res = pcall(function() return Rem:InvokeServer(table.unpack(A, 1, A.n)) end)
        Done = true
    end)
    local Until = os.clock() + Timeout
    while not Done and os.clock() < Until do task.wait(0.1) end
    if not Done then return false, "timeout" end
    return Ok, Res
end

local Invoke = function(Rem, ...)
    if not Rem then return false end
    local A = table.pack(...)
    return pcall(function() return Rem:InvokeServer(table.unpack(A, 1, A.n)) end)
end

local RE = {
    Roll = R("RollService.RF.RollDice"), AutoRoll = R("RollService.RE.SetAutoRoll"),
    EquipBest = R("PlotService.RE.EquipBest"), LevelUp = R("PlotService.RE.LevelUpSlot"),
    Collect = R("PlotService.RE.CollectBalance"),
    Sell = R("SellService.RF.SellInventory"),
    BuyDice = R("DiceShopService.RE.BuyDice"), EquipDice = R("DiceShopService.RE.EquipDice"),
    BuyUpgrade = R("RE.BuyUpgrade"),
    Boost = R("BoostService.RE.Use"),
    TowerTeam = R("Towers.RE.EquipBestTowerTeam"), PlayTower = R("Towers.RF.PlayTower"),
    Floor = R("Towers.RF.CompleteTowerFloor"), CancelTower = R("Towers.RF.CancelTower"),
    AutoTower = R("Towers.RE.SetAutoTower"),
    HwTeleport = R("HalloweenService.RF.Teleport"), ClaimAllPath = R("HalloweenService.RE.ClaimAllPath"),
    CandyUpgrade = R("HalloweenService.RE.BuyUpgrade"), HwQuest = R("HalloweenQuestService.RE.Claim"),
    Quest = R("QuestService.RE.Claim"), Daily = R("DailyRewardService.RE.Claim"),
    Offline = R("OfflineEarningsService.RE.Claim"),
    Rebirth = R("RebirthService.RE.Rebirth"), AddStat = R("RebirthService.RE.AddStat"),
    HoldUnit = R("UnitService.RF.Equip"), DropUnit = R("UnitService.RF.Unequip"),
    PlaceSlot = R("PlotService.RE.InteractSlot"),
    LevelOk = R("PlotService.RE.LevelUpSuccess"),
}

----------------------------------------------------------------
-- GAME DATA + CONFIG MODULES
----------------------------------------------------------------
local F = S.RS:WaitForChild("Framework"):WaitForChild("Features")
local function Req(M) local Ok, V = pcall(require, M) return Ok and V or nil end
S.DataCtl = Req(F.Data.DataController)
S.Units = (Req(F.Inventory.Kinds.Unit.UnitConfig) or {}).entries or {}
S.Boosts = (Req(F.Inventory.Kinds.Boost.BoostConfig) or {}).entries or {}
S.Dice = Req(F.Rolling.Dice)
S.Upgrades = Req(F.Upgrades.Upgrades) or {}
S.CandyUps = Req(F.Halloween.CandyUpgrades)
S.Towers = Req(F.Towers.Towers)
S.TowerRefs = Req(F.Towers.TowerRefs) or {}
S.Rebirths = Req(F.Rebirth.Rebirths)
S.UnitUtil = Req(F.Inventory.Kinds.Unit.UnitUtil)
S.Tree = Req(F.Upgrades.TreeStructure)
S.PlotCfg = Req(F.Plot.PlotConfig)

local function D() return S.DataCtl and S.DataCtl.___X or nil end
local function Money() local X = D() return X and tonumber(X.Money) or 0 end

-- SAVE (per account): best floor per tower
S.SaveFile = ("AnimeDiceKaitun_%d.json"):format(LP.UserId)
local Save = {Best = {}}
pcall(function()
    if isfile and isfile(S.SaveFile) then
        local L = S.Http:JSONDecode(readfile(S.SaveFile))
        if type(L) == "table" then for K, V in pairs(L) do Save[K] = V end end
    end
end)
Save.Best = Save.Best or {}
for _, Name in ipairs(Config.AlreadyCleared) do Save.Best[Name] = math.max(tonumber(Save.Best[Name]) or 0, 150) end
local function WriteSave() pcall(function() if writefile then writefile(S.SaveFile, S.Http:JSONEncode(Save)) end end) end

local Status = "starting"
local Stats = {Sold = 0, Levels = 0, Floors = 0, Doors = 0}

-- anti afk
pcall(function() for _, C in ipairs(getconnections(LP.Idled)) do C:Disable() end end)
LP.Idled:Connect(function() pcall(function() S.VU:CaptureController() S.VU:ClickButton2(Vector2.new()) end) end)

----------------------------------------------------------------
-- UNITS
----------------------------------------------------------------
local function HasExact(List, Text)
    for _, W in ipairs(List) do if tostring(W):lower() == tostring(Text):lower() then return true end end
    return false
end

local function HasPart(List, Text)
    for _, W in ipairs(List) do
        if Text and tostring(Text):lower():find(tostring(W):lower(), 1, true) then return true end
    end
    return false
end

-- RAW income: the unit's income at level 1 (same mutation / grade / trait)
local function Raw(E)
    local Cfg = S.Units[E.name]
    if not Cfg or type(Cfg.income) ~= "function" then return nil end
    local A = {}
    for K, V in pairs(E.attributes or {}) do A[K] = V end
    A.level = 1
    local Ok, V = pcall(Cfg.income, A)
    return Ok and tonumber(V) or nil
end

-- plot: slot -> unit id, unit id -> slot
local function SlotMap()
    local X = D()
    local BySlot, ById = {}, {}
    for Slot, Info in pairs(X and X.Slots or {}) do
        if type(Info) == "table" and Info.unitId then
            BySlot[tonumber(Slot)] = Info.unitId
            ById[Info.unitId] = tonumber(Slot)
        end
    end
    return BySlot, ById
end

local function TowerSet()
    local X = D()
    local T = {}
    for _, Id in pairs(X and X.TowerTeam or {}) do T[Id] = true end
    return T
end

local function SellIds(Ids)
    for I = 1, #Ids, 100 do
        local Part = {}
        for J = I, math.min(I + 99, #Ids) do table.insert(Part, Ids[J]) end
        local Ok = InvokeT(10, RE.Sell, Part)
        if Ok then Stats.Sold += #Part end
        task.wait(0.1)
    end
end

-- true = never sell this unit
function KeepUnit(E)
    local A = E.attributes or {}
    local Cfg = S.Units[E.name] or {}
    if A.locked or A.Locked or A.protected or HasPart(Config.NeverSell, E.name) then return true end
    if not Config.SafeMode then return false end   -- alt account: only the RAW value decides
    local Rarity = Cfg.rarity
    return not Rarity or not HasExact(Config.SellRarities, Rarity)
        or (Cfg.variant and HasExact(Config.KeepVariants, Cfg.variant)) or HasPart(Config.KeepVariants, E.name)
        or (A.mutation and HasExact(Config.KeepMutations, A.mutation))
        or (Config.KeepGrades and A.grade) or (Config.KeepTraits and A.trait) or false
end

-- backpack size (Unit Storage buff)
local function StorageCap()
    local Ok, V = pcall(function()
        local B = require(F.Buffs.BuffController)
        return B.GetBuff("Unit Storage")
    end)
    if not (Ok and tonumber(V)) then
        Ok, V = pcall(function() local B = require(F.Buffs.BuffController) return B:GetBuff("Unit Storage") end)
    end
    return (Ok and tonumber(V)) or 150
end

-- slots the account has unlocked (plot floors open at a rebirth count)
local function UnlockedSlots()
    local X = D()
    local Reb = X and tonumber(X.Rebirth) or 0
    local List = {}
    local Ok, Floors = pcall(function() return S.PlotCfg.GetFloors() end)
    if not Ok or type(Floors) ~= "table" then
        for I = 1, 8 do table.insert(List, I) end
        return List
    end
    for _, Fl in pairs(Floors) do
        if type(Fl) == "table" and Reb >= (tonumber(Fl.rebirth) or 0) then
            for I = tonumber(Fl.firstSlot) or 1, tonumber(Fl.lastSlot) or 8 do table.insert(List, I) end
        end
    end
    table.sort(List)
    return List
end

-- put the highest RAW units on the plot: every slot holding a unit outside the top N (or empty) gets the
-- best unit that is not on the plot yet (hold it, then click the slot)
local function RawPlot()
    local X = D()
    if not X or not X.Inventory then return end
    local Slots = UnlockedSlots()
    local BySlot, ById = SlotMap()

    local All = {}
    for Id, E in pairs(X.Inventory) do
        if type(E) == "table" and S.Units[E.name] then
            local V = Raw(E)
            if V then table.insert(All, {Id = Id, Raw = V, Name = E.name}) end
        end
    end
    table.sort(All, function(A, B) return A.Raw > B.Raw end)
    local Want = {}
    for I = 1, math.min(#Slots, #All) do Want[All[I].Id] = true end

    -- units that should be on the plot but are not, best first
    local ToPlace = {}
    for I = 1, math.min(#Slots, #All) do
        if not ById[All[I].Id] then table.insert(ToPlace, All[I]) end
    end
    if #ToPlace == 0 then return end

    -- slots to fill: empty ones first, then those holding the weakest unwanted units
    local Free = {}
    for _, Slot in ipairs(Slots) do
        local Id = BySlot[Slot]
        if not Id then
            table.insert(Free, {Slot = Slot, Raw = -1})
        elseif not Want[Id] then
            local E = X.Inventory[Id]
            table.insert(Free, {Slot = Slot, Raw = (E and Raw(E)) or 0})
        end
    end
    table.sort(Free, function(A, B) return A.Raw < B.Raw end)

    for I = 1, math.min(#ToPlace, #Free) do
        if not IsActive() then break end
        local U, Sl = ToPlace[I], Free[I]
        local Ok = InvokeT(5, RE.HoldUnit, U.Id)
        task.wait(0.3)
        Fire(RE.PlaceSlot, Sl.Slot)
        task.wait(0.6)
        Log(("plot: %s (RAW %s) -> slot %d"):format(U.Name, Short(U.Raw), Sl.Slot))
    end
    -- nothing left in the hand
    InvokeT(5, RE.DropUnit)
end

local function ManageUnits()
    local X = D()
    if not X or not X.Inventory then return end
    if os.clock() - (S.LastEquip or 0) >= Config.EquipBestEvery then
        S.LastEquip = os.clock()
        if Config.RawPlot then RawPlot() else Fire(RE.EquipBest) end
        task.wait(1)
    end

    local BySlot, ById = SlotMap()
    local Tower = TowerSet()

    -- worst unit on the plot (RAW)
    local WorstId, WorstRaw, PlotCount = nil, nil, 0
    for _, Id in pairs(BySlot) do
        PlotCount += 1
        local E = X.Inventory[Id]
        local V = E and Raw(E)
        if V and (not WorstRaw or V < WorstRaw) then WorstId, WorstRaw = Id, V end
    end
    if not WorstRaw then return end

    local Sell, BestFree, BestFreeRaw = {}, nil, nil
    for Id, E in pairs(X.Inventory) do
        if type(E) == "table" and S.Units[E.name] and not ById[Id] and not Tower[Id] then
            local Keep = KeepUnit(E)
            local V = Raw(E)
            if V and not Keep then
                if V <= WorstRaw then
                    table.insert(Sell, Id)
                elseif not BestFreeRaw or V > BestFreeRaw then
                    BestFree, BestFreeRaw = Id, V
                end
            end
        end
    end

    -- backpack almost full: also sell the weakest sellable units that are better than the worst plot unit
    local UnitCount = 0
    for _, E in pairs(X.Inventory) do
        if type(E) == "table" and S.Units[E.name] then UnitCount += (tonumber(E.amount) or 1) end
    end
    local Cap = StorageCap()
    local Need = (UnitCount - #Sell) - (Cap - Config.StorageFree)
    if Need > 0 then
        local Extra, Picked = {}, {}
        for _, Id in ipairs(Sell) do Picked[Id] = true end
        for Id, E in pairs(X.Inventory) do
            if type(E) == "table" and S.Units[E.name] and not ById[Id] and not Tower[Id] and not Picked[Id] and not KeepUnit(E) then
                table.insert(Extra, {Id = Id, Raw = Raw(E) or 0})
            end
        end
        table.sort(Extra, function(A, B) return A.Raw < B.Raw end)
        for I = 1, math.min(Need, #Extra) do table.insert(Sell, Extra[I].Id) end
        Log(("backpack %d / %d: selling %d more of the weakest units"):format(UnitCount, Cap, math.min(Need, #Extra)))
        if Need > #Extra then
            warn(("[AD] backpack almost full and only %d units can be sold (SafeMode keeps the rest)"):format(#Extra))
        end
    end

    if Config.SellWeaker and #Sell > 0 and Config.SellDryRun then
        local Names = {}
        for I = 1, math.min(#Sell, 15) do
            local E = X.Inventory[Sell[I]]
            local A = E and E.attributes or {}
            table.insert(Names, ("%s%s"):format(A.mutation and (A.mutation .. " ") or "", tostring(E and E.name)))
        end
        Log(("DRY RUN, would sell %d: %s"):format(#Sell, table.concat(Names, ", ")))
        Sell = {}
    end
    if Config.SellWeaker and #Sell > 0 then
        SellIds(Sell)
        Log(("sold %d units weaker than the worst plot unit (RAW %s)"):format(#Sell, Short(WorstRaw)))
    end

    -- a better unit equip best did not place: swap it with the worst plot unit
    if Config.ReplaceWorst and BestFree and WorstId and not Tower[WorstId] then
        local WE = X.Inventory[WorstId]
        Log(("better unit %s (RAW %s) is not on the plot: selling the worst plot unit %s (RAW %s)"):format(
            tostring(X.Inventory[BestFree] and X.Inventory[BestFree].name), Short(BestFreeRaw),
            tostring(WE and WE.name), Short(WorstRaw)))
        InvokeT(10, RE.Sell, {WorstId})
        task.wait(0.5)
        Fire(RE.EquipBest)
    end
end

-- level price from the game (tries the argument forms the game may use); nil = unknown
local function LevelPrice(E)
    local U = S.UnitUtil
    if not U or type(U.GetLevelPrice) ~= "function" then return nil end
    for _, Args in ipairs({{E}, {E.name, E.attributes}, {E.attributes}, {E.name, E.attributes and E.attributes.level}}) do
        local Ok, V = pcall(U.GetLevelPrice, table.unpack(Args))
        if Ok and tonumber(V) then return tonumber(V) end
    end
    return nil
end

local LevelOkAt, LevelRest = {}, {}
pcall(function() RE.LevelOk.OnClientEvent:Connect(function(Slot) LevelOkAt[tonumber(Slot)] = os.clock() Stats.Levels += 1 end) end)

local function LevelUpAll()
    local X = D()
    if not X then return end
    local BySlot = SlotMap()
    local List = {}
    for Slot, Id in pairs(BySlot) do
        local E = X.Inventory and X.Inventory[Id]
        local Lv = E and E.attributes and tonumber(E.attributes.level) or 1
        if E and Lv < Config.MaxLevel and os.clock() >= (LevelRest[Slot] or 0) then
            table.insert(List, {Slot = Slot, Lv = Lv, Price = LevelPrice(E)})
        end
    end
    table.sort(List, function(A, B) return A.Lv < B.Lv end)
    for I = 1, math.min(#List, 4) do
        local L = List[I]
        if L.Price and L.Price > Money() then
            LevelRest[L.Slot] = os.clock() + 10
        else
            local Sent = os.clock()
            Fire(RE.LevelUp, L.Slot)
            task.wait(0.6)
            -- no "LevelUpSuccess": cannot afford it -> leave this slot alone for a while
            if (LevelOkAt[L.Slot] or 0) < Sent then LevelRest[L.Slot] = os.clock() + 20 end
        end
    end
end

-- REBIRTH
local DiceToBuy, ManageDice   -- defined further down
local function DoRebirth()
    local X = D()
    if not X or not S.Rebirths then return end
    if Config.DiceFirst and DiceToBuy() then ManageDice() return end
    local Cur = tonumber(X.Rebirth) or 0
    local Ok, Info = pcall(S.Rebirths.Get, Cur + 1)
    local Cost = Ok and type(Info) == "table" and tonumber(Info.cost)
    if not Cost then return end
    Status = ("rebirth %d: %s / %s"):format(Cur + 1, Short(Money()), Short(Cost))
    if Money() >= Cost then
        Fire(RE.Rebirth)
        task.wait(2)
        local After = tonumber(D() and D().Rebirth) or Cur
        if After > Cur then
            Log(("rebirth %d done"):format(After))
            if Config.RebirthStat then
                for _ = 1, 3 do Fire(RE.AddStat, Config.RebirthStat) task.wait(0.3) end
            end
            if Config.RawPlot then S.LastEquip = 0 else Fire(RE.EquipBest) end
        else
            Log("rebirth request sent but the rebirth count did not change")
        end
    end
end

local function CollectAll()
    local X = D()
    for Slot, Info in pairs(X and X.Slots or {}) do
        if type(Info) == "table" and (tonumber(Info.balance) or 0) > 0 then
            Fire(RE.Collect, tonumber(Slot))
            task.wait(0.1)
        end
    end
end

----------------------------------------------------------------
-- DICE / UPGRADES / CANDY / BOOSTS / CLAIMS
----------------------------------------------------------------
-- name of the best affordable dice that is better than every owned one (nil = none)
function DiceToBuy()
    local X = D()
    if not X or not S.Dice then return nil end
    local Ok, All = pcall(S.Dice.GetAll)
    if not Ok or type(All) ~= "table" then return nil end
    local OwnedBest = 0
    for Name in pairs(X.OwnedDice or {}) do OwnedBest = math.max(OwnedBest, All[Name] and tonumber(All[Name].luck) or 0) end
    local Buy, BuyLuck
    for Name, Info in pairs(All) do
        local Price, Luck = tonumber(Info.price), tonumber(Info.luck) or 0
        if not (X.OwnedDice or {})[Name] and Price and Luck > OwnedBest and Price <= Money() * Config.DiceMaxSpend
            and (not BuyLuck or Luck > BuyLuck) then
            Buy, BuyLuck = Name, Luck
        end
    end
    return Buy
end

function ManageDice()
    local X = D()
    if not X or not S.Dice then return end
    local Ok, All = pcall(S.Dice.GetAll)
    if not Ok or type(All) ~= "table" then return end
    local Owned = X.OwnedDice or {}
    local OwnedBest = 0
    for Name in pairs(Owned) do OwnedBest = math.max(OwnedBest, All[Name] and tonumber(All[Name].luck) or 0) end
    -- buy: the luckiest affordable dice that is better than the best one we own
    local Buy, BuyLuck
    for Name, Info in pairs(All) do
        local Price, Luck = tonumber(Info.price), tonumber(Info.luck) or 0
        if not Owned[Name] and Price and Luck > OwnedBest and Price <= Money() * Config.DiceMaxSpend
            and (not BuyLuck or Luck > BuyLuck) then
            Buy, BuyLuck = Name, Luck
        end
    end
    if Buy then
        Fire(RE.BuyDice, Buy)
        Log(("bought dice %s (luck %s)"):format(Buy, Short(BuyLuck)))
        task.wait(1)
    end
    -- equip: the luckiest owned dice
    local Best, BestLuck
    for Name in pairs(X.OwnedDice or {}) do
        local Info = All[Name]
        local Luck = Info and tonumber(Info.luck) or 0
        if not BestLuck or Luck > BestLuck then Best, BestLuck = Name, Luck end
    end
    if Best and X.Dice ~= Best then
        Fire(RE.EquipDice, Best)
        Log("equipped dice " .. Best)
    end
end

-- upgrade tree: a node can be bought when its parent is owned (Start = root, always owned)
local function UpgradeParent(Name)
    local T = S.Tree
    if not T or type(T.GetParent) ~= "function" then return nil, false end
    local Ok, P = pcall(T.GetParent, Name)
    if not Ok then Ok, P = pcall(T.GetParent, T, Name) end
    if not Ok then return nil, false end
    if type(P) == "table" then P = P.name or P.Name or P[1] end
    return P, true
end

local UpgradeRest, UpgradeShown = {}, false
local function ManageUpgrades()
    local X = D()
    if not X then return end
    if Config.DiceFirst and DiceToBuy() then ManageDice() return end
    local Owned = X.Upgrades or {}
    local function IsOwned(N) return N == nil or N == "Start" or Owned[N] == true end

    -- every node we can buy now: not owned, parent owned, affordable, not resting
    local Ready = {}
    for Name, Info in pairs(S.Upgrades) do
        local Price = type(Info) == "table" and tonumber(Info.price)
        if Name ~= "Start" and not Owned[Name] and Price and Price <= Money() and os.clock() >= (UpgradeRest[Name] or 0) then
            local Parent, Known = UpgradeParent(Name)
            if not Known or IsOwned(Parent) then table.insert(Ready, {Name = Name, Price = Price}) end
        end
    end
    if not UpgradeShown then
        UpgradeShown = true
        local P, K = UpgradeParent("Luck II")
        Log(("upgrade tree: parent of Luck II = %s (tree module %s)"):format(tostring(P), tostring(K)))
    end
    if #Ready == 0 then return end

    -- priority words first, cheapest inside each; then anything cheapest
    local function Rank(N)
        for I, W in ipairs(Config.UpgradePriority) do if N:find("^" .. W .. " ") then return I end end
        return #Config.UpgradePriority + 1
    end
    table.sort(Ready, function(A, B)
        local RA, RB = Rank(A.Name), Rank(B.Name)
        if RA ~= RB then return RA < RB end
        return A.Price < B.Price
    end)

    for I = 1, math.min(#Ready, 3) do
        local U = Ready[I]
        Fire(RE.BuyUpgrade, U.Name)
        task.wait(0.6)
        local After = D() and D().Upgrades or {}
        if After[U.Name] then
            Log(("upgrade bought: %s (%s)"):format(U.Name, Short(U.Price)))
        else
            UpgradeRest[U.Name] = os.clock() + 60   -- refused (locked?): try later
        end
    end
end

local function CandyAmount()
    local X = D()
    for K, E in pairs(X and X.Inventory or {}) do
        if type(E) == "table" and (E.name == "Candy" or K == "Candy") then return tonumber(E.amount) end
    end
    return nil
end

local CandyRest = 0
local function ManageCandy()
    local X = D()
    if not X or not S.CandyUps or os.clock() < CandyRest then return end
    local Levels = X.CandyUpgrades or {}
    local Candy = CandyAmount()
    local Tried = false
    for _, Id in ipairs(Config.CandyUpgrades) do
        local U
        for _, V in ipairs(S.CandyUps.List or {}) do if V.id == Id then U = V end end
        local Lv = tonumber(Levels[Id]) or 0
        if U and Lv < (U.maxLevel or 10) then
            local Cost
            if type(S.CandyUps.GetCost) == "function" then
                local Ok, V = pcall(S.CandyUps.GetCost, Id, Lv)
                if not (Ok and tonumber(V)) then Ok, V = pcall(S.CandyUps.GetCost, U, Lv) end
                Cost = Ok and tonumber(V) or nil
            end
            Cost = Cost or (tonumber(U.baseCost) or 2500) * (tonumber(U.growth) or 1.25) ^ Lv
            if Candy and Candy >= Cost then
                Fire(RE.CandyUpgrade, Id)
                Log(("candy upgrade %s -> %d"):format(Id, Lv + 1))
                return
            end
            Tried = true
        end
    end
    -- nothing affordable: check again in 2 minutes
    if Tried then CandyRest = os.clock() + 120 end
end

-- is this inventory entry a boost / potion? (normal boosts, event potions, anything of kind "Boost")
local HwItems = Req(F.Halloween.HalloweenItems) or {}
local function IsBoost(E)
    if S.Boosts[E.name] then return true end
    local HB = HwItems.Boosts
    if type(HB) == "table" and (HB[E.name] or table.find(HB, E.name)) then return true end
    local Ok, Cfg = pcall(function() return require(F.Inventory.EntryRegistry).getEntryConfig(E.name) end)
    if Ok and type(Cfg) == "table" and (Cfg.kind == "Boost" or Cfg.kind == "boost") then return true end
    return false
end

local BoostShown = false
local function UseBoosts()
    local X = D()
    if not X then return end
    local Active = X.ActiveEntries or {}
    local Skipped = {}
    for _, E in pairs(X.Inventory or {}) do
        if type(E) == "table" and (tonumber(E.amount) or 0) > 0 and not S.Units[E.name] then
            if IsBoost(E) then
                local A = Active[E.name]
                local Left = A and tonumber(A.remaining) or 0
                -- not active, or about to run out: use one (they stack their time)
                if Left < Config.BoostRefill and not HasPart(Config.BoostSkip, E.name) then
                    Fire(RE.Boost, E.name)
                    Log("boost used: " .. E.name)
                    task.wait(0.4)
                end
            else
                table.insert(Skipped, E.name)
            end
        end
    end
    if not BoostShown then
        BoostShown = true
        Log("items that are not boosts (not used): " .. table.concat(Skipped, ", "))
    end
end

local function DoClaims()
    local X = D()
    if not X then return end
    if Config.Claims then
        Fire(RE.Daily)
        Fire(RE.Offline)
        for Period, Q in pairs(X.Quests or {}) do
            for Id in pairs(type(Q) == "table" and Q.progress or {}) do
                if not (Q.claimed and Q.claimed[Id]) then Fire(RE.Quest, Period, Id) task.wait(0.2) end
            end
        end
    end
    if Config.HalloweenClaims and X.Halloween then
        Fire(RE.ClaimAllPath)
        local H = X.Halloween
        for Period, Q in pairs({Hourly = H.HourlyQuests, Daily = H.Quests}) do
            for Id in pairs(type(Q) == "table" and Q.progress or {}) do
                if not (Q.claimed and Q.claimed[Id]) then Fire(RE.HwQuest, Period, Id) task.wait(0.2) end
            end
        end
    end
end

----------------------------------------------------------------
-- TRICK OR TREAT (background)
----------------------------------------------------------------
local function Root() return LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") end
local function Teleport(Pos)
    local HRP = Root()
    if not HRP then return end
    -- ask the server to stream the spot in, but never wait for it (it can hang)
    task.spawn(function() pcall(function() LP:RequestStreamAroundAsync(Pos, 2) end) end)
    HRP.CFrame = CFrame.new(Pos)
    HRP.AssemblyLinearVelocity = Vector3.zero
end

local function TrickOrTreat()
    -- only one trick or treat loop (the separate door script stops)
    getgenv().AdTotId = (rawget(getgenv(), "AdTotId") or 0) + 1
    InvokeT(6, RE.HwTeleport, "Island")
    task.wait(3)
    local LastDoors, LastCheck = 0, os.clock()
    local DoorTotal = 0
    pcall(function() R("TrickOrTreatService.RE.Knocked").OnClientEvent:Connect(function() DoorTotal += 1 end) end)
    while IsActive() and Config.TrickOrTreat do
        -- watchdog: no door opened for 60 s -> back to the Halloween island
        if DoorTotal > LastDoors then
            LastDoors, LastCheck = DoorTotal, os.clock()
        elseif os.clock() - LastCheck > 60 then
            Log("trick or treat: no door for 60 s, back to the Halloween island")
            LastCheck = os.clock()
            InvokeT(6, RE.HwTeleport, "Island")
            task.wait(3)
        end
        local Ok, Err = pcall(function()
            if not Root() then repeat task.wait(0.5) until Root() or not IsActive() task.wait(1) end
            local H = workspace:FindFirstChild("Halloween")
            local Doors = {}
            for _, House in ipairs(H and H:GetChildren() or {}) do
                if House.Name:lower():find("trickortreat") then
                    local O = House:FindFirstChild("DoorOpener", true)
                    local P = O and (O:IsA("BasePart") and O.Position or (O:IsA("Model") and O:GetPivot().Position))
                    if P then table.insert(Doors, P) end
                end
            end
            if #Doors == 0 then
                InvokeT(6, RE.HwTeleport, "Island")
                task.wait(3)
                return
            end
            for _, P in ipairs(Doors) do
                if not IsActive() then break end
                Teleport(P + Vector3.new(0, 3, 0))
                task.wait(Config.DoorStandTime)
            end
        end)
        if not Ok then warn("[AD] trick or treat error: " .. tostring(Err)) task.wait(2) end
    end
end

pcall(function()
    R("TrickOrTreatService.RE.Knocked").OnClientEvent:Connect(function() Stats.Doors += 1 end)
end)

----------------------------------------------------------------
-- TOWERS
----------------------------------------------------------------
local AllTowers = {}
pcall(function() AllTowers = S.Towers.GetAll() end)

local function ActionWait(Action)
    local W = S.TowerRefs.ActionWaitTime
    return (type(W) == "table" and tonumber(W[Action])) or 0.5
end

-- one run: returns the highest floor completed and whether the tower was cleared
-- enemy health of a floor from the tower config (nil = unknown)
local function EnemyHealth(Info, Floor)
    if type(Info) ~= "table" or type(Info.enemyHealth) ~= "function" then return nil end
    local Ok, V = pcall(Info.enemyHealth, Floor)
    if not (Ok and tonumber(V)) then Ok, V = pcall(Info.enemyHealth, Info, Floor) end
    return Ok and tonumber(V) or nil
end

local function RunTower(Name, MaxFloor, Probe)
    Fire(RE.TowerTeam)
    task.wait(1)
    local Ok, Started = InvokeT(10, RE.PlayTower, Name)
    if not Ok or Started ~= true then
        Log(("tower %s did not start (%s)"):format(Name, tostring(Started)))
        return nil, false
    end
    Status = "tower " .. Name
    local Floor, Fails, Ended = 0, 0, false
    while IsActive() do
        local Ok2, Res = InvokeT(10, RE.Floor)
        if not Ok2 or type(Res) ~= "table" then
            Fails += 1
            if Fails >= 4 then break end
            task.wait(1)
        else
            Fails = 0
            local Wait = 0
            for _, A in ipairs(Res) do
                if type(A) == "table" then
                    Wait += ActionWait(A.action)
                    if A.action == "floorCompleted" then
                        Floor = math.max(Floor, tonumber(A.floor) or Floor)
                        Stats.Floors += 1
                    elseif A.action == "ended" then
                        Ended = true
                    elseif A.action == "damageEnemy" and Probe and MaxFloor then
                        -- one hit already kills the LAST floor's enemy: this tower is no challenge, skip it
                        local Hit = tonumber(A.amount)
                        local Last = EnemyHealth(AllTowers[Name], MaxFloor)
                        if Hit and Last and Hit >= Last * Config.SkipMargin then
                            Log(("tower %s: one hit %s >= last floor enemy %s -> counted as cleared"):format(
                                Name, Short(Hit), Short(Last)))
                            InvokeT(8, RE.CancelTower)
                            Save.Best[Name] = math.max(tonumber(Save.Best[Name]) or 0, MaxFloor)
                            WriteSave()
                            task.wait(1)
                            return MaxFloor, true
                        end
                        Probe = false
                    end
                end
            end
            Status = ("tower %s floor %d / %s"):format(Name, Floor, tostring(MaxFloor or "?"))
            if Ended or #Res == 0 or (MaxFloor and Floor >= MaxFloor) then break end
            task.wait(math.max(Wait, 0.3))
        end
    end
    if not Ended then InvokeT(8, RE.CancelTower) end
    local Cleared = MaxFloor ~= nil and Floor >= MaxFloor
    Save.Best[Name] = math.max(tonumber(Save.Best[Name]) or 0, Floor)
    WriteSave()
    Log(("tower %s: floor %d%s (best %d)"):format(Name, Floor, Cleared and " CLEARED" or "", Save.Best[Name]))
    task.wait(2)
    return Floor, Cleared
end

local function TowerLoop()
    Fire(RE.AutoTower, false)   -- the script drives the towers
    InvokeT(8, RE.CancelTower)
    while IsActive() and Config.Towers do
        local Ok, Err = pcall(function()
            -- frontier: the first tower in the order that is not cleared yet
            local Frontier, Prev
            for I, Name in ipairs(Config.TowerOrder) do
                local Info = AllTowers[Name]
                local Max = Info and tonumber(Info.maxFloors) or 100
                if (tonumber(Save.Best[Name]) or 0) < Max then
                    Frontier = Name
                    Prev = Config.TowerOrder[I - 1]
                    break
                end
            end

            if Frontier then
                local Info = AllTowers[Frontier]
                local _, Cleared = RunTower(Frontier, Info and tonumber(Info.maxFloors) or 100, Config.SkipEasyTowers)
                if not Cleared and Prev then
                    local PInfo = AllTowers[Prev]
                    for _ = 1, Config.FarmRuns do
                        if not IsActive() then break end
                        RunTower(Prev, PInfo and tonumber(PInfo.maxFloors) or 100)
                    end
                end
            elseif Config.HalloweenTower then
                -- Haunted House: the wing that holds the next floor after the best one
                local X = D()
                local Best = X and X.Halloween and tonumber(X.Halloween.BestFloor) or 0
                local Wing, WingFirst
                for Name, Info in pairs(AllTowers) do
                    local W = type(Info) == "table" and Info.event == "Halloween" and Info.wing
                    local First = W and tonumber(W.firstFloor)
                    if First and First <= Best + 1 and (not WingFirst or First > WingFirst) then Wing, WingFirst = Name, First end
                end
                Wing = Wing or "Front Yard"
                local Info = AllTowers[Wing]
                RunTower(Wing, Info and Info.maxFloors and (WingFirst or 1) + Info.maxFloors - 1 or nil)
            else
                task.wait(10)
            end
        end)
        if not Ok then warn("[AD] tower error: " .. tostring(Err)) task.wait(5) end
    end
end

----------------------------------------------------------------
-- SKIP CUTSCENES
----------------------------------------------------------------
if Config.SkipCutscenes then
    local function Stub(Mod, Names)
        local M = Req(Mod)
        if type(M) ~= "table" then return end
        for _, N in ipairs(Names) do
            if type(M[N]) == "function" then M[N] = function() end end
        end
    end
    pcall(Stub, F.Rolling.RollController, {"PlayCutscene", "PlayExternalCutscene", "PlayRoll"})
    pcall(Stub, F.Notifications.EntryDropController, {"Play"})
    pcall(Stub, F.Inventory.Kinds.Spin.SpinController, {"PlayShower"})
    pcall(function()
        local RC = Req(F.Rolling.RollConfig)
        if type(RC) == "table" and RC.CLOVER_REVEAL_TIME then RC.CLOVER_REVEAL_TIME = 0 end
    end)
    -- the roll screen ("1 in ...", unit name, AUTO / HIDE): whenever it is on screen, click the game's HIDE
    task.spawn(function()
        local GS = game:GetService("GuiService")
        local VIM = game:GetService("VirtualInputManager")
        local Shown = false
        local function OnScreen(G)
            local O = G
            while O and not O:IsA("PlayerGui") do
                if O:IsA("GuiObject") and not O.Visible then return false end
                if O:IsA("LayerCollector") and not O.Enabled then return false end
                O = O.Parent
            end
            return G.AbsoluteSize.X > 0
        end
        while IsActive() do
            task.wait(0.5)
            local PG = LP:FindFirstChild("PlayerGui")
            for _, G in ipairs(PG and PG:GetDescendants() or {}) do
                if (G:IsA("TextLabel") or G:IsA("TextButton")) and G.Text:upper():gsub("%s", "") == "HIDE" and OnScreen(G) then
                    -- the clickable thing: the button itself, or the nearest button / image above the label
                    local Btn = (G:IsA("GuiButton") and G) or G:FindFirstAncestorWhichIsA("GuiButton") or G.Parent
                    local N = 0
                    pcall(function()
                        for _, Ev in ipairs({"MouseButton1Down", "MouseButton1Up", "MouseButton1Click", "Activated", "InputBegan", "InputEnded"}) do
                            if Btn[Ev] then
                                for _, C in ipairs(getconnections(Btn[Ev])) do
                                    pcall(function()
                                        if Ev:find("Input") then
                                            C:Fire({UserInputType = Enum.UserInputType.MouseButton1, UserInputState = Ev == "InputBegan" and Enum.UserInputState.Begin or Enum.UserInputState.End, Position = Vector3.zero})
                                        else
                                            C:Fire()
                                        end
                                    end)
                                    N += 1
                                end
                            end
                        end
                    end)
                    if N == 0 then
                        -- no script connections found: a real mouse click in the middle of it
                        pcall(function()
                            local P = Btn.AbsolutePosition + Btn.AbsoluteSize / 2 + GS:GetGuiInset()
                            VIM:SendMouseButtonEvent(P.X, P.Y, 0, true, game, 0)
                            task.wait(0.05)
                            VIM:SendMouseButtonEvent(P.X, P.Y, 0, false, game, 0)
                        end)
                    end
                    if not Shown then
                        Shown = true
                        Log(("roll screen: pressing HIDE (%s, %d connections)"):format(Btn:GetFullName(), N))
                    end
                    break
                end
            end
        end
    end)
    Log("cutscenes skipped")
end

----------------------------------------------------------------
-- START
----------------------------------------------------------------
do
    local X = D()
    if not X then warn("[AD] player data not found (DataController.___X). Stopping.") return end
    local Plot = 0
    for _ in pairs(X.Slots or {}) do Plot += 1 end
    print(("[AD] kaitun v1.5 | money %s, rebirth %s, dice %s, plot units %d, towers best %s"):format(
        Short(X.Money), tostring(X.Rebirth), tostring(X.Dice), Plot, S.Http:JSONEncode(Save.Best)))
end

if not Config.SafeMode then
    warn("[AD] SafeMode is OFF (alt account mode): every unit can be sold by its RAW value (except locked / NeverSell). Use SafeMode = true on a main account!")
end
if Config.AutoRoll then Fire(RE.AutoRoll, true) end

local function Every(Seconds, Fn, Name)
    task.spawn(function()
        while IsActive() do
            local Ok, Err = pcall(Fn)
            if not Ok then warn(("[AD] %s error: %s"):format(Name, tostring(Err))) end
            task.wait(Seconds)
        end
    end)
end

Every(Config.SellEvery, ManageUnits, "units")
Every(Config.LevelUpEvery, LevelUpAll, "level up")
Every(Config.CollectEvery, CollectAll, "collect")
if Config.AutoDice then Every(5, ManageDice, "dice") end
if Config.AutoRebirth then Every(5, DoRebirth, "rebirth") end
if Config.AutoUpgrades then Every(5, ManageUpgrades, "upgrades") end
if #Config.CandyUpgrades > 0 then Every(30, ManageCandy, "candy upgrades") end
if Config.AutoBoosts then Every(15, UseBoosts, "boosts") end
Every(Config.ClaimEvery, DoClaims, "claims")
Every(300, function() if Config.AutoRoll then Fire(RE.AutoRoll, true) end end, "auto roll")
if Config.TrickOrTreat then task.spawn(TrickOrTreat) end
if Config.Towers then task.spawn(TowerLoop) end

-- status every 30 s
task.spawn(function()
    while IsActive() do
        task.wait(30)
        print(("[AD] %s | money %s, rebirth %s | 30 s: sold %d, levels %d, floors %d, doors %d"):format(
            Status, Short(Money()), tostring(D() and D().Rebirth), Stats.Sold, Stats.Levels, Stats.Floors, Stats.Doors))
        for K in pairs(Stats) do Session.Count[K] += Stats[K] end
        Stats.Sold, Stats.Levels, Stats.Floors, Stats.Doors = 0, 0, 0, 0
    end
end)


----------------------------------------------------------------
-- CPU / RAM SAVER
----------------------------------------------------------------
if Config.Saver then
    do
        local RunService = game:GetService("RunService")
        if Config.FPSCap and setfpscap then pcall(setfpscap, Config.FPSCap) end
        if Config.WhiteScreen then
            pcall(function() RunService:Set3dRenderingEnabled(false) end)
            if not Config.Panel then
                local Parent
                pcall(function() Parent = gethui() end)
                if not Parent then pcall(function() Parent = game:GetService("CoreGui") end) end
                Parent = Parent or LP:WaitForChild("PlayerGui")
                pcall(function() local Old = Parent:FindFirstChild("AnimeDiceWhite") if Old then Old:Destroy() end end)
                local W = Instance.new("ScreenGui")
                W.Name, W.IgnoreGuiInset, W.ResetOnSpawn, W.DisplayOrder = "AnimeDiceWhite", true, false, 999998
                W.Parent = Parent
                local F = Instance.new("Frame")
                F.Size = UDim2.fromScale(1, 1)
                F.BackgroundColor3 = Color3.new(1, 1, 1)
                F.BorderSizePixel = 0
                F.Parent = W
                task.spawn(function()
                    while IsActive() do task.wait(1) end
                    pcall(function() W:Destroy() end)
                    pcall(function() RunService:Set3dRenderingEnabled(true) end)
                end)
            end
        end
        if Config.LowGraphics then
            pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
            pcall(function()
                local L = game:GetService("Lighting")
                L.GlobalShadows = false
                L.FogEnd = 9e9
                for _, E in ipairs(L:GetChildren()) do
                    if E:IsA("PostEffect") or E:IsA("Atmosphere") or E:IsA("Sky") then pcall(function() E:Destroy() end) end
                end
            end)
            pcall(function() workspace.Terrain.Decoration = false end)
            local function Strip(O)
                pcall(function()
                    if O:IsA("ParticleEmitter") or O:IsA("Trail") or O:IsA("Beam") or O:IsA("Smoke") or O:IsA("Fire") or O:IsA("Sparkles") then
                        O.Enabled = false
                    elseif O:IsA("Decal") or O:IsA("Texture") then
                        O.Transparency = 1
                    elseif O:IsA("Sound") then
                        O.Volume = 0
                    elseif O:IsA("PointLight") or O:IsA("SpotLight") or O:IsA("SurfaceLight") then
                        O.Enabled = false
                    elseif O:IsA("BasePart") then
                        O.CastShadow = false
                        O.Material = Enum.Material.Plastic
                    end
                end)
            end
            task.spawn(function()
                for I, O in ipairs(game:GetDescendants()) do
                    Strip(O)
                    if I % 2000 == 0 then task.wait() end
                end
            end)
            workspace.DescendantAdded:Connect(Strip)
        end
        Log(("saver on: fps cap %s, 3D off %s, low graphics %s"):format(tostring(Config.FPSCap), tostring(Config.WhiteScreen), tostring(Config.LowGraphics)))
    end
end

----------------------------------------------------------------
-- PANEL (full screen, same style as the Tap Simulator kaitun)
----------------------------------------------------------------
if Config.Panel then
    do
        local RunService = game:GetService("RunService")
        local Parent
        pcall(function() Parent = gethui() end)
        if not Parent then pcall(function() Parent = game:GetService("CoreGui") end) end
        Parent = Parent or LP:WaitForChild("PlayerGui")
        pcall(function() local Old = Parent:FindFirstChild("AnimeDicePanel") if Old then Old:Destroy() end end)

        local Green = Color3.fromRGB(26, 188, 156)
        local Gui = Instance.new("ScreenGui")
        Gui.Name, Gui.IgnoreGuiInset, Gui.ResetOnSpawn, Gui.DisplayOrder = "AnimeDicePanel", true, false, 999999
        Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        Gui.Parent = Parent

        local Back = Instance.new("Frame")
        Back.Size = UDim2.fromScale(1, 1)
        Back.BackgroundColor3 = Color3.fromRGB(13, 17, 23)
        Back.BorderSizePixel = 0
        Back.Active = true
        Back.Parent = Gui

        local Box = Instance.new("Frame")
        Box.AnchorPoint = Vector2.new(0.5, 0.5)
        Box.Position = UDim2.fromScale(0.5, 0.5)
        Box.Size = UDim2.fromOffset(720, 760)
        Box.BackgroundTransparency = 1
        Box.Parent = Back
        local Scale = Instance.new("UIScale")
        Scale.Parent = Box
        local function Fit()
            local V = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
            Scale.Scale = math.clamp(math.min(V.X / 760, V.Y / 800), 0.4, 1.2)
        end
        Fit()
        pcall(function() workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(Fit) end)

        local Layout = Instance.new("UIListLayout")
        Layout.Padding = UDim.new(0, 8)
        Layout.SortOrder = Enum.SortOrder.LayoutOrder
        Layout.Parent = Box

        local Title = Instance.new("TextLabel")
        Title.Size = UDim2.new(1, 0, 0, 60)
        Title.BackgroundTransparency = 1
        Title.Font = Enum.Font.GothamBlack
        Title.Text = "Anime Dice Kaitun"
        Title.TextColor3 = Green
        Title.TextScaled = true
        Title.LayoutOrder = 0
        Title.Parent = Box

        local Rows, Order = {}, 0
        local function Row(Name, Gap)
            Order += 1
            if Gap then
                local Line = Instance.new("Frame")
                Line.Size = UDim2.new(1, 0, 0, 2)
                Line.BackgroundColor3 = Green
                Line.BackgroundTransparency = 0.6
                Line.BorderSizePixel = 0
                Line.LayoutOrder = Order
                Line.Parent = Box
                Order += 1
            end
            local F = Instance.new("Frame")
            F.Size = UDim2.new(1, 0, 0, 34)
            F.BackgroundColor3 = Color3.fromRGB(24, 29, 38)
            F.BorderSizePixel = 0
            F.LayoutOrder = Order
            F.Parent = Box
            Instance.new("UICorner", F).CornerRadius = UDim.new(0, 6)
            local L = Instance.new("TextLabel")
            L.Size = UDim2.new(0.45, -12, 1, 0)
            L.Position = UDim2.new(0, 12, 0, 0)
            L.BackgroundTransparency = 1
            L.Font = Enum.Font.GothamBold
            L.Text = Name
            L.TextColor3 = Color3.fromRGB(205, 210, 220)
            L.TextSize = 20
            L.TextXAlignment = Enum.TextXAlignment.Left
            L.Parent = F
            local V = Instance.new("TextLabel")
            V.Size = UDim2.new(0.55, -12, 1, 0)
            V.Position = UDim2.new(0.45, 0, 0, 0)
            V.BackgroundTransparency = 1
            V.Font = Enum.Font.GothamBold
            V.Text = "-"
            V.TextColor3 = Green
            V.TextSize = 20
            V.TextXAlignment = Enum.TextXAlignment.Right
            V.TextTruncate = Enum.TextTruncate.AtEnd
            V.Parent = F
            Rows[Name] = V
        end

        Row("Status")
        Row("Tower")
        Row("Last action")
        Row("Rolls (session)", true)
        Row("Units sold (session)")
        Row("Time Farmed")
        Row("Money", true)
        Row("Candy")
        Row("Rebirth")
        Row("Dice")
        Row("Upgrades / Rebirths (session)", true)
        Row("Backpack")
        Row("Best floors")

        local Toggle = Instance.new("TextButton")
        Toggle.AnchorPoint = Vector2.new(1, 0)
        Toggle.Position = UDim2.new(1, -12, 0, 12)
        Toggle.Size = UDim2.fromOffset(150, 36)
        Toggle.BackgroundColor3 = Green
        Toggle.Font = Enum.Font.GothamBold
        Toggle.TextColor3 = Color3.fromRGB(13, 17, 23)
        Toggle.TextSize = 16
        Toggle.ZIndex = 10
        Toggle.Parent = Gui
        Instance.new("UICorner", Toggle).CornerRadius = UDim.new(0, 8)

        local Shown = true
        local function Apply()
            Back.Visible = Shown
            Toggle.Text = Shown and "Show game" or "Show panel"
            if Config.HideWorld or (Config.Saver and Config.WhiteScreen) then
                pcall(function() RunService:Set3dRenderingEnabled(not Shown) end)
            end
        end
        Toggle.MouseButton1Click:Connect(function() Shown = not Shown Apply() end)
        Apply()

        local function Clock(T)
            T = math.floor(T)
            return ("%02d:%02d:%02d"):format(T // 3600, T % 3600 // 60, T % 60)
        end
        local StartRolls = tonumber(D() and D().Rolls) or 0

        task.spawn(function()
            while IsActive() and Gui.Parent do
                pcall(function()
                    local X = D() or {}
                    local Cn = Session.Count
                    local Units = 0
                    for _, E in pairs(X.Inventory or {}) do
                        if type(E) == "table" and S.Units[E.name] then Units += (tonumber(E.amount) or 1) end
                    end
                    -- current tower: first one in the order not cleared yet
                    local Tower = "Haunted House"
                    for _, N in ipairs(Config.TowerOrder) do
                        local Info = AllTowers[N]
                        if (tonumber(Save.Best[N]) or 0) < (Info and tonumber(Info.maxFloors) or 100) then Tower = N break end
                    end
                    local Cleared = 0
                    for _, N in ipairs(Config.TowerOrder) do
                        local Info = AllTowers[N]
                        if (tonumber(Save.Best[N]) or 0) >= (Info and tonumber(Info.maxFloors) or 100) then Cleared += 1 end
                    end
                    local Last = Session.Feed[1] or "-"
                    Rows["Status"].Text = tostring(Status)
                    Rows["Tower"].Text = ("%s (%d/%d cleared)"):format(Tower, Cleared, #Config.TowerOrder)
                    Rows["Last action"].Text = Last:gsub("^%S+%s+", "")
                    Rows["Rolls (session)"].Text = Short((tonumber(X.Rolls) or 0) - StartRolls)
                    Rows["Units sold (session)"].Text = Short(Cn.Sold + Stats.Sold)
                    Rows["Time Farmed"].Text = Clock(os.clock() - Session.Start)
                    Rows["Money"].Text = Short(X.Money)
                    Rows["Candy"].Text = Short(CandyAmount() or 0)
                    Rows["Rebirth"].Text = tostring(X.Rebirth or 0)
                    Rows["Dice"].Text = tostring(X.Dice or "-")
                    Rows["Upgrades / Rebirths (session)"].Text = ("%d / %d"):format(Cn.Upgrades, Cn.Rebirths)
                    Rows["Backpack"].Text = ("%d / %d"):format(Units, StorageCap())
                    local H = tonumber(X.Halloween and X.Halloween.BestFloor) or 0
                    local Cur = tonumber(Save.Best[Tower]) or 0
                    Rows["Best floors"].Text = ("%s %d | Haunted %d"):format(Tower:gsub(" Tower", ""), Cur, H)
                end)
                task.wait(0.5)
            end
            pcall(function() RunService:Set3dRenderingEnabled(true) end)
            pcall(function() Gui:Destroy() end)
        end)
    end
end

print("[AD] kaitun started")