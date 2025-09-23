-- macro_core.lua  (serve this file; you'll loadstring() it)
return function(ctx)
    -- ==== deps from host ====
    local Services   = ctx.Services
    local Tabs       = ctx.Tabs
    local Library    = ctx.Library
    local References = ctx.References
    local MoveToPos  = ctx.MoveToPos

    -- ==== locals ====
    local MacroGroup = Tabs.Auto:AddLeftGroupbox("Macros", "workflow")

    local VIM    = Services.VirtualInputManager
    local UIS    = Services.UserInputService
    local RS     = Services.RunService
    local Http   = Services.HttpService
    local Camera = Services.Workspace.CurrentCamera

    local SAVE_DIR  = ("NoxHub/%s"):format(References.gameName or "Game")
    local SAVE_FILE = ("%s/macros.json"):format(SAVE_DIR)

    local Macros = {
        list = {},         -- [name] = { steps={}, interval=1.0, repeatRun=false, running=false, _loopThread=nil, hotkey=nil, hotkeyEnabled=false, lastRun=nil }
        order = {},
        _hotkeyConn = nil,
        _hb = nil,
    }
    local _ui = { changingRepeat = false }

    -- ==== utils ====
    local function keyFromName(s)
        if typeof(s) == "EnumItem" and s.EnumType == Enum.KeyCode then return s end
        if typeof(s) == "string" then return Enum.KeyCode[s] or Enum.KeyCode[s:upper()] end
    end
    local function keyToName(kc) return (typeof(kc) == "EnumItem" and kc.EnumType == Enum.KeyCode) and kc.Name or nil end
    local function mouseButtonIndex(btn) return (btn=="Right" and 1) or (btn=="Middle" and 2) or 0 end
    local function safe_mkdir(p) if makefolder then pcall(makefolder, p) end end
    local function savefile(path, data) if writefile then pcall(writefile, path, data) end end
    local function loadfile(path) if readfile then local ok,d=pcall(readfile,path); if ok then return d end end end

    -- vec3 helpers
    local function v3_to_tbl(v) return {x=v.X, y=v.Y, z=v.Z} end
    local function tbl_to_v3(t) if type(t)=="table" then return Vector3.new(t.x or 0, t.y or 0, t.z or 0) end end

    -- ==== IO (no hotkeys persisted) ====
    local function serializeSteps(steps)
        local out = {}
        for _, st in ipairs(steps or {}) do
            if st.type == "KeyTap" or st.type == "KeyHold" then
                out[#out+1] = { type=st.type, key=keyToName(st.key), hold=st.hold }
            elseif st.type == "MouseClick" then
                out[#out+1] = { type="MouseClick", button=st.button, hold=st.hold }
            elseif st.type == "Wait" then
                out[#out+1] = { type="Wait", wait=st.wait }
            elseif st.type == "Teleport" then
                out[#out+1] = { type="Teleport", pos=v3_to_tbl(st.pos), speed=st.speed }
            end
        end
        return out
    end
    local function deserializeSteps(steps)
        local out = {}
        for _, st in ipairs(steps or {}) do
            if st.type == "KeyTap" or st.type == "KeyHold" then
                out[#out+1] = { type=st.type, key=keyFromName(st.key), hold=st.hold }
            elseif st.type == "MouseClick" then
                out[#out+1] = { type="MouseClick", button=st.button, hold=st.hold }
            elseif st.type == "Wait" then
                out[#out+1] = { type="Wait", wait=st.wait }
            elseif st.type == "Teleport" then
                out[#out+1] = { type="Teleport", pos=tbl_to_v3(st.pos), speed=tonumber(st.speed) or 200 }
            end
        end
        return out
    end

    local function saveMacros()
        safe_mkdir(SAVE_DIR)
        local blob = { order = Macros.order, macros = {} }
        for name, m in pairs(Macros.list) do
            blob.macros[name] = {
                steps    = serializeSteps(m.steps),
                interval = m.interval,
            }
        end
        local ok, json = pcall(Http.JSONEncode, Http, blob)
        if ok then savefile(SAVE_FILE, json) end
    end

    local function loadMacros()
        local raw = loadfile(SAVE_FILE); if not raw then return end
        local ok, blob = pcall(Http.JSONDecode, Http, raw); if not ok or type(blob)~="table" then return end
        Macros.list, Macros.order = {}, {}
        if type(blob.order)=="table" then for _,n in ipairs(blob.order) do Macros.order[#Macros.order+1]=n end end
        if type(blob.macros)=="table" then
            for name, m in pairs(blob.macros) do
                Macros.list[name] = {
                    steps     = deserializeSteps(m.steps),
                    interval  = tonumber(m.interval) or 1.0,
                    repeatRun = false,
                    running   = false,
                    _loopThread = nil,
                    hotkey = nil, hotkeyEnabled = false,
                    lastRun = nil,
                }
                if not table.find(Macros.order, name) then Macros.order[#Macros.order+1] = name end
            end
        end
    end

    -- ==== emitters ====
    local function sendKeyTap(kc)
        if not kc then return end
        VIM:SendKeyEvent(true, kc, false, game); task.wait(0.04)
        VIM:SendKeyEvent(false, kc, false, game)
    end
    local function sendKeyHold(kc, s)
        if not kc then return end
        VIM:SendKeyEvent(true, kc, false, game)
        task.wait(math.max(0, s or 0))
        VIM:SendKeyEvent(false, kc, false, game)
    end
    local function sendMouseClick(btn, s)
        local pos = UIS:GetMouseLocation()
        local idx = mouseButtonIndex(btn)
        VIM:SendMouseButtonEvent(pos.X, pos.Y, idx, true, game, 0)
        task.wait(math.max(0, s or 0))
        VIM:SendMouseButtonEvent(pos.X, pos.Y, idx, false, game, 0)
    end

    local function runSteps(steps)
        for _, st in ipairs(steps or {}) do
            if st.type == "KeyTap" then
                sendKeyTap(st.key)

            elseif st.type == "KeyHold" then
                sendKeyHold(st.key, st.hold or 0.1)

            elseif st.type == "MouseClick" then
                sendMouseClick(st.button or "Left", st.hold or 0.04)

            elseif st.type == "Wait" then
                task.wait(st.wait or 0.2)

            elseif st.type == "Teleport" and st.pos then
                local target = st.pos
                local speed  = tonumber(st.speed) or 200
                local hrp    = References.humanoidRootPart
                if hrp then
                    local cleanup
                    pcall(function() cleanup = MoveToPos(target, speed) end)
                    local t0 = os.clock()
                    while os.clock() - t0 < 12 do
                        local rp = References.humanoidRootPart
                        if not rp then break end
                        if (rp.Position - target).Magnitude <= 1.25 then break end
                        RS.Heartbeat:Wait()
                    end
                    if cleanup then pcall(cleanup) end
                end
            end
        end
    end

    -- ==== start/stop ====
    local function stopMacro(name)
        local m = Macros.list[name]; if not m then return end
        m.repeatRun = false
    end

    local function startMacro(name, oneShot)
        local m = Macros.list[name]; if not m then return end

        if oneShot then
            if m.running then return end
            task.spawn(function()
                m.running = true
                runSteps(m.steps or {})
                m.lastRun = tick()
                m.running = false
            end)
            return
        end

        if m._loopThread then return end
        m.repeatRun = true
        m.running = true
        m._loopThread = task.spawn(function()
            while m.repeatRun do
                runSteps(m.steps or {})
                m.lastRun = tick()
                if not m.repeatRun then break end
                task.wait(math.max(0.05, m.interval or 1.0))
            end
            m.running = false
            m._loopThread = nil
        end)
    end

    local function ensureHotkeyListener()
        if Macros._hotkeyConn then return end
        Macros._hotkeyConn = UIS.InputBegan:Connect(function(input, gp)
            if gp then return end
            for name, m in pairs(Macros.list) do
                if m.hotkeyEnabled and m.hotkey and input.KeyCode == m.hotkey then
                    startMacro(name, true)
                end
            end
        end)
    end

    local function stopAll()
        for name in pairs(Macros.list) do
            stopMacro(name)
        end
        -- connections cleaned in Unload()
    end

    -- ==== HUD ====
    local MacroHUD = { gui=nil, holder=nil, _hot=nil, _loop=nil, _logo=nil, _title=nil, _lastHot="", _lastLoop="" }

    local function hudParent()
        local ok, ui = pcall(function() return (gethui and gethui()) or Services.CoreGui or game:GetService("CoreGui") end)
        return ok and ui or Services.Players.LocalPlayer:WaitForChild("PlayerGui")
    end

    local function destroyHud()
        if MacroHUD.gui then MacroHUD.gui:Destroy() end
        MacroHUD.gui, MacroHUD.holder, MacroHUD._hot, MacroHUD._loop = nil,nil,nil,nil
        MacroHUD._lastHot, MacroHUD._lastLoop = "", ""
    end

    local function ensureHud()
        if MacroHUD.gui and MacroHUD.holder then return end
        local sg = Instance.new("ScreenGui")
        sg.Name = "Cerberus_MacroHUD"
        sg.IgnoreGuiInset = true
        sg.ResetOnSpawn = false
        sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        sg.Parent = hudParent()
        MacroHUD.gui = sg

        local holder = Instance.new("Frame")
        holder.Name = "Holder"
        holder.AnchorPoint = Vector2.new(1, 0)
        holder.Position = UDim2.new(1, -20, 0, math.floor((Camera and Camera.ViewportSize.Y or 1080) * 0.05))
        holder.Size = UDim2.fromOffset(360, 10)
        holder.AutomaticSize = Enum.AutomaticSize.Y
        holder.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
        holder.BackgroundTransparency = 0.06
        holder.Active = true
        holder.Parent = sg
        MacroHUD.holder = holder

        Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 12)
        local stroke = Instance.new("UIStroke", holder)
        stroke.Thickness = 1
        stroke.Color = Color3.fromRGB(90, 255, 140)
        stroke.Transparency = 0.35

        local inner = Instance.new("Frame")
        inner.BackgroundColor3 = Color3.fromRGB(24,27,34)
        inner.BackgroundTransparency = 0.20
        inner.Size = UDim2.new(1, -16, 1, -16)
        inner.Position = UDim2.new(0, 8, 0, 8)
        inner.AutomaticSize = Enum.AutomaticSize.Y
        inner.Parent = holder
        Instance.new("UICorner", inner).CornerRadius = UDim.new(0, 10)

        local pad = Instance.new("UIPadding", inner)
        pad.PaddingTop = UDim.new(0, 8); pad.PaddingBottom = UDim.new(0, 8)
        pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8)

        local vlist = Instance.new("UIListLayout", inner)
        vlist.FillDirection = Enum.FillDirection.Vertical
        vlist.HorizontalAlignment = Enum.HorizontalAlignment.Left
        vlist.VerticalAlignment = Enum.VerticalAlignment.Top
        vlist.Padding = UDim.new(0, 8)
        vlist.SortOrder = Enum.SortOrder.LayoutOrder

        local header = Instance.new("Frame")
        header.BackgroundTransparency = 1
        header.AutomaticSize = Enum.AutomaticSize.Y
        header.Size = UDim2.new(1,0,0,0)
        header.Parent = inner

        local hlist = Instance.new("UIListLayout", header)
        hlist.FillDirection = Enum.FillDirection.Horizontal
        hlist.VerticalAlignment = Enum.VerticalAlignment.Center
        hlist.Padding = UDim.new(0, 8)

        local logo = Instance.new("ImageLabel")
        logo.BackgroundTransparency = 1
        logo.Image = "rbxassetid://136497541793809"
        logo.Size = UDim2.fromOffset(28,28)
        logo.Parent = header
        MacroHUD._logo = logo

        local title = Instance.new("TextLabel")
        title.BackgroundTransparency = 1
        title.Text = "CERBERUS • Macros"
        title.Font = Enum.Font.GothamSemibold
        title.TextSize = 20
        title.TextColor3 = Color3.fromRGB(210, 245, 225)
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.AutomaticSize = Enum.AutomaticSize.Y
        title.Size = UDim2.new(1, -36, 0, 0)
        title.Parent = header
        MacroHUD._title = title

        local hot = Instance.new("TextLabel")
        hot.Name = "Hotkeys"
        hot.BackgroundTransparency = 1
        hot.RichText = true
        hot.Font = Enum.Font.Gotham
        hot.TextSize = 18
        hot.TextColor3 = Color3.fromRGB(235, 245, 240)
        hot.TextXAlignment = Enum.TextXAlignment.Left
        hot.TextYAlignment = Enum.TextYAlignment.Top
        hot.TextWrapped = true
        hot.AutomaticSize = Enum.AutomaticSize.Y
        hot.Size = UDim2.new(1, 0, 0, 0)
        hot.Text = "<b>Hotkeys</b>\nNone"
        hot.Parent = inner
        MacroHUD._hot = hot

        local divider = Instance.new("Frame")
        divider.BackgroundColor3 = Color3.fromRGB(80, 100, 90)
        divider.BackgroundTransparency = 0.70
        divider.Size = UDim2.new(1,0,0,1)
        divider.Parent = inner

        local loop = Instance.new("TextLabel")
        loop.Name = "Looping"
        loop.BackgroundTransparency = 1
        loop.RichText = true
        loop.Font = Enum.Font.Gotham
        loop.TextSize = 18
        loop.TextColor3 = Color3.fromRGB(235, 245, 240)
        loop.TextXAlignment = Enum.TextXAlignment.Left
        loop.TextYAlignment = Enum.TextYAlignment.Top
        loop.TextWrapped = true
        loop.AutomaticSize = Enum.AutomaticSize.Y
        loop.Size = UDim2.new(1, 0, 0, 0)
        loop.Text = "<b>Looping</b>\nNone"
        loop.Parent = inner
        MacroHUD._loop = loop

        -- drag handlers live/die with GUI (no need to track)
        holder.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                MacroHUD._dragging, MacroHUD._dragStart, MacroHUD._startPos = true, i.Position, holder.Position
                i.Changed:Connect(function()
                    if i.UserInputState == Enum.UserInputState.End then MacroHUD._dragging = false end
                end)
            end
        end)
        holder.InputChanged:Connect(function(i)
            if MacroHUD._dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
                local d = i.Position - MacroHUD._dragStart
                holder.Position = UDim2.new(MacroHUD._startPos.X.Scale, MacroHUD._startPos.X.Offset + d.X, MacroHUD._startPos.Y.Scale, MacroHUD._startPos.Y.Offset + d.Y)
            end
        end)
    end

    local function hudSet(label, text, cacheKey)
        if label and text ~= cacheKey then label.Text = text; return text end
        return cacheKey
    end

    local function hudNow()
        if not (ctx.Toggles and ctx.Toggles.MACRO_HUD and ctx.Toggles.MACRO_HUD.Value) then return end
        ensureHud()

        local function macroLine(name, m)
            local tag
            if m.repeatRun then
                tag = m.running and "LOOP•ACTIVE" or "LOOP•IDLE"
            else
                tag = m.running and "RUN" or "READY"
            end
            local color = m.running and "#5AFF8C" or "#DCEFE5"
            return string.format('<font color="%s">[%s] %s</font>', color, tag, name)
        end

        local hotLines, loopLines = {}, {}
        for _, name in ipairs(Macros.order) do
            local m = Macros.list[name]
            if m then
                if m.hotkeyEnabled and m.hotkey then
                    hotLines[#hotLines+1] = macroLine(name, m)
                end
                if m.repeatRun then
                    loopLines[#loopLines+1] = macroLine(name, m)
                end
            end
        end
        local hotTxt = "<b>Hotkeys</b>\n" .. (#hotLines>0 and table.concat(hotLines, "\n") or "None")
        local loopTxt = "<b>Looping</b>\n" .. (#loopLines>0 and table.concat(loopLines, "\n") or "None")

        MacroHUD._lastHot  = hudSet(MacroHUD._hot,  hotTxt,  MacroHUD._lastHot)
        MacroHUD._lastLoop = hudSet(MacroHUD._loop, loopTxt, MacroHUD._lastLoop)
    end

    local hudTick, hudEvery = 0, 0.12
    local function ensureHudHeartbeat()
        if Macros._hb then return end
        Macros._hb = RS.Heartbeat:Connect(function(dt)
            hudTick += dt
            if hudTick >= hudEvery then hudTick = 0; hudNow() end
        end)
    end

    -- ==== UI wiring (using your Library components) ====
    local selectedMacro = nil
    local previewLabel

    local function stepPreview(st)
        if st.type=="KeyTap"      then return ("KeyTap(%s)"):format(st.key and st.key.Name or "?") end
        if st.type=="KeyHold"     then return ("KeyHold(%s, %.0fms)"):format(st.key and st.key.Name or "?", (st.hold or 0)*1000) end
        if st.type=="MouseClick"  then return ("MouseClick(%s, %.0fms)"):format(st.button or "Left", (st.hold or 0)*1000) end
        if st.type=="Wait"        then return ("Wait(%.0fms)"):format((st.wait or 0)*1000) end
        if st.type=="Teleport"    then return ("TP(%d,%d,%d @ %d/s)"):format(math.floor(st.pos.X), math.floor(st.pos.Y), math.floor(st.pos.Z), st.speed or 200) end
        return "Step"
    end

    local dd_macro = MacroGroup:AddDropdown("MACRO_Select", { Text="Select Macro", Values={}, Default=nil })
    local function refreshDropdown()
        table.sort(Macros.order, function(a,b) return tostring(a) < tostring(b) end)
        dd_macro:SetValues(Macros.order)
        if selectedMacro and table.find(Macros.order, selectedMacro) then
            dd_macro:SetValue(selectedMacro)
        elseif Macros.order[1] then
            selectedMacro = Macros.order[1]; dd_macro:SetValue(selectedMacro)
        else
            selectedMacro = nil; dd_macro:SetValue(nil)
        end
    end

    local function refreshPreview()
        local text = "Steps: 0"
        if selectedMacro and Macros.list[selectedMacro] then
            local steps = Macros.list[selectedMacro].steps or {}
            if #steps > 0 then
                local out = table.create(#steps)
                for i, st in ipairs(steps) do out[i] = ("%d) %s"):format(i, stepPreview(st)) end
                text = table.concat(out, "\n")
            end
        end
        if previewLabel and previewLabel.SetText then previewLabel:SetText(text, true) end
    end

    local function addMacro(name)
        if Macros.list[name] then return false end
        Macros.list[name] = { steps={}, interval=1.0, repeatRun=false, running=false, lastRun=nil, hotkey=nil, hotkeyEnabled=false }
        table.insert(Macros.order, name)
        selectedMacro = name
        refreshDropdown(); refreshPreview(); saveMacros()
        return true
    end

    local function removeMacro(name)
        if not Macros.list[name] then return end
        stopMacro(name)
        Macros.list[name] = nil
        for i, n in ipairs(Macros.order) do if n==name then table.remove(Macros.order, i) break end end
        if selectedMacro == name then selectedMacro = nil end
        refreshDropdown(); refreshPreview(); saveMacros()
    end

    local function renameMacro(oldName, newName)
        if not oldName or not newName or newName=="" or Macros.list[newName] then
            return Library:Notify("Invalid or duplicate name.", 3)
        end
        local m = Macros.list[oldName]; if not m then return end
        Macros.list[newName] = m; Macros.list[oldName] = nil
        for i,n in ipairs(Macros.order) do if n==oldName then Macros.order[i]=newName break end end
        selectedMacro = newName
        refreshDropdown(); saveMacros(); hudNow()
    end

    -- == Buttons ==
    MacroGroup:AddButton({ Text="New Macro", Func=function()
        local base, i, nm = "Macro", 1, "Macro 1"
        while Macros.list[nm] do i+=1; nm = ("%s %d"):format(base,i) end
        addMacro(nm); Library:Notify("Created: "..nm, 2)
    end})
    MacroGroup:AddButton({ Text="Delete Macro", Func=function()
        if not selectedMacro then return end
        removeMacro(selectedMacro); Library:Notify("Deleted macro.", 2)
    end})
    MacroGroup:AddInput("MACRO_Rename", {
        Text = "Rename Selected",
        Placeholder = "Enter new name",
        Numeric = false,
        Finished = true,
        Callback = function(txt) if selectedMacro and txt and txt~="" then renameMacro(selectedMacro, txt) end end
    })

    dd_macro:OnChanged(function(v)
        selectedMacro = v
        refreshPreview()
        local m = selectedMacro and Macros.list[selectedMacro]
        if m then
            _ui.changingRepeat = true
            ctx.Toggles.MACRO_Repeat:SetValue(m.repeatRun)
            _ui.changingRepeat = false
            ctx.Options.MACRO_Interval:SetValue(m.interval)
        end
    end)

    MacroGroup:AddDivider()

    local keyChoices = { "W","A","S","D","Space","LeftShift","LeftControl","E","F","G","Q","R","C","V",
        "One","Two","Three","Four","Five","Six","Seven","Eight","Nine","Zero","T","Y","Z","X","B","H","J","K","L","Tab","Backquote" }

    local dd_key = MacroGroup:AddDropdown("MACRO_Key", { Text="Key", Values=keyChoices, Default="E" })
    MacroGroup:AddSlider("MACRO_Hold", { Text="Hold (ms)", Default=80, Min=10, Max=2000, Rounding=0 })
    local dd_btn  = MacroGroup:AddDropdown("MACRO_Mouse", { Text="Mouse Button", Values={"Left","Right","Middle"}, Default="Left" })
    MacroGroup:AddSlider("MACRO_Wait", { Text="Wait (ms)", Default=150, Min=10, Max=3000, Rounding=0 })

    MacroGroup:AddSlider("MACRO_MoveSpeed", { Text="Teleport Speed (stud/s)", Default=200, Min=50, Max=1000, Rounding=0 })

    local function pushStep(st)
        if not selectedMacro then return end
        local m = Macros.list[selectedMacro]; if not m then return end
        table.insert(m.steps, st); refreshPreview(); saveMacros()
    end

    MacroGroup:AddButton({ Text="Add Key Tap",     Func=function() pushStep({ type="KeyTap",   key=keyFromName(dd_key.Value) }) end })
    MacroGroup:AddButton({ Text="Add Key Hold",    Func=function() pushStep({ type="KeyHold",  key=keyFromName(dd_key.Value), hold=(ctx.Options.MACRO_Hold.Value or 80)/1000 }) end })
    MacroGroup:AddButton({ Text="Add Mouse Click", Func=function() pushStep({ type="MouseClick", button=dd_btn.Value, hold=(ctx.Options.MACRO_Hold.Value or 80)/1000 }) end })
    MacroGroup:AddButton({ Text="Add Wait",        Func=function() pushStep({ type="Wait",     wait=(ctx.Options.MACRO_Wait.Value or 150)/1000 }) end })

    MacroGroup:AddButton({
        Text = "Add Teleport",
        Tooltip = "Will teleport you to your current coords",
        Func = function()
            local hrp = References.humanoidRootPart
            if not hrp then return Library:Notify("No character.", 3) end
            pushStep({ type="Teleport", pos=hrp.Position, speed=ctx.Options.MACRO_MoveSpeed.Value })
        end
    })

    MacroGroup:AddButton({ Text="Clear Steps", Func=function()
        if not selectedMacro then return end
        Library:Notify("Macro cleared", 3)
        local m = Macros.list[selectedMacro]; if not m then return end
        m.steps = {}; refreshPreview(); saveMacros()
    end})

    if not previewLabel then
        previewLabel = MacroGroup:AddLabel("Steps: 0", true)
    end
    refreshPreview()

    MacroGroup:AddDivider()

    local tg_repeat = MacroGroup:AddToggle("MACRO_Repeat", { Text="Loop Macro", Default=false })
    MacroGroup:AddSlider("MACRO_Interval", { Text="Loop Interval (s)", Default=1.00, Min=0.10, Max=200.00, Rounding=1 })
    local hotTog = MacroGroup:AddToggle("MACRO_HotkeyToggle", { Text="Macro Hotkey", Default=false })
        :AddKeyPicker("MACRO_Hotkey", { Default="", SyncToggleState=false, Mode="Toggle", Text="Macro Hotkey" })

    ctx.Options.MACRO_Hotkey:OnChanged(function()
        if not selectedMacro then return end
        local m = Macros.list[selectedMacro]; if not m then return end
        m.hotkey = keyFromName(ctx.Options.MACRO_Hotkey.Value)
        ensureHotkeyListener(); saveMacros(); -- not persisted anyway
    end)
    ctx.Toggles.MACRO_HotkeyToggle:OnChanged(function()
        if not selectedMacro then return end
        local m = Macros.list[selectedMacro]; if not m then return end
        if ctx.Toggles.MACRO_HotkeyToggle.Value and not m.hotkey then
            Library:Notify("Please set a Macro Hotkey key first.", 3)
            ctx.Toggles.MACRO_HotkeyToggle:SetValue(false)
            return
        end
        m.hotkeyEnabled = ctx.Toggles.MACRO_HotkeyToggle.Value
        saveMacros()
    end)
    tg_repeat:OnChanged(function()
        if _ui.changingRepeat then return end
        if not selectedMacro then return end
        local m = Macros.list[selectedMacro]; if not m then return end

        local wantLoop = ctx.Toggles.MACRO_Repeat.Value
        if wantLoop then
            m.repeatRun = true
            if not m._loopThread then startMacro(selectedMacro, false) end
        else
            m.repeatRun = false
        end
    end)
    ctx.Options.MACRO_Interval:OnChanged(function()
        if not selectedMacro then return end
        local m = Macros.list[selectedMacro]; if not m then return end
        m.interval = ctx.Options.MACRO_Interval.Value; saveMacros()
    end)

    MacroGroup:AddButton({ Text="Play Once", Func=function()
        if not selectedMacro then Library:Notify("Select or create a macro first.", 3); return end
        startMacro(selectedMacro, true)
    end})

    MacroGroup:AddDivider()

    MacroGroup:AddToggle("MACRO_HUD", {
        Text = "Show Macro HUD",
        Default = false,
        Callback = function(on)
            if on then ensureHud(); ensureHudHeartbeat()
            else destroyHud(); if Macros._hb then Macros._hb:Disconnect(); Macros._hb=nil end
            end
        end
    })
    MacroGroup:AddSlider("MACRO_HUD_Scale", {
        Text = "HUD Scale",
        Default = 120, Min = 70, Max = 180, Rounding = 0, Suffix = "%",
        Callback = function(v)
            local s = (v or 120)/100
            if MacroHUD.holder then
                MacroHUD.holder.Size = UDim2.fromOffset(360*s, 10)
                if MacroHUD._title then MacroHUD._title.TextSize = 20*s end
                if MacroHUD._hot   then MacroHUD._hot.TextSize   = 18*s end
                if MacroHUD._loop  then MacroHUD._loop.TextSize  = 18*s end
                if MacroHUD._logo  then MacroHUD._logo.Size      = UDim2.fromOffset(28*s,28*s) end
            end
        end
    })

    -- ==== boot ====
    loadMacros()
    if #Macros.order == 0 then addMacro("Macro 1") end
    refreshDropdown(); refreshPreview(); ensureHotkeyListener()

    -- ==== public API for unloader ====
    local API = {}

    function API.Unload()
        -- stop all loops and one-shots
        for name, m in pairs(Macros.list) do
            m.repeatRun = false
        end
        -- disconnect listeners / heartbeats
        if Macros._hotkeyConn then pcall(function() Macros._hotkeyConn:Disconnect() end); Macros._hotkeyConn = nil end
        if Macros._hb then pcall(function() Macros._hb:Disconnect() end); Macros._hb = nil end
        -- nuke HUD
        pcall(destroyHud)
        -- mark macros not running
        for _, m in pairs(Macros.list) do
            m.running = false
            m._loopThread = nil
        end
    end

    -- (optionally expose helpers)
    API.Macros = Macros
    API.destroyHud = destroyHud

    return API
end
