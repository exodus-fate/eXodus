--[[
	MissionCore — one run of a case, independent of Roblox.

	Owns: mission phase, objectives, flags, team inventory, shared edit charges,
	the timeline, the Loop and Caller anomalies, doors/lights/relays state,
	Presenter awareness, eliminations/revives, extraction, scoring and the report.

	The server glue calls the action methods (interact, commitEdit, ...) after its
	own range/rate checks, calls update(now, world) every tick, applies whatever
	drainEffects() returns to the world, and replicates snapshot(now) to clients.

	Phases: Briefing -> Active -> ExtractionAvailable -> Completed | Failed (| Aborted)
]]

local TimelineCore = require(script.Parent.TimelineCore)
local Grading = require(script.Parent.Grading)
local Variants = require(script.Parent.Variants)
local Format = require(script.Parent.Parent.Util.Format)
local MapLayout = require(script.Parent.Parent.Config.MapLayout)

local MissionCore = {}
MissionCore.__index = MissionCore

local AWARENESS_DECAY = 0.6 -- per second
local AWARENESS_DECK = 1.2 -- per second per open deck
local AWARENESS_EDIT = 15
local AWARENESS_THRESHOLD = 100
local OBSERVE_COOLDOWN = 40
local FAIL_GRACE = 12
local REVIVE_INVULNERABILITY = 6

local ACTIVE_PHASES = { Active = true, ExtractionAvailable = true }
local PLAYABLE_PHASES = { Briefing = true, Active = true, ExtractionAvailable = true }

local function key(userId)
	return tostring(userId)
end

--[[
	opts = {
		mode = "Standard" | "Restricted" | "ArchiveChallenge",
		seed = number,
		now = number,
		participants = { { userId, name } },
	}
]]
function MissionCore.new(caseDef, opts)
	local self = setmetatable({}, MissionCore)
	self.case = caseDef
	self.mode = opts.mode or "Standard"
	self.modeDef = caseDef.modes[self.mode] or caseDef.modes.Standard
	self.seed = opts.seed or 1
	self.variants = Variants.compute(caseDef, self.seed)
	self.timeline = TimelineCore.new(caseDef, { patrolFlip = self.variants.patrolFlip })

	local now = opts.now or 0
	self.createdAt = now
	self.phase = "Briefing"
	self.briefingEnd = now + caseDef.briefing.duration
	self.briefingDone = {}
	self.broadcastStart = nil
	self.endedAt = nil

	self.flags = {}
	self.flagTimes = {}
	self.maxCharges = self.modeDef.charges
	self.charges = self.maxCharges
	self.inventory = {}
	self.installed = {}
	self.participants = {}
	self.participantOrder = {}

	self.awareness = 0
	self.lastNoiseUser = nil
	self.lastObserveAt = -math.huge
	self.deckUsers = {}

	self.generatorStage = 0
	self.relays = { WEST = true, EAST = true }
	self.doorOverrides = {}
	self.loopLocks = {}
	self.doorState = {}
	self.lightOverrides = {}
	self.lights = {}

	self.loop = { active = false, solved = false, cycleStart = 0, attempts = 0, odd = self.variants.loopOdd }
	self.keypad = { opened = false, lockoutUntil = 0, wrongAttempts = 0 }
	self.radioLog = {}
	self.radioDone = {}

	self.teamTokenUsed = false
	self.failPendingUntil = nil
	self.endReason = nil

	self.stats = {
		inspected = {},
		editsMade = 0,
		eliminations = 0,
		eliminationsDuringEdits = 0,
		callerFooled = false,
		framesMarked = {},
		evidenceFound = {},
		tapesFound = {},
		anomaliesIdentified = 0,
		loopFirstTry = false,
	}

	self.effects = {}
	self.version = 0
	self.report = nil

	self:_buildInteractables()
	for _, p in opts.participants or {} do
		self:addParticipant(p.userId, p.name, now)
	end
	self:_refreshDoors()
	self:_refreshLights(now)
	return self
end

---------------------------------------------------------------------------
-- Internals
---------------------------------------------------------------------------

function MissionCore:_emit(effect)
	table.insert(self.effects, effect)
end

function MissionCore:_dirty()
	self.version += 1
end

function MissionCore:drainEffects()
	local list = self.effects
	self.effects = {}
	return list
end

function MissionCore:broadcastClock(now)
	if not self.broadcastStart then
		return 0
	end
	return now - self.broadcastStart
end

function MissionCore:_notify(text, userId)
	self:_emit({ type = "Notify", text = text, userId = userId })
end

function MissionCore:_subtitle(text, kind, extra)
	local effect = { type = "Subtitle", text = text, kind = kind or "cue" }
	for k, v in extra or {} do
		effect[k] = v
	end
	self:_emit(effect)
end

function MissionCore:_buildInteractables()
	local list = {}
	for id, def in self.case.interactables do
		local entry = table.clone(def)
		entry.id = id
		if def.kind == "Deck" then
			local deck = self.case.decks[def.deck]
			entry.pos = deck.pos
			entry.room = deck.room
			entry.object = deck.label
		end
		list[id] = entry
	end
	for itemId, item in self.case.items do
		if item.spawns and #item.spawns > 0 then
			local index = self.variants.itemSpawns[itemId] or 1
			list["ITEM_" .. itemId] = {
				id = "ITEM_" .. itemId,
				kind = "Pickup",
				item = itemId,
				pos = item.spawns[index],
				object = item.label,
			}
		end
	end
	-- Loop props only show their prompts while the Loop is running.
	if self.case.loop then
		for _, prop in self.case.loop.props do
			list[prop.id] = {
				id = prop.id,
				kind = "LoopProp",
				prop = prop.id,
				pos = prop.pos,
				object = prop.label,
				room = self.case.loop.room,
			}
		end
	end
	self.interactables = list
end

function MissionCore:getInteractables()
	return self.interactables
end

function MissionCore:hasFlag(flag)
	return self.flags[flag] == true
end

