--[[
	MenuController — main menu, field office pages and the in-case pause menu.

	Main menu: a slow camera pan across the dead control room, the Division
	header, DEAD AIR / CHANNEL ZERO // SIGNAL DETECTED, and Case Select,
	Evidence Archive, Equipment, Settings, Credits (plus Store and "Enter the
	field office"). All buttons are large, controller-selectable and touch-sized.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CaseRegistry = require(Shared.Config.CaseRegistry)
local Cosmetics = require(Shared.Config.Cosmetics)
local Evidence = require(Shared.Config.Evidence)
local ProfileSchema = require(Shared.Core.ProfileSchema)
local Format = require(Shared.Util.Format)

local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local Controls = require(script.Parent.Parent.UI.Controls)

local MenuController = {}

local gui, root, content, nav, statusLine, title
local page = nil
local panConn = nil
local DeckController -- set in init (avoids a require cycle)

local function gamepadMode()
	return #UserInputService:GetConnectedGamepads() > 0
end

local function heading(parent, text, order)
	return UI.text(parent, text, {
		FontFace = Theme.FontBold,
		TextSize = Theme.LargeText,
		TextColor3 = Theme.Accent,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = order or 0,
	})
end

local function para(parent, text, order, colour)
	return UI.text(parent, text, {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = colour or Theme.Text,
		LayoutOrder = order or 0,
	})
end

local function row(parent, order, height)
	local f = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height or 44), LayoutOrder = order or 0, Parent = parent })
	UI.list(f, 6, Enum.FillDirection.Horizontal)
	return f
end

---------------------------------------------------------------------------
-- Camera pan across the dead control room
---------------------------------------------------------------------------

local function startPan()
	if panConn then
		return
	end
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local t0 = os.clock()
	panConn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - t0) * 0.05
		local x = math.sin(t) * 12
		local pos = Vector3.new(x, 8.5, 15)
		local look = Vector3.new(x * 0.4, 4.5, -18)
		camera.CFrame = CFrame.lookAt(pos, look)
		camera.FieldOfView = 60
	end)
end

local function stopPan()
	if panConn then
		panConn:Disconnect()
		panConn = nil
	end
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = State.settings.fieldOfView or 70
	local character = State.player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------

local Pages = {}

function Pages.Home(c)
	heading(c, "WELCOME, INVESTIGATOR", 1)
	local p = State.profile
	if p then
		para(c, string.format("CLEARANCE %d · RECOVERY CREDITS %d · RESEARCH %d", p.clearance, p.credits, p.research), 2, Theme.Cream)
		if p.offline then
			para(c, "Progress will not be saved this session.", 3, Theme.Amber)
		end
		local completed = p.cases and p.cases.case01 and p.cases.case01.completed or 0
		if completed == 0 then
			para(c, "Start with CASE SELECT. Case 01 teaches everything: tapes, edits, the Presenter and extraction.", 4, Theme.TextDim)
		end
	else
		para(c, "Connecting to Division...", 2, Theme.TextDim)
	end
	local party = State.party
	if party and party.missionActive and not State.inMission() then
		para(c, "A case is in progress on this server.", 5, Theme.Amber)
	end
end

