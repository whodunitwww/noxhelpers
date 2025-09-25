return function(Services, Tabs, References, Toggles, Options, Library)
    -- == Shorthands ==
    local CAS = Services.ContextActionService
    local UIS = Services.UserInputService
    local RS  = Services.RunService
    local PG  = Services.Players.LocalPlayer and Services.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local SG  = Services.StarterGui
    local Cam = Services.Workspace.CurrentCamera

    local FreecamGroup = Tabs.Player:AddRightGroupbox("Utils", "video")
    
    -- == UI ==
    FreecamGroup:AddToggle("Freecam_Enabled", { Text = "Enable Freecam", Default = false })
        :AddKeyPicker("Freecam_Key", { Default = "P", SyncToggleState = true, Mode = "Toggle", Text = "Freecam Key" })

    FreecamGroup:AddSlider("Freecam_Sens", {
        Text = "Sensitivity",
        Default = 1.0, Min = 0.2, Max = 3.0, Rounding = 2,
        Tooltip = "Scales movement, look and zoom speeds"
    })

    -- == Small spring (critically damped) ==
    local pi, exp = math.pi, math.exp
    local Spring = {}; Spring.__index = Spring
    function Spring.new(freq, pos) return setmetatable({ f=freq, p=pos, v=pos*0 }, Spring) end
    function Spring:Reset(pos) self.p=pos; self.v=self.p*0 end
    function Spring:Update(dt, goal)
        local f = self.f*2*pi
        local p0, v0 = self.p, self.v
        local off = goal - p0
        local decay = exp(-f*dt)
        self.p = goal + (v0*dt - off*(f*dt + 1))*decay
        self.v = (f*dt*(off*f - v0) + v0)*decay
        return self.p
    end

    -- == Gains (scaled by sensitivity) ==
    local baseNAV, basePAN, baseFOV = 64, (pi/64)*8, 300
    local function gains()
        local s = Options.Freecam_Sens and (Options.Freecam_Sens.Value or 1) or 1
        return baseNAV*s, basePAN*s, baseFOV*s
    end

    -- == State ==
    local enabled = false
    local camPos, camRot, camFov = Vector3.new(), Vector2.new(), 70
    local velSpring = Spring.new(1.5, Vector3.new())
    local panSpring = Spring.new(1.0,  Vector2.new())
    local fovSpring = Spring.new(4.0,  0)

    local kb = {W=0,A=0,S=0,D=0,Q=0,E=0, Up=0,Down=0}
    local mouseDelta, wheelAccum = Vector2.new(), 0

    -- == Input capture ==
    local function zeroInputs()
        for k in pairs(kb) do kb[k]=0 end
        mouseDelta = Vector2.new(); wheelAccum = 0
    end

    local function onKB(_, state, input)
        local n = input.KeyCode.Name; if kb[n] == nil then return Enum.ContextActionResult.Pass end
        kb[n] = (state == Enum.UserInputState.Begin) and 1 or 0
        return Enum.ContextActionResult.Sink
    end
    local function onMouse(_, _, input)
        local d = input.Delta; mouseDelta = Vector2.new(-d.Y, -d.X)
        return Enum.ContextActionResult.Sink
    end
    local function onWheel(_, _, input)
        wheelAccum = wheelAccum - input.Position.Z
        return Enum.ContextActionResult.Sink
    end

    local function bindInputs()
        CAS:BindActionAtPriority("FC_KB", onKB, false, Enum.ContextActionPriority.High.Value,
            Enum.KeyCode.W,Enum.KeyCode.A,Enum.KeyCode.S,Enum.KeyCode.D,Enum.KeyCode.Q,Enum.KeyCode.E,
            Enum.KeyCode.Up,Enum.KeyCode.Down
        )
        CAS:BindActionAtPriority("FC_Mouse", onMouse, false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.MouseMovement)
        CAS:BindActionAtPriority("FC_Wheel", onWheel, false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.MouseWheel)
    end
    local function unbindInputs()
        zeroInputs()
        pcall(CAS.UnbindAction, CAS, "FC_KB")
        pcall(CAS.UnbindAction, CAS, "FC_Mouse")
        pcall(CAS.UnbindAction, CAS, "FC_Wheel")
    end

    -- == Save/restore player state ==
    local saved = {}
    local function pushState()
        saved = {
            CoreGuis = {
                Backpack = SG:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack),
                Chat     = SG:GetCoreGuiEnabled(Enum.CoreGuiType.Chat),
                Health   = SG:GetCoreGuiEnabled(Enum.CoreGuiType.Health),
                PlayerList = SG:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList),
            },
            Badges = pcall(function() return SG:GetCore("BadgesNotificationsActive") end) and SG:GetCore("BadgesNotificationsActive") or true,
            Points = pcall(function() return SG:GetCore("PointsNotificationsActive") end) and SG:GetCore("PointsNotificationsActive") or true,
            MouseIcon = UIS.MouseIconEnabled,
            CameraType = Cam.CameraType,
            CFrame = Cam.CFrame,
            Focus  = Cam.Focus,
            FOV    = Cam.FieldOfView,
            ShownGuis = {},
        }
        for n,_ in pairs(saved.CoreGuis) do SG:SetCoreGuiEnabled(Enum.CoreGuiType[n], false) end
        pcall(SG.SetCore, SG, "BadgesNotificationsActive", false)
        pcall(SG.SetCore, SG, "PointsNotificationsActive", false)

        if PG then
            for _, gui in ipairs(PG:GetChildren()) do
                if gui:IsA("ScreenGui") and gui.Enabled then
                    table.insert(saved.ShownGuis, gui); gui.Enabled = false
                end
            end
        end

        UIS.MouseIconEnabled = false
        Cam.CameraType = Enum.CameraType.Scriptable
    end
    local function popState()
        for n, v in pairs(saved.CoreGuis or {}) do SG:SetCoreGuiEnabled(Enum.CoreGuiType[n], v) end
        pcall(SG.SetCore, SG, "BadgesNotificationsActive", saved.Badges)
        pcall(SG.SetCore, SG, "PointsNotificationsActive", saved.Points)

        for _, gui in ipairs(saved.ShownGuis or {}) do if gui.Parent then gui.Enabled = true end end

        Cam.FieldOfView = saved.FOV or 70
        Cam.CameraType  = saved.CameraType or Enum.CameraType.Custom
        Cam.CFrame      = saved.CFrame or Cam.CFrame
        Cam.Focus       = saved.Focus or Cam.Focus
        UIS.MouseIconEnabled = (saved.MouseIcon ~= nil) and saved.MouseIcon or true
        saved = {}
    end

    -- == Per-frame update ==
    local function step(dt)
        local NAV_GAIN, PAN_GAIN, FOV_GAIN = gains()

        -- compute intended motion
        local velGoal = Vector3.new(
            (kb.D - kb.A),
            (kb.E - kb.Q),
            (kb.S - kb.W)
        )

        local panGoal = mouseDelta
        mouseDelta = Vector2.new()

        local fovGoal = wheelAccum
        wheelAccum = 0

        local vel = velSpring:Update(dt, velGoal)
        local pan = panSpring:Update(dt, panGoal)
        local fov = fovSpring:Update(dt, fovGoal)

        -- zoom factor so pan/zoom scale sensibly with FOV
        local function tanrad(x) return math.tan(math.rad(x)) end
        local zoom = math.sqrt(tanrad(70/2)/tanrad(camFov/2))

        camFov = math.clamp(camFov + fov*FOV_GAIN*(dt/zoom), 1, 120)
        camRot = camRot + pan*PAN_GAIN*(dt/zoom)
        camRot = Vector2.new(math.clamp(camRot.X, -math.rad(90), math.rad(90)), camRot.Y%(2*pi))

        local cf = CFrame.new(camPos) * CFrame.fromOrientation(camRot.X, camRot.Y, 0) * CFrame.new(vel * NAV_GAIN * dt)
        camPos = cf.Position

        Cam.CFrame = cf
        Cam.Focus  = cf
        Cam.FieldOfView = camFov
    end

    -- == Start/Stop ==
    local function start()
        if enabled then return end
        enabled = true

        local cf = Cam.CFrame
        local x,y,z = cf:toEulerAnglesYXZ()
        camRot = Vector2.new(x,y); camPos = cf.Position; camFov = Cam.FieldOfView

        velSpring:Reset(Vector3.new())
        panSpring:Reset(Vector2.new())
        fovSpring:Reset(0)

        pushState()
        bindInputs()
        RS:BindToRenderStep("Cerb_Freecam", Enum.RenderPriority.Camera.Value, step)

        Library:Notify("Freecam enabled.", 3)
    end
    local function stop()
        if not enabled then return end
        enabled = false
        RS:UnbindFromRenderStep("Cerb_Freecam")
        unbindInputs()
        popState()
        Library:Notify("Freecam disabled.", 3)
    end

    -- == Wire UI ==
    Toggles.Freecam_Enabled:OnChanged(function()
        if Toggles.Freecam_Enabled.Value then start() else stop() end
    end)
    if Options.Freecam_Sens then
        Options.Freecam_Sens:OnChanged(function()
            -- live sensitivity change; nothing else needed (gains() reads slider)
        end)
    end

    -- == Camera handle swap safety ==
    Services.Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        Cam = Services.Workspace.CurrentCamera or Cam
    end)

    -- == Return unload handler ==
    return function()
        stop()
    end
end
