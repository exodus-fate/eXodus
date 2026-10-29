--[[
	CASE 01 · THE 00:17 TRANSMISSION
	Broadcast Station 04

	The whole case is data. The timeline, the Presenter, footage on every tape
	deck and the real world are all driven from these definitions, so what a tape
	shows is exactly what the server will do unless the team edits it.

	Event chain overview (4 editable events, 3 charges in Standard mode):

	TAPE 01  lobby_lights (02:30)        OFF -> presenter_entry LOBBY      (it walks in through the main doors)
	                                     ON  -> presenter_entry SOUTH_HALL (it waits outside the control room)
	TAPE 02  east_corridor_lights (+1:30 after power)
	                                     OFF -> presenter_route_east EAST_CORRIDOR (dark corridor patrol, east relay trips)
	                                     ON  -> presenter_route_east CONTROL_ROOM  (the hub becomes unsafe)
	TAPE 03  presenter_ambush (+0:20 after the sync board is taken)
	                                     ARCHIVE       -> it hunts inside the archive (two exits)
	                                     EAST_CORRIDOR -> it blocks the corridor... and transmitter_watch CHAMBER later
	         control_room_rewind (+1:15) fixed: the control room replays itself; north door relocks for 30 s
	TAPE 04  freight_door (+0:30 after the transmitter is armed)
	                                     JAMMED -> climax_route CHAMBER_HUNT (restart the motor while it hunts)
	                                     OPEN   -> climax_route DOCK_PATROL  (door opens, it patrols the dock)
	         transmitter_watch (+0:03)   derived from presenter_ambush
]]

local MapLayout = require(script.Parent.Parent.MapLayout)
local P = MapLayout.point

local Case01 = {}

Case01.id = "case01"
Case01.number = 1
Case01.title = "THE 00:17 TRANSMISSION"
Case01.location = "BROADCAST STATION 04"
Case01.summary = "A transmission failed at 00:17 in a station that has been empty for nineteen years. Recover the components, shut down tonight's broadcast and get out."
Case01.mapId = "Station04"
Case01.masterRecording = "MASTER_01"
Case01.timeLimit = 30 * 60
Case01.maxParticipants = 4

Case01.modes = {
	Standard = { charges = 3, awarenessScale = 1, huntSpeed = 14.5, showClues = true, label = "STANDARD" },
	Restricted = { charges = 2, awarenessScale = 1.35, huntSpeed = 15.5, showClues = false, label = "RESTRICTED", requiresClearance = 2 },
	ArchiveChallenge = { charges = 3, awarenessScale = 1.15, huntSpeed = 15, showClues = true, label = "ARCHIVE CHALLENGE", fixedSeed = true, requiresClearance = 2 },
}

---------------------------------------------------------------------------
-- Briefing (played in the reception before the broadcast starts)
---------------------------------------------------------------------------
Case01.briefing = {
	duration = 40,
	lines = {
		{ at = 0, text = "Recovery team, this is Division. You are inside Broadcast Station 04." },
		{ at = 6, text = "The station transmits at 00:00 every night. Tonight's programme is about you." },
		{ at = 12, text = "Recover three transmission components and install them in the transmitter. Then leave by the freight door." },
		{ at = 19, text = "The tapes show what happens next. You can change a few conditions on them. Each change costs a charge, and something else moves to make room." },
		{ at = 27, text = "Division only speaks on Channel 2, and we stamp every message with the live tape clock. Anything else is not us." },
		{ at = 35, text = "Broadcast begins now. Doors are sealing." },
	},
}

---------------------------------------------------------------------------
-- Decks: places where tapes can be inspected and edited.
-- battery decks work before the generator is restored.
---------------------------------------------------------------------------
Case01.decks = {
	DECK_LOBBY = { label = "RECEPTION VCR", room = "Lobby", pos = P("Lobby", 0.6, 0.3, 3.6), battery = true },
	DECK_EDIT = { label = "EDIT BAY DECK", room = "EditingSuite", pos = P("EditingSuite", 0.5, 0.16, 3.6), battery = true },
	DECK_MAIN = { label = "TIME-SHIFT DECK", room = "ControlRoom", pos = P("ControlRoom", 0.5, 0.25, 3.6), battery = false },
	DECK_TRANS = { label = "MASTER CONTROL", room = "Transmitter", pos = P("Transmitter", 0.18, 0.75, 3.6), battery = false },
}

