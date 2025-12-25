-- AF_QuestTargets.lua
-- Tracks player quest objectives and exposes the names mentioned so they can be prioritized.
return function(env)
    local Services     = env.Services or {}
    local HttpService  = Services.HttpService or game:GetService("HttpService")
    local Players      = Services.Players or game:GetService("Players")
    local ReplicatedStorage = Services.ReplicatedStorage or game:GetService("ReplicatedStorage")
    local RefreshDelay = env.RefreshDelay or 5

    local PRIORITY_CONFIG_FILE = "Cerberus/The Forge/PriorityConfig.json"

    local DefaultOrePriority = {
        ["Crimson Crystal"] = true,
        ["Violet Crystal"]  = true,
        ["Cyan Crystal"]    = true,
        ["Earth Crystal"]   = true,
        ["Light Crystal"]   = true,
        ["Volcanic Rock"]   = true,
        ["Basalt Vein"]     = true,
        ["Basalt Core"]     = true,
        ["Basalt Rock"]     = true,
        ["Boulder"]         = true,
        ["Rock"]            = true,
        ["Pebble"]          = true,
        ["Lucky Block"]     = true,
    }

    local DefaultEnemyPriority = {
        ["Blazing Slime"]           = true,
        ["Blight Pyromancer"]       = true,
        ["Elite Deathaxe Skeleton"] = true,
        ["Reaper"]                  = true,
        ["Elite Rogue Skeleton"]    = true,
        ["Deathaxe Skeleton"]       = true,
        ["Axe Skeleton"]            = true,
        ["Skeleton Rogue"]          = true,
        ["Bomber"]                  = true,
        ["Slime"]                   = true,
        ["MinerZombie"]             = true,
        ["EliteZombie"]             = true,
        ["Zombie"]                  = true,
        ["Delver Zombie"]           = true,
        ["Brute Zombie"]            = true,
    }

    local function getLocalPlayer()
        return Players.LocalPlayer
    end

    local function normalizeQuestName(name)
        if not name then
            return ""
        end
        local cleaned = tostring(name)
        cleaned = cleaned:gsub("%d+", "")
        cleaned = cleaned:gsub("%s+", " ")
        cleaned = cleaned:gsub("^%s+", ""):gsub("%s+$", "")
        return cleaned
    end

    local function hasNumericAncestor(inst)
        local current = inst
        while current do
            if tonumber(current.Name) then
                return true
            end
            current = current.Parent
        end
        return false
    end

    local function collectQuestFrames()
        local player = getLocalPlayer()
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
            if child:IsA("Frame") and child.Name:match("List") then
                table.insert(questFrames, child)
            end
        end
        return questFrames
    end

    local function collectMenuQuestIds()
        local player = getLocalPlayer()
        if not player then
            return {}
        end
        local gui = player:FindFirstChild("PlayerGui")
        if not gui then
            return {}
        end
        local menu = gui:FindFirstChild("Menu")
        local frameA = menu and menu:FindFirstChild("Frame")
        local frameB = frameA and frameA:FindFirstChild("Frame")
        local menus = frameB and frameB:FindFirstChild("Menus")
        local questsMenu = menus and menus:FindFirstChild("Quests")
        local folder = questsMenu and questsMenu:FindFirstChild("Folder")
        local infoSection = folder and folder:FindFirstChild("InfoSection")
        local scrolling = infoSection and infoSection:FindFirstChild("ScrollingFrame")
        if not scrolling then
            return {}
        end
        local ids = {}
        local seen = {}
        for _, child in ipairs(scrolling:GetChildren()) do
            if child:IsA("Frame") then
                local questId = child.Name:match("^(.+)Title$")
                if questId and questId ~= "" and not seen[questId] then
                    seen[questId] = true
                    table.insert(ids, questId)
                end
            end
        end
        return ids
    end

    local function resolveObjectiveText(objFrame)
        if not objFrame then
            return "", nil
        end
        local main = objFrame:FindFirstChild("Main")
        if not main then
            return "", nil
        end
        local textLabel = main:FindFirstChild("TextLabel")
        if not textLabel then
            return "", nil
        end
        return tostring(textLabel.Text or ""), textLabel.TextColor3
    end

    local function scoreQuestLabel(label, text)
        local score = 0
        local lname = string.lower(label.Name or "")
        local parent = label.Parent and string.lower(label.Parent.Name or "") or ""
        local len = #text

        if lname:find("questtitle", 1, true)
            or lname:find("questname", 1, true)
            or lname:find("title", 1, true)
            or lname == "name" then
            score = score + 6
        end

        if parent:find("title", 1, true) or parent:find("header", 1, true) then
            score = score + 2
        end

        if lname:find("desc", 1, true)
            or lname:find("objective", 1, true)
            or lname:find("task", 1, true)
            or lname:find("detail", 1, true)
            or lname:find("progress", 1, true) then
            score = score - 4
        end

        if parent:find("desc", 1, true)
            or parent:find("objective", 1, true)
            or parent:find("task", 1, true)
            or parent:find("detail", 1, true)
            or parent:find("progress", 1, true) then
            score = score - 2
        end

        if text:find("\n", 1, true) then
            score = score - 2
        end

        if len <= 32 then
            score = score + 2
        elseif len <= 64 then
            score = score + 1
        else
            score = score - 2
        end

        if text:match("%d+/%d+") then
            score = score - 2
        end

        return score
    end

    local function safeRequire(moduleScript)
        if not moduleScript then
            return nil
        end
        local ok, result = pcall(require, moduleScript)
        if ok then
            return result
        end
        return nil
    end

    local questDataLoaded = false
    local questDataCache = nil
    local replicaLoaded = false
    local replicaCache = nil

    local function getQuestData()
        if questDataLoaded then
            return questDataCache
        end
        questDataLoaded = true
        if not ReplicatedStorage then
            return nil
        end
        local shared = ReplicatedStorage:FindFirstChild("Shared")
        local dataFolder = shared and shared:FindFirstChild("Data")
        local questsModule = dataFolder and dataFolder:FindFirstChild("Quests")
        questDataCache = safeRequire(questsModule)
        return questDataCache
    end

    local function getReplica()
        if replicaLoaded then
            return replicaCache
        end
        replicaLoaded = true
        if not ReplicatedStorage then
            return nil
        end
        local shared = ReplicatedStorage:FindFirstChild("Shared")
        local packages = shared and shared:FindFirstChild("Packages")
        local knitModule = packages and packages:FindFirstChild("Knit")
        local Knit = safeRequire(knitModule)
        if not Knit or type(Knit.GetController) ~= "function" then
            return nil
        end
        local ok, controller = pcall(Knit.GetController, Knit, "PlayerController")
        if ok and controller and controller.Replica then
            replicaCache = controller.Replica
        end
        return replicaCache
    end

    local function findQuestIdBySlot(slotIndex)
        local replica = getReplica()
        if not replica or type(replica.Data) ~= "table" or type(replica.Data.Quests) ~= "table" then
            return nil
        end
        for questId, questState in pairs(replica.Data.Quests) do
            if type(questState) == "table" then
                local slot = questState.Slot
                    or questState.SlotIndex
                    or questState.Index
                    or questState.UIIndex
                    or questState.SlotNumber
                    or questState.QuestSlot
                if tonumber(slot) == tonumber(slotIndex) then
                    return questId
                end
            end
        end
        return nil
    end

    local function getActiveQuestIds()
        local replica = getReplica()
        if replica
            and type(replica.Data) == "table"
            and type(replica.Data.Quests) == "table" then
            local ids = {}
            for questId in pairs(replica.Data.Quests) do
                table.insert(ids, questId)
            end
            return ids
        end
        local menuIds = collectMenuQuestIds()
        if #menuIds > 0 then
            return menuIds
        end
        return nil
    end

    local function extractQuestIdFromFrame(questFrame)
        if not questFrame then
            return nil
        end
        local attrId = questFrame:GetAttribute("QuestId")
            or questFrame:GetAttribute("QuestID")
            or questFrame:GetAttribute("QuestName")
            or questFrame:GetAttribute("Quest")
        if type(attrId) == "string" and attrId ~= "" then
            return attrId
        end
        for _, child in ipairs(questFrame:GetChildren()) do
            if child:IsA("StringValue") then
                local lname = string.lower(child.Name or "")
                if lname == "questid"
                    or lname == "quest_id"
                    or lname == "quest"
                    or lname == "id" then
                    if child.Value ~= "" then
                        return child.Value
                    end
                end
            end
        end
        local slotIndex = questFrame.Name:match("Quest(%d+)List$")
        if slotIndex then
            return findQuestIdBySlot(tonumber(slotIndex))
        end
        return nil
    end

    local function getQuestNameFromData(questId)
        if not questId then
            return ""
        end
        local questData = getQuestData()
        if questData and questData[questId] and questData[questId].Name then
            return tostring(questData[questId].Name)
        end
        return ""
    end

    local function isObjectiveDoneFromReplica(replica, questId, objectiveIndex)
        if not replica or type(replica.Data) ~= "table" then
            return false
        end
        local quests = replica.Data.Quests
        if type(quests) ~= "table" then
            return false
        end
        local questState = quests[questId]
        if type(questState) ~= "table" then
            return false
        end
        local progress = questState.Progress
        if type(progress) ~= "table" then
            return false
        end
        local entry = progress[objectiveIndex]
        if type(entry) ~= "table" then
            return false
        end
        local current = tonumber(entry.currentProgress or entry.CurrentProgress or entry.Progress or 0) or 0
        local required = tonumber(entry.requiredAmount or entry.RequiredAmount or entry.Required)
        if current <= 0 then
            return false
        end
        if required == nil then
            return true
        end
        return current >= required
    end

    local function getObjectiveTarget(obj)
        if type(obj) ~= "table" then
            return nil, nil
        end
        local objType = obj.Type or obj.type
        local target = obj.Target or obj.target
        if type(target) ~= "string" or target == "" then
            return nil, nil
        end
        return objType, target
    end

    local function getQuestSlot(questId)
        if not questId then
            return nil
        end
        local replica = getReplica()
        if not replica or type(replica.Data) ~= "table" or type(replica.Data.Quests) ~= "table" then
            return nil
        end
        local questState = replica.Data.Quests[questId]
        if type(questState) ~= "table" then
            return nil
        end
        return questState.Slot
            or questState.SlotIndex
            or questState.Index
            or questState.UIIndex
            or questState.SlotNumber
            or questState.QuestSlot
    end

    local function isQuestCompleted(questId)
        if not questId then
            return false
        end
        local questData = getQuestData()
        if not questData or type(questData[questId]) ~= "table" then
            return false
        end
        local objectives = questData[questId].Objectives
        if type(objectives) ~= "table" then
            return false
        end
        local replica = getReplica()
        local hasObjective = false
        for index in ipairs(objectives) do
            hasObjective = true
            if not isObjectiveDoneFromReplica(replica, questId, index) then
                return false
            end
        end
        return hasObjective
    end

    local function extractQuestName(questFrame)
        if not questFrame then
            return ""
        end

        local questId = extractQuestIdFromFrame(questFrame)
        if questId then
            local dataName = getQuestNameFromData(questId)
            if dataName ~= "" then
                return dataName
            end
        end

        local bestText = ""
        local bestScore = -math.huge

        for _, label in ipairs(questFrame:GetDescendants()) do
            if label:IsA("TextLabel") and not hasNumericAncestor(label) then
                local text = tostring(label.Text or "")
                if text ~= "" then
                    local score = scoreQuestLabel(label, text)
                    if score > bestScore then
                        bestScore = score
                        bestText = text
                    end
                end
            end
        end

        return bestText
    end

    local function colorMatches(a, b)
        if not a or not b then
            return false
        end
        local ra, ga, ba = math.floor(a.R * 255 + 0.5), math.floor(a.G * 255 + 0.5), math.floor(a.B * 255 + 0.5)
        local rb, gb, bb = math.floor(b.R * 255 + 0.5), math.floor(b.G * 255 + 0.5), math.floor(b.B * 255 + 0.5)
        return ra == rb and ga == gb and ba == bb
    end

    local localCompletedColor = Color3.fromRGB(160, 160, 160)

    local function isObjectiveCompleted(color)
        return colorMatches(color, localCompletedColor)
    end

    local function tryLoadPriorityConfig()
        if not (isfile and readfile) then
            return nil
        end
        if not isfile(PRIORITY_CONFIG_FILE) then
            return nil
        end
        local ok, contents = pcall(readfile, PRIORITY_CONFIG_FILE)
        if not ok or type(contents) ~= "string" then
            return nil
        end
        local parsed = nil
        local success, decoded = pcall(function()
            return HttpService:JSONDecode(contents)
        end)
        if success and type(decoded) == "table" then
            parsed = decoded
        end
        return parsed
    end

    local function buildTargetList()
        local list = {}
        local lookup = {}
        local function add(name)
            if name and name ~= "" and not lookup[name] then
                lookup[name] = true
                table.insert(list, name)
            end
        end
        for name in pairs(DefaultOrePriority) do
            add(name)
        end
        for name in pairs(DefaultEnemyPriority) do
            add(name)
        end
        local config = tryLoadPriorityConfig()
        if config then
            if type(config.Ores) == "table" then
                for name in pairs(config.Ores) do
                    add(name)
                end
            end
            if type(config.Enemies) == "table" then
                for name in pairs(config.Enemies) do
                    add(name)
                end
            end
        end
        table.sort(list, function(a, b)
            return #a > #b
        end)
        return list
    end

    local function findTargetsInText(text, targetList)
        if not text or #text == 0 or not targetList then
            return {}
        end
        local lower = string.lower(text)
        local matches = {}
        for _, target in ipairs(targetList) do
            local targetLower = string.lower(target)
            if targetLower ~= "" and lower:find(targetLower, 1, true) then
                table.insert(matches, target)
            end
        end
        return matches
    end

    local lastRefresh = 0
    local currentTargets = {}
    local selectedQuestNames = {}

    local function setQuestFilter(selected)
        selectedQuestNames = {}
        if type(selected) == "table" then
            for name, state in pairs(selected) do
                if state then
                    selectedQuestNames[name] = true
                end
            end
        end
        lastRefresh = 0
    end

    local function isQuestAllowed(normalizedName)
        if next(selectedQuestNames) == nil then
            return true
        end
        if not normalizedName or normalizedName == "" then
            return false
        end
        return selectedQuestNames[normalizedName] == true
    end

    local function getQuestNames()
        local questData = getQuestData()
        local questIds = getActiveQuestIds()
        if questData and questIds then
            local names = {}
            local seen = {}
            for _, questId in ipairs(questIds) do
                local dataName = getQuestNameFromData(questId)
                local normalized = normalizeQuestName(dataName)
                if normalized ~= "" and not seen[normalized] then
                    seen[normalized] = true
                    table.insert(names, normalized)
                end
            end
            table.sort(names)
            return names
        end

        local questFrames = collectQuestFrames()
        local names = {}
        local seen = {}
        for _, quest in ipairs(questFrames) do
            local rawName = extractQuestName(quest)
            local normalized = normalizeQuestName(rawName)
            if normalized ~= "" and not seen[normalized] then
                seen[normalized] = true
                table.insert(names, normalized)
            end
        end
        table.sort(names)
        return names
    end

    local function refreshTargets()
        local now = os.clock()
        if (now - lastRefresh) < RefreshDelay then
            return currentTargets
        end
        lastRefresh = now
        local targetList = buildTargetList()
        local targetLookup = {}
        for _, name in ipairs(targetList) do
            targetLookup[name] = true
        end

        local found = {}
        local questData = getQuestData()
        local questIds = getActiveQuestIds()
        if questData and questIds then
            local replica = getReplica()
            for _, questId in ipairs(questIds) do
                local questInfo = questData[questId]
                if type(questInfo) == "table" then
                    local questName = normalizeQuestName(questInfo.Name or questId)
                    if not isQuestAllowed(questName) then
                        continue
                    end
                    local objectives = questInfo.Objectives
                    if type(objectives) == "table" then
                        for index, obj in ipairs(objectives) do
                            if not isObjectiveDoneFromReplica(replica, questId, index) then
                                local objType, target = getObjectiveTarget(obj)
                                if (objType == "Kill" or objType == "Mine" or objType == "Collect")
                                    and target
                                    and targetLookup[target] then
                                    found[target] = true
                                end
                            end
                        end
                    end
                end
            end
            currentTargets = found
            return currentTargets
        end

        local questFrames = collectQuestFrames()
        for _, quest in ipairs(questFrames) do
            local questName = normalizeQuestName(extractQuestName(quest))
            if not isQuestAllowed(questName) then
                continue
            end
            for _, child in ipairs(quest:GetChildren()) do
                if tonumber(child.Name) then
                    local text, color = resolveObjectiveText(child)
                    if isObjectiveCompleted(color) then
                        continue
                    end
                    local matches = findTargetsInText(text, targetList)
                    for _, match in ipairs(matches) do
                        found[match] = true
                    end
                end
            end
        end
        currentTargets = found
        return currentTargets
    end

    local function isQuestTarget(name)
        if not name then
            return false
        end
        if next(currentTargets) == nil then
            refreshTargets()
        end
        return currentTargets[name] == true
    end

    return {
        refresh = refreshTargets,
        isQuestTarget = isQuestTarget,
        setQuestFilter = setQuestFilter,
        getQuestNames = getQuestNames,
        getQuestData = getQuestData,
        getActiveQuestIds = getActiveQuestIds,
        getQuestSlot = getQuestSlot,
        isQuestCompleted = isQuestCompleted,
    }
end
