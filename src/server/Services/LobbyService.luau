--[[
	LobbyService — the Division field office (HQ) between cases.

	Party and ready-up, case/mode selection, deployment, profile sync, equipment
	and cosmetics, the credits shop, settings, desk decorations and the Archive
	Challenge leaderboard.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CaseRegistry = require(Shared.Config.CaseRegistry)
local Cosmetics = require(Shared.Config.Cosmetics)
local Typeface = require(Shared.Config.Typeface)
local ProfileSchema = require(Shared.Core.ProfileSchema)
local Variants = require(Shared.Core.Variants)
local MapBuilder = require(Shared.World.MapBuilder)
local Outfits = require(Shared.World.Outfits)

local Router = require(script.Parent.Router)

local LobbyService = {}

local DEPLOY_COUNTDOWN = 6

local deps, remotes
local ready = {} -- [player] = true
local selection = { caseId = "case01", mode = "Standard" }
local countdownEnd = nil
local desks = {} -- [index] = player

local TERMINAL_PAGES = {
	HQ_CASES = "Cases",
	HQ_ARCHIVE = "Archive",
	HQ_LOCKER = "Equipment",
	HQ_STORE = "Store",
	HQ_SETTINGS = "Settings",
}

local function inMission(player)
	local mission = deps.MissionService.mission
	if not mission then
		return false
	end
	local p = mission:participant(player.UserId)
	return p ~= nil and p.status ~= "Disconnected"
end

local function hqPlayers()
	local list = {}
	for _, player in Players:GetPlayers() do
		if not inMission(player) and deps.DataService.get(player) then
			table.insert(list, player)
		end
	end
	return list
end

local function clearanceOf(player)
	local profile = deps.DataService.get(player)
	return profile and profile.clearance or 1
end

function LobbyService.broadcast()
	local mission = deps.MissionService.mission
	local members = {}
	for _, player in Players:GetPlayers() do
		table.insert(members, {
			userId = player.UserId,
			name = player.DisplayName,
			ready = ready[player] == true,
			clearance = clearanceOf(player),
			inMission = inMission(player),
		})
	end
	local _, week = Variants.weeklySeed(os.time())
	local payload = {
		members = members,
		selection = selection,
		countdownEnd = countdownEnd,
		missionActive = mission ~= nil,
		missionPhase = mission and mission.phase or nil,
		missionCase = mission and mission.case.id or nil,
		joinable = mission ~= nil
			and (mission.phase == "Briefing" or mission.phase == "Active")
			and not mission.flags.transmitter_armed
			and mission:activeParticipantCount() < (mission.case.maxParticipants or 4),
		week = week,
		serverTime = workspace:GetServerTimeNow(),
	}
	remotes.Party:FireAllClients(payload)
end

---------------------------------------------------------------------------
-- Profile sync
---------------------------------------------------------------------------

function LobbyService.sendProfile(player)
	local profile = deps.DataService.get(player)
	if not profile then
		return
	end
	local passes = deps.MarketService.passes(player)
	local owned = {}
	for id in Cosmetics.Items do
		if Cosmetics.owns(id, profile, passes) then
			owned[id] = true
		end
	end
	for id in Cosmetics.Decor do
		if Cosmetics.owns(id, profile, passes) then
			owned[id] = true
		end
	end
	remotes.Profile:FireClient(player, {
		credits = profile.credits,
		research = profile.research,
		clearance = profile.clearance,
		evidence = profile.evidence,
		tapes = profile.tapes,
		frames = profile.frames,
		masters = profile.masters,
		cases = profile.cases,
		challenges = profile.challenges,
		owned = owned,
		equipped = profile.cosmetics.equipped,
		equipment = profile.equipment,
		settings = profile.settings,
		presets = profile.presets,
		presetSlots = Cosmetics.presetSlots(passes),
		decor = profile.decor,
		storedRevives = profile.storedRevives,
		storedTeamTokens = profile.storedTeamTokens,
		passes = passes,
		offline = deps.DataService.isOffline(player),
		archiveBest = profile.archiveChallengeBest,
		stats = profile.stats,
		tutorialSeen = profile.tutorialSeen,
	})
end

---------------------------------------------------------------------------
-- Desks, nameplates and decor
---------------------------------------------------------------------------

local function deskModel(index)
	local hq = deps.WorldService.hq
	return hq and hq:FindFirstChild("Desks") and hq.Desks:FindFirstChild("Desk" .. index)
end

local function refreshDesk(index)
	local model = deskModel(index)
	if not model then
		return
	end
	local player = desks[index]
	local plate = model:FindFirstChild("Nameplate")
	local label = plate and plate:FindFirstChild("Label") and plate.Label:FindFirstChild("Name")
	if label then
		label.Text = player and string.upper(player.DisplayName) or "VACANT"
	end
	local profile = player and deps.DataService.get(player)
	local passes = player and deps.MarketService.passes(player) or {}
	local decorRoot = model:FindFirstChild("Decor")
	if decorRoot then
		for _, holder in decorRoot:GetChildren() do
			local show = profile ~= nil and profile.decor[holder.Name] == true and Cosmetics.owns(holder.Name, profile, passes)
			for _, d in holder:GetDescendants() do
				if d:IsA("BasePart") then
					d.Transparency = show and (d:GetAttribute("BaseTransparency") or 0) or 1
				elseif d:IsA("SurfaceGui") or d:IsA("Light") then
					d.Enabled = show
				end
			end
		end
	end
end

local function assignDesk(player)
	for i = 1, #MapBuilder.HQDesks do
		if desks[i] == nil then
			desks[i] = player
			refreshDesk(i)
			return
		end
	end
end

local function releaseDesk(player)
	for i, owner in desks do
		if owner == player then
			desks[i] = nil
			refreshDesk(i)
		end
	end
end

local function deskOf(player)
	for i, owner in desks do
		if owner == player then
			return i
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Character dressing (outfit, nameplate, flashlight)
---------------------------------------------------------------------------

-- Office clothes in the field office, field kit in the station.
function LobbyService.outfit(player, character)
	character = character or player.Character
	if not character or character.Parent == nil then
		return
	end
	local profile = deps.DataService.get(player)
	local equipped = profile and profile.cosmetics.equipped or Cosmetics.Defaults
	local uniform = Cosmetics.Items[equipped.uniform] or Cosmetics.Items.uniform_standard
	local colour = Color3.fromRGB(uniform.colour[1], uniform.colour[2], uniform.colour[3])
	local mode = player:GetAttribute("InMission") == true and "Field" or "Lobby"
	Outfits.apply(character, mode, colour, player.DisplayName)
end

function LobbyService.dress(player, character)
	local profile = deps.DataService.get(player)
	task.spawn(function()
		local torso = character:WaitForChild("UpperTorso", 5) or character:FindFirstChild("Torso")
		local head = character:WaitForChild("Head", 5)
		if not torso or not head or character.Parent == nil then
			return
		end
		local equipped = profile and profile.cosmetics.equipped or Cosmetics.Defaults
		LobbyService.outfit(player, character)

		local plateItem = Cosmetics.Items[equipped.nameplate]
		if plateItem and plateItem.text then
			local billboard = Instance.new("BillboardGui")
			billboard.Name = "Nameplate"
			billboard.Size = UDim2.fromOffset(160, 24)
			billboard.StudsOffset = Vector3.new(0, 2.4, 0)
			billboard.AlwaysOnTop = false
			billboard.MaxDistance = 40
			billboard.Adornee = head
			local text = Instance.new("TextLabel")
			text.BackgroundTransparency = 1
			text.Size = UDim2.fromScale(1, 1)
			text.FontFace = Typeface.bold()
			text.TextScaled = true
			text.TextColor3 = Color3.fromRGB(196, 186, 158)
			text.TextStrokeTransparency = 0.5
			text.Text = plateItem.text
			text.Parent = billboard
			billboard.Parent = head
		end

		local light = Instance.new("SpotLight")
		light.Name = "Flashlight"
		light.Face = Enum.NormalId.Front
		light.Angle = 55
		light.Range = 38
		light.Brightness = 2.2
		light.Color = Color3.fromRGB(235, 230, 210)
		light.Shadows = true
		light.Enabled = player:GetAttribute("Flashlight") == true
		light.Parent = head
	end)
end

---------------------------------------------------------------------------
-- Deployment
---------------------------------------------------------------------------

local function validateSelection(caseId, mode, players)
	local case = CaseRegistry.get(caseId)
	if not case then
		return false, "That case is classified."
	end
	local modeDef = case.modes[mode]
	if not modeDef then
		return false, "Unknown mode."
	end
	if modeDef.requiresClearance then
		for _, player in players do
			if clearanceOf(player) < modeDef.requiresClearance then
				return false, string.format("%s needs clearance %d for %s (complete Case 01 first).", player.DisplayName, modeDef.requiresClearance, modeDef.label)
			end
		end
	end
	return true
end

local function tryCountdown()
	local list = hqPlayers()
	if deps.MissionService.mission or #list == 0 then
		countdownEnd = nil
		return
	end
	for _, player in list do
		if not ready[player] then
			countdownEnd = nil
			return
		end
	end
	local ok = validateSelection(selection.caseId, selection.mode, list)
	if not ok then
		countdownEnd = nil
		return
	end
	if not countdownEnd then
		countdownEnd = workspace:GetServerTimeNow() + DEPLOY_COUNTDOWN
	end
end

local function deploy()
	local list = hqPlayers()
	table.sort(list, function(a, b)
		return (ready[a] and 1 or 0) > (ready[b] and 1 or 0)
	end)
	local team = {}
	for _, player in list do
		if ready[player] then
			table.insert(team, player)
		end
	end
	countdownEnd = nil
	for player in ready do
		ready[player] = nil
	end
	if #team == 0 then
		return
	end
	local ok, reason = deps.MissionService.start(team, selection.caseId, selection.mode)
	if not ok then
		for _, player in team do
			remotes.Notify:FireClient(player, { text = reason })
		end
	end
	LobbyService.broadcast()
end

function LobbyService.openTerminal(player, terminalId)
	local page = TERMINAL_PAGES[terminalId]
	if page then
		remotes.Cue:FireClient(player, { cue = "OpenMenu", page = page })
	end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

local function profileOf(player)
	return deps.DataService.get(player)
end

function LobbyService.init(dependencies, remoteTable)
	deps = dependencies
	remotes = remoteTable

	deps.DataService.onLoaded(function(player, _, offline)
		assignDesk(player)
		LobbyService.sendProfile(player)
		LobbyService.broadcast()
		if offline then
			remotes.Notify:FireClient(player, { text = "Progress will not be saved this session (data service unavailable)." })
		end
		deps.MissionService.spawnAt(player, deps.WorldService.hqSpawn())
	end)

	table.insert(deps.MarketService.onPassChanged, function(player)
		LobbyService.sendProfile(player)
		local index = deskOf(player)
		if index then
			refreshDesk(index)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(deps.DataService.load, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(deps.DataService.load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		ready[player] = nil
		releaseDesk(player)
		task.defer(function()
			tryCountdown()
			LobbyService.broadcast()
		end)
	end)

	Router.onRequest("GetProfile", function(player)
		LobbyService.sendProfile(player)
		LobbyService.broadcast()
		return { ok = profileOf(player) ~= nil }
	end, { rate = 1, burst = 3 })

	Router.onAction("SetReady", function(player, payload)
		if inMission(player) or not profileOf(player) then
			return
		end
		ready[player] = payload.ready == true or nil
		tryCountdown()
		LobbyService.broadcast()
	end, { rate = 3, burst = 5 })

	Router.onRequest("SelectCase", function(player, payload)
		if not Router.string(payload.case, 16) or not Router.string(payload.mode, 24) then
			return { ok = false, message = "Malformed." }
		end
		local ok, reason = validateSelection(payload.case, payload.mode, { player })
		if not ok then
			return { ok = false, message = reason }
		end
		selection = { caseId = payload.case, mode = payload.mode }
		countdownEnd = nil
		tryCountdown()
		LobbyService.broadcast()
		return { ok = true }
	end, { rate = 2, burst = 4 })

	Router.onRequest("SetEquipment", function(player, payload)
		local profile = profileOf(player)
		if not profile or not Router.string(payload.equipment, 24) or not ProfileSchema.Equipment[payload.equipment] then
			return { ok = false, message = "Unknown equipment." }
		end
		if inMission(player) then
			return { ok = false, message = "Change equipment in the field office." }
		end
		profile.equipment = payload.equipment
		deps.DataService.markDirty(player)
		LobbyService.sendProfile(player)
		return { ok = true }
	end, { rate = 2, burst = 4 })

	Router.onRequest("SetCosmetic", function(player, payload)
		local profile = profileOf(player)
		local item = Router.string(payload.item, 40) and Cosmetics.Items[payload.item]
		if not profile or not item then
			return { ok = false, message = "Unknown item." }
		end
		if not Cosmetics.owns(payload.item, profile, deps.MarketService.passes(player)) then
			return { ok = false, message = "You don't own that yet." }
		end
		profile.cosmetics.equipped[item.slot] = payload.item
		deps.DataService.markDirty(player)
		LobbyService.sendProfile(player)
		if item.slot == "uniform" and player.Character then
			LobbyService.outfit(player)
		end
		return { ok = true }
	end, { rate = 3, burst = 6 })

	Router.onRequest("BuyCosmetic", function(player, payload)
		local profile = profileOf(player)
		local item = Router.string(payload.item, 40) and Cosmetics.Items[payload.item]
		if not profile or not item or item.source ~= "credits" then
			return { ok = false, message = "That can't be bought with credits." }
		end
		if profile.cosmetics.owned[payload.item] then
			return { ok = false, message = "Already owned." }
		end
		if profile.credits < item.price then
			return { ok = false, message = "Not enough Recovery Credits." }
		end
		profile.credits -= item.price
		profile.cosmetics.owned[payload.item] = true
		deps.DataService.markDirty(player)
		LobbyService.sendProfile(player)
		return { ok = true }
	end, { rate = 2, burst = 4 })

	Router.onRequest("SetDecor", function(player, payload)
		local profile = profileOf(player)
		if not profile or not Router.string(payload.decor, 32) or not Cosmetics.Decor[payload.decor] then
			return { ok = false, message = "Unknown decoration." }
		end
		if not Cosmetics.owns(payload.decor, profile, deps.MarketService.passes(player)) then
			return { ok = false, message = "You don't own that decoration." }
		end
		profile.decor[payload.decor] = payload.on == true or nil
		deps.DataService.markDirty(player)
		local index = deskOf(player)
		if index then
			refreshDesk(index)
		end
		LobbyService.sendProfile(player)
		return { ok = true }
	end, { rate = 3, burst = 6 })

	Router.onRequest("SavePreset", function(player, payload)
		local profile = profileOf(player)
		local slots = Cosmetics.presetSlots(deps.MarketService.passes(player))
		if not profile or not Router.number(payload.slot, 1, slots) then
			return { ok = false, message = "No such preset slot." }
		end
		profile.presets[tostring(math.floor(payload.slot))] = {
			equipment = profile.equipment,
			equipped = table.clone(profile.cosmetics.equipped),
		}
		deps.DataService.markDirty(player)
		LobbyService.sendProfile(player)
		return { ok = true }
	end, { rate = 2, burst = 4 })

	Router.onRequest("LoadPreset", function(player, payload)
		local profile = profileOf(player)
		if not profile or not Router.number(payload.slot, 1, 16) then
			return { ok = false }
		end
		local preset = profile.presets[tostring(math.floor(payload.slot))]
		if not preset then
			return { ok = false, message = "That preset is empty." }
		end
		local passes = deps.MarketService.passes(player)
		if ProfileSchema.Equipment[preset.equipment] then
			profile.equipment = preset.equipment
		end
		for slot, itemId in preset.equipped do
			if Cosmetics.owns(itemId, profile, passes) then
				profile.cosmetics.equipped[slot] = itemId
			end
		end
		deps.DataService.markDirty(player)
		LobbyService.sendProfile(player)
		return { ok = true }
	end, { rate = 2, burst = 4 })

	Router.onRequest("SaveSettings", function(player, payload)
		local profile = profileOf(player)
		if not profile then
			return { ok = false }
		end
		profile.settings = ProfileSchema.sanitizeSettings(profile.settings, payload.settings)
		deps.DataService.markDirty(player)
		return { ok = true, settings = profile.settings }
	end, { rate = 1, burst = 3 })

	Router.onRequest("SetTutorialSeen", function(player)
		local profile = profileOf(player)
		if not profile then
			return { ok = false }
		end
		if not profile.tutorialSeen then
			profile.tutorialSeen = true
			deps.DataService.markDirty(player)
		end
		return { ok = true }
	end, { rate = 1, burst = 3 })

	Router.onRequest("GetStore", function(player)
		return deps.MarketService.catalogue(player)
	end, { rate = 1, burst = 3 })

	Router.onRequest("PromptPass", function(player, payload)
		if not Router.string(payload.pass, 24) then
			return { ok = false }
		end
		local ok, reason = deps.MarketService.promptPass(player, payload.pass)
		return { ok = ok, message = reason }
	end, { rate = 1, burst = 2 })

	Router.onRequest("PromptBundle", function(player, payload)
		-- Only cosmetic bundles are bought from the store; re-entries are offered
		-- in context when eligible, never pushed.
		if payload.product ~= "EvidenceBundle" and payload.product ~= "LobbyBundle" then
			return { ok = false }
		end
		local ok, reason = deps.MarketService.promptProduct(player, payload.product, nil)
		return { ok = ok, message = reason }
	end, { rate = 1, burst = 2 })

	Router.onRequest("GetLeaderboard", function()
		local _, week = Variants.weeklySeed(os.time())
		return { ok = true, week = week, rows = deps.DataService.topScores(week) }
	end, { rate = 1, burst = 2 })

	task.spawn(function()
		while true do
			task.wait(0.25)
			if countdownEnd then
				if deps.MissionService.mission then
					countdownEnd = nil
					LobbyService.broadcast()
				elseif workspace:GetServerTimeNow() >= countdownEnd then
					local ok, err = pcall(deploy)
					if not ok then
						warn("[LobbyService] deploy failed: " .. tostring(err))
						countdownEnd = nil
					end
				end
			end
		end
	end)
end

return LobbyService
