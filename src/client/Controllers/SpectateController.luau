--[[
	SpectateController — for eliminated or extracted investigators.

	Follows a living teammate with an over-the-shoulder camera. Offers (never
	pushes) an optional re-entry when one is possible; otherwise the player can
	keep watching until extraction or return to the field office.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetisation = require(Shared.Config.Monetisation)

local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)

local SpectateController = {}

local gui, panel, statusText, watchingText, reviveButton, reviveInfo, modal
local targetIndex = 1
local active = false
local renderConn = nil
local smoothed = nil

local function aliveTargets()
	local list = {}
	local m = State.mission
	if not m then
		return list
	end
	for _, player in Players:GetPlayers() do
		local p = m.participants[tostring(player.UserId)]
		if p and p.status == "Alive" and player.Character and player.Character:FindFirstChild("Head") then
			table.insert(list, player)
		end
	end
	return list
end

local function cycle(delta)
	local list = aliveTargets()
	if #list == 0 then
		return
	end
	targetIndex = ((targetIndex - 1 + delta) % #list) + 1
end

local function reviveAvailable()
	local m = State.mission
	local me = State.me()
	if not m or not me or me.status ~= "Eliminated" then
		return false, nil
	end
	if m.teamTokenUsed then
		return false, "A team recovery was used. No more re-entries this case."
	end
	if (me.revivesUsed or 0) >= 1 then
		return false, "You have already re-entered once this case."
	end
	local stored = State.profile and State.profile.storedRevives or 0
	if stored > 0 then
		return true, string.format("You have %d stored re-entr%s.", stored, stored == 1 and "y" or "ies")
	end
	if Monetisation.Products.Revive.id ~= 0 then
		return true, Monetisation.Products.Revive.description
	end
	return false, "Keep watching — your team can still finish the case."
end

local function refresh()
	local me = State.me()
	local shouldShow = State.mission ~= nil and me ~= nil and (me.status == "Eliminated" or me.status == "Extracted") and State.mission.phase ~= "Completed" and State.mission.phase ~= "Failed"
	if shouldShow ~= active then
		active = shouldShow
		gui.Enabled = shouldShow
		if shouldShow then
			smoothed = nil
			renderConn = RunService.RenderStepped:Connect(function(dt)
				local list = aliveTargets()
				local camera = Workspace.CurrentCamera
				camera.CameraType = Enum.CameraType.Scriptable
				local target = list[math.clamp(targetIndex, 1, math.max(1, #list))]
				if target and target.Character then
					local head = target.Character:FindFirstChild("Head")
					local root = target.Character:FindFirstChild("HumanoidRootPart")
					if head and root then
						local desired = CFrame.lookAt(head.Position - root.CFrame.LookVector * 8 + Vector3.new(0, 2.5, 0), head.Position + root.CFrame.LookVector * 6)
						smoothed = smoothed and smoothed:Lerp(desired, math.min(1, dt * 6)) or desired
						camera.CFrame = smoothed
					end
					watchingText.Text = "WATCHING: " .. target.DisplayName .. "   [Q / E or the arrows to switch]"
				else
					watchingText.Text = "NO LIVE FEEDS"
				end
			end)
		else
			if renderConn then
				renderConn:Disconnect()
				renderConn = nil
			end
			local camera = Workspace.CurrentCamera
			camera.CameraType = Enum.CameraType.Custom
		end
	end
	if not active then
		return
	end
	if me.status == "Extracted" then
		statusText.Text = "EXTRACTED · WAITING FOR THE TEAM"
	else
		statusText.Text = "SIGNAL LOST · YOU ARE OFF-AIR"
		local m = State.mission
		if m.failPendingUntil then
			statusText.Text ..= string.format(" · CASE ENDS IN %ds", math.max(0, math.ceil(m.failPendingUntil - State.now())))
		end
	end
	local canRevive, info = reviveAvailable()
	reviveButton.Visible = canRevive
	reviveInfo.Text = info or ""
end

function SpectateController.init(playerGui)
	gui = UI.screen("DeadAirSpectate", 15, playerGui)
	gui.Enabled = false
	panel = UI.panel(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20), Size = UDim2.fromOffset(560, 210) })
	UI.padding(panel, 12)
	UI.list(panel, 6)
	modal = UI.modalUnlock(panel)
	statusText = UI.text(panel, "", { FontFace = Theme.FontBold, TextColor3 = Theme.Cream, LayoutOrder = 1 })
	watchingText = UI.text(panel, "", { TextColor3 = Theme.TextDim, TextSize = Theme.SmallText, LayoutOrder = 2 })
	local row = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 3, Parent = panel })
	UI.list(row, 6, Enum.FillDirection.Horizontal)
	UI.button(row, "< PREV", function()
		cycle(-1)
	end, { Size = UDim2.new(0.24, 0, 1, 0) })
	UI.button(row, "NEXT >", function()
		cycle(1)
	end, { Size = UDim2.new(0.24, 0, 1, 0) })
	UI.button(row, "TAPES", function()
		local DeckController = require(script.Parent.DeckController)
		DeckController.open({ mode = "spectate" })
	end, { Size = UDim2.new(0.24, 0, 1, 0) })
	UI.button(row, "LEAVE CASE", function()
		State.action("LeaveCase")
	end, { Size = UDim2.new(0.24, 0, 1, 0), TextColor3 = Theme.TextDim })
	reviveButton = UI.button(panel, "EMERGENCY RE-ENTRY (OPTIONAL)", function()
		local result = State.request("Revive", {})
		if result.message then
			State.notify:Fire(result.message)
		end
	end, { LayoutOrder = 4, TextColor3 = Theme.Accent })
	reviveInfo = UI.text(panel, "", { TextColor3 = Theme.TextDim, TextSize = Theme.SmallText, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5 })
	UI.text(panel, "A teammate still inside can call a team recovery from their pause menu.", { TextColor3 = Theme.TextDim, TextSize = Theme.SmallText, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 6 })

	State.missionChanged:Connect(refresh)
	State.profileChanged:Connect(refresh)
	game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
		if processed or not active then
			return
		end
		if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.DPadLeft then
			cycle(-1)
		elseif input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.DPadRight then
			cycle(1)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			refresh()
		end
	end)
	SpectateController.modal = modal
end

return SpectateController