function Pages.Cases(c)
	heading(c, "CASE SELECT", 1)
	local party = State.party or {}
	local selection = party.selection or { caseId = "case01", mode = "Standard" }
	local profile = State.profile or {}
	for i, entry in CaseRegistry.Order do
		local case = CaseRegistry.get(entry.id)
		local stats = profile.cases and profile.cases[entry.id]
		local label
		if entry.playable then
			label = string.format("CASE %02d · %s · %s", entry.number, entry.title, entry.location)
			if stats then
				label ..= string.format("   BEST %s · RUNS %d", stats.bestGrade or "-", stats.runs or 0)
			end
		else
			label = string.format("CASE %02d · CLASSIFIED · %s · FUTURE UPDATE", entry.number, entry.location)
		end
		local b = UI.button(c, label, function()
			if entry.playable then
				local result = State.request("SelectCase", { case = entry.id, mode = selection.mode })
				if not result.ok then
					State.notify:Fire(result.message or "Unavailable.")
				end
			end
		end, { LayoutOrder = 10 + i * 2, TextXAlignment = Enum.TextXAlignment.Left, TextSize = Theme.SmallText })
		UI.padding(b, 10, 0)
		if not entry.playable then
			UI.setEnabled(b, false)
		elseif selection.caseId == entry.id then
			b.TextColor3 = Theme.Accent
		end
		if case and selection.caseId == entry.id then
			para(c, case.summary, 10 + i * 2 + 1, Theme.TextDim)
		end
	end

	local selected = CaseRegistry.get(selection.caseId)
	if selected then
		heading(c, "MODE", 30)
		local modes = row(c, 31)
		for _, modeId in { "Standard", "Restricted", "ArchiveChallenge" } do
			local def = selected.modes[modeId]
			local locked = def.requiresClearance and (profile.clearance or 1) < def.requiresClearance
			local b = UI.button(modes, def.label .. (locked and " (LOCKED)" or ""), function()
				local result = State.request("SelectCase", { case = selection.caseId, mode = modeId })
				if not result.ok then
					State.notify:Fire(result.message or "Unavailable.")
				end
			end, { Size = UDim2.new(0.32, 0, 1, 0), TextSize = Theme.SmallText })
			if selection.mode == modeId then
				b.TextColor3 = Theme.Accent
			end
			if locked then
				UI.setEnabled(b, false)
			end
		end
		local descriptions = {
			Standard = "Three edit charges. Clues shown. The intended way to play.",
			Restricted = "Two charges, no clue lines, a faster and more alert Presenter. Unlocked at clearance 2.",
			ArchiveChallenge = "This week's fixed seed for everyone. Scores go on the weekly leaderboard. Clearance 2.",
		}
		para(c, descriptions[selection.mode] or "", 32, Theme.TextDim)
	end

	heading(c, "TEAM", 40)
	for i, member in party.members or {} do
		local status = member.inMission and "IN CASE" or (member.ready and "READY" or "NOT READY")
		para(c, string.format("%s · CLEARANCE %d · %s", member.name, member.clearance or 1, status), 40 + i, member.ready and Theme.Accent or Theme.Text)
	end
	if party.countdownEnd then
		local remaining = math.max(0, party.countdownEnd - State.now())
		para(c, string.format("DEPLOYING IN %d...", math.ceil(remaining)), 60, Theme.Amber)
	end
	local me
	for _, member in party.members or {} do
		if member.userId == State.player.UserId then
			me = member
		end
	end
	local actions = row(c, 61)
	if party.missionActive then
		local join = UI.button(actions, "JOIN THE CASE IN PROGRESS", function()
			local result = State.request("JoinMission", {})
			if result.ok then
				MenuController.close()
			else
				State.notify:Fire(result.message or "Can't join.")
			end
		end, { Size = UDim2.new(0.5, 0, 1, 0) })
		if not party.joinable then
			UI.setEnabled(join, false)
			para(c, "The case in progress is too far along or full. Wait for the team to return.", 62, Theme.TextDim)
		end
	else
		UI.button(actions, (me and me.ready) and "CANCEL READY" or "READY", function()
			State.action("SetReady", { ready = not (me and me.ready) })
		end, { Size = UDim2.new(0.5, 0, 1, 0), TextColor3 = Theme.Accent })
		para(c, "When everyone in the field office is ready, the team deploys. You can play alone.", 62, Theme.TextDim)
	end

	if selection.mode == "ArchiveChallenge" then
		heading(c, "THIS WEEK'S ARCHIVE CHALLENGE", 70)
		local holder = UI.new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 71, Parent = c })
		UI.list(holder, 2)
		para(holder, "Loading leaderboard...", 1, Theme.TextDim)
		task.spawn(function()
			local result = State.request("GetLeaderboard", {})
			if holder.Parent then
				UI.clear(holder)
				if not result.rows or #result.rows == 0 then
					para(holder, "No scores yet this week.", 1, Theme.TextDim)
				end
				for i, r in result.rows or {} do
					para(holder, string.format("%d. %s · %d", r.rank, r.name, r.score), i)
				end
			end
		end)
	end
end

local function transcriptView(parent, entry, order)
	local lines = {}
	for _, line in entry.transcript or {} do
		if line.frame then
			table.insert(lines, string.format("[%s] (%s)", Format.short(line.t), line.text))
		else
			table.insert(lines, string.format("[%s] %s: %s", Format.short(line.t), line.speaker, line.text))
		end
	end
	return para(parent, table.concat(lines, "\n"), order, Theme.Cream)
end

local archiveSelection = nil

