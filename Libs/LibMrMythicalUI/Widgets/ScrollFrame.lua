--[[
ScrollFrame.lua - Custom scroll frame (no UIPanelScrollFrameTemplate)
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local ScrollMixin = {}

function ScrollMixin:SetScrollChild(child)
	self._scroll:SetScrollChild(child)
	self._child = child
	self:_UpdateScrollRange()
end

function ScrollMixin:GetScrollChild()
	return self._child
end

function ScrollMixin:_UpdateScrollRange()
	local child = self._child
	if not child then return end
	local viewH = self._scroll:GetHeight() or 0
	local childH = child:GetHeight() or 0
	local maxScroll = math.max(0, childH - viewH)
	self._maxScroll = maxScroll
	if self._scroll:GetVerticalScroll() > maxScroll then
		self._scroll:SetVerticalScroll(maxScroll)
	end
	self:_RefreshThumb()
end

-- Blizzard ScrollFrame API alias used after resizing scroll children
ScrollMixin.UpdateScrollChildRect = ScrollMixin._UpdateScrollRange

function ScrollMixin:_RefreshThumb()
	local track = self.Track
	local thumb = self.Thumb
	if not track or not thumb then return end
	local maxScroll = self._maxScroll or 0
	local trackH = track:GetHeight() or 1
	if maxScroll <= 0 then
		thumb:SetHeight(trackH)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", track, "TOP")
		thumb:Hide()
		return
	end
	thumb:Show()
	local viewH = self._scroll:GetHeight() or 1
	local childH = (self._child and self._child:GetHeight()) or viewH
	local thumbH = math.max(24, trackH * (viewH / childH))
	thumb:SetHeight(thumbH)
	local scroll = self._scroll:GetVerticalScroll() or 0
	local y = (scroll / maxScroll) * (trackH - thumbH)
	thumb:ClearAllPoints()
	thumb:SetPoint("TOP", track, "TOP", 0, -y)
end

function ScrollMixin:SetVerticalScroll(offset)
	self._scroll:SetVerticalScroll(offset or 0)
	self:_RefreshThumb()
end

--- @param parent Frame
--- @param opts table|nil { width, height, name }
function lib:CreateScrollFrame(parent, opts)
	opts = opts or {}
	local width = opts.width or 300
	local height = opts.height or 200
	local barW = 12

	local frame = CreateFrame("Frame", opts.name, parent)
	frame:SetSize(width, height)
	frame._lib = self
	frame._maxScroll = 0

	local scroll = CreateFrame("ScrollFrame", nil, frame)
	scroll:SetPoint("TOPLEFT")
	scroll:SetPoint("BOTTOMRIGHT", -barW - 2, 0)
	frame._scroll = scroll

	local track = CreateFrame("Frame", nil, frame)
	track:SetPoint("TOPRIGHT")
	track:SetPoint("BOTTOMRIGHT")
	track:SetWidth(barW)
	local trackBg = self:CreateColorTexture(track, Theme.COLORS.PROGRESS_TRACK, "BACKGROUND")
	trackBg:SetAllPoints()
	frame.Track = track

	local thumb = CreateFrame("Button", nil, track)
	thumb:SetWidth(barW - 2)
	thumb:SetHeight(40)
	local thumbTex = self:CreateColorTexture(thumb, Theme.COLORS.BUTTON_BORDER, "ARTWORK")
	thumbTex:SetAllPoints()
	frame.Thumb = thumb

	scroll:SetScript("OnScrollRangeChanged", function()
		frame:_UpdateScrollRange()
	end)
	scroll:SetScript("OnVerticalScroll", function()
		frame:_RefreshThumb()
	end)

	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		local step = 28
		local cur = scroll:GetVerticalScroll() or 0
		frame:SetVerticalScroll(math.max(0, math.min(frame._maxScroll or 0, cur - delta * step)))
	end)

	local dragging = false
	thumb:RegisterForDrag("LeftButton")
	thumb:SetScript("OnDragStart", function()
		dragging = true
		thumb:SetScript("OnUpdate", function()
			if not dragging then return end
			local top = track:GetTop()
			local trackH = track:GetHeight() or 1
			local thumbH = thumb:GetHeight() or 1
			if not top then return end
			local _, cursorY = GetCursorPosition()
			cursorY = cursorY / (UIParent:GetEffectiveScale() or 1)
			local frac = (top - cursorY) / math.max(1, trackH - thumbH)
			if frac < 0 then frac = 0 end
			if frac > 1 then frac = 1 end
			frame:SetVerticalScroll(frac * (frame._maxScroll or 0))
		end)
	end)
	thumb:SetScript("OnDragStop", function()
		dragging = false
		thumb:SetScript("OnUpdate", nil)
	end)

	for k, v in pairs(ScrollMixin) do
		frame[k] = v
	end

	return frame
end
