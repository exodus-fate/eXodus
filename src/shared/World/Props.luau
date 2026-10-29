--[[
	Reusable prop builders. Practical, boxy 1990s broadcast shapes with readable
	silhouettes and low part counts. Every builder takes a CFrame for the prop's
	floor-level origin (or a surface point, as noted) and parents into `parent`.
]]

local MapLayout = require(script.Parent.Parent.Config.MapLayout)

local Props = {}

local function rgb(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end

function Props.colour(key)
	local c = MapLayout.Palette[key]
	assert(c, "Unknown palette colour " .. tostring(key))
	return rgb(c)
end
Props.rgb = rgb

--[[
	opts: material, transparency, collide (default true), shadow (default true),
	      shape ("Block" | "Cylinder" | "Ball"), anchored (default true)
]]
function Props.part(parent, name, size, cframe, colour, opts)
	opts = opts or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = opts.anchored ~= false
	p.CanCollide = opts.collide ~= false
	p.CastShadow = opts.shadow ~= false
	p.Material = opts.material or Enum.Material.SmoothPlastic
	p.Color = typeof(colour) == "Color3" and colour or Props.colour(colour or "grey")
	p.Transparency = opts.transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.shape then
		p.Shape = opts.shape
	end
	if opts.massless then
		p.Massless = true
	end
	p.Parent = parent
	return p
end

local part = Props.part

-- Text on the front (-Z) face of a part.
function Props.label(target, text, opts)
	opts = opts or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.Face = opts.face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = opts.pixelsPerStud or 40
	gui.LightInfluence = opts.lightInfluence or 1
	gui.Brightness = opts.brightness or 1
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.FontFace = Font.fromEnum(opts.font or Enum.Font.Code)
	label.TextColor3 = opts.textColour or Color3.fromRGB(30, 30, 26)
	label.TextWrapped = true
	label.Parent = gui
	return gui, label
end

function Props.model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function Props.weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
	return w
end

---------------------------------------------------------------------------
-- Furniture
---------------------------------------------------------------------------

function Props.desk(parent, cf, w, d, h, colour)
	local m = Props.model(parent, "Desk")
	h = h or 3.2
	part(m, "Top", Vector3.new(w, 0.25, d), cf * CFrame.new(0, h - 0.125, 0), colour or "brown", { material = Enum.Material.Wood })
	part(m, "Body", Vector3.new(w - 0.2, h - 0.25, d - 0.4), cf * CFrame.new(0, (h - 0.25) / 2, 0.1), colour or "brownDark", { material = Enum.Material.Wood })
	return m
end

function Props.chair(parent, cf, colour)
	local m = Props.model(parent, "Chair")
	part(m, "Seat", Vector3.new(1.8, 0.4, 1.8), cf * CFrame.new(0, 1.7, 0), colour or "blueDark", { material = Enum.Material.Fabric })
	part(m, "Back", Vector3.new(1.8, 2, 0.3), cf * CFrame.new(0, 2.9, 0.8), colour or "blueDark", { material = Enum.Material.Fabric })
	part(m, "Post", Vector3.new(0.3, 1.5, 0.3), cf * CFrame.new(0, 0.75, 0), "greyDark", { material = Enum.Material.Metal, collide = false })
	part(m, "Base", Vector3.new(1.6, 0.2, 1.6), cf * CFrame.new(0, 0.1, 0), "black", { collide = false })
	return m
end

function Props.bench(parent, cf, length)
	local m = Props.model(parent, "Bench")
	part(m, "Seat", Vector3.new(length, 0.4, 1.6), cf * CFrame.new(0, 1.6, 0), "brown", { material = Enum.Material.Wood })
	part(m, "Back", Vector3.new(length, 1.8, 0.3), cf * CFrame.new(0, 2.6, 0.7), "brown", { material = Enum.Material.Wood })
	part(m, "Legs", Vector3.new(length - 0.4, 1.4, 1.2), cf * CFrame.new(0, 0.7, 0), "greyDark", { material = Enum.Material.Metal })
	return m
end

function Props.cabinet(parent, cf, w, h, d, colour)
	local m = Props.model(parent, "Cabinet")
	part(m, "Body", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), colour or "grey", { material = Enum.Material.Metal })
	local drawers = math.max(1, math.floor(h / 1.2))
	for i = 1, drawers do
		part(m, "Handle" .. i, Vector3.new(w * 0.4, 0.12, 0.1), cf * CFrame.new(0, (i - 0.5) * (h / drawers), -d / 2 - 0.05), "greyDark", { collide = false, shadow = false })
	end
	return m
