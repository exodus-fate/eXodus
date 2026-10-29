--[[
	Broadcast Station 04 floor plan (plus the Division field office HQ).

	Everything is axis-aligned rectangles on a single floor (Y = 0) so that the map
	builder, the footage renderer and the game core can all reason about the same
	geometry. Coordinates are studs; +X is east and +Z is south.

	Rooms:      x0..x1, z0..z1 footprint, h = ceiling height.
	Doors:      a gap in the shared boundary between two rooms. `plane` names the
	            axis the boundary lies on ("z" = a wall running east-west at z = at).
	Windows:    glass panels in a shared boundary (the Presenter can see through them).
	Cameras:    CCTV positions used by tapes, monitors and footage.
]]

local Vec = require(script.Parent.Parent.Util.Vec)

local MapLayout = {}

local DOOR_HEIGHT = 9
MapLayout.DOOR_HEIGHT = DOOR_HEIGHT
MapLayout.WALL_THICKNESS = 1

-- Palette from the brief: muted green, dirty cream, warm grey, dusty brown and
-- faded industrial blue. Red is reserved for warnings.
MapLayout.Palette = {
	cream = { 196, 186, 158 },
	creamDark = { 150, 141, 117 },
	green = { 104, 122, 100 },
	greenDark = { 70, 84, 70 },
	grey = { 120, 116, 110 },
	greyDark = { 72, 70, 68 },
	brown = { 104, 86, 66 },
	brownDark = { 66, 54, 42 },
	blue = { 92, 108, 122 },
	blueDark = { 58, 68, 80 },
	concrete = { 110, 110, 104 },
	vinyl = { 128, 124, 104 },
	black = { 22, 24, 22 },
	warning = { 168, 52, 40 },
	amber = { 214, 150, 62 },
	fluorescent = { 222, 240, 226 },
}