function Pages.Archive(c)
	heading(c, "EVIDENCE ARCHIVE", 1)
	local p = State.profile or {}
	para(c, "Recovered tapes stay unlocked. Replay case tapes to find hidden frames.", 2, Theme.TextDim)

	heading(c, "MASTER RECORDINGS", 10)
	for i, master in Evidence.MasterRecordings do
		local unlocked = p.masters and p.masters[master.id]
		local b = UI.button(c, string.format("%s%s", master.title, unlocked and "" or (master.available and "  [NOT RECOVERED]" or "  [FUTURE CASE]")), function()
			archiveSelection = unlocked and master or nil
			MenuController.show("Archive")
		end, { LayoutOrder = 10 + i, TextXAlignment = Enum.TextXAlignment.Left, TextSize = Theme.SmallText })
		UI.padding(b, 10, 0)
		if not unlocked then
			UI.setEnabled(b, false)
		end
	end

	heading(c, "EVIDENCE TAPES", 30)
	local ids = {}
	for id in Evidence.Tapes do
		table.insert(ids, id)
	end
	table.sort(ids)
	for i, id in ids do
		local tape = Evidence.Tapes[id]
		local unlocked = p.evidence and p.evidence[id]
		local b = UI.button(c, unlocked and tape.title or "UNRECOVERED TAPE", function()
			archiveSelection = unlocked and tape or nil
			MenuController.show("Archive")
		end, { LayoutOrder = 30 + i, TextXAlignment = Enum.TextXAlignment.Left, TextSize = Theme.SmallText })
		UI.padding(b, 10, 0)
		if not unlocked then
			UI.setEnabled(b, false)
		end
	end

	heading(c, "CASE TAPES", 50)
	local case = CaseRegistry.get("case01")
	local any = false
	for i, tapeId in case.tapeOrder do
		if p.tapes and p.tapes[tapeId] then
			any = true
			local tape = case.tapes[tapeId]
			UI.button(c, string.format("REPLAY %s · %s", tape.label, tape.title), function()
				MenuController.close()
				DeckController.open({ mode = "archive", caseId = "case01", tapeId = tapeId })
			end, { LayoutOrder = 50 + i, TextSize = Theme.SmallText })
		end
	end
	if not any then
		para(c, "Recover tapes during a case to replay them here.", 51, Theme.TextDim)
	end
	local frames = 0
	for _ in p.frames or {} do
		frames += 1
	end
	para(c, string.format("HIDDEN FRAMES FOUND: %d / %d", frames, #case.hiddenFrames), 60, Theme.Cream)

	heading(c, "INVESTIGATOR CHALLENGES", 70)
	for i, ch in case.challenges do
		local done = p.challenges and p.challenges[ch.id]
		para(c, string.format("%s %s — %s", done and "[X]" or "[ ]", ch.label, ch.text), 70 + i, done and Theme.Accent or Theme.Text)
	end

	if archiveSelection then
		heading(c, archiveSelection.title, -2)
		transcriptView(c, archiveSelection, -1)
	end
end

function Pages.Equipment(c)
	heading(c, "EQUIPMENT", 1)
	local p = State.profile
	if not p then
		para(c, "Connecting...", 2)
		return
	end
	para(c, "Equipment changes how you gather evidence, never whether you can win.", 2, Theme.TextDim)
	for i, id in ProfileSchema.EquipmentOrder do
		local def = ProfileSchema.Equipment[id]
		local b = UI.button(c, string.format("%s%s — %s", def.label, p.equipment == id and " (EQUIPPED)" or "", def.description), function()
			local result = State.request("SetEquipment", { equipment = id })
			if not result.ok then
				State.notify:Fire(result.message or "Unavailable.")
			end
		end, { LayoutOrder = 2 + i, TextXAlignment = Enum.TextXAlignment.Left, TextSize = Theme.SmallText, TextWrapped = true, Size = UDim2.new(1, 0, 0, 52) })
		UI.padding(b, 10, 0)
		if p.equipment == id then
			b.TextColor3 = Theme.Accent
		end
	end

	heading(c, string.format("COSMETICS · %d RECOVERY CREDITS", p.credits), 20)
	local order = 21
	for _, slot in Cosmetics.Slots do
		para(c, Cosmetics.SlotLabels[slot], order, Theme.TextDim)
		order += 1
		local ids = {}
		for id, item in Cosmetics.Items do
			if item.slot == slot then
				table.insert(ids, id)
			end
		end
		table.sort(ids)
		for _, id in ids do
			local item = Cosmetics.Items[id]
			local owned = p.owned and p.owned[id]
			local equipped = p.equipped and p.equipped[slot] == id
			local suffix
			if equipped then
				suffix = "EQUIPPED"
			elseif owned then
				suffix = "EQUIP"
			elseif item.source == "credits" then
				suffix = string.format("BUY · %d CREDITS", item.price)
			elseif item.source == "pass" then
				suffix = "PASS"
			elseif item.source == "challenge" then
				suffix = "CHALLENGE"
			else
				suffix = "BUNDLE"
			end
			local b = UI.button(c, string.format("%s · %s", item.label, suffix), function()
				local result
				if owned then
					result = State.request("SetCosmetic", { item = id })
				elseif item.source == "credits" then
					result = State.request("BuyCosmetic", { item = id })
				else
					result = { ok = false, message = "Available from the store or a challenge." }
				end
				if not result.ok then
					State.notify:Fire(result.message or "Unavailable.")
				end
			end, { LayoutOrder = order, TextXAlignment = Enum.TextXAlignment.Left, TextSize = Theme.SmallText, Size = UDim2.new(1, 0, 0, 40) })
			UI.padding(b, 10, 0)
			if equipped then
				b.TextColor3 = Theme.Accent
			end
			order += 1
		end
	end

	heading(c, string.format("LOADOUT PRESETS (%d SLOT%s)", p.presetSlots or 1, (p.presetSlots or 1) == 1 and "" or "S"), order)
	order += 1
	for slot = 1, p.presetSlots or 1 do
		local r = row(c, order)
		local saved = p.presets and p.presets[tostring(slot)]
		UI.button(r, string.format("SAVE TO SLOT %d", slot), function()
			State.request("SavePreset", { slot = slot })
		end, { Size = UDim2.new(0.48, 0, 1, 0), TextSize = Theme.SmallText })
		local load = UI.button(r, saved and string.format("LOAD SLOT %d", slot) or "EMPTY", function()
			State.request("LoadPreset", { slot = slot })
		end, { Size = UDim2.new(0.48, 0, 1, 0), TextSize = Theme.SmallText })
		if not saved then
			UI.setEnabled(load, false)
		end
		order += 1
	end

	heading(c, "DESK DECORATIONS", order)
	order += 1
	local anyDecor = false
	local decorIds = {}
	for id in Cosmetics.Decor do
		table.insert(decorIds, id)
	end
	table.sort(decorIds)
	for _, id in decorIds do
		if p.owned and p.owned[id] then
			anyDecor = true
			local on = p.decor and p.decor[id]
			UI.button(c, string.format("%s: %s", Cosmetics.Decor[id].label, on and "SHOWN" or "HIDDEN"), function()
				State.request("SetDecor", { decor = id, on = not on })
			end, { LayoutOrder = order, TextSize = Theme.SmallText })
			order += 1
		end
	end
	if not anyDecor then
		para(c, "Personal Quarters and the Office Decoration Bundle add items to your desk.", order, Theme.TextDim)
	end
end

function Pages.Settings(c)
	heading(c, "SETTINGS", 1)
	local s = State.settings
	local function changed(key)
		return function(value)
			local copy = table.clone(State.settings)
			copy[key] = value
			State.applySettings(copy)
			State.saveSettingsSoon()
		end
	end
	local function section(title, order)
		local holder = UI.new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = order, Parent = c })
		UI.list(holder, 4)
		UI.text(holder, title, { FontFace = Theme.FontBold, TextSize = Theme.SmallText, TextColor3 = Theme.Amber, LayoutOrder = -1 })
		return holder
	end

	local controls = section("CONTROLS", 2)
	UI.slider(controls, "MOUSE / LOOK SENSITIVITY", s.sensitivity, changed("sensitivity"), {
		min = 0.2,
		max = 3,
		step = 0.1,
		format = function(v)
			return string.format("%.1fx", v)
		end,
	})
	UI.toggle(controls, "TOGGLE SPRINT (press once instead of holding)", s.toggleSprint, changed("toggleSprint"))

	local camera = section("CAMERA AND COMFORT", 3)
	UI.slider(camera, "FIELD OF VIEW", s.fieldOfView, changed("fieldOfView"), {
		min = 60,
		max = 90,
		step = 1,
		format = function(v)
			return string.format("%d°", v)
		end,
	})
	UI.slider(camera, "HEAD BOB", s.headBob, changed("headBob"))
	UI.slider(camera, "MOTION BLUR", s.motionBlur, changed("motionBlur"))
	UI.slider(camera, "VIGNETTE", s.vignette, changed("vignette"))
	UI.slider(camera, "CAMERA SHAKE", s.cameraShake, changed("cameraShake"))
	UI.slider(camera, "DISTORTION", s.distortion, changed("distortion"))
	UI.slider(camera, "FLICKER", s.flicker, changed("flicker"))
	UI.toggle(camera, "CROSSHAIR", s.crosshair, changed("crosshair"))
	UI.toggle(camera, "LOW INTENSITY MODE (keeps all information)", s.lowIntensity, changed("lowIntensity"))
	para(camera, "Low intensity mode cuts flicker, distortion, shake, blur, bob and static to a minimum without hiding anything you need.", 99, Theme.TextDim)

	local audio = section("AUDIO", 4)
	UI.slider(audio, "MASTER VOLUME", s.master, changed("master"))
	UI.slider(audio, "MUSIC", s.music, changed("music"))
	UI.slider(audio, "AMBIENCE", s.ambience, changed("ambience"))
	UI.slider(audio, "EFFECTS", s.effects, changed("effects"))

	local display = section("TEXT AND HELP", 5)
	UI.slider(display, "TEXT SIZE", s.textScale, changed("textScale"), {
		min = 0.8,
		max = 1.4,
		step = 0.05,
		format = function(v)
			return string.format("%d%%", math.floor(v * 100 + 0.5))
		end,
	})
	UI.toggle(display, "SUBTITLES", s.subtitles, changed("subtitles"))
	UI.toggle(display, "RADIO LOG ON HUD", s.radioLog, changed("radioLog"))
	UI.toggle(display, "TIPS AND CONTROL HINTS", s.tips, changed("tips"))
	UI.button(display, "REPLAY TUTORIAL", function()
		MenuController.close()
		State.cue:Fire({ cue = "OpenTutorial" })
	end, { LayoutOrder = 98 })

	local keysSection = section("KEY BINDINGS (" .. string.upper(Controls.device()) .. ")", 6)
	for i, action in Controls.Order do
		para(keysSection, string.format("%-16s %s", Controls.key(action), Controls.Labels[action]), i, Theme.Text)
	end
	para(keysSection, "Esc stays the Roblox menu.", 50, Theme.TextDim)

	UI.button(c, "RESET ALL SETTINGS TO DEFAULTS", function()
		State.applySettings(table.clone(ProfileSchema.DefaultSettings))
		State.saveSettingsSoon()
		MenuController.show("Settings")
	end, { LayoutOrder = 20, TextColor3 = Theme.TextDim })
