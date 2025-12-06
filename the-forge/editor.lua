--[[

Cerberus Forge Priority Editor (Live-sorting, Scroll-Safe)

• Priorities: 1 (highest) .. 999 (lowest)
• Rows auto-resort instantly when values change.
• Scroll position is saved during resort so the view doesn't jump.

]]

-- // Services
local Players              = game:GetService("Players")
local HttpService          = game:GetService("HttpService")
local UserInputService     = game:GetService("UserInputService")
local LocalPlayer          = Players.LocalPlayer

-- // File paths
local BaseFolder           = "Cerberus"
local ForgeFolder          = BaseFolder .. "/The Forge"
local PriorityConfigFile   = ForgeFolder .. "/PriorityConfig.json"

local DefaultOrePriority   = {
    ["Crimson Crystal"] = 1,
    ["Violet Crystal"]  = 1,
    ["Cyan Crystal"]    = 1,
    ["Earth Crystal"]   = 1,
    ["Light Crystal"]   = 1,
    ["Volcanic Rock"]   = 2,
    ["Basalt Vein"]     = 3,
    ["Basalt Core"]     = 4,
    ["Basalt Rock"]     = 5,
    ["Boulder"]         = 6,
    ["Rock"]            = 6,
    ["Pebble"]          = 6,
    ["Lucky Block"]     = 6,
}

local DefaultEnemyPriority = {
    ["Blazing Slime"]           = 1,
    ["Elite Deathaxe Skeleton"] = 2,
    ["Reaper"]                  = 3,
    ["Elite Rogue Skeleton"]    = 4,
    ["Deathaxe Skeleton"]       = 5,
    ["Axe Skeleton"]            = 6,
    ["Skeleton Rogue"]          = 7,
    ["Bomber"]                  = 8,
    ["Slime"]                   = 9,
    ["MinerZombie"]             = 9,
    ["EliteZombie"]             = 9,
    ["Zombie"]                  = 9,
    ["Delver Zombie"]           = 9,
    ["Brute Zombie"]            = 9,
}

-- // Helpers
local function ensureFolders()
    if not isfolder(BaseFolder) then makefolder(BaseFolder) end
    if not isfolder(ForgeFolder) then makefolder(ForgeFolder) end
end

local function deepCopy(tbl)
    local new = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            new[k] = deepCopy(v)
        else
            new[k] = v
        end
    end
    return new
end

-- // Config state
local PriorityConfig = {
    Ores    = deepCopy(DefaultOrePriority),
    Enemies = deepCopy(DefaultEnemyPriority),
}

local function savePriorityConfig()
    ensureFolders()
    local payload = {
        Ores    = PriorityConfig.Ores,
        Enemies = PriorityConfig.Enemies,
    }
    local ok, err = pcall(function()
        writefile(PriorityConfigFile, HttpService:JSONEncode(payload))
    end)
    if not ok then
        warn("[PriorityEditor] Failed to save priority config:", err)
    end
end

local function loadPriorityConfig()
    ensureFolders()

    if not isfile(PriorityConfigFile) then
        PriorityConfig.Ores    = deepCopy(DefaultOrePriority)
        PriorityConfig.Enemies = deepCopy(DefaultEnemyPriority)
        savePriorityConfig()
        return
    end

    local success, result = pcall(function()
        return HttpService:JSONDecode(readfile(PriorityConfigFile))
    end)

    if not success or type(result) ~= "table" then
        warn("[PriorityEditor] Invalid or corrupted config. Resetting to defaults.")
        PriorityConfig.Ores    = deepCopy(DefaultOrePriority)
        PriorityConfig.Enemies = deepCopy(DefaultEnemyPriority)
        savePriorityConfig()
        return
    end

    -- Handle loading logic
    if result.Ores or result.Enemies then
        PriorityConfig.Ores = deepCopy(DefaultOrePriority)
        if type(result.Ores) == "table" then
            for k, v in pairs(result.Ores) do
                PriorityConfig.Ores[k] = tonumber(v) or PriorityConfig.Ores[k] or 999
            end
        end

        PriorityConfig.Enemies = deepCopy(DefaultEnemyPriority)
        if type(result.Enemies) == "table" then
            for k, v in pairs(result.Enemies) do
                PriorityConfig.Enemies[k] = tonumber(v) or PriorityConfig.Enemies[k] or 999
            end
        end
    else
        -- Legacy flat format support
        PriorityConfig.Ores = deepCopy(DefaultOrePriority)
        for k, v in pairs(result) do
            PriorityConfig.Ores[k] = tonumber(v) or PriorityConfig.Ores[k] or 999
        end
        PriorityConfig.Enemies = deepCopy(DefaultEnemyPriority)
    end

    -- Ensure defaults exist if missing from file
    for k, v in pairs(DefaultOrePriority) do
        if PriorityConfig.Ores[k] == nil then PriorityConfig.Ores[k] = v end
    end
    for k, v in pairs(DefaultEnemyPriority) do
        if PriorityConfig.Enemies[k] == nil then PriorityConfig.Enemies[k] = v end
    end
