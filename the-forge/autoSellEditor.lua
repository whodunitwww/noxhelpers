-- AutoSellConfigEditor.lua
-- Standalone config editor for AutoSell thresholds, with pretty UI + live ore icons.
-- UPDATED: Added Legendary/Mythical Essence and Essence Icons.

-- CONFIG PATH
local BASE_DIR             = "Cerberus/The Forge"  -- <== make sure this matches References.gameDir in your main script
local AutoSellConfigFile   = BASE_DIR .. "/AutoSellConfig.json"

local Players          = game:GetService("Players")
local HttpService      = game:GetService("HttpService")
local CoreGui          = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

----------------------------------------------------------------
-- DATA (mirrors main script)
----------------------------------------------------------------
local EssenceRarityMap = {
    ["Tiny Essence"]      = "Common",
    ["Small Essence"]     = "Common",
    ["Medium Essence"]    = "Uncommon",
    ["Large Essence"]     = "Uncommon",
    ["Greater Essence"]   = "Rare",
    ["Superior Essence"]  = "Epic",
    ["Epic Essence"]      = "Epic",
    ["Legendary Essence"] = "Legendary", -- ADDED
    ["Mythical Essence"]  = "Mythical",  -- ADDED
}

local OreRarityMap = {
    ["Stone"]             = "Common",
    ["Sand Stone"]        = "Common",
    ["Copper"]            = "Common",
    ["Iron"]              = "Common",
    ["Tin"]               = "Uncommon",
    ["Silver"]            = "Uncommon",
    ["Gold"]              = "Uncommon",
    ["Mushroomite"]       = "Rare",
    ["Platinum"]          = "Rare",
    ["Bananite"]          = "Uncommon",
    ["Cardboardite"]      = "Common",
    ["Aite"]              = "Epic",
    ["Poopite"]           = "Epic",
    ["Slimite"]           = "Epic",
    ["Cobalt"]            = "Uncommon",
    ["Titanium"]          = "Uncommon",
    ["Volcanic Rock"]     = "Rare",
    ["Lapis Lazuli"]      = "Uncommon",
    ["Quartz"]            = "Rare",
    ["Amethyst"]          = "Rare",
    ["Topaz"]             = "Rare",
    ["Diamond"]           = "Rare",
    ["Sapphire"]          = "Rare",
    ["Boneite"]           = "Rare",
    ["Dark Boneite"]      = "Rare",
    ["Cuprite"]           = "Epic",
    ["Obsidian"]          = "Epic",
    ["Emerald"]           = "Epic",
    ["Ruby"]              = "Epic",
    ["Rivalite"]          = "Epic",
    ["Uranium"]           = "Legendary",
    ["Mythril"]           = "Legendary",
    ["Eye Ore"]           = "Legendary",
    ["Fireite"]           = "Legendary",
    ["Magmaite"]          = "Legendary",
    ["Lightite"]          = "Legendary",
    ["Demonite"]          = "Mythical",
    ["Darkryte"]          = "Mythical",
}

-- strong rarity colours
local RarityColors = {
    Common    = Color3.fromRGB(140, 140, 140),
    Uncommon  = Color3.fromRGB(80, 190, 120),
    Rare      = Color3.fromRGB(90, 140, 240),
    Epic      = Color3.fromRGB(200, 90, 240),
    Legendary = Color3.fromRGB(255, 200, 80),
    Mythical  = Color3.fromRGB(255, 80, 110),
}

local EssenceNamesList = {
    "Tiny Essence",
    "Small Essence",
    "Medium Essence",
    "Large Essence",
    "Greater Essence",
    "Superior Essence",
    "Epic Essence",
    "Legendary Essence", -- ADDED
    "Mythical Essence",  -- ADDED
}

local OreNamesList = {}
for oreName in pairs(OreRarityMap) do
    table.insert(OreNamesList, oreName)
end

-- sort ores: Mythical -> Legendary -> Epic -> Rare -> Uncommon -> Common
local rarityOrder = {
    Mythical  = 1,
    Legendary = 2,
    Epic      = 3,
    Rare      = 4,
    Uncommon  = 5,
    Common    = 6,
}
table.sort(OreNamesList, function(a, b)
    local ra = rarityOrder[OreRarityMap[a]] or 99
    local rb = rarityOrder[OreRarityMap[b]] or 99
    if ra == rb then
        return a < b
    end
    return ra < rb
end)

