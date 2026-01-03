-- AF_Priority.lua
-- Handles default priorities and config file loading for ores and enemies
return function(env)
    local HttpService             = env.HttpService
    local notify                  = env.notify

    local PRIORITY_CONFIG_VERSION = 2.0

local DefaultOrePriority = {
    ["Crimson Crystal"]       = 1,
    ["Violet Crystal"]        = 1,
    ["Cyan Crystal"]          = 1,
    ["Earth Crystal"]         = 1,
    ["Light Crystal"]         = 1,
    ["Floating Crystal"]      = 1,
    ["Large Red Crystal"]     = 1, -- Added
    ["Medium Red Crystal"]    = 1, -- Added
    ["Small Red Crystal"]     = 1, -- Added
    ["Crimson Ice"]           = 1,
    ["Large Ice Crystal"]     = 1,
    ["Medium Ice Crystal"]    = 1,
    ["Small Ice Crystal"]     = 1,
    ["Volcanic Rock"]         = 2,
    ["Lava Rock"]             = 2,
    ["Basalt Vein"]           = 3,
    ["Basalt Core"]           = 4,
    ["Basalt Rock"]           = 5,
    ["Basalt"]                = 5,
    ["Boulder"]               = 6,
    ["Rock"]                  = 6,
    ["Pebble"]                = 6,
    ["Icy Boulder"]           = 6,
    ["Icy Pebble"]            = 6,
    ["Icy Rock"]              = 6,
    ["Iceberg"]               = 6,
    ["Heart Of The Island"]   = 6,
    ["Lucky Block"]           = 6,
}
    
    local PermOreList             = {
        "Crimson Crystal",
        "Violet Crystal",
        "Cyan Crystal",
        "Earth Crystal",
        "Light Crystal",
        "Floating Crystal",
        "Large Red Crystal", -- Added
        "Medium Red Crystal", -- Added
        "Small Red Crystal", -- Added
        "Crimson Ice",
        "Large Ice Crystal",
        "Medium Ice Crystal",
        "Small Ice Crystal",
        "Volcanic Rock",
        "Lava Rock",
        "Basalt Vein",
        "Basalt Core",
    }

    local DefaultEnemyPriority    = {
        ["Demonic Queen Spider"]    = 1,
        ["Blazing Slime"]           = 1,
        ["Demonic Spider"]          = 2,
        ["Crystal Golem"]           = 2,
        ["Blight Pyromancer"]       = 2,
        ["Elite Deathaxe Skeleton"] = 2,
        ["Reaper"]                  = 3,
        ["Elite Orc"]               = 3,
        ["Yeti"]                    = 3,
        ["Diamond Spider"]          = 3,
        ["Prismarine Spider"]       = 3,
        ["Crystal Spider"]          = 3,
        ["Elite Rogue Skeleton"]    = 4,
        ["Golem"]                   = 4,
        ["Mini Demonic Spider"]     = 4,
        ["Deathaxe Skeleton"]       = 5,
        ["Common Orc"]              = 5,
        ["Axe Skeleton"]            = 6,
        ["Skeleton Rogue"]          = 7,
        ["Bomber"]                  = 8,
        ["Slime"]                   = 9,
        ["MinerZombie"]             = 9,
        ["EliteZombie"]             = 9,
        ["Zombie"]                  = 9,
        ["Zombie3"]                 = 9,
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
