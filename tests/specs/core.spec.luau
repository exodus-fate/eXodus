-- Unit tests for the engine-independent game core.

local h = Harness.new()
local Shared = h.mount("Shared", "src/shared")
local req = h.require

local Case01 = req(Shared.Config.Cases.Case01)
local MapLayout = req(Shared.Config.MapLayout)
local TimelineCore = req(Shared.Core.TimelineCore)
local PresenterBrain = req(Shared.Core.PresenterBrain)
local SignalModel = req(Shared.Core.SignalModel)
local Grading = req(Shared.Core.Grading)
local Footage = req(Shared.Core.Footage)
local Variants = req(Shared.Core.Variants)
local Format = req(Shared.Util.Format)
local Rng = req(Shared.Util.Rng)

test("Case 01 passes static validation (no cycles, no schedule conflicts)", function()
	local errors = TimelineCore.validateCase(Case01, MapLayout)
	if #errors > 0 then
		error("validation errors:\n  " .. table.concat(errors, "\n  "))
	end
end)

test("validator catches overlapping Presenter windows and bad derivations", function()
	local broken = TimelineCore.deepCopy(Case01)
	-- Move the gantry watcher into the climax window.
	for _, ev in broken.events do
		if ev.id == "transmitter_watch" then
			ev.offset = 31
		end
		if ev.id == "presenter_route_east" then
			ev.stateMap.ON = "NOWHERE"
		end
	end
	local errors = TimelineCore.validateCase(broken, MapLayout)
	local text = table.concat(errors, "\n")
	expect(text).toContain("overlap")
	expect(text).toContain("unknown state NOWHERE")
end)

test("every map reference in Case 01 resolves", function()
	for id, def in Case01.interactables do
		if def.kind == "Deck" then
			expect(Case01.decks[def.deck] ~= nil).toBeTruthy()
		elseif def.kind == "Relay" then
			expect(MapLayout.Relays[def.relay] ~= nil).toBeTruthy()
		else
			expect(def.pos ~= nil).toBeTruthy()
		end
		local pos = def.pos or (def.deck and Case01.decks[def.deck].pos)
		if pos then
			local room = MapLayout.roomAt(pos.x, pos.z)
			if room == nil then
				error(id .. " is outside every room")
			end
		end
	end
	for door in Case01.doorLocks do
		expect(MapLayout.doorById(door) ~= nil).toBeTruthy()
	end
	for itemId, item in Case01.items do
		for _, pos in item.spawns or {} do
			if not MapLayout.roomAt(pos.x, pos.z) then
				error(itemId .. " spawn is outside every room")
			end
		end
	end
end)

test("presenter paths stay inside rooms the footage can see", function()
	for _, ev in Case01.events do
		for state, def in ev.states do
			local cmd = def.presenter
			if cmd and cmd.path then
				for i, key in cmd.path do
					if not MapLayout.roomAt(key.pos.x, key.pos.z) then
						error(string.format("%s.%s keyframe %d is outside the map", ev.id, state, i))
					end
				end
			end
		end
	end
end)

test("map doors sit on a shared boundary of the rooms they connect", function()
	for _, door in MapLayout.Doors do
		for _, roomId in door.rooms do
			local room = MapLayout.Rooms[roomId]
			local onEdge
			if door.plane == "z" then
				onEdge = (door.at == room.z0 or door.at == room.z1)
					and door.center - door.width / 2 >= room.x0
					and door.center + door.width / 2 <= room.x1
			else
				onEdge = (door.at == room.x0 or door.at == room.x1)
					and door.center - door.width / 2 >= room.z0
					and door.center + door.width / 2 <= room.z1
			end
			if not onEdge then
				error(door.id .. " is not on the edge of " .. roomId)
			end
		end
	end
end)

test("rooms never overlap", function()
	local ids = {}
	for id in MapLayout.Rooms do
		table.insert(ids, id)
	end
	for i = 1, #ids do
		for j = i + 1, #ids do
			local a, b = MapLayout.Rooms[ids[i]], MapLayout.Rooms[ids[j]]
			local overlap = a.x0 < b.x1 and b.x0 < a.x1 and a.z0 < b.z1 and b.z0 < a.z1
			if overlap then
				error(ids[i] .. " overlaps " .. ids[j])
			end
		end
	end
end)

test("timeline: valid edit changes the event and its linked consequence", function()
	local tl = TimelineCore.new(Case01)
	tl:setAnchor("broadcast_start", 100)
	expect(tl:effectiveState("presenter_entry")).toBe("LOBBY")
	local ok, code = tl:validateEdit("lobby_lights", "ON", 120, { flags = {}, charges = 3, tapeFound = true })
	expect(ok).toBe(true)
	expect(code).toBe("OK")
	local entry = tl:commit("lobby_lights", "ON", 1, "Ana", 120)
	expect(entry.consequences[1].eventId).toBe("presenter_entry")
	expect(entry.consequences[1].to).toBe("SOUTH_HALL")
	expect(tl:effectiveState("presenter_entry")).toBe("SOUTH_HALL")
end)

