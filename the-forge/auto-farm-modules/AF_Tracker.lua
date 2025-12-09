-- AF_Tracker.lua
-- Handles the Proximity Tracker HUD for ore health and drops
return function(env)
    local Services    = env.Services
    local HttpService = env.HttpService
    local notify      = env.notify
    local getLocalHRP = env.getLocalHRP
    local rockHealth  = env.rockHealth
    local getRocksFolder = env.getRocksFolder
    local ConfigFile  = env.ConfigFile

    local Players = Services.Players or game:GetService("Players")
    local UserInputService = Services.UserInputService

    local TrackerState = {
        Enabled       = false,
        Gui           = nil,
        Container     = nil,
        TargetName    = nil,
        HealthBar     = nil,
        HealthText    = nil,
        DropList      = nil,
        CachedMaxHp   = 100,
        CurrentDrops  = {},
        ActiveTarget  = nil,
        LastCheckHealth = {}
    }

    local function loadHudLayout()
        if isfile and readfile and isfile(ConfigFile) then
            local success, result = pcall(function()
                return HttpService:JSONDecode(readfile(ConfigFile))
            end)
            if success and type(result) == "table" then
                return result
            end
        end
        return nil
    end

    local function saveHudLayout(position, size)
        if not isfolder("Cerberus") then makefolder("Cerberus") end
        if not isfolder("Cerberus/The Forge") then makefolder("Cerberus/The Forge") end
        local data = {
            X = position.X.Offset,
            Y = position.Y.Offset,
            SX = size.X.Offset,
            SY = size.Y.Offset
        }
        pcall(function()
            writefile(ConfigFile, HttpService:JSONEncode(data))
        end)
    end

    local function createTrackerGui()
        if TrackerState.Gui then return end
        local gui = Instance.new("ScreenGui")
        gui.Name = "ProximityTrackerHUD"
        gui.ResetOnSpawn = false
        pcall(function()
            gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
        end)

        local saved = loadHudLayout()
        local initialPos  = UDim2.new(0.5, 0, 0.2, 0)
        local initialSize = UDim2.new(0, 320, 0, 180)
        if saved then
            initialPos  = UDim2.new(0, saved.X, 0, saved.Y)
            initialSize = UDim2.new(0, saved.SX, 0, saved.SY)
        end

        local mainFrame = Instance.new("Frame")
        mainFrame.Name = "MainFrame"
        mainFrame.Size = initialSize
        mainFrame.Position = initialPos
        mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
        mainFrame.BorderSizePixel = 0
        mainFrame.Parent = gui

        -- Draggable functionality
        local dragging, dragStart, startPos, dragInput
        mainFrame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                dragStart = input.Position
                startPos = mainFrame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                        saveHudLayout(mainFrame.Position, mainFrame.Size)
                    end
                end)
            end
        end)
        mainFrame.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement then
                dragInput = input
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if input == dragInput and dragging then
                local delta = input.Position - dragStart
                mainFrame.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end
        end)

        -- UI styling
        local uiCorner = Instance.new("UICorner")
        uiCorner.CornerRadius = UDim.new(0, 8)
        uiCorner.Parent = mainFrame
        local uiStroke = Instance.new("UIStroke")
        uiStroke.Color = Color3.fromRGB(60, 60, 70)
        uiStroke.Thickness = 2
        uiStroke.Transparency = 0.2
        uiStroke.Parent = mainFrame

        -- Resize handle (bottom-right corner)
        local resizeHandle = Instance.new("ImageButton")
        resizeHandle.Name = "ResizeHandle"
        resizeHandle.Size = UDim2.new(0, 20, 0, 20)
        resizeHandle.Position = UDim2.new(1, -20, 1, -20)
        resizeHandle.BackgroundTransparency = 1
        resizeHandle.Image = "rbxassetid://3570695787"
        resizeHandle.ImageColor3 = Color3.fromRGB(150, 150, 150)
        resizeHandle.Parent = mainFrame

        local resizing, resizeStart, startSize
        resizeHandle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                resizing = true
                resizeStart = input.Position
                startSize = mainFrame.AbsoluteSize
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        resizing = false
                        saveHudLayout(mainFrame.Position, mainFrame.Size)
                    end
                end)
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement and resizing then
                local delta = input.Position - resizeStart
                mainFrame.Size = UDim2.new(0, startSize.X + delta.X, 0, startSize.Y + delta.Y)
            end
        end)

        -- Target name label
        local targetLabel = Instance.new("TextLabel")
        targetLabel.Name = "TargetName"
        targetLabel.Size = UDim2.new(1, -20, 0, 26)
        targetLabel.Position = UDim2.new(0, 10, 0, 10)
        targetLabel.BackgroundTransparency = 1
        targetLabel.Font = Enum.Font.GothamBold
        targetLabel.TextSize = 18
        targetLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        targetLabel.Text = "🎯 Searching..."
        targetLabel.TextXAlignment = Enum.TextXAlignment.Left
        targetLabel.TextTruncate = Enum.TextTruncate.AtEnd
        targetLabel.Parent = mainFrame

        -- Health bar background
        local barBg = Instance.new("Frame")
        barBg.Name = "BarBG"
        barBg.Size = UDim2.new(1, -20, 0, 18)
        barBg.Position = UDim2.new(0, 10, 0, 40)
        barBg.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
        barBg.BorderSizePixel = 0
        barBg.Parent = mainFrame
        local barCorner = Instance.new("UICorner")
        barCorner.CornerRadius = UDim.new(0, 5)
        barCorner.Parent = barBg

        local barFill = Instance.new("Frame")
        barFill.Name = "Fill"
        barFill.Size = UDim2.new(1, 0, 1, 0)
        barFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        barFill.BorderSizePixel = 0
        barFill.Parent = barBg
        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(0, 5)
        fillCorner.Parent = barFill
        local gradient = Instance.new("UIGradient")
        gradient.Color = ColorSequence.new{
            ColorSequenceKeypoint.new(0,  Color3.fromRGB(85, 255, 120)),
            ColorSequenceKeypoint.new(1,  Color3.fromRGB(0, 170, 120))
        }
        gradient.Parent = barFill

        local hpText = Instance.new("TextLabel")
        hpText.Size = UDim2.new(1, 0, 1, 0)
        hpText.BackgroundTransparency = 1
        hpText.Font = Enum.Font.GothamBold
        hpText.TextSize = 12
        hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
        hpText.TextStrokeTransparency = 0.5
        hpText.Text = "100 / 100"
        hpText.ZIndex = 2
        hpText.Parent = barBg

        -- Drops label
        local dropsLabel = Instance.new("TextLabel")
        dropsLabel.Name = "DropsLabel"
        dropsLabel.Size = UDim2.new(1, -20, 0, 20)
        dropsLabel.Position = UDim2.new(0, 10, 0, 68)
        dropsLabel.BackgroundTransparency = 1
        dropsLabel.Font = Enum.Font.Gotham
        dropsLabel.TextSize = 14
        dropsLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        dropsLabel.Text = "💎 Drops Detected:"
        dropsLabel.TextXAlignment = Enum.TextXAlignment.Left
        dropsLabel.Parent = mainFrame

        -- Drops list container
        local dropContainer = Instance.new("Frame")
        dropContainer.Name = "DropContainer"
        dropContainer.Size = UDim2.new(1, 0, 1, -95)
        dropContainer.Position = UDim2.new(0, 0, 0, 95)
        dropContainer.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
        dropContainer.BorderSizePixel = 0
        dropContainer.Parent = mainFrame
        local dropCorner = Instance.new("UICorner")
        dropCorner.CornerRadius = UDim.new(0, 6)
        dropCorner.Parent = dropContainer

        local dropList = Instance.new("ScrollingFrame")
        dropList.Name = "DropList"
        dropList.Size = UDim2.new(1, -10, 1, -10)
        dropList.Position = UDim2.new(0, 5, 0, 5)
        dropList.BackgroundTransparency = 1
        dropList.BorderSizePixel = 0
        dropList.ScrollBarThickness = 4
        dropList.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 80)
        dropList.AutomaticCanvasSize = Enum.AutomaticSize.Y
        dropList.CanvasSize = UDim2.new(0, 0, 0, 0)
        dropList.Parent = dropContainer
        local layout = Instance.new("UIListLayout")
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 4)
        layout.Parent = dropList

        TrackerState.Gui        = gui
        TrackerState.Container  = mainFrame
        TrackerState.TargetName = targetLabel
        TrackerState.HealthBar  = barFill
        TrackerState.HealthText = hpText
        TrackerState.DropList   = dropList
        gui.Enabled = false
    end

    local function resetTrackerData(newTarget)
        if not TrackerState.DropList then return end
        for _, child in ipairs(TrackerState.DropList:GetChildren()) do
            if child:IsA("TextLabel") then child:Destroy() end
        end
        table.clear(TrackerState.CurrentDrops)
        if newTarget then
            local hp = rockHealth(newTarget) or 100
            local maxAttr = newTarget:GetAttribute("MaxHealth")
            TrackerState.CachedMaxHp = maxAttr or hp
        end
    end

    local function updateTrackerUi()
        if not TrackerState.Enabled or not TrackerState.Gui then
            if TrackerState.Gui then TrackerState.Gui.Enabled = false end
            return
        end
        TrackerState.Gui.Enabled = true

        local target = TrackerState.ActiveTarget
        if not target or not target.Parent then
            TrackerState.TargetName.Text = "🎯 Searching..."
            TrackerState.HealthBar:TweenSize(UDim2.new(0, 0, 1, 0), "Out", "Quad", 0.3, true)
            TrackerState.HealthText.Text = "0 / 0"
            return
        end
        TrackerState.TargetName.Text = "🎯 " .. target.Name

        local hp    = rockHealth(target) or 0
        local maxHp = math.max(TrackerState.CachedMaxHp, 1)
        local pct   = math.clamp(hp / maxHp, 0, 1)
        TrackerState.HealthBar:TweenSize(UDim2.new(pct, 0, 1, 0), "Out", "Quad", 0.15, true)
        TrackerState.HealthText.Text = string.format("%d / %d", hp, maxHp)

        for _, c in ipairs(target:GetChildren()) do
            if c.Name == "Ore" and not TrackerState.CurrentDrops[c] then
                local oreType = c:GetAttribute("Ore")
                if oreType then
                    TrackerState.CurrentDrops[c] = true
                    local lbl = Instance.new("TextLabel")
                    lbl.Size = UDim2.new(1, 0, 0, 20)
                    lbl.BackgroundTransparency = 1
                    lbl.Font = Enum.Font.GothamMedium
                    lbl.TextSize = 14
                    lbl.TextColor3 = Color3.fromRGB(255, 215, 0)
                    lbl.Text = "  ✨ " .. tostring(oreType)
                    lbl.TextXAlignment = Enum.TextXAlignment.Left
                    lbl.Parent = TrackerState.DropList
                    TrackerState.DropList.CanvasPosition = Vector2.new(0, math.huge)
                end
            end
        end
    end

    -- Background loop to track nearby rock damage and update UI
    task.spawn(function()
        while true do
            if not TrackerState.Enabled then
                if TrackerState.Gui then TrackerState.Gui.Enabled = false end
                task.wait(1)
            else
                local hrp = getLocalHRP()
                if not hrp then
                    task.wait(0.5)
                else
                    local folder = getRocksFolder()
                    local nearbyRocks = {}
                    if folder then
                        for _, desc in ipairs(folder:GetDescendants()) do
                            if desc:IsA("Model") and desc:GetAttribute("Health") then
                                if (desc:GetPivot().Position - hrp.Position).Magnitude <= 15 then
                                    table.insert(nearbyRocks, desc)
                                end
                            end
                        end
                    end
                    for _, rock in ipairs(nearbyRocks) do
                        local currentHp = rockHealth(rock) or 0
                        local prevHp = TrackerState.LastCheckHealth[rock]
                        if prevHp and currentHp < prevHp then
                            if TrackerState.ActiveTarget ~= rock then
                                TrackerState.ActiveTarget = rock
                                resetTrackerData(rock)
                            end
                        end
                        TrackerState.LastCheckHealth[rock] = currentHp
                    end
                    for rock, _ in pairs(TrackerState.LastCheckHealth) do
                        if not rock.Parent or (rock:GetPivot().Position - hrp.Position).Magnitude > 20 then
                            TrackerState.LastCheckHealth[rock] = nil
                        end
                    end
                    if TrackerState.ActiveTarget then
                        local tgt = TrackerState.ActiveTarget
                        if not tgt.Parent or (rockHealth(tgt) or 0) <= 0 
                           or (tgt:GetPivot().Position - hrp.Position).Magnitude > 20 then
                            TrackerState.ActiveTarget = nil
                        end
                    end
                    updateTrackerUi()
                    task.wait(0.1)
                end
            end
        end
    end)

    local function setEnabled(state)
        TrackerState.Enabled = state
        if state then
            createTrackerGui()
        elseif TrackerState.Gui then
            TrackerState.Gui.Enabled = false
        end
    end

    local function resetTracker()
        if TrackerState.Gui then
            pcall(function() TrackerState.Gui:Destroy() end)
            TrackerState.Gui = nil
            TrackerState.Container = nil
            TrackerState.TargetName = nil
            TrackerState.HealthBar = nil
            TrackerState.HealthText = nil
            TrackerState.DropList = nil
            TrackerState.ActiveTarget = nil
            TrackerState.CurrentDrops = {}
            TrackerState.LastCheckHealth = {}
        end
        local deleted = false
        if typeof(isfile) == "function" and typeof(delfile) == "function" then
            if isfile(ConfigFile) then
                local ok, err = pcall(function() delfile(ConfigFile) end)
                deleted = ok and true or false
                if not ok then warn("[Forge] Failed to delete HUD config:", err) end
            end
        end
        if deleted then
            notify("Tracker HUD layout reset. Toggle Progress Tracker on to rebuild.", 4)
        else
            notify("Could not delete HUD config (executor may not support delfile).", 4)
        end
    end

    local function destroyTracker()
        if TrackerState.Gui then
            pcall(function() TrackerState.Gui:Destroy() end)
            TrackerState.Gui = nil
        end
        TrackerState.Enabled = false
    end

    return {
        setEnabled = setEnabled,
        reset      = resetTracker,
        destroy    = destroyTracker
    }
end
