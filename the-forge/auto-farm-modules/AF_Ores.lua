-- AF_Ores.lua
-- Functions for scanning and interacting with ore objects
return function(env)
    local Services    = env.Services
    local References  = env.References
    local AttachPanel = env.AttachPanel
    local Players     = env.Players
    local AF_Config   = env.AF_Config

    local function getRocksFolder()
        return Services.Workspace:FindFirstChild("Rocks")
    end

    local function rockHealth(model)
        if not model or not model.Parent then return nil end
        local ok, value = pcall(function() return model:GetAttribute("Health") end)
        if not ok or value == nil then return nil end
        return tonumber(value)
    end

    local function isRockAlive(model)
        local h = rockHealth(model)
        return h and h > 0
    end

    local function isRockLastHitByOther(model)
        if not model or not model.Parent then return false end
        local ok, value = pcall(function() return model:GetAttribute("LastHitPlayer") end)
        if not ok or value == nil then
            return false  -- no attribute => free rock
        end
        local plr = References.player or Players.LocalPlayer
        if not plr then return false end
        local v = tostring(value)
        if v == plr.Name or v == plr.DisplayName or v == tostring(plr.UserId) then
            return false  -- last hit was us
        end
        return true
    end

    local function rockRoot(model)
        if not model or not model.Parent then return nil end
        if model:IsA("BasePart") then
            return model
        end
        local part = AttachPanel.HrpOf and AttachPanel.HrpOf(model) or nil
        if part then return part end
        for _, inst in ipairs(model:GetDescendants()) do
            if inst:IsA("BasePart") then
                return inst
            end
        end
        return nil
    end

    local function rockPosition(model)
        local root = rockRoot(model)
        return root and root.Position or nil
    end

    local function getZoneFromDescendant(model)
        local rocksFolder = getRocksFolder()
        if not rocksFolder then return nil end
        local current = model.Parent
        while current and current ~= game do
            if current.Parent == rocksFolder then 
                return current.Name 
            end
            if current == rocksFolder then return nil end
            current = current.Parent
        end
        return nil
    end

    local function scanRocks()
        local rocksFolder = getRocksFolder()
        local nameMap = {}
        local uniqueNames = {}
        if not rocksFolder then return nameMap, uniqueNames end

        for _, inst in ipairs(rocksFolder:GetDescendants()) do
            if inst:IsA("Model") then
                local parent = inst.Parent
                local isNested = (parent and parent ~= rocksFolder and parent:IsA("Model"))
                if not isNested then
                    local passedZone = true
                    if AF_Config.ZoneWhitelistEnabled then
                        local zoneName = getZoneFromDescendant(inst)
                        if not zoneName or not AF_Config.WhitelistedZones[zoneName] then
                            passedZone = false
                        end
                    end
                    if passedZone and rockHealth(inst) and not isRockLastHitByOther(inst) then
                        local name = inst.Name
                        if not nameMap[name] then
                            nameMap[name] = {}
                            uniqueNames[#uniqueNames + 1] = name
                        end
                        table.insert(nameMap[name], inst)
                    end
                end
            end
        end
        table.sort(uniqueNames)
        return nameMap, uniqueNames
    end

    local function getGameOreTypes()
        local assets = Services.ReplicatedStorage:FindFirstChild("Assets")
        local oresFolder = assets and assets:FindFirstChild("Ores")
        local list = {}
        if oresFolder then
            for _, v in ipairs(oresFolder:GetChildren()) do
                table.insert(list, v.Name)
            end
        end
        table.sort(list)
        return list
    end

    local function scanZones()
        local rocksFolder = getRocksFolder()
        local zones = {}
        if rocksFolder then
            for _, child in ipairs(rocksFolder:GetChildren()) do
                if child:IsA("Folder") then
                    table.insert(zones, child.Name)
                end
            end
        end
        table.sort(zones)
        return zones
    end

    return {
        getRocksFolder = getRocksFolder,
        rockHealth = rockHealth,
        isRockAlive = isRockAlive,
        isRockLastHitByOther = isRockLastHitByOther,
        rockRoot = rockRoot,
        rockPosition = rockPosition,
        scanRocks = scanRocks,
        getGameOreTypes = getGameOreTypes,
        scanZones = scanZones
    }
end
