--[[
	Surfaces — what every part in the world is made of.

	Builders ask for a surface by what it is ("paintedMetal", "lino",
	"vinylCasing") instead of picking a Roblox material directly. Each surface
	maps to one of Roblox's physically based materials (wood grain, brushed and
	painted metal, plaster, carpet, ceramic tile, leather, rubber, fabric and so
	on - real textures with normal and roughness maps, rendered by the engine),
	plus a small amount of colour variation so a row of identical props does
	not look stamped out.

	Photographic textures: Roblox cannot load image files from this repository,
	so the station ships with the built-in materials. To go further, upload PBR
	texture sets (colour, normal, roughness, metalness) to Roblox and paste their
	asset ids into Surfaces.Variants below. Every surface that names a variant
	then uses it automatically (the server installs the MaterialVariants into
	MaterialService at start-up); empty entries are skipped.
]]

local Surfaces = {}

--[[
	material: Roblox material name
	vary:     +/- fraction of colour variation between parts (0 = exact)
	variant:  optional key into Surfaces.Variants
]]
Surfaces.List = {
	-- Building fabric
	plaster = { material = "Plaster", vary = 0.015, variant = "DeadAir_PaintedPlaster" },
	concrete = { material = "Concrete", vary = 0.03, variant = "DeadAir_Concrete" },
	breezeBlock = { material = "Brick", vary = 0.02 },
	ceilingTile = { material = "Plaster", vary = 0.02, variant = "DeadAir_CeilingTile" },
	lino = { material = "CeramicTiles", vary = 0.02, variant = "DeadAir_Linoleum" },
	carpet = { material = "Carpet", vary = 0.015, variant = "DeadAir_Carpet" },
	checkerPlate = { material = "DiamondPlate", vary = 0.03 },
	acousticFoam = { material = "Fabric", vary = 0.02 },
	panelling = { material = "Wood", vary = 0.03, variant = "DeadAir_Veneer" },
	asphalt = { material = "Asphalt", vary = 0.02 },
	ground = { material = "Ground", vary = 0.03 },

	-- Furniture and fittings
	veneer = { material = "Wood", vary = 0.05, variant = "DeadAir_Veneer" },
	planks = { material = "WoodPlanks", vary = 0.06 },
	upholstery = { material = "Fabric", vary = 0.04 },
	leather = { material = "Leather", vary = 0.05 },
	cardboard = { material = "Cardboard", vary = 0.06 },
	paper = { material = "Cardboard", vary = 0.04 },
	pottery = { material = "Slate", vary = 0.05 },
	foliage = { material = "LeafyGrass", vary = 0.06 },

	-- Metals
	paintedMetal = { material = "Metal", vary = 0.03, variant = "DeadAir_PaintedSteel" },
	bareMetal = { material = "Metal", vary = 0.02 },
	rust = { material = "CorrodedMetal", vary = 0.05 },
	foil = { material = "Foil", vary = 0.02 },
	mesh = { material = "DiamondPlate", vary = 0.02 },

	-- Equipment
	vinylCasing = { material = "Plastic", vary = 0.03 }, -- beige electronics casings
	blackPlastic = { material = "Plastic", vary = 0.02 },
	rubber = { material = "Rubber", vary = 0.02 },
	glass = { material = "Glass", vary = 0 },
	screen = { material = "Glass", vary = 0 },
	glow = { material = "Neon", vary = 0 },
	enamel = { material = "SmoothPlastic", vary = 0.01 }, -- signs, painted lettering
}

--[[
	Optional photographic texture sets (MaterialVariants). Paste uploaded asset
	ids ("rbxassetid://123...") to enable one. base is the Roblox material it
	overrides on the parts that ask for it.
]]
Surfaces.Variants = {
	DeadAir_PaintedPlaster = { base = "Plaster", studsPerTile = 10, colorMap = "", normalMap = "", roughnessMap = "", metalnessMap = "" },
	DeadAir_Concrete = { base = "Concrete", studsPerTile = 12, colorMap = "", normalMap = "", roughnessMap = "", metalnessMap = "" },
	DeadAir_CeilingTile = { base = "Plaster", studsPerTile = 4, colorMap = "", normalMap = "", roughnessMap = "", metalnessMap = "" },
	DeadAir_Linoleum = { base = "CeramicTiles", studsPerTile = 6, colorMap = "", normalMap = "", roughnessMap = "", metalnessMap = "" },
	DeadAir_Carpet = { base = "Carpet", studsPerTile = 6, colorMap = "", normalMap = "", roughnessMap = "", metalnessMap = "" },
	DeadAir_Veneer = { base = "Wood", studsPerTile = 6, colorMap = "", normalMap = "", roughnessMap = "", metalnessMap = "" },
	DeadAir_PaintedSteel = { base = "Metal", studsPerTile = 6, colorMap = "", normalMap = "", roughnessMap = "", metalnessMap = "" },
}

function Surfaces.get(name)
	local s = Surfaces.List[name]
	assert(s, "Unknown surface " .. tostring(name))
	return s
end

function Surfaces.material(name)
	return Enum.Material[Surfaces.get(name).material]
end

-- The variant name to use for a surface, or nil when none is configured.
function Surfaces.variantFor(name)
	local s = Surfaces.List[name]
	local v = s and s.variant and Surfaces.Variants[s.variant]
	if v and v.colorMap ~= "" then
		return s.variant
	end
	return nil
end

-- Deterministic small colour variation from a position, so the same prop
-- always looks the same on every server and in every footage clone.
function Surfaces.vary(colour, amount, position)
	if amount <= 0 or not position then
		return colour
	end
	local h = math.abs(math.sin(position.X * 12.9898 + position.Y * 78.233 + position.Z * 37.719) * 43758.5453) % 1
	local k = 1 + (h * 2 - 1) * amount
	return Color3.new(math.clamp(colour.R * k, 0, 1), math.clamp(colour.G * k, 0, 1), math.clamp(colour.B * k, 0, 1))
end

-- Installs configured MaterialVariants (server, once at start-up).
function Surfaces.install(materialService)
	local count = 0
	for name, v in Surfaces.Variants do
		if v.colorMap ~= "" and not materialService:FindFirstChild(name) then
			local variant = Instance.new("MaterialVariant")
			variant.Name = name
			variant.BaseMaterial = Enum.Material[v.base]
			variant.StudsPerTile = v.studsPerTile
			variant.ColorMap = v.colorMap
			variant.NormalMap = v.normalMap
			variant.RoughnessMap = v.roughnessMap
			variant.MetalnessMap = v.metalnessMap
			variant.Parent = materialService
			count += 1
		end
	end
	return count
end

return Surfaces
