--[[
	ReportController — the case report: result, components, tapes, predictions
	interpreted, edits, team survival, grade D-S, rewards and new unlocks.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CaseRegistry = require(Shared.Config.CaseRegistry)
local Evidence = require(Shared.Config.Evidence)
local Format = require(Shared.Util.Format)

local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)

local ReportController = {}

local gui, body

local RESULT_TEXT = {
	Success = "SUCCESSFUL EXTRACTION",
	Partial = "PARTIAL EXTRACTION",
	Failed = "FAILED CASE",
}

local function line(text, colour, order, size)
	return UI.text(body, text, {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = colour or Theme.Text,
		TextSize = size or Theme.TextSize,
		LayoutOrder = order,
	})
end

local function show(payload)
	local report, personal = payload.report, payload.personal
	UI.clear(body)
	local caseDef = CaseRegistry.get(report.caseId)
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end
	line("NATIONAL BROADCAST RECOVERY DIVISION · CASE REPORT", Theme.TextDim, nextOrder(), Theme.SmallText)
	line(string.format("CASE %02d · %s · %s", caseDef and caseDef.number or 0, report.title, report.modeLabel or report.mode), Theme.Cream, nextOrder())
	line(RESULT_TEXT[report.result] or report.result, report.result == "Failed" and Theme.Danger or Theme.Accent, nextOrder(), 28)
	if report.reason then
		line(report.reason, Theme.TextDim, nextOrder())
	end
	line(string.format("GRADE %s  ·  SCORE %d / 100  ·  BROADCAST TIME %s", report.grade, report.score, Format.clock(report.duration or 0)), Theme.Cream, nextOrder(), 22)

	local comps = {}
	for _, id in caseDef.components do
		table.insert(comps, string.format("%s %s", report.components[id] and "[X]" or "[ ]", caseDef.items[id].label))
	end
	line("COMPONENTS: " .. table.concat(comps, "   ") .. (report.componentsInstalled and "   · INSTALLED" or ""), Theme.Text, nextOrder())
	line(string.format("CASE TAPES RECOVERED: %d / %d   ·   EVIDENCE: %d / %d%s", report.tapesFound, report.tapesTotal, report.evidenceFound, report.evidenceTotal, report.bonusTape and "   · TAPE 07 EXTRACTED" or ""), Theme.Text, nextOrder())
	line(string.format("PREDICTIONS INTERPRETED: %d / %d", report.predictionsInterpreted, report.predictionsTotal), Theme.Text, nextOrder())
	line(string.format("EDITS MADE: %d / %d", report.editsMade, report.maxCharges), Theme.Text, nextOrder())
	for _, edit in report.edits or {} do
		line(string.format("    %s: %s -> %s (%s)", edit.label, edit.from, edit.to, edit.by), Theme.TextDim, nextOrder(), Theme.SmallText)
	end
	local anomalies = {}
	table.insert(anomalies, report.loopSolved and (report.loopFirstTry and "LOOP BROKEN FIRST TRY" or "LOOP BROKEN") or "LOOP UNSOLVED")
	table.insert(anomalies, report.callerFooled and "CALLER'S CODE USED" or "CALLER IGNORED")
	line("ANOMALIES: " .. table.concat(anomalies, " · "), Theme.Text, nextOrder())

	line("TEAM", Theme.Accent, nextOrder())
	for _, p in report.participants or {} do
		local status = ({ Extracted = "EXTRACTED", Eliminated = "OFF-AIR", Disconnected = "LEFT", Alive = "LEFT BEHIND" })[p.status] or p.status
		line(string.format("    %s · %s · items %d · evidence %d · frames %d", p.name, status, p.items, p.evidence, p.frames), Theme.Text, nextOrder(), Theme.SmallText)
	end

	if personal then
		line("REWARDS", Theme.Accent, nextOrder())
		line(string.format("    +%d RECOVERY CREDITS · +%d RESEARCH", personal.credits or 0, personal.research or 0), Theme.Cream, nextOrder())
		if personal.clearance then
			line(string.format("    CLEARANCE RAISED TO %d — Restricted mode and the Archive Challenge are open.", personal.clearance), Theme.Cream, nextOrder())
		end
		if personal.master then
			local master = Evidence.master(personal.master)
			line("    NEW MASTER RECORDING: " .. (master and master.title or personal.master), Theme.Cream, nextOrder())
		end
		for _, id in personal.evidence or {} do
			local tape = Evidence.Tapes[id]
			line("    NEW EVIDENCE: " .. (tape and tape.title or id), Theme.Text, nextOrder(), Theme.SmallText)
		end
		for _, id in personal.challenges or {} do
			for _, ch in caseDef.challenges do
				if ch.id == id then
					line("    CHALLENGE COMPLETE: " .. ch.label, Theme.Text, nextOrder(), Theme.SmallText)
				end
			end
		end
	end
	line("Returning to the field office shortly.", Theme.TextDim, nextOrder(), Theme.SmallText)
	local button = UI.button(body, "RETURN TO THE FIELD OFFICE", function()
		State.action("ReturnToHQ")
		ReportController.close()
	end, { LayoutOrder = nextOrder(), Size = UDim2.new(0.5, 0, 0, 48), TextColor3 = Theme.Accent })

	gui.Enabled = true
	State.setUI("report", true)
	if #UserInputService:GetConnectedGamepads() > 0 then
		GuiService.SelectedObject = button
	end
end

function ReportController.close()
	gui.Enabled = false
	State.setUI("report", false)
	GuiService.SelectedObject = nil
end

function ReportController.init(playerGui)
	gui = UI.screen("DeadAirReport", 30, playerGui)
	gui.Enabled = false
	local root = UI.new("Frame", { BackgroundColor3 = Theme.Background, BackgroundTransparency = 0.05, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = gui })
	UI.modalUnlock(root)
	local panel = UI.panel(root, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.72, 0.86) })
	UI.padding(panel, 20)
	body = UI.scroll(panel, { Size = UDim2.fromScale(1, 1) })
	UI.list(body, 6)
	State.reportReceived:Connect(show)
	State.missionChanged:Connect(function(m)
		if not m and gui.Enabled then
			ReportController.close()
		end
	end)
end

return ReportController
