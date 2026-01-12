-- mazeSrc.lua
-- Maze path visualization module for The Forge
return function(ctx)
    ----------------------------------------------------------------
    -- CONTEXT BINDINGS
    ----------------------------------------------------------------
    local Services            = ctx.Services or {}
    local Tabs                = ctx.Tabs
    local References          = ctx.References
    local Library             = ctx.Library

    local Workspace           = Services.Workspace or workspace

    local function notify(msg, t)
        if Library and Library.Notify then
            Library:Notify(msg, t or 3)
        end
    end

    -- ================== --
    -- ====== MAZE ====== --
    -- ================== --

    local MazeGroupbox = Tabs.Main:AddLeftGroupbox("Maze", "map")

    local function getMazeTargetPosition()
        local endRoom = Workspace:FindFirstChild("EndRoom")
        local door = endRoom and endRoom:FindFirstChild("GlacierDoor")
        if not door then return nil end

        if door:IsA("BasePart") then
            return door.Position
        end

        if door:IsA("Model") then
            if door.PrimaryPart then
                return door.PrimaryPart.Position
            end
            local ok, pivot = pcall(door.GetPivot, door)
            if ok and typeof(pivot) == "CFrame" then
                return pivot.Position
            end
        end

        local part = door:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    local function getFungiTargetPosition()
        local proximity = Workspace:FindFirstChild("Proximity")
        local merchant = proximity and proximity:FindFirstChild("MazeMerchant")
        if not merchant then return nil end

        if merchant:IsA("BasePart") then
            return merchant.Position
        end

        if merchant:IsA("Model") then
            if merchant.PrimaryPart then
                return merchant.PrimaryPart.Position
            end
            local ok, pivot = pcall(merchant.GetPivot, merchant)
            if ok and typeof(pivot) == "CFrame" then
                return pivot.Position
            end
        end

        local part = merchant:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    local function getTargetPosition(name)
        if name == "Maze End" then
            return getMazeTargetPosition()
        end
        if name == "Fungi" then
            return getFungiTargetPosition()
        end
        return nil
    end

    local function getCannonPart()
        -- Cannon location: workspace.Assets.Gaiser.CannonPart
        local assets = Workspace:FindFirstChild("Assets")
        local gaiser = assets and assets:FindFirstChild("Gaiser")
        local cannon = gaiser and gaiser:FindFirstChild("CannonPart")
        return cannon
    end

    local targetOptions = { "Maze End", "Fungi" }
    local selectedTarget = targetOptions[1]

    local function tpToTarget()
        if not References.humanoidRootPart then
            notify("No character.", 3)
            return
        end

        local goal = getTargetPosition(selectedTarget)
        if not goal then
            notify(("Target not found: %s"):format(selectedTarget), 3)
            return
        end

        local hrp = References.humanoidRootPart
        local targetPos = goal + Vector3.new(0, 3, 0)
        local cannonPart = getCannonPart()
        local targetCFrame = CFrame.new(targetPos)

        if cannonPart then
            local prompt = cannonPart:FindFirstChildOfClass("ProximityPrompt")
            local active = true

            task.spawn(function()
                while active do
                    if prompt then fireproximityprompt(prompt) end
                    task.wait(0.1)
                end
            end)

            task.spawn(function()
                local startWait = os.clock()
                repeat
                    hrp.CFrame = cannonPart.CFrame
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    task.wait()
                until (hrp.Position - cannonPart.Position).Magnitude < 10 or (os.clock() - startWait > 2)

                task.wait(0.55)
                active = false

                local hum = References.humanoid
                if hum then hum.Sit = false end

                hrp.Anchored = true
                for i = 1, 12 do
                    hrp.CFrame = targetCFrame
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.AssemblyAngularVelocity = Vector3.zero
                    if hum then hum.Sit = false end
                    task.wait(0.05)
                end
                hrp.Anchored = false
            end)
        else
            local hum = References.humanoid
            hrp.Anchored = true
            for i = 1, 12 do
                hrp.CFrame = targetCFrame
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                if hum then hum.Sit = false end
                task.wait(0.05)
            end
            hrp.Anchored = false
        end
    end

    MazeGroupbox:AddDropdown("Maze_TP_Target", {
        Text = "TP Target",
        Values = targetOptions,
        Default = selectedTarget,
        Callback = function(value)
            selectedTarget = value
        end,
    })

    MazeGroupbox:AddButton({
        Text = "TP Selected",
        Func = tpToTarget,
    })

    return {
        TPToTarget = tpToTarget,
    }
end
