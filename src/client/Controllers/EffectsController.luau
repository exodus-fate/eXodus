--[[
	EffectsController — presentation only. Nothing here changes gameplay; every
	effect scales with the distortion / flicker / camera-shake / low-intensity
	settings so players can tone it down without losing information.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CaseRegistry = require(Shared.Config.CaseRegistry)
local MapLayout = require(Shared.Config.MapLayout)
local Figures = require(Shared.World.Figures)

local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local FootageView = require(script.Parent.Parent.UI.FootageView)

local EffectsController = {}

local rng = Random.new()
local gui, staticFrame, staticDots, staticText
local grade, blur
local staticUntil, staticStrength = 0, 0
local ghostFolder
local loopLastCycle = nil

local function presenter()
	local model = Workspace:FindFirstChild("Presenter")
	if model and model:IsA("Model") and model.PrimaryPart then
		return model
	end
	return nil
end

local function myRoot()
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

---------------------------------------------------------------------------
-- Static bursts
---------------------------------------------------------------------------

function EffectsController.static(duration, strength, text)
	local scale = State.intensity("distortion")
	if scale <= 0 and not text then
		return
	end
	staticUntil = math.max(staticUntil, os.clock() + duration)
	staticStrength = math.max(staticStrength, strength * math.max(scale, text and 0.3 or 0))
	staticText.Text = text or ""
end

local function stepStatic()
	local now = os.clock()
	local active = now < staticUntil
	staticFrame.Visible = active
	if not active then
		staticStrength = 0
		staticText.Text = ""
		return
	end
	staticFrame.BackgroundTransparency = 1 - staticStrength * 0.35
	for _, dot in staticDots do
		if rng:NextNumber() < staticStrength then
			dot.BackgroundTransparency = 0.2 + rng:NextNumber() * 0.6
			dot.Size = UDim2.new(rng:NextNumber() * 0.3, 0, 0, rng:NextInteger(1, 4))
			dot.Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber())
		else
			dot.BackgroundTransparency = 1
		end
	end
end

---------------------------------------------------------------------------
-- Presenter face static
---------------------------------------------------------------------------

local faceCells = {}

local function stepPresenterFace()
	local model = presenter()
	if not model then
		return
	end
	local gui3d = model:FindFirstChild("Static", true)
	if not gui3d or not gui3d:IsA("SurfaceGui") then
		return
	end
	local cells = faceCells[gui3d]
	if not cells then
		cells = {}
		for y = 0, 5 do
			for x = 0, 7 do
				table.insert(cells, UI.new("Frame", {
					BorderSizePixel = 0,
					Position = UDim2.fromScale(x / 8, y / 6),
					Size = UDim2.fromScale(1 / 8, 1 / 6),
					Parent = gui3d,
				}))
			end
		end
		faceCells = { [gui3d] = cells }
	end
	local root = myRoot()
	if root and (root.Position - model.PrimaryPart.Position).Magnitude > 90 then
		return
	end
	local hunting = model:GetAttribute("State") == "Hunting"
	for _, cell in cells do
		local v = rng:NextNumber()
		local bright = hunting and (0.5 + v * 0.5) or (0.25 + v * 0.6)
		cell.BackgroundColor3 = Color3.new(bright, bright, bright * 1.02)
		cell.BackgroundTransparency = rng:NextNumber() * 0.3
	end
end

---------------------------------------------------------------------------
-- Fluorescent flicker (local only; the server owns whether a light is on)
---------------------------------------------------------------------------

local flickering = {}

local function stepFlicker()
	local flicker = State.intensity("flicker")
	local station = Workspace:FindFirstChild("Station04")
	local root = myRoot()
	if flicker <= 0 or not station or not root then
		return
	end
	local roomId = MapLayout.roomAt(root.Position.X, root.Position.Z)
	local roomFolder = roomId and station.Rooms:FindFirstChild(roomId)
	if not roomFolder or roomFolder:GetAttribute("LightMode") ~= "on" then
		return
	end
	local model = presenter()
	local near = model and (model.PrimaryPart.Position - root.Position).Magnitude < 28
	local chance = (near and 0.25 or 0.012) * flicker
	if rng:NextNumber() > chance then
		return
	end
	local lights = roomFolder:FindFirstChild("Lights")
	if not lights then
		return
	end
	local fixtures = {}
	for _, p in lights:GetChildren() do
		if p:GetAttribute("LightKind") == "Fluorescent" then
			table.insert(fixtures, p)
		end
	end
	if #fixtures == 0 then
		return
	end
	local fixture = fixtures[rng:NextInteger(1, #fixtures)]
	if flickering[fixture] then
		return
	end
	flickering[fixture] = true
	local light = fixture:FindFirstChildWhichIsA("Light")
	task.spawn(function()
		for _ = 1, rng:NextInteger(2, 5) do
			if light then
				light.Enabled = false
			end
			fixture.Transparency = 0.6
			task.wait(0.04 + rng:NextNumber() * 0.08)
			if roomFolder:GetAttribute("LightMode") == "on" then
				if light then
					light.Enabled = true
				end
			end
			fixture.Transparency = 0
			task.wait(0.05 + rng:NextNumber() * 0.12)
		end
		flickering[fixture] = nil
	end)
end

---------------------------------------------------------------------------
-- Hunt grading
---------------------------------------------------------------------------

local function stepGrade(dt)
	local model = presenter()
	local root = myRoot()
	local danger = 0
	if model and root then
		local d = (model.PrimaryPart.Position - root.Position).Magnitude
		danger = math.clamp(1 - d / 50, 0, 1)
		if model:GetAttribute("State") == "Hunting" then
			danger = math.max(danger, 0.5)
		end
	end
	local scale = State.intensity("distortion")
	local targetSat = -danger * 0.45 * scale
	local targetBlur = danger > 0.6 and (danger - 0.6) * 6 * scale or 0
	grade.Saturation += (targetSat - grade.Saturation) * math.min(1, dt * 3)
	grade.Contrast = danger * 0.15 * scale
	blur.Size += (targetBlur - blur.Size) * math.min(1, dt * 3)
end

---------------------------------------------------------------------------
-- The Loop's props
---------------------------------------------------------------------------

local function setVariant(container, visible)
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = visible and (d:GetAttribute("BaseTransparency") or 0) or 1
		elseif d:IsA("SurfaceGui") or d:IsA("Light") then
			d.Enabled = visible
		end
	end
end

local function stepLoop()
	local m = State.mission
	local station = Workspace:FindFirstChild("Station04")
	local props = station and station:FindFirstChild("LoopProps")
	if not props then
		return
	end
	local loop = m and m.loop
	local odd = false
	local cycle = nil
	if loop and loop.active then
		local elapsed = State.now() - loop.cycleStart
		cycle = math.floor(elapsed / loop.cycleLength) + 1
		odd = cycle % 2 == 0
		if cycle ~= loopLastCycle then
			loopLastCycle = cycle
			EffectsController.static(0.35, 0.8)
			local caseDef = State.caseDef()
			for _, beat in (caseDef and caseDef.loop.beats) or {} do
				task.delay(beat.at, function()
					local still = State.mission and State.mission.loop and State.mission.loop.active
					if still and loopLastCycle == cycle then
						State.subtitle:Fire({ kind = "cue", text = beat.text })
					end
				end)
			end
		end
	else
		loopLastCycle = nil
	end
	for _, model in props:GetChildren() do
		local showOdd = odd and loop and loop.odd == model.Name
		local normal = model:FindFirstChild("Normal")
		local oddModel = model:FindFirstChild("Odd")
		if normal then
			setVariant(normal, not showOdd)
		end
		if oddModel then
			setVariant(oddModel, showOdd)
		end
	end
end

---------------------------------------------------------------------------
-- Rewind ghosts
---------------------------------------------------------------------------

local function playGhosts(payload)
	if not ghostFolder then
		ghostFolder = Instance.new("Folder")
		ghostFolder.Name = "DeadAirGhosts"
		ghostFolder.Parent = Workspace
	end
	for _, track in payload.tracks or {} do
		local model = Figures.investigator(ghostFolder, Color3.fromRGB(150, 170, 160))
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Transparency = 0.65
				d.Material = Enum.Material.ForceField
			end
		end
		local samples = track.samples
		local start = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local t = os.clock() - start
			if t > (payload.duration or 30) or model.Parent == nil then
				conn:Disconnect()
				model:Destroy()
				return
			end
			local a, b = samples[1], samples[#samples]
			for i = 1, #samples - 1 do
				if samples[i][1] <= t and samples[i + 1][1] > t then
					a, b = samples[i], samples[i + 1]
					break
				end
			end
			local span = math.max(0.001, b[1] - a[1])
			local alpha = math.clamp((t - a[1]) / span, 0, 1)
			local x = a[2] + (b[2] - a[2]) * alpha
			local z = a[3] + (b[3] - a[3]) * alpha
			local look = Vector3.new(a[4], 0, a[5])
			if look.Magnitude < 0.1 then
				look = Vector3.new(0, 0, -1)
			end
			local at = Vector3.new(x, Figures.rootHeight(model), z)
			model:PivotTo(CFrame.lookAt(at, at + look))
		end)
	end
	EffectsController.static(0.6, 0.7)
end

---------------------------------------------------------------------------
-- False safety (extraction) and going off-air
---------------------------------------------------------------------------

local falseSafety

local function playFalseSafety()
	local root = myRoot()
	local lastPos = root and root.Position or Vector3.new(0, 0, -100)
	local overlay = UI.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 20, Parent = gui })
	falseSafety = overlay
	TweenService:Create(overlay, TweenInfo.new(1.2), { BackgroundTransparency = 0 }):Play()
	State.cue:Fire({ cue = "LocalSilence", duration = 6 })
	task.delay(1.6, function()
		if overlay.Parent == nil then
			return
		end
		local holder = UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromScale(0.42, 0.42),
			BackgroundTransparency = 1,
			ZIndex = 21,
			Parent = overlay,
		})
		UI.new("UIAspectRatioConstraint", { AspectRatio = 4 / 3, Parent = holder })
		local view = FootageView.new(holder)
		view:setCamera("CAM11")
		view:setLights("on")
		-- It shows you still inside.
		local inside = MapLayout.point("Transmitter", 0.45, 0.8)
		view:setActors({ { kind = "Investigator", pos = inside, look = { x = lastPos.X, y = 0, z = lastPos.Z } } })
		view:setTexts({ timestamp = "REC", status = "CAM 11 · LIVE", message = "" })
		local conn
		conn = RunService.RenderStepped:Connect(function(dt)
			view:setSignal(70, math.max(0.3, State.intensity("distortion")))
			view:step(dt)
		end)
		task.delay(3.4, function()
			conn:Disconnect()
			view:setTexts({ message = "END OF TRANSMISSION" })
			view:setActors({})
			task.delay(1.5, function()
				TweenService:Create(overlay, TweenInfo.new(1), { BackgroundTransparency = 1 }):Play()
				task.delay(1.1, function()
					overlay:Destroy()
				end)
			end)
		end)
	end)
