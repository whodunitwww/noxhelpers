return function(ctx)
    assert(type(ctx) == "table", "AutoRaid: context table required")

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

    local Remotes = RemoteFunction or (NetworkPath and NetworkPath:WaitForChild("RemoteFunction"))
    if not Remotes then
        error("AutoRaid: RemoteFunction missing")
    end

    local LoadedRemote = Services.ReplicatedStorage:WaitForChild("Files"):WaitForChild("Remotes"):WaitForChild("Loaded")

    local CONFIG_FOLDER_ROOT = "Cerberus"
    local CONFIG_FOLDER_PATH = References.gameDir or "Cerberus/Devil Hunter"
    local CONFIG_FILE_NAME = "RaidAccounts.json"
    local FULL_PATH = CONFIG_FOLDER_PATH .. "/" .. CONFIG_FILE_NAME

    local function normalizeName(name)
        return (tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function addUnique(list, name)
        local cleaned = normalizeName(name)
        if cleaned == "" then return false end
        for _, v in ipairs(list) do
            if v == cleaned then return false end
        end
        table.insert(list, cleaned)
        return true
    end

    local function LoadAccountConfig()
        if isfile(FULL_PATH) then
            local success, result = pcall(function()
                return Services.HttpService:JSONDecode(readfile(FULL_PATH))
            end)
            if success and type(result) == "table" then
                local mains = {}
                if type(result.Mains) == "table" then
                    for _, name in ipairs(result.Mains) do
                        addUnique(mains, name)
                    end
                end

                local mainName = type(result.Main) == "string" and result.Main or ""
                addUnique(mains, mainName)

                return {
                    Main = mainName,
                    Alt = type(result.Alt) == "string" and result.Alt or "",
                    Mains = mains
                }
            end
        end
        return { Main = "", Alt = "", Mains = {} }
    end

    local function UpdateAccountConfig()
        if not isfolder(CONFIG_FOLDER_ROOT) then makefolder(CONFIG_FOLDER_ROOT) end
        if not isfolder(CONFIG_FOLDER_PATH) then makefolder(CONFIG_FOLDER_PATH) end

        Autos.MainAccountName = Options.MainAccountName.Value
        Autos.AltAccountName = Options.AltAccountName.Value

        local data = {
            Main = Autos.MainAccountName,
            Alt = Autos.AltAccountName,
            Mains = Autos.MainAccountNames or {}
        }

        local success, err = pcall(function()
            writefile(FULL_PATH, Services.HttpService:JSONEncode(data))
        end)
        if not success then warn("Failed to save config: " .. tostring(err)) end
    end

    local savedData = LoadAccountConfig()
    Autos.MainAccountName = savedData.Main or Autos.MainAccountName or ""
    Autos.AltAccountName = savedData.Alt or Autos.AltAccountName or ""
    Autos.MainAccountNames = savedData.Mains or {}
    addUnique(Autos.MainAccountNames, Autos.MainAccountName)
    Autos.ZombieRaidActive = Autos.ZombieRaidActive or false
    Autos.ZombieRaidLeftLobby = Autos.ZombieRaidLeftLobby or false
    Autos.LastRaidTypeNotified = Autos.LastRaidTypeNotified or ""
    Autos.LastTeleportTime = Autos.LastTeleportTime or 0
    Autos.SelectedRaidStart = Autos.SelectedRaidStart or "Katana Man Raid"
    Autos.LastPlayGameFire = Autos.LastPlayGameFire or 0
    Autos.ZombieResetting = Autos.ZombieResetting or false
    Autos.ZombieResetCleanup = Autos.ZombieResetCleanup or nil
    Autos.ZombieEmptySince = Autos.ZombieEmptySince or nil
    Autos.ZombieEmptyLastAction = Autos.ZombieEmptyLastAction or 0
    Autos.ActiveMainName = Autos.ActiveMainName or nil
    Autos.SuppressAccountUpdate = Autos.SuppressAccountUpdate or false

    local RAID_START_OPTIONS = { "Katana Man Raid", "Zombie Raid" }
    local ZOMBIE_RAID_ENTRANCE_POS = Vector3.new(37.856991, 6.760758, -1441.734375)
    local ZOMBIE_VOID_POS = Vector3.new(0, -1000, 0)
    local ZOMBIE_EMPTY_POS = Vector3.new(-448.255676, 60.691345, 512.108337)

    local function notify(msg, duration)
        if Autos.LastNotif ~= msg then
            Library:Notify(msg, duration or 3)
            Autos.LastNotif = msg
            task.delay(5, function()
                if Autos.LastNotif == msg then Autos.LastNotif = "" end
            end)
        end
    end

    local function getRaidEntrancePos()
        if Autos.SelectedRaidStart == "Zombie Raid" then
            return ZOMBIE_RAID_ENTRANCE_POS
        end
        return Autos.RaidEntrancePos
    end

    local function addMainAccount(name)
        Autos.MainAccountNames = Autos.MainAccountNames or {}
        return addUnique(Autos.MainAccountNames, name)
    end

    local function getMainAccountListText()
        local mains = Autos.MainAccountNames or {}
        if #mains == 0 then return "None" end
        return table.concat(mains, ", ")
    end

    local function isMainAccount(name)
        if type(name) ~= "string" or name == "" then return false end
        for _, v in ipairs(Autos.MainAccountNames or {}) do
            if v == name then return true end
        end
        return false
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
        return string.find(lower, "zombie", 1, true) ~= nil
            and string.find(lower, "tank", 1, true) ~= nil
    end

    local function isSeaZombieName(name)
        if type(name) ~= "string" then return false end
        local lower = string.lower(name)
        return string.find(lower, "sea", 1, true) ~= nil
    end

    local function isLeechName(name)
        return type(name) == "string" and string.find(string.lower(name), "leech", 1, true) ~= nil
    end

    local function isDevilName(name)
        return type(name) == "string" and string.find(string.lower(name), "devil", 1, true) ~= nil
    end

    local function isTeleportOnlyTarget(name, raidType)
        if isLeechName(name) or isDevilName(name) then
            return true
        end
        return raidType == "Zombie Raid" and isSeaZombieName(name)
    end

    local function getZombieCount()
        local world = Services.Workspace:FindFirstChild("World")
        local entities = world and world:FindFirstChild("Entities")
        if not entities then return 0 end
        local types = {}
        for _, v in ipairs(entities:GetDescendants()) do
            if v:IsA("Model") and not Services.Players:GetPlayerFromCharacter(v) then
                if isZombieName(v.Name) then
                    local base = v.Name:match("^(.*)_[^_]+$") or v.Name
                    base = base:gsub("^%s+", ""):gsub("%s+$", "")
                    if base ~= "" then
                        types[base] = true
                    end
                end
            end
        end
        local count = 0
        for _ in pairs(types) do
            count = count + 1
        end
        return count
    end

    local function isKatanaRaid()
        local gui = References.player:FindFirstChild("PlayerGui")
        if gui then
            local hud = gui:FindFirstChild("HUD")
            local objectives = hud and hud:FindFirstChild("Objectives")
            if objectives and objectives:FindFirstChild("Yakuza Infiltration") then
                return true
            end
        end
        return false
    end

    local function isLobby()
        local map = Services.Workspace:FindFirstChild("Map")
        if map then return false end
        local gui = References.player:FindFirstChild("PlayerGui")
        if not gui then return true end
        return gui:FindFirstChild("EnterRaid") ~= nil
    end

    local function getRaidType()
        local zombieCount = getZombieCount()
        if zombieCount >= 10 then
            Autos.ZombieRaidActive = true
        end

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

    local function isInRaid()
        return getRaidType() ~= nil
    end

    local function isPlayerLoaded()
        if not game:IsLoaded() then return false end

        local char = References.player.Character
        if not char then return false end

        if not char:FindFirstChild("Humanoid") then return false end
        if not char:FindFirstChild("HumanoidRootPart") then return false end
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

        if Autos.IsAttaching then
            AttachPanel.Stop()
            Autos.IsAttaching = false
        end

        local startChar = References.player.Character

        task.spawn(function()
            while Autos.ZombieResetting do
                local char = References.player.Character
                local hum = char and char:FindFirstChild("Humanoid")
                local root = char and char:FindFirstChild("HumanoidRootPart")

                if not char or not char.Parent then
                    break
                end
                if startChar and char ~= startChar then
                    break
                end
                if hum and hum.Health <= 0 then
                    break
                end

                if Autos.ZombieResetCleanup then
                    pcall(Autos.ZombieResetCleanup)
                    Autos.ZombieResetCleanup = nil
                end

                if root then
                    if MoveToPos then
                        Autos.ZombieResetCleanup = MoveToPos(ZOMBIE_VOID_POS, 5000)
                    else
                        root.CFrame = CFrame.new(ZOMBIE_VOID_POS)
                        root.AssemblyLinearVelocity = Vector3.zero
                        root.AssemblyAngularVelocity = Vector3.zero
                    end
                end
                task.wait(1)
            end
            if Autos.ZombieResetCleanup then
                pcall(Autos.ZombieResetCleanup)
                Autos.ZombieResetCleanup = nil
            end

            local currentChar = References.player.Character
            if not currentChar or currentChar == startChar then
                currentChar = References.player.CharacterAdded:Wait()
            end
            if currentChar then
                currentChar:WaitForChild("HumanoidRootPart", 10)
                currentChar:WaitForChild("Humanoid", 10)
            end
            Autos.ZombieResetting = false
        end)
    end

    local function getSafePosition(instance)
        if not instance then return nil end
        if instance:IsA("BasePart") then
            return instance.Position
        elseif instance:IsA("Model") then
            return instance:GetPivot().Position
        end
        return nil
    end

    local function clickGuiButton(btn)
        if not btn or not btn.Visible then return false end

        local pos = btn.AbsolutePosition
        local size = btn.AbsoluteSize
        local centerX = pos.X + (size.X / 2)
        local centerY = pos.Y + (size.Y / 2)

        Services.VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, true, game, 1)
        task.wait(0.05)
        Services.VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, false, game, 1)

        Services.GuiService.SelectedObject = btn
        Services.VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
        task.wait(0.05)
        Services.VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)

        task.wait(0.1)
        Services.GuiService.SelectedObject = nil
        return true
    end

    local function clickRaidButton()
        local gui = References.player:WaitForChild("PlayerGui", 5)
        local enterRaid = gui and gui:WaitForChild("EnterRaid", 5)

        if not enterRaid then return false end

        local enterFrame = enterRaid:FindFirstChild("Frame")
        local btn = enterFrame and enterFrame:FindFirstChild("Enter")

        return clickGuiButton(btn)
    end

    local function hasParty()
        local hud = References.player.PlayerGui:FindFirstChild("HUD")
        if hud then
            local list = hud.Party.Main.Menu.List
            for _, v in ipairs(list:GetChildren()) do
                if v:IsA("Frame") then return true end
            end
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

    local AutoRaidGroup = Tabs.Auto:AddLeftGroupbox("Auto Raid", "shield")

    local InfoLabel = AutoRaidGroup:AddLabel("Info: Requires AutoEquip, AutoAttack (M1), and InstaKill enabled.", true)
    AutoRaidGroup:AddDivider()

    local StatusLabel = AutoRaidGroup:AddLabel("Status: Checking...", true)
    task.spawn(function()
        while true do
            local raidType = getRaidType()
            if raidType then
                StatusLabel:SetText("Status: Raid (Active - " .. raidType .. ")", true)
            else
                StatusLabel:SetText("Status: Lobby")
            end
            task.wait(1)
        end
    end)

    AutoRaidGroup:AddToggle("AutoJoinRaid", { Text = "Auto Join Raid", Default = false })
    AutoRaidGroup:AddToggle("InfiniteRaid", { Text = "Infinite Raid", Default = false, Tooltip = "Requires Main + Alt setup." })
    AutoRaidGroup:AddDropdown("RaidStartSelect", {
        Text = "Raid Start",
        Values = RAID_START_OPTIONS,
        Default = Autos.SelectedRaidStart,
        Multi = false,
    })

    AutoRaidGroup:AddInput("MainAccountName", {
        Default = Autos.MainAccountName,
        Numeric = false, Finished = true,
        Text = "Main Username", Tooltip = "Clearing Account", Placeholder = "Username...",
    })

    AutoRaidGroup:AddInput("AltAccountName", {
        Default = Autos.AltAccountName,
        Numeric = false, Finished = true,
        Text = "Alt Username", Tooltip = "Raid Starter", Placeholder = "Username...",
    })

    AutoRaidGroup:AddButton("Clear Accounts", function()
        Autos.SuppressAccountUpdate = true
        Autos.MainAccountName = ""
        Autos.AltAccountName = ""
        Autos.MainAccountNames = {}
        Autos.ActiveMainName = nil
        if Options.MainAccountName and Options.MainAccountName.SetValue then
            Options.MainAccountName:SetValue("")
        end
        if Options.AltAccountName and Options.AltAccountName.SetValue then
            Options.AltAccountName:SetValue("")
        end
        Autos.SuppressAccountUpdate = false
        UpdateAccountConfig()
        notify("Cleared raid accounts.", 3)
    end)

    AutoRaidGroup:AddDivider()
    AutoRaidGroup:AddToggle("AutoClearRaid", { Text = "Auto Clear Raid", Default = false })
    AutoRaidGroup:AddToggle("Devil_ForceLoaded", { Text = "Force Load", Default = false })

    local function updateRaidInfoLabel()
        if Autos.SelectedRaidStart == "Zombie Raid" then
            InfoLabel:SetText("Info: Zombie Raid - Do NOT use InstaKill. Requires AutoEquip and AutoAttack (M1)")
        else
            InfoLabel:SetText("Info: Requires AutoEquip, AutoAttack (M1), and InstaKill enabled.")
        end
    end

    Options.AltAccountName:OnChanged(function()
        if Autos.SuppressAccountUpdate then return end
        UpdateAccountConfig()
    end)
    Options.RaidStartSelect:OnChanged(function()
        Autos.SelectedRaidStart = Options.RaidStartSelect.Value
        updateRaidInfoLabel()
    end)

    Options.MainAccountName:OnChanged(function()
        if Autos.SuppressAccountUpdate then return end
        Autos.MainAccountName = Options.MainAccountName.Value
        if addMainAccount(Autos.MainAccountName) then
            notify("Added main: " .. Autos.MainAccountName .. "\nMains: " .. getMainAccountListText(), 4)
        end
        UpdateAccountConfig()
    end)

    updateRaidInfoLabel()

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
        pcall(function()
            Services.GuiService.GuiNavigationEnabled = true
            task.wait(0.05)
            Services.GuiService.SelectedObject = btn
            task.wait(0.05)
            if getconnections then
                for _, c in ipairs(getconnections(btn.Activated)) do pcall(function() c:Fire() end) end
                for _, c in ipairs(getconnections(btn.MouseButton1Click)) do pcall(function() c:Fire() end) end
            end
            pcall(function() btn:Activate() end)
        end)
    end

    task.spawn(function()
        while true do
            task.wait(0.5)
            if Toggles.Devil_ForceLoaded and Toggles.Devil_ForceLoaded.Value then
                local skipBtn = getSkipButton()
                if skipBtn and skipBtn.Visible then
                    clickSkipViaGuiNav(skipBtn)
                end
                local playBtn = getPlayGameButton()
                if playBtn and playBtn.Visible then
                    local now = os.clock()
                    if (now - Autos.LastPlayGameFire) >= 10 then
                        LoadedRemote:FireServer(1)
                        Autos.LastPlayGameFire = now
                    end
                end
                if not isPlayerLoaded() then
                    LoadedRemote:FireServer()
                end
            end
        end
    end)

    task.spawn(function()
        while true do
            task.wait(1)

            pcall(function()
                if not isInRaid() and Toggles.AutoJoinRaid.Value then
                    Autos.MainAccountName = Options.MainAccountName.Value
                    Autos.AltAccountName = Options.AltAccountName.Value

                    local myName = References.player.Name
                    local char = References.player.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")

                    if Toggles.InfiniteRaid.Value then
                        if myName == Autos.AltAccountName then
                            local mainName, mainPlayer = getActiveMainPlayer()

                            if not mainPlayer then
                                if os.clock() % 5 < 1 then notify("Waiting for Main...", 2) end
                            else
                                if not hasParty() then
                                    notify("Creating Party...", 2)
                                    Remotes:InvokeServer("RequestCreateParty")
                                    task.wait(1)
                                end

                                if not isPlayerInParty(mainName) then
                                    if (os.clock() - Autos.LastInviteTime) > 15 then
                                        notify("Inviting Main...", 2)
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

                                        local uiFound = false
                                        for _ = 1, 10 do
                                            local pg = References.player:FindFirstChild("PlayerGui")
                                            if pg and pg:FindFirstChild("EnterRaid") and pg.EnterRaid:FindFirstChild("Frame") and pg.EnterRaid.Frame.Visible then
                                                uiFound = true
                                                break
                                            end

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

                                        if uiFound then
                                            for _ = 1, 3 do
                                                if not clickRaidButton() then break end
                                                task.wait(0.5)
                                            end
                                        end
                                    end
                                end
                            end

                        elseif isMainAccount(myName) then
                            local activeName = getActiveMainPlayer()
                            if activeName and activeName ~= myName then
                                if os.clock() % 5 < 1 then
                                    notify("Waiting for active main: " .. activeName .. "...", 2)
                                end
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
                                notify("Waiting for Alt...", 2)
                            end
                        end

                    else
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
                                            v.HoldDuration = 0
                                            v.RequiresLineOfSight = false
                                            fireproximityprompt(v)
                                            break
                                        end
                                    end
                                end
                                task.wait(0.5)
                            end
                            if uiFound then
                                for _ = 1, 3 do
                                    if not clickRaidButton() then break end
                                    task.wait(0.5)
                                end
                            end
                        end
                    end
                end
            end)
        end
    end)

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
                                    notify("Zombie Raid: Entities empty, waiting 15s...", 3)
                                end
                                if not Autos.ZombieResetting
                                    and (os.clock() - Autos.ZombieEmptySince) >= 15
                                    and (os.clock() - Autos.ZombieEmptyLastAction) >= 10 then
                                    local root = References.player.Character and References.player.Character:FindFirstChild("HumanoidRootPart")
                                    if root then
                                        root.CFrame = CFrame.new(ZOMBIE_EMPTY_POS + Vector3.new(0, 3, 0))
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

                        if raidType == "Katana Raid" then
                            if checkAndInteractDialog() then
                                Autos.NoEnemyTimer = os.clock()
                            else
                                if (os.clock() - Autos.NoEnemyTimer) > Autos.WaitThreshold then
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
