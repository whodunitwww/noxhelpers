-- AF_QuestTargets.lua
-- Tracks player quest objectives and exposes the names mentioned so they can be prioritized.
return function(env)
    local Services     = env.Services or {}
    local HttpService  = Services.HttpService or game:GetService("HttpService")
    local Players      = Services.Players or game:GetService("Players")
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

    local function refreshTargets()
        local now = os.clock()
        if (now - lastRefresh) < RefreshDelay then
            return currentTargets
        end
        lastRefresh = now
        local targetList = buildTargetList()
        local questFrames = collectQuestFrames()
        local found = {}
        for _, quest in ipairs(questFrames) do
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
    }
end