---------------------------------------------------------------------------
-- Tapes. Each tape's clock is relative to its anchor flag.
---------------------------------------------------------------------------
Case01.tapes = {
	TAPE01 = {
		label = "TAPE 01",
		title = "RECEPTION / 00:00",
		anchor = "broadcast_start",
		duration = 210,
		cameras = { "CAM01", "CAM02" },
		colour = { 196, 186, 158 },
		baseLights = { CAM01 = "emergency", CAM02 = "off" },
		-- Footage-only figures: the team as the tape "remembers" them.
		actors = {
			CAM01 = {
				{ from = 0, to = 48, pos = P("Lobby", 0.42, 0.66), look = P("Lobby", 0.5, 0.4) },
				{ from = 0, to = 48, pos = P("Lobby", 0.47, 0.68), look = P("Lobby", 0.5, 0.4) },
				{ from = 0, to = 48, pos = P("Lobby", 0.53, 0.68), look = P("Lobby", 0.5, 0.4) },
				-- One of them faces the wall while the real team faces the desk.
				{ from = 0, to = 48, pos = P("Lobby", 0.58, 0.66), look = P("Lobby", 1, 0.66), wrong = true },
			},
		},
	},
	TAPE02 = {
		label = "TAPE 02",
		title = "B-ROLL / POWER",
		anchor = "generator_restored",
		duration = 260,
		cameras = { "CAM06", "CAM07", "CAM09" },
		colour = { 104, 122, 100 },
		baseLights = { CAM06 = "on", CAM07 = "on", CAM09 = "on" },
		actors = {},
	},
	TAPE03 = {
		label = "TAPE 03",
		title = "ARCHIVE / DUB 3",
		anchor = "board_recovered",
		duration = 140,
		cameras = { "CAM08", "CAM06", "CAM07", "CAM09" },
		colour = { 104, 86, 66 },
		baseLights = { CAM08 = "on", CAM06 = "on", CAM07 = "on", CAM09 = "on" },
		actors = {},
	},
	TAPE04 = {
		label = "TAPE 04",
		title = "TRANSMITTER / FINAL",
		anchor = "transmitter_armed",
		duration = 120,
		cameras = { "CAM11", "CAM12" },
		colour = { 92, 108, 122 },
		baseLights = { CAM11 = "on", CAM12 = "emergency" },
		actors = {},
	},
}
Case01.tapeOrder = { "TAPE01", "TAPE02", "TAPE03", "TAPE04" }

---------------------------------------------------------------------------
-- Timeline events
---------------------------------------------------------------------------
local LOBBY_SIGHT = { range = 40, dark = 24, fov = 120, proximity = 7 }

