--[[
	The Presenter and footage silhouettes.

	The Presenter: one readable silhouette - tall, narrow-shouldered, long limbs, an
	outdated formal suit, and a small television where the face should be. Built from
	a handful of parts welded to a HumanoidRootPart so the server can move it with
	Humanoid:MoveTo and PathfindingService. No gore, no high part count.

	Height is 8.4 studs so it fits the 9-stud doors and pathfinding agent height.
]]

local Props = require(script.Parent.Props)
local Outfits = require(script.Parent.Outfits)

local Figures = {}

Figures.PRESENTER_HEIGHT = 8.4
Figures.LEG_LENGTH = 4.2

local SUIT = Color3.fromRGB(58, 52, 46)
local SUIT_DARK = Color3.fromRGB(38, 34, 30)
local SHIRT = Color3.fromRGB(176, 170, 152)
local SKIN = Color3.fromRGB(150, 140, 126)
local GHOST = Color3.fromRGB(14, 16, 14)

local function weldTo(root, p)
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	Props.weld(root, p)
end

--[[
	opts.ghost: build an anchored, all-black silhouette for footage/ghost replays
	(no Humanoid). Otherwise builds the live entity rig.
	Origin: feet at y = 0, facing -Z.
]]
function Figures.presenter(parent, opts)
	opts = opts or {}
	local ghost = opts.ghost == true
	local model = Instance.new("Model")
	model.Name = ghost and "PresenterGhost" or "Presenter"

	local legs = Figures.LEG_LENGTH
	local function c(col)
		return ghost and GHOST or col
	end
	local partOpts = { collide = false, shadow = not ghost, material = Enum.Material.Fabric }

	local root = Props.part(model, "HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(0, legs + 1, 0), Color3.new(0, 0, 0), {
		transparency = 1,
		collide = not ghost,
		shadow = false,
		anchored = ghost,
	})
	local pieces = {}
	local function add(name, size, cf, col, material)
		local o = table.clone(partOpts)
		o.material = material or partOpts.material
		local p = Props.part(model, name, size, cf, c(col), o)
		table.insert(pieces, p)
		return p
	end

	add("LeftLeg", Vector3.new(0.65, legs, 0.7), CFrame.new(-0.42, legs / 2, 0), SUIT_DARK)
	add("RightLeg", Vector3.new(0.65, legs, 0.7), CFrame.new(0.42, legs / 2, 0), SUIT_DARK)
	add("LeftShoe", Vector3.new(0.7, 0.3, 1.1), CFrame.new(-0.42, 0.15, -0.15), Color3.fromRGB(20, 18, 16), Enum.Material.Leather)
	add("RightShoe", Vector3.new(0.7, 0.3, 1.1), CFrame.new(0.42, 0.15, -0.15), Color3.fromRGB(20, 18, 16), Enum.Material.Leather)
	local torsoY = legs + 1.3
	add("Torso", Vector3.new(1.9, 2.6, 0.95), CFrame.new(0, torsoY, 0), SUIT)
	add("Shirt", Vector3.new(0.5, 1.4, 0.05), CFrame.new(0, torsoY + 0.5, -0.49), SHIRT, Enum.Material.SmoothPlastic)
	add("Tie", Vector3.new(0.22, 1.2, 0.06), CFrame.new(0, torsoY + 0.45, -0.52), Color3.fromRGB(70, 62, 56), Enum.Material.SmoothPlastic)
	add("LapelL", Vector3.new(0.45, 1.5, 0.06), CFrame.new(-0.42, torsoY + 0.45, -0.5) * CFrame.Angles(0, 0, math.rad(-12)), SUIT_DARK)
	add("LapelR", Vector3.new(0.45, 1.5, 0.06), CFrame.new(0.42, torsoY + 0.45, -0.5) * CFrame.Angles(0, 0, math.rad(12)), SUIT_DARK)
	-- Long arms hanging slightly too low.
	local armLength = 3.5
	local shoulderY = torsoY + 1.15
	local leftArm = add("LeftArm", Vector3.new(0.5, armLength, 0.55), CFrame.new(-1.22, shoulderY - armLength / 2, 0), SUIT)
	local rightArm = add("RightArm", Vector3.new(0.5, armLength, 0.55), CFrame.new(1.22, shoulderY - armLength / 2, 0), SUIT)
	leftArm:SetAttribute("Sway", -1)
	rightArm:SetAttribute("Sway", 1)
	add("LeftHand", Vector3.new(0.4, 0.7, 0.45), CFrame.new(-1.22, shoulderY - armLength - 0.3, 0), SKIN, Enum.Material.SmoothPlastic)
	add("RightHand", Vector3.new(0.4, 0.7, 0.45), CFrame.new(1.22, shoulderY - armLength - 0.3, 0), SKIN, Enum.Material.SmoothPlastic)
	add("Neck", Vector3.new(0.45, 0.3, 0.45), CFrame.new(0, torsoY + 1.45, 0), SKIN, Enum.Material.SmoothPlastic)

	-- Television head.
	local headY = Figures.PRESENTER_HEIGHT - 0.6
	local head = add("Head", Vector3.new(1.45, 1.2, 1.25), CFrame.new(0, headY, 0), Color3.fromRGB(84, 76, 66), Enum.Material.Plastic)
	add("Antenna", Vector3.new(0.08, 0.7, 0.08), CFrame.new(0.3, headY + 0.9, 0.1) * CFrame.Angles(0, 0, math.rad(-20)), Color3.fromRGB(30, 30, 30), Enum.Material.Metal)
	local screen = add("Screen", Vector3.new(1.15, 0.9, 0.05), CFrame.new(0, headY, -0.64), Color3.fromRGB(200, 205, 200), Enum.Material.Neon)
	if ghost then
		screen.Color = Color3.fromRGB(150, 155, 150)
	else
		-- The client animates static on this surface.
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Static"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Brightness = 1.5
		gui.Parent = screen
		local bg = Instance.new("Frame")
		bg.Name = "Background"
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = Color3.fromRGB(150, 155, 150)
		bg.BorderSizePixel = 0
		bg.Parent = gui
		model:AddTag("Presenter")
	end
	head:SetAttribute("PresenterHead", true)

	for _, p in pieces do
		if ghost then
			p.Anchored = true
		else
			weldTo(root, p)
		end
	end

	model.PrimaryPart = root
	model:SetAttribute("RootHeight", legs + 1)
	if not ghost then
		local humanoid = Instance.new("Humanoid")
		humanoid.Name = "Humanoid"
		humanoid.RigType = Enum.HumanoidRigType.R15
		humanoid.HipHeight = legs
		humanoid.WalkSpeed = 6
		humanoid.AutoRotate = true
		humanoid.RequiresNeck = false
		humanoid.BreakJointsOnDeath = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.MaxHealth = math.huge
		humanoid.Health = math.huge
		humanoid.Parent = model
		root.CanCollide = true
	end
	model.Parent = parent
	return model