end

local function onCue(cue)
	local name = cue.cue
	local me = Players.LocalPlayer.UserId
	if name == "Eliminated" then
		if cue.userId == me then
			EffectsController.static(3, 1, "SIGNAL LOST")
		else
			EffectsController.static(0.4, 0.5)
		end
	elseif name == "LightsFail" then
		EffectsController.static(0.25, 0.5)
	elseif name == "LoopStart" or name == "LoopBreak" or name == "LoopReset" then
		EffectsController.static(0.5, 0.9)
	elseif name == "PresenterAppear" then
		local model = presenter()
		local root = myRoot()
		if model and root and (model.PrimaryPart.Position - root.Position).Magnitude < 45 then
			EffectsController.static(0.25, 0.6)
		end
	elseif name == "HuntStart" then
		EffectsController.static(0.35, 0.7)
	elseif name == "EditCommitted" or name == "LocalEditCommitted" then
		EffectsController.static(0.3, 0.5)
	elseif name == "Extracted" then
		playFalseSafety()
	elseif name == "Revived" then
		EffectsController.static(1, 0.8, "RE-ENTRY · SIGNAL RESTORED")
	elseif name == "ReplayBriefing" then
		local caseDef = State.caseDef() or CaseRegistry.get("case01")
		for i, line in caseDef.briefing.lines do
			task.delay((i - 1) * 4, function()
				State.subtitle:Fire({ kind = "radio", stamp = "REPLAY", sourceId = "NBRD-HQ", channel = 2, text = line.text })
			end)
		end
	elseif name == "EditorShadow" and cue.userId == me then
		State.subtitle:Fire({ kind = "cue", text = "[ON THE RECEPTION MONITOR, SOMETHING STANDS BEHIND YOU]" })
	elseif name == "BroadcastStart" then
		EffectsController.static(0.6, 0.6)
	end
