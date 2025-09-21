-- radar.lua  (module-like self-contained)
return function(Tabs, Services, References)
    -- == PLAYER RADAR == --
    local RadarGroup = Tabs.ESP:AddRightGroupbox("Player Radar", "map")

    local radar = {
        gui = nil, conn = nil,
        range = 500, scale = 1,
        mode = "Camera",
        rings = {},
    }

    local function destroyRadar()
        if radar.conn then radar.conn:Disconnect(); radar.conn = nil end
        if radar.gui then radar.gui:Destroy(); radar.gui = nil end
        radar.rings = {}
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
                                rx = rel.X
                                rz = rel.Z
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

    -- UI
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
end
