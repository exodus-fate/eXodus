--[[
	WorldService — the physical station.

	Keeps a pristine template of Station04 (built by MapBuilder, or whatever was
	saved in the place file - so Studio edits to the map are respected) and
	swaps in a fresh copy for every case, which makes mission cleanup trivial.
	Applies world state decided by MissionCore: room lights, door locks and
	motion, relays, generator lamps and item props.
]]

local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local MapBuilder = require(Shared.World.MapBuilder)
local MapLayout = require(Shared.Config.MapLayout)
local Props = require(Shared.World.Props)
local CaseRegistry = require(Shared.Config.CaseRegistry)

local WorldService = {}

WorldService.station = nil
WorldService.hq = nil
WorldService.template = nil
WorldService.doors = {}
WorldService.rooms = {}
WorldService.anchors = {}
WorldService.items = {}
WorldService.glass = {}
WorldService.onReset = {}
WorldService.onDoorChanged = {}

local FLUORESCENT_ON = Props.rgb(MapLayout.Palette.fluorescent)
local FLUORESCENT_OFF = Color3.fromRGB(70, 74, 70)
local AMBER = Props.rgb(MapLayout.Palette.amber)
local LAMP_OFF = Color3.fromRGB(46, 46, 42)
local LAMP_GOOD = Color3.fromRGB(120, 200, 120)

local function setLightPart(partObj, on, colourOn, colourOff)
	partObj.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
	partObj.Color = on and colourOn or colourOff
	local light = partObj:FindFirstChildWhichIsA("Light")
	if light then
		light.Enabled = on
	end
end

---------------------------------------------------------------------------
-- Indexing
---------------------------------------------------------------------------

local function indexStation(station)
	WorldService.doors = {}
	WorldService.rooms = {}
	WorldService.anchors = {}
	WorldService.items = {}
	WorldService.glass = {}

	for _, roomFolder in station.Rooms:GetChildren() do
		local entry = { fluorescent = {}, emergency = {}, mode = nil, folder = roomFolder }
		for _, d in roomFolder:GetDescendants() do
			if d:IsA("BasePart") then
				local kind = d:GetAttribute("LightKind")
				if kind == "Fluorescent" then
					table.insert(entry.fluorescent, d)
				elseif kind == "Emergency" then
					table.insert(entry.emergency, d)
				end
			end
		end
		WorldService.rooms[roomFolder.Name] = entry
	end

	for _, model in station.Doors:GetChildren() do
		local id = model:GetAttribute("DoorId")
		if id then
			local entry = {
				id = id,
				model = model,
				kind = model:GetAttribute("Kind"),
				refuge = model:GetAttribute("Refuge") == true,
				swing = model:GetAttribute("SwingSign") or 1,
				width = model:GetAttribute("PanelWidth") or 4,
				open = false,
				locked = false,
				panels = {},
				layout = MapLayout.doorById(id),
			}
			for _, child in model:GetChildren() do
				if child:IsA("BasePart") and child.Anchored and (child.Name == "Panel" or child.Name == "PanelL" or child.Name == "PanelR") then
					table.insert(entry.panels, { part = child, closed = child.CFrame })
				end
			end
			WorldService.doors[id] = entry
		end
	end

	for _, anchorPart in station.Anchors:GetChildren() do
		WorldService.anchors[anchorPart.Name] = anchorPart
	end

	for _, d in station:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("SeeThrough") then
			table.insert(WorldService.glass, d)
		end
	end

	local items = station:FindFirstChild("Items")
	if not items then
		items = Instance.new("Folder")
		items.Name = "Items"
		items.Parent = station
	end
	WorldService.itemsFolder = items
end

function WorldService.init()
	local station = Workspace:FindFirstChild("Station04")
	local hq = Workspace:FindFirstChild("FieldOffice")
	if not station or not hq then
		if station then
			station:Destroy()
		end
		if hq then
			hq:Destroy()
		end
		station, hq = MapBuilder.build(Workspace, CaseRegistry.get("case01"))
	end
	WorldService.hq = hq
	WorldService.template = station:Clone()
	WorldService.template.Name = "Station04Template"
	WorldService.template.Parent = ServerStorage
	WorldService.station = station
	indexStation(station)
end

-- Replaces the live station with a clean copy of the template.
function WorldService.reset()
	if WorldService.station then
		WorldService.station:Destroy()
	end
	local fresh = WorldService.template:Clone()
	fresh.Name = "Station04"
	fresh.Parent = Workspace
	WorldService.station = fresh
	indexStation(fresh)
	for _, callback in WorldService.onReset do
		callback(fresh)
	end
	return fresh
end

---------------------------------------------------------------------------
-- Lights
---------------------------------------------------------------------------

