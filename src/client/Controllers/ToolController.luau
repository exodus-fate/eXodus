--[[
	ToolController — the equipped tool (chosen in the field office):

	Camcorder  [1] night-vision viewfinder with REC overlay; filming the Presenter
	           sends a "RecordAnomaly" the server validates for research.
	Analyser   [1] large signal readout with the bearing of the strongest
	           interference.
	Recorder   [1] the full radio log with channel and timestamp, beside the live
	           clock - for telling Division from the Caller.
	Monitor    [1] opens the handheld live CCTV monitor (view-only).

	Tools change how evidence is gathered, never whether a case can be won.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local Format = require(Shared.Util.Format)

local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local HUDController = require(script.Parent.HUDController)

local ToolController = {}

local gui, viewfinder, vfLabel, vfFrame, analyser, analyserText, analyserArrow, recorder, recorderText
local nightVision
local active = false
local lastRecord = 0
local DeckController

local function equipment()
	return State.profile and State.profile.equipment or "Camcorder"
end

local function presenterRoot()
	local model = Workspace:FindFirstChild("Presenter")
	return model and model:IsA("Model") and model.PrimaryPart or nil
end

local function setActive(on)
	active = on
	local kind = equipment()
	viewfinder.Visible = on and kind == "Camcorder"
	analyser.Visible = on and kind == "Analyser"
	recorder.Visible = on and kind == "Recorder"
	nightVision.Enabled = on and kind == "Camcorder"
end

function ToolController.toggle()
	local kind = equipment()
	if kind == "Monitor" then
		if DeckController.isOpen() then
			DeckController.close()
		elseif State.inMission() and State.isAlive() then
			DeckController.open({ mode = "handheld" })
		end
		return
	end
	setActive(not active)
end

local function stepCamcorder()
	local skin = State.profile and State.profile.equipped and Cosmetics.Items[State.profile.equipped.camcorder]
	local recStyle = State.profile and State.profile.equipped and Cosmetics.Items[State.profile.equipped.rec]
	if skin and skin.colour then
		vfFrame.Color = Color3.fromRGB(skin.colour[1], skin.colour[2], skin.colour[3])
	end
	local style = recStyle and recStyle.style or "standard"
	local clock = Format.clock(State.broadcastClock())
	if style == "minimal" then
		vfLabel.Text = "REC " .. clock
	elseif style == "classic" then
		vfLabel.Text = "REC  SP  " .. clock .. "  CH-0"
	else
		vfLabel.Text = "REC  " .. clock .. "  BATT |||"
	end
	-- Evidence: the Presenter on screen and close enough to matter.
	local root = presenterRoot()
	local camera = Workspace.CurrentCamera
	if root and camera and State.inMission() and State.isAlive() and os.clock() - lastRecord > 5 then
		local screenPos, onScreen = camera:WorldToViewportPoint(root.Position + Vector3.new(0, 2, 0))
		local distance = (camera.CFrame.Position - root.Position).Magnitude
		if onScreen and screenPos.Z > 0 and distance < 55 then
			lastRecord = os.clock()
			State.action("RecordAnomaly")
		end
	end
end

local function stepAnalyser()
	local signal = State.player:GetAttribute("Signal") or 100
	local root = presenterRoot()
	local character = Players.LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local bearing = "NO INTERFERENCE"
	analyserArrow.Visible = false
	if root and hrp then
		local delta = root.Position - hrp.Position
		if delta.Magnitude < 80 then
			local look = hrp.CFrame.LookVector
			local angle = math.deg(math.atan2(delta.X, delta.Z) - math.atan2(look.X, look.Z))
			angle = (angle + 540) % 360 - 180
			analyserArrow.Visible = true
			analyserArrow.Rotation = -angle
			bearing = string.format("INTERFERENCE · %d STUDS", math.floor(delta.Magnitude))
		end
	end
	analyserText.Text = string.format("SIGNAL %d%%\n%s", signal, bearing)
end

local function stepRecorder()
	local m = State.mission
	local lines = { "LIVE CLOCK " .. Format.clock(State.broadcastClock()), "" }
	for _, entry in (m and m.radioLog) or {} do
		table.insert(lines, string.format("[%s] %s · CH%d", entry.stamp, entry.sourceId, entry.channel))
		table.insert(lines, "   " .. entry.text)
	end
	recorderText.Text = table.concat(lines, "\n")
end

function ToolController.init(playerGui, deckController)
	DeckController = deckController
	gui = UI.screen("DeadAirTool", 4, playerGui)

	viewfinder = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = gui })
	local inner = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.86, 0.8), Parent = viewfinder })
	vfFrame = UI.stroke(inner, Theme.Cream, 2, 0.2)
	vfLabel = UI.text(inner, "", { Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(1, -24, 0, 22), TextColor3 = Theme.Text, TextStrokeTransparency = 0.4, FontFace = Theme.FontBold })

	analyser = UI.panel(gui, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.55, 0), Size = UDim2.fromOffset(220, 160), Visible = false })
	UI.padding(analyser, 10)
	analyserText = UI.text(analyser, "", { Size = UDim2.new(1, 0, 0, 50), FontFace = Theme.FontBold, TextColor3 = Theme.Accent })
	analyserArrow = UI.new("Frame", { BackgroundColor3 = Theme.Amber, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(6, 60), Parent = analyser })

	recorder = UI.panel(gui, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.55, 0), Size = UDim2.fromOffset(420, 300), Visible = false })
	UI.padding(recorder, 10)
	recorderText = UI.text(recorder, "", { Size = UDim2.fromScale(1, 1), TextYAlignment = Enum.TextYAlignment.Top, TextSize = Theme.SmallText, TextColor3 = Theme.Cream })

	nightVision = Instance.new("ColorCorrectionEffect")
	nightVision.Name = "DeadAirNightVision"
	nightVision.Brightness = 0.18
	nightVision.Contrast = 0.15
	nightVision.Saturation = -0.6
	nightVision.TintColor = Color3.fromRGB(170, 235, 175)
	nightVision.Enabled = false
	nightVision.Parent = Lighting

	State.profileChanged:Connect(function()
		HUDController.tool = equipment()
		if active then
			setActive(true)
		end
	end)
	State.missionChanged:Connect(function()
		if active and State.inMission() and not State.isAlive() then
			setActive(false)
		end
	end)
	HUDController.tool = equipment()

	local accum = 0
	RunService.RenderStepped:Connect(function(dt)
		accum += dt
		if not active or accum < 0.1 then
			return
		end
		accum = 0
		local kind = equipment()
		gui.Enabled = not State.ui.deck and not State.ui.menu
		if kind == "Camcorder" then
			stepCamcorder()
		elseif kind == "Analyser" then
			stepAnalyser()
		elseif kind == "Recorder" then
			stepRecorder()
		end
	end)
end

return ToolController
