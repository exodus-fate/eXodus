--[[
	Test runner. Usage (from the repository root):
		lune run tests/run.luau            -- every spec
		lune run tests/run.luau timeline   -- specs whose file name contains "timeline"
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local luau = require("@lune/luau")

local Harness = require("./lib/Harness")
local Engine = require("./lib/Engine")

local filter = process.args[1]

local function deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function describe(value)
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function makeExpect()
	local function expect(actual)
		local api = {}
		function api.toBe(expected)
			if actual ~= expected then
				error(string.format("expected %s to be %s", describe(actual), describe(expected)), 2)
			end
		end
		function api.toEqual(expected)
			if not deepEqual(actual, expected) then
				error(string.format("expected deep equality, got %s", describe(actual)), 2)
			end
		end
		function api.toBeTruthy()
			if not actual then
				error(string.format("expected truthy, got %s", describe(actual)), 2)
			end
		end
		function api.toBeFalsy()
			if actual then
				error(string.format("expected falsy, got %s", describe(actual)), 2)
			end
		end
		function api.toBeNear(expected, epsilon)
			epsilon = epsilon or 1e-6
			if type(actual) ~= "number" or math.abs(actual - expected) > epsilon then
				error(string.format("expected %s to be within %s of %s", describe(actual), epsilon, expected), 2)
			end
		end
		function api.toBeAtLeast(expected)
			if type(actual) ~= "number" or actual < expected then
				error(string.format("expected %s >= %s", describe(actual), describe(expected)), 2)
			end
		end
		function api.toBeAtMost(expected)
			if type(actual) ~= "number" or actual > expected then
				error(string.format("expected %s <= %s", describe(actual), describe(expected)), 2)
			end
		end
		function api.toContain(expected)
			if type(actual) == "string" then
				if not string.find(actual, expected, 1, true) then
					error(string.format("expected %s to contain %s", describe(actual), describe(expected)), 2)
				end
				return
			end
			for _, v in actual do
				if deepEqual(v, expected) then
					return
				end
			end
			error(string.format("expected list to contain %s", describe(expected)), 2)
		end
		return api
	end
	return expect
end

local specDir = "tests/specs"
local files = fs.readDir(specDir)
table.sort(files)

local passed, failed = 0, 0
local failures = {}

for _, file in files do
	if string.sub(file, -10) == ".spec.luau" and (not filter or string.find(file, filter, 1, true)) then
		local source = fs.readFile(specDir .. "/" .. file)
		local tests = {}
		local env = {
			Harness = Harness,
			Engine = Engine,
			roblox = require("@lune/roblox"),
			expect = makeExpect(),
			test = function(name, fn)
				table.insert(tests, { name = name, fn = fn })
			end,
		}
		local ok, err = pcall(function()
			local chunk = luau.load(source, { debugName = file, environment = env })
			chunk()
		end)
		if not ok then
			failed += 1
			table.insert(failures, string.format("%s (load): %s", file, tostring(err)))
		end
		for _, case in tests do
			local okCase, errCase = pcall(case.fn)
			if okCase then
				passed += 1
				print(string.format("  PASS  %s :: %s", file, case.name))
			else
				failed += 1
				print(string.format("  FAIL  %s :: %s", file, case.name))
				table.insert(failures, string.format("%s :: %s\n      %s", file, case.name, tostring(errCase)))
			end
		end
	end
end

print(string.format("\n%d passed, %d failed", passed, failed))
if #failures > 0 then
	print("\nFailures:")
	for _, f in failures do
		print("  - " .. f)
	end
	process.exit(1)
end
-- Simulated services leave background threads parked; exit explicitly.
process.exit(0)