end

function Pages.Store(c)
	heading(c, "DIVISION STORE", 1)
	para(c, "Everything here is optional. The whole story can be finished without spending anything. Nothing sold here makes you safer or the Presenter weaker.", 2, Theme.TextDim)
	local p = State.profile or {}
	para(c, string.format("STORED RE-ENTRIES: %d · STORED TEAM RECOVERIES: %d", p.storedRevives or 0, p.storedTeamTokens or 0), 3, Theme.Cream)
	local holder = UI.new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 4, Parent = c })
	UI.list(holder, 6)
	para(holder, "Loading...", 1, Theme.TextDim)
	task.spawn(function()
		local store = State.request("GetStore", {})
		if not holder.Parent then
			return
		end
		UI.clear(holder)
		local passes = store.passes or {}
		local products = store.products or {}
		if #passes == 0 and #products == 0 then
			para(holder, "The store is not open yet.", 1, Theme.TextDim)
			return
		end
		for i, pass in passes do
			para(holder, string.format("%s — %s", pass.name, pass.description), i * 2, Theme.Text)
			local b = UI.button(holder, pass.owned and "OWNED" or "VIEW PURCHASE", function()
				State.request("PromptPass", { pass = pass.key })
			end, { LayoutOrder = i * 2 + 1, Size = UDim2.new(0.4, 0, 0, 44) })
			if pass.owned then
				UI.setEnabled(b, false)
			end
		end
		for i, product in products do
			local order = 100 + i * 2
			para(holder, string.format("%s — %s", product.name, product.description), order, Theme.Text)
			if product.key == "EvidenceBundle" or product.key == "LobbyBundle" then
				UI.button(holder, "VIEW PURCHASE", function()
					State.request("PromptBundle", { product = product.key })
				end, { LayoutOrder = order + 1, Size = UDim2.new(0.4, 0, 0, 44) })
			else
				para(holder, "Offered during a case only when it applies. Never required.", order + 1, Theme.TextDim)
			end
		end
	end)
