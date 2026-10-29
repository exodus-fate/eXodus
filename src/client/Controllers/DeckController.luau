--[[
	DeckController — the Time-Shift Deck screen.

	Modes:
	  mission   at a physical deck: inspect tapes and commit edits
	  spectate  eliminated/extracted players: watch the team's tapes, no edits
	  handheld  the handheld monitor: live cameras only, no tapes, no edits
	  archive   field office replay of recovered tapes (original predictions),
	            hidden frames can be marked

	The client only proposes edits. The server validates and commits them; the
	new timeline arrives in the next mission snapshot and the footage updates.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CaseRegistry = require(Shared.Config.CaseRegistry)
local MapLayout = require(Shared.Config.MapLayout)
local Footage = require(Shared.Core.Footage)
local SignalModel = require(Shared.Core.SignalModel)
local Format = require(Shared.Util.Format)

local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local FootageView = require(script.Parent.Parent.UI.FootageView)

local DeckController = {}

local SPEEDS = { 1, 2, 4 }
local FRAME = 1 / Format.FRAMES_PER_SECOND
local WALK_AWAY = 16

local gui, root
local view
local widgets = {}
local session = nil -- { mode, deckId, caseDef, tapeId, cameraId, t, playing, speed, selected, proposed }
local renderConn = nil
local lastMarkerKey = nil

local function toV3(p)
	return Vector3.new(p.x, p.y or 0, p.z)
end

local function presenterPosition()
	for _, model in Workspace:GetChildren() do
		if model.Name == "Presenter" and model:IsA("Model") and model.PrimaryPart then
			return model.PrimaryPart.Position
		end
	end
	return nil
end

local function snapshotTimeline()
	if session.mode == "archive" then
		return nil
	end
	local m = State.mission
	return m and m.timeline or nil
end

local function tapesAvailable()
	local list = {}
	local caseDef = session.caseDef
	if not caseDef then
		return list
	end
	for _, tapeId in caseDef.tapeOrder do
		local has
		if session.mode == "archive" then
			has = State.profile and State.profile.tapes and State.profile.tapes[tapeId]
		else
			has = State.hasTape(tapeId)
		end
		if has then
			table.insert(list, tapeId)
		end
	end
	return list
end

local function camerasForSession()
	if session.mode == "handheld" then
		return MapLayout.CameraOrder
	end
	local tape = session.tapeId and session.caseDef.tapes[session.tapeId]
	return tape and tape.cameras or {}
end

local function cameraQuality(cameraId)
	if session.mode == "archive" then
		return 85, nil
	end
	local m = State.mission
	local camera = MapLayout.Cameras[cameraId]
	if not m or not camera then
		return 0, "NO CAMERA"
	end
	local presenter = presenterPosition()
	local deck = session.deckId and session.caseDef.decks[session.deckId]
	local relayOn = true
	if camera.relay == "WEST" or camera.relay == "EAST" then
		relayOn = m.relays and m.relays[camera.relay] ~= false
	end
	return SignalModel.cameraQuality({
		relay = camera.relay,
		powerOn = m.flags and m.flags.generator_restored == true,
		relayOn = relayOn,
		deckBattery = session.mode ~= "mission" or (deck and deck.battery == true),
		presenterDistance = presenter and (presenter - toV3(camera.pos)).Magnitude or nil,
		anomaly = m.loop and m.loop.active and table.find(camera.rooms, session.caseDef.loop.room) ~= nil,
	})
end

local function garble(text, quality)
	if quality >= SignalModel.CLEAR then
		return text
	end
	local out = {}
	for i = 1, #text do
		local ch = string.sub(text, i, i)
		if ch ~= " " and (i * 7 + #text) % 3 == 0 then
			table.insert(out, "#")
		else
			table.insert(out, ch)
		end
	end
	return table.concat(out)
end

local function tapeClock(tapeId, t)
	local tape = session.caseDef.tapes[tapeId]
	local m = State.mission
	local tl = snapshotTimeline()
	local anchor = tl and tl.anchors and tl.anchors[tape.anchor]
	if session.mode ~= "archive" and anchor and m and m.broadcastStart then
		return Format.timecode(anchor - m.broadcastStart + t), anchor
	end
	return "T+" .. Format.timecode(t), nil
end

local function eventById(eventId)
	local defs = State.eventDefs(session.caseDef, State.mission and State.mission.patrolFlip)
	return defs and defs[eventId]
end

local function eventRecord(eventId)
	local tl = snapshotTimeline()
	return tl and tl.events and tl.events[eventId]
end

---------------------------------------------------------------------------
-- Building the screen
---------------------------------------------------------------------------

local function build(playerGui)
	gui = UI.screen("DeadAirDeck", 10, playerGui)
	gui.Enabled = false
	root = UI.new("Frame", {
		Name = "Deck",
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	UI.modalUnlock(root)
	UI.padding(root, 14, 12)

	-- Header
	local header = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = root })
	widgets.title = UI.text(header, "TIME-SHIFT DECK", {
		FontFace = Theme.FontBold,
		TextSize = Theme.LargeText,
		TextColor3 = Theme.Accent,
		Size = UDim2.new(0.6, 0, 1, 0),
	})
	widgets.charges = UI.text(header, "", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -60, 0, 0),
		Size = UDim2.new(0.35, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Cream,
	})
	widgets.close = UI.button(header, "X", function()
		DeckController.close()
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(48, 36) })

	local body = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 44), Size = UDim2.new(1, 0, 1, -44), Parent = root })

	-- Left: tapes and cameras
	local left = UI.panel(body, { Size = UDim2.new(0.2, -8, 1, 0) })
	UI.padding(left, 8)
	UI.text(left, "TAPES", { TextColor3 = Theme.TextDim, Size = UDim2.new(1, 0, 0, 18) })
	widgets.tapes = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 22), Size = UDim2.new(1, 0, 0.42, -22), Parent = left })
	UI.list(widgets.tapes, 4)
	UI.text(left, "CAMERAS", { TextColor3 = Theme.TextDim, Position = UDim2.new(0, 0, 0.44, 0), Size = UDim2.new(1, 0, 0, 18) })
	widgets.cameras = UI.scroll(left, { Position = UDim2.new(0, 0, 0.44, 22), Size = UDim2.new(1, 0, 0.56, -22) })
	UI.list(widgets.cameras, 4)

	-- Centre: footage, scrubber, transport
	local centre = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.2, 0, 0, 0), Size = UDim2.new(0.52, -8, 1, 0), Parent = body })
	local screenHolder = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -104), Parent = centre })
	local screen = UI.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = screenHolder,
	})
	UI.new("UIAspectRatioConstraint", { AspectRatio = 4 / 3, Parent = screen })
	UI.stroke(screen, Theme.Line, 2)
	view = FootageView.new(screen)

	widgets.scrubber = UI.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -98),
		Size = UDim2.new(1, 0, 0, 34),
		Selectable = false,
		Parent = centre,
	})
	UI.stroke(widgets.scrubber, Theme.Line)
	widgets.markers = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = widgets.scrubber })
	widgets.nowMarker = UI.new("Frame", {
		BackgroundColor3 = Theme.Cream,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 2, 1, 0),
		ZIndex = 2,
		Parent = widgets.scrubber,
	})
	widgets.playhead = UI.new("Frame", {
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0, 3, 1, 8),
		Position = UDim2.new(0, 0, 0, -4),
		ZIndex = 4,
		Parent = widgets.scrubber,
	})
	widgets.scrubLabel = UI.text(centre, "", {
		Position = UDim2.new(0, 0, 1, -62),
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = Theme.TextDim,
		TextSize = Theme.SmallText,
	})

	local transport = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -44), Size = UDim2.new(1, 0, 0, 44), Parent = centre })
	UI.list(transport, 6, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	local function tbtn(text, fn, width)
		return UI.button(transport, text, fn, { Size = UDim2.fromOffset(width or 56, 44) })
	end
	tbtn("-1s", function()
		DeckController.seek(session.t - 1)
	end)
	tbtn("<|", function()
		DeckController.seek(session.t - FRAME)
	end)
	widgets.play = tbtn("PLAY", function()
		session.playing = not session.playing
	end, 76)
	tbtn("|>", function()
		DeckController.seek(session.t + FRAME)
	end)
	tbtn("+1s", function()
		DeckController.seek(session.t + 1)
	end)
	widgets.speed = tbtn("1x", function()
		local i = table.find(SPEEDS, session.speed) or 1
		session.speed = SPEEDS[(i % #SPEEDS) + 1]
	end, 48)
	widgets.mark = tbtn("MARK FRAME", function()
		DeckController.markFrame()
	end, 120)

	-- Right: event panel
	local right = UI.panel(body, { Position = UDim2.new(0.72, 0, 0, 0), Size = UDim2.new(0.28, 0, 1, 0) })
	UI.padding(right, 10)
	local scroll = UI.scroll(right, { Size = UDim2.new(1, 0, 1, -112) })
	UI.list(scroll, 6)
	widgets.eventTitle = UI.text(scroll, "", { FontFace = Theme.FontBold, TextColor3 = Theme.Accent, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
	widgets.eventMeta = UI.text(scroll, "", { TextColor3 = Theme.TextDim, TextSize = Theme.SmallText, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	widgets.eventState = UI.text(scroll, "", { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 })
	widgets.alternatives = UI.new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 4, Parent = scroll })
	UI.list(widgets.alternatives, 4)
	widgets.proposed = UI.text(scroll, "", { TextColor3 = Theme.Cream, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5 })
	widgets.warning = UI.text(scroll, "", { TextColor3 = Theme.Amber, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 6 })
	widgets.clue = UI.text(scroll, "", { TextColor3 = Theme.Text, TextSize = Theme.SmallText, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 7 })
	widgets.reason = UI.text(scroll, "", { TextColor3 = Theme.Danger, TextSize = Theme.SmallText, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 8 })

	local actions = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -104), Size = UDim2.new(1, 0, 0, 104), Parent = right })
	widgets.commit = UI.button(actions, "COMMIT EDIT", function()
		DeckController.commit()
	end, { Size = UDim2.new(1, 0, 0, 48), TextColor3 = Theme.Accent })
	widgets.cancel = UI.button(actions, "CANCEL", function()
		session.proposed = nil
		DeckController.refreshPanel()
	end, { Position = UDim2.new(0, 0, 0, 56), Size = UDim2.new(0.48, 0, 0, 44) })
	UI.button(actions, "CLOSE", function()
		DeckController.close()
	end, { Position = UDim2.new(0.52, 0, 0, 56), Size = UDim2.new(0.48, 0, 0, 44) })

	-- Scrubbing
	local dragging = false
	local function scrubTo(x)
		local tape = session and session.tapeId and session.caseDef.tapes[session.tapeId]
		if not tape then
			return
		end
		local alpha = math.clamp((x - widgets.scrubber.AbsolutePosition.X) / math.max(1, widgets.scrubber.AbsoluteSize.X), 0, 1)
		DeckController.seek(alpha * tape.duration)
	end
	widgets.scrubber.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			scrubTo(input.Position.X)
		end
	end)
	widgets.scrubber.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			scrubTo(input.Position.X)
		end
	end)
	widgets.scrubber.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

