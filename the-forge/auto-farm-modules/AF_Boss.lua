-- AF_Boss.lua
-- Boss handling for The Forge autofarm
return function(env)
    local Services          = env.Services or {}
    local Workspace         = env.Workspace or Services.Workspace or workspace
    local Toggles           = env.Toggles
    local AF_Config         = env.AF_Config or {}
    local FarmState         = env.FarmState or {}
    local AttachPanel       = env.AttachPanel
    local MoveToPos         = env.MoveToPos
    local Movement          = env.Movement or {}
    local getLocalHRP       = env.getLocalHRP
    local isMobAlive        = env.isMobAlive
    local getMobRoot        = env.getMobRoot
    local stopMoving        = env.stopMoving
    local dashboardEnabled  = env.dashboardEnabled
    local Dashboard         = env.Dashboard
    local getAttachPosition = env.getAttachPosition

    local function safeStopMoving()
        if stopMoving then
            stopMoving()
        elseif Movement and Movement.stopMoving then
            Movement.stopMoving()
        end
    end

    local function setDashboardTarget(name)
        if dashboardEnabled and dashboardEnabled() and Dashboard and Dashboard.setCurrentTarget then
            Dashboard.setCurrentTarget(name)
        end
    end

    local function getBossMovementMode()
        return AF_Config.BossMovementMode or AF_Config.MovementMode or "Tween"
    end

    local BossState = {
        enabled              = false,
        spawnInProgress      = false,
        bossTarget           = nil,
        lastTimerText        = nil,
        lastReadyAttempt     = 0,
        lastFailedAttempt    = 0,
        initialSpawnAttempted = false,
        watchThread          = nil,
        lastSpawnAttempt     = 0,
        spawnThread          = nil,
        multiBossActive      = false,
        lastBossSeen         = 0,
    }

    local Constants = {
        READY_TEXT       = "30:00",
        SPAWN_TIMEOUT    = 5,
        RETRY_COOLDOWN   = 10,
        ATTACH_WINDOW    = 900,
        DUPE_ITERATIONS  = 120,
        DUPE_YIELD_EVERY = 8,
        CLEAR_TIMEOUT    = 8,
    }

    local PartyActivateRF        = nil
    local ProximityFunctionalsRF = nil

    local function isBossModel(model)
        return model
            and model:IsA("Model")
            and tostring(model.Name):match("^Golem%d+$")
    end

    local function findAliveGolem()
        local living = (Workspace and Workspace:FindFirstChild("Living")) or workspace:FindFirstChild("Living")
        if not living then
            return nil
        end

        local hrp = getLocalHRP and getLocalHRP() or nil
        local best, bestDist
        for _, model in ipairs(living:GetChildren()) do
            if isBossModel(model) and (not isMobAlive or isMobAlive(model)) then
                if not hrp then
                    local root = getMobRoot and getMobRoot(model) or nil
                    if root then
                        return model
                    end
                    continue
                end
                local root = getMobRoot and getMobRoot(model) or nil
                if not root then
                    continue
                end
                local dist = (root.Position - hrp.Position).Magnitude
                if not bestDist or dist < bestDist then
                    bestDist = dist
                    best     = model
                end
            end
        end

        return best
    end

    local function getBossCreateParty()
        local proximity = Workspace and Workspace:FindFirstChild("Proximity")
        return proximity and proximity:FindFirstChild("CreateParty")
    end

    local function getBossTimerLabel()
        local createParty = getBossCreateParty()
        local golem       = createParty and createParty:FindFirstChild("Golem")
        local timer       = golem and golem:FindFirstChild("Timer")
        local container   = timer and timer:FindFirstChild("Container")
        local label       = container and container:FindFirstChild("Label")
        return label
    end

    local function getBossPrompt()
        local createParty = getBossCreateParty()
        return createParty and createParty:FindFirstChild("ProximityPrompt")
    end

    local function resolveBossPromptPart(prompt)
        if not prompt then
            return nil
        end

        local parent = prompt.Parent
        if parent and parent:IsA("Attachment") then
            parent = parent.Parent
        end
        if parent and parent:IsA("BasePart") then
            return parent
        end

        local ok, adornee = pcall(function()
            return prompt.Adornee
        end)
        if ok and adornee and adornee:IsA("BasePart") then
            return adornee
        end

        return nil
    end

    local function isDoBossesToggleOn()
        return Toggles and Toggles.AF_DoBosses and Toggles.AF_DoBosses.Value == true
    end

    local function isBossDupeToggleOn()
        return Toggles and Toggles.AF_BossDupe and Toggles.AF_BossDupe.Value == true
    end

    local function isBossAttachWindowOpen()
        local lastAttempt = BossState.lastSpawnAttempt or 0
        if lastAttempt <= 0 then
            return false
        end
        return (os.clock() - lastAttempt) <= Constants.ATTACH_WINDOW
    end

    local function isBossCleanupActive()
        return isBossAttachWindowOpen() or BossState.multiBossActive == true
    end

    local function markBossSeen(boss)
        if boss then
            BossState.lastBossSeen = os.clock()
            BossState.multiBossActive = true
        end
    end

    local function clearBossTarget(previousBoss)
        if not (previousBoss and FarmState and FarmState.currentTarget == previousBoss) then
            return
        end
        safeStopMoving()
        FarmState.currentTarget    = nil
        FarmState.tempMobTarget    = nil
        FarmState.attached         = false
        FarmState.lastTargetRef    = nil
        FarmState.lastTargetHealth = 0
        setDashboardTarget(nil)
    end

    local function isBossReady()
        local label = getBossTimerLabel()
        local text = label and tostring(label.Text) or BossState.lastTimerText
        return text == Constants.READY_TEXT
    end

    local function getBossPromptTimeout(targetPart)
        local hrp = getLocalHRP and getLocalHRP() or nil
        if not hrp or not targetPart then
            return 6
        end
        if getBossMovementMode() == "Teleport" then
            return 2
        end

        local dist = (hrp.Position - targetPart.Position).Magnitude
        local speed = tonumber(AF_Config.FarmSpeed) or 80
        local travel = dist / math.max(speed, 1)
        return math.clamp(travel + 3, 6, 30)
    end

    local function getReplicatedStorage()
        return Services.ReplicatedStorage or game:GetService("ReplicatedStorage")
    end

    local function resolveBossActivateRF()
        if PartyActivateRF and PartyActivateRF.Parent then
            return PartyActivateRF
        end

        local ok, result = pcall(function()
            return getReplicatedStorage()
                :WaitForChild("Shared")
                :WaitForChild("Packages")
                :WaitForChild("Knit")
                :WaitForChild("Services")
                :WaitForChild("PartyService")
                :WaitForChild("RF")
                :WaitForChild("Activate")
        end)

        if ok then
            PartyActivateRF = result
        end

        return PartyActivateRF
    end

    local function resolveProximityFunctionalsRF()
        if ProximityFunctionalsRF and ProximityFunctionalsRF.Parent then
            return ProximityFunctionalsRF
        end

        local ok, result = pcall(function()
            return getReplicatedStorage()
                :WaitForChild("Shared")
                :WaitForChild("Packages")
                :WaitForChild("Knit")
                :WaitForChild("Services")
                :WaitForChild("ProximityService")
                :WaitForChild("RF")
                :WaitForChild("Functionals")
        end)

        if ok then
            ProximityFunctionalsRF = result
        end

        return ProximityFunctionalsRF
    end

    local function tryBossDupe(prompt)
        if not (isBossDupeToggleOn() and prompt and fireproximityprompt) then
            return false
        end

        local createParty = getBossCreateParty()
        local proximityRF = resolveProximityFunctionalsRF()
        local activateRF  = resolveBossActivateRF()
        if not (createParty and proximityRF and activateRF) then
            return false
        end

        local function fireProximity()
            pcall(function()
                proximityRF:InvokeServer(createParty)
            end)
        end

        local function fireActivate()
            pcall(function()
                activateRF:InvokeServer()
            end)
        end

        for i = 1, Constants.DUPE_ITERATIONS do
            if not BossState.enabled then
                break
            end
            task.spawn(fireProximity)
            task.spawn(fireActivate)
            pcall(fireproximityprompt, prompt)
            if (i % Constants.DUPE_YIELD_EVERY) == 0 then
                task.wait()
            end
        end

        return true
    end

    local function moveToBossPrompt(prompt)
        local hrp = getLocalHRP and getLocalHRP() or nil
        if not hrp or not prompt then
            return nil
        end

        local targetPart = resolveBossPromptPart(prompt)
        if not targetPart then
            return nil
        end

        safeStopMoving()
        if AttachPanel and AttachPanel.DestroyAttach then
            pcall(AttachPanel.DestroyAttach)
        end
        FarmState.attached      = false
        FarmState.tempMobTarget = nil

        local targetPos = targetPart.Position + Vector3.new(0, 3, 0)
        if getBossMovementMode() == "Teleport" then
            hrp.CFrame = CFrame.new(targetPos)
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        elseif MoveToPos then
            FarmState.moveCleanup = MoveToPos(targetPos, AF_Config.FarmSpeed)
        end

        return targetPart
    end

    local function waitForBossPromptReach(targetPart, timeout)
        local hrp = getLocalHRP and getLocalHRP() or nil
        if not hrp or not targetPart then
            return false
        end

        local start = os.clock()
        while os.clock() - start < (timeout or 4) do
            if not BossState.enabled then
                return false
            end
            local dist = (hrp.Position - targetPart.Position).Magnitude
            if dist <= 8 then
                return true
            end
            task.wait(0.05)
        end

        return false
    end

    local function attemptBossSpawn(reason)
        if not BossState.enabled or BossState.spawnInProgress then
            return
        end

        local existingBoss = findAliveGolem()
        if existingBoss then
            markBossSeen(existingBoss)
            if isBossCleanupActive() then
                BossState.bossTarget = existingBoss
            end
            return
        end

        local now = os.clock()
        local lastFail = BossState.lastFailedAttempt or 0
        if (now - lastFail) < Constants.RETRY_COOLDOWN then
            return
        end
        if (now - (BossState.lastSpawnAttempt or 0)) < 2 then
            return
        end
        BossState.lastSpawnAttempt = now
        BossState.spawnInProgress  = true
        BossState.multiBossActive  = true
        BossState.lastBossSeen     = now

        BossState.spawnThread = task.spawn(function()
            local spawned = false
            local ok, err = pcall(function()
                if not BossState.enabled then
                    return
                end

                safeStopMoving()
                if AttachPanel and AttachPanel.DestroyAttach then
                    pcall(AttachPanel.DestroyAttach)
                end
                FarmState.currentTarget = nil
                FarmState.tempMobTarget = nil
                FarmState.attached      = false
                FarmState.detourActive  = false

                local prompt = getBossPrompt()
                if not prompt then
                    BossState.lastFailedAttempt = os.clock()
                    return
                end

                local targetPart = moveToBossPrompt(prompt)
                if not targetPart then
                    BossState.lastFailedAttempt = os.clock()
                    return
                end

                local reached = waitForBossPromptReach(targetPart, getBossPromptTimeout(targetPart))
                if not reached then
                    BossState.lastFailedAttempt = os.clock()
                    return
                end
                safeStopMoving()
                if not BossState.enabled then
                    return
                end

                local preDupeWait = isBossDupeToggleOn() and 0.1 or 1
                task.wait(preDupeWait)
                local duped = tryBossDupe(prompt)
                if not duped then
                    if prompt and fireproximityprompt then
                        pcall(fireproximityprompt, prompt)
                    end
                    if not BossState.enabled then
                        return
                    end

                    task.wait(1)
                    local activateRF = resolveBossActivateRF()
                    if activateRF then
                        pcall(function()
                            activateRF:InvokeServer()
                        end)
                    end
                end

                local start = os.clock()
                while BossState.enabled and (os.clock() - start) < Constants.SPAWN_TIMEOUT do
                    local golem = findAliveGolem()
                    if golem then
                        spawned = true
                        BossState.lastFailedAttempt = 0
                        markBossSeen(golem)
                        BossState.bossTarget      = golem
                        FarmState.currentTarget   = golem
                        FarmState.attached        = false
                        FarmState.tempMobTarget   = nil
                        FarmState.lastTargetRef   = nil
                        FarmState.lastTargetHealth = 0
                        setDashboardTarget(golem.Name)
                        return
                    end
                    task.wait(0.2)
                end

                if not spawned then
                    BossState.lastFailedAttempt = os.clock()
                end
            end)

            if not ok then
                warn("[AutoFarm] Boss spawn error:", err)
            end

            BossState.spawnInProgress = false
            BossState.spawnThread     = nil
        end)
    end

    local function bossWatchLoop()
        while BossState.enabled do
            local label = getBossTimerLabel()
            local text  = label and tostring(label.Text) or nil
            if text == Constants.READY_TEXT then
                local now = os.clock()
                local shouldAttempt = (BossState.lastTimerText ~= Constants.READY_TEXT)
                    or ((now - (BossState.lastReadyAttempt or 0)) >= Constants.RETRY_COOLDOWN)
                if shouldAttempt then
                    BossState.lastReadyAttempt = now
                    attemptBossSpawn("timer")
                end
            end

            if text ~= BossState.lastTimerText then
                BossState.lastTimerText = text
                if text ~= Constants.READY_TEXT then
                    BossState.lastReadyAttempt = 0
                end
            end
            task.wait(0.1)
        end
    end

    local function startBossWatcher()
        if BossState.watchThread then
            return
        end
        BossState.lastTimerText = nil
        BossState.lastReadyAttempt = 0
        BossState.watchThread   = task.spawn(bossWatchLoop)
    end

    local function stopBossWatcher()
        BossState.watchThread = nil
        BossState.lastTimerText = nil
        BossState.lastReadyAttempt = 0
    end

    local function applyBossOffset()
        if not (FarmState.enabled and FarmState.currentTarget and FarmState.attached) then
            return
        end
        if Movement and Movement.realignAttach then
            Movement.realignAttach(FarmState.currentTarget, nil, "Boss")
        end
    end

    local function restoreBossOffset()
        if not (FarmState.enabled and FarmState.currentTarget and FarmState.attached) then
            return
        end
        if Movement and Movement.realignAttach then
            local offsetType = (FarmState.mode == "Ores") and "Ores" or "Mobs"
            if isBossModel(FarmState.currentTarget) then
                offsetType = "Boss"
            end
            Movement.realignAttach(FarmState.currentTarget, nil, offsetType)
        end
    end

    local function nudgeBossAttach(boss, def)
        if not (boss and def and getLocalHRP and getAttachPosition) then
            return
        end
        local hrp = getLocalHRP()
        if not hrp then
            return
        end
        local targetPos, root = getAttachPosition(boss, def, "Boss")
        if not (targetPos and root) then
            return
        end
        if (hrp.Position - targetPos).Magnitude > 6 then
            hrp.CFrame = CFrame.new(targetPos, root.Position)
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end

    return {
        State             = BossState,
        Constants         = Constants,
        isBossModel       = isBossModel,
        findAliveGolem    = findAliveGolem,
        isBossCleanupActive = isBossCleanupActive,
        markBossSeen      = markBossSeen,
        clearBossTarget   = clearBossTarget,
        isBossReady       = isBossReady,
        attemptBossSpawn  = attemptBossSpawn,
        startWatcher      = startBossWatcher,
        stopWatcher       = stopBossWatcher,
        applyOffset       = applyBossOffset,
        restoreOffset     = restoreBossOffset,
        isDoBossesToggleOn = isDoBossesToggleOn,
        nudgeBossAttach   = nudgeBossAttach,
    }
end
