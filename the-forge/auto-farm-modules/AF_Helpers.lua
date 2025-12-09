-- AF_Helpers.lua
-- General utility functions (HRP reference, notifications, etc.)
return function(env)
    local References = env.References
    local Library    = env.Library
    local Services   = env.Services
    local VirtualInputManager = env.VirtualInputManager
    local Players    = Services.Players

    local function getLocalHRP()
        return References.humanoidRootPart
    end

    local function notify(msg, time)
        if Library and Library.Notify then
            Library:Notify(msg, time or 3)
        end
    end

    local function freezeCharacter(char)
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum  = char:FindFirstChildOfClass("Humanoid")
        if not root or not hum then return end

        -- Only save once
        if not root:GetAttribute("CerbStateSaved") then
            root:SetAttribute("CerbPrevAnchored", root.Anchored)
            root:SetAttribute("CerbPrevVel", root.AssemblyLinearVelocity)
            root:SetAttribute("CerbPrevRotVel", root.AssemblyAngularVelocity)

            root:SetAttribute("CerbPrevState", hum:GetState())
            root:SetAttribute("CerbPrevWalkSpeed", hum.WalkSpeed)
            root:SetAttribute("CerbPrevJumpPower", hum.JumpPower)
            root:SetAttribute("CerbPrevPlatformStand", hum.PlatformStand)
            root:SetAttribute("CerbPrevAutoRotate", hum.AutoRotate)

            root:SetAttribute("CerbStateSaved", true)
        end

        -- HARD FREEZE
        root.Anchored = true
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero

        hum.WalkSpeed = 0
        hum.JumpPower = 0
        hum.AutoRotate = false
        hum.PlatformStand = true

        pcall(function()
            hum:ChangeState(Enum.HumanoidStateType.Physics)
        end)
    end

    local function unfreezeCharacter(char)
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum  = char:FindFirstChildOfClass("Humanoid")
        if not root or not hum then return end

        if not root:GetAttribute("CerbStateSaved") then return end

        -- Restore values
        root.Anchored = root:GetAttribute("CerbPrevAnchored")
        root.AssemblyLinearVelocity = root:GetAttribute("CerbPrevVel")
        root.AssemblyAngularVelocity = root:GetAttribute("CerbPrevRotVel")

        hum.WalkSpeed = root:GetAttribute("CerbPrevWalkSpeed")
        hum.JumpPower = root:GetAttribute("CerbPrevJumpPower")
        hum.AutoRotate = root:GetAttribute("CerbPrevAutoRotate")
        hum.PlatformStand = root:GetAttribute("CerbPrevPlatformStand")

        pcall(function()
            hum:ChangeState(root:GetAttribute("CerbPrevState"))
        end)

        -- Allow new freeze cycles
        root:SetAttribute("CerbStateSaved", nil)
    end

    local function equipHotbarItemByName(name)
        local player = Players.LocalPlayer
        local pg = player and player:FindFirstChild("PlayerGui")
        local hb = pg and pg:FindFirstChild("BackpackGui") 
                    and pg.BackpackGui:FindFirstChild("Backpack") 
                    and pg.BackpackGui.Backpack:FindFirstChild("Hotbar")
        if not hb then return false end

        for _, slot in ipairs(hb:GetChildren()) do
            local idx = tonumber(slot.Name)
            if idx then
                local frame = slot:FindFirstChild("Frame")
                local tn = frame and frame:FindFirstChild("ToolName")
                if tn and tn.Text == name then
                    local keyMap = {
                        Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three,
                        Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six,
                        Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
                        Enum.KeyCode.Zero,
                    }
                    local kc = keyMap[idx]
                    if kc then
                        VirtualInputManager:SendKeyEvent(true, kc, false, player)
                        task.wait(0.05)
                        VirtualInputManager:SendKeyEvent(false, kc, false, player)
                        return true
                    end
                end
            end
        end
        return false
    end

    return {
        getLocalHRP = getLocalHRP,
        notify = notify,
        freezeCharacter = freezeCharacter,
        unfreezeCharacter = unfreezeCharacter,
        equipHotbarItemByName = equipHotbarItemByName
    }
end
