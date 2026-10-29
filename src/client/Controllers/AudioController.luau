--[[
	AudioController — everything the player hears.

	  Mixer       Sound groups for Music, Ambience, Effects, Interface and
	              Cinematic under a master, following the Settings sliders, with
	              ducking (radio lines, the deck) and the false-safety silence.
	  Music       A director picks the track from the situation - main menu,
	              field office, briefing, exploring (with a tension layer that
	              swells with the camera's tension value), the hunt, extraction,
	              the case report - and crossfades between them.
	  Ambience    Room tone that follows where you are and whether the lights
	              are on, fluorescent buzz, wind at the dock, the office hum.
	  Machines    Positional loops on the generator, the transmitter and the van
	              once they are running, and the Presenter's static face.
	  Footsteps   Yours, in time with the head bob, and everyone else's, chosen
	              by the floor surface; the Presenter's heavy tread.
	  Events      Every server cue, door, pickup, relay, radio line, subtitle
	              sound description and interface action has a sound.

	All sounds are slices of four original audio banks (Config/AudioBank) whose
	uploaded ids live in Config/AudioAssets. Until the banks are uploaded, every
	call is a silent no-op; subtitles and visuals carry all information anyway.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared.Config.Audio)
local AudioAssets = require(Shared.Config.AudioAssets)
local AudioBank = require(Shared.Config.AudioBank)
local MapLayout = require(Shared.Config.MapLayout)

local State = require(script.Parent.Parent.State)
local Sound = require(script.Parent.Parent.UI.Sound)

local AudioController = {}

local STEP_LENGTH = 3.1 -- studs per footstep, matches the head bob
local HISTORY = 400

-- Recently requested sounds, newest last (for tests and debugging).
AudioController.history = {}
AudioController.track = nil -- current music track key ("Explore", "Hunt"...)

local groups = {}
local master
local emitterFolder
local recent = {} -- [name] = os.clock() of the last play (dedupe)
local layers = {} -- [name] = { sound, level, target, up, down }
local emitters = {} -- [name] = { sound, part }
local silencedUntil = 0
local radioUntil = 0
local rng = Random.new()

---------------------------------------------------------------------------
-- Sounds
---------------------------------------------------------------------------

local function record(name)
	local history = AudioController.history
	table.insert(history, name)
	if #history > HISTORY then
		table.remove(history, 1)
	end
end

function AudioController.enabled()
	for _, id in AudioAssets.Banks do
		if id ~= "" then
			return true
		end
	end
	return false
end

-- A Sound playing exactly one sound's slice of its bank, or nil if that bank
-- has not been uploaded yet.
local function newSound(name, parent)
	local region = AudioBank.Sounds[name]
	if not region then
		return nil
	end
	local id = AudioAssets.Banks[region.bank]
	if not id or id == "" then
		return nil
	end
	local def = Audio.def(name)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.PlaybackRegionsEnabled = true
	local range = NumberRange.new(region.start, region.start + region.length)
	sound.PlaybackRegion = range
	if region.loop then
		sound.LoopRegion = range
		sound.Looped = true
	end
	sound.Volume = def.volume or 0.7
	sound.SoundGroup = groups[def.group or "Effects"] or groups.Effects
	if parent and parent ~= SoundService then
		local spatial = def.spatial or { 6, 80 }
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = spatial[1]
		sound.RollOffMaxDistance = spatial[2]
	end
	sound.Parent = parent or SoundService
	return sound, region, def
end

local function emitterAt(position)
	local part = Instance.new("Part")
	part.Name = "DeadAirSound"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(position)
	part.Parent = emitterFolder
	return part
end

--[[
	opts: at (Vector3, plays there), parent (BasePart/Attachment), volume (x),
	      dedupe (seconds: skip if the same sound played that recently)
]]
function AudioController.play(name, opts)
	opts = opts or {}
	local now = os.clock()
	if opts.dedupe and recent[name] and now - recent[name] < opts.dedupe then
		return nil
	end
	recent[name] = now
	record(name)
	local temporary = opts.at and emitterAt(opts.at) or nil
	local sound, region, def = newSound(name, temporary or opts.parent)
	if not sound then
		if temporary then
			temporary:Destroy()
		end
		return nil
	end
	local pitch = def.pitch
	if pitch then
		sound.PlaybackSpeed = pitch[1] + (pitch[2] - pitch[1]) * rng:NextNumber()
	end
	sound.Volume *= opts.volume or 1
	sound:Play()
	task.delay(region.length / math.max(sound.PlaybackSpeed, 0.1) + 0.3, function()
		sound:Destroy()
		if temporary then
			temporary:Destroy()
		end
	end)
	return sound
end

-- Plays `name` `count` times, `gap` seconds apart.
local function repeatPlay(name, count, gap, opts)
	for i = 0, count - 1 do
		task.delay(i * gap, AudioController.play, name, opts)
	end
end

---------------------------------------------------------------------------
-- Layers: looping beds and music that fade toward a target level
---------------------------------------------------------------------------

local function setLayer(name, target, up, down)
	local layer = layers[name]
	if not layer then
		if target <= 0 then
			return
		end
		layer = { sound = nil, level = 0, target = 0, up = 0.6, down = 0.4 }
		layers[name] = layer
	end
	layer.target = target
	layer.up = up or layer.up
	layer.down = down or layer.down
end

local function stepLayers(dt)
	for name, layer in layers do
		local rate = layer.target > layer.level and layer.up or layer.down
		local delta = layer.target - layer.level
		layer.level += math.sign(delta) * math.min(math.abs(delta), rate * dt)
		if layer.level > 0.001 and not layer.sound then
			layer.sound = newSound(name)
			if layer.sound then
				layer.sound.Volume = 0
				layer.sound:Play()
			end
		end
		if layer.sound then
			layer.sound.Volume = (Audio.def(name).volume or 0.7) * layer.level
		end
		if layer.level <= 0.001 and layer.target <= 0 then
			if layer.sound then
				layer.sound:Destroy()
			end
			layers[name] = nil
		end
	end
end

function AudioController.layerLevel(name)
	local layer = layers[name]
	return layer and layer.target or 0
end

-- A positional loop attached to a part (nil part removes it).
local function setEmitter(name, part)
	local entry = emitters[name]
	if entry and (part == nil or entry.part ~= part or entry.sound.Parent == nil) then
		entry.sound:Destroy()
		emitters[name] = nil
		entry = nil
	end
	if part and not entry then
		local sound = newSound(name, part)
		record(name)
		if sound then
			sound:Play()
			emitters[name] = { sound = sound, part = part }
		else
			-- Remember the request so tests and debugging can see it.
			emitters[name] = { sound = { Destroy = function() end, Parent = part }, part = part }
		end
	end
end

function AudioController.emitterActive(name)
	return emitters[name] ~= nil
end

---------------------------------------------------------------------------
-- World lookups
---------------------------------------------------------------------------

local function station()
	return Workspace:FindFirstChild("Station04")
end

local function propPart(roomId, modelName, partName)
	local s = station()
	local rooms = s and s:FindFirstChild("Rooms")
	local room = rooms and rooms:FindFirstChild(roomId)
	local props = room and room:FindFirstChild("Props")
	local model = props and props:FindFirstChild(modelName)
	return model and model:FindFirstChild(partName)
end

local function presenter()
	local model = Workspace:FindFirstChild("Presenter")
	if model and model:IsA("Model") and model.PrimaryPart then
		return model
	end
	return nil
end

local function myRoot()
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function listenerPosition()
	local root = myRoot()
	if root and State.inMission() and State.isAlive() then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return camera and camera.CFrame.Position or Vector3.zero
end

local function toV3(p)
	return Vector3.new(p.x, p.y or 0, p.z)
end

local function generatorPosition()
	local body = propPart("Generator", "Generator", "Body")
	return body and body.Position
end

---------------------------------------------------------------------------
-- Footsteps
---------------------------------------------------------------------------

local function surfaceFor(material)
	return Audio.StepSurface[material and material.Name or ""] or "concrete"
end

local function stepName(kind)
	return string.format("Step_%s_%d", kind, rng:NextInteger(1, Audio.StepVariants))
end

-- The local player's step (called by the camera in time with the head bob).
function AudioController.footstep(sprinting)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	AudioController.play(stepName(surfaceFor(humanoid.FloorMaterial)), { volume = sprinting and 1.25 or 0.9 })
end

local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude

local function floorKind(root, character)
	floorParams.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -6, 0), floorParams)
	return surfaceFor(hit and hit.Material)
