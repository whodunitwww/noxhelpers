return function(Services, Tabs, References, Toggles, Options, Library)
    local CTWGroup = Tabs.Player:AddLeftGroupbox("Click To Walk", "mouse-pointer")

    CTWGroup:AddToggle("ClickToWalk", { Text = "Enable Click To Walk", Default = false })
    CTWGroup:AddSlider("CTW_Speed", { Text = "Walk Speed", Default = 16, Min = 8, Max = 100, Rounding = 0, Suffix = " studs/s" })

    local MAX_HOP_DISTANCE = 700
    local MIN_REPATH_INTERVAL = 0.30
    local lastComputeAt = 0

    local clickConn, moveConn, blockedConn, spinConn
    local pathObj
    local segmentFolder
    local beaconFolder
    local currentDest
    local checkpoints = nil
    local segIndex = 0

    local function fadeAndDestroy(folder)
        if not folder then return end
        for _, inst in ipairs(folder:GetDescendants()) do
            if inst:IsA("BasePart") then
                Services.TweenService:Create(inst, TweenInfo.new(0.4), { Transparency = 1 }):Play()
            end
        end
        task.delay(0.45, function() if folder then folder:Destroy() end end)
    end

    local function clearBeacon()
        if spinConn then spinConn:Disconnect(); spinConn = nil end
        if beaconFolder then fadeAndDestroy(beaconFolder); beaconFolder = nil end
    end
    local function clearPathViz()
        if segmentFolder then fadeAndDestroy(segmentFolder); segmentFolder = nil end
    end
    local function clearAllViz()
        clearBeacon(); clearPathViz()
    end

    local function stopClickWalk()
        if clickConn   then clickConn:Disconnect();   clickConn   = nil end
        if moveConn    then moveConn:Disconnect();    moveConn    = nil end
        if blockedConn then blockedConn:Disconnect(); blockedConn = nil end
        pathObj = nil
        currentDest = nil
        checkpoints = nil
        segIndex = 0
        clearAllViz()
        if References.humanoid then References.humanoid.WalkSpeed = 16 end
    end

    local function createBeacon(pos: Vector3)
        clearBeacon()
        beaconFolder = Instance.new("Folder"); beaconFolder.Name = "CTW_Beacon"; beaconFolder.Parent = workspace

        local pillar = Instance.new("Part")
        pillar.Name = "Pillar"; pillar.Anchored = true; pillar.CanCollide = false
        pillar.Material = Enum.Material.Neon; pillar.Color = Color3.fromRGB(55,235,120)
        pillar.Size = Vector3.new(0.25, 12, 0.25)
        pillar.CFrame = CFrame.new(pos + Vector3.new(0, pillar.Size.Y/2, 0))
        pillar.Parent = beaconFolder

        local ring = Instance.new("Part")
        ring.Name = "Ring"; ring.Shape = Enum.PartType.Cylinder; ring.Anchored = true; ring.CanCollide = false
        ring.Material = Enum.Material.Neon; ring.Color = Color3.fromRGB(55,235,120)
        ring.Size = Vector3.new(2, 0.2, 2)
        ring.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(90), 0, 0)
        ring.Parent = beaconFolder

        local glow = Instance.new("Part")
        glow.Name = "Glow"; glow.Anchored = true; glow.CanCollide = false
        glow.Material = Enum.Material.Neon; glow.Color = Color3.fromRGB(55,235,120)
        glow.Transparency = 0.5; glow.Size = Vector3.new(1.5, 0.15, 1.5)
        glow.CFrame = CFrame.new(pos + Vector3.new(0,0.05,0))
        glow.Parent = beaconFolder

        Services.TweenService:Create(ring,   TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1, true), { Size = Vector3.new(6, ring.Size.Y, 6) }):Play()
        Services.TweenService:Create(pillar, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.25 }):Play()

        local theta = 0
        spinConn = Services.RunService.Heartbeat:Connect(function(dt)
            theta += dt * math.pi/2
            if ring and ring.Parent then
                ring.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(90), theta, 0)
            end
        end)
    end

    local function drawPath(waypoints)
        clearPathViz()
        segmentFolder = Instance.new("Folder"); segmentFolder.Name = "CTW_Path"; segmentFolder.Parent = workspace

        for i = 1, #waypoints do
            local wp = Instance.new("Part")
            wp.Name = "CTW_Waypoint"
            wp.Anchored = true; wp.CanCollide = false
            wp.Material = Enum.Material.Neon; wp.Color = Color3.fromRGB(55,235,120)
            wp.Size = Vector3.new(0.35, 0.35, 0.35); wp.Shape = Enum.PartType.Ball
            wp.CFrame = CFrame.new(waypoints[i].Position + Vector3.new(0, 0.15, 0))
            wp.Parent = segmentFolder
        end

        for i = 1, #waypoints - 1 do
            local a, b = waypoints[i].Position, waypoints[i+1].Position
            local seg = Instance.new("Part")
            seg.Name = "CTW_Segment"; seg.Anchored = true; seg.CanCollide = false
            seg.Material = Enum.Material.Neon; seg.Color = Color3.fromRGB(55,235,120)
            seg.Size = Vector3.new(0.15, 0.15, (a - b).Magnitude)
            seg.CFrame = CFrame.new((a + b) / 2, b)
            seg.Transparency = 1; seg.Parent = segmentFolder
            Services.TweenService:Create(seg, TweenInfo.new(0.2), { Transparency = 0 }):Play()
        end
    end

    local function finish()
        clearAllViz()
        if moveConn then moveConn:Disconnect(); moveConn = nil end
        if blockedConn then blockedConn:Disconnect(); blockedConn = nil end
        pathObj = nil
        currentDest = nil
        checkpoints = nil
        segIndex = 0
        if References.humanoid then References.humanoid.WalkSpeed = 16 end
    end

    local function buildCheckpoints(startPos: Vector3, dest: Vector3)
        local delta = dest - startPos
        local dist = delta.Magnitude
        if dist < 1 then return { dest } end
        local dir = delta.Unit
        local pts = {}
        local covered = 0
        while covered + MAX_HOP_DISTANCE < dist do
            covered += MAX_HOP_DISTANCE
            pts[#pts+1] = startPos + dir * covered
        end
        pts[#pts+1] = dest
        return pts
    end

    local function safeCompute(pathObj, a: Vector3, b: Vector3)
        local now = os.clock()
        local waitLeft = MIN_REPATH_INTERVAL - (now - lastComputeAt)
        if waitLeft > 0 then task.wait(waitLeft) end
        lastComputeAt = os.clock()

        local ok, err = pcall(function()
            pathObj:ComputeAsync(a, b)
        end)
        if not ok then
            return false, err
        end
        return true, nil
    end

    local function computeSegmentAndWalk(segStart: Vector3, segEnd: Vector3)
        local p = Services.PathfindingService:CreatePath({
            AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 4,
        })
        pathObj = p

        local ok = safeCompute(p, segStart, segEnd)
        if not ok or p.Status ~= Enum.PathStatus.Success then
            Library:Notify("Path segment failed. Trying again with shorter hop...", 3)
            local half = segStart:Lerp(segEnd, 0.5)
            ok = safeCompute(p, segStart, half)
            if not ok or p.Status ~= Enum.PathStatus.Success then
                Library:Notify("Unable to compute path here.", 3)
                finish()
                return
            else
                table.insert(checkpoints, segIndex, half)
            end
        end

        local wps = p:GetWaypoints()
        if #wps == 0 then
            Library:Notify("No waypoints for this segment.", 3)
            finish()
            return
        end
        drawPath(wps)

        if blockedConn then blockedConn:Disconnect(); blockedConn = nil end
        blockedConn = p.Blocked:Connect(function()
            local root = References.humanoidRootPart
            if root and currentDest and checkpoints then
                computeSegmentAndWalk(root.Position, checkpoints[segIndex])
            end
        end)

        if moveConn then moveConn:Disconnect(); moveConn = nil end
        local i = 1
        References.humanoid:MoveTo(wps[i].Position)
        moveConn = References.humanoid.MoveToFinished:Connect(function(reached)
            if pathObj ~= p then return end
            if not reached then
                local root = References.humanoidRootPart
                if root and checkpoints then
                    computeSegmentAndWalk(root.Position, checkpoints[segIndex])
                end
                return
            end
            i += 1
            if wps[i] then
                References.humanoid:MoveTo(wps[i].Position)
            else
                segIndex += 1
                if checkpoints and checkpoints[segIndex] then
                    local root = References.humanoidRootPart
                    if root then
                        computeSegmentAndWalk(root.Position, checkpoints[segIndex])
                    else
                        finish()
                    end
                else
                    finish()
                end
            end
        end)
    end

    local function startClickWalk()
        if clickConn then return end
        clickConn = Services.UserInputService.InputBegan:Connect(function(input, gp)
            if gp then return end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

            local mouse = References.player:GetMouse()
            if not mouse or not mouse.Hit then return end
            local dest = mouse.Hit.Position
            currentDest = dest

            clearAllViz()
            createBeacon(dest)

            if References.humanoid then
                References.humanoid.WalkSpeed = Options.CTW_Speed.Value
            end

            local root = References.humanoidRootPart
            if not root then return end

            checkpoints = buildCheckpoints(root.Position, dest)
            segIndex = 1
            computeSegmentAndWalk(root.Position, checkpoints[segIndex])
        end)
    end

    Toggles.ClickToWalk:OnChanged(function()
        if Toggles.ClickToWalk.Value then
            startClickWalk()
            if References.humanoid then
                References.humanoid.WalkSpeed = Options.CTW_Speed.Value
            end
        else
            stopClickWalk()
        end
    end)

    Options.CTW_Speed:OnChanged(function(v)
        if Toggles.ClickToWalk.Value and References.humanoid then
            References.humanoid.WalkSpeed = v
        end
    end)
end
