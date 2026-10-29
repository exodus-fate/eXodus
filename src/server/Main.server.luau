--[[
	DEAD AIR: CHANNEL ZERO — server bootstrap.

	Service responsibilities (from the design brief):
	  MissionService      starts cases, tracks objectives, extraction/failure, cleanup
	  TimelineService     edit requests from the Time-Shift Deck, hidden frames
	  EntityService       the Presenter's state machine, pathfinding and targeting
	  EvidenceService     tape discovery, evidence and permanent unlocks
	  SignalService       deterministic signal quality
	  InteractionService  ProximityPrompts, range checks
	  DataService         progression with DataStoreService
	  MarketService       gamepasses and developer products
	  LobbyService        the field office: party, deploy, equipment, cosmetics
	  WorldService        the physical station: map template, doors, lights, items
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local CaseRegistry = require(Shared.Config.CaseRegistry)
local MapLayout = require(Shared.Config.MapLayout)
local TimelineCore = require(Shared.Core.TimelineCore)
local MapBuilder = require(Shared.World.MapBuilder)

local Services = script.Parent:WaitForChild("Services")
local Router = require(Services.Router)

local deps = {
	DataService = require(Services.DataService),
	MarketService = require(Services.MarketService),
	WorldService = require(Services.WorldService),
	InteractionService = require(Services.InteractionService),
	EntityService = require(Services.EntityService),
	SignalService = require(Services.SignalService),
	TimelineService = require(Services.TimelineService),
	EvidenceService = require(Services.EvidenceService),
	MissionService = require(Services.MissionService),
	LobbyService = require(Services.LobbyService),
}

-- Refuse to run a case whose event graph is inconsistent.
for caseId, caseDef in CaseRegistry.Cases do
	local errors = TimelineCore.validateCase(caseDef, MapLayout)
	if #errors > 0 then
		error(string.format("Case %s failed validation:\n%s", caseId, table.concat(errors, "\n")))
	end
end

local remotes = Net.create(ReplicatedStorage)
Router.init(remotes, Players)

deps.DataService.init()
deps.WorldService.init()
deps.MarketService.init(deps)
deps.InteractionService.init(deps)
deps.EntityService.init(deps)
deps.SignalService.init(deps)
deps.TimelineService.init(deps)
deps.EvidenceService.init(deps)
deps.MissionService.init(deps, remotes)
deps.LobbyService.init(deps, remotes)

deps.InteractionService.bindStation(deps.WorldService.station)
deps.InteractionService.bindHQ(deps.WorldService.hq, MapBuilder.HQTerminals)

-- The station sits idle (lights off) until a case starts.
deps.WorldService.setIdleLights()

print("[DeadAir] Server ready.")
