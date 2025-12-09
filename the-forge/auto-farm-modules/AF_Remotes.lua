-- AF_Remotes.lua
-- Remote references and tool invocation helper
return function(env)
    local Services = env.Services

    local ToolActivatedRF = Services.ReplicatedStorage
        :WaitForChild("Shared")
        :WaitForChild("Packages")
        :WaitForChild("Knit")
        :WaitForChild("Services")
        :WaitForChild("ToolService")
        :WaitForChild("RF")
        :WaitForChild("ToolActivated")

    local PurchaseRF = Services.ReplicatedStorage
        :WaitForChild("Shared")
        :WaitForChild("Packages")
        :WaitForChild("Knit")
        :WaitForChild("Services")
        :WaitForChild("ProximityService")
        :WaitForChild("RF")
        :WaitForChild("Purchase")

    local function swingTool(remoteArg)
        local ok, err = pcall(function()
            ToolActivatedRF:InvokeServer(remoteArg)
        end)
        if not ok then
            warn("[AutoFarm] ToolActivated error:", err)
        end
    end

    return {
        ToolActivatedRF = ToolActivatedRF,
        PurchaseRF = PurchaseRF,
        swingTool = swingTool
    }
end
