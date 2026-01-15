return function(ctx)
    -- // Services & Context // --
    local Services = ctx.Services
    local Tabs = ctx.Tabs
    local References = ctx.References
    local Library = ctx.Library
    local Options = ctx.Options
    local Toggles = ctx.Toggles
    local Unloader = ctx.Unloader
    local Config = ctx.AutoParryConfig or { Enabled = false }

    -- // Optimization & Localizing // --
    local VIM = Services.VirtualInputManager
    local RunService = Services.RunService
    local Workspace = Services.Workspace
    local HttpService = Services.HttpService
    local Players = Services.Players

    local clock = os.clock
    local insert, remove = table.insert, table.remove
    
    -- Hard Stop
    if Config.Enabled ~= true then return end

    -- // State Management // --
    local State = {
        -- Global Cleanups
        MainConnections = {}, 
        
        -- Per-Enemy Cleanup
        EnemyTracks = {}, 
        
        -- Cache: Weak Keys ensure AnimationTracks are GC'd automatically
        AnimSeen = setmetatable({}, { __mode = "k" }),
        
        -- Scheduler Queue
        PendingParries = {}, 
        
        -- Math Caches
        RangeSq = 14 * 14,
        FovThreshold = -1, -- -1 = 180 degrees
        
        -- Logic Flags
        ParryAvailTime = 0,
    }

    local AutoParry = {
        ConfigPresets = { 
            { Name = "Custom Config (Local)", Url = nil },
            {
                Name = "Cash/Alexx Config",
                Url = "https://raw.githubusercontent.com/whodunitwww/noxhelpers/refs/heads/main/devilhunter/devil_ap.json"
            }
        },
        
        -- Settings
        enabled = false,
        debug = false,
        pingOn = true,
        pingScale = 100,
        extraBiasMs = 0,
        range = 14,
        useFov = false,
        fovLimit = 180,
        parryFailTime = 0.25,
        rollOnFailGlob = true,
        productionMode = true,
        
        keyCode = Enum.KeyCode.F,
        rollKey = Enum.KeyCode.Q,

        currentPresetIndex = 1,
        apFile = References.gameDir .. "/AP_Config.json",
        apExtraFile = References.gameDir .. "/AP_Config_Extra.json",
        
        AP_Config_Default = {
            ["17030773401"] = {
                name = "Zombie Attack",
                startSec = 0.42,
                hold = 0.30,
                rollOnFail = true,
                distanceAdj = 0,
            },
        },
        AP_ConfigExtra_Default = { parryKey = "F", rollKey = "Q" },
        AP_Config = {},
        AP_ConfigExtra = {},
    }

    -- // Utility Functions // --

    local function getDistSq(posA, posB)
        local dx, dy, dz = posA.X - posB.X, posA.Y - posB.Y, posA.Z - posB.Z
        return dx * dx + dy * dy + dz * dz
    end

    local function checkFov(myRoot, targetRoot)
        if not AutoParry.useFov then return true end
        if not myRoot or not targetRoot then return false end
        
        local dir = (targetRoot.Position - myRoot.Position).Unit
        local look = myRoot.CFrame.LookVector
        return look:Dot(dir) >= State.FovThreshold
    end

    local function debugNote(title, content, duration)
        if not AutoParry.debug or not Library.Notify then return end
        Library:Notify({ Title = title, Description = content or "", Time = duration or 3 })
    end

    local function trackGlobal(conn)
        if conn then insert(State.MainConnections, conn) end
        return conn
    end

    -- // Scheduler System // --
    local function updateScheduler()
        if not References.humanoidRootPart then return end

        local now = clock()
        
        for i = #State.PendingParries, 1, -1 do
            local taskData = State.PendingParries[i]
            if now >= taskData.triggerTime then
                local s, e = pcall(taskData.fn)
                if not s and AutoParry.debug then warn("[AutoParry] Exec Error:", e) end
                remove(State.PendingParries, i)
            end
        end
    end

    trackGlobal(RunService.Heartbeat:Connect(updateScheduler))

    -- Queue Cleaning on Respawn
    trackGlobal(References.player.CharacterAdded:Connect(function()
        table.clear(State.PendingParries)
        if AutoParry.debug then debugNote("Respawn", "Queue Cleared", 2) end
    end))

    -- // Combat Logic // --

    local function performInput(key, hold)
        VIM:SendKeyEvent(true, key, false, game)
        task.spawn(function()
            task.wait(hold)
            VIM:SendKeyEvent(false, key, false, game)
        end)
    end

    function AutoParry:executeParry(cfg, animId, sourceModel, isRepeat, chainId)
        if not self.enabled then return end
        
        local myRoot = References.humanoidRootPart
        if not myRoot then return end

        local now = clock()
        local srcName = sourceModel and sourceModel.Name or "Unknown"

        if now < State.ParryAvailTime then
            if self.rollOnFailGlob and cfg.rollOnFail then
                performInput(self.rollKey, 0.05)
                State.ParryAvailTime = now + self.parryFailTime
                
                -- HOOK: Parry Fail Roll
                if getgenv().AutoParry_OnParryFailRoll then
                    pcall(getgenv().AutoParry_OnParryFailRoll, animId, cfg, srcName, chainId)
                end

                if not self.productionMode then
                    debugNote("Roll", "Conflict/CD: " .. (cfg.name or animId), 2)
                end
            end
            return
        end

        -- 2. FOV Check
        if self.useFov and sourceModel then
            local eRoot = sourceModel:FindFirstChild("HumanoidRootPart") or sourceModel.PrimaryPart
            if not checkFov(myRoot, eRoot) then
                if self.debug then debugNote("FOV Fail", "Enemy outside angle", 1) end
                return
            end
        end

        -- 3. Execute
        local isRoll = (cfg.priority == "roll")
        local keyToUse = isRoll and self.rollKey or self.keyCode
        
        performInput(keyToUse, cfg.hold)
        State.ParryAvailTime = now + self.parryFailTime

        -- HOOK: Parry Fired
        if getgenv().AutoParry_OnParryFired then
            pcall(getgenv().AutoParry_OnParryFired, animId, cfg, srcName, chainId)
        end

        if not self.productionMode then
            debugNote(isRoll and "Roll" or "Parry", cfg.name or animId, 2)
        end
    end

    function AutoParry:schedule(animId, trackObj, sourceModel, cfg)
        local now = clock()
        local rtt = References.player:GetNetworkPing()
        local oneWay = (self.pingOn and (rtt * 0.5 * (self.pingScale / 100))) or 0
        oneWay = math.max(0, oneWay + (self.extraBiasMs / 1000))
        
        local tPos = trackObj.TimePosition or 0
        local timings = { { t = cfg.startSec, isRepeat = false } }

        if cfg.repeats then
            for _, repTime in ipairs(cfg.repeats) do
                insert(timings, { t = tonumber(repTime), isRepeat = true })
            end
        end

        -- Distance Logic
        local distOffset = 0
        if cfg.distanceAdj ~= 0 and sourceModel and References.humanoidRootPart then
            local eRoot = sourceModel:FindFirstChild("HumanoidRootPart") or sourceModel.PrimaryPart
            if eRoot then
                local dist = (eRoot.Position - References.humanoidRootPart.Position).Magnitude
                distOffset = cfg.distanceAdj * (dist / 100)
            end
        end
        
        local chainId = tostring(animId) .. "-" .. tostring(math.floor(now * 1000))
        local srcName = sourceModel and sourceModel.Name or "Unknown"

        for _, timing in ipairs(timings) do
            local hitTime = (timing.t or cfg.startSec) + distOffset
            local delayNeeded = hitTime - tPos - oneWay
            
            -- HOOK: Scheduled
            if getgenv().AutoParry_OnParryScheduled then
                pcall(
                    getgenv().AutoParry_OnParryScheduled,
                    animId,
                    cfg,
                    srcName,
                    delayNeeded,
                    now,
                    chainId
                )
            end

            insert(State.PendingParries, {
                triggerTime = now + math.max(0, delayNeeded),
                fn = function()
                    if sourceModel and sourceModel.Parent then
                        self:executeParry(cfg, animId, sourceModel, timing.isRepeat, chainId)
                    end
                end
            })

            if not self.productionMode and self.debug then
                debugNote("Scheduled", ("%.3fs delay"):format(delayNeeded), 1)
            end
        end
    end

    -- // Hooking System // --

    function AutoParry:unhookHumanoid(hum)
        if State.EnemyTracks[hum] then
            for _, conn in ipairs(State.EnemyTracks[hum]) do
                if conn.Connected then conn:Disconnect() end
            end
            State.EnemyTracks[hum] = nil
        end
    end

    function AutoParry:isValidTarget(model)
        if not model or model == References.character then return false end
        
        local eRoot = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
        local myRoot = References.humanoidRootPart
        
        if not (eRoot and myRoot) then return false end
        if getDistSq(eRoot.Position, myRoot.Position) > State.RangeSq then return false end

        return true
    end

    function AutoParry:processAnim(animator)
        if not animator then return end
        local hum = animator.Parent
        if not hum then return end
        if State.EnemyTracks[hum] then return end

        local connections = {}

        local animConn = hum.AnimationPlayed:Connect(function(animTrack)
            if not self.enabled then return end
            if State.AnimSeen[animTrack] then return end 
            
            local model = hum.Parent
            if not self:isValidTarget(model) then return end

            local rawId = animTrack.Animation and animTrack.Animation.AnimationId or ""
            local animId = rawId:match("%d+")
            if not animId then return end

            local cfg = self.AP_Config[animId]
            if not cfg or cfg.enabled == false then return end

            State.AnimSeen[animTrack] = true 
            self:schedule(animId, animTrack, model, cfg)
        end)
        insert(connections, animConn)

        local ancestryConn = hum.AncestryChanged:Connect(function(_, parent)
            if not parent then
                self:unhookHumanoid(hum) 
            end
        end)
        insert(connections, ancestryConn)

        State.EnemyTracks[hum] = connections
    end

    function AutoParry:Start()
        if self.enabled then return end
        self.enabled = true
        
        for _, v in ipairs(Workspace:GetDescendants()) do
            if v:IsA("Animator") then self:processAnim(v) end
        end

        if not self.descAdd then
            self.descAdd = trackGlobal(Workspace.DescendantAdded:Connect(function(v)
                if v:IsA("Animator") then self:processAnim(v) end
            end))
        end
        
        debugNote("Auto Parry", "Enabled", 2)
    end

    function AutoParry:Stop()
        self.enabled = false
        table.clear(State.PendingParries)
        debugNote("Auto Parry", "Disabled", 2)
    end

    -- // Config Management // --
    
    local function tryRead(path)
        if not (isfile and isfile(path)) then return nil end
        local ok, data = pcall(readfile, path)
        return (ok and type(data) == "string") and data or nil
    end

    local function getFileSig(path)
        local d = tryRead(path)
        return d and (tostring(#d) .. ":" .. string.sub(d, 1, 64)) or "nil"
    end

    local function parseConfig(obj)
        local new = {}
        for id, d in pairs(obj) do
            if type(d) == "table" then
                new[id] = {
                    name = d.name or "Unknown",
                    startSec = tonumber(d.startSec) or 0,
                    hold = tonumber(d.hold) or 0.35,
                    rollOnFail = (d.rollOnFail ~= false),
                    distanceAdj = tonumber(d.distanceAdj) or 0,
                    repeats = d.repeats or {},
                    priority = tostring(d.priority or "parry"):lower(),
                    enabled = (d.enabled ~= false),
                }
            end
        end
        return new
    end

    local function loadConfigs()
        local selected = AutoParry.ConfigPresets[AutoParry.currentPresetIndex] or AutoParry.ConfigPresets[1]
        local loadedConfig, loadedExtra = AutoParry.AP_Config_Default, AutoParry.AP_ConfigExtra_Default
        local mainFrom, animCount = "default", 0

        -- Main Config
        if selected.Url then
            local s, r = pcall(game.HttpGet, game, selected.Url)
            if s then
                local s2, d = pcall(HttpService.JSONDecode, HttpService, r)
                if s2 then 
                    loadedConfig = parseConfig(d)
                    mainFrom = "Web: " .. selected.Name
                end
            end
        elseif isfile(AutoParry.apFile) then
            local content = tryRead(AutoParry.apFile)
            if content then
                local s2, d = pcall(HttpService.JSONDecode, HttpService, content)
                if s2 then 
                    loadedConfig = parseConfig(d)
                    mainFrom = "File: Custom"
                end
            end
        end
        AutoParry.AP_Config = loadedConfig

        -- Extra Config
        if isfile(AutoParry.apExtraFile) then
             local content = tryRead(AutoParry.apExtraFile)
             if content then
                local s2, d = pcall(HttpService.JSONDecode, HttpService, content)
                if s2 then loadedExtra = d end
             end
        end
        AutoParry.AP_ConfigExtra = loadedExtra
        
        local pKey = AutoParry.AP_ConfigExtra.parryKey or "F"
        local rKey = AutoParry.AP_ConfigExtra.rollKey or "Q"
        AutoParry.keyCode = Enum.KeyCode[pKey:upper()] or Enum.KeyCode.F
        AutoParry.rollKey = Enum.KeyCode[rKey:upper()] or Enum.KeyCode.Q

        for _ in pairs(AutoParry.AP_Config) do animCount = animCount + 1 end
        return mainFrom, animCount
    end

    loadConfigs()

    -- // Auto Refresh Logic // --
    getgenv()._AP_AUTOREFRESH = getgenv()._AP_AUTOREFRESH or {}
    local APAR = getgenv()._AP_AUTOREFRESH

    if not APAR._started then
        APAR._started = true
        APAR.enabled = false
        APAR.lastMainSig = nil
        APAR.lastExtraSig = nil

        task.spawn(function()
            while true do
                task.wait(1)
                if APAR.enabled and APAR.Callback then pcall(APAR.Callback) end
            end
        end)
    end

    APAR.Callback = function()
        local isLocal = (AutoParry.ConfigPresets[AutoParry.currentPresetIndex].Url == nil)
        local newMain = isLocal and getFileSig(AutoParry.apFile) or APAR.lastMainSig
        local newExtra = getFileSig(AutoParry.apExtraFile)

        if newMain ~= APAR.lastMainSig or newExtra ~= APAR.lastExtraSig then
            APAR.lastMainSig = newMain
            APAR.lastExtraSig = newExtra
            local m, count = loadConfigs()
            if Library and Library.Notify then
                Library:Notify({ Title = "AutoParry Refreshed", Description = ("%s (%d Anims)"):format(m, count), Time = 4 })
            end
        end
    end

    -- // GUI // --
    local Group = Tabs.Combat:AddRightGroupbox("Auto Parry", "swords")

    Group:AddToggle("AP_Enable", { Text = "Enable Auto Parry", Default = false })
        :AddKeyPicker("AP_ToggleKey", { Default = nil, SyncToggleState = true, Mode = "Toggle" })

    Group:AddDropdown('AP_ConfigProfile', {
        Values = (function()
            local t = {}
            for _, v in ipairs(AutoParry.ConfigPresets) do table.insert(t, v.Name) end
            return t
        end)(),
        Default = 1,
        Multi = false,
        Text = 'Config Profile',
    })

    Group:AddSlider("AP_Range", { Text = "Range", Default = 14, Min = 5, Max = 50, Suffix = " studs" })
    Group:AddDivider()
    Group:AddToggle("AP_UseFov", { Text = "Use FOV Check", Default = false })
    Group:AddSlider("AP_FovLimit", { Text = "FOV Angle", Default = 180, Min = 45, Max = 360, Suffix = " deg" })
    Group:AddDivider()
    Group:AddToggle("AP_Ping", { Text = "Ping Compensation", Default = true })
    Group:AddSlider("AP_PingScale", { Text = "Ping Scale", Default = 100, Min = 0, Max = 150, Suffix = "%" })
    Group:AddSlider("AP_Bias", { Text = "Extra Bias", Default = 0, Min = -150, Max = 150, Suffix = " ms" })
    Group:AddDivider()
    Group:AddToggle("AP_RollOnFail", { Text = "Roll on Fail", Default = true })
    Group:AddSlider("AP_FailWindow", { Text = "Fail Window", Default = 0.25, Min = 0, Max = 1, Suffix = " s" })
    Group:AddToggle("AP_Debug", { Text = "Debug Info", Default = false })
    
    Group:AddToggle("AP_AutoRefresh", { Text = "Auto-Refresh (Local File)", Default = false })

    Group:AddButton({
        Text = "Launch Config Builder",
        Func = function()
            local url = "https://raw.githubusercontent.com/whodunitwww/noxhelpers/refs/heads/main/apBuilder.lua"
            loadstring(game:HttpGet(url))()({
                GameDir = References.gameDir,
                DefaultConfig = AutoParry.AP_Config,
                DefaultExtra = AutoParry.AP_ConfigExtra,
                CounterEditEnabled = false
            })
        end,
    })

    Group:AddButton({
        Text = "Launch Anim Player",
        Func = function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/whodunitwww/noxhelpers/refs/heads/main/animPlayer.lua"))()
        end,
    })

    -- // Events // --
    Toggles.AP_Enable:OnChanged(function(v) if v then AutoParry:Start() else AutoParry:Stop() end end)
    Options.AP_Range:OnChanged(function(v) AutoParry.range = v; State.RangeSq = v*v end)
    Toggles.AP_UseFov:OnChanged(function(v) AutoParry.useFov = v end)
    Options.AP_FovLimit:OnChanged(function(v) AutoParry.fovLimit = v; State.FovThreshold = math.cos(math.rad(v/2)) end)
    Toggles.AP_Debug:OnChanged(function(v) AutoParry.debug = v end)
    Toggles.AP_Ping:OnChanged(function(v) AutoParry.pingOn = v end)
    Options.AP_PingScale:OnChanged(function(v) AutoParry.pingScale = v end)
    Options.AP_Bias:OnChanged(function(v) AutoParry.extraBiasMs = v end)
    Toggles.AP_RollOnFail:OnChanged(function(v) AutoParry.rollOnFailGlob = v end)
    Options.AP_FailWindow:OnChanged(function(v) AutoParry.parryFailTime = v end)
    Toggles.AP_AutoRefresh:OnChanged(function(v)
        APAR.enabled = v
        if v then
            APAR.lastMainSig = getFileSig(AutoParry.apFile)
            APAR.lastExtraSig = getFileSig(AutoParry.apExtraFile)
        end
    end)
    
    Options.AP_ConfigProfile:OnChanged(function(val)
        for i, v in ipairs(AutoParry.ConfigPresets) do
            if v.Name == val then
                AutoParry.currentPresetIndex = i
                local m, c = loadConfigs()
                if Library.Notify then Library:Notify(("Switched: %s (%d anims)"):format(m, c), 3) end
                break
            end
        end
    end)

    -- // Final Unloader // --
    if Unloader then
        Unloader:Register(function()
            AutoParry:Stop()
            for _, c in ipairs(State.MainConnections) do
                if c and c.Disconnect then pcall(c.Disconnect, c) end
            end
            for hum, _ in pairs(State.EnemyTracks) do
                AutoParry:unhookHumanoid(hum)
            end
            table.clear(State.MainConnections)
            table.clear(State.PendingParries)
        end)
    end

    return {}
end
