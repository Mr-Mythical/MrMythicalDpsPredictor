--[[
Progress.lua - Radial progress (SVG ring + Texture radial fill)
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local ProgressMixin = {}

function ProgressMixin:SetPercent(percent)
	percent = tonumber(percent) or 0
	if percent < 0 then
		percent = 0
	end
	if percent > 1 then
		percent = 1
	end
	self._percent = percent

	local fill = self.Fill
	if fill and type(fill.SetRadialProgressBarPercent) == "function" then
		fill:SetRadialProgressBarPercent(percent)
	end
	if self.Label then
		self.Label:SetText(("%d%%"):format(math.floor(percent * 100 + 0.5)))
	end
end

function ProgressMixin:GetPercent()
	return self._percent or 0
end

function ProgressMixin:SetReverse(reverse)
	self._reverse = not not reverse
	local fill = self.Fill
	if fill and type(fill.SetRadialProgressBarReverse) == "function" then
		fill:SetRadialProgressBarReverse(self._reverse)
	end
end

function ProgressMixin:SetFeather(feather)
	local fill = self.Fill
	if fill and type(fill.SetRadialProgressBarFeather) == "function" then
		fill:SetRadialProgressBarFeather(feather or 0)
	end
end

--- @param parent Frame
--- @param opts table|nil { size, percent, reverse, feather, showLabel }
function lib:CreateRadialProgress(parent, opts)
	opts = opts or {}
	local size = opts.size or 64

	local frame = CreateFrame("Frame", opts.name, parent)
	frame:SetSize(size, size)
	frame._lib = self
	frame._percent = opts.percent or 0
	frame._reverse = not not opts.reverse

	local track, trackKind = self:CreateSVG(frame, self.Assets.PROGRESS_RING, "BACKGROUND")
	if track then
		track:SetAllPoints()
		frame.Track = track
		if trackKind == "fallback" then
			Theme.ApplyColorTexture(track, Theme.COLORS.PROGRESS_TRACK)
		end
	end

	local fill = frame:CreateTexture(nil, "ARTWORK")
	fill:SetAllPoints()
	Theme.ApplyColorTexture(fill, Theme.COLORS.PROGRESS_FILL)
	frame.Fill = fill

	if type(fill.SetRadialProgressBarPercent) == "function" then
		fill:SetRadialProgressBarPercent(frame._percent)
		if opts.feather and type(fill.SetRadialProgressBarFeather) == "function" then
			fill:SetRadialProgressBarFeather(opts.feather)
		end
		if frame._reverse and type(fill.SetRadialProgressBarReverse) == "function" then
			fill:SetRadialProgressBarReverse(true)
		end
		if type(fill.SetRadialProgressBarStartOffset) == "function" then
			fill:SetRadialProgressBarStartOffset(opts.startOffset or 0)
		end
		if type(fill.SetRadialProgressBarEndOffset) == "function" then
			fill:SetRadialProgressBarEndOffset(opts.endOffset or 1)
		end
	else
		fill:SetAlpha(0.35)
	end

	if opts.showLabel ~= false then
		local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("CENTER")
		label:SetText(("%d%%"):format(math.floor(frame._percent * 100 + 0.5)))
		frame.Label = label
	end

	for k, v in pairs(ProgressMixin) do
		frame[k] = v
	end

	return frame
end
