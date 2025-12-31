-- homeSrc.lua
return function(ctx)
    local Services   = ctx.Services
    local Tabs       = ctx.Tabs
    local References = ctx.References
    local Library    = ctx.Library
    local Options    = ctx.Options
    local Toggles    = ctx.Toggles
    local META       = ctx.META or {}
    local copyLink           = ctx.copyLink
    local SendDiscordWebhook = ctx.SendDiscordWebhook

    -- track connections for clean unload
    local connections = {}

    local function track(conn)
        if conn then
            connections[#connections + 1] = conn
        end
        return conn
    end

    -- forward declarations so Unload can see them
    local chatBuffer, invBuffer
    local lastChatFlush, lastInvFlush

    -- generic executor/global resolver
    local function resolveExec(name)
        if type(name) ~= "string" or name == "" then
            return nil
        end

        local dot = string.find(name, ".", 1, true)
        if dot then
            local base, key = name:sub(1, dot - 1), name:sub(dot + 1)
            local t
            if getgenv then t = rawget(getgenv(), base) end
            if t == nil then t = rawget(_G, base) end
            if t == nil and getrenv then t = rawget(getrenv(), base) end
            if type(t) == "table" then
                return rawget(t, key)
            end
            return nil
        end

        local v
        if getgenv then v = rawget(getgenv(), name) end
        if v == nil then v = rawget(_G, name) end
        if v == nil and getrenv then v = rawget(getrenv(), name) end
        return v
    end

    -- ================== --
    -- ==== HOME TAB ==== --
    -- ================== --

    -- ==== ABOUT ==== --
    local aboutGroup = Tabs.Home:AddLeftGroupbox((META.name or "Cerberus"), "info")
    aboutGroup:AddDivider()
    aboutGroup:AddLabel(("Script Version: %s"):format(META.version or "v1.0.0"))
    aboutGroup:AddLabel(("Last Updated: %s"):format(META.updated or "Unknown"))
    aboutGroup:AddLabel("Status: " .. (META.status or "Stable Release"))
    aboutGroup:AddDivider()

    -- ==== LINKS ==== --
    local urls = META.urls or {}

    local linksGroup = Tabs.Home:AddLeftGroupbox("Links", "link")
    if copyLink and urls.docs then
        linksGroup:AddButton({
            Text = "Cerberus Docs",
            Tooltip = urls.docs,
            Func = function() copyLink(urls.docs, "Docs link copied!") end,
        })
    end
    if copyLink and urls.website then
        linksGroup:AddButton({
            Text = "Website",
            Tooltip = urls.website,
            Func = function() copyLink(urls.website, "Website link copied!") end,
        })
    end
    if copyLink and urls.discord then
        linksGroup:AddButton({
            Text = "Discord",
            Tooltip = urls.discord,
            Func = function() copyLink(urls.discord, "Discord invite copied!") end,
        })
    end
    if copyLink and urls.youtube then
        linksGroup:AddButton({
            Text = "Youtube",
            Tooltip = urls.youtube,
            Func = function() copyLink(urls.youtube, "Youtube link copied!") end,
        })
    end
    if copyLink and urls.scripts then
        linksGroup:AddButton({
            Text = "More Scripts",
            Tooltip = urls.scripts,
            Func = function() copyLink(urls.scripts, "Scripts link copied!") end,
        })
    end
    if copyLink and urls.bunni then
        linksGroup:AddButton({
            Text = "Premier Executor",
            Tooltip = urls.bunni,
            Func = function() copyLink(urls.bunni, "Bunni link copied!") end,
        })
    end

    -- ==== EXECUTOR ==== --
    local executorGroup = Tabs.Home:AddLeftGroupbox("Executor", "codesandbox")

    local function getExecutorSupport()
        -- Prefer executor functions injected via META, fall back to legacy list
        local execMeta     = META.executor or {}
        local requiredList = (type(execMeta.required) == "table") and execMeta.required or nil

        local defaultRequired = {
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
            "syn.request",
            "server_desync",
        }

        local toCheck = {}

        if requiredList then
            for _, name in ipairs(requiredList) do
                toCheck[#toCheck + 1] = name
            end
        else
            for _, name in ipairs(defaultRequired) do
                toCheck[#toCheck + 1] = name
            end
        end

        local total   = #toCheck
        local good    = 0
        local missing = {}

        for i = 1, total do
            local name = toCheck[i]
            local v    = resolveExec(name)

            -- gethui can be anything non-nil; everything else we expect functions
            local ok = (name == "gethui") and (v ~= nil) or (type(v) == "function")

            if ok then
                good = good + 1
            else
                missing[#missing + 1] = name
            end
        end

        local execLower = tostring(References.executorName or ""):lower()
        local isXeno    = execLower:find("xeno", 1, true) ~= nil

        local status
        if good == total then
            if isXeno then
                local txt = "Xeno detected: ESP will not work due to weak drawing API."
                Library:Notify(txt, 6)
                status = txt
            else
                status = "Full support"
            end
        else
            local msg = string.format(
                "Your executor does not fully support this script, %d/%d required functions available.\nMissing: %s",
                good, total, table.concat(missing, ", ")
            )
            Library:Notify(msg, 6)
            status = string.format("Partial support: %d/%d required functions.", good, total)

            if isXeno then
                status = status .. "\nNote: ESP will not work due to weak drawing API (Xeno)."
                Library:Notify("Xeno detected: ESP will not work due to weak drawing API.", 6)
            end
        end

        return status
    end

    executorGroup:AddLabel("Executor: " .. tostring(References.executorName or "Unknown"), true)
    executorGroup:AddLabel(getExecutorSupport(), true)

    ----------------------------------------------------------------
    -- ================== WEBHOOK + LOGGING ===================== --
    ----------------------------------------------------------------

    local Players     = Services.Players    or game:GetService("Players")
    local RunService  = Services.RunService or game:GetService("RunService")
    local HttpService = Services.HttpService
    local LocalPlayer = Players.LocalPlayer

    -- defaults
    local webhookDefaults = {
        WebhookURL        = "",
        WebhookColor      = Color3.fromRGB(54, 150, 45),
        WebhookAnon       = false,
        WH_EventSelection = {}, -- stored as an array of event names
    }

    -- JSON / data helpers
    local function SerializeColor3(c)
        if typeof(c) ~= "Color3" then
            return { r = 54, g = 150, b = 45 }
        end
        return {
            r = math.floor(c.R * 255 + 0.5),
            g = math.floor(c.G * 255 + 0.5),
            b = math.floor(c.B * 255 + 0.5),
        }
    end

    local function DeserializeColor3(v)
        if typeof(v) == "Color3" then
            return v
        end
        if type(v) == "table" and tonumber(v.r) and tonumber(v.g) and tonumber(v.b) then
            return Color3.fromRGB(v.r, v.g, v.b)
        end
        return Color3.fromRGB(54, 150, 45)
    end

    local function ConvertSelectionToArray(selection)
        if type(selection) ~= "table" then
            return {}
        end

        local arr, seen = {}, {}

        for key, value in pairs(selection) do
            if value == true then
                if not seen[key] then
                    table.insert(arr, key)
                    seen[key] = true
                end
            elseif type(value) == "string" then
                if not seen[value] then
                    table.insert(arr, value)
                    seen[value] = true
                end
            end
        end

        return arr
    end

    -- executor-backed file helpers
    local isfileFn    = resolveExec("isfile")
    local readfileFn  = resolveExec("readfile")
    local writefileFn = resolveExec("writefile")

    -- load defaults from disk, if present
    if isfileFn and readfileFn and isfileFn(References.gameDir .. "/__WebhookDefaults.json") then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfileFn(References.gameDir .. "/__WebhookDefaults.json"))
        end)

        if ok and type(data) == "table" then
            webhookDefaults.WebhookURL        = data.WebhookURL or webhookDefaults.WebhookURL
            webhookDefaults.WebhookColor      = DeserializeColor3(data.WebhookColor)
            webhookDefaults.WebhookAnon       = data.WebhookAnon or webhookDefaults.WebhookAnon
            webhookDefaults.WH_EventSelection = ConvertSelectionToArray(data.WH_EventSelection or webhookDefaults.WH_EventSelection)
        end
    end

    -- event keys
    local WEBHOOK_EVENT_LAUNCH  = "Launch"
    local WEBHOOK_EVENT_INV     = "InventoryChange" -- now: Backpack changes
    local WEBHOOK_EVENT_CHAT    = "Chat"
    local WEBHOOK_EVENT_PLAYERS = "PlayerJoinLeave"

    local webhookEvents = {
        WEBHOOK_EVENT_LAUNCH,
        WEBHOOK_EVENT_INV,
        WEBHOOK_EVENT_CHAT,
        WEBHOOK_EVENT_PLAYERS,
    }

    -- UI
    local webhookGroup = Tabs.Home:AddLeftGroupbox("Webhook", "send")

    webhookGroup:AddInput("WebhookURL", {
        Text = "Default Webhook",
        Default = webhookDefaults.WebhookURL,
        Placeholder = "https://discord.com/api/webhooks/...",
        ClearTextOnFocus = false,
    })

    webhookGroup:AddLabel("Default Color")
        :AddColorPicker("WebhookColor", {
            Title = "Default Color",
            Default = webhookDefaults.WebhookColor,
            Transparency = 0,
        })

    webhookGroup:AddToggle("WebhookAnon", {
        Text = "Anonymize User Data",
        Default = webhookDefaults.WebhookAnon,
    })

    webhookGroup:AddDropdown("WH_EventSelection", {
        Text = "Reported Events",
        Values = webhookEvents,
        Default = webhookDefaults.WH_EventSelection,
        Multi = true,
        Tooltip = "Select which events you want to send to your webhook.",
    })

    -- core helpers
    local function webhookColorDec()
        local c = Options.WebhookColor and Options.WebhookColor.Value or Color3.fromRGB(54, 150, 45)
        local r, g, b = math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255)
        return r * 65536 + g * 256 + b
    end

    local function webhookIsEventEnabled(eventType)
        local selected = Options.WH_EventSelection and Options.WH_EventSelection.Value
        if type(selected) ~= "table" then
            return false
        end

        -- multi-dropdown can be map-like or array-like depending on the lib
        if selected[eventType] == true then
            return true
        end

        for _, v in pairs(selected) do
            if v == eventType then
                return true
            end
        end

        return false
    end

    local notifiedNoWebhook = false

    local function webhookReport(eventType, title, description, nickname, color, iconUrl)
        local webhookUrl = Options.WebhookURL and Options.WebhookURL.Value or ""
        if not webhookUrl:match("https://discord.com/api/webhooks/") then
            if not notifiedNoWebhook then
                notifiedNoWebhook = true
                -- Library:Notify("No valid Discord webhook set in Webhook section", 3)
            end
            return
        end

        -- Launch can be optionally gated by dropdown; if you want it ALWAYS,
        -- remove this check for WEBHOOK_EVENT_LAUNCH.
        if not webhookIsEventEnabled(eventType) then
            return
        end

        local useColor    = color or (webhookColorDec and webhookColorDec()) or 3577389
        local useAnonym   = Toggles.WebhookAnon and Toggles.WebhookAnon.Value or false
        local useNickname = nickname or "Cerberus Webhook"

        -- individual send (chat / inventory are batched BEFORE this)
        task.spawn(function()
            pcall(
                SendDiscordWebhook,
                webhookUrl,
                title,
                description,
                useNickname,
                useColor,
                iconUrl,
                useAnonym
            )
        end)
    end

    -- config save
    do
        local function SaveWebhookConfig()
            if not writefileFn then
                return
            end

            local data = {
                WebhookURL        = Options.WebhookURL and Options.WebhookURL.Value or "",
                WebhookColor      = SerializeColor3(Options.WebhookColor and Options.WebhookColor.Value or webhookDefaults.WebhookColor),
                WebhookAnon       = Toggles.WebhookAnon and Toggles.WebhookAnon.Value or false,
                WH_EventSelection = ConvertSelectionToArray(Options.WH_EventSelection and Options.WH_EventSelection.Value),
            }

            pcall(function()
                writefileFn(References.gameDir .. "/__WebhookDefaults.json", HttpService:JSONEncode(data))
            end)
        end

        if isfileFn and writefileFn and not isfileFn(References.gameDir .. "/__WebhookDefaults.json") then
            SaveWebhookConfig()
        end

        for _, optionName in ipairs({ "WebhookURL", "WebhookColor", "WH_EventSelection" }) do
            if Options[optionName] then
                Options[optionName]:OnChanged(SaveWebhookConfig)
            end
        end
        if Toggles.WebhookAnon then
            Toggles.WebhookAnon:OnChanged(SaveWebhookConfig)
        end
    end

    ----------------------------------------------------------------
    -- ================== EVENT LOGGING ========================== --
    ----------------------------------------------------------------
    do
        local function safeName(plr)
            if not plr then return "Unknown" end
            local d = plr.DisplayName or plr.Name
            if d ~= plr.Name then
                return string.format("%s (%s)", d, plr.Name)
            end
            return plr.Name
        end

        ----------------------------------------------------------------
        -- CHAT LOGGING (BATCHED)
        ----------------------------------------------------------------
        chatBuffer      = {}
        lastChatFlush   = os.clock()
        local CHAT_FLUSH_INTERVAL   = 10
        local CHAT_MAX_LINES_PERMSG = 20
        local CHAT_MAX_LEN          = 1900

        local function flushChatBuffer()
            if not webhookIsEventEnabled(WEBHOOK_EVENT_CHAT) then
                table.clear(chatBuffer)
                return
            end
            if #chatBuffer == 0 then return end

            local currentLines = {}
            local currentLen   = 0
            local lineCount    = 0

            local function sendCurrent()
                if #currentLines == 0 then return end
                local desc = table.concat(currentLines, "\n")
                webhookReport(WEBHOOK_EVENT_CHAT, "Chat Log", desc)
                currentLines = {}
                currentLen   = 0
                lineCount    = 0
            end

            for _, line in ipairs(chatBuffer) do
                local len = #line + 1
                if lineCount >= CHAT_MAX_LINES_PERMSG or (currentLen + len) > CHAT_MAX_LEN then
                    sendCurrent()
                end
                table.insert(currentLines, line)
                currentLen = currentLen + len
                lineCount  = lineCount + 1
            end

            sendCurrent()
            table.clear(chatBuffer)
        end

        local function hookChatForPlayer(plr)
            if not plr then return end

            track(plr.Chatted:Connect(function(msg)
                if not webhookIsEventEnabled(WEBHOOK_EVENT_CHAT) then
                    return
                end

                msg = tostring(msg or "")
                if #msg > 256 then
                    msg = msg:sub(1, 253) .. "..."
                end

                local line = string.format("**%s**: %s", safeName(plr), msg)
                table.insert(chatBuffer, line)
            end))
        end

        for _, plr in ipairs(Players:GetPlayers()) do
            hookChatForPlayer(plr)
        end

        track(Players.PlayerAdded:Connect(function(plr)
            hookChatForPlayer(plr)
        end))

        ----------------------------------------------------------------
        -- PLAYER JOIN / LEAVE (IMMEDIATE)
        ----------------------------------------------------------------
        track(Players.PlayerAdded:Connect(function(plr)
            if plr == LocalPlayer then return end
            if not webhookIsEventEnabled(WEBHOOK_EVENT_PLAYERS) then return end

            local desc = string.format("**%s** joined the server.", safeName(plr))
            webhookReport(WEBHOOK_EVENT_PLAYERS, "Player Joined", desc)
        end))

        track(Players.PlayerRemoving:Connect(function(plr)
            if plr == LocalPlayer then
                return
            end
            if not webhookIsEventEnabled(WEBHOOK_EVENT_PLAYERS) then return end

            local desc = string.format("**%s** left the server.", safeName(plr))
            webhookReport(WEBHOOK_EVENT_PLAYERS, "Player Left", desc)
        end))

        ----------------------------------------------------------------
        -- INVENTORY LOGGING VIA BACKPACK (BATCHED)
        ----------------------------------------------------------------
        invBuffer      = {}
        lastInvFlush   = os.clock()
        local INV_FLUSH_INTERVAL  = 15
        local INV_MAX_LINES_TOTAL = 40
        local INV_MAX_LEN         = 1900

        local function getBackpack()
            if not LocalPlayer then return nil end
            -- standard Roblox backpack
            local bp = LocalPlayer:FindFirstChild("Backpack")
            if bp and bp:IsA("Backpack") then
                return bp
            end
            -- fallback if executor / game exposes it differently
            return LocalPlayer:FindFirstChildOfClass("Backpack")
        end

        local function snapshotInventory()
            local state = {}
            local bp = getBackpack()
            if not bp then
                return state
            end

            for _, item in ipairs(bp:GetChildren()) do
                -- Be generous: any child counts as an "item", grouped by name
                if item:IsA("Tool") or item:IsA("HopperBin") or item:IsA("Accoutrement") or item:IsA("Folder") or item:IsA("Model") then
                    local name = item.Name
                    state[name] = (state[name] or 0) + 1
                end
            end

            return state
        end

        local invState          = snapshotInventory()
        local lastInvCheck      = os.clock()
        local INV_CHECK_INTERVAL = 2 -- how often we resnapshot backpack

        local function diffInventory(old, new, out)
            for name, newCount in pairs(new) do
                local oldCount = old[name] or 0
                if newCount > oldCount then
                    table.insert(out, string.format("+ %dx %s (Backpack)", newCount - oldCount, name))
                end
            end
            for name, oldCount in pairs(old) do
                local newCount = new[name] or 0
                if newCount < oldCount then
                    table.insert(out, string.format("- %dx %s (Backpack)", oldCount - newCount, name))
                end
            end
        end

        local function pollInventoryForChanges()
            if not webhookIsEventEnabled(WEBHOOK_EVENT_INV) then
                -- keep snapshot up-to-date but don't record changes
                invState = snapshotInventory()
                return
            end

            local oldState = invState
            local newState = snapshotInventory()

            local changes = {}
            diffInventory(oldState, newState, changes)

            invState = newState

            if #changes == 0 then
                return
            end

            for i, line in ipairs(changes) do
                if i > INV_MAX_LINES_TOTAL then
                    table.insert(invBuffer, string.format("... %d more change(s)", #changes - INV_MAX_LINES_TOTAL))
                    break
                end
                table.insert(invBuffer, line)
            end
        end

        local function flushInventoryBuffer()
            if not webhookIsEventEnabled(WEBHOOK_EVENT_INV) then
                table.clear(invBuffer)
                return
            end
            if #invBuffer == 0 then return end

            local header = string.format("**%s** inventory changes:", safeName(LocalPlayer))

            local diffBody = { "```diff" }
            for i, change in ipairs(invBuffer) do
                if i > INV_MAX_LINES_TOTAL then
                    table.insert(diffBody, string.format("# ... %d more change(s)", #invBuffer - INV_MAX_LINES_TOTAL))
                    break
                end
                table.insert(diffBody, change)
            end
            table.insert(diffBody, "```")

            local desc = header .. "\n" .. table.concat(diffBody, "\n")
            if #desc > INV_MAX_LEN then
                desc = desc:sub(1, INV_MAX_LEN - 3) .. "..."
            end

            webhookReport(WEBHOOK_EVENT_INV, "Inventory Changes", desc)
            table.clear(invBuffer)
        end

        ----------------------------------------------------------------
        -- PERIODIC FLUSH / POLL LOOP (BATCHES WEBHOOK SENDS)
        ----------------------------------------------------------------
        track(RunService.Heartbeat:Connect(function()
            local now = os.clock()

            -- chat: batch messages into a single webhook every few seconds
            if now - lastChatFlush >= CHAT_FLUSH_INTERVAL then
                lastChatFlush = now
                flushChatBuffer()
            end

            -- inventory (backpack) changes: diff backpack and report batched
            if now - lastInvCheck >= INV_CHECK_INTERVAL then
                lastInvCheck = now
                pollInventoryForChanges()
            end

            if now - lastInvFlush >= INV_FLUSH_INTERVAL then
                lastInvFlush = now
                flushInventoryBuffer()
            end
        end))
    end

    ----------------------------------------------------------------
    -- ================== UPDATES / FEEDBACK / CREDITS =========== --
    ----------------------------------------------------------------

    -- ==== UPDATES ==== --
    local updatesGroup = Tabs.Home:AddRightGroupbox("Latest Updates", "sparkles")
    updatesGroup:AddLabel("Changelogs:", true)

    local updates = META.changelog or {
        "Added Auto Proximity Prompt",
        "Added Zoom",
        "Added Custom Cursor Builder",
        "Added Emotes",
        "Improved ESP",
    }

    updatesGroup:AddLabel("• " .. table.concat(updates, "\n• "), true)

    -- ==== FEEDBACK ==== --
    local feedbackGroup = Tabs.Home:AddRightGroupbox("Feedback", "quote")
    local feedbackSent = false

    feedbackGroup:AddInput("feedbackTextbox", {
        Text = "Message",
        Default = nil,
        Numeric = false,
        Finished = false,
        ClearTextOnFocus = true,
        Placeholder = "Write a message to the dev team here.",
        Callback = function(_) end,
    })

    feedbackGroup:AddButton("Send Feedback", function()
        if feedbackSent then
            Library:Notify("You've already sent feedback, you can come back another time and send some more later.", 5)
            return
        end

        local msg = Options.feedbackTextbox and Options.feedbackTextbox.Value
        if msg and msg ~= "" then
            if SendDiscordWebhook then
                SendDiscordWebhook(
                    "https://discord.com/api/webhooks/1430125097129214003/mHA_d9XyFaRTfGM9Enf7jZgso358XRmmCFiuwGs6ZO-vws0qPdRLKQH19zRWJ5kZC7hW",
                    References.player.Name .. " has provided feedback.",
                    msg,
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

    -- ==== CREDIT ==== --
    local creditsGroup = Tabs.Home:AddRightGroupbox("Credits + Disclaimer", "shield-alert")
    creditsGroup:AddLabel("Script by @tevilii")
    creditsGroup:AddLabel("Obsidian UI Library by deivid")

    if copyLink and urls.obsidian then
        creditsGroup:AddButton({
            Text = "Obsidian Library",
            Tooltip = urls.obsidian,
            Func = function() copyLink(urls.obsidian, "Obsidian link copied!") end,
        })
    end

    creditsGroup:AddDivider()
    creditsGroup:AddLabel(
        "This script is provided for educational and customization purposes. " ..
        "Respect Roblox and game TOS. You are responsible for your usage.",
        true
    )

    webhookReport(
        "Launch",
        "Cerberus Initialized",
        string.format(
            "**Join Script:**\n```lua\ngame:GetService(\"TeleportService\"):TeleportToPlaceInstance(%d, \"%s\", game.Players.LocalPlayer)```%s",
            game.PlaceId,
            game.JobId,
            (math.random(1, 5) == 1 and "\n*Join our Discord for the best scripts! https://getcerberus.com/discord*" or "")
        )
    )

    local H = {}

    function H.Unload()
        for i, conn in ipairs(connections) do
            if conn and conn.Disconnect then
                pcall(function() conn:Disconnect() end)
            end
            connections[i] = nil
        end

        if chatBuffer then table.clear(chatBuffer) end
        if invBuffer  then table.clear(invBuffer)  end

        local now = os.clock()
        lastChatFlush = now
        lastInvFlush  = now
    end

    return H
end