Case01.events = {
	{
		id = "lobby_lights",
		label = "Reception emergency lights",
		tape = "TAPE01",
		cameras = { "CAM01" },
		locationId = "Lobby",
		eventType = "LightingChange",
		anchor = "broadcast_start",
		offset = 150,
		isEditable = true,
		originalState = "OFF",
		allowedStates = { "OFF", "ON" },
		stateLabels = { OFF = "LIGHTS FAIL", ON = "LIGHTS HOLD" },
		editCost = 1,
		maxEdits = 1,
		lockBefore = 5,
		prerequisites = {},
		consequenceEventIds = { "presenter_entry" },
		clue = "CAM 02 · 02:43 — if the lights hold, a figure waits outside the control room instead.",
		warning = "LINKED EVENT DETECTED: PRESENTER ROUTE (CAM 01 / CAM 02)",
		states = {
			OFF = {
				actions = {
					{ at = 0, type = "Lights", room = "Lobby", mode = "off", duration = 75 },
					{ at = 0, type = "Cue", cue = "LightsFail", room = "Lobby" },
				},
			},
			ON = { actions = {} },
		},
	},
	{
		id = "presenter_entry",
		label = "Presenter route",
		tape = "TAPE01",
		cameras = { "CAM01", "CAM02" },
		locationId = "Lobby",
		eventType = "EntityRoute",
		anchor = "broadcast_start",
		offset = 155,
		isEditable = false,
		derivedFrom = "lobby_lights",
		stateMap = { OFF = "LOBBY", ON = "SOUTH_HALL" },
		originalState = "LOBBY",
		allowedStates = { "LOBBY", "SOUTH_HALL" },
		stateLabels = { LOBBY = "ENTERS RECEPTION", SOUTH_HALL = "WAITS AT CONTROL ROOM" },
		states = {
			LOBBY = {
				actions = {
					{ at = -3, type = "Subtitle", text = "[HEAVY FOOTSTEPS — MAIN ENTRANCE]", kind = "cue" },
				},
				presenter = {
					kind = "Displaced",
					duration = 34,
					huntOnSight = true,
					sight = LOBBY_SIGHT,
					path = {
						{ t = 0, pos = P("Lobby", 0.5, 0.97) },
						{ t = 6, pos = P("Lobby", 0.5, 0.75) },
						{ t = 14, pos = P("Lobby", 0.3, 0.5) },
						{ t = 22, pos = P("Lobby", 0.75, 0.4) },
						{ t = 27, pos = P("Lobby", 0.75, 0.15) },
						{ t = 32, pos = P("Lobby", 0.5, 0.08) },
					},
				},
			},
			SOUTH_HALL = {
				actions = {
					{ at = -3, type = "Subtitle", text = "[FOOTSTEPS — CONTROL ROOM]", kind = "cue" },
					{ at = 15, type = "Cue", cue = "EditorShadow", event = "lobby_lights" },
				},
				presenter = {
					kind = "Displaced",
					duration = 45,
					huntOnSight = true,
					sight = { range = 18, dark = 14, fov = 100, proximity = 6 },
					path = {
						{ t = 0, pos = P("ControlRoom", 0.5, 0.85) },
						{ t = 8, pos = P("SouthHall", 0.5, 0.2), look = P("ControlRoom", 0.5, 0.9) },
						{ t = 45, pos = P("SouthHall", 0.5, 0.2), look = P("ControlRoom", 0.5, 0.9) },
					},
				},
			},
		},
	},
	{
		id = "east_corridor_lights",
		label = "East corridor fluorescent bank",
		tape = "TAPE02",
		cameras = { "CAM06" },
		locationId = "EastCorridor",
		eventType = "LightingChange",
		anchor = "generator_restored",
		offset = 90,
		isEditable = true,
		originalState = "OFF",
		allowedStates = { "OFF", "ON" },
		stateLabels = { OFF = "BANK FAILS", ON = "BANK HOLDS" },
		editCost = 1,
		maxEdits = 1,
		lockBefore = 5,
		prerequisites = { "generator_restored" },
		consequenceEventIds = { "presenter_route_east" },
		clue = "CAM 09 — if the corridor stays lit, the control room is where it goes instead.",
		warning = "LINKED EVENT DETECTED: PRESENTER ROUTE (CAM 06 / CAM 09)",
		states = {
			OFF = {
				actions = {
					{ at = 0, type = "Lights", room = "EastCorridor", mode = "off", duration = 155 },
					{ at = 0, type = "Cue", cue = "LightsFail", room = "EastCorridor" },
					{ at = 2, type = "Relay", relay = "EAST", on = false },
				},
			},
			ON = { actions = {} },
		},
	},
	{
		id = "presenter_route_east",
		label = "Presenter route",
		tape = "TAPE02",
		cameras = { "CAM06", "CAM07", "CAM09" },
		locationId = "EastCorridor",
		eventType = "EntityRoute",
		anchor = "generator_restored",
		offset = 95,
		isEditable = false,
		derivedFrom = "east_corridor_lights",
		stateMap = { OFF = "EAST_CORRIDOR", ON = "CONTROL_ROOM" },
		originalState = "EAST_CORRIDOR",
		allowedStates = { "EAST_CORRIDOR", "CONTROL_ROOM" },
		stateLabels = { EAST_CORRIDOR = "PATROLS EAST CORRIDOR", CONTROL_ROOM = "OCCUPIES CONTROL ROOM" },
		states = {
			EAST_CORRIDOR = {
				actions = {
					{ at = -3, type = "Subtitle", text = "[TAPE FLUTTER — EAST WING]", kind = "cue" },
				},
				presenter = {
					kind = "Displaced",
					duration = 150,
					huntOnSight = true,
					sight = { range = 36, dark = 26, fov = 110, proximity = 6 },
					-- Seeded variants may reverse the patrol (see `variants.patrolFlip`).
					path = {
						{ t = 0, pos = P("EastCorridor", 0.95, 0.5) },
						{ t = 25, pos = P("EastCorridor", 0.06, 0.5) },
						{ t = 50, pos = P("EastCorridor", 0.95, 0.5) },
						{ t = 75, pos = P("EastCorridor", 0.06, 0.5) },
						{ t = 100, pos = P("EastCorridor", 0.95, 0.5) },
						{ t = 125, pos = P("EastCorridor", 0.06, 0.5) },
						{ t = 145, pos = P("EastCorridor", 0.5, 0.5) },
					},
				},
			},
			CONTROL_ROOM = {
				actions = {
					{ at = -3, type = "Subtitle", text = "[CHAIR SCRAPES — CONTROL ROOM]", kind = "cue" },
				},
				presenter = {
					kind = "Displaced",
					duration = 120,
					huntOnSight = true,
					sight = { range = 34, dark = 22, fov = 110, proximity = 6 },
					-- Wanders the open floor south of the deck desk and operator chairs.
					path = {
						{ t = 0, pos = { x = 0, y = 0, z = -3.5 } },
						{ t = 20, pos = { x = -9, y = 0, z = -4 } },
						{ t = 40, pos = { x = 9, y = 0, z = -3.5 } },
						{ t = 60, pos = { x = 0, y = 0, z = 5 } },
						{ t = 80, pos = { x = -7, y = 0, z = 1 } },
						{ t = 100, pos = { x = 7, y = 0, z = 0 } },
						{ t = 118, pos = { x = 0, y = 0, z = -3.5 } },
					},
				},
			},
		},
	},
	{
		id = "presenter_ambush",
		label = "Archive intrusion",
		tape = "TAPE03",
		cameras = { "CAM08", "CAM06" },
		locationId = "Archive",
		eventType = "EntityRoute",
		anchor = "board_recovered",
		offset = 20,
		isEditable = true,
		originalState = "ARCHIVE",
		allowedStates = { "ARCHIVE", "EAST_CORRIDOR" },
		stateLabels = { ARCHIVE = "ENTERS ARCHIVE", EAST_CORRIDOR = "HOLDS EAST CORRIDOR" },
		editCost = 1,
		maxEdits = 1,
		lockBefore = 5,
		prerequisites = { "generator_restored" },
		consequenceEventIds = { "transmitter_watch" },
		clue = "TAPE 04 · CAM 11 — something stands on the transmitter gantry in one version of this tape.",
		warning = "LINKED EVENT DETECTED: TRANSMITTER CHAMBER (TAPE 04)",
		states = {
			ARCHIVE = {
				actions = {
					{ at = -2, type = "Subtitle", text = "[SHELVES CREAK — ARCHIVE]", kind = "cue" },
				},
				presenter = {
					kind = "Ambush",
					pos = P("Archive", 0.9, 0.5),
					look = P("Archive", 0.1, 0.5),
					radius = 70,
					windup = 3,
					maxDuration = 40,
				},
			},
			EAST_CORRIDOR = {
				actions = {
					{ at = -2, type = "Subtitle", text = "[FOOTSTEPS STOP — EAST CORRIDOR]", kind = "cue" },
				},
				presenter = {
					kind = "Displaced",
					duration = 45,
					huntOnSight = true,
					sight = { range = 40, dark = 28, fov = 90, proximity = 6 },
					path = {
						{ t = 0, pos = P("EastCorridor", 0.6, 0.5), look = P("EastCorridor", 1, 0.5) },
						{ t = 45, pos = P("EastCorridor", 0.6, 0.5), look = P("EastCorridor", 1, 0.5) },
					},
				},
			},
		},
	},
	{
		id = "control_room_rewind",
		label = "Control room replay",
		tape = "TAPE03",
		cameras = { "CAM09" },
		locationId = "ControlRoom",
		eventType = "Rewind",
		anchor = "board_recovered",
		offset = 75,
		isEditable = false,
		originalState = "REWIND",
		allowedStates = { "REWIND" },
		stateLabels = { REWIND = "ROOM REPLAYS ITSELF" },
		states = {
			REWIND = {
				actions = {
					{ at = 0, type = "Door", door = "D_CR_NH", locked = true },
					{ at = 0, type = "Cue", cue = "Rewind", room = "ControlRoom", duration = 30 },
					{ at = 0, type = "Subtitle", text = "[TAPE REWINDING — CONTROL ROOM]", kind = "cue" },
					{ at = 30, type = "Door", door = "D_CR_NH", locked = false },
				},
				presenter = {
					kind = "Rewind",
					pos = P("ControlRoom", 0.5, 0.5),
					look = P("ControlRoom", 0.5, 0),
					duration = 30,
					sight = { range = 10, dark = 10, fov = 360, proximity = 10 },
				},
			},
		},
	},
	{
		id = "transmitter_watch",
		label = "Gantry watcher",
		tape = "TAPE04",
		cameras = { "CAM11" },
		locationId = "Transmitter",
		eventType = "EntityRoute",
		anchor = "transmitter_armed",
		offset = 3,
		isEditable = false,
		derivedFrom = "presenter_ambush",
		stateMap = { ARCHIVE = "NONE", EAST_CORRIDOR = "CHAMBER" },
		originalState = "NONE",
		allowedStates = { "NONE", "CHAMBER" },
		stateLabels = { NONE = "NOTHING ON THE GANTRY", CHAMBER = "WATCHES FROM THE GANTRY" },
		states = {
			NONE = { actions = {} },
			CHAMBER = {
				actions = {
					{ at = -2, type = "Subtitle", text = "[METAL CREAKS — GANTRY]", kind = "cue" },
				},
				presenter = {
					kind = "Displaced",
					duration = 23,
					huntOnSight = true,
					sight = { range = 36, dark = 26, fov = 140, proximity = 8 },
					path = {
						{ t = 0, pos = P("Transmitter", 0.85, 0.3), look = P("Transmitter", 0.5, 0.72) },
						{ t = 23, pos = P("Transmitter", 0.85, 0.3), look = P("Transmitter", 0.5, 0.72) },
					},
				},
			},
		},
	},
	{
		id = "freight_door",
		label = "Freight door cycle",
		tape = "TAPE04",
		cameras = { "CAM11", "CAM12" },
		locationId = "Transmitter",
		eventType = "DoorState",
		anchor = "transmitter_armed",
		offset = 30,
		isEditable = true,
		originalState = "JAMMED",
		allowedStates = { "JAMMED", "OPEN" },
		stateLabels = { JAMMED = "MOTOR JAMS", OPEN = "DOOR CYCLES OPEN" },
		editCost = 1,
		maxEdits = 1,
		lockBefore = 5,
		prerequisites = { "generator_restored" },
		consequenceEventIds = { "climax_route" },
		clue = "CAM 12 — if the door opens on time, something waits on the loading dock.",
		warning = "LINKED EVENT DETECTED: PRESENTER ROUTE (CAM 11 / CAM 12)",
		states = {
			JAMMED = {
				actions = {
					{ at = 0, type = "Flag", flag = "freight_jammed" },
					{ at = 0, type = "Subtitle", text = "[FREIGHT MOTOR GRINDS AND STOPS]", kind = "cue" },
				},
			},
			OPEN = {
				actions = {
					{ at = 0, type = "Door", door = "D_Freight", locked = false, open = true },
					{ at = 0, type = "Flag", flag = "extraction_open" },
				},
			},
		},
	},
	{
		id = "climax_route",
		label = "Presenter route",
		tape = "TAPE04",
		cameras = { "CAM11", "CAM12" },
		locationId = "Transmitter",
		eventType = "EntityRoute",
		anchor = "transmitter_armed",
		offset = 32,
		isEditable = false,
		derivedFrom = "freight_door",
		stateMap = { JAMMED = "CHAMBER_HUNT", OPEN = "DOCK_PATROL" },
		originalState = "CHAMBER_HUNT",
		allowedStates = { "CHAMBER_HUNT", "DOCK_PATROL" },
		stateLabels = { CHAMBER_HUNT = "ENTERS CHAMBER", DOCK_PATROL = "PATROLS LOADING DOCK" },
		states = {
			CHAMBER_HUNT = {
				actions = {
					{ at = -3, type = "Subtitle", text = "[FOOTSTEPS — TRANSMITTER ACCESS]", kind = "cue" },
				},
				presenter = {
					kind = "Displaced",
					duration = 43,
					huntOnSight = true,
					sight = { range = 55, dark = 40, fov = 140, proximity = 8 },
					-- Enters from the access hall and circles the chamber walls,
					-- keeping clear of the transmitter cabinet and the socket console.
					path = {
						{ t = 0, pos = P("TransmitterHall", 0.5, 0.3) },
						{ t = 5, pos = P("Transmitter", 0.5, 0.9) },
						{ t = 13, pos = P("Transmitter", 0.08, 0.85) },
						{ t = 25, pos = P("Transmitter", 0.08, 0.2) },
						{ t = 37, pos = P("Transmitter", 0.92, 0.2) },
						{ t = 43, pos = P("Transmitter", 0.92, 0.85) },
					},
				},
			},
			DOCK_PATROL = {
				actions = {
					{ at = -3, type = "Subtitle", text = "[GRAVEL SHIFTS — LOADING DOCK]", kind = "cue" },
				},
				presenter = {
					kind = "Displaced",
					duration = 45,
					huntOnSight = true,
					sight = { range = 34, dark = 24, fov = 110, proximity = 6 },
					-- Patrols the west side, crosses between the freight door and the
					-- van's rear doors (t = 22-33), then patrols the east side.
					path = {
						{ t = 0, pos = P("LoadingDock", 0.15, 0.85) },
						{ t = 11, pos = P("LoadingDock", 0.15, 0.17) },
						{ t = 22, pos = P("LoadingDock", 0.15, 0.85) },
						{ t = 33, pos = P("LoadingDock", 0.85, 0.85) },
						{ t = 45, pos = P("LoadingDock", 0.85, 0.17) },
					},
				},
			},
		},
	},
}