--[[
	style: wall/floor colour keys and materials (Roblox Enum.Material names).
	lights: "grid" | "line" | "none" fluorescent layout.
	emergency: battery lights that work before the generator is restored.
	wing: which signal relay serves the room ("WEST", "EAST" or "CORE").
	refuge: a soundproof room - the Presenter cannot sense players inside while
	        its door is shut.
]]
MapLayout.Rooms = {
	Lobby = {
		label = "RECEPTION",
		x0 = -24, x1 = 24, z0 = 36, z1 = 72, h = 14,
		wall = "cream", trim = "brown", floor = "vinyl", floorMaterial = "Slate", wallMaterial = "Plaster",
		lights = "grid", emergency = true, wing = "CORE",
	},
	SouthHall = {
		label = "SOUTH HALL",
		x0 = -5, x1 = 5, z0 = 20, z1 = 36, h = 11,
		wall = "cream", trim = "brown", floor = "vinyl", floorMaterial = "Slate", wallMaterial = "Plaster",
		lights = "line", emergency = false, wing = "CORE",
	},
	ControlRoom = {
		label = "CONTROL ROOM",
		x0 = -20, x1 = 20, z0 = -20, z1 = 20, h = 13,
		wall = "green", trim = "greenDark", floor = "greyDark", floorMaterial = "Carpet", wallMaterial = "SmoothPlastic",
		lights = "grid", emergency = true, wing = "CORE",
	},
	StaffPassage = {
		label = "STAFF PASSAGE",
		x0 = -64, x1 = -24, z0 = 50, z1 = 58, h = 10,
		wall = "creamDark", trim = "brownDark", floor = "concrete", floorMaterial = "Concrete", wallMaterial = "Plaster",
		lights = "line", emergency = false, wing = "WEST",
	},
	StaffLink = {
		label = "STAFF PASSAGE",
		x0 = -64, x1 = -56, z0 = 6, z1 = 50, h = 10,
		wall = "creamDark", trim = "brownDark", floor = "concrete", floorMaterial = "Concrete", wallMaterial = "Plaster",
		lights = "line", emergency = false, wing = "WEST",
	},
	WestCorridor = {
		label = "WEST CORRIDOR",
		x0 = -100, x1 = -20, z0 = -6, z1 = 6, h = 11,
		wall = "green", trim = "greenDark", floor = "vinyl", floorMaterial = "Slate", wallMaterial = "Plaster",
		lights = "line", emergency = false, wing = "WEST",
	},
	Generator = {
		label = "GENERATOR ROOM",
		x0 = -136, x1 = -100, z0 = -20, z1 = 20, h = 14,
		wall = "grey", trim = "greyDark", floor = "concrete", floorMaterial = "Concrete", wallMaterial = "Concrete",
		lights = "grid", emergency = true, emergencyColor = "amber", wing = "WEST",
	},
	EditingSuite = {
		label = "EDITING SUITE",
		x0 = -90, x1 = -66, z0 = -34, z1 = -6, h = 11,
		wall = "blue", trim = "blueDark", floor = "greyDark", floorMaterial = "Carpet", wallMaterial = "Fabric",
		lights = "grid", emergency = false, wing = "WEST", refuge = true,
	},
	ServiceLink = {
		label = "SERVICE HALL",
		x0 = -40, x1 = -32, z0 = -40, z1 = -6, h = 10,
		wall = "grey", trim = "greyDark", floor = "concrete", floorMaterial = "Concrete", wallMaterial = "Concrete",
		lights = "line", emergency = false, wing = "WEST",
	},
	ServiceHall = {
		label = "SERVICE HALL",
		x0 = -40, x1 = 30, z0 = -48, z1 = -40, h = 10,
		wall = "grey", trim = "greyDark", floor = "concrete", floorMaterial = "Concrete", wallMaterial = "Concrete",
		lights = "line", emergency = false, wing = "WEST",
	},
	NorthHall = {
		label = "NORTH HALL",
		x0 = -5, x1 = 5, z0 = -40, z1 = -20, h = 11,
		wall = "green", trim = "greenDark", floor = "vinyl", floorMaterial = "Slate", wallMaterial = "Plaster",
		lights = "line", emergency = false, wing = "CORE",
	},
	TransmitterHall = {
		label = "TRANSMITTER ACCESS",
		x0 = -5, x1 = 5, z0 = -56, z1 = -48, h = 11,
		wall = "grey", trim = "greyDark", floor = "concrete", floorMaterial = "Concrete", wallMaterial = "Concrete",
		lights = "line", emergency = false, wing = "CORE",
	},
	Transmitter = {
		label = "TRANSMITTER CHAMBER",
		x0 = -32, x1 = 32, z0 = -104, z1 = -56, h = 26,
		wall = "greyDark", trim = "black", floor = "concrete", floorMaterial = "DiamondPlate", wallMaterial = "Concrete",
		lights = "grid", emergency = true, wing = "CORE",
	},
	MaintLink = {
		label = "MAINTENANCE",
		x0 = 22, x1 = 30, z0 = -40, z1 = -14, h = 9,
		wall = "greyDark", trim = "black", floor = "concrete", floorMaterial = "Concrete", wallMaterial = "Concrete",
		lights = "line", emergency = false, wing = "EAST",
	},
	MaintPassage = {
		label = "MAINTENANCE",
		x0 = 22, x1 = 104, z0 = -14, z1 = -6, h = 9,
		wall = "greyDark", trim = "black", floor = "concrete", floorMaterial = "Concrete", wallMaterial = "Concrete",
		lights = "line", emergency = false, wing = "EAST",
	},
	EastCorridor = {
		label = "EAST CORRIDOR",
		x0 = 20, x1 = 104, z0 = -6, z1 = 6, h = 11,
		wall = "cream", trim = "green", floor = "vinyl", floorMaterial = "Slate", wallMaterial = "Plaster",
		lights = "line", emergency = false, wing = "EAST",
	},
	Archive = {
		label = "TAPE ARCHIVE",
		x0 = 104, x1 = 140, z0 = -24, z1 = 24, h = 12,
		wall = "brown", trim = "brownDark", floor = "vinyl", floorMaterial = "Slate", wallMaterial = "Wood",
		lights = "grid", emergency = false, wing = "EAST",
	},
	StudioA = {
		label = "STUDIO A",
		x0 = -72, x1 = -40, z0 = -72, z1 = -40, h = 16,
		wall = "black", trim = "greyDark", floor = "greyDark", floorMaterial = "Concrete", wallMaterial = "Fabric",
		lights = "grid", emergency = false, wing = "WEST",
	},
	LoadingDock = {
		label = "LOADING DOCK",
		x0 = -30, x1 = 30, z0 = -140, z1 = -104, h = 0, outdoor = true,
		wall = "concrete", trim = "greyDark", floor = "concrete", floorMaterial = "Asphalt", wallMaterial = "Concrete",
		lights = "none", emergency = true, emergencyColor = "amber", wing = "CORE",
	},
	-- Division field office (pre-mission lobby), far south of the station.
	HQ = {
		label = "NBRD FIELD OFFICE",
		x0 = -30, x1 = 30, z0 = 240, z1 = 284, h = 12,
		wall = "blue", trim = "blueDark", floor = "greyDark", floorMaterial = "Carpet", wallMaterial = "Plaster",
		lights = "grid", emergency = false, wing = "CORE", hq = true,
	},
}

