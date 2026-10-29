-- Minimal synchronous signal used by client state stores.
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local handlers = self.handlers
	local entry = { fn = fn, connected = true }
	table.insert(handlers, entry)
	return {
		Disconnect = function()
			entry.connected = false
			local index = table.find(handlers, entry)
			if index then
				table.remove(handlers, index)
			end
		end,
	}
end

function Signal:Fire(...)
	-- Copy so handlers can disconnect while firing.
	local snapshot = table.clone(self.handlers)
	for _, entry in snapshot do
		if entry.connected then
			local ok, err = pcall(entry.fn, ...)
			if not ok then
				warn("Signal handler error: " .. tostring(err))
			end
		end
	end
end

return Signal
