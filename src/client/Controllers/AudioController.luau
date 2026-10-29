--[[
	AudioController — sound groups with separate sliders, cue sounds and the
	Presenter's footsteps (spatial, so players can judge direction).

	Sound ids live in Shared.Config.Audio. Empty ids are skipped; every important
	cue also has a subtitle and a visual, so silence never hides information.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared.Config.Audio)

local State = require(script.Parent.Parent.State)

local AudioController = {}

local groups = {}
local masterGroup
local loops = {}
local stepSound
local lastStep = 0
local silencedUntil = 0

local CUE_SOUNDS = {
	HuntStart = "HuntStart",
	LightsFail = "LightsFail",
	PowerOn = "PowerOn",
	DoorLocked = "DoorLocked",
	EditCommitted = "EditCommit",
	LocalEditCommitted = "EditCommit",
	Alarm = "Alarm",
	LoopStart = "Static",
	LoopReset = "Static",
	LoopBreak = "Static",
	Rewind = "Rewind",
	Install = "Install",
	Eliminated = "Static",
	CageOpen = "Install",
	DoorForced = "DoorOpen",
}

local function makeSound(cueId, parent)
	local def = Audio.Cues[cueId]
	if not def or def.id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = cueId
	sound.SoundId = def.id
	sound.Volume = def.volume or 0.5
	sound.PlaybackSpeed = def.pitch or 1
	sound.Looped = def.looped == true
	sound.SoundGroup = groups[def.group] or masterGroup
	sound.Parent = parent or SoundService
	return sound
end

function AudioController.play(cueId)
	if os.clock() < silencedUntil then
		return
	end
	local sound = makeSound(cueId)
	if sound then
		sound:Play()
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
		task.delay(15, function()
			if sound.Parent then
				sound:Destroy()
			end
		end)
	end
end

local function applyVolumes(settings)
	masterGroup.Volume = settings.master
	groups.Music.Volume = settings.music
	groups.Ambience.Volume = settings.ambience
	groups.Effects.Volume = settings.effects
end

local function presenterRoot()
	local model = Workspace:FindFirstChild("Presenter")
	return model and model:IsA("Model") and model.PrimaryPart or nil
end

local function stepFootsteps()
	local root = presenterRoot()
	if not root then
		return
	end
	if not stepSound or stepSound.Parent ~= root then
		if stepSound then
			stepSound:Destroy()
		end
		stepSound = makeSound("PresenterStep", root)
		if stepSound then
			stepSound.RollOffMode = Enum.RollOffMode.InverseTapered
			stepSound.RollOffMinDistance = 8
			stepSound.RollOffMaxDistance = 90
		end
	end
	local speed = root.AssemblyLinearVelocity.Magnitude
	local interval = speed > 10 and 0.36 or 0.62
	if stepSound and speed > 1 and os.clock() - lastStep > interval then
		lastStep = os.clock()
		stepSound:Play()
	end
	local near = loops.PresenterNear
	if near then
		local character = Players.LocalPlayer.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local d = hrp and (hrp.Position - root.Position).Magnitude or math.huge
		near.Volume = math.clamp(1 - d / 45, 0, 1) * (Audio.Cues.PresenterNear.volume or 0.6)
	end
end

function AudioController.init()
	masterGroup = Instance.new("SoundGroup")
	masterGroup.Name = "DeadAirMaster"
	masterGroup.Parent = SoundService
	for _, name in Audio.Groups do
		local g = Instance.new("SoundGroup")
		g.Name = name
		g.Parent = masterGroup
		groups[name] = g
	end
	applyVolumes(State.settings)
	State.settingsChanged:Connect(applyVolumes)

	for _, cueId in { "Ambience", "Fluorescent", "PresenterNear" } do
		local sound = makeSound(cueId)
		if sound then
			sound.Volume = cueId == "PresenterNear" and 0 or sound.Volume
			sound:Play()
			loops[cueId] = sound
		end
	end

	State.cue:Connect(function(cue)
		local soundId = CUE_SOUNDS[cue.cue]
		if soundId then
			AudioController.play(soundId)
		end
		if cue.cue == "LocalSilence" then
			-- The quiet before the false-safety beat: everything drops out.
			silencedUntil = os.clock() + (cue.duration or 5)
			TweenService:Create(masterGroup, TweenInfo.new(0.8), { Volume = 0 }):Play()
			task.delay(cue.duration or 5, function()
				TweenService:Create(masterGroup, TweenInfo.new(1.5), { Volume = State.settings.master }):Play()
			end)
		end
	end)
	State.subtitle:Connect(function(line)
		if line.kind == "radio" then
			AudioController.play("RadioClick")
		end
	end)
	State.notify:Connect(function()
		AudioController.play("UIClick")
	end)
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum >= 0.05 then
			accum = 0
			stepFootsteps()
		end
	end)
end

return AudioController
