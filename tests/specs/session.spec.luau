-- Integration: the real server and client scripts running together on the mock
-- engine, driven through the same remotes and prompts a player would use.


local function boot()
	local engine = Engine.new()
	local server = Harness.new({ game = engine.game, globals = engine:globals("server") })
	local client = Harness.new({ game = engine.game, globals = engine:globals("client") })
	engine.sharedMounts.server = server.mount("Shared", "src/shared")
	engine.sharedMounts.client = client.mount("Shared", "src/shared")
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
		serverServices = serverRoot.Services,
		clientRoot = clientRoot,
		serverRoot = serverRoot,
	}
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

test("server and client boot cleanly and the player reaches the field office", function()
	local env = boot()
	assertClean(env, "boot")
	local ws = env.engine.realGame:GetService("Workspace")
	expect(ws:FindFirstChild("Station04") ~= nil).toBeTruthy()
	expect(ws:FindFirstChild("FieldOffice") ~= nil).toBeTruthy()
	local character = env.engine.realOf[env.player].Character
	expect(character ~= nil).toBeTruthy()
	local hq = env.engine.realGame:GetService("Workspace").FieldOffice.HQSpawn.CFrame.Position
	expect(math.abs(character.PrimaryPart.CFrame.Position.Z - hq.Z) < 5).toBeTruthy()
	local gui = env.engine.realOf[env.player].PlayerGui
	for _, name in { "DeadAirHUD", "DeadAirDeck", "DeadAirMenu", "DeadAirReport", "DeadAirOverlay", "DeadAirKeypad", "DeadAirSpectate" } do
		if not gui:FindFirstChild(name) then
			error("missing " .. name)
		end
	end
	expect(env.State.profile ~= nil).toBeTruthy()
	expect(env.State.party ~= nil).toBeTruthy()
	expect(gui.DeadAirMenu.Enabled).toBe(true)
end)

---------------------------------------------------------------------------
-- Helpers for driving the game like a player
---------------------------------------------------------------------------

local function ws(env)
	return env.engine.realGame:GetService("Workspace")
end

local function anchorFor(env, id)
	local station = ws(env).Station04
	local a = station.Anchors:FindFirstChild(id)
	if a then
		return a
	end
	for _, d in station.Items:GetDescendants() do
		if d.Name == id then
			return d
		end
	end
	error("no anchor " .. id)
end

local function triggerPrompt(env, part)
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		error("no prompt on " .. part:GetFullName())
	end
	local pos = part.CFrame.Position
	env.engine:teleport(env.player, roblox.Vector3.new(pos.X + 1.5, 3, pos.Z + 1.5))
	env.engine:signalFor(prompt, "Triggered"):Fire(env.player)
	env.engine:advance(0.3)
	return prompt
end

local function interact(env, id)
	return triggerPrompt(env, anchorFor(env, id))
end

local function guiButton(env, screenName, predicate)
	local gui = env.engine.realOf[env.player].PlayerGui[screenName]
	for _, d in gui:GetDescendants() do
		if d.ClassName == "TextButton" and predicate(d.Text, d) then
			return d
		end
	end
	return nil
end

local function click(env, button)
	if not button then
		error("button not found")
	end
	env.engine:spawnOnSide("client", function()
		env.engine:signalFor(button, "Activated"):Fire()
	end)
	env.engine:advance(0.3)
end

local function mission(env)
	return env.State.mission
end

local function clientDo(env, fn)
	env.engine:run("client", fn)
	env.engine:advance(0.3)
end

local function editAtDeck(env, deckInteractId, eventId, stateLabel)
	interact(env, deckInteractId)
	env.engine:advance(0.5)
	local DeckController = env.client.require(env.clientRoot.Controllers.DeckController)
	expect(DeckController.isOpen()).toBe(true)
	clientDo(env, function()
		DeckController.selectEvent(eventId)
	end)
	env.engine:advance(0.6)
	click(env, guiButton(env, "DeadAirDeck", function(text)
		return text == "> " .. stateLabel
	end))
	click(env, guiButton(env, "DeadAirDeck", function(text)
		return string.sub(text, 1, 11) == "COMMIT EDIT"
	end))
	env.engine:advance(0.5)
	click(env, guiButton(env, "DeadAirDeck", function(text)
		return text == "CLOSE"
	end))
	expect(DeckController.isOpen()).toBe(false)
end

local function serverMission(env)
	return env.server.require(env.serverServices.MissionService).mission
end

