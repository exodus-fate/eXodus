--[[
	CameraController — how the first-person view feels. Presentation only.

	  Head bob     The view rises and falls with each step (up, down, up, down),
	               with a small sideways sway and roll. Sprinting bobs harder;
	               stopping settles the camera back smoothly.
	  Tension      One 0..1 value that builds while the Presenter is close,
	               hunting or in view, while the lights are out, while the Loop
	               runs and as the broadcast clock runs down. It rises fast and
	               drains slowly, so dread lingers after a close call.
	  From tension The vignette closes in and pulses like a heartbeat, the field
	               of view narrows a few degrees, the head drifts with uneven
	               breathing, and turning the camera smears with motion blur.
	  Shake        Short bursts from cues (hunts, lights failing).

	Every effect has its own setting (head bob, motion blur, vignette, camera
	shake, field of view) and low intensity mode scales them all down. The
	camera's own scripts own position and rotation; this controller only adds a
	local offset and roll after them each frame, and roll never changes the
	look direction, so nothing drifts.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapLayout = require(Shared.Config.MapLayout)

local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI.UI)

local CameraController = {}

local INSPECT_FOV = 40
local WALK_REFERENCE = 12 -- studs/s: the walk speed the bob is tuned for
local BOB_HEIGHT = 0.11 -- studs, at walking pace
local BOB_SWAY = 0.06
local BOB_ROLL = math.rad(0.6)
local STEP_LENGTH = 3.1 -- studs per footstep

CameraController.tension = 0
CameraController.inspecting = false
CameraController.onFootstep = nil -- optional callback(sprinting)

local gui, vignetteEdges, pulse
local blur, focus
local phase = 0
local bobAmount = 0
local lastStepSign = 1
local shake = 0
local breathT = 0
local lastLook = nil
local turnBlur = 0
local tensionTarget = 0
local sightCheckAt = 0
local inSight = false
local heartbeat = 0

local function myHumanoid()
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function presenter()
	local model = Workspace:FindFirstChild("Presenter")
	if model and model:IsA("Model") and model.PrimaryPart then
		return model
	end
	return nil
end

function CameraController.shake(amount)
	shake = math.max(shake, amount * State.intensity("cameraShake"))
end

---------------------------------------------------------------------------
-- Tension
---------------------------------------------------------------------------

local function roomLightMode(position)
	local station = Workspace:FindFirstChild("Station04")
	local roomId = MapLayout.roomAt(position.X, position.Z)
	local rooms = station and station:FindFirstChild("Rooms")
	local folder = roomId and rooms and rooms:FindFirstChild(roomId)
	return folder and folder:GetAttribute("LightMode")
end

local function computeTension(camera, root)
	if not State.inMission() or not State.isAlive() or not root then
		return 0
	end
	local t = 0
	local model = presenter()
	if model then
		local offset = model.PrimaryPart.Position - root.Position
		local distance = offset.Magnitude
		t = math.max(t, math.clamp(1 - distance / 60, 0, 1) * 0.85)
		if model:GetAttribute("State") == "Hunting" then
			t = math.max(t, 0.55 + math.clamp(1 - distance / 40, 0, 1) * 0.45)
		end
		-- Seeing it on screen spikes tension (checked a few times a second).
		local now = os.clock()
		if now >= sightCheckAt then
			sightCheckAt = now + 0.25
			inSight = false
			if distance < 70 and offset.Magnitude > 0.1 and camera.CFrame.LookVector:Dot(offset.Unit) > 0.55 then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { Players.LocalPlayer.Character, model }
				inSight = Workspace:Raycast(camera.CFrame.Position, model.PrimaryPart.Position - camera.CFrame.Position, params) == nil
			end
		end
		if inSight then
			t = math.max(t, 0.5) + 0.25
		end
	end
	local light = roomLightMode(root.Position)
	if light == "off" then
		t += 0.22
	elseif light == "emergency" then
		t += 0.1
	end
	local m = State.mission
	if m and m.loop and m.loop.active then
		t += 0.15
	end
	if m and m.timeLimit and m.broadcastStart then
		local progress = math.clamp(State.broadcastClock() / m.timeLimit, 0, 1)
		t += progress * progress * 0.18
	end
	return math.clamp(t, 0, 1)
end

---------------------------------------------------------------------------
-- Vignette: four soft edges (no image assets); corners darken where they meet
---------------------------------------------------------------------------

local function buildVignette(playerGui)
	-- Below every other screen so it never darkens the HUD text.
	gui = UI.screen("DeadAirVignette", 1, playerGui)
	vignetteEdges = {}
	local function edge(rotation, size, position, anchor)
		local frame = UI.new("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			AnchorPoint = anchor,
			Position = position,
			Size = size,
			Parent = gui,
		})
		local gradient = UI.new("UIGradient", { Rotation = rotation, Parent = frame })
		table.insert(vignetteEdges, { frame = frame, gradient = gradient })
	end
	-- Each gradient runs from the screen edge (dark) towards the centre (clear).
	edge(90, UDim2.fromScale(1, 0.42), UDim2.fromScale(0, 0), Vector2.new(0, 0)) -- top
	edge(-90, UDim2.fromScale(1, 0.42), UDim2.fromScale(0, 1), Vector2.new(0, 1)) -- bottom
	edge(0, UDim2.fromScale(0.3, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0)) -- left
	edge(180, UDim2.fromScale(0.3, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0)) -- right
