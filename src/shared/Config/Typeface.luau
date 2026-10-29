--[[
	The one typeface used for every piece of text in the game: menus, HUD,
	subtitles, the deck, CCTV overlays, signs on the map and nameplates.
	Roboto Mono reads like broadcast test equipment and stays legible at small
	sizes; weights give hierarchy without a second family.
]]

local Typeface = {}

Typeface.Family = "rbxasset://fonts/families/RobotoMono.json"

function Typeface.regular()
	return Font.new(Typeface.Family, Enum.FontWeight.Regular)
end

function Typeface.medium()
	return Font.new(Typeface.Family, Enum.FontWeight.Medium)
end

function Typeface.bold()
	return Font.new(Typeface.Family, Enum.FontWeight.Bold)
end

return Typeface
