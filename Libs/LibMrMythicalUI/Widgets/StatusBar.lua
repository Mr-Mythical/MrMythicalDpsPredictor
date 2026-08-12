--[[
StatusBar.lua - Linear progress / status bar
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local StatusMixin = {}

function StatusMixin:SetPercent(percent)
	percent = tonumber(percent) or 0
	if percent < 0 then
		percent = 0
	end
	if percent > 1 then
		percent = 1
	end
	self._percent = percent
	local fill = self.Fill
	if fill then
		local w = math.max(0, (self:GetWidth() or 0) - 2) * percent
		fill:SetWidth(math.max(1, w))
		fill:SetShown(percent > 0)
	end
	if self.Label then
		self.Label:SetText(("%d%%"):format(math.floor(percent * 100 + 0.5)))
	end
end

function StatusMixin:GetPercent()
	return self._percent or 0
end

function StatusMixin:SetMinMaxValues(minV, maxV)
	self._min = minV or 0
	self._max = maxV or 1
end

function StatusMixin:SetValue(value)
	local minV = self._min or 0
	local maxV = self._max or 1
	local range = maxV - minV
	if range <= 0 then
		self:SetPercent(0)
	else
		self:SetPercent(((value or 0) - minV) / range)
	end
end

function StatusMixin:GetValue()
	local minV = self._min or 0
	local maxV = self._max or 1
	local range = maxV - minV
	return minV + (self._percent or 0) * range
end

function StatusMixin:SetLabel(text)
	if self.Label then
		self.Label:SetText(text or "")
	end
end

--- @param parent Frame
--- @param opts table|nil { width, height, percent, showLabel, name }
function lib:CreateStatusBar(parent, opts)
	opts = opts or {}
	local width = opts.width or 200
	local height = opts.height or 16

	local frame = CreateFrame("Frame", opts.name, parent)
	frame:SetSize(width, height)
	frame._lib = self
	frame._percent = opts.percent or 0
	frame._min = 0
	frame._max = 1

	local track = self:CreateColorTexture(frame, Theme.COLORS.PROGRESS_TRACK, "BACKGROUND")
	track:SetAllPoints()
	frame.Track = track

	local fill = self:CreateColorTexture(frame, Theme.COLORS.PROGRESS_FILL, "ARTWORK")
	fill:SetPoint("TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMLEFT", 1, 1)
	fill:SetWidth(math.max(1, (width - 2) * frame._percent))
	frame.Fill = fill

	if opts.showLabel ~= false then
		local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("CENTER")
		label:SetText(("%d%%"):format(math.floor(frame._percent * 100 + 0.5)))
		Theme.ApplyVertexColor(label, Theme.COLORS.TEXT)
		frame.Label = label
	end

	for k, v in pairs(StatusMixin) do
		frame[k] = v
	end

	frame:SetScript("OnSizeChanged", function(self)
		self:SetPercent(self._percent)
	end)

	frame:SetPercent(frame._percent)
	return frame
end
