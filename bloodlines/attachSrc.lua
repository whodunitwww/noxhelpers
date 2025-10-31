-- Attach.lua (UPDATED v2: Safety Mode + Loot Target Override + Noclip Hover + Dodge Range + Label-based AutoY)
-- Clean drop-in for your current Attach.lua

return function(ctx)
    -- ==== Context ====
    local Services, Tabs, References, Library, Options, Toggles =
        ctx.Services, ctx.Tabs, ctx.References, ctx.Library, ctx.Options, ctx.Toggles
    local MoveToPos, PREFIX, Config = ctx.MoveToPos, (ctx.PREFIX or "NH_"), ctx.Config or {}

    -- ==== Config shorthands ====
    local DodgeConfig        = Config.DodgeConfig or {}
    local AutoYOffsetConfig  = Config.AutoYOffsetConfig or {}
    local TargetTypes        = Config.TargetTypes or { Players = {key="Players"}, Entities = {key="Entities"} }
    local Defaults           = Config.Defaults or { mode="Aligned", yOffset=10, horizDist=4, targetType="Players" }
    local UIText             = Config.UIText or { groupTitle="Attach", statusTitle="Autofarm Status" }
    local MoveCfg            = Config.Move or { approachMaxSecs=12, reachDistance=3, moveForceResp=80, moveMaxVelocity=120, orientResp=120 }
    local Perf               = Config.Perf or { scanCooldown=0.5, waitScanHz=4, statusHz=5 }
    local Loot               = Config.Loot or { Names = {} }  -- expects Loot.Names[name] = true

    -- ==== State ====
    local AttachState = {
        mode = Defaults.mode, yOffset = Defaults.yOffset, horizDist = Defaults.horizDist,
        targetType = Defaults.targetType, selectedTargets = {},
        currentInst = nil, attached = false,
        _phase = "Idle", _hb = nil, _watchSelf = nil, _moveCleanup = nil,
        dodgeMode = Defaults.dodgeMode, autoYOffset = Defaults.autoYOffset,
        _dodgeActive = false, _dodgeConns = {}, _dodgeScanHB = nil, _dodgeRange = 50,
        showStatus = Defaults.showStatus,
        _statusHB = nil, _statusDiedConn = nil, _statusLastTarget = nil, _statusLastHealth = nil,
        _statusGui = nil, _statusBar = nil, _statusText = nil,
        _hoverAP=nil, _hoverAO=nil, _hoverA0=nil, _hoverA1=nil, _hoverNoclipHB=nil,
        _instToLabel = {},  -- instance -> label (for AutoY based on selection label)
        _labelToList = {},  -- label -> {instances}
    }

    -- ==== Helpers ====
    local function isAlive(inst)
        if not (inst and inst.Parent) then return false end
        local hum = inst:FindFirstChildOfClass("Humanoid")
        if hum then return hum.Health > 0 end
        if inst:IsA("Player") then
            local ch = inst.Character; local h = ch and ch:FindFirstChildOfClass("Humanoid")
            return (ch and h and h.Health > 0) or false
        end
        return (inst:FindFirstChild("HumanoidRootPart") or inst:FindFirstChildWhichIsA("BasePart")) ~= nil
    end

    local function hrpOf(target)
        if not target then return end
        if target:IsA("Player") then
            local ch = target.Character; return ch and ch:FindFirstChild("HumanoidRootPart")
        end
        return target:FindFirstChild("HumanoidRootPart") or target:FindFirstChildWhichIsA("BasePart")
    end

    local function humOf(target)
        if not target then return end
        if target:IsA("Player") then
            local ch = target.Character; return ch and ch:FindFirstChildOfClass("Humanoid")
        end
        if target:IsA("Model") then return target:FindFirstChildOfClass("Humanoid") end
    end

    local function safeName(inst)
        if not inst then return "nil" end
        if inst:IsA("Player") then return (inst.DisplayName ~= "" and inst.DisplayName) or inst.Name end
        return inst.Name
    end

    local function computeOffset(cf, mode, horiz, yoff)
        local f, r = cf.LookVector, cf.RightVector
        local up = Vector3.new(0, yoff, 0)
        if mode == "Behind" then return (-f*horiz)+up
        elseif mode == "In Front" then return (f*horiz)+up
        elseif mode == "Left" then return (-r*horiz)+up
        elseif mode == "Right" then return (r*horiz)+up
        else return up end -- Aligned
    end

    -- ==== Scanning utilities ====
    local function splitPath(p)
        local parts = {}
        for seg in string.gmatch(p or "", "[^/]+") do parts[#parts+1] = seg end
        return parts
    end

    local function findByPath(root, p)
        if not root then return nil end
        local parts = splitPath(p)
        if #parts == 0 then return nil end
        local start = root
        if parts[1] == "Workspace" then table.remove(parts, 1) end
        for _, seg in ipairs(parts) do
            start = start:FindFirstChild(seg)
            if not start then return nil end
        end
        return start
    end

    local function nameMatches(name, def)
        if not def then return true end
        name = tostring(name or "")
        local ci = def.caseInsensitive
        if def.names then
            for _, n in ipairs(def.names) do
                if ci then
                    if string.lower(name) == string.lower(n) then return true end
                else
                    if name == n then return true end
                end
            end
            return false
        end
        if def.patterns then
            for _, pat in ipairs(def.patterns) do
                local ok, res = pcall(string.find, ci and string.lower(name) or name, ci and string.lower(pat) or pat)
                if ok and res then return true end
            end
            return false
        end
        return true
    end

    local function applyIncludeExclude(map, def)
        if not def then return map end
        local out = {}
        for n, list in pairs(map) do
            local keep = true
            if def.include then keep = def.include[n] == true end
            if def.exclude and def.exclude[n] then keep = false end
            if keep then out[n] = list end
        end
        return out
    end

    local function mapInsert(map, key, inst)
        map[key] = map[key] or {}
        table.insert(map[key], inst)
    end

    local function scanPlayersRaw()
        local res = {}
        for _, p in ipairs(Services.Players:GetPlayers()) do
            if p ~= References.player then
                res[(p.DisplayName ~= "" and p.DisplayName) or p.Name] = { p }
            end
        end
        return res
    end

    local function scanEntitiesRaw()
        local res = {}
        for _, d in ipairs(Services.Workspace:GetDescendants()) do
            if d:IsA("Model") and not Services.Players:GetPlayerFromCharacter(d) then
                local hum = d:FindFirstChildOfClass("Humanoid")
                if hum then mapInsert(res, d.Name, d) end
            end
        end
        return res
    end

    local function scanFolderRaw(path, opts)
        opts = opts or {}
        local root = findByPath(Services.Workspace, path)
        local res = {}
        if not root then return res end
        for _, d in ipairs(root:GetDescendants()) do
            if opts.modelsOnly and d:IsA("Model") then
                if (not opts.humanoidsOnly) or d:FindFirstChildOfClass("Humanoid") then
                    if nameMatches(d.Name, opts) and (not opts.filter or opts.filter(d)) then
                        mapInsert(res, d.Name, d)
                    end
                end
            elseif not opts.modelsOnly then
                if nameMatches(d.Name, opts) and (not opts.filter or opts.filter(d)) then
                    mapInsert(res, d.Name, d)
                end
            end
        end
        return res
    end

    -- cache per category key
    local TargetCache = {}
    local SCAN_COOLDOWN = tonumber(Perf.scanCooldown) or 0.5

    local function getCached(key)
        local now = os.clock()
        local c = TargetCache[key]
        if c and (now - c.t) < SCAN_COOLDOWN then return c.res end
        return nil
    end

    local function setCached(key, res)
        TargetCache[key] = { t = os.clock(), res = res }
    end

    local function scanByDef(tag, def)
        local cached = getCached(tag)
        if cached then return cached end

        local res = {}
        if def.getItems then
            local ok, map = pcall(def.getItems, Services, References)
            res = ok and (map or {}) or {}
        elseif def.folderPath then
            res = scanFolderRaw(def.folderPath, def)
        elseif def.key == "Players" then
            res = scanPlayersRaw()
        elseif def.key == "Entities" then
            local base = scanEntitiesRaw()
            if def.names or def.patterns then
                local filtered = {}
                for n, list in pairs(base) do
                    if nameMatches(n, def) then filtered[n] = list end
                end
                res = filtered
            else
                res = base
            end
        else
            res = {}
        end

        res = applyIncludeExclude(res, def)

        -- Build label mappings for AutoY-by-label
        AttachState._labelToList = res
        AttachState._instToLabel = {}
        for label, list in pairs(res) do
            for _, inst in ipairs(list) do
                AttachState._instToLabel[inst] = label
            end
        end

        setCached(tag, res)
        return res
    end

    local function scanTargets(tag)
        local def = TargetTypes[tag]
        if not def then return {} end
        return scanByDef(tag, def)
    end

    -- ==== SAFETY MODE ====
    local function nearestPlayerDistance(pos)
        local best
        for _, p in ipairs(Services.Players:GetPlayers()) do
            if p ~= References.player then
                local ch = p.Character
                local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local d = (hrp.Position - pos).Magnitude
                    if not best or d < best then best = d end
                end
            end
        end
        return best or math.huge
    end

    local function isSafeTarget(inst)
        if not (Toggles.ATT_Safety and Toggles.ATT_Safety.Value) then return true end
        local part = hrpOf(inst)
        if not part then return false end
        local rng = (Options.ATT_SafetyRange and Options.ATT_SafetyRange.Value) or 50
        return nearestPlayerDistance(part.Position) > rng
    end

    -- ==== Selection ====
    local function currentSelectable()
        local map = scanTargets(AttachState.targetType)
        local sel = {}
        for _, name in ipairs(AttachState.selectedTargets or {}) do
            local list = map[name]
            if list then
                for _, inst in ipairs(list) do
                    if isAlive(inst) and isSafeTarget(inst) then
                        sel[#sel+1] = inst
                    end
                end
            end
        end
        return sel
    end

    local function nearestOf(list)
        local hrp = References.humanoidRootPart
        if not hrp or not list or #list==0 then return end
        local best, bestd
        for _, inst in ipairs(list) do
            local t = hrpOf(inst)
            if t then
                local d = (t.Position - hrp.Position).Magnitude
                if not bestd or d < bestd then best, bestd = inst, d end
            end
        end
        return best
    end

    -- Loot override (only applied when retargeting, never interrupts current hover)
    local function lootCandidates()
        if not (Toggles.ATT_CollectLoot and Toggles.ATT_CollectLoot.Value) then return {} end
        local hrp = References.humanoidRootPart
        if not hrp then return {} end
        local names = Loot.Names or {}
        local maxRange = (Options.ATT_LootRange and Options.ATT_LootRange.Value) or 150
        local list = {}
        for _, child in ipairs(Services.Workspace:GetChildren()) do
            if child:IsA("MeshPart") and names[child.Name] then
                local part = child
                local dist = (part.Position - hrp.Position).Magnitude
                if dist <= maxRange then
                    -- apply safety mode to loot as well
                    if isSafeTarget(child) then
                        list[#list+1] = child
                    end
                end
            end
        end
        return list
    end

    local function chooseNearest()
        -- Prefer loot on retarget, if enabled
        local loot = lootCandidates()
        if #loot > 0 then
            return nearestOf(loot)
        end
        return nearestOf(currentSelectable())
    end

    -- ==== Dodge (range-based) ====
    local function stopDodge()
        for _, c in ipairs(AttachState._dodgeConns) do pcall(function() c:Disconnect() end) end
        AttachState._dodgeConns = {}
        if AttachState._dodgeScanHB then pcall(function() AttachState._dodgeScanHB:Disconnect() end) end
        AttachState._dodgeScanHB = nil
        AttachState._dodgeActive = false
    end

    local function performDodge(tempY, dur)
        if AttachState._dodgeActive then return end
        AttachState._dodgeActive = true
        local prev = AttachState.yOffset
        AttachState.yOffset = tempY
        task.delay(dur, function()
            if AttachState._dodgeActive then AttachState.yOffset = prev; AttachState._dodgeActive=false end
        end)
    end

    local function inDodgeRange(inst)
        local hrp = References.humanoidRootPart
        local t = hrpOf(inst); if not (hrp and t) then return false end
        local r = AttachState._dodgeRange or 50
        return (t.Position - hrp.Position).Magnitude <= r
    end

    local function resubscribeDodge()
        stopDodge()
        if not AttachState.dodgeMode then return end

        -- periodically scan enemies around the player and subscribe to their AnimationPlayed
        AttachState._dodgeScanHB = Services.RunService.Heartbeat:Connect(function()
            -- light scan every ~0.25s
            if math.random() < 0.85 then return end
            -- subscribe to nearby humanoids
            for _, d in ipairs(Services.Workspace:GetDescendants()) do
                if d:IsA("Model") and not Services.Players:GetPlayerFromCharacter(d) then
                    local hum = d:FindFirstChildOfClass("Humanoid")
                    if hum and inDodgeRange(d) then
                        -- avoid duplicate connections by marking
                        if not hum:GetAttribute(PREFIX.."DodgeBound") then
                            hum:SetAttribute(PREFIX.."DodgeBound", true)
                            local conn = hum.AnimationPlayed:Connect(function(anim)
                                local id = tonumber((anim.Animation.AnimationId or ""):match("%d+"))
                                local cfg = id and DodgeConfig[id]
                                if cfg then task.delay(cfg.delay, function() performDodge(cfg.dodgeY, cfg.duration) end) end
                            end)
                            table.insert(AttachState._dodgeConns, conn)
                        end
                    end
                end
            end
        end)
    end

    -- ==== Auto Y (by label) ====
    local function maybeAutoYOffset(target)
        if AttachState._dodgeActive then return end
        if not (AttachState.autoYOffset and target) then return end
        -- Use selection label, not raw model name
        local label = AttachState._instToLabel[target]
        if not label then return end
        for key, val in pairs(AutoYOffsetConfig) do
            if tostring(label):find(key) then
                AttachState.yOffset = val
                return
            end
        end
    end

    -- ==== Phase control ====
    local function stopPhase()
        if AttachState._hb then pcall(function() AttachState._hb:Disconnect() end); AttachState._hb=nil end
        if AttachState._moveCleanup then pcall(AttachState._moveCleanup); AttachState._moveCleanup=nil end
        AttachState._phase = "Idle"
    end
    local function pausePhase()
        if AttachState._moveCleanup then pcall(AttachState._moveCleanup); AttachState._moveCleanup=nil end
    end

    -- ==== Status HUD ====
    local function destroyStatusGui()
        if AttachState._statusGui then pcall(function() AttachState._statusGui:Destroy() end) end
        AttachState._statusGui, AttachState._statusBar, AttachState._statusText = nil,nil,nil
    end

    local function ensureStatusGui()
        if AttachState._statusGui and AttachState._statusGui.Parent then return end
        local playerGui = Services.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui"); if not playerGui then return end
        local gui = Instance.new("ScreenGui"); gui.Name=PREFIX.."AttachStatus"; gui.ResetOnSpawn=false
        gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.Parent=playerGui

        local frame = Instance.new("Frame"); frame.Name="Panel"; frame.AnchorPoint=Vector2.new(0,0)
        frame.Position=UDim2.fromOffset(12,100); frame.Size=UDim2.fromOffset(240,62)
        frame.BackgroundColor3=Color3.fromRGB(18,18,18); frame.BackgroundTransparency=0.2; frame.BorderSizePixel=0
        frame.Parent=gui

        local uiCorner = Instance.new("UICorner"); uiCorner.CornerRadius=UDim.new(0,10); uiCorner.Parent=frame

        local title = Instance.new("TextLabel"); title.Name="Title"; title.Size=UDim2.new(1,-10,0,22)
        title.Position=UDim2.fromOffset(8,6); title.BackgroundTransparency=1; title.Font=Enum.Font.GothamSemibold
        title.TextSize=14; title.TextXAlignment=Enum.TextXAlignment.Left; title.TextColor3=Color3.fromRGB(200,255,200)
        title.Text = UIText.statusTitle or "Autofarm Status"; title.Parent=frame

        local hpText = Instance.new("TextLabel"); hpText.Name="HPText"; hpText.Size=UDim2.new(1,-10,0,18)
        hpText.Position=UDim2.fromOffset(8,28); hpText.BackgroundTransparency=1; hpText.Font=Enum.Font.Gotham
        hpText.TextSize=13; hpText.TextXAlignment=Enum.TextXAlignment.Left; hpText.TextColor3=Color3.fromRGB(230,230,230)
        hpText.Text="Target: —  HP: —/—"; hpText.Parent=frame

        local barBg = Instance.new("Frame"); barBg.Name="BarBG"; barBg.Size=UDim2.fromOffset(224,8)
        barBg.Position=UDim2.fromOffset(8,48); barBg.BackgroundColor3=Color3.fromRGB(45,45,45); barBg.BorderSizePixel=0
        barBg.Parent=frame
        local cornerBg = Instance.new("UICorner"); cornerBg.CornerRadius=UDim.new(0,4); cornerBg.Parent=barBg

        local bar = Instance.new("Frame"); bar.Name="Bar"; bar.Size=UDim2.new(0,0,1,0)
        bar.BackgroundColor3=Color3.fromRGB(50,205,50); bar.BorderSizePixel=0; bar.Parent=barBg
        local cornerBar = Instance.new("UICorner"); cornerBar.CornerRadius=UDim.new(0,4); cornerBar.Parent=bar

        AttachState._statusGui, AttachState._statusBar, AttachState._statusText = gui, bar, hpText
    end

    local function updateStatusGui(target, hp, maxhp)
        if not (AttachState._statusGui and AttachState._statusGui.Parent) then return end
        local t, b = AttachState._statusText, AttachState._statusBar; if not (t and b) then return end
        local h, mh = tonumber(hp) or 0, tonumber(maxhp) or 0
        local ratio = (mh > 0) and math.clamp(h/mh, 0, 1) or 0
        t.Text = ("Target: %s    HP: %d/%d"):format(target and safeName(target) or "—", h, mh)
        b.Size = UDim2.new(ratio, 0, 1, 0)
    end

    local function stopStatus()
        if AttachState._statusHB then pcall(function() AttachState._statusHB:Disconnect() end); AttachState._statusHB=nil end
        if AttachState._statusDiedConn then pcall(function() AttachState._statusDiedConn:Disconnect() end); AttachState._statusDiedConn=nil end
        AttachState._statusLastTarget, AttachState._statusLastHealth = nil, nil
        destroyStatusGui()
    end

    local function bindStatusToTarget(target)
        if AttachState._statusDiedConn then pcall(function() AttachState._statusDiedConn:Disconnect() end); AttachState._statusDiedConn=nil end
        local hum = humOf(target); if hum then
            AttachState._statusDiedConn = hum.Died:Connect(function()
                local deadName = safeName(target)
                local newT = chooseNearest()
                if newT and newT ~= target then
                    AttachState.currentInst = newT
                    if AttachState._phase ~= "Approach" and AttachState.attached then startApproach() end
                end
            end)
        end
    end

    local function startStatus()
        stopStatus()
        if not AttachState.showStatus then return end
        ensureStatusGui()
        local acc, step = 0, (1 / math.max(1, tonumber(Perf.statusHz) or 5))
        AttachState._statusHB = Services.RunService.Heartbeat:Connect(function(dt)
            if not AttachState.showStatus then return end
            acc = acc + dt; if acc < step then return end; acc = 0
            local tgt = AttachState.currentInst
            if tgt ~= AttachState._statusLastTarget then
                AttachState._statusLastTarget, AttachState._statusLastHealth = tgt, nil
                if tgt then bindStatusToTarget(tgt) end
            end
            if not tgt then updateStatusGui(nil,0,0); return end
            local hum = humOf(tgt)
            if hum then
                local hp, mh = math.floor(hum.Health), math.floor(hum.MaxHealth or 0)
                if hp ~= AttachState._statusLastHealth then
                    AttachState._statusLastHealth = hp
                    updateStatusGui(tgt, hp, mh)
                end
            else
                updateStatusGui(tgt, 0, 0)
            end
        end)
    end

    -- ==== Wait loop (when no available target) ====
    local function waitForEnemies()
        stopPhase()
        AttachState._phase = "Waiting"
        local acc, step = 0, (1 / math.max(1, tonumber(Perf.waitScanHz) or 4))
        AttachState._hb = Services.RunService.Heartbeat:Connect(function(dt)
            if not AttachState.attached then return end
            acc = acc + dt; if acc < step then return end; acc = 0

            -- On retarget only: include loot override
            local newT = chooseNearest()
            if newT then
                AttachState.currentInst = newT
                startApproach()
            end
        end)
    end

    -- ==== Approach ====
    function startApproach()
        stopPhase()
        AttachState._phase = "Approach"
        local tgt = AttachState.currentInst
        if not tgt then
            local nt = chooseNearest(); if not nt then waitForEnemies(); return end
            tgt = nt; AttachState.currentInst = nt
        end

        maybeAutoYOffset(tgt); if AttachState.showStatus then startStatus() end
        resubscribeDodge()

        local function unsafeOrDead()
            if not isAlive(tgt) then return true end
            if not isSafeTarget(tgt) then return true end
            return false
        end

        local function goal()
            if unsafeOrDead() then return nil end
            local t = hrpOf(tgt); if not t then return nil end
            return t.Position + computeOffset(t.CFrame, AttachState.mode, AttachState.horizDist, AttachState.yOffset)
        end

        local first = goal(); if not first then waitForEnemies(); return end
        AttachState._moveCleanup = MoveToPos(first, 1000, goal)
        local startT = os.clock()

        AttachState._hb = Services.RunService.Heartbeat:Connect(function()
            if AttachState._phase ~= "Approach" then return end
            local rp = References.humanoidRootPart; if not rp then stopPhase(); return end

            local g = goal(); if not g then
                -- target became unsafe or dead → retarget (loot has priority inside chooseNearest)
                local newT = chooseNearest()
                if newT then AttachState.currentInst = newT; startApproach() else waitForEnemies() end
                return
            end

            if (rp.Position - g).Magnitude <= (MoveCfg.reachDistance or 3) then
                pausePhase(); AttachState._phase = "Hover"
                task.defer(function() if AttachState.attached then task.wait(0.05); startHover() end end)
                return
            end

            if os.clock() - startT > (MoveCfg.approachMaxSecs or 12) then waitForEnemies(); return end

            if not isAlive(tgt) or not isSafeTarget(tgt) then
                local newT = chooseNearest()
                if newT then AttachState.currentInst, tgt = newT, newT
                    maybeAutoYOffset(tgt); local ng = goal()
                    if ng then
                        pausePhase()
                        AttachState._moveCleanup = MoveToPos(ng, 1000, goal)
                        startT = os.clock()
                    else
                        waitForEnemies()
                    end
                else
                    waitForEnemies()
                end
            end
        end)
    end

    -- ==== Hover (with noclip) ====
    local function destroyHoverHelpers()
        for _, v in ipairs({AttachState._hoverAP,AttachState._hoverAO,AttachState._hoverA0,AttachState._hoverA1}) do
            if v then pcall(function() v:Destroy() end) end
        end
        AttachState._hoverAP,AttachState._hoverAO,AttachState._hoverA0,AttachState._hoverA1 = nil,nil,nil,nil
        if AttachState._hoverNoclipHB then pcall(function() AttachState._hoverNoclipHB:Disconnect() end) end
        AttachState._hoverNoclipHB = nil
    end

    local function setCharacterNoclip()
        local char = References.character
        if not char then return end
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") then d.CanCollide = false end
        end
    end

    function startHover()
        if AttachState._hb then pcall(function() AttachState._hb:Disconnect() end); AttachState._hb=nil end
        destroyHoverHelpers()
        AttachState._phase = "Hover"

        local rp, tgt, ht = References.humanoidRootPart, AttachState.currentInst, nil
        ht = hrpOf(tgt)
        if not (rp and ht and isAlive(tgt) and isSafeTarget(tgt)) then waitForEnemies(); return end
        if References.humanoid then References.humanoid.AutoRotate=false end
        rp.AssemblyAngularVelocity = Vector3.zero

        local a0 = Instance.new("Attachment"); a0.Name=PREFIX.."HoverA0"; a0.Parent=rp
        local a1 = Instance.new("Attachment"); a1.Name=PREFIX.."HoverA1"; a1.Parent=ht

        local ap = Instance.new("AlignPosition"); ap.Name=PREFIX.."HoverAP"
        ap.Mode=Enum.PositionAlignmentMode.TwoAttachment; ap.Attachment0=a0; ap.Attachment1=a1
        ap.Responsiveness = MoveCfg.moveForceResp or 80
        ap.MaxVelocity = MoveCfg.moveMaxVelocity or 120
        ap.MaxForce = math.huge; ap.Parent=rp

        local ao = Instance.new("AlignOrientation"); ao.Name=PREFIX.."HoverAO"
        ao.Attachment0=a0; ao.Responsiveness = MoveCfg.orientResp or 120
        ao.MaxTorque=math.huge; ao.RigidityEnabled=true; ao.Parent=rp

        AttachState._hoverAP,AttachState._hoverAO,AttachState._hoverA0,AttachState._hoverA1 = ap,ao,a0,a1

        local function setOffset()
            local htNow = hrpOf(AttachState.currentInst); if not htNow then return end
            if not AttachState._dodgeActive then maybeAutoYOffset(AttachState.currentInst) end
            local cf = htNow.CFrame
            local offset = computeOffset(cf, AttachState.mode, AttachState.horizDist, AttachState.yOffset)
            a1.Position = cf:VectorToObjectSpace(offset)
        end

        local function faceTarget()
            local tgtNow, rpNow, htNow = AttachState.currentInst, References.humanoidRootPart, hrpOf(AttachState.currentInst)
            if not (tgtNow and isAlive(tgtNow) and rpNow and htNow and isSafeTarget(tgtNow)) then waitForEnemies(); return end
            local fromPos, toPos = rpNow.Position, htNow.Position
            local dir = (toPos - fromPos); if dir.Magnitude < 1e-6 then return end; dir = dir.Unit
            local up = (math.abs(dir:Dot(Vector3.yAxis)) > 0.98) and Vector3.xAxis or Vector3.yAxis
            local desired = CFrame.lookAt(fromPos, toPos, up) * CFrame.Angles(0, math.pi, 0)
            AttachState._hoverAO.CFrame = desired
        end

        setOffset(); faceTarget()
        -- Keep noclip while hovering
        setCharacterNoclip()
        AttachState._hoverNoclipHB = Services.RunService.Stepped:Connect(setCharacterNoclip)

        AttachState._hb = Services.RunService.RenderStepped:Connect(function()
            if not AttachState.attached then return end
            setOffset(); faceTarget()
            if not isSafeTarget(AttachState.currentInst) then
                -- drop unsafe target and retarget (won't interrupt hover for loot; only at retarget)
                local newT = chooseNearest()
                if newT and newT ~= AttachState.currentInst then
                    AttachState.currentInst = newT
                    startApproach()
                else
                    waitForEnemies()
                end
            end
        end)
    end

    local function stopHover()
        if AttachState._hb then pcall(function() AttachState._hb:Disconnect() end); AttachState._hb=nil end
        destroyHoverHelpers()
        if References.humanoid then References.humanoid.AutoRotate=true end
        AttachState._phase="Idle"
    end

    -- ==== Watchers (full reboot on respawn) ====
    local function fullReboot()
        stopHover(); stopPhase(); stopStatus(); stopDodge()
        -- rebind references are assumed handled by your reference updater; just restart the flow
        if AttachState.attached then
            task.wait(0.25)
            AttachState.currentInst = nil
            waitForEnemies()
        end
    end

    local function stopWatchers()
        if AttachState._watchSelf then AttachState._watchSelf:Disconnect(); AttachState._watchSelf=nil end
    end
    local function startWatchers()
        stopWatchers()
        AttachState._watchSelf = Services.Players.LocalPlayer.CharacterAdded:Connect(function()
            task.wait(0.35)
            fullReboot()
        end)
    end

    -- ==== UI ====
    local AttachGroup = Tabs.Main:AddRightGroupbox(UIText.groupTitle or "Attach","link")
    local ddTarget, ddType

    local function refreshNames(dd)
        local map = scanTargets(AttachState.targetType)
        local names = {}
        for n, l in pairs(map) do if l and #l > 0 then names[#names+1]=n end end
        table.sort(names); dd:SetValues(names)
    end

    do
        local typeNames = {}
        for k,_ in pairs(TargetTypes) do typeNames[#typeNames+1] = k end
        table.sort(typeNames)
        ddType = AttachGroup:AddDropdown("ATT_Type", {
            Text = "Target Type",
            Values = typeNames,
            Default = Defaults.targetType or typeNames[1],
            Callback = function(v)
                AttachState.targetType=v; AttachState.selectedTargets={}; refreshNames(ddTarget)
            end
        })
    end

    ddTarget = AttachGroup:AddDropdown("ATT_Target", {
        Text="Target", Values={}, Multi=true,
        Callback=function(v)
            local sel={}; for name,on in pairs(v) do if on then sel[#sel+1]=name end end
            AttachState.selectedTargets=sel
            if AttachState.attached then
                local newT=chooseNearest()
                if newT then AttachState.currentInst=newT; startApproach() else waitForEnemies() end
            end
        end
    })

    AttachGroup:AddButton({Text="Refresh Targets", Func=function() refreshNames(ddTarget) end})

    AttachGroup:AddDropdown("ATT_Mode", {
        Text="Attach Mode",
        Values={"Behind","In Front","Left","Right","Aligned"},
        Default=Defaults.mode or "Behind",
        Callback=function(v) AttachState.mode=v; if AttachState.attached then startApproach() end end
    })

    AttachGroup:AddSlider("ATT_Y", {
        Text="Y Offset", Default=Defaults.yOffset or 10, Min=-30, Max=30, Suffix=" studs",
        Callback=function(v) AttachState.yOffset=v; if AttachState.attached then startApproach() end end
    })

    AttachGroup:AddToggle("ATT_On", {
        Text="Attach", Default=false,
        Callback=function(on)
            AttachState.attached=on
            if on then
                startWatchers()
                resubscribeDodge()
                local t=chooseNearest(); AttachState.currentInst=t
                if not t then waitForEnemies(); return end
                startApproach()
                if AttachState.showStatus then startStatus() end
            else
                stopHover(); stopWatchers(); stopStatus(); stopDodge()
            end
        end
    })

    -- Dodge (range)
    AttachGroup:AddToggle("ATT_Dodge", {
        Text="Dodge Mode", Default=Defaults.dodgeMode or false,
        Callback=function(v)
            AttachState.dodgeMode=v
            if v then resubscribeDodge() else stopDodge() end
        end
    })
    AttachGroup:AddSlider("ATT_DodgeRange", {
        Text="Dodge Range", Default=50, Min=10, Max=200, Suffix=" studs",
        Callback=function(v) AttachState._dodgeRange = v end
    })

    -- AutoY
    AttachGroup:AddToggle("ATT_AutoY", {
        Text="AutoSet Y Offset", Default=Defaults.autoYOffset or false,
        Callback=function(v) AttachState.autoYOffset=v end
    })

    -- Status
    AttachGroup:AddToggle("ATT_Status", {
        Text="Show Status", Default=Defaults.showStatus or false,
        Tooltip="On-screen target + HP HUD.",
        Callback=function(on) AttachState.showStatus=on; if on then startStatus() else stopStatus() end end
    })

    -- Safety Mode
    AttachGroup:AddToggle("ATT_Safety", {
        Text="Safety Mode", Default=false,
        Tooltip="Will ignore targets close to other players."
    })
    AttachGroup:AddSlider("ATT_SafetyRange", {
        Text="Safety Range", Default=50, Min=10, Max=200, Suffix=" studs"
    })

    AttachGroup:AddToggle("ATT_CollectLoot", {
        Text="Collect Loot", Default=false,
        Tooltip="Override targets if loot is nearby."
    })
    AttachGroup:AddSlider("ATT_LootRange", {
        Text="Loot Range", Default=150, Min=25, Max=1000, Suffix=" studs"
    })

    refreshNames(ddTarget)

    local M = {}
    function M.Unload()
        stopHover(); stopPhase(); stopStatus(); stopDodge(); stopWatchers()
        if Toggles and Toggles.ATT_On and Toggles.ATT_On.Value then pcall(function() Toggles.ATT_On:SetValue(false) end) end
    end
    return M
end