function WorldService.setRoomLights(roomId, mode)
	local room = WorldService.rooms[roomId]
	if not room then
		return
	end
	room.mode = mode
	room.folder:SetAttribute("LightMode", mode)
	for _, p in room.fluorescent do
		setLightPart(p, mode == "on", FLUORESCENT_ON, FLUORESCENT_OFF)
	end
	for _, p in room.emergency do
		setLightPart(p, mode == "emergency", AMBER, LAMP_OFF)
	end
end

-- Between cases the station sits dark apart from its battery emergency lights.
function WorldService.setIdleLights()
	for roomId in WorldService.rooms do
		local room = MapLayout.Rooms[roomId]
		WorldService.setRoomLights(roomId, room and room.emergency and "emergency" or "off")
	end
	WorldService.setGeneratorStage(0)
end

function WorldService.roomLightMode(roomId)
	local room = WorldService.rooms[roomId]
	return room and room.mode or "off"
end

---------------------------------------------------------------------------
-- Doors
---------------------------------------------------------------------------

local function doorTarget(entry, panel, open)
	if not open then
		return panel.closed
	end
	if entry.kind == "freight" then
		return panel.closed + Vector3.new(0, 10.5, 0)
	end
	local width = entry.width
	if entry.kind == "double" then
		width = panel.part.Size.X
	end
	local hinge = (panel.closed * CFrame.new(-width / 2, 0, 0)).Position
	local angle = math.rad(90) * entry.swing
	return CFrame.new(hinge) * CFrame.Angles(0, angle, 0) * CFrame.new(-hinge) * panel.closed
end

local function moveDoor(entry, open)
	entry.open = open
	entry.model:SetAttribute("Open", open)
	local duration = entry.kind == "freight" and 3 or 0.45
	for _, panel in entry.panels do
		local tween = TweenService:Create(panel.part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = doorTarget(entry, panel, open),
		})
		tween:Play()
	end
	for _, callback in WorldService.onDoorChanged do
		callback(entry.id, entry)
	end
end

local function updateModifiers(entry)
	for _, d in entry.model:GetDescendants() do
		if d:IsA("PathfindingModifier") then
			local passable = not entry.locked and (entry.kind == "door" or entry.open)
			d.Label = passable and "Door" or "LockedDoor"
			d.PassThrough = passable
		end
	end
end

function WorldService.door(doorId)
	return WorldService.doors[doorId]
end

function WorldService.setDoorLocked(doorId, locked)
	local entry = WorldService.doors[doorId]
	if not entry then
		return
	end
	entry.locked = locked
	entry.model:SetAttribute("Locked", locked)
	if locked and entry.open then
		moveDoor(entry, false)
	end
	updateModifiers(entry)
end

function WorldService.openDoor(doorId)
	local entry = WorldService.doors[doorId]
	if not entry or entry.locked or entry.open or #entry.panels == 0 then
		return false
	end
	moveDoor(entry, true)
	updateModifiers(entry)
	return true
end

function WorldService.closeDoor(doorId)
	local entry = WorldService.doors[doorId]
	if not entry or not entry.open then
		return false
	end
	moveDoor(entry, false)
	updateModifiers(entry)
	return true
end

function WorldService.toggleDoor(doorId)
	local entry = WorldService.doors[doorId]
	if not entry then
		return false
	end
	if entry.open then
		return WorldService.closeDoor(doorId)
	end
	return WorldService.openDoor(doorId)
end

-- Closed, unlocked hinged doors near a point (for the Presenter).
function WorldService.closedDoorsNear(position, radius)
	local list = {}
	for id, entry in WorldService.doors do
		if entry.kind == "door" and not entry.open and not entry.locked and #entry.panels > 0 then
			local p = entry.panels[1].closed.Position
			local flat = Vector3.new(p.X - position.X, 0, p.Z - position.Z)
			if flat.Magnitude <= radius then
				table.insert(list, id)
			end
		end
	end
	return list
end

-- A refuge room counts as sealed while every hinged door into it is shut.
function WorldService.refugeSealed(roomId)
	local any = false
	for _, entry in WorldService.doors do
		if entry.refuge and entry.layout and table.find(entry.layout.rooms, roomId) then
			any = true
			if entry.open then
				return false
			end
		end
	end
	return any
end

---------------------------------------------------------------------------
-- Equipment state
---------------------------------------------------------------------------

local function eachTagged(attribute, fn)
	if not WorldService.station then
		return
	end
	for _, d in WorldService.station:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute(attribute) ~= nil then
			fn(d, d:GetAttribute(attribute))
		end
	end
end