end

function Pages.Credits(c)
	heading(c, "CREDITS", 1)
	para(c, "DEAD AIR: CHANNEL ZERO", 2, Theme.Cream)
	para(c, "An original analog-horror mystery. Inspired by the broad genre appeal of Roblox analog horror; no maps, characters, names, UI, story or assets are copied from any other game.", 3)
	para(c, "Design brief: the eXodus team. Built with Rojo, Luau and Roblox Studio.", 4, Theme.TextDim)
	para(c, "All models in this build are original geometry made in code. Audio cues are placeholders until original or licensed sounds are added.", 5, Theme.TextDim)
end

function Pages.Pause(c)
	heading(c, "PAUSED", 1)
	para(c, "The broadcast does not stop while you are here.", 2, Theme.TextDim)
	UI.button(c, "RESUME", function()
		MenuController.close()
	end, { LayoutOrder = 3 })
	UI.button(c, "SETTINGS", function()
		MenuController.show("Settings")
	end, { LayoutOrder = 4 })
	local m = State.mission
	local someoneDown = false
	for _, p in (m and m.participants) or {} do
		if p.status == "Eliminated" then
			someoneDown = true
		end
	end
	if someoneDown and State.isAlive() and m and not m.teamTokenUsed then
		UI.button(c, "CALL A TEAM RECOVERY (TEAM VOTE)", function()
			local result = State.request("TeamRecovery", {})
			State.notify:Fire(result.ok and "Vote started." or (result.message or "Unavailable."))
			MenuController.close()
		end, { LayoutOrder = 5 })
	end
	if m and State.inMission() then
		local equipment = State.profile and State.profile.equipment
		if equipment == "Recorder" then
			heading(c, "AUDIO RECORDER LOG", 6)
			local lines = {}
			for _, entry in m.radioLog or {} do
				table.insert(lines, string.format("[%s] %s · CH%d: %s", entry.stamp, entry.sourceId, entry.channel, entry.text))
			end
			para(c, #lines > 0 and table.concat(lines, "\n") or "Nothing recorded yet.", 7, Theme.Cream)
			para(c, "LIVE CLOCK " .. Format.clock(State.broadcastClock()), 8, Theme.TextDim)
		end
		UI.button(c, "LEAVE THE CASE (NO REWARDS)", function()
			State.action("LeaveCase")
			MenuController.close()
		end, { LayoutOrder = 20, TextColor3 = Theme.Danger })
	end
end

---------------------------------------------------------------------------
-- Shell
---------------------------------------------------------------------------

local NAV = {
	{ id = "Cases", label = "CASE SELECT" },
	{ id = "Archive", label = "EVIDENCE ARCHIVE" },
	{ id = "Equipment", label = "EQUIPMENT" },
	{ id = "Settings", label = "SETTINGS" },
	{ id = "Store", label = "STORE" },
	{ id = "Credits", label = "CREDITS" },
}

local function build(playerGui)
	gui = UI.screen("DeadAirMenu", 20, playerGui)
	gui.Enabled = false
	root = UI.new("Frame", {
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	UI.modalUnlock(root)
	UI.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(1, 0.85),
		}),
		Parent = root,
	})
	local left = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 40, 0, 40), Size = UDim2.new(0.3, 0, 1, -80), Parent = root })
	UI.list(left, 8)
	UI.text(left, "NATIONAL BROADCAST RECOVERY DIVISION", { TextColor3 = Theme.TextDim, TextSize = Theme.SmallText, LayoutOrder = 1 })
	title = UI.text(left, "DEAD AIR", { FontFace = Theme.FontTitle, TextSize = 64, TextColor3 = Theme.Cream, Size = UDim2.new(1, 0, 0, 70), LayoutOrder = 2 })
	UI.text(left, "CHANNEL ZERO // SIGNAL DETECTED", { TextColor3 = Theme.Accent, LayoutOrder = 3 })
	statusLine = UI.text(left, "SIGNAL RECEIVED: 00:00:00", { TextColor3 = Theme.Amber, TextSize = Theme.SmallText, LayoutOrder = 4 })
	UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 5, Parent = left })
	nav = UI.new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 6, Parent = left })
	UI.list(nav, 6)

	local panel = UI.panel(root, { Position = UDim2.new(0.34, 0, 0, 40), Size = UDim2.new(0.63, 0, 1, -80) })
	UI.padding(panel, 16)
	content = UI.scroll(panel, { Size = UDim2.fromScale(1, 1) })
	UI.list(content, 8)