---------------------------------------------------------------------------
-- Lists
---------------------------------------------------------------------------

local lastTapesKey = nil

local function refreshTapes(force)
	local key = session.mode .. ":" .. tostring(session.tapeId) .. ":" .. table.concat(tapesAvailable(), ",")
	if not force and key == lastTapesKey then
		return
	end
	lastTapesKey = key
	UI.clear(widgets.tapes)
	if session.mode == "handheld" then
		UI.text(widgets.tapes, "LIVE FEEDS", { TextColor3 = Theme.Accent })
		UI.text(widgets.tapes, "Handheld monitors cannot play tapes or edit.", { TextColor3 = Theme.TextDim, TextSize = Theme.SmallText, Size = UDim2.new(1, 0, 0, 40) })
		return
	end
	local tapes = tapesAvailable()
	if #tapes == 0 then
		UI.text(widgets.tapes, "No tapes recovered yet.", { TextColor3 = Theme.TextDim, Size = UDim2.new(1, 0, 0, 40) })
	end
	for _, tapeId in tapes do
		local tape = session.caseDef.tapes[tapeId]
		local b = UI.button(widgets.tapes, tape.label .. "  " .. tape.title, function()
			DeckController.selectTape(tapeId)
		end, { TextSize = Theme.SmallText, TextXAlignment = Enum.TextXAlignment.Left })
		UI.padding(b, 8, 0)
		if tapeId == session.tapeId then
			b.TextColor3 = Theme.Accent
		end
	end
