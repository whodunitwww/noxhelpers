return function(ctx)
    ------------------------------------------------------------------------
    -- Context + Aliases
    ------------------------------------------------------------------------
    local Services    = ctx.Services
    local References  = ctx.References
    local Library     = ctx.Library
    local Options     = ctx.Options -- Kept for compatibility, though unused by UI
    local Toggles     = ctx.Toggles -- Kept for compatibility, though unused by UI
    local MoveToPos   = ctx.MoveToPos

    local PREFIX      = ctx.PREFIX or "NH_"

    local Config      = ctx.Config or {}
    local DefaultCfg  = Config.Defaults or {}
    local UIText      = Config.UIText or {}
    local MoveConfig  = Config.Move or {}
    local DodgeConfig = Config.DodgeConfig or {}
    local AutoYOffsetConfig = Config.AutoYOffsetConfig or {}

    -- Target type definitions
    local TargetTypes = Config.TargetTypes or {
        Players  = { key = "Players" },
        Entities = { key = "Entities" },
    }

    -- Keep original short names for compatibility
    local a  = ctx
    local b  = Services
    local d  = References
    local e  = Library
    local f  = Options
    local g  = Toggles
    local h  = MoveToPos
    local i  = PREFIX
    local j  = Config
    local k  = DefaultCfg
    local l  = UIText
    local m  = MoveConfig
    local n  = DodgeConfig
    local o  = AutoYOffsetConfig
    local p  = TargetTypes

    ------------------------------------------------------------------------
    -- Utility: Notifications
    ------------------------------------------------------------------------
    local function notify(message, time)
        if e and e.Notify then
            e:Notify(message, time or 2)
        end
    end

    local function q(message, time)
        notify(message, time)
    end

    ------------------------------------------------------------------------
    -- Utility: RootPart / Humanoid / Validity helpers
    ------------------------------------------------------------------------

    --- Get a "root" part (HRP or some BasePart) from a target
    local function getRootPartFromTarget(target)
        if not target then return nil end

        if target:IsA("Player") then
            local character = target.Character
            if not character then return nil end
            return character:FindFirstChild("HumanoidRootPart")
                or character:FindFirstChildWhichIsA("BasePart")
        end

        if target:IsA("Model") then
            return target:FindFirstChild("HumanoidRootPart")
                or target:FindFirstChildWhichIsA("BasePart")
        end

        if target:IsA("BasePart") then
            return target
        end

        return nil
    end

    local t = getRootPartFromTarget

    --- Get humanoid from a target (Player or Model)
    local function getHumanoidFromTarget(target)
        if not target then return nil end

        if target:IsA("Player") then
            local character = target.Character
            return character and character:FindFirstChildOfClass("Humanoid")
        end

        if target:IsA("Model") then
            return target:FindFirstChildOfClass("Humanoid")
        end

        return nil
    end

    local w = getHumanoidFromTarget

    --- Is target "alive"?
    local function isAlive(target)
        if not (target and target.Parent) then return false end
        local hum = w(target)
        if hum then return hum.Health > 0 end
        return true
    end

    local x = isAlive

    --- Is target valid to use?
    local function isValidTarget(target)
        return target and target.Parent and x(target) and (t(target) ~= nil)
    end

    local z = isValidTarget

    ------------------------------------------------------------------------
    -- Utility: Name / Offset / Target Collection
    ------------------------------------------------------------------------

    local function getDisplayName(instance)
        if not instance then return "nil" end
        if instance:IsA("Player") then
            if instance.DisplayName ~= "" then return instance.DisplayName else return instance.Name end
        end
        return instance.Name
    end

    local A = getDisplayName

    --- Compute offset from a CFrame
    local function computeOffsetFromCFrame(cf, mode, horizDist, yOffset)
        local look = cf.LookVector
        local right = cf.RightVector
        local vertical = Vector3.new(0, yOffset, 0)

        if mode == "Behind" then
            return -look * horizDist + vertical
        elseif mode == "In Front" then
            return look * horizDist + vertical
        elseif mode == "Left" then
            return -right * horizDist + vertical
        elseif mode == "Right" then
            return right * horizDist + vertical
        else
            return vertical
        end
    end

    local C = computeOffsetFromCFrame

    ------------------------------------------------------------------------
    -- Target discovery
    ------------------------------------------------------------------------

    local function collectPlayersByName()
        local result = {}
        for _, plr in ipairs(b.Players:GetPlayers()) do
            if plr ~= d.player then
                local name = (plr.DisplayName ~= "" and plr.DisplayName) or plr.Name
                result[name] = result[name] or {}
                table.insert(result[name], plr)
            end
        end
        return result
    end

    local K = collectPlayersByName

    local function collectEntitiesByName()
        local result = {}
        for _, inst in ipairs(b.Workspace:GetDescendants()) do
            if inst:IsA("Model") and not b.Players:GetPlayerFromCharacter(inst) then
                local hum = inst:FindFirstChildOfClass("Humanoid")
                if hum then
                    local name = inst.Name
                    result[name] = result[name] or {}
                    table.insert(result[name], inst)
                end
            end
        end
        return result
    end

    local P = collectEntitiesByName

    local function collectModelsFromFolderPath(folderPath)
        local current = b.Workspace
        for segment in string.gmatch(folderPath or "", "[^/]+") do
            current = current and current:FindFirstChild(segment)
        end
        local result = {}
        if not current then return result end
        for _, inst in ipairs(current:GetDescendants()) do
            if inst:IsA("Model") then
                local hum = inst:FindFirstChildOfClass("Humanoid")
                if hum then
                    local name = inst.Name
                    result[name] = result[name] or {}
                    table.insert(result[name], inst)
                end
            end
        end
        return result
    end

    local R = collectModelsFromFolderPath

    local function collectStaticModels(staticConfig)
        local result = {}
        if type(staticConfig.static) ~= "table" then return result end
        local workspace = b.Workspace
        for _, modelName in ipairs(staticConfig.static) do
            local matches = {}
            for _, inst in ipairs(workspace:GetDescendants()) do
                if inst:IsA("Model") and inst.Name == modelName then
                    table.insert(matches, inst)
                end
            end
            if #matches > 0 then
                result[modelName] = matches
            end
        end
        return result
    end

    local V = collectStaticModels

    local function getTargetsByType(targetTypeName)
        local typeConfig = p[targetTypeName]
        if not typeConfig then return {} end
        if typeConfig.staticOnly then return V(typeConfig) end
        if typeConfig.getItems then
            local ok, items = pcall(typeConfig.getItems, b, d)
            return ok and (items or {}) or {}
        end
        if typeConfig.folderPath then return R(typeConfig.folderPath) end
        if typeConfig.key == "Players" then return K() end
        if typeConfig.key == "Entities" then return P() end
        return {}
    end

    local Z = getTargetsByType

    ------------------------------------------------------------------------
    -- Attach State
    ------------------------------------------------------------------------

    local state = {
        running       = false,
        stage         = "Idle",

        targetType    = k.targetType or "Players",
        selectedNames = {},         
        currentTarget = nil,

        mode          = k.mode or "Aligned",
        yOffset       = k.yOffset or 10,
        horizDist     = k.horizDist or 4,

        movement      = k.movement or "Approach", 
        autoYOffset   = k.autoYOffset or false,

        dodgeMode     = k.dodgeMode or false,
        dodgeRange    = k.dodgeRange or 50,

        -- Internal references
        _hb           = nil,
        _moveCleanup  = nil,
        _attachA0     = nil,
        _attachA1     = nil,
        _alignPos     = nil,
        _alignOri     = nil,
        _noclipHB     = nil,

        _dodgeActive  = false,
        _humConns     = {},
        _humAdded     = nil,
        _humRemoved   = nil,
    }

    local a2 = state

    ------------------------------------------------------------------------
    -- Auto Y / Dist config based on target name
    ------------------------------------------------------------------------
    local function applyAutoYOffsetForTarget(target)
        if not (a2.autoYOffset and target and o) then return end
        if a2._dodgeActive then return end

        local name = A(target)
        for pattern, cfg in pairs(o) do
            if tostring(name):find(pattern, 1, true) then
                if type(cfg) == "number" then
                    a2.yOffset = cfg
                elseif type(cfg) == "table" then
                    if cfg.y ~= nil then a2.yOffset = tonumber(cfg.y) or a2.yOffset end
                    if cfg.mode and type(cfg.mode) == "string" then a2.mode = cfg.mode end
                    if cfg.horiz ~= nil then a2.horizDist = tonumber(cfg.horiz) or a2.horizDist
                    elseif cfg.horizDist ~= nil then a2.horizDist = tonumber(cfg.horizDist) or a2.horizDist end
                end
                break
            end
        end
    end

    local a3 = applyAutoYOffsetForTarget

    ------------------------------------------------------------------------
    -- Target gathering (from current selection)
    ------------------------------------------------------------------------
    local function getSelectedTargetInstances()
        local byType = Z(a2.targetType)
        local result = {}
        for _, selectedName in ipairs(a2.selectedNames) do
            local instances = byType[selectedName]
            if instances then
                for _, inst in ipairs(instances) do
                    if z(inst) then result[#result + 1] = inst end
                end
            end
        end
        return result
    end

    local a6 = getSelectedTargetInstances

    -- Choose nearest target to local HRP from selection
    local function chooseNearestTarget()
        local hrp = d.humanoidRootPart
        if not hrp then return nil end

        local candidates = a6()
        local bestTarget, bestDist

        for _, inst in ipairs(candidates) do
            local root = t(inst)
            if root then
                local dist = (root.Position - hrp.Position).Magnitude
                if not bestDist or dist < bestDist then
                    bestDist = dist
                    bestTarget = inst
                end
            end
        end
        return bestTarget
    end

    local a8 = chooseNearestTarget

    ------------------------------------------------------------------------
    -- Noclip helpers
    ------------------------------------------------------------------------
    local function applyNoClip()
        local character = d.character
        if not character then return end
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end

    local function startNoClip()
        if a2._noclipHB then return end
        a2._noclipHB = b.RunService.Stepped:Connect(applyNoClip)
    end

    local function stopNoClip()
        if a2._noclipHB then
            a2._noclipHB:Disconnect()
            a2._noclipHB = nil
        end
    end

    local af = applyNoClip
    local ah = startNoClip
    local ai = stopNoClip

    ------------------------------------------------------------------------
    -- Attach / Align creation & cleanup
    ------------------------------------------------------------------------
    local function destroyAttachments()
        if a2._alignPos then pcall(function() a2._alignPos:Destroy() end) end
        if a2._alignOri then pcall(function() a2._alignOri:Destroy() end) end
        if a2._attachA0 then pcall(function() a2._attachA0:Destroy() end) end
        if a2._attachA1 then pcall(function() a2._attachA1:Destroy() end) end

        a2._alignPos, a2._alignOri = nil, nil
        a2._attachA0, a2._attachA1 = nil, nil

        ai()

        if d.humanoid then d.humanoid.AutoRotate = true end
    end

    local aj = destroyAttachments

    local function createAttachmentsToTarget(target)
        aj()
        local hrp = d.humanoidRootPart
        local targetRoot = t(target)
        if not (hrp and targetRoot) then return end

        if d.humanoid then d.humanoid.AutoRotate = false end
        hrp.AssemblyAngularVelocity = Vector3.zero

        local a0 = Instance.new("Attachment")
        a0.Name = i .. "ATT_A0"
        a0.Parent = hrp

        local a1 = Instance.new("Attachment")
        a1.Name = i .. "ATT_A1"
        a1.Parent = targetRoot

        local alignPos = Instance.new("AlignPosition")
        alignPos.Name = i .. "ATT_AP"
        alignPos.Mode = Enum.PositionAlignmentMode.TwoAttachment
        alignPos.Attachment0 = a0
        alignPos.Attachment1 = a1
        alignPos.Responsiveness = m.moveForceResp or 80
        alignPos.MaxVelocity = m.moveMaxVelocity or 120
        alignPos.MaxForce = math.huge
        alignPos.Parent = hrp

        local alignOri = Instance.new("AlignOrientation")
        alignOri.Name = i .. "ATT_AO"
        alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
        alignOri.Attachment0 = a0
        alignOri.Responsiveness = m.orientResp or 120
        alignOri.MaxTorque = math.huge
        alignOri.RigidityEnabled = true
        alignOri.Parent = hrp

        a2._attachA0 = a0
        a2._attachA1 = a1
        a2._alignPos = alignPos
        a2._alignOri = alignOri

        ah()
    end

    local ak = createAttachmentsToTarget

    ------------------------------------------------------------------------
    -- Dodge system: humanoid animation hooks
    ------------------------------------------------------------------------
    local function clearDodgeConnections()
        for hum, conn in pairs(a2._humConns) do
            if conn then pcall(function() conn:Disconnect() end) end
            a2._humConns[hum] = nil
        end
        if a2._humAdded then a2._humAdded:Disconnect(); a2._humAdded = nil end
        if a2._humRemoved then a2._humRemoved:Disconnect(); a2._humRemoved = nil end
        a2._dodgeActive = false
    end

    local aq = clearDodgeConnections

    local function performDodgeTemporary(dodgeYOffset, duration)
        if a2._dodgeActive then return end
        a2._dodgeActive = true
        local originalY = a2.yOffset
        a2.yOffset = dodgeYOffset
        task.delay(duration, function()
            if a2._dodgeActive then
                a2.yOffset = originalY
                a2._dodgeActive = false
            end
        end)
    end

    local as = performDodgeTemporary

    local function isWithinDodgeRange(target)
        local hrp = d.humanoidRootPart
        local targetRoot = t(target)
        if not (hrp and targetRoot) then return false end
        local dist = (targetRoot.Position - hrp.Position).Magnitude
        return dist <= (a2.dodgeRange or 50)
    end

    local av = isWithinDodgeRange

    local function hookHumanoidForDodge(humanoid)
        if not humanoid or a2._humConns[humanoid] then return end
        local isPlayerChar = b.Players:GetPlayerFromCharacter(humanoid.Parent) ~= nil
        if isPlayerChar then return end

        a2._humConns[humanoid] = humanoid.AnimationPlayed:Connect(function(track)
            local anim = track and track.Animation
            local animIdStr = anim and anim.AnimationId or ""
            local animNum = tonumber(string.match(animIdStr, "%d+"))
            if not animNum then return end

            local dodgeCfg = n[animNum]
            if not dodgeCfg then return end
            if not av(humanoid.Parent) then return end

            local delayTime  = tonumber(dodgeCfg.delay) or 0
            local dodgeY     = tonumber(dodgeCfg.dodgeY) or a2.yOffset
            local duration   = tonumber(dodgeCfg.duration) or 0.5

            task.delay(delayTime, function()
                if a2.dodgeMode and av(humanoid.Parent) then
                    as(dodgeY, duration)
                end
            end)
        end)
    end

    local aw = hookHumanoidForDodge

    local function rebuildDodgeMonitoring()
        aq()
        if not a2.dodgeMode then return end

        for _, inst in ipairs(b.Workspace:GetDescendants()) do
            if inst:IsA("Humanoid") then aw(inst) end
        end

        a2._humAdded = b.Workspace.DescendantAdded:Connect(function(inst)
            if a2.dodgeMode and inst:IsA("Humanoid") then aw(inst) end
        end)

        a2._humRemoved = b.Workspace.DescendantRemoving:Connect(function(inst)
            if inst:IsA("Humanoid") then
                local conn = a2._humConns[inst]
                if conn then pcall(function() conn:Disconnect() end) end
                a2._humConns[inst] = nil
            end
        end)
    end

    local aG = rebuildDodgeMonitoring

    ------------------------------------------------------------------------
    -- Heartbeat / movement cleanup
    ------------------------------------------------------------------------
    local function disconnectHeartbeat()
        if a2._hb then
            a2._hb:Disconnect()
            a2._hb = nil
        end
    end

    local aI = disconnectHeartbeat

    local function cleanupMovement()
        if a2._moveCleanup then
            pcall(a2._moveCleanup)
            a2._moveCleanup = nil
        end
    end

    local aJ = cleanupMovement

    ------------------------------------------------------------------------
    -- Teleport helper
    ------------------------------------------------------------------------
    local function teleportToTargetPosition(target)
        local hrp = d.humanoidRootPart
        local targetRoot = t(target)
        if not (hrp and targetRoot) then return false end

        local desiredPos = targetRoot.Position + C(targetRoot.CFrame, a2.mode, a2.horizDist, a2.yOffset)
        hrp.CFrame = CFrame.new(desiredPos, targetRoot.Position)
        return true
    end

    local aK = teleportToTargetPosition

    ------------------------------------------------------------------------
    -- Attach follow mode (attachment + RenderStepped)
    ------------------------------------------------------------------------
    local function goAttachLoop()
        aJ()
        aI()

        local target = a2.currentTarget
        if not z(target) then
            a2.currentTarget = nil
            a2.stage = "Idle"
            aj()
            return
        end

        a2.stage = "Attach"
        ak(target)

        a2._hb = b.RunService.RenderStepped:Connect(function()
            if not a2.running then return end
            local hrp = d.humanoidRootPart
            local targetRoot = t(a2.currentTarget)

            if not (hrp and targetRoot and z(a2.currentTarget)) then
                local newTarget = a8()
                if newTarget then
                    a2.currentTarget = newTarget
                    a3(newTarget)
                    goAttachLoop()
                else
                    a2.currentTarget = nil
                    a2.stage = "Idle"
                    aj()
                    aI()
                end
                return
            end

            if not a2._dodgeActive then a3(a2.currentTarget) end

            if a2._attachA1 then
                local targetCf = targetRoot.CFrame
                local desiredWorldPos = C(targetCf, a2.mode, a2.horizDist, a2.yOffset)
                a2._attachA1.Position = targetCf:VectorToObjectSpace(desiredWorldPos)
            end

            if a2._alignOri then
                local myPos = hrp.Position
                local targetPos = targetRoot.Position
                local dir = targetPos - myPos
                local mag = dir.Magnitude
                if mag > 1e-4 then
                    dir = dir / mag
                    local up = Vector3.yAxis
                    if math.abs(dir:Dot(up)) > 0.98 then up = Vector3.xAxis end
                    a2._alignOri.CFrame = CFrame.lookAt(myPos, targetPos, up)
                end
            end
        end)
    end

    local aM = goAttachLoop

    ------------------------------------------------------------------------
    -- Approach movement (walk/tween etc.), then attach
    ------------------------------------------------------------------------
    local function goApproachThenAttach()
        aJ()
        aI()
        aj()

        local target = a2.currentTarget
        if not z(target) then
            a2.currentTarget = a8()
            target = a2.currentTarget
            if not target then
                a2.stage = "Idle"
                notify("No valid targets to attach.", 2)
                return
            end
        end

        a2.stage = "Approach"
        a3(target)

        -- Teleport mode
        if string.lower(tostring(a2.movement)) == "teleport" then
            if aK(target) then
                aM()
            else
                notify("Teleport failed (no HRP/target).", 2)
                a2.stage = "Idle"
            end
            return
        end

        -- Approach mode
        local function computeTargetPosition()
            local hrp = d.humanoidRootPart
            local targetRoot = t(target)
            if not (hrp and targetRoot and z(target)) then return nil end
            return targetRoot.Position + C(targetRoot.CFrame, a2.mode, a2.horizDist, a2.yOffset)
        end

        local initialPos = computeTargetPosition()
        if not initialPos then
            notify("Failed to compute approach position.", 2)
            a2.stage = "Idle"
            return
        end

        a2._moveCleanup = h(
            initialPos,
            tonumber(m.approachSpeed) or 1000,
            function() return computeTargetPosition() end
        )

        local startTime   = os.clock()
        local maxDuration = m.approachMaxSecs or 12
        local reachDist   = m.reachDistance or 3

        a2._hb = b.RunService.Heartbeat:Connect(function()
            if not a2.running then return end
            local hrp = d.humanoidRootPart
            local targetPos = computeTargetPosition()

            if not (hrp and targetPos and z(target)) then
                local newTarget = a8()
                if newTarget then
                    a2.currentTarget = newTarget
                    target = newTarget
                    a3(newTarget)
                else
                    a2.currentTarget = nil
                    a2.stage = "Idle"
                    aJ()
                    aI()
                end
                return
            end

            if (hrp.Position - targetPos).Magnitude <= reachDist then
                aM()
                return
            end

            if os.clock() - startTime > maxDuration then
                notify("Attach approach timeout.", 2)
                a2.stage = "Idle"
                aJ()
                aI()
            end
        end)
    end

    local aU = goApproachThenAttach

    ------------------------------------------------------------------------
    -- No-Op Function for API compatibility
    ------------------------------------------------------------------------
    -- This function was used to rebuild the UI dropdowns. 
    -- It is kept as a stub so API calls to RebuildTargetNames do not error.
    local function b5() 
    end

    ------------------------------------------------------------------------
    -- Public API
    ------------------------------------------------------------------------
    local AttachEngine = {}

    function AttachEngine.HrpOf(target) return t(target) end
    function AttachEngine.HumOf(target) return w(target) end
    function AttachEngine.IsAlive(target) return x(target) end
    function AttachEngine.IsValid(target) return z(target) end

    function AttachEngine.ComputeOffset(cf, mode, horiz, y)
        return C(cf, mode or a2.mode, horiz or a2.horizDist, y or a2.yOffset)
    end

    function AttachEngine.SetMovement(movementMode) a2.movement = movementMode or a2.movement end
    function AttachEngine.GetMovement() return a2.movement end
    function AttachEngine.SetMode(mode) a2.mode = mode or a2.mode end
    function AttachEngine.SetYOffset(y) a2.yOffset = y or a2.yOffset end
    function AttachEngine.SetHorizDist(dist) a2.horizDist = dist or a2.horizDist end
    function AttachEngine.EnableAutoYOffset(enabled) a2.autoYOffset = not not enabled end

    function AttachEngine.EnableDodge(enabled)
        a2.dodgeMode = not not enabled
        if a2.dodgeMode then aG() else aq() end
    end

    function AttachEngine.RebuildTargetNames() b5() end
    function AttachEngine.ChooseNearest() return a8() end
    function AttachEngine.SetTarget(target) a2.currentTarget = target end
    function AttachEngine.GetTarget() return a2.currentTarget end
    function AttachEngine.SetSelectedNames(names) a2.selectedNames = names or {} end
    function AttachEngine.GetSelectedNames() return a2.selectedNames end
    function AttachEngine.TeleportToTarget(target) return aK(target or a2.currentTarget) end

    function AttachEngine.CreateAttach(target)
        ak(target or a2.currentTarget)
        return a2._alignPos, a2._alignOri
    end

    function AttachEngine.DestroyAttach() aj() end
    function AttachEngine.GoApproach() aU() end
    function AttachEngine.GoAttach() aM() end

    function AttachEngine.PerformDodge(dodgeYOffset, duration)
        as(dodgeYOffset or (a2.yOffset + 10), duration or 0.5)
    end

    function AttachEngine.Start()
        if not d.humanoidRootPart then
            notify("No HumanoidRootPart; cannot attach.", 3)
            return
        end

        a2.running = true
        aG()
        a2.currentTarget = a8()
        if a2.currentTarget then
            aU()
        else
            notify("No targets selected / visible.", 2)
        end
    end

    function AttachEngine.Stop()
        a2.running = false
        aI()
        aJ()
        aj()
        aq()
        a2.currentTarget = nil
        a2.stage = "Idle"
    end

    function AttachEngine.Unload()
        AttachEngine.Stop()
    end

    -- Expose raw state for debugging / tweaking
    AttachEngine.State = a2

    return AttachEngine
end