MapLayout.StationRooms = {
	"Lobby", "SouthHall", "ControlRoom", "StaffPassage", "StaffLink", "WestCorridor", "Generator",
	"EditingSuite", "ServiceLink", "ServiceHall", "NorthHall", "TransmitterHall", "Transmitter",
	"MaintLink", "MaintPassage", "EastCorridor", "Archive", "StudioA", "LoadingDock",
}

--[[
	kind: "door" (hinged single), "double" (main entrance), "freight" (sliding shutter),
	      "opening" (no panel - just an archway).
	window: door panel has a glass vision panel.
	outside: the door leads off-map (only the main entrance).
]]
MapLayout.Doors = {
	{ id = "D_Lobby_Main", rooms = { "Lobby" }, plane = "z", at = 72, center = 0, width = 8, kind = "double", outside = true, label = "Main Entrance" },
	{ id = "A_Lobby_SH", rooms = { "Lobby", "SouthHall" }, plane = "z", at = 36, center = 0, width = 10, kind = "opening" },
	{ id = "D_SH_CR", rooms = { "SouthHall", "ControlRoom" }, plane = "z", at = 20, center = 0, width = 5, kind = "door", window = true, label = "Control Room" },
	{ id = "D_Lobby_Staff", rooms = { "Lobby", "StaffPassage" }, plane = "x", at = -24, center = 54, width = 5, kind = "door", label = "Staff Only" },
	{ id = "A_Staff_Link", rooms = { "StaffPassage", "StaffLink" }, plane = "z", at = 50, center = -60, width = 8, kind = "opening" },
	{ id = "D_Link_WC", rooms = { "StaffLink", "WestCorridor" }, plane = "z", at = 6, center = -60, width = 5, kind = "door", label = "Staff Passage" },
	{ id = "D_CR_WC", rooms = { "ControlRoom", "WestCorridor" }, plane = "x", at = -20, center = 0, width = 5, kind = "door", window = true, label = "West Wing" },
	{ id = "D_WC_Gen", rooms = { "WestCorridor", "Generator" }, plane = "x", at = -100, center = 0, width = 6, kind = "door", label = "Generator Room" },
	{ id = "D_WC_ES", rooms = { "WestCorridor", "EditingSuite" }, plane = "z", at = -6, center = -78, width = 5, kind = "door", refuge = true, label = "Editing Suite" },
	{ id = "A_WC_SL", rooms = { "WestCorridor", "ServiceLink" }, plane = "z", at = -6, center = -36, width = 8, kind = "opening" },
	{ id = "A_SL_SVH", rooms = { "ServiceLink", "ServiceHall" }, plane = "z", at = -40, center = -36, width = 8, kind = "opening" },
	{ id = "D_SVH_Studio", rooms = { "ServiceHall", "StudioA" }, plane = "x", at = -40, center = -44, width = 5, kind = "door", label = "Studio A" },
	{ id = "D_CR_NH", rooms = { "ControlRoom", "NorthHall" }, plane = "z", at = -20, center = 0, width = 5, kind = "door", window = true, label = "North Hall" },
	{ id = "A_NH_SVH", rooms = { "NorthHall", "ServiceHall" }, plane = "z", at = -40, center = 0, width = 10, kind = "opening" },
	{ id = "A_SVH_TH", rooms = { "ServiceHall", "TransmitterHall" }, plane = "z", at = -48, center = 0, width = 10, kind = "opening" },
	{ id = "D_TH_Trans", rooms = { "TransmitterHall", "Transmitter" }, plane = "z", at = -56, center = 0, width = 6, kind = "door", label = "Transmitter Chamber" },
	{ id = "D_SVH_ML", rooms = { "ServiceHall", "MaintLink" }, plane = "z", at = -40, center = 26, width = 5, kind = "door", label = "Maintenance" },
	{ id = "A_ML_MP", rooms = { "MaintLink", "MaintPassage" }, plane = "z", at = -14, center = 26, width = 8, kind = "opening" },
	{ id = "D_MP_EC", rooms = { "MaintPassage", "EastCorridor" }, plane = "z", at = -6, center = 62, width = 4, kind = "door", label = "Crossover" },
	{ id = "D_MP_Arch", rooms = { "MaintPassage", "Archive" }, plane = "x", at = 104, center = -10, width = 4, kind = "door", label = "Archive (Rear)" },
	{ id = "D_CR_EC", rooms = { "ControlRoom", "EastCorridor" }, plane = "x", at = 20, center = 0, width = 5, kind = "door", window = true, label = "East Wing" },
	{ id = "D_EC_Arch", rooms = { "EastCorridor", "Archive" }, plane = "x", at = 104, center = 0, width = 6, kind = "door", window = true, label = "Tape Archive" },
	{ id = "D_Freight", rooms = { "Transmitter", "LoadingDock" }, plane = "z", at = -104, center = 0, width = 12, kind = "freight", label = "Freight Door" },
	-- HQ
	{ id = "D_HQ_Deploy", rooms = { "HQ" }, plane = "z", at = 284, center = 0, width = 8, kind = "double", outside = true, label = "Deployment Bay" },
}

