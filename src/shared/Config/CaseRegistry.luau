--[[
	All cases in the campaign. Only Case 01 is playable in this build; the others
	exist so Case Select shows the campaign and so save data has stable ids.
]]

local Case01 = require(script.Parent.Cases.Case01)

local CaseRegistry = {}

CaseRegistry.Cases = {
	case01 = Case01,
}

CaseRegistry.Order = {
	{ id = "case01", number = 1, title = Case01.title, location = Case01.location, playable = true },
	{ id = "case02", number = 2, title = "CLASSIFIED", location = "RELAY SITE 11", playable = false },
	{ id = "case03", number = 3, title = "CLASSIFIED", location = "STUDIO COMPLEX B", playable = false },
	{ id = "case04", number = 4, title = "CLASSIFIED", location = "ARCHIVE VAULT 2", playable = false },
	{ id = "case05", number = 5, title = "CLASSIFIED", location = "MOBILE UNIT 3", playable = false },
	{ id = "case06", number = 6, title = "CLASSIFIED", location = "TRANSMITTER 2", playable = false },
	{ id = "case07", number = 7, title = "CLASSIFIED", location = "CHANNEL ZERO", playable = false },
}

function CaseRegistry.get(caseId: string)
	return CaseRegistry.Cases[caseId]
end

return CaseRegistry
