--[[
	HUDController — the in-case heads-up display (layout from the brief):
	  top left      case name, objective, optional clue
	  top right     signal quality 0-100%
	  centre        crosshair
	  bottom left   edit charges
	  bottom centre active tool and control hint
	  bottom right  REC indicator, tape time, recording state
	Plus subtitles, the radio log, toasts and the team recovery vote.

	Danger is shown with signal flicker, timestamp jumps and an unexpected REC
	blink - never with red screen flashes alone - and scales with the player's
	distortion / low-intensity settings.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CaseRegistry = require(Shared.Config.CaseRegistry)
local ProfileSchema = require(Shared.Core.ProfileSchema)
local SignalModel = require(Shared.Core.SignalModel)
local Format = require(Shared.Util.Format)

local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)

local HUDController = {}

local gui
local w = {}
local subtitles = {}
local toasts = {}
local voteVisible = false
local rng = Random.new()

HUDController.tool = nil -- set by ToolController
HUDController.stamina = 1

local function presenter()
	local model = Workspace:FindFirstChild("Presenter")
	if model and model:IsA("Model") and model.PrimaryPart then
		return model
	end
	return nil
end

local function corner(parent, anchor, position, size)
	local frame = UI.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = anchor,
		Position = position,
		Size = size,
		Parent = parent,
	})
	return frame
end

local function shadowText(parent, text, props)
	local label = UI.text(parent, text, props)
	label.TextStrokeTransparency = 0.45
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	return label
end

