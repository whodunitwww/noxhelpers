-- AutoParryConfigTool.lua
-- Cerberus AutoParry Config Builder GUI (timeline tracks, hover info, ignore, parry chains)
-- Updated with: Multi-Hit, Counter Attacks, Distance Adjustment, Priority, Enabled, Damage Analysis

-- ==== SERVICES / ENV ==== --
local Players             = game:GetService("Players")
local Workspace           = game:GetService("Workspace")
local HttpService         = game:GetService("HttpService")
local MarketplaceService  = game:GetService("MarketplaceService")
local UserInputService    = game:GetService("UserInputService")

local LocalPlayer         = Players.LocalPlayer

-- Module entry: caller passes GameDir / defaults here
return function(opts)
    opts = opts or {}

    -- [NEW] flag to toggle counter editing in the editor
    -- default: true (show), pass CounterEditEnabled = false to hide
    local counterEditEnabled = (opts.CounterEditEnabled ~= false)

    -- ==== LOAD UI LIB ==== --
    -- Ensure you trust this source or replace with your own UI library loader
    local AutoParryUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/whodunitwww/noxhelpers/refs/heads/main/apUi.lua"))()

    -- ==== CONFIG FILES & DEFAULTS (NOW PARAM-DRIVEN) ==== --

    local GAME_DIR = opts.GameDir or "Cerberus/Universal" -- fallback if not provided

    local AP_CONFIG_FILE        = GAME_DIR .. "/AP_Config.json"
    local AP_CONFIG_EXTRA_FILE  = GAME_DIR .. "/AP_Config_Extra.json"
    local AP_ANIM_LOG_FILE      = GAME_DIR .. "/AP_AnimLog.json"
    local AP_ALL_ANIMS_FILE     = GAME_DIR .. "/AP_AllAnims.json"
    local AP_IGNORE_FILE        = GAME_DIR .. "/AP_IgnoreAnims.json"

    -- caller can override these; if they pass {}, that is used as-is
    local AP_Config_Default = opts.DefaultConfig or {
        ["17030773401"] = { 
            name = "Zombie Attack", 
            startSec = 0.42, 
            hold = 0.30, 
            rollOnFail = true, 
            repeats = {}, 
            counter = nil,
            priority = "parry",
            enabled = true 
        },
    }

    local AP_ConfigExtra_Default = opts.DefaultExtra or {
        parryKey = "F",
        rollKey  = "Q",
    }

    local AP_Config          = {}
    local AP_ConfigExtra     = {}
    local SeenAnimations     = {}   -- [animId] = { lastSeenTime, count, lastSourceName }
    local IgnoredAnimIds     = {}   -- [animId] = true
    
    -- [NEW] Event History for Damage Calculation
    -- List of { type = "anim"|"damage", time = number, animId = string (optional), label = string }
    local GlobalEventHistory = {} 

    local window             -- forward declare for timeline hook

    local function ensureDir(path)
        local dir = string.match(path, "^(.*)/[^/]+$")
        if dir and makefolder then
            pcall(makefolder, dir)
        end
    end

    local function readJsonFile(path, defaultTbl)
        if not isfile or not isfile(path) then
            return table.clone(defaultTbl)
        end
        local ok, contents = pcall(readfile, path)
        if not ok or type(contents) ~= "string" or contents == "" then
            return table.clone(defaultTbl)
        end
        local ok2, decoded = pcall(function()
            return HttpService:JSONDecode(contents)
        end)
        if not ok2 or type(decoded) ~= "table" then
            return table.clone(defaultTbl)
        end
        return decoded
    end

    local function writeJsonFile(path, tbl)
        if not writefile then return end
        ensureDir(path)
        local ok, data = pcall(function()
            return HttpService:JSONEncode(tbl)
        end)
        if ok then
            pcall(writefile, path, data)
        end
    end

    local function loadConfigs()
        AP_Config      = readJsonFile(AP_CONFIG_FILE,       AP_Config_Default)
        AP_ConfigExtra = readJsonFile(AP_CONFIG_EXTRA_FILE, AP_ConfigExtra_Default)
        IgnoredAnimIds = readJsonFile(AP_IGNORE_FILE,       {})
    end

    local function saveConfigs()
        writeJsonFile(AP_CONFIG_FILE,       AP_Config)
        writeJsonFile(AP_CONFIG_EXTRA_FILE, AP_ConfigExtra)
        writeJsonFile(AP_IGNORE_FILE,       IgnoredAnimIds)
    end

    -- First run: ensure config exists
    if not (isfile and isfile(AP_CONFIG_FILE)) then
        loadConfigs()
        saveConfigs()
    else
        loadConfigs()
    end

    -- ==== ANIMATION DETECTION / HOOKING ==== --

    local listeningEnabled  = true
    local listeningRange    = 40
    local saveAllAnimsFlag  = false

    local ignorePlayersFlag = false
    local ignoreEnemiesFlag = false

    local animConnections   = {}

    local function sqrDist(a, b)
        local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
        return dx*dx + dy*dy + dz*dz
    end

    local function inRangeOfLocal(model)
        if not LocalPlayer or not LocalPlayer.Character then return false end
        local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
        local myrp = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not (hrp and myrp) then return false end
        return sqrDist(hrp.Position, myrp.Position) <= listeningRange * listeningRange
    end

    local function getAnimId(track)
        local raw = track.Animation and track.Animation.AnimationId or ""
        local id = tostring(raw):match("%d+")
        return id
    end

    local AnimNameCache = {}
    local function resolveAnimName(animId, track)
        animId = tostring(animId or "")

        -- 1) cache
        local cached = AnimNameCache[animId]
        if cached and cached ~= "" then
            return cached
        end

        local name

        -- 2) track / Animation instance (if dev named it)
        if track then
            local animObj = track.Animation
            if animObj and animObj.Name and animObj.Name ~= "" and animObj.Name ~= "Animation" then
                name = animObj.Name
            elseif track.Name
                and track.Name ~= ""
                and track.Name ~= "Animation"
                and track.Name ~= "AnimationTrack"
            then
                name = track.Name
            end
        end

        -- 3) config name
        if not name and AP_Config[animId] and AP_Config[animId].name and AP_Config[animId].name ~= "" then
            name = AP_Config[animId].name
        end

        -- 4) Roblox catalog name (what you see on the website)
        if not name then
            local numId = tonumber(animId)
            if numId then
                local ok, info = pcall(function()
                    return MarketplaceService:GetProductInfo(numId, Enum.InfoType.Asset)
                end)
                if ok and info and type(info) == "table" and info.Name and info.Name ~= "" then
                    name = info.Name
                end
            end
        end

        -- 5) fallback
        if not name or name == "" then
            name = "Anim " .. animId
        end

        AnimNameCache[animId] = name
        return name
    end

    local function markSeen(animId, sourceModel, track)
        local now = os.clock()
        local animName = resolveAnimName(animId, track)

        local entry = SeenAnimations[animId]
        if not entry then
            entry = {
                id             = animId,
                count          = 0,
                lastSeenTime   = now,
                lastSourceName = sourceModel and sourceModel.Name or "",
                name           = animName,
            }
            SeenAnimations[animId] = entry
        end

        entry.count          = (entry.count or 0) + 1
        entry.lastSeenTime   = now
        entry.lastSourceName = sourceModel and sourceModel.Name or entry.lastSourceName
        entry.name           = animName

        -- optional: log to file with name
        if saveAllAnimsFlag and writefile then
            local logTbl = {}
            if isfile and isfile(AP_ANIM_LOG_FILE) then
                local ok, data = pcall(readfile, AP_ANIM_LOG_FILE)
                if ok and data and data ~= "" then
                    local ok2, dec = pcall(HttpService.JSONDecode, HttpService, data)
                    if ok2 and type(dec) == "table" then
                        logTbl = dec
                    end
                end
            end
            table.insert(logTbl, {
                id   = animId,
                name = animName,
                src  = sourceModel and sourceModel:GetFullName() or "",
                t    = now,
            })
            writeJsonFile(AP_ANIM_LOG_FILE, logTbl)
        end
    end

    local function hookHumanoid(hum)
        if animConnections[hum] then return end

        local conn
        conn = hum.AnimationPlayed:Connect(function(track)
            if not listeningEnabled then return end

            local model = hum.Parent
            if not model or not model:IsDescendantOf(Workspace) then return end

            -- ignore self always
            if LocalPlayer and model == LocalPlayer.Character then
                return
            end

            local plrFromModel = Players:GetPlayerFromCharacter(model)
            local isPlayerChar = plrFromModel ~= nil

            if isPlayerChar and ignorePlayersFlag then
                return
            end
            if (not isPlayerChar) and ignoreEnemiesFlag then
                return
            end

            if not inRangeOfLocal(model) then return end

            local animId = getAnimId(track)
            if not animId then return end

            -- ignore list
            if IgnoredAnimIds[animId] then
                return
            end

            markSeen(animId, model, track)

            if getgenv().AutoParry_OnAnimationSeen then
                getgenv().AutoParry_OnAnimationSeen(animId, track, model)
            end
        end)

        animConnections[hum] = conn
    end

    local function unhookAllHumanoids()
        for hum, conn in pairs(animConnections) do
            if conn then
                conn:Disconnect()
            end
        end
        animConnections = {}
    end

    local function scanExistingHumanoids()
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if inst:IsA("Humanoid") then
                hookHumanoid(inst)
            end
        end
    end

    Workspace.DescendantAdded:Connect(function(d)
        if d:IsA("Humanoid") then
            task.delay(0.05, function()
                if d.Parent then
                    hookHumanoid(d)
                end
            end)
        end
    end)

    scanExistingHumanoids()

    -- ==== DAMAGE-TAKEN EVENTS (for timeline & analysis) ==== --

    local lastHealth = nil

    local function hookLocalHumanoid()
        if not LocalPlayer then return end
        local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
        if not hum then return end

        lastHealth = hum.Health

        hum.HealthChanged:Connect(function(hp)
            if lastHealth and hp < lastHealth then
                local delta = lastHealth - hp
                local now = os.clock()
                
                -- Log to global history
                table.insert(GlobalEventHistory, {
                    type = "damage",
                    time = now,
                    label = string.format("-%d HP", delta)
                })

                if window and window._timeline then
                    window._timeline:AddEvent({
                        type       = "damage",
                        label      = string.format("-%d HP", delta),
                        info       = string.format("HP: %.0f", hp),
                        sourceName = "Self",
                        time       = now,
                    })
                end
            end
            lastHealth = hp
        end)
    end

    if LocalPlayer then
        LocalPlayer.CharacterAdded:Connect(function()
            task.delay(0.1, hookLocalHumanoid)
        end)
        hookLocalHumanoid()
    end

    -- ==== DAMAGE ANALYSIS HELPER (FIXED) ==== --
    local function getClosestDamageDelta(targetAnimId)
        local animTimes = {}
        local damageTimes = {}
        
        -- Filter history
        for _, ev in ipairs(GlobalEventHistory) do
            if ev.type == "anim" and ev.animId == tostring(targetAnimId) then
                table.insert(animTimes, ev.time)
            elseif ev.type == "damage" then
                table.insert(damageTimes, ev.time)
            end
        end

        if #animTimes == 0 or #damageTimes == 0 then return nil end

        local bestDelta = nil
        local minDiff = math.huge

        for _, tA in ipairs(animTimes) do
            for _, tD in ipairs(damageTimes) do
                local diff = tD - tA 
                
                -- FIX: We only want SUBSEQUENT damage (diff >= 0)
                -- We accept a tiny negative buffer (-0.05) just in case of tick misalignment
                if diff > -0.05 and diff < 2.0 then 
                    -- We also ignore damage that happened 2+ seconds later (irrelevant)
                    if diff < minDiff then
                        minDiff = diff
                        bestDelta = diff
                    end
                end
            end
        end

        return bestDelta
    end

    -- ==== BUILD GUI ==== --
    window = AutoParryUI.CreateWindow({
        Title        = "AutoParry Config Builder",
        Size         = Vector2.new(900, 520),
        IconImageId  = "rbxassetid://136497541793809", 
    })

    --------------------------------------------------------
    -- TAB 1: Timeline / Event Stream
    --------------------------------------------------------
    local tabTimeline = window:AddTab("Timeline")

    local timelineControlsSection = tabTimeline:AddSection("Controls")
    timelineControlsSection:AddLabel("Live timeline of animations / parries / damage in range.", 28)

    local timelineZoomSlider = tabTimeline:AddSlider("Time Span (seconds)", 5, 60, 10, function(v)
        if window._timeline then
            window._timeline:SetSpan(v)
        end
    end)

    local timelinePauseToggle = tabTimeline:AddToggle("Pause timeline", false, function(v)
        if window._timeline then
            window._timeline:SetPaused(v)
        end
    end)

    -- filters (apply immediately, even when paused)
    tabTimeline:AddToggle("Show Animations", true, function(v)
        if window._timeline then window._timeline:SetFilter("anim", v) end
    end)
    tabTimeline:AddToggle("Show Config Hits", true, function(v)
        if window._timeline then window._timeline:SetFilter("config", v) end
    end)
    tabTimeline:AddToggle("Show Parries", true, function(v)
        if window._timeline then window._timeline:SetFilter("parry", v) end
    end)
    tabTimeline:AddToggle("Show Schedules", true, function(v)
        if window._timeline then window._timeline:SetFilter("schedule", v) end
    end)
    tabTimeline:AddToggle("Show Damage Taken", true, function(v)
        if window._timeline then window._timeline:SetFilter("damage", v) end
    end)

    -- timeline control
    local timeline = tabTimeline:AddTimeline(220)
    window._timeline = timeline
    timeline:SetSpan(10)

    -- Hide ignored animations from the timeline (past and future)
    if timeline.SetIgnorePredicate then
        timeline:SetIgnorePredicate(function(ev)
            local id = ev.animId
            return id and IgnoredAnimIds[id] == true
        end)
    end

    -- ==== POPUP UI ==== --
    local popupGui = Instance.new("ScreenGui")
    popupGui.Name = "AP_PopupGui"
    popupGui.ResetOnSpawn = false
    popupGui.IgnoreGuiInset = true
    popupGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    local baseOrder = window._gui.DisplayOrder or 100
    popupGui.DisplayOrder = baseOrder + 1
    popupGui.Parent = window._gui.Parent or game:GetService("CoreGui")
    local g = (getgenv and getgenv()) or {}
    if typeof(g.protectgui) == "function" then
        pcall(g.protectgui, popupGui)
    end

    local popupShade = Instance.new("TextButton")
    popupShade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    popupShade.BackgroundTransparency = 0.4
    popupShade.BorderSizePixel = 0
    popupShade.Size = UDim2.new(1, 0, 1, 0)
    popupShade.Text = ""
    popupShade.Visible = false
    popupShade.ZIndex = 500000
    popupShade.Parent = popupGui

    local popupFrame = Instance.new("Frame")
    popupFrame.Size = UDim2.fromOffset(450, 480) -- Increased size to fit new fields
    popupFrame.Position = UDim2.new(0.5, -225, 0.5, -240)
    popupFrame.BackgroundColor3 = Color3.fromRGB(18, 22, 22)
    popupFrame.BorderColor3 = Color3.fromRGB(60, 80, 80)
    popupFrame.Visible = false
    popupFrame.ZIndex = 500001
    popupFrame.Parent = popupShade

    local popupCorner = Instance.new("UICorner")
    popupCorner.CornerRadius = UDim.new(0, 8)
    popupCorner.Parent = popupFrame

    local popupTitle = Instance.new("TextLabel")
    popupTitle.BackgroundTransparency = 1
    popupTitle.Size = UDim2.new(1, -10, 0, 22)
    popupTitle.Position = UDim2.fromOffset(6, 4)
    popupTitle.Text = "Animation"
    popupTitle.Font = Enum.Font.Code
    popupTitle.TextSize = 16
    popupTitle.TextXAlignment = Enum.TextXAlignment.Left
    popupTitle.TextColor3 = Color3.fromRGB(230, 240, 235)
    popupTitle.ZIndex = 500002
    popupTitle.Parent = popupFrame

    local popupBody = Instance.new("ScrollingFrame")
    popupBody.BackgroundTransparency = 1
    popupBody.Size = UDim2.new(1, -12, 1, -30)
    popupBody.Position = UDim2.fromOffset(6, 26)
    popupBody.CanvasSize = UDim2.new(0, 0, 0, 0)
    popupBody.AutomaticCanvasSize = Enum.AutomaticSize.Y
    popupBody.ScrollBarThickness = 4
    popupBody.ZIndex = 500002 -- ABOVE popupFrame (500001)
    popupBody.Parent = popupFrame

    local popupLayout = Instance.new("UIListLayout")
    popupLayout.FillDirection = Enum.FillDirection.Vertical
    popupLayout.SortOrder = Enum.SortOrder.LayoutOrder
    popupLayout.Padding = UDim.new(0, 4)
    popupLayout.Parent = popupBody

    local function clearPopupBody()
        for _, c in ipairs(popupBody:GetChildren()) do
            if c:IsA("GuiObject") then
                c:Destroy()
            end
        end
    end

    local function popupLabel(text, height, color)
        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(1, 0, 0, height or 18)
        lbl.Text = text
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 14
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextColor3 = color or Color3.fromRGB(200, 210, 210)
        lbl.ZIndex = 500003
        lbl.Parent = popupBody
        return lbl
    end

    local function popupInputRow(labelText, defaultText, callback)
        popupLabel(labelText)
        local box = Instance.new("TextBox")
        box.BackgroundColor3 = Color3.fromRGB(26, 30, 30)
        box.BorderColor3 = Color3.fromRGB(70, 90, 90)
        box.Size = UDim2.new(1, 0, 0, 22)
        box.Text = defaultText or ""
        box.Font = Enum.Font.Code
        box.TextSize = 14
        box.TextXAlignment = Enum.TextXAlignment.Left
        box.TextColor3 = Color3.fromRGB(230, 240, 235)
        box.ZIndex = 500003
        box.Parent = popupBody

        box.FocusLost:Connect(function(enter)
            if enter and callback then
                callback(box.Text)
            end
        end)

        return box
    end

    local function popupButton(text, callback)
        local btn = Instance.new("TextButton")
        btn.BackgroundColor3 = Color3.fromRGB(30, 38, 38)
        btn.BorderColor3 = Color3.fromRGB(70, 90, 90)
        btn.Size = UDim2.new(1, 0, 0, 24)
        btn.Text = text
        btn.Font = Enum.Font.Code
        btn.TextSize = 14
        btn.TextColor3 = Color3.fromRGB(230, 240, 235)
        btn.ZIndex = 500003
        btn.Parent = popupBody
        btn.MouseButton1Click:Connect(function()
            if callback then callback() end
        end)
        return btn
    end

    local function popupBoolToggle(labelText, currentValue, callback)
        popupLabel(labelText)
        local btn = Instance.new("TextButton")
        btn.BackgroundColor3 = currentValue and Color3.fromRGB(40, 80, 50) or Color3.fromRGB(80, 40, 40)
        btn.BorderColor3 = Color3.fromRGB(70, 90, 90)
        btn.Size = UDim2.new(1, 0, 0, 22)
        btn.Text = tostring(currentValue)
        btn.Font = Enum.Font.Code
        btn.TextSize = 14
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.ZIndex = 500003
        btn.Parent = popupBody
        btn.MouseButton1Click:Connect(function()
            local newVal = not currentValue
            currentValue = newVal
            btn.Text = tostring(newVal)
            btn.BackgroundColor3 = newVal and Color3.fromRGB(40, 80, 50) or Color3.fromRGB(80, 40, 40)
            if callback then callback(newVal) end
        end)
    end

    popupShade.MouseButton1Click:Connect(function()
        -- Only close when clicking outside the popup frame
        local mousePos = UserInputService:GetMouseLocation()
        local framePos, frameSize = popupFrame.AbsolutePosition, popupFrame.AbsoluteSize
        local inside =
            mousePos.X >= framePos.X and mousePos.X <= framePos.X + frameSize.X and
            mousePos.Y >= framePos.Y and mousePos.Y <= framePos.Y + frameSize.Y

        if inside then
            return
        end

        popupShade.Visible = false
        popupFrame.Visible = false

        if window and window._timeline and window._timeline.HideTooltip then
            window._timeline:HideTooltip()
        end
    end)

    popupFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            -- swallow clicks
        end
    end)

    -- forward declarations (defined later, but used in popup callbacks)
    local refreshLiveList
    local refreshConfigList

    local function openAnimPopup(animId, animNameOverride)
        clearPopupBody()

        local cfg   = AP_Config[animId]
        local seen  = SeenAnimations[animId]
        local name  = animNameOverride
                    or (cfg and cfg.name)
                    or (seen and seen.name)
                    or resolveAnimName(animId)  -- final fallback

        local displayName = name or ("Anim " .. tostring(animId))
        local isIgnored   = IgnoredAnimIds[animId] == true

        popupTitle.Text = displayName
        popupLabel("Anim ID: " .. tostring(animId))

        -- ==== COPY ID BUTTON ==== --
        local copyBtn
        copyBtn = popupButton("Copy Animation ID", function()
            local idStr = tostring(animId)
            local done = false
            if setclipboard then
                setclipboard(idStr)
                done = true
            elseif toclipboard then
                toclipboard(idStr)
                done = true
            end
            
            if done and copyBtn then
                local oldText = copyBtn.Text
                copyBtn.Text = "Copied!"
                task.delay(0.7, function()
                    if copyBtn and copyBtn.Parent then
                        copyBtn.Text = oldText
                    end
                end)
            end
        end)

        -- ==== DAMAGE ANALYZER ==== --
        local damageDelta = getClosestDamageDelta(animId)
        if damageDelta then
            local ms = damageDelta * 1000
            local sign = (ms > 0) and "+" or ""
            local color = (math.abs(ms) < 500) and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(150, 150, 200)
            popupLabel("CLOSEST DAMAGE: " .. sign .. string.format("%.0f ms", ms), 20, color)
        else
            popupLabel("CLOSEST DAMAGE: No damage recorded near this anim.", 18, Color3.fromRGB(100, 100, 100))
        end
        -- ========================= --

        if seen then
            popupLabel(string.format(
                "Seen: %d times, last source: %s",
                seen.count or 0,
                seen.lastSourceName or "?"
            ))
        else
            popupLabel("Seen: (no data yet)")
        end

        popupLabel(isIgnored and "Status: IGNORED (will not be tracked)" or "Status: active")

        if not cfg then
            popupLabel("This animation is not in the config yet.", 18)
            popupButton("Add to config (with defaults)", function()
                AP_Config[animId] = {
                    name       = displayName,
                    startSec   = tonumber(AP_ConfigExtra.defaultStartSec)   or 0.00,
                    hold       = tonumber(AP_ConfigExtra.defaultHoldSec)    or 0.35,
                    rollOnFail = (AP_ConfigExtra.defaultRollOnFail == true),
                    repeats    = {},
                    counter    = nil,
                    priority   = "parry",
                    enabled    = true
                }
                saveConfigs()
                if refreshLiveList then refreshLiveList() end
                if refreshConfigList then refreshConfigList() end
                if window._timeline then window._timeline:Redraw() end
                -- reopen to reflect new state
                openAnimPopup(animId, displayName)
            end)
        else
            popupLabel("Config entry (live edit):", 18)

            -- Enabled Toggle
            popupBoolToggle("Enabled", (cfg.enabled ~= false), function(val)
                cfg.enabled = val
                saveConfigs()
            end)

            popupInputRow("Name", cfg.name or displayName, function(text)
                cfg.name = (text ~= "" and text) or displayName
                saveConfigs()
                if refreshConfigList then refreshConfigList() end
            end)

            popupInputRow("Start (seconds)", tostring(cfg.startSec or 0), function(text)
                local v = tonumber(text)
                if v then
                    cfg.startSec = v
                    saveConfigs()
                end
            end)
            
            -- Priority
            popupInputRow("Priority (parry / roll)", tostring(cfg.priority or "parry"), function(text)
                cfg.priority = text:lower()
                saveConfigs()
            end)

            -- Distance Adjustment
            popupInputRow("Distance Adj. (sec/100 studs)", tostring(cfg.distanceAdj or 0), function(text)
                local v = tonumber(text)
                if v then
                    cfg.distanceAdj = v
                    saveConfigs()
                end
            end)

            popupInputRow("Hold (seconds)", tostring(cfg.hold or 0.35), function(text)
                local v = tonumber(text)
                if v then
                    cfg.hold = v
                    saveConfigs()
                end
            end)

            -- Repeats
            local repStr = table.concat(cfg.repeats or {}, ", ")
            popupInputRow("Repeat Timings (e.g. 0.2, 0.5)", repStr, function(text)
                local newReps = {}
                for s in string.gmatch(text, "[^,]+") do
                    local n = tonumber(s)
                    if n then table.insert(newReps, n) end
                end
                cfg.repeats = newReps
                saveConfigs()
            end)

            -- Counter Attacks (conditionally visible)
            if counterEditEnabled then
                popupLabel("--- Counter Attack ---", 18)
                local cType  = (cfg.counter and cfg.counter.type) or ""
                local cDelay = (cfg.counter and cfg.counter.delay) or 0.4
                
                popupInputRow("Counter Type (e.g. M2, Z) - Empty to disable", cType, function(text)
                    if text == "" then
                        cfg.counter = nil
                    else
                        if not cfg.counter then cfg.counter = { delay = cDelay } end
                        cfg.counter.type = text
                    end
                    saveConfigs()
                end)
                
                popupInputRow("Counter Delay (seconds)", tostring(cDelay), function(text)
                    local v = tonumber(text)
                    if v then 
                        if cfg.counter then cfg.counter.delay = v end
                        cDelay = v 
                        saveConfigs() 
                    end
                end)
            end

            -- Roll On Fail
            popupBoolToggle("Roll on fail", (cfg.rollOnFail == true), function(val)
                cfg.rollOnFail = val
                saveConfigs()
            end)

            popupButton("Remove from config", function()
                AP_Config[animId] = nil
                saveConfigs()
                if refreshLiveList then refreshLiveList() end
                if refreshConfigList then refreshConfigList() end
                if window._timeline then window._timeline:Redraw() end
                popupShade.Visible = false
                popupFrame.Visible = false
            end)
        end

        -- ignore / unignore control
        popupButton(isIgnored and "Unignore this animation" or "Ignore this animation", function()
            if IgnoredAnimIds[animId] then
                IgnoredAnimIds[animId] = nil
            else
                IgnoredAnimIds[animId] = true
            end
            saveConfigs()
            if refreshLiveList then refreshLiveList() end
            if refreshConfigList then refreshConfigList() end
            if window and window._timeline then
                window._timeline:Redraw()
            end
            popupShade.Visible = false
            popupFrame.Visible = false
        end)

        popupShade.Visible = true
        popupFrame.Visible = true
    end

    timeline.OnEventClicked = function(ev)
        if window and window._timeline and window._timeline.HideTooltip then
            window._timeline:HideTooltip()
        end
        if ev.animId then
            openAnimPopup(ev.animId, ev.animName)
        end
    end

    --------------------------------------------------------
    -- TAB 2: Live Animations List
    --------------------------------------------------------
    local tabLiveList = window:AddTab("Live Anims")

    local liveControlsSection = tabLiveList:AddSection("Listening")
    liveControlsSection:AddLabel(
        "Listens for animations around you and lets you add/edit config entries quickly.",
        30
    )

    local listeningToggle = tabLiveList:AddToggle("Listening", true, function(v)
        listeningEnabled = v
    end)

    local listeningRangeSlider = tabLiveList:AddSlider("Listening Range (studs)", 5, 100, listeningRange, function(v)
        listeningRange = v
    end)

    -- new ignore options
    local ignorePlayersToggle = tabLiveList:AddToggle("Ignore player animations", false, function(v)
        ignorePlayersFlag = v
    end)
    local ignoreEnemiesToggle = tabLiveList:AddToggle("Ignore enemy/NPC animations", false, function(v)
        ignoreEnemiesFlag = v
    end)

    local liveList = tabLiveList:AddList(260)

    function refreshLiveList()
        liveList:Clear()
        local entries = {}
        for animId, data in pairs(SeenAnimations) do
            table.insert(entries, {
                id       = animId,
                lastTime = data.lastSeenTime or 0,
                count    = data.count or 0,
                name     = data.name,
            })
        end
        table.sort(entries, function(a, b)
            return a.lastTime > b.lastTime
        end)

        for _, e in ipairs(entries) do
            local inCfg    = AP_Config[e.id] ~= nil
            local niceName = e.name or (AP_Config[e.id] and AP_Config[e.id].name) or ("Anim " .. e.id)

            local label = string.format(
                "[%s] %s  | ID %s  | seen %d",
                inCfg and "CFG" or "NEW",
                niceName,
                e.id,
                e.count
            )
            liveList:AddItem(label, function()
                openAnimPopup(e.id, niceName)
            end)
        end
    end

    --------------------------------------------------------
    -- TAB 3: Config Animations List
    --------------------------------------------------------
    local tabConfigList = window:AddTab("Config Anims")

    local configControlsSection = tabConfigList:AddSection("Config View")
    configControlsSection:AddLabel("Animations loaded from AP_Config.json. Click to edit them.", 30)

    local orderMode    = "numeric" -- numeric, alpha, recent
    local orderButtons = {}
    local configList   -- will be created AFTER the buttons so it renders at the bottom

    local function refreshConfigListInner()
        if not configList then return end

        configList:Clear()
        local entries = {}
        for animId, cfg in pairs(AP_Config) do
            table.insert(entries, {
                id       = animId,
                name     = cfg.name or ("Anim " .. animId),
                lastSeen = (SeenAnimations[animId] and SeenAnimations[animId].lastSeenTime) or 0,
            })
        end

        if orderMode == "numeric" then
            table.sort(entries, function(a,b)
                return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
            end)
        elseif orderMode == "alpha" then
            table.sort(entries, function(a,b)
                return tostring(a.name):lower() < tostring(b.name):lower()
            end)
        elseif orderMode == "recent" then
            table.sort(entries, function(a,b)
                return a.lastSeen > b.lastSeen
            end)
        end

        for _, e in ipairs(entries) do
            local label = string.format("%s  |  ID: %s", e.name, e.id)
            configList:AddItem(label, function()
                openAnimPopup(e.id)
            end)
        end
    end

    function refreshConfigList()
        refreshConfigListInner()
    end

    local function updateSortButtons()
        for mode, btn in pairs(orderButtons) do
            if btn and btn:IsA("TextButton") then
                if mode == orderMode then
                    -- ACTIVE: bright accent + white text
                    btn.BackgroundColor3 = Color3.fromRGB(0, 180, 120)
                    btn.TextColor3       = Color3.fromRGB(255, 255, 255)
                    btn.TextStrokeTransparency = 0.75
                else
                    -- INACTIVE: darker panel + soft text
                    btn.BackgroundColor3 = Color3.fromRGB(18, 24, 24)
                    btn.TextColor3       = Color3.fromRGB(200, 210, 220)
                    btn.TextStrokeTransparency = 1
                end
            end
        end
    end

    -- SORTING BUTTONS (TOP OF TAB)
    orderButtons.numeric = tabConfigList:AddButton("Sort: Numeric (by ID)", function()
        orderMode = "numeric"
        updateSortButtons()
        refreshConfigListInner()
    end)

    orderButtons.alpha = tabConfigList:AddButton("Sort: Alphabetical (by name)", function()
        orderMode = "alpha"
        updateSortButtons()
        refreshConfigListInner()
    end)

    orderButtons.recent = tabConfigList:AddButton("Sort: Most recently detected", function()
        orderMode = "recent"
        updateSortButtons()
        refreshConfigListInner()
    end)

    updateSortButtons()
    configList = tabConfigList:AddList(260)

    --------------------------------------------------------
    -- TAB 4: Utilities
    --------------------------------------------------------
    local tabUtils = window:AddTab("Utilities")

    local utilSection = tabUtils:AddSection("Utilities")
    utilSection:AddLabel("Misc tools to help build configs and debug AutoParry.", 32)

    local saveAllToggle = tabUtils:AddToggle("Save all animations to log file", false, function(v)
        saveAllAnimsFlag = v
    end)

    tabUtils:AddButton("Scan all humanoids again (re-hook)", function()
        unhookAllHumanoids()
        scanExistingHumanoids()
    end)

    tabUtils:AddButton("Write full animation snapshot to file", function()
        local dump = {}
        for animId, data in pairs(SeenAnimations) do
            table.insert(dump, {
                id = animId,
                count = data.count,
                lastSeenTime = data.lastSeenTime,
                lastSourceName = data.lastSourceName,
                inConfig = AP_Config[animId] ~= nil,
                ignored = IgnoredAnimIds[animId] == true,
            })
        end
        writeJsonFile(AP_ALL_ANIMS_FILE, dump)
    end)

    tabUtils:AddButton("Refresh configs from disk", function()
        loadConfigs()
        refreshConfigListInner()
    end)

    tabUtils:AddButton("Force-save configs to disk", function()
        saveConfigs()
    end)

    tabUtils:AddButton("Reload timeline + lists now", function()
        if window._timeline then
            window._timeline:Redraw()
        end
        refreshLiveList()
        refreshConfigListInner()
    end)

    -- NEW: clear ignore list
    tabUtils:AddButton("Clear ignore list", function()
        IgnoredAnimIds = {}
        saveConfigs()
    end)

    -- NEW: controls for default config settings used by "Add to config"
    local defaultsSection = tabUtils:AddSection("Default Config Add Settings")
    defaultsSection:AddLabel("Defaults used when you click 'Add to config'.", 32)

    tabUtils:AddSlider(
        "Default start (ms)", 0, 2000,
        math.floor((AP_ConfigExtra.defaultStartSec or 0) * 1000 + 0.5),
        function(v)
            AP_ConfigExtra.defaultStartSec = (v or 0) / 1000
            saveConfigs()
        end
    )

    tabUtils:AddSlider(
        "Default hold (ms)", 0, 2000,
        math.floor((AP_ConfigExtra.defaultHoldSec or 0.35) * 1000 + 0.5),
        function(v)
            AP_ConfigExtra.defaultHoldSec = (v or 0) / 1000
            saveConfigs()
        end
    )

    tabUtils:AddToggle("Default roll on fail", AP_ConfigExtra.defaultRollOnFail == true, function(v)
        AP_ConfigExtra.defaultRollOnFail = v and true or false
        saveConfigs()
    end)


    --------------------------------------------------------
    -- WIRE AUTOPARRY EVENTS INTO TIMELINE
    --------------------------------------------------------

    -- Anim seen – called from our hookHumanoid
    getgenv().AutoParry_OnAnimationSeen = function(animId, track, model)
        if IgnoredAnimIds[animId] then
            return
        end

        local inCfg    = AP_Config[animId] ~= nil
        local animName = resolveAnimName(animId, track)

        -- Log to global history for analysis
        table.insert(GlobalEventHistory, {
            type = "anim",
            time = os.clock(),
            animId = animId,
            label = animName
        })

        if window and window._timeline then
            window._timeline:AddEvent({
                type       = inCfg and "config" or "anim",
                label      = animName,            -- used for tooltip + hover text
                animId     = animId,
                animName   = animName,
                sourceName = model and model.Name or "",
                inConfig   = inCfg,
                time       = os.clock(),
            })
        end

        refreshLiveList()
        refreshConfigListInner()
    end

    -- These are called from your main AutoParry script:

    getgenv().AutoParry_OnParryScheduled = function(animId, cfg, srcName, pressDelay, scheduledAt)
        local animName = (cfg and cfg.name) or ("Anim " .. tostring(animId))
        local t = scheduledAt or os.clock()   -- fall back just in case

        if window and window._timeline then
            window._timeline:AddEvent({
                type       = "schedule",
                label      = animName,
                animId     = animId,
                animName   = animName,
                sourceName = srcName or "",
                info       = string.format("press in %.1f ms", (pressDelay or 0) * 1000),
                time       = t,
            })
        end
    end

    getgenv().AutoParry_OnParryFired = function(animId, cfg, srcName, chainId)
        local animName = (cfg and cfg.name) or ("Anim " .. tostring(animId))
        if window and window._timeline then
            window._timeline:AddEvent({
                type       = "parry",
                label      = animName,
                animId     = animId,
                animName   = animName,
                sourceName = srcName or "",
                chainId    = chainId,
                time       = os.clock(),
            })
        end
    end

    getgenv().AutoParry_OnParryFailRoll = function(animId, cfg, srcName, chainId)
        local animName = (cfg and cfg.name) or ("Anim " .. tostring(animId))
        if window and window._timeline then
            window._timeline:AddEvent({
                type       = "parry",
                label      = animName,
                animId     = animId,
                animName   = animName,
                sourceName = (srcName or "") .. " (fail → roll)",
                chainId    = chainId,
                time       = os.clock(),
            })
        end
    end

    -- initial draws
    refreshLiveList()
    refreshConfigListInner()
    if window._timeline then
        window._timeline:Redraw()
    end

    -- (optional) return window / config API if you want to hook it later
    return {
        Window        = window,
        GetConfig     = function() return AP_Config end,
        GetConfigExtra= function() return AP_ConfigExtra end,
        GameDir       = GAME_DIR,
    }
end
