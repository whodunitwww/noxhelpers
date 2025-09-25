return function(Services, Tabs, References, Toggles, Options, Library)
    local RunService, Lighting, Players, CAS, UIS, StarterGui, Workspace =
        Services.RunService, Services.Lighting, Services.Players, Services.ContextActionService,
        Services.UserInputService, Services.StarterGui, Services.Workspace

    ------------------------------------------------------------
    -- VISUALS GROUP
    ------------------------------------------------------------
    local VisualsGroup = Tabs.Player:AddRightGroupbox("Visuals", "glasses")

    -- == UNLIMITED CAM DISTANCE ==
    VisualsGroup:AddToggle("InfiniteCamera", { Text = "Infinite Camera Max", Default = false })
    local origCamMax
    Toggles.InfiniteCamera:OnChanged(function()
        local pl = References.player
        if not pl then return end
        if Toggles.InfiniteCamera.Value then
            origCamMax = origCamMax or pl.CameraMaxZoomDistance
            pl.CameraMaxZoomDistance = 1e10
        else
            pl.CameraMaxZoomDistance = origCamMax or 128
            origCamMax = nil
        end
    end)

    -- == NO FOG ==
    VisualsGroup:AddToggle("NoFog", { Text = "No Fog", Default = false })
    local nfConn, nfSaved
    local function nfDisable(inst)
        if not nfSaved then return end
        if inst:IsA("BloomEffect") or inst:IsA("SunRaysEffect") or inst:IsA("DepthOfFieldEffect")
        or inst:IsA("ColorCorrectionEffect") or inst:IsA("BlurEffect") then
            if inst.Enabled then inst:SetAttribute("NFWasEnabled", true); inst.Enabled = false end
        elseif inst:IsA("Atmosphere") then
            if nfSaved.Atmo[inst] == nil then
                nfSaved.Atmo[inst] = {D=inst.Density, H=inst.Haze, O=inst.Offset, G=inst.Glare}
            end
            inst.Density=0; inst.Haze=0; inst.Glare=0
        end
    end
    local function nfOn()
        if nfSaved then return end
        nfSaved = { FogEnd=Lighting.FogEnd, FogStart=Lighting.FogStart, FogColor=Lighting.FogColor, Atmo={} }
        Lighting.FogEnd, Lighting.FogStart = 1e10, 1e10
        for _,d in ipairs(Lighting:GetDescendants()) do nfDisable(d) end
        nfConn = Lighting.DescendantAdded:Connect(nfDisable)
    end
    local function nfOff()
        if not nfSaved then return end
        if nfConn then nfConn:Disconnect(); nfConn=nil end
        Lighting.FogEnd, Lighting.FogStart, Lighting.FogColor = nfSaved.FogEnd, nfSaved.FogStart, nfSaved.FogColor
        for _,d in ipairs(Lighting:GetDescendants()) do
            if d:GetAttribute("NFWasEnabled") then d:SetAttribute("NFWasEnabled", nil); if d.Enabled ~= nil then d.Enabled=true end end
        end
        for atmo,vals in pairs(nfSaved.Atmo) do
            if atmo and atmo.Parent then atmo.Density,atmo.Haze,atmo.Offset,atmo.Glare = vals.D,vals.H,vals.O,vals.G end
        end
        nfSaved=nil
    end
    Toggles.NoFog:OnChanged(function() if Toggles.NoFog.Value then nfOn() else nfOff() end end)

    -- == X-RAY ==
    VisualsGroup:AddToggle("XRay", { Text = "X-Ray", Default = false, Tooltip = "See through structures" })
    local function setXRay(on)
        for _, v in ipairs(Workspace:GetDescendants()) do
            if v:IsA("BasePart") then
                if not v.Parent:FindFirstChildOfClass("Humanoid") and not (v.Parent.Parent and v.Parent.Parent:FindFirstChildOfClass("Humanoid")) then
                    v.LocalTransparencyModifier = on and 0.5 or 0
                end
            end
        end
    end
    Toggles.XRay:OnChanged(function() setXRay(Toggles.XRay.Value) end)

    -- == FULLBRIGHT ==
    VisualsGroup:AddToggle("Fullbright", { Text = "Fullbright", Default = false })
    VisualsGroup:AddSlider("Fullbright_Brightness", { Text="Brightness", Default=2, Min=1, Max=10, Rounding=1 })
    local fbConn, fbSaved
    local function fbOn()
        if fbConn then return end
        fbSaved = fbSaved or { B=Lighting.Brightness, GS=Lighting.GlobalShadows, A=Lighting.Ambient }
        fbConn = RunService.RenderStepped:Connect(function()
            Lighting.Brightness    = Options.Fullbright_Brightness.Value
            Lighting.GlobalShadows = false
            Lighting.Ambient       = Color3.new(1,1,1)
        end)
    end
    local function fbOff()
        if fbConn then fbConn:Disconnect(); fbConn=nil end
        if fbSaved then
            Lighting.Brightness    = fbSaved.B
            Lighting.GlobalShadows = fbSaved.GS
            Lighting.Ambient       = fbSaved.A
            fbSaved = nil
        end
    end
    Toggles.Fullbright:OnChanged(function() if Toggles.Fullbright.Value then fbOn() else fbOff() end end)

    -- == FOV ==
    VisualsGroup:AddSlider("CameraFOV", { Text="Camera FOV", Default=70, Min=40, Max=120, Rounding=0 })
    local function applyFOV()
        if References.camera then References.camera.FieldOfView = Options.CameraFOV.Value end
    end
    Options.CameraFOV:OnChanged(applyFOV); applyFOV()

    ------------------------------------------------------------
    -- FREECAM (toggle + keybind + sensitivity; no RMB needed)
    ------------------------------------------------------------
    VisualsGroup:AddToggle("FreecamEnabled", { Text = "Freecam", Default = false })
        :AddKeyPicker("FreecamKey", { Default = "P", SyncToggleState = true, Mode = "Toggle", Text = "Freecam Key" })
    VisualsGroup:AddSlider("FreecamSensitivity", {
        Text = "Freecam Sensitivity",
        Default = 1.0, Min = 0.1, Max = 3.0, Rounding = 2,
        Tooltip = "Scales look + movement speed"
    })

    local Camera = Workspace.CurrentCamera
    Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function() Camera = Workspace.CurrentCamera end)

    local pi, exp, rad, sqrt, tan, abs, clamp, sign =
        math.pi, math.exp, math.rad, math.sqrt, math.tan, math.abs, math.clamp, math.sign

    local PITCH_LIMIT = rad(90)
    local Spring = {}; Spring.__index = Spring
    function Spring.new(freq, pos) return setmetatable({ f=freq, p=pos, v=pos*0 }, Spring) end
    function Spring:Update(dt, goal)
        local f = self.f*2*pi
        local p0, v0 = self.p, self.v
        local offset = goal - p0
        local decay  = exp(-f*dt)
        local p1 = goal + (v0*dt - offset*(f*dt + 1))*decay
        local v1 = (f*dt*(offset*f - v0) + v0)*decay
        self.p, self.v = p1, v1
        return p1
    end
    function Spring:Reset(pos) self.p = pos; self.v = pos*0 end

    local velSpring  = Spring.new(1.5, Vector3.new())
    local panSpring  = Spring.new(1.0, Vector2.new())
    local fovSpring  = Spring.new(4.0, 0)

    local cameraPos, cameraRot, cameraFov = Vector3.new(), Vector2.new(), 70
    local navSpeed = 1

    local inputBindNames = {
        KB="CerbFC_Keyboard", MousePan="CerbFC_MousePan", Wheel="CerbFC_MouseWheel",
        GPBtn="CerbFC_GPBtn", GPTrig="CerbFC_GPTrig", GPThumb="CerbFC_GPThumb"
    }

    local gamepad = { ButtonX=0, ButtonY=0, ButtonL2=0, ButtonR2=0, Thumbstick1=Vector2.new(), Thumbstick2=Vector2.new() }
    local keyboard = { W=0,A=0,S=0,D=0,E=0,Q=0,U=0,H=0,J=0,K=0,I=0,Y=0,Up=0,Down=0 }
    local mouse = { Delta=Vector2.new(), MouseWheel=0 }

    local function thumbstickCurve(x)
        local K_CURVATURE, K_DEADZONE = 2.0, 0.15
        local function fCurve(v) return (exp(K_CURVATURE*v) - 1)/(exp(K_CURVATURE) - 1) end
        local function fDeadzone(v) return fCurve((v - K_DEADZONE)/(1 - K_DEADZONE)) end
        return sign(x)*clamp(fDeadzone(abs(x)), 0, 1)
    end

    local function StartCapture()
        CAS:BindActionAtPriority(inputBindNames.KB, function(_, state, input)
            keyboard[input.KeyCode.Name] = state == Enum.UserInputState.Begin and 1 or 0
            return Enum.ContextActionResult.Sink
        end, false, Enum.ContextActionPriority.High.Value,
            Enum.KeyCode.W,Enum.KeyCode.U,Enum.KeyCode.A,Enum.KeyCode.H,Enum.KeyCode.S,Enum.KeyCode.J,Enum.KeyCode.D,Enum.KeyCode.K,
            Enum.KeyCode.E,Enum.KeyCode.I,Enum.KeyCode.Q,Enum.KeyCode.Y,Enum.KeyCode.Up,Enum.KeyCode.Down
        )
        CAS:BindActionAtPriority(inputBindNames.MousePan, function(_, _, input)
            local d = input.Delta
            mouse.Delta = Vector2.new(-d.y, -d.x)
            return Enum.ContextActionResult.Sink
        end, false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.MouseMovement)
        CAS:BindActionAtPriority(inputBindNames.Wheel, function(_, _, input)
            mouse[input.UserInputType.Name] = -input.Position.z
            return Enum.ContextActionResult.Sink
        end, false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.MouseWheel)
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
        for k in pairs(gamepad) do gamepad[k] = typeof(gamepad[k])=="Vector2" and Vector2.new() or 0 end
        for k in pairs(keyboard) do keyboard[k] = 0 end
        mouse.Delta = Vector2.new(); mouse.MouseWheel = 0
        for _,n in pairs(inputBindNames) do CAS:UnbindAction(n) end
    end

    local hudCache = {}
    local function pushGuiState()
        hudCache.core = {
            Backpack = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack),
            Chat     = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Chat),
            Health   = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Health),
            PlayerList = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList),
        }
        for k,v in pairs(hudCache.core) do StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType[k], false) end
        local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
        hudCache.screens = {}
        if pg then
            for _,gui in ipairs(pg:GetChildren()) do
                if gui:IsA("ScreenGui") and gui.Enabled then
                    hudCache.screens[#hudCache.screens+1] = gui
                    gui.Enabled = false
                end
            end
        end
    end
    local function popGuiState()
        if hudCache.core then
            for k,v in pairs(hudCache.core) do StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType[k], v) end
        end
        if hudCache.screens then
            for _,gui in ipairs(hudCache.screens) do if gui.Parent then gui.Enabled = true end end
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
                if humRef then humRef.Jump = false end
            end)
        end
    end
    local function enableJump()
        if jumpConn then jumpConn:Disconnect(); jumpConn = nil end
        if humRef and humRef.SetStateEnabled then
            humRef:SetStateEnabled(Enum.HumanoidStateType.Jumping, humJumpState ~= false)
        end
        humRef = nil; humJumpState = nil
    end

    local function velInput(dt, sens)
        navSpeed = clamp(navSpeed + dt*(keyboard.Up - keyboard.Down)*0.75, 0.01, 4)
        local g = Vector3.new(
            thumbstickCurve(gamepad.Thumbstick1.X),
            thumbstickCurve(gamepad.ButtonR2) - thumbstickCurve(gamepad.ButtonL2),
            thumbstickCurve(-gamepad.Thumbstick1.Y)
        )
        local k = Vector3.new(
            keyboard.D - keyboard.A + keyboard.K - keyboard.H,
            keyboard.E - keyboard.Q + keyboard.I - keyboard.Y,
            keyboard.S - keyboard.W + keyboard.J - keyboard.U
        )
        local shift = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
        return (g + k) * (64 * navSpeed * (shift and 0.25 or 1) * sens)
    end
    local function panInput(dt, sens)
        local gp = Vector2.new( thumbstickCurve(gamepad.Thumbstick2.Y), thumbstickCurve(-gamepad.Thumbstick2.X) ) * (pi/8)
        local km = mouse.Delta * (pi/64)
        mouse.Delta = Vector2.new()
        return (gp + km) * (8 * sens)
    end
    local function fovInput()
        local gp = (gamepad.ButtonX - gamepad.ButtonY) * 0.25
        local mw = mouse.MouseWheel * 1.0
        mouse.MouseWheel = 0
        return gp + mw
    end

    -- Use a simple boolean instead of a (nil) renderstep "connection"
    local freecamOn = false

    local function StepFreecam(dt)
        local sens = Options.FreecamSensitivity.Value or 1
        local vel = velSpring:Update(dt, velInput(dt, sens))
        local pan = panSpring:Update(dt, panInput(dt, sens))
        local fov = fovSpring:Update(dt, fovInput())

        local zoomFactor = sqrt(tan(rad(70/2))/tan(rad(cameraFov/2)))
        cameraFov = clamp(cameraFov + fov*300*(dt/zoomFactor), 1, 120)
        cameraRot = cameraRot + pan*(dt/zoomFactor)
        cameraRot = Vector2.new(clamp(cameraRot.X, -PITCH_LIMIT, PITCH_LIMIT), cameraRot.Y%(2*pi))

        local cf = CFrame.new(cameraPos) * CFrame.fromOrientation(cameraRot.X, cameraRot.Y, 0) * CFrame.new(vel*dt)
        cameraPos = cf.Position

        Camera.CFrame = cf
        Camera.Focus  = cf
        Camera.FieldOfView = cameraFov
    end

    local function StartFreecam()
        if freecamOn then return end

        -- seed camera
        local cf = Camera.CFrame
        cameraRot = Vector2.new(cf:toEulerAnglesYXZ()); cameraPos = cf.Position; cameraFov = Camera.FieldOfView
        velSpring:Reset(Vector3.new()); panSpring:Reset(Vector2.new()); fovSpring:Reset(0)

        -- prepare world
        pushGuiState()
        disableJump()
        Camera.CameraType = Enum.CameraType.Scriptable

        -- lock cursor so mouse move always pans (no RMB needed)
        UIS.MouseIconEnabled = false
        UIS.MouseBehavior = Enum.MouseBehavior.LockCenter

        StartCapture()
        RunService:BindToRenderStep("CerbFreecam", Enum.RenderPriority.Camera.Value, StepFreecam)
        freecamOn = true
    end

    local function StopFreecam()
        if not freecamOn then return end
        RunService:UnbindFromRenderStep("CerbFreecam")

        StopCapture()
        enableJump()

        Camera.CameraType = Enum.CameraType.Custom
        UIS.MouseBehavior = Enum.MouseBehavior.Default
        UIS.MouseIconEnabled = true

        -- clear residual mouse delta
        mouse.Delta = Vector2.new(); mouse.MouseWheel = 0

        popGuiState()
        freecamOn = false
    end

    -- Toggle wiring (UI)
    Toggles.FreecamEnabled:OnChanged(function()
        if Toggles.FreecamEnabled.Value then StartFreecam() else StopFreecam() end
    end)

    -- Cleanup on unload
    Library:OnUnload(function()
        if Toggles.InfiniteCamera and Toggles.InfiniteCamera.Value then Toggles.InfiniteCamera:SetValue(false) end
        if Toggles.NoFog and Toggles.NoFog.Value then Toggles.NoFog:SetValue(false) end
        if Toggles.XRay and Toggles.XRay.Value then Toggles.XRay:SetValue(false) end
        if Toggles.Fullbright and Toggles.Fullbright.Value then Toggles.Fullbright:SetValue(false) end
        if Toggles.FreecamEnabled and Toggles.FreecamEnabled.Value then Toggles.FreecamEnabled:SetValue(false) end
        fbOff(); nfOff(); setXRay(false)
        if freecamOn then StopFreecam() end
    end)
end
