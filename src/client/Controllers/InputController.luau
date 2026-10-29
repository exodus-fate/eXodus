--[[
	InputController — controls from the brief, on every device.

	Action        PC              Mobile             Controller
	Interact      E               tap prompt         X (ProximityPrompt)
	Equip tool    1               Tool button        D-pad up
	Open deck     R               Deck button        Y
	Sprint        Shift (hold)    Sprint button      Left-stick click
	Inspect       hold RMB        hold Inspect       hold L2
	Flashlight    F               Light button       D-pad down
	Menu          Tab / P         Menu button        Select
	(Esc stays the Roblox menu; Roblox reserves it.)
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local State = require(script.Parent.Parent.State)
local HUDController = require(script.Parent.HUDController)

local InputController = {}

local WALK_SPEED = 12
local SPRINT_SPEED = 19
local STAMINA_SECONDS = 6
local STAMINA_REGEN_DELAY = 1
local DEFAULT_FOV = 70
local INSPECT_FOV = 40

local sprinting = false
local stamina = 1
local lastSprintAt = 0
local flashlight = false
local inspecting = false
local shake = 0

InputController.onTool = nil -- set by ToolController
InputController.onDeck = nil -- set by Main
InputController.onMenu = nil -- set by Main

local function humanoid()
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function blocked()
	return State.anyModal()
end

-- Local beam that follows the camera (so it tilts with the view in first
-- person). Other players see the server's head-mounted light instead.
local beamPart, beam

local function ensureBeam()
	if beamPart then
		return
	end
	beamPart = Instance.new("Part")
	beamPart.Name = "DeadAirFlashlight"
	beamPart.Anchored = true
	beamPart.CanCollide = false
	beamPart.CanQuery = false
	beamPart.CanTouch = false
	beamPart.Transparency = 1
	beamPart.Size = Vector3.new(0.2, 0.2, 0.2)
	beamPart.Parent = Workspace
	beam = Instance.new("SpotLight")
	beam.Face = Enum.NormalId.Front
	beam.Angle = 55
	beam.Range = 38
	beam.Brightness = 2.2
	beam.Color = Color3.fromRGB(235, 230, 210)
	beam.Shadows = true
	beam.Enabled = false
	beam.Parent = beamPart
end

function InputController.setFlashlight(on)
	flashlight = on
	ensureBeam()
	beam.Enabled = on
	State.action("Flashlight", { on = on })
end

-- Keep our own copy of the server's head light off locally (no double beam).
local function muteOwnHeadLight(character)
	local head = character:WaitForChild("Head", 10)
	local light = head and head:WaitForChild("Flashlight", 10)
	if light then
		light.Enabled = false
		light:GetPropertyChangedSignal("Enabled"):Connect(function()
			if light.Enabled then
				light.Enabled = false
			end
		end)
	end
end

function InputController.shake(amount)
	shake = math.max(shake, amount * State.intensity("cameraShake"))
end

local function bind(name, fn, touchTitle, ...)
	ContextActionService:BindAction(name, function(_, inputState, input)
		return fn(inputState, input)
	end, touchTitle ~= nil, ...)
	if touchTitle then
		ContextActionService:SetTitle(name, touchTitle)
	end
end

local function setupBindings()
	bind("DA_Sprint", function(inputState)
		if inputState == Enum.UserInputState.Begin then
			sprinting = true
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			sprinting = false
		end
		return Enum.ContextActionResult.Pass
	end, "Sprint", Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)

	bind("DA_Flashlight", function(inputState)
		if inputState == Enum.UserInputState.Begin and not blocked() then
			InputController.setFlashlight(not flashlight)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, "Light", Enum.KeyCode.F, Enum.KeyCode.DPadDown)

	bind("DA_Tool", function(inputState)
		if inputState == Enum.UserInputState.Begin and not blocked() and InputController.onTool then
			InputController.onTool()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, "Tool", Enum.KeyCode.One, Enum.KeyCode.DPadUp)

	bind("DA_Deck", function(inputState)
		if inputState == Enum.UserInputState.Begin and InputController.onDeck then
			InputController.onDeck()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, "Deck", Enum.KeyCode.R, Enum.KeyCode.ButtonY)

	bind("DA_Inspect", function(inputState)
		if inputState == Enum.UserInputState.Begin and not blocked() then
			inspecting = true
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			inspecting = false
		end
		return Enum.ContextActionResult.Pass
	end, "Inspect", Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)

	bind("DA_Menu", function(inputState)
		if inputState == Enum.UserInputState.Begin and InputController.onMenu then
			InputController.onMenu()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, "Menu", Enum.KeyCode.Tab, Enum.KeyCode.P, Enum.KeyCode.ButtonSelect)

	-- Touch button layout (right side, large targets).
	local positions = {
		DA_Sprint = UDim2.new(1, -170, 1, -230),
		DA_Inspect = UDim2.new(1, -95, 1, -230),
		DA_Flashlight = UDim2.new(1, -245, 1, -160),
		DA_Tool = UDim2.new(1, -245, 1, -230),
		DA_Deck = UDim2.new(1, -170, 1, -300),
		DA_Menu = UDim2.new(1, -95, 1, -300),
	}
	for name, pos in positions do
		pcall(function()
			ContextActionService:SetPosition(name, pos)
		end)
	end
end

local function step(dt)
	local h = humanoid()
	local camera = Workspace.CurrentCamera
	if h then
		local moving = h.MoveDirection.Magnitude > 0.1
		local canSprint = sprinting and moving and stamina > 0 and not blocked() and (not State.inMission() or State.isAlive())
		if canSprint then
			stamina = math.max(0, stamina - dt / STAMINA_SECONDS)
			lastSprintAt = os.clock()
		elseif os.clock() - lastSprintAt > STAMINA_REGEN_DELAY then
			stamina = math.min(1, stamina + dt / (STAMINA_SECONDS * 1.3))
		end
		local target = canSprint and SPRINT_SPEED or WALK_SPEED
		if h.WalkSpeed > 0 and h.WalkSpeed ~= target then
			h.WalkSpeed = target
		end
		if shake > 0.001 then
			local s = shake
			h.CameraOffset = Vector3.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
			shake = math.max(0, shake - dt * 1.5)
		elseif h.CameraOffset.Magnitude > 0 then
			h.CameraOffset = Vector3.zero
		end
	end
	HUDController.stamina = stamina
	if beamPart and camera then
		beamPart.CFrame = camera.CFrame * CFrame.new(0.4, -0.4, 0)
		beam.Enabled = flashlight and State.inMission() and State.isAlive() or (flashlight and not State.inMission())
	end
	if camera and camera.CameraType == Enum.CameraType.Custom then
		local fov = inspecting and INSPECT_FOV or DEFAULT_FOV
		if math.abs(camera.FieldOfView - fov) > 0.5 then
			camera.FieldOfView = camera.FieldOfView + (fov - camera.FieldOfView) * math.min(1, dt * 10)
		end
	end
end

function InputController.isFlashlightOn()
	return flashlight
end

function InputController.init()
	pcall(function()
		StarterGui:SetCore("ResetButtonCallback", false)
	end)
	setupBindings()
	RunService.RenderStepped:Connect(step)
	State.settingsChanged:Connect(function(settings)
		UserInputService.MouseDeltaSensitivity = settings.sensitivity
	end)
	UserInputService.MouseDeltaSensitivity = State.settings.sensitivity
	State.cue:Connect(function(cue)
		if cue.cue == "HuntStart" then
			InputController.shake(0.25)
		elseif cue.cue == "LightsFail" or cue.cue == "LoopStart" then
			InputController.shake(0.12)
		end
	end)
	if Players.LocalPlayer.Character then
		task.spawn(muteOwnHeadLight, Players.LocalPlayer.Character)
	end
	Players.LocalPlayer.CharacterAdded:Connect(function(character)
		task.spawn(muteOwnHeadLight, character)
		stamina = 1
		if flashlight then
			task.delay(1, function()
				State.action("Flashlight", { on = flashlight })
			end)
		end
	end)
	-- Smooth FOV snaps back after menus.
	State.uiChanged:Connect(function()
		local camera = Workspace.CurrentCamera
		if camera and not State.anyModal() then
			TweenService:Create(camera, TweenInfo.new(0.2), { FieldOfView = DEFAULT_FOV }):Play()
		end
	end)
end

return InputController
