-- AF_Mobs.lua
-- Functions for scanning and interacting with enemy (mob) objects
return function(env)
    local Services    = env.Services
    local getLocalHRP = env.getLocalHRP
    local AF_Config   = env.AF_Config

    local function getLivingFolder()
        local living = Services.Workspace:FindFirstChild("Living")
        return (living and living:IsA("Folder")) and living or nil
    end

    local function normalizeMobName(name)
        local base = tostring(name or "")
        base = base:gsub("%d+$", ""):gsub("%s+$", "")
        return base == "" and "Mob" or base
    end

    local function isPlayerModel(model)
        if not model then return false end
        for _, pl in ipairs(Services.Players:GetPlayers()) do
            local char = pl.Character
            if char and (model == char or model:IsDescendantOf(char)) then
                return true
            end
            if model.Name == pl.Name or model.Name:find(pl.Name, 1, true) then
                return true
            end
        end
        return false
    end

    local function getMobRoot(model)
        if not model or not model.Parent then return nil end
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp then return hrp end
        if model.PrimaryPart then return model.PrimaryPart end
        return model:FindFirstChildWhichIsA("BasePart")
    end

    local function mobPosition(model)
        local root = getMobRoot(model)
        return root and root.Position or nil
    end

    local function isMobAlive(model)
        if not model or not model.Parent then return false end
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not hum then return false end
        if hum.Health <= 0 then return false end
        if hum:GetState() == Enum.HumanoidStateType.Dead then return false end
        return true
    end

    local function getMobHealth(model)
        if not model or not model.Parent then return nil end
        local hum = model:FindFirstChildOfClass("Humanoid")
        return hum and hum.Health or nil
    end

    local function scanMobs()
        local nameMap = {}
        local names   = {}
        local living  = getLivingFolder()
        if not living then return nameMap, names end
        for _, m in ipairs(living:GetChildren()) do
            if m:IsA("Model") then
                local hum = m:FindFirstChildOfClass("Humanoid")
                if hum and not isPlayerModel(m) then
                    local baseName = normalizeMobName(m.Name)
                    if not nameMap[baseName] then
                        nameMap[baseName] = {}
                        table.insert(names, baseName)
                    end
                    table.insert(nameMap[baseName], m)
                end
            end
        end
        table.sort(names)
        return nameMap, names
    end

    local function findNearbyEnemy()
        local hrp = getLocalHRP()
        if not hrp then return nil end
        local living = getLivingFolder()
        if not living then return nil end

        local myPos   = hrp.Position
        local bestMob = nil
        local bestDist = AF_Config.NearbyMobRange
        for _, m in ipairs(living:GetChildren()) do
            if m:IsA("Model") and not isPlayerModel(m) and isMobAlive(m) then
                local root = getMobRoot(m)
                if root then
                    local dist = (root.Position - myPos).Magnitude
                    if dist <= bestDist then
                        bestDist = dist
                        bestMob = m
                    end
                end
            end
        end
        return bestMob
    end

    return {
        getMobRoot = getMobRoot,
        mobPosition = mobPosition,
        isMobAlive = isMobAlive,
        getMobHealth = getMobHealth,
        scanMobs = scanMobs,
        findNearbyEnemy = findNearbyEnemy
    }
end