end

loadPriorityConfig()

-- // Sorting Logic
-- Sorts by Value (Priority) first, then by Name (Alphabetical) for ties
local function sortedKeysByPriority(tbl)
    local list = {}
    for k in pairs(tbl) do
        table.insert(list, k)
    end
    table.sort(list, function(a, b)
        local va = tonumber(tbl[a]) or 999
        local vb = tonumber(tbl[b]) or 999
        
        if va ~= vb then
            return va < vb -- Smaller number = Higher Priority
        end
        return tostring(a) < tostring(b) -- Alphabetical tie-breaker
    end)
    return list
end

-- // UI creation
local function createPriorityEditorGui()
    local parent
    local okCore, coreGui = pcall(function() return game:GetService("CoreGui") end)
    if okCore and coreGui then
        parent = coreGui
    else
        parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    
    -- Cleanup old GUI if exists
    if parent:FindFirstChild("CerberusPriorityEditor") then
        parent.CerberusPriorityEditor:Destroy()
    end

    local sg = Instance.new("ScreenGui")
    sg.Name = "CerberusPriorityEditor"
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Global
    sg.Parent = parent

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    mainFrame.Size = UDim2.new(0, 420, 0, 380)
    mainFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = sg

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = mainFrame

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Color = Color3.fromRGB(70, 70, 90)
    stroke.Transparency = 0.2
    stroke.Parent = mainFrame

    -- Top Bar
    local topBar = Instance.new("Frame")
    topBar.Name = "TopBar"
    topBar.Size = UDim2.new(1, 0, 0, 32)
    topBar.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    topBar.BorderSizePixel = 0
    topBar.Parent = mainFrame

    local topCorner = Instance.new("UICorner")
    topCorner.CornerRadius = UDim.new(0, 10)
    topCorner.Parent = topBar

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, -60, 1, 0)
    title.Position = UDim2.new(0, 10, 0, 0)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.fromRGB(230, 230, 240)
    title.Text = "Cerberus Forge - Priority Editor"
    title.Parent = topBar

    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Size = UDim2.new(0, 32, 0, 24)
    closeButton.Position = UDim2.new(1, -36, 0.5, -12)
    closeButton.BackgroundColor3 = Color3.fromRGB(60, 20, 20)
    closeButton.Text = "X"
    closeButton.Font = Enum.Font.GothamBold
    closeButton.TextSize = 14
    closeButton.TextColor3 = Color3.fromRGB(255, 200, 200)
    closeButton.Parent = topBar
    Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 6)

    -- Draggable
    local dragging, dragInput, dragStart, startPos
    topBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    topBar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then dragInput = input end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    closeButton.MouseButton1Click:Connect(function() sg:Destroy() end)

    -- Mode Switching
    local modeBar = Instance.new("Frame")
    modeBar.Name = "ModeBar"
    modeBar.Size = UDim2.new(1, -20, 0, 28)
    modeBar.Position = UDim2.new(0, 10, 0, 40)
    modeBar.BackgroundTransparency = 1
    modeBar.Parent = mainFrame

    local oresButton = Instance.new("TextButton")
    oresButton.Name = "OresButton"
    oresButton.Size = UDim2.new(0.5, -5, 1, 0)
    oresButton.BackgroundColor3 = Color3.fromRGB(40, 40, 80)
    oresButton.Text = "Ores"
    oresButton.TextColor3 = Color3.fromRGB(230, 230, 255)
    oresButton.Font = Enum.Font.GothamBold
    oresButton.TextSize = 14
    oresButton.Parent = modeBar
    Instance.new("UICorner", oresButton).CornerRadius = UDim.new(0, 6)

    local enemiesButton = Instance.new("TextButton")
    enemiesButton.Name = "EnemiesButton"
    enemiesButton.Size = UDim2.new(0.5, -5, 1, 0)
    enemiesButton.Position = UDim2.new(0.5, 5, 0, 0)
    enemiesButton.BackgroundColor3 = Color3.fromRGB(30, 40, 50)
    enemiesButton.Text = "Enemies"
    enemiesButton.TextColor3 = Color3.fromRGB(200, 200, 210)
    enemiesButton.Font = Enum.Font.GothamBold
    enemiesButton.TextSize = 14
    enemiesButton.Parent = modeBar
    Instance.new("UICorner", enemiesButton).CornerRadius = UDim.new(0, 6)

    -- Reset Row
    local resetRow = Instance.new("Frame")
    resetRow.Name = "ResetRow"
    resetRow.Size = UDim2.new(1, -20, 0, 24)
    resetRow.Position = UDim2.new(0, 10, 0, 72)
    resetRow.BackgroundTransparency = 1
    resetRow.Parent = mainFrame

    local resetOresBtn = Instance.new("TextButton")
    resetOresBtn.Size = UDim2.new(0.5, -5, 1, 0)
    resetOresBtn.BackgroundColor3 = Color3.fromRGB(40, 60, 40)
    resetOresBtn.Text = "Reset Ores"
    resetOresBtn.Font = Enum.Font.Gotham
    resetOresBtn.TextSize = 13
    resetOresBtn.TextColor3 = Color3.fromRGB(220, 255, 220)
    resetOresBtn.Parent = resetRow
    Instance.new("UICorner", resetOresBtn).CornerRadius = UDim.new(0, 6)

    local resetEnemiesBtn = Instance.new("TextButton")
    resetEnemiesBtn.Size = UDim2.new(0.5, -5, 1, 0)
    resetEnemiesBtn.Position = UDim2.new(0.5, 5, 0, 0)
    resetEnemiesBtn.BackgroundColor3 = Color3.fromRGB(60, 50, 40)
    resetEnemiesBtn.Text = "Reset Enemies"
    resetEnemiesBtn.Font = Enum.Font.Gotham
    resetEnemiesBtn.TextSize = 13
    resetEnemiesBtn.TextColor3 = Color3.fromRGB(255, 230, 200)
    resetEnemiesBtn.Parent = resetRow
    Instance.new("UICorner", resetEnemiesBtn).CornerRadius = UDim.new(0, 6)

    -- Info Label
    local infoLabel = Instance.new("TextLabel")
    infoLabel.Size = UDim2.new(1, -20, 0, 40)
    infoLabel.Position = UDim2.new(0, 10, 0, 100)
    infoLabel.BackgroundTransparency = 1
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.TextSize = 12
    infoLabel.TextWrapped = true
    infoLabel.TextColor3 = Color3.fromRGB(190, 190, 200)
    infoLabel.Text = "Priority 1 is highest. Rows automatically resort when numbers change. Remember to click 'Reload Priorities' in the main script."
    infoLabel.Parent = mainFrame

    -- Content Areas
    local contentFrame = Instance.new("Frame")
    contentFrame.Size = UDim2.new(1, -20, 1, -150)
    contentFrame.Position = UDim2.new(0, 10, 0, 140)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Parent = mainFrame

    local oresScroll = Instance.new("ScrollingFrame")
    oresScroll.Size = UDim2.new(1, 0, 1, 0)
    oresScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    oresScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    oresScroll.ScrollBarThickness = 6
    oresScroll.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    oresScroll.BorderSizePixel = 0
    oresScroll.Parent = contentFrame

    local oresLayout = Instance.new("UIListLayout")
    oresLayout.Padding = UDim.new(0, 4)
    oresLayout.SortOrder = Enum.SortOrder.LayoutOrder -- Using LayoutOrder is smoother
    oresLayout.Parent = oresScroll

    local enemiesScroll = Instance.new("ScrollingFrame")
    enemiesScroll.Size = UDim2.new(1, 0, 1, 0)
    enemiesScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    enemiesScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    enemiesScroll.ScrollBarThickness = 6
    enemiesScroll.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    enemiesScroll.BorderSizePixel = 0
    enemiesScroll.Visible = false
    enemiesScroll.Parent = contentFrame

    local enemiesLayout = Instance.new("UIListLayout")
    enemiesLayout.Padding = UDim.new(0, 4)
    enemiesLayout.SortOrder = Enum.SortOrder.LayoutOrder
    enemiesLayout.Parent = enemiesScroll

    -- Helper: Create Row
    local function createPriorityRow(parent, labelText, initialValue, onChanged)
        local row = Instance.new("Frame")
        row.Name = labelText
        row.Size = UDim2.new(1, -8, 0, 28)
        row.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
        row.BorderSizePixel = 0
        row.Parent = parent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

        local nameLabel = Instance.new("TextLabel")
        nameLabel.BackgroundTransparency = 1
        nameLabel.Size = UDim2.new(0.7, -10, 1, 0)
        nameLabel.Position = UDim2.new(0, 10, 0, 0)
        nameLabel.Font = Enum.Font.Gotham
        nameLabel.TextSize = 14
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextColor3 = Color3.fromRGB(230, 230, 240)
        nameLabel.Text = labelText
        nameLabel.Parent = row

        local box = Instance.new("TextBox")
        box.Size = UDim2.new(0.3, -10, 1, -6)
        box.Position = UDim2.new(0.7, 0, 0, 3)
        box.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
        box.TextColor3 = Color3.fromRGB(255, 255, 255)
        box.Font = Enum.Font.GothamSemibold
        box.TextSize = 14
        box.TextXAlignment = Enum.TextXAlignment.Center
        box.ClearTextOnFocus = false
        box.Parent = row
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)

        local lastValid = tonumber(initialValue) or 999
        box.Text = tostring(lastValid)

        -- Input Sanitize (Numbers only)
        box:GetPropertyChangedSignal("Text"):Connect(function()
            local t = box.Text
            local d = t:gsub("%D", "")
            if t ~= d then box.Text = d end
        end)

        -- Save & Trigger Sort on Focus Lost
        box.FocusLost:Connect(function()
            local num = tonumber(box.Text)
            if not num then
                box.Text = tostring(lastValid)
                return
            end
            
            num = math.clamp(math.floor(num), 1, 999)
            lastValid = num
            box.Text = tostring(num)
            
            if onChanged then onChanged(num) end
        end)
        
        return row
    end

    -- Rebuild Functions
    local rebuildOresList, rebuildEnemiesList

    rebuildOresList = function()
        -- 1. SAVE SCROLL POSITION
        local savedPos = oresScroll.CanvasPosition
        
        -- 2. CLEAR
        for _, c in ipairs(oresScroll:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        
        -- 3. REPOPULATE (Sorted)
        local sorted = sortedKeysByPriority(PriorityConfig.Ores)
        for i, name in ipairs(sorted) do
            local val = PriorityConfig.Ores[name]
            local row = createPriorityRow(oresScroll, name, val, function(newVal)
                PriorityConfig.Ores[name] = newVal
                savePriorityConfig()
                rebuildOresList() -- Recursive refresh triggers sort
            end)
            row.LayoutOrder = i -- Enforce order
        end
        
        -- 4. RESTORE SCROLL
        oresScroll.CanvasPosition = savedPos
    end

    rebuildEnemiesList = function()
        local savedPos = enemiesScroll.CanvasPosition
        
        for _, c in ipairs(enemiesScroll:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        
        local sorted = sortedKeysByPriority(PriorityConfig.Enemies)
        for i, name in ipairs(sorted) do
            local val = PriorityConfig.Enemies[name]
            local row = createPriorityRow(enemiesScroll, name, val, function(newVal)
                PriorityConfig.Enemies[name] = newVal
                savePriorityConfig()
                rebuildEnemiesList()
            end)
            row.LayoutOrder = i
        end
        
        enemiesScroll.CanvasPosition = savedPos
    end

    -- Initial Build
    rebuildOresList()
    rebuildEnemiesList()

    -- Tab Switching
    local function setMode(m)
        if m == "Ores" then
            oresScroll.Visible = true
            enemiesScroll.Visible = false
            oresButton.BackgroundColor3 = Color3.fromRGB(60, 60, 120)
            oresButton.TextColor3 = Color3.fromRGB(255, 255, 255)
            enemiesButton.BackgroundColor3 = Color3.fromRGB(30, 40, 50)
            enemiesButton.TextColor3 = Color3.fromRGB(200, 200, 210)
        else
            oresScroll.Visible = false
            enemiesScroll.Visible = true
            enemiesButton.BackgroundColor3 = Color3.fromRGB(120, 60, 40)
            enemiesButton.TextColor3 = Color3.fromRGB(255, 240, 220)
            oresButton.BackgroundColor3 = Color3.fromRGB(30, 40, 50)
            oresButton.TextColor3 = Color3.fromRGB(200, 200, 210)
        end
    end
    
    oresButton.MouseButton1Click:Connect(function() setMode("Ores") end)
    enemiesButton.MouseButton1Click:Connect(function() setMode("Enemies") end)
    setMode("Ores")

    -- Reset Handlers
    resetOresBtn.MouseButton1Click:Connect(function()
        PriorityConfig.Ores = deepCopy(DefaultOrePriority)
        savePriorityConfig()
        rebuildOresList()
    end)
    resetEnemiesBtn.MouseButton1Click:Connect(function()
        PriorityConfig.Enemies = deepCopy(DefaultEnemyPriority)
        savePriorityConfig()
        rebuildEnemiesList()
    end)

    return sg
end

createPriorityEditorGui()
