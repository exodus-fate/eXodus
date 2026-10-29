-- KeypadController — the parts cage keypad (generator room).

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)

local KeypadController = {}

local DIGITS = 4

local gui, display, message
local entry = ""

local function render()
	local shown = entry .. string.rep("_", DIGITS - #entry)
	display.Text = string.gsub(shown, ".", "%0 ")
end

local function close()
	gui.Enabled = false
	State.setUI("keypad", false)
	GuiService.SelectedObject = nil
end

local function submit()
	if #entry < DIGITS then
		message.Text = "Enter all four digits."
		return
	end
	local code = entry
	entry = ""
	render()
	message.Text = "..."
	local result = State.request("SubmitCode", { code = code })
	if result.ok then
		close()
	else
		message.Text = result.message or "Rejected."
	end
end

local function press(key)
	if key == "C" then
		entry = ""
	elseif key == "OK" then
		submit()
		return
	elseif #entry < DIGITS then
		entry ..= key
	end
	message.Text = ""
	render()
end

function KeypadController.open()
	entry = ""
	render()
	message.Text = "Division's code comes over Channel 2 with the live clock."
	gui.Enabled = true
	State.setUI("keypad", true)
	if #UserInputService:GetConnectedGamepads() > 0 then
		GuiService.SelectedObject = gui:FindFirstChild("Key5", true)
	end
end

function KeypadController.init(playerGui)
	gui = UI.screen("DeadAirKeypad", 25, playerGui)
	gui.Enabled = false
	local panel = UI.panel(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(320, 470) })
	UI.modalUnlock(panel)
	UI.padding(panel, 14)
	UI.text(panel, "PARTS CAGE · KEYPAD", { Font = Theme.FontBold, TextColor3 = Theme.Accent, Size = UDim2.new(1, 0, 0, 24) })
	display = UI.text(panel, "", {
		Position = UDim2.new(0, 0, 0, 30),
		Size = UDim2.new(1, 0, 0, 48),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.FontBold,
		TextSize = 34,
		TextColor3 = Theme.Accent,
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(0, 0, 0),
	})
	local grid = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 90), Size = UDim2.new(1, 0, 0, 280), Parent = panel })
	UI.new("UIGridLayout", { CellSize = UDim2.new(0.31, 0, 0, 62), CellPadding = UDim2.new(0.035, 0, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	for i, key in { "1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "OK" } do
		local b = UI.button(grid, key, function()
			press(key)
		end, { LayoutOrder = i, TextSize = 24 })
		b.Name = "Key" .. key
	end
	message = UI.text(panel, "", { Position = UDim2.new(0, 0, 0, 376), Size = UDim2.new(1, 0, 0, 36), TextColor3 = Theme.Amber, TextSize = Theme.SmallText })
	UI.button(panel, "CLOSE", close, { Position = UDim2.new(0, 0, 1, -44), Size = UDim2.new(1, 0, 0, 44) })

	State.cue:Connect(function(cue)
		if cue.cue == "OpenKeypad" then
			KeypadController.open()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not gui.Enabled or processed then
			return
		end
		local map = {
			[Enum.KeyCode.Zero] = "0", [Enum.KeyCode.One] = "1", [Enum.KeyCode.Two] = "2", [Enum.KeyCode.Three] = "3",
			[Enum.KeyCode.Four] = "4", [Enum.KeyCode.Five] = "5", [Enum.KeyCode.Six] = "6", [Enum.KeyCode.Seven] = "7",
			[Enum.KeyCode.Eight] = "8", [Enum.KeyCode.Nine] = "9",
			[Enum.KeyCode.KeypadZero] = "0", [Enum.KeyCode.KeypadOne] = "1", [Enum.KeyCode.KeypadTwo] = "2",
			[Enum.KeyCode.KeypadThree] = "3", [Enum.KeyCode.KeypadFour] = "4", [Enum.KeyCode.KeypadFive] = "5",
			[Enum.KeyCode.KeypadSix] = "6", [Enum.KeyCode.KeypadSeven] = "7", [Enum.KeyCode.KeypadEight] = "8",
			[Enum.KeyCode.KeypadNine] = "9",
		}
		if map[input.KeyCode] then
			press(map[input.KeyCode])
		elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			submit()
		elseif input.KeyCode == Enum.KeyCode.Backspace then
			press("C")
		elseif input.KeyCode == Enum.KeyCode.ButtonB then
			close()
		end
	end)
	State.missionChanged:Connect(function(m)
		if gui.Enabled and (not m or not State.isAlive()) then
			close()
		end
	end)
end

return KeypadController
