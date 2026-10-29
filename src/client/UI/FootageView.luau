--[[
	FootageView — renders one station camera as grainy analog CCTV.

	The scene is a static clone of the camera's rooms inside a ViewportFrame.
	Figures (the Presenter, investigators) are posed where the footage model says
	they are. Noise, scanlines and tracking distortion scale with signal quality
	and the player's distortion setting. Used by the Time-Shift Deck, the live
	monitors in the station, the handheld monitor and the van monitor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapLayout = require(Shared.Config.MapLayout)
local Figures = require(Shared.World.Figures)

local UI = require(script.Parent.UI)
local Theme = require(script.Parent.Theme)

local FootageView = {}
FootageView.__index = FootageView

local LIGHT_MODES = {
	on = { ambient = Color3.fromRGB(140, 150, 140), light = Color3.fromRGB(210, 225, 210) },
	emergency = { ambient = Color3.fromRGB(86, 62, 40), light = Color3.fromRGB(170, 110, 55) },
	off = { ambient = Color3.fromRGB(16, 18, 16), light = Color3.fromRGB(26, 28, 26) },
}

local NOISE_COUNT = 36
local SCANLINES = 48

local function v3(p, y)
	return Vector3.new(p.x, y or p.y or 0, p.z)
end

local function roomsTouch(doorRooms, rooms)
	for _, id in doorRooms do
		if table.find(rooms, id) then
			return true
		end
	end
	return false
end

--[[
	opts = { compact = bool (no labels, for small monitors), zIndex = number }
]]
function FootageView.new(parent, opts)
	opts = opts or {}
	local self = setmetatable({}, FootageView)
	self.compact = opts.compact == true
	self.scenes = {}
	self.cameraId = nil
	self.station = nil
	self.quality = 100
	self.intensity = 1
	self.bandY = 0
	self.rng = Random.new()

	self.root = UI.new("Frame", {
		Name = "Footage",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = opts.size or UDim2.fromScale(1, 1),
		Position = opts.position or UDim2.new(),
		Parent = parent,
	})
	self.viewport = UI.new("ViewportFrame", {
		Name = "Viewport",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ImageColor3 = Color3.fromRGB(196, 222, 196),
		Ambient = LIGHT_MODES.on.ambient,
		LightColor = LIGHT_MODES.on.light,
		LightDirection = Vector3.new(-0.3, -1, -0.2),
		Parent = self.root,
	})
	self.camera = Instance.new("Camera")
	self.camera.FieldOfView = 68
	self.camera.Parent = self.viewport
	self.viewport.CurrentCamera = self.camera

	self.figureRoot = Instance.new("Model")
	self.figureRoot.Name = "Figures"
	self.figureRoot.Parent = self.viewport
	self.presenterPool = {}
	self.investigatorPool = {}

	-- Overlays
	self.overlay = UI.new("Frame", { Name = "Overlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = self.root })
	for i = 0, SCANLINES - 1 do
		UI.new("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.84,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, i / SCANLINES),
			Size = UDim2.new(1, 0, 0, 1),
			ZIndex = 5,
			Parent = self.overlay,
		})
	end
	self.noise = {}
	for i = 1, NOISE_COUNT do
		self.noise[i] = UI.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = self.overlay,
		})
	end
	self.band = UI.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0.05, 0),
		ZIndex = 6,
		Parent = self.overlay,
	})
	self.message = UI.text(self.overlay, "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.2),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(230, 236, 226),
		TextStrokeTransparency = 0.4,
		TextSize = self.compact and 14 or 22,
		ZIndex = 8,
	})
	self.hidden = UI.text(self.overlay, "", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.12),
		Size = UDim2.fromScale(0.8, 0.1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(230, 236, 226),
		TextTransparency = 0.55,
		TextSize = 14,
		ZIndex = 8,
	})
	if not self.compact then
		self.label = UI.text(self.overlay, "", {
			Position = UDim2.new(0, 10, 0, 6),
			Size = UDim2.new(0.6, 0, 0, 20),
			TextColor3 = Color3.fromRGB(230, 236, 226),
			TextStrokeTransparency = 0.5,
			ZIndex = 8,
		})
		self.timestamp = UI.text(self.overlay, "", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 6),
			Size = UDim2.new(0.4, 0, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Color3.fromRGB(230, 236, 226),
			TextStrokeTransparency = 0.5,
			ZIndex = 8,
		})
		self.status = UI.text(self.overlay, "", {
			Position = UDim2.new(0, 10, 1, -26),
			Size = UDim2.new(1, -20, 0, 20),
			TextColor3 = Theme.Amber,
			TextStrokeTransparency = 0.5,
			ZIndex = 8,
		})
	end
	return self
end

---------------------------------------------------------------------------
-- Scene
---------------------------------------------------------------------------

function FootageView:_station()
	local station = Workspace:FindFirstChild("Station04")
	if station ~= self.station then
		for _, scene in self.scenes do
			scene:Destroy()
		end
		self.scenes = {}
		self.station = station
	end
	return station
end

