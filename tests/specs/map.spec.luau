-- Builds Broadcast Station 04 headlessly. Lune validates every class, property and
-- enum name against Roblox's reflection database, and the geometry checks below
-- make sure scripted routes and objectives are physically reachable.

local roblox = require("@lune/roblox")

local game = roblox.Instance.new("DataModel")
local h = Harness.new({ game = game })
local Shared = h.mount("Shared", "src/shared")
local req = h.require

local Case01 = req(Shared.Config.Cases.Case01)
local MapLayout = req(Shared.Config.MapLayout)
local MapBuilder = req(Shared.World.MapBuilder)
local MissionCore = req(Shared.Core.MissionCore)

local workspace = game:GetService("Workspace")
local station, hq

local function build()
	if not station then
		station, hq = MapBuilder.build(workspace, Case01)
	end
	return station, hq
end

local function solidParts(root, filter)
	local list = {}
	for _, d in root:GetDescendants() do
		-- Invisible collision boxes (bench frames, tripods) still block.
		if d:IsA("BasePart") and d.CanCollide and (not filter or filter(d)) then
			table.insert(list, d)
		end
	end
	return list
end

local function blockedBy(parts, point, radius, y0, y1)
	for _, p in parts do
		local cf, size = p.CFrame, p.Size
		local top = cf.Position.Y + size.Y / 2
		local bottom = cf.Position.Y - size.Y / 2
		-- Rough vertical test using the axis-aligned extent.
		if bottom < y1 and top > y0 then
			local l = cf:PointToObjectSpace(roblox.Vector3.new(point.x, cf.Position.Y, point.z))
			if math.abs(l.X) < size.X / 2 + radius and math.abs(l.Z) < size.Z / 2 + radius then
				return p
			end
		end
	end
	return nil
end

