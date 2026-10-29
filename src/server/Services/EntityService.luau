--[[
	EntityService — the Presenter in the world.

	PresenterBrain makes every decision; this service gathers the senses it needs
	(line of sight, light, flashlights, refuges, revive protection), then moves the
	rig with Humanoid:MoveTo / PathfindingService. Movement and targeting are
	server-authoritative; clients only add presentation (static, sway, audio).
]]

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PresenterBrain = require(Shared.Core.PresenterBrain)
local Figures = require(Shared.World.Figures)
local MapLayout = require(Shared.Config.MapLayout)

local EntityService = {}

local TICK = 0.1
local TELEPORT_DRIFT = 14
local DOOR_OPEN_RADIUS = 5
local STUCK_TIME = 2.5

EntityService.model = nil
EntityService.brain = nil
EntityService.state = "Dormant"
EntityService.activeEventId = nil

local deps
local parked
local path = nil
local pathWaypoints = nil
local pathIndex = 0
local pathTarget = nil
local pathBusy = false
local pathFailedAt = -math.huge
local lastProgress = { pos = nil, at = 0 }
local stuckCount = 0

local function root()
	return EntityService.model and EntityService.model.PrimaryPart
end

local function humanoid()
	return EntityService.model and EntityService.model:FindFirstChildOfClass("Humanoid")
end

local function toV3(p)
	return Vector3.new(p.x, p.y or 0, p.z)
end

local function toVec(v)
	return { x = v.X, y = v.Y, z = v.Z }
end

function EntityService.position()
	local r = root()
	if r and EntityService.model.Parent == Workspace then
		return r.Position
	end
	return nil
end

function EntityService.isIdle()
	return EntityService.brain == nil or EntityService.brain:isIdle()
end

local function park()
	local model = EntityService.model
	if model and model.Parent ~= parked then
		model.Parent = parked
	end
	path, pathWaypoints, pathTarget = nil, nil, nil
end

local function place(pos, facePos)
	local model = EntityService.model
	local height = Figures.rootHeight(model)
	local at = Vector3.new(pos.x, (pos.y or 0) + height, pos.z)
	local cf
	if facePos then
		local look = Vector3.new(facePos.x, at.Y, facePos.z)
		if (look - at).Magnitude > 0.1 then
			cf = CFrame.lookAt(at, look)
		end
	end
	model:PivotTo(cf or CFrame.new(at))
	if model.Parent ~= Workspace then
		model.Parent = Workspace
		local r = root()
		pcall(function()
			r:SetNetworkOwner(nil)
		end)
	end
	local h = humanoid()
	if h then
		h:MoveTo(at)
	end
end

local function face(target)
	local r = root()
	if not r or not target then
		return
	end
	local pos = r.Position
	local look = Vector3.new(target.x, pos.Y, target.z)
	if (look - pos).Magnitude > 0.5 then
		r.CFrame = CFrame.lookAt(pos, look)
	end
end

function EntityService.reset(modeDef)
	if EntityService.model then
		EntityService.model:Destroy()
	end
	EntityService.model = Figures.presenter(parked)
	EntityService.model:SetAttribute("State", "Dormant")
	local h = humanoid()
	if h then
		-- A welded (non-jointed) rig: keep the Humanoid upright and walking only.
		for _, state in {
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.Climbing,
			Enum.HumanoidStateType.Swimming,
			Enum.HumanoidStateType.Seated,
			Enum.HumanoidStateType.Jumping,
			Enum.HumanoidStateType.Dead,
		} do
			h:SetStateEnabled(state, false)
		end
	end
	EntityService.brain = PresenterBrain.new({ huntSpeed = (modeDef and modeDef.huntSpeed) or 14.5 })
	EntityService.state = "Dormant"
	EntityService.activeEventId = nil
	park()
end

function EntityService.command(command, startTime, meta)
	if not EntityService.brain then
		return
	end
	EntityService.activeEventId = meta and meta.eventId
	EntityService.brain:setCommand(command, startTime, meta)
end

---------------------------------------------------------------------------
-- Observing spots: somewhere in the player's room, at a distance, in view.
---------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function refreshRayFilter()
	local list = {}
	if EntityService.model then
		table.insert(list, EntityService.model)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, g in deps.WorldService.glass do
		table.insert(list, g)
	end
	if deps.WorldService.itemsFolder then
		table.insert(list, deps.WorldService.itemsFolder)
	end
	rayParams.FilterDescendantsInstances = list
end