end

-- Open shelving: uprights plus boards. Items can rest on the boards (tops at the
-- given levels), unlike a solid box.
function Props.shelf(parent, cf, length, height, depth, levels, colour)
	local m = Props.model(parent, "Shelf")
	levels = levels or { 0.4, 2.5, 4.1, 5.7 }
	colour = colour or "greyDark"
	for _, side in { -1, 1 } do
		part(m, "Upright", Vector3.new(0.25, height, depth), cf * CFrame.new(side * (length / 2 - 0.125), height / 2, 0), colour, { material = Enum.Material.Metal })
	end
	for i, top in levels do
		part(m, "Board" .. i, Vector3.new(length, 0.15, depth), cf * CFrame.new(0, top - 0.075, 0), colour, { material = Enum.Material.Metal })
	end
	return m
end

-- A row of tape spines on a shelf board (decorative, no collision).
function Props.tapeRow(parent, cf, length, colourKeys)
	local count = math.floor(length / 0.6)
	for i = 1, count do
		local key = colourKeys[(i % #colourKeys) + 1]
		part(parent, "Spine", Vector3.new(0.45, 1.1, 1.3), cf * CFrame.new(-length / 2 + (i - 0.5) * 0.6, 0.55, 0), key, { collide = false, shadow = false, material = Enum.Material.Plastic })
	end
end

function Props.plant(parent, cf)
	local m = Props.model(parent, "Plant")
	part(m, "Pot", Vector3.new(1.4, 1.4, 1.4), cf * CFrame.new(0, 0.7, 0), "brownDark", { material = Enum.Material.Slate })
	part(m, "Leaves", Vector3.new(2.2, 2.6, 2.2), cf * CFrame.new(0, 2.6, 0), "greenDark", { material = Enum.Material.Grass, collide = false })
	return m
end

function Props.crate(parent, cf, size)
	return part(parent, "Crate", size, cf * CFrame.new(0, size.Y / 2, 0), "brown", { material = Enum.Material.WoodPlanks })
end

function Props.extinguisher(parent, cf)
	local m = Props.model(parent, "Extinguisher")
	part(m, "Body", Vector3.new(0.7, 1.8, 0.7), cf * CFrame.new(0, 1.4, 0), "warning", { collide = false })
	part(m, "Bracket", Vector3.new(0.9, 0.2, 0.3), cf * CFrame.new(0, 2.3, 0.3), "greyDark", { collide = false })
	return m
end

-- Cylinder from a to b (Vector3s).
function Props.pipe(parent, a, b, radius, colour)
	local length = (b - a).Magnitude
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0)
	return part(parent, "Pipe", Vector3.new(length, radius * 2, radius * 2), cf, colour or "greyDark", {
		shape = Enum.PartType.Cylinder,
		material = Enum.Material.Metal,
		collide = false,
	})
end

function Props.poster(parent, cf, w, h, text, colour)
	local p = part(parent, "Poster", Vector3.new(w, h, 0.05), cf, colour or "cream", { collide = false, shadow = false, material = Enum.Material.Cardboard })
	Props.label(p, text, { textColour = Color3.fromRGB(60, 54, 44), pixelsPerStud = 30 })
	return p
end

function Props.sign(parent, cf, w, h, text, colour, textColour)
	local p = part(parent, "Sign", Vector3.new(w, h, 0.1), cf, colour or "creamDark", { collide = false, shadow = false })
	Props.label(p, text, { textColour = textColour or Color3.fromRGB(34, 34, 30), pixelsPerStud = 30 })
	return p
end

---------------------------------------------------------------------------
-- Broadcast equipment
---------------------------------------------------------------------------

-- CRT monitor. cf is the bottom-centre; the screen faces -Z. Returns model, screen.
function Props.crt(parent, cf, scale, name)
	scale = scale or 1
	local m = Props.model(parent, name or "CRT")
	local w, h, d = 2.2 * scale, 1.9 * scale, 2 * scale
	part(m, "Casing", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0.15 * scale), "cream", { material = Enum.Material.Plastic })
	part(m, "Bezel", Vector3.new(w * 0.92, h * 0.86, 0.1), cf * CFrame.new(0, h / 2, -d / 2 + 0.1 * scale), "creamDark", { collide = false })
	local screen = part(m, "Screen", Vector3.new(w * 0.78, h * 0.68, 0.06), cf * CFrame.new(0, h / 2 + 0.04 * scale, -d / 2 + 0.03 * scale), "black", {
		collide = false,
		shadow = false,
		material = Enum.Material.Glass,
	})
	part(m, "KnobA", Vector3.new(0.2, 0.2, 0.1), cf * CFrame.new(w * 0.4, h * 0.15, -d / 2 + 0.05), "greyDark", { collide = false, shadow = false })
	return m, screen
