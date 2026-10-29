--[[
	InteractionService — ProximityPrompts for everything interactive.

	ProximityPrompts give PC (E), gamepad (X) and touch (tap) support for free.
	Prompt text/visibility mirrors MissionCore:promptState so players always see
	what an object does (or why it won't work). Every trigger is range-checked and
	rate-limited on the server before it reaches the mission.
]]

local Players = game:GetService("Players")

local InteractionService = {}

local MAX_DISTANCE = 9
local DISTANCE_SLACK = 4

InteractionService.missionPrompts = {} -- [interactId] = prompt
InteractionService.doorPrompts = {} -- [doorId] = prompt
InteractionService.hqPrompts = {}
InteractionService.lastTrigger = {}

local deps

local function makePrompt(parent, action, object, hold)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action or "Interact"
	prompt.ObjectText = object or ""
	prompt.HoldDuration = hold or 0
	prompt.MaxActivationDistance = MAX_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	-- Drawn by the client's PromptController in the game's own typeface.
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ClickablePrompt = true
	prompt.Parent = parent
	return prompt
end

local function inRange(player, prompt)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local holder = prompt.Parent
	if not root or not holder or not holder:IsA("BasePart") then
		return false
	end
	return (root.Position - holder.Position).Magnitude <= prompt.MaxActivationDistance + DISTANCE_SLACK
end

local function throttled(player)
	local now = os.clock()
	local last = InteractionService.lastTrigger[player]
	if last and now - last < 0.15 then
		return true
	end
	InteractionService.lastTrigger[player] = now
	return false
end

---------------------------------------------------------------------------
-- Mission prompts
---------------------------------------------------------------------------

function InteractionService.bindMissionAnchor(anchorPart, interactId)
	local existing = InteractionService.missionPrompts[interactId]
	if existing then
		existing:Destroy()
	end
	local prompt = makePrompt(anchorPart, "Interact", "", 0)
	prompt.Enabled = false
	prompt.Triggered:Connect(function(player)
		if throttled(player) or not inRange(player, prompt) then
			return
		end
		deps.MissionService.interact(player, interactId)
	end)
	InteractionService.missionPrompts[interactId] = prompt
	return prompt
end

function InteractionService.unbindMissionAnchor(interactId)
	local prompt = InteractionService.missionPrompts[interactId]
	if prompt then
		prompt:Destroy()
		InteractionService.missionPrompts[interactId] = nil
	end
end

function InteractionService.bindStation(station)
	for id, prompt in InteractionService.missionPrompts do
		prompt:Destroy()
		InteractionService.missionPrompts[id] = nil
	end
	for id, prompt in InteractionService.doorPrompts do
		prompt:Destroy()
		InteractionService.doorPrompts[id] = nil
	end
	for _, anchorPart in station.Anchors:GetChildren() do
		local id = anchorPart:GetAttribute("InteractId")
		if id then
			InteractionService.bindMissionAnchor(anchorPart, id)
		end
	end
	for doorId, entry in deps.WorldService.doors do
		if #entry.panels > 0 then
			local prompt = makePrompt(entry.panels[1].part, "Open", entry.model:GetAttribute("Label") or "", 0)
			prompt.MaxActivationDistance = 7
			prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
			prompt.Triggered:Connect(function(player)
				if throttled(player) or not inRange(player, prompt) then
					return
				end
				deps.MissionService.useDoor(player, doorId)
			end)
			InteractionService.doorPrompts[doorId] = prompt
		end
	end
	InteractionService.refreshDoors()
end

function InteractionService.refresh(mission)
	if not mission then
		for _, prompt in InteractionService.missionPrompts do
			prompt.Enabled = false
		end
		return
	end
	for id, prompt in InteractionService.missionPrompts do
		local state = mission:promptState(id)
		prompt.Enabled = state.visible == true
		if state.visible then
			prompt.ActionText = state.action or "Interact"
			prompt.ObjectText = state.object or ""
			prompt.HoldDuration = state.hold or 0
		end
	end
end

function InteractionService.refreshDoors()
	for doorId, prompt in InteractionService.doorPrompts do
		local entry = deps.WorldService.door(doorId)
		if entry then
			if entry.locked then
				prompt.ActionText = "Locked"
			elseif entry.kind == "freight" then
				prompt.ActionText = entry.open and "Open" or "Closed"
				prompt.Enabled = not entry.open
			else
				prompt.ActionText = entry.open and "Close" or "Open"
			end
			if entry.kind ~= "freight" then
				prompt.Enabled = true
			end
		end
	end
end

---------------------------------------------------------------------------
-- Field office prompts
---------------------------------------------------------------------------

function InteractionService.bindHQ(hq, terminals)
	for _, anchorPart in hq.Anchors:GetChildren() do
		local id = anchorPart:GetAttribute("InteractId")
		local def = terminals[id]
		if def then
			local prompt = makePrompt(anchorPart, def.action, def.label, 0)
			prompt.Triggered:Connect(function(player)
				if throttled(player) or not inRange(player, prompt) then
					return
				end
				deps.LobbyService.openTerminal(player, id)
			end)
			InteractionService.hqPrompts[id] = prompt
		end
	end
end

function InteractionService.init(dependencies)
	deps = dependencies
	Players.PlayerRemoving:Connect(function(player)
		InteractionService.lastTrigger[player] = nil
	end)
	table.insert(deps.WorldService.onDoorChanged, function()
		InteractionService.refreshDoors()
	end)
end

return InteractionService