function MissionCore:setFlag(flag, now)
	if self.flags[flag] then
		return false
	end
	self.flags[flag] = true
	self.flagTimes[flag] = now
	self.timeline:setAnchor(flag, now)

	if flag == "generator_restored" then
		self.relays.WEST = true
		self.relays.EAST = true
		self:_emit({ type = "Power", on = true })
		self:_emit({ type = "Cue", cue = "PowerOn" })
	elseif flag == "extraction_open" then
		if self.phase == "Active" then
			self.phase = "ExtractionAvailable"
			self:_emit({ type = "Phase", phase = self.phase })
		end
		self.doorOverrides.D_Freight = false
		self:_emit({ type = "Door", door = "D_Freight", locked = false, open = true })
	end

	self:_refreshDoors()
	self:_refreshLights(now)
	self:_dirty()
	return true
end

function MissionCore:_doorLocked(doorId)
	if self.loopLocks[doorId] then
		return true
	end
	local override = self.doorOverrides[doorId]
	if override ~= nil then
		return override
	end
	local rule = self.case.doorLocks[doorId]
	if not rule then
		return false
	end
	if rule.unlockFlag and self.flags[rule.unlockFlag] then
		return false
	end
	return rule.locked == true
end

function MissionCore:doorLockReason(doorId)
	if self.loopLocks[doorId] then
		return "It won't open. The room is repeating."
	end
	local rule = self.case.doorLocks[doorId]
	if self.doorOverrides[doorId] == true and doorId == "D_CR_NH" then
		return "Jammed. The room is replaying an earlier version of itself."
	end
	return (rule and rule.reason) or "Locked."
end

function MissionCore:_refreshDoors()
	local ids = {}
	for id in self.case.doorLocks do
		ids[id] = true
	end
	for id in self.doorOverrides do
		ids[id] = true
	end
	for id in self.loopLocks do
		ids[id] = true
	end
	for id in ids do
		local locked = self:_doorLocked(id)
		if self.doorState[id] ~= locked then
			self.doorState[id] = locked
			self:_emit({ type = "Door", door = id, locked = locked })
		end
	end
end

function MissionCore:isDoorLocked(doorId)
	return self.doorState[doorId] == true
end

function MissionCore:_roomLightMode(roomId, room, now)
	local override = self.lightOverrides[roomId]
	if override and now < override.untilTime then
		return override.mode
	end
	local powered = self.flags.generator_restored
	if powered and room.lights ~= "none" then
		return "on"
	end
	if room.emergency then
		return "emergency"
	end
	return "off"
end

function MissionCore:_refreshLights(now)
	for _, roomId in MapLayout.StationRooms do
		local mode = self:_roomLightMode(roomId, MapLayout.Rooms[roomId], now)
		if self.lights[roomId] ~= mode then
			self.lights[roomId] = mode
			self:_emit({ type = "Lights", room = roomId, mode = mode })
		end
	end
end

function MissionCore:addNoise(amount, userId)
	if not ACTIVE_PHASES[self.phase] then
		return
	end
	self.awareness += amount * (self.modeDef.awarenessScale or 1)
	if userId then
		self.lastNoiseUser = userId
	end
end

function MissionCore:participant(userId)
	return self.participants[key(userId)]
end

function MissionCore:isAlive(userId)
	local p = self:participant(userId)
	return p ~= nil and p.status == "Alive"
end

function MissionCore:_counts()
	local alive, extracted, eliminated, total = 0, 0, 0, 0
	for _, k in self.participantOrder do
		local p = self.participants[k]
		if p.status ~= "Disconnected" then
			total += 1
			if p.status == "Alive" then
				alive += 1
			elseif p.status == "Extracted" then
				extracted += 1
			elseif p.status == "Eliminated" then
				eliminated += 1
			end
		end
	end
	return alive, extracted, eliminated, total
end

function MissionCore:activeParticipantCount()
	local _, _, _, total = self:_counts()
	return total
end

---------------------------------------------------------------------------
-- Participants
---------------------------------------------------------------------------

function MissionCore:addParticipant(userId, name, now)
	local k = key(userId)
	local existing = self.participants[k]
	if existing then
		if existing.status == "Disconnected" then
			return false, "You left this case. Wait for the next one."
		end
		return false, "Already part of the case."
	end
	if not PLAYABLE_PHASES[self.phase] or self.flags.transmitter_armed then
		return false, "This case is too far along to join."
	end
	if self:activeParticipantCount() >= (self.case.maxParticipants or 4) then
		return false, "The team is full."
	end
	self.participants[k] = {
		userId = userId,
		name = name,
		status = "Alive",
		joinedAt = now,
		items = 0,
		evidence = 0,
		frames = 0,
		revivesUsed = 0,
		invulnerableUntil = 0,
	}
	table.insert(self.participantOrder, k)
	self:_dirty()
	return true
end

function MissionCore:removeParticipant(userId, now)
	local p = self:participant(userId)
	if not p or p.status == "Disconnected" then
		return
	end
	p.status = "Disconnected"
	self.deckUsers[key(userId)] = nil
	self:_notify(p.name .. " lost contact with the team.")
	self:_dirty()
	self:_checkEnd(now)
end

---------------------------------------------------------------------------
-- Interactions
---------------------------------------------------------------------------

local function componentHints(self)
	local hints = {}
	for _, id in self.case.components do
		if not self.inventory[id] then
			table.insert(hints, self.case.items[id].hint)
		end
	end
	return table.concat(hints, " · ")
end

function MissionCore:_componentsHeld()
	local n = 0
	for _, id in self.case.components do
		if self.inventory[id] then
			n += 1
		end
	end
	return n
end

function MissionCore:_evidenceCounts()
	local found = 0
	for _, id in self.case.optionalEvidence do
		if self.inventory[id] then
			found += 1
		end
	end
	return found, #self.case.optionalEvidence
end

