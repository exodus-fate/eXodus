--[[
	Cosmetics never change gameplay information or survival. Sources:
	  default  everyone owns it
	  credits  bought with Recovery Credits earned in cases
	  pass     comes with a gamepass (see Monetisation.Passes)
	  product  comes with a developer product bundle
	  challenge unlocked by an investigator challenge
]]

local Cosmetics = {}

Cosmetics.Slots = { "uniform", "camcorder", "rec", "menu", "tapeLabel", "nameplate" }

Cosmetics.SlotLabels = {
	uniform = "UNIFORM",
	camcorder = "CAMCORDER SHELL",
	rec = "REC OVERLAY",
	menu = "MENU THEME",
	tapeLabel = "TAPE LABELS",
	nameplate = "NAMEPLATE",
}

Cosmetics.Items = {
	-- Uniform vests (worn over the avatar)
	uniform_standard = { slot = "uniform", label = "Division Standard", colour = { 92, 108, 122 }, source = "default" },
	uniform_field = { slot = "uniform", label = "Field Olive", colour = { 104, 122, 100 }, source = "credits", price = 150 },
	uniform_archive = { slot = "uniform", label = "Archive Brown", colour = { 104, 86, 66 }, source = "credits", price = 150 },
	uniform_night = { slot = "uniform", label = "Night Shift", colour = { 40, 44, 42 }, source = "credits", price = 300 },
	uniform_locker = { slot = "uniform", label = "Locker Reserve", colour = { 150, 141, 117 }, source = "pass", pass = "Locker" },
	uniform_supporter = { slot = "uniform", label = "Supporter Jacket", colour = { 120, 96, 60 }, source = "pass", pass = "Supporter" },
	uniform_loss = { slot = "uniform", label = "Nobody Left Behind", colour = { 70, 84, 92 }, source = "challenge", challenge = "C01_NOLOSS" },

	-- Camcorder viewfinder shells
	cam_standard = { slot = "camcorder", label = "Standard Issue", colour = { 196, 186, 158 }, source = "default" },
	cam_graphite = { slot = "camcorder", label = "Graphite", colour = { 120, 116, 110 }, source = "credits", price = 200 },
	cam_classic = { slot = "camcorder", label = "Classic Broadcast", colour = { 214, 150, 62 }, source = "pass", pass = "ClassicPack" },

	-- REC overlays (layout differs; information stays identical)
	rec_standard = { slot = "rec", label = "Standard REC", style = "standard", source = "default" },
	rec_minimal = { slot = "rec", label = "Minimal REC", style = "minimal", source = "credits", price = 100 },
	rec_classic = { slot = "rec", label = "Classic Broadcast REC", style = "classic", source = "pass", pass = "ClassicPack" },

	-- Menu CRT themes
	menu_green = { slot = "menu", label = "Phosphor Green", colour = { 150, 210, 160 }, source = "default" },
	menu_amber = { slot = "menu", label = "Amber Terminal", colour = { 230, 170, 90 }, source = "credits", price = 120 },
	menu_white = { slot = "menu", label = "Studio White", colour = { 220, 226, 220 }, source = "pass", pass = "ClassicPack" },
	menu_blue = { slot = "menu", label = "Test Card Blue", colour = { 150, 180, 220 }, source = "pass", pass = "ClassicPack" },

	-- Tape label skins (Evidence Archive)
	label_plain = { slot = "tapeLabel", label = "Plain Labels", colour = { 196, 186, 158 }, source = "default" },
	label_red = { slot = "tapeLabel", label = "Red Master Labels", colour = { 168, 80, 70 }, source = "product", product = "EvidenceBundle" },
	label_blue = { slot = "tapeLabel", label = "Archive Blue Labels", colour = { 92, 120, 160 }, source = "product", product = "EvidenceBundle" },

	-- Nameplates
	plate_none = { slot = "nameplate", label = "None", source = "default" },
	plate_investigator = { slot = "nameplate", label = "INVESTIGATOR", text = "INVESTIGATOR", source = "credits", price = 80 },
	plate_supporter = { slot = "nameplate", label = "SUPPORTER", text = "SUPPORTER", source = "pass", pass = "Supporter" },
	plate_archivist = { slot = "nameplate", label = "ARCHIVIST", text = "ARCHIVIST", source = "challenge", challenge = "C01_EVIDENCE" },
}

-- Desk decorations for Personal Quarters (field office desks).
Cosmetics.Decor = {
	decor_poster = { label = "Station Poster", source = "pass", pass = "Quarters" },
	decor_lamp = { label = "Desk Lamp", source = "pass", pass = "Quarters" },
	decor_shelf = { label = "Tape Display Shelf", source = "pass", pass = "Quarters" },
	decor_plant = { label = "Office Plant", source = "product", product = "LobbyBundle" },
	decor_radio = { label = "Old Radio", source = "product", product = "LobbyBundle" },
	decor_tv = { label = "Portable TV", source = "product", product = "LobbyBundle" },
}

Cosmetics.Defaults = {
	uniform = "uniform_standard",
	camcorder = "cam_standard",
	rec = "rec_standard",
	menu = "menu_green",
	tapeLabel = "label_plain",
	nameplate = "plate_none",
}

-- Loadout presets: one free, more with passes.
Cosmetics.BasePresetSlots = 1
Cosmetics.PresetSlotsPerPass = { Locker = 2, ExtraPresets = 3 }

-- Whether a player owns an item, given owned flags, owned passes and challenges.
function Cosmetics.owns(itemId: string, profile, passes)
	local item = Cosmetics.Items[itemId] or Cosmetics.Decor[itemId]
	if not item then
		return false
	end
	if item.source == "default" then
		return true
	elseif item.source == "pass" then
		return passes and passes[item.pass] == true
	elseif item.source == "challenge" then
		return profile.challenges and profile.challenges[item.challenge] == true
	end
	return profile.cosmetics and profile.cosmetics.owned and profile.cosmetics.owned[itemId] == true
end

function Cosmetics.presetSlots(passes)
	local slots = Cosmetics.BasePresetSlots
	for pass, extra in Cosmetics.PresetSlotsPerPass do
		if passes and passes[pass] then
			slots += extra
		end
	end
	return slots
end

return Cosmetics