end

local function refreshCameras()
	UI.clear(widgets.cameras)
	for _, cameraId in camerasForSession() do
		local camera = MapLayout.Cameras[cameraId]
		local quality = cameraQuality(cameraId)
		local b = UI.button(widgets.cameras, string.format("%s  %d%%", camera.label, quality), function()
			DeckController.selectCamera(cameraId)
		end, { TextSize = Theme.SmallText, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -8, 0, 40) })
		UI.padding(b, 8, 0)
		b.Name = cameraId
		if cameraId == session.cameraId then
			b.TextColor3 = Theme.Accent
		end
	end
end

local function updateCameraLabels()
	for _, b in widgets.cameras:GetChildren() do
		if b:IsA("TextButton") then
			local camera = MapLayout.Cameras[b.Name]
			if camera then
				b.Text = string.format("%s  %d%%", camera.label, cameraQuality(b.Name))
			end
		end
	end
end

local function markerColour(marker)
	if marker.fired then
		return Theme.TextDim
	elseif marker.committed then
		return Theme.Cream
	elseif marker.editable then
		return Theme.Accent
	end
	return Theme.Amber
end

local function refreshMarkers(force)
	if session.mode == "handheld" or not session.tapeId then
		UI.clear(widgets.markers)
		lastMarkerKey = nil
		return
	end
	local tape = session.caseDef.tapes[session.tapeId]
	local quality = cameraQuality(session.cameraId)
	local markers = Footage.markers(session.caseDef, State.eventDefs(session.caseDef, State.mission and State.mission.patrolFlip), snapshotTimeline(), session.tapeId)
	local parts = { session.tapeId, tostring(quality >= SignalModel.WEAK) }
	for _, mk in markers do
		table.insert(parts, mk.eventId .. mk.state .. tostring(mk.fired) .. tostring(mk.committed ~= nil))
	end
	local key = table.concat(parts, "|")
	if not force and key == lastMarkerKey then
		return
	end
	lastMarkerKey = key
	UI.clear(widgets.markers)
	if quality < SignalModel.WEAK then
		return
	end
	for _, mk in markers do
		-- Diamond = editable event, circle = consequence.
		local b = UI.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = markerColour(mk),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(mk.t / tape.duration, 0.5),
			Size = UDim2.fromOffset(14, 14),
			Rotation = mk.editable and 45 or 0,
			ZIndex = 5,
			Selectable = true,
			Parent = widgets.markers,
		})
		if not mk.editable then
			UI.new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = b })
		end
		if session.selected == mk.eventId then
			UI.stroke(b, Theme.Text, 2)
		end
		b.Activated:Connect(function()
			DeckController.selectEvent(mk.eventId)
		end)
	end