end

local function setVignette(strength)
	-- strength 0..1: how dark the very edge gets.
	local edgeAlpha = 1 - math.clamp(strength, 0, 0.95)
	local sequence = NumberSequence.new({
		NumberSequenceKeypoint.new(0, edgeAlpha),
		NumberSequenceKeypoint.new(0.45, 1 - (1 - edgeAlpha) * 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	for _, e in vignetteEdges do
		e.gradient.Transparency = sequence
		e.frame.Visible = strength > 0.01
	end
end

---------------------------------------------------------------------------
-- Per frame
---------------------------------------------------------------------------

local function ownView(camera, humanoid)
	return camera.CameraType == Enum.CameraType.Custom and humanoid ~= nil and camera.CameraSubject == humanoid
end

local function step(dt)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	dt = math.min(dt, 0.1)
	local humanoid = myHumanoid()
	local root = humanoid and humanoid.Parent and humanoid.Parent:FindFirstChild("HumanoidRootPart")
	local own = ownView(camera, humanoid)
	local settings = State.settings

	-- Tension rises quickly and drains slowly.
	tensionTarget = own and computeTension(camera, root) or 0
	local rate = tensionTarget > CameraController.tension and 1.6 or 0.22
	CameraController.tension += (tensionTarget - CameraController.tension) * math.min(1, dt * rate)
	local tension = CameraController.tension
	State.tension = tension

	-- Field of view: the setting, narrowed slightly by tension; inspect zooms.
	if camera.CameraType == Enum.CameraType.Custom then
		local base = settings.fieldOfView or 70
		local fov = CameraController.inspecting and INSPECT_FOV or (base - tension * 5 * State.intensity("distortion"))
		if math.abs(camera.FieldOfView - fov) > 0.05 then
			camera.FieldOfView += (fov - camera.FieldOfView) * math.min(1, dt * 8)
		end
	end

	-- Motion blur from how fast the view turns, stronger under tension.
	local look = camera.CFrame.LookVector
	local turnRate = 0
	if lastLook then
		local cos = math.clamp(lastLook:Dot(look), -1, 1)
		turnRate = math.acos(cos) / math.max(dt, 1 / 240) -- radians per second
	end
	lastLook = look
	local blurSetting = State.intensity("motionBlur")
	local wanted = 0
	if own and blurSetting > 0 then
		wanted = math.clamp((turnRate - 1.5) * 1.2, 0, 6) * (0.6 + tension * 0.8) * blurSetting
		wanted += tension * tension * 1.5 * State.intensity("distortion")
	end
	turnBlur += (wanted - turnBlur) * math.min(1, dt * (wanted > turnBlur and 14 or 6))
	blur.Size = turnBlur
	-- Under tension the far end of the room goes soft: the world closes in.
	focus.FarIntensity = own and math.clamp(tension * 0.35 * State.intensity("distortion"), 0, 0.35) or 0

	-- Vignette: always slightly on, darker and pulsing as tension builds.
	local vig = State.intensity("vignette")
	heartbeat += dt * (1.1 + tension * 1.4)
	local beat = math.max(0, math.sin(heartbeat * math.pi * 2)) ^ 6
	local pulseAmount = tension > 0.45 and beat * (tension - 0.45) * 0.5 or 0
	pulse = (0.28 + tension * 0.42 + pulseAmount) * vig
	setVignette(own and pulse or 0.25 * vig)

	if not own then
		bobAmount = 0
		return
	end

	-- Head bob, phase-locked to distance travelled so it matches the steps.
	local velocity = root and root.AssemblyLinearVelocity or Vector3.zero
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local moving = grounded and speed > 1 and humanoid.MoveDirection.Magnitude > 0.05
	local bobSetting = State.intensity("headBob")
	local targetAmount = moving and math.clamp(speed / WALK_REFERENCE, 0.4, 1.7) or 0
	bobAmount += (targetAmount - bobAmount) * math.min(1, dt * (moving and 6 or 4))
	if moving then
		phase += (speed * dt) / STEP_LENGTH * math.pi
		local sign = math.sin(phase) >= 0 and 1 or -1
		if sign ~= lastStepSign then
			lastStepSign = sign
			if CameraController.onFootstep then
				CameraController.onFootstep(speed > WALK_REFERENCE + 2)
			end
		end
	end
	local amount = bobAmount * bobSetting
	-- |sin| gives one dip per footstep: up, down, up, down.
	local bobY = (math.abs(math.sin(phase)) - 0.5) * 2 * BOB_HEIGHT * amount
	local swayX = math.sin(phase) * BOB_SWAY * amount
	local roll = math.sin(phase) * BOB_ROLL * amount

	-- Uneven breathing drift, mostly felt when standing still and tense.
	breathT += dt
	local breath = (0.25 + tension * 0.9) * bobSetting
	local breathY = (math.sin(breathT * 1.7) + math.sin(breathT * 2.9) * 0.35) * 0.018 * breath
	local breathRoll = math.sin(breathT * 0.9) * math.rad(0.25) * breath

	local shakeX, shakeY = 0, 0
	if shake > 0.001 then
		shakeX = (math.random() - 0.5) * shake
		shakeY = (math.random() - 0.5) * shake
		shake = math.max(0, shake - dt * 1.5)
	end
	-- High tension adds a faint tremor.
	local tremor = tension > 0.7 and (tension - 0.7) * 0.03 * State.intensity("cameraShake") or 0
	shakeX += (math.random() - 0.5) * tremor
	shakeY += (math.random() - 0.5) * tremor

	camera.CFrame = camera.CFrame * CFrame.new(swayX + shakeX, bobY + breathY + shakeY, 0) * CFrame.Angles(0, 0, roll + breathRoll)
end

function CameraController.init(playerGui)
	State.tension = 0
	buildVignette(playerGui)
	setVignette(0.25)
	blur = Instance.new("BlurEffect")
	blur.Name = "DeadAirMotionBlur"
	blur.Size = 0
	blur.Parent = Lighting
	focus = Instance.new("DepthOfFieldEffect")
	focus.Name = "DeadAirTensionFocus"
	focus.FarIntensity = 0
	focus.NearIntensity = 0
	focus.FocusDistance = 18
	focus.InFocusRadius = 22
	focus.Parent = Lighting
	-- After the default camera scripts have placed the camera this frame.
	RunService:BindToRenderStep("DeadAirCameraFeel", Enum.RenderPriority.Camera.Value + 1, step)
end

return CameraController
