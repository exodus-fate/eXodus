--[[
	PresenterBrain — decision making for the Presenter, independent of Roblox.

	States (from the brief):
	  Dormant    appears only in footage. Not in the world.
	  Observing  stands at a distance and watches. Comes closer only if you do.
	  Displaced  follows an authored route caused by a timeline event.
	  Hunting    pursues one player after a telegraphed wind-up.
	  Rewinding  stands still while a room replays its earlier state.

	Fairness rules baked in:
	  * Every hunt starts with a wind-up (it stops, the cue plays) before it moves.
	  * It needs line of sight to start a hunt and loses you after a few seconds
	    out of sight; it then searches your last known position and gives up.
	  * Hunts have a hard time limit, and after any hunt it vanishes (release).
	  * Players inside a closed refuge, or who were just revived, are invisible to it.

	The glue layer feeds `sense` each tick and applies the returned intent:
	  sense = {
	    pos = {x,y,z} | nil,   -- current world position (nil while not in the world)
	    players = { { id, pos, dist, los, angle, lit, flashlight, hidden, invulnerable } },
	  }
	  output = {
	    state, visible, teleportTo, moveTo, speed, face, targetId, catchId, events = {...}
	  }
]]

local Vec = require(script.Parent.Parent.Util.Vec)

local PresenterBrain = {}
PresenterBrain.__index = PresenterBrain

PresenterBrain.DefaultConfig = {
	huntSpeed = 14.5,
	catchRadius = 3.6,
	windup = 2.5,
	loseSightTime = 6,
	searchTime = 4,
	maxHunt = 45,
	ambushKnowledge = 3,
	observeDuration = 8,
	observeTrigger = 12,
	huntSight = { range = 90, dark = 45, fov = 220, proximity = 10 },
	defaultSight = { range = 40, dark = 26, fov = 120, proximity = 6 },
}

function PresenterBrain.new(config)
	local merged = table.clone(PresenterBrain.DefaultConfig)
	for k, v in config or {} do
		merged[k] = v
	end
	local self = setmetatable({}, PresenterBrain)
	self.config = merged
	self.state = "Dormant"
	self.command = nil
	self.hunt = nil
	self.pendingEvents = {}
	self.needsAppear = false
	self.anchorPos = nil
	self.anchorLook = nil
	return self
end

local function canSee(p, sight)
	if p.hidden or p.invulnerable or not p.los then
		return false
	end
	local range = (p.lit or p.flashlight) and sight.range or sight.dark
	if p.dist > range then
		return false
	end
	if p.dist <= (sight.proximity or 0) then
		return true
	end
	return p.angle <= (sight.fov or 120) / 2
end
PresenterBrain.canSee = canSee

local function findPlayer(players, id)
	for _, p in players do
		if p.id == id then
			return p
		end
	end
	return nil
end

local function nearest(players, predicate)
	local best, bestDist = nil, math.huge
	for _, p in players do
		if predicate(p) and p.dist < bestDist then
			best, bestDist = p, p.dist
		end
	end
	return best
end

function PresenterBrain:_emit(name, data)
	table.insert(self.pendingEvents, { name = name, data = data })
end

function PresenterBrain:isIdle()
	return self.state == "Dormant"
end

function PresenterBrain:hasScriptedCommand()
	return self.command ~= nil and self.command.scripted == true
end

-- Ends whatever it is doing and leaves the world.
function PresenterBrain:vanish(reason)
	local wasVisible = self.state ~= "Dormant"
	self.state = "Dormant"
	self.command = nil
	self.hunt = nil
	self.anchorPos = nil
	if wasVisible then
		self:_emit("Vanish", { reason = reason })
	end
end