local function build(playerGui)
	gui = UI.screen("DeadAirHUD", 5, playerGui)
	local safe = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	UI.padding(safe, 18, 14)

	-- Top left: case and objective
	local tl = corner(safe, Vector2.new(0, 0), UDim2.new(0, 0, 0, 30), UDim2.new(0.45, 0, 0, 160))
	UI.list(tl, 2)
	w.caseName = shadowText(tl, "", { TextColor3 = Theme.TextDim, TextSize = Theme.SmallText, LayoutOrder = 1 })
	w.objective = shadowText(tl, "", { TextColor3 = Theme.Text, TextSize = 18, Font = Theme.FontBold, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	w.clue = shadowText(tl, "", { TextColor3 = Theme.AccentDim, TextSize = Theme.SmallText, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 })
	w.optional = shadowText(tl, "", { TextColor3 = Theme.TextDim, TextSize = Theme.SmallText, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4 })

	-- Top right: signal
	local tr = corner(safe, Vector2.new(1, 0), UDim2.new(1, 0, 0, 30), UDim2.fromOffset(220, 60))
	w.signal = shadowText(tr, "SIGNAL 100%", { TextXAlignment = Enum.TextXAlignment.Right, Font = Theme.FontBold, TextSize = 20, Size = UDim2.new(1, 0, 0, 24) })
	local bar = UI.new("Frame", { BackgroundColor3 = Theme.PanelLight, BorderSizePixel = 0, Position = UDim2.new(0, 0, 0, 28), Size = UDim2.new(1, 0, 0, 6), Parent = tr })
	w.signalFill = UI.new("Frame", { BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = bar })
	w.signalBand = shadowText(tr, "", { TextXAlignment = Enum.TextXAlignment.Right, TextSize = Theme.SmallText, TextColor3 = Theme.TextDim, Position = UDim2.new(0, 0, 0, 36), Size = UDim2.new(1, 0, 0, 18) })

	-- Radio log (right, below signal)
	w.radio = corner(safe, Vector2.new(1, 0), UDim2.new(1, 0, 0, 110), UDim2.new(0.36, 0, 0, 170))
	UI.list(w.radio, 2)

	-- Centre crosshair
	w.crosshair = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = Theme.Text,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = gui,
	})
	UI.corner(w.crosshair, 2)

	-- Bottom left: charges
	local bl = corner(safe, Vector2.new(0, 1), UDim2.new(0, 0, 1, 0), UDim2.fromOffset(240, 56))
	w.chargesLabel = shadowText(bl, "EDIT CHARGES", { TextSize = Theme.SmallText, TextColor3 = Theme.TextDim, Size = UDim2.new(1, 0, 0, 18) })
	w.chargeRow = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 22), Size = UDim2.new(1, 0, 0, 24), Parent = bl })
	UI.list(w.chargeRow, 6, Enum.FillDirection.Horizontal)

	-- Bottom centre: tool, hint, stamina, subtitles
	local bc = corner(safe, Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, 0), UDim2.new(0.5, 0, 0, 220))
	w.subtitles = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 140), Parent = bc })
	UI.list(w.subtitles, 4, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center).VerticalAlignment = Enum.VerticalAlignment.Bottom
	w.tool = shadowText(bc, "", { TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.FontBold, Position = UDim2.new(0, 0, 1, -50), Size = UDim2.new(1, 0, 0, 20) })
	w.hint = shadowText(bc, "", { TextXAlignment = Enum.TextXAlignment.Center, TextSize = Theme.SmallText, TextColor3 = Theme.TextDim, Position = UDim2.new(0, 0, 1, -28), Size = UDim2.new(1, 0, 0, 18) })
	local stamina = UI.new("Frame", { BackgroundColor3 = Theme.PanelLight, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.fromOffset(160, 3), Parent = bc })
	w.staminaFill = UI.new("Frame", { BackgroundColor3 = Theme.Cream, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = stamina })
	w.staminaBar = stamina

	-- Bottom right: REC and tape time
	local br = corner(safe, Vector2.new(1, 1), UDim2.new(1, 0, 1, 0), UDim2.fromOffset(260, 56))
	w.recDot = UI.new("Frame", { BackgroundColor3 = Theme.Danger, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -150, 0, 6), Size = UDim2.fromOffset(12, 12), Parent = br })
	UI.corner(w.recDot, 6)
	w.rec = shadowText(br, "REC", { TextXAlignment = Enum.TextXAlignment.Right, Font = Theme.FontBold, TextSize = 20, Size = UDim2.new(1, 0, 0, 24) })
	w.recState = shadowText(br, "", { TextXAlignment = Enum.TextXAlignment.Right, TextSize = Theme.SmallText, TextColor3 = Theme.TextDim, Position = UDim2.new(0, 0, 0, 28), Size = UDim2.new(1, 0, 0, 18) })

	-- Toasts (top centre)
	w.toasts = corner(gui, Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 70), UDim2.new(0.5, 0, 0, 120))
	UI.list(w.toasts, 4, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center)

	-- Centre banner (phase changes)
	w.banner = shadowText(gui, "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.new(0.8, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.FontTitle,
		TextSize = 30,
		TextColor3 = Theme.Cream,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	-- Team recovery vote
	w.vote = UI.panel(gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.2, 0), Size = UDim2.fromOffset(380, 130), Visible = false })
	UI.padding(w.vote, 10)
	w.voteText = UI.text(w.vote, "", { Size = UDim2.new(1, 0, 0, 60), TextYAlignment = Enum.TextYAlignment.Top })
	UI.button(w.vote, "AGREE (Y)", function()
		HUDController.answerVote(true)
	end, { Position = UDim2.new(0, 0, 1, -44), Size = UDim2.new(0.48, 0, 0, 44) })
	UI.button(w.vote, "DECLINE (N)", function()
		HUDController.answerVote(false)
	end, { Position = UDim2.new(0.52, 0, 1, -44), Size = UDim2.new(0.48, 0, 0, 44) })
	w.voteModal = UI.modalUnlock(w.vote)
end

---------------------------------------------------------------------------
-- Subtitles, radio and toasts
---------------------------------------------------------------------------

local function formatRadio(line)
	return string.format("[%s] %s · CH%d: %s", line.stamp or "--:--:--", line.sourceId or "?", line.channel or 0, line.text)
end

function HUDController.subtitle(line)
	if not State.settings.subtitles and line.kind ~= "radio" then
		return
	end
	if not State.settings.subtitles and line.kind == "radio" and State.settings.radioLog then
		-- Radio is still readable in the log.
		return
	end
	local text = line.kind == "radio" and formatRadio(line) or line.text
	local label = UI.text(w.subtitles, text, {
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = line.kind == "radio" and Theme.Cream or Theme.Text,
		TextSize = 17,
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.45,
		BackgroundColor3 = Color3.new(0, 0, 0),
		LayoutOrder = math.floor(os.clock() * 100),
	})
	UI.padding(label, 8, 3)
	table.insert(subtitles, label)
	while #subtitles > 3 do
		table.remove(subtitles, 1):Destroy()
	end
	task.delay(line.kind == "radio" and 8 or 5, function()
		local index = table.find(subtitles, label)
		if index then
			table.remove(subtitles, index)
			label:Destroy()
		end
	end)
