-- Presentation: the tutorial, one typeface, camera feel, the tube-TV CCTV
-- picture, custom prompts and the comfort settings, on the real client code.

local function boot()
	local engine = Engine.new()
	local server = Harness.new({ game = engine.game, globals = engine:globals("server") })
	local client = Harness.new({ game = engine.game, globals = engine:globals("client") })
	engine.sharedMounts.server = server.mount("Shared", "src/shared")
	engine.sharedMounts.client = client.mount("Shared", "src/shared")
	local serverRoot = server.mount("Server", "src/server")
	local clientRoot = client.mount("Client", "src/client")
	engine:run("server", function()
		server.run(serverRoot.Main)
	end)
	engine:advance(0.5)
	local player = engine:addPlayer(101, "Ana", true)
	engine:advance(2)
	engine:run("client", function()
		client.run(clientRoot.Main)
	end)
	engine:advance(2)
	return {
		engine = engine,
		server = server,
		client = client,
		player = player,
		State = client.require(clientRoot.State),
		clientRoot = clientRoot,
		serverRoot = serverRoot,
		controller = function(name)
			return client.require(clientRoot.Controllers[name])
		end,
	}
end

local function assertClean(env, label)
	local e = env.engine
	if #e.errors > 0 then
		error(label .. ": runtime errors\n" .. table.concat(e.errors, "\n----\n"))
	end
	if #e.warnings > 0 then
		error(label .. ": warnings\n" .. table.concat(e.warnings, "\n"))
	end
end

local function playerGui(env)
	return env.engine.realOf[env.player].PlayerGui
end

local function buttonWithText(env, screen, text)
	for _, d in playerGui(env)[screen]:GetDescendants() do
		if d.ClassName == "TextButton" and d.Text == text then
			return d
		end
	end
	error("no button " .. text .. " in " .. screen)
end

local function click(env, button)
	env.engine:spawnOnSide("client", function()
		env.engine:signalFor(button, "Activated"):Fire()
	end)
	env.engine:advance(0.2)
end

local function closeOverlays(env)
	local Tutorial = env.controller("TutorialController")
	if Tutorial.isOpen() then
		click(env, buttonWithText(env, "DeadAirTutorial", "SKIP TUTORIAL"))
	end
	env.engine:run("client", function()
		env.controller("MenuController").close()
	end)
	env.engine:advance(0.2)
end

test("first join shows the tutorial; finishing it is saved and it can be replayed", function()
	local env = boot()
	env.engine:advance(1)
	local gui = playerGui(env).DeadAirTutorial
	expect(gui.Enabled).toBe(true)
	expect(env.State.ui.tutorial).toBe(true)
	local Tutorial = env.controller("TutorialController")
	local steps = #Tutorial.Steps
	expect(steps >= 6).toBeTruthy()
	for _ = 1, steps - 1 do
		click(env, buttonWithText(env, "DeadAirTutorial", "NEXT"))
	end
	click(env, buttonWithText(env, "DeadAirTutorial", "FINISH"))
	env.engine:advance(0.5)
	expect(gui.Enabled).toBe(false)
	expect(env.State.ui.tutorial == nil).toBeTruthy()
	local DataService = env.server.require(env.serverRoot.Services.DataService)
	local serverPlayer
	for _, p in env.engine:service("Players"):GetPlayers() do
		serverPlayer = p
	end
	expect(DataService.get(serverPlayer).tutorialSeen).toBe(true)

	-- Replay from Settings.
	env.engine:run("client", function()
		env.controller("MenuController").open("Settings")
	end)
	env.engine:advance(0.2)
	click(env, buttonWithText(env, "DeadAirMenu", "REPLAY TUTORIAL"))
	expect(gui.Enabled).toBe(true)
	click(env, buttonWithText(env, "DeadAirTutorial", "SKIP TUTORIAL"))
	expect(gui.Enabled).toBe(false)
	assertClean(env, "tutorial")
end)

test("every piece of text uses the one game typeface", function()
	local env = boot()
	env.engine:run("client", function()
		env.controller("MenuController").open("Settings")
	end)
	env.engine:advance(0.5)
	local family = "rbxasset://fonts/families/RobotoMono.json"
	local checked = 0
	local function check(root)
		for _, d in root:GetDescendants() do
			if d.ClassName == "TextLabel" or d.ClassName == "TextButton" or d.ClassName == "TextBox" then
				if d.FontFace.Family ~= family then
					error(d:GetFullName() .. " uses " .. d.FontFace.Family)
				end
				checked += 1
			end
		end
	end
	check(playerGui(env))
	check(env.engine.realGame:GetService("Workspace"))
	expect(checked > 200).toBeTruthy()
	assertClean(env, "fonts")
end)