test("the station builds without engine errors", function()
	build()
	expect(station.Name).toBe("Station04")
	expect(#station.Rooms:GetChildren()).toBe(#MapLayout.StationRooms)
	expect(hq.Name).toBe("FieldOffice")
	local count = 0
	for _, d in station:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	print(string.format("      station parts: %d", count))
	expect(count).toBeAtMost(4000)
end)

test("every door in the layout is built, with a panel unless it is an opening", function()
	build()
	for _, door in MapLayout.Doors do
		local parent = door.rooms[1] == "HQ" and hq.Doors or station.Doors
		local model = parent:FindFirstChild(door.id)
		if not model then
			error("missing door " .. door.id)
		end
		if door.kind ~= "opening" and not model.PrimaryPart then
			error(door.id .. " has no primary panel")
		end
	end
end)

test("every interactable has a prompt anchor", function()
	build()
	for id in Case01.interactables do
		if not station.Anchors:FindFirstChild(id) then
			error("missing anchor " .. id)
		end
	end
	for _, prop in Case01.loop.props do
		expect(station.Anchors:FindFirstChild(prop.id) ~= nil).toBeTruthy()
		expect(station.LoopProps:FindFirstChild(prop.id) ~= nil).toBeTruthy()
	end
	for id in MapBuilder.HQTerminals do
		expect(hq.Anchors:FindFirstChild(id) ~= nil).toBeTruthy()
	end
end)

test("CCTV monitors reference real cameras", function()
	build()
	local monitors = 0
	for _, d in station:GetDescendants() do
		if d:HasTag("CCTVMonitor") then
			monitors += 1
			expect(MapLayout.Cameras[d:GetAttribute("CameraId")] ~= nil).toBeTruthy()
		end
	end
	expect(monitors).toBeAtLeast(10)
end)

test("Presenter routes never pass through walls or furniture", function()
	build()
	local solids = solidParts(station.Rooms)
	local problems = {}
	for _, ev in Case01.events do
		for state, def in ev.states do
			local cmd = def.presenter
			local points = {}
			if cmd and cmd.path then
				for i = 1, #cmd.path - 1 do
					local a, b = cmd.path[i].pos, cmd.path[i + 1].pos
					local dist = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
					local steps = math.max(1, math.ceil(dist / 0.5))
					for s = 0, steps do
						local t = s / steps
						table.insert(points, { x = a.x + (b.x - a.x) * t, z = a.z + (b.z - a.z) * t })
					end
				end
			elseif cmd and cmd.pos then
				table.insert(points, cmd.pos)
			end
			for _, pt in points do
				local hit = blockedBy(solids, pt, 1.0, 0.3, 8.4)
				if hit then
					table.insert(problems, string.format("%s.%s at (%.1f, %.1f) hits %s", ev.id, state, pt.x, pt.z, hit:GetFullName()))
					break
				end
			end
		end
	end
	if #problems > 0 then
		error(table.concat(problems, "\n      "))
	end
end)

test("spawns and checkpoints are standing room", function()
	build()
	local solids = solidParts(station.Rooms)
	for i, pos in Case01.spawns do
		local hit = blockedBy(solids, pos, 1.2, 0.3, 5)
		if hit then
			error("spawn " .. i .. " blocked by " .. hit:GetFullName())
		end
	end
	for _, cp in Case01.checkpoints do
		local hit = blockedBy(solids, cp.pos, 1.2, 0.3, 5)
		if hit then
			error("checkpoint " .. cp.id .. " blocked by " .. hit:GetFullName())
		end
	end
end)

test("items rest on a surface and are not buried inside props", function()
	build()
	local solids = solidParts(station.Rooms)
	local problems = {}
	for itemId, item in Case01.items do
		for i, pos in item.spawns or {} do
			-- Something must be directly under the item (or it sits on the floor).
			local supported = pos.y < 0.2
			for _, p in solids do
				local cf, size = p.CFrame, p.Size
				local l = cf:PointToObjectSpace(roblox.Vector3.new(pos.x, pos.y, pos.z))
				local insideXZ = math.abs(l.X) <= size.X / 2 and math.abs(l.Z) <= size.Z / 2
				local top = cf.Position.Y + size.Y / 2
				if insideXZ and math.abs(top - pos.y) < 0.35 then
					supported = true
				end
				if insideXZ and l.Y > -size.Y / 2 + 0.05 and l.Y < size.Y / 2 - 0.4 then
					table.insert(problems, string.format("%s spawn %d is inside %s", itemId, i, p:GetFullName()))
				end
			end
			if not supported then
				table.insert(problems, string.format("%s spawn %d floats at y=%.2f", itemId, i, pos.y))
			end
		end
	end
	if #problems > 0 then
		error(table.concat(problems, "\n      "))
	end
end)

test("interactables are within reach of open floor", function()
	build()
	local solids = solidParts(station.Rooms)
	local m = MissionCore.new(Case01, { seed = 1, now = 0, participants = {} })
	for id, def in m:getInteractables() do
		local pos = def.pos
		if not pos and def.kind == "Relay" then
			pos = MapLayout.Relays[def.relay].pos
		end
		if pos then
			-- Find a free standing spot within 6 studs.
			local found = false
			for r = 1, 6 do
				for a = 0, 15 do
					local ang = a / 16 * math.pi * 2
					local probe = { x = pos.x + math.cos(ang) * r, z = pos.z + math.sin(ang) * r }
					if MapLayout.roomAt(probe.x, probe.z) and not blockedBy(solids, probe, 1, 0.3, 5) then
						found = true
						break
					end
				end
				if found then
					break
				end
			end
			if not found then
				error(id .. " cannot be reached")
			end
		end
	end
end)

test("the Presenter rig and footage figures build", function()
	local Figures = req(Shared.World.Figures)
	local live = Figures.presenter(workspace)
	expect(live:FindFirstChild("Humanoid") ~= nil).toBeTruthy()
	expect(live.Humanoid.HipHeight).toBeNear(Figures.LEG_LENGTH, 1e-4)
	expect(live.PrimaryPart.Name).toBe("HumanoidRootPart")
	expect(live:HasTag("Presenter")).toBe(true)
	local parts = 0
	for _, d in live:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			if d ~= live.PrimaryPart then
				expect(d.Anchored).toBe(false)
			end
		end
	end
	expect(parts).toBeAtMost(25)
	local ghost = Figures.presenter(workspace, { ghost = true })
	expect(ghost:FindFirstChild("Humanoid")).toBe(nil)
	expect(Figures.rootHeight(ghost)).toBeNear(Figures.LEG_LENGTH + 1, 1e-4)
	local person = Figures.investigator(workspace)
	expect(Figures.rootHeight(person)).toBe(3)
end)

test("every surface is a real Roblox material and photo textures plug in", function()
	local Surfaces = req(Shared.Config.Surfaces)
	for name, def in Surfaces.List do
		local ok = pcall(function()
			return roblox.Enum.Material[def.material]
		end)
		if not ok then
			error(name .. " uses unknown material " .. def.material)
		end
		if def.variant and not Surfaces.Variants[def.variant] then
			error(name .. " names missing variant " .. def.variant)
		end
	end
	-- Nothing configured: no variants, built-in materials only.
	local ms = roblox.Instance.new("MaterialService")
	expect(Surfaces.install(ms)).toBe(0)
	expect(Surfaces.variantFor("lino") == nil).toBeTruthy()
	-- Paste an id and the variant is installed and used.
	Surfaces.Variants.DeadAir_Linoleum.colorMap = "rbxassetid://1"
	expect(Surfaces.install(ms)).toBe(1)
	expect(ms.DeadAir_Linoleum.BaseMaterial).toBe(roblox.Enum.Material.CeramicTiles)
	expect(Surfaces.variantFor("lino")).toBe("DeadAir_Linoleum")
	local Props = req(Shared.World.Props)
	local p = Props.part(workspace, "T", roblox.Vector3.new(1, 1, 1), roblox.CFrame.new(), "grey", { surface = "lino" })
	expect(p.MaterialVariant).toBe("DeadAir_Linoleum")
	Surfaces.Variants.DeadAir_Linoleum.colorMap = ""
	p:Destroy()
end)

test("the station and field office are built from textured surfaces", function()
	build()
	local counts, smooth, total = {}, 0, 0
	for _, root in { station, hq } do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				total += 1
				counts[d.Material.Name] = (counts[d.Material.Name] or 0) + 1
				if d.Material == roblox.Enum.Material.SmoothPlastic then
					smooth += 1
				end
			end
		end
	end
	-- Untextured smooth plastic is kept for signal lamps and a few painted signs.
	expect(smooth / total < 0.06).toBeTruthy()
	for _, m in { "CeramicTiles", "Carpet", "Plaster", "Brick", "Wood", "Metal", "Plastic", "Rubber", "Fabric", "Leather", "Cardboard", "Glass" } do
		if not counts[m] then
			error("no part uses " .. m)
		end
	end
	-- The lobby is dressed as an office.
	for _, name in { "CorkBoard", "WaterCooler", "WindowGlass", "CoatRack" } do
		if not hq:FindFirstChild(name, true) then
			error("field office missing " .. name)
		end
	end
end)

test("round parts are sized the way Roblox draws them", function()
	-- A cylinder runs along X with diameter min(Y, Z); a ball uses the smallest
	-- side. Unequal sides mean the part renders differently from its size.
	build()
	local problems = {}
	for _, root in { station, hq } do
		for _, d in root:GetDescendants() do
			if d:IsA("Part") then
				local s = d.Size
				if d.Shape == roblox.Enum.PartType.Cylinder and math.abs(s.Y - s.Z) > 1e-3 then
					table.insert(problems, d:GetFullName() .. " cylinder " .. tostring(s))
				elseif d.Shape == roblox.Enum.PartType.Ball and (math.abs(s.X - s.Y) > 1e-3 or math.abs(s.Y - s.Z) > 1e-3) then
					table.insert(problems, d:GetFullName() .. " ball " .. tostring(s))
				end
			end
		end
	end
	if #problems > 0 then
		error(table.concat(problems, "\n      "))
	end
end)
