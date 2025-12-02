-- autoFarmSrc.lua
-- Simple unified auto farm (ores + enemies) using AttachPanel
-- Outsourced module version.

return function(ctx)
    ----------------------------------------------------------------
    -- CONTEXT BINDINGS
    ----------------------------------------------------------------
    local Services     = ctx.Services
    local Tabs         = ctx.Tabs
    local References   = ctx.References
    local Library      = ctx.Library
    local Options      = ctx.Options
    local Toggles      = ctx.Toggles
    local META         = ctx.META or {}

    local AttachPanel = ctx.AttachPanel
    local MoveToPos   = ctx.MoveToPos
    local RunService  = Services.RunService

    ----------------------------------------------------------------
    -- INTERNAL HELPERS
    ----------------------------------------------------------------

    local function getLocalHRP()
        return References.humanoidRootPart
    end

    local function notify(msg, time)
        if Library and Library.Notify then
            Library:Notify(msg, time or 3)
        end
    end

    -- Shared ToolService remote
    local ToolActivatedRF = Services.ReplicatedStorage
        :WaitForChild("Shared")
        :WaitForChild("Packages")
        :WaitForChild("Knit")
        :WaitForChild("Services")
        :WaitForChild("ToolService")
        :WaitForChild("RF")
        :WaitForChild("ToolActivated")

    local function swingTool(remoteArg)
        local ok, err = pcall(function()
            ToolActivatedRF:InvokeServer(remoteArg)
        end)
        if not ok then
            warn("[AutoFarm] ToolActivated error:", err)
        end
    end

    -- ====================================================================
    --  PRIORITY TABLES
    -- ====================================================================

    local OrePriority = {
        ["Volcanic Rock"] = 1,
        ["Basalt Vein"]   = 2,
        ["Basalt Core"]   = 3,
        ["Basalt Rock"]   = 4,
    }

    local EnemyPriority = {
        ["Blazing Slime"]           = 1,
        ["Elite Deathaxe Skeleton"] = 2,
        ["Reaper"]                  = 3,
        ["Elite Rogue Skeleton"]    = 4,
        ["Deathaxe Skeleton"]       = 5,
        ["Axe Skeleton"]            = 6,
        ["Skeleton Rogue"]          = 7,
        ["Bomber"]                  = 8,
    }

    local function getTargetPriorityForMode(modeName, baseName)
        if modeName == "Ores" then
            return OrePriority[baseName] or 999
        elseif modeName == "Enemies" then
            return EnemyPriority[baseName] or 999
        end
        return 999
    end

    -- ====================================================================
    --  FARM STATE + FLAGS
    -- ====================================================================

    local AvoidLava         = false
    local AvoidPlayers      = false
    local PlayerAvoidRadius = 40
    local DamageDitchEnabled = false
    
    -- Ore Whitelist
    local OreWhitelistEnabled = false
    local WhitelistedOres     = {} 

    -- Zone Whitelist
    local ZoneWhitelistEnabled = false
    local WhitelistedZones     = {} 

    -- Target blacklist (per-instance)
    local TargetBlacklist   = {}  -- [Instance] = expiryTime (os.clock())

    local FarmState = {
        enabled       = false,
        mode          = "Ores", 
        selectedNames = {},   
        nameMap       = {},

        currentTarget = nil,
        moveCleanup   = nil,
        farmThread    = nil,
        noclipConn    = nil, -- Noclip Connection

        attached      = false,
        lastHit       = 0,
        detourActive  = false,

        -- Stuck detection
        lastTargetRef    = nil,
        lastTargetHealth = 0,
        stuckStartTime   = 0,
        
        -- Local Health Tracking for Damage Ditch
        LastLocalHealth  = 100, 
    }

    -- ====================================================================
    --  NOCLIP SYSTEM
    -- ====================================================================

    local function enableNoclip()
        if FarmState.noclipConn then return end
        FarmState.noclipConn = RunService.Stepped:Connect(function()
            local char = References.character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end
        end)
    end

    local function disableNoclip()
        if FarmState.noclipConn then
            FarmState.noclipConn:Disconnect()
            FarmState.noclipConn = nil
        end
        -- Optional: Restore collision if needed, but usually walking restores it naturally or game physics handle it.
    end

    -- ====================================================================
    --  ORE HELPERS
    -- ====================================================================

    local function getRocksFolder()
        return Services.Workspace:FindFirstChild("Rocks")
    end

    -- Helper: Walk up the parent chain to find which Zone (direct child of Rocks) this model belongs to
    local function getZoneFromDescendant(model)
        local rocksFolder = getRocksFolder()
        if not rocksFolder then return nil end
        
        local current = model.Parent
        while current and current ~= game do
            if current.Parent == rocksFolder then
                return current.Name -- This is the Zone Folder Name
            end
            if current == rocksFolder then
                return nil -- Direct child of Rocks, technically no zone subfolder
            end
            current = current.Parent
        end
        return nil
    end

    local function rockHealth(model)
        if not model or not model.Parent then
            return nil
        end
        local ok, value = pcall(function()
            return model:GetAttribute("Health")
        end)
        if not ok or value == nil then
            return nil
        end
        return tonumber(value)
    end

    local function isRockAlive(model)
        local h = rockHealth(model)
        return h and h > 0
    end

    local function rockRoot(model)
        if not model or not model.Parent then return nil end
        if model:IsA("BasePart") then
            return model
        end

        local part = AttachPanel.HrpOf and AttachPanel.HrpOf(model) or nil
        if part then return part end

        for _, inst in ipairs(model:GetDescendants()) do
            if inst:IsA("BasePart") then
                return inst
            end
        end
        return nil
    end

    local function rockPosition(model)
        local root = rockRoot(model)
        return root and root.Position or nil
    end

    -- Cache for the goblin cave folder
    local GoblinCaveFolder = nil

    local function getGoblinCaveFolder()
        if GoblinCaveFolder and GoblinCaveFolder.Parent then
            return GoblinCaveFolder
        end

        local rocksFolder = getRocksFolder()
        if not rocksFolder then
            GoblinCaveFolder = nil
            return nil
        end

        local cave = rocksFolder:FindFirstChild("Island2GoblinCave")
        if cave and cave:IsA("Folder") then
            GoblinCaveFolder = cave
        else
            GoblinCaveFolder = nil
        end

        return GoblinCaveFolder
    end

    local function scanRocks()
        local rocksFolder = getRocksFolder()
        local nameMap = {}
        local uniqueNames = {}

        if not rocksFolder then
            return nameMap, uniqueNames
        end

        local caveFolder = getGoblinCaveFolder()

        for _, inst in ipairs(rocksFolder:GetDescendants()) do
            if inst:IsA("Model") then
                -- HARD IGNORE: anything inside workspace.Rocks.Island2GoblinCave
                if caveFolder and inst:IsDescendantOf(caveFolder) then
                    -- skip
                else
                    local parent = inst.Parent
                    -- Skip nested models like Rock["20"]
                    if not (parent and parent ~= rocksFolder and parent:IsA("Model")) then
                        
                        -- ZONE CHECK (Recursive Parent Check)
                        local passedZone = true
                        if ZoneWhitelistEnabled then
                            local zoneName = getZoneFromDescendant(inst)
                            if not zoneName or not WhitelistedZones[zoneName] then
                                passedZone = false
                            end
                        end

                        if passedZone and rockHealth(inst) then
                            local name = inst.Name
                            if not nameMap[name] then
                                nameMap[name] = {}
                                uniqueNames[#uniqueNames + 1] = name
                            end
                            table.insert(nameMap[name], inst)
                        end
                    end
                end
            end
        end

        table.sort(uniqueNames)
        return nameMap, uniqueNames
    end

    local function getGameOreTypes()
        local assets = Services.ReplicatedStorage:FindFirstChild("Assets")
        local oresFolder = assets and assets:FindFirstChild("Ores")
        
        local list = {}
        if oresFolder then
            for _, v in ipairs(oresFolder:GetChildren()) do
                table.insert(list, v.Name)
            end
        end
        
        table.sort(list)
        return list
    end

    local function scanZones()
        local rocksFolder = getRocksFolder()
        local zones = {}
        if rocksFolder then
            for _, child in ipairs(rocksFolder:GetChildren()) do
                if child:IsA("Folder") then
                    table.insert(zones, child.Name)
                end
            end
        end
        table.sort(zones)
        return zones
    end

    -- ====================================================================
    --  MOB HELPERS
    -- ====================================================================

    local function getLivingFolder()
        local living = Services.Workspace:FindFirstChild("Living")
        if living and living:IsA("Folder") then
            return living
        end
        return nil
    end

    local function normalizeMobName(name)
        local base = tostring(name or "")
        base = base:gsub("%d+$", "")   -- remove trailing digits
        base = base:gsub("%s+$", "")   -- trim trailing spaces
        if base == "" then
            base = tostring(name or "Mob")
        end
        return base
    end

    local function isPlayerModel(model)
        if not model then return false end
        for _, pl in ipairs(Services.Players:GetPlayers()) do
            local char = pl.Character
            if char and (model == char or model:IsDescendantOf(char)) then
                return true
            end
            if model.Name == pl.Name or model.Name:find(pl.Name, 1, true) then
                return true
            end
        end
        return false
    end

    local function getMobRoot(model)
        if not model or not model.Parent then return nil end
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp then return hrp end
        if model.PrimaryPart then return model.PrimaryPart end
        return model:FindFirstChildWhichIsA("BasePart")
    end

    local function mobPosition(model)
        local root = getMobRoot(model)
        return root and root.Position or nil
    end

    local function isMobAlive(model)
        if not model or not model.Parent then return false end
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not hum then return false end
        if hum.Health <= 0 then return false end
        if hum:GetState() == Enum.HumanoidStateType.Dead then return false end
        return true
    end

    local function getMobHealth(model)
        if not model or not model.Parent then return nil end
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not hum then return nil end
        return hum.Health
    end

    local function scanMobs()
        local nameMap = {}
        local names   = {}

        local living = getLivingFolder()
        if not living then
            return nameMap, names
        end

        for _, m in ipairs(living:GetChildren()) do
            if m:IsA("Model") then
                local hum = m:FindFirstChildOfClass("Humanoid")
                if hum and not isPlayerModel(m) then
                    local baseName = normalizeMobName(m.Name)
                    local bucket = nameMap[baseName]
                    if not bucket then
                        bucket = {}
                        nameMap[baseName] = bucket
                        table.insert(names, baseName)
                    end
                    table.insert(bucket, m)
                end
            end
        end

        table.sort(names)
        return nameMap, names
    end

    -- ====================================================================
    --  ATTACH CONFIG
    -- ====================================================================

    local ORE_ATTACH_MODE   = "Aligned"
    local ORE_ATTACH_Y_BASE = -8
    local ORE_ATTACH_HORIZ  = 0
    local ORE_HIT_INTERVAL  = 0.2
    local ORE_HIT_DIST      = 10

    local MOB_ATTACH_MODE   = "Aligned"
    local MOB_ATTACH_Y_BASE = -7
    local MOB_ATTACH_HORIZ  = 0
    local MOB_HIT_INTERVAL  = 0.25
    local MOB_HIT_DIST      = 12

    local ExtraYOffset      = 0      -- global Y offset
    local FarmSpeed         = 80     -- movement speed

    local FARM_MODE_ORES    = "Ores"
    local FARM_MODE_ENEMIES = "Enemies"

    -- Max target height (any target above this Y is ignored)
    local MaxTargetHeight   = 100

    local ModeDefs = {
        [FARM_MODE_ORES] = {
            name          = FARM_MODE_ORES,
            scan          = scanRocks,
            isAlive       = isRockAlive,
            getPos        = rockPosition,
            getRoot       = rockRoot,
            getHealth     = rockHealth,
            attachMode    = ORE_ATTACH_MODE,
            attachBaseY   = ORE_ATTACH_Y_BASE,
            attachHoriz   = ORE_ATTACH_HORIZ,
            hitInterval   = ORE_HIT_INTERVAL,
            hitDistance   = ORE_HIT_DIST,
            toolName      = "Pickaxe",
            toolRemoteArg = "Pickaxe",
        },

        [FARM_MODE_ENEMIES] = {
            name          = FARM_MODE_ENEMIES,
            scan          = scanMobs,
            isAlive       = isMobAlive,
            getPos        = mobPosition,
            getRoot       = getMobRoot,
            getHealth     = getMobHealth,
            attachMode    = MOB_ATTACH_MODE,
            attachBaseY   = MOB_ATTACH_Y_BASE,
            attachHoriz   = MOB_ATTACH_HORIZ,
            hitInterval   = MOB_HIT_INTERVAL,
            hitDistance   = MOB_HIT_DIST,
            toolName      = "Weapon",
            toolRemoteArg = "Weapon",
        },
    }

    local function configureAttachForMode(modeName)
        local def = ModeDefs[modeName]
        if not def then return end

        local y = def.attachBaseY + ExtraYOffset

        if AttachPanel.SetMode then
            AttachPanel.SetMode(def.attachMode)
        end
        if AttachPanel.SetYOffset then
            AttachPanel.SetYOffset(y)
        end
        if AttachPanel.SetHorizDist then
            AttachPanel.SetHorizDist(def.attachHoriz)
        end
        if AttachPanel.SetMovement then
            AttachPanel.SetMovement("Approach")
        end
        if AttachPanel.EnableAutoYOffset then
            AttachPanel.EnableAutoYOffset(false)
        end
        if AttachPanel.EnableDodge then
            AttachPanel.EnableDodge(false)
        end
    end

    -- Save/restore attach state so we don’t mess user’s settings permanently
    local SavedAttach = nil

    local function saveAttachSettings()
        local state = AttachPanel.State or {}
        SavedAttach = {
            mode        = state.mode,
            yOffset     = state.yOffset,
            horizDist   = state.horizDist,
            movement    = state.movement,
            autoYOffset = state.autoYOffset,
            dodgeMode   = state.dodgeMode,
            dodgeRange  = state.dodgeRange,
        }
    end

    local function restoreAttachSettings()
        if not SavedAttach then return end
        if AttachPanel.SetMode then
            AttachPanel.SetMode(SavedAttach.mode)
        end
        if AttachPanel.SetYOffset then
            AttachPanel.SetYOffset(SavedAttach.yOffset)
        end
        if AttachPanel.SetHorizDist then
            AttachPanel.SetHorizDist(SavedAttach.horizDist)
        end
        if AttachPanel.SetMovement then
            AttachPanel.SetMovement(SavedAttach.movement)
        end
        if AttachPanel.EnableAutoYOffset then
            AttachPanel.EnableAutoYOffset(SavedAttach.autoYOffset)
        end
        if AttachPanel.EnableDodge then
            AttachPanel.EnableDodge(SavedAttach.dodgeMode)
        end
        local state = AttachPanel.State
        if state then
            state.dodgeRange = SavedAttach.dodgeRange
        end
        SavedAttach = nil
    end

    -- ====================================================================
    --  PROGRESS HUD SYSTEM (LARGER & IMPROVED)
    -- ====================================================================
    
    local HudState = {
        Enabled      = false,
        Gui          = nil,
        Container    = nil,
        TargetName   = nil,
        HealthBar    = nil,
        HealthText   = nil,
        DropList     = nil,
        
        -- Tracking
        CachedMaxHp  = 100,
        CurrentDrops = {}, -- [ChildInstance] = true
    }

    local function createHudGui()
        if HudState.Gui then return end
        
        local sg = Instance.new("ScreenGui")
        sg.Name = "AutoFarmHUD"
        sg.ResetOnSpawn = false
        pcall(function()
            sg.Parent = Services.Players.LocalPlayer:WaitForChild("PlayerGui")
        end)
        
        -- Main Container (Larger Size)
        local mainFrame = Instance.new("Frame")
        mainFrame.Name = "MainFrame"
        mainFrame.Size = UDim2.new(0, 320, 0, 180) -- Increased size
        mainFrame.Position = UDim2.new(0.5, 0, 0.2, 0)
        mainFrame.AnchorPoint = Vector2.new(0.5, 0)
        mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
        mainFrame.BorderSizePixel = 0
        mainFrame.Parent = sg
        
        -- Rounded Corners
        local uiCorner = Instance.new("UICorner")
        uiCorner.CornerRadius = UDim.new(0, 8)
        uiCorner.Parent = mainFrame
        
        -- Subtle Stroke
        local uiStroke = Instance.new("UIStroke")
        uiStroke.Color = Color3.fromRGB(60, 60, 70)
        uiStroke.Thickness = 2
        uiStroke.Transparency = 0.2
        uiStroke.Parent = mainFrame
        
        -- Padding
        local mainPadding = Instance.new("UIPadding")
        mainPadding.PaddingTop = UDim.new(0, 12)
        mainPadding.PaddingBottom = UDim.new(0, 12)
        mainPadding.PaddingLeft = UDim.new(0, 12)
        mainPadding.PaddingRight = UDim.new(0, 12)
        mainPadding.Parent = mainFrame
        
        -- Target Name Header
        local tName = Instance.new("TextLabel")
        tName.Name = "TargetName"
        tName.Size = UDim2.new(1, 0, 0, 26)
        tName.BackgroundTransparency = 1
        tName.TextColor3 = Color3.fromRGB(255, 255, 255)
        tName.Font = Enum.Font.GothamBold
        tName.TextSize = 18 -- Larger font
        tName.Text = "🎯 Searching..."
        tName.TextXAlignment = Enum.TextXAlignment.Left
        tName.TextTruncate = Enum.TextTruncate.AtEnd
        tName.Parent = mainFrame
        
        -- Health Bar Container
        local barBg = Instance.new("Frame")
        barBg.Name = "BarBG"
        barBg.Size = UDim2.new(1, 0, 0, 18) -- Thicker bar
        barBg.Position = UDim2.new(0, 0, 0, 34)
        barBg.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
        barBg.BorderSizePixel = 0
        barBg.Parent = mainFrame
        
        local barCorner = Instance.new("UICorner")
        barCorner.CornerRadius = UDim.new(0, 5)
        barCorner.Parent = barBg
        
        -- Health Bar Fill
        local barFill = Instance.new("Frame")
        barFill.Name = "Fill"
        barFill.Size = UDim2.new(1, 0, 1, 0)
        barFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        barFill.BorderSizePixel = 0
        barFill.Parent = barBg
        
        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(0, 5)
        fillCorner.Parent = barFill
        
        -- Gradient
        local gradient = Instance.new("UIGradient")
        gradient.Color = ColorSequence.new{
            ColorSequenceKeypoint.new(0, Color3.fromRGB(85, 255, 120)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 170, 120))
        }
        gradient.Parent = barFill
        
        -- Health Text
        local hpText = Instance.new("TextLabel")
        hpText.Size = UDim2.new(1, 0, 1, 0)
        hpText.BackgroundTransparency = 1
        hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
        hpText.Font = Enum.Font.GothamBold
        hpText.TextSize = 12
        hpText.TextStrokeTransparency = 0.5
        hpText.Text = "100 / 100"
        hpText.ZIndex = 2
        hpText.Parent = barBg
        
        -- Drops Header Label
        local dLabel = Instance.new("TextLabel")
        dLabel.Name = "DropsLabel"
        dLabel.Size = UDim2.new(1, 0, 0, 20)
        dLabel.Position = UDim2.new(0, 0, 0, 62)
        dLabel.BackgroundTransparency = 1
        dLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        dLabel.Font = Enum.Font.Gotham
        dLabel.TextSize = 14
        dLabel.Text = "💎 Drops Detected:"
        dLabel.TextXAlignment = Enum.TextXAlignment.Left
        dLabel.Parent = mainFrame
        
        -- Drop List Container
        local dropContainer = Instance.new("Frame")
        dropContainer.Name = "DropContainer"
        dropContainer.Size = UDim2.new(1, 0, 1, -85) -- Fill remaining space
        dropContainer.Position = UDim2.new(0, 0, 0, 85)
        dropContainer.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
        dropContainer.BorderSizePixel = 0
        dropContainer.Parent = mainFrame
        
        local dropCorner = Instance.new("UICorner")
        dropCorner.CornerRadius = UDim.new(0, 6)
        dropCorner.Parent = dropContainer
        
        -- ScrollingFrame
        local dList = Instance.new("ScrollingFrame")
        dList.Name = "DropList"
        dList.Size = UDim2.new(1, -10, 1, -10)
        dList.Position = UDim2.new(0, 5, 0, 5)
        dList.BackgroundTransparency = 1
        dList.BorderSizePixel = 0
        dList.ScrollBarThickness = 4
        dList.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 80)
        dList.AutomaticCanvasSize = Enum.AutomaticSize.Y
        dList.CanvasSize = UDim2.new(0, 0, 0, 0)
        dList.Parent = dropContainer
        
        local layout = Instance.new("UIListLayout")
        layout.Parent = dList
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 4)
        
        HudState.Gui = sg
        HudState.Container = mainFrame
        HudState.TargetName = tName
        HudState.HealthBar = barFill
        HudState.HealthText = hpText
        HudState.DropList = dList
        
        sg.Enabled = false
    end
    
    local function updateHudLogic(target, def)
        if not HudState.Enabled or not HudState.Gui then
            if HudState.Gui then HudState.Gui.Enabled = false end
            return
        end
        
        if not target or not target.Parent then
            HudState.Gui.Enabled = false
            return
        end
        
        HudState.Gui.Enabled = true
        HudState.TargetName.Text = "🎯 " .. target.Name
        
        -- Health Logic
        local hp = def.getHealth(target) or 0
        if hp > HudState.CachedMaxHp then
            HudState.CachedMaxHp = hp
        end
        local attrMax = target:GetAttribute("MaxHealth")
        if attrMax then HudState.CachedMaxHp = attrMax end
        
        local maxHp = math.max(HudState.CachedMaxHp, 1)
        local pct = math.clamp(hp / maxHp, 0, 1)
        
        HudState.HealthBar:TweenSize(UDim2.new(pct, 0, 1, 0), "Out", "Quad", 0.15, true)
        HudState.HealthText.Text = math.floor(hp) .. " / " .. math.floor(maxHp)
        
        -- Scanned Drops
        local children = target:GetChildren()
        for _, c in ipairs(children) do
            if c.Name == "Ore" and not HudState.CurrentDrops[c] then
                local oreType = c:GetAttribute("Ore")
                if oreType then
                    HudState.CurrentDrops[c] = true
                    
                    local lbl = Instance.new("TextLabel")
                    lbl.Size = UDim2.new(1, 0, 0, 20) -- Bigger rows
                    lbl.BackgroundTransparency = 1
                    lbl.TextColor3 = Color3.fromRGB(255, 215, 0)
                    lbl.Font = Enum.Font.GothamMedium
                    lbl.TextSize = 14 -- Bigger drop text
                    lbl.Text = "  ✨ " .. tostring(oreType)
                    lbl.TextXAlignment = Enum.TextXAlignment.Left
                    lbl.Parent = HudState.DropList
                    
                    HudState.DropList.CanvasPosition = Vector2.new(0, 9999)
                end
            end
        end
    end
    
    local function resetHudForNewTarget(target, def)
        if not HudState.Gui then return end
        
        -- Clear drops
        for _, c in ipairs(HudState.DropList:GetChildren()) do
            if c:IsA("TextLabel") then c:Destroy() end
        end
        table.clear(HudState.CurrentDrops)
        
        if target then
            local hp = def.getHealth(target) or 100
            local attrMax = target:GetAttribute("MaxHealth")
            HudState.CachedMaxHp = attrMax or hp
        end
    end

    local function stopMoving()
        if FarmState.moveCleanup then
            pcall(FarmState.moveCleanup)
            FarmState.moveCleanup = nil
        end
    end

    -- ====================================================================
    --  BLACKLIST HELPERS
    -- ====================================================================

    local function isTargetBlacklisted(model)
        if not model then return false end
        local expiry = TargetBlacklist[model]
        if not expiry then return false end

        if not model.Parent or os.clock() >= expiry then
            TargetBlacklist[model] = nil
            return false
        end

        return true
    end

    local function blacklistTarget(model, duration)
        if not model then return end
        TargetBlacklist[model] = os.clock() + (duration or 60)
    end

    -- ====================================================================
    --  SAFE OFFSET WRAPPER (PROTECTS AGAINST ATTACHPANEL ERRORS)
    -- ====================================================================

    local function safeComputeOffset(rootCFrame, def)
        if not AttachPanel or not AttachPanel.ComputeOffset then
            return Vector3.new(0, def.attachBaseY + ExtraYOffset, 0)
        end

        local ok, result = pcall(
            AttachPanel.ComputeOffset,
            rootCFrame,
            def.attachMode,
            def.attachHoriz,
            def.attachBaseY + ExtraYOffset
        )

        if ok and typeof(result) == "Vector3" then
            return result
        end

        -- Fallback: straight down offset
        return Vector3.new(0, def.attachBaseY + ExtraYOffset, 0)
    end

    -- ====================================================================
    --  LAVA AVOIDANCE
    -- ====================================================================

    local LavaParts = {}

    local function refreshLavaParts()
        table.clear(LavaParts)

        local ws = Services.Workspace
        if not ws then return end

        local assets = ws:FindFirstChild("Assets")
        if assets then
            local cave = assets:FindFirstChild("Cave Area [2]")
            if cave then
                local folder = cave:FindFirstChild("Folder")
                if folder then
                    for _, inst in ipairs(folder:GetDescendants()) do
                        if inst:IsA("BasePart") and inst.Name == "Lava" then
                            table.insert(LavaParts, inst)
                        end
                    end
                end
            end
        end

        local debris = ws:FindFirstChild("Debris")
        if debris then
            local lavaZone = debris:FindFirstChild("LavaDamageZone")
            if lavaZone and lavaZone:IsA("BasePart") then
                table.insert(LavaParts, lavaZone)
            end
        end
    end


    local function pointInsidePart(point, part)
        if not part or not part.Parent then return false end
        local relative = part.CFrame:PointToObjectSpace(point)
        local half = part.Size / 2
        return math.abs(relative.X) <= half.X
           and math.abs(relative.Y) <= half.Y
           and math.abs(relative.Z) <= half.Z
    end

    -- IMPORTANT: This function is hard-gated by AvoidLava.
    -- If AvoidLava == false, it **always** returns false and does no lava logic.
    local function isPointInLava(point)
        if not AvoidLava then
            -- Lava avoidance disabled: never treat any point as lava.
            return false
        end

        if #LavaParts == 0 then
            refreshLavaParts()
        end
        for _, part in ipairs(LavaParts) do
            if pointInsidePart(point, part) then
                return true
            end
        end
        return false
    end

    -- ====================================================================
    --  PLAYER AVOIDANCE HELPERS
    -- ====================================================================

    local function isAnyPlayerNearHRP(radius)
        local hrp = getLocalHRP()
        if not hrp then return false, nil end

        local myPlayer = References.player
        for _, plr in ipairs(Services.Players:GetPlayers()) do
            if plr ~= myPlayer then
                local char = plr.Character
                local phrp = char and char:FindFirstChild("HumanoidRootPart")
                if phrp then
                    local dist = (phrp.Position - hrp.Position).Magnitude
                    if dist <= radius then
                        return true, plr
                    end
                end
            end
        end
        return false, nil
    end

    local function isAnyPlayerNearPosition(position, radius)
        if not position then return false, nil end

        local myPlayer = References.player
        for _, plr in ipairs(Services.Players:GetPlayers()) do
            if plr ~= myPlayer then
                local char = plr.Character
                local phrp = char and char:FindFirstChild("HumanoidRootPart")
                if phrp then
                    local dist = (phrp.Position - position).Magnitude
                    if dist <= radius then
                        return true, plr
                    end
                end
            end
        end

        return false, nil
    end

    -- Idle horizontal move away from players
    local function moveAwayFromNearbyPlayers()
        if not AvoidPlayers then return end

        local hrp = getLocalHRP()
        if not hrp then return end

        local myPlayer = References.player
        local hrpPos   = hrp.Position

        local closestDist = math.huge
        local closestPos  = nil

        for _, plr in ipairs(Services.Players:GetPlayers()) do
            if plr ~= myPlayer then
                local char = plr.Character
                local phrp = char and char:FindFirstChild("HumanoidRootPart")
                if phrp then
                    local dist = (phrp.Position - hrpPos).Magnitude
                    if dist <= PlayerAvoidRadius and dist < closestDist then
                        closestDist = dist
                        closestPos  = phrp.Position
                    end
                end
            end
        end

        if closestPos then
            -- Horizontal direction away from player
            local away = hrpPos - closestPos
            away = Vector3.new(away.X, 0, away.Z)
            local mag = away.Magnitude
            if mag < 1 then
                -- If basically on top, pick arbitrary sideways
                away = Vector3.new(1, 0, 0)
            else
                away = away / mag
            end

            local targetPos = hrpPos + away * (PlayerAvoidRadius + 10)
            targetPos = Vector3.new(targetPos.X, hrpPos.Y, targetPos.Z)

            stopMoving()
            FarmState.moveCleanup = MoveToPos(targetPos, FarmSpeed)
        end
    end

    -- Build a simple 1- or 2-point path around players between startPos and endPos
    local function buildPathAroundPlayers(startPos, endPos)
        if not AvoidPlayers then
            return { endPos }
        end

        local ab = endPos - startPos
        local abMag = ab.Magnitude
        if abMag < 5 then
            return { endPos }
        end

        local myPlayer = References.player
        local hitPlayerPos = nil
        local closestHitDist = math.huge

        for _, plr in ipairs(Services.Players:GetPlayers()) do
            if plr ~= myPlayer then
                local char = plr.Character
                local phrp = char and char:FindFirstChild("HumanoidRootPart")
                if phrp then
                    local p = phrp.Position

                    -- Distance from player to line segment startPos-endPos
                    local ap = p - startPos
                    local t = 0
                    local abDot = ab:Dot(ab)
                    if abDot > 0 then
                        t = math.clamp(ap:Dot(ab) / abDot, 0, 1)
                    end
                    local closestPoint = startPos + ab * t
                    local dist = (p - closestPoint).Magnitude

                    if dist <= PlayerAvoidRadius and dist < closestHitDist then
                        closestHitDist = dist
                        hitPlayerPos   = p
                    end
                end
            end
        end

        if not hitPlayerPos then
            return { endPos }
        end

        -- Compute a sideways offset around that player, horizontal only
        local sideDir = ab:Cross(Vector3.yAxis)
        if sideDir.Magnitude < 1e-3 then
            sideDir = Vector3.new(1, 0, 0)
        else
            sideDir = sideDir.Unit
        end

        local offsetDist = PlayerAvoidRadius + 8
        local mid = hitPlayerPos + sideDir * offsetDist
        -- Keep roughly horizontal movement for the detour point
        mid = Vector3.new(mid.X, startPos.Y, mid.Z)

        return { mid, endPos }
    end

    -- ====================================================================
    --  SIMPLE TARGET SELECTION (PRIORITY + NEAREST + LAVA + PLAYER AVOID)
    -- ====================================================================

    local function chooseNearestTarget()
        local hrp = getLocalHRP()
        if not hrp then return nil end

        local def = ModeDefs[FarmState.mode]
        if not def or not def.scan then return nil end

        local nameMap, _ = def.scan()
        FarmState.nameMap = nameMap or {}

        -- Quick lookup table for selected names
        local selectedLookup = {}
        for _, name in ipairs(FarmState.selectedNames) do
            selectedLookup[name] = true
        end

        local bestTarget
        local bestDist
        local bestPriority = math.huge

        for name, models in pairs(nameMap) do
            if selectedLookup[name] and models then
                -- Use shared helper so priority logic is always consistent
                local priority = getTargetPriorityForMode(FarmState.mode, name)

                for _, model in ipairs(models) do
                    if model and model.Parent and def.isAlive(model) and not isTargetBlacklisted(model) then
                        local pos = def.getPos(model)

                        if pos then
                            local skip = false

                            -- Max height filter
                            if pos.Y > MaxTargetHeight then
                                skip = true
                            end

                            -- LAVA AVOIDANCE (ORES + ENEMIES)
                            -- NOTE: guarded by AvoidLava, so when toggle is OFF, this whole block is skipped.
                            if not skip and AvoidLava then
                                local root = def.getRoot(model)
                                if root then
                                    local offset = safeComputeOffset(root.CFrame, def)
                                    local attachPos = root.Position + offset
                                    if isPointInLava(attachPos) then
                                        skip = true
                                    end
                                end
                            end

                            -- PLAYER AVOIDANCE DURING PICK
                            if not skip and AvoidPlayers then
                                local nearTarget, _ = isAnyPlayerNearPosition(pos, PlayerAvoidRadius)
                                if nearTarget then
                                    -- skip (no blacklist here; we only blacklist if it's *our* active target)
                                    skip = true
                                end
                            end

                            if not skip then
                                local dist = (pos - hrp.Position).Magnitude
                                if (priority < bestPriority)
                                    or (priority == bestPriority and (not bestDist or dist < bestDist)) then
                                    bestPriority = priority
                                    bestDist     = dist
                                    bestTarget   = model
                                end
                            end
                        end
                    end
                end
            end
        end

        return bestTarget
    end

    -- ====================================================================
    --  ATTACH + MOVEMENT
    -- ====================================================================

    local function realignAttach(target)
        if not target then return end

        local def = ModeDefs[FarmState.mode]
        if not def then return end

        local state = AttachPanel.State
        if not state then return end

        local attachA1 = state._attachA1
        local alignOri = state._alignOri
        local hrp      = getLocalHRP()
        local root     = def.getRoot(target)

        if not (attachA1 and alignOri and hrp and root) then
            return
        end

        local cf = root.CFrame
        local offsetWorld = safeComputeOffset(cf, def)
        attachA1.Position = cf:VectorToObjectSpace(offsetWorld)

        alignOri.CFrame = CFrame.lookAt(hrp.Position, root.Position, Vector3.yAxis)
    end

    local function attachToTarget(target)
        if not target then return end

        configureAttachForMode(FarmState.mode)

        if AttachPanel.SetTarget then
            AttachPanel.SetTarget(target)
        end
        if AttachPanel.CreateAttach then
            AttachPanel.CreateAttach(target)
        end

        realignAttach(target)
    end

    -- === DETOUR PATH WHEN X < -120 ======================================

    local DETOUR_THRESHOLD_X = -120
    local DETOUR_POINTS = {
        Vector3.new(-259.431091, 21.436172, -129.926697),
        Vector3.new(-417.186188, 31.620274, -246.402084),
        Vector3.new(-138.949982, 30.126343, -497.266479),
        Vector3.new(-43.032295, 32.220428, -583.377686),
        Vector3.new(118.466454, 32.614773, -567.964050),
        Vector3.new(400.246185, 135.009399, -349.578552),
        Vector3.new(336.205627, 142.614944, -237.229599),
        Vector3.new(359.745148, 74.859268, -224.669601),
    }

    local function startMovingToTarget(target)
        stopMoving()

        local hrp = getLocalHRP()
        local def = ModeDefs[FarmState.mode]
        if not (hrp and def and def.getRoot) then
            return
        end

        local function getFinalPos()
            if not target or not target.Parent then
                return nil
            end
            local root = def.getRoot(target)
            if not root then return nil end

            local offset = safeComputeOffset(root.CFrame, def)
            return root.Position + offset
        end

        local startPos = hrp.Position
        local finalPos = getFinalPos()
        if not finalPos then return end

        local useDetour = (startPos.X < DETOUR_THRESHOLD_X)

        if not useDetour then
            -- Normal path: optionally build a detour around players
            local waypoints = { finalPos }
            if AvoidPlayers then
                waypoints = buildPathAroundPlayers(startPos, finalPos)
            end

            if #waypoints == 1 then
                -- Single leg, allow dynamic target updates
                FarmState.moveCleanup = MoveToPos(finalPos, FarmSpeed, getFinalPos)
            else
                -- Multi-leg (side-step around player, then target)
                local active = true
                local currentCleanup = nil

                local function globalCleanup()
                    active = false
                    if currentCleanup then
                        pcall(currentCleanup)
                        currentCleanup = nil
                    end
                end

                FarmState.moveCleanup = globalCleanup

                task.spawn(function()
                    for _, waypoint in ipairs(waypoints) do
                        if not active then return end

                        currentCleanup = MoveToPos(waypoint, FarmSpeed)

                        while active do
                            local h = getLocalHRP()
                            if not h then
                                if currentCleanup then
                                    pcall(currentCleanup)
                                    currentCleanup = nil
                                end
                                return
                            end

                            if (h.Position - waypoint).Magnitude <= 3 then
                                if currentCleanup then
                                    pcall(currentCleanup)
                                    currentCleanup = nil
                                end
                                break
                            end

                            task.wait(0.05)
                        end
                    end

                    if active then
                        -- Done with path
                        FarmState.moveCleanup = nil
                    end
                end)
            end

            return
        end

        -- Detour path: go through each DETOUR_POINTS in order, then final dynamic leg
        local active = true
        local currentCleanup = nil

        local function globalCleanup()
            active = false
            if currentCleanup then
                pcall(currentCleanup)
                currentCleanup = nil
            end
        end

        FarmState.moveCleanup = globalCleanup

        task.spawn(function()
            for _, waypoint in ipairs(DETOUR_POINTS) do
                if not active then return end

                currentCleanup = MoveToPos(waypoint, FarmSpeed)

                while active do
                    local h = getLocalHRP()
                    if not h then
                        if currentCleanup then
                            pcall(currentCleanup)
                            currentCleanup = nil
                        end
                        return
                    end

                    if (h.Position - waypoint).Magnitude <= 3 then
                        if currentCleanup then
                            pcall(currentCleanup)
                            currentCleanup = nil
                        end
                        break
                    end

                    task.wait(0.05)
                end
            end

            if not active then return end

            local fp = getFinalPos()
            if not fp then
                globalCleanup()
                return
            end

            -- Final dynamic leg (no extra around-player logic here; caves already detoured)
            local function dynFinalPos()
                return getFinalPos()
            end

            currentCleanup = MoveToPos(fp, FarmSpeed, dynFinalPos)
            -- Cleanup of this final leg is via globalCleanup / stopMoving()
        end)
    end

    -- ====================================================================
    --  MAIN FARM LOOP (RETARGET ON PLAYER NEAR TARGET)
    -- ====================================================================

    local function farmLoop()
        -- Init health to current so we don't instant-ditch if low
        if References.humanoid then
            FarmState.LastLocalHealth = References.humanoid.Health
        end

        while FarmState.enabled do
            local hrp = getLocalHRP()
            local hum = References.humanoid

            -- death / no char handling (safe)
            if not hrp or not hum then
                stopMoving()
                FarmState.currentTarget = nil
                FarmState.attached      = false
                FarmState.detourActive  = false
                task.wait(0.3)
                continue
            end

            local humHealth
            local humState
            local okState, stateOrErr = pcall(function()
                return hum:GetState()
            end)

            if okState then
                humState  = stateOrErr
                humHealth = hum.Health
            else
                -- Humanoid probably invalid / destroyed
                stopMoving()
                FarmState.currentTarget = nil
                FarmState.attached      = false
                FarmState.detourActive  = false
                task.wait(0.3)
                continue
            end

            if humHealth <= 0 or humState == Enum.HumanoidStateType.Dead then
                stopMoving()
                FarmState.currentTarget = nil
                FarmState.attached      = false
                FarmState.detourActive  = false
                task.wait(0.3)
                continue
            end
            
            -- >>> DAMAGE DITCH LOGIC <<<
            -- Only check if we actually have a target
            if DamageDitchEnabled and FarmState.currentTarget and humHealth < FarmState.LastLocalHealth then
                notify("Took damage! Ditching.", 2)
                blacklistTarget(FarmState.currentTarget, 60)
                stopMoving()
                FarmState.currentTarget = nil
                FarmState.attached      = false
                FarmState.detourActive  = false
                updateHudLogic(nil, nil) -- Hide HUD
                
                -- Update tracking to avoid re-trigger
                FarmState.LastLocalHealth = humHealth 
                task.wait(0.15)
                continue
            end
            -- Update local health tracking for next loop
            FarmState.LastLocalHealth = humHealth

            local def = ModeDefs[FarmState.mode]
            if not def then
                task.wait(0.3)
                continue
            end

            local target = FarmState.currentTarget
            local pos    = target and def.getPos(target) or nil
            local alive  = target and def.isAlive(target)

            -- Pick new target if current is invalid or blacklisted
            if (not target)
                or (not target.Parent)
                or (not pos)
                or (not alive)
                or isTargetBlacklisted(target) then

                FarmState.currentTarget = chooseNearestTarget()
                FarmState.attached      = false
                FarmState.detourActive  = false
                
                -- Reset stuck logic for new target
                FarmState.lastTargetRef    = FarmState.currentTarget
                FarmState.lastTargetHealth = 0
                FarmState.stuckStartTime   = os.clock()
                
                -- Reset HUD logic for new target
                resetHudForNewTarget(FarmState.currentTarget, def)
                
                -- Reset Damage Ditch baseline so new fight doesn't trigger from old damage
                FarmState.LastLocalHealth = humHealth

                target = FarmState.currentTarget

                if target then
                    startMovingToTarget(target)
                    pos = def.getPos(target)
                else
                    -- No targets: idle in place but keep scanning & step away from players
                    stopMoving()
                    updateHudLogic(nil, def) -- Hide HUD
                    if AvoidPlayers then
                        moveAwayFromNearbyPlayers()
                    end
                    task.wait(0.15)
                    continue
                end
            end

            -- Update HUD constantly
            updateHudLogic(target, def)

            -- Double-check target position validity and height (retarget instead of stopping)
            if pos and pos.Y > MaxTargetHeight then
                notify("Target too high! Ditching.", 2)
                blacklistTarget(target, 60) -- too high, don't keep retargeting it

                stopMoving()
                FarmState.currentTarget = nil
                FarmState.attached      = false
                FarmState.detourActive  = false

                -- Immediately retarget to the next one
                local newTarget = chooseNearestTarget()
                if newTarget then
                    FarmState.currentTarget = newTarget
                    FarmState.attached      = false
                    FarmState.detourActive  = false
                    
                    FarmState.lastTargetRef    = newTarget
                    FarmState.lastTargetHealth = 0
                    FarmState.stuckStartTime   = os.clock()
                    
                    resetHudForNewTarget(newTarget, def)
                    
                    FarmState.LastLocalHealth = humHealth -- Reset ditch baseline

                    startMovingToTarget(newTarget)
                    -- next loop will handle hit logic
                else
                    if AvoidPlayers then
                        moveAwayFromNearbyPlayers()
                    end
                    task.wait(0.15)
                end

                continue
            end

            -- If we have a target and a player approaches THAT target, ditch + blacklist + RETARGET
            if AvoidPlayers and target and pos then
                local nearTarget, _ = isAnyPlayerNearPosition(pos, PlayerAvoidRadius)
                if nearTarget then
                    notify("Player nearby! Ditching.", 2)
                    blacklistTarget(target, 60)

                    stopMoving()
                    FarmState.currentTarget = nil
                    FarmState.attached      = false
                    FarmState.detourActive  = false

                    -- Immediately retarget instead of going idle
                    local newTarget = chooseNearestTarget()
                    if newTarget then
                        FarmState.currentTarget = newTarget
                        FarmState.attached      = false
                        FarmState.detourActive  = false
                        
                        FarmState.lastTargetRef    = newTarget
                        FarmState.lastTargetHealth = 0
                        FarmState.stuckStartTime   = os.clock()
                        
                        resetHudForNewTarget(newTarget, def)
                        
                        FarmState.LastLocalHealth = humHealth

                        startMovingToTarget(newTarget)
                        -- let next iteration handle hit
                    else
                        if AvoidPlayers then
                            moveAwayFromNearbyPlayers()
                        end
                        task.wait(0.15)
                    end

                    continue
                end
            end
            
            -- >>> WHITELIST CHECK FOR ORES <<<
            if FarmState.mode == FARM_MODE_ORES and OreWhitelistEnabled and target then
                -- Check if "Ore" children exist
                local oreChildren = {}
                for _, c in ipairs(target:GetChildren()) do
                    if c.Name == "Ore" then
                        table.insert(oreChildren, c)
                    end
                end
                
                if #oreChildren > 0 then
                    -- Ores are visible, check against whitelist
                    local matchFound = false
                    for _, orePart in ipairs(oreChildren) do
                        local oreType = orePart:GetAttribute("Ore")
                        if oreType and WhitelistedOres[oreType] then
                            matchFound = true
                            break
                        end
                    end
                    
                    if not matchFound then
                        -- Target has ores, but NONE match our whitelist -> DITCH
                        notify("No whitelisted ore found! Ditching.", 2)
                        blacklistTarget(target, 60)
                        stopMoving()
                        FarmState.currentTarget = nil
                        FarmState.attached      = false
                        FarmState.detourActive  = false
                        task.wait(0.1)
                        continue
                    end
                end
            end

            -- If we have a target and we somehow end up with X < -120 while NOT attached,
            -- force a detour-based path once per "under-threshold" period.
            if target and not FarmState.attached then
                local hrpPos = hrp.Position
                if hrpPos.X < DETOUR_THRESHOLD_X then
                    if not FarmState.detourActive then
                        FarmState.detourActive = true
                        stopMoving()
                        startMovingToTarget(target) -- will use detour because X < threshold
                    end
                else
                    -- once we're back above the threshold, allow detour to be triggered again later
                    FarmState.detourActive = false
                end
            else
                -- if no target or attached, we don't consider detour
                FarmState.detourActive = false
            end

            if pos then
                local dist = (pos - hrp.Position).Magnitude

                if dist <= def.hitDistance then
                    stopMoving()

                    if not FarmState.attached then
                        attachToTarget(target)
                        FarmState.attached = true
                        -- Reset stuck timer on first attach
                        FarmState.stuckStartTime = os.clock()
                        local h = def.getHealth(target)
                        FarmState.lastTargetHealth = h or 0
                    else
                        -- === ALWAYS FACE TARGET UPDATE ===
                        realignAttach(target)

                        -- >>> STUCK CHECK (20s) <<<
                        -- Only run stuck check if we have been attached to this target
                        if FarmState.lastTargetRef == target then
                            local currentH = def.getHealth(target) or 0
                            -- If health changed (damaged), reset timer
                            if currentH < FarmState.lastTargetHealth then
                                FarmState.lastTargetHealth = currentH
                                FarmState.stuckStartTime = os.clock()
                            else
                                -- Health didn't change
                                if (os.clock() - FarmState.stuckStartTime) > 20 then
                                    -- STUCK FOR 20 SECONDS
                                    notify("Stuck (20s)! Ditching.", 2)
                                    blacklistTarget(target, 60)
                                    stopMoving()
                                    FarmState.currentTarget = nil
                                    FarmState.attached      = false
                                    FarmState.detourActive  = false
                                    task.wait(0.1)
                                    continue
                                end
                            end
                        else
                            -- Target ref mismatch (shouldn't happen often), reset
                            FarmState.lastTargetRef = target
                            FarmState.lastTargetHealth = def.getHealth(target) or 0
                            FarmState.stuckStartTime = os.clock()
                        end
                    end

                    local now = os.clock()
                    if now - FarmState.lastHit >= def.hitInterval then
                        swingTool(def.toolRemoteArg)
                        FarmState.lastHit = now
                    end
                else
                    -- Out of range, make sure we are moving
                    if not FarmState.moveCleanup then
                        startMovingToTarget(target)
                    end
                    FarmState.attached = false
                    -- Reset stuck timer while moving
                    FarmState.stuckStartTime = os.clock()
                end
            end

            task.wait(0.05)
        end

        stopMoving()
        FarmState.currentTarget = nil
        FarmState.attached      = false
        FarmState.detourActive  = false
        updateHudLogic(nil, nil) -- Hide HUD
    end

    -- ====================================================================
    --  START / STOP
    -- ====================================================================

    local function startFarm()
        if FarmState.enabled then return end

        local def = ModeDefs[FarmState.mode]
        if not def then
            notify("Invalid farm mode.", 3)
            if Toggles.AF_Enabled then
                Toggles.AF_Enabled:SetValue(false)
            end
            return
        end

        if FarmState.mode == FARM_MODE_ORES and not getRocksFolder() then
            notify("No workspace.Rocks folder found.", 3)
            if Toggles.AF_Enabled then
                Toggles.AF_Enabled:SetValue(false)
            end
            return
        end

        if FarmState.mode == FARM_MODE_ENEMIES and not getLivingFolder() then
            notify("No workspace.Living folder found.", 3)
            if Toggles.AF_Enabled then
                Toggles.AF_Enabled:SetValue(false)
            end
            return
        end

        if #FarmState.selectedNames == 0 then
            notify("Select at least one target type first.", 3)
            if Toggles.AF_Enabled then
                Toggles.AF_Enabled:SetValue(false)
            end
            return
        end
        
        -- Warning if whitelist enabled but no ores selected
        local whitelistedCount = 0
        for _ in pairs(WhitelistedOres) do whitelistedCount = whitelistedCount + 1 end
        if FarmState.mode == FARM_MODE_ORES and OreWhitelistEnabled and whitelistedCount == 0 then
            notify("Warning: Ore Whitelist ON but no ores selected!", 5)
        end

        saveAttachSettings()
        configureAttachForMode(FarmState.mode)
        
        -- Create HUD if missing
        createHudGui()
        
        -- Enable Noclip
        enableNoclip()

        -- hard reset state so death / previous run can't poison us
        stopMoving()
        FarmState.currentTarget = nil
        FarmState.attached      = false
        FarmState.lastHit       = 0
        FarmState.detourActive  = false

        FarmState.enabled       = true
        FarmState.farmThread    = task.spawn(farmLoop)
    end

    local function stopFarm()
        FarmState.enabled = false
        stopMoving()
        FarmState.currentTarget = nil
        FarmState.attached      = false
        FarmState.detourActive  = false
        
        updateHudLogic(nil, nil) -- Hide HUD
        
        -- Disable Noclip
        disableNoclip()

        if AttachPanel.DestroyAttach then
            pcall(AttachPanel.DestroyAttach)
        end

        restoreAttachSettings()
    end

    -- ====================================================================
    --  UI: MODE + TARGETS + OFFSET + SPEED + AVOID + AUTO TOOL
    -- ====================================================================

    local AutoTab   = Tabs["Auto"] or Tabs.Main
    local FarmGroup = AutoTab:AddLeftGroupbox("Auto Farm", "pickaxe")

    local ModeDropdown
    local TargetDropdown
    local OreTypeDropdown -- New Dropdown
    local ZoneDropdown    -- New Zone Dropdown

    local function refreshTargetDropdown()
        if not TargetDropdown then return end
        local def = ModeDefs[FarmState.mode]
        if not def or not def.scan then
            TargetDropdown:SetValues({})
            return
        end
        local _, names = def.scan()
        TargetDropdown:SetValues(names)
    end
    
    local function refreshOreTypesDropdown()
        if not OreTypeDropdown then return end
        local types = getGameOreTypes()
        OreTypeDropdown:SetValues(types)
    end

    local function refreshZoneDropdown()
        if not ZoneDropdown then return end
        local zones = scanZones()
        ZoneDropdown:SetValues(zones)
    end

    ModeDropdown = FarmGroup:AddDropdown("AF_Mode", {
        Text    = "Farm Mode",
        Values  = { FARM_MODE_ORES, FARM_MODE_ENEMIES },
        Default = FarmState.mode,
        Callback = function(value)
            if FarmState.mode == value then
                return
            end
            FarmState.mode = value
            FarmState.selectedNames = {}
            refreshTargetDropdown()
            -- Hide/Show Ore specific elements? (Library might not support visibility toggle easily, keeping simple)
            
            if FarmState.enabled then
                stopFarm()
                startFarm()
            end
        end,
    })

    TargetDropdown = FarmGroup:AddDropdown("AF_Targets", {
        Text   = "Target Types",
        Values = {},
        Multi  = true,
        Callback = function(selectedTable)
            local list = {}
            for name, selected in pairs(selectedTable) do
                if selected then
                    list[#list + 1] = name
                end
            end
            FarmState.selectedNames = list
        end,
    })

    FarmGroup:AddButton({
        Text = "Refresh Targets",
        Func = function()
            refreshTargetDropdown()
            refreshLavaParts() -- in case map reloaded; harmless if AvoidLava is off
            refreshZoneDropdown()
        end,
    })
    
    -- ZONE WHITELIST UI (NEW)
    FarmGroup:AddToggle("AF_ZoneWhitelist", {
        Text    = "Zone Whitelist",
        Default = false,
        Tooltip = "Only target rocks inside specific Zones",
        Callback = function(state)
            ZoneWhitelistEnabled = state
        end,
    })

    ZoneDropdown = FarmGroup:AddDropdown("AF_Zones", {
        Text   = "Whitelisted Zones",
        Values = {},
        Multi  = true,
        Tooltip = "Select permitted zones",
        Callback = function(selectedTable)
            WhitelistedZones = {}
            for name, selected in pairs(selectedTable) do
                if selected then
                    WhitelistedZones[name] = true
                end
            end
        end,
    })

    -- ORE WHITELIST UI
    FarmGroup:AddToggle("AF_OreWhitelist", {
        Text    = "Ore Whitelist",
        Default = false,
        Tooltip = "Ditches rocks that don't have whitelisted ores",
        Callback = function(state)
            OreWhitelistEnabled = state
        end,
    })
    
    OreTypeDropdown = FarmGroup:AddDropdown("AF_OreTypes", {
        Text   = "Whitelisted Ores",
        Values = {},
        Multi  = true,
        Tooltip = "Select which ores are allowed",
        Callback = function(selectedTable)
            WhitelistedOres = {}
            for name, selected in pairs(selectedTable) do
                if selected then
                    WhitelistedOres[name] = true
                end
            end
        end,
    })
    
    FarmGroup:AddButton({
        Text = "Refresh Ore Types",
        Func = function()
            refreshOreTypesDropdown()
        end,
    })
    
    -- PROGRESS HUD TOGGLE
    FarmGroup:AddToggle("AF_ProgressHud", {
        Text    = "Progress HUD",
        Default = false,
        Tooltip = "Show a seperate progress hud.",
        Callback = function(state)
            HudState.Enabled = state
            if state then
                createHudGui()
            elseif HudState.Gui then
                HudState.Gui.Enabled = false
            end
        end,
    })

    FarmGroup:AddSlider("AF_OffsetAdjust", {
        Text     = "Extra Offset",
        Min      = -5,
        Max      = 5,
        Default  = 0,
        Rounding = 1,
        Suffix   = " studs",
        Callback = function(value)
            ExtraYOffset = value or 0

            if FarmState.enabled and FarmState.currentTarget and FarmState.attached then
                realignAttach(FarmState.currentTarget)
            end
        end,
    })

    FarmGroup:AddSlider("AF_Speed", {
        Text     = "Flight Speed",
        Min      = 50,
        Max      = 120,
        Default  = FarmSpeed,
        Rounding = 0,
        Suffix   = " studs/s",
        Callback = function(value)
            local v = tonumber(value) or FarmSpeed
            FarmSpeed = math.clamp(v, 5, 120)
        end,
    })

    FarmGroup:AddSlider("AF_MaxTargetHeight", {
        Text     = "Max Target Height",
        Min      = 0,
        Max      = 120,
        Default  = MaxTargetHeight,
        Rounding = 0,
        Suffix   = " studs",
        Callback = function(value)
            local v = tonumber(value) or MaxTargetHeight
            MaxTargetHeight = math.clamp(v, 0, 100)
        end,
    })

    FarmGroup:AddToggle("AF_AvoidLava", {
        Text    = "Avoid Lava",
        Default = false,
        Callback = function(state)
            AvoidLava = state and true or false
            if AvoidLava then
                refreshLavaParts()
            end
        end,
    })

    FarmGroup:AddToggle("AF_AvoidPlayers", {
        Text    = "Avoid Players",
        Default = false,
        Callback = function(state)
            AvoidPlayers = state
        end,
    })

    FarmGroup:AddSlider("AF_PlayerAvoidRadius", {
        Text     = "Player Avoid Range",
        Min      = 10,
        Max      = 100,
        Default  = PlayerAvoidRadius,
        Rounding = 0,
        Suffix   = " studs",
        Callback = function(value)
            PlayerAvoidRadius = tonumber(value) or PlayerAvoidRadius
        end,
    })
    
    FarmGroup:AddToggle("AF_DamageDitch", {
        Text    = "Damage Ditch",
        Default = false,
        Tooltip = "Ditches current target if you take damage while farming.",
        Callback = function(state)
            DamageDitchEnabled = state
        end,
    })

    FarmGroup:AddToggle("AF_Enabled", {
        Text    = "Auto Farm",
        Default = false,
        Callback = function(state)
            if state then
                startFarm()
            else
                stopFarm()
            end
        end,
    })

    -- Initial target list + lava parts + Ore types + Zones
    refreshTargetDropdown()
    refreshLavaParts()
    refreshOreTypesDropdown()
    refreshZoneDropdown()

    ----------------------------------------------------------------
    -- MODULE HANDLE
    ----------------------------------------------------------------

    local H = {}

    function H.Start()
        startFarm()
    end

    function H.Stop()
        stopFarm()
    end

    function H.Unload()
        -- stop farm
        FarmState.enabled = false
        stopMoving()
        FarmState.currentTarget = nil
        FarmState.attached      = false
        FarmState.detourActive  = false
        
        updateHudLogic(nil, nil)
        if HudState.Gui then
            HudState.Gui:Destroy()
            HudState.Gui = nil
        end
        
        disableNoclip()

        -- disable toggle in UI
        if Toggles.AF_Enabled then
            pcall(function()
                Toggles.AF_Enabled:SetValue(false)
            end)
        end
        -- destroy attach + restore user settings
        if AttachPanel.DestroyAttach then
            pcall(AttachPanel.DestroyAttach)
        end
        restoreAttachSettings()
    end

    return H
end
