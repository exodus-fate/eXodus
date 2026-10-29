--[[
	A deterministic stand-in for the Roblox engine, for integration tests.

	Real Instances come from Lune (so every class, property and enum is still
	validated against Roblox's reflection database), wrapped in proxies that add
	what Lune does not have: events, a scheduler with a fake clock, remotes wired
	between the server and client scripts running in this same process, players
	and characters, DataStores, MarketplaceService, pathfinding and tweens.

	It is deliberately simple: no physics (Humanoid:MoveTo glides), raycasts are
	either always blocked or always clear, and replication is instantaneous. The
	point is to execute the real server and client code paths end to end and
	surface runtime errors, not to reproduce Roblox exactly.
]]

local roblox = require("@lune/roblox")

local Engine = {}
Engine.__index = Engine

-- Event names the game connects to (Lune instances have no events).
local EVENTS = {
	Triggered = true, MouseEnter = true, MouseLeave = true, SelectionGained = true, SelectionLost = true,
	Activated = true, InputBegan = true, InputChanged = true, InputEnded = true, Heartbeat = true,
	RenderStepped = true, Stepped = true, PlayerAdded = true, PlayerRemoving = true, CharacterAdded = true,
	Died = true, OnServerEvent = true, OnClientEvent = true, ChildAdded = true, ChildRemoved = true,
	DescendantAdded = true, AncestryChanged = true, Ended = true, Completed = true, Changed = true,
	PromptGamePassPurchaseFinished = true, PromptProductPurchaseFinished = true, PromptButtonHoldBegan = true,
	PromptButtonHoldEnded = true, MoveToFinished = true, FocusLost = true, PromptShown = true, PromptHidden = true,
	CharacterRemoving = true,
}

local CALLBACKS = { OnServerInvoke = true, OnClientInvoke = true, ProcessReceipt = true }

local function newSignal(engine, name)
	local signal = { name = name, handlers = {} }
	function signal:Connect(fn)
		local entry = { fn = fn, side = engine:currentSide(), connected = true }
		table.insert(self.handlers, entry)
		return {
			Connected = true,
			Disconnect = function()
				entry.connected = false
			end,
		}
	end
	function signal:Once(fn)
		local conn
		conn = self:Connect(function(...)
			conn.Disconnect()
			fn(...)
		end)
		return conn
	end
	function signal:Wait()
		local co = coroutine.running()
		local conn
		conn = self:Connect(function(...)
			conn.Disconnect()
			engine:_resume(co, ...)
		end)
		return coroutine.yield()
	end
	function signal:Fire(...)
		for _, entry in table.clone(self.handlers) do
			if entry.connected then
				engine:spawnOnSide(entry.side, entry.fn, ...)
			end
		end
	end
	return signal
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

function Engine.new()
	local self = setmetatable({}, Engine)
	self.clock = 1000
	self.waiting = {}
	self.errors = {}
	self.warnings = {}
	self.prints = {}
	self.unreadable = {}
	-- Keyed by real instance and released on Destroy (Luau weak tables do not
	-- break proxy <-> instance cycles, so weak keys would leak everything).
	self.proxyOf = {}
	self.signals = {}
	self.callbacks = {}
	self.stored = {}
	self.moves = {}
	self.velocities = {}
	self.renderBindings = {}
	self.sideOf = setmetatable({}, { __mode = "k" })
	self.realOf = setmetatable({}, {
		__index = function(_, proxy)
			return type(proxy) == "table" and rawget(proxy, "__real") or nil
		end,
	})
	self.running = nil
	self.sharedMounts = {}
	self.losBlocked = true
	self.actions = {}
	self.dataStores = {}
	self.ordered = {}
	self.prompted = {}
	self.closeHandlers = {}
	self.remoteLog = {}

	self.realGame = roblox.Instance.new("DataModel")
	self.game = self:wrap(self.realGame)
	local ws = self.realGame:GetService("Workspace")
	self.realCamera = roblox.Instance.new("Camera")
	self.realCamera.Name = "Camera"
	self.realCamera.Parent = ws

	self.task = self:_makeTask()
	local engine = self
	self.os = setmetatable({
		clock = function()
			return engine.clock
		end,
		time = function()
			return math.floor(1700000000 + engine.clock)
		end,
	}, { __index = os })
	self.Instance = {
		new = function(className, parent)
			local proxy = engine:wrap(roblox.Instance.new(className))
			if parent then
				proxy.Parent = parent
			end
			return proxy
		end,
	}
	self.RaycastParams = {
		new = function()
			return { FilterType = nil, FilterDescendantsInstances = {}, RespectCanCollide = false }
		end,
	}
	return self
end

function Engine:currentSide()
	return (self.running and self.sideOf[self.running]) or "server"
end

---------------------------------------------------------------------------
-- Scheduler
---------------------------------------------------------------------------

function Engine:_resume(co, ...)
	if coroutine.status(co) == "dead" then
		return
	end
	local previous = self.running
	self.running = co
	local ok, err = coroutine.resume(co, ...)
	self.running = previous
	if not ok then
		table.insert(self.errors, debug.traceback(co, tostring(err)))
	end
end

function Engine:spawnOnSide(side, fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	self.sideOf[co] = self.sideOf[co] or side
	self:_resume(co, ...)
	return co
end

function Engine:spawn(fn, ...)
	return self:spawnOnSide(self:currentSide(), fn, ...)
end

function Engine:_makeTask()
	local engine = self
	local t = {}
	function t.wait(seconds)
		local co = coroutine.running()
		local start = engine.clock
		table.insert(engine.waiting, { co = co, at = engine.clock + (seconds or 0) })
		coroutine.yield()
		return engine.clock - start
	end
	function t.spawn(fn, ...)
		return engine:spawn(fn, ...)
	end
	function t.defer(fn, ...)
		local co = type(fn) == "thread" and fn or coroutine.create(fn)
		engine.sideOf[co] = engine:currentSide()
		table.insert(engine.waiting, { co = co, at = engine.clock, args = table.pack(...) })
		return co
	end
	function t.delay(seconds, fn, ...)
		local co = coroutine.create(fn)
		engine.sideOf[co] = engine:currentSide()
		table.insert(engine.waiting, { co = co, at = engine.clock + (seconds or 0), args = table.pack(...) })
		return co
	end
	function t.cancel(co)
		for i = #engine.waiting, 1, -1 do
			if engine.waiting[i].co == co then
				table.remove(engine.waiting, i)
			end
		end
	end
	return t
end

function Engine:_resumeDue()
	local due, keep = {}, {}
	for _, w in self.waiting do
		if w.at <= self.clock + 1e-9 then
			table.insert(due, w)
		else
			table.insert(keep, w)
		end
	end
	self.waiting = keep
	table.sort(due, function(a, b)
		return a.at < b.at
	end)
	for _, w in due do
		if w.args then
			self:_resume(w.co, table.unpack(w.args, 1, w.args.n))
		else
			self:_resume(w.co)
		end
	end
end

function Engine:service(name)
	return self:wrap(self.realGame:GetService(name))
end

-- Advances simulated time, firing frame events and waking threads.
function Engine:_forget(real)
	self.proxyOf[real] = nil
	self.signals[real] = nil
	self.callbacks[real] = nil
	self.stored[real] = nil
	self.moves[real] = nil
end

function Engine:advance(seconds, step)
	step = step or 0.1
	local target = self.clock + seconds
	local run = self.realGame:GetService("RunService")
	while self.clock < target - 1e-9 do
		self.clock += step
		self:_stepMoves(step)
		self:signalFor(run, "Stepped"):Fire(self.clock, step)
		self:signalFor(run, "Heartbeat"):Fire(step)
		self:signalFor(run, "RenderStepped"):Fire(step)
		self:_resumeDue()
	end
	self:_resumeDue()
end

-- Runs a function on a side ("server" or "client") inside the scheduler.
function Engine:run(side, fn, ...)
	return self:spawnOnSide(side, fn, ...)
end

---------------------------------------------------------------------------
-- Proxies
---------------------------------------------------------------------------

function Engine:signalFor(real, name)
	local byName = self.signals[real]
	if not byName then
		byName = {}
		self.signals[real] = byName
	end
	if not byName[name] then
		byName[name] = newSignal(self, name)
	end
	return byName[name]
end

function Engine:unwrap(value)
	if type(value) == "table" then
		local real = self.realOf[value]
		if real then
			return real
		end
	end
	return value
end

local function isInstance(v)
	return typeof(v) == "Instance"
end

function Engine:wrapValue(v)
	if isInstance(v) then
		return self:wrap(v)
	end
	if type(v) == "table" then
		-- Lists of instances (GetChildren etc.).
		local out = {}
		for k, item in v do
			out[k] = isInstance(item) and self:wrap(item) or item
		end
		return out
	end
	return v
end

function Engine:unwrapArgs(...)
	local args = table.pack(...)
	for i = 1, args.n do
		local v = args[i]
		if type(v) == "table" and not self.realOf[v] then
			-- Tables of proxies (e.g. FilterDescendantsInstances) stay tables.
			args[i] = v
		else
			args[i] = self:unwrap(v)
		end
	end
	return table.unpack(args, 1, args.n)
end

local ProxyMT = {}

function Engine:wrap(real)
	if real == nil then
		return nil
	end
	local existing = self.proxyOf[real]
	if existing then
		return existing
	end
	local proxy = setmetatable({}, ProxyMT)
	self.proxyOf[real] = proxy
	rawset(proxy, "__real", real)
	rawset(proxy, "__engine", self)
	return proxy
end

local methods = {}

ProxyMT.__index = function(proxy, key)
	local engine = rawget(proxy, "__engine")
	local real = engine.realOf[proxy]
	if EVENTS[key] then
		return engine:signalFor(real, key)
	end
	local stored = engine.stored[real]
	if stored and stored[key] ~= nil then
		return stored[key]
	end
	local cb = engine.callbacks[real]
	if CALLBACKS[key] then
		return cb and cb[key] or nil
	end
	local override = methods[key]
	if override then
		local okOverride, handled, result = pcall(override, engine, proxy, real, nil, true)
		if not okOverride then
			if string.find(tostring(handled), "has been destroyed", 1, true) then
				return function() end
			end
			error(handled, 2)
		end
		if handled then
			if type(result) == "function" then
				-- Roblox tolerates calls on destroyed instances; mirror that.
				local fn = result
				return function(...)
					local packed = table.pack(pcall(fn, ...))
					if not packed[1] then
						if string.find(tostring(packed[2]), "has been destroyed", 1, true) then
							return nil
						end
						error(packed[2], 2)
					end
					return table.unpack(packed, 2, packed.n)
				end
			end
			return result
		end
	end
	local ok, value = pcall(function()
		return real[key]
	end)
	if not ok and string.find(tostring(value), "has been destroyed", 1, true) then
		-- Roblox lets scripts touch destroyed instances; Lune does not.
		return key == "Parent" and nil or (function() end)
	end
	if ok then
		if type(value) == "function" then
			return function(selfArg, ...)
				local packed = table.pack(pcall(value, engine:unwrap(selfArg), engine:unwrapArgs(...)))
				if not packed[1] then
					if string.find(tostring(packed[2]), "has been destroyed", 1, true) then
						return nil
					end
					error(packed[2], 2)
				end
				local results = table.pack(table.unpack(packed, 2, packed.n))
				for i = 1, results.n do
					results[i] = engine:wrapValue(results[i])
				end
				return table.unpack(results, 1, results.n)
			end
		end
		return engine:wrapValue(value)
	end
	local message = tostring(value)
	if string.find(message, "missing default value", 1, true) then
		engine.unreadable[real.ClassName .. "." .. key] = true
		return nil
	end
	error(message, 2)
end

ProxyMT.__newindex = function(proxy, key, value)
	local engine = rawget(proxy, "__engine")
	local real = engine.realOf[proxy]
	if CALLBACKS[key] then
		engine.callbacks[real] = engine.callbacks[real] or {}
		engine.callbacks[real][key] = value
		return
	end
	local raw = engine:unwrap(value)
	local ok, err = pcall(function()
		real[key] = raw
	end)
	if not ok and string.find(tostring(err), "has been destroyed", 1, true) then
		return
	end
	if not ok then
		local message = tostring(err)
		if string.find(message, "not a valid member", 1, true) or string.find(message, "Failed to cast", 1, true) or string.find(message, "Expected", 1, true) then
			error(message, 2)
		end
		engine.stored[real] = engine.stored[real] or {}
		engine.stored[real][key] = value
		return
	end
	-- GetPropertyChangedSignal listeners (only if someone is listening).
	local byName = engine.signals[real]
	local changed = byName and byName["Changed:" .. key]
	if changed then
		changed:Fire()
	end
	if key == "Parent" and raw ~= nil then
		engine:signalFor(raw, "ChildAdded"):Fire(proxy)
		local ancestor = raw
		while ancestor do
			engine:signalFor(ancestor, "DescendantAdded"):Fire(proxy)
			ancestor = ancestor.Parent
		end
	end
end

ProxyMT.__tostring = function(proxy)
	local engine = rawget(proxy, "__engine")
	return tostring(engine.realOf[proxy])
end

ProxyMT.__eq = function(a, b)
	return rawequal(a, b)
end

---------------------------------------------------------------------------
-- Method / property overrides. Each returns handled, value.
---------------------------------------------------------------------------

local function bound(fn)
	return true, fn
end

local function isA(real, className)
	local ok, result = pcall(function()
		return real:IsA(className)
	end)
	return ok and result
end

methods.GetServerTimeNow = function(engine)
	return bound(function()
		return engine.clock
	end)
end

methods.WaitForChild = function(engine, _, real)
	return bound(function(_, name, timeout)
		if real.ClassName == "ReplicatedStorage" and name == "Shared" then
			return engine.sharedMounts[engine:currentSide()]
		end
		local waited = 0
		while true do
			local child = real:FindFirstChild(name)
			if child then
				return engine:wrap(child)
			end
			if waited >= (timeout or 30) then
				if timeout then
					return nil
				end
				error("Infinite yield waiting for " .. real:GetFullName() .. "." .. tostring(name))
			end
			engine.task.wait(0.05)
			waited += 0.05
		end
	end)
end

methods.Raycast = function(engine, _, real)
	if real.ClassName ~= "Workspace" then
		return false
	end
	return bound(function(_, origin)
		if engine.losBlocked then
			return { Position = origin, Instance = nil, Normal = roblox.Vector3.new(0, 1, 0) }
		end
		return nil
	end)
end

methods.GetPlayers = function(engine, _, real)
	return bound(function()
		local list = {}
		for _, child in real:GetChildren() do
			if child.ClassName == "Player" then
				table.insert(list, engine:wrap(child))
			end
		end
		return list
	end)
end

methods.GetPlayerByUserId = function(engine, _, real)
	return bound(function(_, userId)
		for _, child in real:GetChildren() do
			if child.ClassName == "Player" and child.UserId == userId then
				return engine:wrap(child)
			end
		end
		return nil
	end)
end

methods.LocalPlayer = function(engine, _, real)
	if real.ClassName ~= "Players" then
		return false
	end
	if engine:currentSide() == "client" then
		return true, engine.localPlayer
	end
	return true, nil
end

methods.CurrentCamera = function(engine, _, real)
	if real.ClassName ~= "Workspace" then
		return false
	end
	return true, engine:wrap(engine.realCamera)
end

methods.JobId = function(_, _, real)
	if real.ClassName == "DataModel" then
		return true, "simulated-job"
	end
	return false
end

methods.LoadCharacter = function(engine, proxy)
	return bound(function()
		engine:loadCharacter(proxy)
	end)
end

local function modelParts(real)
	local parts = {}
	for _, d in real:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	if real:IsA("BasePart") then
		table.insert(parts, real)
	end
	return parts
end

methods.GetPivot = function(_, _, real)
	if not isA(real, "PVInstance") then
		return false
	end
	return bound(function()
		if real:IsA("BasePart") then
			return real.CFrame
		end
		local primary = real.PrimaryPart
		if primary then
			return primary.CFrame
		end
		local parts = modelParts(real)
		return parts[1] and parts[1].CFrame or roblox.CFrame.new()
	end)
end

methods.PivotTo = function(engine, proxy, real)
	if not isA(real, "PVInstance") then
		return false
	end
	return bound(function(_, cf)
		local pivot = proxy:GetPivot()
		if not pivot then
			return -- destroyed: nothing to move (Roblox ignores this too)
		end
		local delta = cf * pivot:Inverse()
		for _, p in modelParts(real) do
			p.CFrame = delta * p.CFrame
		end
		engine.moves[real] = nil
	end)
end

methods.MoveTo = function(engine, _, real)
	if real.ClassName ~= "Humanoid" then
		return false
	end
	return bound(function(_, target)
		engine.moves[real] = target
	end)
end

function Engine:_stepMoves(dt)
	for humanoid, target in self.moves do
		local model = humanoid.Parent
		local root = model and model.PrimaryPart
		if not model or not root then
			self.moves[humanoid] = nil
		else
			local pos = root.CFrame.Position
			local flat = roblox.Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
			local dist = flat.Magnitude
			local speed = humanoid.WalkSpeed
			if dist < 0.2 or speed <= 0 then
				if dist < 0.2 then
					self.moves[humanoid] = nil
				end
			else
				local stepLen = math.min(dist, speed * dt)
				local delta = roblox.CFrame.new(flat.Unit * stepLen)
				for _, p in modelParts(model) do
					p.CFrame = delta * p.CFrame
				end
			end
		end
	end
end

-- Destroy / ClearAllChildren release engine bookkeeping for the whole subtree.
methods.Destroy = function(engine, _, real)
	return bound(function()
		-- Destroying twice is harmless in Roblox.
		local ok, descendants = pcall(function()
			return real:GetDescendants()
		end)
		for _, d in ok and descendants or {} do
			engine:_forget(d)
		end
		engine:_forget(real)
		pcall(function()
			real:Destroy()
		end)
	end)
end

methods.ClearAllChildren = function(engine, _, real)
	return bound(function()
		for _, d in real:GetDescendants() do
			engine:_forget(d)
		end
		real:ClearAllChildren()
	end)
end

local stubs = {
	SetNetworkOwner = true, SetStateEnabled = true, Kick = true, SetCore = true, Play = true, Stop = true,
	Pause = true, Resume = true, SetTitle = true, SetPosition = true, SetImage = true, UnbindAction = true,
}
for name in stubs do
	methods[name] = function(engine, _, real)
		if name == "Play" or name == "Stop" or name == "Pause" or name == "Resume" then
			if not isA(real, "Sound") then
				return false
			end
		end
		return bound(function()
			return nil
		end)
	end
end

methods.BindAction = function(engine)
	return bound(function(_, name, fn, _, ...)
		engine.actions[name] = { fn = fn, inputs = { ... }, side = engine:currentSide() }
	end)
end

methods.BindActionAtPriority = function(engine)
	return bound(function(_, name, fn, _, _, ...)
		engine.actions[name] = { fn = fn, inputs = { ... }, side = engine:currentSide() }
	end)
end

-- RenderStep bindings run every simulated frame, like RenderStepped.
methods.BindToRenderStep = function(engine, _, real)
	return bound(function(_, name, _, fn)
		local conn = engine:signalFor(real, "RenderStepped"):Connect(fn)
		engine.renderBindings[name] = conn
	end)
end

methods.UnbindFromRenderStep = function(engine)
	return bound(function(_, name)
		local conn = engine.renderBindings[name]
		if conn then
			conn.Disconnect()
			engine.renderBindings[name] = nil
		end
	end)
end

methods.GetConnectedGamepads = function()
	return bound(function()
		return {}
	end)
end

methods.IsTenFootInterface = function()
	return bound(function()
		return false
	end)
end

methods.IsStudio = function()
	return bound(function()
		return true
	end)
end

methods.BindToClose = function(engine)
	return bound(function(_, fn)
		table.insert(engine.closeHandlers, fn)
	end)
end

methods.GetPropertyChangedSignal = function(engine, _, real)
	return bound(function(_, prop)
		return engine:signalFor(real, "Changed:" .. prop)
	end)
end

methods.WorldToViewportPoint = function()
	return bound(function()
		return roblox.Vector3.new(0, 0, -1), false
	end)
end

methods.GetTagged = function(engine)
	return bound(function(_, tag)
		local list = {}
		for _, d in engine.realGame:GetDescendants() do
			if d:HasTag(tag) then
				table.insert(list, engine:wrap(d))
			end
		end
		return list
	end)
end

methods.GetNameFromUserIdAsync = function()
	return bound(function(_, userId)
		return "Player" .. tostring(userId)
	end)
end

for _, name in { "AbsolutePosition", "AbsoluteSize", "TextBounds" } do
	methods[name] = function()
		return true, roblox.Vector2.new(0, 0)
	end
end
-- Derived properties Lune does not serialise.
methods.Position = function(_, _, real)
	if isA(real, "BasePart") then
		return true, real.CFrame.Position
	end
	return false
end
methods.CameraOffset = function(_, _, real)
	if real.ClassName ~= "Humanoid" then
		return false
	end
	return true, roblox.Vector3.new(0, 0, 0)
end
methods.MoveDirection = function(engine, _, real)
	if real.ClassName ~= "Humanoid" then
		return false
	end
	-- Tests can set a root velocity to simulate walking.
	local root = real.Parent and real.Parent:FindFirstChild("HumanoidRootPart")
	local v = root and engine.velocities[root]
	if v and v.Magnitude > 0 then
		return true, roblox.Vector3.new(v.X, 0, v.Z).Unit
	end
	return true, roblox.Vector3.new(0, 0, 0)
end
methods.AssemblyLinearVelocity = function(engine, _, real)
	if not isA(real, "BasePart") then
		return false
	end
	return true, engine.velocities[real] or roblox.Vector3.new(0, 0, 0)
end
methods.FloorMaterial = function(_, _, real)
	if real.ClassName ~= "Humanoid" then
		return false
	end
	return true, roblox.Enum.Material.Concrete
end
for name, value in { TouchEnabled = false, KeyboardEnabled = true, MouseEnabled = true, GamepadEnabled = false } do
	methods[name] = function(_, _, real)
		if real.ClassName ~= "UserInputService" then
			return false
		end
		return true, value
	end
end

-- TweenService:Create -> applies the goal immediately when played.
methods.Create = function(engine, _, real)
	if real.ClassName ~= "TweenService" then
		return false
	end
	return bound(function(_, target, _, goals)
		local tween = { Completed = newSignal(engine, "Completed") }
		function tween:Play()
			for k, v in goals do
				target[k] = v
			end
			self.Completed:Fire(roblox.Enum.PlaybackState.Completed)
		end
		function tween:Cancel() end
		function tween:Destroy() end
		return tween
	end)
end

-- PathfindingService:CreatePath -> straight-line paths.
methods.CreatePath = function(engine, _, real)
	if real.ClassName ~= "PathfindingService" then
		return false
	end
	return bound(function()
		local path = { Status = roblox.Enum.PathStatus.NoPath, waypoints = {} }
		function path:ComputeAsync(from, to)
			self.Status = roblox.Enum.PathStatus.Success
			self.waypoints = { { Position = from }, { Position = to } }
		end
		function path:GetWaypoints()
			return self.waypoints
		end
		return path
	end)
end

-- DataStoreService with in-memory stores.
local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, item in v do
		out[k] = deepCopy(item)
	end
	return out
end

local function makeStore(engine, name)
	local store = { data = {} }
	function store:UpdateAsync(key, fn)
		local old = deepCopy(self.data[key])
		local new = fn(old)
		if new ~= nil then
			self.data[key] = deepCopy(new)
		end
		return deepCopy(new ~= nil and new or self.data[key])
	end
	function store:GetAsync(key)
		return deepCopy(self.data[key])
	end
	function store:SetAsync(key, value)
		self.data[key] = deepCopy(value)
	end
	function store:GetSortedAsync(ascending, pageSize)
		local rows = {}
		for k, v in self.data do
			table.insert(rows, { key = k, value = v })
		end
		table.sort(rows, function(a, b)
			if ascending then
				return a.value < b.value
			end
			return a.value > b.value
		end)
		local page = {}
		for i = 1, math.min(pageSize, #rows) do
			page[i] = rows[i]
		end
		return {
			GetCurrentPage = function()
				return page
			end,
		}
	end
	engine.dataStores[name] = store
	return store
end

methods.GetDataStore = function(engine, _, real)
	if real.ClassName ~= "DataStoreService" then
		return false
	end
	return bound(function(_, name)
		return engine.dataStores[name] or makeStore(engine, name)
	end)
end
methods.GetOrderedDataStore = methods.GetDataStore

methods.UserOwnsGamePassAsync = function()
	return bound(function()
		return false
	end)
end
for _, name in { "PromptGamePassPurchase", "PromptProductPurchase" } do
	methods[name] = function(engine)
		return bound(function(_, player, id)
			table.insert(engine.prompted, { kind = name, player = player, id = id })
		end)
	end
end

-- Remotes: payloads are deep-copied (and checked) as if serialised.
local function checkPayload(engine, value, path)
	local t = type(value)
	if t == "function" or t == "thread" then
		table.insert(engine.warnings, "remote payload contains a " .. t .. " at " .. path)
	elseif t == "table" then
		if engine.realOf[value] then
			return
		end
		local hasNumber, hasString, n = false, false, 0
		for k, v in value do
			if type(k) == "number" then
				hasNumber = true
				n += 1
			else
				hasString = true
			end
			checkPayload(engine, v, path .. "." .. tostring(k))
		end
		if hasNumber and hasString then
			table.insert(engine.warnings, "remote payload mixes array and dictionary keys at " .. path)
		elseif hasNumber and n ~= #value then
			table.insert(engine.warnings, "remote payload has a sparse array at " .. path)
		end
	end
end

local function transmit(engine, ...)
	local args = table.pack(...)
	for i = 1, args.n do
		checkPayload(engine, args[i], "arg" .. i)
		if type(args[i]) == "table" and not engine.realOf[args[i]] then
			args[i] = deepCopy(args[i])
		end
	end
	return table.unpack(args, 1, args.n)
end

methods.FireServer = function(engine, _, real)
	return bound(function(_, ...)
		table.insert(engine.remoteLog, { dir = "C2S", remote = real.Name })
		local packed = table.pack(transmit(engine, ...))
		for _, entry in table.clone(engine:signalFor(real, "OnServerEvent").handlers) do
			if entry.connected then
				engine:spawnOnSide("server", entry.fn, engine.localPlayer, table.unpack(packed, 1, packed.n))
			end
		end
	end)
end

methods.FireClient = function(engine, _, real)
	return bound(function(_, player, ...)
		if player ~= engine.localPlayer then
			return
		end
		table.insert(engine.remoteLog, { dir = "S2C", remote = real.Name })
		local packed = table.pack(transmit(engine, ...))
		for _, entry in table.clone(engine:signalFor(real, "OnClientEvent").handlers) do
			if entry.connected then
				engine:spawnOnSide("client", entry.fn, table.unpack(packed, 1, packed.n))
			end
		end
	end)
end

methods.FireAllClients = function(engine, proxy)
	return bound(function(_, ...)
		proxy:FireClient(engine.localPlayer, ...)
	end)
end

methods.InvokeServer = function(engine, _, real)
	return bound(function(_, ...)
		local cb = engine.callbacks[real] and engine.callbacks[real].OnServerInvoke
		if not cb then
			error("OnServerInvoke not set for " .. real.Name)
		end
		local previous = engine.running and engine.sideOf[engine.running]
		if engine.running then
			engine.sideOf[engine.running] = "server"
		end
		local results = table.pack(pcall(cb, engine.localPlayer, transmit(engine, ...)))
		if engine.running then
			engine.sideOf[engine.running] = previous
		end
		if not results[1] then
			error(results[2])
		end
		return transmit(engine, table.unpack(results, 2, results.n))
	end)
end

---------------------------------------------------------------------------
-- Players and characters
---------------------------------------------------------------------------

function Engine:addPlayer(userId, name, isLocal)
	local players = self.realGame:GetService("Players")
	local player = roblox.Instance.new("Player")
	player.Name = name
	player.UserId = userId
	player.DisplayName = name
	local gui = roblox.Instance.new("PlayerGui")
	gui.Name = "PlayerGui"
	gui.Parent = player
	player.Parent = players
	local proxy = self:wrap(player)
	if isLocal then
		self.localPlayer = proxy
	end
	self:signalFor(players, "PlayerAdded"):Fire(proxy)
	return proxy
end

function Engine:loadCharacter(playerProxy)
	local player = self.realOf[playerProxy]
	if player.Character then
		player.Character:Destroy()
	end
	local character = roblox.Instance.new("Model")
	character.Name = player.Name
	local function part(name, size, y)
		local p = roblox.Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = roblox.CFrame.new(0, y, 260)
		p.Parent = character
		return p
	end
	local root = part("HumanoidRootPart", roblox.Vector3.new(2, 2, 1), 3)
	part("UpperTorso", roblox.Vector3.new(2, 1.6, 1), 3.4)
	part("Head", roblox.Vector3.new(1.2, 1.2, 1.2), 4.8)
	local humanoid = roblox.Instance.new("Humanoid")
	humanoid.WalkSpeed = 12
	humanoid.Parent = character
	character.PrimaryPart = root
	character.Parent = self.realGame:GetService("Workspace")
	player.Character = character
	self:signalFor(player, "CharacterAdded"):Fire(self:wrap(character))
end

-- Sends a remote event / invocation as a non-local player (their client is
-- not simulated, so server -> client traffic to them is dropped).
function Engine:fireServerAs(playerProxy, remoteName, payload)
	local folder = self.realGame:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	local remote = folder:FindFirstChild(remoteName)
	local packed = deepCopy(payload)
	for _, entry in table.clone(self:signalFor(remote, "OnServerEvent").handlers) do
		if entry.connected then
			self:spawnOnSide("server", entry.fn, playerProxy, packed)
		end
	end
end

function Engine:invokeServerAs(playerProxy, payload)
	local folder = self.realGame:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	local remote = folder:FindFirstChild("Request")
	local cb = self.callbacks[remote].OnServerInvoke
	local result
	self:spawnOnSide("server", function()
		result = cb(playerProxy, deepCopy(payload))
	end)
	return result
end

function Engine:teleport(playerProxy, position)
	local character = self.realOf[playerProxy].Character
	if character then
		self:wrap(character):PivotTo(roblox.CFrame.new(position.X, 3, position.Z))
	end
end

---------------------------------------------------------------------------
-- Script execution
---------------------------------------------------------------------------

-- Globals injected into every script and module.
function Engine:globals(side, extra)
	local engine = self
	local g = {
		game = self.game,
		workspace = self:service("Workspace"),
		Instance = self.Instance,
		task = self.task,
		os = self.os,
		RaycastParams = self.RaycastParams,
		print = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring(select(i, ...))
			end
			table.insert(engine.prints, table.concat(parts, " "))
		end,
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring(select(i, ...))
			end
			table.insert(engine.warnings, "[" .. side .. "] " .. table.concat(parts, " "))
		end,
	}
	for k, v in extra or {} do
		g[k] = v
	end
	return g
end

return Engine