end

function HUDController.toast(text)
	local label = UI.text(w.toasts, text, {
		TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.25,
		BackgroundColor3 = Theme.Panel,
		TextColor3 = Theme.Text,
		LayoutOrder = math.floor(os.clock() * 100),
	})
	UI.padding(label, 10, 4)
	UI.stroke(label, Theme.Line)
	table.insert(toasts, label)
	while #toasts > 3 do
		table.remove(toasts, 1):Destroy()
	end
	task.delay(4.5, function()
		local index = table.find(toasts, label)
		if index then
			table.remove(toasts, index)
			label:Destroy()
		end
	end)
end

function HUDController.banner(text, seconds)
	w.banner.Text = text
	w.banner.TextTransparency = 0
	w.banner.TextStrokeTransparency = 0.5
	task.delay(seconds or 3, function()
		if w.banner.Text == text then
			w.banner.TextTransparency = 1
			w.banner.TextStrokeTransparency = 1
		end
	end)
end

local function refreshRadio(m)
	UI.clear(w.radio)
	if not m or not State.settings.radioLog then
		return
	end
	local log = m.radioLog or {}
	local first = math.max(1, #log - 3)
	for i = first, #log do
		local entry = log[i]
		UI.text(w.radio, formatRadio(entry), {
			TextXAlignment = Enum.TextXAlignment.Right,
			TextSize = Theme.SmallText,
			TextColor3 = Theme.Cream,
			AutomaticSize = Enum.AutomaticSize.Y,
			TextStrokeTransparency = 0.5,
			LayoutOrder = i,
		})
	end
end

---------------------------------------------------------------------------
-- Vote
---------------------------------------------------------------------------

function HUDController.answerVote(yes)
	State.action("TeamVoteReply", { yes = yes })
	voteVisible = false
	w.vote.Visible = false
end

---------------------------------------------------------------------------
-- Per-frame update
---------------------------------------------------------------------------

local function controlHint()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Tap prompts to interact · buttons on the right for tools"
	elseif #UserInputService:GetConnectedGamepads() > 0 and UserInputService.GamepadEnabled and not UserInputService.MouseEnabled then
		return "[X] Interact · [Y] Deck · [D-Up] Tool · [D-Down] Light · [L3] Sprint · [Select] Menu"
	end
	return "[E] Interact · [R] Deck · [1] Tool · [F] Flashlight · [Shift] Sprint · [RMB] Inspect · [Tab] Menu"
end

local function setCharges(m)
	UI.clear(w.chargeRow)
	for i = 1, m.maxCharges or 0 do
		local full = i <= (m.charges or 0)
		local box = UI.new("Frame", {
			BackgroundColor3 = full and Theme.Accent or Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(22, 22),
			LayoutOrder = i,
			Parent = w.chargeRow,
		})
		UI.stroke(box, Theme.Accent, 1, full and 0 or 0.4)
	end
	UI.text(w.chargeRow, string.format("%d / %d", m.charges or 0, m.maxCharges or 0), {
		Size = UDim2.fromOffset(60, 22),
		TextStrokeTransparency = 0.5,
		LayoutOrder = 99,
	})
end

local lastCharges = nil

local function onMission(m)
	if not m then
		w.caseName.Text = "NATIONAL BROADCAST RECOVERY DIVISION · FIELD OFFICE"
		w.objective.Text = "Walk to a terminal, or press [Tab] for the menu."
		w.clue.Text = ""
		w.optional.Text = ""
		UI.clear(w.chargeRow)
		w.chargesLabel.Visible = false
		lastCharges = nil
		refreshRadio(nil)
		return
	end
	local caseDef = CaseRegistry.get(m.caseId)
	w.chargesLabel.Visible = true
	w.caseName.Text = string.format("CASE %02d · %s · %s", caseDef.number, caseDef.title, m.modeLabel or "")
	if m.phase == "Briefing" then
		w.objective.Text = "Listen to the briefing. Take the tape from the reception desk."
	elseif m.objective then
		w.objective.Text = m.objective.text
	else
		w.objective.Text = ""
	end
	w.clue.Text = m.objective and m.objective.clue or ""
	w.optional.Text = table.concat(m.optional or {}, "\n")
	local key = tostring(m.charges) .. "/" .. tostring(m.maxCharges)
	if key ~= lastCharges then
		lastCharges = key
		setCharges(m)
	end
	refreshRadio(m)
	if m.vote and State.isAlive() and not voteVisible then
		voteVisible = true
		w.vote.Visible = true
		w.voteText.Text = string.format("%s asked Division for a TEAM RECOVERY.\nEveryone still inside must agree. (%d/%d)", m.vote.proposer, m.vote.yes, m.vote.needed)
	elseif not m.vote and voteVisible then
		voteVisible = false
		w.vote.Visible = false
	end
end

local function update()
	local m = State.mission
	local inCase = m ~= nil and State.inMission()
	gui.Enabled = not State.ui.menu and not State.ui.deck and not State.ui.report
	w.crosshair.Visible = inCase and State.isAlive()
	w.staminaBar.Visible = HUDController.stamina < 0.99
	w.staminaFill.Size = UDim2.fromScale(HUDController.stamina, 1)

	-- Signal meter and danger cues.
	local signal = State.player:GetAttribute("Signal") or 100
	local model = presenter()
	local hunting = model and model:GetAttribute("State") == "Hunting"
	local distortion = State.intensity("distortion")
	local flicker = State.intensity("flicker")
	local shown = signal
	if inCase and signal < 60 and flicker > 0 and rng:NextNumber() < 0.25 * flicker then
		shown = math.clamp(signal + rng:NextInteger(-12, 12), 0, 100)
	end
	w.signal.Text = string.format("SIGNAL %d%%", inCase and shown or 100)
	w.signalFill.Size = UDim2.fromScale((inCase and signal or 100) / 100, 1)
	local band = SignalModel.band(signal)
	w.signalFill.BackgroundColor3 = band == "CLEAR" and Theme.Accent or (band == "WEAK" and Theme.Amber or Theme.Danger)
	w.signalBand.Text = inCase and band or ""

	-- REC and tape clock.
	if inCase then
		local clock = State.broadcastClock()
		if hunting and distortion > 0 and rng:NextNumber() < 0.15 * distortion then
			clock += rng:NextInteger(-90, 90) -- timestamp jump
		end
		if m.phase == "Briefing" then
			w.rec.Text = "STBY 00:00:00"
			w.recState.Text = "PRE-BROADCAST"
		else
			w.rec.Text = "REC " .. Format.clock(clock)
			w.recState.Text = m.phase == "ExtractionAvailable" and "BROADCAST ENDING" or "BROADCAST LIVE"
		end
		local blink = (os.clock() % 1) < 0.5
		if model and model.PrimaryPart and distortion > 0 then
			local character = State.player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if hrp and (hrp.Position - model.PrimaryPart.Position).Magnitude < 30 then
				blink = rng:NextNumber() < 0.5 -- unexpected REC flicker
			end
		end
		w.recDot.Visible = blink
	else
		w.rec.Text = os.date("!%H:%M:%S")
		w.recState.Text = "FIELD OFFICE"
		w.recDot.Visible = false
	end

	local tool = HUDController.tool
	local toolLabel = tool and ProfileSchema.Equipment[tool] and ProfileSchema.Equipment[tool].label or ""
	w.tool.Text = toolLabel ~= "" and ("TOOL: " .. toolLabel) or ""
	w.hint.Text = controlHint()
end

function HUDController.init(playerGui)
	build(playerGui)
	onMission(State.mission)
	State.missionChanged:Connect(onMission)
	State.settingsChanged:Connect(function()
		onMission(State.mission)
	end)
	State.subtitle:Connect(HUDController.subtitle)
	State.notify:Connect(HUDController.toast)
	State.cue:Connect(function(cue)
		if cue.cue == "BroadcastStart" then
			HUDController.banner("THE BROADCAST HAS BEGUN", 3.5)
		elseif cue.cue == "PowerOn" then
			HUDController.banner("STATION POWER RESTORED", 2.5)
		elseif cue.cue == "TransmitterArmed" then
			HUDController.banner("TRANSMITTER ARMED", 2.5)
		elseif cue.cue == "TeamVote" then
			onMission(State.mission)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not voteVisible then
			return
		end
		if input.KeyCode == Enum.KeyCode.Y then
			HUDController.answerVote(true)
		elseif input.KeyCode == Enum.KeyCode.N then
			HUDController.answerVote(false)
		end
	end)
	local accum = 0
	RunService.RenderStepped:Connect(function(dt)
		accum += dt
		if accum >= 0.1 then
			accum = 0
			update()
		end
	end)
end

return HUDController
