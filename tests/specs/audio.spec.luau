-- Audio: every sound the code asks for exists in the banks, every server cue
-- is heard, and a playthrough on the real client produces the right sounds,
-- music and mix.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local game = roblox.Instance.new("DataModel")
local h = Harness.new({ game = game })
local Shared = h.mount("Shared", "src/shared")
local Audio = h.require(Shared.Config.Audio)
local AudioBank = h.require(Shared.Config.AudioBank)
local AudioAssets = h.require(Shared.Config.AudioAssets)

local function sourceFiles(dir, out)
	out = out or {}
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			sourceFiles(path, out)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(out, path)
		end
	end
	return out
end

local function allSource()
	local list = {}
	for _, path in sourceFiles("src") do
		table.insert(list, { path = path, text = fs.readFile(path) })
	end
	return list
end

local function exists(name)
	return AudioBank.Sounds[name] ~= nil
end

test("every sound named in the code exists in the audio banks", function()
	local missing = {}
	local patterns = {
		'Sound%.play%("([%w_]+)"',
		'AudioController%.play%("([%w_]+)"',
		'repeatPlay%("([%w_]+)"',
		'Sound%.loop%("([%w_]+)"',
		'setEmitter%("([%w_]+)"',
		'setLayer%("([%w_]+)"',
		'"ClickSound", "([%w_]+)"',
		'task%.delay%([%d%.]+, AudioController%.play, "([%w_]+)"',
		'task%.delay%([%d%.]+, Sound%.play, "([%w_]+)"',
	}
	local seen = 0
	for _, file in allSource() do
		for _, pattern in patterns do
			for name in string.gmatch(file.text, pattern) do
				seen += 1
				if not exists(name) then
					table.insert(missing, file.path .. ": " .. name)
				end
			end
		end
	end
	expect(seen > 40).toBeTruthy()
	-- Sounds chosen through tables.
	for cue, name in Audio.Cues do
		if not exists(name) then
			table.insert(missing, "Audio.Cues." .. cue .. " -> " .. name)
		end
	end
	for key, name in Audio.Music do
		if not exists(name) then
			table.insert(missing, "Audio.Music." .. key .. " -> " .. name)
		end
	end
	for _, entry in Audio.SubtitleSounds do
		if not exists(entry[2]) then
			table.insert(missing, "SubtitleSounds -> " .. entry[2])
		end
	end
	for _, kind in Audio.StepKinds do
		for i = 1, Audio.StepVariants do
			local name = string.format("Step_%s_%d", kind, i)
			if not exists(name) then
				table.insert(missing, name)
			end
		end
	end
	for name in Audio.Sounds do
		if not exists(name) then
			table.insert(missing, "Audio.Sounds." .. name .. " is not in a bank")
		end
	end
	if #missing > 0 then
		error("missing sounds:\n  " .. table.concat(missing, "\n  "))
	end
end)

test("every bank sound has a mix setting and fits inside its bank", function()
	local problems = {}
	for name, region in AudioBank.Sounds do
		local bank = AudioBank.Banks[region.bank]
		if not bank then
			table.insert(problems, name .. " is in unknown bank " .. region.bank)
		elseif region.start < 0 or region.start + region.length > bank.duration + 1e-3 then
			table.insert(problems, name .. " runs past the end of " .. region.bank)
		end
		if string.sub(name, 1, 5) ~= "Step_" and not Audio.Sounds[name] then
			table.insert(problems, name .. " has no entry in Audio.Sounds")
		end
		local def = Audio.def(name)
		if def.group and not table.find(Audio.Groups, def.group) then
			table.insert(problems, name .. " uses unknown group " .. def.group)
		end
	end
	for _, name in Audio.Music do
		expect(AudioBank.Sounds[name].loop).toBe(true)
	end
	for bankName in AudioBank.Banks do
		expect(AudioAssets.Banks[bankName] ~= nil).toBeTruthy()
	end
	if #problems > 0 then
		error(table.concat(problems, "\n  "))
	end
end)

