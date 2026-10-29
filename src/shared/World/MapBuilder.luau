--[[
	Builds Broadcast Station 04 and the Division field office from MapLayout.

	Greybox-first, modular construction: every room is a floor, a ceiling and four
	walls with openings cut where MapLayout puts doors and windows. Props are simple
	boxes with readable silhouettes. All interactive things carry attributes and
	tags so the server can find them even after the map is edited in Studio:

	  Station04
	    Rooms/<RoomId>/{Shell, Lights, Props, Signs}
	    Doors/<DoorId>        Model, attributes DoorId, Kind, SwingSign; Panel part(s)
	    Windows/Glass         attribute SeeThrough
	    Cameras/<CamId>       CCTV housings
	    Anchors/<InteractId>  invisible parts that hold ProximityPrompts
	    LoopProps/<PropId>    Normal / Odd variants for the Loop anomaly
	    Spawns/Spawn<n>
	  FieldOffice (HQ)
]]

local MapLayout = require(script.Parent.Parent.Config.MapLayout)
local Props = require(script.Parent.Props)

local MapBuilder = {}

local T = MapLayout.WALL_THICKNESS
local DOOR_H = MapLayout.DOOR_HEIGHT
local part = Props.part

local function V(p, y)
	return Vector3.new(p.x, y or p.y or 0, p.z)
end

local function folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- CFrame at a floor point whose front (-Z) faces the given direction.
local function facing(pos, dir)
	return CFrame.lookAt(pos, pos + dir)
end

local NORTH, SOUTH, EAST, WEST = Vector3.new(0, 0, -1), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0)

---------------------------------------------------------------------------
-- Room shell
---------------------------------------------------------------------------

local function doorTop(door)
	if door.kind == "opening" then
		local lowest = math.huge
		for _, id in door.rooms do
			lowest = math.min(lowest, MapLayout.Rooms[id].h)
		end
		return math.max(DOOR_H, lowest - 1)
	elseif door.kind == "freight" then
		return 10
	end
	return DOOR_H
end

-- Openings along one edge of a room: { a, b, bottom, top }
local function edgeOpenings(roomId, room, edge)
	local list = {}
	local function onEdge(entry)
		if not table.find(entry.rooms, roomId) then
			return false
		end
		if entry.plane == "z" then
			return (edge == "N" and entry.at == room.z0) or (edge == "S" and entry.at == room.z1)
		end
		return (edge == "W" and entry.at == room.x0) or (edge == "E" and entry.at == room.x1)
	end
	for _, door in MapLayout.Doors do
		if onEdge(door) then
			table.insert(list, { a = door.center - door.width / 2, b = door.center + door.width / 2, bottom = 0, top = doorTop(door) })
		end
	end
	for _, win in MapLayout.Windows do
		if onEdge(win) then
			table.insert(list, { a = win.center - win.width / 2, b = win.center + win.width / 2, bottom = win.y0, top = win.y1 })
		end
	end
	table.sort(list, function(x, y)
		return x.a < y.a
	end)
	return list
end

local function wallPiece(parent, room, edge, a, b, y0, y1, colour, material)
	if b - a < 0.01 or y1 - y0 < 0.01 then
		return
	end
	local len, height = b - a, y1 - y0
	local mid, y = (a + b) / 2, (y0 + y1) / 2
	local size, pos
	if edge == "N" then
		size, pos = Vector3.new(len, height, T), Vector3.new(mid, y, room.z0 + T / 2)
	elseif edge == "S" then
		size, pos = Vector3.new(len, height, T), Vector3.new(mid, y, room.z1 - T / 2)
	elseif edge == "W" then
		size, pos = Vector3.new(T, height, len), Vector3.new(room.x0 + T / 2, y, mid)
	else
		size, pos = Vector3.new(T, height, len), Vector3.new(room.x1 - T / 2, y, mid)
	end
	part(parent, "Wall", size, CFrame.new(pos), colour, { material = material })
end

local function buildWall(parent, roomId, room, edge, height)
	local wallColour = room.wall
	local material = Enum.Material[room.wallMaterial or "Plaster"]
	local s0, s1
	if edge == "N" or edge == "S" then
		s0, s1 = room.x0, room.x1
	else
		s0, s1 = room.z0, room.z1
	end
	local cursor = s0
	for _, o in edgeOpenings(roomId, room, edge) do
		wallPiece(parent, room, edge, cursor, o.a, 0, height, wallColour, material)
		if o.bottom > 0 then
			wallPiece(parent, room, edge, o.a, o.b, 0, o.bottom, wallColour, material)
		end
		if o.top < height then
			wallPiece(parent, room, edge, o.a, o.b, o.top, height, wallColour, material)
		end
		cursor = math.max(cursor, o.b)
	end
	wallPiece(parent, room, edge, cursor, s1, 0, height, wallColour, material)
	-- Skirting board: a darker trim line that helps rooms read in low light.
	if not room.outdoor then
		local trimParent = parent
		if edge == "N" or edge == "S" then
			local z = edge == "N" and (room.z0 + T + 0.05) or (room.z1 - T - 0.05)
			part(trimParent, "Skirting", Vector3.new(room.x1 - room.x0 - 2 * T, 0.6, 0.1), CFrame.new((room.x0 + room.x1) / 2, 0.3, z), room.trim, { collide = false, shadow = false })
		else
			local x = edge == "W" and (room.x0 + T + 0.05) or (room.x1 - T - 0.05)
			part(trimParent, "Skirting", Vector3.new(0.1, 0.6, room.z1 - room.z0 - 2 * T), CFrame.new(x, 0.3, (room.z0 + room.z1) / 2), room.trim, { collide = false, shadow = false })
		end
	end
end

local function buildShell(roomFolder, roomId, room)
	local shell = folder(roomFolder, "Shell")
	local w, d = room.x1 - room.x0, room.z1 - room.z0
	local cx, cz = (room.x0 + room.x1) / 2, (room.z0 + room.z1) / 2
	local floor = part(shell, "Floor", Vector3.new(w, 1, d), CFrame.new(cx, -0.5, cz), room.floor, {
		material = Enum.Material[room.floorMaterial or "Concrete"],
	})
	floor:SetAttribute("RoomId", roomId)
	if room.outdoor then
		for _, edge in { "N", "W", "E" } do
			buildWall(shell, roomId, room, edge, 10)
		end
		return
	end
	part(shell, "Ceiling", Vector3.new(w, 1, d), CFrame.new(cx, room.h + 0.5, cz), room.hq and "creamDark" or "greyDark", {
		material = Enum.Material.SmoothPlastic,
		shadow = true,
	})
	for _, edge in { "N", "S", "W", "E" } do
		buildWall(shell, roomId, room, edge, room.h)
	end
