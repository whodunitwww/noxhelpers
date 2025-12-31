return function(Services, Tabs, References, Toggles, Options, Library, Shared)
    -- ============================
    --   SERVICE SHORTCUTS
    -- ============================
    local Players           = Services.Players           or game:GetService("Players")
    local RunService        = Services.RunService        or game:GetService("RunService")
    local UIS               = Services.UserInputService  or game:GetService("UserInputService")
    local HttpService       = Services.HttpService       or game:GetService("HttpService")
    local Workspace         = Services.Workspace         or game:GetService("Workspace")
    local ReplicatedStorage = Services.ReplicatedStorage or game:GetService("ReplicatedStorage")
    local VIM               = Services.VirtualInputManager or game:GetService("VirtualInputManager")
    local CoreGui           = Services.CoreGui           or game:GetService("CoreGui")

    -- ============================
    --   EXTERNAL HELPERS
    -- ============================
    -- Injected from loader via Shared, with soft fallbacks if you ever move them
    local AttachPanel  = Shared and Shared.AttachPanel  or getgenv().AttachPanel
    local MoveToPos    = Shared and Shared.MoveToPos    or getgenv().MoveToPos
    local SecureTravel = Shared and Shared.SecureTravel or getgenv().SecureTravel

    -- Ensure AutoFarm table exists and prefer injected one
    getgenv().AutoFarm = getgenv().AutoFarm or { Active = false }
    local AutoFarm = (Shared and Shared.AutoFarm) or getgenv().AutoFarm

    local BOSS_PLACE_ID = 89413197677760

    -- ============================
    --   CONFIG PATHS / FOLDERS
    -- ============================
    local GAME_DIR = (References and References.gameDir) or "Cerberus/GhoulRE"

    local function ensureDir(path)
        if typeof(isfolder) ~= "function" or typeof(makefolder) ~= "function" then return end
        local parts = string.split(path, "/")
        local accum = ""
        for i, part in ipairs(parts) do
            accum = (i == 1) and part or (accum .. "/" .. part)
            if not isfolder(accum) then
                pcall(makefolder, accum)
            end
        end
    end

    ensureDir(GAME_DIR)

    local PARTY_FILE  = GAME_DIR .. "/AutoBossParty.json"
    local REPLAY_FILE = GAME_DIR .. "/AutoBossReplay.json"

    -- ============================
    --        UI GROUPBOX
    -- ============================
    local AutoBossGroupbox = Tabs.Auto:AddRightGroupbox("Auto Boss", "robot")

    AutoBossGroupbox:AddLabel(
        "Make sure you configure the auto attack, auto equip, and instakill settings as well (main tab). You can instakill the boss after 4 mins.",
        true
    )

    local BossState = {
        Connections        = {},
        IsVoiding          = false,
        VoidTriggered      = false,
        JoiningDebounce    = false,
        ActiveTarget       = nil,
        LastReplayClick    = 0,
        WaitingForClickSet = false,
        CurrentYOffset     = 20,
        CurrentHorizOffset = 0,

        PartyConfig = {
            PartyEnabled    = false,
            HostName        = "",
            MemberNames     = {}, -- { "User1", "User2", ... }
            MembersRequired = 1,
        },

        ReplayConfig = {
            ScaleX = 0.0252,
            ScaleY = 0.9173,
        },

        EffectiveMode   = "Solo", -- "Solo" | "Host" | "Member"
        QDidForThisLife = false,
    }

    ------------------------------------------------------
    -- Party mode resolver
    ------------------------------------------------------
    local function ResolvePartyMode()
        if not BossState.PartyConfig.PartyEnabled then
            BossState.EffectiveMode = "Solo"
            return
        end

        local lp = Players.LocalPlayer
        if not lp then
            BossState.EffectiveMode = "Solo"
            return
        end

        local myName = string.lower(lp.Name)
        local host   = string.lower(BossState.PartyConfig.HostName or "")

        if host ~= "" and myName == host then
            BossState.EffectiveMode = "Host"
            return
        end

        for _, name in ipairs(BossState.PartyConfig.MemberNames or {}) do
            if type(name) == "string" and name ~= "" then
                if myName == string.lower(name) then
                    BossState.EffectiveMode = "Member"
                    return
                end
            end
        end

        BossState.EffectiveMode = "Solo"
    end

    ------------------------------------------------------
    -- Config load/save
    ------------------------------------------------------
    local function SavePartyConfig()
        ensureDir(GAME_DIR)
        local data = {
            PartyEnabled    = BossState.PartyConfig.PartyEnabled,
            HostName        = BossState.PartyConfig.HostName,
            MemberNames     = BossState.PartyConfig.MemberNames,
            MembersRequired = BossState.PartyConfig.MembersRequired,
        }
        writefile(PARTY_FILE, HttpService:JSONEncode(data))
    end

    local function SaveReplayConfig()
        ensureDir(GAME_DIR)
        writefile(REPLAY_FILE, HttpService:JSONEncode(BossState.ReplayConfig))
    end

    local function LoadConfigs()
        if isfile(PARTY_FILE) then
            local ok, data = pcall(function()
                return HttpService:JSONDecode(readfile(PARTY_FILE))
            end)
            if ok and type(data) == "table" then
                BossState.PartyConfig.PartyEnabled    = data.PartyEnabled    or false

                -- HostName: load and trim
                local hostFromFile = ""
                if type(data.HostName) == "string" then
                    hostFromFile = data.HostName
                end
                hostFromFile = hostFromFile:gsub("^%s+", ""):gsub("%s+$", "")
                BossState.PartyConfig.HostName = hostFromFile

                BossState.PartyConfig.MemberNames     = data.MemberNames     or {}
                BossState.PartyConfig.MembersRequired = data.MembersRequired or BossState.PartyConfig.MembersRequired

                -- Backwards compat with old Whitelist field
                if (#BossState.PartyConfig.MemberNames == 0) and type(data.Whitelist) == "table" then
                    BossState.PartyConfig.MemberNames = data.Whitelist
                end
            end
        end

        if isfile(REPLAY_FILE) then
            local ok, data = pcall(function()
                return HttpService:JSONDecode(readfile(REPLAY_FILE))
            end)
            if ok and type(data) == "table" then
                BossState.ReplayConfig.ScaleX = data.ScaleX or 0.0252
                BossState.ReplayConfig.ScaleY = data.ScaleY or 0.9173
            end
        end

        ResolvePartyMode()
    end

    LoadConfigs()

    ------------------------------------------------------
    -- Q key helper
    ------------------------------------------------------
    local function FireQOnce()
        VIM:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
    end

    local function OnCharacterArriveAtBoss(char)
        BossState.QDidForThisLife = false

        if not Toggles.AutoBoss_Integrated
            or not Toggles.AutoBoss_Integrated.Value then
            return
        end

        if game.PlaceId ~= BOSS_PLACE_ID then
            return
        end

        task.spawn(function()
            task.wait(0.5) -- allow full spawn
            if not BossState.QDidForThisLife then
                FireQOnce()
                BossState.QDidForThisLife = true
            end
        end)
    end

    ------------------------------------------------------
    -- UI
    ------------------------------------------------------
    local BossDropdown = AutoBossGroupbox:AddDropdown("BossSelect", {
        Values  = { "Noro", "Eto", "Tatara", "Kuzen" },
        Default = 1,
        Multi   = false,
        Text    = "Select Boss",
    })

    AutoBossGroupbox:AddSlider("BossYOffset", {
        Text    = "Vertical Offset",
        Default = BossState.CurrentYOffset,
        Min     = -20,
        Max     = 50,
        Rounding = 1,
        Suffix  = " studs",
        Callback = function(val)
            BossState.CurrentYOffset = val
            if AttachPanel then
                AttachPanel.SetYOffset(val)
            end
        end
    })

    AutoBossGroupbox:AddSlider("BossHorizOffset", {
        Text    = "Horizontal Offset",
        Default = BossState.CurrentHorizOffset,
        Min     = -30,
        Max     = 30,
        Rounding = 1,
        Suffix  = " studs",
        Callback = function(val)
            BossState.CurrentHorizOffset = val
            if AttachPanel then
                AttachPanel.SetHorizDist(val)
            end
        end
    })

    AutoBossGroupbox:AddDivider()

    -- Party UI
    local PartyToggle = AutoBossGroupbox:AddToggle("AutoBoss_PartyEnabled", {
        Text    = "Party Mode",
        Default = BossState.PartyConfig.PartyEnabled,
    })

    local HostInput = AutoBossGroupbox:AddInput("AutoBoss_HostName", {
        Text        = "Host Username",
        Default     = BossState.PartyConfig.HostName or "",
        Placeholder = "Exact Roblox username",
        Finished    = true,
        Callback    = function(val)
            -- normalize + trim
            local host = tostring(val or "")
            host = host:gsub("^%s+", ""):gsub("%s+$", "")
            BossState.PartyConfig.HostName = host
            ResolvePartyMode()
            SavePartyConfig()
        end
    })

    -- Label showing current members
    local MemberListLabel = AutoBossGroupbox:AddLabel("Members: (none)", true)

    local function RefreshMemberLabel()
        if not MemberListLabel then return end
        local list = BossState.PartyConfig.MemberNames or {}
        if #list == 0 then
            MemberListLabel:SetText("Members: (none)")
        else
            MemberListLabel:SetText("Members: " .. table.concat(list, ", "))
        end
    end

    RefreshMemberLabel()

    -- Input to add a single member at a time; Enter commits + clears
    AutoBossGroupbox:AddInput("AutoBoss_AddMember", {
        Text        = "Add Member",
        Default     = "",
        Placeholder = "Username (press Enter)",
        Finished    = true,
        Callback    = function(val)
            local name = tostring(val or "")
            name = name:gsub("^%s+", ""):gsub("%s+$", "")

            if name == "" then
                return
            end

            -- check duplicate (case-insensitive)
            for _, existing in ipairs(BossState.PartyConfig.MemberNames or {}) do
                if string.lower(existing) == string.lower(name) then
                    Library:Notify(name .. " is already in the member list.", 3)
                    -- clear input anyway
                    if Options.AutoBoss_AddMember then
                        Options.AutoBoss_AddMember:SetValue("")
                    end
                    return
                end
            end

            table.insert(BossState.PartyConfig.MemberNames, name)
            ResolvePartyMode()
            SavePartyConfig()
            RefreshMemberLabel()

            -- clear input after commit
            if Options.AutoBoss_AddMember then
                Options.AutoBoss_AddMember:SetValue("")
            end

            Library:Notify("Added " .. name .. " to party members.", 3)
        end
    })

    local MembersSlider = AutoBossGroupbox:AddSlider("ReqMembers", {
        Text    = "Required Members (Host Only)",
        Default = BossState.PartyConfig.MembersRequired or 1,
        Min     = 1,
        Max     = 5,
        Rounding = 0,
        Callback = function(val)
            BossState.PartyConfig.MembersRequired = val
            SavePartyConfig()
        end
    })

    -- ===== Extra config buttons =====

    AutoBossGroupbox:AddButton({
        Text = "Clear Party Config",
        Func = function()
            BossState.PartyConfig.PartyEnabled    = false
            BossState.PartyConfig.HostName        = ""
            BossState.PartyConfig.MemberNames     = {}
            BossState.PartyConfig.MembersRequired = 1

            ResolvePartyMode()
            SavePartyConfig()
            RefreshMemberLabel()

            if Toggles.AutoBoss_PartyEnabled then
                Toggles.AutoBoss_PartyEnabled:SetValue(false)
            end
            if Options.AutoBoss_HostName then
                Options.AutoBoss_HostName:SetValue("")
            end
            if Options.AutoBoss_AddMember then
                Options.AutoBoss_AddMember:SetValue("")
            end
            if MembersSlider and MembersSlider.SetValue then
                MembersSlider:SetValue(1)
            end

            Library:Notify("Auto Boss party config fully cleared.", 3)
        end
    })

    AutoBossGroupbox:AddDivider()

    AutoBossGroupbox:AddToggle("AutoBoss_SkipCutscene", {
        Text    = "Auto Skip Cutscene",
        Default = true,
    })

    AutoBossGroupbox:AddToggle("AutoBoss_AutoReplay", {
        Text    = "Auto Replay",
        Default = false,
    })

    AutoBossGroupbox:AddButton({
        Text = "Update Replay Button Pos",
        Func = function()
            BossState.WaitingForClickSet = true
            Library:Notify("Click anywhere on the screen to set Replay position...", 5)
        end
    })

    PartyToggle:OnChanged(function(val)
        BossState.PartyConfig.PartyEnabled = val and true or false
        ResolvePartyMode()
        SavePartyConfig()
    end)

    ------------------------------------------------------
    -- Replay helpers
    ------------------------------------------------------
    UIS.InputBegan:Connect(function(input, gameProcessed)
        if BossState.WaitingForClickSet
            and input.UserInputType == Enum.UserInputType.MouseButton1 then

            BossState.WaitingForClickSet = false
            local mousePos   = UIS:GetMouseLocation()
            local screenSize = Workspace.CurrentCamera.ViewportSize

            BossState.ReplayConfig.ScaleX = mousePos.X / screenSize.X
            BossState.ReplayConfig.ScaleY = mousePos.Y / screenSize.Y

            SaveReplayConfig()
            Library:Notify(string.format(
                "Replay Pos Saved: %.4f, %.4f",
                BossState.ReplayConfig.ScaleX,
                BossState.ReplayConfig.ScaleY
            ), 3)
        end
    end)

    local function VisualizeClick(x, y)
        local gui = Instance.new("ScreenGui")
        gui.Name = "AutoBossDebugVisual"
        gui.Parent = CoreGui

        local dot = Instance.new("Frame")
        dot.Size = UDim2.new(0, 10, 0, 10)
        dot.Position = UDim2.new(0, x - 5, 0, y - 5)
        dot.BackgroundColor3 = Color3.new(1, 0, 0)
        dot.BorderSizePixel = 0
        dot.Parent = gui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = dot

        task.delay(0.5, function()
            gui:Destroy()
        end)
    end

    local function PerformReplayClick()
        local screenSize = Workspace.CurrentCamera.ViewportSize
        local absX = screenSize.X * BossState.ReplayConfig.ScaleX
        local absY = screenSize.Y * BossState.ReplayConfig.ScaleY

        VisualizeClick(absX, absY)
        VIM:SendMouseButtonEvent(absX, absY, 0, true, game, 1)
        task.wait(0.05)
        VIM:SendMouseButtonEvent(absX, absY, 0, false, game, 1)
    end

    ------------------------------------------------------
    -- Core helpers
    ------------------------------------------------------
    local function StopAutoBoss()
        for _, conn in pairs(BossState.Connections) do
            if conn then
                conn:Disconnect()
            end
        end
        table.clear(BossState.Connections)

        BossState.IsVoiding        = false
        BossState.VoidTriggered    = false
        BossState.ActiveTarget     = nil
        BossState.QDidForThisLife  = false

        if AutoFarm then
            AutoFarm.Active = false
        end
        if AttachPanel and AttachPanel.Stop then
            AttachPanel.Stop()
        end
    end

    local function GetPartyMemberCount()
        local gui = Players.LocalPlayer:WaitForChild("PlayerGui", 5)
        local membersFolder =
            gui
            and gui:FindFirstChild("Party")
            and gui.Party:FindFirstChild("Members")
            and gui.Party.Members:FindFirstChild("Players")

        if not membersFolder then
            return 0
        end

        local count = 0
        for _, v in ipairs(membersFolder:GetChildren()) do
            if v:IsA("ImageButton") then
                count += 1
            end
        end
        return count
    end

    local function HandlePartyLogic()
        if not BossState.PartyConfig.PartyEnabled then
            return true
        end

        local mode   = BossState.EffectiveMode or "Solo"
        local Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Party")

        if mode == "Host" then
            if GetPartyMemberCount() == 0 then
                Remote:FireServer("Create")
                task.wait(1)
            end

            for _, username in ipairs(BossState.PartyConfig.MemberNames or {}) do
                local target = Players:FindFirstChild(username)
                if target then
                    Remote:FireServer("Invite", { target })
                end
            end

            local current = GetPartyMemberCount()
            if current >= BossState.PartyConfig.MembersRequired then
                return true
            else
                Library:Notify(
                    ("Waiting for party... (%d/%d)")
                        :format(current, BossState.PartyConfig.MembersRequired),
                    1
                )
                return false
            end

        elseif mode == "Member" then
            local gui = Players.LocalPlayer:WaitForChild("PlayerGui", 5)
            local inviteFolder =
                gui
                and gui:FindFirstChild("Party")
                and gui.Party:FindFirstChild("Invites")

            if inviteFolder then
                local expectedHost      = BossState.PartyConfig.HostName
                local expectedHostLower = expectedHost ~= "" and string.lower(expectedHost) or nil

                for _, inviteFrame in ipairs(inviteFolder:GetChildren()) do
                    local label =
                        inviteFrame:FindFirstChild("TextLabel")
                        or inviteFrame:FindFirstChildWhichIsA("TextLabel", true)

                    if label and label.Text then
                        local textLower = string.lower(label.Text)

                        if expectedHostLower and not string.find(textLower, expectedHostLower, 1, true) then
                            -- skip unmatched host invites
                        else
                            Remote:FireServer("Join", { label.Text })
                            Library:Notify("Accepting invite: " .. label.Text, 3)
                            task.wait(1)
                        end
                    end
                end
            end

            Library:Notify("Waiting for Host to start...", 1)
            return false
        end

        return true -- Solo/default
    end

    local function AttemptJoinBoss()
        if BossState.JoiningDebounce then
            return
        end
        BossState.JoiningDebounce = true

        local isReady = HandlePartyLogic()
        if not isReady then
            BossState.JoiningDebounce = false
            return
        end

        if not (References.humanoidRootPart and References.character) then
            BossState.JoiningDebounce = false
            return
        end

        local function findArenaPart()
            local Dialogues  = Workspace:FindFirstChild("Dialogues")
            local BossArenas = Dialogues and Dialogues:FindFirstChild("Boss Arenas")
            return BossArenas and BossArenas:FindFirstChild("HumanoidRootPart")
        end

        local TargetPart = findArenaPart()

        if not TargetPart then
            local fallbackPos = Vector3.new(7724.73, -6.44, -970.39)
            if (References.humanoidRootPart.Position - fallbackPos).Magnitude > 20 then
                if SecureTravel then
                    SecureTravel(fallbackPos)
                else
                    References.humanoidRootPart.CFrame = CFrame.new(fallbackPos)
                end
            else
                References.humanoidRootPart.CFrame = CFrame.new(fallbackPos)
            end
            task.wait(1)
            TargetPart = findArenaPart()
        end

        if TargetPart then
            local frontCFrame = TargetPart.CFrame * CFrame.new(0, 0, -4)
            local targetPos   = frontCFrame.Position
            local currentDist = (References.humanoidRootPart.Position - targetPos).Magnitude

            if currentDist > 15 then
                if SecureTravel then
                    SecureTravel(targetPos)
                else
                    References.humanoidRootPart.CFrame = frontCFrame
                end
            else
                References.humanoidRootPart.CFrame = CFrame.new(targetPos, TargetPart.Position)
                References.humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
            end

            if References.humanoidRootPart then
                References.humanoidRootPart.CFrame = CFrame.new(targetPos, TargetPart.Position)
                References.humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
            end

            task.wait(0.5)

            for i = 1, 5 do
                local prompt =
                    TargetPart:FindFirstChildWhichIsA("ProximityPrompt")
                    or TargetPart:FindFirstChildWhichIsA("ClickDetector")

                if not prompt then
                    local Detector = TargetPart:FindFirstChild("Detector")
                    if Detector then
                        prompt =
                            Detector:FindFirstChildWhichIsA("ProximityPrompt")
                            or Detector:FindFirstChildWhichIsA("ClickDetector")
                    end
                end

                if not prompt and TargetPart.Parent then
                    prompt = TargetPart.Parent:FindFirstChildWhichIsA("ProximityPrompt")
                end

                if prompt then
                    if prompt:IsA("ProximityPrompt") then
                        fireproximityprompt(prompt)
                    elseif prompt:IsA("ClickDetector") then
                        fireclickdetector(prompt)
                    end
                    break
                end
                task.wait(0.15)
            end

            task.wait(0.6)

            local selectedBoss = BossDropdown.Value
            local args = {
                [1] = {
                    [1] = {
                        ["Message"] = "You looking for a real fight? It'll Cost you 5k.";
                        ["Choice"]  = selectedBoss;
                        ["NPCName"] = "";
                        ["Choices"] = {
                            [1] = "Noro",
                            [2] = "Eto",
                            [3] = "Tatara",
                            [4] = "Kuzen",
                            [5] = "...",
                        };
                        ["Properties"] = {
                            ["Sound"]        = "rbxassetid://6929790120",
                            ["DotDelay"]     = 0,
                            ["RegularDelay"] = 0.02,
                            ["Name"]         = "?",
                        };
                        ["Name"] = "Boss Arenas";
                        ["Part"] = 1;
                    },
                    [2] = "\3";
                };
            }

            local bridge = ReplicatedStorage:WaitForChild("Bridgenet2Main", 5)
            local remote = bridge and bridge:WaitForChild("dataRemoteEvent", 5)

            if remote then
                remote:FireServer(unpack(args))
                Library:Notify("Sent request for " .. selectedBoss, 3)
            end
        end

        task.wait(3)
        BossState.JoiningDebounce = false
    end

    local function HandleBossCombat()
        if AttachPanel then
            AttachPanel.SetMode("Aligned")
            AttachPanel.SetYOffset(BossState.CurrentYOffset)
            AttachPanel.SetHorizDist(BossState.CurrentHorizOffset)
        end

        if Toggles.AutoBoss_SkipCutscene and Toggles.AutoBoss_SkipCutscene.Value then
            task.spawn(function()
                local start      = os.clock()
                local skipRemote = ReplicatedStorage:WaitForChild("BossCutsceneSkip", 5)
                if skipRemote then
                    Library:Notify("Skipping Cutscene...", 2)
                    while (os.clock() - start) < 20 do
                        if not Toggles.AutoBoss_Integrated.Value then
                            break
                        end
                        pcall(function() skipRemote:FireServer() end)
                        task.wait(1)
                    end
                end
            end)
        end

        local hb = RunService.Heartbeat:Connect(function()
            if not References.player or not References.character then
                return
            end

            local hum  = References.character:FindFirstChild("Humanoid")
            local root = References.humanoidRootPart

            if not (hum and root and hum.Health > 0) then
                BossState.IsVoiding     = false
                BossState.VoidTriggered = false
                BossState.ActiveTarget  = nil
                return
            end

            local healthPct = hum.Health / hum.MaxHealth

            if healthPct <= 0.30 then
                BossState.IsVoiding = true
            end

            if BossState.IsVoiding then
                if AttachPanel then
                    AttachPanel.Stop()
                end

                if not BossState.VoidTriggered then
                    BossState.VoidTriggered = true
                    Library:Notify("Low HP! Committing to Void...", 2)

                    local pos = root.Position
                    if MoveToPos then
                        MoveToPos(Vector3.new(pos.X, -5000, pos.Z), 10000)
                    end
                end
                return
            else
                BossState.VoidTriggered = false
            end

            local entityFolder = Workspace:FindFirstChild("Entities") or Workspace
            local filterName   = tostring(BossDropdown.Value):lower()
            local closestTarget, closestDist = nil, 99999

            for _, v in ipairs(entityFolder:GetChildren()) do
                if v:IsA("Model")
                    and v ~= References.character
                    and v:FindFirstChild("HumanoidRootPart")
                    and v:FindFirstChild("Humanoid") then

                    if string.find(string.lower(v.Name), filterName) then
                        local dist = (root.Position - v.HumanoidRootPart.Position).Magnitude
                        if dist < closestDist then
                            closestDist  = dist
                            closestTarget = v
                        end
                    end
                end
            end

            if closestTarget then
                BossState.ActiveTarget = closestTarget
                if AttachPanel then
                    AttachPanel.SetTarget(closestTarget)
                    AttachPanel.TeleportToTarget(closestTarget)
                else
                    root.CFrame = closestTarget.HumanoidRootPart.CFrame
                        * CFrame.new(BossState.CurrentHorizOffset, BossState.CurrentYOffset, 0)
                end
                root.AssemblyLinearVelocity  = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            else
                if AttachPanel then
                    AttachPanel.Stop()
                end

                if Toggles.AutoBoss_AutoReplay
                    and Toggles.AutoBoss_AutoReplay.Value then

                    if (os.clock() - BossState.LastReplayClick) > 2 then
                        BossState.LastReplayClick = os.clock()
                        PerformReplayClick()
                    end
                end
            end
        end)

        table.insert(BossState.Connections, hb)
    end

    ------------------------------------------------------
    -- Main toggle / loop
    ------------------------------------------------------
    AutoBossGroupbox:AddToggle("AutoBoss_Integrated", {
        Text    = "Auto Boss",
        Default = false,
        Callback = function(val)
            StopAutoBoss()

            if AutoFarm then
                AutoFarm.Active = val
            end

            if val then
                ResolvePartyMode()

                local modeLabel = BossState.PartyConfig.PartyEnabled
                    and (BossState.EffectiveMode .. " (Party)")
                    or "Solo"

                Library:Notify("Auto Boss: " .. modeLabel, 3)

                local lp = Players.LocalPlayer
                if lp then
                    local charConn = lp.CharacterAdded:Connect(OnCharacterArriveAtBoss)
                    table.insert(BossState.Connections, charConn)

                    if lp.Character then
                        OnCharacterArriveAtBoss(lp.Character)
                    end
                end

                task.spawn(function()
                    while Toggles.AutoBoss_Integrated
                        and Toggles.AutoBoss_Integrated.Value do

                        if game.PlaceId == BOSS_PLACE_ID then
                            -- replicate original behaviour: only start combat loop when we have
                            -- 0 or 1 connections (usually just charConn)
                            if #BossState.Connections <= 1 then
                                Library:Notify("Boss Arena Detected. Engaging.", 3)
                                HandleBossCombat()
                            end

                            task.wait(1)
                        else
                            AttemptJoinBoss()
                            task.wait(1)
                        end
                    end
                end)
            else
                Library:Notify("Auto Boss Disabled.", 2)
            end
        end
    })

    ------------------------------------------------------
    -- Unload cleanup
    ------------------------------------------------------
    Library:OnUnload(function()
        if Toggles.AutoBoss_Integrated and Toggles.AutoBoss_Integrated.Value then
            Toggles.AutoBoss_Integrated:SetValue(false)
        end
        StopAutoBoss()
    end)
end