end

local function rebuildNav()
	UI.clear(nav)
	if State.inMission() then
		UI.button(nav, "RESUME", function()
			MenuController.close()
		end, { LayoutOrder = 1 })
		UI.button(nav, "PAUSE MENU", function()
			MenuController.show("Pause")
		end, { LayoutOrder = 2 })
		UI.button(nav, "SETTINGS", function()
			MenuController.show("Settings")
		end, { LayoutOrder = 3 })
		return
	end
	for i, item in NAV do
		local b = UI.button(nav, item.label, function()
			MenuController.show(item.id)
		end, { LayoutOrder = i })
		if page == item.id then
			b.TextColor3 = Theme.Accent
		end
	end
	UI.button(nav, "ENTER THE FIELD OFFICE", function()
		MenuController.close()
	end, { LayoutOrder = 50, TextColor3 = Theme.Cream })
end

function MenuController.show(pageId)
	page = pageId
	UI.clear(content)
	content.CanvasPosition = Vector2.zero
	local builder = Pages[pageId] or Pages.Home
	local ok, err = pcall(builder, content)
	if not ok then
		warn("[Menu] " .. tostring(err))
	end
	rebuildNav()
end

function MenuController.open(pageId)
	gui.Enabled = true
	State.setUI("menu", true)
	if not State.inMission() then
		startPan()
	end
	MenuController.show(pageId or (State.inMission() and "Pause" or "Home"))
	if gamepadMode() then
		local first = nav:FindFirstChildWhichIsA("TextButton")
		GuiService.SelectedObject = first
	end