---------------------------------------------------------------------------
-- Items and their seeded spawn spots. y is the surface height.
---------------------------------------------------------------------------
Case01.items = {
	TAPE01 = { label = "TAPE 01", kind = "Tape", tape = "TAPE01", spawns = { P("Lobby", 0.46, 0.3, 3.4) } },
	TAPE02 = { label = "TAPE 02", kind = "Tape", tape = "TAPE02", spawns = { P("EditingSuite", 0.4, 0.16, 3.4) } },
	TAPE03 = {
		label = "TAPE 03",
		kind = "Tape",
		tape = "TAPE03",
		spawns = { P("ControlRoom", 0.4, 0.25, 3.4) },
		visibleFlag = "generator_restored",
	},
	TAPE04 = {
		label = "TAPE 04",
		kind = "Tape",
		tape = "TAPE04",
		spawns = { P("Archive", 0.36, 0.2, 3.4) },
		visibleFlag = "loop_solved",
	},
	COIL = {
		label = "CARRIER COIL",
		kind = "Component",
		spawns = { P("EditingSuite", 0.18, 0.55, 2.6), P("EditingSuite", 0.82, 0.7, 2.6) },
		hint = "Carrier coil — editing suite",
	},
	VALVE = { label = "MODULATOR VALVE", kind = "Component", fromCage = true, hint = "Modulator valve — generator parts cage" },
	BOARD = { label = "SYNC BOARD", kind = "Component", fromRack = true, hint = "Sync board — tape archive (east)" },
	KEY = {
		label = "TRANSMITTER KEY",
		kind = "Key",
		spawns = { P("Archive", 0.22, 0.2, 3.4) },
		visibleFlag = "loop_solved",
	},
	EV_ORIENTATION = {
		label = "STAFF ORIENTATION TAPE",
		kind = "Evidence",
		evidence = "EV_ORIENTATION",
		spawns = { P("StaffPassage", 0.3, 0.25, 2.6), P("Lobby", 0.08, 0.85, 2.6) },
	},
	EV_ENGINEER = {
		label = "ENGINEER'S LOG TAPE",
		kind = "Evidence",
		evidence = "EV_ENGINEER",
		spawns = { P("Generator", 0.8, 0.85, 2.6), P("Generator", 0.25, 0.12, 2.6) },
	},
	EV_WEATHER = {
		label = "WEATHER BULLETIN TAPE",
		kind = "Evidence",
		evidence = "EV_WEATHER",
		spawns = { P("Archive", 0.85, 0.85, 2.6), P("Archive", 0.85, 0.12, 2.6) },
	},
	EV_TESTCARD = {
		label = "TEST CARD TAPE",
		kind = "Evidence",
		evidence = "EV_TESTCARD",
		spawns = { P("MaintPassage", 0.45, 0.2, 2.6), P("ServiceHall", 0.8, 0.25, 2.6) },
	},
	TAPE07 = {
		label = "TAPE 07",
		kind = "Evidence",
		evidence = "EV_FINAL_BULLETIN",
		bonus = true,
		spawns = { P("StudioA", 0.5, 0.3, 3.4) },
	},
}
Case01.components = { "COIL", "VALVE", "BOARD" }
Case01.optionalEvidence = { "EV_ORIENTATION", "EV_ENGINEER", "EV_WEATHER", "EV_TESTCARD", "TAPE07" }

