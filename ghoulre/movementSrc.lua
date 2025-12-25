return function(ctx)
    local Services = ctx.Services
    local Tabs = ctx.Tabs
    local References = ctx.References
    local Library = ctx.Library
    local Options = ctx.Options
    local Toggles = ctx.Toggles
    local LPH_NO_VIRTUALIZE = ctx.LPH_NO_VIRTUALIZE or function(f)
        return f
    end

    local W = {}

    -- ==== FLIGHT ==== --
    local FlightGroup = Tabs.Player:AddLeftGroupbox("Flight", "move-3d")

    FlightGroup:AddToggle("FlightEnabled", {
        Text = "Flight",
        Default = false
    }):AddKeyPicker("FlightKey", {
        Default = "Y",
        SyncToggleState = true,
        Mode = "Toggle"
    })
    FlightGroup:AddSlider("FlightSpeed", {
        Text = "Flight Speed",
        Default = 80,
        Min = 30,
        Max = 100,
        Rounding = 0
    })

    local flightConn
    local function startFlight()
        if flightConn then
            return
        end
        Library:Notify("Flight enabled.", 2)
        flightConn = Services.RunService.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
            if not References.humanoidRootPart or not References.camera then
                return
            end
            local cframe = References.camera.CFrame
            local look, right, up = cframe.LookVector, cframe.RightVector, cframe.UpVector
            local dir = Vector3.zero
            local KC = Enum.KeyCode

            if Services.UserInputService:IsKeyDown(KC.W) then
                dir = dir + look
            end
            if Services.UserInputService:IsKeyDown(KC.S) then
                dir = dir - look
            end
            if Services.UserInputService:IsKeyDown(KC.A) then
                dir = dir - right
            end
            if Services.UserInputService:IsKeyDown(KC.D) then
                dir = dir + right
            end
            if Services.UserInputService:IsKeyDown(KC.Space) then
                dir = dir + up
            end
            if Services.UserInputService:IsKeyDown(KC.LeftShift) or Services.UserInputService:IsKeyDown(KC.LeftControl) then
                dir = dir - up
            end

            if References.humanoid and Services.UserInputService.TouchEnabled then
                local md = References.humanoid.MoveDirection
                if md.Magnitude > 0 then
                    dir = dir + (look * md.Z * -1) + (right * md.X)
                end
            end

            local v = Options.FlightSpeed.Value
            if dir.Magnitude > 0 then
                References.humanoidRootPart.AssemblyAngularVelocity = Vector3.zero
                References.humanoidRootPart.AssemblyLinearVelocity = dir.Unit * v
            else
                References.humanoidRootPart.AssemblyAngularVelocity = Vector3.zero
                References.humanoidRootPart.AssemblyLinearVelocity = Vector3.new(0, 2.2, 0)
            end
        end))
    end

    local function stopFlight()
        if flightConn then
            Library:Notify("Flight disabled.", 2)
            flightConn:Disconnect()
            flightConn = nil
            if References.humanoidRootPart then
                References.humanoidRootPart.AssemblyAngularVelocity = Vector3.zero
                References.humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
            end
        end
    end

    Toggles.FlightEnabled:OnChanged(function()
        if Toggles.FlightEnabled.Value then
            startFlight()
        else
            stopFlight()
        end
    end)

    -- ==== SPEED ==== --
    local SpeedGroup = Tabs.Player:AddLeftGroupbox("Speed", "move")

    SpeedGroup:AddToggle("SpeedEnabled", {
        Text = "Speed",
        Default = false
    }):AddKeyPicker("SpeedKey", {
        Default = "G",
        SyncToggleState = true,
        Mode = "Toggle"
    })
    SpeedGroup:AddSlider("SpeedValue", {
        Text = "Speed Value",
        Default = 30,
        Min = 16,
        Max = 300,
        Rounding = 0
    })

    local speedConn
    local function startSpeed()
        if speedConn then
            return
        end
        Library:Notify("Speed enabled.", 2)
        speedConn = Services.RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
            if References.humanoid then
                local v = Options.SpeedValue.Value
                References.humanoid.WalkSpeed = v
            end
        end))
    end

    local function stopSpeed()
        if speedConn then
            Library:Notify("Speed disabled.", 2)
            speedConn:Disconnect()
            speedConn = nil
        end
        if References.humanoid then
            References.humanoid.WalkSpeed = 16
        end
    end

    Toggles.SpeedEnabled:OnChanged(function()
        if Toggles.SpeedEnabled.Value then
            startSpeed()
        else
            stopSpeed()
        end
    end)

    -- ==== JUMP POWER ==== --
    local JumpGroup = Tabs.Player:AddLeftGroupbox("Jump", "move-vertical")

    JumpGroup:AddToggle("JumpPower", {
        Text = "Jump Power",
        Default = false
    })
    JumpGroup:AddSlider("JumpHeight", {
        Text = "Jump Height",
        Default = 7.2,
        Min = 5,
        Max = 100,
        Rounding = 1
    })
    JumpGroup:AddToggle("InfiniteJump", {
        Text = "Infinite Jump",
        Default = false
    })

    local function applyJumpHeight()
        if not References.humanoid then
            return
        end
        local desiredHeight = tonumber(Options.JumpHeight.Value) or 50
        local g = workspace.Gravity or 196.2
        local jumpPower = math.sqrt(math.max(0, 2 * g * desiredHeight))
        if References.humanoid.UseJumpPower ~= nil then
            References.humanoid.UseJumpPower = true
        end
        if References.humanoid.JumpPower ~= nil then
            References.humanoid.JumpPower = jumpPower
        end
    end

    local _orig = nil
    local jumpConn
    local function startJumpMod()
        if jumpConn then
            return
        end
        local hum = References.humanoid
        if hum and not _orig then
            _orig = {
                UseJumpPower = hum.UseJumpPower,
                JumpPower = hum.JumpPower,
                JumpHeight = hum.JumpHeight
            }
        end
        applyJumpHeight()
        jumpConn = Services.RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
            applyJumpHeight()
        end))
    end

    local function stopJumpMod()
        if jumpConn then
            jumpConn:Disconnect();
            jumpConn = nil
        end
        local hum = References.humanoid
        if hum and _orig then
            if hum.UseJumpPower ~= nil then
                hum.UseJumpPower = _orig.UseJumpPower
            end
            if hum.JumpPower ~= nil then
                hum.JumpPower = _orig.JumpPower
            end
            if hum.JumpHeight ~= nil then
                hum.JumpHeight = _orig.JumpHeight
            end
        end
    end

    local ijConn, ijBusy = nil, false
    local function startInfiniteJump()
        if ijConn then
            return
        end
        ijConn = Services.UserInputService.JumpRequest:Connect(LPH_NO_VIRTUALIZE(function()
            if not Toggles.InfiniteJump.Value then
                return
            end
            local hum = References.humanoid
            if not hum or ijBusy then
                return
            end
            ijBusy = true
            task.defer(function()
                pcall(function()
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    hum.Jump = true
                end)
                task.wait()
                ijBusy = false
            end)
        end))
    end

    local function stopInfiniteJump()
        if ijConn then
            ijConn:Disconnect();
            ijConn = nil
        end
        ijBusy = false
    end

    Toggles.JumpPower:OnChanged(function()
        if Toggles.JumpPower.Value then
            startJumpMod()
        else
            stopJumpMod()
        end
    end)

    Options.JumpHeight:OnChanged(function()
        if Toggles.JumpPower.Value then
            applyJumpHeight()
        end
    end)

    Toggles.InfiniteJump:OnChanged(function()
        if Toggles.InfiniteJump.Value then
            startInfiniteJump()
        else
            stopInfiniteJump()
        end
    end)

    -- ==== CLICK TO TP ==== --
    local ClickTPGroup = Tabs.Player:AddLeftGroupbox("Click Teleport", "mouse-pointer-click")

    ClickTPGroup:AddToggle("ClickTPEnabled", {
        Text = "Click To Teleport",
        Default = false,
        Tooltip = "Hold the chosen key and right-click anywhere to instantly teleport there."
    }):AddKeyPicker("ClickTPKey", {
        Default = "Q",
        SyncToggleState = false,
        Mode = "Hold"
    })

    local clickTPConn
    local function startClickTP()
        if clickTPConn then
            return
        end
        clickTPConn = Services.UserInputService.InputBegan:Connect(function(input, gp)
            if gp then
                return
            end
            if input.UserInputType == Enum.UserInputType.MouseButton2 and
                Services.UserInputService:IsKeyDown(Enum.KeyCode[Options.ClickTPKey.Value]) then
                local mousePos = Services.UserInputService:GetMouseLocation()
                local unitRay = References.camera:ViewportPointToRay(mousePos.X, mousePos.Y)
                local raycast = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, RaycastParams.new())
                if raycast and References.humanoidRootPart then
                    References.humanoidRootPart.CFrame = CFrame.new(raycast.Position + Vector3.new(0, 3, 0))
                end
            end
        end)
    end

    local function stopClickTP()
        if clickTPConn then
            clickTPConn:Disconnect();
            clickTPConn = nil
        end
    end

    Toggles.ClickTPEnabled:OnChanged(function()
        if Toggles.ClickTPEnabled.Value then
            startClickTP()
        else
            stopClickTP()
        end
    end)

    Options.ClickTPKey:OnChanged(function()
    end)

    local CTWGroup = Tabs.Player:AddLeftGroupbox("Click To Walk", "mouse-pointer")

    CTWGroup:AddToggle("ClickToWalk", {
        Text = "Enable Click To Walk",
        Default = false
    })
    CTWGroup:AddSlider("CTW_Speed", {
        Text = "Walk Speed",
        Default = 16,
        Min = 8,
        Max = 300,
        Rounding = 0,
        Suffix = " studs/s"
    })

    -- === Tunables ===
    local MAX_HOP_DISTANCE = 700
    local MIN_REPATH_INTERVAL = 0.30
    local lastComputeAt = 0

    -- === State ===
    local clickConn, moveConn, blockedConn, spinConn
    local pathObj
    local segmentFolder
    local beaconFolder
    local currentDest
    local checkpoints = nil
    local segIndex = 0

    local isClickMoving = false
    local origWalkSpeed = nil

    -- interrupt connections (keyboard/gamepad/character/humanoid)
    local interruptConns = {}

    -- === Utils ===
    local function applyCTWSpeed()
        local hum = References.humanoid
        if not hum then
            return
        end
        if origWalkSpeed == nil then
            origWalkSpeed = hum.WalkSpeed
        end
        hum.WalkSpeed = Options.CTW_Speed.Value
    end

    local function restoreWalkSpeed()
        local hum = References.humanoid
        if hum and origWalkSpeed ~= nil then
            hum.WalkSpeed = origWalkSpeed
        end
        origWalkSpeed = nil
    end

    local function fadeAndDestroy(folder)
        if not folder then
            return
        end
        for _, inst in ipairs(folder:GetDescendants()) do
            if inst:IsA("BasePart") then
                Services.TweenService:Create(inst, TweenInfo.new(0.25), {
                    Transparency = 1
                }):Play()
            end
        end
        task.delay(0.3, function()
            pcall(function()
                if folder then
                    folder:Destroy()
                end
            end)
        end)
    end

    local function clearBeacon()
        if spinConn then
            spinConn:Disconnect();
            spinConn = nil
        end
        if beaconFolder then
            fadeAndDestroy(beaconFolder);
            beaconFolder = nil
        end
    end

    local function clearPathViz()
        if segmentFolder then
            fadeAndDestroy(segmentFolder);
            segmentFolder = nil
        end
    end

    local function clearAllViz()
        clearBeacon()
        clearPathViz()
    end

    local function haltHumanoidMotion()
        local hum, root = References.humanoid, References.humanoidRootPart
        if hum then
            -- Stop the current MoveTo request by sending a tiny MoveTo to current position.
            pcall(function()
                if root then
                    hum:MoveTo(root.Position)
                end
            end)
            -- Also zero desired movement
            pcall(function()
                hum:Move(Vector3.zero)
            end)
        end
    end

    local function disconnectMovePathConns()
        if moveConn then
            moveConn:Disconnect();
            moveConn = nil
        end
        if blockedConn then
            blockedConn:Disconnect();
            blockedConn = nil
        end
        pathObj = nil
    end

    local function disconnectInterrupts()
        for k, c in pairs(interruptConns) do
            if c then
                c:Disconnect()
            end
            interruptConns[k] = nil
        end
    end

    -- Cancel ONLY the active walk, keep the click listener if toggle is still on.
    local function cancelActiveWalk()
        if not isClickMoving then
            clearAllViz()
            disconnectMovePathConns()
            restoreWalkSpeed()
            disconnectInterrupts()
            currentDest, checkpoints, segIndex = nil, nil, 0
            return
        end

        isClickMoving = false
        haltHumanoidMotion()
        clearAllViz()
        disconnectMovePathConns()
        restoreWalkSpeed()
        disconnectInterrupts()
        currentDest, checkpoints, segIndex = nil, nil, 0
    end

    -- Full stop including click listener (used when toggle turns OFF)
    local function stopClickWalk()
        cancelActiveWalk()
        if clickConn then
            clickConn:Disconnect();
            clickConn = nil
        end
    end

    local function createBeacon(pos)
        clearBeacon()

        beaconFolder = Instance.new("Folder")
        beaconFolder.Name = "CTW_Beacon"
        beaconFolder.Parent = workspace

        local pillar = Instance.new("Part")
        pillar.Name = "Pillar"
        pillar.Anchored, pillar.CanCollide = true, false
        pillar.Material = Enum.Material.Neon
        pillar.Color = Color3.fromRGB(55, 235, 120)
        pillar.Size = Vector3.new(0.25, 12, 0.25)
        pillar.CFrame = CFrame.new(pos + Vector3.new(0, pillar.Size.Y / 2, 0))
        pillar.Parent = beaconFolder

        local ring = Instance.new("Part")
        ring.Name = "Ring"
        ring.Shape = Enum.PartType.Cylinder
        ring.Anchored, ring.CanCollide = true, false
        ring.Material = Enum.Material.Neon
        ring.Color = Color3.fromRGB(55, 235, 120)
        ring.Size = Vector3.new(2, 0.2, 2)
        ring.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(90), 0, 0)
        ring.Parent = beaconFolder

        local glow = Instance.new("Part")
        glow.Name = "Glow"
        glow.Anchored, glow.CanCollide = true, false
        glow.Material = Enum.Material.Neon
        glow.Color = Color3.fromRGB(55, 235, 120)
        glow.Transparency = 0.5
        glow.Size = Vector3.new(1.5, 0.15, 1.5)
        glow.CFrame = CFrame.new(pos + Vector3.new(0, 0.05, 0))
        glow.Parent = beaconFolder

        Services.TweenService:Create(ring,
            TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1, true), {
                Size = Vector3.new(6, ring.Size.Y, 6)
            }):Play()
        Services.TweenService:Create(pillar,
            TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
                Transparency = 0.25
            }):Play()

        local theta = 0
        spinConn = Services.RunService.Heartbeat:Connect(function(dt)
            if not ring or not ring.Parent then
                return
            end
            theta = theta + dt * math.pi / 2
            ring.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(90), theta, 0)
        end)
    end

    local function drawPath(waypoints)
        clearPathViz()

        segmentFolder = Instance.new("Folder")
        segmentFolder.Name = "CTW_Path"
        segmentFolder.Parent = workspace

        for i = 1, #waypoints do
            local wp = Instance.new("Part")
            wp.Name = "CTW_Waypoint"
            wp.Anchored, wp.CanCollide = true, false
            wp.Material = Enum.Material.Neon
            wp.Color = Color3.fromRGB(55, 235, 120)
            wp.Size = Vector3.new(0.35, 0.35, 0.35)
            wp.Shape = Enum.PartType.Ball
            wp.CFrame = CFrame.new(waypoints[i].Position + Vector3.new(0, 0.15, 0))
            wp.Parent = segmentFolder
        end

        for i = 1, #waypoints - 1 do
            local a, b = waypoints[i].Position, waypoints[i + 1].Position
            local seg = Instance.new("Part")
            seg.Name = "CTW_Segment"
            seg.Anchored, seg.CanCollide = true, false
            seg.Material = Enum.Material.Neon
            seg.Color = Color3.fromRGB(55, 235, 120)
            seg.Size = Vector3.new(0.15, 0.15, (a - b).Magnitude)
            seg.CFrame = CFrame.new((a + b) / 2, b)
            seg.Transparency = 1
            seg.Parent = segmentFolder
            Services.TweenService:Create(seg, TweenInfo.new(0.2), {
                Transparency = 0
            }):Play()
        end
    end

    local function buildCheckpoints(startPos, dest)
        local delta = dest - startPos
        local dist = delta.Magnitude
        if dist < 1 then
            return {dest}
        end
        local dir = delta.Unit
        local pts, covered = {}, 0
        while covered + MAX_HOP_DISTANCE < dist do
            covered = covered + MAX_HOP_DISTANCE
            pts[#pts + 1] = startPos + dir * covered
        end
        pts[#pts + 1] = dest
        return pts
    end

    local function safeCompute(path, a, b)
        -- throttle computation a bit
        local now = os.clock()
        local waitLeft = MIN_REPATH_INTERVAL - (now - lastComputeAt)
        if waitLeft > 0 then
            task.wait(waitLeft)
        end
        lastComputeAt = os.clock()
        local ok, err = pcall(function()
            path:ComputeAsync(a, b)
        end)
        if not ok then
            return false, err
        end
        return true
    end

    -- === Interrupt wiring ===
    local function wireInterrupts()
        disconnectInterrupts()

        -- Manual movement keys cancel (WASD). Not listening for Space to allow jumping without cancel.
        interruptConns.WASD = Services.UserInputService.InputBegan:Connect(function(input, gp)
            if gp then
                return
            end
            local kc = input.KeyCode
            if kc == Enum.KeyCode.W or kc == Enum.KeyCode.A or kc == Enum.KeyCode.S or kc == Enum.KeyCode.D then
                cancelActiveWalk()
            end
        end)

        -- Gamepad stick movement cancels
        interruptConns.GP = Services.UserInputService.InputChanged:Connect(function(input, gp)
            if gp then
                return
            end
            if input.UserInputType == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.Thumbstick1 then
                if input.Position.Magnitude > 0.15 then
                    cancelActiveWalk()
                end
            end
        end)

        -- Right click cancels (handy UX)
        interruptConns.RMB = Services.UserInputService.InputBegan:Connect(function(input, gp)
            if gp then
                return
            end
            if input.UserInputType == Enum.UserInputType.MouseButton2 then
                cancelActiveWalk()
            end
        end)

        -- Character/humanoid lifecycle cancels
        if References.player then
            interruptConns.CharAdded = References.player.CharacterAdded:Connect(function()
                cancelActiveWalk()
            end)
        end

        local hum = References.humanoid
        if hum then
            interruptConns.Died = hum.Died:Connect(cancelActiveWalk)
            interruptConns.Seated = hum.Seated:Connect(function(active)
                if active then
                    cancelActiveWalk()
                end
            end)
            interruptConns.Ancestry = hum.AncestryChanged:Connect(function(_, parent)
                if parent == nil then
                    cancelActiveWalk()
                end
            end)
        end
    end

    -- === Segment compute + walk ===
    local function computeSegmentAndWalk(segStart, segEnd)
        if not isClickMoving then
            return
        end

        local p = Services.PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
            WaypointSpacing = 4
        })
        pathObj = p

        local ok = safeCompute(p, segStart, segEnd)
        if not ok or p.Status ~= Enum.PathStatus.Success then
            -- try a shorter hop
            local half = segStart:Lerp(segEnd, 0.5)
            ok = safeCompute(p, segStart, half)
            if not ok or p.Status ~= Enum.PathStatus.Success then
                Library:Notify("Unable to compute path.", 3)
                cancelActiveWalk()
                return
            else
                if checkpoints then
                    table.insert(checkpoints, segIndex, half)
                end
            end
        end

        if not isClickMoving then
            return
        end

        local wps = p:GetWaypoints()
        if #wps == 0 then
            Library:Notify("No waypoints for this segment.", 3)
            cancelActiveWalk()
            return
        end
        drawPath(wps)

        if blockedConn then
            blockedConn:Disconnect();
            blockedConn = nil
        end
        blockedConn = p.Blocked:Connect(function()
            if not isClickMoving then
                return
            end
            local root = References.humanoidRootPart
            if root and currentDest and checkpoints then
                computeSegmentAndWalk(root.Position, checkpoints[segIndex])
            end
        end)

        if moveConn then
            moveConn:Disconnect();
            moveConn = nil
        end
        local i = 1
        local hum = References.humanoid
        if not hum then
            cancelActiveWalk();
            return
        end

        hum:MoveTo(wps[i].Position)
        moveConn = hum.MoveToFinished:Connect(function(reached)
            if not isClickMoving then
                return
            end
            if pathObj ~= p then
                return
            end

            if not reached then
                local root = References.humanoidRootPart
                if root and checkpoints then
                    computeSegmentAndWalk(root.Position, checkpoints[segIndex])
                else
                    cancelActiveWalk()
                end
                return
            end

            i = i + 1
            if wps[i] then
                hum:MoveTo(wps[i].Position)
            else
                segIndex = segIndex + 1
                if checkpoints and checkpoints[segIndex] then
                    local root = References.humanoidRootPart
                    if root then
                        computeSegmentAndWalk(root.Position, checkpoints[segIndex])
                    else
                        cancelActiveWalk()
                    end
                else
                    -- Destination reached
                    cancelActiveWalk()
                end
            end
        end)
    end

    -- === Start listening for clicks (when toggle ON) ===
    local function startClickListener()
        if clickConn then
            return
        end
        clickConn = Services.UserInputService.InputBegan:Connect(function(input, gp)
            if gp then
                return
            end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end

            local mouse = References.player and References.player:GetMouse()
            if not mouse or not mouse.Hit then
                return
            end
            local dest = mouse.Hit.Position

            -- If already walking, cancel the old run first (ensures speed + visuals cleared)
            if isClickMoving then
                cancelActiveWalk()
            end

            currentDest = dest
            clearAllViz()
            createBeacon(dest)

            local root = References.humanoidRootPart
            local hum = References.humanoid
            if not (root and hum) then
                cancelActiveWalk()
                return
            end

            isClickMoving = true
            applyCTWSpeed()
            wireInterrupts() -- (re)attach interrupts for this run

            checkpoints = buildCheckpoints(root.Position, dest)
            segIndex = 1
            computeSegmentAndWalk(root.Position, checkpoints[segIndex])
        end)
    end

    -- === Bind UI ===
    Toggles.ClickToWalk:OnChanged(function()
        if Toggles.ClickToWalk.Value then
            startClickListener()
            -- do not set WalkSpeed here – only during an active run
        else
            stopClickWalk()
        end
    end)

    Options.CTW_Speed:OnChanged(function(v)
        if isClickMoving and References.humanoid then
            References.humanoid.WalkSpeed = v
        end
    end)

    W.startFlight = startFlight
    W.startSpeed = startSpeed
    W.startJumpMod = startJumpMod
    W.startInfiniteJump = startInfiniteJump
    W.stopFlight = stopFlight
    W.stopSpeed = stopSpeed
    W.stopJumpMod = stopJumpMod
    W.stopInfiniteJump = stopInfiniteJump

    function W.Unload()
        stopFlight()
        stopSpeed()
        stopJumpMod()
        stopInfiniteJump()
        stopClickTP()
        stopClickWalk()
    end
    return W    
end
