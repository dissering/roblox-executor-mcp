-- Temporary self-owned GUI only; no game buttons, remotes, or keyboard input are used.
local RegisterInput = require("../connector-src/bridge/handlers/input")
local screen = Instance.new("ScreenGui")
local result
local ok, failure = pcall(function()
    assert(type(firesignal) ~= "function", "This probe expects the missing-firesignal fallback.")
    screen.Name = "MCPCompatibilityProbe"
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 100000
    screen.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    local button = Instance.new("TextButton")
    button.Text = "MCP test"
    button.Position = UDim2.fromOffset(500, 500)
    button.Size = UDim2.fromOffset(120, 45)
    button.Parent = screen
    local clicks = 0
    local inputEvents = 0
    button.MouseButton1Click:Connect(function() clicks += 1 end)
    button.InputBegan:Connect(function() inputEvents += 1 end)
    local callbacks = {}
    RegisterInput({ VirtualInputManager = Instance.new("VirtualInputManager") }, {
        BindToType = function(_, name, callback) callbacks[name] = callback end,
    })
    task.wait(0.2)
    local sent = callbacks["click-button"]({ path = button })
    task.wait(0.2)
    local center = button.AbsolutePosition + button.AbsoluteSize / 2
    local inset = game:GetService("GuiService"):GetGuiInset()
    local hits = screen.Parent:GetGuiObjectsAtPosition(center.X, center.Y + inset.Y)
    result = { method = sent.method, observedClicks = clicks, inputEvents = inputEvents,
        topHit = hits[1] and hits[1].Name, position = tostring(button.AbsolutePosition),
        mousePosition = tostring(game:GetService("UserInputService"):GetMouseLocation()), inset = tostring(inset) }
end)
screen:Destroy()
assert(ok, failure)
return result
