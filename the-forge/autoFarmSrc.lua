return function(ctx)
    local Services   = ctx.Services
    local Tabs       = ctx.Tabs
    local References = ctx.References
    local Library    = ctx.Library
    local Options    = ctx.Options
    local Toggles    = ctx.Toggles
    local META       = ctx.META or {}

    local AttachPanel = ctx.AttachPanel
    local MoveToPos   = ctx.MoveToPos

    local function getLocalHRP()
        return References.humanoidRootPart
    end

    local function notify(msg, time)
        if Library and Library.Notify then
            Library:Notify(msg, time or 3)
        end
    end

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

    local OrePriority = {
        ["Volcanic Rock"] = 1,
        ["Basalt Vein"]   = 2,
        ["Basalt Core"]   = 3,
        ["Basalt Rock"]   = 4,
    }

    local EnemyPriority = {
        ["Blazing Slime"]           = 1,
        ["Elite Deathaxe Skeleton"] = 2,
        ["Reaper"]                  = 3,
        ["Elite Rogue Skeleton"]    = 4,
        ["Deathaxe Skeleton"]       = 5,
        ["Axe Skeleton"]            = 6,
        ["Skeleton Rogue"]          = 7,
        ["Bomber"]                  = 8,
    }

    local function getTargetPriorityForMode(modeName, baseName)
        if modeName == "Ores" then
            return OrePriority[baseName] or 999
        elseif modeName == "Enemies" then
            return EnemyPriority[baseName] or 999
        end
        return 999
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

    local function getRocksFolder()
        return Services.Workspace:FindFirstChild("Rocks")
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
                else
                    local parent = inst.Parent
                    if not (parent and parent ~= rocksFolder and parent:IsA("Model")) then
                        if rockHealth(inst) then
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

    local function getLivingFolder()
        local living = Services.Workspace:FindFirstChild("Living")
        if living and living:IsA("Folder") then
            return living
        end
        return nil
    end

    local function normalizeMobName(name)
        local base = tostring(name or "")
        base = base:gsub("%d+$", "")
        base = base:gsub("%s+$", "")
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

    local ExtraYOffset      = 0
    local FarmSpeed         = 80

    local FARM_MODE_ORES    = "Ores"
    local FARM_MODE_ENEMIES = "Enemies"

    local MaxTargetHeight   = 50

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

    local AvoidLava         = false
    local AvoidPlayers      = false
    local PlayerAvoidRadius = 40

    local TargetBlacklist   = {}

    local FarmState = {
        enabled       = false,
        mode          = FARM_MODE_ORES,
        selectedNames = {},
        nameMap       = {},

        currentTarget = nil,
        moveCleanup   = nil,
        farmThread    = nil,

        attached      = false,
        lastHit       = 0,
        detourActive  = false,
    }

    local function stopMoving()
        if FarmState.moveCleanup then
            pcall(FarmState.moveCleanup)
            FarmState.moveCleanup = nil
        end
    end

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

    local LavaParts = {}

    local function refreshLavaParts()
        table.clear(LavaParts)

        local ws = Services.Workspace
        if not ws then return end

        local assets = ws:FindFirstChild("Assets")
        if not assets then return end

        local cave = assets:FindFirstChild("Cave Area [2]")
        if not cave then return end

        local folder = cave:FindFirstChild("Folder")
        if not folder then return end

        for _, inst in ipairs(folder:GetDescendants()) do
            if inst:IsA("BasePart") and inst.Name == "Lava" then
                table.insert(LavaParts, inst)
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
            local away = hrpPos - closestPos
            away = Vector3.new(away.X, 0, away.Z)
            local mag = away.Magnitude
            if mag < 1 then
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

        local sideDir = ab:Cross(Vector3.yAxis)
        if sideDir.Magnitude < 1e-3 then
            sideDir = Vector3.new(1, 0, 0)
        else
            sideDir = sideDir.Unit
        end

        local offsetDist = PlayerAvoidRadius + 8
        local mid = hitPlayerPos + sideDir * offsetDist
        mid = Vector3.new(mid.X, startPos.Y, mid.Z)

        return { mid, endPos }
    end

    local function chooseNearestTarget()
        local hrp = getLocalHRP()
        if not hrp then return nil end

        local def = ModeDefs[FarmState.mode]
        if not def or not def.scan then return nil end

        local nameMap, _ = def.scan()
        FarmState.nameMap = nameMap or {}

        local selectedLookup = {}
        for _, name in ipairs(FarmState.selectedNames) do
            selectedLookup[name] = true
        end

        local bestTarget
        local bestDist
        local bestPriority = math.huge

        for name, models in pairs(nameMap) do
            if selectedLookup[name] and models then
                local priority = getTargetPriorityForMode(FarmState.mode, name)

                for _, model in ipairs(models) do
                    if model and model.Parent and def.isAlive(model) and not isTargetBlacklisted(model) then
                        local pos = def.getPos(model)

                        if pos then
                            local skip = false

                            if pos.Y > MaxTargetHeight then
                                skip = true
                            end

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

                            if not skip and AvoidPlayers then
                                local nearTarget, _ = isAnyPlayerNearPosition(pos, PlayerAvoidRadius)
                                if nearTarget then
                                    skip = true
                                end
                            end

                            if not skip then
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
        end

        return bestTarget
    end

    local function realignAttach(target)
        if not target then return end

        local def = ModeDefs[FarmState.mode]
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

    local function attachToTarget(target)
        if not target then return end

        configureAttachForMode(FarmState.mode)

        if AttachPanel.SetTarget then
            AttachPanel.SetTarget(target)
        end
        if AttachPanel.CreateAttach then
            AttachPanel.CreateAttach(target)
        end

        realignAttach(target)
    end

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

    local function startMovingToTarget(target)
        stopMoving()

        local hrp = getLocalHRP()
        local def = ModeDefs[FarmState.mode]
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

        local useDetour = (startPos.X < DETOUR_THRESHOLD_X)

        if not useDetour then
            local waypoints = { finalPos }
            if AvoidPlayers then
                waypoints = buildPathAroundPlayers(startPos, finalPos)
            end

            if #waypoints == 1 then
                FarmState.moveCleanup = MoveToPos(finalPos, FarmSpeed, getFinalPos)
            else
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
                        FarmState.moveCleanup = nil
                    end
                end)
            end

            return
        end

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

            local function dynFinalPos()
                return getFinalPos()
            end

            currentCleanup = MoveToPos(fp, FarmSpeed, dynFinalPos)
        end)
    end

    local function farmLoop()
        while FarmState.enabled do
            local hrp = getLocalHRP()
            local hum = References.humanoid

            if not hrp or not hum then
                stopMoving()
                FarmState.currentTarget = nil
                FarmState.attached      = false
                FarmState.detourActive  = false
                task.wait(0.3)
                continue
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
                stopMoving()
                FarmState.currentTarget = nil
                FarmState.attached      = false
                FarmState.detourActive  = false
                task.wait(0.3)
                continue
            end

            if humHealth <= 0 or humState == Enum.HumanoidStateType.Dead then
                stopMoving()
                FarmState.currentTarget = nil
                FarmState.attached      = false
                FarmState.detourActive  = false
                task.wait(0.3)
                continue
            end

            local def = ModeDefs[FarmState.mode]
            if not def then
                task.wait(0.3)
                continue
            end

            local target = FarmState.currentTarget
            local pos    = target and def.getPos(target) or nil
            local alive  = target and def.isAlive(target)

            if (not target)
                or (not target.Parent)
                or (not pos)
                or (not alive)
                or isTargetBlacklisted(target) then

                FarmState.currentTarget = chooseNearestTarget()
                FarmState.attached      = false
                FarmState.detourActive  = false
                target = FarmState.currentTarget

                if target then
                    startMovingToTarget(target)
                    pos = def.getPos(target)
                else
                    stopMoving()
                    if AvoidPlayers then
                        moveAwayFromNearbyPlayers()
                    end
                    task.wait(0.15)
                    continue
                end
            end

            if pos and pos.Y > MaxTargetHeight then
                blacklistTarget(target, 60)

                stopMoving()
                FarmState.currentTarget = nil
                FarmState.attached      = false
                FarmState.detourActive  = false

                local newTarget = chooseNearestTarget()
                if newTarget then
                    FarmState.currentTarget = newTarget
                    FarmState.attached      = false
                    FarmState.detourActive  = false

                    startMovingToTarget(newTarget)
                else
                    if AvoidPlayers then
                        moveAwayFromNearbyPlayers()
                    end
                    task.wait(0.15)
                end

                continue
            end

            if AvoidPlayers and target and pos then
                local nearTarget, _ = isAnyPlayerNearPosition(pos, PlayerAvoidRadius)
                if nearTarget then
                    blacklistTarget(target, 60)

                    stopMoving()
                    FarmState.currentTarget = nil
                    FarmState.attached      = false
                    FarmState.detourActive  = false

                    local newTarget = chooseNearestTarget()
                    if newTarget then
                        FarmState.currentTarget = newTarget
                        FarmState.attached      = false
                        FarmState.detourActive  = false

                        startMovingToTarget(newTarget)
                    else
                        if AvoidPlayers then
                            moveAwayFromNearbyPlayers()
                        end
                        task.wait(0.15)
                    end

                    continue
                end
            end
            if target and not FarmState.attached then
                local hrpPos = hrp.Position
                if hrpPos.X < DETOUR_THRESHOLD_X then
                    if not FarmState.detourActive then
                        FarmState.detourActive = true
                        stopMoving()
                        startMovingToTarget(target)
                    end
                else
                    FarmState.detourActive = false
                end
            else
                FarmState.detourActive = false
            end

            if pos then
                local dist = (pos - hrp.Position).Magnitude

                if dist <= def.hitDistance then
                    stopMoving()

                    if not FarmState.attached then
                        attachToTarget(target)
                        FarmState.attached = true
                    end

                    local now = os.clock()
                    if now - FarmState.lastHit >= def.hitInterval then
                        swingTool(def.toolRemoteArg)
                        FarmState.lastHit = now
                    end
                else
                    if not FarmState.moveCleanup then
                        startMovingToTarget(target)
                    end
                    FarmState.attached = false
                end
            end

            task.wait(0.05)
        end

        stopMoving()
        FarmState.currentTarget = nil
        FarmState.attached      = false
        FarmState.detourActive  = false
    end

    local function startFarm()
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

        if #FarmState.selectedNames == 0 then
            notify("Select at least one target type first.", 3)
            if Toggles.AF_Enabled then
                Toggles.AF_Enabled:SetValue(false)
            end
            return
        end

        saveAttachSettings()
        configureAttachForMode(FarmState.mode)

        stopMoving()
        FarmState.currentTarget = nil
        FarmState.attached      = false
        FarmState.lastHit       = 0
        FarmState.detourActive  = false

        FarmState.enabled       = true
        FarmState.farmThread    = task.spawn(farmLoop)
    end

    local function stopFarm()
        FarmState.enabled = false
        stopMoving()
        FarmState.currentTarget = nil
        FarmState.attached      = false
        FarmState.detourActive  = false

        if AttachPanel.DestroyAttach then
            pcall(AttachPanel.DestroyAttach)
        end

        restoreAttachSettings()
    end

    local AutoTab   = Tabs["Auto"] or Tabs.Main
    local FarmGroup = AutoTab:AddLeftGroupbox("Auto Farm", "pickaxe")

    local ModeDropdown
    local TargetDropdown

    local function refreshTargetDropdown()
        if not TargetDropdown then return end
        local def = ModeDefs[FarmState.mode]
        if not def or not def.scan then
            TargetDropdown:SetValues({})
            return
        end
        local _, names = def.scan()
        TargetDropdown:SetValues(names)
    end

    ModeDropdown = FarmGroup:AddDropdown("AF_Mode", {
        Text    = "Farm Mode",
        Values  = { FARM_MODE_ORES, FARM_MODE_ENEMIES },
        Default = FarmState.mode,
        Callback = function(value)
            if FarmState.mode == value then
                return
            end
            FarmState.mode = value
            FarmState.selectedNames = {}
            refreshTargetDropdown()

            if FarmState.enabled then
                stopFarm()
                startFarm()
            end
        end,
    })

    TargetDropdown = FarmGroup:AddDropdown("AF_Targets", {
        Text   = "Target Types",
        Values = {},
        Multi  = true,
        Callback = function(selectedTable)
            local list = {}
            for name, selected in pairs(selectedTable) do
                if selected then
                    list[#list + 1] = name
                end
            end
            FarmState.selectedNames = list
        end,
    })

    FarmGroup:AddButton({
        Text = "Refresh Targets",
        Func = function()
            refreshTargetDropdown()
            refreshLavaParts()
        end,
    })

    FarmGroup:AddSlider("AF_OffsetAdjust", {
        Text     = "Extra Offset",
        Min      = -5,
        Max      = 5,
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
        Max      = 100,
        Default  = MaxTargetHeight,
        Rounding = 0,
        Suffix   = " studs",
        Callback = function(value)
            local v = tonumber(value) or MaxTargetHeight
            MaxTargetHeight = math.clamp(v, 0, 100)
        end,
    })

    FarmGroup:AddToggle("AF_AvoidLava", {
        Text    = "Avoid Lava",
        Default = false,
        Tooltip = "Skips targets whose attach position is inside lava. Turn off to completely ignore lava.",
        Callback = function(state)
            AvoidLava = state and true or false
            if AvoidLava then
                refreshLavaParts()
            end
        end,
    })

    FarmGroup:AddToggle("AF_AvoidPlayers", {
        Text    = "Avoid Players",
        Default = false,
        Tooltip = "Ditches and blacklists current target if any player gets too close.",
        Callback = function(state)
            AvoidPlayers = state
        end,
    })

    FarmGroup:AddSlider("AF_PlayerAvoidRadius", {
        Text     = "Player Avoid Range",
        Min      = 10,
        Max      = 100,
        Default  = PlayerAvoidRadius,
        Rounding = 0,
        Suffix   = " studs",
        Callback = function(value)
            PlayerAvoidRadius = tonumber(value) or PlayerAvoidRadius
        end,
    })

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

    refreshTargetDropdown()
    refreshLavaParts()

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
        FarmState.attached      = false
        FarmState.detourActive  = false

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
