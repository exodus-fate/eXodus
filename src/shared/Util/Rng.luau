--[[
	Deterministic xorshift32 generator.

	Case variants (item spots, keypad codes, the Loop's odd detail, patrol phase)
	must come out identically on every server and in tests for the same seed, so the
	game never uses Roblox's Random for anything that affects gameplay.
]]

local Rng = {}
Rng.__index = Rng

function Rng.new(seed: number)
	local state = math.floor(seed) % 4294967296
	if state == 0 then
		state = 0x9E3779B9
	end
	local self = setmetatable({ state = state }, Rng)
	-- Discard the first outputs so nearby seeds diverge quickly.
	for _ = 1, 4 do
		self:nextU32()
	end
	return self
end

function Rng:nextU32(): number
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x
end

-- Float in [0, 1).
function Rng:float(): number
	return self:nextU32() / 4294967296
end

-- Integer in [low, high], inclusive.
function Rng:int(low: number, high: number): number
	return low + (self:nextU32() % (high - low + 1))
end

function Rng:pick(list)
	return list[self:int(1, #list)]
end

-- Derives an independent generator for a named purpose so adding a new random
-- choice never shifts the results of existing ones.
function Rng.forPurpose(seed: number, purpose: string)
	local h = 2166136261
	for i = 1, #purpose do
		h = bit32.bxor(h, string.byte(purpose, i))
		-- 16777619 = 2^24 + 403; split so the product stays exact in a double.
		h = (bit32.lshift(h, 24) + h * 403) % 4294967296
	end
	return Rng.new(bit32.bxor(math.floor(seed) % 4294967296, h))
end

return Rng
