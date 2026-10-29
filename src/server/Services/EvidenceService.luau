--[[
	EvidenceService — permanent unlocks: evidence tapes, case tapes (replayable in
	the field office), hidden frames and master recordings.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CaseRegistry = require(Shared.Config.CaseRegistry)
local Evidence = require(Shared.Config.Evidence)

local Router = require(script.Parent.Router)

local EvidenceService = {}

local FRAME_RESEARCH = 15

local deps

-- Applies a mission "Unlock" effect to everyone it names.
function EvidenceService.applyUnlock(effect)
	for _, userId in effect.userIds or {} do
		local player = Players:GetPlayerByUserId(userId)
		local profile = player and deps.DataService.get(player)
		if profile then
			if effect.evidence and Evidence.Tapes[effect.evidence] then
				profile.evidence[effect.evidence] = true
			end
			if effect.tape then
				profile.tapes[effect.tape] = true
			end
			if effect.frame then
				profile.frames[effect.frame] = true
			end
			deps.DataService.markDirty(player)
			deps.LobbyService.sendProfile(player)
		end
	end
end

-- Hidden frames found while replaying tapes in the field office archive.
function EvidenceService.markArchiveFrame(player, tapeId, cameraId, t)
	local profile = deps.DataService.get(player)
	if not profile then
		return { ok = false, message = "Profile not loaded." }
	end
	if not profile.tapes[tapeId] then
		return { ok = false, message = "You have not recovered that tape." }
	end
	for _, case in CaseRegistry.Cases do
		for _, hf in case.hiddenFrames or {} do
			if hf.tape == tapeId and hf.camera == cameraId and math.abs(t - hf.t) <= (hf.window or 0.5) then
				if profile.frames[hf.id] then
					return { ok = false, message = "Already marked." }
				end
				profile.frames[hf.id] = true
				profile.research += FRAME_RESEARCH
				deps.DataService.markDirty(player)
				deps.LobbyService.sendProfile(player)
				return { ok = true, frame = hf.id, message = hf.text }
			end
		end
	end
	return { ok = false, message = "Nothing unusual on this frame." }
end

function EvidenceService.init(dependencies)
	deps = dependencies
	Router.onRequest("GetArchive", function(player)
		local profile = deps.DataService.get(player)
		if not profile then
			return { ok = false }
		end
		return {
			ok = true,
			evidence = profile.evidence,
			tapes = profile.tapes,
			frames = profile.frames,
			masters = profile.masters,
		}
	end, { rate = 1, burst = 3 })
end

return EvidenceService
