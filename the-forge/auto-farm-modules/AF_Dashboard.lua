-- AF_Dashboard.lua
-- Enhanced Autofarm Dashboard HUD with mobile support
-- • Fully responsive design that adapts to screen size
-- • Automatic text scaling to prevent cutoff
-- • Touch-friendly controls for mobile
-- • Sections hidden when no data exists
-- • Improved highlighted item appearance

return function(env)
    ----------------------------------------------------------------
    -- CONTEXT
    ----------------------------------------------------------------
    local Services   = env.Services
    local References = env.References
    local Library    = env.Library
    local META       = env.META or {}

    local Players          = Services.Players
    local RunService       = Services.RunService
    local UserInputService = Services.UserInputService or game:GetService("UserInputService")

    local function getLocalPlayer()
        return References.player or Players.LocalPlayer
    end

    local function getLocalHRP()
        if env.getLocalHRP then
            return env.getLocalHRP()
        end
        local lp   = getLocalPlayer()
        local char = lp and lp.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    ----------------------------------------------------------------
    -- SCREEN GUI + WINDOW
    ----------------------------------------------------------------
    local localPlayer = getLocalPlayer()
    if not localPlayer then
        localPlayer = Players.LocalPlayer
    end

    local playerGui = localPlayer:WaitForChild("PlayerGui")

    local GUI_NAME = "Cerberus_AutofarmDashboard"

    -- Cleanup any existing instance
    local existing = playerGui:FindFirstChild(GUI_NAME)
    if existing then
        existing:Destroy()
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name          = GUI_NAME
    screenGui.ResetOnSpawn  = false
    screenGui.IgnoreGuiInset = true
    screenGui.Enabled       = false
    screenGui.Parent        = playerGui

    -- Detect mobile
    local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
    
    -- Responsive sizing based on screen and device type
    local baseWidth = isMobile and 340 or 450
    
    -- Main window with responsive sizing
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "Main"
    mainFrame.Size = UDim2.new(0, baseWidth, 0, 0)
    mainFrame.Position = isMobile and UDim2.new(0.5, 0, 0.5, 0) or UDim2.new(1, -20, 0, 80)
    mainFrame.AnchorPoint = isMobile and Vector2.new(0.5, 0.5) or Vector2.new(1, 0)
    mainFrame.BackgroundColor3 = Color3.fromRGB(10, 14, 22)
    mainFrame.BorderSizePixel = 0
    mainFrame.ClipsDescendants = false
    mainFrame.AutomaticSize = Enum.AutomaticSize.Y
    mainFrame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = mainFrame

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Transparency = 0.2
    stroke.Color = Color3.fromRGB(80, 220, 130)
    stroke.Parent = mainFrame

    -- Size constraint to enforce min/max
    local sizeConstraint = Instance.new("UISizeConstraint")
    sizeConstraint.MinSize = Vector2.new(isMobile and 300 or 420, 0)
    sizeConstraint.MaxSize = Vector2.new(isMobile and 600 or 520, 10000)
    sizeConstraint.Parent = mainFrame

    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, isMobile and 50 or 40)
    titleBar.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = mainFrame

    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 12)
    titleCorner.Parent = titleBar

    -- Mask for title bar
    local titleMask = Instance.new("Frame")
    titleMask.BackgroundColor3 = titleBar.BackgroundColor3
    titleMask.BorderSizePixel = 0
    titleMask.Size = UDim2.new(1, 0, 0, 12)
    titleMask.Position = UDim2.new(0, 0, 1, -12)
    titleMask.Parent = titleBar

    local titleLabel = Instance.new("TextLabel")
    titleLabel.BackgroundTransparency = 1
    titleLabel.Size = UDim2.new(1, -20, 0.6, 0)
    titleLabel.Position = UDim2.new(0, 12, 0, 2)
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = isMobile and 16 or 15
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextColor3 = Color3.fromRGB(240, 250, 255)
    titleLabel.Text = "CERBERUS • Autofarm Dashboard"
    titleLabel.Parent = titleBar

    local subtitleLabel = Instance.new("TextLabel")
    subtitleLabel.BackgroundTransparency = 1
    subtitleLabel.Size = UDim2.new(1, -20, 0.4, 0)
    subtitleLabel.Position = UDim2.new(0, 12, 0.6, 0)
    subtitleLabel.Font = Enum.Font.Gotham
    subtitleLabel.TextSize = isMobile and 12 or 11
    subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    subtitleLabel.TextColor3 = Color3.fromRGB(160, 180, 200)
    subtitleLabel.Text = "Live AutoFarm overview."
    subtitleLabel.Parent = titleBar

    -- Drag hint (for desktop) or close hint (mobile)
    local hintLabel = Instance.new("TextLabel")
    hintLabel.BackgroundTransparency = 1
    hintLabel.Size = UDim2.new(0, isMobile and 60 or 50, 1, 0)
    hintLabel.Position = UDim2.new(1, isMobile and -65 or -55, 0, 0)
    hintLabel.Font = Enum.Font.GothamMedium
    hintLabel.TextSize = isMobile and 11 or 10
    hintLabel.TextXAlignment = Enum.TextXAlignment.Center
    hintLabel.TextColor3 = Color3.fromRGB(120, 160, 180)
    hintLabel.Text = isMobile and "Toggle\nin Menu" or ""
    hintLabel.Parent = titleBar

    -- Content container with padding
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.BackgroundTransparency = 1
    content.Size = UDim2.new(1, 0, 0, 0)
    content.Position = UDim2.new(0, 0, 0, isMobile and 50 or 40)
    content.AutomaticSize = Enum.AutomaticSize.Y
    content.Parent = mainFrame

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 8)
    layout.Parent = content

    local contentPadding = Instance.new("UIPadding")
    contentPadding.PaddingLeft = UDim.new(0, 10)
    contentPadding.PaddingRight = UDim.new(0, 10)
    contentPadding.PaddingTop = UDim.new(0, 10)
    contentPadding.PaddingBottom = UDim.new(0, 10)
    contentPadding.Parent = content

    -- Helper to create sections
    local function createSection(titleText, emoji)
        local section = Instance.new("Frame")
        section.BackgroundColor3 = Color3.fromRGB(18, 24, 36)
        section.BorderSizePixel = 0
        section.Size = UDim2.new(1, 0, 0, 0)
        section.AutomaticSize = Enum.AutomaticSize.Y
        section.Visible = false  -- Hidden by default

        local secCorner = Instance.new("UICorner")
        secCorner.CornerRadius = UDim.new(0, 10)
        secCorner.Parent = section

        local secStroke = Instance.new("UIStroke")
        secStroke.Thickness = 1
        secStroke.Transparency = 0.5
        secStroke.Color = Color3.fromRGB(60, 85, 110)
        secStroke.Parent = section

        local header = Instance.new("TextLabel")
        header.BackgroundTransparency = 1
        header.Size = UDim2.new(1, -20, 0, isMobile and 28 or 26)
        header.Position = UDim2.new(0, 10, 0, 6)
        header.Font = Enum.Font.GothamBold
        header.TextSize = isMobile and 15 or 14
        header.TextXAlignment = Enum.TextXAlignment.Left
        header.TextColor3 = Color3.fromRGB(210, 230, 255)
        header.Text = emoji .. " " .. titleText
        header.Parent = section

        local body = Instance.new("TextLabel")
        body.Name = "BodyText"
        body.BackgroundTransparency = 1
        body.Size = UDim2.new(1, -20, 0, 0)
        body.Position = UDim2.new(0, 10, 0, isMobile and 34 or 32)
        body.Font = Enum.Font.RobotoMono
        body.TextSize = isMobile and 13 or 12
        body.TextXAlignment = Enum.TextXAlignment.Left
        body.TextYAlignment = Enum.TextYAlignment.Top
        body.TextWrapped = true
        body.RichText = true  -- Enable RichText for colored highlighting
        body.TextColor3 = Color3.fromRGB(200, 215, 240)
        body.Text = ""
        body.AutomaticSize = Enum.AutomaticSize.Y
        body.Parent = section

        local secPadding = Instance.new("UIPadding")
        secPadding.PaddingBottom = UDim.new(0, 10)
        secPadding.Parent = section

        return section, body
    end

    -- Create sections
    local rocksSection, rocksBody = createSection("Rocks", "⛏️")
    rocksSection.LayoutOrder = 1
    rocksSection.Parent = content

    local mobsSection, mobsBody = createSection("Mobs", "⚔️")
    mobsSection.LayoutOrder = 2
    mobsSection.Parent = content

    local playersSection, playersBody = createSection("Nearby Players", "👥")
    playersSection.LayoutOrder = 3
    playersSection.Parent = content

    ----------------------------------------------------------------
    -- DRAGGING (Desktop only)
    ----------------------------------------------------------------
    if not isMobile then
        local dragging = false
        local dragStart
        local startPos

        titleBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                dragStart = input.Position
                startPos = mainFrame.Position

                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local delta = input.Position - dragStart
                mainFrame.Position = UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
            end
        end)
    end

    -- Mobile touch dragging
    if isMobile then
        local dragging = false
        local dragStart
        local startPos

        titleBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = mainFrame.Position

                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - dragStart
                mainFrame.Position = UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
            end
        end)
    end

    ----------------------------------------------------------------
    -- INTERNAL STATE
    ----------------------------------------------------------------
    local State = {
        rocksTotalByName       = {},
        rocksBlacklistedByName = {},
        mobsTotalByName        = {},
        mobsBlacklistedByName  = {},

        rocksTotalCount       = 0,
        rocksBlacklistedCount = 0,
        mobsTotalCount        = 0,
        mobsBlacklistedCount  = 0,

        playersNearby    = {},
        enabled          = false,
        
        currentTargetName = nil,
    }

    ----------------------------------------------------------------
    -- HELPERS
    ----------------------------------------------------------------
    local function countFromList(list, nameAttr1, nameAttr2, mergeNumberSuffixes)
        local byName = {}
        local total  = 0

        for _, inst in ipairs(list or {}) do
            if inst and inst.Parent then
                local n
                if nameAttr1 and inst:GetAttribute(nameAttr1) then
                    n = inst:GetAttribute(nameAttr1)
                elseif nameAttr2 and inst:GetAttribute(nameAttr2) then
                    n = inst:GetAttribute(nameAttr2)
                elseif inst:GetAttribute("Ore") then
                    n = inst:GetAttribute("Ore")
                else
                    n = inst.Name or "Unknown"
                end

                n = tostring(n)
                
                if mergeNumberSuffixes then
                    n = n:match("^(.-)%d*$") or n
                end

                byName[n] = (byName[n] or 0) + 1
                total += 1
            end
        end

        return byName, total
    end

    local function buildCountsText(title, totalByName, availByName, totalCount, availCount, blacklistedByName, blacklistedCount, currentTargetName, mergeNumbers)
        local lines = {}
        table.insert(
            lines,
            string.format(
                "Total: %d  •  Blacklisted: %d",
                totalCount or 0,
                blacklistedCount or 0
            )
        )
        table.insert(lines, string.rep("─", 38))

        local names = {}
        for name in pairs(totalByName) do
            table.insert(names, name)
        end
        table.sort(names)

        if #names == 0 then
            return nil  -- Return nil to hide section
        else
            local normalizedTarget = currentTargetName
            if mergeNumbers and normalizedTarget then
                normalizedTarget = normalizedTarget:match("^(.-)%d*$") or normalizedTarget
            end
            
            if normalizedTarget then
                for i, name in ipairs(names) do
                    if name == normalizedTarget then
                        table.remove(names, i)
                        table.insert(names, 1, name)
                        break
                    end
                end
            end
            
            for _, name in ipairs(names) do
                local t = totalByName[name] or 0
                local b = blacklistedByName[name] or 0
                local truncName = #name > 16 and (name:sub(1, 13) .. "...") or name
                
                if name == normalizedTarget then
                    -- Highlighted with rich text formatting
                    table.insert(lines, string.format(
                        '<font color="rgb(100, 220, 150)"><b>▶ %-14s  %3d  (%d)</b></font>',
                        truncName, t, b
                    ))
                else
                    table.insert(lines, string.format("  %-14s  %3d  (%d)", truncName, t, b))
                end
            end
        end

        return table.concat(lines, "\n")
    end

    local function buildPlayersText(playersNearby)
        if not playersNearby or #playersNearby == 0 then
            return nil  -- Return nil to hide section
        end

        local lines = {}
        table.insert(lines, string.rep("─", 38))

        local maxShown = isMobile and 6 or 10
        for i = 1, math.min(#playersNearby, maxShown) do
            local entry = playersNearby[i]
            local name = entry.Name or entry.name or "Unknown"
            local dist = entry.Distance or entry.distance or 0
            local truncName = #name > 18 and (name:sub(1, 15) .. "...") or name
            table.insert(lines, string.format("%-18s  %6.1f", truncName, dist))
        end

        if #playersNearby > maxShown then
            table.insert(lines, string.format("\n(+%d more players...)", #playersNearby - maxShown))
        end

        return table.concat(lines, "\n")
    end

    local function refreshUI()
        if not screenGui or not screenGui.Parent then
            return
        end

        -- Rocks
        local rocksText = buildCountsText(
            "",
            State.rocksTotalByName,
            {},
            State.rocksTotalCount,
            0,
            State.rocksBlacklistedByName,
            State.rocksBlacklistedCount,
            State.currentTargetName,
            false
        )
        if rocksText then
            rocksBody.Text = rocksText
            rocksSection.Visible = true
        else
            rocksSection.Visible = false
        end

        -- Mobs
        local mobsText = buildCountsText(
            "",
            State.mobsTotalByName,
            {},
            State.mobsTotalCount,
            0,
            State.mobsBlacklistedByName,
            State.mobsBlacklistedCount,
            State.currentTargetName,
            true
        )
        if mobsText then
            mobsBody.Text = mobsText
            mobsSection.Visible = true
        else
            mobsSection.Visible = false
        end

        -- Players
        local playersText = buildPlayersText(State.playersNearby)
        if playersText then
            playersBody.Text = playersText
            playersSection.Visible = true
        else
            playersSection.Visible = false
        end
    end

    ----------------------------------------------------------------
    -- PUBLIC API
    ----------------------------------------------------------------
    local Dashboard = {}

    function Dashboard.setEnabled(on)
        State.enabled = on and true or false
        if screenGui then
            screenGui.Enabled = State.enabled
        end
    end

    function Dashboard.setRockLists(allRocks, availableRocks)
        local totalByName, totalCount = countFromList(allRocks, "OreName", nil, false)
        local availByName, availCount = countFromList(availableRocks, "OreName", nil, false)

        local blacklistedByName = {}
        for name, total in pairs(totalByName) do
            local avail = availByName[name] or 0
            blacklistedByName[name] = math.max(0, total - avail)
        end

        State.rocksTotalByName       = totalByName
        State.rocksTotalCount        = totalCount
        State.rocksBlacklistedByName = blacklistedByName
        State.rocksBlacklistedCount  = math.max(0, totalCount - (availCount or 0))
        refreshUI()
    end

    function Dashboard.setMobLists(allMobs, blacklistedMobs)
        State.mobsTotalByName, State.mobsTotalCount = countFromList(allMobs, "MobName", "EnemyName", true)
        State.mobsBlacklistedByName, State.mobsBlacklistedCount = countFromList(blacklistedMobs, "MobName", "EnemyName", true)
        refreshUI()
    end

    function Dashboard.setNearbyPlayers(playersData)
        State.playersNearby = playersData or {}
        refreshUI()
    end
    
    function Dashboard.setCurrentTarget(targetName)
        State.currentTargetName = targetName
        refreshUI()
    end

    function Dashboard.destroy()
        if screenGui then
            screenGui:Destroy()
        end
        screenGui = nil
    end

    ----------------------------------------------------------------
    -- INITIAL
    ----------------------------------------------------------------
    refreshUI()

    return Dashboard
end
