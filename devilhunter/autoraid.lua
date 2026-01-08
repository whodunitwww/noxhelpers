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

    local function LoadAccountConfig()
        if isfile(FULL_PATH) then
            local success, result = pcall(function()
                return Services.HttpService:JSONDecode(readfile(FULL_PATH))
            end)
            if success and result then return result end
        end
        return { Main = "", Alt = "" }
    end

    local function UpdateAccountConfig()
        if not isfolder(CONFIG_FOLDER_ROOT) then makefolder(CONFIG_FOLDER_ROOT) end
        if not isfolder(CONFIG_FOLDER_PATH) then makefolder(CONFIG_FOLDER_PATH) end

        Autos.MainAccountName = Options.MainAccountName.Value
        Autos.AltAccountName = Options.AltAccountName.Value

        local data = {
            Main = Autos.MainAccountName,
            Alt = Autos.AltAccountName
        }

        local success, err = pcall(function()
            writefile(FULL_PATH, Services.HttpService:JSONEncode(data))
        end)
        if not success then warn("Failed to save config: " .. tostring(err)) end
    end

    local savedData = LoadAccountConfig()
    Autos.MainAccountName = savedData.Main or Autos.MainAccountName or ""
    Autos.AltAccountName = savedData.Alt or Autos.AltAccountName or ""
    Autos.ZombieRaidActive = Autos.ZombieRaidActive or false
    Autos.ZombieRaidLeftLobby = Autos.ZombieRaidLeftLobby or false
    Autos.LastRaidTypeNotified = Autos.LastRaidTypeNotified or ""
    Autos.LastTeleportTime = Autos.LastTeleportTime or 0
    Autos.DevilZombieTarget = Autos.DevilZombieTarget or nil
    Autos.LastDevilTeleportTime = Autos.LastDevilTeleportTime or 0
    Autos.SelectedRaidStart = Autos.SelectedRaidStart or "Katana Man Raid"

    local RAID_START_OPTIONS = { "Katana Man Raid", "Zombie Raid" }
    local ZOMBIE_RAID_ENTRANCE_POS = Vector3.new(37.856991, 6.760758, -1441.734375)

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

    local function isZombieName(name)
        return type(name) == "string" and string.find(string.lower(name), "zombie", 1, true) ~= nil
    end

    local function isDevilZombieName(name)
        if type(name) ~= "string" then return false end
        local lower = string.lower(name)
        return string.find(lower, "zombie", 1, true) ~= nil
            and string.find(lower, "devil", 1, true) ~= nil
    end

    local function hasZombieEntity()
        local world = Services.Workspace:FindFirstChild("World")
        local entities = world and world:FindFirstChild("Entities")
        if not entities then return false end
        for _, v in ipairs(entities:GetDescendants()) do
            if isZombieName(v.Name) then
                return true
            end
        end
        return false
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
        local zombieNow = hasZombieEntity()
        if zombieNow then
            Autos.ZombieRaidActive = true
        end

        if Autos.ZombieRaidActive then
            if not Autos.ZombieRaidLeftLobby and not isLobby() then
                Autos.ZombieRaidLeftLobby = true
            end
            if Autos.ZombieRaidLeftLobby and isLobby() and not zombieNow then
                Autos.ZombieRaidActive = false
                Autos.ZombieRaidLeftLobby = false
            end
        end

        if Autos.ZombieRaidActive then
            Autos.RaidType = "Zombie Raid"
            return Autos.RaidType
        end

        if isKatanaRaid() then
            Autos.RaidType = "Katana Raid"
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

    local function getSafePosition(instance)
        if not instance then return nil end
        if instance:IsA("BasePart") then
            return instance.Position
        elseif instance:IsA("Model") then
            return instance:GetPivot().Position
        end
        return nil
    end

    local function clickRaidButton()
        local gui = References.player:WaitForChild("PlayerGui", 5)
        local enterRaid = gui and gui:WaitForChild("EnterRaid", 5)

        if not enterRaid then return false end

        local enterFrame = enterRaid:FindFirstChild("Frame")
        local btn = enterFrame and enterFrame:FindFirstChild("Enter")

        if btn and btn.Visible then
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
        return false
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

    AutoRaidGroup:AddLabel("Info: Requires AutoEquip, AutoAttack (M1), and InstaKill enabled.", true)
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

    AutoRaidGroup:AddDivider()
    AutoRaidGroup:AddToggle("AutoClearRaid", { Text = "Auto Clear Raid", Default = false })
    AutoRaidGroup:AddToggle("Devil_ForceLoaded", { Text = "Force Load", Default = false })

    Options.MainAccountName:OnChanged(function() UpdateAccountConfig() end)
    Options.AltAccountName:OnChanged(function() UpdateAccountConfig() end)
    Options.RaidStartSelect:OnChanged(function()
        Autos.SelectedRaidStart = Options.RaidStartSelect.Value
    end)

    local function getSkipButton()
        local pg = References.player:FindFirstChild("PlayerGui")
        local ls = pg and pg:FindFirstChild("LoadScreen")
        local skip = ls and ls:FindFirstChild("Skip")
        return (skip and skip:IsA("GuiButton")) and skip or nil
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
                            local mainPlayer = Services.Players:FindFirstChild(Autos.MainAccountName)

                            if not mainPlayer then
                                if os.clock() % 5 < 1 then notify("Waiting for Main...", 2) end
                            else
                                if not hasParty() then
                                    notify("Creating Party...", 2)
                                    Remotes:InvokeServer("RequestCreateParty")
                                    task.wait(1)
                                end

                                if not isPlayerInParty(Autos.MainAccountName) then
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

                        elseif myName == Autos.MainAccountName then
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

        local function findDevilZombie(entities)
            for _, v in ipairs(entities:GetDescendants()) do
                if isDevilZombieName(v.Name) then
                    return v
                end
            end
            return nil
        end

        local TARGET_PLACE_ID = 131079272918660

        local function rejoinServer()
            pcall(function()
                Services.TeleportService:Teleport(TARGET_PLACE_ID, References.player)
            end)
        end

        while true do
            task.wait(0.5)

            local raidType = getRaidType()
            if Toggles.AutoClearRaid.Value and raidType then
                if Autos.LastRaidTypeNotified ~= raidType then
                    notify("AutoClear: " .. raidType .. " detected", 3)
                    Autos.LastRaidTypeNotified = raidType
                end

                local world = Services.Workspace:FindFirstChild("World")
                Autos.RaidEntitiesPath = world and world:FindFirstChild("Entities")

                local target = nil
                local shortestDist = math.huge
                local myRoot = References.player.Character and References.player.Character:FindFirstChild("HumanoidRootPart")

                if raidType == "Zombie Raid" and Autos.RaidEntitiesPath then
                    if Autos.DevilZombieTarget then
                        if not Autos.DevilZombieTarget:IsDescendantOf(Autos.RaidEntitiesPath) then
                            Autos.DevilZombieTarget = nil
                            Autos.LastDevilTeleportTime = 0
                            notify("Devil zombie gone. Rejoining...", 3)
                            rejoinServer()
                        end
                    else
                        Autos.DevilZombieTarget = findDevilZombie(Autos.RaidEntitiesPath)
                        if Autos.DevilZombieTarget then
                            Autos.LastDevilTeleportTime = 0
                        end
                    end
                end

                if Autos.DevilZombieTarget then
                    if Autos.IsAttaching then
                        AttachPanel.Stop()
                        Autos.IsAttaching = false
                    end

                    if myRoot then
                        local now = os.clock()
                        if (now - Autos.LastDevilTeleportTime) >= 10 then
                            local pos = getSafePosition(Autos.DevilZombieTarget)
                            if pos then
                                myRoot.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
                                Autos.LastDevilTeleportTime = now
                            end
                        end
                    end
                else
                    if myRoot and Autos.RaidEntitiesPath then
                        for _, v in ipairs(Autos.RaidEntitiesPath:GetChildren()) do
                            local hum = v:FindFirstChild("Humanoid")
                            local root = v:FindFirstChild("HumanoidRootPart")
                            if hum and root and hum.Health > 0 and v ~= References.player.Character then
                                local dist = (root.Position - myRoot.Position).Magnitude
                                if dist < shortestDist then
                                    shortestDist = dist
                                    target = v
                                end
                            end
                        end
                    end

                    if target then
                        Autos.NoEnemyTimer = os.clock()

                        AttachPanel.SetMode("Behind")
                        AttachPanel.SetHorizDist(4)
                        AttachPanel.SetYOffset(0)
                        AttachPanel.EnableDodge(false)

                        if AttachPanel.GetTarget() ~= target or not Autos.IsAttaching then
                            AttachPanel.SetTarget(target)
                            AttachPanel.State.running = true
                            AttachPanel.GoApproach()
                            Autos.IsAttaching = true
                        end

                    else
                        if Autos.IsAttaching then
                            AttachPanel.Stop()
                            Autos.IsAttaching = false
                            if raidType == "Katana Raid" then
                                notify("Room Clear. Searching...", 3)
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
                Autos.DevilZombieTarget = nil
                Autos.LastRaidTypeNotified = ""
            end
        end
    end)

    task.spawn(function()
        while true do
            task.wait(0.1)
            if isInRaid() and not Autos.DevilZombieTarget then
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