test("a full Case 01 run through the real server, client, UI and remotes", function()
	local env = boot()
	local e = env.engine

	-- Ready up in the field office; the team deploys after the countdown.
	clientDo(env, function()
		env.State.action("SetReady", { ready = true })
	end)
	expect(env.State.party.countdownEnd ~= nil).toBeTruthy()
	e:advance(7)
	expect(mission(env) ~= nil).toBeTruthy()
	expect(mission(env).phase).toBe("Briefing")
	expect(e.realOf[env.player].PlayerGui.DeadAirMenu.Enabled).toBe(false)
	assertClean(env, "deploy")

	e:advance(41)
	expect(mission(env).phase).toBe("Active")

	-- TAPE 01 and the reception VCR edit (keep the lights on).
	interact(env, "ITEM_TAPE01")
	expect(mission(env).inventory.TAPE01).toBe("Ana")
	editAtDeck(env, "I_DECK_LOBBY", "lobby_lights", "LIGHTS HOLD")
	expect(mission(env).charges).toBe(2)
	expect(mission(env).timeline.events.presenter_entry.state).toBe("SOUTH_HALL")
	assertClean(env, "first edit")

	-- The predicted Presenter route plays out.
	local start = mission(env).broadcastStart
	e:advance(start + 160 - e.clock)
	local presenter = ws(env):FindFirstChild("Presenter")
	expect(presenter ~= nil).toBeTruthy()
	expect(presenter:GetAttribute("State")).toBe("Displaced")
	assertClean(env, "presenter entry")

	-- Restore power.
	interact(env, "I_GENERATOR")
	interact(env, "I_GENERATOR")
	expect(mission(env).flags.generator_restored).toBe(true)
	e:advance(5)
	local station = ws(env).Station04
	expect(station.Rooms.WestCorridor:GetAttribute("LightMode")).toBe("on")
	expect(station.Doors.D_EC_Arch:GetAttribute("Locked")).toBe(false)

	-- The keypad: read Division's Channel 2 code from the radio log and type it.
	local code
	for _, entry in mission(env).radioLog do
		if entry.channel == 2 and string.find(entry.text, "Cage code", 1, true) then
			code = string.match(entry.text, "(%d%d%d%d)")
		end
	end
	expect(code ~= nil).toBeTruthy()
	interact(env, "I_CAGE")
	expect(e.realOf[env.player].PlayerGui.DeadAirKeypad.Enabled).toBe(true)
	for i = 1, #code do
		local digit = string.sub(code, i, i)
		click(env, guiButton(env, "DeadAirKeypad", function(text)
			return text == digit
		end))
	end
	click(env, guiButton(env, "DeadAirKeypad", function(text)
		return text == "OK"
	end))
	expect(mission(env).inventory.VALVE ~= nil).toBeTruthy()
	assertClean(env, "keypad")

	interact(env, "ITEM_TAPE02")
	interact(env, "ITEM_COIL")
	interact(env, "ITEM_TAPE03")
	expect(mission(env).inventory.TAPE03 ~= nil).toBeTruthy()

	-- Leave the corridor lights alone; the patrol trips the east relay; reset it.
	local power = mission(env).timeline.anchors.generator_restored
	e:advance(power + 98 - e.clock)
	expect(mission(env).relays.EAST).toBe(false)
	interact(env, "I_RELAY_EAST")
	expect(mission(env).relays.EAST).toBe(true)
	assertClean(env, "patrol")

	-- Wait out the patrol, then the Loop.
	e:advance(power + 250 - e.clock)
	interact(env, "I_RACK")
	expect(mission(env).loop.active).toBe(true)
	local odd = mission(env).loop.odd
	local sm = serverMission(env)
	for _ = 1, 80 do
		local _, isOdd = sm:loopCycle(e.clock)
		if isOdd then
			break
		end
		e:advance(0.5)
	end
	e:advance(0.5)
	interact(env, odd)
	expect(mission(env).loop.solved).toBe(true)
	interact(env, "I_RACK")
	expect(mission(env).flags.board_recovered).toBe(true)
	interact(env, "ITEM_KEY")
	interact(env, "ITEM_TAPE04")
	assertClean(env, "loop")

	-- Ride out the ambush and the control room rewind.
	local board = mission(env).timeline.anchors.board_recovered
	e:advance(board + 110 - e.clock)
	expect(station.Doors.D_TH_Trans:GetAttribute("Locked")).toBe(false)

	-- Install the components; edit the freight door open at master control.
	interact(env, "I_SOCKET_COIL")
	interact(env, "I_SOCKET_VALVE")
	interact(env, "I_SOCKET_BOARD")
	expect(mission(env).flags.transmitter_armed).toBe(true)
	editAtDeck(env, "I_DECK_TRANS", "freight_door", "DOOR CYCLES OPEN")
	expect(mission(env).charges).toBe(1)
	e:advance(33)
	expect(mission(env).phase).toBe("ExtractionAvailable")
	expect(station.Doors.D_Freight:GetAttribute("Open")).toBe(true)
	assertClean(env, "transmitter")

	-- Wait for the dock patrol to pass, then board the van.
	e:advance(50)
	interact(env, "I_VAN")
	e:advance(1)
	expect(env.State.report ~= nil).toBeTruthy()
	local report = env.State.report.report
	expect(report.result).toBe("Success")
	expect(report.componentsCount).toBe(3)
	expect(report.editsMade).toBe(2)
	expect(e.realOf[env.player].PlayerGui.DeadAirReport.Enabled).toBe(true)
	local personal = env.State.report.personal
	expect(personal.master).toBe("MASTER_01")
	expect(personal.clearance).toBe(2)
	expect(personal.credits > 0).toBeTruthy()

	-- Back to the field office.
	e:advance(6)
	click(env, guiButton(env, "DeadAirReport", function(text)
		return text == "RETURN TO THE FIELD OFFICE"
	end))
	e:advance(3)
	expect(env.State.mission).toBe(nil)
	expect(env.State.profile.clearance).toBe(2)
	expect(env.State.profile.masters.MASTER_01).toBe(true)
	local character = e.realOf[env.player].Character
	expect(character.PrimaryPart.CFrame.Position.Z > 200).toBeTruthy()
	assertClean(env, "return")

	-- Progress was written to the (simulated) DataStore.
	e:advance(130)
	local store = e.dataStores.DeadAir_Profiles_v1
	expect(store ~= nil).toBeTruthy()
	expect(store.data.u_101.clearance).toBe(2)
	expect(store.data.u_101.cases.case01.completed).toBe(1)
	assertClean(env, "save")
end)