local function clearLine(from, to)
	local result = Workspace:Raycast(from, to - from, rayParams)
	return result == nil
end

function EntityService.observeNear(userId, startTime)
	if not EntityService.brain or not EntityService.brain:isIdle() then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local r = character and character:FindFirstChild("HumanoidRootPart")
	if not r then
		return
	end
	refreshRayFilter()
	local roomId = MapLayout.roomAt(r.Position.X, r.Position.Z)
	local room = roomId and MapLayout.Rooms[roomId]
	if not room or room.hq then
		return
	end
	local candidates = {}
	for _, u in { 0.12, 0.5, 0.88 } do
		for _, v in { 0.12, 0.5, 0.88 } do
			table.insert(candidates, MapLayout.point(roomId, u, v, 0))
		end
	end
	local best, bestScore = nil, -math.huge
	local eye = r.Position + Vector3.new(0, 1.5, 0)
	for _, c in candidates do
		local spot = toV3(c)
		local dist = (Vector3.new(spot.X, eye.Y, spot.Z) - eye).Magnitude
		if dist >= 16 and dist <= 48 and clearLine(eye, spot + Vector3.new(0, 7.5, 0)) then
			local score = -math.abs(dist - 28)
			if score > bestScore then
				best, bestScore = c, score
			end
		end
	end
	if not best then
		return
	end
	EntityService.command({
		kind = "Observe",
		pos = best,
		look = toVec(r.Position),
		duration = 8,
		triggerRadius = 12,
	}, startTime, { scripted = false, eventId = "awareness" })
end

---------------------------------------------------------------------------
-- Sensing
---------------------------------------------------------------------------

local function sense(mission, now)
	local r = root()
	local selfPos = r and EntityService.model.Parent == Workspace and r.Position or nil
	local list = {}
	if not selfPos then
		-- Not in the world: distances are irrelevant but the brain may need
		-- positions for an ambush that is about to appear.
		local anchorPos = EntityService.brain.anchorPos
		if anchorPos then
			selfPos = toV3(anchorPos) + Vector3.new(0, Figures.rootHeight(EntityService.model), 0)
		end
	end
	refreshRayFilter()
	local eye = selfPos and (selfPos + Vector3.new(0, 3, 0))
	local lookVector = r and r.CFrame.LookVector or Vector3.new(0, 0, -1)
	for _, player in Players:GetPlayers() do
		local p = mission:participant(player.UserId)
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if p and p.status == "Alive" and hrp and eye then
			local head = character:FindFirstChild("Head")
			local target = (head and head.Position) or (hrp.Position + Vector3.new(0, 1.5, 0))
			local flat = Vector3.new(target.X - eye.X, 0, target.Z - eye.Z)
			local dist = flat.Magnitude
			local angle = 0
			if dist > 0.01 then
				local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
				if flatLook.Magnitude > 0.01 then
					local dot = math.clamp(flatLook.Unit:Dot(flat.Unit), -1, 1)
					angle = math.deg(math.acos(dot))
				end
			end
			local roomId = MapLayout.roomAt(hrp.Position.X, hrp.Position.Z)
			local lit = roomId ~= nil and (mission.lights[roomId] or "off") ~= "off"
			local room = roomId and MapLayout.Rooms[roomId]
			local hidden = room ~= nil and room.refuge == true and deps.WorldService.refugeSealed(roomId)
			table.insert(list, {
				id = player.UserId,
				pos = toVec(hrp.Position),
				dist = dist,
				los = dist < 120 and clearLine(eye, target),
				angle = angle,
				lit = lit,
				flashlight = player:GetAttribute("Flashlight") == true,
				hidden = hidden,
				invulnerable = mission:isInvulnerable(player.UserId, now),
			})
		end
	end
	return { pos = selfPos and toVec(selfPos) or nil, players = list }
end

---------------------------------------------------------------------------
-- Movement
---------------------------------------------------------------------------

