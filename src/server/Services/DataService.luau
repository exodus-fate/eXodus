--[[
	DataService — loads and saves player progression with DataStoreService.

	* UpdateAsync everywhere, with a lightweight session lock so two servers never
	  overwrite each other's progress.
	* Retries with back-off; if DataStores are unavailable (for example in Studio
	  without "Enable Studio Access to API Services"), the player keeps a
	  session-only profile and is told progress will not be saved.
	* Autosaves dirty profiles every two minutes, on leave and on shutdown - never
	  after every tiny interaction.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ProfileSchema = require(Shared.Core.ProfileSchema)

local DataService = {}

local STORE_NAME = "DeadAir_Profiles_v1"
local LEADERBOARD_PREFIX = "DeadAir_ArchiveChallenge_w"
local LOCK_TIMEOUT = 300
local AUTOSAVE_INTERVAL = 120
local MAX_ATTEMPTS = 5

DataService.profiles = {} -- [player] = { data, dirty, offline, loaded }
DataService.loadedCallbacks = {}

local store = nil
local storeOk = pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)

local function keyFor(userId)
	return "u_" .. tostring(userId)
end

local function retry(fn)
	local lastErr
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		task.wait(math.min(2 ^ attempt * 0.5, 8))
	end
	return false, lastErr
end

-- Strips runtime-only fields before writing.
local function serialise(data)
	local copy = table.clone(data)
	copy.__lock = nil
	return copy
end

function DataService.onLoaded(callback)
	table.insert(DataService.loadedCallbacks, callback)
end

function DataService.get(player)
	local entry = DataService.profiles[player]
	return entry and entry.loaded and entry.data or nil
end

function DataService.isOffline(player)
	local entry = DataService.profiles[player]
	return entry == nil or entry.offline == true
end

function DataService.markDirty(player)
	local entry = DataService.profiles[player]
	if entry then
		entry.dirty = true
	end
end

function DataService.load(player)
	local entry = { data = nil, dirty = false, offline = false, loaded = false }
	DataService.profiles[player] = entry
	local data = nil
	if storeOk and store then
		local key = keyFor(player.UserId)
		local jobId = game.JobId
		for attempt = 1, MAX_ATTEMPTS do
			local blocked = false
			local ok, result = pcall(function()
				return store:UpdateAsync(key, function(old)
					local profile = ProfileSchema.migrate(old)
					local lock = type(old) == "table" and old.__lock or nil
					local stale = not lock or os.time() - (lock.time or 0) > LOCK_TIMEOUT
					if lock and lock.jobId ~= jobId and not stale and attempt < MAX_ATTEMPTS then
						blocked = true
						return nil -- another server still owns it; retry shortly
					end
					local saved = serialise(profile)
					saved.__lock = { jobId = jobId, time = os.time() }
					return saved
				end)
			end)
			if ok and not blocked then
				data = ProfileSchema.migrate(result)
				break
			end
			if not ok then
				warn(string.format("[DataService] load attempt %d for %s failed: %s", attempt, player.Name, tostring(result)))
			end
			task.wait(blocked and 3 or 2 ^ attempt * 0.5)
		end
	end
	if not data then
		entry.offline = true
		data = ProfileSchema.default()
		if not RunService:IsStudio() then
			warn("[DataService] Using a session-only profile for " .. player.Name)
		end
	end
	data.__lock = nil
	entry.data = data
	entry.loaded = true
	if player.Parent ~= Players then
		return nil
	end
	for _, callback in DataService.loadedCallbacks do
		task.spawn(callback, player, data, entry.offline)
	end
	return data
end

function DataService.save(player, release)
	local entry = DataService.profiles[player]
	if not entry or not entry.loaded or entry.offline or not store then
		return false
	end
	local jobId = game.JobId
	local snapshot = serialise(entry.data)
	local ok, err = retry(function()
		store:UpdateAsync(keyFor(player.UserId), function(old)
			local lock = type(old) == "table" and old.__lock or nil
			if lock and lock.jobId ~= jobId and os.time() - (lock.time or 0) <= LOCK_TIMEOUT then
				-- Another server took over this profile; don't clobber it.
				return nil
			end
			local out = table.clone(snapshot)
			out.__lock = not release and { jobId = jobId, time = os.time() } or nil
			return out
		end)
	end)
	if ok then
		entry.dirty = false
	else
		warn(string.format("[DataService] save for %s failed: %s", player.Name, tostring(err)))
	end
	return ok
end

-- Saves now (used after purchases). Returns success.
function DataService.saveNow(player)
	local entry = DataService.profiles[player]
	if entry and entry.offline then
		-- Nothing to persist to; the grant still applies for this session.
		return true
	end
	return DataService.save(player, false)
end

---------------------------------------------------------------------------
-- Archive Challenge leaderboard (weekly OrderedDataStore).
---------------------------------------------------------------------------

function DataService.submitScore(week, userId, score)
	local ok, err = pcall(function()
		local board = DataStoreService:GetOrderedDataStore(LEADERBOARD_PREFIX .. tostring(week))
		board:UpdateAsync(tostring(userId), function(old)
			if type(old) == "number" and old >= score then
				return nil
			end
			return math.floor(score)
		end)
	end)
	if not ok then
		warn("[DataService] leaderboard submit failed: " .. tostring(err))
	end
	return ok
end

local leaderboardCache = { week = nil, at = 0, rows = {} }

function DataService.topScores(week)
	if leaderboardCache.week == week and os.clock() - leaderboardCache.at < 60 then
		return leaderboardCache.rows
	end
	local rows = {}
	local ok = pcall(function()
		local board = DataStoreService:GetOrderedDataStore(LEADERBOARD_PREFIX .. tostring(week))
		local page = board:GetSortedAsync(false, 10):GetCurrentPage()
		for rank, entry in page do
			local name = "Investigator"
			pcall(function()
				name = Players:GetNameFromUserIdAsync(tonumber(entry.key))
			end)
			table.insert(rows, { rank = rank, name = name, score = entry.value })
		end
	end)
	if ok then
		leaderboardCache = { week = week, at = os.clock(), rows = rows }
	end
	return rows
end

function DataService.init()
	Players.PlayerRemoving:Connect(function(player)
		DataService.save(player, true)
		DataService.profiles[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, entry in DataService.profiles do
				if entry.dirty and player.Parent == Players then
					task.spawn(DataService.save, player, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in DataService.profiles do
			pending += 1
			task.spawn(function()
				DataService.save(player, true)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.2)
		end
	end)
end

return DataService