end

---------------------------------------------------------------------------
-- Event panel
---------------------------------------------------------------------------

local function commitBlockReason(ev, rec)
	local m = State.mission
	if session.mode ~= "mission" then
		return session.mode == "archive" and "Archive copies are read-only." or "Edits are only possible at a tape deck."
	end
	if not State.isAlive() then
		return "Spectators can watch the timeline but cannot edit it."
	end
	if not ev.isEditable then
		local source = ev.derivedFrom and eventById(ev.derivedFrom)
		return "This follows from " .. (source and source.label or "another event") .. ". Edit that instead."
	end
	if rec and rec.fired then
		return "This event has already happened."
	end
	if rec and rec.edits >= (ev.maxEdits or 1) then
		return "Already edited" .. (rec.committed and rec.committed.name and (" by " .. rec.committed.name) or "") .. "."
	end
	if rec and rec.locked then
		return "Locked — the event is about to play out."
	end
	for _, flag in ev.prerequisites or {} do
		if not (m.flags and m.flags[flag]) then
			return "Requires: " .. ((session.caseDef.flagLabels and session.caseDef.flagLabels[flag]) or flag) .. "."
		end
	end
	if (m.charges or 0) < (ev.editCost or 1) then
		return "No edit charges left."
	end
	if cameraQuality(session.cameraId) < SignalModel.WEAK then
		local any = false
		for _, cam in ev.cameras do
			if cameraQuality(cam) >= SignalModel.WEAK then
				any = true
			end
		end
		if not any then
			return "Signal too weak to edit. Reset the relay or try another camera."
		end
	end
	if not session.proposed then
		return "Choose an alternative state above."
	end
	return nil