---------------------------------------------------------------------------
-- Fixed interactables (item pickups are generated from `items`).
---------------------------------------------------------------------------
Case01.interactables = {
	I_BRIEFING = { kind = "Briefing", room = "Lobby", pos = P("Lobby", 0.25, 0.3, 3.6), object = "Briefing Terminal" },
	I_DECK_LOBBY = { kind = "Deck", deck = "DECK_LOBBY" },
	I_DECK_EDIT = { kind = "Deck", deck = "DECK_EDIT" },
	I_DECK_MAIN = { kind = "Deck", deck = "DECK_MAIN" },
	I_DECK_TRANS = { kind = "Deck", deck = "DECK_TRANS" },
	I_GENERATOR = { kind = "Generator", room = "Generator", pos = P("Generator", 0.5, 0.5, 3), object = "Generator" },
	I_CAGE = { kind = "Cage", room = "Generator", pos = P("Generator", 0.12, 0.85, 4), object = "Parts Cage" },
	I_RELAY_WEST = { kind = "Relay", relay = "WEST" },
	I_RELAY_EAST = { kind = "Relay", relay = "EAST" },
	I_RACK = { kind = "BoardRack", room = "Archive", pos = P("Archive", 0.5, 0.5, 3.5), object = "Equipment Rack" },
	I_SOCKET_COIL = { kind = "Socket", item = "COIL", room = "Transmitter", pos = P("Transmitter", 0.4, 0.72, 3.5), object = "Coil Housing" },
	I_SOCKET_VALVE = { kind = "Socket", item = "VALVE", room = "Transmitter", pos = P("Transmitter", 0.5, 0.72, 3.5), object = "Valve Socket" },
	I_SOCKET_BOARD = { kind = "Socket", item = "BOARD", room = "Transmitter", pos = P("Transmitter", 0.6, 0.72, 3.5), object = "Sync Slot" },
	-- v runs north (0) to south (1): the freight door is on the chamber's north wall.
	I_LEVER = { kind = "Lever", room = "Transmitter", pos = P("Transmitter", 0.75, 0.07, 3.5), object = "Freight Motor" },
	I_VAN = { kind = "Van", room = "LoadingDock", pos = P("LoadingDock", 0.5, 0.567, 2.5), object = "Extraction Van" },
}