end

-- Tape deck (VCR). cf is the bottom-centre; the slot faces -Z.
function Props.vcr(parent, cf, colour)
	local m = Props.model(parent, "TapeDeck")
	part(m, "Body", Vector3.new(2.6, 0.6, 1.8), cf * CFrame.new(0, 0.3, 0), colour or "greyDark", { material = Enum.Material.Metal })
	part(m, "Slot", Vector3.new(1.6, 0.12, 0.05), cf * CFrame.new(-0.3, 0.38, -0.91), "black", { collide = false, shadow = false })
	for i = 0, 3 do
		part(m, "Button" .. i, Vector3.new(0.18, 0.12, 0.05), cf * CFrame.new(0.75 + i * 0.22, 0.22, -0.91), "creamDark", { collide = false, shadow = false })
	end
	local led = part(m, "StatusLED", Vector3.new(0.12, 0.08, 0.05), cf * CFrame.new(0.9, 0.42, -0.91), Color3.fromRGB(120, 200, 120), {
		collide = false,
		shadow = false,
		material = Enum.Material.Neon,
	})
	return m, led
end

function Props.beigeComputer(parent, cf)
	local m = Props.model(parent, "Computer")
	part(m, "Tower", Vector3.new(2, 0.7, 1.8), cf * CFrame.new(0, 0.35, 0), "cream", { material = Enum.Material.Plastic })
	local _, screen = Props.crt(m, cf * CFrame.new(0, 0.7, 0), 0.8, "Monitor")
	part(m, "Keyboard", Vector3.new(1.8, 0.12, 0.7), cf * CFrame.new(0, 0.06, -1.5), "creamDark", { collide = false })
	return m, screen
end

function Props.mixingConsole(parent, cf, w)
	local m = Props.model(parent, "Console")
	part(m, "Base", Vector3.new(w, 2.8, 2.6), cf * CFrame.new(0, 1.4, 0), "greyDark", { material = Enum.Material.Metal })
	local slope = part(m, "Panel", Vector3.new(w, 0.3, 2.4), cf * CFrame.new(0, 3, -0.1) * CFrame.Angles(math.rad(-12), 0, 0), "black", { material = Enum.Material.Metal })
	local faders = math.floor(w / 0.6)
	for i = 1, faders do
		part(m, "Fader", Vector3.new(0.18, 0.15, 0.5), slope.CFrame * CFrame.new(-w / 2 + (i - 0.5) * 0.6, 0.2, ((i % 3) - 1) * 0.3), "creamDark", { collide = false, shadow = false })
	end
	return m
end

function Props.equipmentRack(parent, cf, h, name)
	local m = Props.model(parent, name or "Rack")
	part(m, "Frame", Vector3.new(2.4, h, 2.2), cf * CFrame.new(0, h / 2, 0), "black", { material = Enum.Material.Metal })
	local units = math.floor((h - 0.6) / 0.9)
	for i = 1, units do
		part(m, "Unit" .. i, Vector3.new(2.1, 0.7, 0.1), cf * CFrame.new(0, 0.5 + (i - 0.5) * 0.9, -1.12), i % 2 == 0 and "greyDark" or "grey", { collide = false, shadow = false })
	end
	return m
end

