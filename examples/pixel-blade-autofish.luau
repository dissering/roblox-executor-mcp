--!nocheck
--[[
	Pixel Blade -- Auto Fish v2 (refined)

	Drives the games fishing state machine through its client signals.
	No remote is fired directly and no game code is patched.

	Reverse-engineered state machine:

	  idle       -> UserInput.attack          -> on_primary_press starts the charge
	  charging   -> UserInput.attack_up       -> release_charge (min 1.0s, by design)
	  releasing  -> (1.0s) -> casting -> (0.9s) -> waiting
	  waiting    -> UserInput.skill_one       -> each hit cuts server bite wait by 14% (floor 30%)
	               -> bubbles (hold 0.55s, release)
	  reel       -> fishing_intents.reel_press (10 presses = instant, saves ~9s)
	  reeling_in -> (0.92s) -> idle

	Mode fast = lure minigame + reel skip (auto stays off).
	Mode safe = built-in auto + reel skip only.

	Usage:
	  loadstring(game:HttpGet("http://localhost:16384/script.luau"))()   -- connector
	  -- then execute this file or run:  getgenv().AutoFish.start()

	F6 toggles. F7 prints stats. F8 changes mode.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CONFIG = {
	mode = "fast",
	bubble_hold = 0.55,
	lure_interval = 0.25,
	recast_delay = 1.15,
	stuck_seconds = 12.0,
	deny_limit = 8,
	min_charge = 1.0,
	reel_interval = 0.1,
	toggle_key = Enum.KeyCode.F6,
	stats_key  = Enum.KeyCode.F7,
	mode_key   = Enum.KeyCode.F8,
}

local player = Players.LocalPlayer
local src = ReplicatedStorage:WaitForChild("src")

local Intents = require(src.client.fishing_intents)
local UserInput = require(src.client.user_input)
local Network = require(src.network)

local S = {
	running = false,
	conn = nil,
	mode_index = 1,
	modes = { "fast", "safe" },
	last_activity = 0,
	last_cast = 0,
	last_bite = 0,
	last_catch = 0,
	last_deny = 0,
	last_lure = 0,
	last_release = 0,
	last_reel = 0,
	idle_at = 0,
	casts = 0,
	catches = 0,
	denies = 0,
	reels_sent = 0,
	started_at = 0,
}

local function hudCanvas()
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return nil end
	local folder = pg:FindFirstChild("fishing_hud")
	if not folder then return nil end
	local gui = folder:FindFirstChild("FishingHud")
	if not gui then return nil end
	return gui:FindFirstChild("canvas")
end

local function isWaiting()
	local cv = hudCanvas()
	return cv ~= nil and cv:FindFirstChild("lure") ~= nil
end

local function listen(channel, fn)
	local ch = Network[channel]
	if not ch then return false end
	local ev = ch.event
	if not ev then return false end
	return pcall(function()
		ev.OnClientEvent:Connect(fn)
	end)
end

local function now()
	return os.clock()
end

local origCast = nil
local function installCastHook()
	local ch = Network.fishing_cast
	if not ch or type(ch.fire) ~= "function" then return false end
	origCast = ch.fire
	S.castHook = origCast
	ch.fire = function(...)
		local t = now()
		S.casts = (S.casts or 0) + 1
		S.last_cast = t
		S.last_activity = t
		return origCast(...)
	end
	return true
end

local function removeCastHook()
	local ch = Network.fishing_cast
	if ch and S.castHook then
		ch.fire = S.castHook
	end
	S.castHook = nil
	origCast = nil
end

local function step()
	if not S.running then return end
	local t = now()

	Intents.reel_press:Fire(t)
	Intents.bubble_down:Fire(t)
	UserInput.attack_up:Fire(t)

	if t - S.last_release >= CONFIG.bubble_hold then
		S.last_release = t
		Intents.bubble_up:Fire(t)
	end

	if CONFIG.mode == "fast" then
		local waiting = isWaiting()
		local mayCast = not waiting
			and t - S.last_bite > 2.0
			and t - S.last_cast > 2.0
		local wantCast = t >= S.idle_at
		local stuck = t - S.last_activity >= CONFIG.stuck_seconds

		if waiting then
			if t - S.last_lure >= CONFIG.lure_interval then
				S.last_lure = t
				UserInput.skill_one:Fire(t)
			end
		end

		if mayCast and (wantCast or stuck) then
			S.idle_at = t + CONFIG.min_charge
			S.last_activity = t
			UserInput.attack:Fire(t)
		end

	else
		if not S.autoSent then
			S.autoSent = true
			Intents.auto_on:Fire(t)
		end
		if t - S.last_reel >= CONFIG.reel_interval then
			S.last_reel = t
		end
	end

	if (S.denies or 0) >= CONFIG.deny_limit then
		S.running = false
		print("[AutoFish] stopped after " .. S.denies .. " denials -- face the water and retry.")
	end
end

local function stats()
	local t = now()
	local elapsed = t - S.started_at
	local rate = elapsed > 0 and (S.catches / elapsed * 60) or 0
	return string.format(
		"[AutoFish] mode=%s run=%s casts=%d catches=%d denies=%d rate=%.2f/min",
		CONFIG.mode, tostring(S.running),
		S.casts or 0, S.catches or 0, S.denies or 0, rate
	)
end

local API = {}

function API.start()
	if S.running then return "already running" end

	S.running = true
	S.autoSent = false
	S.casts = 0
	S.catches = 0
	S.denies = 0
	S.started_at = now()
	S.last_activity = S.started_at
	S.last_cast = 0
	S.last_bite = 0
	S.last_catch = 0
	S.last_deny = 0
	S.last_lure = 0
	S.last_release = 0
	S.last_reel = 0
	S.idle_at = S.started_at + 1.0

	installCastHook()

	listen("fishing_bite", function()
		S.last_bite = now()
		S.last_activity = S.last_bite
	end)

	listen("fishing_caught_item", function()
		S.catches = (S.catches or 0) + 1
		S.last_catch = now()
		S.last_activity = S.last_catch
		S.idle_at = S.last_catch + CONFIG.recast_delay
	end)

	listen("fishing_denied", function()
		S.denies = (S.denies or 0) + 1
		S.last_deny = now()
		S.last_activity = S.last_deny
		S.idle_at = S.last_deny + 2.0
	end)

	S.conn = RunService.RenderStepped:Connect(step)
	print("[AutoFish] started (mode=" .. CONFIG.mode .. ")")
	return "started"
end

function API.stop()
	S.running = false
	if S.conn then
		S.conn:Disconnect()
		S.conn = nil
	end
	removeCastHook()
	pcall(function()
		Intents.auto_off:Fire(now())
	end)
	S.autoSent = false
	print("[AutoFish] stopped")
	return "stopped"
end

function API.toggle()
	if S.running then return API.stop() end
	return API.start()
end

function API.mode() return CONFIG.mode end

function API.setMode(mode)
	if mode == "fast" or mode == "safe" then
		CONFIG.mode = mode
		print("[AutoFish] mode changed to " .. mode)
		return mode
	end
	return nil
end

function API.cycleMode()
	local next = S.mode_index + 1
	if next > #S.modes then next = 1 end
	S.mode_index = next
	return API.setMode(S.modes[next])
end

function API.stats() return stats() end
function API.config() return CONFIG end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == CONFIG.toggle_key then
		print("[AutoFish] " .. API.toggle())
	elseif input.KeyCode == CONFIG.stats_key then
		print(stats())
	elseif input.KeyCode == CONFIG.mode_key then
		print("[AutoFish] mode -> " .. tostring(API.cycleMode()))
	end
end)

getgenv().AutoFish = API
print("[AutoFish] loaded -- F6 toggle, F7 stats, F8 mode. API: getgenv().AutoFish")

return API