test("timeline: invalid edits are refused with a reason", function()
	local tl = TimelineCore.new(Case01)
	tl:setAnchor("broadcast_start", 0)
	local ctx = { flags = {}, charges = 3, tapeFound = true }
	local function code(id, state, now, c)
		local _, reason = tl:validateEdit(id, state, now, c or ctx)
		return reason
	end
	expect(code("nope", "ON", 1)).toBe("UNKNOWN_EVENT")
	expect(code("presenter_entry", "SOUTH_HALL", 1)).toBe("NOT_EDITABLE")
	expect(code("lobby_lights", "PURPLE", 1)).toBe("INVALID_STATE")
	expect(code("lobby_lights", "OFF", 1)).toBe("NO_CHANGE")
	expect(code("lobby_lights", "ON", 1, { flags = {}, charges = 0, tapeFound = true })).toBe("NO_CHARGES")
	expect(code("lobby_lights", "ON", 1, { flags = {}, charges = 3, tapeFound = false })).toBe("TAPE_MISSING")
	expect(code("east_corridor_lights", "ON", 1)).toBe("PREREQUISITE")
	-- Locks 5 seconds before it fires (fires at 150).
	expect(code("lobby_lights", "ON", 146)).toBe("LOCKED")
	expect(code("lobby_lights", "ON", 144)).toBe("OK")
	expect(code("lobby_lights", "ON", 144, { flags = {}, charges = 3, tapeFound = true, expectedState = "ON" })).toBe("VERSION")
end)

test("timeline: no event can be edited twice", function()
	local tl = TimelineCore.new(Case01)
	tl:setAnchor("broadcast_start", 0)
	tl:commit("lobby_lights", "ON", 1, "Ana", 10)
	local ok, code, message = tl:validateEdit("lobby_lights", "OFF", 11, { flags = {}, charges = 3, tapeFound = true })
	expect(ok).toBe(false)
	expect(code).toBe("ALREADY_EDITED")
	expect(message).toContain("Ana")
end)