local OreRarityList     = { "Mythical", "Legendary", "Epic", "Rare", "Uncommon", "Common" }
-- UPDATED: Added Mythical and Legendary to the filter list
local EssenceRarityList = { "Mythical", "Legendary", "Epic", "Rare", "Uncommon", "Common" }

-- Runes + image IDs
local RuneValues = {
    "Miner Shard",
    "Blast Chip",
    "Flame Spark",
    "Briar Notch",
    "Rage Mark",
    "Drain Edge",
    "Ward Patch",
    "Venom Crumb",
}

local RuneImageIds = {
    ["Ward Patch"]  = "136618198347198",
    ["Briar Notch"] = "130375351000261",
    ["Rage Mark"]   = "74377849245058",
    ["Miner Shard"] = "110898589664978",
    ["Flame Spark"] = "73865699740150",
    ["Blast Chip"]  = "85050444076173",
    ["Drain Edge"]  = "89173473574831",
    ["Venom Crumb"] = "77052262266995",
}

-- ADDED: Essence Image IDs
local EssenceImageIds = {
    ["Tiny Essence"]      = "72025528879375",
    ["Small Essence"]     = "117483889562292",
    ["Medium Essence"]    = "92874766076839",
    ["Large Essence"]     = "122449926928886",
    ["Greater Essence"]   = "75420167695755",
    ["Superior Essence"]  = "120798786019612",
    ["Epic Essence"]      = "71038820643974",
    ["Legendary Essence"] = "126658024565240",
    ["Mythical Essence"]  = "97191650147139",
}

----------------------------------------------------------------
-- GRAB ORE ICONS FROM IN-GAME MENU
----------------------------------------------------------------
local OreIconSources = {}
local GenericOreIconTemplate = nil

local function createGenericOreIcon()
    local vf = Instance.new("ViewportFrame")
    vf.BackgroundTransparency = 1
    vf.BorderSizePixel = 0

    local wm = Instance.new("WorldModel")
    wm.Parent = vf

    local ore = Instance.new("Part")
    ore.Size = Vector3.new(2, 2, 2)
    ore.Shape = Enum.PartType.Block
    ore.Material = Enum.Material.SmoothPlastic
    ore.Color = Color3.fromRGB(120, 180, 255)
    ore.Anchored = true
    ore.Position = Vector3.new(0, 0, 0)
    ore.Parent = wm

    local bevel = Instance.new("SpecialMesh")
    bevel.MeshType = Enum.MeshType.Sphere
    bevel.Scale = Vector3.new(0.9, 0.9, 0.9)
    bevel.Parent = ore

    local light = Instance.new("PointLight")
    light.Brightness = 2
    light.Range = 16
    light.Color = Color3.fromRGB(180, 220, 255)
    light.Parent = ore

    local cam = Instance.new("Camera")
    cam.CFrame = CFrame.new(Vector3.new(4, 3, 4), Vector3.new(0, 0, 0))
    cam.Parent = vf
    vf.CurrentCamera = cam

    return vf
end

local function getOreIconTemplate(oreName)
    local t = OreIconSources[oreName]
    if t then return t end
    if not GenericOreIconTemplate then
        GenericOreIconTemplate = createGenericOreIcon()
    end
    return GenericOreIconTemplate
end

local function initOreIcons()
    local ok, oresRoot = pcall(function()
        return LocalPlayer
            :WaitForChild("PlayerGui", 5)
            .Menu
            .Frame
            .Frame
            .Menus
            .Index
            .Pages
            .Ores
    end)

    if not ok or not oresRoot then
        warn("[AutoSellEditor] Could not locate Menu.Ores root; icons will be generic.")
        return
    end

    local listNames = {
        "Forgotten Kingdom List",
        "Iron Valley List",
    }

    for _, listName in ipairs(listNames) do
        local listFolder = oresRoot:FindFirstChild(listName)
        if listFolder then
            for _, oreFrame in ipairs(listFolder:GetChildren()) do
                if oreFrame:IsA("Frame") then
                    local main = oreFrame:FindFirstChild("Main")
                    local vf   = main and main:FindFirstChild("ViewportFrame")
                    if vf and vf:IsA("ViewportFrame") then
                        OreIconSources[oreFrame.Name] = vf
                    end
                end
            end
        end
    end
end

initOreIcons()

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local function makeDefaultConfig()
    return {
        version         = 1,
        ores            = {},
        oreRarities     = {},
        essence         = {},
        essenceRarities = {},
        runes           = {},
    }