end

function EffectsController.init(playerGui)
	gui = UI.screen("DeadAirOverlay", 40, playerGui)
	staticFrame = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(30, 34, 30), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false, Parent = gui })
	staticDots = {}
	for i = 1, 60 do
		staticDots[i] = UI.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, BackgroundTransparency = 1, Parent = staticFrame })
	end
	staticText = UI.text(staticFrame, "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, 60),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.FontTitle,
		TextSize = 40,
		TextColor3 = Theme.Cream,
		TextStrokeTransparency = 0.4,
		ZIndex = 3,
	})

	grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "DeadAirHuntGrade"
	grade.Parent = Lighting
	blur = Instance.new("BlurEffect")
	blur.Name = "DeadAirHuntBlur"
	blur.Size = 0
	blur.Parent = Lighting

	State.cue:Connect(onCue)
	State.ghosts:Connect(playGhosts)
	State.missionChanged:Connect(function(m)
		if not m and ghostFolder then
			ghostFolder:ClearAllChildren()
		end
	end)

	local accum = 0
	RunService.RenderStepped:Connect(function(dt)
		stepStatic()
		stepGrade(dt)
		accum += dt
		if accum >= 0.08 then
			accum = 0
			stepPresenterFace()
			stepFlicker()
			stepLoop()
		end
	end)
	EffectsController.falseSafety = function()
		return falseSafety
	end
end

return EffectsController
