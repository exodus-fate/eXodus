--[[
	SignalService — deterministic signal quality.

	Per player (HUD meter, replicated as the "Signal" attribute) and per camera
	(what a deck can show, and whether an edit can be made). Uses the shared
	SignalModel so the client's deck renders exactly what the server validates.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local SignalModel = require(Shared.Core.SignalModel)
local MapLayout = require(Shared.Config.MapLayout)

local SignalService = {}

local deps

local function toV3(p)
	return Vector3.new(p.x, p.y or 0, p.z)
end

local function anomalyIn(mission, rooms)
	if not mission or not mission.loop.active then
		return false
	end
	return table.find(rooms, mission.case.loop.room) ~= nil
end

function SignalService.cameraQuality(mission, deckId, cameraId)
	local camera = MapLayout.Cameras[cameraId]
	local deck = mission.case.decks[deckId]
	if not camera then
		return 0, "NO CAMERA"
	end
	local presenter = deps.EntityService.position()
	local relayOn = true
	if camera.relay == "WEST" or camera.relay == "EAST" then
		relayOn = mission.relays[camera.relay] ~= false
	end
	return SignalModel.cameraQuality({
		relay = camera.relay,
		powerOn = mission.flags.generator_restored == true,
		relayOn = relayOn,
		deckBattery = deck ~= nil and deck.battery == true,
		presenterDistance = presenter and (presenter - toV3(camera.pos)).Magnitude or nil,
		anomaly = anomalyIn(mission, camera.rooms),
	})
end

-- An edit needs at least one camera showing the event with a usable signal.
function SignalService.canEdit(mission, deckId, eventId)
	local ev = mission.timeline:getEvent(eventId)
	if not ev then
		return false
	end
	for _, cameraId in ev.cameras or {} do
		if SignalService.cameraQuality(mission, deckId, cameraId) >= SignalModel.WEAK then
			return true
		end
	end
	return false
end

local function update()
	local mission = deps.MissionService.mission
	local presenter = deps.EntityService.position()
	for _, player in Players:GetPlayers() do
		local quality = 100
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if mission and hrp and mission:participant(player.UserId) then
			local roomId = MapLayout.roomAt(hrp.Position.X, hrp.Position.Z)
			local room = roomId and MapLayout.Rooms[roomId]
			local wing = room and room.wing
			quality = SignalModel.playerQuality({
				powerOn = mission.flags.generator_restored == true,
				wingRelayOn = (wing == "WEST" or wing == "EAST") and mission.relays[wing] ~= false or nil,
				presenterDistance = presenter and (presenter - hrp.Position).Magnitude or nil,
				anomaly = mission.loop.active and roomId == mission.case.loop.room,
			})
		end
		if player:GetAttribute("Signal") ~= quality then
			player:SetAttribute("Signal", quality)
		end
	end
end

function SignalService.init(dependencies)
	deps = dependencies
	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(update)
			if not ok then
				warn("[SignalService] " .. tostring(err))
			end
		end
	end)
end

return SignalService