-- Glass between the east corridor and the maintenance passage: the "silhouette
-- through glass" beat. Kept west of the crossover door on purpose (see Case 01).
MapLayout.Windows = {
	{ id = "W_EC_MP_1", rooms = { "EastCorridor", "MaintPassage" }, plane = "z", at = -6, center = 34, width = 6, y0 = 3.5, y1 = 7 },
	{ id = "W_EC_MP_2", rooms = { "EastCorridor", "MaintPassage" }, plane = "z", at = -6, center = 46, width = 6, y0 = 3.5, y1 = 7 },
}

local function P(roomId: string, u: number, v: number, y: number?)
	local room = MapLayout.Rooms[roomId]
	assert(room, "Unknown room " .. tostring(roomId))
	return Vec.new(room.x0 + (room.x1 - room.x0) * u, y or 0, room.z0 + (room.z1 - room.z0) * v)
end

-- Point inside a room from normalised coordinates: u runs west->east, v runs
-- north->south, y is height above the floor.
MapLayout.point = P

--[[
	CCTV cameras. `rooms` lists the rooms the camera can see (used to decide which
	actors appear on footage). `relay` is the signal relay the feed depends on;
	"LOCAL" cameras have their own battery and work before the generator is fixed;
	"MAINS" cameras need station power but no relay.
]]
MapLayout.Cameras = {
	CAM01 = { label = "CAM 01 · RECEPTION", pos = Vec.new(-22, 12.5, 70), look = Vec.new(6, 3, 42), rooms = { "Lobby" }, relay = "LOCAL" },
	CAM02 = { label = "CAM 02 · SOUTH HALL", pos = Vec.new(4, 9.5, 35), look = Vec.new(0, 4, 21), rooms = { "SouthHall" }, relay = "LOCAL" },
	CAM03 = { label = "CAM 03 · WEST CORRIDOR", pos = Vec.new(-22, 9.5, 5), look = Vec.new(-98, 3, 0), rooms = { "WestCorridor" }, relay = "WEST" },
	CAM04 = { label = "CAM 04 · GENERATOR", pos = Vec.new(-102, 12, 18), look = Vec.new(-125, 2, -10), rooms = { "Generator" }, relay = "WEST" },
	CAM05 = { label = "CAM 05 · EDITING SUITE", pos = Vec.new(-68, 9.5, -8), look = Vec.new(-85, 3, -30), rooms = { "EditingSuite" }, relay = "WEST" },
	CAM06 = { label = "CAM 06 · EAST CORRIDOR", pos = Vec.new(22, 9.5, 5), look = Vec.new(100, 3, 0), rooms = { "EastCorridor" }, relay = "EAST" },
	CAM07 = { label = "CAM 07 · MAINTENANCE", pos = Vec.new(24, 7.5, -7), look = Vec.new(100, 2, -12), rooms = { "MaintPassage" }, relay = "EAST" },
	CAM08 = { label = "CAM 08 · TAPE ARCHIVE", pos = Vec.new(106, 10.5, 22), look = Vec.new(130, 2, -15), rooms = { "Archive" }, relay = "EAST" },
	CAM09 = { label = "CAM 09 · CONTROL ROOM", pos = Vec.new(-18, 11, 18), look = Vec.new(10, 2, -12), rooms = { "ControlRoom" }, relay = "LOCAL" },
	CAM10 = { label = "CAM 10 · SERVICE HALL", pos = Vec.new(-38, 8.5, -41), look = Vec.new(28, 2, -46), rooms = { "ServiceHall" }, relay = "WEST" },
	CAM11 = { label = "CAM 11 · TRANSMITTER", pos = Vec.new(30, 22, -58), look = Vec.new(-10, 4, -95), rooms = { "Transmitter", "TransmitterHall" }, relay = "MAINS" },
	CAM12 = { label = "CAM 12 · LOADING DOCK", pos = Vec.new(28, 10, -106), look = Vec.new(-10, 1, -135), rooms = { "LoadingDock" }, relay = "MAINS" },
	CAM13 = { label = "CAM 13 · STUDIO A", pos = Vec.new(-42, 13, -42), look = Vec.new(-65, 3, -68), rooms = { "StudioA" }, relay = "WEST" },
}

