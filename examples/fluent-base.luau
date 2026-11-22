--[[
	Fluent GUI base for chat-driven Roblox scripting.

	Layered on top of:
	  * Fluent (https://github.com/dawid-scripts/Fluent) - the interface.
	  * A feature registry with enable/disable lifecycles, so a feature can be
	    started and stopped from a toggle, a keybind, or the MCP chat.
	  * Optional bridge (re)connect back to the Roblox Executor MCP server.

	Run from the MCP chat:  execute-file examples/fluent-base.luau
	Run in the executor:    loadstring(game:HttpGet("<raw-url>"))()

	The base is published as getgenv().CopilotBase, so a chat-driven script can
	reach it later without re-creating the window:

		local Base = getgenv().CopilotBase
		local feature = Base:CreateFeature("mine", {
			OnEnable = function(self)
				while self:Sleep(1) do print("tick") end
			end,
		})
		feature:Enable()
]]

local CONFIG = {
	FluentURL = "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua",
	SaveManagerURL = "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua",
	InterfaceManagerURL = "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua",

	Title = "Copilot Base",
	SubTitle = "Fluent GUI base",
	TabWidth = 160,
	Size = UDim2.fromOffset(580, 460),
	Acrylic = true,
	Theme = "Dark",
	MinimizeKey = Enum.KeyCode.RightControl,

	BridgeURL = "localhost:16384",
	ConnectOnLoad = false,

	-- Where the "Reload interface" button re-downloads this file from.
	SourceURL = "https://raw.githubusercontent.com/dissering/roblox-executor-mcp/main/examples/fluent-base.luau",

	HubFolder = "CopilotBase",
}

local function httpGet(url)
	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	if ok and type(body) == "string" and #body > 0 then
		return body
	end

	-- Executors without game:HttpGet (for example Athena) expose request.
	local sender = request or http_request or (syn and syn.request) or (http and http.request)
	if sender then
		local ok2, response = pcall(sender, { Url = url, Method = "GET" })
		if ok2 and type(response) == "table" and type(response.Body) == "string" then
			return response.Body
		end
	end

	return nil
end

-- Replace any previous instance instead of stacking windows.
local previous = getgenv().CopilotBase
if type(previous) == "table" and type(previous.Unload) == "function" then
	pcall(previous.Unload)
end

local fluentSource = httpGet(CONFIG.FluentURL)
if not fluentSource then
	error("[CopilotBase] could not download Fluent from " .. CONFIG.FluentURL)
end

local Fluent = loadstring(fluentSource)()
if type(Fluent) ~= "table" then
	error("[CopilotBase] Fluent returned " .. type(Fluent))
end

local Window = Fluent:CreateWindow({
	Title = CONFIG.Title,
	SubTitle = CONFIG.SubTitle,
	TabWidth = CONFIG.TabWidth,
	Size = CONFIG.Size,
	Acrylic = CONFIG.Acrylic,
	Theme = CONFIG.Theme,
	MinimizeKey = CONFIG.MinimizeKey,
})

local Tabs = {
	Main = Window:AddTab({ Title = "Main", Icon = "" }),
	Bridge = Window:AddTab({ Title = "Bridge", Icon = "" }),
	Features = Window:AddTab({ Title = "Features", Icon = "" }),
	Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

local Base = {
	Version = "1.0.0",
	Config = CONFIG,
	Fluent = Fluent,
	Window = Window,
	Tabs = Tabs,
	Options = Fluent.Options,
	Features = {},
}

-- Keeps a long-running feature responsive to being switched off mid-loop.
function Base:CreateFeature(id, handlers)
	handlers = handlers or {}

	local feature = {
		Id = id,
		Enabled = false,
		Element = nil,
		OnEnable = handlers.OnEnable,
		OnDisable = handlers.OnDisable,
	}

	function feature:IsActive()
		return self.Enabled
	end

	-- Sleep that aborts early once the feature is disabled. Returns self.Enabled.
	function feature:Sleep(seconds)
		local remaining = seconds
		while remaining > 0 and self.Enabled do
			remaining -= task.wait(math.min(0.1, remaining))
		end
		return self.Enabled
	end

	function feature:Enable()
		if self.Enabled then
			return
		end
		self.Enabled = true
		if type(self.OnEnable) == "function" then
			task.spawn(function()
				local ok, err = pcall(self.OnEnable, self)
				if not ok then
					warn(("[CopilotBase] %s: %s"):format(self.Id, tostring(err)))
					Base:Notify({ Title = "Feature error", Content = tostring(err), Duration = 6 })
				end
			end)
		end
	end

	function feature:Disable()
		if not self.Enabled then
			return
		end
		self.Enabled = false
		if type(self.OnDisable) == "function" then
			local ok, err = pcall(self.OnDisable, self)
			if not ok then
				warn(("[CopilotBase] %s disable: %s"):format(self.Id, tostring(err)))
			end
		end
	end

	function feature:SetEnabled(state)
		if state then
			self:Enable()
		else
			self:Disable()
		end
		if self.Element then
			pcall(function()
				self.Element:SetValue(state)
			end)
		end
	end

	Base.Features[id] = feature
	return feature
end

-- Toggle bound to a feature lifecycle. Handler loops should use self:Sleep.
function Base:AddFeatureToggle(tab, id, spec, handlers)
	spec = spec or {}
	local feature = self:CreateFeature(id, handlers)

	local toggle = tab:AddToggle(id, {
		Title = spec.Title or id,
		Description = spec.Description,
		Default = spec.Default or false,
		Callback = function(state)
			if state then
				feature:Enable()
			else
				feature:Disable()
			end
		end,
	})

	feature.Element = toggle
	return feature, toggle
end

function Base:Notify(spec)
	if type(spec) == "string" then
		spec = { Content = spec }
	end
	spec.Duration = spec.Duration or 5
	return Fluent:Notify(spec)
end

-- Status line for the bridge section; Fluent's paragraph API has changed before.
function Base:SetBridgeStatus(text)
	if self._bridgeStatus then
		pcall(function()
			self._bridgeStatus:SetDesc(text)
		end)
	end
end

function Base:ConnectBridge(url)
	url = url or self.Config.BridgeURL
	self.Config.BridgeURL = url

	local ok, err = pcall(function()
		getgenv().BridgeURL = url
		local source = httpGet(("http://%s/script.luau"):format(url))
		if not source then
			error("bridge not reachable at " .. url)
		end
		loadstring(source)({ BridgeURL = url })
	end)

	if ok then
		self:SetBridgeStatus("Connected to " .. url)
		self:Notify({ Title = "MCP Bridge", Content = "Connected to " .. url })
	else
		self:SetBridgeStatus("Failed: " .. tostring(err))
		self:Notify({ Title = "MCP Bridge", Content = tostring(err), Duration = 6 })
	end

	return ok
end

function Base:Unload()
	for _, feature in pairs(self.Features) do
		pcall(function()
			feature:Disable()
		end)
	end
	self.Features = {}

	if self.Window then
		pcall(function()
			self.Window:Destroy()
		end)
	end
	pcall(function()
		Fluent:Destroy()
	end)

	if getgenv().CopilotBase == self then
		getgenv().CopilotBase = nil
	end
end

Tabs.Main:AddParagraph({
	Title = "Interface ready",
	Content = "Add features from the MCP chat with Base:AddFeatureToggle, "
		.. "or load another script that reuses getgenv().CopilotBase.",
})

Tabs.Main:AddSection("Session")

Tabs.Main:AddButton({
	Title = "Unload interface",
	Description = "Stops every feature and closes the window",
	Callback = function()
		Base:Unload()
	end,
})

Tabs.Main:AddButton({
	Title = "Reload interface",
	Description = "Re-downloads this base from SourceURL and restarts it",
	Callback = function()
		local source = httpGet(CONFIG.SourceURL)
		if source then
			loadstring(source)()
		else
			Base:Notify({ Title = "Reload", Content = "Could not fetch " .. CONFIG.SourceURL, Duration = 5 })
		end
	end,
})

Tabs.Bridge:AddParagraph({
	Title = "MCP Bridge",
	Content = "Connects this client to the local Roblox Executor MCP server on port 16384.",
})

Base._bridgeStatus = Tabs.Bridge:AddParagraph({ Title = "Status", Content = "Not connected" })

local bridgeInput = Tabs.Bridge:AddInput("BridgeURL", {
	Title = "Bridge URL",
	Default = CONFIG.BridgeURL,
	Placeholder = "localhost:16384",
	Finished = true,
	Callback = function(value)
		CONFIG.BridgeURL = value
	end,
})

Tabs.Bridge:AddButton({
	Title = "Connect / Reconnect",
	Description = "Fetches the connector from the bridge and starts it",
	Callback = function()
		Base:ConnectBridge(bridgeInput.Value)
	end,
})

Tabs.Bridge:AddToggle("ConnectOnLoad", {
	Title = "Connect when this base loads",
	Description = "Leave off when the connector is already running",
	Default = CONFIG.ConnectOnLoad,
	Callback = function(state)
		CONFIG.ConnectOnLoad = state
	end,
})

Tabs.Features:AddParagraph({
	Title = "Feature registry",
	Content = "Each toggle below is a feature with its own start/stop lifecycle.",
})

Base:AddFeatureToggle(Tabs.Features, "SampleFeature", {
	Title = "Sample feature",
	Description = "Logs once a second while enabled",
	Default = false,
}, {
	OnEnable = function(self)
		while self:Sleep(1) do
			print("[CopilotBase] sample feature tick")
		end
	end,
	OnDisable = function()
		print("[CopilotBase] sample feature stopped")
	end,
})

-- Addons are optional: a blocked GitHub would otherwise take the base down.
local saveManager = httpGet(CONFIG.SaveManagerURL)
local interfaceManager = httpGet(CONFIG.InterfaceManagerURL)

if saveManager and interfaceManager then
	local ok, err = pcall(function()
		local SaveManager = loadstring(saveManager)()
		local InterfaceManager = loadstring(interfaceManager)()

		SaveManager:SetLibrary(Fluent)
		InterfaceManager:SetLibrary(Fluent)
		SaveManager:IgnoreThemeSettings()
		SaveManager:SetIgnoreIndexes({})

		InterfaceManager:SetFolder(CONFIG.HubFolder)
		SaveManager:SetFolder(CONFIG.HubFolder .. "/shared")

		InterfaceManager:BuildInterfaceSection(Tabs.Settings)
		SaveManager:BuildConfigSection(Tabs.Settings)

		Base.SaveManager = SaveManager
		Base.InterfaceManager = InterfaceManager

		SaveManager:LoadAutoloadConfig()
	end)
	if not ok then
		warn("[CopilotBase] addons failed: " .. tostring(err))
	end
end

getgenv().CopilotBase = Base

Window:SelectTab(1)

Base:Notify({
	Title = "Copilot Base " .. Base.Version,
	Content = "Interface loaded. Bridge: " .. CONFIG.BridgeURL,
	Duration = 6,
})

if CONFIG.ConnectOnLoad then
	task.spawn(function()
		Base:ConnectBridge(CONFIG.BridgeURL)
	end)
end

return Base
