return function(Services, Tabs, References, Toggles, Options, Library)
    local RunService, Lighting, Players, CAS, UIS, StarterGui, Workspace = Services.RunService, Services.Lighting,
        Services.Players, Services.ContextActionService, Services.UserInputService, Services.StarterGui,
        Services.Workspace

    local RadarGroup = Tabs.ESP:AddRightGroupbox("Player Radar", "map")

    local radar = {
        gui = nil, conn = nil,
        range = 500, scale = 1,
        mode = "Camera",
        rings = {},
        _holder = nil, _centerIcon = nil,
        buildRings = nil, updateRings = nil,
    }

    local function destroyRadar()
        if radar.conn then radar.conn:Disconnect(); radar.conn = nil end
        if radar.gui then radar.gui:Destroy(); radar.gui = nil end
        radar.rings = {}
        radar._holder, radar._centerIcon = nil, nil
    end

    local function createRadar()
        destroyRadar()
        local parent = (gethui and gethui()) or Services.CoreGui
        local sg = Instance.new("ScreenGui")
        sg.Name = "CerberusRadar"
        sg.ResetOnSpawn = false
        sg.IgnoreGuiInset = true
        sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        sg.Parent = parent
        radar.gui = sg

        local holder = Instance.new("Frame")
        holder.Name = "Holder"
        holder.AnchorPoint = Vector2.new(1,1)
        holder.Position = UDim2.new(1,-20,1,-20)
        holder.Size = UDim2.fromOffset(200 * radar.scale, 200 * radar.scale)
        holder.BackgroundColor3 = Color3.fromRGB(25,25,25)
        holder.BackgroundTransparency = 0.2
        holder.Active = true
        holder.ClipsDescendants = false
        holder.Parent = sg

        local corner = Instance.new("UICorner", holder)
        corner.CornerRadius = UDim.new(1, 0)
        local stroke = Instance.new("UIStroke", holder)
        stroke.Thickness = 2
        stroke.Color = Color3.fromRGB(92,94,104)
        stroke.Transparency = 0.3

        local centerIcon = Instance.new("ImageLabel")
        centerIcon.BackgroundTransparency = 1
        centerIcon.Image = "rbxassetid://136497541793809"
        centerIcon.ImageColor3 = Color3.fromRGB(55,235,120)
        centerIcon.AnchorPoint = Vector2.new(0.5,0.5)
        centerIcon.Position = UDim2.fromScale(0.5,0.5)
        centerIcon.Size = UDim2.fromOffset(22 * radar.scale, 22 * radar.scale)
        centerIcon.Parent = holder

        local function buildRings()
            for _, r in ipairs(radar.rings) do r.Frame:Destroy() end
            radar.rings = {}
            for _, pct in ipairs({0.25, 0.75}) do
                local ring = Instance.new("Frame")
                ring.Name = "Ring"
                ring.BackgroundTransparency = 1
                ring.SizeConstraint = Enum.SizeConstraint.RelativeXX
                ring.Size = UDim2.fromScale(pct, pct)
                ring.AnchorPoint = Vector2.new(0.5,0.5)
                ring.Position = UDim2.fromScale(0.5,0.5)
                ring.Parent = holder
                local rc = Instance.new("UICorner", ring); rc.CornerRadius = UDim.new(1,0)
                local rs = Instance.new("UIStroke", ring)
                rs.Color = Color3.fromRGB(60,60,60); rs.Thickness = 1; rs.Transparency = 0.6

                local lbl = Instance.new("TextLabel")
                lbl.Name = "Studs"
                lbl.BackgroundTransparency = 1
                lbl.Font = Enum.Font.Gotham
                lbl.TextColor3 = Color3.fromRGB(150,150,150)
                lbl.TextSize = 10 * radar.scale
                lbl.AnchorPoint = Vector2.new(0.5,0)
                lbl.Position = UDim2.new(0.5, 0, 1, 2 * radar.scale)
                lbl.ZIndex = 5
                lbl.Parent = ring

                table.insert(radar.rings, { Frame = ring, Label = lbl, Percent = pct })
            end
        end

        local function updateRingLabels()
            for _, r in ipairs(radar.rings) do
                r.Label.Text = string.format("%d studs", math.floor(r.Percent * radar.range + 0.5))
                r.Label.TextSize = 10 * radar.scale
                r.Label.Position = UDim2.new(0.5, 0, 1, 2 * radar.scale)
            end
        end

        buildRings()
        updateRingLabels()

        do
            local dragging, dragStart, startPos
            holder.InputBegan:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                    dragging = true; dragStart = i.Position; startPos = holder.Position
                    i.Changed:Connect(function()
                        if i.UserInputState == Enum.UserInputState.End then dragging = false end
                    end)
                end
            end)
            holder.InputChanged:Connect(function(i)
                if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                    local d = i.Position - dragStart
                    holder.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
                end
            end)
        end

        radar.conn = Services.RunService.Heartbeat:Connect(function()
            local root = References.humanoidRootPart
            if not root then return end

            for _, child in ipairs(holder:GetChildren()) do
                if child.Name == "Blip" and child:IsA("Frame") then child:Destroy() end
            end

            local size = holder.AbsoluteSize
            local center = Vector2.new(size.X/2, size.Y/2)
            local radius = math.min(size.X, size.Y)/2 - (12 * radar.scale)

            local teamsAvailable = Services.Teams and #Services.Teams:GetChildren() > 0
            local myTeam = Services.Players.LocalPlayer.Team

            local cam = workspace.CurrentCamera
            local camRight = cam and cam.CFrame.RightVector
            local camForward = cam and cam.CFrame.LookVector

            for _, pl in ipairs(Services.Players:GetPlayers()) do
                if pl ~= References.player and pl.Character then
                    local hrp = pl.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local rel = hrp.Position - root.Position
                        local dist = rel.Magnitude
                        if dist <= radar.range then
                            local rx, rz
                            if radar.mode == "Camera" and camRight and camForward then
                                rx = rel:Dot(camRight)
                                rz = -rel:Dot(camForward)
                            else
                                rx = rel.X; rz = rel.Z
                            end

                            local pos = Vector2.new(rx, rz) / radar.range * radius
                            local isFriendly = teamsAvailable and (pl.Team ~= nil and myTeam ~= nil and pl.Team == myTeam)

                            local blip = Instance.new("Frame")
                            blip.Name = "Blip"
                            blip.AnchorPoint = Vector2.new(0.5, 0.5)
                            blip.Size = UDim2.fromOffset(8 * radar.scale, 8 * radar.scale)
                            blip.Position = UDim2.fromOffset(center.X + pos.X, center.Y + pos.Y)
                            blip.BackgroundColor3 = isFriendly and Color3.fromRGB(55,235,120) or Color3.fromRGB(235,55,55)
                            blip.BorderSizePixel = 0
                            blip.ZIndex = 10
                            blip.Parent = holder
                            local bc = Instance.new("UICorner", blip); bc.CornerRadius = UDim.new(1,0)
                        end
                    end
                end
            end
        end)

        radar._holder = holder
        radar._centerIcon = centerIcon
        radar.buildRings = buildRings
        radar.updateRings = updateRingLabels
    end

    RadarGroup:AddToggle("Radar_Enable", {
        Text = "Enable Radar",
        Default = false,
        Callback = function(v) if v then createRadar() else destroyRadar() end end
    })

    RadarGroup:AddSlider("Radar_Range", {
        Text = "Range",
        Default = 500, Min = 100, Max = 2000, Rounding = 0, Suffix = " studs",
        Callback = function(v)
            radar.range = v
            if radar.updateRings then radar.updateRings() end
        end
    })

    RadarGroup:AddSlider("Radar_Scale", {
        Text = "HUD Scale",
        Default = 100, Min = 50, Max = 200, Rounding = 0, Suffix = "%",
        Callback = function(v)
            radar.scale = v / 100
            if radar.gui and radar._holder then
                local h = radar._holder
                h.Size = UDim2.fromOffset(200 * radar.scale, 200 * radar.scale)
                if radar._centerIcon then
                    radar._centerIcon.Size = UDim2.fromOffset(22 * radar.scale, 22 * radar.scale)
                end
                for _, r in ipairs(radar.rings) do
                    r.Label.TextSize = 10 * radar.scale
                    r.Label.Position = UDim2.new(0.5, 0, 1, 2 * radar.scale)
                end
            end
        end
    })

    RadarGroup:AddDropdown("Radar_Mode", {
        Text = "Rotation Mode",
        Values = { "Camera", "North" },
        Default = "Camera",
        Callback = function(v) radar.mode = v end
    })

    ------------------------------------------------------------
    -- VISUALS GROUP
    ------------------------------------------------------------
    local VisualsGroup = Tabs.Player:AddRightGroupbox("Visuals", "glasses")

    -- == UNLIMITED CAM DISTANCE == --
    VisualsGroup:AddToggle("InfiniteCamera", {
        Text = "Infinite Camera Max",
        Default = false
    })
    local origCamMax
    Toggles.InfiniteCamera:OnChanged(function()
        local pl = References.player
        if not pl then
            return
        end
        if Toggles.InfiniteCamera.Value then
            origCamMax = origCamMax or pl.CameraMaxZoomDistance
            pl.CameraMaxZoomDistance = 1e10
        else
            pl.CameraMaxZoomDistance = origCamMax or 128
            origCamMax = nil
        end
    end)