function MissionCore:_giveItem(userId, itemId, now)
	if self.inventory[itemId] then
		return false
	end
	local item = self.case.items[itemId]
	local p = self:participant(userId)
	self.inventory[itemId] = { by = userId, name = p and p.name or "?", at = now }
	if p then
		if item.kind == "Evidence" then
			p.evidence += 1
		else
			p.items += 1
		end
	end
	if item.kind == "Tape" then
		self.stats.tapesFound[item.tape] = true
		self:_emit({ type = "Unlock", tape = item.tape, userIds = self:_teamUserIds() })
	end
	if item.kind == "Evidence" then
		self.stats.evidenceFound[item.evidence] = true
		self:_emit({ type = "Unlock", evidence = item.evidence, userIds = self:_teamUserIds() })
	end
	self:_emit({ type = "Item", item = itemId, present = false })
	self:_notify(string.format("%s recovered %s.", p and p.name or "Someone", item.label))
	self:setFlag("item_" .. itemId, now)
	if itemId == "BOARD" then
		self:setFlag("board_recovered", now)
	end
	if self:_componentsHeld() == #self.case.components then
		self:setFlag("components_complete", now)
	end
	local found, total = self:_evidenceCounts()
	if found == total then
		self:setFlag("all_evidence", now)
	end
	if item.bonus then
		-- The bonus tape is never free: the studio lights go to air and it comes.
		self:_emit({ type = "Cue", cue = "OnAir", room = "StudioA" })
		self:_subtitle("[ON AIR LIGHT — STUDIO A]", "cue")
		self:_emit({
			type = "Presenter",
			scripted = false,
			startTime = now,
			eventId = "bonus_tape",
			command = {
				kind = "Ambush",
				-- Far corner from the only door, so the exit is always reachable.
				pos = MapLayout.point("StudioA", 0.15, 0.12),
				look = MapLayout.point("StudioA", 0.5, 0.3),
				radius = 60,
				windup = 2.5,
				maxDuration = 35,
			},
		})
	end
	self:_dirty()
	return true
end

function MissionCore:_teamUserIds()
	local ids = {}
	for _, k in self.participantOrder do
		local p = self.participants[k]
		if p.status ~= "Disconnected" then
			table.insert(ids, p.userId)
		end
	end
	return ids
end

function MissionCore:_deckAvailable(deckId)
	local deck = self.case.decks[deckId]
	if not deck then
		return false, "Unknown deck."
	end
	if not deck.battery and not self.flags.generator_restored then
		return false, deck.label .. " has no power. Restore the generator first."
	end
	return true
end

function MissionCore:deckAvailable(deckId)
	return self:_deckAvailable(deckId)
end

--[[
	Prompt presentation for an interactable: { visible, action, object, hold }.
	The glue mirrors this onto ProximityPrompts whenever the version changes.
]]
function MissionCore:promptState(id)
	local def = self.interactables[id]
	if not def then
		return { visible = false }
	end
	local kind = def.kind
	local flags = self.flags
	if kind == "Pickup" then
		local item = self.case.items[def.item]
		local visible = not self.inventory[def.item] and (not item.visibleFlag or flags[item.visibleFlag] == true)
		return { visible = visible, action = "Take", object = item.label, hold = 0 }
	elseif kind == "Deck" then
		local ok = self:_deckAvailable(def.deck)
		return { visible = true, action = ok and "Open Deck" or "No Power", object = def.object, hold = 0 }
	elseif kind == "Briefing" then
		return { visible = true, action = "Replay Briefing", object = def.object, hold = 0 }
	elseif kind == "Generator" then
		if self.generatorStage == 0 then
			return { visible = true, action = "Prime Fuel Pump", object = "Generator · UNPOWERED", hold = 2.5 }
		elseif self.generatorStage == 1 then
			return { visible = true, action = "Pull Starter", object = "Generator · PRIMED", hold = 5 }
		end
		return { visible = false }
	elseif kind == "Cage" then
		if self.keypad.opened then
			return { visible = false }
		end
		return { visible = true, action = "Enter Code", object = def.object, hold = 0 }
	elseif kind == "Relay" then
		if self.relays[def.relay] or not flags.generator_restored then
			return { visible = false }
		end
		return { visible = true, action = "Reset Relay", object = def.relay .. " RELAY · TRIPPED", hold = 2 }
	elseif kind == "BoardRack" then
		if self.inventory.BOARD then
			return { visible = false }
		elseif self.loop.solved then
			return { visible = true, action = "Take Sync Board", object = def.object, hold = 0 }
		elseif self.loop.active then
			return { visible = true, action = "Sealed", object = def.object, hold = 0 }
		end
		return { visible = true, action = "Open Rack", object = def.object, hold = 0 }
	elseif kind == "LoopProp" then
		return { visible = self.loop.active, action = "Inspect", object = def.object, hold = 0 }
	elseif kind == "Socket" then
		if self.installed[def.item] then
			return { visible = false }
		end
		local label = self.case.items[def.item].label
		return {
			visible = true,
			action = self.inventory[def.item] and ("Install " .. label) or ("Needs " .. label),
			object = def.object,
			hold = self.inventory[def.item] and 1.5 or 0,
		}
	elseif kind == "Lever" then
		local visible = flags.freight_jammed == true and not flags.extraction_open
		return { visible = visible, action = "Restart Motor", object = def.object, hold = 8 }
	elseif kind == "Van" then
		return { visible = self.phase == "ExtractionAvailable", action = "Leave the Station", object = def.object, hold = 2 }
	end
	return { visible = false }
end

