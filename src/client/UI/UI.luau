--[[
	Tiny UI construction helpers. Everything is built in code so the whole
	interface lives in the repository.
]]

local Theme = require(script.Parent.Theme)

local UI = {}

-- UI.new("Frame", { Size = ..., Parent = ... }, { children })
function UI.new(className, props, children)
	local inst = Instance.new(className)
	local parent = nil
	for k, v in props or {} do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UI.screen(name, order, playerGui)
	return UI.new("ScreenGui", {
		Name = name,
		DisplayOrder = order,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
end

function UI.stroke(parent, colour, thickness, transparency)
	return UI.new("UIStroke", {
		Color = colour or Theme.Line,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function UI.corner(parent, radius)
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 2), Parent = parent })
end

function UI.padding(parent, px, py)
	py = py or px
	return UI.new("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, py),
		PaddingBottom = UDim.new(0, py),
		Parent = parent,
	})
end

function UI.list(parent, padding, direction, align)
	return UI.new("UIListLayout", {
		Padding = UDim.new(0, padding or 6),
		FillDirection = direction or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		Parent = parent,
	})
end

function UI.panel(parent, props)
	local frame = UI.new("Frame", {
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Parent = parent,
	})
	for k, v in props or {} do
		frame[k] = v
	end
	UI.stroke(frame, Theme.Line, 1)
	return frame
end

function UI.text(parent, text, props)
	local label = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text or "",
		Font = Theme.Font,
		TextSize = Theme.TextSize,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
		RichText = false,
		Size = UDim2.new(1, 0, 0, Theme.TextSize + 6),
		Parent = parent,
	})
	for k, v in props or {} do
		label[k] = v
	end
	return label
end

-- Large, controller-selectable button with a visible focus state.
function UI.button(parent, text, onClick, props)
	local button = UI.new("TextButton", {
		BackgroundColor3 = Theme.PanelLight,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = text or "",
		Font = Theme.FontBold,
		TextSize = Theme.TextSize,
		TextColor3 = Theme.Text,
		Size = UDim2.new(1, 0, 0, Theme.TouchTarget),
		Selectable = true,
		Parent = parent,
	})
	for k, v in props or {} do
		button[k] = v
	end
	local stroke = UI.stroke(button, Theme.Line, 1)
	local function refresh(highlight)
		stroke.Color = highlight and Theme.Accent or Theme.Line
		stroke.Thickness = highlight and 2 or 1
		button.BackgroundColor3 = highlight and Theme.PanelLight:Lerp(Theme.Accent, 0.15) or Theme.PanelLight
	end
	button.MouseEnter:Connect(function()
		refresh(true)
	end)
	button.MouseLeave:Connect(function()
		refresh(false)
	end)
	button.SelectionGained:Connect(function()
		refresh(true)
	end)
	button.SelectionLost:Connect(function()
		refresh(false)
	end)
	if onClick then
		button.Activated:Connect(function()
			if button:GetAttribute("Disabled") then
				return
			end
			onClick(button)
		end)
	end
	return button
end

function UI.setEnabled(button, enabled)
	button:SetAttribute("Disabled", not enabled)
	button.TextTransparency = enabled and 0 or 0.55
	button.BackgroundTransparency = enabled and 0.05 or 0.4
end

-- Removes every child except layout objects.
function UI.clear(container)
	for _, child in container:GetChildren() do
		if not child:IsA("UIComponent") then
			child:Destroy()
		end
	end
end

-- A scrolling column that grows with its content.
function UI.scroll(parent, props)
	local frame = UI.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.AccentDim,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Selectable = false,
		Parent = parent,
	})
	for k, v in props or {} do
		frame[k] = v
	end
	return frame
end

-- Horizontal slider 0..1. onChange(value) fires while dragging.
function UI.slider(parent, label, value, onChange, opts)
	opts = opts or {}
	local holder = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = parent })
	local caption = UI.text(holder, "", { Size = UDim2.new(0.45, 0, 1, 0) })
	local track = UI.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.new(0.47, 0, 0.5, -8),
		Size = UDim2.new(0.5, 0, 0, 16),
		Selectable = true,
		Parent = holder,
	})
	UI.stroke(track, Theme.Line)
	local fill = UI.new("Frame", { BackgroundColor3 = Theme.AccentDim, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track })
	local min, max = opts.min or 0, opts.max or 1
	local step = opts.step or 0.05
	local current = value
	local function render()
		local alpha = (current - min) / (max - min)
		fill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
		caption.Text = string.format("%s  %s", label, opts.format and opts.format(current) or string.format("%d%%", math.floor(alpha * 100 + 0.5)))
	end
	local function setFromX(x)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		local raw = min + (max - min) * alpha
		current = math.clamp(math.floor(raw / step + 0.5) * step, min, max)
		render()
		onChange(current)
	end
	local dragging = false
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		elseif input.KeyCode == Enum.KeyCode.DPadRight or input.KeyCode == Enum.KeyCode.Right then
			current = math.clamp(current + step, min, max)
			render()
			onChange(current)
		elseif input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.Left then
			current = math.clamp(current - step, min, max)
			render()
			onChange(current)
		end
	end)
	track.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	track.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	render()
	return holder
end

function UI.toggle(parent, label, value, onChange)
	local current = value
	local button
	button = UI.button(parent, "", function()
		current = not current
		button.Text = string.format("%s: %s", label, current and "ON" or "OFF")
		onChange(current)
	end)
	button.Text = string.format("%s: %s", label, current and "ON" or "OFF")
	button.TextXAlignment = Enum.TextXAlignment.Left
	UI.padding(button, 10, 0)
	return button
end

-- An invisible modal button: while visible it frees the mouse in first person.
function UI.modalUnlock(parent)
	return UI.new("TextButton", {
		Name = "ModalUnlock",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		Modal = true,
		Selectable = false,
		Parent = parent,
	})
end

return UI