test("timeline: events fire at their time with the committed state, then lock", function()
	local tl = TimelineCore.new(Case01)
	tl:setAnchor("broadcast_start", 0)
	tl:commit("lobby_lights", "ON", 1, "Ana", 10)
	local early = tl:update(140)
	expect(#early).toBe(0)
	local outputs = tl:update(160)
	local kinds = {}
	for _, o in outputs do
		kinds[o.kind .. ":" .. o.eventId] = o
	end
	expect(kinds["fired:lobby_lights"] ~= nil).toBeTruthy()
	expect(kinds["presenter:presenter_entry"].command.path[1].pos.z).toBe(MapLayout.point("ControlRoom", 0.5, 0.85).z)
	-- The lights stayed on: no Lights action.
	for _, o in outputs do
		if o.kind == "action" then
			expect(o.action.type ~= "Lights").toBeTruthy()
		end
	end
	expect(tl:isLocked("lobby_lights", 160)).toBe(true)
	-- Running update again emits nothing new.
	expect(#tl:update(165)).toBe(0)
end)

test("timeline: patrol variant reverses the east corridor patrol", function()
	local normal = TimelineCore.new(Case01)
	local flipped = TimelineCore.new(Case01, { patrolFlip = true })
	local a = normal:getEvent("presenter_route_east").states.EAST_CORRIDOR.presenter.path
	local b = flipped:getEvent("presenter_route_east").states.EAST_CORRIDOR.presenter.path
	expect(a[1].pos.x).toBe(b[2].pos.x)
	expect(a[2].pos.x).toBe(b[1].pos.x)
	-- The shared case table is untouched.
	expect(Case01.events[4].states.EAST_CORRIDOR.presenter.path[1].pos.x).toBe(a[1].pos.x)
end)

local function sensed(id, dist, opts)
	opts = opts or {}
	return {
		id = id,
		pos = opts.pos or { x = dist, y = 0, z = 0 },
		dist = dist,
		los = opts.los ~= false,
		angle = opts.angle or 0,
		lit = opts.lit ~= false,
		flashlight = opts.flashlight or false,
		hidden = opts.hidden or false,
		invulnerable = opts.invulnerable or false,
	}
end

local function displacedCmd()
	return {
		kind = "Displaced",
		duration = 60,
		huntOnSight = true,
		sight = { range = 40, dark = 20, fov = 120, proximity = 6 },
		path = { { t = 0, pos = { x = 0, y = 0, z = 0 } }, { t = 60, pos = { x = 0, y = 0, z = 0 } } },
	}
end

test("presenter: hunts only after a wind-up, never instantly", function()
	local brain = PresenterBrain.new()
	brain:setCommand(displacedCmd(), 0, { scripted = true })
	local out = brain:update(0.1, { players = { sensed(1, 20) } })
	expect(out.state).toBe("Hunting")
	expect(out.huntPhase).toBe("windup")
	expect(out.speed).toBe(0)
	out = brain:update(1.5, { players = { sensed(1, 2) } })
	expect(out.catchId).toBe(nil)
	out = brain:update(2.7, { players = { sensed(1, 10) } })
	expect(out.huntPhase).toBe("chase")
	expect(out.moveTo ~= nil).toBeTruthy()
end)

test("presenter: does not see players in the dark beyond dark range, or behind it", function()
	local brain = PresenterBrain.new()
	brain:setCommand(displacedCmd(), 0, { scripted = true })
	local out = brain:update(0.1, { players = { sensed(1, 30, { lit = false }) } })
	expect(out.state).toBe("Displaced")
	out = brain:update(0.2, { players = { sensed(1, 30, { lit = false, flashlight = true }) } })
	expect(out.state).toBe("Hunting")
	brain = PresenterBrain.new()
	brain:setCommand(displacedCmd(), 0, { scripted = true })
	out = brain:update(0.1, { players = { sensed(1, 15, { angle = 170 }) } })
	expect(out.state).toBe("Displaced")
end)

test("presenter: loses a player who breaks line of sight, searches, then gives up", function()
	local brain = PresenterBrain.new()
	brain:setCommand(displacedCmd(), 0, { scripted = true })
	brain:update(0, { players = { sensed(1, 20) } })
	brain:update(3, { players = { sensed(1, 20) } })
	local out = brain:update(4, { players = { sensed(1, 25, { los = false }) } })
	expect(out.huntPhase).toBe("chase")
	out = brain:update(9.2, { players = { sensed(1, 25, { los = false }) } })
	expect(out.huntPhase).toBe("search")
	out = brain:update(14, { players = { sensed(1, 25, { los = false }) } })
	expect(out.state).toBe("Dormant")
	local names = {}
	for _, e in out.events or {} do
		names[e.name] = e.data
	end
	expect(names.HuntEnd.reason).toBe("Lost")
end)

test("presenter: catches only within reach and line of sight", function()
	local brain = PresenterBrain.new()
	brain:setCommand(displacedCmd(), 0, { scripted = true })
	brain:update(0, { players = { sensed(1, 20) } })
	brain:update(3, { players = { sensed(1, 10) } })
	local out = brain:update(3.5, { players = { sensed(1, 3, { los = false }) } })
	expect(out.catchId).toBe(nil)
	out = brain:update(4, { players = { sensed(1, 3) } })
	expect(out.catchId).toBe(1)
	expect(out.state).toBe("Dormant")
end)

test("presenter: refuges and revive protection make players invisible", function()
	local brain = PresenterBrain.new()
	brain:setCommand(displacedCmd(), 0, { scripted = true })
	local out = brain:update(0.1, { players = { sensed(1, 3, { hidden = true }), sensed(2, 3, { invulnerable = true }) } })
	expect(out.state).toBe("Displaced")
end)

test("presenter: hunts end at the time limit", function()
	local brain = PresenterBrain.new({ maxHunt = 10 })
	brain:setCommand(displacedCmd(), 0, { scripted = true })
	brain:update(0, { players = { sensed(1, 30) } })
	local out
	for t = 1, 12 do
		out = brain:update(t, { players = { sensed(1, 30) } })
	end
	expect(out.state).toBe("Dormant")
end)

test("presenter: an ambush with nobody nearby turns into observing", function()
	local brain = PresenterBrain.new()
	brain:setCommand({ kind = "Ambush", pos = { x = 0, y = 0, z = 0 }, look = { x = 1, y = 0, z = 0 }, radius = 20, windup = 2, maxDuration = 30 }, 0, { scripted = true })
	local out = brain:update(0.1, { players = { sensed(1, 50) } })
	expect(out.teleportTo ~= nil).toBeTruthy()
	expect(out.state).toBe("Hunting")
	out = brain:update(2.5, { players = { sensed(1, 50) } })
	expect(out.state).toBe("Observing")
end)

test("signal quality is deterministic and never random", function()
	local params = { relay = "EAST", powerOn = true, relayOn = false, deckBattery = false, presenterDistance = 20, anomaly = false }
	local a = SignalModel.cameraQuality(params)
	local b = SignalModel.cameraQuality(params)
	expect(a).toBe(b)
	expect(SignalModel.band(a)).toBe("LOST")
	local unpowered = SignalModel.cameraQuality({ relay = "WEST", powerOn = false })
	expect(unpowered).toBe(0)
	local lobby = SignalModel.cameraQuality({ relay = "LOCAL", powerOn = false, deckBattery = true })
	expect(SignalModel.band(lobby)).toBe("WEAK")
	expect(SignalModel.playerQuality({ powerOn = true, presenterDistance = nil })).toBe(92)
end)

test("grading: rewards survival, evidence and predictions; failure caps at D", function()
	local perfect = Grading.compute({
		result = "Success", participants = 2, survivors = 2,
		evidenceFound = 5, evidenceTotal = 5,
		predictionsInterpreted = 8, predictionsTotal = 8,
		editsMade = 1, maxCharges = 3, eliminationsDuringEdits = 0,
		loopFirstTry = true, callerFooled = false,
	})
	expect(perfect.grade).toBe("S")
	local failed = Grading.compute({ result = "Failed", participants = 1, survivors = 0, maxCharges = 3, loopFirstTry = true })
	expect(failed.grade).toBe("D")
	local rewards = Grading.rewards({ result = "Success", grade = "S", anomaliesIdentified = 2, bonusTapeExtracted = true }, { itemsRecovered = 3, evidenceRecovered = 1, framesMarked = 1, extracted = true })
	expect(rewards.credits).toBe(120 + 80 + 40)
	expect(rewards.research).toBe(20 + 15 + 10 + 25)
end)

test("footage predicts the configured events and updates after an edit", function()
	local tl = TimelineCore.new(Case01)
	local defs = tl:eventDefinitions()
	local snap = tl:snapshot(0)
	-- Original prediction: reception lights fail at 02:30 and it walks in.
	expect(Footage.lightsAt(Case01, defs, snap, "TAPE01", "CAM01", 149)).toBe("emergency")
	expect(Footage.lightsAt(Case01, defs, snap, "TAPE01", "CAM01", 151)).toBe("off")
	local f = Footage.frame(Case01, defs, snap, "TAPE01", "CAM01", 165)
	local presenters = 0
	for _, a in f.actors do
		if a.kind == "Presenter" then
			presenters += 1
		end
	end
	expect(presenters).toBe(1)
	expect(#Footage.frame(Case01, defs, snap, "TAPE01", "CAM02", 165).actors).toBe(0)
	-- After the edit the lights hold and the figure shows up on CAM 02 instead.
	tl:commit("lobby_lights", "ON", 1, "Ana", 10)
	snap = tl:snapshot(10)
	expect(Footage.lightsAt(Case01, defs, snap, "TAPE01", "CAM01", 151)).toBe("emergency")
	expect(#Footage.frame(Case01, defs, snap, "TAPE01", "CAM01", 170).actors).toBe(0)
	expect(#Footage.frame(Case01, defs, snap, "TAPE01", "CAM02", 170).actors).toBe(1)
	local markers = Footage.markers(Case01, defs, snap, "TAPE01")
	expect(markers[1].eventId).toBe("lobby_lights")
	expect(markers[1].state).toBe("ON")
end)

test("footage shows the hidden frame only on its exact frame", function()
	local tl = TimelineCore.new(Case01)
	local f = Footage.frame(Case01, tl:eventDefinitions(), tl:snapshot(0), "TAPE01", "CAM01", 12.4)
	expect(f.hiddenFrame.id).toBe("HF_T01_FIFTH")
	f = Footage.frame(Case01, tl:eventDefinitions(), tl:snapshot(0), "TAPE01", "CAM01", 14)
	expect(f.hiddenFrame).toBe(nil)
end)

test("variants are deterministic per seed and the Caller's code is always wrong", function()
	for seed = 1, 200 do
		local a = Variants.compute(Case01, seed)
		local b = Variants.compute(Case01, seed)
		expect(a.code).toBe(b.code)
		expect(a.loopOdd).toBe(b.loopOdd)
		expect(a.code ~= a.fakeCode).toBeTruthy()
		expect(#a.code).toBe(4)
	end
	local seen = {}
	for seed = 1, 60 do
		seen[Variants.compute(Case01, seed).loopOdd] = true
	end
	local kinds = 0
	for _ in seen do
		kinds += 1
	end
	expect(kinds).toBeAtLeast(4)
end)

test("rng and format helpers", function()
	local r1, r2 = Rng.new(42), Rng.new(42)
	for _ = 1, 20 do
		expect(r1:int(1, 6)).toBe(r2:int(1, 6))
	end
	local r = Rng.new(-5)
	for _ = 1, 50 do
		local v = r:float()
		expect(v >= 0 and v < 1).toBeTruthy()
	end
	expect(Format.clock(3725)).toBe("01:02:05")
	expect(Format.timecode(1.5)).toBe("00:00:01:15")
	expect(Format.relative(150)).toBe("T+02:30")
end)