test("every cue the server sends is heard (or deliberately silent)", function()
	-- UI-only cues open screens; their screens make the sounds.
	local silent = { OpenDeck = true, OpenKeypad = true, OpenMenu = true, OpenTutorial = true, ReplayBriefing = true }
	local special = { DoorMoved = true, DoorForced = true, Eliminated = true, Extracted = true, LocalSilence = true, GeneratorPrime = true, PowerOn = true }
	local cues = {}
	for _, file in allSource() do
		for name in string.gmatch(file.text, 'cue = "([%w_]+)"') do
			cues[name] = true
		end
	end
	local deaf = {}
	for name in cues do
		if not silent[name] and not special[name] and not Audio.Cues[name] then
			table.insert(deaf, name)
		end
	end
	table.sort(deaf)
	if #deaf > 0 then
		error("cues with no sound: " .. table.concat(deaf, ", "))
	end
end)

---------------------------------------------------------------------------
-- Playthrough on the real client
---------------------------------------------------------------------------

local function boot()
	local engine = Engine.new()
	local server = Harness.new({ game = engine.game, globals = engine:globals("server") })
	local client = Harness.new({ game = engine.game, globals = engine:globals("client") })
	engine.sharedMounts.server = server.mount("Shared", "src/shared")
	engine.sharedMounts.client = client.mount("Shared", "src/shared")
	-- Pretend the banks are uploaded so real Sound instances are made.
	local assets = client.require(engine.sharedMounts.client.Config.AudioAssets)
	for bank in assets.Banks do
		assets.Banks[bank] = "rbxassetid://1000" .. bank
	end
	local serverRoot = server.mount("Server", "src/server")
	local clientRoot = client.mount("Client", "src/client")
	engine:run("server", function()
		server.run(serverRoot.Main)
	end)
	engine:advance(0.5)
	local player = engine:addPlayer(101, "Ana", true)
	engine:advance(2)
	engine:run("client", function()
		client.run(clientRoot.Main)
	end)
	engine:advance(2)
	return {
		engine = engine,
		server = server,
		client = client,
		player = player,
		State = client.require(clientRoot.State),
		Audio = client.require(clientRoot.Controllers.AudioController),
		serverRoot = serverRoot,
		clientRoot = clientRoot,
	}
end

local function heard(env, name)
	for _, n in env.Audio.history do
		if n == name then
			return true
		end
	end
	return false
end

local function expectHeard(env, ...)
	local missing = {}
	for _, name in { ... } do
		if not heard(env, name) then
			table.insert(missing, name)
		end
	end
	if #missing > 0 then
		error("did not hear: " .. table.concat(missing, ", ") .. "\nheard: " .. table.concat(env.Audio.history, ", "))
	end
end

local function clearHistory(env)
	table.clear(env.Audio.history)
end

local function assertClean(env, label)
	local e = env.engine
	if #e.errors > 0 then
		error(label .. ": runtime errors\n" .. table.concat(e.errors, "\n----\n"))
	end
	if #e.warnings > 0 then
		error(label .. ": warnings\n" .. table.concat(e.warnings, "\n"))
	end
end

local function soundsNamed(env, name)
	local list = {}
	for _, d in env.engine.realGame:GetDescendants() do
		if d.ClassName == "Sound" and d.Name == name then
			table.insert(list, d)
		end
	end
	return list
end