---------------------------------------------------------------------------
-- The Loop (tape archive). Six props; one differs on every second cycle.
---------------------------------------------------------------------------
Case01.loop = {
	room = "Archive",
	cycleLength = 14,
	doors = { "D_EC_Arch", "D_MP_Arch" },
	tolerance = 0.75,
	props = {
		{ id = "LP_CLOCK", label = "Wall Clock", normal = "12:00", odd = "12:17", pos = P("Archive", 0.97, 0.35, 7) },
		{ id = "LP_CHAIR", label = "Office Chair", normal = "facing the desk", odd = "facing the wall", pos = P("Archive", 0.3, 0.32, 0) },
		{ id = "LP_LAMP", label = "Desk Lamp", normal = "white", odd = "amber", pos = P("Archive", 0.25, 0.2, 3.3) },
		{ id = "LP_TAPE", label = "Shelf Tape", normal = "TAPE 19", odd = "TAPE 91", pos = P("Archive", 0.7, 0.12, 4.2) },
		{ id = "LP_POSTER", label = "Safety Poster", normal = "upright", odd = "upside down", pos = P("Archive", 0.6, 0.97, 6) },
		{ id = "LP_PHONE", label = "Desk Phone", normal = "on the hook", odd = "off the hook", pos = P("Archive", 0.32, 0.2, 3.3) },
	},
	-- Presentation beats inside each cycle (client + subtitles).
	beats = {
		{ at = 3, text = "[PHONE RINGING]" },
		{ at = 7, text = "[A TAPE FALLS FROM A SHELF]" },
		{ at = 11, text = "[CLOCK TICKS]" },
	},
}