end

function MenuController.close()
	gui.Enabled = false
	State.setUI("menu", false)
	GuiService.SelectedObject = nil
	stopPan()
end

function MenuController.toggle()
	if gui.Enabled then
		MenuController.close()
	else
		MenuController.open()
	end
end

function MenuController.isOpen()
	return gui.Enabled
end

function MenuController.init(playerGui, deckController)
	DeckController = deckController
	build(playerGui)
	MenuController.open("Home")
	local function refreshIfOpen()
		if gui.Enabled and page and page ~= "Settings" then
			MenuController.show(page)
		end
	end
	State.profileChanged:Connect(function(profile)
		local menuTheme = profile.equipped and Cosmetics.Items[profile.equipped.menu]
		if menuTheme and menuTheme.colour then
			Theme.applyAccent(Color3.fromRGB(menuTheme.colour[1], menuTheme.colour[2], menuTheme.colour[3]))
		end
		refreshIfOpen()
	end)
	State.partyChanged:Connect(function()
		if page == "Cases" or page == "Home" then
			refreshIfOpen()
		end
	end)
	State.cue:Connect(function(cue)
		if cue.cue == "OpenMenu" then
			MenuController.open(cue.page)
		end
	end)
	local wasInMission = false
	State.missionChanged:Connect(function(m)
		-- Deploying closes the menu; returning to the field office reopens it.
		local inMission = m ~= nil and State.inMission()
		if inMission and gui.Enabled and page ~= "Pause" and page ~= "Settings" then
			MenuController.close()
		elseif wasInMission and not inMission then
			task.delay(1, function()
				if not State.inMission() and not gui.Enabled then
					MenuController.open("Cases")
				end
			end)
		end
		wasInMission = inMission
	end)
	RunService.Heartbeat:Connect(function()
		if gui.Enabled then
			statusLine.Text = "SIGNAL RECEIVED: " .. os.date("!%H:%M:%S", math.floor(State.now()))
			local flicker = State.intensity("flicker")
			title.TextTransparency = (flicker > 0 and math.random() < 0.02 * flicker) and 0.6 or 0
		end
	end)
	-- Countdown text refresh.
	task.spawn(function()
		while true do
			task.wait(1)
			if gui.Enabled and page == "Cases" and State.party and State.party.countdownEnd then
				MenuController.show("Cases")
			end
		end
	end)
end

return MenuController