-- Returns ok, message (message is shown to the acting player).
function MissionCore:interact(userId, id, now)
	local def = self.interactables[id]
	if not def then
		return false, "Nothing to do here."
	end
	if not PLAYABLE_PHASES[self.phase] then
		return false, "The case is over."
	end
	local p = self:participant(userId)
	if not p or p.status ~= "Alive" then
		return false, "Spectators cannot interact."
	end
	local kind = def.kind
	local state = self:promptState(id)
	if not state.visible then
		return false, "Nothing to do here."
	end

	if kind == "Pickup" then
		self:_giveItem(userId, def.item, now)
		return true
	elseif kind == "Deck" then
		local ok, reason = self:_deckAvailable(def.deck)
		if not ok then
			return false, reason
		end
		self:_emit({ type = "OpenDeck", userId = userId, deck = def.deck })
		return true
	elseif kind == "Briefing" then
		self:_emit({ type = "Briefing", userId = userId })
		return true
	elseif kind == "Generator" then
		if self.phase == "Briefing" then
			return false, "Wait for the briefing to finish."
		end
		if self.generatorStage == 0 then
			self.generatorStage = 1
			self:addNoise(10, userId)
			self:_subtitle("[FUEL PUMP RATTLES]", "cue")
			self:_emit({ type = "Cue", cue = "GeneratorPrime", room = "Generator" })
			self:_dirty()
			return true
		elseif self.generatorStage == 1 then
			self.generatorStage = 2
			self:addNoise(20, userId)
			self:_subtitle("[GENERATOR ROARS TO LIFE]", "cue")
			self:setFlag("generator_restored", now)
			return true
		end
		return false, "Already running."
	elseif kind == "Cage" then
		if not self.flags.generator_restored then
			return false, "The keypad is dark. Restore power first."
		end
		if now < self.keypad.lockoutUntil then
			return false, "Keypad locked. Wait a few seconds."
		end
		self:_emit({ type = "OpenKeypad", userId = userId })
		return true
	elseif kind == "Relay" then
		self.relays[def.relay] = true
		self:addNoise(5, userId)
		self:_subtitle("[RELAY CLICKS BACK ON]", "cue")
		self:_emit({ type = "Relay", relay = def.relay, on = true })
		self:_dirty()
		return true
	elseif kind == "BoardRack" then
		if self.loop.solved then
			self:_giveItem(userId, "BOARD", now)
			return true
		elseif self.loop.active then
			return false, "The rack is sealed. The room is repeating."
		end
		if not self.flags.generator_restored then
			return false, "The rack's maglock has no power."
		end
		self:_startLoop(now)
		return true
	elseif kind == "LoopProp" then
		return self:_inspectLoopProp(userId, def, now)
	elseif kind == "Socket" then
		if not self.inventory[def.item] then
			return false, "You need the " .. self.case.items[def.item].label .. "."
		end
		self.installed[def.item] = true
		self:_subtitle("[COMPONENT SEATS WITH A CLUNK]", "cue")
		self:_emit({ type = "Cue", cue = "Install", item = def.item })
		local all = true
		for _, comp in self.case.components do
			if not self.installed[comp] then
				all = false
			end
		end
		if all then
			self:_emit({ type = "Cue", cue = "TransmitterArmed", room = "Transmitter" })
			self:setFlag("transmitter_armed", now)
		end
		self:_dirty()
		return true
	elseif kind == "Lever" then
		self.doorOverrides.D_Freight = false
		self:_emit({ type = "Door", door = "D_Freight", locked = false, open = true })
		self:_subtitle("[FREIGHT MOTOR CATCHES — DOOR RISING]", "cue")
		self:addNoise(15, userId)
		self:setFlag("extraction_open", now)
		return true
	elseif kind == "Van" then
		return self:extract(userId, now)
	end
	return false, "Nothing to do here."
end

---------------------------------------------------------------------------
-- The Loop
---------------------------------------------------------------------------

function MissionCore:_startLoop(now)
	local loop = self.loop
	loop.active = true
	loop.cycleStart = now
	for _, doorId in self.case.loop.doors do
		self.loopLocks[doorId] = true
	end
	self:_subtitle("[DOORS SLAM — THE ARCHIVE GOES QUIET]", "cue")
	self:_emit({ type = "Cue", cue = "LoopStart", room = self.case.loop.room })
	self:setFlag("loop_active", now)
	self:_refreshDoors()
	self:_dirty()
end

function MissionCore:loopCycle(now)
	local loop = self.loop
	local length = self.case.loop.cycleLength
	local index = math.floor((now - loop.cycleStart) / length) + 1
	return index, index % 2 == 0
end

function MissionCore:_inspectLoopProp(_userId, def, now)
	local loop = self.loop
	if not loop.active then
		return false, "Nothing unusual."
	end
	local _, oddNow = self:loopCycle(now)
	local _, oddBefore = self:loopCycle(now - (self.case.loop.tolerance or 0))
	local prop
	for _, candidate in self.case.loop.props do
		if candidate.id == def.prop then
			prop = candidate
		end
	end
	if def.prop == loop.odd and (oddNow or oddBefore) then
		loop.active = false
		loop.solved = true
		self.stats.loopFirstTry = loop.attempts == 0
		self.stats.anomaliesIdentified += 1
		self.loopLocks = {}
		self:_subtitle(string.format("The %s was %s. The loop breaks.", string.lower(prop.label), prop.odd), "event")
		self:_emit({ type = "Cue", cue = "LoopBreak", room = self.case.loop.room })
		self:setFlag("loop_solved", now)
		self:_refreshDoors()
		self:_dirty()
		return true
	end
	loop.attempts += 1
	loop.cycleStart = now
	self:_subtitle(string.format("Nothing is wrong with the %s. The loop resets.", string.lower(prop.label)), "event")
	self:_emit({ type = "Cue", cue = "LoopReset", room = self.case.loop.room })
	self:_dirty()
	return false, "Wrong detail. The loop resets — watch two full cycles."
end

---------------------------------------------------------------------------
-- Keypad (the Caller lies about the code)
---------------------------------------------------------------------------

function MissionCore:submitCode(userId, code, now)
	if not self:isAlive(userId) then
		return false, "Spectators cannot interact."
	end
	if self.keypad.opened then
		return true
	end
	if not self.flags.generator_restored then
		return false, "The keypad is dark."
	end
	if now < self.keypad.lockoutUntil then
		return false, "Keypad locked. Wait a few seconds."
	end
	if type(code) ~= "string" or #code ~= (self.case.keypad.digits or 4) or not string.match(code, "^%d+$") then
		return false, "Enter all digits."
	end
	if code == self.variants.code then
		self.keypad.opened = true
		if not self.stats.callerFooled then
			self.stats.anomaliesIdentified += 1
		end
		self:_subtitle("[CAGE LOCK RELEASES]", "cue")
		self:_emit({ type = "Cue", cue = "CageOpen", room = "Generator" })
		self:_giveItem(userId, "VALVE", now)
		self:_dirty()
		return true
	end
	if code == self.variants.fakeCode then
		self.stats.callerFooled = true
	end
	self.keypad.wrongAttempts += 1
	self.keypad.lockoutUntil = now + (self.case.keypad.lockout or 5)
	self:addNoise(self.case.keypad.alarmAwareness or 35, userId)
	self:_subtitle("[ALARM BELL — GENERATOR ROOM]", "cue")
	self:_emit({ type = "Cue", cue = "Alarm", room = "Generator" })
	self:_dirty()
	return false, "Wrong code. The alarm is ringing."
