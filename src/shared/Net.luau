--[[
	Remote names. The server creates them under ReplicatedStorage.Remotes; the
	client waits for them. All client -> server traffic goes through `Action`
	(fire-and-forget) or `Request` (needs an answer) and is validated and
	rate-limited on the server.
]]

local Net = {}

Net.FolderName = "Remotes"

Net.Events = {
	"Action", -- C->S { type = "...", ... }
	"Mission", -- S->C mission snapshot
	"Subtitle", -- S->C subtitle / radio line
	"Cue", -- S->C presentation cue
	"Notify", -- S->C toast
	"Report", -- S->C case report
	"Profile", -- S->C profile summary
	"Party", -- S->C HQ party / ready state
	"Ghosts", -- S->C recorded positions for a Rewind replay
}

Net.Functions = {
	"Request", -- C->S->C { type = "...", ... } -> result table
}

function Net.create(replicatedStorage)
	local folder = replicatedStorage:FindFirstChild(Net.FolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Net.FolderName
		folder.Parent = replicatedStorage
	end
	local remotes = {}
	for _, name in Net.Events do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		remotes[name] = remote
	end
	for _, name in Net.Functions do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
		remotes[name] = remote
	end
	return remotes
end

function Net.wait(replicatedStorage)
	local folder = replicatedStorage:WaitForChild(Net.FolderName)
	local remotes = {}
	for _, name in Net.Events do
		remotes[name] = folder:WaitForChild(name)
	end
	for _, name in Net.Functions do
		remotes[name] = folder:WaitForChild(name)
	end
	return remotes
end

return Net
