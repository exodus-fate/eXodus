--[[
	Controls — the key, button or touch label for each action on the device the
	player is using right now. The HUD hint, the tutorial, the prompts and the
	controls list in Settings all read from here so they always agree with the
	bindings in InputController.
]]

local UserInputService = game:GetService("UserInputService")

local Controls = {}

-- Action order for the controls list.
Controls.Order = { "Move", "Look", "Interact", "Sprint", "Flashlight", "Inspect", "Tool", "Deck", "Menu" }

Controls.Labels = {
	Move = "Move",
	Look = "Look around",
	Interact = "Interact / pick up",
	Sprint = "Sprint",
	Flashlight = "Flashlight",
	Inspect = "Inspect (zoom)",
	Tool = "Equip tool",
	Deck = "Open tape deck",
	Menu = "Menu / pause",
}

local KEYS = {
	keyboard = {
		Move = "W A S D",
		Look = "MOUSE",
		Interact = "E",
		Sprint = "SHIFT",
		Flashlight = "F",
		Inspect = "HOLD RMB",
		Tool = "1",
		Deck = "R",
		Menu = "TAB",
	},
	gamepad = {
		Move = "L-STICK",
		Look = "R-STICK",
		Interact = "X",
		Sprint = "L3",
		Flashlight = "D-DOWN",
		Inspect = "HOLD L2",
		Tool = "D-UP",
		Deck = "Y",
		Menu = "SELECT",
	},
	touch = {
		Move = "LEFT THUMB",
		Look = "DRAG",
		Interact = "TAP PROMPT",
		Sprint = "SPRINT",
		Flashlight = "LIGHT",
		Inspect = "INSPECT",
		Tool = "TOOL",
		Deck = "DECK",
		Menu = "MENU",
	},
}

local GAMEPAD_NAMES = {
	ButtonA = "A",
	ButtonB = "B",
	ButtonX = "X",
	ButtonY = "Y",
	ButtonL1 = "L1",
	ButtonR1 = "R1",
	ButtonL2 = "L2",
	ButtonR2 = "R2",
	ButtonL3 = "L3",
	ButtonR3 = "R3",
	DPadUp = "D-UP",
	DPadDown = "D-DOWN",
	DPadLeft = "D-LEFT",
	DPadRight = "D-RIGHT",
}

local lastDevice = nil

function Controls.device()
	local ok, last = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	if ok and last then
		if last == Enum.UserInputType.Touch then
			lastDevice = "touch"
		elseif string.sub(last.Name, 1, 7) == "Gamepad" then
			lastDevice = "gamepad"
		elseif last == Enum.UserInputType.Keyboard or string.sub(last.Name, 1, 5) == "Mouse" then
			lastDevice = "keyboard"
		end
	end
	if lastDevice then
		return lastDevice
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.MouseEnabled then
		return "gamepad"
	end
	return "keyboard"
end

function Controls.key(action, device)
	local keys = KEYS[device or Controls.device()] or KEYS.keyboard
	return keys[action] or "?"
end

-- "[E]" style, as shown inline in hints.
function Controls.tag(action, device)
	return "[" .. Controls.key(action, device) .. "]"
end

-- Label for a ProximityPrompt's key on the current device.
function Controls.promptKey(prompt, device)
	device = device or Controls.device()
	if device == "touch" then
		return "TAP"
	elseif device == "gamepad" then
		local name = prompt.GamepadKeyCode.Name
		return GAMEPAD_NAMES[name] or name
	end
	local name = prompt.KeyboardKeyCode.Name
	return string.upper(name)
end

return Controls
