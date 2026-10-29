-- Simulated playthroughs of Case 01 through MissionCore (the acceptance tests
-- that can be run without Roblox Studio).

local h = Harness.new()
local Shared = h.mount("Shared", "src/shared")
local req = h.require

local Case01 = req(Shared.Config.Cases.Case01)
local MissionCore = req(Shared.Core.MissionCore)

local SEED = 424242

local function newMission(players, mode)
	local list = {}
	for i, name in players do
		table.insert(list, { userId = i, name = name })
	end
	return MissionCore.new(Case01, { mode = mode or "Standard", seed = SEED, now = 0, participants = list })
end

-- Ticks the mission and collects every effect.
local function advance(m, from, to, world)
	local effects = {}
	local t = from
	while t <= to + 1e-9 do
		m:update(t, world or { presenterIdle = true })
		for _, e in m:drainEffects() do
			e._t = t
			table.insert(effects, e)
		end
		t += 0.5
	end
	return effects
end

local function find(effects, predicate)
	for _, e in effects do
		if predicate(e) then
			return e
		end
	end
	return nil
end

local function ok(m, user, id, now)
	local success, msg = m:interact(user, id, now)
	if not success then
		error(string.format("interact %s failed: %s", id, tostring(msg)), 2)
	end
end

-- Finds a time >= now at which the odd prop is showing.
local function nextOddTime(m, now)
	local t = now
	for _ = 1, 200 do
		local _, odd = m:loopCycle(t)
		if odd then
			return t + 0.5
		end
		t += 0.5
	end
	error("no odd cycle")
end

