return function(ctx)
    assert(type(ctx) == "table", "AutoRaid: context table required")

    -- // SERVICES & UTILS //
    local Services = assert(ctx.Services, "AutoRaid: Services missing")
    local References = assert(ctx.References, "AutoRaid: References missing")
    local Library = assert(ctx.Library, "AutoRaid: Library missing")
    local Tabs = assert(ctx.Tabs, "AutoRaid: Tabs missing")
    local Options = assert(ctx.Options, "AutoRaid: Options missing")
    local Toggles = assert(ctx.Toggles, "AutoRaid: Toggles missing")
    local Autos = assert(ctx.Autos, "AutoRaid: Autos missing")
    local AttachPanel = assert(ctx.AttachPanel, "AutoRaid: AttachPanel missing")
    local MoveToPos = ctx.MoveToPos
    local NetworkPath = ctx.NetworkPath
    local RemoteFunction = ctx.RemoteFunction

    -- Ensure Services
    Services.TeleportService = Services.TeleportService or game:GetService("TeleportService")
    Services.HttpService = Services.HttpService or game:GetService("HttpService")
    Services.GuiService = Services.GuiService or game:GetService("GuiService")
    Services.VirtualInputManager = Services.VirtualInputManager or game:GetService("VirtualInputManager")
    Services.RunService = Services.RunService or game:GetService("RunService")

    local Remotes = RemoteFunction or (NetworkPath and NetworkPath:WaitForChild("RemoteFunction"))
    if not Remotes then
        error("AutoRaid: RemoteFunction missing")
    end

    local LoadedRemote = Services.ReplicatedStorage:WaitForChild("Files"):WaitForChild("Remotes"):WaitForChild("Loaded")

    -- // CONFIGURATION CONSTANTS //
    local CONFIG_FOLDER_ROOT = "Cerberus"
    local CONFIG_FOLDER_PATH = References.gameDir or "Cerberus/Devil Hunter"
    local CONFIG_FILE_NAME = "RaidGroups_v2.json"
    local FULL_PATH = CONFIG_FOLDER_PATH .. "/" .. CONFIG_FILE_NAME

    local GROUP_OPTIONS = { "Group 1", "Group 2", "Group 3", "Group 4", "Group 5" }
    
    -- // STATE INITIALIZATION //
    Autos.CurrentGroupIndex = "Group 1"
    Autos.NextHopTime = nil
    Autos.LastJobIdCheck = 0
    Autos.IsHopping = false
    Autos.WaitThreshold = 5
    Autos.HopWaitStart = nil -- Added for the 15s delay logic
    
    Autos.LastTeleportTime = Autos.LastTeleportTime or 0
    Autos.NoEnemyTimer = Autos.NoEnemyTimer or 0
    Autos.LastPlayGameFire = Autos.LastPlayGameFire or 0
    Autos.LastInviteTime = Autos.LastInviteTime or 0
    Autos.ZombieResetting = Autos.ZombieResetting or false
    Autos.ZombieResetCleanup = Autos.ZombieResetCleanup or nil
    Autos.ZombieEmptySince = Autos.ZombieEmptySince or nil
    Autos.ZombieEmptyLastAction = Autos.ZombieEmptyLastAction or 0

    -- // HELPER FUNCTIONS //
    local function normalizeName(name)
        return (tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function ParseMains(str)
        local list = {}
        for s in string.gmatch(str, "([^,]+)") do
            local clean = normalizeName(s)
            if clean ~= "" then table.insert(list, clean) end
        end
        return list
    end

    local function MainsToString(list)
        return table.concat(list or {}, ", ")
    end

    -- // CONFIGURATION HANDLERS //
    local function GetDefaultConfig()
        local cfg = { LastSelected = "Group 1", Groups = {} }
        for _, g in ipairs(GROUP_OPTIONS) do
            cfg.Groups[g] = { Alt = "", Mains = {}, JobId = "" }
        end
        return cfg
    end

    local function LoadConfig()
        if isfile(FULL_PATH) then
            local success, result = pcall(function()
                return Services.HttpService:JSONDecode(readfile(FULL_PATH))
            end)
            if success and type(result) == "table" and result.Groups then
                for _, g in ipairs(GROUP_OPTIONS) do
                    if not result.Groups[g] then
                        result.Groups[g] = { Alt = "", Mains = {}, JobId = "" }
                    end
                end
                return result
            end
        end
        return GetDefaultConfig()
    end

    local function SaveConfig(data)
        if not isfolder(CONFIG_FOLDER_ROOT) then makefolder(CONFIG_FOLDER_ROOT) end
        if not isfolder(CONFIG_FOLDER_PATH) then makefolder(CONFIG_FOLDER_PATH) end
        
        local success, err = pcall(function()
            writefile(FULL_PATH, Services.HttpService:JSONEncode(data))
        end)
        if not success then warn("AutoRaid Save Error: " .. tostring(err)) end
    end

    -- Initial Load
    local CachedConfig = LoadConfig()
    Autos.CurrentGroupIndex = CachedConfig.LastSelected or "Group 1"

    local function RefreshLocalAutos()
        local gData = CachedConfig.Groups[Autos.CurrentGroupIndex]
        if gData then
            Autos.AltAccountName = gData.Alt
            Autos.MainAccountNames = gData.Mains
            Autos.MainAccountName = gData.Mains[1] or ""
        end
    end
    RefreshLocalAutos()

    -- // NOTIFICATION //
    local function notify(msg, duration)
        if Autos.LastNotif ~= msg then
            Library:Notify(msg, duration or 3)
            Autos.LastNotif = msg
            task.delay(5, function()
                if Autos.LastNotif == msg then Autos.LastNotif = "" end
            end)
        end
    end

    -- // RAID CONSTANTS //
    local RAID_START_OPTIONS = { "Katana Man Raid", "Zombie Raid" }
    local ZOMBIE_RAID_ENTRANCE_POS = Vector3.new(37.856991, 6.760758, -1441.734375)
    local ZOMBIE_VOID_POS = Vector3.new(0, -1000, 0)
    local ZOMBIE_EMPTY_POS = Vector3.new(-448.255676, 60.691345, 512.108337)

    -- // IDENTITY CHECKS //
    local function isMainAccount(name)
        local norm = normalizeName(name)
        for _, v in ipairs(Autos.MainAccountNames or {}) do
            if normalizeName(v) == norm then return true end
        end
        return false
    end

    local function isAltAccount(name)
        return normalizeName(Autos.AltAccountName) == normalizeName(name)
    end

    -- // GUI CONSTRUCTION //
    local AutoRaidGroup = Tabs.Auto:AddLeftGroupbox("Auto Raid Manager", "shield")
    local InfoLabel = AutoRaidGroup:AddLabel("Info: Configure Groups & Multi-Instance", true)
    
    AutoRaidGroup:AddDivider()

    -- Group Select
    AutoRaidGroup:AddDropdown("GroupSelect", {
        Text = "Select Group",
        Values = GROUP_OPTIONS,
        Default = Autos.CurrentGroupIndex,
        Multi = false,
    })

    -- Config Inputs
    AutoRaidGroup:AddInput("AltAccountName", {
        Default = Autos.AltAccountName,
        Numeric = false, Finished = true,
        Text = "Alt Name (Host)", Tooltip = "The account that broadcasts JobID", Placeholder = "Username...",
    })

    AutoRaidGroup:AddInput("MainAccountName", {
        Default = MainsToString(Autos.MainAccountNames),
        Numeric = false, Finished = true,
        Text = "Main Name(s)", Tooltip = "Separate with commas", Placeholder = "User1, User2...",
    })

    -- Buttons
    AutoRaidGroup:AddButton("Clear Current Group", function()
        Autos.SuppressAccountUpdate = true
        CachedConfig = LoadConfig()
        CachedConfig.Groups[Autos.CurrentGroupIndex] = { Alt = "", Mains = {}, JobId = "" }
        SaveConfig(CachedConfig)

        if Options.AltAccountName then Options.AltAccountName:SetValue("") end
        if Options.MainAccountName then Options.MainAccountName:SetValue("") end
        
        RefreshLocalAutos()
        Autos.SuppressAccountUpdate = false
        notify("Cleared config for " .. Autos.CurrentGroupIndex, 3)
    end)

    AutoRaidGroup:AddDivider()
    
    -- Alt Hop
    AutoRaidGroup:AddToggle("AltHop", { 
        Text = "Alt Hop",
        Default = false, 
        Tooltip = "Alt hops every 30 mins. Must have AutoLoad and ForceLoad!"
    })

    -- Raid Toggles
    AutoRaidGroup:AddLabel("Raid Logic")
    AutoRaidGroup:AddToggle("AutoJoinRaid", { Text = "Auto Join Raid", Default = false })
    AutoRaidGroup:AddToggle("InfiniteRaid", { Text = "Infinite Raid", Default = false, Tooltip = "Uses Group Logic" })
    
    AutoRaidGroup:AddDropdown("RaidStartSelect", {
        Text = "Raid Start",
        Values = RAID_START_OPTIONS,
        Default = Autos.SelectedRaidStart or "Katana Man Raid",
        Multi = false,
    })
    
    AutoRaidGroup:AddToggle("AutoClearRaid", { Text = "Auto Clear Raid", Default = false })
    AutoRaidGroup:AddToggle("Devil_ForceLoaded", { Text = "Force Load", Default = false })

    local StatusLabel = AutoRaidGroup:AddLabel("Status: Initializing...", true)

    -- // UI CALLBACKS //
    local function UpdateUIFromConfig()
        local gData = CachedConfig.Groups[Autos.CurrentGroupIndex]
        if gData then
            Autos.SuppressAccountUpdate = true
            if Options.AltAccountName then Options.AltAccountName:SetValue(gData.Alt) end
            if Options.MainAccountName then Options.MainAccountName:SetValue(MainsToString(gData.Mains)) end
            Autos.SuppressAccountUpdate = false
            RefreshLocalAutos()
        end
    end

    Options.GroupSelect:OnChanged(function()
        Autos.CurrentGroupIndex = Options.GroupSelect.Value
        CachedConfig = LoadConfig() 
        CachedConfig.LastSelected = Autos.CurrentGroupIndex
        SaveConfig(CachedConfig)
        UpdateUIFromConfig()
    end)

    local function SaveCurrentInputs()
        if Autos.SuppressAccountUpdate then return end
        local alt = normalizeName(Options.AltAccountName.Value)
        local mains = ParseMains(Options.MainAccountName.Value)
        
        CachedConfig.Groups[Autos.CurrentGroupIndex].Alt = alt
        CachedConfig.Groups[Autos.CurrentGroupIndex].Mains = mains
        SaveConfig(CachedConfig)
        RefreshLocalAutos()
    end

    Options.AltAccountName:OnChanged(SaveCurrentInputs)
    Options.MainAccountName:OnChanged(SaveCurrentInputs)
    
    Options.RaidStartSelect:OnChanged(function()
        Autos.SelectedRaidStart = Options.RaidStartSelect.Value
        if Autos.SelectedRaidStart == "Zombie Raid" then
            InfoLabel:SetText("Info: Zombie Raid - No InstaKill. Needs AutoEquip + M1")
        else
            InfoLabel:SetText("Info: Requires AutoEquip, AutoAttack (M1), and InstaKill.")
        end
    end)

    Toggles.AltHop:OnChanged(function()
        if Toggles.AltHop.Value then
            Autos.NextHopTime = os.time() + 1800 -- 30 mins from now
        else
            Autos.NextHopTime = nil
        end
    end)

    -- // RAID HELPER FUNCTIONS (MOVED UP FOR SCOPE) //
    local function getRaidEntrancePos()
        if Autos.SelectedRaidStart == "Zombie Raid" then
            return ZOMBIE_RAID_ENTRANCE_POS
        end
        return Autos.RaidEntrancePos or Vector3.new(0,0,0)
    end

    local function getActiveMainPlayer()
        local mains = Autos.MainAccountNames or {}
        local activeName = Autos.ActiveMainName
        if activeName and activeName ~= "" then
            local activePlayer = Services.Players:FindFirstChild(activeName)
            if activePlayer then
                return activeName, activePlayer
            end
            Autos.ActiveMainName = nil
        end

        for _, name in ipairs(mains) do
            if name ~= Autos.AltAccountName then
                local player = Services.Players:FindFirstChild(name)
                if player then
                    Autos.ActiveMainName = name
                    return name, player
                end
            end
        end
        return nil, nil
    end

    local function isZombieName(name)
        return type(name) == "string" and string.find(string.lower(name), "zombie", 1, true) ~= nil
    end
    
    local function isTankZombieName(name)
        if type(name) ~= "string" then return false end
        local lower = string.lower(name)
        return string.find(lower, "zombie", 1, true) ~= nil and string.find(lower, "tank", 1, true) ~= nil
    end

    local function isSeaZombieName(name)
        if type(name) ~= "string" then return false end
        return string.find(string.lower(name), "sea", 1, true) ~= nil
    end

    local function isLeechName(name)
        return type(name) == "string" and string.find(string.lower(name), "leech", 1, true) ~= nil
    end

    local function isDevilName(name)
        return type(name) == "string" and string.find(string.lower(name), "devil", 1, true) ~= nil
    end

    local function isTeleportOnlyTarget(name, raidType)
        if isLeechName(name) or isDevilName(name) then return true end
        return raidType == "Zombie Raid" and isSeaZombieName(name)
    end

    local function getZombieCount()
        local world = Services.Workspace:FindFirstChild("World")
        local entities = world and world:FindFirstChild("Entities")
        if not entities then return 0 end
        local count = 0
        for _, v in ipairs(entities:GetDescendants()) do
            if v:IsA("Model") and not Services.Players:GetPlayerFromCharacter(v) and isZombieName(v.Name) then
                count = count + 1
            end
        end
        return count
    end

    local function isKatanaRaid()
        local gui = References.player:FindFirstChild("PlayerGui")
        local hud = gui and gui:FindFirstChild("HUD")
        local objectives = hud and hud:FindFirstChild("Objectives")
        return objectives and objectives:FindFirstChild("Yakuza Infiltration") ~= nil
    end

    local function getRaidType()
        local zombieCount = getZombieCount()
        if zombieCount >= 10 then Autos.ZombieRaidActive = true end

        if isKatanaRaid() then
            Autos.RaidType = "Katana Raid"
            return Autos.RaidType
        end

        if Autos.ZombieRaidActive then
            Autos.RaidType = "Zombie Raid"
            return Autos.RaidType
        end
        Autos.RaidType = nil
        return nil
    end

    local function isInRaid() return getRaidType() ~= nil end

    local function isPlayerLoaded()
        if not game:IsLoaded() then return false end
        local char = References.player.Character
        if not char or not char:FindFirstChild("Humanoid") or not char:FindFirstChild("HumanoidRootPart") then return false end
        if not References.player:FindFirstChild("PlayerGui") then return false end
        return true
    end

    local function getHealthRatio()
        local char = References.player.Character
        local hum = char and char:FindFirstChild("Humanoid")
        if not hum or hum.MaxHealth <= 0 then return nil end
        return hum.Health / hum.MaxHealth
    end

    local function triggerZombieReset()
        if Autos.ZombieResetting then return end
        Autos.ZombieResetting = true
        if Autos.IsAttaching then AttachPanel.Stop(); Autos.IsAttaching = false end
        
        local startChar = References.player.Character
        task.spawn(function()
            while Autos.ZombieResetting do
                local char = References.player.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                local hum = char and char:FindFirstChild("Humanoid")
                
                if not char or not char.Parent or (startChar and char ~= startChar) or (hum and hum.Health <= 0) then break end
                
                if root then
                    if MoveToPos then Autos.ZombieResetCleanup = MoveToPos(ZOMBIE_VOID_POS, 5000)
                    else root.CFrame = CFrame.new(ZOMBIE_VOID_POS); root.AssemblyLinearVelocity = Vector3.zero end
                end
                task.wait(1)
            end
            if Autos.ZombieResetCleanup then pcall(Autos.ZombieResetCleanup); Autos.ZombieResetCleanup = nil end
            local currentChar = References.player.Character
            if not currentChar or currentChar == startChar then References.player.CharacterAdded:Wait() end
            Autos.ZombieResetting = false
        end)
    end

    local function getSafePosition(instance)
        if not instance then return nil end
        if instance:IsA("BasePart") then return instance.Position
        elseif instance:IsA("Model") then return instance:GetPivot().Position end
        return nil
    end

    -- // NETWORKING & HOPPING LOOP (MODIFIED & MOVED) //
    task.spawn(function()
        while true do
            task.wait(2) -- Heartbeat for config sync
            
            -- Reload Config to get updates from other instances
            local diskConfig = LoadConfig()
            diskConfig.LastSelected = Autos.CurrentGroupIndex 
            CachedConfig = diskConfig
            RefreshLocalAutos()

            local myName = normalizeName(References.player.Name)
            local currentGroup = CachedConfig.Groups[Autos.CurrentGroupIndex]

            if currentGroup and Toggles.AutoJoinRaid.Value then
                
                -- >> ALT LOGIC <<
                if isAltAccount(myName) then
                    local needsSave = false
                    
                    -- 1. Broadcast Job ID
                    if currentGroup.JobId ~= game.JobId then
                        currentGroup.JobId = game.JobId
                        needsSave = true
                    end
                    
                    if needsSave then
                        SaveConfig(CachedConfig)
                    end

                    -- 2. Alt Hop Logic
                    if Toggles.AltHop.Value and Autos.NextHopTime and not Autos.IsHopping then
                        local timeLeft = Autos.NextHopTime - os.time()
                        if timeLeft <= 0 then
                            Autos.IsHopping = true
                            notify("Alt Hop: Switching Servers...", 5)
                            
                            if queue_on_teleport then
                                -- queue_on_teleport('loadstring(game:HttpGet("YOUR_SCRIPT_URL_HERE"))()') 
                            end
                            
                            Services.TeleportService:Teleport(game.PlaceId, References.player)
                            task.wait(10)
                        elseif timeLeft < 60 and timeLeft % 15 == 0 then
                            notify("Alt Hop: " .. timeLeft .. "s remaining", 3)
                        end
                    end
                end

                -- >> MAIN LOGIC (UPDATED WITH 15S WAIT + NO RAID CHECK) <<
                if isMainAccount(myName) then
                    local targetJob = currentGroup.JobId
                    
                    -- Check if target exists, we are NOT in that server, and NOT hopping
                    if targetJob and targetJob ~= "" and targetJob ~= game.JobId and not Autos.IsHopping then
                        
                        -- Requirement 1: Only if not in a raid
                        if not isInRaid() then
                            -- Requirement 2 & 3: Wait 15s before assessing
                            if not Autos.HopWaitStart then
                                Autos.HopWaitStart = os.time()
                                notify("Main: Wrong server. Waiting 15s to hop...", 4)
                            else
                                local elapsed = os.time() - Autos.HopWaitStart
                                if elapsed >= 15 then
                                    Autos.IsHopping = true
                                    notify("Main: Joining Alt's Server Now...", 5)
                                    Services.TeleportService:TeleportToPlaceInstance(game.PlaceId, targetJob, References.player)
                                    task.wait(10)
                                elseif elapsed % 5 == 0 then
                                    -- Optional countdown status
                                    -- notify("Main: Hop in " .. (15 - elapsed) .. "s", 1)
                                end
                            end
                        else
                            -- We are in a raid, cancel any pending hop
                            Autos.HopWaitStart = nil
                        end
                    else
                        -- We are either in the right server, target is invalid, or already hopping
                        Autos.HopWaitStart = nil
                    end
                end
            end
        end
    end)

    -- // IMPROVED CLICKER (UPDATED WITH UI SELECTION) //
    local function clickGuiButton(btn)
        if not btn or not btn.Visible then return false end
        
        -- 1. Ensure the button is technically selectable so the engine accepts it
        btn.Selectable = true
        btn.Active = true
        
        -- 2. Force Roblox to "Select" this object visually and logically
        Services.GuiService.SelectedObject = btn
        
        -- 3. Wait one frame to ensure the selection registers
        Services.RunService.RenderStepped:Wait()
        
        -- 4. Send the "Return" (Enter) key via VirtualInputManager
        Services.VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
        task.wait(0.1)
        Services.VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
        
        -- 5. Cleanup: Clear selection to avoid stuck UI highlights
        task.delay(0.1, function()
            if Services.GuiService.SelectedObject == btn then
                Services.GuiService.SelectedObject = nil
            end
        end)

        return true
    end

    local function clickRaidButton()
        local gui = References.player:WaitForChild("PlayerGui", 5)
        local enterRaid = gui and gui:WaitForChild("EnterRaid", 5)
        if not enterRaid then return false end
        
        local frame = enterRaid:FindFirstChild("Frame")
        if not frame or not frame.Visible then return false end

        -- Try typical button names
        local btn = frame:FindFirstChild("Enter") or frame:FindFirstChild("Button")
        if btn and btn:IsA("GuiButton") then return clickGuiButton(btn) end
        
        -- Recursive search
        for _, v in ipairs(frame:GetDescendants()) do
            if v:IsA("GuiButton") and (v.Name == "Enter" or v.Name == "Button" or v.Name == "Yes") then
                 return clickGuiButton(v)
            end
        end
        return false
    end

    local function hasParty()
        local hud = References.player.PlayerGui:FindFirstChild("HUD")
        if hud then
            local list = hud.Party.Main.Menu.List
            for _, v in ipairs(list:GetChildren()) do if v:IsA("Frame") then return true end end
        end
        return false
    end

    local function isPlayerInParty(targetName)
        local hud = References.player.PlayerGui:FindFirstChild("HUD")
        if hud then
            local list = hud.Party.Main.Menu.List
            if list:FindFirstChild(targetName) then return true end
            for _, v in ipairs(list:GetChildren()) do
                if v:IsA("Frame") then
                    for _, lbl in ipairs(v:GetDescendants()) do
                        if lbl:IsA("TextLabel") and lbl.Text == targetName then return true end
                    end
                end
            end
        end
        return false
    end

    -- // UTILITY BUTTON CLICKERS //
    local function getSkipButton()
        local pg = References.player:FindFirstChild("PlayerGui")
        local ls = pg and pg:FindFirstChild("LoadScreen")
        local skip = ls and ls:FindFirstChild("Skip")
        return (skip and skip:IsA("GuiButton")) and skip or nil
    end

    local function getPlayGameButton()
        local pg = References.player:FindFirstChild("PlayerGui")
        local main = pg and pg:FindFirstChild("Main")
        local menu = main and main:FindFirstChild("Menu")
        local buttons = menu and menu:FindFirstChild("Buttons")
        local btn = buttons and buttons:FindFirstChild("PLAY GAME")
        return (btn and btn:IsA("GuiButton")) and btn or nil
    end

    local function getCraneDropButton()
        local pg = References.player:FindFirstChild("PlayerGui")
        local crane = pg and pg:FindFirstChild("CraneDrop")
        local frame = crane and crane:FindFirstChild("Frame")
        local btn = frame and frame:FindFirstChild("Drop")
        return (btn and btn:IsA("GuiButton")) and btn or nil
    end

    local function clickSkipViaGuiNav(btn)
        if not btn or not btn.Visible then return end
        clickGuiButton(btn)
    end

    -- // BACKGROUND LOOP: FORCE LOAD //
    task.spawn(function()
        while true do
            task.wait(0.5)
            if Toggles.Devil_ForceLoaded and Toggles.Devil_ForceLoaded.Value then
                local skipBtn = getSkipButton()
                if skipBtn and skipBtn.Visible then clickSkipViaGuiNav(skipBtn) end
                
                local playBtn = getPlayGameButton()
                if playBtn and playBtn.Visible then
                    local now = os.clock()
                    if (now - Autos.LastPlayGameFire) >= 10 then
                        LoadedRemote:FireServer(1)
                        Autos.LastPlayGameFire = now
                    end
                end
                
                if not isPlayerLoaded() then LoadedRemote:FireServer() end
            end
        end
    end)

    -- // BACKGROUND LOOP: STATUS //
    task.spawn(function()
        while true do
            local raidType = getRaidType()
            if raidType then StatusLabel:SetText("Status: Raid (Active - " .. raidType .. ")", true)
            else StatusLabel:SetText("Status: Lobby") end
            task.wait(1)
        end
    end)

    -- // MAIN JOIN LOOP //
    task.spawn(function()
        while true do
            task.wait(1)
            pcall(function()
                if not isInRaid() and Toggles.AutoJoinRaid.Value then
                    local myName = normalizeName(References.player.Name)
                    local char = References.player.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")

                    RefreshLocalAutos()

                    if Toggles.InfiniteRaid.Value then
                        
                        -- == ALT (HOST) LOGIC ==
                        if isAltAccount(myName) then
                            local mainName, mainPlayer = getActiveMainPlayer()

                            if not mainPlayer then
                                if os.clock() % 5 < 1 then notify("Waiting for a Main...", 2) end
                            else
                                if not hasParty() then
                                    notify("Creating Party...", 2)
                                    Remotes:InvokeServer("RequestCreateParty")
                                    task.wait(1)
                                end

                                if not isPlayerInParty(mainName) then
                                    if (os.clock() - (Autos.LastInviteTime or 0)) > 15 then
                                        notify("Inviting " .. mainName .. "...", 2)
                                        Remotes:InvokeServer("InviteParty", mainPlayer)
                                        Autos.LastInviteTime = os.clock()
                                    end
                                else
                                    notify("Starting Raid...", 2)
                                    if root then
                                        local raidPos = getRaidEntrancePos()
                                        if (root.Position - raidPos).Magnitude > 5 then
                                            root.CFrame = CFrame.new(raidPos)
                                            task.wait(0.5)
                                        end

                                        -- UI Detection and Clicking
                                        local pg = References.player:FindFirstChild("PlayerGui")
                                        local enterRaid = pg and pg:FindFirstChild("EnterRaid")
                                        local frame = enterRaid and enterRaid:FindFirstChild("Frame")
                                        local uiVisible = (frame and frame.Visible)
                                        
                                        if not uiVisible then
                                            for _, v in ipairs(Services.Workspace:GetDescendants()) do
                                                if v:IsA("ProximityPrompt") then
                                                    local pos = getSafePosition(v.Parent)
                                                    if pos and (pos - raidPos).Magnitude < 15 then
                                                        v.HoldDuration = 0
                                                        v.RequiresLineOfSight = false
                                                        fireproximityprompt(v)
                                                        break
                                                    end
                                                end
                                            end
                                            task.wait(0.5)
                                        end

                                        if uiVisible or (pg and pg:FindFirstChild("EnterRaid") and pg.EnterRaid:FindFirstChild("Frame") and pg.EnterRaid.Frame.Visible) then
                                            for _ = 1, 5 do
                                                if clickRaidButton() then break end
                                                task.wait(0.3)
                                            end
                                        end
                                    end
                                end
                            end

                        -- == MAIN (JOINER) LOGIC ==
                        elseif isMainAccount(myName) then
                            local activeName, _ = getActiveMainPlayer()
                            
                            if activeName and activeName ~= myName then
                                if os.clock() % 5 < 1 then notify("Waiting for active main: " .. activeName, 2) end
                                return
                            end

                            Autos.ActiveMainName = myName
                            local altPlayer = Services.Players:FindFirstChild(Autos.AltAccountName)
                            
                            if altPlayer then
                                if not isPlayerInParty(Autos.AltAccountName) then
                                    notify("Waiting for invite...", 2)
                                    Remotes:InvokeServer("AcceptInvite", altPlayer)
                                    task.wait(2)
                                else
                                    notify("In Party! Waiting for start...", 2)
                                end
                            else
                                notify("Waiting for Alt to load...", 2)
                            end
                        end

                    else
                        -- == STANDARD SOLO LOGIC ==
                        if root then
                            local raidPos = getRaidEntrancePos()
                            if (root.Position - raidPos).Magnitude > 5 then
                                root.CFrame = CFrame.new(raidPos)
                                task.wait(0.5)
                            end

                            local pg = References.player:WaitForChild("PlayerGui")
                            local uiFound = false
                            for _ = 1, 10 do
                                if pg:FindFirstChild("EnterRaid") and pg.EnterRaid:FindFirstChild("Frame") and pg.EnterRaid.Frame.Visible then
                                    uiFound = true
                                    break
                                end
                                for _, v in ipairs(Services.Workspace:GetDescendants()) do
                                    if v:IsA("ProximityPrompt") then
                                        local pos = getSafePosition(v.Parent)
                                        if pos and (pos - raidPos).Magnitude < 15 then
                                            v.HoldDuration = 0; v.RequiresLineOfSight = false
                                            fireproximityprompt(v)
                                            break
                                        end
                                    end
                                end
                                task.wait(0.5)
                            end
                            if uiFound then
                                for _ = 1, 5 do
                                    if clickRaidButton() then break end
                                    task.wait(0.3)
                                end
                            end
                        end
                    end
                end
            end)
        end
    end)

    -- // AUTOCLEAR LOGIC //
    task.spawn(function()
        local function checkAndInteractDialog()
            local map = Services.Workspace:FindFirstChild("Map")
            if not map then return false end

            for _, v in ipairs(map:GetDescendants()) do
                if v:IsA("ProximityPrompt") and v.Name == "Dialog" and v.Enabled then
                    local pos = getSafePosition(v.Parent)
                    if pos then
                        local char = References.player.Character
                        local root = char and char:FindFirstChild("HumanoidRootPart")
                        if root then
                            notify("Interacting with Dialog...", 3)
                            local oldAnchor = root.Anchored
                            root.Anchored = true
                            root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
                            task.wait(0.3)
                            fireproximityprompt(v)
                            task.wait(3)
                            root.Anchored = oldAnchor
                            return true
                        end
                    end
                end
            end
            return false
        end

        local function getElevatorTarget()
            local map = Services.Workspace:FindFirstChild("Map")
            if not map then return nil, nil end

            local office = map:FindFirstChild("Office_Floor")
            if office then
                local zone = office:FindFirstChild("Elevatorzone")
                local prompt = zone and zone:FindFirstChild("Prompt")
                if zone and prompt and prompt.Enabled then return zone, prompt end
            end

            for _, v in ipairs(map:GetDescendants()) do
                if v.Name == "Elevatorzone" then
                    local prompt = v:FindFirstChild("Prompt")
                    if prompt and prompt.Enabled then return v, prompt end
                end
            end
            return nil, nil
        end

        local function getClosestEntityNoHealth(entities, myRoot)
            local closest = nil
            local shortestDist = math.huge
            for _, v in ipairs(entities:GetChildren()) do
                if v ~= References.player.Character and v.Name ~= References.player.Name then
                    local pos = getSafePosition(v)
                    if pos then
                        local dist = (pos - myRoot.Position).Magnitude
                        if dist < shortestDist then
                            shortestDist = dist
                            closest = v
                        end
                    end
                end
            end
            return closest
        end

        local function getNearestPrompt(root)
            if not root then return nil end
            local closest = nil
            local shortestDist = math.huge
            for _, v in ipairs(Services.Workspace:GetDescendants()) do
                if v:IsA("ProximityPrompt") and v.Enabled then
                    local pos = getSafePosition(v.Parent)
                    if pos then
                        local dist = (pos - root.Position).Magnitude
                        if dist < shortestDist then
                            shortestDist = dist
                            closest = v
                        end
                    end
                end
            end
            return closest
        end

        while true do
            task.wait(0.5)

            local raidType = getRaidType()
            if raidType ~= "Zombie Raid" then
                Autos.ZombieResetting = false
            end
            if Toggles.AutoClearRaid.Value and raidType then
                if Autos.LastRaidTypeNotified ~= raidType then
                    notify("AutoClear: " .. raidType .. " detected", 3)
                    Autos.LastRaidTypeNotified = raidType
                end

                if raidType == "Zombie Raid" then
                    local ratio = getHealthRatio()
                    if ratio and ratio <= 0.2 then
                        triggerZombieReset()
                    end
                end

                local world = Services.Workspace:FindFirstChild("World")
                Autos.RaidEntitiesPath = world and world:FindFirstChild("Entities")

                local target = nil
                local shortestDist = math.huge
                local myRoot = References.player.Character and References.player.Character:FindFirstChild("HumanoidRootPart")

                if Autos.ZombieResetting then
                    Autos.LastTeleportTime = os.clock()
                else
                    if myRoot and Autos.RaidEntitiesPath then
                        for _, v in ipairs(Autos.RaidEntitiesPath:GetChildren()) do
                            if v ~= References.player.Character then
                                local isTeleportOnly = isTeleportOnlyTarget(v.Name, raidType)
                                local pos = nil

                                if isTeleportOnly then
                                    pos = getSafePosition(v)
                                else
                                    local hum = v:FindFirstChild("Humanoid")
                                    local root = v:FindFirstChild("HumanoidRootPart")
                                    if hum and root and hum.Health > 0 then
                                        pos = root.Position
                                    end
                                end

                                if pos then
                                    local dist = (pos - myRoot.Position).Magnitude
                                    if dist < shortestDist then
                                        shortestDist = dist
                                        target = v
                                    end
                                end
                            end
                        end
                    end

                    if target then
                        Autos.NoEnemyTimer = os.clock()

                        if isTeleportOnlyTarget(target.Name, raidType) then
                            if Autos.IsAttaching then
                                AttachPanel.Stop()
                                Autos.IsAttaching = false
                            end

                            if myRoot then
                                local pos = getSafePosition(target)
                                if pos then
                                    local delta = myRoot.Position - pos
                                    local distXZ = Vector3.new(delta.X, 0, delta.Z).Magnitude
                                    if distXZ > 8 then
                                        myRoot.CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0))
                                    end
                                end
                            end
                        else
                            AttachPanel.SetMode("Behind")
                            AttachPanel.SetHorizDist(4)
                            if raidType == "Zombie Raid" then
                                if isTankZombieName(target.Name) then
                                    AttachPanel.SetYOffset(-2)
                                else
                                    AttachPanel.SetYOffset(0)
                                end
                            else
                                AttachPanel.SetYOffset(0)
                            end
                            AttachPanel.EnableDodge(false)

                            if AttachPanel.GetTarget() ~= target or not Autos.IsAttaching then
                                AttachPanel.SetTarget(target)
                                AttachPanel.State.running = true
                                AttachPanel.GoApproach()
                                Autos.IsAttaching = true
                            end
                        end

                    else
                        if Autos.IsAttaching then
                            AttachPanel.Stop()
                            Autos.IsAttaching = false
                            if raidType == "Katana Raid" then
                                notify("Room Clear. Searching...", 3)
                            end
                        end

                        if raidType == "Zombie Raid" then
                            local nonPlayerFound = false
                            if Autos.RaidEntitiesPath then
                                for _, v in ipairs(Autos.RaidEntitiesPath:GetChildren()) do
                                    if v ~= References.player.Character and v.Name ~= References.player.Name then
                                        nonPlayerFound = true
                                        break
                                    end
                                end
                            end

                            if nonPlayerFound then
                                Autos.ZombieEmptySince = nil
                                Autos.ZombieEmptyLastAction = 0
                            else
                                if not Autos.ZombieEmptySince then
                                    Autos.ZombieEmptySince = os.clock()
                                    notify("Zombie Raid: Entities empty, waiting 10s...", 3)
                                end
                                if not Autos.ZombieResetting
                                    and (os.clock() - Autos.ZombieEmptySince) >= 10
                                    and (os.clock() - Autos.ZombieEmptyLastAction) >= 10 then
                                    local root = References.player.Character and References.player.Character:FindFirstChild("HumanoidRootPart")
                                    if root then
                                        root.CFrame = CFrame.new(ZOMBIE_EMPTY_POS + Vector3.new(0, 3, 0))
                                        wait(0.5)
                                        local prompt = getNearestPrompt(root)
                                        if prompt then
                                            fireproximityprompt(prompt)
                                            task.wait(0.5)
                                            local dropBtn = getCraneDropButton()
                                            if dropBtn and dropBtn.Visible then
                                                clickGuiButton(dropBtn)
                                            end
                                        end
                                    end
                                    Autos.ZombieEmptyLastAction = os.clock()
                                end
                            end
                        end

                        -- // RESTORED KATANA RAID ELEVATOR LOGIC //
                        if raidType == "Katana Raid" then
                            if checkAndInteractDialog() then
                                Autos.NoEnemyTimer = os.clock()
                            else
                                if (os.clock() - (Autos.NoEnemyTimer or 0)) > Autos.WaitThreshold then
                                    local zone, prompt = getElevatorTarget()

                                    if zone and prompt then
                                        local char = References.player.Character
                                        local root = char and char:FindFirstChild("HumanoidRootPart")
                                        if root then
                                            notify("Elevator Found! Traveling...", 5)
                                            root.CFrame = zone.CFrame + Vector3.new(0, 3, 0)
                                            task.wait(0.3)
                                            fireproximityprompt(prompt)
                                            notify("Loading Next Level...", 10)
                                            task.wait(12)
                                            Autos.NoEnemyTimer = os.clock()
                                        end
                                    end
                                end
                            end
                        end
                        -- // END RESTORED LOGIC //
                    end

                    if not Autos.IsAttaching and Autos.RaidEntitiesPath and myRoot then
                        local now = os.clock()
                        if (now - Autos.LastTeleportTime) >= 2 then
                            local closest = getClosestEntityNoHealth(Autos.RaidEntitiesPath, myRoot)
                            local pos = closest and getSafePosition(closest)
                            if pos then
                                myRoot.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
                                Autos.LastTeleportTime = now
                            end
                        end
                    end
                end
            else
                if Autos.IsAttaching then
                    AttachPanel.Stop()
                    Autos.IsAttaching = false
                end
                Autos.LastRaidTypeNotified = ""
            end
        end
    end)

    task.spawn(function()
        while true do
            task.wait(0.1)
            if isInRaid() then
                local world = Services.Workspace:FindFirstChild("World")
                local entities = world and world:FindFirstChild("Entities")
                local myEntity = entities and entities:FindFirstChild(References.player.Name)

                if myEntity and myEntity:FindFirstChild("ForceField") then
                    Services.VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
                    task.wait(0.1)
                    Services.VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
                    task.wait(1)
                end
            end
        end
    end)
end
