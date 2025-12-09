return function(ctx)
    ----------------------------------------------------------------
    -- CONTEXT / DEPENDENCIES
    ----------------------------------------------------------------
    local Services    = ctx.Services
    local Tabs        = ctx.Tabs
    local References  = ctx.References
    local Library     = ctx.Library
    local Options     = ctx.Options
    local Toggles     = ctx.Toggles
    local META        = ctx.META or {}
    local copyLink    = ctx.copyLink
    local sendWebhook = ctx.SendDiscordWebhook

    ----------------------------------------------------------------
    -- CONNECTION TRACKING / UNLOAD SUPPORT
    ----------------------------------------------------------------
    local TrackedConnections = {}

    local function trackConnection(conn)
        if conn then
            TrackedConnections[#TrackedConnections + 1] = conn
        end
        return conn
    end

    -- Buffers for webhook batching
    local ChatBuffer          -- list<string>
    local StashDiffBuffer     -- list<string>

    -- Time markers for batching
    local lastChatFlushTime
    local lastStashScanTime
    local lastStashSummaryTime
    local lastGoldPollTime
    local lastGoldSummaryTime

    ----------------------------------------------------------------
    -- HOME: INFO / METADATA
    ----------------------------------------------------------------
    local infoGroup = Tabs.Home:AddLeftGroupbox(META.name or "Cerberus", "info")

    infoGroup:AddDivider()
    infoGroup:AddLabel(("Script Version: %s"):format(META.version or "v1.0.0"))
    infoGroup:AddLabel(("Last Updated: %s"):format(META.updated or "Unknown"))
    infoGroup:AddLabel("Status: " .. (META.status or "Stable Release"))
    infoGroup:AddDivider()

    ----------------------------------------------------------------
    -- HOME: LINKS
    ----------------------------------------------------------------
    local urls = META.urls or {}
    local linksGroup = Tabs.Home:AddLeftGroupbox("Links", "link")

    if copyLink and urls.docs then
        linksGroup:AddButton({
            Text    = "Cerberus Docs",
            Tooltip = urls.docs,
            Func    = function()
                copyLink(urls.docs, "Docs link copied!")
            end,
        })
    end

    if copyLink and urls.website then
        linksGroup:AddButton({
            Text    = "Website",
            Tooltip = urls.website,
            Func    = function()
                copyLink(urls.website, "Website link copied!")
            end,
        })
    end

    if copyLink and urls.discord then
        linksGroup:AddButton({
            Text    = "Discord",
            Tooltip = urls.discord,
            Func    = function()
                copyLink(urls.discord, "Discord invite copied!")
            end,
        })
    end

    if copyLink and urls.youtube then
        linksGroup:AddButton({
            Text    = "Youtube",
            Tooltip = urls.youtube,
            Func    = function()
                copyLink(urls.youtube, "Youtube link copied!")
            end,
        })
    end

    if copyLink and urls.scripts then
        linksGroup:AddButton({
            Text    = "More Scripts",
            Tooltip = urls.scripts,
            Func    = function()
                copyLink(urls.scripts, "Scripts link copied!")
            end,
        })
    end

    if copyLink and urls.bunni then
        linksGroup:AddButton({
            Text    = "Premier Executor",
            Tooltip = urls.bunni,
            Func    = function()
                copyLink(urls.bunni, "Bunni link copied!")
            end,
        })
    end

    ----------------------------------------------------------------
    -- HOME: EXECUTOR INFO / CAPABILITY CHECK
    ----------------------------------------------------------------
    local executorGroup = Tabs.Home:AddLeftGroupbox("Executor", "codesandbox")

    -- Check required exploit functions to see how "compatible" we are.
    local function detectExecutorSupport()
        -- Resolve a global, including dotted paths: "syn.request"
        local function resolveGlobal(name)
            local dotIndex = string.find(name, ".", 1, true)
            if dotIndex then
                local root   = name:sub(1, dotIndex - 1)
                local member = name:sub(dotIndex + 1)

                local rootTable
                if getgenv then
                    rootTable = rawget(getgenv(), root)
                end
                if rootTable == nil then
                    rootTable = rawget(_G, root)
                end
                if rootTable == nil and getrenv then
                    rootTable = rawget(getrenv(), root)
                end

                if type(rootTable) == "table" then
                    return rawget(rootTable, member)
                end

                return nil
            end

            local value
            if getgenv then
                value = rawget(getgenv(), name)
            end
            if value == nil then
                value = rawget(_G, name)
            end
            if value == nil and getrenv then
                value = rawget(getrenv(), name)
            end
            return value
        end

        local requiredGlobals = {
            "makefolder",
            "isfile",
            "readfile",
            "writefile",
            "sethiddenproperty",
            "setclipboard",
            "identifyexecutor",
            "setfpscap",
            "gethui",
            "http_request",
            "request",
        }

        local requiredCount  = #requiredGlobals
        local availableCount = 0
        local missingList    = {}

        for index = 1, requiredCount do
            local name  = requiredGlobals[index]
            local value = resolveGlobal(name)

            local isAvailable =
                (name == "gethui" and value ~= nil) or
                (type(value) == "function")

            if isAvailable then
                availableCount += 1
            else
                missingList[#missingList + 1] = name
            end
        end

        local executorNameLower = tostring(References.executorName or ""):lower()
        local isXeno = executorNameLower:find("xeno", 1, true) ~= nil

        local statusMessage

        if availableCount == requiredCount then
            -- Full support
            if isXeno then
                local warnMsg = "Xeno detected: ESP will not work due to weak drawing API."
                Library:Notify(warnMsg, 6)
                statusMessage = warnMsg
            else
                statusMessage = "Full support"
            end
        else
            local notifyText = string.format(
                "Your executor does not fully support this script, %d/%d required functions available.\nMissing: %s",
                availableCount,
                requiredCount,
                table.concat(missingList, ", ")
            )

            Library:Notify(notifyText, 6)
            statusMessage = string.format("Partial support: %d/%d required functions.", availableCount, requiredCount)

            if isXeno then
                statusMessage = statusMessage .. "\nNote: ESP will not work due to weak drawing API (Xeno)."
                Library:Notify("Xeno detected: ESP will not work due to weak drawing API.", 6)
            end
        end

        return statusMessage
    end

    executorGroup:AddLabel("Executor: " .. tostring(References.executorName or "Unknown"), true)
    executorGroup:AddLabel(detectExecutorSupport(), true)

    ----------------------------------------------------------------
    -- BASIC SERVICES / PLAYER
    ----------------------------------------------------------------
    local Players     = Services.Players or game:GetService("Players")
    local RunService  = Services.RunService or game:GetService("RunService")
    local HttpService = Services.HttpService
    local LocalPlayer = Players.LocalPlayer

    ----------------------------------------------------------------
    -- INVENTORY ITEM LISTS (FOR WHITELIST DROPDOWN)
    ----------------------------------------------------------------
    local EssenceRarityMap = {
        ["Tiny Essence"]      = "Common",
        ["Small Essence"]     = "Common",
        ["Medium Essence"]    = "Uncommon",
        ["Large Essence"]     = "Uncommon",
        ["Greater Essence"]   = "Rare",
        ["Superior Essence"]  = "Epic",
        ["Epic Essence"]      = "Epic",
        ["Legendary Essence"] = "Legendary",
        ["Mythical Essence"]  = "Mythical",
    }

    local OreRarityMap = {
        ["Stone"]         = "Common",
        ["Sand Stone"]    = "Common",
        ["Copper"]        = "Common",
        ["Iron"]          = "Common",
        ["Tin"]           = "Uncommon",
        ["Silver"]        = "Uncommon",
        ["Gold"]          = "Uncommon",
        ["Mushroomite"]   = "Rare",
        ["Platinum"]      = "Rare",
        ["Bananite"]      = "Uncommon",
        ["Cardboardite"]  = "Common",
        ["Aite"]          = "Epic",
        ["Poopite"]       = "Epic",
        ["Slimite"]       = "Epic",
        ["Cobalt"]        = "Uncommon",
        ["Titanium"]      = "Uncommon",
        ["Volcanic Rock"] = "Rare",
        ["Lapis Lazuli"]  = "Uncommon",
        ["Quartz"]        = "Rare",
        ["Amethyst"]      = "Rare",
        ["Topaz"]         = "Rare",
        ["Diamond"]       = "Rare",
        ["Sapphire"]      = "Rare",
        ["Boneite"]       = "Rare",
        ["Dark Boneite"]  = "Rare",
        ["Cuprite"]       = "Epic",
        ["Obsidian"]      = "Epic",
        ["Emerald"]       = "Epic",
        ["Ruby"]          = "Epic",
        ["Rivalite"]      = "Epic",
        ["Uranium"]       = "Legendary",
        ["Mythril"]       = "Legendary",
        ["Eye Ore"]       = "Legendary",
        ["Fireite"]       = "Legendary",
        ["Magmaite"]      = "Legendary",
        ["Lightite"]      = "Legendary",
        ["Demonite"]      = "Mythical",
        ["Darkryte"]      = "Mythical",
    }

    local RuneValues = {
        "Miner Shard",
        "Blast Chip",
        "Flame Spark",
        "Briar Notch",
        "Rage Mark",
        "Drain Edge",
        "Ward Patch",
        "Venom Crumb",
    }

    local InventoryWhitelistValues do
        local set = {}
        for name in pairs(EssenceRarityMap) do
            set[name] = true
        end
        for name in pairs(OreRarityMap) do
            set[name] = true
        end
        for _, name in ipairs(RuneValues) do
            set[name] = true
        end

        InventoryWhitelistValues = {}
        for name in pairs(set) do
            table.insert(InventoryWhitelistValues, name)
        end
        table.sort(InventoryWhitelistValues)
    end

    ----------------------------------------------------------------
    -- WEBHOOK CONFIG / UI
    ----------------------------------------------------------------
    local WebhookConfig = {
        WebhookURL          = "",
        WebhookColor        = Color3.fromRGB(54, 150, 45),
        WebhookAnon         = false,
        WH_EventSelection   = {},
        WH_InventoryWhitelist = {},
    }

    local function color3ToTable(color)
        if typeof(color) ~= "Color3" then
            return { r = 54, g = 150, b = 45 }
        end

        return {
            r = math.floor(color.R * 255 + 0.5),
            g = math.floor(color.G * 255 + 0.5),
            b = math.floor(color.B * 255 + 0.5),
        }
    end

    local function tableToColor3(value)
        if typeof(value) == "Color3" then
            return value
        end

        if type(value) == "table"
            and tonumber(value.r)
            and tonumber(value.g)
            and tonumber(value.b)
        then
            return Color3.fromRGB(value.r, value.g, value.b)
        end

        return Color3.fromRGB(54, 150, 45)
    end

    -- Normalise selection table (can be { [value]=true } or array of strings)
    local function normalizeSelection(selection)
        if type(selection) ~= "table" then
            return {}
        end

        local list = {}
        local seen = {}

        for key, value in pairs(selection) do
            if value == true then
                if not seen[key] then
                    table.insert(list, key)
                    seen[key] = true
                end
            elseif type(value) == "string" then
                if not seen[value] then
                    table.insert(list, value)
                    seen[value] = true
                end
            end
        end

        return list
    end

    -- Load persisted defaults (if any)
    if isfile and isfile(References.gameDir .. "/__WebhookDefaults.json") then
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(readfile(References.gameDir .. "/__WebhookDefaults.json"))
        end)

        if ok and type(decoded) == "table" then
            WebhookConfig.WebhookURL   = decoded.WebhookURL or WebhookConfig.WebhookURL
            WebhookConfig.WebhookColor = tableToColor3(decoded.WebhookColor)
            WebhookConfig.WebhookAnon  = decoded.WebhookAnon or WebhookConfig.WebhookAnon
            WebhookConfig.WH_EventSelection =
                normalizeSelection(decoded.WH_EventSelection or WebhookConfig.WH_EventSelection)
            WebhookConfig.WH_InventoryWhitelist =
                normalizeSelection(decoded.WH_InventoryWhitelist or WebhookConfig.WH_InventoryWhitelist)
        end
    end

    -- Webhook event types
    local EVENT_LAUNCH            = "Launch"
    local EVENT_INVENTORY_CHANGE  = "InventoryChange"
    local EVENT_CHAT              = "Chat"
    local EVENT_PLAYER_JOIN_LEAVE = "PlayerJoinLeave"
    local EVENT_GOLD_CHANGE       = "GoldChange"

    local ALL_EVENT_TYPES = {
        EVENT_LAUNCH,
        EVENT_INVENTORY_CHANGE,
        EVENT_CHAT,
        EVENT_PLAYER_JOIN_LEAVE,
        EVENT_GOLD_CHANGE,
    }

    -- Webhook UI
    local webhookGroup = Tabs.Home:AddLeftGroupbox("Webhook", "send")

    webhookGroup:AddInput("WebhookURL", {
        Text             = "Default Webhook",
        Default          = WebhookConfig.WebhookURL,
        Placeholder      = "https://discord.com/api/webhooks/...",
        ClearTextOnFocus = false,
    })

    webhookGroup:AddLabel("Default Color")
        :AddColorPicker("WebhookColor", {
            Title        = "Default Color",
            Default      = WebhookConfig.WebhookColor,
            Transparency = 0,
        })

    webhookGroup:AddToggle("WebhookAnon", {
        Text    = "Anonymize User Data",
        Default = WebhookConfig.WebhookAnon,
    })

    webhookGroup:AddDropdown("WH_EventSelection", {
        Text    = "Reported Events",
        Values  = ALL_EVENT_TYPES,
        Default = WebhookConfig.WH_EventSelection,
        Multi   = true,
        Tooltip = "Select which events you want to send to your webhook.",
    })

    -- NEW: Inventory Change Whitelist
    webhookGroup:AddDropdown("WH_InventoryWhitelist", {
        Text    = "Inventory Change Whitelist",
        Values  = InventoryWhitelistValues,
        Default = WebhookConfig.WH_InventoryWhitelist,
        Multi   = true,
        Tooltip = "Only these items will be reported in stash changes. Leave empty for ALL.",
    })

    ----------------------------------------------------------------
    -- WEBHOOK: UTILITIES
    ----------------------------------------------------------------
    local function getCurrentWebhookColorInt()
        local color = Options.WebhookColor and Options.WebhookColor.Value or Color3.fromRGB(54, 150, 45)
        local r, g, b = math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255)
        return r * 65536 + g * 256 + b
    end

    local function selectionContains(selection, value)
        if type(selection) ~= "table" then
            return false
        end

        if selection[value] == true then
            return true
        end

        for _, v in pairs(selection) do
            if v == value then
                return true
            end
        end

        return false
    end

    local function isEventEnabled(eventName)
        local selection = Options.WH_EventSelection and Options.WH_EventSelection.Value
        if type(selection) ~= "table" then
            return false
        end

        return selectionContains(selection, eventName)
    end

    -- Inventory whitelist:
    --  - If no selection (empty), treat as ALL ITEMS allowed.
    --  - Otherwise only items present in the selection are reported.
    local function isItemWhitelisted(itemName)
        local selection = Options.WH_InventoryWhitelist and Options.WH_InventoryWhitelist.Value
        if type(selection) ~= "table" then
            return true
        end

        -- Detect if there's any actual entry; if not, treat as "no filter" (allow all)
        local hasAny = false
        for k, v in pairs(selection) do
            if v == true or type(v) == "string" then
                hasAny = true
                break
            end
        end

        if not hasAny then
            return true
        end

        return selectionContains(selection, itemName)
    end

    local hasWarnedInvalidWebhook = false

    --- Sends a webhook if enabled for the given event.
    -- @param eventName string (one of EVENT_*)
    -- @param title     string
    -- @param description string
    -- @param usernameOverride string | nil
    -- @param colorOverride number | nil
    -- @param fields    table | nil
    local function sendEventWebhook(eventName, title, description, usernameOverride, colorOverride, fields)
        local url = (Options.WebhookURL and Options.WebhookURL.Value) or ""

        -- Validate URL
        if not url:match("https://discord.com/api/webhooks/") then
            if not hasWarnedInvalidWebhook then
                hasWarnedInvalidWebhook = true
                -- Keeping this silent to avoid spam.
            end
            return
        end

        -- Check event toggle
        if not isEventEnabled(eventName) then
            return
        end

        local color     = colorOverride or (getCurrentWebhookColorInt and getCurrentWebhookColorInt()) or 3577389
        local anonymize = Toggles.WebhookAnon and Toggles.WebhookAnon.Value or false
        local username  = usernameOverride or "Cerberus Webhook"

        task.spawn(function()
            pcall(sendWebhook, url, title, description, username, color, fields, anonymize)
        end)
    end

    ----------------------------------------------------------------
    -- WEBHOOK DEFAULTS: AUTO SAVE ON CHANGE
    ----------------------------------------------------------------
    do
        local function saveWebhookDefaults()
            if not writefile then
                return
            end

            local payload = {
                WebhookURL           = Options.WebhookURL and Options.WebhookURL.Value or "",
                WebhookColor         = color3ToTable(Options.WebhookColor and Options.WebhookColor.Value or WebhookConfig.WebhookColor),
                WebhookAnon          = Toggles.WebhookAnon and Toggles.WebhookAnon.Value or false,
                WH_EventSelection    = normalizeSelection(Options.WH_EventSelection and Options.WH_EventSelection.Value),
                WH_InventoryWhitelist = normalizeSelection(Options.WH_InventoryWhitelist and Options.WH_InventoryWhitelist.Value),
            }

            pcall(function()
                writefile(References.gameDir .. "/__WebhookDefaults.json", HttpService:JSONEncode(payload))
            end)
        end

        -- If there is no defaults file yet, create it once.
        if not (isfile and isfile(References.gameDir .. "/__WebhookDefaults.json")) then
            saveWebhookDefaults()
        end

        -- Hook changes
        for _, optName in ipairs({ "WebhookURL", "WebhookColor", "WH_EventSelection", "WH_InventoryWhitelist" }) do
            if Options[optName] then
                Options[optName]:OnChanged(saveWebhookDefaults)
            end
        end

        if Toggles.WebhookAnon then
            Toggles.WebhookAnon:OnChanged(saveWebhookDefaults)
        end
    end

    ----------------------------------------------------------------
    -- PLAYER HELPER (FOR WEBHOOK TEXT)
    ----------------------------------------------------------------
    local function getPrettyPlayerName(player)
        if not player then
            return "Unknown"
        end

        local displayName = player.DisplayName or player.Name
        if displayName ~= player.Name then
            return string.format("%s (%s)", displayName, player.Name)
        end

        return player.Name
    end

    ----------------------------------------------------------------
    -- CHAT LOGGING
    ----------------------------------------------------------------
    ChatBuffer        = {}
    lastChatFlushTime = os.clock()

    local CHAT_FLUSH_INTERVAL   = 10    -- seconds
    local CHAT_LINES_PER_BATCH  = 20    -- max lines per message
    local CHAT_MAX_CHARS        = 1900  -- max characters in a single webhook description

    local function flushChatBuffer()
        if not isEventEnabled(EVENT_CHAT) then
            table.clear(ChatBuffer)
            return
        end

        if #ChatBuffer == 0 then
            return
        end

        local messageBatch = {}
        local charsInBatch = 0
        local linesInBatch = 0

        local function sendBatch()
            if #messageBatch == 0 then
                return
            end

            local body = table.concat(messageBatch, "\n")
            sendEventWebhook(EVENT_CHAT, "Chat Log", body)

            messageBatch = {}
            charsInBatch = 0
            linesInBatch = 0
        end

        for _, line in ipairs(ChatBuffer) do
            local lineLength = #line + 1
            if linesInBatch >= CHAT_LINES_PER_BATCH or (charsInBatch + lineLength) > CHAT_MAX_CHARS then
                sendBatch()
            end

            table.insert(messageBatch, line)
            charsInBatch += lineLength
            linesInBatch += 1
        end

        sendBatch()
        table.clear(ChatBuffer)
    end

    local function hookPlayerChat(player)
        if not player then
            return
        end

        trackConnection(player.Chatted:Connect(function(message)
            if not isEventEnabled(EVENT_CHAT) then
                return
            end

            message = tostring(message or "")
            if #message > 256 then
                message = message:sub(1, 253) .. "..."
            end

            local line = string.format("**%s**: %s", getPrettyPlayerName(player), message)
            table.insert(ChatBuffer, line)
        end))
    end

    -- Existing players
    for _, player in ipairs(Players:GetPlayers()) do
        hookPlayerChat(player)
    end

    -- New players
    trackConnection(Players.PlayerAdded:Connect(function(player)
        hookPlayerChat(player)
    end))

    ----------------------------------------------------------------
    -- JOIN / LEAVE WEBHOOKS
    ----------------------------------------------------------------
    trackConnection(Players.PlayerAdded:Connect(function(player)
        if player == LocalPlayer then
            return
        end
        if not isEventEnabled(EVENT_PLAYER_JOIN_LEAVE) then
            return
        end

        local text = string.format("**%s** joined the server.", getPrettyPlayerName(player))
        sendEventWebhook(EVENT_PLAYER_JOIN_LEAVE, "Player Joined", text)
    end))

    trackConnection(Players.PlayerRemoving:Connect(function(player)
        if player == LocalPlayer then
            return
        end
        if not isEventEnabled(EVENT_PLAYER_JOIN_LEAVE) then
            return
        end

        local text = string.format("**%s** left the server.", getPrettyPlayerName(player))
        sendEventWebhook(EVENT_PLAYER_JOIN_LEAVE, "Player Left", text)
    end))

    ----------------------------------------------------------------
    -- STASH CHANGE TRACKING (INVENTORY MENU)
    ----------------------------------------------------------------
    StashDiffBuffer      = {}
    lastStashScanTime    = os.clock()
    lastStashSummaryTime = os.clock()

    local STASH_SCAN_INTERVAL     = 2   -- seconds
    local STASH_SUMMARY_INTERVAL  = 15  -- seconds
    local STASH_MAX_LINES_SUMMARY = 40
    local STASH_MAX_CHARS         = 1900

    -- Locates the stash UI frame
    local function getStashBackgroundFrame()
        local playerGui   = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
        local menuGui     = playerGui and playerGui:FindFirstChild("Menu")
        local frame       = menuGui and menuGui:FindFirstChild("Frame")
        local innerFrame  = frame and frame:FindFirstChild("Frame")
        local menus       = innerFrame and innerFrame:FindFirstChild("Menus")
        local stashMenu   = menus and menus:FindFirstChild("Stash")
        return stashMenu and stashMenu:FindFirstChild("Background")
    end

    -- Reads the stash items and returns a map { [name] = quantity }
    local function readStashSnapshot()
        local snapshot   = {}
        local background = getStashBackgroundFrame()
        if not background then
            return snapshot
        end

        for _, child in ipairs(background:GetChildren()) do
            if child:IsA("Frame") then
                local itemName   = child.Name
                local mainFrame  = child:FindFirstChild("Main")
                local qtyLabel   = mainFrame and mainFrame:FindFirstChild("Quantity")

                local qty = 1
                if qtyLabel and qtyLabel:IsA("TextLabel") then
                    local text = tostring(qtyLabel.Text or ""):gsub("%s+", "")
                    if text ~= "" then
                        local match = text:match("x(%d+)") or text:match("(%d+)")
                        qty = tonumber(match) or 1
                    end
                end

                if qty > 0 then
                    snapshot[itemName] = qty
                end
            end
        end

        return snapshot
    end

    local lastStashSnapshot = readStashSnapshot()

    -- Diff and record stash changes, respecting the whitelist and including total
    local function diffStashSnapshots(oldSnapshot, newSnapshot, outDiffList)
        -- Additions / increases
        for itemName, newQty in pairs(newSnapshot) do
            local oldQty = oldSnapshot[itemName] or 0
            if newQty > oldQty and isItemWhitelisted(itemName) then
                local delta = newQty - oldQty
                table.insert(outDiffList, string.format(
                    "+ %dx %s (Stash, Total: %d)",
                    delta,
                    itemName,
                    newQty
                ))
            end
        end

        -- Decreases / removals
        for itemName, oldQty in pairs(oldSnapshot) do
            local newQty = newSnapshot[itemName] or 0
            if newQty < oldQty and isItemWhitelisted(itemName) then
                local delta = oldQty - newQty
                table.insert(outDiffList, string.format(
                    "- %dx %s (Stash, Total: %d)",
                    delta,
                    itemName,
                    newQty
                ))
            end
        end
    end

    local function captureStashChanges()
        if not isEventEnabled(EVENT_INVENTORY_CHANGE) then
            lastStashSnapshot = readStashSnapshot()
            return
        end

        local prevSnapshot = lastStashSnapshot
        local newSnapshot  = readStashSnapshot()
        local diffLines    = {}

        diffStashSnapshots(prevSnapshot, newSnapshot, diffLines)
        lastStashSnapshot = newSnapshot

        if #diffLines == 0 then
            return
        end

        for index, line in ipairs(diffLines) do
            if index > STASH_MAX_LINES_SUMMARY then
                table.insert(StashDiffBuffer, string.format("... %d more change(s)", #diffLines - STASH_MAX_LINES_SUMMARY))
                break
            end
            table.insert(StashDiffBuffer, line)
        end
    end

    local function sendStashSummary()
        if not isEventEnabled(EVENT_INVENTORY_CHANGE) then
            table.clear(StashDiffBuffer)
            return
        end

        if #StashDiffBuffer == 0 then
            return
        end

        local header = string.format("**%s** stash changes:", getPrettyPlayerName(LocalPlayer))
        local lines  = { "```diff" }

        for index, line in ipairs(StashDiffBuffer) do
            if index > STASH_MAX_LINES_SUMMARY then
                table.insert(lines, string.format("# ... %d more change(s)", #StashDiffBuffer - STASH_MAX_LINES_SUMMARY))
                break
            end
            table.insert(lines, line)
        end

        table.insert(lines, "```")

        local body = header .. "\n" .. table.concat(lines, "\n")
        if #body > STASH_MAX_CHARS then
            body = body:sub(1, STASH_MAX_CHARS - 3) .. "..."
        end

        sendEventWebhook(EVENT_INVENTORY_CHANGE, "Stash Changes", body)
        table.clear(StashDiffBuffer)
    end

    ----------------------------------------------------------------
    -- GOLD CHANGE TRACKING
    ----------------------------------------------------------------
    local goldChangeBuffer     = {}
    lastGoldPollTime           = os.clock()
    lastGoldSummaryTime        = os.clock()
    local lastGoldValue        = nil

    local GOLD_POLL_INTERVAL   = 1.5
    local GOLD_SUMMARY_INTERVAL= 15
    local GOLD_MAX_LINES       = 30
    local GOLD_MAX_CHARS       = 1900

    local function getGoldLabel()
        local ok, result = pcall(function()
            local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
            local main      = playerGui and playerGui:FindFirstChild("Main")
            local screen    = main and main:FindFirstChild("Screen")
            local hud       = screen and screen:FindFirstChild("Hud")
            return hud and hud:FindFirstChild("Gold")
        end)

        if ok then
            return result
        end
    end

    local function readGoldAmount()
        local label = getGoldLabel()
        if not (label and label:IsA("TextLabel")) then
            return nil
        end

        local text = tostring(label.Text or "")
        text = text:gsub("[%$,]", "")
        local num = tonumber(text)
        return num
    end

    local function pollGoldChange()
        if not isEventEnabled(EVENT_GOLD_CHANGE) then
            lastGoldValue = readGoldAmount() or lastGoldValue
            return
        end

        local current = readGoldAmount()
        if not current then
            return
        end

        if lastGoldValue == nil then
            lastGoldValue = current
            return
        end

        if current ~= lastGoldValue then
            local delta = current - lastGoldValue
            local sign  = delta > 0 and "+" or ""
            local line  = string.format("%s%.2f ( %.2f -> %.2f )", sign, delta, lastGoldValue, current)
            table.insert(goldChangeBuffer, line)
            lastGoldValue = current
        end
    end

    local function sendGoldSummary()
        if not isEventEnabled(EVENT_GOLD_CHANGE) then
            table.clear(goldChangeBuffer)
            return
        end

        if #goldChangeBuffer == 0 then
            return
        end

        local header = string.format("**%s** gold changes:", getPrettyPlayerName(LocalPlayer))
        local lines  = { "```diff" }

        for index, line in ipairs(goldChangeBuffer) do
            if index > GOLD_MAX_LINES then
                table.insert(lines, string.format("# ... %d more change(s)", #goldChangeBuffer - GOLD_MAX_LINES))
                break
            end
            table.insert(lines, line)
        end

        table.insert(lines, "```")

        local body = header .. "\n" .. table.concat(lines, "\n")
        if #body > GOLD_MAX_CHARS then
            body = body:sub(1, GOLD_MAX_CHARS - 3) .. "..."
        end

        sendEventWebhook(EVENT_GOLD_CHANGE, "Gold Changes", body)
        table.clear(goldChangeBuffer)
    end

    ----------------------------------------------------------------
    -- HEARTBEAT TICK: BATCH + POLL
    ----------------------------------------------------------------
    trackConnection(RunService.Heartbeat:Connect(function()
        local now = os.clock()

        -- Chat batches
        if now - lastChatFlushTime >= CHAT_FLUSH_INTERVAL then
            lastChatFlushTime = now
            flushChatBuffer()
        end

        -- Stash scans
        if now - lastStashScanTime >= STASH_SCAN_INTERVAL then
            lastStashScanTime = now
            captureStashChanges()
        end

        -- Stash summary
        if now - lastStashSummaryTime >= STASH_SUMMARY_INTERVAL then
            lastStashSummaryTime = now
            sendStashSummary()
        end

        -- Gold poll
        if now - lastGoldPollTime >= GOLD_POLL_INTERVAL then
            lastGoldPollTime = now
            pollGoldChange()
        end

        -- Gold summary
        if now - lastGoldSummaryTime >= GOLD_SUMMARY_INTERVAL then
            lastGoldSummaryTime = now
            sendGoldSummary()
        end
    end))

    ----------------------------------------------------------------
    -- LATEST UPDATES / CHANGELOG
    ----------------------------------------------------------------
    local updatesGroup = Tabs.Home:AddRightGroupbox("Latest Updates", "sparkles")
    updatesGroup:AddLabel("Changelogs:", true)

    local changelog = META.changelog or {
        "Added Auto Proximity Prompt",
        "Added Zoom",
        "Added Custom Cursor Builder",
        "Added Emotes",
        "Improved ESP",
    }

    updatesGroup:AddLabel("• " .. table.concat(changelog, "\n• "), true)

    ----------------------------------------------------------------
    -- FEEDBACK BOX
    ----------------------------------------------------------------
    local feedbackGroup = Tabs.Home:AddRightGroupbox("Feedback", "quote")
    local feedbackSent  = false

    feedbackGroup:AddInput("feedbackTextbox", {
        Text             = "Message",
        Default          = nil,
        Numeric          = false,
        Finished         = false,
        ClearTextOnFocus = true,
        Placeholder      = "Write a message to the dev team here.",
        Callback         = function(_) end,
    })

    feedbackGroup:AddButton("Send Feedback", function()
        if feedbackSent then
            Library:Notify(
                "You've already sent feedback, you can come back another time and send some more later.",
                5
            )
            return
        end

        local text = Options.feedbackTextbox and Options.feedbackTextbox.Value
        if text and text ~= "" then
            if sendWebhook then
                sendWebhook(
                    "https://discord.com/api/webhooks/1430125097129214003/mHA_d9XyFaRTfGM9Enf7jZgso358XRmmCFiuwGs6ZO-vws0qPdRLKQH19zRWJ5kZC7hW",
                    References.player.Name .. " has provided feedback.",
                    text,
                    "Cerberus Feedback",
                    nil,
                    nil,
                    false
                )

                Library:Notify("Your feedback has successfully been sent to the developers!", 5)
                feedbackSent = true
            else
                Library:Notify("Feedback webhook function not available.", 3)
            end
        else
            Library:Notify("You need to type your feedback into the box above before you can send it.", 3)
        end
    end)

    ----------------------------------------------------------------
    -- CREDITS + DISCLAIMER
    ----------------------------------------------------------------
    local creditsGroup = Tabs.Home:AddRightGroupbox("Credits + Disclaimer", "shield-alert")

    creditsGroup:AddLabel("Script by @tevilii")
    creditsGroup:AddLabel("Obsidian UI Library by deivid")

    if copyLink and urls.obsidian then
        creditsGroup:AddButton({
            Text    = "Obsidian Library",
            Tooltip = urls.obsidian,
            Func    = function()
                copyLink(urls.obsidian, "Obsidian link copied!")
            end,
        })
    end

    creditsGroup:AddDivider()
    creditsGroup:AddLabel(
        "This script is provided for educational and customization purposes. " ..
        "Respect Roblox and game TOS. You are responsible for your usage.",
        true
    )

    ----------------------------------------------------------------
    -- LAUNCH WEBHOOK
    ----------------------------------------------------------------
    sendEventWebhook(
        EVENT_LAUNCH,
        "Cerberus Initialized",
        string.format(
            "**Join Script:**\n```lua\ngame:GetService(\"TeleportService\"):TeleportToPlaceInstance(%d, \"%s\", game.Players.LocalPlayer)```%s",
            game.PlaceId,
            game.JobId,
            math.random(1, 5) == 1
                and "\n*Join our Discord for the best scripts! https://getcerberus.com/discord*"
                or ""
        )
    )

    ----------------------------------------------------------------
    -- MODULE API
    ----------------------------------------------------------------
    local HomeModule = {}

    function HomeModule.Unload()
        -- Disconnect all tracked connections
        for index, conn in ipairs(TrackedConnections) do
            if conn and conn.Disconnect then
                pcall(function()
                    conn:Disconnect()
                end)
            end
            TrackedConnections[index] = nil
        end

        -- Clear buffers
        if ChatBuffer then
            table.clear(ChatBuffer)
        end
        if StashDiffBuffer then
            table.clear(StashDiffBuffer)
        end

        -- Reset timers
        local now = os.clock()
        lastChatFlushTime     = now
        lastStashScanTime     = now
        lastStashSummaryTime  = now
        lastGoldPollTime      = now
        lastGoldSummaryTime   = now
    end

    return HomeModule
end