end

---------------------------------------------------------------------------
-- Lighting
---------------------------------------------------------------------------

local FLUORESCENT = Props.rgb(MapLayout.Palette.fluorescent)
local AMBER = Props.rgb(MapLayout.Palette.amber)

local function fluorescent(parent, pos, along, roomId, range, shadows)
	local size = along == "x" and Vector3.new(4, 0.2, 1.2) or Vector3.new(1.2, 0.2, 4)
	local panel = part(parent, "Fluorescent", size, CFrame.new(pos), FLUORESCENT, {
		material = Enum.Material.Neon,
		collide = false,
		shadow = false,
	})
	panel:SetAttribute("LightKind", "Fluorescent")
	panel:SetAttribute("RoomId", roomId)
	local light = Instance.new("SurfaceLight")
	light.Name = "Light"
	light.Face = Enum.NormalId.Bottom
	light.Angle = 120
	light.Range = range
	light.Brightness = 1.3
	light.Color = FLUORESCENT
	light.Shadows = shadows == true
	light.Parent = panel
	return panel
end

local function emergencyLight(parent, pos, roomId, colour)
	local box = part(parent, "Emergency", Vector3.new(0.9, 0.5, 0.5), CFrame.new(pos), colour or AMBER, {
		material = Enum.Material.Neon,
		collide = false,
		shadow = false,
	})
	box:SetAttribute("LightKind", "Emergency")
	box:SetAttribute("RoomId", roomId)
	local light = Instance.new("PointLight")
	light.Name = "Light"
	light.Range = 20
	light.Brightness = 0.9
	light.Color = colour or AMBER
	light.Shadows = false
	light.Parent = box
	return box
end

local function buildLights(roomFolder, roomId, room)
	local lights = folder(roomFolder, "Lights")
	local w, d = room.x1 - room.x0, room.z1 - room.z0
	local y = room.h - 0.15
	local range = math.min(room.h + 6, 22)
	if room.lights == "grid" then
		local spacing = (w * d > 2000) and 20 or 17
		local nx = math.max(1, math.floor(w / spacing + 0.5))
		local nz = math.max(1, math.floor(d / spacing + 0.5))
		for i = 1, nx do
			for j = 1, nz do
				local x = room.x0 + w * (i - 0.5) / nx
				local z = room.z0 + d * (j - 0.5) / nz
				-- Only the first fixture casts shadows: atmosphere without the cost.
				fluorescent(lights, Vector3.new(x, y, z), "x", roomId, range, i == 1 and j == 1 and not room.hq)
			end
		end
	elseif room.lights == "line" then
		local along = w >= d and "x" or "z"
		local length = math.max(w, d)
		local n = math.max(1, math.floor(length / 16 + 0.5))
		for i = 1, n do
			local t = (i - 0.5) / n
			local pos = along == "x" and Vector3.new(room.x0 + w * t, y, (room.z0 + room.z1) / 2)
				or Vector3.new((room.x0 + room.x1) / 2, y, room.z0 + d * t)
			fluorescent(lights, pos, along, roomId, range, false)
		end
	end
	if room.emergency then
		local colour = AMBER
		if room.outdoor then
			return lights
		end
		emergencyLight(lights, Vector3.new((room.x0 + room.x1) / 2, room.h - 1.2, room.z0 + T + 0.3), roomId, colour)
		if w * d > 1200 then
			emergencyLight(lights, Vector3.new((room.x0 + room.x1) / 2, room.h - 1.2, room.z1 - T - 0.3), roomId, colour)
		end
	end
	return lights
end

---------------------------------------------------------------------------
-- Doors and windows
---------------------------------------------------------------------------

-- The depth (perpendicular to the wall) at which panels and trim sit.
local function doorDepth(door)
	if #door.rooms == 2 then
		return door.at
	end
	local room = MapLayout.Rooms[door.rooms[1]]
	if door.plane == "z" then
		return door.at == room.z0 and door.at + T / 2 or door.at - T / 2
	end
	return door.at == room.x0 and door.at + T / 2 or door.at - T / 2
end

-- World CFrame at a point on the door's plane, with the panel's X axis running
-- along the wall.
local function doorFrame(door, along, y)
	local depth = doorDepth(door)
	if door.plane == "z" then
		return CFrame.new(along, y, depth)
	end
	return CFrame.new(depth, y, along) * CFrame.Angles(0, math.rad(90), 0)
end

local function roomArea(id)
	local r = MapLayout.Rooms[id]
	return (r.x1 - r.x0) * (r.z1 - r.z0)
end

-- Which way (+1/-1 around Y) the panel swings so it opens into the bigger room.
local function swingSign(door)
	local target = door.rooms[1]
	if #door.rooms == 2 and roomArea(door.rooms[2]) > roomArea(door.rooms[1]) then
		target = door.rooms[2]
	end
	local room = MapLayout.Rooms[target]
	if door.plane == "z" then
		-- +90 deg swings toward -Z (north).
		local roomIsNorth = room.z1 == door.at
		return roomIsNorth and 1 or -1
	end
	-- Rotated panels: +90 deg swings toward -X (west).
	local roomIsWest = room.x1 == door.at
	return roomIsWest and 1 or -1
end

local function addPathModifier(target, label, passThrough)
	local modifier = Instance.new("PathfindingModifier")
	modifier.Label = label
	modifier.PassThrough = passThrough
	modifier.Parent = target
end

