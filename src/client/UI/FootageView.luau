--[[
	FootageView — renders one station camera as an old black-and-white tube
	monitor, the kind of closed-circuit set a 1960s building would have had.

	The scene is a static clone of the camera's rooms inside a ViewportFrame,
	converted to greyscale when it is built. Figures (the Presenter,
	investigators) are posed where the footage model says they are. On top sit
	the tube effects: a cool phosphor tint, interlace scanlines, film-like grain
	and dust, a slow dark hum bar rolling up the picture, brightness flicker,
	vertical-hold slips, a faint horizontal wobble, curved-glass falloff at the
	edges, rounded tube corners with a black bezel, and a glass reflection.
	Changing channel rolls the picture; powering on opens from a bright line.
	Noise and slips scale with signal quality and the distortion setting.

	Used by the Time-Shift Deck, the live monitors in the station, the handheld
	monitor and the van monitor.
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

-- Monochrome: emergency lighting simply reads as a dimmer picture.
local LIGHT_MODES = {
	on = { ambient = Color3.fromRGB(150, 150, 150), light = Color3.fromRGB(226, 226, 226) },
	emergency = { ambient = Color3.fromRGB(78, 78, 78), light = Color3.fromRGB(150, 150, 150) },
	off = { ambient = Color3.fromRGB(14, 14, 14), light = Color3.fromRGB(24, 24, 24) },
}

local PHOSPHOR = Color3.fromRGB(218, 226, 232) -- cool white of an old tube
local OSD_TEXT = Color3.fromRGB(236, 238, 232)

local NOISE_COUNT = 64
local NOISE_COUNT_COMPACT = 22
local SCANLINES = 60
local SCANLINES_COMPACT = 30

-- Luminance with a little extra contrast, as a tube set renders it.
local function mono(colour)
	local l = 0.299 * colour.R + 0.587 * colour.G + 0.114 * colour.B
	l = math.clamp((l - 0.5) * 1.18 + 0.5, 0, 1)
	return Color3.new(l, l, l)
end

local function toMonochrome(root)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = mono(d.Color)
		end
	end
end

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
	self.t = 0
	self.rollOffset = 0
	self.switchUntil = 0
	self.powerT = 1
	self.flicker = 0
	self.viewport = UI.new("ViewportFrame", {
		Name = "Viewport",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ImageColor3 = PHOSPHOR,
		Ambient = LIGHT_MODES.on.ambient,
		LightColor = LIGHT_MODES.on.light,
		LightDirection = Vector3.new(-0.3, -1, -0.2),
		Parent = self.root,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0.06, 0), Parent = self.viewport })
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
	local lines = self.compact and SCANLINES_COMPACT or SCANLINES
	for i = 0, lines - 1 do
		UI.new("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.8,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, i / lines),
			Size = UDim2.new(1, 0, 0, 1),
			ZIndex = 5,
			Parent = self.overlay,
		})
	end
	-- Grain: bright specks and dark dust.
	self.noise = {}
	for i = 1, self.compact and NOISE_COUNT_COMPACT or NOISE_COUNT do
		self.noise[i] = UI.new("Frame", {
			BackgroundColor3 = i % 3 == 0 and Color3.new(0, 0, 0) or Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = self.overlay,
		})
	end
	-- The hum bar: a soft dark band that crawls up the picture.
	self.band = UI.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0.22, 0),
		ZIndex = 6,
		Parent = self.overlay,
	})
	self.bandGradient = UI.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.7),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = self.band,
	})
	-- A thin bright tracking line that sometimes rides with the bar.
	self.trackLine = UI.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 2),
		ZIndex = 6,
		Parent = self.overlay,
	})
	-- Whole-picture brightness flicker.
	self.flickerFrame = UI.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 7,
		Parent = self.overlay,
	})
	-- Curved glass: the picture falls off towards the edges.
	local function falloff(rotation, size, position, anchor)
		local f = UI.new("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			AnchorPoint = anchor,
			Position = position,
			Size = size,
			ZIndex = 7,
			Parent = self.overlay,
		})
		UI.new("UIGradient", {
			Rotation = rotation,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.25),
				NumberSequenceKeypoint.new(0.5, 0.82),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = f,
		})
	end
	falloff(90, UDim2.fromScale(1, 0.24), UDim2.fromScale(0, 0), Vector2.new(0, 0))
	falloff(-90, UDim2.fromScale(1, 0.24), UDim2.fromScale(0, 1), Vector2.new(0, 1))
	falloff(0, UDim2.fromScale(0.18, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0))
	falloff(180, UDim2.fromScale(0.18, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0))
	-- Reflection on the glass, top left.
	local glare = UI.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.55, 0.45),
		ZIndex = 7,
		Parent = self.overlay,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0.3, 0), Parent = glare })
	UI.new("UIGradient", {
		Rotation = 35,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(0.45, 0.965),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = glare,
	})
	-- Power-on: the picture opens out of a bright horizontal line.
	self.powerTop = UI.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.fromScale(1, 0), ZIndex = 9, Parent = self.overlay })
	self.powerBottom = UI.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		ZIndex = 9,
		Parent = self.overlay,
	})
	self.powerLine = UI.new("Frame", {
		BackgroundColor3 = PHOSPHOR,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, 3),
		ZIndex = 9,
		Parent = self.overlay,
	})
	-- Rounded tube mask and bezel over everything.
	local bezel = UI.new("Frame", { Name = "Bezel", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = self.root })
	UI.new("UICorner", { CornerRadius = UDim.new(0.06, 0), Parent = bezel })
	UI.new("UIStroke", {
		Color = Color3.fromRGB(14, 14, 12),
		Thickness = self.compact and 4 or 10,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = bezel,
	})
	self.message = UI.text(self.overlay, "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.2),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = OSD_TEXT,
		TextStrokeTransparency = 0.4,
		TextSize = self.compact and 14 or 22,
		ZIndex = 8,
	})
	self.hidden = UI.text(self.overlay, "", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.12),
		Size = UDim2.fromScale(0.8, 0.1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = OSD_TEXT,
		TextTransparency = 0.55,
		TextSize = 14,
		ZIndex = 8,
	})
	if not self.compact then
		self.label = UI.text(self.overlay, "", {
			Position = UDim2.new(0, 10, 0, 6),
			Size = UDim2.new(0.6, 0, 0, 20),
			TextColor3 = OSD_TEXT,
			TextStrokeTransparency = 0.5,
			ZIndex = 8,
		})
		self.timestamp = UI.text(self.overlay, "", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 6),
			Size = UDim2.new(0.4, 0, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = OSD_TEXT,
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
	toMonochrome(scene)
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
	if self.cameraId ~= nil and self.cameraId ~= cameraId then
		-- Changing channel: the picture rolls and breaks up for a moment.
		self.switchUntil = self.t + 0.35
		self.rollOffset = 0.6
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
		local model = Figures.presenter(parent, { ghost = true })
		toMonochrome(model)
		return model
	end, #presenters)
	pool(self, self.investigatorPool, function(parent)
		local model = Figures.investigator(parent)
		toMonochrome(model)
		return model
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

-- Plays the tube warming up: the picture opens out of a bright line.
function FootageView:powerOn()
	self.powerT = 0
end

-- Animates the tube; call every frame (or a few times a second for monitors).
function FootageView:step(dt)
	self.t += dt
	local t = self.t
	local rng = self.rng
	local switching = t < self.switchUntil
	local loss = math.clamp((100 - self.quality) / 100, 0, 1)
	if switching then
		loss = math.max(loss, 0.75)
	end
	local intensity = self.intensity

	-- Grain is always there on an old set; signal loss thickens it.
	local amount = math.clamp(0.3 + loss * 0.7, 0, 1) * math.max(intensity, 0.35)
	local active = math.floor(#self.noise * amount + 0.5)
	for i, dot in self.noise do
		if i <= active then
			local long = rng:NextNumber() < loss * 0.5
			dot.BackgroundTransparency = 0.35 + rng:NextNumber() * 0.55
			dot.Size = long and UDim2.new(rng:NextNumber() * 0.25, 2, 0, rng:NextInteger(1, 2)) or UDim2.fromOffset(rng:NextInteger(1, 3), rng:NextInteger(1, 3))
			dot.Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber())
		else
			dot.BackgroundTransparency = 1
		end
	end

	-- Hum bar crawling upwards, about one pass every seven seconds.
	local barY = 1.1 - ((t * 0.15) % 1.35)
	self.band.Position = UDim2.fromScale(0, barY - 0.11)
	self.bandGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, math.clamp(0.8 - loss * 0.3 * intensity, 0.4, 0.9)),
		NumberSequenceKeypoint.new(1, 1),
	})
	local tracking = loss > 0.3 or rng:NextNumber() < 0.04
	self.trackLine.Position = UDim2.fromScale(0, barY + (rng:NextNumber() - 0.5) * 0.04)
	self.trackLine.BackgroundTransparency = tracking and (0.55 + rng:NextNumber() * 0.35) or 1

	-- Brightness flicker, with the odd bright pulse.
	local target = 0.9 + rng:NextNumber() * 0.08
	if rng:NextNumber() < 0.03 * math.max(intensity, 0.3) then
		target = 0.75
	end
	self.flicker += (target - self.flicker) * 0.5
	self.flickerFrame.BackgroundTransparency = self.flicker + (1 - self.flicker) * (1 - math.min(1, intensity + 0.3))

	-- Vertical hold slips: the frame rolls and snaps back.
	if self.rollOffset <= 0 and rng:NextNumber() < loss * loss * 0.04 * intensity then
		self.rollOffset = 0.25 + rng:NextNumber() * 0.5
	end
	local rollY = 0
	if self.rollOffset > 0 then
		rollY = self.rollOffset
		self.rollOffset = math.max(0, self.rollOffset - dt * 2.4)
	end
	-- Horizontal wobble from an unsteady time base, worse on a weak signal.
	local wobble = math.sin(t * 7.3) * (0.6 + loss * 3) + math.sin(t * 23.1) * 0.4
	local jitter = loss > 0.45 and (rng:NextNumber() - 0.5) * 10 * loss * intensity or 0
	self.viewport.Position = UDim2.new(0, wobble * intensity + jitter, -rollY, 0)
	self.viewport.ImageTransparency = math.clamp(loss * 0.55 + (switching and 0.3 or 0), 0, 0.75)

	-- Power-on animation.
	if self.powerT < 1 then
		self.powerT = math.min(1, self.powerT + dt / 0.45)
		local open = self.powerT < 0.35 and 0 or (self.powerT - 0.35) / 0.65
		local closed = (1 - open) / 2
		self.powerTop.Size = UDim2.fromScale(1, closed)
		self.powerBottom.Size = UDim2.fromScale(1, closed)
		self.powerLine.BackgroundTransparency = self.powerT < 0.5 and 0 or (self.powerT - 0.5) * 2
		self.powerLine.Size = UDim2.new(math.min(1, self.powerT / 0.35), 0, 0, 3)
	elseif self.powerTop.Size.Y.Scale > 0 or self.powerLine.BackgroundTransparency < 1 then
		self.powerTop.Size = UDim2.fromScale(1, 0)
		self.powerBottom.Size = UDim2.fromScale(1, 0)
		self.powerLine.BackgroundTransparency = 1
	end
end

function FootageView:destroy()
	self.root:Destroy()
end

return FootageView
