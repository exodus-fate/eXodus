--[[
	TimelineService — the Time-Shift Deck's server side.

	Execution rules from the brief:
	  1. The client sends an event id and requested state.
	  2. The server checks the mission, the player (spectators can't edit), deck
	     access and interaction range.
	  3-4. MissionCore/TimelineCore verify the event, prerequisites and charges and
	     deduct them atomically.
	  5-6. The edit is recorded, consequences update, every client gets the new
	     timeline in the next mission snapshot.
	  7. Invalid requests are rejected without spending anything, and every edit is
	     logged for debugging and scoring.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local MapLayout = require(Shared.Config.MapLayout)

local Router = require(script.Parent.Router)

local TimelineService = {}

local DECK_RANGE = 14

TimelineService.openDecks = {} -- [player] = deckId | "HANDHELD" | "ARCHIVE"

local deps

local function nearDeck(player, mission, deckId)
	local deck = mission.case.decks[deckId]
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not deck or not hrp then
		return false
	end
	local pos = Vector3.new(deck.pos.x, deck.pos.y, deck.pos.z)
	return (hrp.Position - pos).Magnitude <= DECK_RANGE
end

function TimelineService.init(dependencies)
	deps = dependencies

	Router.onAction("DeckOpen", function(player, payload)
		local mission = deps.MissionService.mission
		if not mission or not mission:participant(player.UserId) then
			return
		end
		local deckId = payload.deck
		if deckId == "HANDHELD" then
			TimelineService.openDecks[player] = "HANDHELD"
			mission:setWatching(player.UserId, true)
			return
		end
		if not Router.string(deckId, 32) or not mission.case.decks[deckId] or not nearDeck(player, mission, deckId) then
			return
		end
		local tapeId = Router.string(payload.tape, 16) and payload.tape or nil
		if mission:deckOpened(player.UserId, deckId, tapeId, workspace:GetServerTimeNow()) then
			TimelineService.openDecks[player] = deckId
			deps.MissionService.markDirty()
		end
	end, { rate = 4, burst = 8 })

	Router.onAction("DeckClose", function(player)
		local mission = deps.MissionService.mission
		TimelineService.openDecks[player] = nil
		if mission then
			mission:deckClosed(player.UserId)
			mission:setWatching(player.UserId, false)
		end
	end)

	Router.onAction("InspectEvent", function(player, payload)
		local mission = deps.MissionService.mission
		if mission and Router.string(payload.event, 40) then
			mission:inspectEvent(player.UserId, payload.event, workspace:GetServerTimeNow())
		end
	end)

	Router.onRequest("CommitEdit", function(player, payload)
		local mission = deps.MissionService.mission
		if not mission then
			return { ok = false, code = "PHASE", message = "No case is running." }
		end
		if not Router.string(payload.event, 40) or not Router.string(payload.state, 32) or not Router.string(payload.deck, 32) then
			return { ok = false, code = "INVALID_STATE", message = "Malformed edit." }
		end
		local deckId = payload.deck
		if TimelineService.openDecks[player] ~= deckId or not nearDeck(player, mission, deckId) then
			return { ok = false, code = "NO_DECK", message = "Stand at the deck to edit." }
		end
		local now = workspace:GetServerTimeNow()
		local ok, code, message = mission:commitEdit(player.UserId, payload.event, payload.state, {
			deckId = deckId,
			expectedState = Router.string(payload.expected, 32) and payload.expected or nil,
			signalOk = deps.SignalService.canEdit(mission, deckId, payload.event),
		}, now)
		print(string.format("[Timeline] %s edit %s -> %s : %s", player.Name, payload.event, payload.state, ok and "OK" or tostring(code)))
		deps.MissionService.markDirty()
		return { ok = ok, code = code, message = message, charges = mission.charges }
	end, { rate = 2, burst = 4 })

	Router.onRequest("MarkFrame", function(player, payload)
		if not Router.string(payload.tape, 16) or not Router.string(payload.camera, 16) or not Router.number(payload.t, 0, 600) then
			return { ok = false, message = "Malformed." }
		end
		local mission = deps.MissionService.mission
		if mission and mission:participant(player.UserId) and mission:tapeFound(payload.tape) then
			local ok, result = mission:markFrame(player.UserId, payload.tape, payload.camera, payload.t, workspace:GetServerTimeNow())
			deps.MissionService.markDirty()
			return { ok = ok, message = ok and nil or result, frame = ok and result or nil }
		end
		return deps.EvidenceService.markArchiveFrame(player, payload.tape, payload.camera, payload.t)
	end, { rate = 2, burst = 4 })

	Players.PlayerRemoving:Connect(function(player)
		TimelineService.openDecks[player] = nil
	end)
end

function TimelineService.closeAll()
	TimelineService.openDecks = {}
end

-- Used by the camera feed list in the deck UI.
TimelineService.Cameras = MapLayout.Cameras

return TimelineService