local function computePath(from, to)
	if pathBusy then
		return
	end
	pathBusy = true
	task.spawn(function()
		local ok = pcall(function()
			path:ComputeAsync(from, to)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			pathWaypoints = path:GetWaypoints()
			pathIndex = math.min(2, #pathWaypoints)
		else
			pathWaypoints = nil
			pathFailedAt = os.clock()
		end
		pathTarget = to
		pathBusy = false
	end)
end

local function followPath(goal, speed)
	local h = humanoid()
	local r = root()
	if not h or not r then
		return
	end
	h.WalkSpeed = speed
	if not path then
		path = PathfindingService:CreatePath({
			AgentRadius = 1.6,
			AgentHeight = 9,
			AgentCanJump = false,
			WaypointSpacing = 4,
			Costs = { Door = 2, LockedDoor = math.huge },
		})
	end
	local moved = not pathTarget or (pathTarget - goal).Magnitude > 5
	-- After a failed search, wait a second before trying the same goal again.
	if moved or (not pathWaypoints and os.clock() - pathFailedAt > 1) then
		computePath(r.Position, goal)
	end
	if pathWaypoints and pathWaypoints[pathIndex] then
		local wp = pathWaypoints[pathIndex].Position
		local flat = Vector3.new(wp.X - r.Position.X, 0, wp.Z - r.Position.Z)
		if flat.Magnitude < 2.5 and pathIndex < #pathWaypoints then
			pathIndex += 1
			wp = pathWaypoints[pathIndex].Position
		end
		h:MoveTo(wp)
	else
		-- No path (yet): head straight for it.
		h:MoveTo(goal)
	end
end

local function openDoorsAhead()
	local r = root()
	if not r then
		return
	end
	for _, doorId in deps.WorldService.closedDoorsNear(r.Position, DOOR_OPEN_RADIUS) do
		local entry = deps.WorldService.door(doorId)
		-- It never opens a refuge door: the soundproof edit bay is a safe room.
		if entry and not entry.refuge then
			deps.WorldService.openDoor(doorId)
			deps.MissionService.cue({ cue = "DoorForced", door = doorId })
		end
	end
end

local function checkStuck(now, moving)
	local r = root()
	if not r or not moving then
		lastProgress = { pos = r and r.Position, at = now }
		stuckCount = 0
		return false
	end
	if not lastProgress.pos or (r.Position - lastProgress.pos).Magnitude > 1 then
		lastProgress = { pos = r.Position, at = now }
		return false
	end
	if now - lastProgress.at > STUCK_TIME then
		lastProgress = { pos = r.Position, at = now }
		stuckCount += 1
		pathTarget = nil
		return stuckCount >= 3
	end
	return false
end

local function step(now)
	local mission = deps.MissionService.mission
	local brain = EntityService.brain
	if not mission or not brain then
		return
	end
	local out = brain:update(now, sense(mission, now))
	local model = EntityService.model

	if out.events then
		for _, e in out.events do
			deps.MissionService.presenterEvent(e.name, e.data or {})
		end
	end

	if out.catchId then
		deps.MissionService.caught(out.catchId, EntityService.activeEventId)
	end

	if not out.visible then
		park()
	else
		if out.teleportTo then
			place(out.teleportTo, out.face)
		end
		local r = root()
		local h = humanoid()
		if r and h and model.Parent == Workspace then
			if out.moveTo then
				local goal = toV3(out.moveTo) + Vector3.new(0, 0, 0)
				if out.state == "Hunting" and out.chasing ~= nil then
					followPath(goal, out.speed or 14)
					openDoorsAhead()
				elseif (out.speed or 0) > 0 then
					local flat = Vector3.new(goal.X - r.Position.X, 0, goal.Z - r.Position.Z)
					if flat.Magnitude > TELEPORT_DRIFT then
						place(out.moveTo, out.face)
					else
						h.WalkSpeed = math.max(out.speed, 2)
						h:MoveTo(goal)
					end
					openDoorsAhead()
				else
					h:MoveTo(r.Position)
					face(out.face)
				end
			elseif out.face then
				face(out.face)
			end
			local moving = out.state == "Hunting" and out.huntPhase == "chase"
			if checkStuck(now, moving) then
				-- Fairness: a stuck pursuer gives up rather than camping a doorway.
				brain:vanish("Stuck")
				deps.MissionService.presenterEvent("HuntEnd", { reason = "Stuck" })
				park()
			end
		end
	end

	if out.state ~= EntityService.state then
		EntityService.state = out.state
	end
	if model then
		model:SetAttribute("State", out.state)
		model:SetAttribute("HuntPhase", out.huntPhase or "")
		model:SetAttribute("TargetId", out.targetId or 0)
	end
end

function EntityService.init(dependencies)
	deps = dependencies
	parked = Instance.new("Folder")
	parked.Name = "PresenterParking"
	parked.Parent = ServerStorage
	EntityService.reset(nil)

	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(step, Workspace:GetServerTimeNow())
			if not ok then
				warn("[EntityService] " .. tostring(err))
			end
		end
	end)
end

return EntityService
