--[[
	Visual language for every screen: dark green-black panels, phosphor text,
	cream labels, amber for linked-event warnings, red only for real danger.
	Menu colour themes (cosmetics) only change the accent - all information stays
	equally readable.
]]

local Theme = {}

Theme.Background = Color3.fromRGB(10, 14, 12)
Theme.Panel = Color3.fromRGB(16, 22, 18)
Theme.PanelLight = Color3.fromRGB(26, 34, 28)
Theme.Line = Color3.fromRGB(60, 84, 66)
Theme.Accent = Color3.fromRGB(150, 210, 160)
Theme.AccentDim = Color3.fromRGB(90, 130, 100)
Theme.Text = Color3.fromRGB(214, 224, 210)
Theme.TextDim = Color3.fromRGB(130, 146, 128)
Theme.Cream = Color3.fromRGB(196, 186, 158)
Theme.Amber = Color3.fromRGB(226, 164, 76)
Theme.Danger = Color3.fromRGB(206, 76, 60)
Theme.Good = Color3.fromRGB(120, 200, 120)
Theme.Black = Color3.fromRGB(0, 0, 0)

Theme.Font = Enum.Font.Code
Theme.FontBold = Enum.Font.RobotoMono
Theme.FontTitle = Enum.Font.SpecialElite

Theme.TextSize = 16
Theme.SmallText = 13
Theme.LargeText = 22
Theme.TouchTarget = 44

function Theme.applyAccent(colour)
	if typeof(colour) == "Color3" then
		Theme.Accent = colour
		Theme.AccentDim = colour:Lerp(Color3.new(0, 0, 0), 0.4)
	end
end

return Theme
