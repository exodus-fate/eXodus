--[[
	Outfits — what an investigator wears, built from welded parts so it works on
	any avatar (R15 or R6) without uploaded clothing.

	  Lobby  Division office staff in the field office: a wool jacket in the
	         uniform colour over the avatar, a lanyard and a photo ID badge.
	  Field  Kit for the station: a padded utility vest with reflective tape, a
	         chest radio with its antenna, a leather belt with pouches, a canvas
	         backpack with straps and a headlamp.

	The server swaps outfits when a player deploys or returns; the footage
	figures on the deck wear the field kit too.
]]

local Typeface = require(script.Parent.Parent.Config.Typeface)

local Outfits = {}

local LEATHER = Color3.fromRGB(58, 42, 30)
local CANVAS = Color3.fromRGB(74, 78, 62)
local TAPE = Color3.fromRGB(214, 210, 188)
local BLACK = Color3.fromRGB(24, 24, 22)
local BRASS = Color3.fromRGB(160, 130, 70)

local function attach(folder, body, name, size, offset, colour, material, opts)
	opts = opts or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = body.CFrame * offset
	p.Color = colour
	p.Material = material
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.CastShadow = opts.shadow ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.shape then
		p.Shape = opts.shape
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = p
	weld.Parent = p
	p.Parent = folder
	return p
end

local function bodyParts(character)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local lower = character:FindFirstChild("LowerTorso") or torso
	local head = character:FindFirstChild("Head")
	return torso, lower, head
end

local function lobby(folder, torso, _lower, head, colour, name)
	local s = torso.Size
	-- Jacket: a shell just over the torso, with lapels and a collar.
	attach(folder, torso, "Jacket", Vector3.new(s.X + 0.12, s.Y * 0.98, s.Z + 0.12), CFrame.new(0, 0, 0), colour, Enum.Material.Fabric)
	for _, side in { -1, 1 } do
		attach(folder, torso, "Lapel", Vector3.new(s.X * 0.16, s.Y * 0.5, 0.05), CFrame.new(side * s.X * 0.16, s.Y * 0.18, -s.Z / 2 - 0.08) * CFrame.Angles(0, 0, math.rad(side * 12)), colour:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Fabric)
	end
	attach(folder, torso, "Shirt", Vector3.new(s.X * 0.2, s.Y * 0.42, 0.04), CFrame.new(0, s.Y * 0.22, -s.Z / 2 - 0.07), Color3.fromRGB(206, 200, 184), Enum.Material.Fabric)
	attach(folder, torso, "Tie", Vector3.new(s.X * 0.07, s.Y * 0.4, 0.04), CFrame.new(0, s.Y * 0.16, -s.Z / 2 - 0.1), Color3.fromRGB(96, 40, 34), Enum.Material.Fabric)
	-- Lanyard and ID badge.
	for _, side in { -1, 1 } do
		attach(folder, torso, "Lanyard", Vector3.new(0.06, s.Y * 0.5, 0.03), CFrame.new(side * s.X * 0.14, s.Y * 0.2, -s.Z / 2 - 0.12) * CFrame.Angles(0, 0, math.rad(-side * 14)), Color3.fromRGB(140, 40, 34), Enum.Material.Fabric, { shadow = false })
	end
	local badge = attach(folder, torso, "IDBadge", Vector3.new(s.X * 0.26, s.Y * 0.24, 0.04), CFrame.new(s.X * 0.02, -s.Y * 0.08, -s.Z / 2 - 0.13), Color3.fromRGB(226, 220, 200), Enum.Material.Plastic, { shadow = false })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.Parent = badge
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.TextScaled = true
	text.FontFace = Typeface.bold()
	text.TextColor3 = Color3.fromRGB(40, 40, 36)
	text.Text = "NBRD\n" .. string.upper(name or "STAFF")
	text.Parent = gui
	if head then
		-- Reading glasses pushed up: a small civilian touch.
		local h = head.Size
		attach(folder, head, "Glasses", Vector3.new(h.X * 0.8, 0.08, 0.06), CFrame.new(0, h.Y * 0.08, -h.Z / 2 - 0.02), BLACK, Enum.Material.Plastic, { shadow = false })
	end
end