local function buildPanel(model, door, centre, width, colour, withWindow)
	local ph = DOOR_H - 0.2
	local thickness = 0.3
	local base = doorFrame(door, centre, 0)
	if not withWindow then
		local panel = part(model, "Panel", Vector3.new(width, ph, thickness), base * CFrame.new(0, ph / 2, 0), colour, { material = Enum.Material.Wood })
		return panel
	end
	local winBottom, winTop, winWidth = 4.6, 7.2, math.min(1.6, width - 1)
	local lower = part(model, "Panel", Vector3.new(width, winBottom, thickness), base * CFrame.new(0, winBottom / 2, 0), colour, { material = Enum.Material.Wood })
	local pieces = {
		part(model, "PanelUpper", Vector3.new(width, ph - winTop, thickness), base * CFrame.new(0, (winTop + ph) / 2, 0), colour, { material = Enum.Material.Wood, anchored = false, massless = true }),
		part(model, "PanelLeft", Vector3.new((width - winWidth) / 2, winTop - winBottom, thickness), base * CFrame.new(-(width + winWidth) / 4, (winBottom + winTop) / 2, 0), colour, { material = Enum.Material.Wood, anchored = false, massless = true }),
		part(model, "PanelRight", Vector3.new((width - winWidth) / 2, winTop - winBottom, thickness), base * CFrame.new((width + winWidth) / 4, (winBottom + winTop) / 2, 0), colour, { material = Enum.Material.Wood, anchored = false, massless = true }),
	}
	local glass = part(model, "VisionGlass", Vector3.new(winWidth, winTop - winBottom, 0.12), base * CFrame.new(0, (winBottom + winTop) / 2, 0), Color3.fromRGB(150, 170, 160), {
		material = Enum.Material.Glass,
		transparency = 0.55,
		anchored = false,
		massless = true,
		shadow = false,
	})
	glass:SetAttribute("SeeThrough", true)
	table.insert(pieces, glass)
	for _, piece in pieces do
		Props.weld(lower, piece)
	end
	return lower
end