end

---------------------------------------------------------------------------
-- Decks and editing
---------------------------------------------------------------------------

function MissionCore:tapeFound(tapeId)
	return self.stats.tapesFound[tapeId] == true
end

function MissionCore:deckOpened(userId, deckId, tapeId, now)
	if not self:isAlive(userId) then
		return false
	end
	local ok = self:_deckAvailable(deckId)
	if not ok then
		return false
	end
	self.deckUsers[key(userId)] = deckId
	if tapeId and self:tapeFound(tapeId) then
		self:setFlag("viewed_" .. tapeId, now)
	end
	return true
end

function MissionCore:deckClosed(userId)
	self.deckUsers[key(userId)] = nil
end

-- The handheld monitor shows live cameras anywhere; watching it raises awareness
-- like a deck does, but it can never be used to edit.
function MissionCore:setWatching(userId, watching)
	if watching and self:isAlive(userId) then
		self.deckUsers[key(userId)] = "HANDHELD"
	elseif self.deckUsers[key(userId)] == "HANDHELD" then
		self.deckUsers[key(userId)] = nil
	end
end

function MissionCore:inspectEvent(userId, eventId, now)
	local ev = self.timeline:getEvent(eventId)
	if not ev or not self:participant(userId) then
		return
	end
	if not self:tapeFound(ev.tape) then
		return
	end
	local rec = self.timeline.records[eventId]
	if not rec.fired and not self.stats.inspected[eventId] then
		self.stats.inspected[eventId] = now
		self:_dirty()
	end
end

--[[
	ctx = { deckId, expectedState, signalOk }
	Returns ok, code, message. Nothing is spent unless ok.
]]
function MissionCore:commitEdit(userId, eventId, newState, ctx, now)
	ctx = ctx or {}
	if not PLAYABLE_PHASES[self.phase] then
		return false, "PHASE", "The case is over."
	end
	local p = self:participant(userId)
	if not p or p.status ~= "Alive" then
		return false, "SPECTATOR", "Spectators can watch the timeline but cannot edit it."
	end
	if not ctx.deckId then
		return false, "NO_DECK", "Edits are made at a tape deck."
	end
	local deckOk, deckReason = self:_deckAvailable(ctx.deckId)
	if not deckOk then
		return false, "NO_DECK", deckReason
	end
	local ev = self.timeline:getEvent(eventId)
	if ctx.signalOk == false then
		return false, "SIGNAL", "Signal too weak to edit. Reset the relay or try another camera."
	end
	local ok, code, message = self.timeline:validateEdit(eventId, newState, now, {
		flags = self.flags,
		charges = self.charges,
		tapeFound = ev ~= nil and self:tapeFound(ev.tape),
		expectedState = ctx.expectedState,
	})
	if not ok then
		return false, code, message
	end
	local cost = ev.editCost or 1
	-- Atomic within this call: validate -> deduct -> commit.
	self.charges -= cost
	local entry = self.timeline:commit(eventId, newState, userId, p.name, now)
	self.stats.editsMade += 1
	if not self.stats.inspected[eventId] then
		self.stats.inspected[eventId] = now
	end
	self:addNoise(AWARENESS_EDIT, userId)
	self:setFlag("decided_" .. eventId, now)
	self:_emit({ type = "Cue", cue = "EditCommitted", eventId = eventId, userId = userId, entry = entry })
	local label = ev.stateLabels[newState] or newState
	self:_notify(string.format("%s edited %s: %s", p.name, ev.label, label))
	self:_dirty()
	return true, "OK", nil
end

---------------------------------------------------------------------------
-- Hidden frames
---------------------------------------------------------------------------

function MissionCore:markFrame(userId, tapeId, cameraId, t, _now)
	if not self:participant(userId) then
		return false, "Not part of this case."
	end
	if not self:tapeFound(tapeId) then
		return false, "Your team does not have that tape."
	end
	for _, hf in self.case.hiddenFrames do
		if hf.tape == tapeId and hf.camera == cameraId and type(t) == "number" and math.abs(t - hf.t) <= (hf.window or 0.5) then
			if self.stats.framesMarked[hf.id] then
				return false, "Already marked."
			end
			self.stats.framesMarked[hf.id] = userId
			local p = self:participant(userId)
			p.frames += 1
			self:_emit({ type = "Unlock", frame = hf.id, userIds = { userId } })
			self:_notify(string.format("%s marked a hidden frame: %s", p.name, hf.text))
			self:_dirty()
			return true, hf.id
		end
	end
	return false, "Nothing unusual on this frame."
end

---------------------------------------------------------------------------
-- Eliminations, revives, extraction
---------------------------------------------------------------------------

function MissionCore:isInvulnerable(userId, now)
	local p = self:participant(userId)
	return p ~= nil and now < (p.invulnerableUntil or 0)
end

function MissionCore:eliminate(userId, now, cause)
	local p = self:participant(userId)
	if not p or p.status ~= "Alive" or not PLAYABLE_PHASES[self.phase] then
		return false
	end
	if now < (p.invulnerableUntil or 0) then
		return false
	end
	p.status = "Eliminated"
	p.eliminatedAt = now
	self.stats.eliminations += 1
	local eventId = cause and cause.eventId
	if eventId then
		local ev = self.timeline:getEvent(eventId)
		local sourceId = ev and (ev.derivedFrom or ev.id)
		if sourceId and self.timeline.records[sourceId] and self.timeline.records[sourceId].edits > 0 then
			self.stats.eliminationsDuringEdits += 1
		end
	end
	self.deckUsers[key(userId)] = nil
	self.awareness = 30
	self:_emit({ type = "Eliminated", userId = userId })
	self:_notify(string.format("SIGNAL LOST — %s", string.upper(p.name)))
	self:_dirty()
	self:_checkEnd(now)
	return true
end

