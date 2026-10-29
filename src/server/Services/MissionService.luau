--[[
	MissionService — runs one case at a time on this server.

	Lifecycle: Lobby -> start() -> Briefing -> Active -> ExtractionAvailable
	           -> Completed | Failed -> report -> endMission() -> Lobby
	(an aborted case - everyone left - skips straight to cleanup).

	It ticks MissionCore, applies its effects to the world through the other
	services, and replicates the mission snapshot to every participant.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CaseRegistry = require(Shared.Config.CaseRegistry)
local MapLayout = require(Shared.Config.MapLayout)
local MissionCore = require(Shared.Core.MissionCore)
local ProfileSchema = require(Shared.Core.ProfileSchema)
local Variants = require(Shared.Core.Variants)

local Router = require(script.Parent.Router)

local MissionService = {}

local TICK = 0.1
local SNAPSHOT_MIN_INTERVAL = 0.1
local SNAPSHOT_HEARTBEAT = 1
local REVIVE_DELAY = 3
local REPORT_LINGER = 35
local GHOST_SAMPLE = 0.5
local GHOST_KEEP = 600
local VOTE_TIME = 20

MissionService.mission = nil
MissionService.caseDef = nil

local deps, remotes
local lastSent = { version = -1, at = 0 }
local promptVersion = -1
local dirty = false
local pendingSpawn = {} -- [player] = CFrame
local returnVotes = {}
local reportAt = nil
local history = {} -- [userId] = { samples }
local lastGhostSample = 0
local vote = nil
local runId = 0

local function now()
	return Workspace:GetServerTimeNow()
end

local function toV3(p)
	return Vector3.new(p.x, p.y or 0, p.z)
end

function MissionService.markDirty()
	dirty = true
end

local function missionPlayers()
	local list = {}
	local mission = MissionService.mission
	if not mission then
		return list
	end
	for _, player in Players:GetPlayers() do
		local p = mission:participant(player.UserId)
		if p and p.status ~= "Disconnected" then
			table.insert(list, player)
		end
	end
	return list
end
MissionService.players = missionPlayers

local function sendAll(remote, payload)
	for _, player in missionPlayers() do
		remote:FireClient(player, payload)
	end
end

local function notify(player, text)
	if player and text then
		remotes.Notify:FireClient(player, { text = text })
	end
end

function MissionService.cue(payload)
	sendAll(remotes.Cue, payload)
end

---------------------------------------------------------------------------
-- Characters
---------------------------------------------------------------------------

local function spawnAt(player, cf)
	pendingSpawn[player] = cf
	task.spawn(function()
		local ok, err = pcall(function()
			player:LoadCharacter()
		end)
		if not ok then
			warn("[MissionService] LoadCharacter failed: " .. tostring(err))
		end
	end)
end
MissionService.spawnAt = spawnAt

local function moveCharacter(player, cf)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp then
		character:PivotTo(cf + Vector3.new(0, 3, 0))
		return true
	end
	return false
end

local function removeCharacter(player, delay)
	task.delay(delay or 0, function()
		local character = player.Character
		if character then
			character:Destroy()
		end
	end)
end

local function freeze(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
	end
	if hrp then
		hrp.Anchored = true
	end
end

local function checkpointFor(checkpoints)
	local presenter = deps.EntityService.position()
	local fallback = nil
	for _, cp in checkpoints do
		local pos = toV3(cp.pos)
		fallback = fallback or pos
		if not presenter or (presenter - pos).Magnitude > 40 then
			return CFrame.new(pos), cp
		end
	end
	return CFrame.new(fallback or Vector3.new(0, 0, 58)), nil
end

---------------------------------------------------------------------------
-- Snapshot replication
---------------------------------------------------------------------------

local function replicate(force)
	local mission = MissionService.mission
	if not mission then
		return
	end
	local t = os.clock()
	if not force and mission.version == lastSent.version and t - lastSent.at < SNAPSHOT_HEARTBEAT then
		return
	end
	if not force and t - lastSent.at < SNAPSHOT_MIN_INTERVAL then
		return
	end
	local snapshot = mission:snapshot(now())
	snapshot.serverTime = now()
	snapshot.vote = vote and { proposer = vote.proposerName, expires = vote.expires, yes = vote.yesCount, needed = vote.needed } or nil
	sendAll(remotes.Mission, snapshot)
	lastSent = { version = mission.version, at = t }
end

local function refreshPrompts(force)
	local mission = MissionService.mission
	if not mission then
		return
	end
	if force or mission.version ~= promptVersion then
		promptVersion = mission.version
		deps.InteractionService.refresh(mission)
		for id, def in mission:getInteractables() do
			if def.kind == "Pickup" then
				deps.WorldService.setItemVisible(def.item, mission:promptState(id).visible == true)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Effects from MissionCore
---------------------------------------------------------------------------

local function playerById(userId)
	return userId and Players:GetPlayerByUserId(userId) or nil
end

local function onReport(report)
	reportAt = now()
	local week = select(2, Variants.weeklySeed(os.time()))
	for _, player in missionPlayers() do
		local profile = deps.DataService.get(player)
		local summary = nil
		if profile then
			summary = ProfileSchema.applyReport(profile, report, player.UserId)
			if report.mode == "ArchiveChallenge" then
				local best = profile.archiveChallengeBest[tostring(week)] or 0
				if report.score > best then
					profile.archiveChallengeBest[tostring(week)] = report.score
				end
				task.spawn(deps.DataService.submitScore, week, player.UserId, report.score)
			end
			deps.DataService.markDirty(player)
			task.spawn(deps.DataService.save, player, false)
			deps.LobbyService.sendProfile(player)
		end
		remotes.Report:FireClient(player, { report = report, personal = summary })
	end
end

local applyEffect

local handlers = {
	Notify = function(e)
		if e.userId then
			notify(playerById(e.userId), e.text)
		else
			sendAll(remotes.Notify, { text = e.text })
		end
	end,
	Subtitle = function(e)
		sendAll(remotes.Subtitle, e)
	end,
	Cue = function(e)
		if e.cue == "Rewind" then
			MissionService.sendGhosts(e.room, e.duration or 30)
		elseif e.cue == "TransmitterArmed" then
			deps.WorldService.setTransmitterArmed(true)
		elseif e.cue == "OnAir" then
			deps.WorldService.setOnAir(true)
		end
		sendAll(remotes.Cue, e)
	end,
	Lights = function(e)
		deps.WorldService.setRoomLights(e.room, e.mode)
	end,
	Door = function(e)
		deps.WorldService.setDoorLocked(e.door, e.locked)
		if e.open then
			deps.WorldService.openDoor(e.door)
		end
		deps.InteractionService.refreshDoors()
	end,
	Relay = function(e)
		deps.WorldService.setRelay(e.relay, e.on)
	end,
	Power = function()
		deps.WorldService.setGeneratorStage(2)
	end,
	Item = function(e)
		if not e.present then
			deps.WorldService.removeItem(e.item)
			deps.InteractionService.unbindMissionAnchor("ITEM_" .. e.item)
		end
	end,
	Presenter = function(e)
		deps.EntityService.command(e.command, e.startTime, { scripted = e.scripted, eventId = e.eventId })
	end,
	ObserveNear = function(e)
		deps.EntityService.observeNear(e.userId, e.startTime)
	end,
	OpenDeck = function(e)
		local player = playerById(e.userId)
		if player then
			remotes.Cue:FireClient(player, { cue = "OpenDeck", deck = e.deck })
		end
	end,
	OpenKeypad = function(e)
		local player = playerById(e.userId)
		if player then
			remotes.Cue:FireClient(player, { cue = "OpenKeypad" })
		end
	end,
	Briefing = function(e)
		local player = playerById(e.userId)
		if player then
			remotes.Cue:FireClient(player, { cue = "ReplayBriefing" })
		end
	end,
	Eliminated = function(e)
		local player = playerById(e.userId)
		sendAll(remotes.Cue, { cue = "Eliminated", userId = e.userId })
		if player then
			freeze(player)
			removeCharacter(player, 1.6)
		end
	end,
	Revive = function(e)
		local player = playerById(e.userId)
		if not player then
			return
		end
		local cf = checkpointFor(e.checkpoints or {})
		local token = runId
		task.delay(REVIVE_DELAY, function()
			if token == runId and MissionService.mission and MissionService.mission:isAlive(player.UserId) then
				spawnAt(player, cf)
				remotes.Cue:FireClient(player, { cue = "Revived", invulnerableUntil = e.invulnerableUntil })
			end
		end)
	end,
	Extracted = function(e)
		local player = playerById(e.userId)
		if player then
			remotes.Cue:FireClient(player, { cue = "Extracted" })
			freeze(player)
			removeCharacter(player, 4.5)
		end
	end,
	Phase = function(e)
		if e.phase == "Aborted" then
			task.defer(MissionService.endMission)
		end
		deps.LobbyService.broadcast()
	end,
	Report = function(e)
		onReport(e.report)
	end,
	Unlock = function(e)
		deps.EvidenceService.applyUnlock(e)
	end,
}

applyEffect = function(e)
	local handler = handlers[e.type]
	if handler then
		local ok, err = pcall(handler, e)
		if not ok then
			warn(string.format("[MissionService] effect %s failed: %s", tostring(e.type), tostring(err)))
		end
	end
end

local function applyEffects()
	local mission = MissionService.mission
	if not mission then
		return
	end
	for _, e in mission:drainEffects() do
		applyEffect(e)
	end
end

---------------------------------------------------------------------------
-- Ghost replay (the Rewinding state: a room replays its earlier occupants)
---------------------------------------------------------------------------

local function sampleGhosts(t)
	local mission = MissionService.mission
	for _, player in missionPlayers() do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp and mission:isAlive(player.UserId) then
			local list = history[player.UserId]
			if not list then
				list = {}
				history[player.UserId] = list
			end
			local p = hrp.Position
			local look = hrp.CFrame.LookVector
			table.insert(list, { t = t, x = p.X, z = p.Z, lx = look.X, lz = look.Z })
			while #list > 0 and t - list[1].t > GHOST_KEEP do
				table.remove(list, 1)
			end
		end
	end
end

function MissionService.sendGhosts(roomId, duration)
	local room = MapLayout.Rooms[roomId]
	if not room then
		return
	end
	local t = now()
	local tracks = {}
	for userId, list in history do
		local player = Players:GetPlayerByUserId(userId)
		local samples = {}
		for _, s in list do
			if t - s.t > 20 and s.x >= room.x0 and s.x <= room.x1 and s.z >= room.z0 and s.z <= room.z1 then
				table.insert(samples, s)
			end
		end
		-- Keep the most recent visit, at most `duration` seconds of it.
		local trimmed = {}
		for i = #samples, 1, -1 do
			local s = samples[i]
			if #trimmed > 0 and trimmed[1].t - s.t > duration then
				break
			end
			table.insert(trimmed, 1, s)
		end
		if #trimmed > 1 then
			local base = trimmed[1].t
			local out = {}
			for _, s in trimmed do
				table.insert(out, { s.t - base, s.x, s.z, s.lx, s.lz })
			end
			table.insert(tracks, { name = player and player.DisplayName or "?", samples = out })
		end
	end
	sendAll(remotes.Ghosts, { room = roomId, duration = duration, tracks = tracks })
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function MissionService.start(players, caseId, mode)
	if MissionService.mission then
		return false, "A case is already running."
	end
	local caseDef = CaseRegistry.get(caseId)
	if not caseDef or not caseDef.modes[mode] then
		return false, "Unknown case."
	end
	runId += 1
	local seed
	if caseDef.modes[mode].fixedSeed then
		seed = Variants.weeklySeed(os.time())
	else
		seed = Random.new():NextInteger(1, 2147483646)
	end
	deps.WorldService.reset()
	deps.EntityService.reset(caseDef.modes[mode])
	deps.TimelineService.closeAll()

	local list = {}
	for i, player in players do
		if i > (caseDef.maxParticipants or 4) then
			break
		end
		table.insert(list, { userId = player.UserId, name = player.DisplayName })
	end
	local t = now()
	local mission = MissionCore.new(caseDef, { mode = mode, seed = seed, now = t, participants = list })
	MissionService.mission = mission
	MissionService.caseDef = caseDef
	history = {}
	returnVotes = {}
	reportAt = nil
	vote = nil
	lastSent = { version = -1, at = 0 }
	promptVersion = -1

	-- Physical items for this run's seeded spots.
	for id, def in mission:getInteractables() do
		if def.kind == "Pickup" then
			local _, anchorPart = deps.WorldService.spawnItem(caseDef, def.item, def.pos, true)
			if anchorPart then
				deps.InteractionService.bindMissionAnchor(anchorPart, id)
			end
		end
	end
	-- Non-interactive displays: the valve in its cage, the board in its rack.
	local cage = caseDef.interactables.I_CAGE
	if cage then
		deps.WorldService.spawnItem(caseDef, "VALVE", { x = cage.pos.x, y = 3.25, z = cage.pos.z }, false)
	end
	local rack = caseDef.interactables.I_RACK
	if rack then
		deps.WorldService.spawnItem(caseDef, "BOARD", { x = rack.pos.x - 1.3, y = 3, z = rack.pos.z }, false)
	end

	applyEffects()
	deps.WorldService.setGeneratorStage(0)
	deps.WorldService.setRelay("WEST", true)
	deps.WorldService.setRelay("EAST", true)
	refreshPrompts(true)

	local spawns = deps.WorldService.spawnPoints()
	for i, entry in list do
		local player = Players:GetPlayerByUserId(entry.userId)
		if player then
			player:SetAttribute("InMission", true)
			local cf = spawns[((i - 1) % math.max(1, #spawns)) + 1] or CFrame.new(0, 0, 58)
			if moveCharacter(player, cf) then
				deps.LobbyService.outfit(player)
			else
				spawnAt(player, cf)
			end
		end
	end
	replicate(true)
	deps.LobbyService.broadcast()
	print(string.format("[MissionService] %s started (%s, seed %d) with %d investigator(s)", caseId, mode, seed, #list))
	return true
end

function MissionService.endMission()
	local mission = MissionService.mission
	if not mission then
		return
	end
	runId += 1
	local players = {}
	for _, player in Players:GetPlayers() do
		if mission:participant(player.UserId) then
			table.insert(players, player)
		end
	end
	MissionService.mission = nil
	MissionService.caseDef = nil
	vote = nil
	deps.EntityService.reset(nil)
	deps.TimelineService.closeAll()
	deps.InteractionService.refresh(nil)
	deps.WorldService.reset()
	deps.WorldService.setIdleLights()
	for _, player in players do
		player:SetAttribute("InMission", false)
		player:SetAttribute("Flashlight", false)
		remotes.Mission:FireClient(player, { phase = "None" })
		spawnAt(player, deps.WorldService.hqSpawn())
	end
	deps.LobbyService.broadcast()
end

function MissionService.join(player)
	local mission = MissionService.mission
	if not mission then
		return false, "No case is running."
	end
	local ok, reason = mission:addParticipant(player.UserId, player.DisplayName, now())
	if not ok then
		return false, reason
	end
	player:SetAttribute("InMission", true)
	local spawns = deps.WorldService.spawnPoints()
	local cf = spawns[1] or CFrame.new(0, 0, 58)
	if moveCharacter(player, cf) then
		deps.LobbyService.outfit(player)
	else
		spawnAt(player, cf)
	end
	dirty = true
	replicate(true)
	deps.LobbyService.broadcast()
	return true
end

function MissionService.leave(player)
	local mission = MissionService.mission
	if not mission or not mission:participant(player.UserId) then
		return
	end
	mission:removeParticipant(player.UserId, now())
	player:SetAttribute("InMission", false)
	remotes.Mission:FireClient(player, { phase = "None" })
	spawnAt(player, deps.WorldService.hqSpawn())
	applyEffects()
	deps.LobbyService.broadcast()
end

function MissionService.interact(player, interactId)
	local mission = MissionService.mission
	if not mission then
		return
	end
	local ok, message = mission:interact(player.UserId, interactId, now())
	if not ok and message then
		notify(player, message)
	end
	applyEffects()
	refreshPrompts(false)
	replicate(false)
end

function MissionService.useDoor(player, doorId)
	local mission = MissionService.mission
	local entry = deps.WorldService.door(doorId)
	if not entry then
		return
	end
	if mission and mission:participant(player.UserId) and not mission:isAlive(player.UserId) then
		return
	end
	if entry.locked then
		local reason = mission and mission:doorLockReason(doorId) or "Locked."
		notify(player, reason)
		remotes.Cue:FireClient(player, { cue = "DoorLocked", door = doorId })
		return
	end
	if deps.WorldService.toggleDoor(doorId) and mission then
		mission:addNoise(2, player.UserId)
	end
end

function MissionService.presenterEvent(name, data)
	if name == "HuntStart" then
		sendAll(remotes.Subtitle, { kind = "cue", text = "[TAPE FLUTTER — IT IS HUNTING]" })
		sendAll(remotes.Cue, { cue = "HuntStart", targetId = data.targetId })
	elseif name == "HuntEnd" then
		sendAll(remotes.Cue, { cue = "HuntEnd", reason = data.reason })
		if data.reason == "Lost" or data.reason == "TimeLimit" or data.reason == "Stuck" then
			sendAll(remotes.Subtitle, { kind = "cue", text = "[THE SIGNAL CLEARS]" })
		end
	elseif name == "Searching" then
		sendAll(remotes.Subtitle, { kind = "cue", text = "[IT HAS LOST SIGHT OF YOU]" })
	elseif name == "Appear" then
		sendAll(remotes.Cue, { cue = "PresenterAppear", kind = data.kind })
	elseif name == "Vanish" then
		sendAll(remotes.Cue, { cue = "PresenterVanish" })
	end
end

function MissionService.caught(userId, eventId)
	local mission = MissionService.mission
	if mission then
		mission:eliminate(userId, now(), { eventId = eventId })
		applyEffects()
		replicate(true)
	end
end

---------------------------------------------------------------------------
-- Revives (free stored tokens first; purchases are optional)
---------------------------------------------------------------------------

local function useStoredRevive(player)
	local mission = MissionService.mission
	local profile = deps.DataService.get(player)
	if not mission or not profile or profile.storedRevives <= 0 then
		return false
	end
	if not mission:canRevive(player.UserId, "Personal") then
		return false
	end
	profile.storedRevives -= 1
	deps.DataService.markDirty(player)
	mission:revive(player.UserId, now(), "Personal")
	applyEffects()
	replicate(true)
	deps.LobbyService.sendProfile(player)
	return true
end

local function useStoredTeamToken(player)
	local mission = MissionService.mission
	local profile = deps.DataService.get(player)
	if not mission or not profile or profile.storedTeamTokens <= 0 then
		return false
	end
	if not mission:canTeamRecover() then
		return false
	end
	profile.storedTeamTokens -= 1
	deps.DataService.markDirty(player)
	mission:teamRecover(now())
	applyEffects()
	replicate(true)
	deps.LobbyService.sendProfile(player)
	return true
end

local function finishVote(passed)
	local v = vote
	vote = nil
	dirty = true
	if not v then
		return
	end
	local proposer = Players:GetPlayerByUserId(v.proposer)
	if not passed then
		sendAll(remotes.Notify, { text = "Team recovery cancelled." })
		return
	end
	if not proposer then
		return
	end
	if not useStoredTeamToken(proposer) then
		local ok, reason = deps.MarketService.promptProduct(proposer, "TeamToken", { runId = runId })
		if not ok then
			notify(proposer, reason)
		end
	end
end

function MissionService.init(dependencies, remoteTable)
	deps = dependencies
	remotes = remoteTable

	local function setupPlayer(player)
		player.CharacterAdded:Connect(function(character)
			local cf = pendingSpawn[player]
			pendingSpawn[player] = nil
			local hrp = character:WaitForChild("HumanoidRootPart", 10)
			if cf and hrp then
				task.wait()
				character:PivotTo(cf + Vector3.new(0, 3, 0))
			end
			deps.LobbyService.dress(player, character)
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Died:Connect(function()
					-- Deaths that are not the Presenter (it never kills; it takes
					-- players off-air) respawn at a checkpoint without penalty.
					local mission = MissionService.mission
					if mission and mission:isAlive(player.UserId) then
						local spot = checkpointFor(mission:checkpoints())
						task.delay(REVIVE_DELAY, function()
							if MissionService.mission == mission and mission:isAlive(player.UserId) then
								spawnAt(player, spot)
							end
						end)
					elseif not mission or not mission:participant(player.UserId) then
						task.delay(REVIVE_DELAY, function()
							spawnAt(player, deps.WorldService.hqSpawn())
						end)
					end
				end)
			end
		end)
	end
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		pendingSpawn[player] = nil
		returnVotes[player.UserId] = nil
		local mission = MissionService.mission
		if mission and mission:participant(player.UserId) then
			mission:removeParticipant(player.UserId, now())
			applyEffects()
			replicate(true)
		end
		history[player.UserId] = nil
	end)

	Router.onAction("Flashlight", function(player, payload)
		local on = payload.on == true
		player:SetAttribute("Flashlight", on)
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		local light = head and head:FindFirstChild("Flashlight")
		if light then
			light.Enabled = on
		end
	end, { rate = 4, burst = 6 })

	Router.onAction("ReturnToHQ", function(player)
		local mission = MissionService.mission
		if not mission then
			return
		end
		if mission.phase == "Completed" or mission.phase == "Failed" then
			returnVotes[player.UserId] = true
			local all = true
			for _, p in missionPlayers() do
				if not returnVotes[p.UserId] then
					all = false
				end
			end
			if all then
				MissionService.endMission()
			end
		end
	end)

	Router.onRequest("SubmitCode", function(player, payload)
		local mission = MissionService.mission
		local cage = mission and mission.case.interactables.I_CAGE
		if not mission or not cage or not Router.string(payload.code, 8) then
			return { ok = false, message = "Nothing to unlock." }
		end
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp or (hrp.Position - toV3(cage.pos)).Magnitude > 12 then
			return { ok = false, message = "Stand at the cage keypad." }
		end
		local ok, message = mission:submitCode(player.UserId, payload.code, now())
		applyEffects()
		replicate(true)
		return { ok = ok, message = message }
	end, { rate = 1, burst = 3 })

	-- Camcorder evidence: filming the Presenter earns a little research.
	local recorded = {} -- [userId] = research granted this case
	Router.onAction("RecordAnomaly", function(player)
		local mission = MissionService.mission
		local presenter = deps.EntityService.position()
		if not mission or not presenter or not mission:isAlive(player.UserId) then
			return
		end
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		if not head or (head.Position - presenter).Magnitude > 60 then
			return
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.RespectCanCollide = true
		params.FilterDescendantsInstances = { character, deps.EntityService.model }
		local target = presenter + Vector3.new(0, 3, 0)
		if Workspace:Raycast(head.Position, target - head.Position, params) then
			return
		end
		local key = tostring(runId) .. ":" .. player.UserId
		local granted = recorded[key] or 0
		if granted >= 30 then
			return
		end
		local profile = deps.DataService.get(player)
		if profile then
			recorded[key] = granted + 5
			profile.research += 5
			deps.DataService.markDirty(player)
			notify(player, "Anomaly recorded (+5 research).")
			deps.LobbyService.sendProfile(player)
		end
	end, { rate = 0.2, burst = 1 })

	Router.onAction("LeaveCase", function(player)
		MissionService.leave(player)
	end, { rate = 1, burst = 2 })

	Router.onRequest("JoinMission", function(player)
		local ok, reason = MissionService.join(player)
		return { ok = ok, message = reason }
	end, { rate = 1, burst = 2 })

	Router.onRequest("Revive", function(player)
		local mission = MissionService.mission
		if not mission then
			return { ok = false, message = "No case is running." }
		end
		local ok, reason = mission:canRevive(player.UserId, "Personal")
		if not ok then
			return { ok = false, message = reason }
		end
		if useStoredRevive(player) then
			return { ok = true, message = "Re-entering..." }
		end
		local prompted, why = deps.MarketService.promptProduct(player, "Revive", { runId = runId })
		return { ok = prompted, prompted = prompted, message = why }
	end, { rate = 1, burst = 2 })

	Router.onRequest("TeamRecovery", function(player)
		local mission = MissionService.mission
		if not mission then
			return { ok = false, message = "No case is running." }
		end
		if not mission:isAlive(player.UserId) then
			return { ok = false, message = "Only investigators still inside can call it in." }
		end
		local ok, reason = mission:canTeamRecover()
		if not ok then
			return { ok = false, message = reason }
		end
		if vote then
			return { ok = false, message = "A vote is already running." }
		end
		local needed = 0
		for _, p in missionPlayers() do
			if mission:isAlive(p.UserId) then
				needed += 1
			end
		end
		vote = {
			proposer = player.UserId,
			proposerName = player.DisplayName,
			yes = { [player.UserId] = true },
			yesCount = 1,
			needed = needed,
			expires = now() + VOTE_TIME,
		}
		dirty = true
		if vote.yesCount >= vote.needed then
			finishVote(true)
		else
			sendAll(remotes.Cue, { cue = "TeamVote", proposer = player.DisplayName })
		end
		return { ok = true }
	end, { rate = 1, burst = 2 })

	Router.onAction("TeamVoteReply", function(player, payload)
		local mission = MissionService.mission
		if not vote or not mission or not mission:isAlive(player.UserId) then
			return
		end
		if payload.yes ~= true then
			finishVote(false)
			return
		end
		if not vote.yes[player.UserId] then
			vote.yes[player.UserId] = true
			vote.yesCount += 1
			dirty = true
		end
		if vote.yesCount >= vote.needed then
			finishVote(true)
		end
	end, { rate = 2, burst = 4 })

	table.insert(deps.MarketService.onGranted, function(player, productKey)
		local intent = deps.MarketService.takeIntent(player, productKey)
		if productKey == "Revive" then
			if not (intent and type(intent) == "table" and intent.runId == runId and useStoredRevive(player)) then
				notify(player, "Emergency re-entry stored for a future case.")
			end
		elseif productKey == "TeamToken" then
			if not (intent and type(intent) == "table" and intent.runId == runId and useStoredTeamToken(player)) then
				notify(player, "Team recovery stored for a future case.")
			end
		end
		deps.LobbyService.sendProfile(player)
	end)

	table.insert(deps.WorldService.onReset, function(station)
		deps.InteractionService.bindStation(station)
	end)

	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(function()
				local mission = MissionService.mission
				if not mission then
					return
				end
				local t = now()
				mission:update(t, { presenterIdle = deps.EntityService.isIdle() })
				applyEffects()
				if t - lastGhostSample >= GHOST_SAMPLE then
					lastGhostSample = t
					sampleGhosts(t)
				end
				if vote then
					local alive = mission:canTeamRecover()
					if t > vote.expires or not alive then
						finishVote(false)
					end
				end
				refreshPrompts(false)
				if dirty then
					dirty = false
					replicate(true)
				else
					replicate(false)
				end
				if reportAt and t - reportAt > REPORT_LINGER then
					MissionService.endMission()
				end
			end)
			if not ok then
				warn("[MissionService] tick failed: " .. tostring(err))
			end
		end
	end)
end

return MissionService