--[[
	cmd kinds:
	  { kind = "Displaced", path, duration, huntOnSight, sight }
	  { kind = "Ambush", pos, look, radius, windup, maxDuration }
	  { kind = "Observe", pos, look, duration, triggerRadius }
	  { kind = "Rewind", pos, look, duration, sight }
	  { kind = "Dormant" }
	meta.scripted = true for timeline events (they override awareness behaviour).
]]
function PresenterBrain:setCommand(cmd, startTime, meta)
	meta = meta or {}
	if self.hunt then
		self:_emit("HuntEnd", { reason = "Overridden", targetId = self.hunt.targetId })
	end
	self.hunt = nil
	if cmd.kind == "Dormant" then
		self:vanish("Command")
		return
	end
	self.command = { def = cmd, start = startTime, scripted = meta.scripted == true, eventId = meta.eventId }
	self.needsAppear = true
	if cmd.kind == "Displaced" then
		self.state = "Displaced"
	elseif cmd.kind == "Ambush" then
		self.anchorPos = cmd.pos
		self.anchorLook = cmd.look
		self.state = "Hunting"
		self.hunt = {
			phase = "windup",
			phaseStart = startTime,
			started = startTime,
			windup = cmd.windup or self.config.windup,
			targetId = nil,
			ambush = true,
			maxDuration = cmd.maxDuration or self.config.maxHunt,
		}
		self:_emit("HuntStart", { ambush = true })
	elseif cmd.kind == "Observe" then
		self.anchorPos = cmd.pos
		self.anchorLook = cmd.look
		self.state = "Observing"
	elseif cmd.kind == "Rewind" then
		self.anchorPos = cmd.pos
		self.anchorLook = cmd.look
		self.state = "Rewinding"
	end
	self:_emit("Appear", { kind = cmd.kind, eventId = meta.eventId })
end

