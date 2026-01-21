return function(ctx)
    assert(type(ctx) == "table", "AutoMission: context table required")

    local Services = assert(ctx.Services, "AutoMission: Services missing")
    local References = assert(ctx.References, "AutoMission: References missing")
    local Library = assert(ctx.Library, "AutoMission: Library missing")
    local Tabs = assert(ctx.Tabs, "AutoMission: Tabs missing")
    local Options = assert(ctx.Options, "AutoMission: Options missing")
    local Toggles = assert(ctx.Toggles, "AutoMission: Toggles missing")
    local Auto = assert(ctx.Auto, "AutoMission: Auto missing")
    local Shared = assert(ctx.Shared, "AutoMission: Shared missing")
    local Player = assert(ctx.Player, "AutoMission: Player missing")
    local WebhookAPI = ctx.Webhook
    local startNoclip = ctx.startNoclip or ctx.StartNoclip
    local stopNoclip = ctx.stopNoclip or ctx.StopNoclip
    assert(type(startNoclip) == "function", "AutoMission: startNoclip missing")
    assert(type(stopNoclip) == "function", "AutoMission: stopNoclip missing")

    Services.ReplicatedStorage = Services.ReplicatedStorage or game:GetService("ReplicatedStorage")
    Services.Players = Services.Players or game:GetService("Players")
    Services.RunService = Services.RunService or game:GetService("RunService")
    Services.VirtualInputManager = Services.VirtualInputManager or game:GetService("VirtualInputManager")
    Services.Workspace = Services.Workspace or game:GetService("Workspace")
    Services.HttpService = Services.HttpService or game:GetService("HttpService")

    local world = Services.Workspace:FindFirstChild("World")

    Auto.Autos = {
        -- ==== AUTO MISSION ==== --
        MissionID = nil,
        SafePoint = Vector3.new(-2641.438721, 120.946236, -80.263588),
        SpawnBackup = Vector3.new(-1653.63, 5.81, -625.84),
        TeleportBackup = Vector3.new(-2053.32, 5.18, -537.90),
        TurnInBackup = Vector3.new(-2821.05, 7.01, -683.34),
        MaxFailures = 2,
        ConsecutiveFailures = 0,
        DamageConnection = nil,
        missionPlatform = nil,
        platformConn = nil,
        CleanupTakenNotified = false,
        PreferCommercialNext = {
            ["Cleanup Duty"] = false,
        },

        -- ==== AUTO INTERCEPT ==== --
        InterceptConfigFile = (References and References.gameDir or "") .. "/AutoInterceptAccounts.json",
        LegacyInterceptConfigFile = (References and References.gameDir or "") .. "/HoldTheLineAccounts.json",
        InterceptAccounts = { Mains = {}, Alts = {} },
        InterceptLastStatus = "",
        InterceptTargetMissionId = nil,
        InterceptLastAttempt = 0,

        -- ==== AUTO RAID ==== --
        MainAccountName = "",
        AltAccountName = "",
        RaidEntrancePos = Vector3.new(382.002197, 6.003088, 940.823303),
        RaidEntitiesPath = world and world:FindFirstChild("Entities"),
        WaitThreshold = 5,
        LastInviteTime = 0,
        NoEnemyTimer = 0,
        IsAttaching = false,
        LastNotif = "",
        IsForceLoading = false,
    }

    -- ==== AUTO MISSION / INTERCEPT ==== --
    Auto.AutoMissionGroupbox = Tabs.Auto:AddLeftGroupbox("AutoMission", "rocket")
    Auto.AutoInterceptGroupbox = Tabs.Auto:AddRightGroupbox("AutoIntercept", "crosshair")

    local ReplicatedStorage = Services.ReplicatedStorage
    local Players = Services.Players

    local LocalPlayer = Players.LocalPlayer

    local ClientController =
        require(ReplicatedStorage.Files.Modules.Client.ClientController)

    local MissionData =
        require(
            ReplicatedStorage
                :WaitForChild("Files")
                :WaitForChild("Modules")
                :WaitForChild("Shared")
                :WaitForChild("OverworldMissionData")
        )

    --==============================
    -- NETWORK (REAL REMOTES)
    --==============================
    local NetworkConfig =
        ReplicatedStorage
            :WaitForChild("Files")
            :WaitForChild("Framework")
            :WaitForChild("Network")

    local RemoteFunction = NetworkConfig:FindFirstChildWhichIsA("RemoteFunction")
    assert(RemoteFunction, "RemoteFunction missing")

    local function invoke(name, data)
        return RemoteFunction:InvokeServer(name, data)
    end

    local function isTakenResponse(res)
        if type(res) == "string" then
            return res:lower() == "taken"
        end
        if type(res) == "table" then
            local reason = res.Reason or res.reason or res.Status or res.status or res.Message or res.message
            if type(reason) == "string" then
                return reason:lower() == "taken"
            end
        end
        return false
    end

    -- Resolve a FREE location, prioritising Residential Area
    local function resolveFreeLocationId(directive, preferName)
        local locations = invoke("RequestLocationData", { directive })
        if not locations then return end

        local missionInfo = MissionData.Missions[directive]
        local allowed = missionInfo and missionInfo.Locations
        if not allowed then return end

        local preferId, preferLabel
        local residentialId, residentialName
        local fallbackId, fallbackName

        for id, name in pairs(locations) do
            if table.find(allowed, name) then
                if preferName and name == preferName then
                    preferId, preferLabel = id, name
                elseif name == "Residential Area" then
                    residentialId, residentialName = id, name
                elseif not fallbackId then
                    fallbackId, fallbackName = id, name
                end
            end
        end

        if preferId then
            return preferId, preferLabel
        end

        if residentialId then
            return residentialId, residentialName
        end

        return fallbackId, fallbackName
    end

    local function trimName(value)
        return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function normalizeName(value)
        return trimName(value):lower()
    end

    local function sanitizeNameList(list)
        local cleaned, seen = {}, {}
        if type(list) ~= "table" then return cleaned end
        for _, entry in ipairs(list) do
            if type(entry) == "string" then
                local key = normalizeName(entry)
                if key ~= "" and not seen[key] then
                    seen[key] = true
                    table.insert(cleaned, trimName(entry))
                end
            end
        end
        return cleaned
    end

    local function loadInterceptConfig()
        Auto.Autos.InterceptAccounts = { Mains = {}, Alts = {} }
        local configPath = Auto.Autos.InterceptConfigFile
        if isfile and not isfile(configPath) and Auto.Autos.LegacyInterceptConfigFile then
            if isfile(Auto.Autos.LegacyInterceptConfigFile) then
                configPath = Auto.Autos.LegacyInterceptConfigFile
            end
        end
        if isfile and isfile(configPath) then
            local ok, decoded = pcall(function()
                return Services.HttpService:JSONDecode(readfile(configPath))
            end)
            if ok and type(decoded) == "table" then
                Auto.Autos.InterceptAccounts.Mains = sanitizeNameList(decoded.Mains)
                Auto.Autos.InterceptAccounts.Alts = sanitizeNameList(decoded.Alts)
                if #Auto.Autos.InterceptAccounts.Mains > 0 and #Auto.Autos.InterceptAccounts.Alts > 0 then
                    local mainSet = {}
                    for _, name in ipairs(Auto.Autos.InterceptAccounts.Mains) do
                        mainSet[normalizeName(name)] = true
                    end
                    local cleanedAlts = {}
                    for _, name in ipairs(Auto.Autos.InterceptAccounts.Alts) do
                        if not mainSet[normalizeName(name)] then
                            table.insert(cleanedAlts, name)
                        end
                    end
                    Auto.Autos.InterceptAccounts.Alts = cleanedAlts
                end
            end
        end
    end

    local function saveInterceptConfig()
        if not writefile then return end
        local payload = {
            Mains = Auto.Autos.InterceptAccounts.Mains,
            Alts = Auto.Autos.InterceptAccounts.Alts,
        }
        writefile(Auto.Autos.InterceptConfigFile, Services.HttpService:JSONEncode(payload))
    end

    local function nameInList(list, name)
        local key = normalizeName(name)
        if key == "" then return false end
        for _, entry in ipairs(list or {}) do
            if normalizeName(entry) == key then
                return true
            end
        end
        return false
    end

    local function addInterceptName(listName, rawName)
        local trimmed = trimName(rawName)
        if trimmed == "" then return false end

        local accounts = Auto.Autos.InterceptAccounts
        local isMain = listName == "Mains"
        local targetList = isMain and accounts.Mains or accounts.Alts
        local otherList = isMain and accounts.Alts or accounts.Mains

        if nameInList(targetList, trimmed) then
            return false, "already_in_list"
        end
        if nameInList(otherList, trimmed) then
            return false, "in_other_list"
        end

        table.insert(targetList, trimmed)
        saveInterceptConfig()
        return true
    end

    local function clearInterceptConfig()
        Auto.Autos.InterceptAccounts = { Mains = {}, Alts = {} }
        saveInterceptConfig()
    end

    loadInterceptConfig()

    --==============================
    -- UI
    --==============================
    Auto.AutoMissionGroupbox:AddLabel(
        "Cleanup Duty auto farm for mains.",
        true
    )

    Auto.AutoMissionGroupbox:AddToggle("AutoMission", {
        Text = "Auto Mission",
        Default = false,
    })

    Auto.AutoInterceptGroupbox:AddLabel(
        "Your main just needs to use AutoMission normally, your alt will automatically intercept so that you always get lootboxes.",
        true
    )

    Auto.AutoInterceptGroupbox:AddToggle("AutoIntercept", {
        Text = "Auto Intercept",
        Default = false,
    })

    Auto.InterceptRoleLabel = Auto.AutoInterceptGroupbox:AddLabel(
        "Auto Intercept Role: Unassigned | Other type in server: -", true
    )

    Auto.InterceptInfoLabel = Auto.AutoInterceptGroupbox:AddLabel(
        "Add Auto Intercept accounts (press Enter).",
        true
    )

    Auto.InterceptMainInput = Auto.AutoInterceptGroupbox:AddInput("AutoIntercept_MainInput", {
        Text = "Main Username",
        Placeholder = "Username",
        ClearTextOnFocus = false,
        Finished = true,
        Callback = function(value)
            local ok, reason = addInterceptName("Mains", value)
            if ok then
                if Options.AutoIntercept_MainInput and Options.AutoIntercept_MainInput.SetValue then
                    Options.AutoIntercept_MainInput:SetValue("")
                elseif Options.AutoIntercept_MainInput then
                    Options.AutoIntercept_MainInput.Value = ""
                end
                if Library then Library:Notify("Main account saved.", 3) end
            elseif reason == "in_other_list" then
                if Library then Library:Notify("That username is already in the Alt list.", 3) end
            elseif reason == "already_in_list" then
                if Library then Library:Notify("That username is already in the Main list.", 3) end
            end
        end,
    })

    Auto.InterceptAltInput = Auto.AutoInterceptGroupbox:AddInput("AutoIntercept_AltInput", {
        Text = "Alt Username",
        Placeholder = "Username",
        ClearTextOnFocus = false,
        Finished = true,
        Callback = function(value)
            local ok, reason = addInterceptName("Alts", value)
            if ok then
                if Options.AutoIntercept_AltInput and Options.AutoIntercept_AltInput.SetValue then
                    Options.AutoIntercept_AltInput:SetValue("")
                elseif Options.AutoIntercept_AltInput then
                    Options.AutoIntercept_AltInput.Value = ""
                end
                if Library then Library:Notify("Alt account saved.", 3) end
            elseif reason == "in_other_list" then
                if Library then Library:Notify("That username is already in the Main list.", 3) end
            elseif reason == "already_in_list" then
                if Library then Library:Notify("That username is already in the Alt list.", 3) end
            end
        end,
    })

    Auto.InterceptClearButton = Auto.AutoInterceptGroupbox:AddButton({
        Text = "Clear Auto Intercept Accounts",
        Func = function()
            clearInterceptConfig()
            Auto.Autos.InterceptLastStatus = ""
            if Auto.InterceptRoleLabel then
                Auto.InterceptRoleLabel:SetText("Auto Intercept Role: Unassigned | Other type in server: -", true)
            end
            if Library then Library:Notify("Auto Intercept accounts cleared.", 3) end
        end
    })

    local function formatNumber(n)
        if type(n) ~= "number" then return "?" end
        local s = tostring(math.floor(n + 0.5))
        local rev = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
        if rev:sub(1,1) == "," then rev = rev:sub(2) end
        return rev
    end

    local function getYenAmount()
        local pg = References.player and References.player:FindFirstChild("PlayerGui")
        local hud = pg and pg:FindFirstChild("HUD")
        local yen = hud and hud:FindFirstChild("Yen")
        local label = yen and yen:FindFirstChild("TextLabel")
        local text = label and label.Text
        if type(text) ~= "string" then return nil end
        local digits = text:gsub("[^%d]", "")
        if digits == "" then return nil end
        return tonumber(digits)
    end

    task.spawn(function()
        local lastYen = nil
        while true do
            task.wait(1)
            local yen = getYenAmount()
            if not yen then
                lastYen = nil
                continue
            end
            if not (Toggles.AutoMission and Toggles.AutoMission.Value) then
                lastYen = yen
                continue
            end

            if lastYen and yen > lastYen then
                local delta = yen - lastYen
                if WebhookAPI and WebhookAPI.Report and (WebhookAPI.IsEnabled == nil or WebhookAPI.IsEnabled("MissionRaid")) then
                    local desc = string.format(
                        "Auto mission reward: +%s Yen (now %s).",
                        formatNumber(delta),
                        formatNumber(yen)
                    )
                    WebhookAPI.Report("MissionRaid", "Auto Mission Completed", desc)
                end
            end

            lastYen = yen
        end
    end)

    -- =====================
    -- STATIC SAFE TELEPORT
    -- =====================
    local function tp(dest)
        local char = References.player.Character
        if not char then return end

        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChild("Humanoid")
        if not hrp or not hum then return end

        local pos =
            typeof(dest) == "Vector3" and dest
            or (dest and (dest:IsA("BasePart") and dest.Position or dest:GetPivot().Position))

        if not pos then return end

        if not Auto.Autos.missionPlatform then
            local p = Instance.new("Part")
            p.Name = "AutoMissionPlatform"
            p.Size = Vector3.new(18, 1.2, 18)
            p.Anchored = true
            p.CanCollide = true
            p.Transparency = 1
            p.Material = Enum.Material.SmoothPlastic
            p.Parent = workspace
            Auto.Autos.missionPlatform = p
        end

        local platformPos = pos - Vector3.new(0, 14, 0)
        Auto.Autos.missionPlatform.CFrame = CFrame.new(platformPos)
        hrp.CFrame = CFrame.new(platformPos + Vector3.new(0, 3, 0))

        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        hum:ChangeState(Enum.HumanoidStateType.Landed)
    end

    -- =====================
    -- INTERACTION
    -- =====================
    local function interact()
        local char = References.player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local best, dist = nil, 40
        for _, v in ipairs(Services.Workspace:GetDescendants()) do
            if v:IsA("ProximityPrompt") and v.Enabled then
                local p =
                    v.Parent
                    and (v.Parent:IsA("BasePart") and v.Parent.Position or v.Parent:GetPivot().Position)

                local d = p and (p - hrp.Position).Magnitude
                if d and d < dist then
                    best, dist = v, d
                end
            end
        end

        if best then
            fireproximityprompt(best)
        end
    end

    -- =====================
    -- FAILSAFE
    -- =====================
    local function HandleFailsafe(reason)
        warn("[AutoMission] Failsafe:", reason)

        Shared.QuickReset()

        local newChar = References.player.CharacterAdded:Wait()
        newChar:WaitForChild("HumanoidRootPart", 10)
        newChar:WaitForChild("Humanoid", 10)

        task.wait(1)
        tp(Auto.Autos.SafePoint)
        Auto.Autos.ConsecutiveFailures = 0
    end

    -- =====================
    -- HEALTH MONITOR
    -- =====================
    local function MonitorHealth()
        if Auto.Autos.DamageConnection then
            Auto.Autos.DamageConnection:Disconnect()
        end

        local char = References.player.Character or References.player.CharacterAdded:Wait()
        local hum = char:WaitForChild("Humanoid", 5)
        if not hum then return end

        Auto.Autos.DamageConnection = hum.HealthChanged:Connect(function(hp)
            if Toggles.AutoMission.Value and hp > 0 and hp < hum.MaxHealth then
                HandleFailsafe("Took Damage")
            end
        end)
    end

    local function findPlayerByName(name)
        local key = normalizeName(name)
        if key == "" then return nil end
        for _, plr in ipairs(Players:GetPlayers()) do
            if normalizeName(plr.Name) == key then
                return plr
            end
        end
        return nil
    end

    local function getInterceptRole()
        local name = LocalPlayer and LocalPlayer.Name or (References.player and References.player.Name)
        if nameInList(Auto.Autos.InterceptAccounts.Mains, name) then
            return "Main"
        end
        if nameInList(Auto.Autos.InterceptAccounts.Alts, name) then
            return "Alt"
        end
        return nil
    end

    local function isPlayerInServer(name)
        return findPlayerByName(name) ~= nil
    end

    local function isOtherRolePresent(role)
        if role == "Main" then
            for _, altName in ipairs(Auto.Autos.InterceptAccounts.Alts) do
                if isPlayerInServer(altName) then
                    return true
                end
            end
        elseif role == "Alt" then
            for _, mainName in ipairs(Auto.Autos.InterceptAccounts.Mains) do
                if isPlayerInServer(mainName) then
                    return true
                end
            end
        end
        return false
    end

    local function updateInterceptStatus(role, otherPresent)
        if not Auto.InterceptRoleLabel then return end
        local roleText = role or "Unassigned"
        local otherText = role and (otherPresent and "yes" or "no") or "-"
        local text = ("Auto Intercept Role: %s | Other type in server: %s"):format(roleText, otherText)
        if Auto.Autos.InterceptLastStatus ~= text then
            Auto.Autos.InterceptLastStatus = text
            Auto.InterceptRoleLabel:SetText(text, true)
        end
    end

    local function isCleanupLiveMission(liveData)
        if type(liveData) ~= "table" then return false end
        local active = liveData.ActiveData
        local lib = liveData.LibraryData
        local missionType =
            (type(active) == "table" and active.MissionType)
            or (type(lib) == "table" and lib.Name)
        if type(missionType) ~= "string" then return false end
        return missionType:lower() == "cleanup duty"
    end

    local function missionHasMain(liveData)
        local active = type(liveData) == "table" and liveData.ActiveData or nil
        if type(active) ~= "table" then return false end

        local mains = Auto.Autos.InterceptAccounts.Mains or {}
        if #mains == 0 then return false end

        local function hasNameMatch(name)
            if type(name) ~= "string" then return false end
            for _, mainName in ipairs(mains) do
                if normalizeName(name) == normalizeName(mainName) then
                    return true
                end
            end
            return false
        end

        local saved = active.SavedPositions
        if type(saved) == "table" then
            for key, value in pairs(saved) do
                local keyString = type(key) == "string" and key or tostring(key)
                local lowered = keyString:lower()
                for _, mainName in ipairs(mains) do
                    local target = normalizeName(mainName)
                    if target ~= "" and lowered:find(target, 1, true) then
                        return true
                    end
                    if type(value) == "table" then
                        local maybeName = value.Name or value.Player or value.Username or value.PlayerName or value.DisplayName
                        if hasNameMatch(maybeName) then
                            return true
                        end
                    end
                end
            end
        end

        local listKeys = { "Players", "PlayerList", "Participants", "ActivePlayers" }
        for _, listKey in ipairs(listKeys) do
            local list = active[listKey]
            if type(list) == "table" then
                for _, entry in pairs(list) do
                    local entryName = entry
                    if type(entry) == "table" then
                        entryName = entry.Name or entry.Username or entry.PlayerName or entry.DisplayName
                    end
                    if hasNameMatch(entryName) then
                        return true
                    end
                end
            end
        end

        return false
    end

    local function findMainCleanupMissionId()
        local rs = game:GetService("ReplicatedStorage")
        local missionData = rs:FindFirstChild("OverworldMissionData")
        local activeFolder = missionData and missionData:FindFirstChild("Active")

        if not activeFolder then return nil end

        for _, missionFolder in ipairs(activeFolder:GetChildren()) do
            local id = missionFolder.Name

            if id ~= "" then
                local ok, liveData = pcall(function()
                    return invoke("RequestLiveMissionData", { id })
                end)

                if ok and isCleanupLiveMission(liveData) and missionHasMain(liveData) then
                    return id
                end
            end
        end
        return nil
    end

    References.player.CharacterAdded:Connect(function()
        if Toggles.AutoMission.Value then
            task.wait(1)
            MonitorHealth()
        end
    end)

    -- =====================
    -- AUTO MISSION LOOP
    -- =====================
    task.spawn(function()
        while true do
            task.wait(1)

            if not Toggles.AutoMission.Value then
                if Auto.Autos.DamageConnection then
                    Auto.Autos.DamageConnection:Disconnect()
                    Auto.Autos.DamageConnection = nil
                end
                continue
            end

            MonitorHealth()

            local preferCommercial = Auto.Autos.PreferCommercialNext["Cleanup Duty"]
            local locationId, locationName =
                resolveFreeLocationId("Cleanup Duty", preferCommercial and "Commercial District" or nil)
            Auto.Autos.PreferCommercialNext["Cleanup Duty"] = false

            if not locationId then
                warn("[AutoMission] All Cleanup locations are taken")
                task.wait(2)
                continue
            end

            local ok, res = pcall(function()
                return invoke("OverworldMissions", {
                    Request        = "Engage",
                    Directive      = "Cleanup Duty",
                    Identification = locationId,
                    Conditions     = { "Bloodlust", "Blind Path" },
                })
            end)

            if not ok or res ~= true then
                if isTakenResponse(res) then
                    Auto.Autos.PreferCommercialNext["Cleanup Duty"] = true
                    if not Auto.Autos.CleanupTakenNotified and Library then
                        Library:Notify("Desired mission taken - waiting until it is free", 4)
                    end
                    Auto.Autos.CleanupTakenNotified = true
                    task.wait(2)
                    continue
                end

                Auto.Autos.CleanupTakenNotified = false
                Auto.Autos.ConsecutiveFailures += 1
                warn("[AutoMission] Failed:", res)

                if Auto.Autos.ConsecutiveFailures >= Auto.Autos.MaxFailures then
                    HandleFailsafe("Repeated mission start failure")
                end
                continue
            end

            Auto.Autos.ConsecutiveFailures = 0
            Auto.Autos.CleanupTakenNotified = false
            task.wait(4)

            local world = Services.Workspace.World
            local mission = world.Missions:FindFirstChild("Cleanup Duty")
            local area = mission and mission:FindFirstChild(locationName)

            tp((area and area:FindFirstChild("SpawnPoint")) or Auto.Autos.SpawnBackup)
            task.wait(1)
            interact()
            task.wait(4.5)

            tp((area and area:FindFirstChild("TeleportPoint")) or Auto.Autos.TeleportBackup)
            task.wait(0.1)

            tp((area and area:FindFirstChild("TurnIn")) or Auto.Autos.TurnInBackup)
            task.wait(0.8)
            interact()

            task.wait(1.2)
            tp(Auto.Autos.SafePoint)
            task.wait(4)
        end
    end)

    -- =====================
    -- AUTO INTERCEPT LOOP
    -- =====================
    task.spawn(function()
        while true do
            task.wait(1)

            local role = getInterceptRole()
            local otherPresent = role and isOtherRolePresent(role)
            updateInterceptStatus(role, otherPresent)

            if not (Toggles.AutoIntercept and Toggles.AutoIntercept.Value) then
                Auto.Autos.InterceptTargetMissionId = nil
                Auto.Autos.InterceptLastAttempt = 0
                continue
            end

            if role ~= "Alt" then
                Auto.Autos.InterceptTargetMissionId = nil
                task.wait(1)
                continue
            end

            if not Auto.Autos.InterceptTargetMissionId then
                local missionId = findMainCleanupMissionId()
                if not missionId then
                    task.wait(0.5)
                    continue
                end
                Auto.Autos.InterceptTargetMissionId = missionId
                warn("[AutoIntercept] Target set:", missionId)
            end

            local targetId = Auto.Autos.InterceptTargetMissionId
            local okLive, liveData = pcall(function()
                return invoke("RequestLiveMissionData", { targetId })
            end)
            if not okLive or not isCleanupLiveMission(liveData) or not missionHasMain(liveData) then
                Auto.Autos.InterceptTargetMissionId = nil
                task.wait(0.5)
                continue
            end

            local now = os.clock()
            if now - (Auto.Autos.InterceptLastAttempt or 0) >= 1 then
                Auto.Autos.InterceptLastAttempt = now
                local ok, res = pcall(function()
                    return invoke("OverworldMissions", {
                        Identification = targetId,
                        Request = "Intercept"
                    })
                end)

                if not ok or res ~= true then
                    warn("[AutoIntercept] Intercept failed:", res)
                end
            end
        end
    end)

    Toggles.AutoMission:OnChanged(function(enabled)
        if enabled then
            startNoclip()
            Auto.Autos.ConsecutiveFailures = 0
            Auto.Autos.CleanupTakenNotified = false
        else
            stopNoclip()
            if Auto.Autos.DamageConnection then
                Auto.Autos.DamageConnection:Disconnect()
                Auto.Autos.DamageConnection = nil
            end
            if Auto.Autos.missionPlatform then
                Auto.Autos.missionPlatform:Destroy()
                Auto.Autos.missionPlatform = nil
            end
        end
    end)

    Toggles.AutoIntercept:OnChanged(function()
        Auto.Autos.InterceptTargetMissionId = nil
        Auto.Autos.InterceptLastAttempt = 0
    end)
end