local function buildDoor(doorsFolder, door, trimColour)
	local model = Instance.new("Model")
	model.Name = door.id
	model:SetAttribute("DoorId", door.id)
	model:SetAttribute("Kind", door.kind)
	model:SetAttribute("Label", door.label or "")
	model:SetAttribute("Refuge", door.refuge == true)
	model.Parent = doorsFolder

	local depthSize = (#door.rooms == 2) and (2 * T + 0.2) or (T + 0.2)
	local top = doorTop(door)
	local half = door.width / 2
	-- Trim: jambs and header around the opening.
	for _, side in { -1, 1 } do
		part(model, "Jamb", Vector3.new(0.3, top, depthSize), doorFrame(door, door.center + side * (half + 0.15), top / 2), trimColour, { collide = false })
	end
	part(model, "Header", Vector3.new(door.width + 0.6, 0.4, depthSize), doorFrame(door, door.center, top + 0.2), trimColour, { collide = false })

	if door.kind == "opening" then
		return model
	end

	local panelColour = door.window and "brown" or "brownDark"
	if door.kind == "freight" then
		local shutter = part(model, "Panel", Vector3.new(door.width, top, 0.5), doorFrame(door, door.center, top / 2), "greyDark", { material = Enum.Material.CorrodedMetal })
		for i = 1, 8 do
			part(model, "Slat" .. i, Vector3.new(door.width, 0.1, 0.55), doorFrame(door, door.center, i * top / 9), "black", {
				collide = false,
				shadow = false,
				anchored = false,
				massless = true,
			})
		end
		for _, child in model:GetChildren() do
			if string.sub(child.Name, 1, 4) == "Slat" then
				Props.weld(shutter, child)
			end
		end
		model.PrimaryPart = shutter
		addPathModifier(shutter, "LockedDoor", false)
		return model
	end

	if door.kind == "double" then
		local w = door.width / 2 - 0.1
		local left = buildPanel(model, door, door.center - door.width / 4, w, "greyDark", true)
		left.Name = "PanelL"
		local right = buildPanel(model, door, door.center + door.width / 4, w, "greyDark", true)
		right.Name = "PanelR"
		-- buildPanel names the lower piece "Panel"; keep one primary.
		model.PrimaryPart = left
		addPathModifier(left, "LockedDoor", false)
		addPathModifier(right, "LockedDoor", false)
		return model
	end

	local panel = buildPanel(model, door, door.center, door.width - 0.2, panelColour, door.window)
	model.PrimaryPart = panel
	model:SetAttribute("SwingSign", swingSign(door))
	model:SetAttribute("PanelWidth", door.width - 0.2)
	-- Pathfinding treats closed (unlocked) doors as passable; the server opens
	-- them when the Presenter arrives. Locked doors are relabelled at runtime.
	addPathModifier(panel, "Door", true)
	local handle = part(model, "Handle", Vector3.new(0.4, 0.15, 0.5), doorFrame(door, door.center + half - 0.6, 3.6), "grey", {
		collide = false,
		shadow = false,
		anchored = false,
		massless = true,
		material = Enum.Material.Metal,
	})
	Props.weld(panel, handle)
	return model
end

local function buildWindows(windowsFolder)
	for _, win in MapLayout.Windows do
		local depthSize = 2 * T
		local cf
		if win.plane == "z" then
			cf = CFrame.new(win.center, (win.y0 + win.y1) / 2, win.at)
		else
			cf = CFrame.new(win.at, (win.y0 + win.y1) / 2, win.center) * CFrame.Angles(0, math.rad(90), 0)
		end
		local glass = part(windowsFolder, "Glass", Vector3.new(win.width, win.y1 - win.y0, 0.2), cf, Color3.fromRGB(140, 160, 150), {
			material = Enum.Material.Glass,
			transparency = 0.6,
			shadow = false,
		})
		glass:SetAttribute("SeeThrough", true)
		glass:SetAttribute("WindowId", win.id)
		part(windowsFolder, "Sill", Vector3.new(win.width + 0.4, 0.25, depthSize + 0.2), cf * CFrame.new(0, -(win.y1 - win.y0) / 2 - 0.1, 0), "creamDark", {
			collide = false,
		})
	end
end

---------------------------------------------------------------------------
-- Signage: each doorway is labelled with where it leads.
---------------------------------------------------------------------------

local function buildSigns(station)
	local signs = folder(station, "Signs")
	for _, door in MapLayout.Doors do
		if #door.rooms == 2 then
			for i, roomId in door.rooms do
				local other = MapLayout.Rooms[door.rooms[3 - i]]
				local room = MapLayout.Rooms[roomId]
				local normal, depth
				if door.plane == "z" then
					if door.at == room.z0 then
						normal, depth = SOUTH, door.at + T + 0.06
					else
						normal, depth = NORTH, door.at - T - 0.06
					end
				else
					if door.at == room.x0 then
						normal, depth = EAST, door.at + T + 0.06
					else
						normal, depth = WEST, door.at - T - 0.06
					end
				end
				local top = math.min(doorTop(door) + 0.9, room.h - 0.6)
				local pos
				if door.plane == "z" then
					pos = Vector3.new(door.center, top, depth)
				else
					pos = Vector3.new(depth, top, door.center)
				end
				if top > DOOR_H then
					Props.sign(signs, facing(pos, normal), math.min(5.5, door.width + 1.5), 0.8, other.label, "creamDark")
				end
			end
		end
	end
	return signs
end

---------------------------------------------------------------------------
-- Furnishing
---------------------------------------------------------------------------

local P = MapLayout.point

local function monitor(parent, cf, scale, cameraId, role)
	local m, screen = Props.crt(parent, cf, scale)
	if cameraId then
		screen:AddTag("CCTVMonitor")
		screen:SetAttribute("CameraId", cameraId)
		if role then
			screen:SetAttribute("MonitorRole", role)
		end
	end
	return m, screen
end

local Furnish = {}

function Furnish.Lobby(f)
	Props.desk(f, facing(Vector3.new(0, 0, 46.8), SOUTH), 14, 3, 3.4, "brown")
	-- Reception VCR + TV (DECK_LOBBY).
	Props.vcr(f, facing(Vector3.new(4.8, 3.4, 46.8), SOUTH))
	monitor(f, facing(Vector3.new(4.8, 4, 46.8), SOUTH), 0.9, "CAM01", "LobbyVCR")
	-- Briefing terminal.
	part(f, "TerminalTable", Vector3.new(3, 3, 2.4), CFrame.new(-12, 1.5, 46.8), "brownDark", { material = Enum.Material.Wood })
	Props.beigeComputer(f, facing(Vector3.new(-12, 3, 46.8), SOUTH))
	for i = 0, 3 do
		Props.chair(f, facing(Vector3.new(20.5, 0, 52 + i * 4), WEST), "blueDark")
	end
	Props.bench(f, facing(Vector3.new(-21.5, 0, 58), EAST), 7)
	part(f, "SideTable", Vector3.new(2, 2.6, 2), CFrame.new(-20.2, 1.3, 66.6), "brownDark", { material = Enum.Material.Wood })
	Props.plant(f, CFrame.new(-21.5, 0, 69.5))
	Props.plant(f, CFrame.new(21.5, 0, 69.5))
	Props.sign(f, facing(Vector3.new(0, 12, 37.06), SOUTH), 16, 1.6, "BROADCAST STATION 04", "cream")
	Props.wallClock(f, facing(Vector3.new(-14, 9, 37.15), SOUTH), "00:00")
	Props.poster(f, facing(Vector3.new(-22.94, 6, 44), EAST), 4, 3, "STAFF NOTICE\nNIGHT BULLETIN 00:00\nDO NOT ADJUST THE DECK AFTER SIGN-OFF")
	Props.poster(f, facing(Vector3.new(22.94, 6, 44), WEST), 3, 4, "CHANNEL 4\nTHE VOICE OF THE VALLEY\nSINCE 1971")
end

function Furnish.SouthHall(f)
	Props.bench(f, facing(Vector3.new(-3.4, 0, 29), EAST), 5)
	Props.extinguisher(f, facing(Vector3.new(4.3, 0, 26), WEST))
end

function Furnish.ControlRoom(f)
	-- Monitor wall along the north wall: live CCTV feeds.
	part(f, "MonitorBank", Vector3.new(32, 3.2, 2.6), CFrame.new(0, 1.6, -17.7), "greyDark", { material = Enum.Material.Metal })
	part(f, "MonitorShelf", Vector3.new(32, 0.3, 2.2), CFrame.new(0, 6.1, -18), "greyDark", { material = Enum.Material.Metal })
	local lower = { "CAM01", "CAM02", "CAM03", "CAM06", "CAM07" }
	local upper = { "CAM08", "CAM10", "CAM11", "CAM12", "CAM04" }
	for i = 1, 5 do
		local x = -12 + (i - 1) * 6
		monitor(f, facing(Vector3.new(x, 3.2, -17.6), SOUTH), 1.3, lower[i])
		monitor(f, facing(Vector3.new(x, 6.25, -18), SOUTH), 1.3, upper[i])
	end
	-- Time-Shift Deck desk (DECK_MAIN).
	Props.desk(f, facing(Vector3.new(0, 0, -10), SOUTH), 10, 3, 3.4, "greyDark")
	local deck = Props.vcr(f, facing(Vector3.new(0, 3.4, -10), SOUTH), "black")
	deck.Name = "TimeShiftDeck"
	monitor(f, facing(Vector3.new(0, 4, -10.6), SOUTH), 1.1, "CAM09", "MainDeck")
	Props.mixingConsole(f, facing(Vector3.new(-8, 0, -10.2), SOUTH), 5)
	Props.mixingConsole(f, facing(Vector3.new(8, 0, -10.2), SOUTH), 5)
	Props.chair(f, facing(Vector3.new(0, 0, -7.4), NORTH), "greyDark")
	Props.chair(f, facing(Vector3.new(-6, 0, -7.9), NORTH), "greyDark")
	for i = 0, 3 do
		Props.equipmentRack(f, facing(Vector3.new(-18.2, 0, -6 + i * 4), EAST), 7)
		Props.equipmentRack(f, facing(Vector3.new(18.2, 0, -6 + i * 4), WEST), 7)
	end
	Props.wallClock(f, facing(Vector3.new(10, 9, 18.85), NORTH), "00:17")
	Props.sign(f, facing(Vector3.new(0, 10.6, -18.94), SOUTH), 12, 1.2, "MASTER CONTROL · STATION 04", "greenDark", Color3.fromRGB(196, 186, 158))
end

function Furnish.WestCorridor(f)
	Props.extinguisher(f, facing(Vector3.new(-30, 0, 5.3), NORTH))
	Props.poster(f, facing(Vector3.new(-50, 5.5, -5.06), SOUTH), 3, 2.5, "SAFETY FIRST\nREPORT ALL FAULTS")
	Props.pipe(f, Vector3.new(-99, 10, 4.5), Vector3.new(-21, 10, 4.5), 0.25)
end

function Furnish.StaffPassage(f)
	Props.crate(f, CFrame.new(-52, 0, 52), Vector3.new(2, 2.6, 2))
	Props.crate(f, CFrame.new(-36, 0, 56.6), Vector3.new(2.4, 2, 2.4))
end

function Furnish.StaffLink(f)
	Props.poster(f, facing(Vector3.new(-56.94, 5.5, 30), WEST), 2.5, 3, "STAFF ONLY\nBEYOND THIS POINT")
end

function Furnish.Generator(f)
	Props.generator(f, facing(Vector3.new(-118, 0, 0), NORTH))
	Props.cage(f, facing(Vector3.new(-131.7, 0, 14), EAST))
	Props.relayBox(f, facing(Vector3.new(-101.45, 4, -15.2), WEST), "WEST RELAY")
	part(f, "Workbench", Vector3.new(3, 2.6, 2), CFrame.new(-107.2, 1.3, 14), "brownDark", { material = Enum.Material.Wood })
	Props.cabinet(f, facing(Vector3.new(-127, 0, -15.2), SOUTH), 2.4, 2.6, 1.6, "greyDark")
	for i = 0, 2 do
		Props.cabinet(f, facing(Vector3.new(-128 + i * 5, 0, -18.6), SOUTH), 3, 6.5, 1.4, "grey")
	end
	Props.pipe(f, Vector3.new(-135, 12, -10), Vector3.new(-101, 12, -10), 0.5, "greyDark")
	Props.pipe(f, Vector3.new(-135, 12.5, 8), Vector3.new(-101, 12.5, 8), 0.35, "brownDark")
	Props.sign(f, facing(Vector3.new(-118, 10, 18.94), NORTH), 10, 1, "DANGER · HIGH VOLTAGE", "cream", Props.rgb(MapLayout.Palette.warning))
end

function Furnish.EditingSuite(f)
	Props.desk(f, facing(Vector3.new(-78, 0, -30.8), SOUTH), 12, 3, 3.4, "greyDark")
	local deck = Props.vcr(f, facing(Vector3.new(-78, 3.4, -30.4), SOUTH), "black")
	deck.Name = "EditDeck"
	monitor(f, facing(Vector3.new(-78, 4, -31.2), SOUTH), 1, "CAM05", "EditDeck")
	monitor(f, facing(Vector3.new(-82.5, 3.4, -31.4), SOUTH), 0.9)
	monitor(f, facing(Vector3.new(-73.5, 3.4, -31.4), SOUTH), 0.9)
	Props.chair(f, facing(Vector3.new(-78, 0, -27), NORTH), "blueDark")
	for _, pos in { Vector3.new(-85.68, 0, -18.6), Vector3.new(-70.32, 0, -14.4) } do
		part(f, "Cart", Vector3.new(1.8, 2.6, 1.4), CFrame.new(pos + Vector3.new(0, 1.3, 0)), "grey", { material = Enum.Material.Metal })
	end
	for i = 0, 3 do
		part(f, "AcousticPanel", Vector3.new(0.2, 4, 3), CFrame.new(-89.1, 5.5, -30 + i * 6), "blueDark", { material = Enum.Material.Fabric, collide = false })
	end
	Props.sign(f, facing(Vector3.new(-78, 9.8, -7.06), NORTH), 7, 0.9, "EDIT BAY · SOUNDPROOF · KEEP DOOR SHUT", "blueDark", Color3.fromRGB(196, 186, 158))
end

function Furnish.ServiceHall(f)
	Props.crate(f, CFrame.new(16, 0, -46), Vector3.new(2, 2.6, 2))
	Props.pipe(f, Vector3.new(-39, 8.6, -47), Vector3.new(29, 8.6, -47), 0.4)
	Props.pipe(f, Vector3.new(-39, 9.2, -41.5), Vector3.new(29, 9.2, -41.5), 0.25, "brownDark")
end

function Furnish.ServiceLink(f)
	Props.pipe(f, Vector3.new(-33.5, 8.6, -39), Vector3.new(-33.5, 8.6, -7), 0.35)
end

function Furnish.NorthHall(f)
	Props.poster(f, facing(Vector3.new(-4.94, 5.5, -30), EAST), 2.5, 3, "TRANSMITTER\nAUTHORISED STAFF")
end

function Furnish.MaintLink(f)
	Props.pipe(f, Vector3.new(29, 7.6, -39), Vector3.new(29, 7.6, -15), 0.35)
end

function Furnish.MaintPassage(f)
	Props.crate(f, CFrame.new(58.9, 0, -12.4), Vector3.new(2, 2.6, 2))
	Props.relayBox(f, facing(Vector3.new(95.8, 4, -12.55), SOUTH), "EAST RELAY")
	Props.pipe(f, Vector3.new(23, 7.8, -13), Vector3.new(103, 7.8, -13), 0.35)
	Props.pipe(f, Vector3.new(23, 8.3, -8), Vector3.new(103, 8.3, -8), 0.25, "brownDark")
end

function Furnish.EastCorridor(f)
	Props.extinguisher(f, facing(Vector3.new(84, 0, 5.3), NORTH))
	Props.poster(f, facing(Vector3.new(90, 5.5, 5.06), NORTH), 3, 2.5, "ARCHIVE\nSIGN ALL TAPES OUT")
end

function Furnish.Archive(f)
	Props.equipmentRack(f, facing(Vector3.new(122, 0, 0), WEST), 6, "BoardRack")
	Props.desk(f, facing(Vector3.new(114.1, 0, -14.4), SOUTH), 8, 3, 3.3, "brown")
	local tapes = { "creamDark", "brown", "greyDark", "blueDark", "greenDark" }
	local northShelf = Props.shelf(f, facing(Vector3.new(130, 0, -18.24), SOUTH), 12, 6, 1.5)
	Props.tapeRow(northShelf, CFrame.new(127, 4.1, -18.24), 4, tapes)
	Props.tapeRow(northShelf, CFrame.new(131.5, 5.7, -18.24), 7, tapes)
	for i = 0, 2 do
		local shelf = Props.shelf(f, facing(Vector3.new(110 + i * 12, 0, 22.2), NORTH), 10, 7, 1.5)
		Props.tapeRow(shelf, CFrame.new(110 + i * 12, 2.5, 22.2), 9, tapes)
		Props.tapeRow(shelf, CFrame.new(110 + i * 12, 4.1, 22.2), 9, tapes)
	end
	for i = 0, 1 do
		local shelf = Props.shelf(f, facing(Vector3.new(138.2, 0, 4 + i * 10), WEST), 8, 7, 1.5)
		Props.tapeRow(shelf, CFrame.new(138.2, 2.5, 4 + i * 10) * CFrame.Angles(0, math.rad(90), 0), 7, tapes)
	end
	Props.cabinet(f, facing(Vector3.new(134.6, 0, 16.8), NORTH), 2, 2.5, 1.6, "grey")
	Props.sign(f, facing(Vector3.new(122, 10.6, 22.94), NORTH), 9, 1, "TAPE ARCHIVE · DUBBING", "brownDark", Color3.fromRGB(196, 186, 158))
end

function Furnish.Transmitter(f)
	Props.transmitter(f, facing(Vector3.new(0, 0, -80), SOUTH))
	-- Socket console (I_SOCKET_*) on the transmitter's south side.
	part(f, "SocketConsole", Vector3.new(20, 3.3, 2), CFrame.new(0, 1.65, -70.4), "greyDark", { material = Enum.Material.Metal })
	for i, x in { -6.4, 0, 6.4 } do
		local socket = part(f, "Socket" .. i, Vector3.new(1.6, 0.4, 1.4), CFrame.new(x, 3.5, -70), "black", { collide = false })
		socket:SetAttribute("SocketIndex", i)
	end
	Props.desk(f, facing(Vector3.new(-20.5, 0, -68.6), SOUTH), 5, 2.5, 3.4, "greyDark")
	Props.vcr(f, facing(Vector3.new(-20.5, 3.4, -68.2), SOUTH), "black")
	monitor(f, facing(Vector3.new(-20.5, 4, -68.9), SOUTH), 0.9, "CAM12", "TransDeck")
	-- East gantry railing (the watcher's spot).
	part(f, "Railing", Vector3.new(0.3, 3.4, 30), CFrame.new(18.5, 1.7, -86), "greyDark", { material = Enum.Material.Metal, collide = false })
	-- Freight motor lever panel by the north wall.
	part(f, "LeverPanel", Vector3.new(2.2, 3.2, 0.6), CFrame.new(16, 3.5, -102.7), "cream", { material = Enum.Material.Metal })
	local lever = part(f, "Lever", Vector3.new(0.3, 1.6, 0.3), CFrame.new(16, 3.8, -102.2) * CFrame.Angles(math.rad(20), 0, 0), Props.rgb(MapLayout.Palette.warning), { collide = false })
	lever:SetAttribute("FreightLever", true)
	for i = 0, 3 do
		Props.pipe(f, Vector3.new(-31, 20 + i, -100 + i * 10), Vector3.new(31, 20 + i, -100 + i * 10), 0.4, i % 2 == 0 and "greyDark" or "brownDark")
	end
	Props.sign(f, facing(Vector3.new(0, 12, -103.94), SOUTH), 10, 1.2, "FREIGHT · LOADING DOCK", "greyDark", Color3.fromRGB(196, 186, 158))
end

function Furnish.StudioA(f)
	part(f, "Backdrop", Vector3.new(26, 12, 0.4), CFrame.new(-56, 6, -71), "blueDark", { material = Enum.Material.Fabric })
	Props.desk(f, facing(Vector3.new(-56, 0, -62.4), SOUTH), 10, 3, 3.4, "greyDark")
	Props.chair(f, facing(Vector3.new(-56, 0, -65), SOUTH), "black")
	Props.studioCamera(f, facing(Vector3.new(-60, 0, -50), NORTH))
	Props.studioCamera(f, facing(Vector3.new(-50, 0, -51), NORTH))
	local onAir = part(f, "OnAir", Vector3.new(3, 1, 0.3), facing(Vector3.new(-40.9, 11, -44), WEST), "black", { collide = false })
	Props.label(onAir, "ON AIR", { textColour = Color3.fromRGB(90, 40, 36), lightInfluence = 0 })
	onAir:SetAttribute("OnAirSign", true)
	Props.sign(f, facing(Vector3.new(-56, 13, -70.7), SOUTH), 12, 1.4, "THE NIGHT BULLETIN", "blueDark", Color3.fromRGB(196, 186, 158))
end

function Furnish.LoadingDock(f)
	Props.van(f, facing(Vector3.new(0, 0, -128), NORTH))
	Props.floodlight(f, facing(Vector3.new(-27, 0, -137), SOUTH))
	Props.floodlight(f, facing(Vector3.new(27, 0, -137), SOUTH))
	Props.floodlight(f, facing(Vector3.new(27, 0, -106.5), NORTH))
	Props.crate(f, CFrame.new(-26, 0, -108), Vector3.new(3, 3, 3))
	Props.crate(f, CFrame.new(-26, 0, -112), Vector3.new(2.5, 2.5, 2.5))
end

---------------------------------------------------------------------------
-- The Loop's props (tape archive): each has a Normal and an Odd variant.
---------------------------------------------------------------------------

local function variantFolder(model, name)
	local f = Instance.new("Model")
	f.Name = name
	f.Parent = model
	return f
end

local function hideVariant(container)
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("BaseTransparency", d.Transparency)
			d.Transparency = 1
			d.CanCollide = false
		elseif d:IsA("SurfaceGui") or d:IsA("Light") then
			d.Enabled = false
		end
	end
end

local function rememberVariant(container)
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("BaseTransparency", d.Transparency)
			d.CanCollide = false
		end
	end
end

local function buildLoopProps(station, caseDef)
	local root = folder(station, "LoopProps")
	if not caseDef or not caseDef.loop then
		return root
	end
	for _, prop in caseDef.loop.props do
		local model = Props.model(root, prop.id)
		model:SetAttribute("LoopProp", prop.id)
		local normal = variantFolder(model, "Normal")
		local odd = variantFolder(model, "Odd")
		local pos = V(prop.pos)
		if prop.id == "LP_CLOCK" then
			Props.wallClock(normal, facing(pos, WEST), prop.normal)
			Props.wallClock(odd, facing(pos, WEST), prop.odd)
		elseif prop.id == "LP_CHAIR" then
			Props.chair(normal, facing(Vector3.new(pos.X, 0, pos.Z), NORTH), "brownDark")
			Props.chair(odd, facing(Vector3.new(pos.X, 0, pos.Z), SOUTH), "brownDark")
		elseif prop.id == "LP_LAMP" then
			part(model, "LampBase", Vector3.new(0.6, 0.15, 0.6), CFrame.new(pos + Vector3.new(0, 0.08, 0)), "greyDark", { collide = false })
			part(model, "LampArm", Vector3.new(0.12, 1.2, 0.12), CFrame.new(pos + Vector3.new(0, 0.7, 0)), "greyDark", { collide = false })
			for _, v in { { normal, Color3.fromRGB(230, 236, 226) }, { odd, Props.rgb(MapLayout.Palette.amber) } } do
				local shade = part(v[1], "Shade", Vector3.new(0.8, 0.45, 0.8), CFrame.new(pos + Vector3.new(0, 1.45, 0)), v[2], {
					material = Enum.Material.Neon,
					collide = false,
					shadow = false,
				})
				local light = Instance.new("PointLight")
				light.Range = 7
				light.Brightness = 0.7
				light.Color = v[2]
				light.Shadows = false
				light.Parent = shade
			end
		elseif prop.id == "LP_TAPE" then
			for _, v in { { normal, prop.normal }, { odd, prop.odd } } do
				local tape = part(v[1], "Spine", Vector3.new(1.3, 0.5, 1.2), CFrame.new(pos + Vector3.new(0, 0.25, 0)), "creamDark", { collide = false })
				Props.label(tape, v[2], { face = Enum.NormalId.Back, pixelsPerStud = 60 })
			end
		elseif prop.id == "LP_POSTER" then
			Props.poster(normal, facing(pos, NORTH), 3, 4, "SAFETY\nFIRST", "cream")
			Props.poster(odd, facing(pos, NORTH) * CFrame.Angles(0, 0, math.rad(180)), 3, 4, "SAFETY\nFIRST", "cream")
		elseif prop.id == "LP_PHONE" then
			part(model, "PhoneBase", Vector3.new(0.9, 0.3, 0.7), CFrame.new(pos + Vector3.new(0, 0.15, 0)), "cream", { collide = false })
			part(normal, "Handset", Vector3.new(0.9, 0.2, 0.3), CFrame.new(pos + Vector3.new(0, 0.4, 0)), "creamDark", { collide = false })
			part(odd, "Handset", Vector3.new(0.9, 0.2, 0.3), CFrame.new(pos + Vector3.new(0.8, 0.1, 0.5)) * CFrame.Angles(0, math.rad(40), 0), "creamDark", { collide = false })
		end
		rememberVariant(normal)
		hideVariant(odd)
	end
	return root
end

---------------------------------------------------------------------------
-- Interaction anchors
---------------------------------------------------------------------------

local function anchor(parent, id, pos)
	local a = part(parent, id, Vector3.new(1, 1, 1), CFrame.new(pos), "black", { collide = false, shadow = false, transparency = 1 })
	a.CanQuery = false
	a.CanTouch = false
	a:SetAttribute("InteractId", id)
	return a
end

local function buildAnchors(station, caseDef)
	local anchors = folder(station, "Anchors")
	if not caseDef then
		return anchors
	end
	for id, def in caseDef.interactables do
		local pos
		if def.kind == "Deck" then
			pos = V(caseDef.decks[def.deck].pos)
		elseif def.kind == "Relay" then
			pos = V(MapLayout.Relays[def.relay].pos, 4)
		else
			pos = V(def.pos)
		end
		anchor(anchors, id, pos)
	end
	if caseDef.loop then
		for _, prop in caseDef.loop.props do
			anchor(anchors, prop.id, V(prop.pos) + Vector3.new(0, 0.6, 0))
		end
	end
	return anchors
end

---------------------------------------------------------------------------
-- Field office (HQ)
---------------------------------------------------------------------------

MapBuilder.HQTerminals = {
	HQ_CASES = { label = "CASE BOARD", action = "Case Select", pos = P("HQ", 0.5, 0.06, 4) },
	HQ_ARCHIVE = { label = "EVIDENCE ARCHIVE", action = "Evidence Archive", pos = P("HQ", 0.1, 0.35, 3.6) },
	HQ_LOCKER = { label = "EQUIPMENT LOCKER", action = "Equipment", pos = P("HQ", 0.9, 0.35, 3.6) },
	HQ_STORE = { label = "DIVISION STORE", action = "Store", pos = P("HQ", 0.9, 0.7, 3.6) },
	HQ_SETTINGS = { label = "SETTINGS", action = "Settings", pos = P("HQ", 0.1, 0.7, 3.6) },
}

MapBuilder.HQDesks = {
	{ pos = P("HQ", 0.3, 0.55), look = NORTH },
	{ pos = P("HQ", 0.7, 0.55), look = NORTH },
	{ pos = P("HQ", 0.3, 0.8), look = NORTH },
	{ pos = P("HQ", 0.7, 0.8), look = NORTH },
}

local function buildHQ(parent)
	local hq = Instance.new("Model")
	hq.Name = "FieldOffice"
	hq.Parent = parent
	local room = MapLayout.Rooms.HQ
	local roomFolder = folder(hq, "Room")
	buildShell(roomFolder, "HQ", room)
	buildLights(roomFolder, "HQ", room)
	local f = folder(hq, "Props")

	local board = part(f, "CaseBoard", Vector3.new(20, 7, 0.4), facing(Vector3.new(0, 6, 241.2), SOUTH), "black", { collide = false })
	Props.label(board, "NATIONAL BROADCAST RECOVERY DIVISION\nCASE BOARD", { textColour = Color3.fromRGB(150, 210, 160), lightInfluence = 0, pixelsPerStud = 20 })
	for id, def in MapBuilder.HQTerminals do
		if id ~= "HQ_CASES" then
			local base = V(def.pos, 0)
			part(f, id .. "_Stand", Vector3.new(3, 3, 2.4), CFrame.new(base + Vector3.new(0, 1.5, 0)), "greyDark", { material = Enum.Material.Metal })
			local dir = base.X < 0 and EAST or WEST
			local _, screen = Props.beigeComputer(f, facing(base + Vector3.new(0, 3, 0), dir))
			Props.label(screen, def.label, { textColour = Color3.fromRGB(150, 210, 160), lightInfluence = 0, pixelsPerStud = 40 })
		end
	end
	local desks = folder(hq, "Desks")
	for i, desk in MapBuilder.HQDesks do
		local m = Props.model(desks, "Desk" .. i)
		m:SetAttribute("DeskIndex", i)
		local base = V(desk.pos, 0)
		Props.desk(m, facing(base, desk.look), 6, 3, 3.2, "brown")
		Props.chair(m, facing(base + Vector3.new(0, 0, 2.6), NORTH), "blueDark")
		local plate = part(m, "Nameplate", Vector3.new(2.4, 0.5, 0.1), facing(base + Vector3.new(0, 3.5, 1.2), SOUTH), "creamDark", { collide = false, shadow = false })
		local _, text = Props.label(plate, "VACANT", { pixelsPerStud = 50 })
		text.Name = "Name"
		local decor = Props.model(m, "Decor")
		local items = {
			decor_poster = function(d)
				Props.poster(d, facing(base + Vector3.new(-1.5, 5.5, -1.6), SOUTH), 2, 2.6, "STATION 04\nCOLLECTOR'S POSTER")
			end,
			decor_lamp = function(d)
				part(d, "Lamp", Vector3.new(0.6, 1.4, 0.6), CFrame.new(base + Vector3.new(2.2, 3.9, -0.6)), "greenDark", { collide = false })
			end,
			decor_shelf = function(d)
				local s = Props.shelf(d, facing(base + Vector3.new(0, 3.2, -1.2), SOUTH), 3, 1.4, 0.6, { 0.1, 0.8 })
				Props.tapeRow(s, CFrame.new(base + Vector3.new(0, 3.3, -1.2)), 2.4, { "brown", "blueDark", "creamDark" })
			end,
			decor_plant = function(d)
				Props.plant(d, CFrame.new(base + Vector3.new(3.8, 0, 0)))
			end,
			decor_radio = function(d)
				part(d, "Radio", Vector3.new(1.4, 0.8, 0.6), CFrame.new(base + Vector3.new(-2, 3.6, -0.5)), "brownDark", { collide = false })
			end,
			decor_tv = function(d)
				Props.crt(d, facing(base + Vector3.new(1.2, 3.2, -0.6), SOUTH), 0.6, "PortableTV")
			end,
		}
		for decorId, build in items do
			local holder = Props.model(decor, decorId)
			build(holder)
			hideVariant(holder)
		end
	end
	Props.plant(f, CFrame.new(-27, 0, 281))
	Props.plant(f, CFrame.new(27, 0, 281))
	Props.bench(f, facing(Vector3.new(0, 0, 279), NORTH), 8)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HQSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = CFrame.new(V(MapLayout.HQSpawn, 0.1))
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = hq

	local anchors = folder(hq, "Anchors")
	for id, def in MapBuilder.HQTerminals do
		anchor(anchors, id, V(def.pos))
	end
	for _, door in MapLayout.Doors do
		if door.rooms[1] == "HQ" then
			buildDoor(folder(hq, "Doors"), door, "blueDark")
		end
	end
	return hq
end

---------------------------------------------------------------------------
-- Exterior
---------------------------------------------------------------------------

local function buildExterior(station)
	local ext = folder(station, "Exterior")
	part(ext, "Ground", Vector3.new(800, 1, 800), CFrame.new(0, -1.5, 60), Color3.fromRGB(36, 40, 36), { material = Enum.Material.Ground })
	-- Car park outside the main doors, visible through the glass.
	part(ext, "CarPark", Vector3.new(60, 0.2, 40), CFrame.new(0, -0.9, 94), Color3.fromRGB(48, 50, 50), { material = Enum.Material.Asphalt })
	for _, x in { -18, 18 } do
		local pole = part(ext, "LampPost", Vector3.new(0.5, 12, 0.5), CFrame.new(x, 6, 98), "greyDark", { material = Enum.Material.Metal })
		local light = Instance.new("PointLight")
		light.Range = 20
		light.Brightness = 0.6
		light.Color = Color3.fromRGB(220, 170, 110)
		light.Shadows = false
		light.Parent = pole
	end
	-- Facade around the main doors, seen from the car park (gap for the doors).
	local doorHalf = 4.6
	for _, side in { -1, 1 } do
		local width = 28 - doorHalf
		part(ext, "Facade", Vector3.new(width, 18, 1), CFrame.new(side * (doorHalf + width / 2), 9, 73), "creamDark", { material = Enum.Material.Concrete })
	end
	part(ext, "FacadeLintel", Vector3.new(doorHalf * 2, 18 - DOOR_H, 1), CFrame.new(0, DOOR_H + (18 - DOOR_H) / 2, 73), "creamDark", { material = Enum.Material.Concrete })
	local facadeSign = part(ext, "FacadeSign", Vector3.new(24, 2.4, 0.3), facing(Vector3.new(0, 15.5, 73.7), SOUTH), "black", { collide = false })
	Props.label(facadeSign, "STATION 04", { textColour = Color3.fromRGB(150, 140, 120), lightInfluence = 1 })
	return ext
end

---------------------------------------------------------------------------
-- Entry point
---------------------------------------------------------------------------

function MapBuilder.build(parent, caseDef)
	local station = Instance.new("Model")
	station.Name = "Station04"
	local rooms = folder(station, "Rooms")
	for _, roomId in MapLayout.StationRooms do
		local room = MapLayout.Rooms[roomId]
		local roomFolder = folder(rooms, roomId)
		roomFolder:SetAttribute("RoomId", roomId)
		buildShell(roomFolder, roomId, room)
		buildLights(roomFolder, roomId, room)
		local propsFolder = folder(roomFolder, "Props")
		if Furnish[roomId] then
			Furnish[roomId](propsFolder)
		end
	end
	-- Shared corridor/hall segments that are one space but two rectangles.
	local doors = folder(station, "Doors")
	for _, door in MapLayout.Doors do
		if door.rooms[1] ~= "HQ" then
			local trim = MapLayout.Rooms[door.rooms[1]].trim
			buildDoor(doors, door, trim)
		end
	end
	buildWindows(folder(station, "Windows"))
	local cams = folder(station, "Cameras")
	for _, camId in MapLayout.CameraOrder do
		local cam = MapLayout.Cameras[camId]
		Props.cctvCamera(cams, V(cam.pos), V(cam.look), camId)
	end
	buildSigns(station)
	buildLoopProps(station, caseDef)
	buildAnchors(station, caseDef)
	local spawns = folder(station, "Spawns")
	if caseDef then
		for i, pos in caseDef.spawns do
			local s = part(spawns, "Spawn" .. i, Vector3.new(2, 0.2, 2), CFrame.new(V(pos, 0.1)), "black", { collide = false, transparency = 1, shadow = false })
			s.CanQuery = false
		end
	end
	buildExterior(station)
	station.Parent = parent

	local hq = buildHQ(parent)
	return station, hq
end

-- Exposed for the server so door motion matches the built geometry.
MapBuilder.doorFrame = doorFrame
MapBuilder.doorTop = doorTop

return MapBuilder
