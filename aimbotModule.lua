return function(a)
    -- Dependency injection
    local Services, References, Tabs, Library = a.Services, a.References, a.Tabs, a.Library
    local Players, Workspace, RunService, UserInputService = Services.Players, Services.Workspace, Services.RunService, Services.UserInputService

    -- Namespaced config in getgenv to avoid collisions
    local root = getgenv()
    root.CERB = root.CERB or {}
    root.CERB.Aimbot = root.CERB.Aimbot or {}
    local cfg = root.CERB.Aimbot

    -- camera accessor
    local function camera()
        return References.camera or Workspace.CurrentCamera
    end

    -- defaults (only set if not present)
    cfg.Enabled            = (cfg.Enabled ~= nil) and cfg.Enabled or false
    cfg.AimKey             = cfg.AimKey or Enum.KeyCode.Q
    cfg.FOV                = cfg.FOV or 80
    cfg.FOVColor           = cfg.FOVColor or Color3.fromRGB(0,255,0)
    cfg.ShowFOV            = (cfg.ShowFOV ~= nil) and cfg.ShowFOV or false
    cfg.Smoothness         = cfg.Smoothness or 0.25
    cfg.Prediction         = cfg.Prediction or 0
    cfg.DropCompensation   = cfg.DropCompensation or 0
    cfg.TargetParts        = cfg.TargetParts or {"Head"}
    cfg.TargetTypes        = cfg.TargetTypes or {"Players"}
    cfg.WallCheck          = (cfg.WallCheck ~= nil) and cfg.WallCheck or false
    cfg.TeamCheck          = (cfg.TeamCheck ~= nil) and cfg.TeamCheck or false
    cfg.MobileAutoAim      = (cfg.MobileAutoAim ~= nil) and cfg.MobileAutoAim or false
    cfg.ShowAimLine        = (cfg.ShowAimLine ~= nil) and cfg.ShowAimLine or false
    cfg.ProjectileSpeed    = cfg.ProjectileSpeed or 0        -- 0 = hitscan / no ballistic math
    cfg.DeadzonePixels     = cfg.DeadzonePixels or 6

    -- Drawing support (some executors don't support Drawing)
    local hasDrawing, Drawing = pcall(function() return Drawing end)
    hasDrawing = hasDrawing and type(Drawing) == "table"
    local fovCircle, aimLine
    if hasDrawing then
        local ok, circle = pcall(function() return Drawing.new("Circle") end)
        local ok2, line = pcall(function() return Drawing.new("Line") end)
        if ok and ok2 and circle and line then
            fovCircle = circle
            fovCircle.Thickness, fovCircle.Filled = 1, false
            fovCircle.Color = cfg.FOVColor
            fovCircle.Visible = cfg.ShowFOV

            aimLine = line
            aimLine.Color = Color3.fromRGB(255,0,0)
            aimLine.Thickness = 1
            aimLine.Visible = false
        else
            hasDrawing = false
            fovCircle, aimLine = nil, nil
        end
    end

    -- Highlight
    local highlight = cfg.Highlight or Instance.new("Highlight")
    highlight.Name = "AimbotTargetHighlight"
    highlight.FillColor = Color3.new(1,0,0)
    highlight.OutlineColor = Color3.new(0,0,0)
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 0.25
    highlight.OutlineTransparency = 0
    highlight.Adornee = nil
    highlight.Enabled = false
    local coreParent = (gethui and gethui()) or game:GetService("CoreGui")
    if highlight.Parent ~= coreParent then highlight.Parent = coreParent end
    cfg.Highlight = highlight

    -- Reusable RaycastParams
    local rcParams = RaycastParams.new()
    rcParams.FilterType = Enum.RaycastFilterType.Exclude
    rcParams.FilterDescendantsInstances = {}

    local function setRaycastFilter(excludeInstances)
        -- always exclude local character so raycasts don't hit self
        local t = {}
        if References.character then t[#t+1] = References.character end
        if excludeInstances then
            if type(excludeInstances) == "table" then
                for _,v in ipairs(excludeInstances) do t[#t+1] = v end
            else
                t[#t+1] = excludeInstances
            end
        end
        rcParams.FilterDescendantsInstances = t
    end

    -- NPC cache & watcher (avoid GetDescendants() every frame)
    local npcFolders = {}
    local function discoverNpcFolders()
        npcFolders = {}
        local f1 = Workspace:FindFirstChild("NPCs") or Workspace:FindFirstChild("NPCS")
        if f1 then npcFolders[#npcFolders+1] = f1 end
    end
    discoverNpcFolders()
    local npcAddConns = {}
    local function watchNpcFolder(folder)
        if not folder then return end
        local con = folder.ChildAdded:Connect(function() end) -- placeholder: existence ensures folder watched, actual scan done by npcModels()
        npcAddConns[#npcAddConns+1] = con
    end
    for _,f in ipairs(npcFolders) do watchNpcFolder(f) end

    local function npcModels()
        local out = {}
        for _,folder in ipairs(npcFolders) do
            if folder and folder.Parent then
                for _,child in ipairs(folder:GetChildren()) do
                    if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
                        out[#out+1] = child
                    end
                end
            end
        end
        return out
    end

    -- target acquisition helpers
    local function isFriendly(model)
        if not cfg.TeamCheck then return false end
        local pl = Players:GetPlayerFromCharacter(model)
        if not pl or not References.player then return false end
        -- prefer Team objects; fall back to TeamColor
        if References.player.Team and pl.Team then
            return References.player.Team == pl.Team
        end
        return References.player.TeamColor == pl.TeamColor
    end

    local function wallFree(part)
        if not cfg.WallCheck then return true end
        local cam = camera()
        if not cam or not part then return false end
        setRaycastFilter({References.character})
        local origin = cam.CFrame.Position
        local dir = part.Position - origin
        local res = Workspace:Raycast(origin, dir, rcParams)
        if not res then return true end
        local inst = res.Instance
        return inst and inst:IsDescendantOf(part.Parent)
    end

    local function collectCandidates()
        local out = {}
        local wantPlayers = table.find(cfg.TargetTypes, "Players") ~= nil
        local wantNPCs = table.find(cfg.TargetTypes, "NPCs") ~= nil
        if wantPlayers then
            for _,pl in ipairs(Players:GetPlayers()) do
                if pl ~= References.player and pl.Character then out[#out+1] = pl.Character end
            end
        end
        if wantNPCs then
            local list = npcModels()
            for _,m in ipairs(list) do out[#out+1] = m end
        end
        return out
    end

    -- sticky target with throttled reacquire
    local currentTarget = nil
    local lastAcquire = 0
    local ACQUIRE_INTERVAL = 0.075 -- seconds

    local function acquireTarget(force)
        local now = tick()
        if not force and currentTarget then
            -- validate current
            if currentTarget.Parent and currentTarget:FindFirstChildOfClass("Humanoid") and currentTarget:FindFirstChildOfClass("Humanoid").Health > 0 then
                return currentTarget
            else
                currentTarget = nil
            end
        end
        if not force and (now - lastAcquire) < ACQUIRE_INTERVAL then
            return currentTarget
        end
        lastAcquire = now

        local cam = camera()
        if not cam then return nil end
        local center = Vector2.new(cam.ViewportSize.X*0.5, cam.ViewportSize.Y*0.5)
        local best, bestScore = nil, math.huge
        local targetPartName = cfg.TargetParts[1]

        for _,cand in ipairs(collectCandidates()) do
            local hum = cand:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then goto CONT end
            if cfg.TeamCheck and isFriendly(cand) then goto CONT end

            local part = cand:FindFirstChild(targetPartName) or cand:FindFirstChild("HumanoidRootPart")
            if not part then goto CONT end

            local screenPos, onScreen = cam:WorldToViewportPoint(part.Position)
            if not onScreen or screenPos.Z <= 0 then goto CONT end

            local pix = Vector2.new(screenPos.X, screenPos.Y)
            local fovErr = (pix - center).Magnitude
            if fovErr > cfg.FOV then goto CONT end

            if not wallFree(part) then goto CONT end

            -- scoring: prefer smaller fovErr, then closer distance
            local dist3 = (part.Position - cam.CFrame.Position).Magnitude
            local score = (fovErr / cfg.FOV) * 0.8 + math.clamp(dist3 / 200, 0, 1) * 0.2

            if score < bestScore then
                bestScore = score
                best = cand
            end
            ::CONT::
        end

        currentTarget = best
        return currentTarget
    end

    -- Aim lead & drop handling
    local gravityVec = Vector3.new(0, -Workspace.Gravity, 0)
    local function leadPoint(origin, targetPos, targetVel)
        if cfg.ProjectileSpeed and cfg.ProjectileSpeed > 0 then
            -- crude ballistic first-order approximation
            local toTarget = targetPos - origin
            local distance = toTarget.Magnitude
            local t = distance / cfg.ProjectileSpeed -- first pass
            -- refine once
            local pred = targetPos + targetVel * t + 0.5 * gravityVec * (t*t)
            return pred
        else
            -- hitscan-ish: simple linear prediction + optional drop compensation
            return targetPos + targetVel * cfg.Prediction + Vector3.new(0, (distance and (distance/100)*cfg.DropCompensation or 0), 0)
        end
    end

    -- Exponential smoothing helper (frame-independent)
    local function expSmooth(alphaPerSec, dt)
        return 1 - math.exp(-math.max(alphaPerSec,1e-6) * dt)
    end

    -- Should aim? handle mobile and key variants
    local function shouldAim()
        if UserInputService.TouchEnabled then
            return cfg.MobileAutoAim
        end
        -- support AimKey being Enum.KeyCode or string name
        if typeof(cfg.AimKey) == "EnumItem" then
            if UserInputService:IsKeyDown(cfg.AimKey) then return true end
        elseif type(cfg.AimKey) == "string" then
            local keyEnum = Enum.KeyCode[cfg.AimKey]
            if keyEnum and UserInputService:IsKeyDown(keyEnum) then return true end
        end
        -- mouse right button support
        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return true end
        return false
    end

    -- Aim action: moves the camera toward the target lead point using dt-scaled smoothing
    local lastTick = tick()
    local function aimAt(model, dt)
        local cam = camera()
        if not (cam and model) then return end
        local part = model:FindFirstChild(cfg.TargetParts[1]) or model:FindFirstChild("HumanoidRootPart")
        if not part then return end

        local vel = part.AssemblyLinearVelocity or part:FindFirstChildWhichIsA("BasePart") and part.Velocity or Vector3.zero
        local origin = cam.CFrame.Position

        -- compute lead & drop compensation
        local targetLead = leadPoint(origin, part.Position, vel)
        -- compute angular error and adapt responsiveness
        local toDir = (targetLead - origin)
        if toDir.Magnitude <= 0 then return end
        local toUnit = toDir.Unit
        local lookVec = cam.CFrame.LookVector
        local dot = math.clamp(lookVec:Dot(toUnit), -1, 1)
        local angleErr = math.acos(dot) -- radians

        -- responsiveness: bigger error -> faster response
        local baseResp = 8  -- per-second base
        local resp = baseResp + (22 * (angleErr / math.rad(cfg.FOV))) -- in range [8,30] roughly
        -- scale by Smoothness (lower Smoothness = faster response, invert to keep semantics)
        local smoothFactor = math.clamp(1 - cfg.Smoothness, 0.01, 1) * resp
        local alpha = expSmooth(smoothFactor, dt)

        -- apply lerp
        local newCF = CFrame.new(origin, targetLead)
        cam.CFrame = cam.CFrame:Lerp(newCF, alpha)

        -- Aim line drawing (screen)
        if cfg.ShowAimLine and hasDrawing and aimLine then
            local vs = cam.ViewportSize
            aimLine.From = Vector2.new(vs.X*0.5, vs.Y)
            local sc = cam:WorldToViewportPoint(targetLead)
            aimLine.To = Vector2.new(sc.X, sc.Y)
            aimLine.Visible = true
        elseif hasDrawing and aimLine then
            aimLine.Visible = false
        end
    end

    -- Update FOV circle position & visuals
    local function updateFOV()
        if not hasDrawing or not fovCircle then return end
        local cam = camera()
        if not cam then return end
        local vs = cam.ViewportSize
        fovCircle.Position = Vector2.new(vs.X*0.5, vs.Y*0.5)
        fovCircle.Radius = cfg.FOV
        fovCircle.Color = cfg.FOVColor
        fovCircle.Visible = cfg.ShowFOV
    end

    -- Main render loop connections
    local fovConn, aimConn, camConn
    fovConn = RunService.RenderStepped:Connect(updateFOV)

    aimConn = RunService.RenderStepped:Connect(function(dt)
        -- dt here is seconds passed since last render step; some executors pass dt directly, others not — safeguard:
        dt = tonumber(dt) or math.max(1/60, tick() - lastTick)
        lastTick = tick()

        if not cfg.Enabled then
            if highlight and highlight.Enabled then highlight.Enabled = false; highlight.Adornee = nil end
            if hasDrawing and aimLine then aimLine.Visible = false end
            return
        end

        -- sticky target logic
        local target = acquireTarget()
        if target then
            -- highlight
            highlight.Adornee = target
            highlight.Enabled = true

            if shouldAim() then
                aimAt(target, dt)
            else
                if hasDrawing and aimLine then aimLine.Visible = false end
            end
        else
            -- no target
            if highlight and highlight.Enabled then highlight.Enabled = false; highlight.Adornee = nil end
            if hasDrawing and aimLine then aimLine.Visible = false end
        end
    end)

    camConn = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateFOV)

    -- UI: register controls in the provided Tab group
    local group = Tabs.Combat:AddLeftGroupbox("Aimbot", "crosshair")
    group:AddToggle("AB_AimbotEnabled", {Text = "Enable Aimbot", Default = cfg.Enabled, Callback = function(v) cfg.Enabled = v end})
    group:AddToggle("AB_MobileAutoAim", {Text = "Mobile Auto Aim", Default = cfg.MobileAutoAim, Callback = function(v) cfg.MobileAutoAim = v end})
    group:AddToggle("AB_ShowAimLine", {Text = "Show Aim Line", Default = cfg.ShowAimLine, Callback = function(v) cfg.ShowAimLine = v if hasDrawing and aimLine then aimLine.Visible = false end end})
    group:AddDropdown("AB_TargetTypes", { Text = "Target Types", Values = {"Players","NPCs"}, Default = cfg.TargetTypes, Multi = true, Callback = function(v) cfg.TargetTypes = v end })
    group:AddDropdown("AB_TargetParts", { Text = "Target Part", Values = {"Head","HumanoidRootPart","UpperTorso","LowerTorso","Torso"}, Default = cfg.TargetParts[1], Callback = function(v) cfg.TargetParts = {v} end })
    group:AddToggle("AB_TeamCheck", {Text = "Team Check", Default = cfg.TeamCheck, Callback = function(v) cfg.TeamCheck = v end})
    group:AddToggle("AB_WallCheck", {Text = "Wall Check", Default = cfg.WallCheck, Callback = function(v) cfg.WallCheck = v end})
    group:AddLabel("FOV Circle Color"):AddColorPicker("FOVColorPicker", {Default = cfg.FOVColor, Title = "FOV Circle Color", Callback = function(col) cfg.FOVColor = col if hasDrawing and fovCircle then fovCircle.Color = col end end})
    group:AddToggle("AB_ShowFOVCircle", {Text = "Show FOV Circle", Default = cfg.ShowFOV, Callback = function(v) cfg.ShowFOV = v if hasDrawing and fovCircle then fovCircle.Visible = v end end})
    group:AddSlider("AB_FOVRadius", {Text = "FOV Radius", Default = cfg.FOV, Min = 20, Max = 300, Rounding = 0, Callback = function(v) cfg.FOV = v if hasDrawing and fovCircle then fovCircle.Radius = v end end})
    group:AddSlider("AB_Smoothness", {Text = "Smoothness", Default = cfg.Smoothness, Min = 0.01, Max = 1, Rounding = 2, Callback = function(v) cfg.Smoothness = v end})
    group:AddSlider("AB_Prediction", {Text = "Prediction", Default = cfg.Prediction, Min = 0, Max = 0.5, Rounding = 2, Callback = function(v) cfg.Prediction = v end})
    group:AddSlider("AB_DropCompensation", {Text = "Drop Compensation", Default = cfg.DropCompensation, Min = 0, Max = 5, Rounding = 2, Callback = function(v) cfg.DropCompensation = v end})
    group:AddSlider("AB_ProjectileSpeed", {Text = "Projectile Speed (0=hitscan)", Default = cfg.ProjectileSpeed, Min = 0, Max = 2000, Rounding = 0, Callback = function(v) cfg.ProjectileSpeed = v end})
    group:AddLabel("Aim Key"):AddKeyPicker("AB_AimKey", {
        Default = (typeof(cfg.AimKey) == "EnumItem" and cfg.AimKey.Name) or tostring(cfg.AimKey) or "Q",
        NoUI = false,
        Text = "Hold/Press to Aim",
        ChangedCallback = function(val)
            -- KeyPicker might return Enum.KeyCode or string; store either
            if typeof(val) == "EnumItem" then
                cfg.AimKey = val
            elseif type(val) == "string" then
                -- try to resolve to Enum.KeyCode if possible
                cfg.AimKey = (Enum.KeyCode[val] and Enum.KeyCode[val]) or val
            else
                cfg.AimKey = val
            end
        end
    })

    -- teardown / stop function
    local function stop()
        if aimConn then aimConn:Disconnect(); aimConn = nil end
        if fovConn then fovConn:Disconnect(); fovConn = nil end
        if camConn then camConn:Disconnect(); camConn = nil end
        -- destroy drawings if present
        if hasDrawing then
            pcall(function() if fovCircle and fovCircle.Remove then fovCircle:Remove() end end)
            pcall(function() if aimLine and aimLine.Remove then aimLine:Remove() end end)
        end
        -- disable visuals
        if fovCircle then fovCircle.Visible = false end
        if aimLine then aimLine.Visible = false end
        if highlight then highlight.Enabled = false; highlight.Adornee = nil end
        -- clear NPC watchers
        for _,c in ipairs(npcAddConns) do pcall(function() c:Disconnect() end) end
        npcAddConns = {}
        -- clear cached state
        currentTarget = nil
    end

    _G.stopAimbot = stop
    return stop
end
