local Format = {}

local FRAMES_PER_SECOND = 30

-- 00:MM:SS broadcast clock. Negative values clamp to zero.
function Format.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	return string.format("%02d:%02d:%02d", h, m, s)
end

-- MM:SS for short countdowns.
function Format.short(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", seconds // 60, seconds % 60)
end

-- HH:MM:SS:FF tape timecode.
function Format.timecode(seconds: number): string
	seconds = math.max(0, seconds)
	local whole = math.floor(seconds)
	local frames = math.floor((seconds - whole) * FRAMES_PER_SECOND)
	return string.format("%s:%02d", Format.clock(whole), frames)
end

function Format.frameNumber(seconds: number): number
	return math.floor(math.max(0, seconds) * FRAMES_PER_SECOND)
end

-- Relative tape offset such as "T+02:30".
function Format.relative(seconds: number): string
	local sign = seconds < 0 and "-" or "+"
	return "T" .. sign .. Format.short(math.abs(seconds))
end

Format.FRAMES_PER_SECOND = FRAMES_PER_SECOND

return Format