-- == NO FOG & CLEAR WEATHER == -- 
    VisualsGroup:AddToggle("NoFog", {
        Text = "No Fog / Clear Weather",
        Default = false
    })

    local nfConn, nfSaved, debrisConn
    local Lighting = Services.Lighting

    local function nfDisable(inst)
        if not nfSaved then return end
        
        if inst:IsA("BloomEffect") or inst:IsA("SunRaysEffect") or inst:IsA("DepthOfFieldEffect") or
           inst:IsA("ColorCorrectionEffect") or inst:IsA("BlurEffect") then
            if inst.Enabled then
                inst:SetAttribute("NFWasEnabled", true)
                inst.Enabled = false
            end
        elseif inst:IsA("Atmosphere") then
            if nfSaved.Atmo[inst] == nil then
                nfSaved.Atmo[inst] = {
                    D = inst.Density,
                    H = inst.Haze,
                    O = inst.Offset,
                    G = inst.Glare
                }
            end
            inst.Density = 0
            inst.Haze = 0
            inst.Glare = 0
        end
    end

    local function nfOn()
        if nfSaved then return end
        
        -- 1. Setup Fog State
        nfSaved = {
            FogEnd = Lighting.FogEnd,
            FogStart = Lighting.FogStart,
            FogColor = Lighting.FogColor,
            Atmo = {}
        }
        Lighting.FogEnd, Lighting.FogStart = 1e10, 1e10
        
        -- 2. Disable Existing Lighting Effects
        for _, d in ipairs(Lighting:GetDescendants()) do
            nfDisable(d)
        end
        nfConn = Lighting.DescendantAdded:Connect(nfDisable)

        -- 3. Delete Player Specific Weather (e.g. NewToyotaSupraWeather)
        local debris = Services.Workspace:FindFirstChild("DebrisFolder")
        if debris then
            local weatherName = References.player.Name .. "Weather"
            
            -- Check immediately
            local existing = debris:FindFirstChild(weatherName)
            if existing then existing:Destroy() end
            
            -- Watch for respawn
            debrisConn = debris.ChildAdded:Connect(function(child)
                if child.Name == weatherName then
                    task.defer(function() child:Destroy() end)
                end
            end)
        end
    end

    local function nfOff()
        if not nfSaved then return end
        
        -- 1. Restore Lighting Connection
        if nfConn then
            nfConn:Disconnect()
            nfConn = nil
        end
        
        -- 2. Restore Fog Values
        Lighting.FogEnd = nfSaved.FogEnd
        Lighting.FogStart = nfSaved.FogStart
        Lighting.FogColor = nfSaved.FogColor
        
        -- 3. Restore Lighting Effects
        for _, d in ipairs(Lighting:GetDescendants()) do
            if d:GetAttribute("NFWasEnabled") then
                d:SetAttribute("NFWasEnabled", nil)
                if d.Enabled ~= nil then
                    d.Enabled = true
                end
            end
        end
        for atmo, vals in pairs(nfSaved.Atmo) do
            if atmo and atmo.Parent then
                atmo.Density, atmo.Haze, atmo.Offset, atmo.Glare = vals.D, vals.H, vals.O, vals.G
            end
        end
        
        -- 4. Stop Debris Monitoring
        if debrisConn then
            debrisConn:Disconnect()
            debrisConn = nil
        end
        
        nfSaved = nil
    end

    Toggles.NoFog:OnChanged(function()
        if Toggles.NoFog.Value then
            nfOn()
        else
            nfOff()
        end
    end)

    -- == X-RAY == --
    VisualsGroup:AddToggle("XRay", {
        Text = "X-Ray",
        Default = false,
        Tooltip = "See through structures"
    })
    local function setXRay(on)
        for _, v in ipairs(Workspace:GetDescendants()) do
            if v:IsA("BasePart") then
                if not v.Parent:FindFirstChildOfClass("Humanoid") and
                    not (v.Parent.Parent and v.Parent.Parent:FindFirstChildOfClass("Humanoid")) then
                    v.LocalTransparencyModifier = on and 0.5 or 0
                end
            end
        end
    end
    Toggles.XRay:OnChanged(function()
        setXRay(Toggles.XRay.Value)
    end)

    -- == FULLBRIGHT == --
    VisualsGroup:AddToggle("Fullbright", {
        Text = "Fullbright",
        Default = false
    })
    VisualsGroup:AddSlider("Fullbright_Brightness", {
        Text = "Brightness",
        Default = 1,
        Min = 0.01,
        Max = 5,
        Rounding = 3
    })
    local fbConn, fbSaved
    local function fbOn()
        if fbConn then
            return
        end
        fbSaved = fbSaved or {
            B = Lighting.Brightness,
            GS = Lighting.GlobalShadows,
            A = Lighting.Ambient
        }
        fbConn = RunService.RenderStepped:Connect(function()
            Lighting.Brightness = Options.Fullbright_Brightness.Value
            Lighting.GlobalShadows = false
            Lighting.Ambient = Color3.new(1, 1, 1)
        end)
    end
    local function fbOff()
        if fbConn then
            fbConn:Disconnect();
            fbConn = nil
        end
        if fbSaved then
            Lighting.Brightness = fbSaved.B
            Lighting.GlobalShadows = fbSaved.GS
            Lighting.Ambient = fbSaved.A
            fbSaved = nil
        end
    end
    Toggles.Fullbright:OnChanged(function()
        if Toggles.Fullbright.Value then
            fbOn()
        else
            fbOff()
        end
    end)

    -- == FOV == --
    VisualsGroup:AddSlider("CameraFOV", {
        Text = "Camera FOV",
        Default = 70,
        Min = 40,
        Max = 120,
        Rounding = 0
    })
    local function applyFOV()
        if References.camera then
            References.camera.FieldOfView = Options.CameraFOV.Value
        end
    end
    Options.CameraFOV:OnChanged(applyFOV);
    applyFOV()

    -- == FREECAM == --
    VisualsGroup:AddToggle("FreecamEnabled", {
        Text = "Freecam",
        Default = false
    }):AddKeyPicker("FreecamKey", {
        Default = nil,
        SyncToggleState = true,
        Mode = "Toggle",
        Text = "Freecam Key"
    })
    VisualsGroup:AddSlider("FreecamSensitivity", {
        Text = "Freecam Sensitivity",
        Default = 1.0,
        Min = 0.1,
        Max = 3.0,
        Rounding = 2,
        Tooltip = "Scales look + movement speed"
    })

    local Camera = Workspace.CurrentCamera
    Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        Camera = Workspace.CurrentCamera
    end)

    local pi, exp, rad, sqrt, tan, abs, clamp, sign = math.pi, math.exp, math.rad, math.sqrt, math.tan, math.abs,
        math.clamp, math.sign

    local PITCH_LIMIT = rad(90)
    local Spring = {};
    Spring.__index = Spring
    function Spring.new(freq, pos)
        return setmetatable({
            f = freq,
            p = pos,
            v = pos * 0
        }, Spring)
    end
    function Spring:Update(dt, goal)
        local f = self.f * 2 * pi
        local p0, v0 = self.p, self.v
        local offset = goal - p0
        local decay = exp(-f * dt)
        local p1 = goal + (v0 * dt - offset * (f * dt + 1)) * decay
        local v1 = (f * dt * (offset * f - v0) + v0) * decay
        self.p, self.v = p1, v1
        return p1
    end
    function Spring:Reset(pos)
        self.p = pos;
        self.v = pos * 0
    end

    local velSpring = Spring.new(1.5, Vector3.new())
    local panSpring = Spring.new(1.0, Vector2.new())
    local fovSpring = Spring.new(4.0, 0)

    local cameraPos, cameraRot, cameraFov = Vector3.new(), Vector2.new(), 70
    local navSpeed = 1

    local inputBindNames = {
        KB = "CerbFC_Keyboard",
        MousePan = "CerbFC_MousePan",
        Wheel = "CerbFC_MouseWheel",
        GPBtn = "CerbFC_GPBtn",
        GPTrig = "CerbFC_GPTrig",
        GPThumb = "CerbFC_GPThumb",
        TouchPan = "CerbFC_TouchPan",
        Pinch = "CerbFC_Pinch" -- [NEW] Added touch binds
    }

    local gamepad = {
        ButtonX = 0,
        ButtonY = 0,
        ButtonL2 = 0,
        ButtonR2 = 0,
        Thumbstick1 = Vector2.new(),
        Thumbstick2 = Vector2.new()
    }
    local keyboard = {
        W = 0,
        A = 0,
        S = 0,
        D = 0,
        E = 0,
        Q = 0,
        U = 0,
        H = 0,
        J = 0,
        K = 0,
        I = 0,
        Y = 0,
        Up = 0,
        Down = 0
    }
    local mouse = {
        Delta = Vector2.new(),
        MouseWheel = 0
    }
    -- [NEW] Table to store touch input state
    local touch = {
        PanDelta = Vector2.new(),
        VerticalPanDelta = Vector2.new(),
        PinchDelta = 1.0,
        ActiveTouches = {}
    }

    local function thumbstickCurve(x)
        local K_CURVATURE, K_DEADZONE = 2.0, 0.15
        local function fCurve(v)
            return (exp(K_CURVATURE * v) - 1) / (exp(K_CURVATURE) - 1)
        end
        local function fDeadzone(v)
            return fCurve((v - K_DEADZONE) / (1 - K_DEADZONE))
        end
        return sign(x) * clamp(fDeadzone(abs(x)), 0, 1)
    end

    local function StartCapture()
        CAS:BindActionAtPriority(inputBindNames.KB, function(_, state, input)
            keyboard[input.KeyCode.Name] = state == Enum.UserInputState.Begin and 1 or 0
            return Enum.ContextActionResult.Sink
        end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.W, Enum.KeyCode.U, Enum.KeyCode.A,
            Enum.KeyCode.H, Enum.KeyCode.S, Enum.KeyCode.J, Enum.KeyCode.D, Enum.KeyCode.K, Enum.KeyCode.E,
            Enum.KeyCode.I, Enum.KeyCode.Q, Enum.KeyCode.Y, Enum.KeyCode.Up, Enum.KeyCode.Down)
        CAS:BindActionAtPriority(inputBindNames.MousePan, function(_, _, input)
            local d = input.Delta
            mouse.Delta = Vector2.new(-d.y, -d.x)
            return Enum.ContextActionResult.Sink
        end, false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.MouseMovement)
        CAS:BindActionAtPriority(inputBindNames.Wheel, function(_, _, input)
            mouse[input.UserInputType.Name] = -input.Position.z
            return Enum.ContextActionResult.Sink
        end, false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.MouseWheel)

        -- [NEW] Touch pan binding (1-finger pan for rotation, 2-finger pan for vertical)
        CAS:BindActionAtPriority(inputBindNames.TouchPan, function(_, state, input)
            if state == Enum.UserInputState.Begin then
                touch.ActiveTouches[input.UserInputType] = true
            elseif state == Enum.UserInputState.End then
                touch.ActiveTouches[input.UserInputType] = nil
            elseif state == Enum.UserInputState.Change then
                local touchCount = 0
                for _ in pairs(touch.ActiveTouches) do
                    touchCount = touchCount + 1
                end

                if touchCount == 1 then
                    -- 1-finger pan (rotation)
                    local d = input.Delta
                    touch.PanDelta = touch.PanDelta + Vector2.new(-d.y, -d.x)
                elseif touchCount >= 2 then
                    -- 2-finger pan (vertical movement)
                    local d = input.Delta
                    touch.VerticalPanDelta = touch.VerticalPanDelta + d
                end
            end
            return Enum.ContextActionResult.Sink
        end, false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.Touch)

        -- [NEW] Touch pinch binding (for zoom)
        CAS:BindActionAtPriority(inputBindNames.Pinch, function(_, state, input)
            if state == Enum.UserInputState.Change then
                touch.PinchDelta = input.Scale
            end
            return Enum.ContextActionResult.Sink
        end, false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.Pinch)

        CAS:BindActionAtPriority(inputBindNames.GPBtn, function(_, state, input)
            gamepad[input.KeyCode.Name] = state == Enum.UserInputState.Begin and 1 or 0
            return Enum.ContextActionResult.Sink
        end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonY)
        CAS:BindActionAtPriority(inputBindNames.GPTrig, function(_, _, input)
            gamepad[input.KeyCode.Name] = input.Position.z
            return Enum.ContextActionResult.Sink
        end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonL2)
        CAS:BindActionAtPriority(inputBindNames.GPThumb, function(_, _, input)
            gamepad[input.KeyCode.Name] = input.Position
            return Enum.ContextActionResult.Sink
        end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Thumbstick1, Enum.KeyCode.Thumbstick2)
    end
    local function StopCapture()
        navSpeed = 1
        for k in pairs(gamepad) do
            gamepad[k] = typeof(gamepad[k]) == "Vector2" and Vector2.new() or 0
        end
        for k in pairs(keyboard) do
            keyboard[k] = 0
        end
        mouse.Delta = Vector2.new();
        mouse.MouseWheel = 0
        -- [NEW] Clear touch state on stop
        touch.PanDelta = Vector2.new();
        touch.VerticalPanDelta = Vector2.new();
        touch.PinchDelta = 1.0;
        table.clear(touch.ActiveTouches)

        for _, n in pairs(inputBindNames) do
            CAS:UnbindAction(n)
        end
    end

    local hudCache = {}
    local function pushGuiState()
        -- [MODIFIED] Do not hide CoreGuis to preserve mobile controls (thumbstick)
        -- hudCache.core = { ... }
        -- for k,v in pairs(hudCache.core) do StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType[k], false) end

        local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
        hudCache.screens = {}
        if pg then
            for _, gui in ipairs(pg:GetChildren()) do
                -- [MODIFIED] Do not hide TouchGui or DynamicThumbstick
                if gui:IsA("ScreenGui") and gui.Enabled and gui.Name ~= "TouchGui" and gui.Name ~= "DynamicThumbstick" then
                    hudCache.screens[#hudCache.screens + 1] = gui
                    gui.Enabled = false
                end
            end
        end
    end
    local function popGuiState()
        -- [MODIFIED] Do not restore CoreGuis
        -- if hudCache.core then ... end
        if hudCache.screens then
            for _, gui in ipairs(hudCache.screens) do
                if gui.Parent then
                    gui.Enabled = true
                end
            end
        end
        hudCache = {}
    end

    local humRef, humJumpState, jumpConn
    local function disableJump()
        humRef = References.humanoid
        if humRef and humRef.SetStateEnabled then
            humJumpState = humRef:GetStateEnabled(Enum.HumanoidStateType.Jumping)
            humRef:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
        end
        if UIS and UIS.JumpRequest then
            jumpConn = UIS.JumpRequest:Connect(function()
                if humRef then
                    humRef.Jump = false
                end
            end)
        end
    end
    local function enableJump()
        if jumpConn then
            jumpConn:Disconnect();
            jumpConn = nil
        end
        if humRef and humRef.SetStateEnabled then
            humRef:SetStateEnabled(Enum.HumanoidStateType.Jumping, humJumpState ~= false)
        end
        humRef = nil;
        humJumpState = nil
    end

    local function velInput(dt, sens)
        navSpeed = clamp(navSpeed + dt * (keyboard.Up - keyboard.Down) * 0.75, 0.01, 4)
        local g = Vector3.new(thumbstickCurve(gamepad.Thumbstick1.X),
            thumbstickCurve(gamepad.ButtonR2) - thumbstickCurve(gamepad.ButtonL2),
            thumbstickCurve(-gamepad.Thumbstick1.Y))
        -- [MODIFIED] Added vertical pan delta for Up/Down movement
        local k = Vector3.new(keyboard.D - keyboard.A + keyboard.K - keyboard.H,
            keyboard.E - keyboard.Q + keyboard.I - keyboard.Y - (touch.VerticalPanDelta.Y * 0.1), -- [NEW]
            keyboard.S - keyboard.W + keyboard.J - keyboard.U)
        touch.VerticalPanDelta = Vector2.new() -- [NEW] Reset after reading

        local shift = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
        return (g + k) * (64 * navSpeed * (shift and 0.25 or 1) * sens)
    end
    local function panInput(dt, sens)
        local gp = Vector2.new(thumbstickCurve(gamepad.Thumbstick2.Y), thumbstickCurve(-gamepad.Thumbstick2.X)) *
                       (pi / 8)

        -- [MODIFIED] Added touch pan delta for rotation
        local km = (mouse.Delta + touch.PanDelta) * (pi / 64)
        mouse.Delta = Vector2.new()
        touch.PanDelta = Vector2.new() -- [NEW] Reset after reading

        return (gp + km) * (8 * sens)
    end
    local function fovInput()
        local gp = (gamepad.ButtonX - gamepad.ButtonY) * 0.25
        local mw = mouse.MouseWheel * 1.0

        -- [NEW] Added pinch delta for zoom
        -- (Scale - 1.0) gives a delta (e.g., 0.1 or -0.1). Multiply for sensitivity.
        -- Inverted to match your mouse wheel direction.
        local pinch = (touch.PinchDelta - 1.0) * -5.0

        mouse.MouseWheel = 0
        touch.PinchDelta = 1.0 -- [NEW] Reset after reading

        return gp + mw + pinch
    end

    local freecamOn = false

    local function StepFreecam(dt)
        local sens = Options.FreecamSensitivity.Value or 1
        local vel = velSpring:Update(dt, velInput(dt, sens))
        local pan = panSpring:Update(dt, panInput(dt, sens))
        local fov = fovSpring:Update(dt, fovInput())

        local zoomFactor = sqrt(tan(rad(70 / 2)) / tan(rad(cameraFov / 2)))
        cameraFov = clamp(cameraFov + fov * 300 * (dt / zoomFactor), 1, 120)
        cameraRot = cameraRot + pan * (dt / zoomFactor)
        cameraRot = Vector2.new(clamp(cameraRot.X, -PITCH_LIMIT, PITCH_LIMIT), cameraRot.Y % (2 * pi))

        local cf = CFrame.new(cameraPos) * CFrame.fromOrientation(cameraRot.X, cameraRot.Y, 0) * CFrame.new(vel * dt)
        cameraPos = cf.Position

        Camera.CFrame = cf
        Camera.Focus = cf
        Camera.FieldOfView = cameraFov
    end

    local function StartFreecam()
        if freecamOn then
            return
        end

        local cf = Camera.CFrame
        cameraRot = Vector2.new(cf:toEulerAnglesYXZ());
        cameraPos = cf.Position;
        cameraFov = Camera.FieldOfView
        velSpring:Reset(Vector3.new());
        panSpring:Reset(Vector2.new());
        fovSpring:Reset(0)

        pushGuiState()
        disableJump()
        Camera.CameraType = Enum.CameraType.Scriptable

        UIS.MouseIconEnabled = false
        UIS.MouseBehavior = Enum.MouseBehavior.LockCenter

        StartCapture()
        RunService:BindToRenderStep("CerbFreecam", Enum.RenderPriority.Camera.Value, StepFreecam)
        freecamOn = true
    end

    local function StopFreecam()
        if not freecamOn then
            return
        end
        RunService:UnbindFromRenderStep("CerbFreecam")

        StopCapture()
        enableJump()

        Camera.CameraType = Enum.CameraType.Custom
        UIS.MouseBehavior = Enum.MouseBehavior.Default
        UIS.MouseIconEnabled = true

        mouse.Delta = Vector2.new();
        mouse.MouseWheel = 0

        popGuiState()
        freecamOn = false
    end

    Toggles.FreecamEnabled:OnChanged(function()
        if Toggles.FreecamEnabled.Value then
            Library:Notify("Freecam enabled.", 2)
            StartFreecam()
        else
            Library:Notify("Freecam disabled.", 2)
            StopFreecam()
        end
    end)

    Library:OnUnload(function()
        destroyRadar()
        if Toggles.InfiniteCamera and Toggles.InfiniteCamera.Value then
            Toggles.InfiniteCamera:SetValue(false)
        end
        if Toggles.NoFog and Toggles.NoFog.Value then
            Toggles.NoFog:SetValue(false)
        end
        if Toggles.XRay and Toggles.XRay.Value then
            Toggles.XRay:SetValue(false)
        end
        if Toggles.Fullbright and Toggles.Fullbright.Value then
            Toggles.Fullbright:SetValue(false)
        end
        if Toggles.FreecamEnabled and Toggles.FreecamEnabled.Value then
            Toggles.FreecamEnabled:SetValue(false)
        end
        fbOff();
        nfOff();
        setXRay(false)
        if freecamOn then
            StopFreecam()
        end
    end)
end