local function deploySolo(env)
	clientDo(env, function()
		env.State.action("SetReady", { ready = true })
	end)
	env.engine:advance(7)
	env.engine:advance(41)
	expect(mission(env).phase).toBe("Active")
end

test("getting caught: off-air, spectating, a stored re-entry, and leaving the case", function()
	local env = boot()
	local e = env.engine
	-- Give the player a stored re-entry, as if bought earlier.
	local DataService = env.server.require(env.serverServices.DataService)
	DataService.get(env.player).storedRevives = 1
	deploySolo(env)
	interact(env, "ITEM_TAPE01")
	-- Stand in reception with clear line of sight as it walks in.
	e.losBlocked = false
	local start = mission(env).broadcastStart
	e:advance(start + 154 - e.clock)
	e:teleport(env.player, roblox.Vector3.new(0, 3, 64))
	for _ = 1, 200 do
		e:advance(0.2)
		local presenter = ws(env):FindFirstChild("Presenter")
		local character = e.realOf[env.player].Character
		if presenter and character then
			-- Walk into it (players get caught by standing their ground).
			e:teleport(env.player, presenter.PrimaryPart.CFrame.Position + roblox.Vector3.new(1, 0, 1))
		end
		if env.State.me() and env.State.me().status == "Eliminated" then
			break
		end
	end
	expect(env.State.me().status).toBe("Eliminated")
	e:advance(2)
	expect(e.realOf[env.player].Character).toBe(nil)
	local spectate = e.realOf[env.player].PlayerGui.DeadAirSpectate
	expect(spectate.Enabled).toBe(true)
	-- The optional re-entry uses the stored one.
	local button = guiButton(env, "DeadAirSpectate", function(text)
		return string.find(text, "RE-ENTRY", 1, true) ~= nil
	end)
	click(env, button)
	e:advance(4)
	expect(env.State.me().status).toBe("Alive")
	expect(e.realOf[env.player].Character ~= nil).toBeTruthy()
	expect(DataService.get(env.player).storedRevives).toBe(0)
	expect(mission(env).charges).toBe(3)
	e.losBlocked = true
	-- Leave the case from the pause menu.
	clientDo(env, function()
		env.State.action("LeaveCase")
	end)
	e:advance(3)
	expect(env.State.mission).toBe(nil)
	assertClean(env, "caught")
end)

