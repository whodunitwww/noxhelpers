-- AF_Movement.lua
-- Manages AttachPanel configuration and movement towards targets (including detour logic)
return function(env)
    local AttachPanel  = env.AttachPanel
    local MoveToPos    = env.MoveToPos
    local getLocalHRP  = env.getLocalHRP
    local FarmState    = env.FarmState
    local AF_Config    = env.AF_Config
    local Services     = env.Services or {}
    local References   = env.References or {}
    local Players      = Services.Players or game:GetService("Players")

    -- Attach settings constants
    local ORE_ATTACH_MODE   = "Aligned"
    local ORE_ATTACH_Y_BASE = -8
    local ORE_ATTACH_HORIZ  = 0
    local ORE_HIT_INTERVAL  = 0.15
    local ORE_HIT_DIST      = 20

    local MOB_ATTACH_MODE   = "Aligned"
    local MOB_ATTACH_Y_BASE = -7
    local MOB_ATTACH_HORIZ  = 0
    local MOB_HIT_INTERVAL  = 0.15
    local MOB_HIT_DIST      = 20

    -- Detour path constants
    local DETOUR_ENABLED     = (game.PlaceId == 129009554587176)
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
            dodgeRange  = state.dodgeRange
        }
    end

    local function restoreAttachSettings()
        if not SavedAttach then return end
        if AttachPanel.SetMode then AttachPanel.SetMode(SavedAttach.mode) end
        if AttachPanel.SetYOffset then AttachPanel.SetYOffset(SavedAttach.yOffset) end
        if AttachPanel.SetHorizDist then AttachPanel.SetHorizDist(SavedAttach.horizDist) end
        if AttachPanel.SetMovement then AttachPanel.SetMovement(SavedAttach.movement) end
        if AttachPanel.EnableAutoYOffset then AttachPanel.EnableAutoYOffset(SavedAttach.autoYOffset) end
        if AttachPanel.EnableDodge then AttachPanel.EnableDodge(SavedAttach.dodgeMode) end
        local state = AttachPanel.State
        if state then state.dodgeRange = SavedAttach.dodgeRange end
        SavedAttach = nil
    end

    local function configureAttachForMode(modeName)
        if modeName == "Ores" then
            local y = ORE_ATTACH_Y_BASE + AF_Config.ExtraYOffset
            if AttachPanel.SetMode then AttachPanel.SetMode(ORE_ATTACH_MODE) end
            if AttachPanel.SetYOffset then AttachPanel.SetYOffset(y) end
            if AttachPanel.SetHorizDist then AttachPanel.SetHorizDist(ORE_ATTACH_HORIZ) end
        elseif modeName == "Enemies" then
            local y = MOB_ATTACH_Y_BASE + AF_Config.ExtraYOffset
            if AttachPanel.SetMode then AttachPanel.SetMode(MOB_ATTACH_MODE) end
            if AttachPanel.SetYOffset then AttachPanel.SetYOffset(y) end
            if AttachPanel.SetHorizDist then AttachPanel.SetHorizDist(MOB_ATTACH_HORIZ) end
        end
        if AttachPanel.SetMovement then AttachPanel.SetMovement("Approach") end
        if AttachPanel.EnableAutoYOffset then AttachPanel.EnableAutoYOffset(false) end
        if AttachPanel.EnableDodge then AttachPanel.EnableDodge(false) end
    end

    local function stopMoving()
        if FarmState.moveCleanup then
            pcall(FarmState.moveCleanup)
            FarmState.moveCleanup = nil
        end
    end

    local function safeComputeOffset(rootCFrame, modeName)
        local baseY = (modeName == "Ores") and ORE_ATTACH_Y_BASE or MOB_ATTACH_Y_BASE
        if not AttachPanel or not AttachPanel.ComputeOffset then
            return Vector3.new(0, baseY + AF_Config.ExtraYOffset, 0)
        end
        local attachMode  = (modeName == "Ores") and ORE_ATTACH_MODE or MOB_ATTACH_MODE
        local attachHoriz = (modeName == "Ores") and ORE_ATTACH_HORIZ or MOB_ATTACH_HORIZ
        local offsetYBase = baseY + AF_Config.ExtraYOffset
        local ok, result = pcall(AttachPanel.ComputeOffset, rootCFrame, attachMode, attachHoriz, offsetYBase)
        if ok and typeof(result) == "Vector3" then
            return result 
        end
        return Vector3.new(0, baseY + AF_Config.ExtraYOffset, 0)
    end

    local function realignAttach(target, overrideDef)
        if not target then return end
        local modeName = overrideDef and overrideDef.name or FarmState.mode
        local state = AttachPanel.State
        if not state then return end
        local attachA1 = state._attachA1
        local alignOri = state._alignOri
        local hrp      = getLocalHRP()
        local rootPart = (overrideDef and overrideDef.getRoot and overrideDef.getRoot(target)) or target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart or target
        if not (attachA1 and alignOri and hrp and rootPart) then return end

        local offsetWorld = safeComputeOffset(rootPart.CFrame, modeName)
        attachA1.Position = rootPart.CFrame:VectorToObjectSpace(offsetWorld)
        alignOri.CFrame = CFrame.lookAt(hrp.Position, rootPart.Position, Vector3.yAxis)
    end

    local function attachToTarget(target, overrideDef)
        if not target then return end
        if overrideDef then
            if AttachPanel.SetMode then AttachPanel.SetMode(overrideDef.attachMode) end
            if AttachPanel.SetYOffset then AttachPanel.SetYOffset(overrideDef.attachBaseY + AF_Config.ExtraYOffset) end
            if AttachPanel.SetHorizDist then AttachPanel.SetHorizDist(overrideDef.attachHoriz) end
        else
            configureAttachForMode(FarmState.mode)
        end
        if AttachPanel.SetTarget then AttachPanel.SetTarget(target) end
        if AttachPanel.CreateAttach then AttachPanel.CreateAttach(target) end
        realignAttach(target, overrideDef)
    end

    local function startMovingToTarget(target, overrideDef)
        if AttachPanel.DestroyAttach then pcall(AttachPanel.DestroyAttach) end
        stopMoving()
        local hrp = getLocalHRP()
        local def = overrideDef or nil  -- def is not heavily used in this version
        if not hrp then return end

        local function getFinalPos()
            if not target or not target.Parent then return nil end
            local root = (def and def.getRoot and def.getRoot(target)) or target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart or target
            if not root then return nil end
            local modeName = overrideDef and overrideDef.name or FarmState.mode
            return root.Position + safeComputeOffset(root.CFrame, modeName)
        end

        local startPos = hrp.Position
        local finalPos = getFinalPos()
        if not finalPos then return end

        FarmState.lastMovePos = startPos
        FarmState.lastMoveTime = os.clock()

        local useDetour = DETOUR_ENABLED and (startPos.X < DETOUR_THRESHOLD_X)
        if not useDetour then
            local waypoints = { finalPos }
            if AF_Config.AvoidPlayers then
                -- Compute path around nearby player (if any)
                local ab = finalPos - startPos
                if ab.Magnitude >= 5 then
                    local hitPlayerPos = nil
                    local closestHitDist = math.huge
                    for _, plr in ipairs(Players:GetPlayers()) do
                        local myPlayer = References.player or Players.LocalPlayer
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
                                if dist <= AF_Config.PlayerAvoidRadius and dist < closestHitDist then
                                    closestHitDist = dist
                                    hitPlayerPos   = p
                                end
                            end
                        end
                    end
                    if hitPlayerPos then
                        local sideDir = ab:Cross(Vector3.yAxis)
                        if sideDir.Magnitude < 1e-3 then 
                            sideDir = Vector3.new(1, 0, 0) 
                        else 
                            sideDir = sideDir.Unit 
                        end
                        local offsetDist = AF_Config.PlayerAvoidRadius + 8
                        local mid = hitPlayerPos + sideDir * offsetDist
                        mid = Vector3.new(mid.X, startPos.Y, mid.Z)
                        waypoints = { mid, finalPos }
                    end
                end
            end

            if #waypoints == 1 then
                FarmState.moveCleanup = MoveToPos(finalPos, AF_Config.FarmSpeed, getFinalPos)
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
                        currentCleanup = MoveToPos(waypoint, AF_Config.FarmSpeed)
                        local wpStart = os.clock()
                        while active do
                            local h = getLocalHRP()
                            if not h then
                                if currentCleanup then pcall(currentCleanup) end
                                return
                            end
                            if (h.Position - waypoint).Magnitude <= 3 then
                                if currentCleanup then pcall(currentCleanup) end
                                break
                            end
                            if (os.clock() - wpStart) > 5 then
                                if currentCleanup then pcall(currentCleanup) end
                                break
                            end
                            task.wait(0.05)
                        end
                    end
                    if active then FarmState.moveCleanup = nil end
                end)
                -- No direct return here, allow function to proceed to end in non-detour case
            end
            return
        end

        -- Detour path logic (if useDetour == true)
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
                currentCleanup = MoveToPos(waypoint, AF_Config.FarmSpeed)
                local wpStart = os.clock()
                while active do
                    local h = getLocalHRP()
                    if not h then
                        if currentCleanup then pcall(currentCleanup) end
                        return
                    end
                    if (h.Position - waypoint).Magnitude <= 3 then
                        if currentCleanup then pcall(currentCleanup) end
                        break
                    end
                    if (os.clock() - wpStart) > 8 then
                        if currentCleanup then pcall(currentCleanup) end
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
            currentCleanup = MoveToPos(fp, AF_Config.FarmSpeed, function() return getFinalPos() end)
        end)
    end

    return {
        configureAttachForMode = configureAttachForMode,
        saveAttachSettings     = saveAttachSettings,
        restoreAttachSettings  = restoreAttachSettings,
        stopMoving             = stopMoving,
        realignAttach          = realignAttach,
        attachToTarget         = attachToTarget,
        startMovingToTarget    = startMovingToTarget
    }
end
