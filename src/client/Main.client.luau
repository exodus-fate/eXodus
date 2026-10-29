--[[
	DEAD AIR: CHANNEL ZERO — client bootstrap.

	The client owns input, UI, camera and presentation. It never decides
	outcomes: every interaction, edit, purchase and reward is validated on the
	server, and the HUD only reflects replicated state.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local State = require(script.Parent.State)
local Controllers = script.Parent.Controllers

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = Net.wait(ReplicatedStorage)
State.init(remotes)

local AudioController = require(Controllers.AudioController)
local HUDController = require(Controllers.HUDController)
local CameraController = require(Controllers.CameraController)
local InputController = require(Controllers.InputController)
local DeckController = require(Controllers.DeckController)
local MenuController = require(Controllers.MenuController)
local ReportController = require(Controllers.ReportController)
local SpectateController = require(Controllers.SpectateController)
local KeypadController = require(Controllers.KeypadController)
local EffectsController = require(Controllers.EffectsController)
local MonitorController = require(Controllers.MonitorController)
local ToolController = require(Controllers.ToolController)
local PromptController = require(Controllers.PromptController)
local TutorialController = require(Controllers.TutorialController)

local function safeInit(name, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn(string.format("[DeadAir] %s failed to start: %s", name, tostring(err)))
	end
end

safeInit("Audio", AudioController.init)
safeInit("HUD", HUDController.init, playerGui)
safeInit("Camera", CameraController.init, playerGui)
safeInit("Input", InputController.init)
safeInit("Deck", DeckController.init, playerGui)
safeInit("Menu", MenuController.init, playerGui, DeckController)
safeInit("Report", ReportController.init, playerGui)
safeInit("Spectate", SpectateController.init, playerGui)
safeInit("Keypad", KeypadController.init, playerGui)
safeInit("Effects", EffectsController.init, playerGui)
safeInit("Monitors", MonitorController.init)
safeInit("Tools", ToolController.init, playerGui, DeckController)
safeInit("Prompts", PromptController.init, playerGui)
safeInit("Tutorial", TutorialController.init, playerGui)

InputController.onTool = ToolController.toggle
-- Your footsteps land in time with the head bob.
CameraController.onFootstep = AudioController.footstep

InputController.onDeck = function()
	if DeckController.isOpen() then
		DeckController.close()
		return
	end
	if State.anyModal() then
		return
	end
	if State.inMission() then
		if State.isAlive() then
			local deckId = DeckController.nearbyDeck()
			local caseDef = State.caseDef()
			local deck = deckId and caseDef and caseDef.decks[deckId]
			local powered = State.mission.flags and State.mission.flags.generator_restored
			if deck and not deck.battery and not powered then
				State.notify:Fire(deck.label .. " has no power. Restore the generator first.")
			elseif deckId then
				DeckController.open({ mode = "mission", deckId = deckId })
			elseif State.profile and State.profile.equipment == "Monitor" then
				DeckController.open({ mode = "handheld" })
			else
				State.notify:Fire("Stand at a tape deck to open it.")
			end
		else
			DeckController.open({ mode = "spectate" })
		end
	end
end

InputController.onMenu = function()
	if DeckController.isOpen() then
		DeckController.close()
		return
	end
	MenuController.toggle()
end

-- Text size setting: every label keeps its designed size times the scale.
local function scaleText(gui)
	local function apply(obj)
		-- Deferred: the object may already have been removed by a rebuild.
		if obj.Parent == nil then
			return
		end
		if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
			local base = obj:GetAttribute("BaseTextSize")
			if not base then
				base = obj.TextSize
				obj:SetAttribute("BaseTextSize", base)
			end
			obj.TextSize = math.floor(base * State.settings.textScale + 0.5)
		end
	end
	for _, d in gui:GetDescendants() do
		apply(d)
	end
	gui.DescendantAdded:Connect(function(d)
		task.defer(apply, d)
	end)
	State.settingsChanged:Connect(function()
		for _, d in gui:GetDescendants() do
			apply(d)
		end
	end)
end

for _, gui in playerGui:GetChildren() do
	if gui:IsA("ScreenGui") and string.sub(gui.Name, 1, 7) == "DeadAir" then
		scaleText(gui)
	end
end

-- Ask for our profile in case it arrived before the listeners were ready.
task.spawn(function()
	State.request("GetProfile", {})
end)
