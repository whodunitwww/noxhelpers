--// Animation Scrubber GUI (Draggable / Closable / Minimizable) - LocalScript
--// FIXES:
--//  - Pause works (we manage speed ourselves)
--//  - Scrubbing updates pose on character (track kept "armed": playing + weight + speed 0)
--//  - Slider is easier to grab (bigger hitbox + drag anywhere + click-to-jump)

local Services = rawget(_G, "Services") or {
	Players = game:GetService("Players"),
	UserInputService = game:GetService("UserInputService"),
	RunService = game:GetService("RunService"),
}

local LocalPlayer = Services.Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local function getCharacter()
	return (rawget(_G, "References") and _G.References.character) or LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getHumanoid()
	local character = getCharacter()
	return (rawget(_G, "References") and _G.References.humanoid)
		or character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid")
end

local function getAnimator(humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

local function mk(className, props)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	return inst
end

local function round2(n)
	return math.floor(n * 100 + 0.5) / 100
end

--// Root GUI
local screen = mk("ScreenGui", {
	Name = "AnimScrubberGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
})
screen.Parent = PlayerGui

local main = mk("Frame", {
	Name = "Main",
	Position = UDim2.fromOffset(40, 200),
	Size = UDim2.fromOffset(420, 230),
	BackgroundColor3 = Color3.fromRGB(20, 22, 28),
	BorderSizePixel = 0,
})
main.Parent = screen
mk("UICorner", { CornerRadius = UDim.new(0, 12), Parent = main })
mk("UIStroke", { Thickness = 1, Transparency = 0.3, Color = Color3.fromRGB(120, 140, 170), Parent = main })

-- Top bar
local topBar = mk("Frame", {
	Name = "TopBar",
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundColor3 = Color3.fromRGB(16, 18, 24),
	BorderSizePixel = 0,
})
topBar.Parent = main
mk("UICorner", { CornerRadius = UDim.new(0, 12), Parent = topBar })

local topMask = mk("Frame", {
	Name = "TopMask",
	Position = UDim2.fromOffset(0, 24),
	Size = UDim2.new(1, 0, 1, -24),
	BackgroundColor3 = main.BackgroundColor3,
	BorderSizePixel = 0,
})
topMask.Parent = topBar

local title = mk("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 0),
	Size = UDim2.new(1, -120, 1, 0),
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(230, 240, 255),
	Text = "Animation Scrubber",
})
title.Parent = topBar

local function topButton(txt, x)
	local b = mk("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -x, 0.5, 0),
		Size = UDim2.fromOffset(28, 22),
		BackgroundColor3 = Color3.fromRGB(30, 33, 41),
		TextColor3 = Color3.fromRGB(235, 245, 255),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		Text = txt,
		AutoButtonColor = true,
	})
	b.Parent = topBar
	mk("UICorner", { CornerRadius = UDim.new(0, 7), Parent = b })
	return b
end

local closeBtn = topButton("X", 10)
closeBtn.BackgroundColor3 = Color3.fromRGB(170, 60, 60)
local minBtn = topButton("—", 44)

local body = mk("Frame", {
	Name = "Body",
	Position = UDim2.fromOffset(0, 34),
	Size = UDim2.new(1, 0, 1, -34),
	BackgroundTransparency = 1,
})
body.Parent = main

local idLabel = mk("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 10),
	Size = UDim2.fromOffset(110, 20),
	Font = Enum.Font.Gotham,
	TextSize = 12,
	TextColor3 = Color3.fromRGB(200, 210, 225),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Animation ID:",
})
idLabel.Parent = body

local idBox = mk("TextBox", {
	Name = "IdBox",
	Position = UDim2.fromOffset(120, 6),
	Size = UDim2.fromOffset(288, 28),
	BackgroundColor3 = Color3.fromRGB(30, 33, 41),
	TextColor3 = Color3.fromRGB(235, 245, 255),
	PlaceholderText = "Paste ID (e.g. 507771019) or rb*assetid://...",
	PlaceholderColor3 = Color3.fromRGB(140, 150, 165),
	Font = Enum.Font.Gotham,
	TextSize = 12,
	ClearTextOnFocus = false,
	Text = "",
	TextXAlignment = Enum.TextXAlignment.Left,
})
idBox.Parent = body
mk("UICorner", { CornerRadius = UDim.new(0, 8), Parent = idBox })
mk("UIPadding", { PaddingLeft = UDim.new(0, 10), Parent = idBox })

local function makeButton(parent, text, x, y, w)
	local b = mk("TextButton", {
		Size = UDim2.fromOffset(w, 30),
		Position = UDim2.fromOffset(x, y),
		BackgroundColor3 = Color3.fromRGB(45, 90, 160),
		TextColor3 = Color3.fromRGB(245, 250, 255),
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		Text = text,
		AutoButtonColor = true,
	})
	b.Parent = parent
	mk("UICorner", { CornerRadius = UDim.new(0, 8), Parent = b })
	return b
