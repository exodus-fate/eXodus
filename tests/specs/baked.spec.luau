test("the baked place's map boots and runs a case", function()
	local fs = require("@lune/fs")
	if not fs.isFile("build/DeadAir.rbxl") then
		return
	end
	local place = roblox.deserializePlace(fs.readFile("build/DeadAir.rbxl"))
	local engine = Engine.new()
	local ws = engine.realGame:GetService("Workspace")
	for _, child in place:GetService("Workspace"):GetChildren() do
		if child.Name == "Station04" or child.Name == "FieldOffice" then
			child.Parent = ws
		end
	end
	local server = Harness.new({ game = engine.game, globals = engine:globals("server") })
	engine.sharedMounts.server = server.mount("Shared", "src/shared")
	local root = server.mount("Server", "src/server")
	engine:run("server", function() server.run(root.Main) end)
	engine:advance(0.5)
	local player = engine:addPlayer(7, "Cal", false)
	engine:advance(3)
	engine:fireServerAs(player, "Action", { type = "SetReady", ready = true })
	engine:advance(50)
	local m = server.require(root.Services.MissionService).mission
	assert(m and m.phase == "Active", "case did not start on the baked map")
	local prompts = 0
	for _, d in ws.Station04:GetDescendants() do
		if d.ClassName == "ProximityPrompt" then
			prompts += 1
		end
	end
	assert(prompts > 40, "too few prompts: " .. prompts)
	if #engine.errors > 0 or #engine.warnings > 0 then
		error(table.concat(engine.errors, "\n") .. table.concat(engine.warnings, "\n"))
	end
end)