---------------------------------------------------------------------------
-- Parts cage keypad (the Caller lies about the code).
---------------------------------------------------------------------------
Case01.keypad = {
	digits = 4,
	alarmAwareness = 35,
	lockout = 5,
}

---------------------------------------------------------------------------
-- Radio script. stamp: "live" (correct broadcast clock) or a number of
-- seconds the Caller's stamp is wrong by. Channel 2 is Division.
---------------------------------------------------------------------------
Case01.radio = {
	{ anchor = "broadcast_start", offset = 5, source = "HQ", text = "TAPE 01 is on the reception desk. Play it on the reception VCR." },
	{ anchor = "broadcast_start", offset = 70, source = "CALLER", stamp = -600, text = "Division here. Stay in the reception. The lights will hold." },
	{ anchor = "generator_restored", offset = 3, source = "HQ", text = "Power's up. The modulator valve is in the generator room parts cage. Cage code {code}." },
	{ anchor = "generator_restored", offset = 14, source = "CALLER", stamp = 420, text = "Correction: the cage code is {fakeCode}. Then wait in the east corridor." },
	{ anchor = "generator_restored", offset = 26, source = "HQ", text = "Carrier coil should be in the editing suite. The sync board is in the tape archive, east wing. TAPE 03 just ejected in the control room." },
	{ anchor = "loop_active", offset = 4, source = "HQ", text = "You're in a loop. Watch two cycles. One thing changes. Touch it." },
	{ anchor = "board_recovered", offset = 3, source = "CALLER", stamp = -300, text = "Stay in the archive. It cannot reach you in there." },
	{ anchor = "board_recovered", offset = 5, source = "HQ", text = "Get out of the archive. Use whichever door the tape shows clear." },
	{ anchor = "components_complete", offset = 2, source = "HQ", text = "That's all three components. Transmitter chamber is north, past the service hall." },
	{ anchor = "transmitter_armed", offset = 2, source = "HQ", text = "Transmitter is live. The freight door should cycle in thirty seconds." },
	{ anchor = "transmitter_armed", offset = 9, source = "CALLER", stamp = 900, text = "Extraction is cancelled. Stay exactly where you are." },
	{ anchor = "extraction_open", offset = 1, source = "HQ", text = "Freight door is open. Get to the van." },
	{ anchor = "extraction_open", offset = 7, source = "HQ", text = "Studio A just unlocked by itself. Whatever is in there is optional. Your call." },
}
Case01.radioChannels = { HQ = { id = "NBRD-HQ", channel = 2 }, CALLER = { id = "NBRD-HQ", channel = 0 } }

---------------------------------------------------------------------------
-- Objectives. The first unfinished, visible objective is shown.
---------------------------------------------------------------------------
Case01.objectives = {
	{ id = "tape01", text = "Take TAPE 01 from the reception desk", doneFlag = "item_TAPE01" },
	{ id = "watch01", text = "Play TAPE 01 on the reception VCR", doneFlag = "viewed_TAPE01", clue = "Stand at the VCR and interact, or press R nearby." },
	{
		id = "decide01",
		text = "Find the marker at {mark:lobby_lights}. Edit it, or leave it.",
		doneFlag = "decided_lobby_lights",
		altDoneFlag = "fired_lobby_lights",
		clue = "Markers are predicted events. An edit costs one charge, and something else moves.",
	},
	{
		id = "leave",
		text = "Choose a route out of reception before {time:presenter_entry}",
		doneFlag = "fired_presenter_entry",
		clue = "The tape shows where it will be. The staff door (west) avoids the south hall.",
	},
	{ id = "power", text = "Restore power in the generator room (west wing)", doneFlag = "generator_restored", clue = "Prime the pump, then pull the starter." },
	{ id = "components", text = "Recover the transmission components ({components}/3)", doneFlag = "components_complete", clue = "{componentHints}" },
	{ id = "key", text = "Find the transmitter key in the tape archive", doneFlag = "item_KEY", clue = "It appears once the archive stops repeating." },
	{ id = "install", text = "Install the components in the transmitter chamber", doneFlag = "transmitter_armed", clue = "North hall or service hall. Check the control room tape first." },
	{ id = "freight", text = "Restart the freight motor at the lever", doneFlag = "extraction_open", showFlag = "freight_jammed", clue = "Hold the lever. Watch the access hall." },
	{ id = "wait", text = "Wait for the freight door to cycle", doneFlag = "extraction_open", clue = "Check TAPE 04 for what happens when it opens." },
	{ id = "extract", text = "Board the extraction van", doneFlag = "never", clue = "Anyone still inside when the last investigator leaves is left behind." },
}
Case01.optionalObjectives = {
	{ id = "studio", text = "Optional: Studio A is open. TAPE 07 is inside.", showFlag = "extraction_open", doneFlag = "item_TAPE07" },
	{ id = "evidence", text = "Optional: recover evidence tapes ({evidence}/{evidenceTotal})", showFlag = "broadcast_start", doneFlag = "all_evidence" },
}

