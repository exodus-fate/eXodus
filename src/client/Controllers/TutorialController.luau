--[[
	TutorialController — a short walkthrough the first time someone plays, and a
	handful of one-time tips during their first case.

	The walkthrough is a stack of Division briefing cards over the main menu:
	BACK / NEXT / SKIP, readable with mouse, controller or touch, with the right
	keys for the device in use. Finishing or skipping it saves `tutorialSeen` on
	the profile; Settings > Replay tutorial shows it again.

	Tips appear once per session at the moment they matter (first tape, first
	dark room, first hunt) and can be turned off in Settings.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapLayout = require(Shared.Config.MapLayout)

local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local Controls = require(script.Parent.Parent.UI.Controls)

local TutorialController = {}

local function keys(...)
	local out = {}
	for _, action in { ... } do
		table.insert(out, action)
	end
	return out
end

-- Each card: title, body, and the actions whose keys it shows.
TutorialController.Steps = {
	{
		title = "WELCOME, INVESTIGATOR",
		body = "You work for the National Broadcast Recovery Division. Broadcast Station 04 has been empty for nineteen years. Tonight it started transmitting again.\n\nThis takes a minute. You can skip it and replay it from Settings.",
	},
	{
		title = "MOVING AROUND",
		body = "You see everything through your own eyes. Sprinting drains stamina (the thin bar at the bottom). The station is dark: keep your flashlight handy, and hold inspect to look closely at something.",
		keys = keys("Move", "Look", "Sprint", "Flashlight", "Inspect"),
	},
	{
		title = "THE FIELD OFFICE",
		body = "This is the lobby. Choose a case from CASE SELECT or the case board, then press READY. Play alone or with up to three others; when everyone here is ready, the team deploys to the station.",
		keys = keys("Interact", "Menu"),
	},
	{
		title = "TAPES AND THE DECK",
		body = "VHS tapes are hidden around the station. Take one to a Time-Shift Deck and it shows tonight's CCTV footage - footage of things that have not happened yet.",
		keys = keys("Interact", "Deck"),
	},
	{
		title = "EDITING THE FUTURE",
		body = "Diamonds on the tape are events you can change; circles are their consequences. Amber means one change will set off another. Every edit costs a charge, so think before you commit.",
	},
	{
		title = "THE PRESENTER",
		body = "Something walks the station. If it sees you, it hunts. Break its line of sight, put doors between you, and do not stare at the monitors for too long - it notices who is watching.",
	},
	{
		title = "THE CAMERAS",
		body = "Old closed-circuit sets show the station's cameras live. A weak signal means a rolling, snowy picture. What you see on them is information: use it.",
	},
	{
		title = "GETTING OUT",
		body = "Your objective is always at the top left. Recover the components, stop tonight's broadcast, and get to the van at the loading dock. If you are caught, your team can still finish without you.",
	},
	{
		title = "COMFORT SETTINGS",
		body = "The menu has head bob, motion blur, vignette, field of view, camera shake, text size and a low intensity mode that keeps every piece of information. Good luck.",
		keys = keys("Menu"),
	},
}

local gui, panel, titleText, bodyText, keyRow, counter, backButton, nextButton
local index = 1
local open = false

local tipGui, tipText
local tipsShown = {}

---------------------------------------------------------------------------
-- Walkthrough
---------------------------------------------------------------------------

local function render()
	local step = TutorialController.Steps[index]
	titleText.Text = step.title
	bodyText.Text = step.body
	counter.Text = string.format("BRIEFING %d / %d", index, #TutorialController.Steps)
	UI.clear(keyRow)
	local device = Controls.device()
	for i, action in step.keys or {} do
		local chip = UI.new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), LayoutOrder = i, Parent = keyRow })
		UI.list(chip, 6, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left).VerticalAlignment = Enum.VerticalAlignment.Center
		local cap = UI.new("Frame", { BackgroundColor3 = Theme.PanelLight, BorderSizePixel = 0, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), LayoutOrder = 1, Parent = chip })
		UI.stroke(cap, Theme.Accent, 1)
		UI.corner(cap, 3)
		UI.padding(cap, 8, 0)
		UI.text(cap, Controls.key(action, device), {
			FontFace = Theme.FontBold,
			TextSize = Theme.SmallText,
			TextColor3 = Theme.Accent,
			TextWrapped = false,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
		})
		UI.text(chip, Controls.Labels[action], {
			TextSize = Theme.SmallText,
			TextColor3 = Theme.TextDim,
			TextWrapped = false,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 26),
			LayoutOrder = 2,
		})
	end
	UI.setEnabled(backButton, index > 1)
	nextButton.Text = index == #TutorialController.Steps and "FINISH" or "NEXT"
end

local function finish()
	if not open then
		return
	end
	open = false
	gui.Enabled = false
	State.setUI("tutorial", false)
	GuiService.SelectedObject = nil
	if State.profile then
		State.profile.tutorialSeen = true
	end
	task.spawn(function()
		State.request("SetTutorialSeen", {})
	end)
end

function TutorialController.start()
	index = 1
	open = true
	gui.Enabled = true
	State.setUI("tutorial", true)
	render()
	panel.Position = UDim2.fromScale(0.5, 0.53)
	TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(0.5, 0.5) }):Play()
	if #UserInputService:GetConnectedGamepads() > 0 then
		GuiService.SelectedObject = nextButton
	end
end

function TutorialController.isOpen()
	return open
end

local function step(delta)
	local nextIndex = index + delta
	if nextIndex > #TutorialController.Steps then
		finish()
	elseif nextIndex >= 1 then
		index = nextIndex
		render()
	end
end