end

function DeckController.refreshPanel()
	if not session then
		return
	end
	local m = State.mission
	if widgets.charges then
		if m and session.mode ~= "archive" then
			widgets.charges.Text = string.format("EDIT CHARGES %d / %d", m.charges or 0, m.maxCharges or 0)
		else
			widgets.charges.Text = session.mode == "archive" and "ARCHIVE COPY" or ""
		end
	end
	UI.clear(widgets.alternatives)
	local eventId = session.selected
	local ev = eventId and eventById(eventId)
	if not ev then
		widgets.eventTitle.Text = session.mode == "handheld" and "LIVE MONITOR" or "NO EVENT SELECTED"
		widgets.eventMeta.Text = session.mode == "handheld" and "Watching raises its awareness of you." or "Select a marker on the timeline. Diamond = editable · circle = consequence."
		widgets.eventState.Text = ""
		widgets.proposed.Text = ""
		widgets.warning.Text = ""
		widgets.clue.Text = ""
		widgets.reason.Text = ""
		widgets.commit.Visible = session.mode == "mission"
		UI.setEnabled(widgets.commit, false)
		widgets.cancel.Visible = false
		return
	end
	local rec = eventRecord(eventId)
	local current = (rec and rec.state) or ev.originalState
	local tape = session.caseDef.tapes[ev.tape]
	local clockText = tapeClock(ev.tape, ev.offset)
	widgets.eventTitle.Text = string.upper(ev.label)
	widgets.eventMeta.Text = string.format("%s · %s · %s · %s", tape.label, Format.relative(ev.offset), clockText, MapLayout.Rooms[ev.locationId] and MapLayout.Rooms[ev.locationId].label or ev.locationId)
	local lines = {
		"ORIGINAL: " .. (ev.stateLabels[ev.originalState] or ev.originalState),
		"PREDICTED: " .. (ev.stateLabels[current] or current),
	}
	if rec and rec.committed then
		table.insert(lines, string.format("EDITED BY %s", string.upper(rec.committed.name or "?")))
	end
	if rec and rec.fired then
		table.insert(lines, "STATUS: OCCURRED")
	elseif rec and rec.locked then
		table.insert(lines, "STATUS: LOCKED — IMMINENT")
	end
	if not ev.isEditable then
		table.insert(lines, "CONSEQUENCE — NOT DIRECTLY EDITABLE")
	end
	widgets.eventState.Text = table.concat(lines, "\n")

	local reason = commitBlockReason(ev, rec)
	if ev.isEditable and session.mode == "mission" then
		for _, state in ev.allowedStates do
			if state ~= current then
				local b = UI.button(widgets.alternatives, "> " .. (ev.stateLabels[state] or state), function()
					session.proposed = state
					DeckController.refreshPanel()
				end, { TextSize = Theme.SmallText })
				if session.proposed == state then
					b.TextColor3 = Theme.Accent
				end
			end
		end
	end
	widgets.proposed.Text = session.proposed and ("PROPOSED: " .. (ev.stateLabels[session.proposed] or session.proposed)) or ""
	local quality = cameraQuality(session.cameraId)
	if ev.warning and #(ev.consequenceEventIds or {}) > 0 then
		widgets.warning.Text = ev.warning
		local clue = ev.clue or ""
		if State.mission and State.mission.mode == "Restricted" then
			clue = ""
		end
		widgets.clue.Text = clue ~= "" and ("CLUE: " .. garble(clue, quality)) or ""
	else
		widgets.warning.Text = ""
		widgets.clue.Text = ""
	end
	widgets.commit.Visible = session.mode == "mission" and ev.isEditable
	widgets.commit.Text = string.format("COMMIT EDIT (%d CHARGE%s)", ev.editCost or 1, (ev.editCost or 1) == 1 and "" or "S")
	UI.setEnabled(widgets.commit, reason == nil)
	widgets.cancel.Visible = session.proposed ~= nil
	widgets.reason.Text = reason or ""
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

