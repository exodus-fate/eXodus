--[[
	Audio cues. Every cue that matters for gameplay also has a subtitle and a visual
	signal, so the game is fully playable muted or with subtitles only.

	`id` values are empty except for engine-bundled sounds (rbxasset://) because
	this project ships no third-party audio. Add original or properly licensed
	Creator Store sounds by pasting "rbxassetid://<number>" into `id`. Suggested
	Creator Store search terms are in `search`.

	group: Ambience | Effects | Music (each has its own volume slider).
]]

local Audio = {}

Audio.Cues = {
	Ambience = { id = "", group = "Ambience", volume = 0.35, looped = true, search = "ventilation hum room tone" },
	Fluorescent = { id = "", group = "Ambience", volume = 0.15, looped = true, search = "fluorescent light buzz" },
	GeneratorLoop = { id = "", group = "Ambience", volume = 0.4, looped = true, search = "diesel generator idle" },

	PresenterStep = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", group = "Effects", volume = 0.9, pitch = 0.55, search = "heavy footstep" },
	PresenterNear = { id = "", group = "Effects", volume = 0.6, looped = true, search = "tape flutter low tone" },
	HuntStart = { id = "", group = "Effects", volume = 0.8, search = "tape warble sting" },
	Static = { id = "", group = "Effects", volume = 0.4, search = "tv static burst" },
	LightsFail = { id = "", group = "Effects", volume = 0.7, search = "fluorescent light power down" },
	PowerOn = { id = "", group = "Effects", volume = 0.7, search = "power up hum breaker" },
	DoorOpen = { id = "", group = "Effects", volume = 0.5, search = "metal door open" },
	DoorLocked = { id = "", group = "Effects", volume = 0.5, search = "locked door rattle" },
	Pickup = { id = "", group = "Effects", volume = 0.5, search = "vhs tape pickup" },
	EditCommit = { id = "", group = "Effects", volume = 0.6, search = "vcr button clunk" },
	Alarm = { id = "", group = "Effects", volume = 0.7, search = "old alarm bell" },
	Phone = { id = "", group = "Effects", volume = 0.5, search = "old phone ring" },
	RadioClick = { id = "", group = "Effects", volume = 0.4, search = "radio squelch click" },
	UIClick = { id = "rbxasset://sounds/electronicpingshort.wav", group = "Effects", volume = 0.25 },
	Rewind = { id = "", group = "Effects", volume = 0.6, search = "tape rewind" },
	Install = { id = "", group = "Effects", volume = 0.6, search = "heavy metal clunk" },
}

Audio.Groups = { "Ambience", "Effects", "Music" }

return Audio
