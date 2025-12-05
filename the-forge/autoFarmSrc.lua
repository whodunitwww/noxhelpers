-- autoFarmSrc.lua
-- Simple unified auto farm (ores + enemies) using AttachPanel
-- Outsourced module version.
-- UPDATED: Added "Ditch Health %" Slider for conditional retreating

return function(ctx)
    ----------------------------------------------------------------
    -- CONTEXT BINDINGS
    ----------------------------------------------------------------
    local Services      = ctx.Services
    local Tabs          = ctx.Tabs
    local References    = ctx.References
    local Library       = ctx.Library
    local Options       = ctx.Options
    local Toggles       = ctx.Toggles
    local META          = ctx.META or {}

    local AttachPanel       = ctx.AttachPanel
    local MoveToPos         = ctx.MoveToPos
    local RunService        = Services.RunService
    local UserInputService  = Services.UserInputService
    local HttpService       = Services.HttpService

    ----------------------------------------------------------------
    -- INTERNAL HELPERS (Global Scope)
    ----------------------------------------------------------------

    local function getLocalHRP()
        return References.humanoidRootPart
    end

    local function notify(msg, time)
        if Library and Library.Notify then
            Library:Notify(msg, time or 3)
        end
    end
    
    local function getRocksFolder()
        return Services.Workspace:FindFirstChild("Rocks")
    end

    local function rockHealth(model)
        if not model or not model.Parent then
            return nil
        end
        local ok, value = pcall(function()
            return model:GetAttribute("Health")
        end)
        if not ok or value == nil then
            return nil
        end
        return tonumber(value)
    end

    local function isRockAlive(model)
        local h = rockHealth(model)
        return h and h > 0
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

    -- Shared ToolService remote
    local ToolActivatedRF = Services.ReplicatedStorage
        :WaitForChild("Shared")
        :WaitForChild("Packages")
        :WaitForChild("Knit")
        :WaitForChild("Services")
        :WaitForChild("ToolService")
        :WaitForChild("RF")
        :WaitForChild("ToolActivated")

    local function swingTool(remoteArg)
        local ok, err = pcall(function()
            ToolActivatedRF:InvokeServer(remoteArg)
        end)
        if not ok then
            warn("[AutoFarm] ToolActivated error:", err)
        end
    end

    -- ====================================================================
    --  PRIORITY TABLES & CONFIG LOADING
    -- ====================================================================

    -- Default priorities for ORES
    local DefaultOrePriority = {
        ["Crimson Crystal"] = 1,
        ["Cyan Crystal"]    = 1,
        ["Earth Crystal"]   = 1,
        ["Light Crystal"]   = 1,
        ["Volcanic Rock"]   = 2,
        ["Basalt Vein"]     = 3,
        ["Basalt Core"]     = 4,
        ["Basalt Rock"]     = 5,
    }

    -- Some ores don’t always appear in scan but should always be selectable for "Applies To"
    local PermOreList = {
        "Crimson Crystal",
        "Cyan Crystal",
        "Earth Crystal",
        "Light Crystal",
        "Volcanic Rock",
    }

    -- Default priorities for MOBS
    local DefaultEnemyPriority = {
        ["Blazing Slime"]           = 1,
        ["Elite Deathaxe Skeleton"] = 2,
        ["Reaper"]                  = 3,
        ["Elite Rogue Skeleton"]    = 4,
        ["Deathaxe Skeleton"]       = 5,
        ["Axe Skeleton"]            = 6,
        ["Skeleton Rogue"]          = 7,
        ["Bomber"]                  = 8,
    }

    -- Live (mutable) priority tables (can be overridden by config)
    local OrePriority   = {}
    local EnemyPriority = {}

    for k, v in pairs(DefaultOrePriority) do
        OrePriority[k] = v
    end

    for k, v in pairs(DefaultEnemyPriority) do
        EnemyPriority[k] = v
    end

    local PriorityConfigFile = "Cerberus/The Forge/PriorityConfig.json"

    local function loadPriorityConfig()
        -- Ensure folders exist
        if not isfolder("Cerberus") then makefolder("Cerberus") end
        if not isfolder("Cerberus/The Forge") then makefolder("Cerberus/The Forge") end

        if isfile(PriorityConfigFile) then
            local success, result = pcall(function()
                return HttpService:JSONDecode(readfile(PriorityConfigFile))
            end)

            if success and type(result) == "table" then
                if result.Ores or result.Enemies then
                    if type(result.Ores) == "table" then
                        OrePriority = {}
                        for k, v in pairs(result.Ores) do
                            OrePriority[k] = tonumber(v) or 999
                        end
                    end

                    if type(result.Enemies) == "table" then
                        EnemyPriority = {}
                        for k, v in pairs(result.Enemies) do
                            EnemyPriority[k] = tonumber(v) or 999
                        end
                    end
                else
                    OrePriority = {}
                    for k, v in pairs(result) do
                        OrePriority[k] = tonumber(v) or 999
                    end
                end
            else
                notify("Failed to load priority config. Using defaults.", 5)
            end
        else
            -- No file yet: create a proper default with BOTH Ores + Enemies
            local defaultPayload = {
                Ores    = DefaultOrePriority,
                Enemies = DefaultEnemyPriority,
            }

            local ok, err = pcall(function()
                writefile(PriorityConfigFile, HttpService:JSONEncode(defaultPayload))
            end)

            if not ok then
                warn("[AutoFarm] Failed to save default priority config:", err)
            end
        end
    end

    -- Load immediately on script start
    loadPriorityConfig()

    local function getTargetPriorityForMode(modeName, baseName)
        -- We prefer the LIVE tables (from config), and fall back to defaults
        if modeName == "Ores" then
            return (OrePriority[baseName])
                or (DefaultOrePriority[baseName])
                or 999
        elseif modeName == "Enemies" then
            return (EnemyPriority[baseName])
                or (DefaultEnemyPriority[baseName])
                or 999
        end
        return 999
    end

    -- ====================================================================
    --  FARM STATE + FLAGS
    -- ====================================================================

    local AvoidLava          = false
    local AvoidPlayers       = false
    local DamageDitchEnabled = false
    local DamageDitchThreshold = 100 -- Default 100%
    local TargetFullHealth   = false 
    local PlayerAvoidRadius  = 40
    
    -- New Flags for Nearby Mob Attack
    local AttackNearbyMobs   = false
    local NearbyMobRange     = 40

    -- Whitelists (Filters)
    local OreWhitelistEnabled = false
    local WhitelistedOres     = {} 
    local WhitelistAppliesTo  = {} 

    local ZoneWhitelistEnabled = false
    local WhitelistedZones     = {} 

    local TargetBlacklist    = {} 

    local FarmState = {
        enabled       = false,
        mode          = "Ores", 
        nameMap       = {},

        currentTarget = nil,
        moveCleanup   = nil,
        farmThread    = nil,
        noclipConn    = nil, 

        attached      = false,
        lastHit       = 0,
        detourActive  = false,

        lastTargetRef    = nil,
        lastTargetHealth = 0,
        stuckStartTime   = 0,
        
        -- Movement stuck watchdog
        lastMovePos      = Vector3.zero,
        lastMoveTime     = 0,
        
        LastLocalHealth  = 100, 
        
        -- State to track if we are temporarily distracted by a mob
        tempMobTarget    = nil, 
    }

    -- ====================================================================
    --  CONFIG SYSTEM (HUD)
    -- ====================================================================
    
    local ConfigFolder = "Cerberus/The Forge"
    local ConfigFile   = ConfigFolder .. "/HudConfig.json"

    local function saveHudConfig(position, size)
        if not isfolder("Cerberus") then makefolder("Cerberus") end
        if not isfolder("Cerberus/The Forge") then makefolder("Cerberus/The Forge") end
        
        local data = {
            X = position.X.Offset,
            Y = position.Y.Offset,
            SX = size.X.Offset,
            SY = size.Y.Offset
        }
        writefile(ConfigFile, HttpService:JSONEncode(data))
    end

    local function loadHudConfig()
        if isfile(ConfigFile) then
            local success, result = pcall(function()
                return HttpService:JSONDecode(readfile(ConfigFile))
            end)
            if success then return result end
        end
        return nil
    end

    -- ====================================================================
    --  NOCLIP SYSTEM (Updated for robustness)
    -- ====================================================================

    local function enableNoclip()
        if FarmState.noclipConn then return end
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
        -- Restore collision roughly
        local char = References.character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.CanCollide = true end
        end
    end

    -- ====================================================================
    --  ORE HELPERS (Cont)
    -- ====================================================================

    local function getZoneFromDescendant(model)
        local rocksFolder = getRocksFolder()
        if not rocksFolder then return nil end
        
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

    local GoblinCaveFolder = nil

    local function getGoblinCaveFolder()
        if GoblinCaveFolder and GoblinCaveFolder.Parent then
            return GoblinCaveFolder
        end

        local rocksFolder = getRocksFolder()
        if not rocksFolder then
            GoblinCaveFolder = nil
            return nil
        end

        local cave = rocksFolder:FindFirstChild("Island2GoblinCave")
        if cave and cave:IsA("Folder") then
            GoblinCaveFolder = cave
        else
            GoblinCaveFolder = nil
        end

        return GoblinCaveFolder
    end

    local function scanRocks()
        local rocksFolder = getRocksFolder()
        local nameMap = {}
        local uniqueNames = {}

        if not rocksFolder then
            return nameMap, uniqueNames
        end

        local caveFolder = getGoblinCaveFolder()

        for _, inst in ipairs(rocksFolder:GetDescendants()) do
            if inst:IsA("Model") then
                if caveFolder and inst:IsDescendantOf(caveFolder) then
                    -- skip
                else
                    local parent = inst.Parent
                    if not (parent and parent ~= rocksFolder and parent:IsA("Model")) then
                        
                        -- ZONE CHECK
                        local passedZone = true
                        if ZoneWhitelistEnabled then
                            local zoneName = getZoneFromDescendant(inst)
                            if not zoneName or not WhitelistedZones[zoneName] then
                                passedZone = false
                            end
                        end

                        if passedZone and rockHealth(inst) then
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

    -- ====================================================================
    --  MOB HELPERS
    -- ====================================================================

    local function getLivingFolder()
        local living = Services.Workspace:FindFirstChild("Living")
        if living and living:IsA("Folder") then
            return living
        end
        return nil
    end

    local function normalizeMobName(name)
        local base = tostring(name or "")
        base = base:gsub("%d+$", "")   -- remove trailing digits
        base = base:gsub("%s+$", "")   -- trim trailing spaces
        if base == "" then
            base = tostring(name or "Mob")
        end
        return base
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
        if not hum then return nil end
        return hum.Health
    end

    local function scanMobs()
        local nameMap = {}
        local names   = {}

        local living = getLivingFolder()
        if not living then
            return nameMap, names
        end

        for _, m in ipairs(living:GetChildren()) do
            if m:IsA("Model") then
                local hum = m:FindFirstChildOfClass("Humanoid")
                if hum and not isPlayerModel(m) then
                    local baseName = normalizeMobName(m.Name)
                    local bucket = nameMap[baseName]
                    if not bucket then
                        bucket = {}
                        nameMap[baseName] = bucket
                        table.insert(names, baseName)
                    end
                    table.insert(bucket, m)
                end
            end
        end

        table.sort(names)
        return nameMap, names
    end
    
    -- New helper for Nearby Mob Attack Logic
    local function findNearbyEnemy()
        local hrp = getLocalHRP()
        if not hrp then return nil end
        
        local living = getLivingFolder()
        if not living then return nil end
        
        local myPos = hrp.Position
        local bestMob = nil
        local bestDist = NearbyMobRange -- use the slider value
        
        for _, m in ipairs(living:GetChildren()) do
            if m:IsA("Model") and not isPlayerModel(m) and isMobAlive(m) then
                local root = getMobRoot(m)
                if root then
                    local dist = (root.Position - myPos).Magnitude
                    if dist <= bestDist then
                        -- Check line of sight or other conditions if needed? 
                        -- For now, pure distance.
                        bestDist = dist
                        bestMob = m
                    end
                end
            end
        end
        
        return bestMob
    end

    -- ====================================================================
    --  ATTACH CONFIG
    -- ====================================================================

    local ORE_ATTACH_MODE   = "Aligned"
    local ORE_ATTACH_Y_BASE = -8
    local ORE_ATTACH_HORIZ  = 0
    local ORE_HIT_INTERVAL  = 0.2
    local ORE_HIT_DIST      = 10

    local MOB_ATTACH_MODE   = "Aligned"
    local MOB_ATTACH_Y_BASE = -7
    local MOB_ATTACH_HORIZ  = 0
    local MOB_HIT_INTERVAL  = 0.25
    local MOB_HIT_DIST      = 12

    local ExtraYOffset      = 0      -- global Y offset
    local FarmSpeed         = 80     -- movement speed

    local FARM_MODE_ORES    = "Ores"
    local FARM_MODE_ENEMIES = "Enemies"

    local MaxTargetHeight   = 100

    local ModeDefs = {
        [FARM_MODE_ORES] = {
            name          = FARM_MODE_ORES,
            scan          = scanRocks,
            isAlive       = isRockAlive,
            getPos        = rockPosition,
            getRoot       = rockRoot,
            getHealth     = rockHealth,
            attachMode    = ORE_ATTACH_MODE,
            attachBaseY   = ORE_ATTACH_Y_BASE,
            attachHoriz   = ORE_ATTACH_HORIZ,
            hitInterval   = ORE_HIT_INTERVAL,
            hitDistance   = ORE_HIT_DIST,
            toolName      = "Pickaxe",
            toolRemoteArg = "Pickaxe",
        },

        [FARM_MODE_ENEMIES] = {
            name          = FARM_MODE_ENEMIES,
            scan          = scanMobs,
            isAlive       = isMobAlive,
            getPos        = mobPosition,
            getRoot       = getMobRoot,
            getHealth     = getMobHealth,
            attachMode    = MOB_ATTACH_MODE,
            attachBaseY   = MOB_ATTACH_Y_BASE,
            attachHoriz   = MOB_ATTACH_HORIZ,
            hitInterval   = MOB_HIT_INTERVAL,
            hitDistance   = MOB_HIT_DIST,
            toolName      = "Weapon",
            toolRemoteArg = "Weapon",
        },
    }

    local function configureAttachForMode(modeName)
        local def = ModeDefs[modeName]
        if not def then return end

        local y = def.attachBaseY + ExtraYOffset

        if AttachPanel.SetMode then
            AttachPanel.SetMode(def.attachMode)
        end
        if AttachPanel.SetYOffset then
            AttachPanel.SetYOffset(y)
        end
        if AttachPanel.SetHorizDist then
            AttachPanel.SetHorizDist(def.attachHoriz)
        end
        if AttachPanel.SetMovement then
            AttachPanel.SetMovement("Approach")
        end
        if AttachPanel.EnableAutoYOffset then
            AttachPanel.EnableAutoYOffset(false)
        end
        if AttachPanel.EnableDodge then
            AttachPanel.EnableDodge(false)
        end
    end

    local SavedAttach = nil

    local function saveAttachSettings()
        local state = AttachPanel.State or {}
        SavedAttach = {
            mode        = state.mode,
            yOffset     = state.yOffset,
            horizDist   = state.horizDist,
            movement    = state.movement,
            autoYOffset = state.autoYOffset,
            dodgeMode   = state.dodgeMode,
            dodgeRange  = state.dodgeRange,
        }
    end

    local function restoreAttachSettings()
        if not SavedAttach then return end
        if AttachPanel.SetMode then
            AttachPanel.SetMode(SavedAttach.mode)
        end
        if AttachPanel.SetYOffset then
            AttachPanel.SetYOffset(SavedAttach.yOffset)
        end
        if AttachPanel.SetHorizDist then
            AttachPanel.SetHorizDist(SavedAttach.horizDist)
        end
        if AttachPanel.SetMovement then
            AttachPanel.SetMovement(SavedAttach.movement)
        end
        if AttachPanel.EnableAutoYOffset then
            AttachPanel.EnableAutoYOffset(SavedAttach.autoYOffset)
        end
        if AttachPanel.EnableDodge then
            AttachPanel.EnableDodge(SavedAttach.dodgeMode)
        end
        local state = AttachPanel.State
        if state then
            state.dodgeRange = SavedAttach.dodgeRange
        end
        SavedAttach = nil
    end

    local function stopMoving()
        if FarmState.moveCleanup then
            pcall(FarmState.moveCleanup)
            FarmState.moveCleanup = nil
        end
    end

    -- ====================================================================
    --  BLACKLIST HELPERS
    -- ====================================================================

    local function isTargetBlacklisted(model)
        if not model then return false end
        local expiry = TargetBlacklist[model]
        if not expiry then return false end

        if not model.Parent or os.clock() >= expiry then
            TargetBlacklist[model] = nil
            return false
        end

        return true
    end

    local function blacklistTarget(model, duration)
        if not model then return end
        TargetBlacklist[model] = os.clock() + (duration or 60)
    end

    -- ====================================================================
    --  SAFE OFFSET WRAPPER
    -- ====================================================================

    local function safeComputeOffset(rootCFrame, def)
        if not AttachPanel or not AttachPanel.ComputeOffset then
            return Vector3.new(0, def.attachBaseY + ExtraYOffset, 0)
        end

        local ok, result = pcall(
            AttachPanel.ComputeOffset,
            rootCFrame,
            def.attachMode,
            def.attachHoriz,
            def.attachBaseY + ExtraYOffset
        )

        if ok and typeof(result) == "Vector3" then
            return result
        end

        return Vector3.new(0, def.attachBaseY + ExtraYOffset, 0)
    end

    -- ====================================================================
    --  LAVA AVOIDANCE
    -- ====================================================================

    local LavaParts = {}

    local function refreshLavaParts()
        table.clear(LavaParts)

        local ws = Services.Workspace
        if not ws then return end

        local assets = ws:FindFirstChild("Assets")
        if assets then
            local cave = assets:FindFirstChild("Cave Area [2]")
            if cave then
                local folder = cave:FindFirstChild("Folder")
                if folder then
                    for _, inst in ipairs(folder:GetDescendants()) do
                        if inst:IsA("BasePart") and inst.Name == "Lava" then
                            table.insert(LavaParts, inst)
                        end
                    end
                end
            end
        end

        local debris = ws:FindFirstChild("Debris")
        if debris then
            local lavaZone = debris:FindFirstChild("LavaDamageZone")
            if lavaZone and lavaZone:IsA("BasePart") then
                table.insert(LavaParts, lavaZone)
            end
        end
    end


    local function pointInsidePart(point, part)
        if not part or not part.Parent then return false end
        local relative = part.CFrame:PointToObjectSpace(point)
        local half = part.Size / 2
        return math.abs(relative.X) <= half.X
            and math.abs(relative.Y) <= half.Y
            and math.abs(relative.Z) <= half.Z
    end

    local function isPointInLava(point)
        if not AvoidLava then
            return false
        end

        if #LavaParts == 0 then
            refreshLavaParts()
        end
        for _, part in ipairs(LavaParts) do
            if pointInsidePart(point, part) then
                return true
            end
        end
        return false
    end

    -- ====================================================================
    --  PLAYER AVOIDANCE HELPERS
    -- ====================================================================

    local function isAnyPlayerNearHRP(radius)
        local hrp = getLocalHRP()
        if not hrp then return false, nil end

        local myPlayer = References.player
        for _, plr in ipairs(Services.Players:GetPlayers()) do
            if plr ~= myPlayer then
                local char = plr.Character
                local phrp = char and char:FindFirstChild("HumanoidRootPart")
                if phrp then
                    local dist = (phrp.Position - hrp.Position).Magnitude
                    if dist <= radius then
                        return true, plr
                    end
                end
            end
        end
        return false, nil
    end

    local function isAnyPlayerNearPosition(position, radius)
        if not position then return false, nil end

        local myPlayer = References.player
        for _, plr in ipairs(Services.Players:GetPlayers()) do
            if plr ~= myPlayer then
                local char = plr.Character
                local phrp = char and char:FindFirstChild("HumanoidRootPart")
                if phrp then
                    local dist = (phrp.Position - position).Magnitude
                    if dist <= radius then
                        return true, plr
                    end
                end
            end
        end

        return false, nil
    end

    -- Idle horizontal move away from players
    local function moveAwayFromNearbyPlayers()
        if not AvoidPlayers then return end

        local hrp = getLocalHRP()
        if not hrp then return end

        local myPlayer = References.player
        local hrpPos   = hrp.Position

        local closestDist = math.huge
        local closestPos  = nil

        for _, plr in ipairs(Services.Players:GetPlayers()) do
            if plr ~= myPlayer then
                local char = plr.Character
                local phrp = char and char:FindFirstChild("HumanoidRootPart")
                if phrp then
                    local dist = (phrp.Position - hrpPos).Magnitude
                    if dist <= PlayerAvoidRadius and dist < closestDist then
                        closestDist = dist
                        closestPos  = phrp.Position
                    end
                end
            end
        end

        if closestPos then
            -- Horizontal direction away from player
            local away = hrpPos - closestPos
            away = Vector3.new(away.X, 0, away.Z)
            local mag = away.Magnitude
            if mag < 1 then
                -- If basically on top, pick arbitrary sideways
                away = Vector3.new(1, 0, 0)
            else
                away = away / mag
            end

            local targetPos = hrpPos + away * (PlayerAvoidRadius + 10)
            targetPos = Vector3.new(targetPos.X, hrpPos.Y, targetPos.Z)

            stopMoving()
            FarmState.moveCleanup = MoveToPos(targetPos, FarmSpeed)
        end
    end

    -- Build a simple 1- or 2-point path around players between startPos and endPos
    local function buildPathAroundPlayers(startPos, endPos)
        if not AvoidPlayers then
            return { endPos }
        end

        local ab = endPos - startPos
        local abMag = ab.Magnitude
        if abMag < 5 then
            return { endPos }
        end

        local myPlayer = References.player
        local hitPlayerPos = nil
        local closestHitDist = math.huge

        for _, plr in ipairs(Services.Players:GetPlayers()) do
            if plr ~= myPlayer then
                local char = plr.Character
                local phrp = char and char:FindFirstChild("HumanoidRootPart")
                if phrp then
                    local p = phrp.Position

                    -- Distance from player to line segment startPos-endPos
                    local ap = p - startPos
                    local t = 0
                    local abDot = ab:Dot(ab)
                    if abDot > 0 then
                        t = math.clamp(ap:Dot(ab) / abDot, 0, 1)
                    end
                    local closestPoint = startPos + ab * t
                    local dist = (p - closestPoint).Magnitude

                    if dist <= PlayerAvoidRadius and dist < closestHitDist then
                        closestHitDist = dist
                        hitPlayerPos   = p
                    end
                end
            end
        end

        if not hitPlayerPos then
            return { endPos }
        end

        -- Compute a sideways offset around that player, horizontal only
        local sideDir = ab:Cross(Vector3.yAxis)
        if sideDir.Magnitude < 1e-3 then
            sideDir = Vector3.new(1, 0, 0)
        else
            sideDir = sideDir.Unit
        end

        local offsetDist = PlayerAvoidRadius + 8
        local mid = hitPlayerPos + sideDir * offsetDist
        -- Keep roughly horizontal movement for the detour point
        mid = Vector3.new(mid.X, startPos.Y, mid.Z)

        return { mid, endPos }
    end

    -- ====================================================================
    --  SIMPLE TARGET SELECTION (PRIORITY + NEAREST + LAVA + PLAYER AVOID)
    -- ====================================================================

    local function chooseNearestTarget()
        local hrp = getLocalHRP()
        if not hrp then return nil end

        local def = ModeDefs[FarmState.mode]
        if not def or not def.scan then return nil end

        local nameMap, _ = def.scan()
        FarmState.nameMap = nameMap or {}

        local bestTarget
        local bestDist
        local bestPriority = math.huge

        -- Updated: No longer uses selectedNames. Iterates EVERYTHING available.
        for name, models in pairs(nameMap) do
            -- Use shared helper so priority logic is always consistent
            local priority = getTargetPriorityForMode(FarmState.mode, name)

            if models then
                for _, model in ipairs(models) do
                    if model and model.Parent and def.isAlive(model) and not isTargetBlacklisted(model) then
                        local pos = def.getPos(model)

                        if pos then
                            local skip = false

                            -- Max height filter
                            if pos.Y > MaxTargetHeight then
                                skip = true
                            end

                            -- LAVA AVOIDANCE (ORES + ENEMIES)
                            -- NOTE: guarded by AvoidLava, so when toggle is OFF, this whole block is skipped.
                            if not skip and AvoidLava then
                                local root = def.getRoot(model)
                                if root then
                                    local offset = safeComputeOffset(root.CFrame, def)
                                    local attachPos = root.Position + offset
                                    if isPointInLava(attachPos) then
                                        skip = true
                                    end
                                end
                            end

                            -- PLAYER AVOIDANCE DURING PICK
                            if not skip and AvoidPlayers then
                                local nearTarget, _ = isAnyPlayerNearPosition(pos, PlayerAvoidRadius)
                                if nearTarget then
                                    -- skip (no blacklist here; we only blacklist if it's *our* active target)
                                    skip = true
                                end
                            end
                            
                            -- FULL HEALTH CHECK
                            if not skip and TargetFullHealth and def.name == FARM_MODE_ORES then
                                local h = def.getHealth(model)
                                local m = model:GetAttribute("MaxHealth")
                                if h and m and h < m then
                                    skip = true
                                end
                            end

                            if not skip then
                                local dist = (pos - hrp.Position).Magnitude
                                -- Priority first, then Distance
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
        end

        return bestTarget
    end

    -- ====================================================================
    --  ATTACH + MOVEMENT
    -- ====================================================================

    local function realignAttach(target, overrideDef)
        if not target then return end

        local def = overrideDef or ModeDefs[FarmState.mode]
        if not def then return end

        local state = AttachPanel.State
        if not state then return end

        local attachA1 = state._attachA1
        local alignOri = state._alignOri
        local hrp      = getLocalHRP()
        local root     = def.getRoot(target)

        if not (attachA1 and alignOri and hrp and root) then
            return
        end

        local cf = root.CFrame
        local offsetWorld = safeComputeOffset(cf, def)
        attachA1.Position = cf:VectorToObjectSpace(offsetWorld)

        alignOri.CFrame = CFrame.lookAt(hrp.Position, root.Position, Vector3.yAxis)
    end

    local function attachToTarget(target, overrideDef)
        if not target then return end

        -- If overriding (e.g. mob attack during ore farm), we don't call standard configure
        if overrideDef then
             -- Manual config for override (Enemies)
             if AttachPanel.SetMode then AttachPanel.SetMode(overrideDef.attachMode) end
             if AttachPanel.SetYOffset then AttachPanel.SetYOffset(overrideDef.attachBaseY + ExtraYOffset) end
             if AttachPanel.SetHorizDist then AttachPanel.SetHorizDist(overrideDef.attachHoriz) end
        else
            configureAttachForMode(FarmState.mode)
        end

        if AttachPanel.SetTarget then
            AttachPanel.SetTarget(target)
        end
        if AttachPanel.CreateAttach then
            AttachPanel.CreateAttach(target)
        end

        realignAttach(target, overrideDef)
    end

    -- === DETOUR PATH WHEN X < -120 ======================================

    local DETOUR_THRESHOLD_X = -120
    local DETOUR_POINTS = {
        Vector3.new(-259.431091, 21.436172, -129.926697),
        Vector3.new(-417.186188, 31.620274, -246.402084),
        Vector3.new(-138.949982, 30.126343, -497.266479),
        Vector3.new(-43.032295, 32.220428, -583.377686),
        Vector3.new(118.466454, 32.614773, -567.964050),
        Vector3.new(400.246185, 135.009399, -349.578552),
        Vector3.new(336.205627, 142.614944, -237.229599),
        Vector3.new(359.745148, 74.859268, -224.669601),
    }

    local function startMovingToTarget(target, overrideDef)
        stopMoving()

        local hrp = getLocalHRP()
        local def = overrideDef or ModeDefs[FarmState.mode]
        if not (hrp and def and def.getRoot) then
            return
        end

        local function getFinalPos()
            if not target or not target.Parent then
                return nil
            end
            local root = def.getRoot(target)
            if not root then return nil end

            local offset = safeComputeOffset(root.CFrame, def)
            return root.Position + offset
        end

        local startPos = hrp.Position
        local finalPos = getFinalPos()
        if not finalPos then return end

        -- Set initial watchdog data
        FarmState.lastMovePos = startPos
        FarmState.lastMoveTime = os.clock()

        local useDetour = (startPos.X < DETOUR_THRESHOLD_X)

        if not useDetour then
            -- Normal path: optionally build a detour around players
            local waypoints = { finalPos }
            if AvoidPlayers then
                waypoints = buildPathAroundPlayers(startPos, finalPos)
            end

            if #waypoints == 1 then
                -- Single leg, allow dynamic target updates
                FarmState.moveCleanup = MoveToPos(finalPos, FarmSpeed, getFinalPos)
            else
                -- Multi-leg (side-step around player, then target)
                local active = true
                local currentCleanup = nil

                local function globalCleanup()
                    active = false
                    if currentCleanup then
                        pcall(currentCleanup)
                        currentCleanup = nil
                    end
                end

                FarmState.moveCleanup = globalCleanup

                task.spawn(function()
                    for _, waypoint in ipairs(waypoints) do
                        if not active then return end

                        currentCleanup = MoveToPos(waypoint, FarmSpeed)

                        while active do
                            local h = getLocalHRP()
                            if not h then
                                if currentCleanup then
                                    pcall(currentCleanup)
                                    currentCleanup = nil
                                end
                                return
                            end

                            if (h.Position - waypoint).Magnitude <= 3 then
                                if currentCleanup then
                                    pcall(currentCleanup)
                                    currentCleanup = nil
                                end
                                break
                            end

                            task.wait(0.05)
                        end
                    end

                    if active then
                        -- Done with path
                        FarmState.moveCleanup = nil
                    end
                end)
            end

            return
        end

        -- Detour path: go through each DETOUR_POINTS in order, then final dynamic leg
        local active = true
        local currentCleanup = nil

        local function globalCleanup()
            active = false
            if currentCleanup then
                pcall(currentCleanup)
                currentCleanup = nil
            end
        end

        FarmState.moveCleanup = globalCleanup

        task.spawn(function()
            for _, waypoint in ipairs(DETOUR_POINTS) do
                if not active then return end

                currentCleanup = MoveToPos(waypoint, FarmSpeed)

                while active do
                    local h = getLocalHRP()
                    if not h then
                        if currentCleanup then
                            pcall(currentCleanup)
                            currentCleanup = nil
                        end
                        return
                    end

                    if (h.Position - waypoint).Magnitude <= 3 then
                        if currentCleanup then
                            pcall(currentCleanup)
                            currentCleanup = nil
                        end
                        break
                    end

                    task.wait(0.05)
                end
            end

            if not active then return end

            local fp = getFinalPos()
            if not fp then
                globalCleanup()
                return
            end

            -- Final dynamic leg (no extra around-player logic here; caves already detoured)
            local function dynFinalPos()
                return getFinalPos()
            end

            currentCleanup = MoveToPos(fp, FarmSpeed, dynFinalPos)
            -- Cleanup of this final leg is via globalCleanup / stopMoving()
        end)
    end

    -- ====================================================================
    --  PROXIMITY TRACKER (SEPARATE HUD SYSTEM)
    -- ====================================================================
    
    local TrackerState = {
        Enabled      = false,
        Gui          = nil,
        Container    = nil,
        TargetName   = nil,
        HealthBar    = nil,
        HealthText   = nil,
        DropList     = nil,
        
        CachedMaxHp  = 100,
        CurrentDrops = {}, 
        
        ActiveTarget    = nil,
        LastCheckHealth = {}, 
    }

    local function createTrackerGui()
        if TrackerState.Gui then return end
        
        local sg = Instance.new("ScreenGui")
        sg.Name = "ProximityTrackerHUD"
        sg.ResetOnSpawn = false
        pcall(function()
            sg.Parent = Services.Players.LocalPlayer:WaitForChild("PlayerGui")
        end)
        
        local savedConfig = loadHudConfig()
        local initialPos = UDim2.new(0.5, 0, 0.2, 0)
        local initialSize = UDim2.new(0, 320, 0, 180)
        
        if savedConfig then
            initialPos = UDim2.new(0, savedConfig.X, 0, savedConfig.Y)
            initialSize = UDim2.new(0, savedConfig.SX, 0, savedConfig.SY)
        end
        
        local mainFrame = Instance.new("Frame")
        mainFrame.Name = "MainFrame"
        mainFrame.Size = initialSize
        mainFrame.Position = initialPos
        mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
        mainFrame.BorderSizePixel = 0
        mainFrame.Parent = sg
        
        -- Drag Logic
        local dragging, dragInput, dragStart, startPos
        mainFrame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                dragStart = input.Position
                startPos = mainFrame.Position
                
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                        saveHudConfig(mainFrame.Position, mainFrame.Size)
                    end
                end)
            end
        end)
        
        mainFrame.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement then
                dragInput = input
            end
        end)
        
        UserInputService.InputChanged:Connect(function(input)
            if input == dragInput and dragging then
                local delta = input.Position - dragStart
                mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
        
        local uiCorner = Instance.new("UICorner")
        uiCorner.CornerRadius = UDim.new(0, 8)
        uiCorner.Parent = mainFrame
        
        local uiStroke = Instance.new("UIStroke")
        uiStroke.Color = Color3.fromRGB(60, 60, 70)
        uiStroke.Thickness = 2
        uiStroke.Transparency = 0.2
        uiStroke.Parent = mainFrame
        
        -- Resize Handle
        local resizeHandle = Instance.new("ImageButton")
        resizeHandle.Name = "ResizeHandle"
        resizeHandle.Size = UDim2.new(0, 20, 0, 20)
        resizeHandle.Position = UDim2.new(1, -20, 1, -20)
        resizeHandle.BackgroundTransparency = 1
        resizeHandle.Image = "rbxassetid://3570695787" -- Standard resize icon
        resizeHandle.ImageColor3 = Color3.fromRGB(150, 150, 150)
        resizeHandle.Parent = mainFrame
        
        local resizing, resizeStart, startSize
        resizeHandle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                resizing = true
                resizeStart = input.Position
                startSize = mainFrame.AbsoluteSize
                
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        resizing = false
                        saveHudConfig(mainFrame.Position, mainFrame.Size)
                    end
                end)
            end
        end)
        
        UserInputService.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement and resizing then
                local delta = input.Position - resizeStart
                mainFrame.Size = UDim2.new(0, startSize.X + delta.X, 0, startSize.Y + delta.Y)
            end
        end)

        local tName = Instance.new("TextLabel")
        tName.Name = "TargetName"
        tName.Size = UDim2.new(1, -20, 0, 26)
        tName.Position = UDim2.new(0, 10, 0, 10)
        tName.BackgroundTransparency = 1
        tName.TextColor3 = Color3.fromRGB(255, 255, 255)
        tName.Font = Enum.Font.GothamBold
        tName.TextSize = 18 
        tName.Text = "🎯 Searching..."
        tName.TextXAlignment = Enum.TextXAlignment.Left
        tName.TextTruncate = Enum.TextTruncate.AtEnd
        tName.Parent = mainFrame
        
        local barBg = Instance.new("Frame")
        barBg.Name = "BarBG"
        barBg.Size = UDim2.new(1, -20, 0, 18) 
        barBg.Position = UDim2.new(0, 10, 0, 40)
        barBg.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
        barBg.BorderSizePixel = 0
        barBg.Parent = mainFrame
        
        local barCorner = Instance.new("UICorner")
        barCorner.CornerRadius = UDim.new(0, 5)
        barCorner.Parent = barBg
        
        local barFill = Instance.new("Frame")
        barFill.Name = "Fill"
        barFill.Size = UDim2.new(1, 0, 1, 0)
        barFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        barFill.BorderSizePixel = 0
        barFill.Parent = barBg
        
        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(0, 5)
        fillCorner.Parent = barFill
        
        local gradient = Instance.new("UIGradient")
        gradient.Color = ColorSequence.new{
            ColorSequenceKeypoint.new(0, Color3.fromRGB(85, 255, 120)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 170, 120))
        }
        gradient.Parent = barFill
        
        local hpText = Instance.new("TextLabel")
        hpText.Size = UDim2.new(1, 0, 1, 0)
        hpText.BackgroundTransparency = 1
        hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
        hpText.Font = Enum.Font.GothamBold
        hpText.TextSize = 12
        hpText.TextStrokeTransparency = 0.5
        hpText.Text = "100 / 100"
        hpText.ZIndex = 2
        hpText.Parent = barBg
        
        local dLabel = Instance.new("TextLabel")
        dLabel.Name = "DropsLabel"
        dLabel.Size = UDim2.new(1, -20, 0, 20)
        dLabel.Position = UDim2.new(0, 10, 0, 68)
        dLabel.BackgroundTransparency = 1
        dLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        dLabel.Font = Enum.Font.Gotham
        dLabel.TextSize = 14
        dLabel.Text = "💎 Drops Detected:"
        dLabel.TextXAlignment = Enum.TextXAlignment.Left
        dLabel.Parent = mainFrame
        
        local dropContainer = Instance.new("Frame")
        dropContainer.Name = "DropContainer"
        dropContainer.Size = UDim2.new(1, 0, 1, -95) 
        dropContainer.Position = UDim2.new(0, 0, 0, 95)
        dropContainer.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
        dropContainer.BorderSizePixel = 0
        dropContainer.Parent = mainFrame
        
        local dropCorner = Instance.new("UICorner")
        dropCorner.CornerRadius = UDim.new(0, 6)
        dropCorner.Parent = dropContainer
        
        local dList = Instance.new("ScrollingFrame")
        dList.Name = "DropList"
        dList.Size = UDim2.new(1, -10, 1, -10)
        dList.Position = UDim2.new(0, 5, 0, 5)
        dList.BackgroundTransparency = 1
        dList.BorderSizePixel = 0
        dList.ScrollBarThickness = 4
        dList.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 80)
        dList.AutomaticCanvasSize = Enum.AutomaticSize.Y
        dList.CanvasSize = UDim2.new(0, 0, 0, 0)
        dList.Parent = dropContainer
        
        local layout = Instance.new("UIListLayout")
        layout.Parent = dList
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 4)
        
        TrackerState.Gui = sg
        TrackerState.Container = mainFrame
        TrackerState.TargetName = tName
        TrackerState.HealthBar = barFill
        TrackerState.HealthText = hpText
        TrackerState.DropList = dList
        
        sg.Enabled = false
    end
    
    local function resetTrackerData(newTarget)
        if not TrackerState.Gui then return end
        
        -- Clear Drops
        for _, c in ipairs(TrackerState.DropList:GetChildren()) do
            if c:IsA("TextLabel") then c:Destroy() end
        end
        table.clear(TrackerState.CurrentDrops)
        
        if newTarget then
            local hp = rockHealth(newTarget) or 100
            local attrMax = newTarget:GetAttribute("MaxHealth")
            TrackerState.CachedMaxHp = attrMax or hp
        end
    end
    
    local function updateTrackerUi()
        if not TrackerState.Enabled or not TrackerState.Gui then
            if TrackerState.Gui then TrackerState.Gui.Enabled = false end
            return
        end
        
        -- PERSISTENCE: Keep UI open even if no target
        TrackerState.Gui.Enabled = true
        
        local target = TrackerState.ActiveTarget
        if not target or not target.Parent then
            -- Show "Searching..." state
            TrackerState.TargetName.Text = "🎯 Searching..."
            TrackerState.HealthBar:TweenSize(UDim2.new(0, 0, 1, 0), "Out", "Quad", 0.3, true)
            TrackerState.HealthText.Text = "0 / 0"
            return
        end
        
        TrackerState.TargetName.Text = "🎯 " .. target.Name
        
        local hp = rockHealth(target) or 0
        local maxHp = math.max(TrackerState.CachedMaxHp, 1)
        
        local pct = math.clamp(hp / maxHp, 0, 1)
        TrackerState.HealthBar:TweenSize(UDim2.new(pct, 0, 1, 0), "Out", "Quad", 0.15, true)
        TrackerState.HealthText.Text = math.floor(hp) .. " / " .. math.floor(maxHp)
        
        -- Scan Drops
        local children = target:GetChildren()
        for _, c in ipairs(children) do
            if c.Name == "Ore" and not TrackerState.CurrentDrops[c] then
                local oreType = c:GetAttribute("Ore")
                if oreType then
                    TrackerState.CurrentDrops[c] = true
                    
                    local lbl = Instance.new("TextLabel")
                    lbl.Size = UDim2.new(1, 0, 0, 20)
                    lbl.BackgroundTransparency = 1
                    lbl.TextColor3 = Color3.fromRGB(255, 215, 0)
                    lbl.Font = Enum.Font.GothamMedium
                    lbl.TextSize = 14
                    lbl.Text = "  ✨ " .. tostring(oreType)
                    lbl.TextXAlignment = Enum.TextXAlignment.Left
                    lbl.Parent = TrackerState.DropList
                    
                    TrackerState.DropList.CanvasPosition = Vector2.new(0, 9999)
                end
            end
        end
    end

    -- Independent Loop for Proximity Tracker
    task.spawn(function()
        while true do
            if not TrackerState.Enabled then
                if TrackerState.Gui then TrackerState.Gui.Enabled = false end
                task.wait(1)
                continue
            end
            
            local hrp = getLocalHRP()
            if not hrp then
                task.wait(0.5)
                continue
            end
            
            local rocks = {}
            local folder = getRocksFolder()
            
            if folder then
                for _, desc in ipairs(folder:GetDescendants()) do
                    if desc:IsA("Model") and desc:GetAttribute("Health") then
                        if (desc:GetPivot().Position - hrp.Position).Magnitude <= 15 then
                            table.insert(rocks, desc)
                        end
                    end
                end
            end
            
            for _, rock in ipairs(rocks) do
                local currentHp = rockHealth(rock) or 0
                local oldHp = TrackerState.LastCheckHealth[rock]
                
                if oldHp and currentHp < oldHp then
                    if TrackerState.ActiveTarget ~= rock then
                        TrackerState.ActiveTarget = rock
                        resetTrackerData(rock)
                    end
                end
                
                TrackerState.LastCheckHealth[rock] = currentHp
            end
            
            for r, _ in pairs(TrackerState.LastCheckHealth) do
                if not r.Parent or (r:GetPivot().Position - hrp.Position).Magnitude > 20 then
                    TrackerState.LastCheckHealth[r] = nil
                end
            end
            
            if TrackerState.ActiveTarget then
                local t = TrackerState.ActiveTarget
                if not t.Parent or (rockHealth(t) or 0) <= 0 or (t:GetPivot().Position - hrp.Position).Magnitude > 20 then
                    TrackerState.ActiveTarget = nil
                end
            end
            
            updateTrackerUi()
            task.wait(0.1)
        end
    end)
    
    -- ====================================================================
    --  MAIN FARM LOOP (RETARGET ON PLAYER NEAR TARGET)
    -- ====================================================================

    local function farmLoop()
        -- Init health to current so we don't instant-ditch if low
        if References.humanoid then
            FarmState.LastLocalHealth = References.humanoid.Health
        end

        while FarmState.enabled do
            -- >>> CRASH PROTECTION: Wrap loop body in pcall <<<
            local loopSuccess, loopError = pcall(function()
                
                local hrp = getLocalHRP()
                local hum = References.humanoid

                -- death / no char handling (safe)
                if not hrp or not hum then
                    stopMoving()
                    FarmState.currentTarget = nil
                    FarmState.attached      = false
                    FarmState.detourActive  = false
                    FarmState.tempMobTarget = nil
                    task.wait(0.3)
                    return -- acts as continue inside pcall
                end

                local humHealth
                local humState
                local okState, stateOrErr = pcall(function()
                    return hum:GetState()
                end)

                if okState then
                    humState  = stateOrErr
                    humHealth = hum.Health
                else
                    -- Humanoid probably invalid / destroyed
                    stopMoving()
                    FarmState.currentTarget = nil
                    FarmState.attached      = false
                    FarmState.detourActive  = false
                    FarmState.tempMobTarget = nil
                    task.wait(0.3)
                    return
                end

                if humHealth <= 0 or humState == Enum.HumanoidStateType.Dead then
                    stopMoving()
                    FarmState.currentTarget = nil
                    FarmState.attached      = false
                    FarmState.detourActive  = false
                    FarmState.tempMobTarget = nil
                    task.wait(0.3)
                    return
                end
                
                -- >>> DAMAGE DITCH LOGIC (UPDATED: Check Threshold) <<<
                -- Only ditch if: Enabled AND Health Dropped AND Health < Threshold %
                local ditchLimit = hum.MaxHealth * (DamageDitchThreshold / 100)
                
                if DamageDitchEnabled and FarmState.currentTarget and humHealth < FarmState.LastLocalHealth and humHealth < ditchLimit then
                    notify("Took damage! Ditching.", 2)
                    blacklistTarget(FarmState.currentTarget, 60)
                    stopMoving()
                    FarmState.currentTarget = nil
                    FarmState.attached      = false
                    FarmState.detourActive  = false
                    FarmState.tempMobTarget = nil
                    
                    FarmState.LastLocalHealth = humHealth 
                    task.wait(0.15)
                    return
                end
                -- Update local health tracking for next loop
                FarmState.LastLocalHealth = humHealth
                
                -- >>> NEARBY MOB CHECK (Ore Mode Only) <<<
                local activeTarget = nil
                local activeDef = nil
                local isDistracted = false

                if FarmState.mode == FARM_MODE_ORES and AttackNearbyMobs then
                    -- If we already have a focused mob, check if it's still valid
                    if FarmState.tempMobTarget then
                        if FarmState.tempMobTarget.Parent and isMobAlive(FarmState.tempMobTarget) then
                            -- It's still valid, keep attacking
                            local root = getMobRoot(FarmState.tempMobTarget)
                            local dist = root and (root.Position - hrp.Position).Magnitude or 9999
                            if dist <= NearbyMobRange + 10 then -- slight buffer to finish kill
                                activeTarget = FarmState.tempMobTarget
                                activeDef = ModeDefs[FARM_MODE_ENEMIES]
                                isDistracted = true
                            else
                                FarmState.tempMobTarget = nil
                            end
                        else
                             FarmState.tempMobTarget = nil
                        end
                    end
                    
                    -- If no active mob, scan for new one
                    if not FarmState.tempMobTarget then
                        local mob = findNearbyEnemy()
                        if mob then
                            FarmState.tempMobTarget = mob
                            activeTarget = mob
                            activeDef = ModeDefs[FARM_MODE_ENEMIES]
                            isDistracted = true
                            notify("Attacking nearby " .. mob.Name, 1)
                        end
                    end
                end
                
                -- If not distracted by a mob, use standard logic
                if not isDistracted then
                    activeTarget = FarmState.currentTarget
                    activeDef = ModeDefs[FarmState.mode]
                end

                if not activeDef then
                    task.wait(0.3)
                    return
                end

                local pos    = activeTarget and activeDef.getPos(activeTarget) or nil
                local alive  = activeTarget and activeDef.isAlive(activeTarget)

                -- Pick new target if current is invalid or blacklisted (ONLY if not distracted)
                if (not activeTarget)
                    or (not activeTarget.Parent)
                    or (not pos)
                    or (not alive)
                    or (not isDistracted and isTargetBlacklisted(activeTarget)) then
                    
                    if isDistracted then
                        -- Mob died or vanished. Clear temp logic and loop will revert to ores next tick.
                        FarmState.tempMobTarget = nil
                        FarmState.attached = false
                        stopMoving()
                        -- Don't return, let loop continue to pick new ore
                    end

                    -- Standard Target Selection
                    FarmState.currentTarget = chooseNearestTarget()
                    FarmState.attached      = false
                    FarmState.detourActive  = false
                    
                    -- Reset stuck logic for new target
                    FarmState.lastTargetRef    = FarmState.currentTarget
                    FarmState.lastTargetHealth = 0
                    FarmState.stuckStartTime   = os.clock()
                    
                    -- Reset Damage Ditch baseline
                    FarmState.LastLocalHealth = humHealth

                    activeTarget = FarmState.currentTarget
                    activeDef = ModeDefs[FarmState.mode] -- Revert def

                    if activeTarget then
                        startMovingToTarget(activeTarget, activeDef)
                        pos = activeDef.getPos(activeTarget)
                    else
                        -- No targets found:
                        -- We stay idle but anchor to prevent falling through map
                        stopMoving()
                        
                        if hrp and hrp.Anchored == false then
                            hrp.Anchored = true -- prevent fall
                        end
                        
                        if AvoidPlayers then
                            moveAwayFromNearbyPlayers()
                        end
                        task.wait(0.15)
                        return
                    end
                end

                -- If we have target, ensure unanchored so we can move
                if hrp.Anchored == true then
                    hrp.Anchored = false
                end

                -- Double-check target position validity and height (retarget instead of stopping)
                if pos and pos.Y > MaxTargetHeight then
                    notify("Target too high! Ditching.", 2)
                    blacklistTarget(activeTarget, 60) -- too high, don't keep retargeting it

                    stopMoving()
                    FarmState.currentTarget = nil
                    FarmState.attached      = false
                    FarmState.detourActive  = false

                    -- Immediately retarget to the next one (Only if we aren't distracted by mob)
                    if not isDistracted then
                         local newTarget = chooseNearestTarget()
                        if newTarget then
                            FarmState.currentTarget = newTarget
                            FarmState.attached      = false
                            FarmState.detourActive  = false
                            
                            FarmState.lastTargetRef    = newTarget
                            FarmState.lastTargetHealth = 0
                            FarmState.stuckStartTime   = os.clock()
                            
                            FarmState.LastLocalHealth = humHealth 

                            startMovingToTarget(newTarget, activeDef)
                            -- next loop will handle hit logic
                        end
                    else
                         FarmState.tempMobTarget = nil -- Reset mob target
                    end
                    task.wait(0.15)
                    return
                end

                -- >>> DYNAMIC PLAYER AVOIDANCE <<<
                if AvoidPlayers then
                    -- Check if any player is dangerously close to our current position
                    local nearMe, _ = isAnyPlayerNearHRP(PlayerAvoidRadius)
                    if nearMe then
                        notify("Player too close! Moving.", 2)
                        -- If attached, detach. If moving, find new path/target.
                        if activeTarget and not isDistracted then
                            blacklistTarget(activeTarget, 60)
                        end
                        stopMoving()
                        FarmState.currentTarget = nil
                        FarmState.tempMobTarget = nil
                        FarmState.attached = false
                        FarmState.detourActive = false
                        task.wait(0.15)
                        return
                    end
                    
                    -- Check target area
                    if pos then
                        local nearTarget, _ = isAnyPlayerNearPosition(pos, PlayerAvoidRadius)
                        if nearTarget then
                            notify("Player at target! Ditching.", 2)
                            if not isDistracted then
                                blacklistTarget(activeTarget, 60)
                            else
                                FarmState.tempMobTarget = nil -- Abandon mob
                            end
                            stopMoving()
                            FarmState.currentTarget = nil
                            FarmState.attached = false
                            FarmState.detourActive = false
                            task.wait(0.15)
                            return
                        end
                    end
                end
                
                -- >>> WHITELIST CHECK FOR ORES (Gated by OreWhitelistEnabled) <<<
                -- Note: Only run this if we are NOT distracted by a mob
                if not isDistracted and FarmState.mode == FARM_MODE_ORES and OreWhitelistEnabled and activeTarget then
                    -- Only apply check if target name matches the "Applies To" list
                    if WhitelistAppliesTo[activeTarget.Name] then
                        local oreChildren = {}
                        for _, c in ipairs(activeTarget:GetChildren()) do
                            if c.Name == "Ore" then
                                table.insert(oreChildren, c)
                            end
                        end
                        
                        if #oreChildren > 0 then
                            local matchFound = false
                            for _, orePart in ipairs(oreChildren) do
                                local oreType = orePart:GetAttribute("Ore")
                                if oreType and WhitelistedOres[oreType] then
                                    matchFound = true
                                    break
                                end
                            end
                            
                            if not matchFound then
                                notify("No whitelisted ore found! Ditching.", 2)
                                blacklistTarget(activeTarget, 60)
                                stopMoving()
                                FarmState.currentTarget = nil
                                FarmState.attached      = false
                                FarmState.detourActive  = false
                                task.wait(0.1)
                                return
                            end
                        end
                    end
                end

                -- If we have a target and we somehow end up with X < -120 while NOT attached,
                -- force a detour-based path once per "under-threshold" period.
                if activeTarget and not FarmState.attached and not isDistracted then
                    local hrpPos = hrp.Position
                    if hrpPos.X < DETOUR_THRESHOLD_X then
                        if not FarmState.detourActive then
                            FarmState.detourActive = true
                            stopMoving()
                            startMovingToTarget(activeTarget, activeDef) -- will use detour because X < threshold
                        end
                    else
                        -- once we're back above the threshold, allow detour to be triggered again later
                        FarmState.detourActive = false
                    end
                else
                    -- if no target or attached, we don't consider detour
                    FarmState.detourActive = false
                end

                if pos then
                    local dist = (pos - hrp.Position).Magnitude

                    if dist <= activeDef.hitDistance then
                        stopMoving()

                        if not FarmState.attached then
                            attachToTarget(activeTarget, activeDef) -- Pass activeDef for mob override
                            FarmState.attached = true
                            -- Reset stuck timer on first attach
                            FarmState.stuckStartTime = os.clock()
                            local h = activeDef.getHealth(activeTarget)
                            FarmState.lastTargetHealth = h or 0
                        else
                            -- === ALWAYS FACE TARGET UPDATE ===
                            realignAttach(activeTarget, activeDef)

                            -- >>> STUCK CHECK (20s) <<<
                            -- Only run stuck check if we have been attached to this target
                            -- (Skipped for mob attacks to prevent ditching active combat)
                            if not isDistracted and FarmState.lastTargetRef == activeTarget then
                                local currentH = activeDef.getHealth(activeTarget) or 0
                                -- If health changed (damaged), reset timer
                                if currentH < FarmState.lastTargetHealth then
                                    FarmState.lastTargetHealth = currentH
                                    FarmState.stuckStartTime = os.clock()
                                else
                                    -- Health didn't change
                                    if (os.clock() - FarmState.stuckStartTime) > 20 then
                                        -- STUCK FOR 20 SECONDS
                                        notify("Stuck (20s)! Ditching.", 2)
                                        blacklistTarget(activeTarget, 60)
                                        stopMoving()
                                        FarmState.currentTarget = nil
                                        FarmState.attached      = false
                                        FarmState.detourActive  = false
                                        task.wait(0.1)
                                        return
                                    end
                                end
                            else
                                -- Target ref mismatch (shouldn't happen often), reset
                                FarmState.lastTargetRef = activeTarget
                                FarmState.lastTargetHealth = activeDef.getHealth(activeTarget) or 0
                                FarmState.stuckStartTime = os.clock()
                            end
                        end

                        local now = os.clock()
                        if now - FarmState.lastHit >= activeDef.hitInterval then
                            swingTool(activeDef.toolRemoteArg) -- Dynamically uses Weapon/Pickaxe
                            FarmState.lastHit = now
                        end
                    else
                        -- Out of range, make sure we are moving
                        if not FarmState.moveCleanup then
                            startMovingToTarget(activeTarget, activeDef)
                        end
                        FarmState.attached = false
                        -- Reset stuck timer while moving
                        FarmState.stuckStartTime = os.clock()
                        
                        -- >>> MOVEMENT WATCHDOG <<<
                        -- If we are supposed to be moving, but our position hasn't changed by >3 studs in 3 seconds, reset.
                        if (os.clock() - FarmState.lastMoveTime) > 3 then
                            if (hrp.Position - FarmState.lastMovePos).Magnitude < 3 then
                                notify("Movement Stuck! Resetting.", 2)
                                stopMoving() -- Stop current tween
                                startMovingToTarget(activeTarget, activeDef) -- Try again
                            end
                            FarmState.lastMovePos = hrp.Position
                            FarmState.lastMoveTime = os.clock()
                        end
                    end
                end

                task.wait(0.05)
            end) -- end pcall

            if not loopSuccess then
                warn("[AutoFarm] Crash detected in loop:", loopError)
                stopMoving()
                FarmState.attached = false
                task.wait(1) -- Cool down before restarting loop
            end
        end

        stopMoving()
        FarmState.currentTarget = nil
        FarmState.tempMobTarget = nil
        FarmState.attached      = false
        FarmState.detourActive  = false
        
        local hrp = getLocalHRP()
        if hrp then hrp.Anchored = false end -- Always unanchor on stop
        
        disableNoclip()
    end

    -- ====================================================================
    --  START / STOP
    -- ====================================================================

    local function startFarm()
        -- *** ERROR FIX: Ensure Tracker GUI exists BEFORE farm starts ***
        if TrackerState.Enabled then
            createTrackerGui()
        end

        if FarmState.enabled then return end

        local def = ModeDefs[FarmState.mode]
        if not def then
            notify("Invalid farm mode.", 3)
            if Toggles.AF_Enabled then
                Toggles.AF_Enabled:SetValue(false)
            end
            return
        end

        if FarmState.mode == FARM_MODE_ORES and not getRocksFolder() then
            notify("No workspace.Rocks folder found.", 3)
            if Toggles.AF_Enabled then
                Toggles.AF_Enabled:SetValue(false)
            end
            return
        end

        if FarmState.mode == FARM_MODE_ENEMIES and not getLivingFolder() then
            notify("No workspace.Living folder found.", 3)
            if Toggles.AF_Enabled then
                Toggles.AF_Enabled:SetValue(false)
            end
            return
        end
        
        -- Warning if whitelist enabled but no ores selected
        local whitelistedCount = 0
        for _ in pairs(WhitelistedOres) do whitelistedCount = whitelistedCount + 1 end
        if FarmState.mode == FARM_MODE_ORES and OreWhitelistEnabled and whitelistedCount == 0 then
            notify("Warning: Ore Whitelist ON but no ores selected!", 5)
        end

        saveAttachSettings()
        configureAttachForMode(FarmState.mode)
        
        -- Enable Noclip
        enableNoclip()

        -- hard reset state so death / previous run can't poison us
        stopMoving()
        FarmState.currentTarget = nil
        FarmState.tempMobTarget = nil
        FarmState.attached      = false
        FarmState.lastHit       = 0
        FarmState.detourActive  = false
        FarmState.lastMoveTime  = os.clock()

        FarmState.enabled       = true
        FarmState.farmThread    = task.spawn(farmLoop)
    end

    local function stopFarm()
        FarmState.enabled = false
        stopMoving()
        FarmState.currentTarget = nil
        FarmState.tempMobTarget = nil
        FarmState.attached      = false
        FarmState.detourActive  = false
        
        local hrp = getLocalHRP()
        if hrp then hrp.Anchored = false end

        disableNoclip()

        if AttachPanel.DestroyAttach then
            pcall(AttachPanel.DestroyAttach)
        end

        restoreAttachSettings()
    end

    -- ====================================================================
    --  UI: MODE + TARGETS + OFFSET + SPEED + AVOID + AUTO TOOL
    -- ====================================================================

    local AutoTab   = Tabs["Auto"] or Tabs.Main
    local WhitelistGroup = AutoTab:AddLeftGroupbox("Whitelists", "list")
    local FarmGroup = AutoTab:AddLeftGroupbox("Auto Farm", "pickaxe")
    local TrackingGroupbox = Tabs.Auto:AddRightGroupbox("Tracking", "compass")

    local ModeDropdown
    -- TargetDropdown Removed
    local OreTypeDropdown
    local ZoneDropdown 
    local AppliesToDropdown

    -- Renamed from refreshTargetDropdown to prevent confusion (it only updates the AppliesTo list now)
    local function refreshAvailableTargets()
        local def = ModeDefs[FarmState.mode]
        if not def or not def.scan then
            if AppliesToDropdown then AppliesToDropdown:SetValues({}) end
            return
        end
        
        local nameMap, uniqueNames = def.scan()
        
        -- Merge PermOreList if in Ore Mode
        if FarmState.mode == FARM_MODE_ORES then
            local set = {}
            for _, n in ipairs(uniqueNames) do set[n] = true end
            for _, n in ipairs(PermOreList) do
                if not set[n] then
                    table.insert(uniqueNames, n)
                    set[n] = true
                end
            end
            table.sort(uniqueNames)
        end
        
        if AppliesToDropdown then
            AppliesToDropdown:SetValues(uniqueNames)
        end
    end
    
    local function refreshOreTypesDropdown()
        if not OreTypeDropdown then return end
        local types = getGameOreTypes()
        OreTypeDropdown:SetValues(types)
    end

    local function refreshZoneDropdown()
        if not ZoneDropdown then return end
        local zones = scanZones()
        ZoneDropdown:SetValues(zones)
    end

    -- >>> WHITELISTS GROUP <<<
    
    ModeDropdown = WhitelistGroup:AddDropdown("AF_Mode", {
        Text    = "Farm Mode",
        Values  = { FARM_MODE_ORES, FARM_MODE_ENEMIES },
        Default = FarmState.mode,
        Callback = function(value)
            if FarmState.mode == value then return end
            FarmState.mode = value
            refreshAvailableTargets()
            if FarmState.enabled then
                stopFarm()
                startFarm()
            end
        end,
    })

    WhitelistGroup:AddLabel("Mob/Ore selection is now controlled by priorities, use the priority editor below to do this.", true)

    -- TargetDropdown REMOVED here --
    
    WhitelistGroup:AddToggle("AF_TargetFullHealth", {
        Text    = "Target Full Health Only",
        Default = false,
        Tooltip = "Only targets fresh rocks.",
        Callback = function(state)
            TargetFullHealth = state
        end,
    })
    
    WhitelistGroup:AddToggle("AF_ZoneWhitelist", {
        Text    = "Zone Whitelist",
        Default = false,
        Tooltip = "Only target rocks inside specific Zone folders.",
        Callback = function(state)
            ZoneWhitelistEnabled = state
        end,
    })

    ZoneDropdown = WhitelistGroup:AddDropdown("AF_Zones", {
        Text   = "Whitelisted Zones",
        Values = {},
        Multi  = true,
        Callback = function(selectedTable)
            WhitelistedZones = {}
            for name, selected in pairs(selectedTable) do
                if selected then
                    WhitelistedZones[name] = true
                end
            end
        end,
    })
    
    WhitelistGroup:AddDivider()

    WhitelistGroup:AddToggle("AF_OreWhitelist", {
        Text    = "Ore Drop Whitelist",
        Default = false,
        Tooltip = "If enabled, checks inside the rock for specific ore drops.",
        Callback = function(state)
            OreWhitelistEnabled = state
        end,
    })
    
    AppliesToDropdown = WhitelistGroup:AddDropdown("AF_AppliesTo", {
        Text   = "Whitelist Applies To",
        Values = {},
        Multi  = true,
        Tooltip = "Select which rocks require drop checking. Unselected rocks are mined freely.",
        Callback = function(selectedTable)
            WhitelistAppliesTo = {}
            for name, selected in pairs(selectedTable) do
                if selected then
                    WhitelistAppliesTo[name] = true
                end
            end
        end,
    })
    
    OreTypeDropdown = WhitelistGroup:AddDropdown("AF_OreTypes", {
        Text   = "Whitelisted Ores",
        Values = {},
        Multi  = true,
        Tooltip = "Select which drops (Iron, Gold, etc) allow mining.",
        Callback = function(selectedTable)
            WhitelistedOres = {}
            for name, selected in pairs(selectedTable) do
                if selected then
                    WhitelistedOres[name] = true
                end
            end
        end,
    })
    
    WhitelistGroup:AddDivider()
    
    WhitelistGroup:AddButton({
        Text = "Launch Priority Editor",
        Func = function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/whodunitwww/noxhelpers/refs/heads/main/the-forge/editor.lua"))()
        end,
    })
    
    WhitelistGroup:AddButton({
        Text = "Reload Priorities",
        Func = function()
            loadPriorityConfig()
            notify("Priorities reloaded from config!", 3)
        end,
    })
    
    WhitelistGroup:AddButton({
        Text = "Refresh All Whitelists",
        Func = function()
            refreshAvailableTargets()
            refreshLavaParts() 
            refreshZoneDropdown()
            refreshOreTypesDropdown()
        end,
    })
    
    -- >>> AUTO FARM GROUP <<<

    FarmGroup:AddSlider("AF_OffsetAdjust", {
        Text     = "Extra Offset",
        Min      = -5,
        Max      = 15,
        Default  = 0,
        Rounding = 1,
        Suffix   = " studs",
        Callback = function(value)
            ExtraYOffset = value or 0
            if FarmState.enabled and FarmState.currentTarget and FarmState.attached then
                realignAttach(FarmState.currentTarget)
            end
        end,
    })

    FarmGroup:AddSlider("AF_Speed", {
        Text     = "Flight Speed",
        Min      = 50,
        Max      = 120,
        Default  = FarmSpeed,
        Rounding = 0,
        Suffix   = " studs/s",
        Callback = function(value)
            local v = tonumber(value) or FarmSpeed
            FarmSpeed = math.clamp(v, 5, 120)
        end,
    })

    FarmGroup:AddSlider("AF_MaxTargetHeight", {
        Text     = "Max Target Height",
        Min      = 0,
        Max      = 120,
        Default  = MaxTargetHeight,
        Rounding = 0,
        Suffix   = " studs",
        Callback = function(value)
            local v = tonumber(value) or MaxTargetHeight
            MaxTargetHeight = math.clamp(v, 0, 100)
        end,
    })

    FarmGroup:AddDivider()

    FarmGroup:AddToggle("AF_AvoidLava", {
        Text    = "Avoid Lava",
        Default = false,
        Callback = function(state)
            AvoidLava = state and true or false
            if AvoidLava then
                refreshLavaParts()
            end
        end,
    })
    
    FarmGroup:AddToggle("AF_AttackNearbyMobs", {
        Text    = "Attack Nearby Mobs",
        Default = false,
        Callback = function(state)
            AttackNearbyMobs = state
        end,
    })
    

    FarmGroup:AddToggle("AF_AvoidPlayers", {
        Text    = "Avoid Players",
        Default = false,
        Callback = function(state)
            AvoidPlayers = state
        end,
    })
    
    FarmGroup:AddToggle("AF_DamageDitch", {
        Text    = "Damage Ditch",
        Default = false,
        Callback = function(state)
            DamageDitchEnabled = state
        end,
    })

    FarmGroup:AddSlider("AF_NearbyMobRange", {
        Text     = "Mob Detect Range",
        Tooltip  = "Range we attack mobs at when ore farming",
        Min      = 10,
        Max      = 100,
        Default  = NearbyMobRange,
        Rounding = 0,
        Suffix   = " studs",
        Callback = function(value)
            NearbyMobRange = tonumber(value) or 40
        end,
    })
    
    FarmGroup:AddSlider("AF_PlayerAvoidRadius", {
        Text     = "Player Avoid Range",
        Tooltip  = "Distance we keep from other players",
        Min      = 10,
        Max      = 100,
        Default  = PlayerAvoidRadius,
        Rounding = 0,
        Suffix   = " studs",
        Callback = function(value)
            PlayerAvoidRadius = tonumber(value) or PlayerAvoidRadius
        end,
    })

    FarmGroup:AddSlider("AF_DitchThreshold", {
        Text     = "Ditch Health %",
        Tooltip  = "Level of health we start ditching targets when we take damage",
        Min      = 10,
        Max      = 100,
        Default  = 100,
        Rounding = 0,
        Suffix   = "%",
        Callback = function(value)
            DamageDitchThreshold = tonumber(value) or 100
        end,
    })

    FarmGroup:AddDivider()

    FarmGroup:AddToggle("AF_Enabled", {
        Text    = "Auto Farm",
        Default = false,
        Callback = function(state)
            if state then
                startFarm()
            else
                stopFarm()
            end
        end,
    })

    -- Initial target list + lava parts + Ore types + Zones
    refreshAvailableTargets()
    refreshLavaParts()
    refreshOreTypesDropdown()
    refreshZoneDropdown()
    
    ----------------------------------------------------------------
    -- PROXIMITY TRACKER (SEPARATE HUD SYSTEM)
    ----------------------------------------------------------------
    
    TrackingGroupbox:AddToggle("AF_ProximityTracker", {
        Text    = "Progress Tracker",
        Default = false,
        Callback = function(state)
            TrackerState.Enabled = state
            if state then
                createTrackerGui()
            end
        end,
    })

    ----------------------------------------------------------------
    -- MODULE HANDLE
    ----------------------------------------------------------------

    local H = {}

    function H.Start()
        startFarm()
    end

    function H.Stop()
        stopFarm()
    end

    function H.Unload()
        -- stop farm
        FarmState.enabled = false
        stopMoving()
        FarmState.currentTarget = nil
        FarmState.tempMobTarget = nil
        FarmState.attached      = false
        FarmState.detourActive  = false
        
        disableNoclip()
        
        if TrackerState.Gui then
            TrackerState.Gui:Destroy()
            TrackerState.Gui = nil
        end

        if Toggles.AF_Enabled then
            pcall(function()
                Toggles.AF_Enabled:SetValue(false)
            end)
        end
        if AttachPanel.DestroyAttach then
            pcall(AttachPanel.DestroyAttach)
        end
        restoreAttachSettings()
    end

    return H
end