function Props.cctvCamera(parent, position, look, cameraId)
	local m = Props.model(parent, cameraId)
	local cf = CFrame.lookAt(position, look)
	part(m, "Housing", Vector3.new(0.7, 0.6, 1.4), cf, "cream", { collide = false })
	part(m, "Lens", Vector3.new(0.4, 0.4, 0.2), cf * CFrame.new(0, 0, -0.75), "black", { collide = false, shadow = false, material = Enum.Material.Glass })
	local led = part(m, "Tally", Vector3.new(0.1, 0.1, 0.1), cf * CFrame.new(0.25, 0.25, -0.7), Color3.fromRGB(150, 40, 30), {
		collide = false,
		shadow = false,
		material = Enum.Material.Neon,
	})
	led:SetAttribute("TallyLight", true)
	m:SetAttribute("CameraId", cameraId)
	return m
end

function Props.generator(parent, cf)
	local m = Props.model(parent, "Generator")
	part(m, "Body", Vector3.new(12, 6, 6), cf * CFrame.new(0, 3.4, 0), "greenDark", { material = Enum.Material.Metal })
	part(m, "Skid", Vector3.new(13, 0.4, 7), cf * CFrame.new(0, 0.2, 0), "black", { material = Enum.Material.Metal })
	part(m, "Exhaust", Vector3.new(1, 5, 1), cf * CFrame.new(4.5, 8.5, 1.5), "greyDark", { material = Enum.Material.CorrodedMetal, collide = false })
	part(m, "Panel", Vector3.new(3, 2.2, 0.3), cf * CFrame.new(-3, 3.8, -3.15), "cream", { collide = false })
	local lamps = {}
	for i, name in { "Unpowered", "Primed", "Powered" } do
		local lamp = part(m, "Lamp" .. name, Vector3.new(0.35, 0.35, 0.1), cf * CFrame.new(-4.1 + i * 0.55, 4.5, -3.35), "greyDark", {
			collide = false,
			shadow = false,
			material = Enum.Material.SmoothPlastic,
		})
		lamp:SetAttribute("GeneratorStage", i - 1)
		lamps[i] = lamp
	end
	for i = 1, 4 do
		part(m, "Fin" .. i, Vector3.new(0.2, 4.5, 5.6), cf * CFrame.new(1 + i * 0.9, 3.4, 0), "black", { collide = false, shadow = false })
	end
	return m
end

function Props.cage(parent, cf)
	local m = Props.model(parent, "PartsCage")
	local w, h, d = 4.5, 7, 4
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			part(m, "Post", Vector3.new(0.2, h, 0.2), cf * CFrame.new(x * w / 2, h / 2, z * d / 2), "greyDark", { material = Enum.Material.Metal })
		end
	end
	local meshOpts = { material = Enum.Material.DiamondPlate, transparency = 0.55 }
	part(m, "MeshBack", Vector3.new(w, h, 0.1), cf * CFrame.new(0, h / 2, d / 2), "grey", meshOpts)
	part(m, "MeshLeft", Vector3.new(0.1, h, d), cf * CFrame.new(-w / 2, h / 2, 0), "grey", meshOpts)
	part(m, "MeshRight", Vector3.new(0.1, h, d), cf * CFrame.new(w / 2, h / 2, 0), "grey", meshOpts)
	local door = part(m, "MeshDoor", Vector3.new(w, h, 0.1), cf * CFrame.new(0, h / 2, -d / 2), "grey", meshOpts)
	door:SetAttribute("CageDoor", true)
	part(m, "Roof", Vector3.new(w, 0.1, d), cf * CFrame.new(0, h, 0), "grey", meshOpts)
	part(m, "Shelf", Vector3.new(w - 0.4, 0.15, d - 0.4), cf * CFrame.new(0, 3.2, 0), "greyDark", { material = Enum.Material.Metal })
	local keypad = part(m, "Keypad", Vector3.new(0.8, 1.1, 0.25), cf * CFrame.new(w / 2 + 0.6, 4, -d / 2), "greyDark", { collide = false })
	Props.label(keypad, "1 2 3\n4 5 6\n7 8 9\n  0  ", { textColour = Color3.fromRGB(150, 210, 160), lightInfluence = 0, pixelsPerStud = 50 })
	return m
end