function WorldService.setGeneratorStage(stage)
	eachTagged("GeneratorStage", function(lamp, lampStage)
		local colour = lampStage == 0 and Color3.fromRGB(150, 70, 50) or (lampStage == 1 and AMBER or LAMP_GOOD)
		setLightPart(lamp, lampStage == stage, colour, LAMP_OFF)
	end)
end

function WorldService.setRelay(relayId, on)
	local relay = MapLayout.Relays[relayId]
	if not relay then
		return
	end
	local room = WorldService.rooms[relay.room]
	if not room then
		return
	end
	for _, d in room.folder:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("RelayLamp") then
			setLightPart(d, true, on and LAMP_GOOD or AMBER, LAMP_OFF)
		end
	end
end

function WorldService.setTransmitterArmed(armed)
	eachTagged("TransmitterLamp", function(lamp)
		-- The chamber's single red status lamp: red is reserved for this kind of beat.
		setLightPart(lamp, armed, Props.rgb(MapLayout.Palette.warning), Color3.fromRGB(70, 30, 26))
	end)
end

function WorldService.setOnAir(on)
	eachTagged("OnAirSign", function(sign)
		local gui = sign:FindFirstChildWhichIsA("SurfaceGui")
		local label = gui and gui:FindFirstChildWhichIsA("TextLabel")
		if label then
			label.TextColor3 = on and Color3.fromRGB(230, 70, 60) or Color3.fromRGB(90, 40, 36)
		end
		sign.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
		sign.Color = on and Color3.fromRGB(60, 16, 14) or Color3.fromRGB(22, 24, 22)
	end)
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

function WorldService.spawnItem(caseDef, itemId, pos, interactive)
	local item = caseDef.items[itemId]
	local cf = CFrame.new(pos.x, pos.y, pos.z)
	local model
	if item.kind == "Tape" then
		local tape = caseDef.tapes[item.tape]
		local c = tape.colour
		model = Props.vhsTape(WorldService.itemsFolder, cf, item.label, Color3.fromRGB(c[1], c[2], c[3]))
	elseif item.kind == "Evidence" then
		local colour = item.bonus and Color3.fromRGB(168, 70, 60) or Color3.fromRGB(150, 141, 117)
		model = Props.vhsTape(WorldService.itemsFolder, cf, item.label, colour)
	else
		model = Props.component(WorldService.itemsFolder, cf, itemId)
	end
	model.Name = itemId
	model:SetAttribute("ItemId", itemId)
	local anchorPart = nil
	if interactive then
		anchorPart = Props.part(model, "ITEM_" .. itemId, Vector3.new(1.2, 1.2, 1.2), cf * CFrame.new(0, 0.6, 0), "black", {
			collide = false,
			shadow = false,
			transparency = 1,
		})
		anchorPart.CanQuery = false
		anchorPart:SetAttribute("InteractId", "ITEM_" .. itemId)
		WorldService.anchors["ITEM_" .. itemId] = anchorPart
	end
	-- A faint glow so objective items read in the dark (never pixel-hunting).
	local glow = Instance.new("PointLight")
	glow.Range = 4
	glow.Brightness = 0.35
	glow.Color = Color3.fromRGB(200, 220, 200)
	glow.Shadows = false
	glow.Parent = model.PrimaryPart
	WorldService.items[itemId] = model
	return model, anchorPart
end

function WorldService.removeItem(itemId)
	local model = WorldService.items[itemId]
	if model then
		model:Destroy()
		WorldService.items[itemId] = nil
	end
	WorldService.anchors["ITEM_" .. itemId] = nil
end

function WorldService.setItemVisible(itemId, visible)
	local model = WorldService.items[itemId]
	if not model then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not string.match(d.Name, "^ITEM_") then
			if d:GetAttribute("BaseTransparency") == nil then
				d:SetAttribute("BaseTransparency", d.Transparency)
			end
			d.Transparency = visible and d:GetAttribute("BaseTransparency") or 1
		elseif d:IsA("SurfaceGui") or d:IsA("Light") then
			d.Enabled = visible
		end
	end
end

function WorldService.spawnPoints()
	local list = {}
	if WorldService.station and WorldService.station:FindFirstChild("Spawns") then
		for _, s in WorldService.station.Spawns:GetChildren() do
			table.insert(list, s.CFrame)
		end
	end
	table.sort(list, function(a, b)
		return a.Position.X < b.Position.X
	end)
	return list
end

function WorldService.hqSpawn()
	local spawn = WorldService.hq and WorldService.hq:FindFirstChild("HQSpawn")
	if spawn then
		return spawn.CFrame + Vector3.new(0, 3, 0)
	end
	local p = MapLayout.HQSpawn
	return CFrame.new(p.x, 3, p.z)
end

return WorldService