test("head bob moves the view up and down while walking and settles when stopped", function()
	local env = boot()
	closeOverlays(env)
	local e = env.engine
	local camera = e.realCamera
	local character = e.realOf[env.player].Character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character.HumanoidRootPart
	camera.CameraType = roblox.Enum.CameraType.Custom
	camera.CameraSubject = humanoid
	local base = roblox.CFrame.new(0, 5, 260)
	local function sampleFrames(n)
		local lo, hi, rolls = math.huge, -math.huge, 0
		for _ = 1, n do
			camera.CFrame = base
			e:advance(0.05, 0.05)
			local offset = base:ToObjectSpace(camera.CFrame)
			lo = math.min(lo, offset.Position.Y)
			hi = math.max(hi, offset.Position.Y)
			local _, _, roll = offset:ToEulerAnglesXYZ()
			rolls = math.max(rolls, math.abs(roll))
		end
		return hi - lo, rolls
	end
	local steps = 0
	env.controller("CameraController").onFootstep = function()
		steps += 1
	end
	e.velocities[root] = roblox.Vector3.new(12, 0, 0)
	sampleFrames(20) -- ease in
	local walkRange, walkRoll = sampleFrames(40)
	expect(walkRange > 0.08).toBeTruthy()
	expect(walkRoll > 0).toBeTruthy()
	-- About two steps per second at walking pace (3.1 studs per step).
	expect(steps >= 6).toBeTruthy()
	-- Sprinting bobs harder.
	e.velocities[root] = roblox.Vector3.new(19, 0, 0)
	sampleFrames(20)
	local sprintRange = sampleFrames(40)
	expect(sprintRange > walkRange).toBeTruthy()
	-- Stopping settles it (only the faint breathing remains).
	e.velocities[root] = nil
	sampleFrames(40)
	local stillRange = sampleFrames(20)
	expect(stillRange < 0.03).toBeTruthy()
	-- Head bob off in Settings: walking leaves the view steady.
	env.engine:run("client", function()
		local copy = table.clone(env.State.settings)
		copy.headBob = 0
		env.State.applySettings(copy)
	end)
	e.velocities[root] = roblox.Vector3.new(12, 0, 0)
	sampleFrames(20)
	local offRange = sampleFrames(40)
	expect(offRange < 0.01).toBeTruthy()
	assertClean(env, "head bob")
end)

test("tension builds near a hunting Presenter, then drains slowly; the vignette closes in", function()
	local env = boot()
	closeOverlays(env)
	local e = env.engine
	env.engine:run("client", function()
		env.State.action("SetReady", { ready = true })
	end)
	e:advance(8)
	expect(env.State.inMission()).toBe(true)
	local camera = e.realCamera
	local character = e.realOf[env.player].Character
	camera.CameraType = roblox.Enum.CameraType.Custom
	camera.CameraSubject = character:FindFirstChildOfClass("Humanoid")
	local Camera = env.controller("CameraController")
	e:advance(2)
	local calm = Camera.tension
	expect(calm < 0.35).toBeTruthy()

	-- A hunting figure a few studs away.
	local pos = character.HumanoidRootPart.CFrame.Position
	local model = roblox.Instance.new("Model")
	model.Name = "Presenter"
	local torso = roblox.Instance.new("Part")
	torso.Name = "Root"
	torso.CFrame = roblox.CFrame.new(pos + roblox.Vector3.new(6, 0, 0))
	torso.Parent = model
	model.PrimaryPart = torso
	model:SetAttribute("State", "Hunting")
	model.Parent = e.realGame:GetService("Workspace")
	e:advance(3)
	local scared = Camera.tension
	expect(scared > 0.6).toBeTruthy()
	expect(env.State.tension).toBeNear(scared, 0.05)

	local edge = playerGui(env).DeadAirVignette:FindFirstChildWhichIsA("Frame"):FindFirstChildWhichIsA("UIGradient")
	local darkest = edge.Transparency.Keypoints[1].Value
	expect(darkest < 0.5).toBeTruthy()

	-- It leaves: dread lingers for a while before it fades.
	model:Destroy()
	e:advance(1)
	expect(Camera.tension > 0.45).toBeTruthy()
	e:advance(20)
	expect(Camera.tension < scared * 0.5).toBeTruthy()
	assertClean(env, "tension")
end)

test("the CCTV picture is black and white, rolls on a channel change and warms up", function()
	local env = boot()
	local e = env.engine
	local view
	env.engine:run("client", function()
		local FootageView = env.client.require(env.clientRoot.UI.FootageView)
		local screen = roblox.Instance.new("ScreenGui")
		screen.Parent = playerGui(env)
		view = FootageView.new(e:wrap(screen))
		view:setCamera("CAM01")
		view:setActors({ { kind = "Presenter", pos = { x = 0, y = 0, z = 20 } }, { kind = "Investigator", pos = { x = 2, y = 0, z = 20 } } })
		view:setLights("emergency")
		view:powerOn()
		for _ = 1, 20 do
			view:step(1 / 30)
		end
	end)
	local viewport = e.realOf[view.viewport]
	local parts = 0
	for _, d in viewport:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			local c = d.Color
			if math.abs(c.R - c.G) > 0.01 or math.abs(c.G - c.B) > 0.01 then
				error(d:GetFullName() .. " is not greyscale")
			end
		end
	end
	expect(parts > 50).toBeTruthy()
	local ambient = viewport.Ambient
	expect(ambient.R).toBeNear(ambient.B, 0.01)
	env.engine:run("client", function()
		view:setCamera("CAM02")
		view:step(1 / 30)
	end)
	expect(view.switchUntil > view.t).toBeTruthy()
	assertClean(env, "footage")
end)

