--[[
	Footage — what a camera on a tape shows at tape time t.

	Footage is not a recording of the 3D world. It is computed from the same event
	definitions and timeline state the server uses, so a tape always predicts what
	the server will actually do (until someone edits it).
]]

local MapLayout = require(script.Parent.Parent.Config.MapLayout)
local PresenterBrain = require(script.Parent.PresenterBrain)
local Vec = require(script.Parent.Parent.Util.Vec)

local Footage = {}

local function eventsOnTape(caseDef, eventDefs, tapeId)
	local list = {}
	for _, base in caseDef.events do
		local ev = eventDefs[base.id] or base
		if ev.tape == tapeId then
			table.insert(list, ev)
		end
	end
	return list
end
Footage.eventsOnTape = eventsOnTape

local function stateOf(snapshot, ev)
	local rec = snapshot and snapshot.events and snapshot.events[ev.id]
	return (rec and rec.state) or ev.originalState
end

-- Light mode for a camera at tape time t: "on", "off" or "emergency".
function Footage.lightsAt(caseDef, eventDefs, snapshot, tapeId, cameraId, t)
	local tape = caseDef.tapes[tapeId]
	local camera = MapLayout.Cameras[cameraId]
	local mode = (tape.baseLights and tape.baseLights[cameraId]) or "on"
	local latest = -math.huge
	for _, ev in eventsOnTape(caseDef, eventDefs, tapeId) do
		local stateDef = ev.states[stateOf(snapshot, ev)]
		for _, action in (stateDef and stateDef.actions) or {} do
			if action.type == "Lights" and table.find(camera.rooms, action.room) then
				local start = ev.offset + (action.at or 0)
				local stop = action.duration and (start + action.duration) or math.huge
				if t >= start and t < stop and start >= latest then
					mode = action.mode
					latest = start
				end
			end
		end
	end
	return mode
end

-- Presenter position (if any) predicted by an event at tape time t.
local function presenterAt(ev, stateDef, t)
	local cmd = stateDef and stateDef.presenter
	if not cmd then
		return nil
	end
	local start = ev.offset + (cmd.at or 0)
	local elapsed = t - start
	if elapsed < 0 then
		return nil
	end
	if cmd.kind == "Displaced" then
		if elapsed > cmd.duration then
			return nil
		end
		local pos, _, look, index = PresenterBrain.pathPosition(cmd.path, elapsed)
		if not look then
			local nextKey = cmd.path[math.min(index + 1, #cmd.path)]
			if nextKey and Vec.flatDistance(nextKey.pos, pos) > 0.1 then
				look = nextKey.pos
			end
		end
		return pos, look
	elseif cmd.kind == "Ambush" then
		-- Footage shows the arrival and the wind-up; what follows depends on you.
		if elapsed > (cmd.windup or 2.5) + 2 then
			return nil
		end
		return cmd.pos, cmd.look
	elseif cmd.kind == "Rewind" or cmd.kind == "Observe" then
		if elapsed > (cmd.duration or 8) then
			return nil
		end
		return cmd.pos, cmd.look
	end
	return nil
end

--[[
	Returns {
		lights = "on" | "off" | "emergency",
		actors = { { kind = "Presenter" | "Investigator", pos, look, wrong, eventId } },
		hiddenFrame = { id, text } | nil,
	}
]]
function Footage.frame(caseDef, eventDefs, snapshot, tapeId, cameraId, t)
	local tape = caseDef.tapes[tapeId]
	local camera = MapLayout.Cameras[cameraId]
	local frame = {
		lights = Footage.lightsAt(caseDef, eventDefs, snapshot, tapeId, cameraId, t),
		actors = {},
		hiddenFrame = nil,
	}
	for _, ev in eventsOnTape(caseDef, eventDefs, tapeId) do
		local pos, look = presenterAt(ev, ev.states[stateOf(snapshot, ev)], t)
		if pos and MapLayout.inRooms(pos, camera.rooms, 1.5) then
			table.insert(frame.actors, { kind = "Presenter", pos = pos, look = look, eventId = ev.id })
		end
	end
	for _, actor in (tape.actors and tape.actors[cameraId]) or {} do
		if t >= actor.from and t < actor.to then
			table.insert(frame.actors, {
				kind = "Investigator",
				pos = actor.pos,
				look = actor.look,
				wrong = actor.wrong == true,
			})
		end
	end
	for _, hf in caseDef.hiddenFrames or {} do
		if hf.tape == tapeId and hf.camera == cameraId and math.abs(t - hf.t) <= (hf.window or 0.5) then
			frame.hiddenFrame = { id = hf.id, text = hf.text }
			if hf.id == "HF_T01_FIFTH" then
				-- The extra figure stands behind the group.
				table.insert(frame.actors, {
					kind = "Investigator",
					pos = MapLayout.point("Lobby", 0.5, 0.8),
					look = MapLayout.point("Lobby", 0.5, 0.4),
					wrong = true,
				})
			end
		end
	end
	return frame
end

-- Event markers for the scrubber.
function Footage.markers(caseDef, eventDefs, snapshot, tapeId)
	local list = {}
	for _, ev in eventsOnTape(caseDef, eventDefs, tapeId) do
		local rec = snapshot and snapshot.events and snapshot.events[ev.id]
		table.insert(list, {
			eventId = ev.id,
			t = ev.offset,
			label = ev.label,
			editable = ev.isEditable == true,
			state = (rec and rec.state) or ev.originalState,
			fired = rec and rec.fired or false,
			locked = rec and rec.locked or false,
			committed = rec and rec.committed or nil,
			cameras = ev.cameras,
		})
	end
	table.sort(list, function(a, b)
		return a.t < b.t
	end)
	return list
end

-- Which cameras on the tape show a given event.
function Footage.camerasFor(caseDef, eventId)
	for _, ev in caseDef.events do
		if ev.id == eventId then
			return ev.cameras or {}
		end
	end
	return {}
end

return Footage