end

-- A blocky investigator silhouette for footage (the team as the tape sees it).
-- A person in field kit, for CCTV footage and rewind ghosts.
function Figures.investigator(parent, colour)
	local model = Instance.new("Model")
	model.Name = "InvestigatorGhost"
	local col = colour or Color3.fromRGB(40, 46, 42)
	local function add(name, size, cf, c, material)
		return Props.part(model, name, size, cf, c or col, { collide = false, shadow = false, material = material or Enum.Material.Fabric })
	end
	local root = add("Torso", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0))
	for _, side in { -1, 1 } do
		add(side < 0 and "LeftLeg" or "RightLeg", Vector3.new(0.92, 2, 0.95), CFrame.new(side * 0.5, 1, 0), col:Lerp(Color3.new(0, 0, 0), 0.35))
		add(side < 0 and "LeftArm" or "RightArm", Vector3.new(0.8, 1.9, 0.85), CFrame.new(side * 1.42, 3.02, 0) * CFrame.Angles(0, 0, math.rad(side * 4)))
		add("Boot", Vector3.new(0.95, 0.35, 1.15), CFrame.new(side * 0.5, 0.18, -0.08), Color3.fromRGB(30, 26, 22), Enum.Material.Leather)
	end
	add("Head", Vector3.new(1.15, 1.2, 1.15), CFrame.new(0, 4.62, 0), colour or Color3.fromRGB(150, 128, 110), Enum.Material.Plastic)
	add("Neck", Vector3.new(0.6, 0.3, 0.6), CFrame.new(0, 4.05, 0), colour or Color3.fromRGB(150, 128, 110), Enum.Material.Plastic)
	Outfits.apply(model, "Field", colour or Color3.fromRGB(92, 108, 122))
	model.PrimaryPart = root
	model:SetAttribute("RootHeight", 3)
	model.Parent = parent
	return model
end

-- Height of a figure's PrimaryPart above its feet; place figures with
-- model:PivotTo(feetCFrame * CFrame.new(0, Figures.rootHeight(model), 0)).
function Figures.rootHeight(model)
	return model:GetAttribute("RootHeight") or 0
end

return Figures