test("the Caller's code sets off the alarm; the menu pages and archive replay all work", function()
	local env = boot()
	local e = env.engine
	-- Every field office page builds without errors.
	local Menu = env.client.require(env.clientRoot.Controllers.MenuController)
	for _, page in { "Home", "Cases", "Archive", "Equipment", "Settings", "Store", "Credits" } do
		clientDo(env, function()
			Menu.show(page)
		end)
	end
	-- Buy and equip a cosmetic with credits.
	local DataService = env.server.require(env.serverServices.DataService)
	DataService.get(env.player).credits = 500
	clientDo(env, function()
		local r1 = env.State.request("BuyCosmetic", { item = "uniform_field" })
		local r2 = env.State.request("SetCosmetic", { item = "uniform_field" })
		local r3 = env.State.request("SetEquipment", { equipment = "Analyser" })
		local r4 = env.State.request("SaveSettings", { settings = { subtitles = false, sensitivity = 9 } })
		assert(r1.ok and r2.ok and r3.ok and r4.ok, "store/equipment requests failed")
	end)
	e:advance(1)
	local profile = DataService.get(env.player)
	expect(profile.credits).toBe(350)
	expect(profile.cosmetics.equipped.uniform).toBe("uniform_field")
	expect(profile.equipment).toBe("Analyser")
	expect(profile.settings.sensitivity).toBe(3) -- clamped
	expect(profile.settings.subtitles).toBe(false)

	deploySolo(env)
	interact(env, "I_GENERATOR")
	interact(env, "I_GENERATOR")
	e:advance(16)
	local fake
	for _, entry in mission(env).radioLog do
		if entry.channel == 0 and string.find(entry.text, "cage code", 1, true) then
			fake = string.match(entry.text, "(%d%d%d%d)")
		end
	end
	expect(fake ~= nil).toBeTruthy()
	interact(env, "I_CAGE")
	local result
	clientDo(env, function()
		result = env.State.request("SubmitCode", { code = fake })
	end)
	expect(result.ok).toBe(false)
	expect(env.server.require(env.serverServices.MissionService).mission.stats.callerFooled).toBe(true)
	-- The pause menu and the analyser tool run in a case too.
	clientDo(env, function()
		Menu.open("Pause")
		Menu.close()
	end)
	local Tools = env.client.require(env.clientRoot.Controllers.ToolController)
	clientDo(env, function()
		Tools.toggle()
	end)
	e:advance(1)
	clientDo(env, function()
		Tools.toggle()
	end)
	assertClean(env, "caller")

	-- Leave, then replay a recovered tape in the archive.
	interact(env, "ITEM_TAPE01")
	clientDo(env, function()
		env.State.action("LeaveCase")
	end)
	e:advance(3)
	expect(DataService.get(env.player).tapes.TAPE01).toBe(true)
	local Deck = env.client.require(env.clientRoot.Controllers.DeckController)
	clientDo(env, function()
		Deck.open({ mode = "archive", caseId = "case01", tapeId = "TAPE01" })
	end)
	e:advance(1)
	clientDo(env, function()
		Deck.seek(12.4)
	end)
	e:advance(0.2)
	click(env, guiButton(env, "DeadAirDeck", function(text)
		return text == "MARK FRAME"
	end))
	e:advance(0.5)
	expect(DataService.get(env.player).frames.HF_T01_FIFTH).toBe(true)
	clientDo(env, function()
		Deck.close()
	end)
	assertClean(env, "archive")
end)

test("two investigators share one timeline; the team recovery vote brings a teammate back", function()
	local env = boot()
	local e = env.engine
	local ben = e:addPlayer(202, "Ben", false)
	e:advance(3)
	e:fireServerAs(ben, "Action", { type = "SetReady", ready = true })
	deploySolo(env)
	local m = env.server.require(env.serverServices.MissionService).mission
	expect(m:activeParticipantCount()).toBe(2)
	interact(env, "ITEM_TAPE01")
	-- Ben (standing at the VCR) and Ana both try to edit the same event.
	e:teleport(ben, roblox.Vector3.new(4.8, 3, 49))
	e:fireServerAs(ben, "Action", { type = "DeckOpen", deck = "DECK_LOBBY" })
	e:advance(0.2)
	local benResult = e:invokeServerAs(ben, { type = "CommitEdit", event = "lobby_lights", state = "ON", deck = "DECK_LOBBY", expected = "OFF" })
	expect(benResult.ok).toBe(true)
	-- Ana tries to reverse it: the deck refuses (already edited) and nothing is spent.
	editAtDeck(env, "I_DECK_LOBBY", "lobby_lights", "LIGHTS FAIL")
	expect(mission(env).charges).toBe(2)
	expect(mission(env).timeline.events.lobby_lights.committed.name).toBe("Ben")
	-- Ben goes off-air; Ana calls a team recovery and agrees by default as proposer.
	m:eliminate(202, e.clock, {})
	e:advance(0.5)
	local DataService = env.server.require(env.serverServices.DataService)
	DataService.get(env.player).storedTeamTokens = 1
	local result
	clientDo(env, function()
		result = env.State.request("TeamRecovery", {})
	end)
	expect(result.ok).toBe(true)
	e:advance(4)
	expect(m:isAlive(202)).toBe(true)
	expect(m.teamTokenUsed).toBe(true)
	expect(DataService.get(env.player).storedTeamTokens).toBe(0)
	assertClean(env, "co-op")
end)