end

local Config = nil

local function loadConfig()
    if not (isfile and readfile) then
        return makeDefaultConfig()
    end

    if not isfile(AutoSellConfigFile) then
        return makeDefaultConfig()
    end

    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(readfile(AutoSellConfigFile))
    end)

    if not ok or type(decoded) ~= "table" then
        return makeDefaultConfig()
    end

    decoded.version         = decoded.version or 1
    decoded.ores            = decoded.ores            or {}
    decoded.oreRarities     = decoded.oreRarities     or {}
    decoded.essence         = decoded.essence         or {}
    decoded.essenceRarities = decoded.essenceRarities or {}
    decoded.runes           = decoded.runes           or {}

    return decoded
end

local function saveConfig()
    if not (writefile and HttpService.JSONEncode) then return end
    local ok, raw = pcall(function()
        return HttpService:JSONEncode(Config)
    end)
    if ok then
        pcall(writefile, AutoSellConfigFile, raw)
    end
end

Config = loadConfig()

----------------------------------------------------------------
-- UI HELPERS
----------------------------------------------------------------
local function safeParentGui(gui)
    if gethui then
        gui.Parent = gethui()
    elseif syn and syn.protect_gui then
        syn.protect_gui(gui)
        gui.Parent = CoreGui
    else
        gui.Parent = CoreGui
    end
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
local function createUI()
    local existing = CoreGui:FindFirstChild("AutoSellConfigGui")
    if existing then
        existing:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "AutoSellConfigGui"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    safeParentGui(gui)

    local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

    -- main window
    local mainFrame = Instance.new("Frame")
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    if isMobile then
        -- Scale-based, fills most of the screen on phones
        mainFrame.Size = UDim2.new(0.96, 0, 0.85, 0)
    else
        -- Desktop-style fixed size
        mainFrame.Size = UDim2.new(0, 900, 0, 480)
    end
    mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    mainFrame.BorderSizePixel = 0
    mainFrame.ZIndex = 2
    mainFrame.Parent = gui

    local uicorner = Instance.new("UICorner")
    uicorner.CornerRadius = UDim.new(0, 12)
    uicorner.Parent = mainFrame

    local mfGrad = Instance.new("UIGradient")
    mfGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 30, 40)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 12, 18)),
    })
    mfGrad.Rotation = 90
    mfGrad.Parent = mainFrame

    -- title bar
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 38)
    titleBar.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
    titleBar.BorderSizePixel = 0
    titleBar.ZIndex = 3
    titleBar.Parent = mainFrame

    local tbCorner = Instance.new("UICorner")
    tbCorner.CornerRadius = UDim.new(0, 12)
    tbCorner.Parent = titleBar

    local tbGrad = Instance.new("UIGradient")
    tbGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 50, 90)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 24, 32)),
    })
    tbGrad.Rotation = 0
    tbGrad.Parent = titleBar

    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(0, 300, 1, 0)
    titleText.Position = UDim2.new(0, 16, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.Font = Enum.Font.GothamBold
    titleText.TextSize = 18
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleText.Text = "Cerberus • AutoSell Configuration"
    titleText.ZIndex = 4
    titleText.Parent = titleBar

    local subtitle = Instance.new("TextLabel")
    subtitle.Size = UDim2.new(1, -120, 1, 0)
    subtitle.Position = UDim2.new(0, 0, 0, 0)
    subtitle.BackgroundTransparency = 1
    subtitle.Font = Enum.Font.Gotham
    subtitle.TextSize = 12
    subtitle.TextXAlignment = Enum.TextXAlignment.Right
    subtitle.TextColor3 = Color3.fromRGB(185, 185, 210)
    subtitle.Text = "WORK IN PROGRESS"
    subtitle.ZIndex = 4
    subtitle.Parent = titleBar

    local closeButton = Instance.new("TextButton")
    closeButton.Size = UDim2.new(0, 38, 1, 0)
    closeButton.Position = UDim2.new(1, -38, 0, 0)
    closeButton.BackgroundTransparency = 1
    closeButton.Text = "X"
    closeButton.Font = Enum.Font.GothamBold
    closeButton.TextSize = 18
    closeButton.TextColor3 = Color3.fromRGB(235, 90, 90)
    closeButton.ZIndex = 10
    closeButton.Parent = titleBar

    local infoLabel = Instance.new("TextLabel")
    infoLabel.Size = UDim2.new(1, -32, 0, 42)
    infoLabel.Position = UDim2.new(0, 16, 0, 44)
    infoLabel.BackgroundTransparency = 1
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.TextSize = 13
    infoLabel.TextWrapped = true
    infoLabel.TextXAlignment = Enum.TextXAlignment.Left
    infoLabel.TextYAlignment = Enum.TextYAlignment.Top
    infoLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
    infoLabel.ZIndex = 3
    infoLabel.Text =
        "Threshold is how many to keep; any extra gets auto-sold. " ..
        "Changes save instantly; hit Reload AutoSell in the main script to apply."
    infoLabel.Parent = mainFrame

    ----------------------------------------------------------------
    -- TAB BAR (scrollable for mobile)
    ----------------------------------------------------------------
    local tabBar = Instance.new("ScrollingFrame")
    tabBar.Size = UDim2.new(1, -32, 0, 30)
    tabBar.Position = UDim2.new(0, 16, 0, 90)
    tabBar.BackgroundTransparency = 1
    tabBar.ZIndex = 3
    tabBar.ScrollBarThickness = isMobile and 6 or 3
    tabBar.ScrollingDirection = Enum.ScrollingDirection.X
    tabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
    tabBar.BorderSizePixel = 0
    tabBar.Parent = mainFrame

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 8)
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Parent = tabBar

    tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        tabBar.CanvasSize = UDim2.new(0, tabLayout.AbsoluteContentSize.X + 8, 0, 0)
    end)

    ----------------------------------------------------------------
    -- CONTENT AREA
    ----------------------------------------------------------------
    local contentFrame = Instance.new("Frame")
    contentFrame.Size = UDim2.new(1, -32, 1, -146)
    contentFrame.Position = UDim2.new(0, 16, 0, 130)
    contentFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
    contentFrame.BorderSizePixel = 0
    contentFrame.ZIndex = 2
    contentFrame.Parent = mainFrame

    local cfCorner = Instance.new("UICorner")
    cfCorner.CornerRadius = UDim.new(0, 10)
    cfCorner.Parent = contentFrame

    local cfStroke = Instance.new("UIStroke")
    cfStroke.Color = Color3.fromRGB(60, 60, 90)
    cfStroke.Thickness = 1
    cfStroke.Transparency = 0.35
    cfStroke.Parent = contentFrame

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -8, 1, -8)
    scroll.Position = UDim2.new(0, 4, 0, 4)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.ScrollBarThickness = isMobile and 10 or 6
    scroll.BackgroundTransparency = 1
    scroll.ZIndex = 2
    scroll.BorderSizePixel = 0
    scroll.Parent = contentFrame

    local grid = Instance.new("UIGridLayout")
    grid.CellSize = UDim2.new(0, 275, 0, 55) -- will be updated responsively
    grid.CellPadding = UDim2.new(0, 8, 0, 8)
    grid.FillDirection = Enum.FillDirection.Horizontal
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.Parent = scroll

    local padding = Instance.new("UIPadding")
    padding.PaddingTop    = UDim.new(0, 8)
    padding.PaddingLeft   = UDim.new(0, 8)
    padding.PaddingRight  = UDim.new(0, 8)
    padding.PaddingBottom = UDim.new(0, 8)
    padding.Parent = scroll

    grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.new(0, 0, 0, grid.AbsoluteContentSize.Y + 16)
    end)

    ----------------------------------------------------------------
    -- RESPONSIVE GRID (desktop / tablet / phone)
    ----------------------------------------------------------------
    local function updateGridLayout()
        local width = scroll.AbsoluteSize.X - 16 -- padding
        if width <= 0 then return end

        local columns
        if width >= 820 then
            columns = 3
        elseif width >= 540 then
            columns = 2
        else
            columns = 1
        end

        local cardWidth = math.floor((width - (columns - 1) * 8) / columns)
        grid.CellSize = UDim2.new(0, cardWidth, 0, 55)
    end

    scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateGridLayout)
    mainFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateGridLayout)

    -- initial layout
    task.defer(updateGridLayout)

    ----------------------------------------------------------------
    -- drag logic for title bar (mouse + touch)
    ----------------------------------------------------------------
    do
        local dragging, dragStart, startPos
        titleBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch
            then
                dragging = true
                dragStart = input.Position
                startPos  = mainFrame.Position
            end
        end)
        titleBar.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch
            then
                dragging = false
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and (
                input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch
            ) then
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

    local function closeGui()
        gui:Destroy()
    end

    closeButton.MouseButton1Click:Connect(closeGui)

    ----------------------------------------------------------------
    -- Card creators
    ----------------------------------------------------------------
    local function makeToggleButton(parent, initialEnabled, rarityName, onChanged)
        local btn = Instance.new("TextButton")
        btn.AnchorPoint = Vector2.new(1, 0.5)
        btn.Position = UDim2.new(1, -8, 0.5, 0)
        btn.Size = UDim2.new(0, 50, 0, 24)
        btn.BorderSizePixel = 0
        btn.ZIndex = 4
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 12
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.AutoButtonColor = false
        btn.Parent = parent

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = btn

        local function applyState(enabled)
            if enabled then
                btn.Text = "ON"
                btn.BackgroundColor3 = rarityName and RarityColors[rarityName] or Color3.fromRGB(90, 200, 120)
            else
                btn.Text = "OFF"
                btn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
            end
        end

        applyState(initialEnabled)

        btn.MouseButton1Click:Connect(function()
            local enabled = (btn.Text ~= "ON")
            applyState(enabled)
            onChanged(enabled)
        end)

        return btn
    end

    -- item card (with threshold)
    -- iconTemplate: ViewportFrame (ores)
    -- iconImageId: string assetId (runes)
    local function createItemCard(labelText, initialEnabled, initialThreshold, onChanged, iconTemplate, rarityName, iconImageId)
        local card = Instance.new("Frame")
        card.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
        card.BorderSizePixel = 0
        card.ZIndex = 2

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = card

        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 1
        stroke.Transparency = 0.35
        stroke.Color = rarityName and (RarityColors[rarityName] or Color3.fromRGB(70, 70, 90)) or Color3.fromRGB(70, 70, 90)
        stroke.Parent = card

        -- subtle gradient tinted by rarity
        local grad = Instance.new("UIGradient")
        local base1 = Color3.fromRGB(26, 26, 36)
        local base2 = Color3.fromRGB(16, 16, 24)
        if rarityName and RarityColors[rarityName] then
            local tint = RarityColors[rarityName]
            base1 = Color3.new(
                (base1.R + tint.R) / 2,
                (base1.G + tint.G) / 2,
                (base1.B + tint.B) / 2
            )
        end
        grad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, base1),
            ColorSequenceKeypoint.new(1, base2),
        })
        grad.Rotation = 90
        grad.Parent = card

        -- icon
        local iconHolder = Instance.new("Frame")
        iconHolder.AnchorPoint = Vector2.new(0, 0.5)
        iconHolder.Size = UDim2.new(0, 38, 0, 38)
        iconHolder.Position = UDim2.new(0, 8, 0.5, 0)
        iconHolder.BackgroundTransparency = 1
        iconHolder.ZIndex = 3
        iconHolder.Parent = card

        local iconBG = Instance.new("Frame")
        iconBG.Size = UDim2.new(1, 0, 1, 0)
        iconBG.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
        iconBG.BorderSizePixel = 0
        iconBG.ZIndex = 3
        iconBG.Parent = iconHolder

        local iconCorner = Instance.new("UICorner")
        iconCorner.CornerRadius = UDim.new(0, 6)
        iconCorner.Parent = iconBG

        local iconStroke = Instance.new("UIStroke")
        iconStroke.Color = stroke.Color
        iconStroke.Transparency = 0.25
        iconStroke.Thickness = 1
        iconStroke.Parent = iconBG

        local icon
        if iconTemplate then
            icon = iconTemplate:Clone()
            icon.Size = UDim2.fromScale(1, 1)
            icon.Position = UDim2.new(0, 0, 0, 0)
            icon.AnchorPoint = Vector2.new(0, 0)
            icon.BackgroundTransparency = 1
            icon.BorderSizePixel = 0
            icon.ZIndex = 4
            icon.Parent = iconBG

            local cam = icon:FindFirstChildOfClass("Camera")
            if cam then
                icon.CurrentCamera = cam
            end
        elseif iconImageId then
            icon = Instance.new("ImageLabel")
            icon.Size = UDim2.fromScale(1, 1)
            icon.Position = UDim2.new(0, 0, 0, 0)
            icon.AnchorPoint = Vector2.new(0, 0)
            icon.BackgroundTransparency = 1
            icon.BorderSizePixel = 0
            icon.Image = "rbxassetid://" .. iconImageId
            icon.ScaleType = Enum.ScaleType.Fit
            icon.ZIndex = 4
            icon.Parent = iconBG
        end

        -- name
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Position = UDim2.new(0, 54, 0, 0)
        nameLabel.Size = UDim2.new(1, -120, 1, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamSemibold
        nameLabel.TextSize = 13
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextYAlignment = Enum.TextYAlignment.Center
        nameLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        nameLabel.Text = labelText
        nameLabel.ZIndex = 4
        nameLabel.Parent = card

        -- internal state
        local enabledState    = initialEnabled
        local currentThreshold = initialThreshold or 0

        -- toggle button
        makeToggleButton(card, enabledState, rarityName, function(enabled)
            enabledState = enabled
            onChanged(enabledState, currentThreshold)
        end)

        -- threshold box
        local thresholdBox = Instance.new("TextBox")
        thresholdBox.AnchorPoint = Vector2.new(1, 0.5)
        thresholdBox.Size = UDim2.new(0, 44, 0, 24)
        thresholdBox.Position = UDim2.new(1, -64, 0.5, 0) -- 64px from right
        thresholdBox.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        thresholdBox.BorderSizePixel = 0
        thresholdBox.Font = Enum.Font.Gotham
        thresholdBox.TextSize = 12
        thresholdBox.TextColor3 = Color3.fromRGB(255, 255, 255)
        thresholdBox.Text = tostring(initialThreshold or 0)
        thresholdBox.PlaceholderText = "0"
        thresholdBox.ClearTextOnFocus = false
        thresholdBox.ZIndex = 4
        thresholdBox.Parent = card

        local thCorner = Instance.new("UICorner")
        thCorner.CornerRadius = UDim.new(0, 6)
        thCorner.Parent = thresholdBox

        local function updateCallback()
            local txt = thresholdBox.Text:gsub("%D", "")
            local num = tonumber(txt) or 0
            num = math.clamp(num, 0, 999)
            thresholdBox.Text = tostring(num)
            currentThreshold = num
            onChanged(enabledState, currentThreshold)
        end

        thresholdBox.FocusLost:Connect(function()
            updateCallback()
        end)

        -- hover highlight (mouse only)
        card.MouseEnter:Connect(function()
            card.BackgroundColor3 = Color3.fromRGB(26, 26, 36)
        end)
        card.MouseLeave:Connect(function()
            card.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
        end)

        return card
    end

    -- rarity card (no quantity)
    local function createRarityCard(labelText, initialEnabled, onChanged, rarityName)
        local card = Instance.new("Frame")
        card.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
        card.BorderSizePixel = 0
        card.ZIndex = 2

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = card

        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 1
        stroke.Transparency = 0.35
        stroke.Color = rarityName and (RarityColors[rarityName] or Color3.fromRGB(70, 70, 90)) or Color3.fromRGB(70, 70, 90)
        stroke.Parent = card

        local grad = Instance.new("UIGradient")
        local base1 = Color3.fromRGB(28, 28, 38)
        local base2 = Color3.fromRGB(16, 16, 24)
        if rarityName and RarityColors[rarityName] then
            local tint = RarityColors[rarityName]
            base1 = Color3.new(
                (base1.R + tint.R) / 2,
                (base1.G + tint.G) / 2,
                (base1.B + tint.B) / 2
            )
        end
        grad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, base1),
            ColorSequenceKeypoint.new(1, base2),
        })
        grad.Rotation = 90
        grad.Parent = card

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Position = UDim2.new(0, 14, 0, 0)
        nameLabel.Size = UDim2.new(1, -70, 1, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamSemibold
        nameLabel.TextSize = 14
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextYAlignment = Enum.TextYAlignment.Center
        nameLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
        nameLabel.Text = labelText
        nameLabel.ZIndex = 4
        nameLabel.Parent = card

        local enabledState = initialEnabled
        makeToggleButton(card, enabledState, rarityName, function(enabled)
            enabledState = enabled
            onChanged(enabledState)
        end)

        card.MouseEnter:Connect(function()
            card.BackgroundColor3 = Color3.fromRGB(26, 26, 36)
        end)
        card.MouseLeave:Connect(function()
            card.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
        end)

        return card
    end

    ----------------------------------------------------------------
    -- Tabs / population
    ----------------------------------------------------------------
    local currentTab = nil
    local tabButtons = {}

    local function clearCards()
        for _, child in ipairs(scroll:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end
    end

    local function setTab(name)
        currentTab = name
        for tabName, btn in pairs(tabButtons) do
            btn.BackgroundColor3 = (tabName == name) and Color3.fromRGB(70, 70, 110) or Color3.fromRGB(35, 35, 50)
        end

        clearCards()

        if name == "Ores" then
            for _, oreName in ipairs(OreNamesList) do
                local rule = Config.ores[oreName] or { enabled = false, threshold = 0 }
                local iconTemplate = getOreIconTemplate(oreName)
                local rarityName = OreRarityMap[oreName]

                local card = createItemCard(
                    oreName,
                    rule.enabled,
                    rule.threshold or 0,
                    function(enabled, threshold)
                        Config.ores[oreName] = { enabled = enabled, threshold = threshold }
                        saveConfig()
                    end,
                    iconTemplate,
                    rarityName
                )

                card.Parent = scroll
            end

        elseif name == "Ore Rarities" then
            for _, rName in ipairs(OreRarityList) do
                local rule = Config.oreRarities[rName] or { enabled = false, threshold = 0 }

                local card = createRarityCard(
                    rName,
                    rule.enabled,
                    function(enabled)
                        -- no quantity: always treat rarity threshold as 0, just enable/disable
                        Config.oreRarities[rName] = { enabled = enabled, threshold = 0 }
                        saveConfig()
                    end,
                    rName
                )

                card.Parent = scroll
            end

        elseif name == "Essence" then
            for _, essName in ipairs(EssenceNamesList) do
                local rule = Config.essence[essName] or { enabled = false, threshold = 0 }
                local rarityName = EssenceRarityMap[essName]
                -- ADDED: Look up image ID
                local imageId = EssenceImageIds[essName]

                local card = createItemCard(
                    essName,
                    rule.enabled,
                    rule.threshold or 0,
                    function(enabled, threshold)
                        Config.essence[essName] = { enabled = enabled, threshold = threshold }
                        saveConfig()
                    end,
                    nil,        -- no viewport
                    rarityName,
                    imageId     -- pass image ID
                )

                card.Parent = scroll
            end

        elseif name == "Essence Rarities" then
            for _, rName in ipairs(EssenceRarityList) do
                local rule = Config.essenceRarities[rName] or { enabled = false, threshold = 0 }

                local card = createRarityCard(
                    rName,
                    rule.enabled,
                    function(enabled)
                        Config.essenceRarities[rName] = { enabled = enabled, threshold = 0 }
                        saveConfig()
                    end,
                    rName
                )

                card.Parent = scroll
            end

        elseif name == "Runes" then
            for _, runeName in ipairs(RuneValues) do
                local rule = Config.runes[runeName] or { enabled = false, threshold = 0 }
                local imageId = RuneImageIds[runeName]

                local card = createItemCard(
                    runeName,
                    rule.enabled,
                    rule.threshold or 0,
                    function(enabled, threshold)
                        Config.runes[runeName] = { enabled = enabled, threshold = threshold }
                        saveConfig()
                    end,
                    nil,             -- no viewport
                    "Rare",          -- treat as Rare for colour
                    imageId          -- iconImageId
                )

                card.Parent = scroll
            end
        end

        -- recalc scroll / grid layout after repopulating
        task.defer(updateGridLayout)
    end

    local function makeTabButton(name)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 120, 1, 0)
        btn.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
        btn.BorderSizePixel = 0
        btn.Font = Enum.Font.GothamSemibold
        btn.TextSize = 13
        btn.TextColor3 = Color3.fromRGB(225, 225, 235)
        btn.Text = name
        btn.ZIndex = 3
        btn.Parent = tabBar

        local bCorner = Instance.new("UICorner")
        bCorner.CornerRadius = UDim.new(0, 6)
        bCorner.Parent = btn

        btn.MouseButton1Click:Connect(function()
            setTab(name)
        end)

        tabButtons[name] = btn
    end

    makeTabButton("Ores")
    makeTabButton("Ore Rarities")
    makeTabButton("Essence")
    makeTabButton("Essence Rarities")
    makeTabButton("Runes")

    setTab("Ores")

    return gui
end

-- Expose to main script (so a button can re-open it)
getgenv().OpenAutoSellConfig = function()
    createUI()
end

-- Auto-open when running this script standalone
createUI()
