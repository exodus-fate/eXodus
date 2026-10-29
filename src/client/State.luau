--[[
	Client state store. Everything the UI shows comes from server snapshots; the
	client never decides game outcomes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local CaseRegistry = require(Shared.Config.CaseRegistry)
local ProfileSchema = require(Shared.Core.ProfileSchema)
local TimelineCore = require(Shared.Core.TimelineCore)

local State = {}

State.player = Players.LocalPlayer
State.remotes = nil
State.mission = nil
State.profile = nil
State.party = nil
State.report = nil
State.settings = table.clone(ProfileSchema.DefaultSettings)

State.missionChanged = Signal.new()
State.profileChanged = Signal.new()
State.partyChanged = Signal.new()
State.settingsChanged = Signal.new()
State.cue = Signal.new()
State.subtitle = Signal.new()
State.notify = Signal.new()
State.reportReceived = Signal.new()
State.ghosts = Signal.new()
State.uiChanged = Signal.new()

-- Which modal screens are open (input is suspended while any is).
State.ui = {}

function State.setUI(name, open)
	if (State.ui[name] == true) ~= (open == true) then
		State.ui[name] = open or nil
		State.uiChanged:Fire(name, open)
	end
end

function State.anyModal()
	return next(State.ui) ~= nil
end

function State.now()
	return Workspace:GetServerTimeNow()
end

function State.action(kind, payload)
	payload = payload or {}
	payload.type = kind
	State.remotes.Action:FireServer(payload)
end

function State.request(kind, payload)
	payload = payload or {}
	payload.type = kind
	local ok, result = pcall(function()
		return State.remotes.Request:InvokeServer(payload)
	end)
	if not ok then
		return { ok = false, message = "Connection problem." }
	end
	return result or { ok = false }
end

function State.inMission()
	local m = State.mission
	if not m or m.phase == "None" then
		return false
	end
	local me = m.participants and m.participants[tostring(State.player.UserId)]
	return me ~= nil and me.status ~= "Disconnected"
end

function State.me()
	local m = State.mission
	return m and m.participants and m.participants[tostring(State.player.UserId)]
end

function State.isAlive()
	local me = State.me()
	return me ~= nil and me.status == "Alive"
end

function State.caseDef()
	local m = State.mission
	return m and m.caseId and CaseRegistry.get(m.caseId) or nil
end

-- Event definitions after seeded variants (for footage), cached per run.
local defsCache = { key = nil, defs = nil }
function State.eventDefs(caseDef, patrolFlip)
	caseDef = caseDef or State.caseDef()
	if not caseDef then
		return nil
	end
	local key = caseDef.id .. ":" .. tostring(patrolFlip == true)
	if defsCache.key ~= key then
		defsCache.key = key
		defsCache.defs = TimelineCore.new(caseDef, { patrolFlip = patrolFlip == true }):eventDefinitions()
	end
	return defsCache.defs
end

function State.broadcastClock()
	local m = State.mission
	if not m or not m.broadcastStart then
		return 0
	end
	return State.now() - m.broadcastStart
end

function State.hasTape(tapeId)
	local m = State.mission
	if not m or not m.inventory then
		return false
	end
	local caseDef = State.caseDef()
	if not caseDef then
		return false
	end
	for itemId, item in caseDef.items do
		if item.kind == "Tape" and item.tape == tapeId and m.inventory[itemId] then
			return true
		end
	end
	return false
end

function State.applySettings(settings)
	State.settings = ProfileSchema.sanitizeSettings(State.settings, settings)
	State.settingsChanged:Fire(State.settings)
end

-- Saves settings to the server shortly after the player stops changing them.
local saveToken = 0
function State.saveSettingsSoon()
	saveToken += 1
	local token = saveToken
	task.delay(1.5, function()
		if token == saveToken then
			State.request("SaveSettings", { settings = State.settings })
		end
	end)
end

-- Effective intensity multiplier for distortion-type effects.
function State.intensity(kind)
	local s = State.settings
	local base = s[kind] or 1
	if s.lowIntensity then
		base *= 0.25
	end
	return base
end

function State.init(remotes)
	State.remotes = remotes
	remotes.Mission.OnClientEvent:Connect(function(snapshot)
		if snapshot.phase == "None" then
			State.mission = nil
		else
			State.mission = snapshot
		end
		State.missionChanged:Fire(State.mission)
	end)
	remotes.Profile.OnClientEvent:Connect(function(profile)
		local first = State.profile == nil
		State.profile = profile
		if first and profile.settings then
			State.applySettings(profile.settings)
		end
		State.profileChanged:Fire(profile)
	end)
	remotes.Party.OnClientEvent:Connect(function(party)
		State.party = party
		State.partyChanged:Fire(party)
	end)
	remotes.Cue.OnClientEvent:Connect(function(cue)
		State.cue:Fire(cue)
	end)
	remotes.Subtitle.OnClientEvent:Connect(function(line)
		State.subtitle:Fire(line)
	end)
	remotes.Notify.OnClientEvent:Connect(function(n)
		State.notify:Fire(n.text)
	end)
	remotes.Report.OnClientEvent:Connect(function(payload)
		State.report = payload
		State.reportReceived:Fire(payload)
	end)
	remotes.Ghosts.OnClientEvent:Connect(function(payload)
		State.ghosts:Fire(payload)
	end)
end

return State
