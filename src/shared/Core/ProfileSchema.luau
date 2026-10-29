--[[
	Saved player progression: defaults, migration, settings sanitising and applying
	a finished case report. Pure so it can be tested; DataService persists it.
]]

local Cosmetics = require(script.Parent.Parent.Config.Cosmetics)

local ProfileSchema = {}

ProfileSchema.VERSION = 1

ProfileSchema.GradeOrder = { D = 1, C = 2, B = 3, A = 4, S = 5 }

ProfileSchema.Equipment = {
	Camcorder = { label = "CAMCORDER", description = "Night-vision viewfinder. Recording anomalies on screen earns research." },
	Analyser = { label = "SIGNAL ANALYSER", description = "Shows signal strength and the direction of the strongest interference." },
	Recorder = { label = "AUDIO RECORDER", description = "Logs every radio message with its channel and timestamp, for review." },
	Monitor = { label = "HANDHELD MONITOR", description = "View live station cameras anywhere. Watching raises its awareness." },
}
ProfileSchema.EquipmentOrder = { "Camcorder", "Analyser", "Recorder", "Monitor" }

ProfileSchema.DefaultSettings = {
	sensitivity = 1,
	subtitles = true,
	radioLog = true,
	cameraShake = 1,
	distortion = 1,
	flicker = 1,
	lowIntensity = false,
	master = 1,
	music = 0.8,
	ambience = 0.8,
	effects = 1,
	textScale = 1,
	-- Camera and comfort
	fieldOfView = 70,
	headBob = 1,
	motionBlur = 1,
	vignette = 1,
	toggleSprint = false,
	crosshair = true,
	tips = true,
}

local SETTING_RANGES = {
	sensitivity = { 0.2, 3 },
	cameraShake = { 0, 1 },
	distortion = { 0, 1 },
	flicker = { 0, 1 },
	master = { 0, 1 },
	music = { 0, 1 },
	ambience = { 0, 1 },
	effects = { 0, 1 },
	textScale = { 0.8, 1.4 },
	fieldOfView = { 60, 90 },
	headBob = { 0, 1 },
	motionBlur = { 0, 1 },
	vignette = { 0, 1 },
}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

function ProfileSchema.default()
	return {
		version = ProfileSchema.VERSION,
		credits = 0,
		research = 0,
		clearance = 1,
		evidence = {},
		tapes = {},
		frames = {},
		masters = {},
		cases = {},
		challenges = {},
		cosmetics = { owned = {}, equipped = table.clone(Cosmetics.Defaults) },
		equipment = "Camcorder",
		presets = {},
		decor = {},
		settings = table.clone(ProfileSchema.DefaultSettings),
		storedRevives = 0,
		storedTeamTokens = 0,
		stats = { casesPlayed = 0, casesCompleted = 0, eliminations = 0, editsMade = 0 },
		archiveChallengeBest = {},
		tutorialSeen = false,
	}
end

-- Fills any missing keys with defaults without overwriting saved values.
local function fill(target, defaults)
	for k, v in defaults do
		if target[k] == nil then
			target[k] = deepCopy(v)
		elseif type(v) == "table" and type(target[k]) == "table" and next(v) ~= nil then
			fill(target[k], v)
		end
	end
end

function ProfileSchema.migrate(data)
	if type(data) ~= "table" then
		return ProfileSchema.default()
	end
	fill(data, ProfileSchema.default())
	data.version = ProfileSchema.VERSION
	return data
end

-- Settings come from the client: accept only known keys with sane values.
function ProfileSchema.sanitizeSettings(current, incoming)
	local out = table.clone(current or ProfileSchema.DefaultSettings)
	if type(incoming) ~= "table" then
		return out
	end
	for k, default in ProfileSchema.DefaultSettings do
		local v = incoming[k]
		if type(default) == "boolean" and type(v) == "boolean" then
			out[k] = v
		elseif type(default) == "number" and type(v) == "number" and v == v then
			local range = SETTING_RANGES[k]
			out[k] = range and math.clamp(v, range[1], range[2]) or v
		end
	end
	return out
end

--[[
	Applies a finished case report for one player. Returns a summary of what is
	new so the case report screen can list unlocks.
]]
function ProfileSchema.applyReport(profile, report, userId)
	local summary = { evidence = {}, frames = {}, challenges = {}, master = nil, clearance = nil, firstCompletion = false }
	local key = tostring(userId)
	local reward = report.rewards and report.rewards[key]
	if reward then
		profile.credits += reward.credits
		profile.research += reward.research
		summary.credits = reward.credits
		summary.research = reward.research
	end

	for _, id in report.evidenceIds or {} do
		if not profile.evidence[id] then
			profile.evidence[id] = true
			table.insert(summary.evidence, id)
		end
	end

	for _, id in report.challenges or {} do
		if not profile.challenges[id] then
			profile.challenges[id] = true
			table.insert(summary.challenges, id)
		end
	end

	local caseStats = profile.cases[report.caseId] or { runs = 0, completed = 0, bestGrade = nil, bestScore = 0 }
	profile.cases[report.caseId] = caseStats
	caseStats.runs += 1
	profile.stats.casesPlayed += 1
	profile.stats.editsMade += report.editsMade or 0

	local success = report.result == "Success" or report.result == "Partial"
	if success then
		if caseStats.completed == 0 then
			summary.firstCompletion = true
		end
		caseStats.completed += 1
		profile.stats.casesCompleted += 1
		if report.masterRecording and not profile.masters[report.masterRecording] then
			profile.masters[report.masterRecording] = true
			summary.master = report.masterRecording
		end
		-- Clearance comes from story milestones, not combat: completing Case 01
		-- grants clearance 2 (Restricted mode and the Archive Challenge).
		if profile.clearance < 2 then
			profile.clearance = 2
			summary.clearance = 2
		end
	end
	local old = caseStats.bestGrade and ProfileSchema.GradeOrder[caseStats.bestGrade] or 0
	if ProfileSchema.GradeOrder[report.grade] and ProfileSchema.GradeOrder[report.grade] > old then
		caseStats.bestGrade = report.grade
	end
	caseStats.bestScore = math.max(caseStats.bestScore or 0, report.score or 0)
	return summary
end

return ProfileSchema
