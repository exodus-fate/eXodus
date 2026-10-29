--[[
	Evidence tapes and master recordings. Recovered entries are saved permanently
	and can be replayed from the Evidence Archive in the field office.

	Each transcript line is { t = seconds, speaker = "...", text = "..." }.
	Lines with `frame = true` are visual descriptions shown in the replay viewer.
]]

local Evidence = {}

Evidence.Tapes = {
	EV_ORIENTATION = {
		title = "STAFF ORIENTATION — 1996",
		label = "VHS · TRAINING",
		case = "case01",
		research = 10,
		transcript = {
			{ t = 0, frame = true, text = "Colour bars. A cheerful jingle, slightly slow." },
			{ t = 4, speaker = "NARRATOR", text = "Welcome to Station 04, the voice of the valley since 1971!" },
			{ t = 10, speaker = "NARRATOR", text = "Our Night Bulletin airs at midnight. After sign-off, the Time-Shift Deck is the engineer's responsibility." },
			{ t = 17, speaker = "NARRATOR", text = "Please do not adjust the Deck after sign-off. Please do not watch it for long." },
			{ t = 23, frame = true, text = "A staff photo. One face has been carefully scratched off the tape itself." },
			{ t = 28, speaker = "NARRATOR", text = "Remember: if a programme is running that isn't on the schedule, it is not your programme. Go home." },
		},
	},
	EV_ENGINEER = {
		title = "NIGHT ENGINEER LOG — M. HARROW",
		label = "VHS · HANDWRITTEN LABEL",
		case = "case01",
		research = 15,
		transcript = {
			{ t = 0, speaker = "HARROW", text = "Log, the fourteenth. The Deck is showing tomorrow's programme again." },
			{ t = 6, speaker = "HARROW", text = "I changed one thing. The light in the corridor. It worked. The corridor stayed lit." },
			{ t = 12, speaker = "HARROW", text = "But it didn't go away. It went somewhere else. It went to the room I was in." },
			{ t = 19, speaker = "HARROW", text = "It doesn't see the switches. It doesn't care about the switches. It sees the tape." },
			{ t = 25, frame = true, text = "Harrow looks past the camera for a long time." },
			{ t = 31, speaker = "HARROW", text = "If you are watching this, you have three changes. I used mine. Don't waste yours." },
		},
	},
	EV_WEATHER = {
		title = "WEATHER BULLETIN — 00:12",
		label = "BETACAM · AIRCHECK",
		case = "case01",
		research = 10,
		transcript = {
			{ t = 0, speaker = "FORECASTER", text = "Good evening. Tonight's weather for the valley." },
			{ t = 5, speaker = "FORECASTER", text = "A front arrives at seventeen minutes past midnight. You will not hear it arrive." },
			{ t = 11, frame = true, text = "The map behind her shows the station, not the valley." },
			{ t = 15, speaker = "FORECASTER", text = "Visibility will be poor. Stay where the lights are on — no. Sorry. That was yesterday's forecast." },
			{ t = 22, speaker = "FORECASTER", text = "Tomorrow: the same as tonight." },
		},
	},
	EV_TESTCARD = {
		title = "TEST CARD — PRESENTER",
		label = "U-MATIC · NO LABEL",
		case = "case01",
		research = 15,
		transcript = {
			{ t = 0, frame = true, text = "A test card. In the centre circle, where the girl and the chalkboard should be, a man in a suit." },
			{ t = 5, frame = true, text = "His face is a smaller television, showing the same test card." },
			{ t = 10, speaker = "CAPTION", text = "PLEASE STAND BY." },
			{ t = 15, speaker = "CAPTION", text = "YOUR PROGRAMME WILL CONTINUE WITH YOU." },
			{ t = 20, frame = true, text = "He has moved closer to the edge of the circle. The card itself has not changed." },
		},
	},
	EV_FINAL_BULLETIN = {
		title = "TAPE 07 — THE FINAL BULLETIN",
		label = "MASTER DUB · RED LABEL",
		case = "case01",
		research = 25,
		bonus = true,
		transcript = {
			{ t = 0, frame = true, text = "Studio A, lit for broadcast. The anchor desk is empty, then it is not." },
			{ t = 5, speaker = "THE PRESENTER", text = "Good evening. Here is tomorrow's news." },
			{ t = 10, speaker = "THE PRESENTER", text = "A recovery team will leave Station 04 by the freight door." },
			{ t = 15, speaker = "THE PRESENTER", text = "They will think they edited the programme. They were always in it." },
			{ t = 21, frame = true, text = "Behind the Presenter, a monitor shows the loading dock. The van's rear doors are open." },
			{ t = 26, speaker = "THE PRESENTER", text = "We will continue after this. We always continue after this." },
		},
	},
}

-- The campaign's seven master recordings. Only Case 01 ships in this build; the
-- rest are listed so the archive and case select show the campaign's shape.
Evidence.MasterRecordings = {
	{
		id = "MASTER_01",
		title = "MASTER 01 · SIGN-OFF",
		case = "case01",
		available = true,
		summary = "Station 04's last scheduled sign-off, 23:59, 1997. The Deck kept recording after the station went dark.",
		transcript = {
			{ t = 0, speaker = "ANNOUNCER", text = "This concludes tonight's programmes on Station 04." },
			{ t = 5, frame = true, text = "The sign-off slide holds. Then the station clock on the slide starts moving." },
			{ t = 10, speaker = "ANNOUNCER", text = "Programmes will resume at midnight." },
			{ t = 14, speaker = "ANNOUNCER", text = "Programmes have resumed." },
			{ t = 19, frame = true, text = "A list of broadcast dates scrolls past: every night since 1997. Tonight's date is near the end." },
			{ t = 25, speaker = "CAPTION", text = "SOURCE: TRANSMITTER 2 · LOCATION: NOT STATION 04" },
		},
	},
	{ id = "MASTER_02", title = "MASTER 02 · CLASSIFIED", available = false, summary = "Requires a future case." },
	{ id = "MASTER_03", title = "MASTER 03 · CLASSIFIED", available = false, summary = "Requires a future case." },
	{ id = "MASTER_04", title = "MASTER 04 · CLASSIFIED", available = false, summary = "Requires a future case." },
	{ id = "MASTER_05", title = "MASTER 05 · CLASSIFIED", available = false, summary = "Requires a future case." },
	{ id = "MASTER_06", title = "MASTER 06 · CLASSIFIED", available = false, summary = "Requires a future case." },
	{ id = "MASTER_07", title = "MASTER 07 · CLASSIFIED", available = false, summary = "Requires a future case." },
}

function Evidence.master(id: string)
	for _, master in Evidence.MasterRecordings do
		if master.id == id then
			return master
		end
	end
	return nil
end

return Evidence