function MissionCore:canRevive(userId, kind)
	local p = self:participant(userId)
	if not p or p.status ~= "Eliminated" then
		return false, "Only eliminated investigators can re-enter."
	end
	if not PLAYABLE_PHASES[self.phase] then
		return false, "The case is over."
	end
	if self.teamTokenUsed then
		return false, "The team recovery has been used. No more re-entries this case."
	end
	if kind == "Personal" and p.revivesUsed >= 1 then
		return false, "You have already re-entered once this case."
	end
	return true
end

function MissionCore:canTeamRecover()
	if not PLAYABLE_PHASES[self.phase] then
		return false, "The case is over."
	end
	if self.teamTokenUsed then
		return false, "Already used this case."
	end
	local alive, _, eliminated = self:_counts()
	if eliminated == 0 then
		return false, "Nobody needs recovering."
	end
	if alive == 0 then
		return false, "Someone still inside has to call it in."
	end
	return true
end

-- Checkpoints unlocked so far, most advanced first.
function MissionCore:checkpoints()
	local list = {}
	for _, cp in self.case.checkpoints do
		if not cp.requires or self.flags[cp.requires] then
			table.insert(list, cp)
		end
	end
	return list
end

function MissionCore:_reviveOne(p, now)
	p.status = "Alive"
	p.invulnerableUntil = now + REVIVE_INVULNERABILITY
	self.failPendingUntil = nil
	self:_emit({ type = "Revive", userId = p.userId, invulnerableUntil = p.invulnerableUntil, checkpoints = self:checkpoints() })
	self:_notify(string.format("%s re-entered the station.", p.name))
end

function MissionCore:revive(userId, now, kind)
	local ok, reason = self:canRevive(userId, kind)
	if not ok then
		return false, reason
	end
	local p = self:participant(userId)
	if kind == "Personal" then
		p.revivesUsed += 1
	end
	self:_reviveOne(p, now)
	self:_dirty()
	return true
end

function MissionCore:teamRecover(now)
	local ok, reason = self:canTeamRecover()
	if not ok then
		return false, reason
	end
	self.teamTokenUsed = true
	for _, k in self.participantOrder do
		local p = self.participants[k]
		if p.status == "Eliminated" then
			self:_reviveOne(p, now)
		end
	end
	self:_dirty()
	return true
end

function MissionCore:extract(userId, now)
	if self.phase ~= "ExtractionAvailable" then
		return false, "The freight door is still closed."
	end
	local p = self:participant(userId)
	if not p or p.status ~= "Alive" then
		return false, "Spectators cannot extract."
	end
	p.status = "Extracted"
	p.extractedAt = now
	self.deckUsers[key(userId)] = nil
	self:_emit({ type = "Extracted", userId = userId })
	self:_notify(string.format("%s boarded the van.", p.name))
	self:_dirty()
	self:_checkEnd(now)
	return true
end

function MissionCore:_checkEnd(now)
	if not PLAYABLE_PHASES[self.phase] then
		return
	end
	local alive, extracted, eliminated, total = self:_counts()
	if total == 0 then
		self:_finish(now, "Aborted", "Everyone left.")
		return
	end
	if alive > 0 then
		self.failPendingUntil = nil
		return
	end
	if extracted > 0 then
		self:_finish(now, eliminated == 0 and "Success" or "Partial", nil)
		return
	end
	-- Everyone is down. Leave a short window for an optional re-entry.
	if not self.failPendingUntil then
		self.failPendingUntil = now + FAIL_GRACE
		self:_dirty()
	elseif now >= self.failPendingUntil then
		self:_finish(now, "Failed", "The whole team went off-air.")
	end
end

---------------------------------------------------------------------------
-- Update loop
---------------------------------------------------------------------------

local function resolveTokens(self, text)
	text = string.gsub(text, "{code}", self.variants.code)
	text = string.gsub(text, "{fakeCode}", self.variants.fakeCode)
	return text
end

function MissionCore:_radio(now, msg, index)
	local channelDef = self.case.radioChannels[msg.source]
	local live = self:broadcastClock(now)
	local stamped = live
	if type(msg.stamp) == "number" then
		stamped = math.max(0, live + msg.stamp)
	end
	local entry = {
		index = index,
		time = now,
		stamp = Format.clock(stamped),
		sourceId = channelDef.id,
		channel = channelDef.channel,
		text = resolveTokens(self, msg.text),
		caller = msg.source == "CALLER",
	}
	table.insert(self.radioLog, entry)
	while #self.radioLog > 8 do
		table.remove(self.radioLog, 1)
	end
	self:_emit({
		type = "Subtitle",
		kind = "radio",
		text = entry.text,
		stamp = entry.stamp,
		sourceId = entry.sourceId,
		channel = entry.channel,
		caller = entry.caller,
	})
	self:_dirty()
end

function MissionCore:_applyTimelineOutput(output, now)
	if output.kind == "fired" then
		self:setFlag("fired_" .. output.eventId, now)
		return
	end
	if output.kind == "presenter" then
		self:_emit({
			type = "Presenter",
			scripted = true,
			command = output.command,
			startTime = output.startTime,
			eventId = output.eventId,
		})
		return
	end
	local action = output.action
	if action.type == "Lights" then
		self.lightOverrides[action.room] = {
			mode = action.mode,
			untilTime = action.duration and (output.time + action.duration) or math.huge,
		}
		self:_refreshLights(now)
	elseif action.type == "Door" then
		self.doorOverrides[action.door] = action.locked
		if action.open then
			self:_emit({ type = "Door", door = action.door, locked = action.locked, open = true })
		end
		self:_refreshDoors()
	elseif action.type == "Relay" then
		self.relays[action.relay] = action.on
		self:_emit({ type = "Relay", relay = action.relay, on = action.on })
		if not action.on then
			self:_subtitle("[" .. action.relay .. " RELAY TRIPS]", "cue")
		end
	elseif action.type == "Cue" then
		local cue = table.clone(action)
		cue.type = "Cue"
		cue.eventId = output.eventId
		if action.event then
			local rec = self.timeline.records[action.event]
			cue.userId = rec and rec.committedBy or nil
		end
		self:_emit(cue)
	elseif action.type == "Subtitle" then
		self:_subtitle(action.text, action.kind)
	elseif action.type == "Flag" then
		self:setFlag(action.flag, now)
	end
	self:_dirty()
end

