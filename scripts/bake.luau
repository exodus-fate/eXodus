--[[
	Bakes Broadcast Station 04 and the field office into a built place file so the
	map is visible (and editable) in Roblox Studio's Explorer.

	Usage (repository root):
		rojo build default.project.json -o build/DeadAir.rbxl
		lune run scripts/bake.luau build/DeadAir.rbxl

	The server also builds the map at runtime if Workspace has no Station04, so the
	game still works when synced with `rojo serve` into an empty place.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Harness = require("../tests/lib/Harness")

local path = process.args[1] or "build/DeadAir.rbxl"
if not fs.isFile(path) then
	error("Place file not found: " .. path .. " (run rojo build first)")
end

local game = roblox.deserializePlace(fs.readFile(path))
local workspace = game:GetService("Workspace")

for _, name in { "Station04", "FieldOffice" } do
	local existing = workspace:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
end

local h = Harness.new({ game = game })
local Shared = h.mount("Shared", "src/shared")
local Case01 = h.require(Shared.Config.Cases.Case01)
local MapBuilder = h.require(Shared.World.MapBuilder)

local station, hq = MapBuilder.build(workspace, Case01)

local parts = 0
for _, d in station:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	end
end
for _, d in hq:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	end
end

fs.writeFile(path, roblox.serializePlace(game))
print(string.format("Baked Station04 + FieldOffice (%d parts) into %s", parts, path))
