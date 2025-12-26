-- autoFarmSrc.lua
-- Unified Auto-Farm script loading separated modules from "The Forge" folder
return function(ctx)
    ----------------------------------------------------------------
    -- CONTEXT BINDINGS
    ----------------------------------------------------------------
    local Services             = ctx.Services or {}
    local Tabs                 = ctx.Tabs
    local References           = ctx.References
    local Library              = ctx.Library
    local Options              = ctx.Options
    local Toggles              = ctx.Toggles
    local META                 = ctx.META or {}
    local AttachPanel          = ctx.AttachPanel
    local MoveToPos            = ctx.MoveToPos
    local RunService           = Services.RunService or game:GetService("RunService")
    local UserInputService     = Services.UserInputService or game:GetService("UserInputService")
    local HttpService          = Services.HttpService or game:GetService("HttpService")
    local VirtualInputManager  = Services.VirtualInputManager or game:GetService("VirtualInputManager")
    local Players              = game:GetService("Players")

    local ALT_FARM_MODE_MAIN   = "Main Alt"
    local ALT_FARM_MODE_HELPER = "Helper Alt"
    local ALT_FARM_DATA_FILE   = "Cerberus/The Forge/AltFarmAlts.txt"

    ----------------------------------------------------------------
    -- CONFIGURATION FLAGS & STATE
    ----------------------------------------------------------------
    local AF_Config            = {
        AvoidLava                    = false,
        AvoidPlayers                 = false,
        DamageDitchEnabled           = false,
        DamageDitchThreshold         = 100,
        TargetFullHealth             = false,
        PlayerAvoidRadius            = 40,
        AttackNearbyMobs             = false,
        NearbyMobRange               = 40,
        OreWhitelistEnabled          = false,
        WhitelistedOres              = {},
        WhitelistAppliesTo           = {},
        ZoneWhitelistEnabled         = false,
        WhitelistedZones             = {},
        TargetBlacklist              = {},
        ExtraYOffset                 = 0,
        FarmSpeed                    = 80,
        AltFarmEnabled               = false,
        AltFarmMode                  = ALT_FARM_MODE_MAIN,
        AltNames                     = {},
        AltNameSet                   = {},
        QuestPriorityOverrideEnabled = false,
        QuestAutoCompleteEnabled     = false,
        QuestTargetFilter            = {},
        MovementMode                 = "Teleport",
    }

    local FarmState            = {
        enabled             = false,
        mode                = "Ores",
        nameMap             = {},
        -- Potion interop
        restocking          = false,
        potionThread        = nil,
        -- Current target data
        currentTarget       = nil,
        tempMobTarget       = nil,
        attached            = false,
        moveCleanup         = nil,
        farmThread          = nil,
        noclipConn          = nil,
        lastHit             = 0,
        detourActive        = false,
        detourNotified      = false,
        lastTargetRef       = nil,
        lastTargetHealth    = 0,
        stuckStartTime      = 0,
        lastMovePos         = Vector3.zero,
        lastMoveTime        = 0,
        LastLocalHealth     = 100,
        avoidingPlayer      = false,
        lastAvoidMoveTime   = 0,
        lastAvoidNoticeTime = 0,
    }

    ----------------------------------------------------------------
    -- MODULE LOADER (file -> GitHub fallback)
    ----------------------------------------------------------------
    local function loadModule(moduleName)
        local path = "Cerberus/The Forge/" .. moduleName .. ".lua"
        local chunk
        if isfile and isfile(path) then
            chunk = readfile(path)
        else
            chunk = game:HttpGet(
                "https://raw.githubusercontent.com/whodunitwww/noxhelpers/refs/heads/main/the-forge/auto-farm-modules/" ..
                moduleName .. ".lua"
            )
        end

        local loader, err = loadstring(chunk)
        if not loader then
            error("Error loading module " .. moduleName .. ": " .. tostring(err))
        end

        local moduleFunc = loader()
        if typeof(moduleFunc) ~= "function" then
            error("Module " .. moduleName .. " did not return a function!")
        end
        return moduleFunc
    end

    -- Load each module with context
    local Helpers = loadModule("AF_Helpers")({
        References          = References,
        Library             = Library,
        Services            = Services,
        VirtualInputManager = VirtualInputManager,
    })

    local Remotes = loadModule("AF_Remotes")({
        Services = Services,
    })

    local Priority = loadModule("AF_Priority")({
        HttpService = HttpService,
        notify      = function(msg, t)
            Helpers.notify(msg, t)
        end,
    })

    local QuestTargets = loadModule("AF_QuestTargets")({
        Services     = Services,
        RefreshDelay = 4,
    })

    local Ores = loadModule("AF_Ores")({
        Services    = Services,
        References  = References,
        AttachPanel = AttachPanel,
        Players     = Players,
        AF_Config   = AF_Config,
    })

    local Mobs = loadModule("AF_Mobs")({
        Services    = Services,
        getLocalHRP = Helpers.getLocalHRP,
        AF_Config   = AF_Config,
    })

    local Movement = loadModule("AF_Movement")({
        AttachPanel = AttachPanel,
        MoveToPos   = MoveToPos,
        getLocalHRP = Helpers.getLocalHRP,
        FarmState   = FarmState,
        AF_Config   = AF_Config,
        Services    = Services,
        References  = References,
    })

    local Avoidance = loadModule("AF_Avoidance")({
        Services    = Services,
        References  = References,
        getLocalHRP = Helpers.getLocalHRP,
        MoveToPos   = MoveToPos,
        stopMoving  = function()
            if Movement.stopMoving then
                Movement.stopMoving()
            end
        end,
        FarmState   = FarmState,
        AF_Config   = AF_Config,
    })

    local Potions = loadModule("AF_Potions")({
        Services        = Services,
        Options         = Options,
        Toggles         = Toggles,
        FarmState       = FarmState,
        PurchaseRF      = Remotes.PurchaseRF,
        ToolActivatedRF = Remotes.ToolActivatedRF,
        notify          = Helpers.notify,
        AttachPanel     = AttachPanel,
        stopMoving      = function()
            if Movement.stopMoving then
                Movement.stopMoving()
            end
        end,
    })

    local Tracker = loadModule("AF_Tracker")({
        Services       = Services,
        HttpService    = HttpService,
        notify         = Helpers.notify,
        getLocalHRP    = Helpers.getLocalHRP,
        rockHealth     = Ores.rockHealth,
        getRocksFolder = Ores.getRocksFolder,
        ConfigFile     = "Cerberus/The Forge/HudConfig.json",
    })

    -- NEW: Autofarm Dashboard (standalone HUD)
    local Dashboard = nil
    local okDash, errDash = pcall(function()
        Dashboard = loadModule("AF_Dashboard")({
            Services   = Services,
            References = References,
            Library    = Library,
            META       = META,
        })
    end)
    if not okDash then
        warn("[AutoFarm] Failed to load AF_Dashboard:", errDash)
        Dashboard = nil
    end

    -- Helper: is dashboard toggle actually ON?
    local function dashboardEnabled()
        return Dashboard
            and Toggles
            and Toggles.AF_DashboardEnabled
            and Toggles.AF_DashboardEnabled.Value
    end

    ----------------------------------------------------------------
    -- Alias commonly used module functions for clarity
    ----------------------------------------------------------------
    local getLocalHRP                = Helpers.getLocalHRP
    local notify                     = Helpers.notify
    local swingTool                  = Remotes.swingTool
    local stopMoving                 = Movement.stopMoving
    local startMovingToTarget        = Movement.startMovingToTarget
    local attachToTarget             = Movement.attachToTarget
    local realignAttach              = Movement.realignAttach
    local saveAttachSettings         = Movement.saveAttachSettings
    local restoreAttachSettings      = Movement.restoreAttachSettings
    local isPointInHazard            = Avoidance.isPointInHazard
    local isAnyPlayerNearHRP         = Avoidance.isAnyPlayerNearHRP
    local isAnyPlayerNearPosition    = Avoidance.isAnyPlayerNearPosition
    local moveAwayFromNearbyPlayers  = Avoidance.moveAwayFromNearbyPlayers
    local isRockLastHitByOther       = Ores.isRockLastHitByOther
    local isMobAlive                 = Mobs.isMobAlive
    local getMobRoot                 = Mobs.getMobRoot
    local findNearbyEnemy            = Mobs.findNearbyEnemy
    local questTargets               = QuestTargets

    local AUTO_QUEST_SCAN_INTERVAL   = 5
    local AUTO_QUEST_REPEAT_INTERVAL = 60

    local RunCommandRemote           = nil
    local QuestServiceRemote         = nil
    local autoQuestMissingWarn       = false
    local AutoQuestState             = {
        running         = false,
        thread          = nil,
        lastCommandTime = {},
    }

    local function resolveRunCommandRemote()
        if RunCommandRemote then
            return RunCommandRemote
        end

        local storage = Services.ReplicatedStorage or game:GetService("ReplicatedStorage")
        if not storage then
            return nil
        end

        -- Safe child resolver with fallback to WaitForChild and a timeout
        local function safeGetChild(parent, name, timeout)
            if not parent then return nil end

            local child = parent:FindFirstChild(name)
            if child then return child end

            timeout = timeout or 10
            local ok, result = pcall(function()
                return parent:WaitForChild(name, timeout)
            end)

            if ok then
                return result
            else
                return nil
            end
        end

        local function findServicesFolder()
            local shared     = safeGetChild(storage, "Shared")
            local packages   = safeGetChild(shared, "Packages") or safeGetChild(storage, "Packages")
            local knitFolder = safeGetChild(packages, "Knit")
            local services   = safeGetChild(knitFolder, "Services") or safeGetChild(packages, "Services")
            if services then
                return services
            end
            return safeGetChild(shared, "Services")
        end

        local services   = findServicesFolder()
        local dialogue   = safeGetChild(services, "DialogueService")
        local rf         = safeGetChild(dialogue, "RF")
        local runCommand = safeGetChild(rf, "RunCommand")

        if not runCommand then
            for _, inst in ipairs(storage:GetDescendants()) do
                if inst:IsA("RemoteFunction") and inst.Name == "RunCommand" then
                    runCommand = inst
                    break
                end
            end
        end

        if runCommand then
            RunCommandRemote = runCommand
        end

        return RunCommandRemote
    end

    local function resolveQuestService()
        if QuestServiceRemote then
            return QuestServiceRemote
        end

        local storage = Services.ReplicatedStorage or game:GetService("ReplicatedStorage")
        if not storage then
            return nil
        end

        local function safeGetChild(parent, name, timeout)
            if not parent then return nil end

            local child = parent:FindFirstChild(name)
            if child then return child end

            timeout = timeout or 10
            local ok, result = pcall(function()
                return parent:WaitForChild(name, timeout)
            end)

            if ok then
                return result
            else
                return nil
            end
        end

        local shared     = safeGetChild(storage, "Shared")
        local packages   = safeGetChild(shared, "Packages") or safeGetChild(storage, "Packages")
        local knitHolder = safeGetChild(packages, "Knit") or safeGetChild(shared, "Knit") or safeGetChild(storage, "Knit")
        local knitModule = knitHolder
        if knitModule and knitModule:IsA("Folder") then
            knitModule = safeGetChild(knitModule, "Knit")
        end
        if not knitModule or not knitModule:IsA("ModuleScript") then
            return nil
        end

        local okKnit, Knit = pcall(require, knitModule)
        if not okKnit or type(Knit) ~= "table" or type(Knit.GetService) ~= "function" then
            return nil
        end

        local okService, service = pcall(Knit.GetService, Knit, "QuestService")
        if okService and service then
            QuestServiceRemote = service
        end
        return QuestServiceRemote
    end

    local function tryQuestServiceFinish(service, questId)
        if not service or not questId then
            return false
        end
        local methods = {
            "CompleteQuest",
            "FinishQuest",
            "TurnInQuest",
            "ClaimQuest",
        }
        for _, methodName in ipairs(methods) do
            local fn = service[methodName]
            if type(fn) == "function" then
                local ok = pcall(fn, service, questId)
                if ok then
                    return true
                end
            end
        end
        return false
    end

    local function collectQuestListFrames()
        local player = Players.LocalPlayer
        if not player then
            return {}
        end
        local gui = player:FindFirstChild("PlayerGui")
        if not gui then
            return {}
        end
        local main = gui:FindFirstChild("Main")
        if not main then
            return {}
        end
        local screen = main:FindFirstChild("Screen")
        local quests = screen and screen:FindFirstChild("Quests")
        local listFolder = quests and quests:FindFirstChild("List")
        if not listFolder then
            return {}
        end
        local questFrames = {}
        for _, child in ipairs(listFolder:GetChildren()) do
            if child:IsA("Frame") and child.Name:match("List$") then
                table.insert(questFrames, child)
            end
        end
        return questFrames
    end

    local function buildQuestFinishCommand(listName)
        if not listName or listName == "" then
            return nil
        end
        local questIndex = listName:match("Quest(%d+)List$")
        if questIndex then
            return "FinishQuest" .. questIndex
        end
        local base = listName
        if #base > 4 and base:sub(-4) == "List" then
            base = base:sub(1, -5)
        end
        if base == "" then
            return nil
        end
        return "Finish" .. base
    end

    local function invokeQuestCommand(commandName, remote)
        if not commandName or not remote then
            return false
        end
        local ok, err = pcall(function()
            remote:InvokeServer(commandName)
        end)
        if not ok then
            warn("[AutoFarm] Quest Autocomplete failed for " .. commandName .. ": " .. tostring(err))
        end
        return ok
    end

    local function runAutoQuestLoop()
        while AutoQuestState.running do
            local questData = questTargets and questTargets.getQuestData and questTargets.getQuestData()
            local questIds = questTargets and questTargets.getActiveQuestIds and questTargets.getActiveQuestIds()
            local questService = resolveQuestService()
            local remote = resolveRunCommandRemote()

            if questData and questIds and questTargets and questTargets.isQuestCompleted then
                if not questService and not remote then
                    if not autoQuestMissingWarn then
                        warn("[AutoFarm] Cannot find QuestService or RunCommand for quest autocomplete.")
                        autoQuestMissingWarn = true
                    end
                else
                    autoQuestMissingWarn = false
                    local now = os.clock()
                    for _, questId in ipairs(questIds) do
                        if questTargets.isQuestCompleted(questId) then
                            local key = "QuestFinish:" .. questId
                            local lastTime = AutoQuestState.lastCommandTime[key]
                            if not lastTime or (now - lastTime) >= AUTO_QUEST_REPEAT_INTERVAL then
                                local finished = false
                                if questService then
                                    finished = tryQuestServiceFinish(questService, questId)
                                end
                                if not finished and remote then
                                    local command = "Finish" .. questId
                                    finished = invokeQuestCommand(command, remote)
                                    if not finished and questTargets.getQuestSlot then
                                        local slot = questTargets.getQuestSlot(questId)
                                        if slot then
                                            finished = invokeQuestCommand("FinishQuest" .. tostring(slot), remote)
                                        end
                                    end
                                end
                                if finished then
                                    AutoQuestState.lastCommandTime[key] = now
                                end
                            end
                        end
                    end
                end
            else
                if not remote then
                    if not autoQuestMissingWarn then
                        warn("[AutoFarm] Cannot find RunCommand RF for quest autocomplete.")
                        autoQuestMissingWarn = true
                    end
                else
                    autoQuestMissingWarn = false
                    local now = os.clock()
                    local frames = collectQuestListFrames()
                    for _, frame in ipairs(frames) do
                        local command = buildQuestFinishCommand(frame.Name)
                        if command then
                            local lastTime = AutoQuestState.lastCommandTime[command]
                            if not lastTime or (now - lastTime) >= AUTO_QUEST_REPEAT_INTERVAL then
                                if invokeQuestCommand(command, remote) then
                                    AutoQuestState.lastCommandTime[command] = now
                                end
                            end
                        end
                    end
                end
            end

            local elapsed = 0
            while AutoQuestState.running and elapsed < AUTO_QUEST_SCAN_INTERVAL do
                task.wait(0.05)
                elapsed = elapsed + 0.05
            end
        end
    end

    local function startAutoQuestLoop()
        if AutoQuestState.running then
            return
        end
        AutoQuestState.lastCommandTime = {}
        AutoQuestState.running = true
        AutoQuestState.thread = task.spawn(runAutoQuestLoop)
    end

    local function stopAutoQuestLoop()
        AutoQuestState.running = false
        AutoQuestState.thread = nil
    end

    ----------------------------------------------------------------
    -- MODE DEFINITIONS (for target scanning and hitting)
    ----------------------------------------------------------------
    local FARM_MODE_ORES    = "Ores"
    local FARM_MODE_ENEMIES = "Enemies"

    local ModeDefs          = {
        [FARM_MODE_ORES] = {
            name          = FARM_MODE_ORES,
            scan          = Ores.scanRocks,
            isAlive       = Ores.isRockAlive,
            getPos        = Ores.rockPosition,
            getRoot       = Ores.rockRoot,
            getHealth     = Ores.rockHealth,
            attachMode    = "Aligned",
            attachBaseY   = -8,
            attachHoriz   = 0,
            hitInterval   = 0.15,
            hitDistance   = 20,
            toolName      = "Pickaxe",
            toolRemoteArg = "Pickaxe",
        },

        [FARM_MODE_ENEMIES] = {
            name          = FARM_MODE_ENEMIES,
            scan          = Mobs.scanMobs,
            isAlive       = Mobs.isMobAlive,
            getPos        = Mobs.mobPosition,
            getRoot       = Mobs.getMobRoot,
            getHealth     = Mobs.getMobHealth,
            attachMode    = "Aligned",
            attachBaseY   = -7,
            attachHoriz   = 0,
            hitInterval   = 0.15,
            hitDistance   = 20,
            toolName      = "Weapon",
            toolRemoteArg = "Weapon",
        },
    }

    ----------------------------------------------------------------
    -- CORE HELPER FUNCTIONS (Blacklisting & target selection)
    ----------------------------------------------------------------
    local function isTargetBlacklisted(model)
        if not model then
            return false
        end

        local expiry = AF_Config.TargetBlacklist[model]
        if not expiry then
            return false
        end

        if (not model.Parent) or os.clock() >= expiry then
            AF_Config.TargetBlacklist[model] = nil
            return false
        end

        return true
    end

    local function blacklistTarget(model, duration)
        if not model then
            return
        end
        AF_Config.TargetBlacklist[model] = os.clock() + (duration or 60)
    end

    local function hasWhitelistSelections()
        if not AF_Config.OreWhitelistEnabled then
            return false
        end

        local whitelisted = AF_Config.WhitelistedOres or {}
        return next(whitelisted) ~= nil
    end

    local function shouldHoldTargetForWhitelist(model)
        if not model or not hasWhitelistSelections() then
            return false
        end

        local appliesTo = AF_Config.WhitelistAppliesTo or {}
        if not appliesTo[model.Name] then
            return false
        end

        local whitelisted = AF_Config.WhitelistedOres or {}
        for _, child in ipairs(model:GetChildren()) do
            if child.Name == "Ore" then
                local oreType = child:GetAttribute("Ore")
                if oreType and whitelisted[oreType] then
                    return true
                end
            end
        end

        return false
    end

    local function ensureAltDataFolder()
        if not makefolder then
            return
        end
        pcall(makefolder, "Cerberus")
        pcall(makefolder, "Cerberus/The Forge")
    end

    local function applyAltNamesList(list)
        local cleaned = {}
        local seen = {}
        for _, name in ipairs(list or {}) do
            local normalized = tostring(name):match("^%s*(.-)%s*$")
            if normalized ~= "" then
                local key = normalized:lower()
                if not seen[key] then
                    seen[key] = true
                    table.insert(cleaned, normalized)
                end
            end
        end
        AF_Config.AltNames   = cleaned
        AF_Config.AltNameSet = {}
        for _, name in ipairs(cleaned) do
            AF_Config.AltNameSet[name:lower()] = true
        end
    end

    local function loadAltNamesFromFile()
        if not (isfile and isfile(ALT_FARM_DATA_FILE)) then
            return {}
        end

        local ok, contents = pcall(readfile, ALT_FARM_DATA_FILE)
        if not ok or not contents then
            return {}
        end

        local result = {}
        for line in tostring(contents):gmatch("[^\r\n]+") do
            local normalized = line:match("^%s*(.-)%s*$")
            if normalized ~= "" then
                table.insert(result, normalized)
            end
        end
        return result
    end

    local function saveAltNamesToFile()
        if not writefile then
            return
        end
        ensureAltDataFolder()
        local serialized = table.concat(AF_Config.AltNames or {}, "\n")
        pcall(writefile, ALT_FARM_DATA_FILE, serialized)
    end

    local function addAltName(name)
        local normalized = tostring(name or ""):match("^%s*(.-)%s*$")
        if normalized == "" then
            return false, "Name is empty"
        end
        if AF_Config.AltNameSet[normalized:lower()] then
            return false, "Already tracking " .. normalized
        end
        local list = { table.unpack(AF_Config.AltNames or {}) }
        table.insert(list, normalized)
        applyAltNamesList(list)
        saveAltNamesToFile()
        return true
    end

    local function notifyAltRoster()
        local names = AF_Config.AltNames or {}
        local msg
        if #names == 0 then
            msg = "No saved alts yet."
        else
            msg = "Alts: " .. table.concat(names, ", ")
        end
        notify("Alt Farm enabled. " .. msg, 3)
    end

    ensureAltDataFolder()
    applyAltNamesList(loadAltNamesFromFile())

    local function updateDashboardPlayers()
        if not dashboardEnabled() or not Dashboard or not Dashboard.setNearbyPlayers then
            return
        end

        local hrp = getLocalHRP()
        if not hrp then
            return
        end

        -- extra safety: if for some reason Players wasn’t bound, grab it now
        local playersService = Players or game:GetService("Players")
        if not playersService then return end

        local data        = {}
        local localPlayer = References.player or playersService.LocalPlayer

        for _, plr in ipairs(playersService:GetPlayers()) do
            if plr ~= localPlayer then
                local char = plr.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if root then
                    local dist = (root.Position - hrp.Position).Magnitude
                    table.insert(data, {
                        Player   = plr,
                        Name     = (plr.DisplayName or plr.Name) .. " (" .. plr.Name .. ")",
                        Distance = dist,
                    })
                end
            end
        end

        table.sort(data, function(a, b)
            return a.Distance < b.Distance
        end)

        Dashboard.setNearbyPlayers(data)
    end

    local function isHelperAltEnabled()
        return AF_Config.AltFarmEnabled
            and AF_Config.AltFarmMode == ALT_FARM_MODE_HELPER
            and hasWhitelistSelections()
    end

    local function isMainAltEnabled()
        return AF_Config.AltFarmEnabled
            and AF_Config.AltFarmMode == ALT_FARM_MODE_MAIN
            and hasWhitelistSelections()
            and next(AF_Config.AltNameSet or {}) ~= nil
    end

    local function rockLastHitWasAlt(model)
        if not model then
            return false
        end
        local lastHit = model:GetAttribute("LastHitPlayer")
        if not lastHit then
            return false
        end
        local altSet = AF_Config.AltNameSet or {}
        return altSet[tostring(lastHit):lower()] == true
    end

    local function getAltRockZone(model)
        local rocksFolder = Ores.getRocksFolder()
        if not rocksFolder or not model then
            return nil
        end
        local current = model.Parent
        while current and current ~= game do
            if current.Parent == rocksFolder then
                return current.Name
            end
            if current == rocksFolder then
                return nil
            end
            current = current.Parent
        end
        return nil
    end

    local function rockIsInAllowedZone(model)
        if not AF_Config.ZoneWhitelistEnabled then
            return true
        end
        local zone = getAltRockZone(model)
        if not zone then
            return false
        end
        return AF_Config.WhitelistedZones[zone] == true
    end

    local function findAltWhitelistRock(hrp)
        if not hrp then
            return nil
        end
        local altSet = AF_Config.AltNameSet or {}
        if next(altSet) == nil then
            return nil
        end

        local rocksFolder = Ores.getRocksFolder()
        if not rocksFolder then
            return nil
        end

        local bestRock, bestDist = nil, math.huge
        for _, inst in ipairs(rocksFolder:GetDescendants()) do
            if inst:IsA("Model") then
                local parent = inst.Parent
                local isNested = (parent and parent ~= rocksFolder and parent:IsA("Model"))
                if not isNested
                    and Ores.rockHealth(inst)
                    and shouldHoldTargetForWhitelist(inst) then
                    if not rockIsInAllowedZone(inst) then
                        continue
                    end
                    if isTargetBlacklisted(inst) then
                        continue
                    end
                    local lastHit = inst:GetAttribute("LastHitPlayer")
                    if lastHit and altSet[tostring(lastHit):lower()] then
                        local pos = Ores.rockPosition(inst)
                        if pos then
                            local dist = (pos - hrp.Position).Magnitude
                            if dist < bestDist then
                                bestDist = dist
                                bestRock = inst
                            end
                        end
                    end
                end
            end
        end
        return bestRock
    end

    -- CHANGED: chooseNearestTarget now feeds data into dashboard (if enabled)
    local function chooseNearestTarget()
        local hrp = getLocalHRP()
        if not hrp then
            return nil
        end

        local def = ModeDefs[FarmState.mode]
        if not def or not def.scan then
            return nil
        end

        local helperAltActive = isHelperAltEnabled()
        local mainAltActive   = isMainAltEnabled()
        local questOverrideActive = AF_Config.QuestPriorityOverrideEnabled and questTargets

        if questOverrideActive and questTargets.refresh then
            questTargets.refresh()
        end

        local nameMap, uniqueNames = def.scan()
        FarmState.nameMap          = nameMap or {}

        local bestTarget, bestDist
        local bestPriority         = math.huge

        local wantDashboard        = dashboardEnabled()
        local allList              = wantDashboard and {} or nil
        local availList            = wantDashboard and {} or nil

        for name, models in pairs(nameMap or {}) do
            local priority = Priority.getTargetPriorityForMode(FarmState.mode, name)
            if questOverrideActive
                and questTargets.isQuestTarget
                and questTargets.isQuestTarget(name) then
                priority = priority - 1000
            end

            for _, model in ipairs(models) do
                if model and model.Parent and def.isAlive(model) then
                    if helperAltActive and shouldHoldTargetForWhitelist(model) then
                        blacklistTarget(model, 60)
                        continue
                    end
                    -- Count as "total" for dashboard
                    if allList then
                        table.insert(allList, model)
                    end

                    if isTargetBlacklisted(model) then
                        -- total, but not available
                        continue
                    end

                    if def.name == FARM_MODE_ORES and isRockLastHitByOther(model) then
                        local allowAltRock = mainAltActive
                            and rockLastHitWasAlt(model)
                            and shouldHoldTargetForWhitelist(model)
                        if not allowAltRock then
                            -- tagged by others; not available
                            continue
                        end
                    end

                    local pos = def.getPos(model)
                    if pos then
                        local skip = false

                        -- lava/hazard
                        if not skip then
                            local root = def.getRoot(model)
                            if root then
                                local offset = (AttachPanel.ComputeOffset and AttachPanel.ComputeOffset(
                                    root.CFrame,
                                    def.attachMode,
                                    def.attachHoriz,
                                    def.attachBaseY + AF_Config.ExtraYOffset
                                )) or Vector3.new(0, def.attachBaseY + AF_Config.ExtraYOffset, 0)

                                local attachPos = root.Position
                                    + (typeof(offset) == "Vector3" and offset or Vector3.new(0, 0, 0))

                                if isPointInHazard(attachPos) then
                                    skip = true
                                end
                            end
                        end

                        -- player avoidance
                        if not skip and AF_Config.AvoidPlayers then
                            local nearTarget, _ = isAnyPlayerNearPosition(pos, AF_Config.PlayerAvoidRadius)
                            if nearTarget then
                                skip = true
                            end
                        end

                        -- full-health-only (rocks)
                        if not skip and AF_Config.TargetFullHealth and def.name == FARM_MODE_ORES then
                            local h    = def.getHealth(model)
                            local maxH = model:GetAttribute("MaxHealth")
                            if h and maxH and h < maxH then
                                skip = true
                            end
                        end

                        if not skip then
                            -- "available" for dashboard
                            if availList then
                                table.insert(availList, model)
                            end

                            local dist = (pos - hrp.Position).Magnitude
                            if (priority < bestPriority)
                                or (priority == bestPriority and (not bestDist or dist < bestDist)) then
                                bestPriority = priority
                                bestDist     = dist
                                bestTarget   = model
                            end
                        end
                    end
                end
            end
        end

        -- Send to dashboard
        if wantDashboard and Dashboard then
            if def.name == FARM_MODE_ORES and Dashboard.setRockLists then
                Dashboard.setRockLists(allList or {}, availList or {})
            elseif def.name == FARM_MODE_ENEMIES and Dashboard.setMobLists then
                Dashboard.setMobLists(allList or {}, availList or {})
            end

            -- ADD THIS: Update current target highlight
            if bestTarget then
                local targetName = bestTarget:GetAttribute("OreName")
                    or bestTarget:GetAttribute("MobName")
                    or bestTarget:GetAttribute("EnemyName")
                    or bestTarget.Name
                Dashboard.setCurrentTarget(targetName)
            else
                Dashboard.setCurrentTarget(nil)
            end
        end

        return bestTarget
    end

    ----------------------------------------------------------------
    -- NOCLIP SYSTEM
    ----------------------------------------------------------------
    local function enableNoclip()
        if FarmState.noclipConn then
            return
        end

        FarmState.noclipConn = RunService.Stepped:Connect(function()
            local char = References.character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end
        end)
    end

    local function disableNoclip()
        if FarmState.noclipConn then
            FarmState.noclipConn:Disconnect()
            FarmState.noclipConn = nil
        end

        local char = References.character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CanCollide = true
            end
        end
    end

    ----------------------------------------------------------------
    -- MAIN FARM LOOP
    ----------------------------------------------------------------
    local lastPlayerUpdate = 0

    local function farmLoop()
        if References.humanoid then
            FarmState.LastLocalHealth = References.humanoid.Health
        end

        while FarmState.enabled do
            if FarmState.restocking then
                task.wait(0.5)
                continue
            end

            local loopSuccess, loopError = pcall(function()
                local hrp = getLocalHRP()
                local hum = References.humanoid

                -- Dashboard: update nearby players at ~2x per second max
                local nowLoop = os.clock()
                if dashboardEnabled() and Dashboard and Dashboard.setNearbyPlayers then
                    if (nowLoop - lastPlayerUpdate) > 0.5 then
                        lastPlayerUpdate = nowLoop
                        updateDashboardPlayers()
                    end
                end

                if not hrp or not hum then
                    stopMoving()
                    FarmState.currentTarget = nil
                    if dashboardEnabled() and Dashboard and Dashboard.setCurrentTarget then
                        Dashboard.setCurrentTarget(nil)
                    end
                    FarmState.attached      = false
                    FarmState.detourActive  = false
                    FarmState.tempMobTarget = nil
                    task.wait(0.3)
                    return
                end

                local humState        = hum:GetState()
                local humHealth       = hum.Health

                local helperAltActive = isHelperAltEnabled()
                local mainAltActive   = isMainAltEnabled()

                if humHealth <= 0 or humState == Enum.HumanoidStateType.Dead then
                    stopMoving()
                    FarmState.currentTarget = nil
                    if dashboardEnabled() and Dashboard and Dashboard.setCurrentTarget then
                        Dashboard.setCurrentTarget(nil)
                    end
                    FarmState.attached      = false
                    FarmState.detourActive  = false
                    FarmState.tempMobTarget = nil
                    task.wait(0.3)
                    return
                end

                -- DAMAGE DITCH LOGIC
                local ditchLimit = hum.MaxHealth * (AF_Config.DamageDitchThreshold / 100)
                local protectDamageDitchTarget = shouldHoldTargetForWhitelist(FarmState.currentTarget)
                    and not helperAltActive
                if AF_Config.DamageDitchEnabled
                    and FarmState.currentTarget
                    and humHealth < FarmState.LastLocalHealth
                    and humHealth < ditchLimit
                    and not protectDamageDitchTarget then
                    notify("Took damage! Ditching.", 2)
                    blacklistTarget(FarmState.currentTarget, 20)
                    stopMoving()
                    FarmState.currentTarget   = nil
                    FarmState.attached        = false
                    FarmState.detourActive    = false
                    FarmState.tempMobTarget   = nil
                    FarmState.LastLocalHealth = humHealth
                    task.wait(0.15)
                    return
                end
                FarmState.LastLocalHealth = humHealth

                -- NEARBY MOB CHECK (when farming ores)
                local activeTarget        = nil
                local activeDef           = nil
                local isDistracted        = false
                local holdNearbyMobs      = AF_Config.AttackNearbyMobs
                    and AF_Config.DamageDitchEnabled
                    and humHealth < ditchLimit

                if FarmState.mode == FARM_MODE_ORES and AF_Config.AttackNearbyMobs and not holdNearbyMobs then
                    if FarmState.tempMobTarget then
                        if FarmState.tempMobTarget.Parent and isMobAlive(FarmState.tempMobTarget) then
                            local root = getMobRoot(FarmState.tempMobTarget)
                            local dist = root and (root.Position - hrp.Position).Magnitude or math.huge
                            if dist <= AF_Config.NearbyMobRange + 10 then
                                activeTarget = FarmState.tempMobTarget
                                activeDef    = ModeDefs[FARM_MODE_ENEMIES]
                                isDistracted = true
                            else
                                FarmState.tempMobTarget = nil
                            end
                        else
                            FarmState.tempMobTarget = nil
                        end
                    end

                    if not FarmState.tempMobTarget and FarmState.attached then
                        local mob = findNearbyEnemy()
                        if mob then
                            local mobRoot = getMobRoot(mob)
                            local isSafe  = true

                            if mobRoot and isPointInHazard(mobRoot.Position) then
                                isSafe = false
                            end

                            if isSafe then
                                FarmState.tempMobTarget = mob
                                activeTarget            = mob
                                activeDef               = ModeDefs[FARM_MODE_ENEMIES]
                                isDistracted            = true
                                notify("Attacking nearby " .. mob.Name, 1)

                                -- ADD THIS: Update dashboard to show mob
                                if dashboardEnabled() and Dashboard and Dashboard.setCurrentTarget then
                                    Dashboard.setCurrentTarget(mob.Name)
                                end
                            end
                        end
                    end
                elseif holdNearbyMobs then
                    FarmState.tempMobTarget = nil
                end

                if not isDistracted then
                    activeTarget = FarmState.currentTarget
                    activeDef    = ModeDefs[FarmState.mode]
                end

                if not activeDef then
                    task.wait(0.3)
                    return
                end

                -- If an ore was tagged by someone else, ditch it immediately
                if activeTarget and activeDef.name == FARM_MODE_ORES and isRockLastHitByOther(activeTarget) then
                    local allowAltRock = mainAltActive
                        and rockLastHitWasAlt(activeTarget)
                        and shouldHoldTargetForWhitelist(activeTarget)
                    if not allowAltRock then
                        if shouldHoldTargetForWhitelist(activeTarget) and not helperAltActive then
                            task.wait(0.1)
                            return
                        end

                        blacklistTarget(activeTarget, 20)
                        stopMoving()
                        FarmState.attached     = false
                        FarmState.detourActive = false

                        if isDistracted then
                            FarmState.tempMobTarget = nil
                        else
                            FarmState.currentTarget = nil
                            if dashboardEnabled() and Dashboard and Dashboard.setCurrentTarget then
                                Dashboard.setCurrentTarget(nil)
                            end
                        end

                        task.wait(0.1)
                        return
                    end
                end

                if FarmState.mode == FARM_MODE_ORES and mainAltActive then
                    local altCandidate = findAltWhitelistRock(hrp)
                    if altCandidate
                        and (not activeTarget or (activeTarget ~= altCandidate and not shouldHoldTargetForWhitelist(activeTarget))) then
                        stopMoving()
                        FarmState.attached      = false
                        FarmState.detourActive  = false
                        FarmState.tempMobTarget = nil
                        FarmState.lastTargetRef = nil
                        FarmState.currentTarget = altCandidate
                        activeTarget            = altCandidate
                        activeDef               = ModeDefs[FARM_MODE_ORES]
                    end
                end

                local pos   = activeTarget and activeDef.getPos(activeTarget) or nil
                local alive = activeTarget and activeDef.isAlive(activeTarget)
                if helperAltActive and activeTarget and shouldHoldTargetForWhitelist(activeTarget) then
                    notify("Helper Alt: skipping whitelisted rock.", 2)
                    blacklistTarget(activeTarget, 60)
                    stopMoving()
                    FarmState.currentTarget = nil
                    if dashboardEnabled() and Dashboard and Dashboard.setCurrentTarget then
                        Dashboard.setCurrentTarget(nil)
                    end
                    FarmState.attached      = false
                    FarmState.detourActive  = false
                    FarmState.tempMobTarget = nil
                    task.wait(0.1)
                    return
                end

                local whitelistHoldTarget = mainAltActive and shouldHoldTargetForWhitelist(activeTarget)
                if (not activeTarget)
                    or (not activeTarget.Parent)
                    or (not pos)
                    or (not alive)
                    or (not isDistracted and isTargetBlacklisted(activeTarget)) then
                    if isDistracted then
                        FarmState.tempMobTarget = nil
                        FarmState.attached      = false
                        stopMoving()
                        -- fall through to ores
                    end

                    FarmState.currentTarget    = chooseNearestTarget()
                    FarmState.attached         = false
                    FarmState.detourActive     = false
                    FarmState.lastTargetRef    = FarmState.currentTarget
                    FarmState.lastTargetHealth = 0
                    FarmState.stuckStartTime   = os.clock()
                    FarmState.LastLocalHealth  = humHealth

                    activeTarget               = FarmState.currentTarget
                    activeDef                  = ModeDefs[FarmState.mode]

                    if activeTarget then
                        startMovingToTarget(activeTarget, activeDef)
                        pos = activeDef.getPos(activeTarget)
                    else
                        stopMoving()
                        if hrp and not hrp.Anchored then
                            hrp.Anchored = true
                        end

                        if AF_Config.AvoidPlayers then
                            moveAwayFromNearbyPlayers()
                        end

                        task.wait(0.15)
                        return
                    end
                end

                if hrp.Anchored then
                    hrp.Anchored = false
                end

                -- DYNAMIC PLAYER AVOIDANCE
                if AF_Config.AvoidPlayers and not FarmState.detourActive then
                    local innerRadius = AF_Config.PlayerAvoidRadius
                    local outerRadius = math.max(AF_Config.PlayerAvoidRadius * 1.2, AF_Config.PlayerAvoidRadius + 5)
                    local now         = os.clock()

                    local nearMe, _   = isAnyPlayerNearHRP(innerRadius)
                    if nearMe then
                        if (now - (FarmState.lastAvoidNoticeTime or 0)) > 2 then
                            notify("Player too close! Moving.", 2)
                            FarmState.lastAvoidNoticeTime = now
                        end

                        if FarmState.attached then
                            FarmState.attached = false
                            if AttachPanel.DestroyAttach then
                                AttachPanel.DestroyAttach()
                            end
                        end

                        moveAwayFromNearbyPlayers()
                        task.wait(0.2)
                        return
                    else
                        if FarmState.avoidingPlayer then
                            local stillNear, _ = isAnyPlayerNearHRP(outerRadius)
                            if not stillNear then
                                FarmState.avoidingPlayer    = false
                                FarmState.lastAvoidMoveTime = 0
                                if activeTarget then
                                    stopMoving()
                                    startMovingToTarget(activeTarget, activeDef)
                                end
                            else
                                task.wait(0.05)
                                return
                            end
                        end
                    end

                    if pos then
                        local distToTarget = (pos - hrp.Position).Magnitude
                        if distToTarget < 100 then
                            local nearTarget, _ = isAnyPlayerNearPosition(pos, innerRadius)
                            if nearTarget then
                                if whitelistHoldTarget then
                                    stopMoving()
                                    FarmState.attached       = false
                                    FarmState.avoidingPlayer = false
                                    task.wait(0.1)
                                    return
                                end

                                if (now - (FarmState.lastAvoidNoticeTime or 0)) > 2 then
                                    notify("Player at target! Ditching.", 2)
                                    FarmState.lastAvoidNoticeTime = now
                                end

                                if not isDistracted then
                                    blacklistTarget(activeTarget, 20)
                                else
                                    FarmState.tempMobTarget = nil
                                end

                                stopMoving()
                                FarmState.currentTarget  = nil
                                FarmState.attached       = false
                                FarmState.avoidingPlayer = false
                                task.wait(0.1)
                                return
                            end
                        end
                    end
                end

                -- ORE DROP WHITELIST CHECK
                if not isDistracted
                    and FarmState.mode == FARM_MODE_ORES
                    and AF_Config.OreWhitelistEnabled
                    and activeTarget then
                    if AF_Config.WhitelistAppliesTo[activeTarget.Name] then
                        local oreParts = {}
                        for _, c in ipairs(activeTarget:GetChildren()) do
                            if c.Name == "Ore" then
                                table.insert(oreParts, c)
                            end
                        end

                        if #oreParts > 0 then
                            local matchFound = false
                            for _, orePart in ipairs(oreParts) do
                                local oreType = orePart:GetAttribute("Ore")
                                if oreType and AF_Config.WhitelistedOres[oreType] then
                                    matchFound = true
                                    break
                                end
                            end

                            if not matchFound then
                                notify("No whitelisted ore! Ditching.", 2)
                                blacklistTarget(activeTarget, 20)
                                stopMoving()
                                FarmState.currentTarget = nil
                                if dashboardEnabled() and Dashboard and Dashboard.setCurrentTarget then
                                    Dashboard.setCurrentTarget(nil)
                                end
                                FarmState.attached = false
                                return
                            end
                        end
                    end
                end

                -- DETOUR LOGIC
                if activeTarget and not FarmState.attached and not isDistracted then
                    local hrpPos = hrp.Position
                    if (game.PlaceId == 129009554587176) and hrpPos.X < -180 then
                        if not FarmState.detourActive then
                            FarmState.detourActive = true
                            if not FarmState.detourNotified then
                                FarmState.detourNotified = true
                                notify("Detour engaged to avoid lagback chunks and players.", 3)
                            end
                            stopMoving()
                            startMovingToTarget(activeTarget, activeDef)
                        end
                    else
                        FarmState.detourActive   = false
                        FarmState.detourNotified = false
                    end
                else
                    FarmState.detourActive   = false
                    FarmState.detourNotified = false
                end

                if pos then
                    local dist = (pos - hrp.Position).Magnitude

                    if dist <= activeDef.hitDistance then
                        stopMoving()

                        local needAttach = not FarmState.attached or (activeTarget ~= FarmState.lastTargetRef)
                        if needAttach then
                            attachToTarget(activeTarget, activeDef)
                            FarmState.attached         = true
                            FarmState.lastTargetRef    = activeTarget
                            FarmState.stuckStartTime   = os.clock()
                            FarmState.lastTargetHealth = activeDef.getHealth(activeTarget) or 0
                            FarmState.lastHit          = 0
                        else
                            realignAttach(activeTarget, activeDef)

                            if not isDistracted and FarmState.lastTargetRef == activeTarget then
                                local currHealth = activeDef.getHealth(activeTarget) or 0
                                if currHealth < FarmState.lastTargetHealth then
                                    FarmState.lastTargetHealth = currHealth
                                    FarmState.stuckStartTime   = os.clock()
                                else
                                    if (os.clock() - FarmState.stuckStartTime) > 20 then
                                        if whitelistHoldTarget then
                                            FarmState.stuckStartTime = os.clock()
                                            task.wait(0.1)
                                            return
                                        end

                                        notify("Stuck (20s)! Ditching.", 2)
                                        blacklistTarget(activeTarget, 20)
                                        stopMoving()
                                        FarmState.currentTarget = nil
                                        if dashboardEnabled() and Dashboard and Dashboard.setCurrentTarget then
                                            Dashboard.setCurrentTarget(nil)
                                        end
                                        FarmState.attached = false
                                        return
                                    end
                                end
                            else
                                FarmState.lastTargetHealth = activeDef.getHealth(activeTarget) or 0
                                FarmState.stuckStartTime   = os.clock()
                            end
                        end

                        local now = os.clock()
                        if now - FarmState.lastHit >= activeDef.hitInterval then
                            swingTool(activeDef.toolRemoteArg)
                            FarmState.lastHit = now
                        end
                    else
                        if not FarmState.moveCleanup then
                            startMovingToTarget(activeTarget, activeDef)
                        end

                        FarmState.attached       = false
                        FarmState.stuckStartTime = os.clock()

                        if (os.clock() - FarmState.lastMoveTime) > 3 then
                            if (hrp.Position - FarmState.lastMovePos).Magnitude < 3 then
                                notify("Movement Stuck! Resetting.", 2)
                                stopMoving()
                                startMovingToTarget(activeTarget, activeDef)
                            end
                            FarmState.lastMovePos  = hrp.Position
                            FarmState.lastMoveTime = os.clock()
                        end
                    end
                end

                task.wait(0.05)
            end)

            if not loopSuccess then
                warn("[AutoFarm] Crash in farmLoop:", loopError)
                stopMoving()
                FarmState.attached = false
                task.wait(1)
            end
        end

        stopMoving()
        FarmState.currentTarget = nil
        if dashboardEnabled() and Dashboard and Dashboard.setCurrentTarget then
            Dashboard.setCurrentTarget(nil)
        end
        FarmState.tempMobTarget = nil
        FarmState.attached      = false

        local hrp               = getLocalHRP()
        if hrp then
            hrp.Anchored = false
        end

        disableNoclip()
    end

    ----------------------------------------------------------------
    -- START/STOP CONTROL
    ----------------------------------------------------------------
    local function startFarm()
        if Toggles.AF_ProximityTracker and Toggles.AF_ProximityTracker.Value then
            Tracker.setEnabled(true)
        end

        if FarmState.enabled then
            return
        end

        local def = ModeDefs[FarmState.mode]
        if not def then
            notify("Invalid farm mode.", 3)
            if Toggles.AF_Enabled then
                Toggles.AF_Enabled:SetValue(false)
            end
            return
        end

        if FarmState.mode == FARM_MODE_ORES and not Ores.getRocksFolder() then
            notify("No workspace.Rocks folder found.", 3)
            if Toggles.AF_Enabled then
                Toggles.AF_Enabled:SetValue(false)
            end
            return
        end

        if FarmState.mode == FARM_MODE_ENEMIES and not Services.Workspace:FindFirstChild("Living") then
            notify("No workspace.Living folder found.", 3)
            if Toggles.AF_Enabled then
                Toggles.AF_Enabled:SetValue(false)
            end
            return
        end

        local count = 0
        for _ in pairs(AF_Config.WhitelistedOres) do
            count += 1
        end
        if FarmState.mode == FARM_MODE_ORES and AF_Config.OreWhitelistEnabled and count == 0 then
            notify("Warning: Ore Whitelist ON but no ores selected!", 5)
        end

        saveAttachSettings()
        Movement.configureAttachForMode(FarmState.mode)
        enableNoclip()
        stopMoving()

        FarmState.currentTarget = nil
        if dashboardEnabled() and Dashboard and Dashboard.setCurrentTarget then
            Dashboard.setCurrentTarget(nil)
        end
        FarmState.tempMobTarget = nil
        FarmState.attached      = false
        FarmState.lastHit       = 0
        FarmState.detourActive  = false
        FarmState.restocking    = false
        FarmState.lastMoveTime  = os.clock()
        FarmState.enabled       = true
        FarmState.farmThread    = task.spawn(farmLoop)

        Potions.startPotionLoop()
    end

    local function stopFarm()
        FarmState.enabled = false
        stopMoving()
        FarmState.currentTarget = nil
        if dashboardEnabled() and Dashboard and Dashboard.setCurrentTarget then
            Dashboard.setCurrentTarget(nil)
        end
        FarmState.tempMobTarget = nil
        FarmState.attached      = false
        FarmState.detourActive  = false
        FarmState.restocking    = false

        local hrp               = getLocalHRP()
        if hrp then
            hrp.Anchored = false
        end

        disableNoclip()
        if AttachPanel.DestroyAttach then
            pcall(AttachPanel.DestroyAttach)
        end
        Movement.restoreAttachSettings()
    end

    ----------------------------------------------------------------
    -- UI SETUP
    ----------------------------------------------------------------
    local AutoTab             = Tabs["Auto"] or Tabs.Main
    local AutoPotionsGroupbox = AutoTab:AddRightGroupbox("Auto Potions", "flask-round")
    local WhitelistGroup      = AutoTab:AddLeftGroupbox("Whitelists", "list")
    local FarmGroup           = AutoTab:AddLeftGroupbox("Auto Farm", "pickaxe")
    local TrackingGroupbox    = AutoTab:AddRightGroupbox("Tracking", "compass")

    -- Auto Potions UI
    AutoPotionsGroupbox:AddDropdown("AutoPotions_List", {
        Text    = "Potions to Manage",
        Values  = {
            "Damage Potion I",
            "Speed Potion I",
            "Health Potion I",
            "Luck Potion I",
            "Miner Potion I",
        },
        Default = {},
        Multi   = true,
    })

    AutoPotionsGroupbox:AddSlider("AutoPotions_Interval", {
        Text     = "Auto Use Interval",
        Default  = 300,
        Min      = 60,
        Max      = 600,
        Rounding = 0,
        Suffix   = " sec",
    })

    AutoPotionsGroupbox:AddToggle("AutoPotions_Enable", {
        Text     = "Auto Use Potions",
        Default  = false,
        Callback = function(state)
            if state then
                Potions.startPotionLoop()
            end
        end,
    })

    AutoPotionsGroupbox:AddToggle("AutoPotions_AutoRestock", {
        Text    = "Auto Restock",
        Default = false,
    })

    AutoPotionsGroupbox:AddButton("Manual Restock", function()
        Potions.restockPotions(false)
    end)

    ----------------------------------------------------------------
    -- Whitelist & Mode UI
    ----------------------------------------------------------------
    local ModeDropdown, OreTypeDropdown, ZoneDropdown, AppliesToDropdown, QuestTargetsDropdown

    local function refreshAvailableTargets()
        local def = ModeDefs[FarmState.mode]
        if not def or not def.scan then
            if AppliesToDropdown then
                AppliesToDropdown:SetValues({})
            end
            return
        end

        local _, uniqueNames = def.scan()

        if FarmState.mode == FARM_MODE_ORES then
            local seen = {}
            for _, name in ipairs(uniqueNames) do
                seen[name] = true
            end
            for _, perm in ipairs(Priority.PermOreList) do
                if not seen[perm] then
                    table.insert(uniqueNames, perm)
                    seen[perm] = true
                end
            end
            table.sort(uniqueNames)
        end

        if AppliesToDropdown then
            AppliesToDropdown:SetValues(uniqueNames)
        end
    end

    local function refreshOreTypesDropdown()
        if OreTypeDropdown then
            OreTypeDropdown:SetValues(Ores.getGameOreTypes())
        end
    end

    local function refreshZoneDropdown()
        if ZoneDropdown then
            ZoneDropdown:SetValues(Ores.scanZones())
        end
    end

    local function refreshQuestTargetsDropdown()
        if QuestTargetsDropdown and questTargets and questTargets.getQuestNames then
            QuestTargetsDropdown:SetValues(questTargets.getQuestNames())
        end
    end

    ModeDropdown = WhitelistGroup:AddDropdown("AF_Mode", {
        Text     = "Farm Mode",
        Values   = { FARM_MODE_ORES, FARM_MODE_ENEMIES },
        Default  = FarmState.mode,
        Callback = function(value)
            if FarmState.mode == value then
                return
            end

            FarmState.mode = value
            refreshAvailableTargets()

            if FarmState.enabled then
                stopFarm()
                startFarm()
            end
        end,
    })

    WhitelistGroup:AddToggle("AF_TargetFullHealth", {
        Text     = "Fresh Targets Only",
        Default  = false,
        Callback = function(state)
            AF_Config.TargetFullHealth = state
        end,
    })

    WhitelistGroup:AddToggle("AF_ZoneWhitelist", {
        Text     = "Zone Whitelist",
        Default  = false,
        Tooltip  = "Only target rocks inside specific zones",
        Callback = function(state)
            AF_Config.ZoneWhitelistEnabled = state
        end,
    })

    ZoneDropdown = WhitelistGroup:AddDropdown("AF_Zones", {
        Text     = "Whitelisted Zones",
        Values   = {},
        Multi    = true,
        Callback = function(selectedTable)
            AF_Config.WhitelistedZones = {}
            for name, sel in pairs(selectedTable) do
                if sel then
                    AF_Config.WhitelistedZones[name] = true
                end
            end
        end,
    })

    WhitelistGroup:AddDivider()

    WhitelistGroup:AddToggle("AF_OreWhitelist", {
        Text     = "Ore Drop Whitelist",
        Default  = false,
        Tooltip  = "If enabled, only mine rocks that contain specific ore drops.",
        Callback = function(state)
            AF_Config.OreWhitelistEnabled = state
        end,
    })

    AppliesToDropdown = WhitelistGroup:AddDropdown("AF_AppliesTo", {
        Text     = "Whitelist Applies To",
        Values   = {},
        Multi    = true,
        Tooltip  = "Select which rocks should be checked for whitelisted drops.",
        Callback = function(selectedTable)
            AF_Config.WhitelistAppliesTo = {}
            for name, sel in pairs(selectedTable) do
                if sel then
                    AF_Config.WhitelistAppliesTo[name] = true
                end
            end
        end,
    })

    OreTypeDropdown = WhitelistGroup:AddDropdown("AF_OreTypes", {
        Text     = "Whitelisted Ores",
        Values   = {},
        Multi    = true,
        Tooltip  = "Select which ore drops are allowed.",
        Callback = function(selectedTable)
            AF_Config.WhitelistedOres = {}
            for name, sel in pairs(selectedTable) do
                if sel then
                    AF_Config.WhitelistedOres[name] = true
                end
            end
        end,
    })

    WhitelistGroup:AddDivider()

    WhitelistGroup:AddButton("Launch Priority Editor", function()
        loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/whodunitwww/noxhelpers/refs/heads/main/the-forge/editor.lua"
        ))()
    end)

    WhitelistGroup:AddButton("Reload Priorities", function()
        Priority.loadPriorityConfig()
        notify("Priorities reloaded from config!", 3)
    end)

    WhitelistGroup:AddButton("Refresh All Whitelists", function()
        refreshAvailableTargets()
        Avoidance.refreshHazards()
        refreshZoneDropdown()
        refreshOreTypesDropdown()
    end)

    ----------------------------------------------------------------
    -- Farm Options UI
    ----------------------------------------------------------------
    FarmGroup:AddSlider("AF_OffsetAdjust", {
        Text     = "Extra Offset",
        Min      = -5,
        Max      = 15,
        Default  = AF_Config.ExtraYOffset,
        Rounding = 1,
        Suffix   = " studs",
        Callback = function(value)
            AF_Config.ExtraYOffset = tonumber(value) or 0
            if FarmState.enabled and FarmState.currentTarget and FarmState.attached then
                Movement.realignAttach(FarmState.currentTarget)
            end
        end,
    })

    FarmGroup:AddSlider("AF_Speed", {
        Text     = "Flight Speed",
        Min      = 50,
        Max      = 120,
        Default  = AF_Config.FarmSpeed,
        Rounding = 0,
        Suffix   = " studs/s",
        Callback = function(value)
            local v = tonumber(value) or AF_Config.FarmSpeed
            AF_Config.FarmSpeed = math.clamp(v, 5, 120)
        end,
    })

    FarmGroup:AddDivider()

    FarmGroup:AddToggle("AF_AvoidLava", {
        Text     = "Avoid Lava",
        Default  = false,
        Callback = function(state)
            AF_Config.AvoidLava = state and true or false
            if AF_Config.AvoidLava then
                Avoidance.refreshHazards()
            end
        end,
    })

    FarmGroup:AddToggle("AF_AttackNearbyMobs", {
        Text     = "Attack Nearby Mobs",
        Default  = false,
        Callback = function(state)
            AF_Config.AttackNearbyMobs = state
        end,
    })

    FarmGroup:AddToggle("AF_AvoidPlayers", {
        Text     = "Avoid Players",
        Default  = false,
        Callback = function(state)
            AF_Config.AvoidPlayers = state
        end,
    })

    FarmGroup:AddToggle("AF_DamageDitch", {
        Text     = "Damage Ditch",
        Default  = false,
        Callback = function(state)
            AF_Config.DamageDitchEnabled = state
        end,
    })

    FarmGroup:AddSlider("AF_NearbyMobRange", {
        Text     = "Mob Detect Range",
        Tooltip  = "Range at which to auto-attack mobs when mining",
        Min      = 10,
        Max      = 100,
        Default  = AF_Config.NearbyMobRange,
        Rounding = 0,
        Suffix   = " studs",
        Callback = function(value)
            AF_Config.NearbyMobRange = tonumber(value) or 40
        end,
    })

    FarmGroup:AddSlider("AF_PlayerAvoidRadius", {
        Text     = "Player Avoid Range",
        Tooltip  = "Distance to keep away from other players",
        Min      = 10,
        Max      = 100,
        Default  = AF_Config.PlayerAvoidRadius,
        Rounding = 0,
        Suffix   = " studs",
        Callback = function(value)
            AF_Config.PlayerAvoidRadius = tonumber(value) or AF_Config.PlayerAvoidRadius
        end,
    })

    FarmGroup:AddSlider("AF_DitchThreshold", {
        Text     = "Ditch Health %",
        Tooltip  = "Health percentage threshold to ditch target when hit",
        Min      = 10,
        Max      = 100,
        Default  = AF_Config.DamageDitchThreshold,
        Rounding = 0,
        Suffix   = "%",
        Callback = function(value)
            AF_Config.DamageDitchThreshold = tonumber(value) or 100
        end,
    })

    FarmGroup:AddDivider()

    FarmGroup:AddDropdown("AF_MovementMode", {
        Text     = "Movement Method",
        Values   = { "Tween", "Teleport" },
        Default  = "Teleport",
        Callback = function(value)
            AF_Config.MovementMode = value
        end,
    })

    FarmGroup:AddToggle("AF_Enabled", {
        Text     = "Auto Farm",
        Default  = false,
        Callback = function(state)
            if state then
                startFarm()
            else
                stopFarm()
            end
        end,
    })

    ----------------------------------------------------------------
    -- ALT FARM UI
    ----------------------------------------------------------------
    local AltFarmGroup = AutoTab:AddRightGroupbox("Alt Farm", "bot")

    AltFarmGroup:AddLabel(
    "To use this you need to set one account as the main alt, and the rest as helper alts. Then in all accounts, select the ores you want the main alt to steal under whitelisted ores. Then whenever one of your alts finds a whitelisted or, it will ditch the rock, and your main will go in to mine it.",
        true)

    AltFarmGroup:AddToggle("AF_AltFarmEnabled", {
        Text     = "Enable Alt Farm",
        Default  = AF_Config.AltFarmEnabled,
        Callback = function(state)
            AF_Config.AltFarmEnabled = state
            if state then
                notifyAltRoster()
            end
        end,
    })

    AltFarmGroup:AddDropdown("AF_AltFarmMode", {
        Text     = "Alt Role",
        Values   = { ALT_FARM_MODE_MAIN, ALT_FARM_MODE_HELPER },
        Default  = AF_Config.AltFarmMode,
        Callback = function(value)
            AF_Config.AltFarmMode = value
        end,
    })

    AltFarmGroup:AddLabel("Type an alt username and press Enter to save.", true)
    AltFarmGroup:AddInput("AF_AltFarmAddAlt", {
        Text        = "Add Alt",
        Placeholder = "Alt username",
        Default     = "",
        Finished    = true,
        Callback    = function(value)
            local trimmed = tostring(value or ""):match("^%s*(.-)%s*$")
            if trimmed == "" then
                return
            end
            local added, reason = addAltName(trimmed)
            if added then
                notify("Added alt: " .. trimmed, 2)
                if Options and Options.AF_AltFarmAddAlt then
                    Options.AF_AltFarmAddAlt.Value = ""
                end
            else
                notify(reason or "Alt already tracked.", 2)
            end
        end,
    })

    ----------------------------------------------------------------
    -- QUEST PRIORITY OVERRIDE UI
    ----------------------------------------------------------------
    local QuestGroup = AutoTab:AddLeftGroupbox("Auto Quest", "scroll")

    QuestGroup:AddToggle("AF_QuestPriorityOverride", {
        Text     = "Quest Priority Override",
        Default  = AF_Config.QuestPriorityOverrideEnabled,
        Tooltip  = "Overrides targets with quest objectives.",
        Callback = function(state)
            AF_Config.QuestPriorityOverrideEnabled = state
        end,
    })

    QuestTargetsDropdown = QuestGroup:AddDropdown("AF_QuestTargetFilter", {
        Text     = "Quest Target Filter",
        Values   = {},
        Default  = {},
        Multi    = true,
        Tooltip  = "Only prioritize targets from selected quests.",
        Callback = function(selectedTable)
            AF_Config.QuestTargetFilter = {}
            for name, sel in pairs(selectedTable) do
                if sel then
                    AF_Config.QuestTargetFilter[name] = true
                end
            end
            if questTargets and questTargets.setQuestFilter then
                questTargets.setQuestFilter(AF_Config.QuestTargetFilter)
            end
        end,
    })

    QuestGroup:AddButton("Refresh Quest List", function()
        refreshQuestTargetsDropdown()
    end)

    QuestGroup:AddToggle("AF_QuestAutoComplete", {
        Text     = "Quest Autocomplete",
        Default  = AF_Config.QuestAutoCompleteEnabled,
        Tooltip  = "Automatically finishes some quests.",
        Callback = function(state)
            AF_Config.QuestAutoCompleteEnabled = state
            if state then
                startAutoQuestLoop()
            else
                stopAutoQuestLoop()
            end
        end,
    })

    if AF_Config.QuestAutoCompleteEnabled then
        startAutoQuestLoop()
    end

    refreshAvailableTargets()
    Avoidance.refreshHazards()
    refreshOreTypesDropdown()
    refreshZoneDropdown()
    refreshQuestTargetsDropdown()
    if questTargets and questTargets.setQuestFilter then
        questTargets.setQuestFilter(AF_Config.QuestTargetFilter)
    end

    TrackingGroupbox:AddToggle("AF_ProximityTracker", {
        Text     = "Progress Tracker",
        Default  = false,
        Callback = function(state)
            Tracker.setEnabled(state)
        end,
    })

    -- Autofarm Dashboard toggle (standalone HUD, like Tracker)
    TrackingGroupbox:AddToggle("AF_DashboardEnabled", {
        Text     = "Autofarm Dashboard",
        Default  = false,
        Callback = function(state)
            if Dashboard and Dashboard.setEnabled then
                Dashboard.setEnabled(state)
            end
        end,
    })

    TrackingGroupbox:AddButton({
        Text    = "Reset Progress Tracker",
        Tooltip = "Use if the tracker HUD misbehaves",
        Func    = function()
            Tracker.reset()
        end,
    })

    ----------------------------------------------------------------
    -- MODULE HANDLE RETURN
    ----------------------------------------------------------------
    local H = {}

    function H.Start()
        startFarm()
    end

    function H.Stop()
        stopFarm()
    end

    function H.Unload()
        FarmState.enabled = false
        stopMoving()
        FarmState.currentTarget = nil
        if dashboardEnabled() and Dashboard and Dashboard.setCurrentTarget then
            Dashboard.setCurrentTarget(nil)
        end
        FarmState.tempMobTarget = nil
        FarmState.attached      = false
        FarmState.detourActive  = false
        disableNoclip()

        if Tracker and Tracker.destroy then
            pcall(Tracker.destroy)
        end

        if Dashboard and Dashboard.destroy then
            pcall(Dashboard.destroy)
        elseif Dashboard and Dashboard.setEnabled then
            pcall(Dashboard.setEnabled, false)
        end

        if Toggles.AF_Enabled then
            pcall(function()
                Toggles.AF_Enabled:SetValue(false)
            end)
        end

        stopAutoQuestLoop()
        AF_Config.QuestAutoCompleteEnabled = false
        if Toggles.AF_QuestAutoComplete and Toggles.AF_QuestAutoComplete.SetValue then
            pcall(function()
                Toggles.AF_QuestAutoComplete:SetValue(false)
            end)
        end

        if AttachPanel.DestroyAttach then
            pcall(AttachPanel.DestroyAttach)
        end

        Movement.restoreAttachSettings()
    end

    return H
end
