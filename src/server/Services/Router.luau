--[[
	Router — the only entry point for client -> server traffic.

	Every message is a table with a string `type`. Handlers are registered per
	type; anything unknown, malformed or over the rate limit is dropped. Handlers
	must still validate every field they read.
]]

local Router = {}
Router.actions = {}
Router.requests = {}
Router.buckets = {}

-- Token bucket per player per message type.
local DEFAULT_LIMIT = { rate = 8, burst = 16 }

local function allow(player, kind, limit)
	limit = limit or DEFAULT_LIMIT
	local userBuckets = Router.buckets[player]
	if not userBuckets then
		userBuckets = {}
		Router.buckets[player] = userBuckets
	end
	local now = os.clock()
	local bucket = userBuckets[kind]
	if not bucket then
		bucket = { tokens = limit.burst, at = now }
		userBuckets[kind] = bucket
	end
	bucket.tokens = math.min(limit.burst, bucket.tokens + (now - bucket.at) * limit.rate)
	bucket.at = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function Router.onAction(kind, handler, limit)
	Router.actions[kind] = { handler = handler, limit = limit }
end

function Router.onRequest(kind, handler, limit)
	Router.requests[kind] = { handler = handler, limit = limit }
end

function Router.init(remotes, players)
	remotes.Action.OnServerEvent:Connect(function(player, payload)
		if type(payload) ~= "table" or type(payload.type) ~= "string" then
			return
		end
		local entry = Router.actions[payload.type]
		if not entry or not allow(player, payload.type, entry.limit) then
			return
		end
		local ok, err = pcall(entry.handler, player, payload)
		if not ok then
			warn(string.format("[Router] action %s from %s failed: %s", payload.type, player.Name, tostring(err)))
		end
	end)

	remotes.Request.OnServerInvoke = function(player, payload)
		if type(payload) ~= "table" or type(payload.type) ~= "string" then
			return { ok = false, message = "Malformed request." }
		end
		local entry = Router.requests[payload.type]
		if not entry then
			return { ok = false, message = "Unknown request." }
		end
		if not allow(player, payload.type, entry.limit) then
			return { ok = false, message = "Slow down." }
		end
		local ok, result = pcall(entry.handler, player, payload)
		if not ok then
			warn(string.format("[Router] request %s from %s failed: %s", payload.type, player.Name, tostring(result)))
			return { ok = false, message = "Something went wrong." }
		end
		return result or { ok = true }
	end

	players.PlayerRemoving:Connect(function(player)
		Router.buckets[player] = nil
	end)
end

-- Small validation helpers.
function Router.string(value, maxLength)
	return type(value) == "string" and #value <= (maxLength or 64)
end

function Router.number(value, min, max)
	return type(value) == "number" and value == value and value >= min and value <= max
end

return Router