local function build(playerGui)
	gui = UI.screen("DeadAirTutorial", 60, playerGui)
	gui.Enabled = false
	-- Active: the shade swallows clicks so the menu behind it can't be used.
	local shade = UI.new("Frame", {
		BackgroundColor3 = Theme.Black,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Active = true,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	UI.modalUnlock(shade)
	panel = UI.panel(shade, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0, 360),
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(640, 420), Parent = panel })
	UI.padding(panel, 22, 18)
	counter = UI.text(panel, "", { TextSize = Theme.SmallText, TextColor3 = Theme.Amber, Size = UDim2.new(1, 0, 0, 18) })
	UI.text(panel, "NBRD · FIELD BRIEFING", {
		TextSize = Theme.SmallText,
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, 0, 0, 18),
	})
	UI.new("Frame", { BackgroundColor3 = Theme.Line, BorderSizePixel = 0, Position = UDim2.new(0, 0, 0, 24), Size = UDim2.new(1, 0, 0, 1), Parent = panel })
	titleText = UI.text(panel, "", {
		FontFace = Theme.FontBold,
		TextSize = 26,
		TextColor3 = Theme.Cream,
		Position = UDim2.new(0, 0, 0, 36),
		Size = UDim2.new(1, 0, 0, 34),
	})
	bodyText = UI.text(panel, "", {
		TextColor3 = Theme.Text,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 0, 0, 80),
		Size = UDim2.new(1, 0, 1, -190),
	})
	keyRow = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -104), Size = UDim2.new(1, 0, 0, 60), Parent = panel })
	local layout = UI.list(keyRow, 14, Enum.FillDirection.Horizontal)
	layout.Wraps = true
	local buttons = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -44), Size = UDim2.new(1, 0, 0, 44), Parent = panel })
	UI.button(buttons, "SKIP TUTORIAL", finish, { Size = UDim2.new(0.3, 0, 1, 0), TextColor3 = Theme.TextDim, TextSize = Theme.SmallText })
	backButton = UI.button(buttons, "BACK", function()
		step(-1)
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -170, 0, 0), Size = UDim2.new(0, 150, 1, 0) })
	nextButton = UI.button(buttons, "NEXT", function()
		step(1)
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 150, 1, 0), TextColor3 = Theme.Accent })
	nextButton:SetAttribute("ClickSound", "TutorialPage")
	backButton:SetAttribute("ClickSound", "TutorialPage")

	-- Tip card for in-case hints.
	tipGui = UI.screen("DeadAirTips", 15, playerGui)
	local card = UI.panel(tipGui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 200),
		Size = UDim2.fromOffset(440, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
	})
	UI.padding(card, 12, 8)
	UI.list(card, 2)
	UI.text(card, "TIP", { FontFace = Theme.FontBold, TextSize = Theme.SmallText, TextColor3 = Theme.Amber, LayoutOrder = 1 })
	tipText = UI.text(card, "", { AutomaticSize = Enum.AutomaticSize.Y, TextSize = Theme.SmallText, LayoutOrder = 2 })
	TutorialController._tipCard = card
end

---------------------------------------------------------------------------
-- One-time tips during a case
---------------------------------------------------------------------------

local tipToken = 0

function TutorialController.tip(id, text)
	if tipsShown[id] or not State.settings.tips then
		return false
	end
	tipsShown[id] = true
	tipToken += 1
	local token = tipToken
	tipText.Text = text
	TutorialController._tipCard.Visible = true
	task.delay(7, function()
		if token == tipToken then
			TutorialController._tipCard.Visible = false
		end
	end)
	return true
end

local function firstCase()
	local p = State.profile
	local stats = p and p.cases and p.cases.case01
	return not stats or (stats.runs or 0) < 2
end

local function checkTips()
	if not State.inMission() then
		TutorialController._tipCard.Visible = false
		return
	end
	if not State.isAlive() or not firstCase() then
		return
	end
	local m = State.mission
	if m.phase == "Briefing" or m.phase == "Active" then
		TutorialController.tip("objective", "Your objective is at the top left. Listen to the radio: it tells you where to look.")
	end
	for itemId in m.inventory or {} do
		local caseDef = State.caseDef()
		local item = caseDef and caseDef.items[itemId]
		if item and item.kind == "Tape" then
			TutorialController.tip("tape", string.format("Tape recovered. Stand at a tape deck and press %s to see what happens next.", Controls.tag("Deck")))
		end
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local station = Workspace:FindFirstChild("Station04")
		local roomId = MapLayout.roomAt(root.Position.X, root.Position.Z)
		local folder = station and roomId and station.Rooms:FindFirstChild(roomId)
		local mode = folder and folder:GetAttribute("LightMode")
		if mode == "off" or mode == "emergency" then
			TutorialController.tip("dark", string.format("It is dark in here. Press %s for your flashlight.", Controls.tag("Flashlight")))
		end
	end
	local presenter = Workspace:FindFirstChild("Presenter")
	if presenter and presenter:GetAttribute("State") == "Hunting" then
		TutorialController.tip("hunt", "IT IS HUNTING. Break line of sight and keep moving. Doors slow it down.")
	end
end

function TutorialController.init(playerGui)
	build(playerGui)
	local offered = false
	local function maybeStart(profile)
		if offered or not profile then
			return
		end
		offered = true
		if not profile.tutorialSeen and not State.inMission() then
			task.delay(0.5, TutorialController.start)
		end
	end
	State.profileChanged:Connect(maybeStart)
	maybeStart(State.profile)
	State.cue:Connect(function(cue)
		if cue.cue == "OpenTutorial" then
			TutorialController.start()
		end
	end)
	-- Deploying into a case closes the walkthrough (it can be replayed later).
	State.missionChanged:Connect(function()
		if open and State.inMission() then
			finish()
		end
	end)
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum >= 0.5 then
			accum = 0
			checkTips()
		end
	end)
end

return TutorialController
