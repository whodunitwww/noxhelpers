-- AF_Priority.lua
-- Handles default priorities and config file loading for ores and enemies
return function(env)
    local HttpService = env.HttpService
    local notify      = env.notify

    local PRIORITY_CONFIG_VERSION = 1.1

    local DefaultOrePriority = {
        ["Crimson Crystal"] = 1,
        ["Violet Crystal"]  = 1,
        ["Cyan Crystal"]    = 1,
        ["Earth Crystal"]   = 1,
        ["Light Crystal"]   = 1,
        ["Volcanic Rock"]   = 2,
        ["Basalt Vein"]     = 3,
        ["Basalt Core"]     = 4,
        ["Basalt Rock"]     = 5,
        ["Boulder"]         = 6,
        ["Rock"]            = 6,
        ["Pebble"]          = 6,
        ["Lucky Block"]     = 6,
    }
    local PermOreList = {
        "Crimson Crystal",
        "Cyan Crystal",
        "Earth Crystal",
        "Light Crystal",
        "Volcanic Rock",
        "Basalt Vein",
        "Basalt Core",
    }
    local DefaultEnemyPriority = {
        ["Blazing Slime"]           = 1,
        ["Blight Pyromancer"]       = 2,
        ["Elite Deathaxe Skeleton"] = 2,
        ["Reaper"]                  = 3,
        ["Elite Rogue Skeleton"]    = 4,
        ["Deathaxe Skeleton"]       = 5,
        ["Axe Skeleton"]            = 6,
        ["Skeleton Rogue"]          = 7,
        ["Bomber"]                  = 8,
        ["Slime"]                   = 9,
        ["MinerZombie"]             = 9,
        ["EliteZombie"]             = 9,
        ["Zombie"]                  = 9,
        ["Delver Zombie"]           = 9,
        ["Brute Zombie"]            = 9,
    }

    local OrePriority   = {}
    local EnemyPriority = {}
    for k, v in pairs(DefaultOrePriority) do OrePriority[k] = v end
    for k, v in pairs(DefaultEnemyPriority) do EnemyPriority[k] = v end

    local PriorityConfigFile = "Cerberus/The Forge/PriorityConfig.json"

    local function writeDefaultPriorityConfig()
        local payload = {
            Version = PRIORITY_CONFIG_VERSION,
            Ores    = DefaultOrePriority,
            Enemies = DefaultEnemyPriority
        }
        pcall(function()
            writefile(PriorityConfigFile, HttpService:JSONEncode(payload))
        end)
    end

    local function applyDefaultPriorities()
        OrePriority   = {}
        EnemyPriority = {}
        for k, v in pairs(DefaultOrePriority) do OrePriority[k] = v end
        for k, v in pairs(DefaultEnemyPriority) do EnemyPriority[k] = v end
    end

    local function loadPriorityConfig()
        if not isfolder("Cerberus") then makefolder("Cerberus") end
        if not isfolder("Cerberus/The Forge") then makefolder("Cerberus/The Forge") end
        if not (isfile and readfile and writefile) then
            return
        end

        if isfile(PriorityConfigFile) then
            local success, result = pcall(function()
                return HttpService:JSONDecode(readfile(PriorityConfigFile))
            end)
            if success and type(result) == "table" then
                local fileVersion = tonumber(result.Version)
                if not fileVersion then
                    if (type(result.Ores) == "table") or (type(result.Enemies) == "table") then
                        warn("[Config] Legacy format detected. Auto-patching to v" .. PRIORITY_CONFIG_VERSION)
                        result.Version = PRIORITY_CONFIG_VERSION
                        pcall(function()
                            writefile(PriorityConfigFile, HttpService:JSONEncode(result))
                        end)
                        fileVersion = PRIORITY_CONFIG_VERSION
                    else
                        fileVersion = 0
                    end
                end
                if fileVersion < PRIORITY_CONFIG_VERSION then
                    applyDefaultPriorities()
                    writeDefaultPriorityConfig()
                    notify("Priority config outdated (v" .. fileVersion 
                           .. " vs v" .. PRIORITY_CONFIG_VERSION .. "). Resetting.", 5)
                    return
                end
                if type(result.Ores) == "table" then
                    OrePriority = {}
                    for k, v in pairs(result.Ores) do
                        OrePriority[k] = tonumber(v) or 999
                    end
                else
                    for k, v in pairs(DefaultOrePriority) do OrePriority[k] = v end
                end
                if type(result.Enemies) == "table" then
                    EnemyPriority = {}
                    for k, v in pairs(result.Enemies) do
                        EnemyPriority[k] = tonumber(v) or 999
                    end
                else
                    for k, v in pairs(DefaultEnemyPriority) do EnemyPriority[k] = v end
                end
            else
                applyDefaultPriorities()
                writeDefaultPriorityConfig()
                notify("Config corrupted. Reset to defaults.", 5)
            end
        else
            applyDefaultPriorities()
            writeDefaultPriorityConfig()
        end
    end

    loadPriorityConfig()

    local function getTargetPriorityForMode(modeName, baseName)
        if modeName == "Ores" then
            return OrePriority[baseName] or DefaultOrePriority[baseName] or 999
        elseif modeName == "Enemies" then
            return EnemyPriority[baseName] or DefaultEnemyPriority[baseName] or 999
        end
        return 999
    end

    return {
        PermOreList = PermOreList,
        loadPriorityConfig = loadPriorityConfig,
        getTargetPriorityForMode = getTargetPriorityForMode
    }
end