function Props.relayBox(parent, cf, label)
	local m = Props.model(parent, "Relay")
	part(m, "Box", Vector3.new(2.2, 2.8, 0.8), cf, "grey", { material = Enum.Material.Metal })
	local lamp = part(m, "Lamp", Vector3.new(0.4, 0.4, 0.1), cf * CFrame.new(0.6, 0.8, -0.45), Color3.fromRGB(120, 200, 120), {
		collide = false,
		shadow = false,
		material = Enum.Material.Neon,
	})
	lamp:SetAttribute("RelayLamp", true)
	local plate = part(m, "Plate", Vector3.new(1.6, 0.5, 0.05), cf * CFrame.new(-0.2, -0.6, -0.42), "cream", { collide = false, shadow = false })
	Props.label(plate, label, { pixelsPerStud = 40 })
	return m
end

function Props.transmitter(parent, cf)
	local m = Props.model(parent, "Transmitter")
	part(m, "Cabinet", Vector3.new(14, 14, 10), cf * CFrame.new(0, 7, 0), "greyDark", { material = Enum.Material.Metal })
	part(m, "Upper", Vector3.new(9, 8, 7), cf * CFrame.new(0, 18, 0), "black", { material = Enum.Material.Metal })
	part(m, "Mast", Vector3.new(1.4, 4, 1.4), cf * CFrame.new(0, 24, 0), "grey", { material = Enum.Material.Metal, collide = false })
	for i = 1, 5 do
		part(m, "Vent" .. i, Vector3.new(11, 0.4, 0.1), cf * CFrame.new(0, 2 + i * 2, -5.05), "black", { collide = false, shadow = false })
	end
	local status = part(m, "StatusLamp", Vector3.new(0.8, 0.8, 0.8), cf * CFrame.new(0, 14.6, -3.6), Color3.fromRGB(70, 30, 26), {
		collide = false,
		shadow = false,
		material = Enum.Material.SmoothPlastic,
	})
	status:SetAttribute("TransmitterLamp", true)
	return m
end

function Props.van(parent, cf)
	local m = Props.model(parent, "ExtractionVan")
	part(m, "Body", Vector3.new(7.5, 6.5, 15), cf * CFrame.new(0, 4.2, 0), "cream", { material = Enum.Material.Metal })
	part(m, "Cab", Vector3.new(7.5, 4.5, 3.5), cf * CFrame.new(0, 3.2, -9), "cream", { material = Enum.Material.Metal })
	part(m, "Windscreen", Vector3.new(6.8, 2, 0.1), cf * CFrame.new(0, 4.4, -10.8), "blueDark", { material = Enum.Material.Glass, transparency = 0.3, collide = false })
	part(m, "Stripe", Vector3.new(7.6, 0.6, 15.1), cf * CFrame.new(0, 4.4, 0), "blue", { collide = false, shadow = false })
	for _, x in { -3.4, 3.4 } do
		for _, z in { -8, 5 } do
			part(m, "Wheel", Vector3.new(1, 2.2, 2.2), cf * CFrame.new(x, 1.1, z), "black", { shape = Enum.PartType.Cylinder, material = Enum.Material.Rubber })
		end
	end
	local doors = part(m, "RearDoors", Vector3.new(7, 6, 0.2), cf * CFrame.new(0, 4.2, 7.6), "creamDark", { material = Enum.Material.Metal })
	Props.label(doors, "NBRD · MOBILE UNIT 4", { textColour = Color3.fromRGB(60, 70, 80), face = Enum.NormalId.Back, pixelsPerStud = 20 })
	-- Small monitor inside the rear doors: the false-safety beat plays on it.
	local _, screen = Props.crt(m, cf * CFrame.new(2.2, 3, 6.6) * CFrame.Angles(0, math.rad(180), 0), 0.7, "VanMonitor")
	screen:AddTag("CCTVMonitor")
	screen:SetAttribute("CameraId", "CAM11")
	screen:SetAttribute("MonitorRole", "Van")
	return m
end

function Props.floodlight(parent, cf, colour)
	local m = Props.model(parent, "Floodlight")
	part(m, "Pole", Vector3.new(0.5, 14, 0.5), cf * CFrame.new(0, 7, 0), "greyDark", { material = Enum.Material.Metal })
	local head = part(m, "Head", Vector3.new(2, 1, 1), cf * CFrame.new(0, 14, -0.5), colour or Color3.fromRGB(230, 200, 150), {
		material = Enum.Material.Neon,
		collide = false,
		shadow = false,
	})
	local light = Instance.new("SpotLight")
	light.Name = "Light"
	light.Face = Enum.NormalId.Bottom
	light.Angle = 80
	light.Range = 34
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(230, 190, 130)
	light.Shadows = false
	light.Parent = head
	head:SetAttribute("LightKind", "Emergency")
	return m