local function liveActors(cameraId)
	local camera = MapLayout.Cameras[cameraId]
	local actors = {}
	local presenter = presenterPosition()
	if presenter then
		local pos = { x = presenter.X, y = 0, z = presenter.Z }
		if MapLayout.inRooms(pos, camera.rooms, 1) then
			table.insert(actors, { kind = "Presenter", pos = pos, look = { x = camera.pos.x, y = 0, z = camera.pos.z } })
		end
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local pos = { x = hrp.Position.X, y = 0, z = hrp.Position.Z }
			if MapLayout.inRooms(pos, camera.rooms, 0.5) then
				local look = hrp.Position + hrp.CFrame.LookVector * 4
				table.insert(actors, { kind = "Investigator", pos = pos, look = { x = look.X, y = 0, z = look.Z } })
			end
		end
	end
	return actors
end

local function liveLights(cameraId)
	local camera = MapLayout.Cameras[cameraId]
	local station = Workspace:FindFirstChild("Station04")
	local folder = station and station:FindFirstChild("Rooms") and station.Rooms:FindFirstChild(camera.rooms[1])
	return folder and folder:GetAttribute("LightMode") or "off"
end

local function render(dt)
	if not session then
		return
	end
	local intensity = State.intensity("distortion")
	local cameraId = session.cameraId
	if not cameraId then
		view:setTexts({ message = "SELECT A TAPE", timestamp = "", status = "" })
		view:step(dt)
		return
	end
	local quality, reason = cameraQuality(cameraId)
	view:setSignal(quality, intensity)
	if session.mode == "handheld" then
		if quality <= 0 then
			view:setActors({})
			view:setLights("off")
			view:setTexts({ message = reason or "NO CARRIER", timestamp = "LIVE", status = "" })
		else
			view:setActors(liveActors(cameraId))
			view:setLights(liveLights(cameraId))
			view:setTexts({
				message = quality < SignalModel.WEAK and (reason or "SIGNAL LOST") or "",
				timestamp = "LIVE " .. Format.clock(State.broadcastClock()),
				status = string.format("SIGNAL %d%% · %s", quality, SignalModel.band(quality)),
				hidden = "",
			})
		end
		view:step(dt)
		return
	end

	local tape = session.caseDef.tapes[session.tapeId]
	if session.playing then
		session.t = math.min(tape.duration, session.t + dt * session.speed)
		if session.t >= tape.duration then
			session.playing = false
		end
	end
	widgets.play.Text = session.playing and "PAUSE" or "PLAY"
	widgets.speed.Text = session.speed .. "x"
	widgets.playhead.Position = UDim2.new(session.t / tape.duration, 0, 0, -4)

	local clock, anchor = tapeClock(session.tapeId, session.t)
	local nowRel = anchor and (State.now() - anchor) or nil
	if nowRel and nowRel >= 0 and nowRel <= tape.duration then
		widgets.nowMarker.Visible = true
		widgets.nowMarker.Position = UDim2.fromScale(nowRel / tape.duration, 0)
	else
		widgets.nowMarker.Visible = false
	end
	local tag
	if session.mode == "archive" then
		tag = "ARCHIVE"
	elseif not anchor then
		local labels = session.caseDef.flagLabels or {}
		tag = "AWAITING " .. string.upper(labels[tape.anchor] or string.gsub(tape.anchor, "_", " "))
	elseif nowRel and session.t <= nowRel then
		tag = "RECORDED"
	else
		tag = "PREDICTED"
	end
	widgets.scrubLabel.Text = string.format("%s · %s · FRAME %06d · %s", tape.label, Format.relative(session.t), Format.frameNumber(session.t), tag)

	if quality <= 0 then
		view:setActors({})
		view:setLights("off")
		view:setTexts({ message = reason or "NO CARRIER", timestamp = "PLAY " .. clock, status = "", hidden = "" })
	else
		local frame = Footage.frame(session.caseDef, State.eventDefs(session.caseDef, State.mission and State.mission.patrolFlip), snapshotTimeline(), session.tapeId, cameraId, session.t)
		view:setActors(frame.actors)
		view:setLights(frame.lights)
		view:setTexts({
			message = quality < SignalModel.WEAK and ((reason or "SIGNAL LOST") .. "\nMARKERS UNAVAILABLE") or "",
			timestamp = (session.playing and "PLAY " or "PAUSE ") .. clock,
			status = string.format("SIGNAL %d%% · %s%s", quality, SignalModel.band(quality), reason and (" · " .. reason) or ""),
			hidden = (frame.hiddenFrame and quality >= SignalModel.WEAK) and frame.hiddenFrame.text or "",
		})
	end
	view:step(dt)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function DeckController.seek(t)
	if not session or not session.tapeId then
		return
	end
	local tape = session.caseDef.tapes[session.tapeId]
	session.t = math.clamp(t, 0, tape.duration)
