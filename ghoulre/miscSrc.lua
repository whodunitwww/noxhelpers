return function(ctx)
    local Services = ctx.Services
    local Tabs = ctx.Tabs
    local References = ctx.References
    local Library = ctx.Library
    local Options = ctx.Options
    local Toggles = ctx.Toggles
    local LPH_NO_VIRTUALIZE = ctx.LPH_NO_VIRTUALIZE or function(f)
        return f
    end

    local M = {}

    local function SmartServerHop(filter, maxPlayersLimit, maxPingLimit, placeId, maxPages)
        local request = (syn and syn.request) or http_request or request or (fluxus and fluxus.request) or
                            (krnl and krnl.request)

        if not request then
            return false, "No HTTP request function available"
        end

        placeId = tonumber(placeId) or game.PlaceId
        maxPages = maxPages or 2
        local currentJob = game.JobId

        local function fetchPage(cursor)
            local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(placeId)
            if cursor and cursor ~= "" then
                url = url .. "&cursor=" .. Services.HttpService:UrlEncode(cursor)
            end

            local res = request({
                Url = url,
                Method = "GET",
                Headers = {
                    ["Content-Type"] = "application/json"
                }
            })

            if not res or not res.Success then
                return false, (res and res.StatusMessage) or "HTTP error"
            end

            local ok, decoded = pcall(Services.HttpService.JSONDecode, Services.HttpService, res.Body)
            if not ok then
                return false, "JSON decode failed"
            end

            return true, decoded
        end

        local candidates = {}
        local cursor = nil
        local pages = 0

        while pages < maxPages do
            local ok, dataOrErr = fetchPage(cursor)
            if not ok then
                return false, dataOrErr
            end

            local data = dataOrErr
            if type(data.data) ~= "table" then
                break
            end

            for _, srv in ipairs(data.data) do
                local jobId = srv.id
                local playing = srv.playing or 0
                local maxPlayers = srv.maxPlayers or 0
                local ping = srv.ping or srv.playerPing

                if jobId ~= currentJob then
                    local hasSpace = (playing < maxPlayers)

                    local okPlayers = true
                    if maxPlayersLimit then
                        okPlayers = (playing <= maxPlayersLimit)
                    end

                    local okPing = true
                    if maxPingLimit then
                        if ping == nil then
                            okPing = false
                        else
                            okPing = (ping <= maxPingLimit)
                        end
                    end

                    if hasSpace and okPlayers and okPing then
                        table.insert(candidates, {
                            jobId = jobId,
                            players = playing,
                            maxPlayers = maxPlayers,
                            ping = ping or math.huge,
                            raw = srv
                        })
                    end
                end
            end

            cursor = data.nextPageCursor
            pages = pages + 1
            if not cursor or cursor == "" then
                break
            end
        end

        if #candidates == 0 then
            return false, "No suitable servers found"
        end

        if filter == "lowest_player" then
            table.sort(candidates, function(a, b)
                if a.players == b.players then
                    return a.ping < b.ping
                end
                return a.players < b.players
            end)
        elseif filter == "lowest_ping" then
            table.sort(candidates, function(a, b)
                if a.ping == b.ping then
                    return a.players < b.players
                end
                return a.ping < b.ping
            end)
        elseif filter == "random" then
            math.randomseed(os.time() + #candidates)
            local idx = math.random(1, #candidates)
            local chosen = candidates[idx]
            local ok, err = pcall(function()
                Services.TeleportService:TeleportToPlaceInstance(placeId, chosen.jobId, References.player)
            end)
            if not ok then
                return false, "Teleport failed: " .. tostring(err)
            end
            return true, "Teleporting to random server"
        else
            table.sort(candidates, function(a, b)
                if a.ping == b.ping then
                    return a.players < b.players
                end
                return a.ping < b.ping
            end)
        end

        local chosen = candidates[1]
        local ok, err = pcall(function()
            Services.TeleportService:TeleportToPlaceInstance(placeId, chosen.jobId, References.player)
        end)
        if not ok then
            return false, "Teleport failed: " .. tostring(err)
        end

        return true, "Teleporting to server " .. tostring(chosen.jobId)
    end

    local ServerGroup = Tabs.Misc:AddLeftGroupbox("Server Panel", "server")

    ServerGroup:AddSlider("SERVER_MaxPlayers", {
        Text = "Max Player Count",
        Min = 1,
        Max = 50,
        Default = 20,
        Rounding = 0
    })

    ServerGroup:AddSlider("SERVER_MaxPing", {
        Text = "Max Ping (ms)",
        Min = 1,
        Max = 1000,
        Default = 200,
        Rounding = 0
    })

    local filterValues = {"Lowest Players", "Lowest Ping", "Random"}

    ServerGroup:AddDropdown("SERVER_Filter", {
        Text = "Filter",
        Values = filterValues,
        Default = "Lowest Ping",
        Multi = false
    })

    local function getFilterKey()
        local v = Options.SERVER_Filter and Options.SERVER_Filter.Value or "Lowest Ping"
        if v == "Lowest Players" then
            return "lowest_player"
        elseif v == "Random" then
            return "random"
        else
            return "lowest_ping"
        end
    end

    local function doSingleHop()
        local maxPlayers = tonumber(Options.SERVER_MaxPlayers and Options.SERVER_MaxPlayers.Value) or nil
        local maxPing = tonumber(Options.SERVER_MaxPing and Options.SERVER_MaxPing.Value) or nil
        local filterKey = getFilterKey()

        local ok, msg = SmartServerHop(filterKey, maxPlayers, maxPing)
        if not ok then
            Library:Notify("[Server Hop] Failed: " .. tostring(msg), 4)
        else
            Library:Notify("[Server Hop] " .. tostring(msg), 4)
        end
    end

    ServerGroup:AddButton({
        Text = "Server Hop Once",
        Func = function()
            doSingleHop()
        end
    })

    ServerGroup:AddSlider("SERVER_AutoHopInterval", {
        Text = "Auto Hop Interval (s)",
        Min = 1,
        Max = 600,
        Default = 60,
        Rounding = 0,
        Suffix = "s"
    })

    local serverAutoHopRunning = false

    local function stopServerAutoHop()
        serverAutoHopRunning = false
    end

    local function startServerAutoHop()
        if serverAutoHopRunning then
            return
        end
        serverAutoHopRunning = true

        task.spawn(function()
            while serverAutoHopRunning and Toggles.SERVER_AutoHop and Toggles.SERVER_AutoHop.Value do
                -- attempt hop
                local maxPlayers = tonumber(Options.SERVER_MaxPlayers and Options.SERVER_MaxPlayers.Value) or nil
                local maxPing = tonumber(Options.SERVER_MaxPing and Options.SERVER_MaxPing.Value) or nil
                local filterKey = getFilterKey()

                local ok, msg = SmartServerHop(filterKey, maxPlayers, maxPing)
                if not ok then
                    Library:Notify("[Auto Hop] Failed: " .. tostring(msg), 4)
                else
                    Library:Notify("[Auto Hop] " .. tostring(msg), 4)
                end

                -- wait interval, but allow early cancel
                local interval = tonumber(Options.SERVER_AutoHopInterval and Options.SERVER_AutoHopInterval.Value) or 60
                interval = math.clamp(interval, 1, 600)

                local elapsed = 0
                while elapsed < interval do
                    if not serverAutoHopRunning or not (Toggles.SERVER_AutoHop and Toggles.SERVER_AutoHop.Value) then
                        break
                    end
                    task.wait(0.5)
                    elapsed = elapsed + 0.5
                end
            end
        end)
    end

    ServerGroup:AddToggle("SERVER_AutoHop", {
        Text = "Enable Auto Hop",
        Default = false,
        Tooltip = "Automatically hops to a new server every interval using the selected filter."
    }):OnChanged(function(on)
        if on then
            startServerAutoHop()
        else
            stopServerAutoHop()
        end
    end)

    ServerGroup:AddButton({
        Text = "Rejoin Server",
        Func = function()
            Library:Notify("Attempting to rejoin current server...", 3)

            local ok, err = pcall(function()
                Services.TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, References.player)
            end)

            if not ok then
                Library:Notify("[Rejoin] Failed: " .. tostring(err), 4)
            end
        end
    })

    ServerGroup:AddButton({
        Text = "Copy Join Script",
        Func = function()
            setclipboard(
                ([[game:GetService("TeleportService"):TeleportToPlaceInstance(%d, "%s", game:GetService("Players").LocalPlayer)]]):format(
                    game.PlaceId, game.JobId))
            Library:Notify("Join script copied!", 3)
        end
    })
    
-- == PLAYER SPY == --
    local SpyGroup = Tabs.Misc:AddRightGroupbox("Player Spy", "eye")

    local SpyLabels = {}
    local SpyTarget = nil
    
    -- Configuration
    local BasicKeys = { "RC Cells", "Race", "Rank", "Type" } -- "Type" is Weapon
    local ExtraKeys = { "Stance", "Cash" } 

    -- 1. Sorting & Filter Options
    local SortMode = "RC Cells"

    local SpySortDropdown = SpyGroup:AddDropdown("Spy_SortDropdown", {
        Values = { "RC Cells", "Rank" },
        Default = "RC Cells",
        Multi = false,
        Text = "Sort Players By",
    })

    local SpyBasicToggle = SpyGroup:AddToggle("Spy_BasicToggle", {
        Text = "Basic Mode",
        Default = true,
    })

    -- 2. Target Dropdown
    local SpyDropdown = SpyGroup:AddDropdown("Spy_TargetDropdown", {
        Values = {},
        Default = nil,
        Multi = false,
        Text = "Select Player",
    })

    -- 3. Logic Functions
    local function GetEntity(plrName)
        local entities = workspace:FindFirstChild("Entities")
        return entities and entities:FindFirstChild(plrName)
    end

    local function GetStatValue(plrName, statName)
        local entity = GetEntity(plrName)
        if not entity then return -1 end 

        if statName == "RC Cells" then
            return entity:GetAttribute("RCCells") or -1
        elseif statName == "Rank" then
            local rObj = entity:FindFirstChild("Rank")
            return rObj and tostring(rObj.Value) or "ZZZ" 
        end
        return 0
    end

    local function RefreshPlayerList()
        local players = Services.Players:GetPlayers()
        local sortList = {}

        for _, pl in ipairs(players) do
            local val = GetStatValue(pl.Name, SortMode)
            table.insert(sortList, { Name = pl.Name, Value = val })
        end

        table.sort(sortList, function(a, b)
            if SortMode == "RC Cells" then
                return (tonumber(a.Value) or 0) > (tonumber(b.Value) or 0)
            else
                return tostring(a.Value) < tostring(b.Value)
            end
        end)

        local finalNames = {}
        for _, item in ipairs(sortList) do
            table.insert(finalNames, item.Name)
        end
        
        SpyDropdown:SetValues(finalNames)
    end

    SpyGroup:AddButton({
        Text = "Refresh Players",
        Func = RefreshPlayerList
    })

    SpyGroup:AddButton({
        Text = "Show Inventory",
        Func = function()
            if not SpyTarget then 
                Library:Notify({ Title = "Inventory", Description = "No player selected", Time = 3 })
                return 
            end

            local targetPlr = Services.Players:FindFirstChild(SpyTarget)
            if not targetPlr then
                Library:Notify({ Title = "Inventory", Description = "Player left the server", Time = 3 })
                return
            end

            local invList = {}
            if targetPlr.Character then
                local equipped = targetPlr.Character:FindFirstChildOfClass("Tool")
                if equipped then
                    table.insert(invList, "[Equipped] " .. equipped.Name)
                end
            end
            if targetPlr.Backpack then
                for _, tool in ipairs(targetPlr.Backpack:GetChildren()) do
                    if tool:IsA("Tool") then
                        table.insert(invList, tool.Name)
                    end
                end
            end

            local content = #invList > 0 and table.concat(invList, ", ") or "Empty Inventory"
            Library:Notify({
                Title = targetPlr.Name .. "'s Inventory",
                Description = content,
                Time = 8
            })
        end
    })

    SpyGroup:AddDivider()

    -- == UI LABELS == --
    local NameLabel = SpyGroup:AddLabel({ Text = "Name: ...", DoesWrap = true })

    local function CreateSpyLabels(keyList)
        for _, key in ipairs(keyList) do
            local labelName = (key == "Type") and "Weapon" or key
            SpyLabels[key] = SpyGroup:AddLabel({
                Text = labelName .. ": ...",
                DoesWrap = true
            })
        end
    end

    CreateSpyLabels(BasicKeys)
    CreateSpyLabels(ExtraKeys)

    -- Divider for Equipment
    local EquipDivider = SpyGroup:AddDivider()
    local EquipmentHeader = SpyGroup:AddLabel("== Equipment ==")
    local EquipmentLabel = SpyGroup:AddLabel({ Text = "None", DoesWrap = true })

    -- 4. Main Update Logic
    local function UpdateVisibility()
        local isBasic = SpyBasicToggle.Value
        
        -- SAFE Loop for Labels (Checks if 'obj' exists first)
        for _, key in ipairs(ExtraKeys) do
            local obj = SpyLabels[key]
            if obj and obj.SetVisible then
                obj:SetVisible(not isBasic)
            end
        end
        
        -- SAFE Checks for Dividers/Headers
        if EquipDivider and EquipDivider.SetVisible then 
            EquipDivider:SetVisible(not isBasic) 
        end
        if EquipmentHeader and EquipmentHeader.SetVisible then 
            EquipmentHeader:SetVisible(not isBasic) 
        end
        if EquipmentLabel and EquipmentLabel.SetVisible then 
            EquipmentLabel:SetVisible(not isBasic) 
        end
    end

    local function UpdateSpy()
        UpdateVisibility()

        if not SpyTarget then return end

        local entity = GetEntity(SpyTarget)
        
        if entity then
            -- Name
            local fNameObj = entity:FindFirstChild("FirstName")
            local clanObj = entity:FindFirstChild("Clan")
            local fName = fNameObj and tostring(fNameObj.Value) or "???"
            local clan = clanObj and tostring(clanObj.Value) or ""
            NameLabel:SetText("Name: " .. fName .. " " .. clan)

            -- Basic Stats
            for _, key in ipairs(BasicKeys) do
                local label = SpyLabels[key]
                local labelTitle = (key == "Type") and "Weapon" or key
                
                if key == "RC Cells" then
                    local rcVal = entity:GetAttribute("RCCells")
                    if rcVal then
                        label:SetText("RC Cells: " .. math.floor(rcVal + 0.5))
                    else
                        label:SetText("RC Cells: N/A")
                    end
                else
                    local valObj = entity:FindFirstChild(key)
                    label:SetText(labelTitle .. ": " .. (valObj and tostring(valObj.Value) or "N/A"))
                end
            end

            -- Extra Stats
            if not SpyBasicToggle.Value then
                for _, key in ipairs(ExtraKeys) do
                    local label = SpyLabels[key]
                    local valObj = entity:FindFirstChild(key)
                    if label then
                        label:SetText(key .. ": " .. (valObj and tostring(valObj.Value) or "N/A"))
                    end
                end

                local equipFolder = entity:FindFirstChild("Equipment")
                if equipFolder then
                    local equipList = {}
                    for _, slot in ipairs(equipFolder:GetChildren()) do
                        local foundItem = "Empty"
                        for _, item in ipairs(slot:GetChildren()) do
                            foundItem = item.Name; break 
                        end
                        if foundItem ~= "Empty" then
                            table.insert(equipList, "[" .. slot.Name .. "] " .. foundItem)
                        end
                    end
                    EquipmentLabel:SetText(#equipList > 0 and table.concat(equipList, "\n") or "No Equipment")
                else
                    EquipmentLabel:SetText("No Equipment")
                end
            end
        else
            NameLabel:SetText("Name: Entity Not Found")
        end
    end

    -- 5. Connections
    SpyDropdown:OnChanged(function(val)
        SpyTarget = val
        UpdateSpy()
    end)

    SpySortDropdown:OnChanged(function(val)
        SortMode = val
        RefreshPlayerList()
    end)
    
    SpyBasicToggle:OnChanged(function()
        UpdateSpy()
    end)

    task.spawn(function()
        while true do
            if SpyTarget then
                UpdateSpy()
            end
            task.wait(1)
        end
    end)

    RefreshPlayerList()
    UpdateVisibility()

    -- == CONSOLE  == --
    local ConsoleGroup = Tabs.Misc:AddRightGroupbox("Console", "code")

    ConsoleGroup:AddButton({
        Text = "Console",
        Func = function()
            Library:Notify("Launched console.", 3)
            loadstring(game:HttpGet(
                "https://raw.githubusercontent.com/whodunitwww/noxhelpers/refs/heads/main/console.lua"))()
        end
    })

    -- == FPS AND PING HUD  == --
    local HudGroup = Tabs.Misc:AddRightGroupbox("Performance HUD", "gauge")

    local hud = {
        gui = nil,
        conn = nil,
        fpsSmooth = 60,
        scale = 1
    }

    local function uiParent()
        local ok, ui = pcall(function()
            return (rawget(getfenv(), "gethui") and gethui()) or Services.CoreGui or game:GetService("CoreGui")
        end)
        return ok and ui or Services.Players.LocalPlayer:WaitForChild("PlayerGui")
    end

    local function destroyHud()
        if hud.conn then
            hud.conn:Disconnect();
            hud.conn = nil
        end
        if hud.gui then
            hud.gui:Destroy();
            hud.gui = nil
        end
    end

    local function createHud()
        destroyHud()

        local parent = uiParent()
        local sg = Instance.new("ScreenGui")
        sg.Name = "CerberusHUD"
        sg.ResetOnSpawn = false
        sg.IgnoreGuiInset = true
        sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        sg.Parent = parent
        hud.gui = sg

        local holder = Instance.new("Frame")
        holder.Name = "Holder"
        holder.AnchorPoint = Vector2.new(1, 0)
        holder.Position = UDim2.new(1, -20, 0, 20)
        holder.Size = UDim2.fromOffset(320, 100)
        holder.BackgroundColor3 = Color3.fromRGB(29, 30, 36)
        holder.BackgroundTransparency = 0.05
        holder.Active = true
        holder.Parent = sg

        local corner = Instance.new("UICorner", holder)
        corner.CornerRadius = UDim.new(0, 18)

        local stroke = Instance.new("UIStroke", holder)
        stroke.Thickness = 2
        stroke.Transparency = 0.3
        stroke.Color = Color3.fromRGB(92, 94, 104)

        local shadow = Instance.new("ImageLabel")
        shadow.Name = "Shadow"
        shadow.BackgroundTransparency = 1
        shadow.Image = "rbxassetid://5028857084"
        shadow.ImageTransparency = 0.6
        shadow.ScaleType = Enum.ScaleType.Slice
        shadow.SliceCenter = Rect.new(24, 24, 276, 276)
        shadow.Size = UDim2.new(1, 24, 1, 24)
        shadow.Position = UDim2.new(0, -12, 0, -12)
        shadow.ZIndex = 0
        shadow.Parent = holder

        local left = Instance.new("Frame")
        left.Name = "Left"
        left.BackgroundTransparency = 1
        left.Size = UDim2.new(0.65, 0, 1, -20)
        left.Position = UDim2.new(0, 20, 0, 10)
        left.Parent = holder

        local vlist = Instance.new("UIListLayout", left)
        vlist.FillDirection = Enum.FillDirection.Vertical
        vlist.VerticalAlignment = Enum.VerticalAlignment.Center
        vlist.Padding = UDim.new(0, 12)

        local function metric(label)
            local f = Instance.new("Frame")
            f.BackgroundTransparency = 1
            f.Size = UDim2.new(1, 0, 0, 34)

            local t = Instance.new("TextLabel")
            t.Name = "Title"
            t.BackgroundTransparency = 1
            t.Font = Enum.Font.Gotham
            t.Text = label
            t.TextColor3 = Color3.fromRGB(172, 175, 185)
            t.TextSize = 16
            t.TextXAlignment = Enum.TextXAlignment.Left
            t.Size = UDim2.new(0.5, 0, 1, 0)
            t.Parent = f

            local v = Instance.new("TextLabel")
            v.Name = "Value"
            v.BackgroundTransparency = 1
            v.Font = Enum.Font.GothamSemibold
            v.Text = "--"
            v.TextColor3 = Color3.fromRGB(238, 239, 244)
            v.TextSize = 28
            v.TextXAlignment = Enum.TextXAlignment.Left
            v.Position = UDim2.new(0.5, 0, 0, 0)
            v.Size = UDim2.new(0.5, 0, 1, 0)
            v.Parent = f

            return f, v
        end

        local fpsFrame, fpsValue = metric("FPS")
        fpsFrame.Parent = left

        local pingFrame, pingValue = metric("Ping")
        pingFrame.Parent = left

        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.BackgroundTransparency = 1
        icon.AnchorPoint = Vector2.new(1, 0.5)
        icon.Position = UDim2.new(1, -24, 0.5, 0)
        icon.Size = UDim2.fromOffset(56, 56)
        icon.Image = "rbxassetid://136497541793809"
        icon.ImageColor3 = Color3.fromRGB(55, 235, 120)
        icon.Parent = holder

        local dragging, dragStart, startPos
        holder.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                dragging, dragStart, startPos = true, i.Position, holder.Position
                i.Changed:Connect(function()
                    if i.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)
        holder.InputChanged:Connect(function(i)
            if dragging and
                (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                local delta = i.Position - dragStart
                holder.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y)
            end
        end)

        local Stats = game:GetService("Stats")
        local pingItem = Stats and Stats.Network and Stats.Network.ServerStatsItem and
                             Stats.Network.ServerStatsItem["Data Ping"]

        hud.conn = Services.RunService.RenderStepped:Connect(
            LPH_NO_VIRTUALIZE(function(dt)
                local instFPS = (dt > 0) and (1 / dt) or 60
                hud.fpsSmooth = hud.fpsSmooth + (instFPS - hud.fpsSmooth) * 0.2
                fpsValue.Text = string.format("%d", math.clamp(math.floor(hud.fpsSmooth + 0.5), 1, 1000))

                local ms
                if pingItem and pingItem.GetValue then
                    local ok, v = pcall(function()
                        return pingItem:GetValue()
                    end)
                    if ok and type(v) == "number" then
                        ms = math.floor(v + 0.5)
                    end
                end
                if not ms and pingItem and pingItem.GetValueString then
                    local ok, s = pcall(function()
                        return pingItem:GetValueString()
                    end)
                    if ok and type(s) == "string" then
                        ms = tonumber(s:match("(%d+)"))
                    end
                end
                pingValue.Text = ms and (ms .. " ms") or "--"
            end))
    end

    HudGroup:AddToggle("HUD_Enable", {
        Text = "Show FPS + Ping",
        Tooltip = "Can only show up to 60 fps",
        Default = false,
        Callback = function(on)
            if on then
                createHud()
            else
                destroyHud()
            end
        end
    })

    HudGroup:AddSlider("HUD_Scale", {
        Text = "HUD Scale",
        Default = 90,
        Min = 70,
        Max = 150,
        Rounding = 0,
        Suffix = "%",
        Callback = function(v)
            hud.scale = v / 100
            if hud.gui and hud.gui:FindFirstChild("Holder") then
                local holder = hud.gui.Holder
                holder.Size = UDim2.fromOffset(320 * hud.scale, 100 * hud.scale)
                for _, frame in ipairs(holder:GetDescendants()) do
                    if frame:IsA("TextLabel") then
                        if frame.Name == "Title" then
                            frame.TextSize = 16 * hud.scale
                        elseif frame.Name == "Value" then
                            frame.TextSize = 28 * hud.scale
                        end
                    end
                end
            end
        end
    })

    -- == ENVIRONMENT UI == --
    local EnvironmentGroup = Tabs.Misc:AddRightGroupbox("Environment", "trees")

    local ambientOn, ambientColor = false, Color3.fromRGB(128, 128, 128)
    local ambientOrig = Services.Lighting and Services.Lighting.Ambient or Color3.new()
    local timeLocked, timeValue, timeConn = false, (Services.Lighting and Services.Lighting.ClockTime or 12), nil

    local function applyAmbient()
        if Services.Lighting then
            Services.Lighting.Ambient = ambientOn and ambientColor or ambientOrig
        end
    end

    EnvironmentGroup:AddToggle("ENV_Ambient", {
        Text = "Custom Ambient",
        Default = false,
        Tooltip = "Choose your own custom ambient color.",
        Callback = function(v)
            ambientOn = v;
            applyAmbient()
        end
    })
    EnvironmentGroup:AddLabel("Ambient Color"):AddColorPicker("ENV_AmbientColor", {
        Default = ambientColor,
        Title = "Ambient Color",
        Callback = function(c)
            ambientColor = c;
            if ambientOn then
                applyAmbient()
            end
        end
    })

    EnvironmentGroup:AddToggle("ENV_TimeLock", {
        Text = "Custom Time of Day",
        Default = false,
        Callback = function(on)
            timeLocked = on
            if on then
                if Services.Lighting then
                    Services.Lighting.ClockTime = timeValue
                end
                if not timeConn then
                    timeConn = Services.RunService.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
                        if Services.Lighting then
                            Services.Lighting.ClockTime = timeValue
                        end
                    end))
                end
                Library:Notify("Time of Day locked.", 3)
            else
                if timeConn then
                    timeConn:Disconnect();
                    timeConn = nil
                end
                Library:Notify("Time of Day unlocked.", 3)
            end
        end
    })

    EnvironmentGroup:AddSlider("ENV_Time", {
        Text = "Time of Day",
        Default = timeValue,
        Min = 0,
        Max = 24,
        Rounding = 2,
        Suffix = "h",
        Callback = function(v)
            timeValue = v;
            if timeLocked and Services.Lighting then
                Services.Lighting.ClockTime = v
            end
        end
    })

    local function stopEnvironment()
        if timeConn then
            timeConn:Disconnect();
            timeConn = nil
        end
        if Services.Lighting then
            Services.Lighting.Ambient = ambientOrig
        end
    end

    -- == AUTOCHAT == --
    local AutoChatGroup = Tabs.Misc:AddRightGroupbox("Auto Chat", "message-circle")

    local autoChatLoop
    local autoChatRunning = false

    AutoChatGroup:AddToggle("autoChatEnabled", {
        Text = "Auto Chat",
        Default = false,
        Callback = function(enabled)
            autoChatRunning = enabled

            if enabled then
                task.spawn(function()
                    while autoChatRunning do
                        local msg = Options.autoChatMessage.Value
                        local interval = tonumber(Options.autoChatInterval.Value) or 5

                        if msg and msg:match("%S") then
                            local channel = game:GetService("TextChatService").TextChannels:FindFirstChild("RBXGeneral")
                            if channel then
                                pcall(function()
                                    channel:SendAsync(msg)
                                end)
                            end
                        else
                            Library:Notify("Your message can't be empty.", 3)
                            autoChatRunning = false
                            Toggles.autoChatEnabled:SetValue(false)
                            break
                        end

                        task.wait(interval)
                    end
                end)
            else
            end
        end
    })

    AutoChatGroup:AddInput("autoChatMessage", {
        Default = "Hello Everyone!",
        Numeric = false,
        Finished = false,
        ClearTextOnFocus = true,
        Text = "Message",
        Callback = function(Value)
        end
    })

    AutoChatGroup:AddSlider("autoChatInterval", {
        Text = "Chat Interval (s)",
        Default = 10,
        Min = 1,
        Max = 120,
        Rounding = 1,
        Suffix = "s",
        Callback = function(Value)
        end
    })

    -- == STREAMER MODE == --
    local TextChatService = Services.TextChatService
    local CoreGui = Services.CoreGui

    local LOCAL = Services.Players.LocalPlayer

    local Streamer = {
        enabled = false,
        selected = {
            ["Hide Own Name"] = false,
            ["Hide Others Names"] = false,
            ["Hide Own Skin"] = false,
            ["Hide Others Skins"] = false
        },
        _cons = {},
        _chatConn = nil,
        _legacyChatConns = {},
        _uiLoop = nil,
        _uiScrub = nil,
        _nameDDT = {},
        _skin = {},
        _nameCache = {},
        _descAddedConn = nil
    }

    local function alive(inst)
        return typeof(inst) == "Instance" and inst.Parent ~= nil
    end

    local function safeChar(plr)
        local c = plr and plr.Character
        if alive(c) then
            return c
        end
        return nil
    end

    local function safeFindFirstChildOfClass(parent, className)
        if not alive(parent) then
            return nil
        end
        local ok, res = pcall(function()
            return parent:FindFirstChildOfClass(className)
        end)
        if ok and alive(res) then
            return res
        end
        return nil
    end

    local function safeFindFirstChild(parent, name)
        if not alive(parent) then
            return nil
        end
        local ok, res = pcall(function()
            return parent:FindFirstChild(name)
        end)
        if ok and alive(res) then
            return res
        end
        return nil
    end

    local function humanoid(char)
        local h = safeFindFirstChildOfClass(char, "Humanoid")
        if h and h.Health > 0 then
            return h
        end
        return nil
    end

    local function escapePattern(s)
        return (s:gsub("([^%w])", "%%%1"))
    end

    local function setOverheadHidden(plr, hidden)
        local char = safeChar(plr)
        local hum = humanoid(char)
        if not hum then
            return
        end
        local uid = plr.UserId

        if hidden then
            if Streamer._nameDDT[uid] == nil then
                Streamer._nameDDT[uid] = hum.DisplayDistanceType
            end
            hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        else
            hum.DisplayDistanceType = Streamer._nameDDT[uid] or Enum.HumanoidDisplayDistanceType.Viewer
        end
    end

    local function cacheOriginalName(plr)
        if not plr then
            return
        end
        local uid = plr.UserId
        if not Streamer._nameCache[uid] then
            Streamer._nameCache[uid] = {
                Name = plr.Name,
                Display = plr.DisplayName
            }
        end
    end

    local function setPlayerNameQuestion(plr)
        if not plr then
            return
        end
        cacheOriginalName(plr)
        pcall(function()
            plr.Name = "???"
        end)
        pcall(function()
            plr.DisplayName = "???"
        end)
    end

    local function restorePlayerName(plr)
        if not plr then
            return
        end
        local uid = plr.UserId
        local orig = Streamer._nameCache[uid]
        if not orig then
            return
        end
        pcall(function()
            plr.Name = orig.Name
        end)
        pcall(function()
            plr.DisplayName = orig.Display
        end)
    end

    local function buildReplaceMapToQuestion()
        local map = {}
        local hideSelf = Streamer.selected["Hide Own Name"]
        local hideOthers = Streamer.selected["Hide Others Names"]
        if not (hideSelf or hideOthers) then
            return map
        end

        local function add(str)
            if str and str ~= "" then
                map[str] = "???"
            end
        end

        for _, p in ipairs(Services.Players:GetPlayers()) do
            local isMe = (p == LOCAL)
            if (isMe and hideSelf) or ((not isMe) and hideOthers) then
                local uid = p.UserId
                local cached = Streamer._nameCache[uid]
                if cached then
                    add(cached.Name);
                    add(cached.Display)
                    add("@" .. cached.Name);
                    add("@" .. cached.Display)
                else
                    add(p.Name);
                    add(p.DisplayName)
                    add("@" .. p.Name);
                    add("@" .. p.DisplayName)
                end
            end
        end
        return map
    end

    local function replaceTextWithMap(text, map)
        if not text or text == "" then
            return text
        end
        local out = text
        for real, alias in pairs(map) do
            out = out:gsub(escapePattern(real), alias)
        end
        return out
    end

    local function scrubNodeText(node, map)
        if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
            if node.Text and #node.Text > 0 then
                local newText = replaceTextWithMap(node.Text, map)
                if newText ~= node.Text then
                    node.Text = newText
                end
            end
        end
    end

    local function startUIScrubbers()
        if Streamer._uiScrub then
            Streamer._uiScrub:Disconnect()
        end
        local t = 0
        Streamer._uiScrub = Services.RunService.RenderStepped:Connect(function(dt)
            if not Streamer.enabled then
                return
            end
            t = t + dt
            if t < 0.25 then
                return
            end
            t = 0
            local map = buildReplaceMapToQuestion()
            if next(map) == nil then
                return
            end

            local function scrub(root)
                if not alive(root) then
                    return
                end
                for _, d in ipairs(root:GetDescendants()) do
                    if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                        scrubNodeText(d, map)
                    elseif d:IsA("BillboardGui") then
                        for _, tchild in ipairs(d:GetDescendants()) do
                            if tchild:IsA("TextLabel") then
                                scrubNodeText(tchild, map)
                            end
                        end
                    end
                end
            end

            scrub(CoreGui)
            if LOCAL and alive(LOCAL) then
                local pg = safeFindFirstChild(LOCAL, "PlayerGui")
                if pg then
                    scrub(pg)
                end
            end
        end)

        if Streamer._descAddedConn then
            Streamer._descAddedConn:Disconnect()
        end
        Streamer._descAddedConn = game.DescendantAdded:Connect(function(obj)
            if not Streamer.enabled then
                return
            end
            local map = buildReplaceMapToQuestion()
            if next(map) == nil then
                return
            end
            pcall(function()
                if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                    scrubNodeText(obj, map)
                elseif obj:IsA("BillboardGui") then
                    for _, tchild in ipairs(obj:GetDescendants()) do
                        if tchild:IsA("TextLabel") then
                            scrubNodeText(tchild, map)
                        end
                    end
                end
            end)
        end)
    end

    local function stopUIScrubbers()
        if Streamer._uiScrub then
            Streamer._uiScrub:Disconnect()
        end
        Streamer._uiScrub = nil
        if Streamer._descAddedConn then
            Streamer._descAddedConn:Disconnect()
        end
        Streamer._descAddedConn = nil
    end

    -- ---------- skin hiding (no HumanoidDescription) ----------
    local function clearSkinCacheFor(plr)
        if not plr then
            return
        end
        Streamer._skin[plr.UserId] = nil
    end

    local function cacheSkin(plr, char)
        if not (plr and alive(char)) then
            return
        end
        local uid = plr.UserId
        if Streamer._skin[uid] then
            return
        end

        local bucket = {
            acc = {},
            shirt = nil,
            pants = nil,
            tshirt = nil,
            colors = nil
        }
        for _, inst in ipairs(char:GetChildren()) do
            if inst:IsA("Accessory") then
                table.insert(bucket.acc, inst)
            end
        end
        bucket.shirt = safeFindFirstChildOfClass(char, "Shirt")
        bucket.pants = safeFindFirstChildOfClass(char, "Pants")
        bucket.tshirt = safeFindFirstChildOfClass(char, "ShirtGraphic")

        local bc = safeFindFirstChildOfClass(char, "BodyColors")
        if bc then
            bucket.colors = {
                Head = bc.HeadColor3,
                LA = bc.LeftArmColor3,
                RA = bc.RightArmColor3,
                LL = bc.LeftLegColor3,
                RL = bc.RightLegColor3,
                Torso = bc.TorsoColor3
            }
        end

        Streamer._skin[uid] = bucket
    end

    local function hideSkin(plr)
        local char = safeChar(plr)
        if not char then
            return
        end
        cacheSkin(plr, char)

        for _, inst in ipairs(char:GetChildren()) do
            if inst:IsA("Accessory") and alive(inst) then
                inst.Parent = nil
            end
        end

        local s = safeFindFirstChildOfClass(char, "Shirt")
        local p = safeFindFirstChildOfClass(char, "Pants")
        local t = safeFindFirstChildOfClass(char, "ShirtGraphic")
        if s then
            s.Parent = nil
        end
        if p then
            p.Parent = nil
        end
        if t then
            t.Parent = nil
        end

        local bc = safeFindFirstChildOfClass(char, "BodyColors")
        if bc then
            local neutral = Color3.fromRGB(130, 130, 130)
            pcall(function()
                bc.HeadColor3 = neutral
                bc.LeftArmColor3 = neutral
                bc.RightArmColor3 = neutral
                bc.LeftLegColor3 = neutral
                bc.RightLegColor3 = neutral
                bc.TorsoColor3 = neutral
            end)
        end
    end

    local function restoreSkin(plr)
        local char = safeChar(plr)
        if not char then
            return
        end
        local bucket = Streamer._skin[plr.UserId]
        if not bucket then
            return
        end

        if bucket.shirt and bucket.shirt.Parent == nil then
            bucket.shirt.Parent = char
        end
        if bucket.pants and bucket.pants.Parent == nil then
            bucket.pants.Parent = char
        end
        if bucket.tshirt and bucket.tshirt.Parent == nil then
            bucket.tshirt.Parent = char
        end

        for _, acc in ipairs(bucket.acc) do
            if alive(acc) and acc.Parent == nil then
                acc.Parent = char
            end
        end

        local bc = safeFindFirstChildOfClass(char, "BodyColors")
        if bc and bucket.colors then
            pcall(function()
                bc.HeadColor3 = bucket.colors.Head
                bc.LeftArmColor3 = bucket.colors.LA
                bc.RightArmColor3 = bucket.colors.RA
                bc.LeftLegColor3 = bucket.colors.LL
                bc.RightLegColor3 = bucket.colors.RL
                bc.TorsoColor3 = bucket.colors.Torso
            end)
        end
    end

    local function applyFor(plr)
        if not Streamer.enabled then
            return
        end
        local isMe = (plr == LOCAL)

        local hideOwnName = Streamer.selected["Hide Own Name"]
        local hideOtherNames = Streamer.selected["Hide Others Names"]
        if (isMe and hideOwnName) or ((not isMe) and hideOtherNames) then
            setPlayerNameQuestion(plr)
            setOverheadHidden(plr, true)
        else
            restorePlayerName(plr)
            setOverheadHidden(plr, false)
        end

        local hideOwnSkin = Streamer.selected["Hide Own Skin"]
        local hideOtherSkins = Streamer.selected["Hide Others Skins"]
        if (isMe and hideOwnSkin) or ((not isMe) and hideOtherSkins) then
            hideSkin(plr)
        else
            restoreSkin(plr)
        end
    end

    local function restoreAll()
        local function restore(plr)
            restorePlayerName(plr)
            setOverheadHidden(plr, false)
            restoreSkin(plr)
        end
        if LOCAL then
            restore(LOCAL)
        end
        for _, p in ipairs(Services.Players:GetPlayers()) do
            if p ~= LOCAL then
                restore(p)
            end
        end
    end

    local function applyAll()
        if not Streamer.enabled then
            restoreAll()
            return
        end
        if LOCAL then
            applyFor(LOCAL)
        end
        for _, p in ipairs(Services.Players:GetPlayers()) do
            if p ~= LOCAL then
                applyFor(p)
            end
        end
    end

    local function hookChat()
        if Streamer._chatConn then
            Streamer._chatConn:Disconnect()
        end
        for _, c in ipairs(Streamer._legacyChatConns) do
            pcall(function()
                c:Disconnect()
            end)
        end
        Streamer._legacyChatConns = {}
        Streamer._chatConn = nil

        if TextChatService and TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            Streamer._chatConn = TextChatService.OnIncomingMessage:Connect(function(msg)
                if not (Streamer.enabled and msg) then
                    return
                end
                local src = msg.TextSource
                if not src then
                    return
                end
                local plr = Services.Players:GetPlayerByUserId(src.UserId)
                if not plr then
                    return
                end

                local isMe = (plr == LOCAL)
                local hideSelf = Streamer.selected["Hide Own Name"]
                local hideOthers = Streamer.selected["Hide Others Names"]

                if (isMe and hideSelf) or ((not isMe) and hideOthers) then
                    local props = Instance.new("TextChatMessageProperties")
                    props.PrefixText = "???:"
                    local map = buildReplaceMapToQuestion()
                    props.Text = replaceTextWithMap(msg.Text or "", map)
                    return props
                end
            end)
            return
        end

        local Rep = Services.ReplicatedStorage
        local ChatEvents = Rep and safeFindFirstChild(Rep, "DefaultChatSystemChatEvents")
        if ChatEvents then
            local ev = safeFindFirstChild(ChatEvents, "OnMessageDoneFiltering")
            if ev and ev.OnClientEvent then
                table.insert(Streamer._legacyChatConns, ev.OnClientEvent:Connect(function(data)
                    if not (Streamer.enabled and data) then
                        return
                    end
                    local speaker = data.FromSpeaker
                    local plr = speaker and Services.Players:FindFirstChild(speaker)
                    if not plr then
                        return
                    end
                    local isMe = (plr == LOCAL)
                    local hideSelf = Streamer.selected["Hide Own Name"]
                    local hideOthers = Streamer.selected["Hide Others Names"]
                    if (isMe and hideSelf) or ((not isMe) and hideOthers) then
                        data.FromSpeaker = "???"
                        if data.Message then
                            local map = buildReplaceMapToQuestion()
                            data.Message = replaceTextWithMap(data.Message, map)
                        end
                        data.ExtraData = data.ExtraData or {}
                    end
                end))
            end
        end
    end

    local function unbindAll()
        for _, c in ipairs(Streamer._cons) do
            pcall(function()
                c:Disconnect()
            end)
        end
        Streamer._cons = {}
        if Streamer._chatConn then
            Streamer._chatConn:Disconnect()
        end
        Streamer._chatConn = nil
        for _, c in ipairs(Streamer._legacyChatConns) do
            pcall(function()
                c:Disconnect()
            end)
        end
        Streamer._legacyChatConns = {}
        stopUIScrubbers()
    end

    local function bindAll()
        unbindAll()

        table.insert(Streamer._cons, LOCAL.CharacterAdded:Connect(function()
            clearSkinCacheFor(LOCAL)
            task.defer(applyAll)
        end))

        table.insert(Streamer._cons, Services.Players.PlayerAdded:Connect(function(plr)
            table.insert(Streamer._cons, plr.CharacterAdded:Connect(function()
                clearSkinCacheFor(plr)
                task.defer(function()
                    applyFor(plr)
                end)
            end))
            if plr.Character then
                clearSkinCacheFor(plr)
                task.defer(function()
                    applyFor(plr)
                end)
            end
        end))

        for _, plr in ipairs(Services.Players:GetPlayers()) do
            if plr ~= LOCAL then
                table.insert(Streamer._cons, plr.CharacterAdded:Connect(function()
                    clearSkinCacheFor(plr)
                    task.defer(function()
                        applyFor(plr)
                    end)
                end))
                if plr.Character then
                    clearSkinCacheFor(plr)
                    task.defer(function()
                        applyFor(plr)
                    end)
                end
            end
        end

        hookChat()
        startUIScrubbers()
    end

    local smGroup = Tabs.Misc:AddLeftGroupbox("Streamer Mode", "video")

    local optionsList = {"Hide Own Name", "Hide Others Names", "Hide Own Skin", "Hide Others Skins"}
    smGroup:AddDropdown("streamer_mode_options", {
        Text = "Affects",
        Values = optionsList,
        Multi = true,
        Default = {},
        AllowNull = true,
        Callback = function(selected)
            for k in pairs(Streamer.selected) do
                Streamer.selected[k] = false
            end
            if typeof(selected) == "table" then
                local hasBool = false
                for k, v in pairs(selected) do
                    if type(v) == "boolean" then
                        hasBool = true
                        if v and Streamer.selected[k] ~= nil then
                            Streamer.selected[k] = true
                        end
                    end
                end
                if not hasBool then
                    for _, v in ipairs(selected) do
                        if Streamer.selected[v] ~= nil then
                            Streamer.selected[v] = true
                        end
                    end
                end
            end
            if Streamer.enabled then
                applyAll()
            end
        end
    })

    smGroup:AddToggle("streamer_mode_toggle", {
        Text = "Enable Streamer Mode",
        Default = false,
        Callback = function(on)
            Streamer.enabled = on
            if on then
                Library:Notify("Please open the roblox menu briefly for the best results.", 3)
                bindAll()
                applyAll()
            else
                applyAll()
                unbindAll()
            end
        end
    })

    -- == SPECTATE UI == --
    local SpectateGroupbox = Tabs.Misc:AddLeftGroupbox("Spectate", "view")

    local spectateConn, spectating, Spectate_PlayerAddedConn, Spectate_PlayerRemovingConn
    local dd = SpectateGroupbox:AddDropdown("SpectateTarget", {
        Values = {},
        Default = nil,
        Multi = false,
        Text = "Select Player"
    })

    SpectateGroupbox:AddButton({
        Text = "Refresh Players",
        Func = function()
            local t = {}
            for _, pl in ipairs(Services.Players:GetPlayers()) do
                if pl ~= References.player then
                    t[#t + 1] = pl.Name
                end
            end
            dd:SetValues(t)
        end
    })

    local tg = SpectateGroupbox:AddToggle("SpectateEnabled", {
        Text = "Spectate Player",
        Default = false
    })

    local function stopSpectate()
        if spectateConn then
            spectateConn:Disconnect();
            spectateConn = nil
        end
        spectating = nil
        if References.humanoid then
            References.camera.CameraSubject = References.humanoid
        end
    end

    local function startSpectate(target)
        stopSpectate()
        spectating = target
        if not spectating then
            return
        end
        spectateConn = Services.RunService.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
            local char = spectating.Character
            if char and char:FindFirstChild("Humanoid") then
                References.camera.CameraSubject = char:FindFirstChild("Humanoid")
            else
                stopSpectate()
                tg:SetValue(false)
            end
        end))
    end

    tg:OnChanged(function()
        if tg.Value then
            local name = dd.Value
            local target = name and Services.Players:FindFirstChild(name)
            if target then
                startSpectate(target)
            else
                Library:Notify("Select a player to spectate.", 3)
                tg:SetValue(false)
            end
        else
            stopSpectate()
        end
    end)

    dd:OnChanged(function(name)
        if tg.Value then
            local target = name and Services.Players:FindFirstChild(name)
            if target then
                startSpectate(target)
            end
        end
    end)

    Spectate_PlayerAddedConn = Services.Players.PlayerAdded:Connect(function()
        local t = {}
        for _, pl in ipairs(Services.Players:GetPlayers()) do
            if pl ~= References.player then
                t[#t + 1] = pl.Name
            end
        end
        dd:SetValues(t)
    end)

    Spectate_PlayerRemovingConn = Services.Players.PlayerRemoving:Connect(function(leaver)
        local t = {}
        for _, pl in ipairs(Services.Players:GetPlayers()) do
            if pl ~= References.player and pl ~= leaver then
                t[#t + 1] = pl.Name
            end
        end
        dd:SetValues(t)
        if spectating == leaver then
            tg:SetValue(false)
        end
    end)

    do
        local t = {}
        for _, pl in ipairs(Services.Players:GetPlayers()) do
            if pl ~= References.player then
                t[#t + 1] = pl.Name
            end
        end
        dd:SetValues(t)
    end

    -- ==== UNLOADER ====
    M.SmartServerHop = SmartServerHop

    function M.Unload()
        stopServerAutoHop()
        destroyHud()
        stopEnvironment()
        stopSpectate()
        if Spectate_PlayerAddedConn then
            Spectate_PlayerAddedConn:Disconnect();
            Spectate_PlayerAddedConn = nil
        end
        if Spectate_PlayerRemovingConn then
            Spectate_PlayerRemovingConn:Disconnect();
            Spectate_PlayerRemovingConn = nil
        end

        if Toggles.SERVER_AutoHop and Toggles.SERVER_AutoHop.Value then
            Toggles.SERVER_AutoHop:SetValue(false)
        end

        autoChatRunning = false
        if Toggles.autoChatEnabled and Toggles.autoChatEnabled.Value then
            Toggles.autoChatEnabled:SetValue(false)
        end

        if Streamer.enabled then
            Streamer.enabled = false
            pcall(unbindAll)
            pcall(restoreAll)
        end
        if Toggles.streamer_mode_toggle and Toggles.streamer_mode_toggle.Value then
            Toggles.streamer_mode_toggle:SetValue(false)
        end
    end

    return M
end
