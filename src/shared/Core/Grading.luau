--[[
	Case grading and rewards. Grades reward survival, evidence, correct
	predictions and smart use of edits - not speed.
]]

local Grading = {}

Grading.Thresholds = {
	{ grade = "S", min = 90 },
	{ grade = "A", min = 75 },
	{ grade = "B", min = 60 },
	{ grade = "C", min = 40 },
	{ grade = "D", min = 0 },
}

local RESULT_POINTS = { Success = 35, Partial = 18, Failed = 0 }

local function ratio(a: number, b: number): number
	if b <= 0 then
		return 0
	end
	return math.clamp(a / b, 0, 1)
end

--[[
	stats = {
		result = "Success" | "Partial" | "Failed",
		participants, survivors,
		evidenceFound, evidenceTotal,
		predictionsInterpreted, predictionsTotal,
		editsMade, maxCharges, eliminationsDuringEdits,
		loopFirstTry, callerFooled,
	}
]]
function Grading.compute(stats)
	local breakdown = {}
	breakdown.result = RESULT_POINTS[stats.result] or 0
	breakdown.survival = 20 * ratio(stats.survivors or 0, stats.participants or 0)
	breakdown.evidence = 15 * ratio(stats.evidenceFound or 0, stats.evidenceTotal or 0)
	breakdown.predictions = 15 * ratio(stats.predictionsInterpreted or 0, stats.predictionsTotal or 0)
	local unused = math.max(0, (stats.maxCharges or 0) - (stats.editsMade or 0))
	local edits = 5 * ratio(unused, stats.maxCharges or 0)
	if (stats.editsMade or 0) > 0 and (stats.eliminationsDuringEdits or 0) == 0 then
		edits += 5
	end
	breakdown.edits = edits
	breakdown.anomalies = (stats.loopFirstTry and 5 or 0) + (stats.callerFooled and 0 or 5)

	local score = 0
	for _, v in breakdown do
		score += v
	end
	score = math.clamp(math.floor(score + 0.5), 0, 100)

	local grade = "D"
	for _, t in Grading.Thresholds do
		if score >= t.min then
			grade = t.grade
			break
		end
	end
	-- A failed case never grades above D.
	if stats.result == "Failed" then
		grade = "D"
	end
	return { score = score, grade = grade, breakdown = breakdown }
end

local BASE_CREDITS = { Success = 120, Partial = 70, Failed = 20 }
local GRADE_BONUS = { S = 80, A = 50, B = 30, C = 10, D = 0 }

--[[
	personal = { itemsRecovered, evidenceRecovered, framesMarked, extracted }
	team     = { result, grade, anomaliesIdentified, bonusTapeExtracted }
]]
function Grading.rewards(team, personal)
	local credits = (BASE_CREDITS[team.result] or 0) + (GRADE_BONUS[team.grade] or 0)
	local contribution = (personal.itemsRecovered or 0) * 10 + (personal.evidenceRecovered or 0) * 10
	credits += math.min(contribution, 60)
	if team.result ~= "Failed" and not personal.extracted then
		-- Left behind or eliminated: still paid, but less.
		credits = math.floor(credits * 0.6)
	end
	local research = (team.anomaliesIdentified or 0) * 10
		+ (personal.framesMarked or 0) * 15
		+ (personal.evidenceRecovered or 0) * 10
	if team.bonusTapeExtracted then
		research += 25
	end
	return { credits = credits, research = research }
end

return Grading