MapLayout.CameraOrder = {
	"CAM01", "CAM02", "CAM03", "CAM04", "CAM05", "CAM06", "CAM07",
	"CAM08", "CAM09", "CAM10", "CAM11", "CAM12", "CAM13",
}

MapLayout.Relays = {
	WEST = { label = "WEST RELAY", room = "Generator", pos = P("Generator", 0.92, 0.12, 0) },
	EAST = { label = "EAST RELAY", room = "MaintPassage", pos = P("MaintPassage", 0.9, 0.12, 0) },
}

MapLayout.HQSpawn = P("HQ", 0.5, 0.45, 0)

-- Returns the room containing a point, preferring the smallest match so that
-- doorway overlaps resolve to the corridor rather than the big room.
function MapLayout.roomAt(x: number, z: number, margin: number?): string?
	margin = margin or 0
	local best, bestArea = nil, math.huge
	for id, room in MapLayout.Rooms do
		if x >= room.x0 - margin and x <= room.x1 + margin and z >= room.z0 - margin and z <= room.z1 + margin then
			local area = (room.x1 - room.x0) * (room.z1 - room.z0)
			if area < bestArea then
				best, bestArea = id, area
			end
		end
	end
	return best
end

function MapLayout.inRooms(pos, rooms: { string }, margin: number?): boolean
	margin = margin or 0
	for _, id in rooms do
		local room = MapLayout.Rooms[id]
		if room and pos.x >= room.x0 - margin and pos.x <= room.x1 + margin and pos.z >= room.z0 - margin and pos.z <= room.z1 + margin then
			return true
		end
	end
	return false
end

function MapLayout.roomCenter(roomId: string)
	return P(roomId, 0.5, 0.5, 0)
end

function MapLayout.doorById(doorId: string)
	for _, door in MapLayout.Doors do
		if door.id == doorId then
			return door
		end
	end
	return nil
end

-- World-space centre of a door gap at floor level.
function MapLayout.doorPosition(door)
	if door.plane == "z" then
		return Vec.new(door.center, 0, door.at)
	end
	return Vec.new(door.at, 0, door.center)
end

return MapLayout
