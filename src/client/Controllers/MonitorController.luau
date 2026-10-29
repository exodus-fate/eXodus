--[[
	MonitorController — live CCTV on the station's CRT monitors.

	Only monitors near the player are active (performance). Feeds show the real
	room, the real Presenter if it is in frame, and investigators. Two scares live
	here, both presentation only:
	  * phantom frames: a figure appears on a feed of an empty room for a moment
	  * the editor's shadow: after the reception edit, the reception TV shows a
	    figure standing right behind the person who made it
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapLayout = require(Shared.Config.MapLayout)

local State = require(script.Parent.Parent.State)
local FootageView = require(script.Parent.Parent.UI.FootageView)

local MonitorController = {}

local ACTIVE_RADIUS = 34
local MAX_ACTIVE = 5
local UPDATE_INTERVAL = 0.2

local monitors = {} -- [screenPart] = { gui, view, cameraId, role }
local phantom = nil -- { cameraId, until, pos }
local shadow = nil -- { userId, until }
local nextPhantomAt = os.clock() + 70
local rng = Random.new()

local function myRoot()
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function presenterPos()
	local model = Workspace:FindFirstChild("Presenter")
	if model and model:IsA("Model") and model.PrimaryPart then
		return model.PrimaryPart.Position
	end
	return nil
end

local function ensure(screen)
	local entry = monitors[screen]
	if entry then
		return entry
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "CCTV"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.Parent = screen
	local view = FootageView.new(gui, { compact = true })
	entry = { gui = gui, view = view, cameraId = screen:GetAttribute("CameraId"), role = screen:GetAttribute("MonitorRole"), enabled = false }
	view:setCamera(entry.cameraId)
	monitors[screen] = entry
	return entry
end

local function setEnabled(entry, on)
	if entry.enabled ~= on then
		entry.enabled = on
		entry.gui.Enabled = on
		if on then
			entry.view:powerOn()
		end
	end
end

local function liveActors(cameraId, t)
	local camera = MapLayout.Cameras[cameraId]
	local actors = {}
	local p = presenterPos()
	if p then
		local pos = { x = p.X, y = 0, z = p.Z }
		if MapLayout.inRooms(pos, camera.rooms, 1) then
			table.insert(actors, { kind = "Presenter", pos = pos, look = { x = camera.pos.x, y = 0, z = camera.pos.z } })
		end
	end
	if phantom and phantom.cameraId == cameraId and t < phantom.untilTime then
		table.insert(actors, { kind = "Presenter", pos = phantom.pos, look = { x = camera.pos.x, y = 0, z = camera.pos.z } })
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local pos = { x = hrp.Position.X, y = 0, z = hrp.Position.Z }
			if MapLayout.inRooms(pos, camera.rooms, 0.5) then
				local look = hrp.Position + hrp.CFrame.LookVector * 4
				table.insert(actors, { kind = "Investigator", pos = pos, look = { x = look.X, y = 0, z = look.Z } })
				if shadow and shadow.userId == player.UserId and t < shadow.untilTime then
					local behind = hrp.Position - hrp.CFrame.LookVector * 2.6
					table.insert(actors, { kind = "Presenter", pos = { x = behind.X, y = 0, z = behind.Z }, look = { x = hrp.Position.X, y = 0, z = hrp.Position.Z } })
				end
			end
		end
	end
	return actors
end

local function lightMode(cameraId)
	local camera = MapLayout.Cameras[cameraId]
	local station = Workspace:FindFirstChild("Station04")
	local folder = station and station:FindFirstChild("Rooms") and station.Rooms:FindFirstChild(camera.rooms[1])
	return folder and folder:GetAttribute("LightMode") or "off"
end

local function maybePhantom(t)
	if t < nextPhantomAt or not State.inMission() or presenterPos() then
		return
	end
	nextPhantomAt = t + rng:NextInteger(60, 120)
	local root = myRoot()
	if not root then
		return
	end
	-- Pick an active monitor showing a room the player is not in.
	local here = MapLayout.roomAt(root.Position.X, root.Position.Z)
	local candidates = {}
	for _, entry in monitors do
		local camera = MapLayout.Cameras[entry.cameraId]
		if entry.enabled and camera and not table.find(camera.rooms, here) then
			table.insert(candidates, entry)
		end
	end
	if #candidates == 0 then
		return
	end
	local entry = candidates[rng:NextInteger(1, #candidates)]
	local camera = MapLayout.Cameras[entry.cameraId]
	local roomId = camera.rooms[1]
	phantom = {
		cameraId = entry.cameraId,
		untilTime = t + 1.6,
		pos = MapLayout.point(roomId, 0.3 + rng:NextNumber() * 0.4, 0.3 + rng:NextNumber() * 0.4),
	}
end

local function update()
	local t = os.clock()
	local root = myRoot()
	local inStation = State.inMission()
	maybePhantom(t)
	local nearby = {}
	for _, screen in CollectionService:GetTagged("CCTVMonitor") do
		if screen:IsDescendantOf(Workspace) and screen:GetAttribute("CameraId") and MapLayout.Cameras[screen:GetAttribute("CameraId")] then
			local d = root and (screen.Position - root.Position).Magnitude or math.huge
			if inStation and d <= ACTIVE_RADIUS and screen:GetAttribute("MonitorRole") ~= "Van" then
				table.insert(nearby, { screen = screen, d = d })
			elseif monitors[screen] then
				setEnabled(monitors[screen], false)
			end
		end
	end
	table.sort(nearby, function(a, b)
		return a.d < b.d
	end)
	local m = State.mission
	local powered = m and m.flags and m.flags.generator_restored
	for i = MAX_ACTIVE + 1, #nearby do
		local far = monitors[nearby[i].screen]
		if far then
			setEnabled(far, false)
		end
	end
	for i = 1, math.min(#nearby, MAX_ACTIVE) do
		local item = nearby[i]
		local entry = ensure(item.screen)
		local camera = MapLayout.Cameras[entry.cameraId]
		local live = camera.relay == "LOCAL" or powered
		setEnabled(entry, true)
		if live then
			entry.view:setCamera(entry.cameraId)
			entry.view:setLights(lightMode(entry.cameraId))
			entry.view:setActors(liveActors(entry.cameraId, t))
			local quality = 90
			local p = presenterPos()
			if p then
				quality -= math.clamp(40 - (p - Vector3.new(camera.pos.x, camera.pos.y, camera.pos.z)).Magnitude, 0, 40)
			end
			entry.view:setSignal(quality, State.intensity("distortion"))
			entry.view:setTexts({ message = "" })
		else
			entry.view:setActors({})
			entry.view:setLights("off")
			entry.view:setSignal(5, State.intensity("distortion"))
			entry.view:setTexts({ message = "NO SIGNAL" })
		end
		entry.view:step(UPDATE_INTERVAL)
	end
end

function MonitorController.init()
	State.cue:Connect(function(cue)
		if cue.cue == "EditorShadow" and cue.userId then
			shadow = { userId = cue.userId, untilTime = os.clock() + 4.5 }
		end
	end)
	-- Station resets replace every monitor part.
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Station04" then
			for screen, entry in monitors do
				entry.view:destroy()
				entry.gui:Destroy()
				monitors[screen] = nil
			end
		end
	end)
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum >= UPDATE_INTERVAL then
			accum = 0
			local ok, err = pcall(update)
			if not ok then
				warn("[MonitorController] " .. tostring(err))
			end
		end
	end)
end

return MonitorController
