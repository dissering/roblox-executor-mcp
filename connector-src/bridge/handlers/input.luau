return function(context, Bridge)
local VirtualInputManager = context.VirtualInputManager

    Bridge:BindToType("type-text-box", function(data)
        local path = data.path
        local text = data.string or data.text
        local enter = data.enter
        local useKeyPress = data.useKeyPress

        local textBox
        if typeof(path) == "string" then
            textBox = loadstring("return " .. path)()
        else
            textBox = path
        end
        
        assert(typeof(textBox) == "Instance", "Path did not resolve to a valid Instance.")
        assert(textBox:IsA("TextBox"), "Resolved Instance is not a TextBox.")

        textBox:CaptureFocus()
        task.wait(0.05)
        
        if useKeyPress then
            assert(VirtualInputManager or type(keypress) == "function", "This executor cannot simulate text input; use useKeyPress=false to set Text directly.")
            local success = pcall(function()
                for i = 1, #text do
                    VirtualInputManager:SendTextInput(text:sub(i, i), nil, game)
                    task.wait(0.01)
                end
            end)
            
            if not success and type(keypress) == "function" then
                for i = 1, #text do
                    local char = text:sub(i, i):upper()
                    local byte = char:byte()
                    if byte then
                        keypress(byte)
                        task.wait(0.01)
                        if type(keyrelease) == "function" then
                            keyrelease(byte)
                        end
                    end
                end
            end
        else
            textBox.Text = text
        end

        if enter then
            if useKeyPress then
                if type(keypress) == "function" then
                    keypress(0x0D)
                    task.wait(0.01)
                    if type(keyrelease) == "function" then
                        keyrelease(0x0D)
                    end
                else
                    pcall(function()
                        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
                        task.wait(0.01)
                        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
                    end)
                end
            end
            textBox:ReleaseFocus(true)
        else
            textBox:ReleaseFocus(false)
        end

        return {
            status = "success",
            message = "Successfully typed into TextBox."
        }
    end)

    Bridge:BindToType("click-button", function(data)
        local path = data.path
        local action = data.Action or data.action

        local button
        if typeof(path) == "string" then
            button = loadstring("return " .. path)()
        else
            button = path
        end

        assert(typeof(button) == "Instance", "Path did not resolve to a valid Instance.")
        assert(button:IsA("GuiButton"), "Resolved Instance is not a GuiButton (e.g., TextButton or ImageButton).")

        local Signals = {"Activated", "MouseButton1Down", "MouseButton2Down", "MouseButton1Click", "MouseButton2Click"}
        
        if action then assert(table.find(Signals, action), "Invalid action provided. Valid actions are: " .. table.concat(Signals, ", ")) end
        if typeof(firesignal) ~= "function" then
            assert(VirtualInputManager, "This executor supports neither firesignal nor VirtualInputManager; button clicking is unavailable.")
            assert(action == nil or action == "Activated" or action == "MouseButton1Click" or action == "MouseButton2Click", "Exact down-only signals require firesignal; select a click action for virtual mouse input.")
            assert(button.Visible and button.AbsoluteSize.X > 0 and button.AbsoluteSize.Y > 0, "Virtual mouse clicking needs a visible button with a nonzero size.")
            local center = button.AbsolutePosition + button.AbsoluteSize / 2
            -- AbsolutePosition uses CoreUISafeInsets coordinates; virtual mouse input uses screen coordinates.
            local guiService = context.GuiService or game:GetService("GuiService")
            local inset = guiService:GetGuiInset()
            local x, y = center.X + inset.X, center.Y + inset.Y
            local mouseButton = action == "MouseButton2Click" and 1 or 0
            VirtualInputManager:SendMouseMoveEvent(x, y, game)
            task.wait()
            VirtualInputManager:SendMouseButtonEvent(x, y, mouseButton, true, game, 0)
            task.wait(0.05)
            local released, releaseError = pcall(function()
                VirtualInputManager:SendMouseButtonEvent(x, y, mouseButton, false, game, 0)
            end)
            assert(released, "Virtual mouse release failed: " .. tostring(releaseError))
            return { status = "success", method = "virtual-input", message = "Sent a mouse click; the button must be unobstructed and on screen." }
        end

        if action then
            firesignal(button[action])
        else
            local fired = 0
            for _, signalName in pairs(Signals) do
                local ok = pcall(function() firesignal(button[signalName]) end)
                if ok then fired += 1 end
            end
            assert(fired > 0, "The executor's firesignal function failed for every button signal.")
        end

        return {
            status = "success",
            message = "Successfully fired click signals on Button."
        }
    end)
end
