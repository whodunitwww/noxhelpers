-- AF_Potions.lua
-- Manages auto-using potions and auto-restocking with Cannon Bypass
return function(env)
    local Services        = env.Services
    local Options         = env.Options
    local Toggles         = env.Toggles
    local FarmState       = env.FarmState
    local PurchaseRF      = env.PurchaseRF
    local ToolActivatedRF = env.ToolActivatedRF
    local notify          = env.notify
    local AttachPanel     = env.AttachPanel
    local stopMoving      = env.stopMoving

    local Players = Services.Players or game:GetService("Players")

    local RESTOCK_CFRAME = CFrame.new(-94.434898, 20.585484, -34.270695)
    local PotionDisplayToToolId = {
        ["Damage Potion I"] = "AttackDamagePotion1",
        ["Speed Potion I"]  = "MovementSpeedPotion1",
        ["Health Potion I"] = "HealthPotion1",
        ["Luck Potion I"]   = "LuckPotion1",
        ["Miner Potion I"]  = "MinerPotion1",
    }

    -- Helper to find the cannon (Same logic as Movement module)
    local function getCannonPart()
        local land = workspace.Assets:FindFirstChild("Main Island [2]")
        if land then
            local subLand = land:FindFirstChild("Land [2]")
            if subLand then
                local children = subLand:GetChildren()
                if children[21] and children[21]:FindFirstChild("CannonPart") then
                    return children[21].CannonPart
                end
                for _, child in ipairs(children) do
                    if child:FindFirstChild("CannonPart") then
                        return child.CannonPart
                    end
                end
            end
        end
        return nil
    end

    local function getPotionCount(displayName)
        local player = Players.LocalPlayer
        if not player then return 0 end
        local playerGui   = player:FindFirstChild("PlayerGui")
        local backpackGui = playerGui and playerGui:FindFirstChild("BackpackGui")
        local backpack    = backpackGui and backpackGui:FindFirstChild("Backpack")
        local hotbar      = backpack and backpack:FindFirstChild("Hotbar")
        if not hotbar then return 0 end
        for _, slot in pairs(hotbar:GetChildren()) do
            local frame = slot:FindFirstChild("Frame")
            if frame then
                local toolName = frame:FindFirstChild("ToolName")
                if toolName and toolName.Text == displayName then
                    local stack = frame:FindFirstChild("StackNumber")
                    if stack and stack.Visible and stack.Text ~= "" then
                        return tonumber(string.match(stack.Text, "%d+")) or 1
                    else
                        return 1
                    end
                end
            end
        end
        return 0
    end

    local function restockPotions(doFreeze)
        local selected = Options.AutoPotions_List.Value
        local didSomething = false
        -- ensure something is selected
        local any = false
        for _, sel in pairs(selected) do
            if sel then any = true; break end
        end
        if not any then return end

        local player = Players.LocalPlayer
        local char = player and player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum  = char and char:FindFirstChild("Humanoid")
        if not root then return end

        FarmState.restocking = true
        
        -- 1. Clean up existing farming states
        stopMoving()
        if AttachPanel.DestroyAttach then pcall(AttachPanel.DestroyAttach) end
        FarmState.attached = false
        FarmState.currentTarget = nil

        -- 2. Execute Cannon Bypass Logic
        local cannonPart = getCannonPart()
        
        if cannonPart then
            local prompt = cannonPart:FindFirstChildOfClass("ProximityPrompt")
            local active = true

            -- A. Background Spammer
            task.spawn(function()
                while active do
                    if prompt then fireproximityprompt(prompt) end
                    task.wait(0.1)
                end
            end)

            -- B. Teleport to Cannon & Wait for connection
            local startWait = os.clock()
            repeat
                root.CFrame = cannonPart.CFrame
                root.AssemblyLinearVelocity = Vector3.zero
                task.wait()
            until (root.Position - cannonPart.Position).Magnitude < 10 or (os.clock() - startWait > 2)
            
            -- C. Interaction Buffer
            task.wait(0.55)

            -- D. Stop Spamming
            active = false

            -- E. Force Un-sit (Prevent snapback)
            if hum then hum.Sit = false end

            -- F. Move to Shop (Velocity Kill Loop)
            root.Anchored = true
            for i = 1, 15 do
                root.CFrame = RESTOCK_CFRAME
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                if hum then hum.Sit = false end
                task.wait(0.05)
            end
            root.Anchored = false
        else
            -- Fallback if no cannon found
            root.AssemblyLinearVelocity = Vector3.zero
            root.CFrame = RESTOCK_CFRAME
            task.wait(0.5)
        end

        -- 3. Purchase potions up to 10 each
        for displayName, isOn in pairs(selected) do
            if isOn then
                local current = getPotionCount(displayName)
                local needed = 10 - current
                local toolId = PotionDisplayToToolId[displayName]
                if needed > 0 and toolId then
                    pcall(function()
                        PurchaseRF:InvokeServer(toolId, needed)
                    end)
                    didSomething = true
                    task.wait(0.05)
                end
            end
        end

        FarmState.restocking = false
        if didSomething then
            notify("Potions restocked.", 2)
        end
    end

    local function needsRestock(threshold)
        threshold = threshold or 2
        local selected = Options.AutoPotions_List and Options.AutoPotions_List.Value
        if type(selected) ~= "table" then return false end
        for name, isOn in pairs(selected) do
            if isOn and getPotionCount(name) < threshold then
                return true
            end
        end
        return false
    end

    local function startPotionLoop()
        if FarmState.potionThread then return end
        FarmState.potionThread = task.spawn(function()
            local lastUse = 0
            while true do
                task.wait(1)
                if not (Toggles.AutoPotions_Enable and Toggles.AutoPotions_Enable.Value) then
                    continue
                end
                
                -- Check auto-restock
                if Toggles.AutoPotions_AutoRestock.Value and needsRestock(2) then
                    -- Only restock if we aren't already doing it
                    if not FarmState.restocking then
                        pcall(function() restockPotions(false) end)
                        task.wait(1)  -- wait for inventory update
                    end
                end
                
                -- Use potions at interval
                local interval = Options.AutoPotions_Interval.Value
                if os.clock() - lastUse < interval then continue end
                lastUse = os.clock()
                
                local selected = Options.AutoPotions_List.Value
                local player = Players.LocalPlayer
                if player and player.Character then
                    local char = player.Character
                    local hum = char:FindFirstChild("Humanoid")
                    local backpack = player:FindFirstChild("Backpack")
                    
                    if hum and backpack and not FarmState.restocking then
                        -- Save currently equipped tool
                        local previouslyEquipped = char:FindFirstChildOfClass("Tool")
                        
                        for displayName, isOn in pairs(selected) do
                            if isOn then
                                local toolId = PotionDisplayToToolId[displayName]
                                local tool = backpack:FindFirstChild(displayName) or char:FindFirstChild(displayName)
                                if not tool and toolId then
                                    tool = backpack:FindFirstChild(toolId) or char:FindFirstChild(toolId)
                                end
                                
                                if tool then
                                    hum:EquipTool(tool)
                                    task.wait(0.3)
                                    if toolId then
                                        pcall(function()
                                            ToolActivatedRF:InvokeServer(toolId)
                                        end)
                                    else
                                        tool:Activate()  -- fallback
                                    end
                                    task.wait(2.5)
                                end
                            end
                        end
                        
                        -- Restore previous tool
                        if previouslyEquipped and previouslyEquipped.Parent == backpack then
                            hum:EquipTool(previouslyEquipped)
                        end
                    end
                end
            end
        end)
    end

    return {
        restockPotions = restockPotions,
        startPotionLoop = startPotionLoop
    }
end