end

function DeckController.selectTape(tapeId)
	session.tapeId = tapeId
	session.t = 0
	session.selected = nil
	session.proposed = nil
	local tape = session.caseDef.tapes[tapeId]
	session.cameraId = tape.cameras[1]
	view:setCamera(session.cameraId)
	if session.mode == "mission" then
		State.action("DeckOpen", { deck = session.deckId, tape = tapeId })
	end
	refreshTapes(true)
	refreshCameras()
	refreshMarkers(true)
	DeckController.refreshPanel()
end

function DeckController.selectCamera(cameraId)
	session.cameraId = cameraId
	view:setCamera(cameraId)
	refreshCameras()
	refreshMarkers(true)
end

function DeckController.selectEvent(eventId)
	session.selected = eventId
	session.proposed = nil
	local ev = eventById(eventId)
	if ev then
		session.t = ev.offset
		if not table.find(ev.cameras, session.cameraId) and ev.cameras[1] then
			DeckController.selectCamera(ev.cameras[1])
		end
	end
	if session.mode ~= "archive" and session.mode ~= "handheld" then
		State.action("InspectEvent", { event = eventId })
	end
	DeckController.refreshPanel()
end

function DeckController.commit()
	if not session or not session.selected or not session.proposed then
		return
	end
	local ev = eventById(session.selected)
	local rec = eventRecord(session.selected)
	local result = State.request("CommitEdit", {
		event = session.selected,
		state = session.proposed,
		deck = session.deckId,
		expected = (rec and rec.state) or (ev and ev.originalState),
	})
	if result.ok then
		State.notify:Fire("Edit committed. The tape is updating.")
		session.proposed = nil
		State.cue:Fire({ cue = "LocalEditCommitted" })
	else
		widgets.reason.Text = result.message or "Edit refused."
	end
	DeckController.refreshPanel()
end

function DeckController.markFrame()
	if not session or not session.tapeId then
		return
	end
	local result = State.request("MarkFrame", { tape = session.tapeId, camera = session.cameraId, t = session.t })
	State.notify:Fire(result.ok and ("Hidden frame marked: " .. (result.message or result.frame or "")) or (result.message or "Nothing unusual."))
end

