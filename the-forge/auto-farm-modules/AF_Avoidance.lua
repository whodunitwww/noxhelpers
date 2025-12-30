-- AF_Avoidance.lua
-- Hazard (lava) + player avoidance helpers for The Forge autofarm

return function(env)
    ----------------------------------------------------------------
    -- CONTEXT & SAFE SERVICE BINDINGS
    ----------------------------------------------------------------
    local Services    = env.Services or {}
    local References  = env.References or {}
    local getLocalHRP = env.getLocalHRP
    local MoveToPos   = env.MoveToPos
    local stopMoving  = env.stopMoving
    local FarmState   = env.FarmState
    local AF_Config   = env.AF_Config

    -- Always fall back to game:GetService so we never index nil with 'Players'
    local Workspace         = Services.Workspace         or game:GetService("Workspace")
    local CollectionService = Services.CollectionService or game:GetService("CollectionService")

    local function getPlayersService()
        return Services.Players or game:GetService("Players")
    end

    -- Local, *safe* version of getLocalPlayer (no global dependency)
    local function getLocalPlayer()
        -- Prefer the reference from your main context if present
        if References.player and typeof(References.player) == "Instance" then
            return References.player
        end
        local players = getPlayersService()
        return players and players.LocalPlayer
    end

    ----------------------------------------------------------------
    -- INTERNAL STATE
    ----------------------------------------------------------------
    local Hazards = {}  -- { { part = BasePart, cframe = CFrame, halfSize = Vector3 } }
    local RedCaveMin = Vector3.new(
        math.min(360.7152099609375, 771.6004638671875),
        math.min(0.97214126586914, 79.01676177978516),
        math.min(111.72977447509766, -149.13143920898438)
    )
    local RedCaveMax = Vector3.new(
        math.max(360.7152099609375, 771.6004638671875),
        math.max(0.97214126586914, 79.01676177978516),
        math.max(111.72977447509766, -149.13143920898438)
    )

    ----------------------------------------------------------------
    -- HAZARD SCANNING
    ----------------------------------------------------------------

    local function isHazardPart(part)
        if not part or not part:IsA("BasePart") then return false end

        local name = part.Name:lower()
        if name:find("lava") or name:find("kill") or name:find("acid") then
            return true
        end

        if part:GetAttribute("Lava") == true
        or part:GetAttribute("Hazard") == true
        or part:GetAttribute("KillBrick") == true then
            return true
        end

        -- CollectionService tags, if the game uses them
        local ok, hasTag = pcall(function()
            return CollectionService:HasTag(part, "Lava")
                or CollectionService:HasTag(part, "Hazard")
                or CollectionService:HasTag(part, "KillBrick")
        end)
        if ok and hasTag then
            return true
        end

        return false
    end

    local function rebuildHazardsFromWorkspace()
        table.clear(Hazards)

        if not Workspace then return end

        for _, inst in ipairs(Workspace:GetDescendants()) do
            if inst:IsA("BasePart") and isHazardPart(inst) then
                local part = inst
                local half = (part.Size * 0.5) + Vector3.new(2, 2, 2) -- small padding
                table.insert(Hazards, {
                    part     = part,
                    cframe   = part.CFrame,
                    halfSize = half,
                })
            end
        end
    end

    local function refreshHazards()
        if not AF_Config.AvoidLava then
            -- If lava avoidance is off, we still clear the list so we don’t waste time scanning it.
            table.clear(Hazards)
            return
        end

        rebuildHazardsFromWorkspace()
    end

    ----------------------------------------------------------------
    -- HAZARD QUERIES
    ----------------------------------------------------------------

    local function isPointInRedCave(pos)
        if not pos then
            return false
        end
        return pos.X >= RedCaveMin.X and pos.X <= RedCaveMax.X
            and pos.Y >= RedCaveMin.Y and pos.Y <= RedCaveMax.Y
            and pos.Z >= RedCaveMin.Z and pos.Z <= RedCaveMax.Z
    end

    local function isPointInHazard(pos)
        if AF_Config.AvoidRedCave and isPointInRedCave(pos) then
            return true
        end

        if not AF_Config.AvoidLava then
            return false
        end

        if #Hazards == 0 then
            -- First time / map changed
            rebuildHazardsFromWorkspace()
            if #Hazards == 0 then
                return false
            end
        end

        for _, hz in ipairs(Hazards) do
            local part = hz.part
            if part and part.Parent then
                local cf       = hz.cframe
                local half     = hz.halfSize
                local localPos = cf:PointToObjectSpace(pos)

                if math.abs(localPos.X) <= half.X
                and math.abs(localPos.Y) <= half.Y
                and math.abs(localPos.Z) <= half.Z then
                    return true
                end
            end
        end

        return false
    end

    ----------------------------------------------------------------
    -- PLAYER PROXIMITY HELPERS
    ----------------------------------------------------------------

    local function isAnyPlayerNearPosition(position, radius)
        local lp = getLocalPlayer()
        if not lp then return false, nil, nil end

        local nearest, nearestDist = nil, math.huge

        local playersService = getPlayersService()
        if not playersService then
            return false, nil, nil
        end

        for _, plr in ipairs(playersService:GetPlayers()) do
            if plr ~= lp then
                local char = plr.Character
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local d = (hrp.Position - position).Magnitude
                    if d <= radius and d < nearestDist then
                        nearestDist = d
                        nearest     = plr
                    end
                end
            end
        end

        if nearest then
            return true, nearest, nearestDist
        end
        return false, nil, nil
    end

    local function isAnyPlayerNearHRP(radius)
        local hrp = getLocalHRP()
        if not hrp then return false, nil, nil end
        return isAnyPlayerNearPosition(hrp.Position, radius)
    end

    ----------------------------------------------------------------
    -- PLAYER AVOIDANCE MOVEMENT
    ----------------------------------------------------------------

    local function pickSafeAvoidPosition(currentPos, awayDir, baseRadius)
        local horiz = Vector3.new(awayDir.X, 0, awayDir.Z)
        if horiz.Magnitude < 1e-3 then
            horiz = Vector3.new(1, 0, 0)
        else
            horiz = horiz.Unit
        end

        local function tryDir(dir)
            local target = currentPos + dir * (baseRadius + 10)
            target = Vector3.new(target.X, currentPos.Y, target.Z)
            if not isPointInHazard(target) then
                return target
            end
            return nil
        end

        -- 1) Straight away
        local candidate = tryDir(horiz)
        if candidate then return candidate end

        -- 2) Rotate 90° left
        local left = Vector3.new(-horiz.Z, 0, horiz.X)
        candidate = tryDir(left)
        if candidate then return candidate end

        -- 3) Rotate 90° right
        local right = Vector3.new(horiz.Z, 0, -horiz.X)
        candidate = tryDir(right)
        if candidate then return candidate end

        -- 4) Fallback: small step in any direction (even if lava, we tried)
        return currentPos + horiz * (baseRadius + 5)
    end

    local function moveAwayFromNearbyPlayers()
        local hrp = getLocalHRP()
        if not hrp then return end

        local radius = AF_Config.PlayerAvoidRadius or 40
        local lp     = getLocalPlayer()
        if not lp then return end

        local nearest, nearestDist, nearestPos = nil, math.huge, nil

        local playersService = getPlayersService()
        if not playersService then
            return
        end

        for _, plr in ipairs(playersService:GetPlayers()) do
            if plr ~= lp then
                local char = plr.Character
                local phrp = char and char:FindFirstChild("HumanoidRootPart")
                if phrp then
                    local d = (phrp.Position - hrp.Position).Magnitude
                    if d <= radius and d < nearestDist then
                        nearestDist = d
                        nearest     = plr
                        nearestPos  = phrp.Position
                    end
                end
            end
        end

        if not nearest or not nearestPos then
            return
        end

        local awayDir = (hrp.Position - nearestPos)
        if awayDir.Magnitude < 1e-3 then
            awayDir = Vector3.new(1, 0, 0)
        end

        local safePos = pickSafeAvoidPosition(hrp.Position, awayDir, radius)
        if not safePos then
            return
        end

        -- Mark that we're in an avoidance move
        FarmState.avoidingPlayer    = true
        FarmState.lastAvoidMoveTime = os.clock()

        -- Cancel current movement, then move out
        stopMoving()
        local cleanup = MoveToPos(safePos, AF_Config.FarmSpeed or 80)
        FarmState.moveCleanup = cleanup
    end

    ----------------------------------------------------------------
    -- PUBLIC API
    ----------------------------------------------------------------

    return {
        refreshHazards            = refreshHazards,
        isPointInHazard           = isPointInHazard,
        isAnyPlayerNearHRP        = isAnyPlayerNearHRP,
        isAnyPlayerNearPosition   = isAnyPlayerNearPosition,
        moveAwayFromNearbyPlayers = moveAwayFromNearbyPlayers,
    }
end
