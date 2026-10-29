--[[
	PromptController — draws every interaction prompt in the game's typeface
	and colours instead of Roblox's default style.

	A prompt shows the key for the current device (E, X or TAP), what it does
	and what it is for, and a fill bar while a hold prompt is held. On touch the
	whole card is a button: press and hold it like the key.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local Controls = require(script.Parent.Parent.UI.Controls)

local PromptController = {}

local shown = {} -- [prompt] = { gui, fill, conns }

local function hide(prompt)
	local entry = shown[prompt]
	if not entry then
		return
	end
	shown[prompt] = nil
	for _, conn in entry.conns do
		conn:Disconnect()
	end
	entry.gui:Destroy()
end

local function show(prompt, playerGui)
	hide(prompt)
	local adornee = prompt.Parent
	if not adornee or not (adornee:IsA("BasePart") or adornee:IsA("Attachment") or adornee:IsA("Model")) then
		return
	end
	local device = Controls.device()
	local gui = UI.new("BillboardGui", {
		Name = "DeadAirPrompt",
		Adornee = adornee,
		AlwaysOnTop = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(250, 58),
		StudsOffsetWorldSpace = Vector3.new(0, 1.2, 0),
		ResetOnSpawn = false,
		Active = device == "touch",
	})
	local card = UI.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Selectable = false,
		Parent = gui,
	})
	UI.stroke(card, Theme.Line, 1)
	UI.corner(card, 3)
	local key = UI.new("Frame", {
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(42, 42),
		Parent = card,
	})
	UI.stroke(key, Theme.Accent, 1)
	UI.corner(key, 3)
	local keyText = Controls.promptKey(prompt, device)
	UI.text(key, keyText, {
		FontFace = Theme.FontBold,
		TextSize = #keyText > 2 and 12 or 18,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
	})
	local fill = UI.new("Frame", {
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		Parent = key,
	})
	UI.text(card, string.upper(prompt.ActionText), {
		FontFace = Theme.FontBold,
		TextSize = 16,
		TextColor3 = Theme.Text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(60, prompt.ObjectText ~= "" and 8 or 18),
		Size = UDim2.new(1, -68, 0, 20),
	})
	if prompt.ObjectText ~= "" then
		UI.text(card, string.upper(prompt.ObjectText), {
			TextSize = 12,
			TextColor3 = Theme.TextDim,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(60, 30),
			Size = UDim2.new(1, -68, 0, 18),
		})
	end
	if prompt.HoldDuration > 0 then
		UI.text(card, "HOLD", {
			TextSize = 10,
			TextColor3 = Theme.AccentDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 3),
			Size = UDim2.fromOffset(40, 12),
		})
	end

	local entry = { gui = gui, fill = fill, conns = {} }
	shown[prompt] = entry
	local tween
	table.insert(entry.conns, prompt.PromptButtonHoldBegan:Connect(function()
		if tween then
			tween:Cancel()
		end
		fill.Size = UDim2.fromScale(1, 0)
		tween = TweenService:Create(fill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
		tween:Play()
	end))
	table.insert(entry.conns, prompt.PromptButtonHoldEnded:Connect(function()
		if tween then
			tween:Cancel()
			tween = nil
		end
		fill.Size = UDim2.fromScale(1, 0)
	end))
	table.insert(entry.conns, prompt.Triggered:Connect(function()
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundTransparency = 0.2
	end))
	-- Touch: hold the card like a key.
	table.insert(entry.conns, card.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldBegin()
		end
	end))
	table.insert(entry.conns, card.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldEnd()
		end
	end))
	gui.Parent = playerGui
end

function PromptController.init(playerGui)
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if prompt.Style == Enum.ProximityPromptStyle.Custom then
			show(prompt, playerGui)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(hide)
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		for prompt in shown do
			hide(prompt)
		end
	end)
end

return PromptController