end

-- Other investigators: a step every STEP_LENGTH studs they move.
local others = {} -- [player] = { last, travelled }
local function stepOthers()
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local track = others[player]
			if root then
				local pos = root.Position
				if not track or track.root ~= root then
					track = { root = root, last = pos, travelled = 0 }
					others[player] = track
				end
				local moved = Vector3.new(pos.X - track.last.X, 0, pos.Z - track.last.Z).Magnitude
				track.last = pos
				if moved < 4 then -- ignore teleports
					track.travelled += moved
				end
				if track.travelled >= STEP_LENGTH then
					track.travelled = 0
					AudioController.play(stepName(floorKind(root, character)), { parent = root })
				end
			else
				others[player] = nil
			end
		end
	end
	for player in others do
		if player.Parent == nil then
			others[player] = nil
		end
	end
end

-- Roblox's default running sound is replaced by the surface footsteps above.
local function muteDefaultSteps(character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	local function mute(child)
		if child:IsA("Sound") and child.Name == "Running" then
			child.Volume = 0
		end
	end
	for _, child in root:GetChildren() do
		mute(child)
	end
	root.ChildAdded:Connect(mute)
end

local presenterTrack = { last = nil, travelled = 0 }
local function stepPresenter()
	local model = presenter()
	if not model then
		presenterTrack.last = nil
		return
	end
	local root = model.PrimaryPart
	local pos = root.Position
	if presenterTrack.last then
		local moved = Vector3.new(pos.X - presenterTrack.last.X, 0, pos.Z - presenterTrack.last.Z).Magnitude
		if moved < 6 then
			presenterTrack.travelled += moved
		end
	end
	presenterTrack.last = pos
	-- Its stride is long: a step every 4.6 studs.
	if presenterTrack.travelled >= 4.6 then
		presenterTrack.travelled = 0
		AudioController.play("PresenterStep", { parent = root })
	end
end

---------------------------------------------------------------------------
-- Directors (run ten times a second)
---------------------------------------------------------------------------

local function chooseMusic()
	if State.ui.report then
		return "Report"
	end
	local m = State.mission
	if m and State.inMission() then
		if m.phase == "Briefing" then
			return "Briefing"
		end
		if m.phase == "Completed" or m.phase == "Failed" then
			return "Report"
		end
		local model = presenter()
		if model and model:GetAttribute("State") == "Hunting" then
			return "Hunt"
		end
		if m.phase == "ExtractionAvailable" then
			return "Extract"
		end
		return "Explore"
	end
	if State.ui.menu then
		return "Menu"
	end
	return "Lobby"
end

local function directMusic()
	local key = chooseMusic()
	AudioController.track = key
	for trackKey, name in Audio.Music do
		if trackKey ~= "Tension" then
			local on = trackKey == key
			if trackKey == "Hunt" then
				setLayer(name, on and 1 or 0, 3, 0.35) -- slams in, lingers out
			else
				setLayer(name, on and 1 or 0, 0.5, 0.5)
			end
		end
	end
	-- The tension layer swells over the exploration score.
	local tension = State.tension or 0
	local swell = key == "Explore" and math.clamp((tension - 0.3) / 0.45, 0, 1) or 0
	setLayer(Audio.Music.Tension, swell, 0.8, 0.25)
end

local function directAmbience()
	local beds = { AmbStation = 0, AmbDark = 0, AmbHQ = 0, AmbOutdoor = 0, Fluorescent = 0 }
	if State.inMission() then
		local pos = listenerPosition()
		local roomId = MapLayout.roomAt(pos.X, pos.Z)
		local room = roomId and MapLayout.Rooms[roomId]
		local s = station()
		local folder = s and roomId and s:FindFirstChild("Rooms") and s.Rooms:FindFirstChild(roomId)
		local mode = folder and folder:GetAttribute("LightMode") or "off"
		if room and room.outdoor then
			beds.AmbOutdoor = 1
			beds.AmbDark = 0.3
		elseif mode == "on" then
			beds.AmbStation = 1
			beds.Fluorescent = 1
		elseif mode == "emergency" then
			beds.AmbStation = 0.6
			beds.AmbDark = 0.6
		else
			beds.AmbDark = 1
			beds.AmbStation = 0.2
		end
	else
		beds.AmbHQ = 1
		beds.Fluorescent = 0.45
	end
	for name, target in beds do
		setLayer(name, target, 0.5, 0.35)
	end
end

local function directMachines()
	local m = State.mission
	local flags = m and m.flags or {}
	local inMission = m ~= nil and State.inMission()
	setEmitter("GeneratorLoop", inMission and flags.generator_restored and propPart("Generator", "Generator", "Body") or nil)
	setEmitter("TransmitterLoop", inMission and flags.transmitter_armed and propPart("Transmitter", "Transmitter", "Cabinet") or nil)
	local vanRunning = inMission and (m.phase == "ExtractionAvailable" or flags.extraction_open)
	setEmitter("VanIdle", vanRunning and propPart("LoadingDock", "ExtractionVan", "Body") or nil)

	local model = presenter()
	local near = 0
	local face = nil
	if model and inMission then
		local d = (model.PrimaryPart.Position - listenerPosition()).Magnitude
		near = math.clamp(1 - d / 45, 0, 1)
		if d < 90 then
			face = model:FindFirstChild("Head") or model.PrimaryPart
		end
	end
	setEmitter("PresenterStatic", face)
	setLayer("PresenterNear", near, 1.5, 0.6)
end

-- Heartbeat when tension is high.
local nextBeat = 0
local function stepHeart()
	local tension = State.tension or 0
	if tension < 0.55 or not State.inMission() or not State.isAlive() then
		return
	end
	local now = os.clock()
	if now >= nextBeat then
		nextBeat = now + 60 / (64 + tension * 70)
		AudioController.play("Heartbeat", { volume = math.clamp((tension - 0.55) / 0.45, 0.2, 1) })
	end
end

-- Mixer: settings, ducking and the false-safety silence.
local function mixGroups(dt)
	local settings = State.settings
	local now = os.clock()
	local silent = now < silencedUntil and 0 or 1
	local duckMusic, duckAmbience = 1, 1
	if now < radioUntil then
		duckMusic, duckAmbience = 0.55, 0.75
	end
	if State.ui.deck then
		duckMusic, duckAmbience = math.min(duckMusic, 0.6), math.min(duckAmbience, 0.7)
	end
	local targets = {
		Music = settings.music * duckMusic * silent,
		Ambience = settings.ambience * duckAmbience * silent,
		Effects = settings.effects * silent,
		Interface = settings.effects * silent,
		Cinematic = settings.effects,
	}
	local k = math.min(1, dt * 4)
	for name, target in targets do
		local g = groups[name]
		if g then
			g.Volume += (target - g.Volume) * k
		end
	end
	master.Volume = settings.master
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function doorSound(cue)
	local door = MapLayout.doorById(cue.door)
	local at = door and toV3(MapLayout.doorPosition(door)) + Vector3.new(0, 4, 0) or nil
	if cue.cue == "DoorForced" then
		AudioController.play("DoorForced", { at = at })
	elseif cue.kind == "freight" then
		AudioController.play("FreightDoor", { at = at })
	else
		AudioController.play(cue.open and "DoorOpen" or "DoorClose", { at = at })
	end
end

local function onCue(cue)
	local name = cue.cue
	local me = Players.LocalPlayer.UserId
	if name == "DoorMoved" or name == "DoorForced" then
		doorSound(cue)
		return
	elseif name == "Eliminated" then
		AudioController.play(cue.userId == me and "Eliminated" or "StaticShort")
		return
	elseif name == "Extracted" then
		AudioController.play("VanDoorSlam")
		return
	elseif name == "LocalSilence" then
		silencedUntil = os.clock() + (cue.duration or 5)
		return
	elseif name == "EditorShadow" and cue.userId ~= me then
		return
	elseif name == "GeneratorPrime" then
		AudioController.play("GeneratorPrime", { at = generatorPosition() })
		return
	elseif name == "PowerOn" then
		AudioController.play("GeneratorStart", { at = generatorPosition() })
	end
	local sound = Audio.Cues[name]
	if sound then
		-- The editor hears their own commit at once; the server's echo is skipped.
		AudioController.play(sound, { dedupe = 1.5 })
	end
end

local function onSubtitle(line)
	if line.kind == "radio" then
		if line.caller then
			AudioController.play("PhoneRing", { dedupe = 20 })
		end
		AudioController.play("RadioIn", { dedupe = 0.3 })
		local duration = 2.2 + #(line.text or "") * 0.045
		radioUntil = os.clock() + duration
		setLayer("RadioBed", 1, 6, 6)
		task.delay(duration, function()
			if os.clock() >= radioUntil - 0.05 then
				setLayer("RadioBed", 0, 6, 6)
				AudioController.play("RadioOut", { dedupe = 0.3 })
			end
		end)
	elseif line.kind == "cue" then
		local text = string.upper(line.text or "")
		for _, entry in Audio.SubtitleSounds do
			if string.find(text, entry[1], 1, true) then
				local model = presenter()
				local opts = model and { parent = model.PrimaryPart } or { volume = 0.6 }
				repeatPlay(entry[2], entry[3], 0.75, opts)
				break
			end
		end
	end
end

-- What changed between two mission snapshots.
local lastMission = nil
local tapesFound = 0
local function onMission(m)
	local before = lastMission
	local wasIn = before ~= nil
	local nowIn = m ~= nil and State.inMission()
	if nowIn and not wasIn then
		tapesFound = 0
		AudioController.play("Deploy")
	end
	if m and before and nowIn then
		local caseDef = State.caseDef()
		for itemId in m.inventory or {} do
			if not (before.inventory and before.inventory[itemId]) then
				local item = caseDef and caseDef.items[itemId]
				local kind = item and item.kind
				if kind == "Tape" then
					AudioController.play("PickupTape")
					tapesFound += 1
					if tapesFound == 1 then
						task.delay(0.35, AudioController.play, "StingDiscovery")
					end
				elseif kind == "Key" then
					AudioController.play("PickupKey")
				else
					AudioController.play("PickupMetal")
				end
			end
		end
		for relayId, on in m.relays or {} do
			if before.relays and before.relays[relayId] ~= on then
				local relay = MapLayout.Relays[relayId]
				AudioController.play("Relay", { at = relay and toV3(relay.pos) + Vector3.new(0, 4, 0) or nil })
			end
		end
	end
	lastMission = nowIn and m or nil
end

local function onReport(payload)
	local report = payload and payload.report
	if not report then
		return
	end
	local success = report.result == "Success" or report.result == "Partial"
	AudioController.play(success and "StingSuccess" or "StingFail")
	local personal = payload.personal
	if personal and (personal.master or personal.clearance or #(personal.evidence or {}) > 0 or #(personal.challenges or {}) > 0) then
		task.delay(2.2, AudioController.play, "Unlock")
	end
end

local function onUI(name, open)
	if name == "menu" then
		AudioController.play(open and "MenuOpen" or "MenuClose", { dedupe = 0.2 })
	elseif name == "deck" then
		AudioController.play(open and "DeckOpen" or "DeckClose", { dedupe = 0.2 })
		setLayer("DeckHum", open and 1 or 0, 2, 3)
	elseif name == "tutorial" and open then
		AudioController.play("TutorialPage")
	elseif name == "report" and open then
		AudioController.play("ReportStamp")
		repeatPlay("ReportKey", 8, 0.07, nil)
	end
end

-- Lobby: a stamp when you ready up, a tick each second of the countdown.
local wasReady = false
local lastCount = nil
local function onParty(party)
	local me = nil
	for _, member in (party and party.members) or {} do
		if member.userId == Players.LocalPlayer.UserId then
			me = member
		end
	end
	local ready = me ~= nil and me.ready == true
	if ready and not wasReady then
		AudioController.play("Ready")
	end
	wasReady = ready
end

local function stepCountdown()
	local party = State.party
	if not party or not party.countdownEnd or State.inMission() then
		lastCount = nil
		return
	end
	local remaining = math.ceil(party.countdownEnd - State.now())
	if remaining > 0 and remaining ~= lastCount then
		lastCount = remaining
		AudioController.play("Countdown")
	end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function AudioController.init()
	master = Instance.new("SoundGroup")
	master.Name = "DeadAirMaster"
	master.Parent = SoundService
	for _, name in Audio.Groups do
		local g = Instance.new("SoundGroup")
		g.Name = name
		g.Volume = 0
		g.Parent = master
		groups[name] = g
	end
	emitterFolder = Instance.new("Folder")
	emitterFolder.Name = "DeadAirSounds"
	emitterFolder.Parent = Workspace

	-- Every controller plays through the Sound bridge.
	Sound.play = AudioController.play
	Sound.loop = function(name, on)
		setLayer(name, on and 1 or 0, 8, 4)
	end

	State.cue:Connect(onCue)
	State.subtitle:Connect(onSubtitle)
	State.notify:Connect(function()
		AudioController.play("UINotify", { dedupe = 0.15 })
	end)
	State.missionChanged:Connect(onMission)
	State.reportReceived:Connect(onReport)
	State.uiChanged:Connect(onUI)
	State.partyChanged:Connect(onParty)

	local function watchCharacter(character)
		task.spawn(muteDefaultSteps, character)
	end
	local function watchPlayer(player)
		if player.Character then
			watchCharacter(player.Character)
		end
		player.CharacterAdded:Connect(watchCharacter)
	end
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)

	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		mixGroups(dt)
		stepLayers(dt)
		stepPresenter()
		stepOthers()
		accum += dt
		if accum >= 0.1 then
			accum = 0
			directMusic()
			directAmbience()
			directMachines()
			stepHeart()
			stepCountdown()
		end
	end)
end

return AudioController