end

function Props.studioCamera(parent, cf)
	local m = Props.model(parent, "StudioCamera")
	part(m, "Tripod", Vector3.new(1.6, 4.4, 1.6), cf * CFrame.new(0, 2.2, 0), "black", { material = Enum.Material.Metal })
	part(m, "Body", Vector3.new(1.4, 1.5, 2.6), cf * CFrame.new(0, 5.1, 0), "greyDark", { material = Enum.Material.Metal })
	part(m, "Lens", Vector3.new(0.8, 0.8, 0.8), cf * CFrame.new(0, 5.1, -1.6), "black", { collide = false, material = Enum.Material.Glass })
	return m
end

function Props.wallClock(parent, cf, time)
	local m = Props.model(parent, "Clock")
	local face = part(m, "Face", Vector3.new(0.15, 2, 2), cf * CFrame.Angles(0, math.rad(90), 0), "cream", {
		shape = Enum.PartType.Cylinder,
		collide = false,
	})
	-- Rotating a cylinder 90 degrees about Y points its +X (Right) disc along -Z.
	local _, text = Props.label(face, time or "", { textColour = Color3.fromRGB(40, 40, 36), face = Enum.NormalId.Right, pixelsPerStud = 40 })
	text.Name = "Time"
	return m, text
end

---------------------------------------------------------------------------
-- Pick-up items (spawned at runtime). cf is the resting point on a surface.
---------------------------------------------------------------------------

function Props.vhsTape(parent, cf, labelText, colour)
	local m = Props.model(parent, "Tape")
	local body = part(m, "Body", Vector3.new(1.9, 0.5, 1.1), cf * CFrame.new(0, 0.25, 0), "black", { collide = false, material = Enum.Material.Plastic })
	local sticker = part(m, "Sticker", Vector3.new(1.5, 0.05, 0.6), cf * CFrame.new(0, 0.52, 0), colour or Color3.fromRGB(196, 186, 158), { collide = false, shadow = false })
	Props.label(sticker, labelText, { face = Enum.NormalId.Top, pixelsPerStud = 60, textColour = Color3.fromRGB(30, 30, 26) })
	m.PrimaryPart = body
	return m
end

function Props.component(parent, cf, itemId)
	local m = Props.model(parent, itemId)
	local main
	if itemId == "COIL" then
		main = part(m, "Coil", Vector3.new(1.6, 1, 1), cf * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(176, 110, 64), {
			shape = Enum.PartType.Cylinder,
			material = Enum.Material.Metal,
			collide = false,
		})
		part(m, "Core", Vector3.new(1.8, 0.4, 0.4), cf * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), "greyDark", { shape = Enum.PartType.Cylinder, collide = false })
	elseif itemId == "VALVE" then
		main = part(m, "Tube", Vector3.new(1.4, 0.7, 0.7), cf * CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(190, 210, 200), {
			shape = Enum.PartType.Cylinder,
			material = Enum.Material.Glass,
			transparency = 0.3,
			collide = false,
		})
		part(m, "Base", Vector3.new(0.9, 0.3, 0.9), cf * CFrame.new(0, 0.15, 0), "black", { collide = false })
	elseif itemId == "BOARD" then
		main = part(m, "Board", Vector3.new(1.8, 0.12, 1.2), cf * CFrame.new(0, 0.06, 0), Color3.fromRGB(46, 96, 60), { collide = false })
		for i = 1, 4 do
			part(m, "Chip" .. i, Vector3.new(0.3, 0.1, 0.2), cf * CFrame.new(-0.6 + i * 0.25, 0.15, 0.2), "black", { collide = false, shadow = false })
		end
	elseif itemId == "KEY" then
		main = part(m, "Fob", Vector3.new(0.8, 0.2, 0.5), cf * CFrame.new(0, 0.1, 0), Color3.fromRGB(196, 160, 70), { collide = false, material = Enum.Material.Metal })
		part(m, "Tag", Vector3.new(0.6, 0.05, 0.9), cf * CFrame.new(0.6, 0.05, 0), "cream", { collide = false, shadow = false })
	end
	m.PrimaryPart = main
	return m
end

return Props
