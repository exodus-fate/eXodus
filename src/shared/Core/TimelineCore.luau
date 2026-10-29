--[[
	TimelineCore — the authoritative model of a case's predicted events.

	Rules (from the design brief):
	  * Footage is a genuine prediction unless players interfere.
	  * Players edit conditions (an event's state), never the monster or the mission.
	  * Every edit has an authored, deterministic consequence: derived events read
	    their state from the event they depend on through a fixed `stateMap`.
	  * Invalid edits never spend charges; no event is edited twice unless its
	    `maxEdits` allows it; once an event (or one of its consequences) starts to
	    play out, its state is locked.

	This module is engine-independent. `update(now)` returns what became due so the
	mission layer can apply it to the world; nothing here touches Roblox.
]]

local TimelineCore = {}
TimelineCore.__index = TimelineCore

TimelineCore.Messages = {
	UNKNOWN_EVENT = "That event is not on this tape.",
	NOT_EDITABLE = "This event cannot be edited directly. It follows from another event.",
	TAPE_MISSING = "Your team has not recovered the tape that holds this event.",
	INVALID_STATE = "That state is not one of this event's allowed alternatives.",
	ALREADY_OCCURRED = "This event has already happened.",
	ALREADY_EDITED = "This event has already been edited.",
	NO_CHANGE = "That is already the predicted state.",
	PREREQUISITE = "This event cannot be edited yet.",
	LOCKED = "Too late. The event is already playing out.",
	NO_CHARGES = "No edit charges left.",
	VERSION = "The timeline changed while you were looking. Review the update first.",
}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end
TimelineCore.deepCopy = deepCopy

local function samePos(a, b)
	return a and b and a.x == b.x and a.z == b.z
end

-- Reverses an A/B patrol by swapping its two end points.
local function flipPatrol(path)
	if #path < 2 then
		return path
	end
	local a, b = path[1].pos, path[2].pos
	for _, key in path do
		if samePos(key.pos, a) then
			key.pos = deepCopy(b)
		elseif samePos(key.pos, b) then
			key.pos = deepCopy(a)
		end
	end
	return path
end

-- Window of time (relative to the anchor) during which an event's Presenter command
-- controls the entity. Used for schedule-conflict validation.
local function presenterWindow(ev, stateDef)
	local cmd = stateDef and stateDef.presenter
	if not cmd then
		return nil
	end
	local start = ev.offset + (cmd.at or 0)
	local length
	if cmd.kind == "Ambush" then
		length = (cmd.windup or 0) + (cmd.maxDuration or 0)
	else
		length = cmd.duration or 0
	end
	return start, start + length
end
TimelineCore.presenterWindow = presenterWindow

function TimelineCore.new(caseDef, options)
	options = options or {}
	local self = setmetatable({}, TimelineCore)
	self.case = caseDef
	self.events = {}
	self.order = {}
	self.records = {}
	self.anchors = {}
	self.version = 0
	self.editLog = {}

	for _, def in caseDef.events do
		local ev = def
		if options.patrolFlip and caseDef.variants and caseDef.variants.patrolFlipEvent == def.id then
			ev = deepCopy(def)
			for _, stateDef in ev.states do
				if stateDef.presenter and stateDef.presenter.path then
					flipPatrol(stateDef.presenter.path)
				end
			end
		end
		self.events[ev.id] = ev
		table.insert(self.order, ev.id)
		self.records[ev.id] = {
			committedState = nil,
			committedBy = nil,
			committedName = nil,
			committedAt = nil,
			edits = 0,
			fired = false,
			lockedState = nil,
			actionsDone = {},
			presenterDone = false,
		}
	end
	return self
end

function TimelineCore:getEvent(id)
	return self.events[id]
end

function TimelineCore:anchorTime(flag)
	return self.anchors[flag]
end

function TimelineCore:setAnchor(flag, now)
	if self.anchors[flag] ~= nil then
		return false
	end
	self.anchors[flag] = now
	self.version += 1
	return true
end

function TimelineCore:fireTime(id)
	local ev = self.events[id]
	local anchor = ev and self.anchors[ev.anchor]
	if not anchor then
		return nil
	end
	return anchor + ev.offset
end

function TimelineCore:effectiveState(id)
	local ev = self.events[id]
	local rec = self.records[id]
	if rec.lockedState then
		return rec.lockedState
	end
	if ev.derivedFrom then
		local sourceState = self:effectiveState(ev.derivedFrom)
		return ev.stateMap[sourceState] or ev.originalState
	end
	return rec.committedState or ev.originalState
end

function TimelineCore:dependents(id)
	local list = {}
	for _, otherId in self.order do
		if self.events[otherId].derivedFrom == id then
			table.insert(list, otherId)
		end
	end
	return list
end

local function hasStarted(self, id)
	local rec = self.records[id]
	if rec.lockedState ~= nil then
		return true
	end
	for _, dep in self:dependents(id) do
		if hasStarted(self, dep) then
			return true
		end
	end
	return false
end

function TimelineCore:isLocked(id, now)
	local ev = self.events[id]
	if hasStarted(self, id) then
		return true
	end
	local fire = self:fireTime(id)
	if fire and now >= fire - (ev.lockBefore or 5) then
		return true
	end
	-- A consequence that is about to play also locks the source.
	for _, dep in self:dependents(id) do
		local depFire = self:fireTime(dep)
		local depEv = self.events[dep]
		if depFire and now >= depFire - (depEv.lockBefore or ev.lockBefore or 5) then
			return true
		end
	end
	return false
end

--[[
	context = {
		flags = { [flag] = true },
		charges = number,
		tapeFound = boolean,
		expectedState = string?     -- the event state the client was looking at
	}
	Returns ok, code, message.
]]
function TimelineCore:validateEdit(id, newState, now, context)
	local ev = self.events[id]
	if not ev then
		return false, "UNKNOWN_EVENT", TimelineCore.Messages.UNKNOWN_EVENT
	end
	if not ev.isEditable then
		return false, "NOT_EDITABLE", TimelineCore.Messages.NOT_EDITABLE
	end
	if not context.tapeFound then
		return false, "TAPE_MISSING", TimelineCore.Messages.TAPE_MISSING
	end
	if type(newState) ~= "string" or not table.find(ev.allowedStates, newState) then
		return false, "INVALID_STATE", TimelineCore.Messages.INVALID_STATE
	end
	local rec = self.records[id]
	if rec.fired then
		return false, "ALREADY_OCCURRED", TimelineCore.Messages.ALREADY_OCCURRED
	end
	if rec.edits >= (ev.maxEdits or 1) then
		local who = rec.committedName and (" by " .. rec.committedName) or ""
		return false, "ALREADY_EDITED", "This event has already been edited" .. who .. "."
	end
	-- Two investigators reviewing the same event: the second commit sees that the
	-- state changed underneath them and is refused without spending a charge.
	if context.expectedState ~= nil and context.expectedState ~= self:effectiveState(id) then
		return false, "VERSION", TimelineCore.Messages.VERSION
	end
	if newState == self:effectiveState(id) then
		return false, "NO_CHANGE", TimelineCore.Messages.NO_CHANGE
	end
	for _, flag in ev.prerequisites or {} do
		if not (context.flags and context.flags[flag]) then
			local label = (self.case.flagLabels and self.case.flagLabels[flag]) or flag
			return false, "PREREQUISITE", "Requires: " .. label .. "."
		end
	end
	if self:isLocked(id, now) then
		return false, "LOCKED", TimelineCore.Messages.LOCKED
	end
	if (context.charges or 0) < (ev.editCost or 1) then
		return false, "NO_CHARGES", TimelineCore.Messages.NO_CHARGES
	end
	return true, "OK", nil
end

-- Applies a validated edit. Returns a summary of what changed.
function TimelineCore:commit(id, newState, byUserId, byName, now)
	local ev = self.events[id]
	local rec = self.records[id]
	local from = self:effectiveState(id)
	local before = {}
	for _, dep in self:dependents(id) do
		before[dep] = self:effectiveState(dep)
	end
	rec.committedState = newState
	rec.committedBy = byUserId
	rec.committedName = byName
	rec.committedAt = now
	rec.edits += 1
	self.version += 1
	local consequences = {}
	for _, dep in self:dependents(id) do
		table.insert(consequences, { eventId = dep, from = before[dep], to = self:effectiveState(dep) })
	end
	local entry = {
		eventId = id,
		from = from,
		to = newState,
		by = byUserId,
		byName = byName,
		at = now,
		cost = ev.editCost or 1,
		consequences = consequences,
	}
	table.insert(self.editLog, entry)
	return entry
end

local function lockState(rec, state)
	if rec.lockedState == nil then
		rec.lockedState = state
	end
end

--[[
	Advances the timeline. Returns a list of outputs in time order:
	  { kind = "action", eventId, action, time }
	  { kind = "presenter", eventId, command, startTime }
	  { kind = "fired", eventId, state }
]]
function TimelineCore:update(now)
	local out = {}
	for _, id in self.order do
		local ev = self.events[id]
		local fire = self:fireTime(id)
		if fire then
			local rec = self.records[id]
			local state = self:effectiveState(id)
			local stateDef = ev.states[state]
			if stateDef then
				for index, action in stateDef.actions or {} do
					local t = fire + (action.at or 0)
					if now >= t and not rec.actionsDone[index] then
						lockState(rec, state)
						rec.actionsDone[index] = true
						table.insert(out, { kind = "action", eventId = id, action = action, time = t })
					end
				end
				local cmd = stateDef.presenter
				if cmd and not rec.presenterDone then
					local t = fire + (cmd.at or 0)
					if now >= t then
						lockState(rec, state)
						rec.presenterDone = true
						table.insert(out, { kind = "presenter", eventId = id, command = cmd, startTime = t })
					end
				end
			end
			if now >= fire and not rec.fired then
				lockState(rec, state)
				rec.fired = true
				self.version += 1
				table.insert(out, { kind = "fired", eventId = id, state = state })
			end
		end
	end
	table.sort(out, function(a, b)
		local ta = a.time or a.startTime or 0
		local tb = b.time or b.startTime or 0
		return ta < tb
	end)
	return out
end

-- Serialisable view for clients.
function TimelineCore:snapshot(now)
	local events = {}
	for _, id in self.order do
		local rec = self.records[id]
		events[id] = {
			state = self:effectiveState(id),
			fired = rec.fired,
			fireTime = self:fireTime(id),
			edits = rec.edits,
			locked = self:isLocked(id, now),
			committed = rec.committedState and {
				state = rec.committedState,
				by = rec.committedBy,
				name = rec.committedName,
				at = rec.committedAt,
			} or nil,
		}
	end
	return {
		version = self.version,
		anchors = table.clone(self.anchors),
		events = events,
	}
end

-- Presenter paths actually in use (after seeded variants) for footage rendering.
function TimelineCore:eventDefinitions()
	return self.events
end

---------------------------------------------------------------------------
-- Static validation of a case definition. Returns a list of error strings.
---------------------------------------------------------------------------
function TimelineCore.validateCase(caseDef, mapLayout)
	local errors = {}
	local function fail(fmt, ...)
		table.insert(errors, string.format(fmt, ...))
	end

	local byId = {}
	for _, ev in caseDef.events do
		if byId[ev.id] then
			fail("duplicate event id %s", ev.id)
		end
		byId[ev.id] = ev
	end
	local anchors = {}
	for _, a in caseDef.anchors or {} do
		anchors[a] = true
	end

	for _, ev in caseDef.events do
		local id = ev.id
		if not anchors[ev.anchor] then
			fail("%s: anchor %s is not declared in case.anchors", id, tostring(ev.anchor))
		end
		if type(ev.offset) ~= "number" or ev.offset < 0 then
			fail("%s: offset must be a non-negative number", id)
		end
		local tape = caseDef.tapes[ev.tape]
		if not tape then
			fail("%s: unknown tape %s", id, tostring(ev.tape))
		else
			if tape.anchor ~= ev.anchor then
				fail("%s: anchor %s differs from its tape's anchor %s", id, ev.anchor, tape.anchor)
			end
			if ev.offset > tape.duration then
				fail("%s: offset %d is past the end of %s", id, ev.offset, ev.tape)
			end
			for _, cam in ev.cameras or {} do
				if not table.find(tape.cameras, cam) then
					fail("%s: camera %s is not recorded on %s", id, cam, ev.tape)
				end
				if mapLayout and not mapLayout.Cameras[cam] then
					fail("%s: camera %s does not exist on the map", id, cam)
				end
			end
		end
		if not table.find(ev.allowedStates, ev.originalState) then
			fail("%s: originalState %s is not allowed", id, tostring(ev.originalState))
		end
		for _, state in ev.allowedStates do
			if not ev.states[state] then
				fail("%s: allowed state %s has no definition", id, state)
			end
			if not (ev.stateLabels and ev.stateLabels[state]) then
				fail("%s: allowed state %s has no label", id, state)
			end
		end
		if ev.isEditable then
			if ev.derivedFrom then
				fail("%s: an editable event cannot also be derived", id)
			end
			if type(ev.editCost) ~= "number" or ev.editCost < 1 then
				fail("%s: editable events must cost at least one charge", id)
			end
			if #ev.allowedStates < 2 then
				fail("%s: editable events need at least two states", id)
			end
		end
		if ev.derivedFrom then
			local src = byId[ev.derivedFrom]
			if not src then
				fail("%s: derivedFrom %s does not exist", id, ev.derivedFrom)
			else
				for _, srcState in src.allowedStates do
					local mapped = ev.stateMap and ev.stateMap[srcState]
					if not mapped then
						fail("%s: stateMap does not cover %s.%s", id, src.id, srcState)
					elseif not table.find(ev.allowedStates, mapped) then
						fail("%s: stateMap maps %s to unknown state %s", id, srcState, mapped)
					end
				end
				if not table.find(src.consequenceEventIds or {}, id) then
					fail("%s: source %s does not list it as a consequence", id, src.id)
				end
			end
		end
		for _, cid in ev.consequenceEventIds or {} do
			local c = byId[cid]
			if not c then
				fail("%s: consequence %s does not exist", id, cid)
			elseif c.derivedFrom ~= id then
				fail("%s: consequence %s is not derived from it", id, cid)
			end
		end
		-- Actions may only run before the fire time if edits are already locked by then.
		local lockBefore = ev.lockBefore or 5
		for state, stateDef in ev.states do
			for _, action in stateDef.actions or {} do
				if (action.at or 0) < -lockBefore then
					fail("%s.%s: action at %s runs before edits lock", id, state, tostring(action.at))
				end
			end
			local cmd = stateDef.presenter
			if cmd and cmd.path then
				local last = -1
				for i, key in cmd.path do
					if key.t <= last then
						fail("%s.%s: path keyframe %d is out of order", id, state, i)
					end
					last = key.t
				end
				if cmd.path[1] and cmd.path[1].t ~= 0 then
					fail("%s.%s: path must start at t = 0", id, state)
				end
				if cmd.duration and last > cmd.duration then
					fail("%s.%s: path runs past the command duration", id, state)
				end
			end
		end
		-- A derived event on the same anchor must not start before its source locks.
		if ev.derivedFrom and byId[ev.derivedFrom] and byId[ev.derivedFrom].anchor == ev.anchor then
			local src = byId[ev.derivedFrom]
			local srcLock = src.offset - (src.lockBefore or 5)
			for state, stateDef in ev.states do
				for _, action in stateDef.actions or {} do
					if ev.offset + (action.at or 0) < srcLock then
						fail("%s.%s: action starts before %s locks", id, state, src.id)
					end
				end
			end
		end
	end

	-- Derivation cycles.
	for _, ev in caseDef.events do
		local seen = {}
		local node = ev
		while node and node.derivedFrom do
			if seen[node.id] then
				fail("derivation cycle through %s", ev.id)
				break
			end
			seen[node.id] = true
			node = byId[node.derivedFrom]
		end
	end

	-- Contradictory Presenter schedules: for every combination of editable
	-- states, no two Presenter windows on the same anchor may overlap.
	local editable = {}
	for _, ev in caseDef.events do
		if ev.isEditable then
			table.insert(editable, ev)
		end
	end
	local function effective(ev, choice)
		if ev.derivedFrom then
			return ev.stateMap[effective(byId[ev.derivedFrom], choice)]
		end
		return choice[ev.id] or ev.originalState
	end
	local combos = 1
	for _, ev in editable do
		combos *= #ev.allowedStates
	end
	for combo = 0, combos - 1 do
		local choice = {}
		local rest = combo
		for _, ev in editable do
			local n = #ev.allowedStates
			choice[ev.id] = ev.allowedStates[(rest % n) + 1]
			rest = rest // n
		end
		local windows = {}
		for _, ev in caseDef.events do
			local s, e = presenterWindow(ev, ev.states[effective(ev, choice)])
			if s then
				windows[ev.anchor] = windows[ev.anchor] or {}
				table.insert(windows[ev.anchor], { id = ev.id, s = s, e = e })
			end
		end
		for anchor, list in windows do
			for i = 1, #list do
				for j = i + 1, #list do
					local a, b = list[i], list[j]
					if a.s < b.e and b.s < a.e then
						fail("presenter windows of %s and %s overlap on anchor %s", a.id, b.id, anchor)
					end
				end
			end
		end
	end

	-- Hidden frames.
	for _, hf in caseDef.hiddenFrames or {} do
		local tape = caseDef.tapes[hf.tape]
		if not tape then
			fail("hidden frame %s: unknown tape", hf.id)
		elseif not table.find(tape.cameras, hf.camera) then
			fail("hidden frame %s: camera %s not on %s", hf.id, hf.camera, hf.tape)
		elseif hf.t > tape.duration then
			fail("hidden frame %s: past the end of the tape", hf.id)
		end
	end

	-- De-duplicate (the overlap check repeats per combination).
	local unique, seenErr = {}, {}
	for _, e in errors do
		if not seenErr[e] then
			seenErr[e] = true
			table.insert(unique, e)
		end
	end
	return unique
end

return TimelineCore