local function pathPosition(path, elapsed)
	if elapsed <= path[1].t then
		return Vec.copy(path[1].pos), 0, path[1].look, 1
	end
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		if elapsed >= a.t and elapsed < b.t then
			local span = b.t - a.t
			local alpha = (elapsed - a.t) / span
			local speed = Vec.flatDistance(a.pos, b.pos) / span
			return Vec.lerp(a.pos, b.pos, alpha), speed, b.look, i
		end
	end
	local last = path[#path]
	return Vec.copy(last.pos), 0, last.look, #path
end
PresenterBrain.pathPosition = pathPosition

function PresenterBrain:_startHunt(now, target, windup, knowledge)
	self.state = "Hunting"
	self.hunt = {
		phase = "windup",
		phaseStart = now,
		started = now,
		windup = windup or self.config.windup,
		targetId = target and target.id or nil,
		lastKnown = target and Vec.copy(target.pos) or nil,
		lastSeen = now,
		knowsUntil = knowledge and (now + knowledge) or nil,
		maxDuration = self.config.maxHunt,
	}
	self:_emit("HuntStart", { targetId = self.hunt.targetId })
end

function PresenterBrain:_endHunt(reason)
	local targetId = self.hunt and self.hunt.targetId
	self:_emit("HuntEnd", { reason = reason, targetId = targetId })
	self:vanish(reason)
end

function PresenterBrain:update(now, sense)
	local out = {
		state = self.state,
		visible = false,
		events = nil,
	}
	local players = sense.players or {}
	local cfg = self.config
	local cmd = self.command and self.command.def

	if self.state == "Displaced" and cmd then
		local elapsed = now - self.command.start
		if elapsed >= (cmd.duration or 0) then
			self:vanish("RouteComplete")
		else
			local pos, speed, look = pathPosition(cmd.path, elapsed)
			if self.needsAppear then
				out.teleportTo = pos
				self.needsAppear = false
			end
			out.moveTo = pos
			out.speed = math.clamp(speed, 0, 16)
			out.face = look
			if cmd.huntOnSight then
				local sight = cmd.sight or cfg.defaultSight
				local seen = nearest(players, function(p)
					return canSee(p, sight)
				end)
				if seen then
					self:_startHunt(now, seen, cfg.windup)
				end
			end
		end
	elseif (self.state == "Observing" or self.state == "Rewinding") and cmd then
		local elapsed = now - self.command.start
		local duration = cmd.duration or cfg.observeDuration
		if elapsed >= duration then
			self:vanish(self.state == "Observing" and "ObserveComplete" or "RewindComplete")
		else
			if self.needsAppear then
				out.teleportTo = self.anchorPos
				self.needsAppear = false
			end
			out.moveTo = self.anchorPos
			out.speed = 0
			local closest = nearest(players, function(p)
				return not p.hidden and not p.invulnerable
			end)
			out.face = (self.state == "Observing" and closest and closest.pos) or self.anchorLook
			local trigger
			if self.state == "Observing" then
				local radius = cmd.triggerRadius or cfg.observeTrigger
				trigger = nearest(players, function(p)
					return p.los and not p.hidden and not p.invulnerable and p.dist <= radius
				end)
			else
				local sight = cmd.sight or cfg.defaultSight
				trigger = nearest(players, function(p)
					return canSee(p, sight)
				end)
			end
			if trigger then
				self:_startHunt(now, trigger, self.state == "Observing" and 1.5 or 2)
			end
		end
	end

	-- Hunting is evaluated after the transitions above so a hunt can start and
	-- report its wind-up on the same tick.
	if self.state == "Hunting" and self.hunt then
		local hunt = self.hunt
		if self.needsAppear and self.anchorPos then
			out.teleportTo = self.anchorPos
			self.needsAppear = false
		end
		if now - hunt.started > hunt.maxDuration then
			self:_endHunt("TimeLimit")
		elseif hunt.phase == "windup" then
			out.speed = 0
			if hunt.targetId then
				local t = findPlayer(players, hunt.targetId)
				out.face = t and t.pos or nil
			else
				out.face = self.anchorLook
			end
			if now - hunt.phaseStart >= hunt.windup then
				if hunt.ambush then
					local radius = (cmd and cmd.radius) or 70
					local target = nearest(players, function(p)
						return not p.hidden and not p.invulnerable and p.dist <= radius
					end)
					if target then
						hunt.targetId = target.id
						hunt.lastKnown = Vec.copy(target.pos)
						hunt.lastSeen = now
						hunt.knowsUntil = now + cfg.ambushKnowledge
						hunt.phase = "chase"
						hunt.phaseStart = now
					else
						-- Nobody here: it watches the room for a while instead.
						local pos = self.anchorPos
						local look = self.anchorLook
						self.hunt = nil
						self.state = "Observing"
						self.command = {
							def = { kind = "Observe", pos = pos, look = look, duration = 12 },
							start = now,
							scripted = self.command and self.command.scripted or false,
						}
						self:_emit("HuntEnd", { reason = "NoTarget" })
					end
				else
					hunt.phase = "chase"
					hunt.phaseStart = now
				end
			end
		end

		if self.hunt and (self.hunt.phase == "chase" or self.hunt.phase == "search") then
			hunt = self.hunt
			local target = hunt.targetId and findPlayer(players, hunt.targetId)
			if target and (target.hidden or target.invulnerable) then
				target = nil
			end
			local seesTarget = target and (canSee(target, cfg.huntSight) or (hunt.knowsUntil and now < hunt.knowsUntil))
			if seesTarget then
				hunt.lastKnown = Vec.copy(target.pos)
				hunt.lastSeen = now
				if hunt.phase == "search" then
					hunt.phase = "chase"
					hunt.phaseStart = now
				end
			end
			if target and seesTarget and target.dist <= cfg.catchRadius and target.los then
				out.catchId = target.id
				self:_endHunt("Caught")
			elseif hunt.phase == "chase" and now - hunt.lastSeen > cfg.loseSightTime then
				hunt.phase = "search"
				hunt.phaseStart = now
				self:_emit("Searching", { targetId = hunt.targetId })
			elseif hunt.phase == "search" and now - hunt.phaseStart > cfg.searchTime then
				self:_endHunt("Lost")
			end
			if self.hunt then
				out.moveTo = hunt.lastKnown
				out.speed = hunt.phase == "chase" and cfg.huntSpeed or cfg.huntSpeed * 0.6
				out.face = hunt.lastKnown
				out.targetId = hunt.targetId
				out.chasing = hunt.phase == "chase"
			end
		end
	end

	out.state = self.state
	out.visible = self.state ~= "Dormant"
	if self.hunt then
		out.huntPhase = self.hunt.phase
	end
	if #self.pendingEvents > 0 then
		out.events = self.pendingEvents
		self.pendingEvents = {}
	end
	return out
end

return PresenterBrain
