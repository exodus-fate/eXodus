--[[
	Runs the game's Roblox-style ModuleScripts headlessly under Lune.

	Source folders are mounted as a virtual instance tree so that code written for
	Roblox (`require(script.Parent.Foo)`, `script:WaitForChild("Bar")`) resolves to
	files on disk. Real Roblox datatypes and Instances come from Lune's roblox
	library, which validates class, property and enum names against the engine's
	reflection database - so building the map or UI here catches typos that would
	otherwise only surface in Studio.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Harness = {}

local Proxy = {}
Proxy.__index = function(self, key)
	local method = Proxy[key]
	if method then
		return method
	end
	local raw = rawget(self, "_fields")
	if raw[key] ~= nil then
		return raw[key]
	end
	local child = self:FindFirstChild(key)
	if child then
		return child
	end
	error(string.format("%s is not a valid member of %s", tostring(key), raw.Name), 2)
end

local function stripName(fileName)
	for _, suffix in { ".server.luau", ".client.luau", ".luau", ".server.lua", ".client.lua", ".lua" } do
		if string.sub(fileName, -#suffix) == suffix then
			return string.sub(fileName, 1, #fileName - #suffix), suffix
		end
	end
	return nil
end

local function newProxy(name, path, isDir, parent, harness)
	local className = "Folder"
	local modulePath = nil
	if isDir then
		for _, init in { "init.luau", "init.lua" } do
			if fs.isFile(path .. "/" .. init) then
				className = "ModuleScript"
				modulePath = path .. "/" .. init
			end
		end
	else
		local _, suffix = stripName(string.match(path, "[^/]+$"))
		if suffix == ".server.luau" or suffix == ".server.lua" then
			className = "Script"
		elseif suffix == ".client.luau" or suffix == ".client.lua" then
			className = "LocalScript"
		else
			className = "ModuleScript"
		end
		modulePath = path
	end
	local self = setmetatable({
		_fields = {
			Name = name,
			Parent = parent,
			ClassName = className,
		},
		_path = path,
		_isDir = isDir,
		_modulePath = modulePath,
		_children = nil,
		_harness = harness,
	}, Proxy)
	return self
end

-- Lune's filesystem calls yield, and metamethods cannot yield, so the whole tree
-- (and every source file) is read eagerly when a folder is mounted.
local function scan(proxy)
	local children = {}
	if rawget(proxy, "_isDir") then
		local path = rawget(proxy, "_path")
		local names = fs.readDir(path)
		table.sort(names)
		for _, entry in names do
			local full = path .. "/" .. entry
			if fs.isDir(full) then
				local child = newProxy(entry, full, true, proxy, rawget(proxy, "_harness"))
				scan(child)
				children[entry] = child
			else
				local base = stripName(entry)
				if base and base ~= "init" then
					local child = newProxy(base, full, false, proxy, rawget(proxy, "_harness"))
					scan(child)
					children[base] = child
				end
			end
		end
	end
	local modulePath = rawget(proxy, "_modulePath")
	if modulePath then
		rawset(proxy, "_source", fs.readFile(modulePath))
	end
	rawset(proxy, "_children", children)
end

function Proxy:_loadChildren()
	return rawget(self, "_children")
end

function Proxy:FindFirstChild(name)
	return self:_loadChildren()[name]
end

function Proxy:WaitForChild(name)
	local child = self:FindFirstChild(name)
	if not child then
		error(string.format("Infinite yield: %s has no child %s", rawget(self, "_fields").Name, tostring(name)), 2)
	end
	return child
end

function Proxy:GetChildren()
	local list = {}
	for _, child in self:_loadChildren() do
		table.insert(list, child)
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

function Proxy:IsA(className)
	return rawget(self, "_fields").ClassName == className
end

function Proxy:GetFullName()
	local parts = {}
	local node = self
	while node do
		table.insert(parts, 1, node.Name)
		node = rawget(node, "_fields").Parent
	end
	return table.concat(parts, ".")
end

-- Minimal stand-ins for engine types Lune does not provide.
local function makeRandom()
	local RandomStub = {}
	function RandomStub.new(seed)
		local state = math.floor(seed or 1) % 2147483647
		if state <= 0 then
			state = state + 2147483646
		end
		local r = {}
		function r:NextNumber(a, b)
			state = (state * 48271) % 2147483647
			local f = state / 2147483647
			if a then
				return a + (b - a) * f
			end
			return f
		end
		function r:NextInteger(a, b)
			return a + math.floor(r:NextNumber() * (b - a + 1))
		end
		return r
	end
	return RandomStub
end

local function makeTweenInfo()
	local TweenInfoStub = {}
	function TweenInfoStub.new(time, style, direction, repeatCount, reverses, delayTime)
		return {
			Time = time or 1,
			EasingStyle = style,
			EasingDirection = direction,
			RepeatCount = repeatCount or 0,
			Reverses = reverses or false,
			DelayTime = delayTime or 0,
		}
	end
	return TweenInfoStub
end

function Harness.new(options)
	options = options or {}
	local self = {
		roots = {},
		cache = {},
		game = options.game,
		extraGlobals = options.globals or {},
	}

	function self.mount(name, path)
		local proxy = newProxy(name, path, true, nil, self)
		scan(proxy)
		self.roots[name] = proxy
		return proxy
	end

	function self.require(target)
		if type(target) ~= "table" or getmetatable(target) ~= Proxy then
			error("Harness require expects a mounted module, got " .. tostring(target), 2)
		end
		local modulePath = rawget(target, "_modulePath")
		if not modulePath then
			error(target:GetFullName() .. " is not a ModuleScript", 2)
		end
		local cached = self.cache[modulePath]
		if cached then
			if cached.loading then
				error("Cyclic require detected at " .. modulePath, 2)
			end
			return cached.value
		end
		local entry = { loading = true }
		self.cache[modulePath] = entry
		local source = rawget(target, "_source")
		local env = self.makeEnv(target)
		local chunk = luau.load(source, { debugName = modulePath, environment = env })
		local value = chunk()
		entry.value = value
		entry.loading = false
		return value
	end

	-- Executes a Script/LocalScript (no caching).
	function self.run(target)
		local source = rawget(target, "_source")
		local env = self.makeEnv(target)
		local chunk = luau.load(source, { debugName = rawget(target, "_modulePath"), environment = env })
		return chunk()
	end

	function self.makeEnv(scriptProxy)
		local env = {
			script = scriptProxy,
			require = self.require,
			task = task,
			game = self.game,
			workspace = self.game and self.game:GetService("Workspace") or nil,
			Vector3 = roblox.Vector3,
			Vector2 = roblox.Vector2,
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			UDim = roblox.UDim,
			UDim2 = roblox.UDim2,
			Enum = roblox.Enum,
			Instance = roblox.Instance,
			NumberSequence = roblox.NumberSequence,
			NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
			ColorSequence = roblox.ColorSequence,
			ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
			NumberRange = roblox.NumberRange,
			BrickColor = roblox.BrickColor,
			Font = roblox.Font,
			Rect = roblox.Rect,
			PhysicalProperties = roblox.PhysicalProperties,
			Faces = roblox.Faces,
			Axes = roblox.Axes,
			Random = makeRandom(),
			TweenInfo = makeTweenInfo(),
			warn = function(...)
				print("[warn]", ...)
			end,
		}
		for key, value in self.extraGlobals do
			env[key] = value
		end
		return env
	end

	return self
end

return Harness