local function field(folder, torso, lower, head, colour)
	local s = torso.Size
	-- Padded vest with reflective tape bands.
	attach(folder, torso, "Vest", Vector3.new(s.X + 0.2, s.Y * 0.88, s.Z + 0.24), CFrame.new(0, -s.Y * 0.04, 0), colour, Enum.Material.Fabric)
	for i, y in { 0.12, -0.22 } do
		attach(folder, torso, "ReflectiveTape" .. i, Vector3.new(s.X + 0.24, 0.14, s.Z + 0.28), CFrame.new(0, s.Y * y, 0), TAPE, Enum.Material.Foil, { shadow = false })
	end
	-- Chest radio on the left shoulder strap.
	local radio = attach(folder, torso, "Radio", Vector3.new(0.42, 0.62, 0.22), CFrame.new(-s.X * 0.28, s.Y * 0.18, -s.Z / 2 - 0.22), BLACK, Enum.Material.Plastic)
	attach(folder, radio, "Antenna", Vector3.new(0.06, 0.6, 0.06), CFrame.new(0.12, 0.58, 0), BLACK, Enum.Material.Rubber, { shadow = false })
	attach(folder, radio, "Speaker", Vector3.new(0.3, 0.22, 0.02), CFrame.new(0, -0.08, -0.12), Color3.fromRGB(46, 46, 44), Enum.Material.DiamondPlate, { shadow = false })
	-- Pen-sized flashlight clipped right.
	attach(folder, torso, "PenLight", Vector3.new(0.12, 0.42, 0.12), CFrame.new(s.X * 0.3, s.Y * 0.2, -s.Z / 2 - 0.2), Color3.fromRGB(150, 150, 146), Enum.Material.Metal, { shadow = false })
	-- Backpack with straps.
	attach(folder, torso, "Backpack", Vector3.new(s.X * 0.82, s.Y * 0.9, 0.7), CFrame.new(0, -s.Y * 0.02, s.Z / 2 + 0.42), CANVAS, Enum.Material.Fabric)
	attach(folder, torso, "BackpackFlap", Vector3.new(s.X * 0.84, s.Y * 0.3, 0.74), CFrame.new(0, s.Y * 0.32, s.Z / 2 + 0.42), CANVAS:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Fabric)
	for _, side in { -1, 1 } do
		attach(folder, torso, "Strap", Vector3.new(0.16, s.Y * 0.95, 0.05), CFrame.new(side * s.X * 0.26, 0, -s.Z / 2 - 0.14), LEATHER, Enum.Material.Leather, { shadow = false })
	end
	-- Belt with pouches and a brass buckle.
	if lower then
		local l = lower.Size
		-- On a one-piece torso (R6, footage figures) the belt sits at its base.
		local y = lower == torso and -l.Y * 0.45 or l.Y * 0.3
		attach(folder, lower, "Belt", Vector3.new(l.X + 0.14, 0.24, l.Z + 0.14), CFrame.new(0, y, 0), LEATHER, Enum.Material.Leather)
		attach(folder, lower, "Buckle", Vector3.new(0.3, 0.22, 0.05), CFrame.new(0, y, -l.Z / 2 - 0.09), BRASS, Enum.Material.Metal, { shadow = false })
		for _, side in { -1, 1 } do
			attach(folder, lower, "Pouch", Vector3.new(0.4, 0.42, 0.28), CFrame.new(side * (l.X / 2 - 0.1), y - 0.22, -l.Z / 2 - 0.1), CANVAS, Enum.Material.Fabric)
		end
	end
	-- Headlamp on an elastic band.
	if head then
		local h = head.Size
		attach(folder, head, "HeadBand", Vector3.new(h.X + 0.06, 0.16, h.Z + 0.06), CFrame.new(0, h.Y * 0.22, 0), BLACK, Enum.Material.Rubber, { shadow = false })
		local lamp = attach(folder, head, "Headlamp", Vector3.new(0.36, 0.26, 0.2), CFrame.new(0, h.Y * 0.22, -h.Z / 2 - 0.12), Color3.fromRGB(60, 60, 56), Enum.Material.Plastic, { shadow = false })
		attach(folder, lamp, "Lens", Vector3.new(0.22, 0.16, 0.03), CFrame.new(0, 0, -0.11), Color3.fromRGB(230, 226, 200), Enum.Material.Glass, { shadow = false })
	end
end

-- Replaces any outfit on the character. mode: "Lobby" | "Field".
function Outfits.apply(character, mode, colour, name)
	local old = character:FindFirstChild("Outfit")
	if old then
		old:Destroy()
	end
	local torso, lower, head = bodyParts(character)
	if not torso then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = "Outfit"
	folder:SetAttribute("Mode", mode)
	if mode == "Field" then
		field(folder, torso, lower, head, colour)
	else
		lobby(folder, torso, lower, head, colour, name)
	end
	folder.Parent = character
	return folder
end

return Outfits
