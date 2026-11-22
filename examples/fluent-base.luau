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

	-- Game identification for per-game script separation
	GameName = "Pixel-Blade",
	RepositoryURL = "",  -- e.g., "git@github.com:pattapee-XXX/Pixel-Blade.git" or empty for local-only

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
	Scripts = {},
}

local Base = {
	Version = "1.0.0",
	Config = CONFIG,
	Fluent = Fluent,
	Window = Window,
	Tabs = Tabs,
	Options = Fluent.Options,
	Features = {},
	Scripts = {},
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

-- ── Scripts tab: feature registry with pause-by-default ──

Tabs.Scripts = Window:AddTab({ Title = "Scripts", Icon = "code" })

function Base:ListScripts()
	local list = {}
	for id, script in pairs(self.Scripts) do
		table.insert(list, { id = id, enabled = script.Enabled, queued = script.Queued })
	end
	return list
end

function Base:GetPendingScripts()
	local list = {}
	for id, script in pairs(self.Scripts) do
		if script.Queued then
			table.insert(list, id)
		end
	end
	return list
end

function Base:PauseAll()
	for id, script in pairs(self.Scripts) do
		if script.Enabled then
			script:Disable()
		end
	end
end

function Base:UnqueueAll()
	for _, script in pairs(self.Scripts) do
		script.Queued = false
	end
end

-- Build the Scripts tab UI
local scriptsParagraph = Tabs.Scripts:AddParagraph({
	Title = "Script Registry",
	Content = "ทุก script ถูก disabled โดย default จนกว่าจะสั่ง 'update to github' "
		.. "หรือ enable จาก toggle ใน tab นี้.",
})

local statusParagraph = Tabs.Scripts:AddParagraph({
	Title = "Status",
	Content = "No scripts queued.",
})

Tabs.Scripts:AddButton({
	Title = "Unqueue Script",
	Description = "Enable script นี้ (unqueue)",
	Callback = function()
		Base:UnqueueAll()
		Base:Notify({ Title = "Unqueue", Content = "All scripts unqueued.", Duration = 5 })
	end,
})

local queueCount = 0

function Base:UpdateStatusParagraph()
	queueCount = #Base:GetPendingScripts()
	statusParagraph:SetDesc((queueCount == 0 and "No scripts queued.")
		or (queueCount == 1 and "1 script queued.")
		or ("%d scripts queued."):format(queueCount))
end

-- Override CreateFeature / AddFeatureToggle to add Queued property and Auto-disable
local oldCreateFeature = Base.CreateFeature
local oldAddFeatureToggle = Base.AddFeatureToggle

Base.CreateFeature = function(self, id, handlers)
	-- Remove old script with same id if exists (prevent duplicates)
	if self.Scripts[id] then
		self.Scripts[id]:Disable()
		self.Features[self.Scripts[id].Id] = nil
		self.Scripts[id] = nil
	end

	local script = oldCreateFeature(self, id, handlers)
	script:Disable()
	script.Queued = true
	script.Unqueue = function(s) s.Queued = false end
	script.ToStatus = function(s) return s.Queued and "pending" or (s.Enabled and "running" or "paused") end
	Base.Scripts[script.Id] = script
	Base:UpdateStatusParagraph()
	return script
end

Base.AddFeatureToggle = function(self, tab, id, spec, handlers)
	-- Remove old script with same id if exists (prevent duplicates)
	if self.Scripts[id] then
		self.Scripts[id]:Disable()
		self.Features[self.Scripts[id].Id] = nil
		self.Scripts[id] = nil
	end

	local script, toggle = oldAddFeatureToggle(self, tab, id, spec, handlers)
	script:Disable()
	script.Queued = true
	script.Unqueue = function(s) s.Queued = false end
	script.ToStatus = function(s) return s.Queued and "pending" or (s.Enabled and "running" or "paused") end
	Base.Scripts[script.Id] = script
	Base:UpdateStatusParagraph()
	return script, toggle
end

-- ── End Scripts tab ──

-- ── Export to GitHub ──

function Base:ExportToGitHub()
	local gameName = self.Config.GameName or "Pixel-Blade"
	local outputDir = "./scripts/" .. gameName

	-- Build Lua code to gather scripts from CopilotBase
	local gatherCode = [[
		local base = getgenv().CopilotBase
		if not base or not base.Scripts then
			return { scriptCount = 0, scripts = {}, error = "CopilotBase not found." }
		end

		local result = { scriptCount = 0, scripts = {} }

		for id, script in pairs(base.Scripts) do
			result.scriptCount = result.scriptCount + 1
			table.insert(result.scripts, {
				id = script.Id or id,
				name = script.Name or script.Id or id,
				description = script.Description or "No description",
				enabled = script.Enabled or false,
				queued = script.Queued or false,
				source = script.OnEnable or "",
				gameName = base.Config and base.Config.GameName or "Pixel-Blade",
			})
		end

		return result
	]]

	-- Query scripts from executor
	local ok, result = pcall(function()
		-- This would normally use the MCP bridge, but for now we return a notification
		return { error = "Use MCP chat to run export-copilot-scripts" }
	end)

	Base:Notify({
		Title = "Export to GitHub",
		Content = "Game: " .. gameName .. " | Scripts: " .. tostring(ok and result.scriptCount or 0),
		Duration = 5,
	})

	Base:PauseAll()

	local scriptCount = ok and (result.scriptCount or 0) or 0
	statusParagraph:SetDesc("Exported " .. scriptCount .. " script(s) to ./scripts/" .. gameName)

	return scriptCount
end

-- Migrate existing features (created before override) into Scripts table
for id, script in pairs(Base.Features) do
	Base.Scripts[script.Id] = script
	script:Disable()
	script.Queued = true
	script.Unqueue = function(s) s.Queued = false end
	script.ToStatus = function(s) return s.Queued and "pending" or (s.Enabled and "running" or "paused") end
	Base:UpdateStatusParagraph()
end

getgenv().CopilotBase = Base

Window:SelectTab(4)

Base:Notify({
	Title = "Copilot Base " .. Base.Version,
	Content = "Interface loaded. Bridge: " .. CONFIG.BridgeURL .. " | Scripts paused until push.",
	Duration = 6,
})

if CONFIG.ConnectOnLoad then
	task.spawn(function()
		Base:ConnectBridge(CONFIG.BridgeURL)
	end)
end

return Base