--[[
	world = { presenterIdle = boolean }
]]
function MissionCore:update(now, world)
	world = world or {}
	if self.phase == "Briefing" then
		for i, line in self.case.briefing.lines do
			if not self.briefingDone[i] and now >= self.createdAt + line.at then
				self.briefingDone[i] = true
				self:_emit({
					type = "Subtitle",
					kind = "radio",
					text = line.text,
					stamp = "00:00:00",
					sourceId = self.case.radioChannels.HQ.id,
					channel = self.case.radioChannels.HQ.channel,
					caller = false,
				})
			end
		end
		if now >= self.briefingEnd then
			self.phase = "Active"
			self.broadcastStart = now
			self:_emit({ type = "Phase", phase = "Active" })
			self:_emit({ type = "Cue", cue = "BroadcastStart" })
			self:setFlag("broadcast_start", now)
			self:_dirty()
		end
	end

	if PLAYABLE_PHASES[self.phase] then
		for _, output in self.timeline:update(now) do
			self:_applyTimelineOutput(output, now)
		end

		for i, msg in self.case.radio do
			if not self.radioDone[i] then
				local t = self.flagTimes[msg.anchor]
				if t and now >= t + msg.offset then
					self.radioDone[i] = true
					self:_radio(now, msg, i)
				end
			end
		end

		self:_refreshLights(now)
	end

	if ACTIVE_PHASES[self.phase] then
		local dt = math.max(0, now - (self.lastUpdate or now))
		self.awareness = math.max(0, self.awareness - AWARENESS_DECAY * dt)
		for userKey in self.deckUsers do
			self.awareness += AWARENESS_DECK * dt * (self.modeDef.awarenessScale or 1)
			self.lastNoiseUser = self.lastNoiseUser or tonumber(userKey)
		end
		if
			self.awareness >= AWARENESS_THRESHOLD
			and world.presenterIdle
			and now - self.lastObserveAt >= OBSERVE_COOLDOWN
		then
			local target = self.lastNoiseUser
			if not (target and self:isAlive(target)) then
				target = nil
				for _, k in self.participantOrder do
					if self.participants[k].status == "Alive" then
						target = self.participants[k].userId
						break
					end
				end
			end
			if target then
				self.lastObserveAt = now
				self.awareness = 35
				self:_emit({ type = "ObserveNear", userId = target, startTime = now })
			end
		end

		if self.broadcastStart and now - self.broadcastStart > self.case.timeLimit then
			self:_finish(now, "Failed", "The broadcast ended with the team still inside.")
		end
	end

	if PLAYABLE_PHASES[self.phase] then
		self:_checkEnd(now)
	end
	self.lastUpdate = now
end

---------------------------------------------------------------------------
-- Objectives and snapshot
---------------------------------------------------------------------------

function MissionCore:_resolveObjectiveText(text)
	local tl = self.timeline
	text = string.gsub(text, "{mark:([%w_]+)}", function(eventId)
		local ev = tl:getEvent(eventId)
		if not ev then
			return "?"
		end
		local anchor = tl:anchorTime(ev.anchor)
		if anchor and self.broadcastStart then
			return Format.clock(anchor - self.broadcastStart + ev.offset)
		end
		return Format.relative(ev.offset)
	end)
	text = string.gsub(text, "{time:([%w_]+)}", function(eventId)
		local fire = tl:fireTime(eventId)
		if fire and self.broadcastStart then
			return Format.clock(fire - self.broadcastStart)
		end
		local ev = tl:getEvent(eventId)
		return ev and Format.relative(ev.offset) or "?"
	end)
	local found, total = self:_evidenceCounts()
	text = string.gsub(text, "{components}", tostring(self:_componentsHeld()))
	text = string.gsub(text, "{componentHints}", componentHints(self))
	text = string.gsub(text, "{evidenceTotal}", tostring(total))
	text = string.gsub(text, "{evidence}", tostring(found))
	return text
end

function MissionCore:currentObjective()
	for _, obj in self.case.objectives do
		local done = self.flags[obj.doneFlag] or (obj.altDoneFlag and self.flags[obj.altDoneFlag])
		local shown = not obj.showFlag or self.flags[obj.showFlag]
		if not done and shown then
			return {
				id = obj.id,
				text = self:_resolveObjectiveText(obj.text),
				clue = (self.modeDef.showClues and obj.clue) and self:_resolveObjectiveText(obj.clue) or nil,
			}
		end
	end
	return nil
end

function MissionCore:optionalObjectives()
	local list = {}
	for _, obj in self.case.optionalObjectives or {} do
		if (not obj.showFlag or self.flags[obj.showFlag]) and not self.flags[obj.doneFlag] then
			table.insert(list, self:_resolveObjectiveText(obj.text))
		end
	end
	return list
end

function MissionCore:snapshot(now)
	local participants = {}
	for _, k in self.participantOrder do
		local p = self.participants[k]
		participants[k] = {
			name = p.name,
			status = p.status,
			invulnerableUntil = p.invulnerableUntil,
			revivesUsed = p.revivesUsed,
		}
	end
	local inventory = {}
	for itemId, entry in self.inventory do
		inventory[itemId] = entry.name
	end
	local flags = {}
	for flag in self.flags do
		flags[flag] = true
	end
	local doors = table.clone(self.doorState)
	return {
		caseId = self.case.id,
		mode = self.mode,
		modeLabel = self.modeDef.label,
		phase = self.phase,
		version = self.version,
		createdAt = self.createdAt,
		briefingEnd = self.briefingEnd,
		broadcastStart = self.broadcastStart,
		timeLimit = self.case.timeLimit,
		charges = self.charges,
		maxCharges = self.maxCharges,
		flags = flags,
		inventory = inventory,
		installed = table.clone(self.installed),
		participants = participants,
		objective = self:currentObjective(),
		optional = self:optionalObjectives(),
		radioLog = self.radioLog,
		loop = {
			active = self.loop.active,
			solved = self.loop.solved,
			cycleStart = self.loop.cycleStart,
			cycleLength = self.case.loop.cycleLength,
			odd = self.loop.active and self.loop.odd or nil,
		},
		keypad = { opened = self.keypad.opened, lockoutUntil = self.keypad.lockoutUntil },
		generatorStage = self.generatorStage,
		relays = table.clone(self.relays),
		doors = doors,
		lights = table.clone(self.lights),
		patrolFlip = self.variants.patrolFlip,
		timeline = self.timeline:snapshot(now),
		teamTokenUsed = self.teamTokenUsed,
		failPendingUntil = self.failPendingUntil,
		endReason = self.endReason,
	}