test("solo: a single player can start and finish Case 01", function()
	local m = newMission({ "Ana" })
	expect(m.phase).toBe("Briefing")
	local fx = advance(m, 0, 41)
	expect(m.phase).toBe("Active")
	expect(m.broadcastStart).toBe(40)
	expect(find(fx, function(e)
		return e.type == "Door" and e.door == "D_Lobby_Main" and e.locked
	end) ~= nil).toBeTruthy()
	expect(m:currentObjective().id).toBe("tape01")

	ok(m, 1, "ITEM_TAPE01", 42)
	expect(m:currentObjective().id).toBe("watch01")
	expect(m:deckOpened(1, "DECK_LOBBY", "TAPE01", 43)).toBe(true)
	expect(m:currentObjective().id).toBe("decide01")
	expect(m:currentObjective().text).toContain("00:02:30")
	m:inspectEvent(1, "lobby_lights", 44)

	-- Invalid edits never spend a charge.
	local good, code = m:commitEdit(1, "lobby_lights", "PURPLE", { deckId = "DECK_LOBBY" }, 45)
	expect(good).toBe(false)
	expect(code).toBe("INVALID_STATE")
	expect(m.charges).toBe(3)
	good, code = m:commitEdit(1, "east_corridor_lights", "ON", { deckId = "DECK_LOBBY" }, 45)
	expect(code).toBe("TAPE_MISSING")
	good, code = m:commitEdit(1, "lobby_lights", "ON", { deckId = "DECK_MAIN" }, 45)
	expect(code).toBe("NO_DECK")
	expect(m.charges).toBe(3)

	-- Keep the reception lights on: it waits outside the control room instead.
	good = m:commitEdit(1, "lobby_lights", "ON", { deckId = "DECK_LOBBY", expectedState = "OFF" }, 46)
	expect(good).toBe(true)
	expect(m.charges).toBe(2)
	expect(m:currentObjective().id).toBe("leave")
	m:deckClosed(1)

	fx = advance(m, 41.5, 200)
	local cmd = find(fx, function(e)
		return e.type == "Presenter" and e.eventId == "presenter_entry"
	end)
	expect(cmd ~= nil).toBeTruthy()
	expect(cmd._t).toBe(40 + 155)
	expect(cmd.command.path[2].pos.z).toBe(23.2) -- south hall, outside the control room
	expect(find(fx, function(e)
		return e.type == "Lights" and e.room == "Lobby" and e.mode == "off"
	end)).toBe(nil)
	local shadow = find(fx, function(e)
		return e.type == "Cue" and e.cue == "EditorShadow"
	end)
	expect(shadow == nil).toBeTruthy() -- fires at 210, after this window
	fx = advance(m, 200.5, 211)
	shadow = find(fx, function(e)
		return e.type == "Cue" and e.cue == "EditorShadow"
	end)
	expect(shadow.userId).toBe(1)
	expect(m:currentObjective().id).toBe("power")

	-- Generator: two stages, then power.
	local before = m:promptState("I_DECK_MAIN")
	expect(before.action).toBe("No Power")
	ok(m, 1, "I_GENERATOR", 212)
	expect(m.flags.generator_restored).toBe(nil)
	ok(m, 1, "I_GENERATOR", 214)
	expect(m.flags.generator_restored).toBe(true)
	expect(m:promptState("I_DECK_MAIN").action).toBe("Open Deck")
	expect(m:isDoorLocked("D_EC_Arch")).toBe(false)
	expect(m:isDoorLocked("D_TH_Trans")).toBe(true)
	fx = advance(m, 214, 245)
	local radio = {}
	for _, e in fx do
		if e.type == "Subtitle" and e.kind == "radio" then
			table.insert(radio, e)
		end
	end
	expect(#radio).toBe(3)
	expect(radio[1].channel).toBe(2)
	expect(radio[1].text).toContain(m.variants.code)
	expect(radio[2].channel).toBe(0)
	expect(radio[2].caller).toBe(true)
	expect(radio[2].text).toContain(m.variants.fakeCode)
	expect(radio[2].stamp ~= radio[1].stamp).toBeTruthy()

	-- The keypad: the true code from Channel 2.
	ok(m, 1, "I_CAGE", 246)
	local opened = m:submitCode(1, m.variants.code, 247)
	expect(opened).toBe(true)
	expect(m.inventory.VALVE ~= nil).toBeTruthy()

	ok(m, 1, "ITEM_TAPE02", 250)
	ok(m, 1, "ITEM_COIL", 251)
	ok(m, 1, "ITEM_TAPE03", 252)
	expect(m:currentObjective().text).toContain("2/3")

	-- Leave the east corridor prediction alone (OFF): the patrol starts at +95.
	fx = advance(m, 245.5, 214 + 96)
	local patrol = find(fx, function(e)
		return e.type == "Presenter" and e.eventId == "presenter_route_east"
	end)
	expect(patrol ~= nil).toBeTruthy()
	expect(find(fx, function(e)
		return e.type == "Relay" and e.relay == "EAST" and e.on == false
	end) ~= nil).toBeTruthy()
	ok(m, 1, "I_RELAY_EAST", 312)
	expect(m.relays.EAST).toBe(true)

	-- The Loop: a wrong guess resets it; the odd detail on an odd cycle breaks it.
	ok(m, 1, "I_RACK", 320)
	expect(m.loop.active).toBe(true)
	expect(m:isDoorLocked("D_EC_Arch")).toBe(true)
	local wrongProp
	for _, prop in Case01.loop.props do
		if prop.id ~= m.loop.odd then
			wrongProp = prop.id
			break
		end
	end
	local wrong = m:interact(1, wrongProp, 321)
	expect(wrong).toBe(false)
	expect(m.loop.attempts).toBe(1)
	local tOdd = nextOddTime(m, 321)
	ok(m, 1, m.loop.odd, tOdd)
	expect(m.loop.solved).toBe(true)
	expect(m:isDoorLocked("D_EC_Arch")).toBe(false)
	ok(m, 1, "I_RACK", tOdd + 1)
	expect(m.flags.board_recovered).toBe(true)
	expect(m.flags.components_complete).toBe(true)
	ok(m, 1, "ITEM_KEY", tOdd + 2)
	ok(m, 1, "ITEM_TAPE04", tOdd + 3)
	expect(m:isDoorLocked("D_TH_Trans")).toBe(false)

	local tBoard = m.flagTimes.board_recovered
	fx = advance(m, tOdd + 3.5, tBoard + 110)
	local ambush = find(fx, function(e)
		return e.type == "Presenter" and e.eventId == "presenter_ambush"
	end)
	expect(ambush.command.kind).toBe("Ambush")
	local rewindLock = find(fx, function(e)
		return e.type == "Door" and e.door == "D_CR_NH" and e.locked == true
	end)
	expect(rewindLock ~= nil).toBeTruthy()
	expect(m:isDoorLocked("D_CR_NH")).toBe(false) -- unlocked again after 30 s

	-- Install everything; then edit the freight door to open on time.
	local tInstall = tBoard + 111
	ok(m, 1, "I_SOCKET_COIL", tInstall)
	ok(m, 1, "I_SOCKET_VALVE", tInstall)
	ok(m, 1, "I_SOCKET_BOARD", tInstall)
	expect(m.flags.transmitter_armed).toBe(true)
	good = m:commitEdit(1, "freight_door", "OPEN", { deckId = "DECK_TRANS" }, tInstall + 2)
	expect(good).toBe(true)
	expect(m.charges).toBe(1)
	fx = advance(m, tInstall + 0.5, tInstall + 33)
	expect(m.phase).toBe("ExtractionAvailable")
	local dock = find(fx, function(e)
		return e.type == "Presenter" and e.eventId == "climax_route"
	end)
	expect(dock.command.path[1].pos.z < -104).toBeTruthy() -- loading dock

	ok(m, 1, "I_VAN", tInstall + 90)
	expect(m.phase).toBe("Completed")
	local report = m:getReport()
	expect(report.result).toBe("Success")
	expect(report.componentsCount).toBe(3)
	expect(report.editsMade).toBe(2)
	expect(report.maxCharges).toBe(3)
	expect(report.tapesFound).toBe(4)
	expect(report.loopFirstTry).toBe(false)
	expect(report.callerFooled).toBe(false)
	expect(report.masterRecording).toBe("MASTER_01")
	expect(report.challenges).toContain("C01_UNUSED")
	expect(report.challenges).toContain("C01_SOLO")
	expect(report.challenges).toContain("C01_CALLER")
	expect(report.rewards["1"].credits).toBeAtLeast(120)
	expect(report.predictionsInterpreted).toBeAtLeast(2)
end)

test("co-op: two players share one timeline and one charge pool", function()
	local m = newMission({ "Ana", "Ben" })
	advance(m, 0, 41)
	ok(m, 2, "ITEM_TAPE01", 42)
	-- Both open the VCR and race to edit the same event.
	m:deckOpened(1, "DECK_LOBBY", "TAPE01", 43)
	m:deckOpened(2, "DECK_LOBBY", "TAPE01", 43)
	local a = m:commitEdit(1, "lobby_lights", "ON", { deckId = "DECK_LOBBY", expectedState = "OFF" }, 44)
	local b, code, message = m:commitEdit(2, "lobby_lights", "ON", { deckId = "DECK_LOBBY", expectedState = "OFF" }, 44)
	expect(a).toBe(true)
	expect(b).toBe(false)
	expect(code).toBe("ALREADY_EDITED")
	expect(message).toContain("Ana")
	expect(m.charges).toBe(2)
	local snap = m:snapshot(44)
	expect(snap.timeline.events.presenter_entry.state).toBe("SOUTH_HALL")
	expect(snap.inventory.TAPE01).toBe("Ben")
	expect(snap.participants["1"].name).toBe("Ana")
end)

test("co-op: spectators can watch but cannot edit; disconnects do not end the case", function()
	local m = newMission({ "Ana", "Ben" })
	advance(m, 0, 41)
	ok(m, 1, "ITEM_TAPE01", 42)
	m:eliminate(2, 50, {})
	local good, code = m:commitEdit(2, "lobby_lights", "ON", { deckId = "DECK_LOBBY" }, 51)
	expect(good).toBe(false)
	expect(code).toBe("SPECTATOR")
	expect(m.charges).toBe(3)
	expect(m:interact(2, "I_BRIEFING", 51)).toBe(false)
	m:removeParticipant(2, 52)
	advance(m, 52, 60)
	expect(m.phase).toBe("Active")
	-- A late joiner can fill the empty slot.
	local joined = m:addParticipant(3, "Cal", 61)
	expect(joined).toBe(true)
	expect(m:activeParticipantCount()).toBe(2)
end)

test("failure: if everyone is eliminated the case fails after a short grace window", function()
	local m = newMission({ "Ana" })
	advance(m, 0, 41)
	expect(m:eliminate(1, 100, {})).toBe(true)
	advance(m, 100, 105)
	expect(m.phase).toBe("Active")
	expect(m.failPendingUntil).toBe(112)
	advance(m, 105.5, 113)
	expect(m.phase).toBe("Failed")
	local report = m:getReport()
	expect(report.result).toBe("Failed")
	expect(report.grade).toBe("D")
	expect(report.masterRecording).toBe(nil)
end)

test("revive: once per player per case, at a checkpoint, with brief invulnerability", function()
	local m = newMission({ "Ana" })
	advance(m, 0, 41)
	m:eliminate(1, 100, {})
	local good = m:revive(1, 104, "Personal")
	expect(good).toBe(true)
	expect(m:isAlive(1)).toBe(true)
	expect(m.failPendingUntil).toBe(nil)
	expect(m:isInvulnerable(1, 105)).toBe(true)
	expect(m:eliminate(1, 105, {})).toBe(false) -- protected
	expect(m:isInvulnerable(1, 111)).toBe(false)
	m:eliminate(1, 120, {})
	local again, reason = m:revive(1, 121, "Personal")
	expect(again).toBe(false)
	expect(reason).toContain("already")
	-- Revives never restore spent charges.
	expect(m.charges).toBe(3)
end)

test("team recovery: needs a living teammate, and blocks further re-entries", function()
	local m = newMission({ "Ana", "Ben" })
	advance(m, 0, 41)
	m:eliminate(2, 60, {})
	expect(m:canTeamRecover()).toBe(true)
	expect(m:teamRecover(61)).toBe(true)
	expect(m:isAlive(2)).toBe(true)
	m:eliminate(2, 80, {})
	local again = m:teamRecover(81)
	expect(again).toBe(false)
	local personal = m:revive(2, 82, "Personal")
	expect(personal).toBe(false)
end)

test("partial extraction when part of the team is lost", function()
	local m = newMission({ "Ana", "Ben" })
	advance(m, 0, 41)
	m:setFlag("generator_restored", 50)
	m:setFlag("extraction_open", 60)
	expect(m.phase).toBe("ExtractionAvailable")
	m:eliminate(2, 61, {})
	m:extract(1, 62)
	expect(m.phase).toBe("Completed")
	expect(m:getReport().result).toBe("Partial")
end)

test("the Caller's code sets off the alarm and raises awareness", function()
	local m = newMission({ "Ana" })
	advance(m, 0, 41)
	ok(m, 1, "I_GENERATOR", 50)
	ok(m, 1, "I_GENERATOR", 52)
	local before = m.awareness
	local good, message = m:submitCode(1, m.variants.fakeCode, 53)
	expect(good).toBe(false)
	expect(message).toContain("alarm")
	expect(m.stats.callerFooled).toBe(true)
	expect(m.awareness > before).toBeTruthy()
	local locked = m:submitCode(1, m.variants.code, 54)
	expect(locked).toBe(false) -- lockout
	expect(m:submitCode(1, m.variants.code, 59)).toBe(true)
end)

test("awareness from deck use makes it observe the player - never instantly hunt", function()
	local m = newMission({ "Ana" })
	advance(m, 0, 41)
	m:deckOpened(1, "DECK_LOBBY", nil, 41)
	-- Net +0.6/s while watching: roughly 2.5-3 minutes of continuous deck use.
	local fx = advance(m, 41, 260)
	local observe = find(fx, function(e)
		return e.type == "ObserveNear"
	end)
	expect(observe ~= nil).toBeTruthy()
	expect(observe.userId).toBe(1)
	-- Cooldown prevents back-to-back observes.
	local count = 0
	for _, e in fx do
		if e.type == "ObserveNear" then
			count += 1
		end
	end
	expect(count).toBeAtMost(4)
end)

test("hidden frames are only accepted on the exact frame, once", function()
	local m = newMission({ "Ana" })
	advance(m, 0, 41)
	ok(m, 1, "ITEM_TAPE01", 42)
	local miss = m:markFrame(1, "TAPE01", "CAM01", 20, 43)
	expect(miss).toBe(false)
	local hit, frameId = m:markFrame(1, "TAPE01", "CAM01", 12.5, 43)
	expect(hit).toBe(true)
	expect(frameId).toBe("HF_T01_FIFTH")
	expect(m:markFrame(1, "TAPE01", "CAM01", 12.5, 44)).toBe(false)
end)

test("restricted mode has fewer charges and hides clues", function()
	local m = newMission({ "Ana" }, "Restricted")
	expect(m.charges).toBe(2)
	advance(m, 0, 41)
	expect(m:currentObjective().clue).toBe(nil)
end)

test("time limit fails a stalled case", function()
	local m = newMission({ "Ana" })
	advance(m, 0, 41)
	m:update(40 + Case01.timeLimit + 1, { presenterIdle = true })
	expect(m.phase).toBe("Failed")
end)

test("the bonus tape in Studio A triggers a hunt", function()
	local m = newMission({ "Ana" })
	advance(m, 0, 41)
	m:setFlag("extraction_open", 60)
	ok(m, 1, "ITEM_TAPE07", 61)
	local fx = m:drainEffects()
	local hunt = find(fx, function(e)
		return e.type == "Presenter" and e.eventId == "bonus_tape"
	end)
	expect(hunt.command.kind).toBe("Ambush")
end)
