--[[
	Sound — the one call every controller uses to make a noise:

	    Sound.play("TapeInsert")
	    Sound.play("DoorOpen", { at = Vector3 })        -- positional
	    Sound.loop("TapeScrub", true) / Sound.loop("TapeScrub", false)

	AudioController installs the real implementation at start-up. Until then
	(and in any code path that runs without it) these are silent no-ops, so
	nothing depends on audio being available.
]]

local Sound = {}

function Sound.play(_name, _opts) end

function Sound.loop(_name, _on) end

return Sound