end

---------------------------------------------------------------------------
-- Ending and report
---------------------------------------------------------------------------

function MissionCore:_finish(now, result, reason)
	if not PLAYABLE_PHASES[self.phase] then
		return
	end
	self.endedAt = now
	self.endReason = reason
	if result == "Aborted" then
		self.phase = "Aborted"
		self:_emit({ type = "Phase", phase = "Aborted" })
		self:_dirty()
		return
	end
	self.phase = (result == "Failed") and "Failed" or "Completed"
	self.report = self:_buildReport(now, result)
	self:_emit({ type = "Phase", phase = self.phase })
	self:_emit({ type = "Report", report = self.report })
	self:_dirty()
end

function MissionCore:_buildReport(now, result)
	local case = self.case
	local participants = {}
	local survivors, counted = 0, 0
	for _, k in self.participantOrder do
		local p = self.participants[k]
		if p.status ~= "Disconnected" then
			counted += 1
			if p.status == "Extracted" or p.status == "Alive" then
				survivors += 1
			end
		end
		table.insert(participants, {
			userId = p.userId,
			name = p.name,
			status = p.status,
			items = p.items,
			evidence = p.evidence,
			frames = p.frames,
		})
	end

	-- Predictions: events on recovered tapes that someone inspected before they fired.
	local predictionsTotal, interpreted = 0, 0
	for _, ev in case.events do
		if self:tapeFound(ev.tape) then
			predictionsTotal += 1
			local seenAt = self.stats.inspected[ev.id]
			local fire = self.timeline:fireTime(ev.id)
			if seenAt and (not fire or seenAt <= fire) then
				interpreted += 1
			end
		end
	end

	local evidenceFound, evidenceTotal = self:_evidenceCounts()
	local tapesFound = 0
	for _ in self.stats.tapesFound do
		tapesFound += 1
	end

	local gradeStats = {
		result = result,
		participants = counted,
		survivors = survivors,
		evidenceFound = evidenceFound,
		evidenceTotal = evidenceTotal,
		predictionsInterpreted = interpreted,
		predictionsTotal = predictionsTotal,
		editsMade = self.stats.editsMade,
		maxCharges = self.maxCharges,
		eliminationsDuringEdits = self.stats.eliminationsDuringEdits,
		loopFirstTry = self.stats.loopFirstTry,
		callerFooled = self.stats.callerFooled,
	}
	local grading = Grading.compute(gradeStats)
	local bonusExtracted = self.inventory.TAPE07 ~= nil and result ~= "Failed"

	local edits = {}
	for _, entry in self.timeline.editLog do
		local ev = self.timeline:getEvent(entry.eventId)
		table.insert(edits, {
			label = ev.label,
			from = ev.stateLabels[entry.from] or entry.from,
			to = ev.stateLabels[entry.to] or entry.to,
			by = entry.byName,
		})
	end

	local teamChallenges = {}
	local success = result == "Success" or result == "Partial"
	if success and self.charges > 0 then
		table.insert(teamChallenges, "C01_UNUSED")
	end
	if evidenceFound == evidenceTotal then
		table.insert(teamChallenges, "C01_EVIDENCE")
	end
	if result == "Success" then
		table.insert(teamChallenges, "C01_NOLOSS")
	end
	if self.loop.solved and self.stats.loopFirstTry then
		table.insert(teamChallenges, "C01_LOOP")
	end
	if self.keypad.opened and not self.stats.callerFooled then
		table.insert(teamChallenges, "C01_CALLER")
	end
	if next(self.stats.framesMarked) then
		table.insert(teamChallenges, "C01_FRAME")
	end
	if success and counted == 1 then
		table.insert(teamChallenges, "C01_SOLO")
	end
	if success and self.mode == "Restricted" then
		table.insert(teamChallenges, "C01_RESTRICTED")
	end

	local rewards = {}
	for _, entry in participants do
		if entry.status ~= "Disconnected" then
			rewards[key(entry.userId)] = Grading.rewards({
				result = result,
				grade = grading.grade,
				anomaliesIdentified = self.stats.anomaliesIdentified,
				bonusTapeExtracted = bonusExtracted,
			}, {
				itemsRecovered = entry.items,
				evidenceRecovered = entry.evidence,
				framesMarked = entry.frames,
				extracted = entry.status == "Extracted",
			})
		end
	end

	local components = {}
	for _, id in case.components do
		components[id] = self.inventory[id] ~= nil
	end

	return {
		caseId = case.id,
		title = case.title,
		mode = self.mode,
		modeLabel = self.modeDef.label,
		seed = self.seed,
		result = result,
		reason = self.endReason,
		grade = grading.grade,
		score = grading.score,
		breakdown = grading.breakdown,
		components = components,
		componentsCount = self:_componentsHeld(),
		componentsInstalled = self.flags.transmitter_armed == true,
		tapesFound = tapesFound,
		tapesTotal = #case.tapeOrder,
		evidenceFound = evidenceFound,
		evidenceTotal = evidenceTotal,
		predictionsInterpreted = interpreted,
		predictionsTotal = predictionsTotal,
		editsMade = self.stats.editsMade,
		maxCharges = self.maxCharges,
		edits = edits,
		eliminations = self.stats.eliminations,
		loopSolved = self.loop.solved,
		loopFirstTry = self.stats.loopFirstTry,
		callerFooled = self.stats.callerFooled,
		bonusTape = bonusExtracted,
		participants = participants,
		rewards = rewards,
		challenges = teamChallenges,
		masterRecording = success and case.masterRecording or nil,
		duration = self.broadcastStart and (now - self.broadcastStart) or 0,
		evidenceIds = (function()
			local ids = {}
			for id in self.stats.evidenceFound do
				table.insert(ids, id)
			end
			table.sort(ids)
			return ids
		end)(),
	}
end

function MissionCore:getReport()
	return self.report
end


return MissionCore
