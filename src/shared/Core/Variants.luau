--[[
	Case variants derived from a run seed. Repeat runs move selected items, change
	the keypad codes and the Loop's odd detail, and may reverse a patrol, while the
	story logic and event graph stay the same.
]]

local Rng = require(script.Parent.Parent.Util.Rng)

local Variants = {}

local function code(rng, digits)
	local out = {}
	for i = 1, digits do
		-- No leading zero so the code reads clearly on subtitles.
		out[i] = tostring(i == 1 and rng:int(1, 9) or rng:int(0, 9))
	end
	return table.concat(out)
end

function Variants.compute(caseDef, seed: number)
	local result = {
		seed = seed,
		itemSpawns = {},
	}

	local spawnRng = Rng.forPurpose(seed, "items")
	local itemIds = {}
	for id in caseDef.items do
		table.insert(itemIds, id)
	end
	table.sort(itemIds)
	for _, id in itemIds do
		local item = caseDef.items[id]
		if item.spawns and #item.spawns > 0 then
			result.itemSpawns[id] = spawnRng:int(1, #item.spawns)
		end
	end

	local digits = (caseDef.keypad and caseDef.keypad.digits) or 4
	local codeRng = Rng.forPurpose(seed, "keypad")
	result.code = code(codeRng, digits)
	repeat
		result.fakeCode = code(codeRng, digits)
	until result.fakeCode ~= result.code

	if caseDef.loop then
		local loopRng = Rng.forPurpose(seed, "loop")
		result.loopOdd = caseDef.loop.props[loopRng:int(1, #caseDef.loop.props)].id
	end

	result.patrolFlip = Rng.forPurpose(seed, "patrol"):int(0, 1) == 1
	return result
end

-- Week-long fixed seed for the Archive Challenge leaderboard.
function Variants.weeklySeed(unixTime: number): (number, number)
	local week = unixTime // (7 * 24 * 3600)
	return 7919 * week + 104729, week
end

return Variants
