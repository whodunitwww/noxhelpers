return function(ctx)
    -- ctx = { Services, References, Tabs, Library }
    local S, R, Tabs, Library = ctx.Services, ctx.References, ctx.Tabs, ctx.Library
    local P, W, RS, UIS = S.Players, S.Workspace, S.RunService, S.UserInputService

    -- shared env (persists across reloads)
    local E = getgenv()
    local function Cam() return R.camera or S.Workspace.CurrentCamera end

    -- defaults (only fill if missing)
    E.AimbotEnabled    = (E.AimbotEnabled    ~= nil) and E.AimbotEnabled    or false
    E.AimKey           = E.AimKey           or Enum.KeyCode.Q
    E.FOV              = E.FOV              or 80
    E.FOVColor         = E.FOVColor         or Color3.fromRGB(0,255,0)
    E.FOVCircleVisible = (E.FOVCircleVisible ~= nil) and E.FOVCircleVisible or false
    E.Smoothness       = E.Smoothness       or 0.25
    E.Prediction       = E.Prediction       or 0
    E.DropCompensation = E.DropCompensation or 0
    E.TargetParts      = E.TargetParts      or {"Head"}
    E.TargetTypes      = E.TargetTypes      or {"Players"}   -- {"Players","NPCs"}
    E.WallCheck        = (E.WallCheck ~= nil) and E.WallCheck or false
    E.TeamCheck        = (E.TeamCheck ~= nil) and E.TeamCheck or false
    E.MobileAutoAim    = (E.MobileAutoAim ~= nil) and E.MobileAutoAim or false
    E.ShowAimLine      = (E.ShowAimLine ~= nil) and E.ShowAimLine or false

    -- drawings (reuse if exist)
    E.FOVCircle = E.FOVCircle or Drawing.new("Circle")
    E.FOVCircle.Thickness, E.FOVCircle.Filled = 1, false

    E.AimLine = E.AimLine or Drawing.new("Line")
    E.AimLine.Color, E.AimLine.Thickness, E.AimLine.Visible = Color3.fromRGB(255,0,0), 1, false

    -- highlight (use CoreGui/gethui)
    E.CurrentHighlight = E.CurrentHighlight or Instance.new("Highlight")
    do
        local h = E.CurrentHighlight
        h.Name = "AimbotTargetHighlight"
        h.FillColor, h.OutlineColor = Color3.new(1,0,0), Color3.new(0,0,0)
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.FillTransparency, h.OutlineTransparency = 0.25, 0
        h.Adornee, h.Enabled = nil, false
        local parent = (gethui and gethui()) or game:GetService("CoreGui")
        if h.Parent ~= parent then h.Parent = parent end
    end

    -- small helpers
    local function updateFOV()
        local c = Cam(); if not c then return end
        local v = c.ViewportSize
        E.FOVCircle.Position = Vector2.new(v.X*0.5, v.Y*0.5)
        E.FOVCircle.Radius   = E.FOV
        E.FOVCircle.Color    = E.FOVColor
        E.FOVCircle.Visible  = E.FOVCircleVisible
    end

    local function visible(part)
        if not E.WallCheck then return true end
        local c = Cam(); if not c then return false end
        local origin = c.CFrame.Position
        local dir = (part.Position - origin)
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = { R.character }
        local hit = W:Raycast(origin, dir, rp)
        return (not hit) or (hit.Instance and hit.Instance:IsDescendantOf(part.Parent))
    end

    local function aiming()
        if UIS.TouchEnabled then return E.MobileAutoAim end
        if typeof(E.AimKey) ~= "EnumItem" then return false end
        return UIS:IsKeyDown(E.AimKey) or UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
    end

    local function collectCandidates()
        local t = {}
        local wantPlayers = table.find(E.TargetTypes, "Players") ~= nil
        local wantNPCs    = table.find(E.TargetTypes, "NPCs")    ~= nil

        if wantPlayers then
            for _, pl in ipairs(P:GetPlayers()) do
                if pl ~= R.player and pl.Character then t[#t+1] = pl.Character end
            end
        end
        if wantNPCs then
            local folder = W:FindFirstChild("NPCS") or W:FindFirstChild("NPCs")
            if folder then
                for _, m in ipairs(folder:GetDescendants()) do
                    if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
                        t[#t+1] = m
                    end
                end
            end
        end
        return t
    end

    local function closestTarget()
        local c = Cam(); if not c then return nil end
        local center = E.FOVCircle.Position
        local aimName = E.TargetParts[1]
        local best, bestDist

        for _, char in ipairs(collectCandidates()) do
            local h = char:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then
                if not E.TeamCheck or (function()
                    local owner = P:GetPlayerFromCharacter(char)
                    return not (owner and R.player.Team and owner.Team and owner.Team == R.player.Team)
                end)() then
                    local part = char:FindFirstChild(aimName) or char:FindFirstChild("HumanoidRootPart")
                    if part then
                        local sp, on = c:WorldToViewportPoint(part.Position)
                        if on then
                            local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                            if d <= E.FOV and (not bestDist or d < bestDist) and visible(part) then
                                best, bestDist = char, d
                            end
                        end
                    end
                end
            end
        end
        return best
    end

    local function aimAt(char)
        local c = Cam(); if not c then return end
        local part = char:FindFirstChild(E.TargetParts[1]) or char:FindFirstChild("HumanoidRootPart")
        if not part then return end

        -- velocity support for both parts (BasePart.Velocity or AssemblyLinearVelocity)
        local vel = (part.AssemblyLinearVelocity or part.Velocity or Vector3.zero)
        local camPos = c.CFrame.Position
        local tgtPos = part.Position + vel * E.Prediction
        local dist   = (tgtPos - camPos).Magnitude
        local drop   = Vector3.new(0, (dist/100) * E.DropCompensation, 0)
        local aimPos = tgtPos + drop

        c.CFrame = c.CFrame:Lerp(CFrame.new(camPos, aimPos), math.clamp(E.Smoothness, 0.01, 1))

        if E.ShowAimLine then
            local v = c.ViewportSize
            E.AimLine.From = Vector2.new(v.X*0.5, v.Y) -- bottom-center
            local to2d = c:WorldToViewportPoint(aimPos)
            E.AimLine.To   = Vector2.new(to2d.X, to2d.Y)
            E.AimLine.Visible = true
        else
            E.AimLine.Visible = false
        end
    end

    -- live hooks
    local fovConn   = RS.RenderStepped:Connect(updateFOV)
    local mainConn  = RS.RenderStepped:Connect(function()
        if not E.AimbotEnabled then
            E.CurrentHighlight.Enabled, E.CurrentHighlight.Adornee = false, nil
            E.AimLine.Visible = false
            return
        end
        local tgt = closestTarget()
        if tgt then
            E.CurrentHighlight.Adornee = tgt
            E.CurrentHighlight.Enabled = true
            if aiming() then aimAt(tgt) else E.AimLine.Visible = false end
        else
            E.CurrentHighlight.Enabled, E.CurrentHighlight.Adornee = false, nil
            E.AimLine.Visible = false
        end
    end)

    -- resync when CurrentCamera swaps
    local camConn = W:GetPropertyChangedSignal("CurrentCamera"):Connect(updateFOV)

    -- UI
    local GB = Tabs.Combat:AddLeftGroupbox("Aimbot", "crosshair")

    GB:AddToggle("AB_AimbotEnabled", { Text="Enable Aimbot", Default=E.AimbotEnabled,
        Callback=function(v) E.AimbotEnabled=v end })

    GB:AddToggle("AB_MobileAutoAim", { Text="Mobile Auto Aim", Default=E.MobileAutoAim,
        Callback=function(v) E.MobileAutoAim=v end })

    GB:AddToggle("AB_ShowAimLine", { Text="Show Aim Line", Default=E.ShowAimLine,
        Callback=function(v) E.ShowAimLine=v; E.AimLine.Visible=false end })

    GB:AddDropdown("AB_TargetTypes", {
        Text="Target Types", Values={"Players","NPCs"}, Default=E.TargetTypes, Multi=true,
        Callback=function(vals) E.TargetTypes = vals end
    })

    GB:AddDropdown("AB_TargetParts", {
        Text="Target Part",
        Values={"Head","HumanoidRootPart","UpperTorso","LowerTorso","Torso"},
        Default=E.TargetParts[1],
        Callback=function(o) E.TargetParts = { o } end
    })

    GB:AddToggle("AB_TeamCheck", { Text="Team Check", Default=E.TeamCheck,
        Callback=function(v) E.TeamCheck=v end })

    GB:AddToggle("AB_WallCheck", { Text="Wall Check", Default=E.WallCheck,
        Callback=function(v) E.WallCheck=v end })

    GB:AddLabel("FOV Circle Color"):AddColorPicker("FOVColorPicker", {
        Default=E.FOVColor, Title="FOV Circle Color",
        Callback=function(c) E.FOVColor=c; E.FOVCircle.Color=c end
    })

    GB:AddToggle("AB_ShowFOVCircle", {
        Text="Show FOV Circle", Default=E.FOVCircleVisible,
        Callback=function(v) E.FOVCircleVisible=v; E.FOVCircle.Visible=v end
    })

    GB:AddSlider("AB_FOVRadius", {
        Text="FOV Radius", Default=E.FOV, Min=20, Max=300, Rounding=0,
        Callback=function(v) E.FOV=v; E.FOVCircle.Radius=v end
    })

    GB:AddSlider("AB_Smoothness", {
        Text="Smoothness", Default=E.Smoothness, Min=0.01, Max=1, Rounding=2,
        Callback=function(v) E.Smoothness=v end
    })

    GB:AddSlider("AB_Prediction", {
        Text="Prediction", Default=E.Prediction, Min=0, Max=0.5, Rounding=2,
        Callback=function(v) E.Prediction=v end
    })

    GB:AddSlider("AB_DropCompensation", {
        Text="Drop Compensation", Default=E.DropCompensation, Min=0, Max=5, Rounding=2,
        Callback=function(v) E.DropCompensation=v end
    })

    GB:AddLabel("Aim Key"):AddKeyPicker("AB_AimKey", {
        Default = (E.AimKey and E.AimKey.Name) or "Q",
        NoUI = false, Text = "Hold/Press to Aim",
        ChangedCallback = function(newKey) E.AimKey = newKey end
    })

    -- stop function for unloader
    local function stop()
        if mainConn then mainConn:Disconnect() end
        if fovConn  then fovConn:Disconnect()  end
        if camConn  then camConn:Disconnect()  end
        -- hide visuals (keep objects for reuse)
        E.FOVCircle.Visible = false
        E.AimLine.Visible   = false
        if E.CurrentHighlight then
            E.CurrentHighlight.Enabled = false
            E.CurrentHighlight.Adornee = nil
        end
    end

    -- also export on _G if you like
    _G.stopAimbot = stop

    return stop
end
