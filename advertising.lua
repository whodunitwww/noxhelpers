local ICON_ASSET_ID = "rbxassetid://136497541793809"
local GREEN = Color3.fromRGB(0, 220, 120)
local BLACK = Color3.fromRGB(10, 10, 10)
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Camera = workspace.CurrentCamera
local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui") or Players.LocalPlayer:WaitForChild("PlayerGui")
local function softenURLs(s)
    s = s:gsub("https?://[%w%p]+", function(url)
        url = url:gsub("/", "/\226\128\139")
        url = url:gsub("%.", ".\226\128\139")
        return url
    end)
    return s
end
local function copyToClipboard(text)
    local ok = false
    pcall(function()
        if setclipboard then setclipboard(text); ok = true
        elseif toclipboard then toclipboard(text); ok = true
        elseif (syn and syn.write_clipboard) then syn.write_clipboard(text); ok = true
        elseif writeclipboard then writeclipboard(text); ok = true
        end
    end)
    return ok
end
local function showNotification(opts)
    opts = opts or {}
    local titleText = tostring(opts.title or "Notification")
    local bodyRaw = tostring(opts.message or "")
    local bodyText = softenURLs(bodyRaw)
    local duration = tonumber(opts.duration or 5)
    local copyText = (type(opts.copyText) == "string" and #opts.copyText > 0) and opts.copyText or nil
    local buttonLabel = tostring(opts.buttonText or "Copy")
    local viewportX = Camera and Camera.ViewportSize.X or 1280
    local targetWidth = math.clamp(math.floor(viewportX * 0.8), 640, 1360)
    local gui = Instance.new("ScreenGui")
    gui.Name = "CerberusTopToast"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = playerGui
    local frame = Instance.new("Frame")
    frame.Name = "Toast"
    frame.Size = UDim2.fromOffset(targetWidth, 20)
    frame.AutomaticSize = Enum.AutomaticSize.Y
    frame.Position = UDim2.fromScale(0.5, -0.12)
    frame.AnchorPoint = Vector2.new(0.5, 0)
    frame.BackgroundColor3 = BLACK
    frame.BorderSizePixel = 0
    frame.BackgroundTransparency = 0.05
    frame.ClipsDescendants = true
    frame.Parent = gui
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 24); corner.Parent = frame
    local stroke = Instance.new("UIStroke"); stroke.Thickness = 4; stroke.Color = GREEN; stroke.Transparency = 0.2; stroke.Parent = frame
    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0.0, Color3.fromRGB(18,18,18)),
        ColorSequenceKeypoint.new(1.0, Color3.fromRGB(8,8,8))
    }
    grad.Rotation = 90
    grad.Parent = frame
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 20)
    padding.PaddingBottom = UDim.new(0, 20)
    padding.PaddingLeft = UDim.new(0, 24)
    padding.PaddingRight = UDim.new(0, 24)
    padding.Parent = frame
    local list = Instance.new("UIListLayout")
    list.FillDirection = Enum.FillDirection.Horizontal
    list.VerticalAlignment = Enum.VerticalAlignment.Center
    list.Padding = UDim.new(0, 20)
    list.Parent = frame
    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.fromOffset(80, 80)
    icon.BackgroundTransparency = 1
    icon.Image = ICON_ASSET_ID
    icon.ScaleType = Enum.ScaleType.Fit
    icon.Parent = frame
    local iconCorner = Instance.new("UICorner"); iconCorner.CornerRadius = UDim.new(0, 16); iconCorner.Parent = icon
    local reservedLeft = 80 + 20 + 24
    local reservedRight = (copyText and (340 + 20) or 0) + 24
    local textPixelWidth = targetWidth - reservedLeft - reservedRight
    local textHolder = Instance.new("Frame")
    textHolder.Name = "TextHolder"
    textHolder.BackgroundTransparency = 1
    textHolder.Size = UDim2.fromOffset(math.max(240, textPixelWidth), 0)
    textHolder.AutomaticSize = Enum.AutomaticSize.Y
    textHolder.Parent = frame
    local textLayout = Instance.new("UIListLayout")
    textLayout.FillDirection = Enum.FillDirection.Vertical
    textLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    textLayout.Padding = UDim.new(0, 4)
    textLayout.Parent = textHolder
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, 0, 0, 0)
    title.AutomaticSize = Enum.AutomaticSize.Y
    title.Font = Enum.Font.GothamBold
    title.TextSize = 36
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextYAlignment = Enum.TextYAlignment.Top
    title.TextWrapped = true
    title.Text = titleText
    title.TextColor3 = GREEN
    title.Parent = textHolder
    local body = Instance.new("TextLabel")
    body.Name = "Body"
    body.BackgroundTransparency = 1
    body.Size = UDim2.new(1, 0, 0, 0)
    body.AutomaticSize = Enum.AutomaticSize.Y
    body.Font = Enum.Font.Gotham
    body.TextSize = 32
    body.TextWrapped = true
    body.TextXAlignment = Enum.TextXAlignment.Left
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.TextTruncate = Enum.TextTruncate.None
    body.TextColor3 = Color3.fromRGB(225,225,225)
    body.Text = bodyText
    body.Parent = textHolder
    local btn
    if copyText then
        btn = Instance.new("TextButton")
        btn.Name = "CopyBtn"
        btn.Size = UDim2.fromOffset(340, 76)
        btn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        btn.AutoButtonColor = false
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 32
        btn.TextColor3 = Color3.fromRGB(255,255,255)
        btn.Text = buttonLabel
        btn.Parent = frame
        local btnCorner = Instance.new("UICorner"); btnCorner.CornerRadius = UDim.new(0, 20); btnCorner.Parent = btn
        local btnStroke = Instance.new("UIStroke"); btnStroke.Thickness = 4; btnStroke.Color = GREEN; btnStroke.Transparency = 0.25; btnStroke.Parent = btn
        btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {BackgroundColor3 = Color3.fromRGB(28,28,28)}):Play()
        end)
        btn.MouseLeave:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {BackgroundColor3 = Color3.fromRGB(20,20,20)}):Play()
        end)
        local copying = false
        btn.Activated:Connect(function()
            if copying then return end
            copying = true
            local ok = copyToClipboard(copyText)
            local original = btn.Text
            btn.Text = ok and "Copied!" or "Copy failed — see chat"
            if not ok then print("[Cerberus] Copy this:", copyText) end
            task.delay(1, function() btn.Text = original; copying = false end)
        end)
    end
    TweenService:Create(frame, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.fromScale(0.5, 0.03), BackgroundTransparency = 0.05}):Play()
    task.delay(duration, function()
        local out = TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = UDim2.fromScale(0.5, -0.12), BackgroundTransparency = 0.3})
        out:Play()
        out.Completed:Wait()
        gui:Destroy()
    end)
    if copyText then
        body.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                copyToClipboard(copyText)
            end
        end)
    end
end

local DISCORD = "https://getcerberus.com/discord"
math.randomseed(os.clock()*1e6)

showNotification{
    title = "Welcome to Cerberus",
    message = "Thanks for choosing Cerberus! Enjoy fast, safe features and a clean UI. Join our Discord for updates and support.",
    duration = 5,
    copyText = DISCORD,
    buttonText = "Copy Discord Link"
}

local pool = {
    {
        title = "Enjoying this script?",
        message = "Check out our Discord for more free scripts with over 30 supported games: " .. DISCORD,
        duration = 5,
        copyText = DISCORD,
        buttonText = "Copy Discord Link"
    },
    {
        title = "More Scripts. More Power.",
        message = "Grab updates, request features, and get instant help in our Discord. Don’t miss new releases and exclusive drops: " .. DISCORD,
        duration = 5,
        copyText = DISCORD,
        buttonText = "Copy Discord Link"
    }
}

task.spawn(function()
    while true do
        task.wait(120)
        local cfg = pool[math.random(1, #pool)]
        showNotification(cfg)
    end
end)
