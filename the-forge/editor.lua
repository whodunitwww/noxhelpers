--[[

Cerberus Forge Priority Editor (Live-sorting, clamped, input-safe)

• Reads / writes: Cerberus/The Forge/PriorityConfig.json
• Priorities: 1 (highest) .. 999 (lowest)
• Rows auto-resort whenever you change a value.
• Non-numeric input is stripped; invalid/empty entries revert to last valid.
• Changes save instantly, BUT you must press "Reload Priorities" in the main
  Forge script to actually apply them in the autofarm.

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

local DefaultOrePriority = {
    ["Basalt"] = 5,
    ["Basalt Core"] = 4,
    ["Basalt Rock"] = 5,
    ["Basalt Vein"] = 3,
    ["Boulder"] = 6,
    ["Crimson Crystal"] = 1,
    ["Cyan Crystal"] = 1,
    ["Earth Crystal"] = 1,
    ["Floating Crystal"] = 1,
    ["Heart Of The Island"] = 6,
    ["Iceberg"] = 6,
    ["Icy Boulder"] = 6,
    ["Icy Pebble"] = 6,
    ["Icy Rock"] = 6,
    ["Large Ice Crystal"] = 1,
    ["Large Red Crystal"] = 1,
    ["Lava Rock"] = 2,
    ["Light Crystal"] = 1,
    ["Lucky Block"] = 6,
    ["Medium Ice Crystal"] = 1,
    ["Medium Red Crystal"] = 1,
    ["Pebble"] = 6,
    ["Rock"] = 6,
    ["Small Ice Crystal"] = 1,
    ["Small Red Crystal"] = 1,
    ["Violet Crystal"] = 1,
    ["Volcanic Rock"] = 2,
}

local DefaultEnemyPriority = {
    ["Axe Skeleton"] = 6,
    ["Blazing Slime"] = 1,
    ["Blight Pyromancer"] = 2,
    ["Bomber"] = 8,
    ["Brute Zombie"] = 9,
    ["Chuthlu"] = 10,
    ["Common Orc"] = 5,
    ["Crystal Golem"] = 2,
    ["Crystal Spider"] = 3,
    ["Deathaxe Skeleton"] = 5,
    ["Delver Zombie"] = 9,
    ["Demonic Queen Spider"] = 1,
    ["Demonic Spider"] = 2,
    ["Diamond Spider"] = 3,
    ["Elite Deathaxe Skeleton"] = 2,
    ["Elite Orc"] = 3,
    ["Elite Rogue Skeleton"] = 4,
    ["EliteZombie"] = 9,
    ["Golem"] = 4,
    ["MinerZombie"] = 9,
    ["Mini Demonic Spider"] = 4,
    ["Prismarine Spider"] = 3,
    ["Reaper"] = 3,
    ["Skeleton Pirate"] = 10,
    ["Skeleton Rogue"] = 7,
    ["Slime"] = 9,
    ["Yeti"] = 3,
    ["Zombie"] = 9,
    ["Zombie3"] = 9,
}

-- // Helpers
local function ensureFolders()
    if not isfolder(BaseFolder) then
        makefolder(BaseFolder)
    end
    if not isfolder(ForgeFolder) then
        makefolder(ForgeFolder)
    end
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
        -- old flat format => treat as Ores
        PriorityConfig.Ores = deepCopy(DefaultOrePriority)
        for k, v in pairs(result) do
            PriorityConfig.Ores[k] = tonumber(v) or PriorityConfig.Ores[k] or 999
        end
        PriorityConfig.Enemies = deepCopy(DefaultEnemyPriority)
    end

    -- ensure defaults exist
    for k, v in pairs(DefaultOrePriority) do
        if PriorityConfig.Ores[k] == nil then
            PriorityConfig.Ores[k] = v
        end
    end
    for k, v in pairs(DefaultEnemyPriority) do
        if PriorityConfig.Enemies[k] == nil then
            PriorityConfig.Enemies[k] = v
        end
    end
end

loadPriorityConfig()

-- Sort helper: by priority (ascending), then name
local function sortedKeysByPriority(tbl)
    local list = {}
    for k in pairs(tbl) do
        table.insert(list, k)
    end
    table.sort(list, function(a, b)
        local va = tonumber(tbl[a]) or 999
        local vb = tonumber(tbl[b]) or 999
        if va == vb then
            return tostring(a) < tostring(b)
        end
        return va < vb -- smaller number = higher priority
    end)
    return list
end

-- // UI creation
local function createPriorityEditorGui()
    -- Use CoreGui if possible, else PlayerGui
    local parent
    local okCore, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)
    if okCore and coreGui then
        parent = coreGui
    else
        parent = LocalPlayer:WaitForChild("PlayerGui")
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

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 6)
    closeCorner.Parent = closeButton

    -- Drag logic
    do
        local dragging, dragInput, dragStart, startPos

        local function update(input)
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end

        topBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
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

        topBar.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if input == dragInput and dragging then
                update(input)
            end
        end)
    end

    closeButton.MouseButton1Click:Connect(function()
        sg:Destroy()
    end)

    -- Mode buttons (Ores / Enemies)
    local modeBar = Instance.new("Frame")
    modeBar.Name = "ModeBar"
    modeBar.Size = UDim2.new(1, -20, 0, 28)
    modeBar.Position = UDim2.new(0, 10, 0, 40)
    modeBar.BackgroundTransparency = 1
    modeBar.Parent = mainFrame

    local oresButton = Instance.new("TextButton")
    oresButton.Name = "OresButton"
    oresButton.Size = UDim2.new(0.5, -5, 1, 0)
    oresButton.Position = UDim2.new(0, 0, 0, 0)
    oresButton.BackgroundColor3 = Color3.fromRGB(40, 40, 80)
    oresButton.Text = "Ores"
    oresButton.TextColor3 = Color3.fromRGB(230, 230, 255)
    oresButton.Font = Enum.Font.GothamBold
    oresButton.TextSize = 14
    oresButton.Parent = modeBar

    local oresCorner = Instance.new("UICorner")
    oresCorner.CornerRadius = UDim.new(0, 6)
    oresCorner.Parent = oresButton

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

    local enemiesCorner = Instance.new("UICorner")
    enemiesCorner.CornerRadius = UDim.new(0, 6)
    enemiesCorner.Parent = enemiesButton

    -- Reset buttons row
    local resetRow = Instance.new("Frame")
    resetRow.Name = "ResetRow"
    resetRow.Size = UDim2.new(1, -20, 0, 24)
    resetRow.Position = UDim2.new(0, 10, 0, 72)
    resetRow.BackgroundTransparency = 1
    resetRow.Parent = mainFrame

    local resetOresBtn = Instance.new("TextButton")
    resetOresBtn.Name = "ResetOres"
    resetOresBtn.Size = UDim2.new(0.5, -5, 1, 0)
    resetOresBtn.Position = UDim2.new(0, 0, 0, 0)
    resetOresBtn.BackgroundColor3 = Color3.fromRGB(40, 60, 40)
    resetOresBtn.Text = "Reset Ores"
    resetOresBtn.Font = Enum.Font.Gotham
    resetOresBtn.TextSize = 13
    resetOresBtn.TextColor3 = Color3.fromRGB(220, 255, 220)
    resetOresBtn.Parent = resetRow

    local resetOresCorner = Instance.new("UICorner")
    resetOresCorner.CornerRadius = UDim.new(0, 6)
    resetOresCorner.Parent = resetOresBtn

    local resetEnemiesBtn = Instance.new("TextButton")
    resetEnemiesBtn.Name = "ResetEnemies"
    resetEnemiesBtn.Size = UDim2.new(0.5, -5, 1, 0)
    resetEnemiesBtn.Position = UDim2.new(0.5, 5, 0, 0)
    resetEnemiesBtn.BackgroundColor3 = Color3.fromRGB(60, 50, 40)
    resetEnemiesBtn.Text = "Reset Enemies"
    resetEnemiesBtn.Font = Enum.Font.Gotham
    resetEnemiesBtn.TextSize = 13
    resetEnemiesBtn.TextColor3 = Color3.fromRGB(255, 230, 200)
    resetEnemiesBtn.Parent = resetRow

    local resetEnemiesCorner = Instance.new("UICorner")
    resetEnemiesCorner.CornerRadius = UDim.new(0, 6)
    resetEnemiesCorner.Parent = resetEnemiesBtn

    -- Info text
    local infoLabel = Instance.new("TextLabel")
    infoLabel.Name = "InfoLabel"
    infoLabel.Size = UDim2.new(1, -20, 0, 40)
    infoLabel.Position = UDim2.new(0, 10, 0, 100)
    infoLabel.BackgroundTransparency = 1
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.TextSize = 12
    infoLabel.TextWrapped = true
    infoLabel.TextXAlignment = Enum.TextXAlignment.Left
    infoLabel.TextYAlignment = Enum.TextYAlignment.Top
    infoLabel.TextColor3 = Color3.fromRGB(190, 190, 200)
    infoLabel.Text = "Priority 1 is highest, bigger numbers are lower priority. " ..
        "Changes save instantly to PriorityConfig.json, but you MUST press 'Reload Priorities' " ..
        "in the main Forge script for them to take effect."
    infoLabel.Parent = mainFrame

    -- Scrolling content (below info text)
    local contentFrame = Instance.new("Frame")
    contentFrame.Name = "ContentFrame"
    contentFrame.Size = UDim2.new(1, -20, 1, -150)
    contentFrame.Position = UDim2.new(0, 10, 0, 140)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Parent = mainFrame

    local oresScroll = Instance.new("ScrollingFrame")
    oresScroll.Name = "OresScroll"
    oresScroll.Size = UDim2.new(1, 0, 1, 0)
    oresScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    oresScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    oresScroll.ScrollBarThickness = 6
    oresScroll.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    oresScroll.BorderSizePixel = 0
    oresScroll.Parent = contentFrame

    local oresLayout = Instance.new("UIListLayout")
    oresLayout.Padding = UDim.new(0, 4)
    oresLayout.SortOrder = Enum.SortOrder.Name
    oresLayout.Parent = oresScroll

    local enemiesScroll = Instance.new("ScrollingFrame")
    enemiesScroll.Name = "EnemiesScroll"
    enemiesScroll.Size = UDim2.new(1, 0, 1, 0)
    enemiesScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    enemiesScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    enemiesScroll.ScrollBarThickness = 6
    enemiesScroll.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    enemiesScroll.BorderSizePixel = 0
    enemiesScroll.Visible = false
    enemiesScroll.Parent = contentFrame

    local enemiesLayout = Instance.new("UIListLayout")
    enemiesLayout.Padding = UDim.new(0, 4)
    enemiesLayout.SortOrder = Enum.SortOrder.Name
    enemiesLayout.Parent = enemiesScroll

    -- Forward declarations so callbacks can rebuild
    local rebuildOresList, rebuildEnemiesList

    -- Helper to build a row (name + priority text box)
    local function createPriorityRow(parent, labelText, initialValue, onChanged)
        local row = Instance.new("Frame")
        row.Name = labelText
        row.Size = UDim2.new(1, -8, 0, 28)
        row.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
        row.BorderSizePixel = 0
        row.Parent = parent

        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 6)
        rowCorner.Parent = row

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "NameLabel"
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
        box.Name = "PriorityBox"
        box.Size = UDim2.new(0.3, -10, 1, -6)
        box.Position = UDim2.new(0.7, 0, 0, 3)
        box.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
        box.TextColor3 = Color3.fromRGB(255, 255, 255)
        box.Font = Enum.Font.GothamSemibold
        box.TextSize = 14
        box.ClearTextOnFocus = false
        box.TextXAlignment = Enum.TextXAlignment.Center
        box.Parent = row

        local lastValid = tonumber(initialValue) or 1
        if lastValid < 1 then lastValid = 1 end
        if lastValid > 999 then lastValid = 999 end
        box.Text = tostring(lastValid)

        local boxCorner = Instance.new("UICorner")
        boxCorner.CornerRadius = UDim.new(0, 6)
        boxCorner.Parent = box

        -- Strip any non-digit characters live
        box:GetPropertyChangedSignal("Text"):Connect(function()
            local raw = box.Text or ""
            local digits = raw:gsub("%D", "")
            if digits ~= raw then
                local oldLen = #raw
                local newLen = #digits
                local curPos = box.CursorPosition
                box.Text = digits
                local delta = oldLen - newLen
                if curPos ~= -1 then
                    box.CursorPosition = math.clamp(curPos - delta, 1, #digits + 1)
                end
            end
        end)

        -- Validate on focus lost
        box.FocusLost:Connect(function()
            local raw = box.Text or ""
            if raw == "" then
                -- Reject empty: revert
                box.Text = tostring(lastValid)
                return
            end

            local num = tonumber(raw)
            if not num then
                box.Text = tostring(lastValid)
                return
            end

            num = math.floor(num)
            if num < 1 then num = 1 end
            if num > 999 then num = 999 end -- hard clamp
            lastValid = num
            box.Text = tostring(num)

            if onChanged then
                onChanged(num)
            end
        end)

        return row
    end

    -- Rebuilders

    rebuildOresList = function()
        for _, child in ipairs(oresScroll:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end

        for _, name in ipairs(sortedKeysByPriority(PriorityConfig.Ores)) do
            local value = PriorityConfig.Ores[name]
            createPriorityRow(oresScroll, name, value, function(newValue)
                PriorityConfig.Ores[name] = newValue
                savePriorityConfig()
                -- re-sort list after every change
                rebuildOresList()
            end)
        end
    end

    rebuildEnemiesList = function()
        for _, child in ipairs(enemiesScroll:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end

        for _, name in ipairs(sortedKeysByPriority(PriorityConfig.Enemies)) do
            local value = PriorityConfig.Enemies[name]
            createPriorityRow(enemiesScroll, name, value, function(newValue)
                PriorityConfig.Enemies[name] = newValue
                savePriorityConfig()
                rebuildEnemiesList()
            end)
        end
    end

    rebuildOresList()
    rebuildEnemiesList()

    -- Mode switching
    local function setMode(mode)
        if mode == "Ores" then
            oresScroll.Visible             = true
            enemiesScroll.Visible          = false
            oresButton.BackgroundColor3    = Color3.fromRGB(60, 60, 120)
            oresButton.TextColor3          = Color3.fromRGB(255, 255, 255)
            enemiesButton.BackgroundColor3 = Color3.fromRGB(30, 40, 50)
            enemiesButton.TextColor3       = Color3.fromRGB(200, 200, 210)
        elseif mode == "Enemies" then
            oresScroll.Visible             = false
            enemiesScroll.Visible          = true
            enemiesButton.BackgroundColor3 = Color3.fromRGB(120, 60, 40)
            enemiesButton.TextColor3       = Color3.fromRGB(255, 240, 220)
            oresButton.BackgroundColor3    = Color3.fromRGB(30, 40, 50)
            oresButton.TextColor3          = Color3.fromRGB(200, 200, 210)
        end
    end

    oresButton.MouseButton1Click:Connect(function()
        setMode("Ores")
    end)

    enemiesButton.MouseButton1Click:Connect(function()
        setMode("Enemies")
    end)

    setMode("Ores")

    -- Reset buttons
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