end

local loadBtn  = makeButton(body, "Load / Apply", 12, 44, 130)
local playBtn  = makeButton(body, "Play",         148, 44, 90)
local pauseBtn = makeButton(body, "Pause",        244, 44, 90)
local resetBtn = makeButton(body, "Reset",        340, 44, 68)
resetBtn.BackgroundColor3 = Color3.fromRGB(170, 60, 60)

local sliderLabel = mk("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 86),
	Size = UDim2.fromOffset(396, 18),
	Font = Enum.Font.Gotham,
	TextSize = 12,
	TextColor3 = Color3.fromRGB(200, 210, 225),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Time: 0.00s / 0.00s",
})
sliderLabel.Parent = body

-- Slider visuals
local slider = mk("Frame", {
	Name = "Slider",
	Position = UDim2.fromOffset(12, 110),
	Size = UDim2.fromOffset(396, 16),
	BackgroundColor3 = Color3.fromRGB(30, 33, 41),
	BorderSizePixel = 0,
})
slider.Parent = body
mk("UICorner", { CornerRadius = UDim.new(0, 8), Parent = slider })

local fill = mk("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = Color3.fromRGB(95, 169, 230),
	BorderSizePixel = 0,
})
fill.Parent = slider
mk("UICorner", { CornerRadius = UDim.new(0, 8), Parent = fill })

local knob = mk("Frame", {
	Name = "Knob",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0, 0.5),
	Size = UDim2.fromOffset(14, 14),
	BackgroundColor3 = Color3.fromRGB(235, 245, 255),
	BorderSizePixel = 0,
})
knob.Parent = slider
mk("UICorner", { CornerRadius = UDim.new(1, 0), Parent = knob })
mk("UIStroke", { Thickness = 1, Transparency = 0.35, Color = Color3.fromRGB(0, 0, 0), Parent = knob })

-- BIG hitbox to make it easy to grab (covers above/below slider too)
local sliderHit = mk("TextButton", {
	Name = "SliderHitbox",
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	Position = UDim2.new(0, 0, 0, -10),
	Size = UDim2.new(1, 0, 1, 20),
})
sliderHit.Parent = slider

local hint = mk("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 136),
	Size = UDim2.fromOffset(396, 18),
	Font = Enum.Font.Gotham,
	TextSize = 11,
	TextColor3 = Color3.fromRGB(145, 155, 170),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Load an animation, then scrub (should move your character).",
})
hint.Parent = body

--// Animation state
local currentTrack: AnimationTrack? = nil
local currentAnim: Animation? = nil
local isScrubbing = false
local currentSpeed = 0 -- we manage this ourselves (0 paused / 1 playing)

local function normalizeAnimId(text: string): string?
	local t = (text or ""):gsub("%s+", "")
	if t == "" then return nil end
	if t:match("^%d+$") then return "rbxassetid://" .. t end
	if t:find("rbxassetid://") or t:find("rbxasset://") then return t end
	local num = t:match("(%d+)")
	if num then return "rbxassetid://" .. num end
	return nil
end

local function clearAnim()
	currentSpeed = 0
	if currentTrack then
		pcall(function() currentTrack:Stop(0) end)
		pcall(function() currentTrack:Destroy() end)
		currentTrack = nil
	end
	if currentAnim then
		pcall(function() currentAnim:Destroy() end)
		currentAnim = nil
	end
	fill.Size = UDim2.fromScale(0, 1)
	knob.Position = UDim2.fromScale(0, 0.5)
	sliderLabel.Text = "Time: 0.00s / 0.00s"
end

-- Keeps animation affecting the character, even when "paused" (speed 0)
local function ensureArmed()
	if not currentTrack then return end

	-- Force it to be playing so TimePosition updates visually
	if not currentTrack.IsPlaying then
		pcall(function() currentTrack:Play(0) end)
	end

	-- Weight & priority to override default Animate where possible
	pcall(function() currentTrack:AdjustWeight(1, 0) end)
	pcall(function() currentTrack.Priority = Enum.AnimationPriority.Core end) -- strongest
end

local function setSpeed(speed: number)
	if not currentTrack then return end
	ensureArmed()
	currentSpeed = speed
	pcall(function() currentTrack:AdjustSpeed(speed) end)
end