-- Human-readable names for flags used as edit prerequisites.
Case01.flagLabels = {
	generator_restored = "station power restored",
}

-- Flags that also act as timeline anchors.
Case01.anchors = { "broadcast_start", "generator_restored", "board_recovered", "transmitter_armed", "loop_active", "components_complete", "extraction_open" }

---------------------------------------------------------------------------
-- Doors whose lock state is owned by the case.
---------------------------------------------------------------------------
Case01.doorLocks = {
	-- doorId = { lockedAtStart, unlockFlag }
	D_Lobby_Main = { locked = true },
	D_SVH_ML = { locked = true, unlockFlag = "generator_restored", reason = "Electronic lock — no power" },
	D_MP_EC = { locked = true, unlockFlag = "generator_restored", reason = "Electronic lock — no power" },
	D_MP_Arch = { locked = true, unlockFlag = "generator_restored", reason = "Electronic lock — no power" },
	D_EC_Arch = { locked = true, unlockFlag = "generator_restored", reason = "Electronic lock — no power" },
	D_TH_Trans = { locked = true, unlockFlag = "item_KEY", reason = "Needs the transmitter key" },
	D_SVH_Studio = { locked = true, unlockFlag = "extraction_open", reason = "Sealed from the inside" },
	D_Freight = { locked = true, reason = "Freight motor offline" },
}

Case01.spawns = {
	P("Lobby", 0.42, 0.66, 0),
	P("Lobby", 0.47, 0.68, 0),
	P("Lobby", 0.53, 0.68, 0),
	P("Lobby", 0.58, 0.66, 0),
}

-- Safe re-entry points for revives, latest unlocked first.
Case01.checkpoints = {
	{ id = "NorthHall", label = "NORTH HALL", pos = P("NorthHall", 0.5, 0.5, 0), requires = "components_complete" },
	{ id = "EditingSuite", label = "EDITING SUITE", pos = P("EditingSuite", 0.5, 0.6, 0), requires = "generator_restored" },
	{ id = "Lobby", label = "RECEPTION", pos = P("Lobby", 0.5, 0.62, 0) },
}

---------------------------------------------------------------------------
-- Hidden frames: single frames worth marking in the deck.
---------------------------------------------------------------------------
Case01.hiddenFrames = {
	{ id = "HF_T01_FIFTH", tape = "TAPE01", camera = "CAM01", t = 12.4, window = 0.5, text = "FIVE FIGURES IN FRAME. YOUR TEAM IS SMALLER." },
	{ id = "HF_T02_DECK", tape = "TAPE02", camera = "CAM09", t = 33, window = 0.5, text = "THE DECK SCREEN IS SHOWING THIS FRAME." },
	{ id = "HF_T03_SHELF", tape = "TAPE03", camera = "CAM08", t = 58.2, window = 0.5, text = "SHELF LABEL: RECOVERY TEAM · 2016 · DO NOT AIR" },
	{ id = "HF_T04_VAN", tape = "TAPE04", camera = "CAM12", t = 96.5, window = 0.5, text = "THE VAN IS ALREADY PARKED. IT HAS BEEN SINCE 1997." },
}

---------------------------------------------------------------------------
-- Optional investigator challenges (persisted once completed).
---------------------------------------------------------------------------
Case01.challenges = {
	{ id = "C01_UNUSED", label = "Off the Books", text = "Extract with at least one unused edit charge." },
	{ id = "C01_EVIDENCE", label = "Full Archive", text = "Recover every evidence tape in a single run." },
	{ id = "C01_NOLOSS", label = "Nobody Left Behind", text = "Extract with the whole team." },
	{ id = "C01_LOOP", label = "Spot the Difference", text = "Break the Loop on your first try." },
	{ id = "C01_CALLER", label = "Wrong Number", text = "Never enter the Caller's code." },
	{ id = "C01_FRAME", label = "Frame by Frame", text = "Mark a hidden frame during a case." },
	{ id = "C01_SOLO", label = "Lone Signal", text = "Complete the case alone." },
	{ id = "C01_RESTRICTED", label = "Restricted Clearance", text = "Complete the case in Restricted mode." },
}

---------------------------------------------------------------------------
-- Seeded variants.
---------------------------------------------------------------------------
Case01.variants = {
	-- When true for a seed, the east-corridor patrol starts at the control room end.
	patrolFlipEvent = "presenter_route_east",
}

return Case01
