--[[
	Deterministic signal quality (0-100). No randomness: the same inputs always
	give the same number, and signal never harms players directly.

	Deck footage quality controls what the Time-Shift Deck can show:
	  CLEAR (>= 70) timestamps and event markers fully visible
	  WEAK  (40-69) heavier noise; markers visible, clue text partly garbled
	  LOST  (< 40)  markers hidden - reset the relay or use another camera
]]

local SignalModel = {}

SignalModel.CLEAR = 70
SignalModel.WEAK = 40

function SignalModel.band(quality: number): string
	if quality >= SignalModel.CLEAR then
		return "CLEAR"
	elseif quality >= SignalModel.WEAK then
		return "WEAK"
	end
	return "LOST"
end

local function interference(distance: number?, radius: number, strength: number): number
	if not distance or distance >= radius then
		return 0
	end
	return (1 - distance / radius) * strength
end

--[[
	params = {
		relay = "LOCAL" | "MAINS" | "WEST" | "EAST",  -- camera's feed
		powerOn = boolean,                              -- station generator running
		relayOn = boolean,                              -- the camera's relay is not tripped
		deckBattery = boolean,                          -- viewing on a battery deck
		presenterDistance = number?,                    -- Presenter to camera (nil if dormant)
		anomaly = boolean,                              -- an anomaly is active in the camera's room
	}
	Returns quality, reason.
]]
function SignalModel.cameraQuality(params): (number, string?)
	local relay = params.relay
	if relay ~= "LOCAL" and not params.powerOn then
		return 0, "NO CARRIER — CAMERA UNPOWERED"
	end
	local quality = params.deckBattery and 64 or 96
	local reason = nil
	if (relay == "WEST" or relay == "EAST") and params.relayOn == false then
		quality -= 55
		reason = relay .. " RELAY TRIPPED"
	end
	quality -= interference(params.presenterDistance, 40, 35)
	if params.anomaly then
		quality -= 40
		reason = reason or "ANOMALOUS INTERFERENCE"
	end
	quality = math.clamp(math.floor(quality + 0.5), 0, 100)
	if quality < SignalModel.WEAK and not reason then
		reason = "INTERFERENCE"
	end
	return quality, reason
end

--[[
	The HUD signal meter: a proximity sense for the Presenter and anomalies.
	params = { powerOn, wingRelayOn, presenterDistance, anomaly }
]]
function SignalModel.playerQuality(params): number
	local quality = params.powerOn and 92 or 68
	if params.wingRelayOn == false then
		quality -= 15
	end
	quality -= interference(params.presenterDistance, 60, 55)
	if params.anomaly then
		quality -= 35
	end
	return math.clamp(math.floor(quality + 0.5), 0, 100)
end

return SignalModel