local function applyAnim()
	local animId = normalizeAnimId(idBox.Text)
	if not animId then
		hint.Text = "Invalid ID. Paste a number or rb*assetid:// format."
		return
	end

	clearAnim()

	local humanoid = getHumanoid()
	local animator = getAnimator(humanoid)

	currentAnim = Instance.new("Animation")
	currentAnim.AnimationId = animId

	local ok, trackOrErr = pcall(function()
		return animator:LoadAnimation(currentAnim)
	end)

	if not ok or typeof(trackOrErr) ~= "Instance" then
		hint.Text = "Failed to load (private / not permitted / invalid)."
		clearAnim()
		return
	end

	currentTrack = trackOrErr :: AnimationTrack
	currentTrack.Looped = false
	currentTrack.Priority = Enum.AnimationPriority.Core

	-- Arm it immediately and pause at t=0
	ensureArmed()
	pcall(function() currentTrack.TimePosition = 0 end)
	setSpeed(0)

	hint.Text = "Loaded. Drag slider to scrub (should move your character)."
end

local function setTrackTime(alpha: number)
	alpha = math.clamp(alpha, 0, 1)

	fill.Size = UDim2.fromScale(alpha, 1)
	knob.Position = UDim2.fromScale(alpha, 0.5)

	if not currentTrack then
		sliderLabel.Text = "Time: 0.00s / 0.00s"
		return
	end

	local length = currentTrack.Length
	if not length or length <= 0 then
		sliderLabel.Text = "Time: 0.00s / 0.00s"
		return
	end

	local t = alpha * length

	-- The key: keep it armed + speed 0, then set TimePosition
	ensureArmed()
	pcall(function()
		currentTrack:AdjustSpeed(0) -- freeze while scrubbing
		currentTrack.TimePosition = t
	end)

	sliderLabel.Text = ("Time: %.2fs / %.2fs"):format(round2(t), round2(length))
end

local function alphaFromMouseX(x: number)
	local absPos = slider.AbsolutePosition.X
	local absSize = slider.AbsoluteSize.X
	if absSize <= 0 then return 0 end
	return (x - absPos) / absSize
end

-- Buttons
loadBtn.MouseButton1Click:Connect(applyAnim)

playBtn.MouseButton1Click:Connect(function()
	if not currentTrack then
		hint.Text = "Load an animation first."
		return
	end
	setSpeed(1)
	hint.Text = "Playing."
end)

pauseBtn.MouseButton1Click:Connect(function()
	if not currentTrack then return end
	-- Proper pause: keep armed, speed 0
	setSpeed(0)
	hint.Text = "Paused."
end)

resetBtn.MouseButton1Click:Connect(function()
	clearAnim()
	hint.Text = "Cleared."
end)

-- Slider scrubbing (easy to grab anywhere)
local resumeAfterScrub = false

local function beginScrub(mouseX: number)
	isScrubbing = true
	resumeAfterScrub = (currentSpeed > 0)
	if currentTrack then
		ensureArmed()
		setSpeed(0)
	end
	setTrackTime(alphaFromMouseX(mouseX))
end

local function endScrub()
	isScrubbing = false
	if currentTrack and resumeAfterScrub then
		setSpeed(1)
	end
end

-- Click anywhere on hitbox to jump + start dragging
sliderHit.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		beginScrub(input.Position.X)
	end
end)

sliderHit.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		endScrub()
	end
end)

Services.UserInputService.InputChanged:Connect(function(input)
	if not isScrubbing then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		setTrackTime(alphaFromMouseX(input.Position.X))
	end
end)

Services.UserInputService.InputEnded:Connect(function(input)
	if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and isScrubbing then
		endScrub()
	end
end)

-- Keep UI synced while playing
Services.RunService.RenderStepped:Connect(function()
	if isScrubbing then return end
	if not currentTrack then return end
	local length = currentTrack.Length
	if not length or length <= 0 then return end

	local t = currentTrack.TimePosition
	local alpha = math.clamp(t / length, 0, 1)
	fill.Size = UDim2.fromScale(alpha, 1)
	knob.Position = UDim2.fromScale(alpha, 0.5)
	sliderLabel.Text = ("Time: %.2fs / %.2fs"):format(round2(t), round2(length))
end)

-- Minimize / Restore
local isMinimized = false
local fullSize = main.Size

local function setMinimized(mini: boolean)
	isMinimized = mini
	body.Visible = not mini
	if mini then
		main.Size = UDim2.fromOffset(fullSize.X.Offset, 34)
		minBtn.Text = "+"
	else
		main.Size = fullSize
		minBtn.Text = "—"
	end
end

minBtn.MouseButton1Click:Connect(function()
	setMinimized(not isMinimized)
end)

-- Close
closeBtn.MouseButton1Click:Connect(function()
	clearAnim()
	screen:Destroy()
end)

-- Dragging (top bar)
do
	local dragging = false
	local dragStart
	local startPos

	local function update(input)
		local delta = input.Position - dragStart
		main.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end

	topBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = main.Position

			local conn
			conn = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if conn then conn:Disconnect() end
				end
			end)
		end
	end)

	Services.UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			update(input)
		end
	end)
end

setMinimized(false)