function FootageView:_buildScene(cameraId)
	local station = self:_station()
	local camera = MapLayout.Cameras[cameraId]
	if not station or not camera then
		return nil
	end
	local scene = Instance.new("Model")
	scene.Name = cameraId
	local rooms = station:FindFirstChild("Rooms")
	for _, roomId in camera.rooms do
		local source = rooms and rooms:FindFirstChild(roomId)
		if source then
			local copy = source:Clone()
			-- Strip anything a viewport can't render. This matters: rooms hold the
			-- CCTV monitors, whose SurfaceGuis contain their own cloned scenes -
			-- keeping them would nest copies inside copies on every monitor.
			for _, d in copy:GetDescendants() do
				if d:IsA("LayerCollector") or d:IsA("Light") or d:IsA("ProximityPrompt") or d:IsA("Sound") then
					d:Destroy()
				end
			end
			copy.Parent = scene
		end
	end
	local doors = station:FindFirstChild("Doors")
	if doors then
		for _, door in doors:GetChildren() do
			local layout = MapLayout.doorById(door.Name)
			if layout and roomsTouch(layout.rooms, camera.rooms) then
				door:Clone().Parent = scene
			end
		end
	end
	local windows = station:FindFirstChild("Windows")
	if windows then
		for _, glass in windows:GetChildren() do
			local id = glass:GetAttribute("WindowId")
			for _, win in MapLayout.Windows do
				if win.id == id and roomsTouch(win.rooms, camera.rooms) then
					glass:Clone().Parent = scene
				end
			end
		end
	end
	return scene
end

function FootageView:setCamera(cameraId)
	self:_station()
	if self.cameraId == cameraId and self.scenes[cameraId] and self.scenes[cameraId].Parent == self.viewport then
		return
	end
	for _, scene in self.scenes do
		scene.Parent = nil
	end
	self.cameraId = cameraId
	local camera = MapLayout.Cameras[cameraId]
	if not camera then
		return
	end
	local scene = self.scenes[cameraId]
	if not scene then
		scene = self:_buildScene(cameraId)
		self.scenes[cameraId] = scene
	end
	if scene then
		scene.Parent = self.viewport
	end
	self.camera.CFrame = CFrame.lookAt(v3(camera.pos), v3(camera.look))
	if self.label then
		self.label.Text = camera.label
	end
end

function FootageView:setLights(mode)
	local look = LIGHT_MODES[mode] or LIGHT_MODES.on
	self.viewport.Ambient = look.ambient
	self.viewport.LightColor = look.light
end

local function pool(self, list, build, count)
	while #list < count do
		table.insert(list, build(self.figureRoot))
	end
	for i, model in list do
		if i > count then
			model.Parent = nil
		elseif model.Parent ~= self.figureRoot then
			model.Parent = self.figureRoot
		end
	end
end

local function pose(model, pos, look)
	local height = Figures.rootHeight(model)
	local at = Vector3.new(pos.x, (pos.y or 0) + height, pos.z)
	local target = look and Vector3.new(look.x, at.Y, look.z) or (at + Vector3.new(0, 0, -1))
	if (target - at).Magnitude < 0.1 then
		target = at + Vector3.new(0, 0, -1)
	end
	model:PivotTo(CFrame.lookAt(at, target))
end

-- actors: { { kind = "Presenter" | "Investigator", pos, look } }
function FootageView:setActors(actors)
	local presenters, people = {}, {}
	for _, a in actors or {} do
		if a.kind == "Presenter" then
			table.insert(presenters, a)
		else
			table.insert(people, a)
		end
	end
	pool(self, self.presenterPool, function(parent)
		return Figures.presenter(parent, { ghost = true })
	end, #presenters)
	pool(self, self.investigatorPool, function(parent)
		return Figures.investigator(parent)
	end, #people)
	for i, a in presenters do
		pose(self.presenterPool[i], a.pos, a.look)
	end
	for i, a in people do
		pose(self.investigatorPool[i], a.pos, a.look)
	end
end

---------------------------------------------------------------------------
-- Overlays
---------------------------------------------------------------------------

function FootageView:setSignal(quality, intensity)
	self.quality = quality
	self.intensity = intensity or 1
end

function FootageView:setTexts(texts)
	if texts.message ~= nil then
		self.message.Text = texts.message
	end
	if texts.hidden ~= nil then
		self.hidden.Text = texts.hidden
	end
	if self.timestamp and texts.timestamp ~= nil then
		self.timestamp.Text = texts.timestamp
	end
	if self.status and texts.status ~= nil then
		self.status.Text = texts.status
	end
	if self.label and texts.label ~= nil then
		self.label.Text = texts.label
	end
end

-- Animates noise; call every frame (or a few times a second for monitors).
function FootageView:step(dt)
	local loss = math.clamp((100 - self.quality) / 100, 0, 1)
	local amount = math.clamp(0.15 + loss * 0.85, 0, 1) * self.intensity
	local active = math.floor(NOISE_COUNT * amount + 0.5)
	local rng = self.rng
	for i, dot in self.noise do
		if i <= active then
			dot.BackgroundTransparency = 0.25 + rng:NextNumber() * 0.6
			dot.Size = UDim2.new(rng:NextNumber() * 0.12, 2, 0, rng:NextInteger(1, 3))
			dot.Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber())
		else
			dot.BackgroundTransparency = 1
		end
	end
	self.bandY = (self.bandY + dt * (0.25 + loss * 0.6)) % 1.1
	self.band.Position = UDim2.fromScale(0, self.bandY - 0.05)
	self.band.Size = UDim2.new(1, 0, 0.04 + loss * 0.1 * self.intensity, 0)
	self.band.BackgroundTransparency = 0.92 - loss * 0.25 * self.intensity
	local jitter = loss > 0.45 and (rng:NextNumber() - 0.5) * 10 * loss * self.intensity or 0
	self.viewport.Position = UDim2.fromOffset(jitter, 0)
	self.viewport.ImageTransparency = math.clamp(loss * 0.55, 0, 0.6)
end

function FootageView:destroy()
	self.root:Destroy()
end

return FootageView