--[[
	opts = { mode = "mission" | "spectate" | "handheld" | "archive", deckId, caseId, tapeId }
]]
function DeckController.open(opts)
	local caseDef = opts.caseId and CaseRegistry.get(opts.caseId) or State.caseDef() or CaseRegistry.get("case01")
	session = {
		mode = opts.mode,
		deckId = opts.deckId,
		caseDef = caseDef,
		tapeId = nil,
		cameraId = nil,
		t = 0,
		playing = false,
		speed = 1,
		selected = nil,
		proposed = nil,
	}
	local deck = opts.deckId and caseDef.decks[opts.deckId]
	if opts.mode == "handheld" then
		widgets.title.Text = "HANDHELD MONITOR · LIVE"
	elseif opts.mode == "archive" then
		widgets.title.Text = "EVIDENCE ARCHIVE · TAPE REPLAY"
	elseif opts.mode == "spectate" then
		widgets.title.Text = "TIME-SHIFT DECK · OBSERVER"
	else
		widgets.title.Text = "TIME-SHIFT DECK · " .. (deck and deck.label or "")
	end
	widgets.mark.Visible = opts.mode ~= "handheld"
	widgets.scrubber.Visible = opts.mode ~= "handheld"
	gui.Enabled = true
	State.setUI("deck", true)
	view:powerOn()
	if opts.mode == "mission" then
		State.action("DeckOpen", { deck = opts.deckId })
	elseif opts.mode == "handheld" then
		State.action("DeckOpen", { deck = "HANDHELD" })
	end
	if opts.mode == "handheld" then
		session.cameraId = MapLayout.CameraOrder[1]
		view:setCamera(session.cameraId)
		refreshTapes()
		refreshCameras()
		refreshMarkers(true)
	else
		local tapes = tapesAvailable()
		local first = opts.tapeId or tapes[#tapes]
		refreshTapes()
		if first then
			DeckController.selectTape(first)
		else
			refreshCameras()
			refreshMarkers(true)
		end
	end
	DeckController.refreshPanel()
	if GuiService:IsTenFootInterface() or #game:GetService("UserInputService"):GetConnectedGamepads() > 0 then
		GuiService.SelectedObject = widgets.close
	end
	if renderConn then
		renderConn:Disconnect()
	end
	local accum = 0
	renderConn = RunService.RenderStepped:Connect(function(dt)
		render(dt)
		accum += dt
		if accum > 0.5 then
			accum = 0
			updateCameraLabels()
			refreshMarkers(false)
			DeckController.refreshPanel()
			-- Walking away (or being taken off-air) closes the deck.
			if session and session.mode == "mission" then
				local deckDef = session.caseDef.decks[session.deckId]
				local character = Players.LocalPlayer.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if not State.isAlive() or not hrp or (deckDef and (hrp.Position - toV3(deckDef.pos)).Magnitude > WALK_AWAY) then
					DeckController.close()
				end
			end
		end
	end)
	ContextActionService:BindActionAtPriority("DeckKeys", function(_, inputState, input)
		if inputState ~= Enum.UserInputState.Begin or not session then
			return Enum.ContextActionResult.Pass
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Space then
			session.playing = not session.playing
		elseif key == Enum.KeyCode.Left or key == Enum.KeyCode.DPadLeft then
			DeckController.seek(session.t - FRAME)
		elseif key == Enum.KeyCode.Right or key == Enum.KeyCode.DPadRight then
			DeckController.seek(session.t + FRAME)
		elseif key == Enum.KeyCode.ButtonB or key == Enum.KeyCode.Backspace then
			DeckController.close()
		else
			return Enum.ContextActionResult.Pass
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.Space, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
end

function DeckController.close()
	if not session then
		return
	end
	local mode = session.mode
	session = nil
	gui.Enabled = false
	State.setUI("deck", false)
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	ContextActionService:UnbindAction("DeckKeys")
	GuiService.SelectedObject = nil
	if mode == "mission" or mode == "handheld" then
		State.action("DeckClose")
	end
end

function DeckController.isOpen()
	return session ~= nil
end

-- Nearest physical deck within reach, or nil.
function DeckController.nearbyDeck()
	local caseDef = State.caseDef()
	local character = Players.LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not caseDef or not hrp then
		return nil
	end
	local best, bestDist = nil, 10
	for deckId, deck in caseDef.decks do
		local d = (hrp.Position - toV3(deck.pos)).Magnitude
		if d < bestDist then
			best, bestDist = deckId, d
		end
	end
	return best
end

function DeckController.init(playerGui)
	build(playerGui)
	State.cue:Connect(function(cue)
		if cue.cue == "OpenDeck" and not session then
			DeckController.open({ mode = "mission", deckId = cue.deck })
		end
	end)
	State.missionChanged:Connect(function(m)
		if not session then
			return
		end
		if not m and session.mode ~= "archive" then
			DeckController.close()
			return
		end
		refreshTapes()
		refreshMarkers(false)
		DeckController.refreshPanel()
	end)
end

return DeckController