test("interaction prompts are drawn by the game, in its typeface, and go away", function()
	local env = boot()
	local e = env.engine
	local ws = e.realGame:GetService("Workspace")
	local part = roblox.Instance.new("Part")
	part.Parent = ws
	local prompt = roblox.Instance.new("ProximityPrompt")
	prompt.ActionText = "Insert tape"
	prompt.ObjectText = "Reception VCR"
	prompt.HoldDuration = 1
	prompt.Style = roblox.Enum.ProximityPromptStyle.Custom
	prompt.Parent = part
	local pps = e.realGame:GetService("ProximityPromptService")
	e:spawnOnSide("client", function()
		e:signalFor(pps, "PromptShown"):Fire(e:wrap(prompt), roblox.Enum.ProximityPromptInputType.Keyboard)
	end)
	e:advance(0.1)
	local billboard = playerGui(env):FindFirstChild("DeadAirPrompt")
	expect(billboard ~= nil).toBeTruthy()
	local texts = {}
	for _, d in billboard:GetDescendants() do
		if d.ClassName == "TextLabel" then
			texts[d.Text] = true
		end
	end
	expect(texts["E"]).toBe(true)
	expect(texts["INSERT TAPE"]).toBe(true)
	expect(texts["RECEPTION VCR"]).toBe(true)
	expect(texts["HOLD"]).toBe(true)
	e:spawnOnSide("client", function()
		e:signalFor(prompt, "PromptButtonHoldBegan"):Fire()
	end)
	e:advance(0.1)
	e:spawnOnSide("client", function()
		e:signalFor(pps, "PromptHidden"):Fire(e:wrap(prompt))
	end)
	e:advance(0.1)
	expect(playerGui(env):FindFirstChild("DeadAirPrompt") == nil).toBeTruthy()
	assertClean(env, "prompts")
end)

test("comfort settings are sanitised and toggle sprint works", function()
	local env = boot()
	local ProfileSchema = env.client.require(env.engine.sharedMounts.client.Core.ProfileSchema)
	local s = ProfileSchema.sanitizeSettings(nil, { fieldOfView = 200, headBob = -1, motionBlur = 0.5, vignette = 3, toggleSprint = true, crosshair = "yes" })
	expect(s.fieldOfView).toBe(90)
	expect(s.headBob).toBe(0)
	expect(s.motionBlur).toBe(0.5)
	expect(s.vignette).toBe(1)
	expect(s.toggleSprint).toBe(true)
	expect(s.crosshair).toBe(true)

	closeOverlays(env)
	local e = env.engine
	env.engine:run("client", function()
		local copy = table.clone(env.State.settings)
		copy.toggleSprint = true
		env.State.applySettings(copy)
	end)
	local Input = env.controller("InputController")
	local sprint = e.actions.DA_Sprint
	local root = e.realOf[env.player].Character.HumanoidRootPart
	e.velocities[root] = roblox.Vector3.new(12, 0, 0)
	e:spawnOnSide("client", function()
		sprint.fn("DA_Sprint", roblox.Enum.UserInputState.Begin, {})
		sprint.fn("DA_Sprint", roblox.Enum.UserInputState.End, {})
	end)
	e:advance(0.2)
	expect(Input.isSprinting()).toBe(true)
	-- Stopping ends a toggled sprint.
	e.velocities[root] = nil
	e:advance(0.2)
	expect(Input.isSprinting()).toBe(false)
	assertClean(env, "settings")
end)

test("investigators wear office clothes in the field office and field kit in the station", function()
	local env = boot()
	closeOverlays(env)
	local e = env.engine
	local function outfit()
		local character = e.realOf[env.player].Character
		return character and character:FindFirstChild("Outfit")
	end
	e:advance(1)
	expect(outfit():GetAttribute("Mode")).toBe("Lobby")
	expect(outfit():FindFirstChild("IDBadge") ~= nil).toBeTruthy()
	expect(outfit():FindFirstChild("Headlamp") == nil).toBeTruthy()
	env.engine:run("client", function()
		env.State.action("SetReady", { ready = true })
	end)
	e:advance(8)
	expect(env.State.inMission()).toBe(true)
	expect(outfit():GetAttribute("Mode")).toBe("Field")
	for _, name in { "Vest", "Radio", "Backpack", "Belt", "Headlamp" } do
		if not outfit():FindFirstChild(name) then
			error("field kit missing " .. name)
		end
	end
	-- Every piece is welded on and never blocks movement.
	for _, p in outfit():GetChildren() do
		expect(p.CanCollide).toBe(false)
		expect(p.Massless).toBe(true)
		expect(p:FindFirstChildOfClass("WeldConstraint") ~= nil).toBeTruthy()
	end
	env.engine:run("client", function()
		env.State.action("LeaveCase")
	end)
	e:advance(3)
	expect(outfit():GetAttribute("Mode")).toBe("Lobby")
	assertClean(env, "outfits")
end)