test("lobby: menu music, office ambience, interface sounds, ready and countdown", function()
	local env = boot()
	local e = env.engine
	e:advance(1)
	expect(env.Audio.track).toBe("Menu")
	local menu = soundsNamed(env, "MusicMenu")
	expect(#menu).toBe(1)
	-- The sound plays exactly its slice of the music bank, looping.
	local region = AudioBank.Sounds.MusicMenu
	expect(menu[1].PlaybackRegionsEnabled).toBe(true)
	expect(menu[1].PlaybackRegion.Min).toBeNear(region.start, 1e-3)
	expect(menu[1].LoopRegion.Max).toBeNear(region.start + region.length, 1e-3)
	expect(menu[1].Looped).toBe(true)
	expect(string.find(menu[1].SoundId, "Music", 1, true) ~= nil).toBeTruthy()
	expect(#soundsNamed(env, "AmbHQ")).toBe(1)

	-- Clicking a menu button clicks; a disabled one buzzes.
	local gui = e.realOf[env.player].PlayerGui
	local function button(text)
		for _, d in gui:GetDescendants() do
			if d.ClassName == "TextButton" and d.Text == text then
				return d
			end
		end
		error("no button " .. text)
	end
	local function click(b)
		e:spawnOnSide("client", function()
			e:signalFor(b, "Activated"):Fire()
		end)
		e:advance(0.2)
	end
	-- Close the first-run tutorial (its pages turn with a sound).
	click(button("NEXT"))
	expectHeard(env, "TutorialPage")
	click(button("SKIP TUTORIAL"))
	click(button("SETTINGS"))
	expectHeard(env, "UIClick")
	click(button("SUBTITLES: ON"))
	expectHeard(env, "UIToggle")

	-- Leaving the menu: field office music.
	e:run("client", function()
		env.client.require(env.clientRoot.Controllers.MenuController).close()
	end)
	e:advance(1)
	expect(env.Audio.track).toBe("Lobby")
	expectHeard(env, "MenuClose")

	-- Ready up: a stamp, then a tick a second until the team deploys.
	clearHistory(env)
	e:run("client", function()
		env.State.action("SetReady", { ready = true })
	end)
	e:advance(3)
	expectHeard(env, "Ready", "Countdown")
	e:advance(5)
	expectHeard(env, "Deploy")
	expect(env.Audio.track).toBe("Briefing")
	assertClean(env, "lobby audio")
end)

test("in the station: ambience by light, radio, doors, pickups, the deck, machines and the hunt", function()
	local env = boot()
	local e = env.engine
	e:run("client", function()
		env.State.action("SetReady", { ready = true })
	end)
	e:advance(8)
	expect(env.State.inMission()).toBe(true)
	e:advance(2)
	-- The briefing comes over the radio.
	expectHeard(env, "RadioIn")
	expect(env.Audio.layerLevel("AmbStation") + env.Audio.layerLevel("AmbDark") > 0).toBeTruthy()
	expect(env.Audio.layerLevel("AmbHQ")).toBe(0)

	local start = env.State.mission.briefingEnd
	e:advance(start - e.clock + 1)
	expect(env.State.mission.phase).toBe("Active")
	e:advance(1)
	expect(env.Audio.track).toBe("Explore")

	-- A door, opened on the server, is heard by the client where it is.
	clearHistory(env)
	local WorldService = env.server.require(env.serverRoot.Services.WorldService)
	local doorId
	for id, entry in WorldService.doors do
		if entry.kind == "door" and not entry.locked and not entry.open and #entry.panels > 0 then
			doorId = id
			break
		end
	end
	e:run("server", function()
		WorldService.openDoor(doorId)
	end)
	e:advance(0.3)
	expectHeard(env, "DoorOpen")
	e:run("server", function()
		WorldService.closeDoor(doorId)
	end)
	e:advance(0.3)
	expectHeard(env, "DoorClose")

	-- Picking up the first tape: the pickup and the discovery sting.
	local station = e.realGame:GetService("Workspace").Station04
	local anchor
	for _, d in station:GetDescendants() do
		if d.Name == "ITEM_TAPE01" then
			anchor = d
		end
	end
	local prompt = anchor:FindFirstChildOfClass("ProximityPrompt")
	local pos = anchor.CFrame.Position
	e:teleport(env.player, roblox.Vector3.new(pos.X + 1.5, 3, pos.Z + 1.5))
	e:signalFor(prompt, "Triggered"):Fire(env.player)
	e:advance(1)
	expectHeard(env, "PickupTape", "StingDiscovery")

	-- The deck: power-on, hum while open, a tape going in, the channel changing.
	clearHistory(env)
	local Deck = env.client.require(env.clientRoot.Controllers.DeckController)
	e:run("client", function()
		Deck.open({ mode = "archive", caseId = "case01", tapeId = "TAPE01" })
	end)
	e:advance(0.5)
	expectHeard(env, "DeckOpen")
	expect(env.Audio.layerLevel("DeckHum")).toBe(1)
	e:run("client", function()
		Deck.selectTape("TAPE01")
		Deck.selectTape("TAPE02")
		Deck.setPlaying(true)
		Deck.step(1 / 24)
		Deck.selectCamera("CAM05")
	end)
	e:advance(1)
	expectHeard(env, "TapeEject", "TapeInsert", "DeckPlay", "FrameStep", "ChannelSwitch")
	e:run("client", function()
		Deck.close()
	end)
	e:advance(0.5)
	expectHeard(env, "DeckClose")
	expect(env.Audio.layerLevel("DeckHum")).toBe(0)

	-- The generator, once running, hums where it stands.
	e:run("server", function()
		local m = env.server.require(env.serverRoot.Services.MissionService).mission
		m.flags.generator_restored = true
		m:_dirty()
	end)
	e:advance(1.5)
	expect(env.Audio.emitterActive("GeneratorLoop")).toBe(true)

	-- A hunting Presenter nearby: the hunt music, its static face, a heartbeat.
	clearHistory(env)
	local character = e.realOf[env.player].Character
	local root = character.HumanoidRootPart
	local model = roblox.Instance.new("Model")
	model.Name = "Presenter"
	local body = roblox.Instance.new("Part")
	body.Name = "Root"
	body.CFrame = roblox.CFrame.new(root.CFrame.Position + roblox.Vector3.new(6, 0, 0))
	body.Parent = model
	model.PrimaryPart = body
	model:SetAttribute("State", "Hunting")
	model.Parent = e.realGame:GetService("Workspace")
	local camera = e.realCamera
	camera.CameraType = roblox.Enum.CameraType.Custom
	camera.CameraSubject = character:FindFirstChildOfClass("Humanoid")
	e:advance(4)
	expect(env.Audio.track).toBe("Hunt")
	expect(env.Audio.emitterActive("PresenterStatic")).toBe(true)
	expect(env.Audio.layerLevel("PresenterNear") > 0.5).toBeTruthy()
	expectHeard(env, "Heartbeat")
	-- It walks: heavy footsteps where it is.
	for i = 1, 6 do
		body.CFrame = body.CFrame + roblox.Vector3.new(1, 0, 0)
		e:advance(0.1)
	end
	expectHeard(env, "PresenterStep")
	model:Destroy()
	e:advance(1)
	expect(env.Audio.track).toBe("Explore")
	assertClean(env, "station audio")
end)

test("the mix follows the settings, ducks under radio, and goes silent for the false safety", function()
	local env = boot()
	local e = env.engine
	e:advance(2)
	local master = e.realGame:GetService("SoundService").DeadAirMaster
	local music = master.Music
	expect(music.Volume).toBeNear(env.State.settings.music, 0.05)
	e:run("client", function()
		local copy = table.clone(env.State.settings)
		copy.music = 0.2
		copy.master = 0.5
		env.State.applySettings(copy)
	end)
	e:advance(2)
	expect(music.Volume).toBeNear(0.2, 0.02)
	expect(master.Volume).toBeNear(0.5, 1e-3)
	-- A radio line ducks the music.
	e:run("client", function()
		env.State.subtitle:Fire({ kind = "radio", text = "Investigators, this is Division. Hold position.", stamp = "00:00:01", sourceId = "NBRD-HQ", channel = 2 })
	end)
	e:advance(1)
	expect(music.Volume < 0.15).toBeTruthy()
	expectHeard(env, "RadioIn")
	e:advance(6)
	expectHeard(env, "RadioOut")
	expect(music.Volume).toBeNear(0.2, 0.02)
	-- The false safety: everything drops out except the end-of-transmission tone.
	e:run("client", function()
		env.State.cue:Fire({ cue = "LocalSilence", duration = 4 })
	end)
	e:advance(2)
	expect(music.Volume < 0.01).toBeTruthy()
	expect(master.Effects.Volume < 0.01).toBeTruthy()
	expect(master.Cinematic.Volume > 0.5).toBeTruthy()
	e:advance(4)
	expect(music.Volume).toBeNear(0.2, 0.02)
	assertClean(env, "mix")
end)

test("footsteps follow the floor and the default running sound is replaced", function()
	local env = boot()
	local e = env.engine
	local character = e.realOf[env.player].Character
	local root = character.HumanoidRootPart
	-- Roblox's default running sound (made by its character sound script).
	local running = roblox.Instance.new("Sound")
	running.Name = "Running"
	running.Volume = 0.65
	e:run("client", function()
		e:wrap(running).Parent = e:wrap(root)
	end)
	e:advance(0.5)
	expect(running.Volume).toBe(0)
	clearHistory(env)
	e:run("client", function()
		env.Audio.footstep(false)
	end)
	-- FloorMaterial is Concrete in the test engine.
	local step = env.Audio.history[#env.Audio.history]
	expect(string.sub(step, 1, 14)).toBe("Step_concrete_")
	assertClean(env, "footsteps")
end)
