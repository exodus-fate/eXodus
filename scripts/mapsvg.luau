--[[
	Writes docs/station04-map.svg: a top-down plan of Broadcast Station 04 drawn
	from the same MapLayout and Case 01 data the game uses.

		lune run scripts/mapsvg.luau
]]

local fs = require("@lune/fs")

local Harness = require("../tests/lib/Harness")

local h = Harness.new()
local Shared = h.mount("Shared", "src/shared")
local MapLayout = h.require(Shared.Config.MapLayout)
local Case01 = h.require(Shared.Config.Cases.Case01)

local SCALE = 4
local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
for _, id in MapLayout.StationRooms do
	local r = MapLayout.Rooms[id]
	minX, maxX = math.min(minX, r.x0), math.max(maxX, r.x1)
	minZ, maxZ = math.min(minZ, r.z0), math.max(maxZ, r.z1)
end
local pad = 20
local width = (maxX - minX + pad * 2) * SCALE
local height = (maxZ - minZ + pad * 2) * SCALE + 70

local function X(x)
	return (x - minX + pad) * SCALE
end
local function Z(z)
	return (z - minZ + pad) * SCALE + 50
end

local out = {}
local function add(s)
	table.insert(out, s)
end

add(string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" font-family="monospace">', width, height, width, height))
add(string.format('<rect width="%d" height="%d" fill="#0e1210"/>', width, height))
add('<text x="20" y="32" fill="#c4ba9e" font-size="22">BROADCAST STATION 04 · FLOOR PLAN (north is up)</text>')

local fills = {
	Lobby = "#4a4638", ControlRoom = "#34423a", Archive = "#43382c", EditingSuite = "#323c46",
	Generator = "#3c3a37", Transmitter = "#2c2c2b", StudioA = "#262a2a", LoadingDock = "#2a2c2c",
}
for _, id in MapLayout.StationRooms do
	local r = MapLayout.Rooms[id]
	add(string.format('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" stroke="#5a7a62" stroke-width="2"/>',
		X(r.x0), Z(r.z0), (r.x1 - r.x0) * SCALE, (r.z1 - r.z0) * SCALE, fills[id] or "#2f3631"))
end
for _, door in MapLayout.Doors do
	if door.rooms[1] ~= "HQ" then
		local colour = door.kind == "opening" and "#8aa08e" or (Case01.doorLocks[door.id] and "#e2a44c" or "#d6e0d2")
		if door.plane == "z" then
			add(string.format('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="6"/>',
				X(door.center - door.width / 2), Z(door.at), X(door.center + door.width / 2), Z(door.at), colour))
		else
			add(string.format('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="6"/>',
				X(door.at), Z(door.center - door.width / 2), X(door.at), Z(door.center + door.width / 2), colour))
		end
	end
end
for _, win in MapLayout.Windows do
	add(string.format('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#7fb0c8" stroke-width="4" stroke-dasharray="4 3"/>',
		X(win.center - win.width / 2), Z(win.at), X(win.center + win.width / 2), Z(win.at)))
end
local labelled = {}
for _, id in MapLayout.StationRooms do
	local r = MapLayout.Rooms[id]
	if not labelled[r.label] then
		labelled[r.label] = true
		local big = (r.x1 - r.x0) > 20 and (r.z1 - r.z0) > 20
		add(string.format('<text x="%.1f" y="%.1f" fill="#c4ba9e" font-size="%d" text-anchor="middle">%s</text>',
			X((r.x0 + r.x1) / 2), Z((r.z0 + r.z1) / 2), big and 14 or 10, r.label))
	end
end
for _, camId in MapLayout.CameraOrder do
	local cam = MapLayout.Cameras[camId]
	add(string.format('<circle cx="%.1f" cy="%.1f" r="4" fill="#96d2a0"/><text x="%.1f" y="%.1f" fill="#96d2a0" font-size="10">%s</text>',
		X(cam.pos.x), Z(cam.pos.z), X(cam.pos.x) + 6, Z(cam.pos.z) - 4, camId))
end
local function marker(pos, colour, text)
	add(string.format('<rect x="%.1f" y="%.1f" width="8" height="8" fill="%s"/><text x="%.1f" y="%.1f" fill="%s" font-size="10">%s</text>',
		X(pos.x) - 4, Z(pos.z) - 4, colour, X(pos.x) + 7, Z(pos.z) + 4, colour, text))
end
for id, deck in Case01.decks do
	marker(deck.pos, "#e2a44c", deck.label)
end
for _, id in { "I_GENERATOR", "I_CAGE", "I_RACK", "I_LEVER", "I_VAN" } do
	local def = Case01.interactables[id]
	marker(def.pos, "#d6e0d2", def.object)
end
local legendY = height - 16
add(string.format('<text x="20" y="%d" fill="#8aa08e" font-size="12">white = door · amber = locked until a condition · dashed blue = glass · green dots = CCTV · amber squares = tape decks</text>', legendY))
add("</svg>")

fs.writeDir("docs")
fs.writeFile("docs/station04-map.svg", table.concat(out, "\n"))
print("Wrote docs/station04-map.svg")
