--[[
Tooltip.lua - GameTooltip helpers
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

--- @param frame Frame
--- @param text string
--- @param anchor string|nil
function lib:AttachTooltip(frame, text, anchor)
	if not frame or not text or text == "" then
		return frame
	end
	frame._mmTooltipText = text
	frame._mmTooltipAnchor = anchor or "ANCHOR_RIGHT"

	local target = frame.EditBox or frame
	if target ~= frame.EditBox then
		target:EnableMouse(true)
	end

	local function onEnter()
		local body = frame._mmTooltipText
		if not body then
			return
		end
		GameTooltip:SetOwner(frame, frame._mmTooltipAnchor or "ANCHOR_RIGHT")
		GameTooltip:SetText(body, nil, nil, nil, nil, true)
		GameTooltip:Show()
	end
	local function onLeave()
		GameTooltip:Hide()
	end

	if target:GetScript("OnEnter") then
		target:HookScript("OnEnter", onEnter)
	else
		target:SetScript("OnEnter", onEnter)
	end
	if target:GetScript("OnLeave") then
		target:HookScript("OnLeave", onLeave)
	else
		target:SetScript("OnLeave", onLeave)
	end
	return frame
end

local TipMixin = {}

function TipMixin:SetText(text)
	self._tipText = text or ""
	self._mmTooltipText = self._tipText
end

--- @param parent Frame
--- @param opts table|nil { text, size, name }
function lib:CreateTip(parent, opts)
	opts = opts or {}
	local size = opts.size or 18

	local button = CreateFrame("Button", opts.name, parent)
	button:SetSize(size, size)
	button._lib = self
	button._tipText = opts.text or "Tip"

	local bg = self:CreateColorTexture(button, Theme.COLORS.BUTTON_BG, "BACKGROUND")
	bg:SetAllPoints()

	local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("CENTER")
	label:SetText("?")
	Theme.ApplyVertexColor(label, Theme.COLORS.ACCENT)
	button.Label = label

	for k, v in pairs(TipMixin) do
		button[k] = v
	end

	self:AttachTooltip(button, button._tipText)
	return button
end
