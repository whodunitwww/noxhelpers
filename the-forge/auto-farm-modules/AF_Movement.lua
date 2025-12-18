-- AF_Movement.lua
-- UPDATED: Uses Forced-Anchor Cannon TP Bypass and Respawn-Safe logic
return function(env)
    local AttachPanel  = env.AttachPanel
    local MoveToPos    = env.MoveToPos
    local getLocalHRP  = env.getLocalHRP
    local FarmState    = env.FarmState
    local AF_Config    = env.AF_Config
    local Services     = env.Services or {}
    local References   = env.References or {}
    local Players      = Services.Players or game:GetService("Players")

    -- Attach settings constants
    local ORE_ATTACH_MODE   = "Aligned"
    local ORE_ATTACH_Y_BASE = -8
    local ORE_ATTACH_HORIZ  = 0
    local ORE_HIT_INTERVAL  = 0.15
    local ORE_HIT_DIST      = 20

    local MOB_ATTACH_MODE   = "Aligned"
    local MOB_ATTACH_Y_BASE = -7
    local MOB_ATTACH_HORIZ  = 0
    local MOB_HIT_INTERVAL  = 0.15
    local MOB_HIT_DIST      = 20

    -- Cannon Path
    local CANNON_PATH = workspace.Assets["Main Island [2]"]["Land [2]"]:GetChildren()[21].CannonPart

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
            dodgeRange  = state.dodgeRange
        }
    end

    local function restoreAttachSettings()
        if not SavedAttach then return end
        if AttachPanel.SetMode then AttachPanel.SetMode(SavedAttach.mode) end
        if AttachPanel.SetYOffset then AttachPanel.SetYOffset(SavedAttach.yOffset) end
        if AttachPanel.SetHorizDist then AttachPanel.SetHorizDist(SavedAttach.horizDist) end
        if AttachPanel.SetMovement then AttachPanel.SetMovement(SavedAttach.movement) end
        if AttachPanel.EnableAutoYOffset then AttachPanel.EnableAutoYOffset(SavedAttach.autoYOffset) end
        if AttachPanel.EnableDodge then AttachPanel.EnableDodge(SavedAttach.dodgeMode) end
        local state = AttachPanel.State
        if state then state.dodgeRange = SavedAttach.dodgeRange end
        SavedAttach = nil
    end

    local function configureAttachForMode(modeName)
        if modeName == "Ores" then
            local y = ORE_ATTACH_Y_BASE + AF_Config.ExtraYOffset
            if AttachPanel.SetMode then AttachPanel.SetMode(ORE_ATTACH_MODE) end
            if AttachPanel.SetYOffset then AttachPanel.SetYOffset(y) end
            if AttachPanel.SetHorizDist then AttachPanel.SetHorizDist(ORE_ATTACH_HORIZ) end
        elseif modeName == "Enemies" then
            local y = MOB_ATTACH_Y_BASE + AF_Config.ExtraYOffset
            if AttachPanel.SetMode then AttachPanel.SetMode(MOB_ATTACH_MODE) end
            if AttachPanel.SetYOffset then AttachPanel.SetYOffset(y) end
            if AttachPanel.SetHorizDist then AttachPanel.SetHorizDist(MOB_ATTACH_HORIZ) end
        end
        if AttachPanel.SetMovement then AttachPanel.SetMovement("Approach") end
        if AttachPanel.EnableAutoYOffset then AttachPanel.EnableAutoYOffset(false) end
        if AttachPanel.EnableDodge then AttachPanel.EnableDodge(false) end
    end

    local function stopMoving()
        if FarmState.moveCleanup then
            pcall(FarmState.moveCleanup)
            FarmState.moveCleanup = nil
        end
    end

    local function safeComputeOffset(rootCFrame, modeName)
        local baseY = (modeName == "Ores") and ORE_ATTACH_Y_BASE or MOB_ATTACH_Y_BASE
        if not AttachPanel or not AttachPanel.ComputeOffset then
            return Vector3.new(0, baseY + AF_Config.ExtraYOffset, 0)
        end
        local attachMode  = (modeName == "Ores") and ORE_ATTACH_MODE or MOB_ATTACH_MODE
        local attachHoriz = (modeName == "Ores") and ORE_ATTACH_HORIZ or MOB_ATTACH_HORIZ
        local offsetYBase = baseY + AF_Config.ExtraYOffset
        local ok, result = pcall(AttachPanel.ComputeOffset, rootCFrame, attachMode, attachHoriz, offsetYBase)
        if ok and typeof(result) == "Vector3" then
            return result 
        end
        return Vector3.new(0, baseY + AF_Config.ExtraYOffset, 0)
    end

    local function realignAttach(target, overrideDef)
        if not target then return end
        local modeName = overrideDef and overrideDef.name or FarmState.mode
        local state = AttachPanel.State
        if not state then return end
        local attachA1 = state._attachA1
        local alignOri = state._alignOri
        local hrp      = getLocalHRP()
        local rootPart = (overrideDef and overrideDef.getRoot and overrideDef.getRoot(target)) or target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart or target
        if not (attachA1 and alignOri and hrp and rootPart) then return end

        local offsetWorld = safeComputeOffset(rootPart.CFrame, modeName)
        attachA1.Position = rootPart.CFrame:VectorToObjectSpace(offsetWorld)
        alignOri.CFrame = CFrame.lookAt(hrp.Position, rootPart.Position, Vector3.yAxis)
    end

    local function attachToTarget(target, overrideDef)
        if not target then return end
        if overrideDef then
            if AttachPanel.SetMode then AttachPanel.SetMode(overrideDef.attachMode) end
            if AttachPanel.SetYOffset then AttachPanel.SetYOffset(overrideDef.attachBaseY + AF_Config.ExtraYOffset) end
            if AttachPanel.SetHorizDist then AttachPanel.SetHorizDist(overrideDef.attachHoriz) end
        else
            configureAttachForMode(FarmState.mode)
        end
        if AttachPanel.SetTarget then AttachPanel.SetTarget(target) end
        if AttachPanel.CreateAttach then AttachPanel.CreateAttach(target) end
        realignAttach(target, overrideDef)
    end

    -- THE BYPASS MOVEMENT LOGIC
    local function startMovingToTarget(target, overrideDef)
        if AttachPanel.DestroyAttach then pcall(AttachPanel.DestroyAttach) end
        stopMoving()
        
        local hrp = getLocalHRP()
        if not hrp then return end

        local function getFinalCFrame()
            if not target or not target.Parent then return nil end
            local root = (overrideDef and overrideDef.getRoot and overrideDef.getRoot(target)) or target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart or target
            if not root then return nil end
            local modeName = overrideDef and overrideDef.name or FarmState.mode
            local offset = safeComputeOffset(root.CFrame, modeName)
            return root.CFrame * CFrame.new(offset)
        end

        local targetCFrame = getFinalCFrame()
        if not targetCFrame then return end

        local prompt = CANNON_PATH:FindFirstChildOfClass("ProximityPrompt")
        local active = true

        -- Background Spammer
        task.spawn(function()
            while active do
                if prompt then fireproximityprompt(prompt) end
                task.wait(0.05)
            end
        end)

        task.wait(0.1)
        
        hrp.CFrame = CANNON_PATH.CFrame
        task.wait(0.48) 
        hrp.CFrame = targetCFrame

        -- 3. FORCED VELOCITY NEUTRALIZER
        -- We anchor the HRP to kill all physics force instantly
        hrp.Anchored = true 
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        
        task.wait(0.2) -- Stay anchored long enough for the cannon script to stop applying force
        hrp.Anchored = false 

        active = false 
        
        -- Finalize Attachment (Only after bypass is finished)
        attachToTarget(target, overrideDef)
    end

    return {
        configureAttachForMode = configureAttachForMode,
        saveAttachSettings     = saveAttachSettings,
        restoreAttachSettings  = restoreAttachSettings,
        stopMoving             = stopMoving,
        realignAttach          = realignAttach,
        attachToTarget         = attachToTarget,
        startMovingToTarget    = startMovingToTarget
    }
end
