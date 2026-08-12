--[[
Layout.lua - Tiny stack / relative placement helpers (not a full Ace container system)
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local StackMixin = {}

function StackMixin:GetGap()
	return self._gap or Theme.LAYOUT.PADDING or 8
end

function StackMixin:SetGap(gap)
	self._gap = gap or Theme.LAYOUT.PADDING or 8
end

function StackMixin:GetDirection()
	return self._direction or "vertical"
end

--- Add a child and place it after the previous entry.
--- @param child Frame
--- @param gap number|nil override spacing for this step
--- @return Frame child
function StackMixin:Add(child, gap)
	if not child then
		return
	end
	child:SetParent(self)
	local step = gap
	if step == nil then
		step = self:GetGap()
	end
	local prev = self._last
	child:ClearAllPoints()
	if not prev then
		local pad = self._padding or 0
		child:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -pad)
	elseif self._direction == "horizontal" then
		child:SetPoint("TOPLEFT", prev, "TOPRIGHT", step, 0)
	else
		child:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -step)
	end
	self._last = child
	self._children = self._children or {}
	self._children[#self._children + 1] = child
	return child
end

function StackMixin:GetLast()
	return self._last
end

function StackMixin:Clear()
	self._last = nil
	self._children = {}
end

--- Place `frame` directly below `relativeTo`.
--- @param frame Frame
--- @param relativeTo Region
--- @param gap number|nil
function lib:PlaceBelow(frame, relativeTo, gap)
	if not frame or not relativeTo then
		return
	end
	if gap == nil then
		gap = Theme.LAYOUT.PADDING or 8
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", 0, -gap)
end

--- Place `frame` to the right of `relativeTo`.
--- @param frame Frame
--- @param relativeTo Region
--- @param gap number|nil
function lib:PlaceRight(frame, relativeTo, gap)
	if not frame or not relativeTo then
		return
	end
	if gap == nil then
		gap = Theme.LAYOUT.PADDING or 8
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", relativeTo, "TOPRIGHT", gap, 0)
end

--- Lightweight sequential layout host. Call stack:Add(child) instead of manual SetPoint chains.
--- @param parent Frame
--- @param opts table|nil { direction="vertical"|"horizontal", gap, padding, width, height, name }
function lib:CreateStack(parent, opts)
	opts = opts or {}
	local frame = CreateFrame("Frame", opts.name, parent)
	if opts.width or opts.height then
		frame:SetSize(opts.width or 1, opts.height or 1)
	end
	frame._lib = self
	frame._direction = (opts.direction == "horizontal") and "horizontal" or "vertical"
	frame._gap = opts.gap
	if frame._gap == nil then
		frame._gap = Theme.LAYOUT.PADDING or 8
	end
	frame._padding = opts.padding or 0
	frame._last = nil
	frame._children = {}

	for k, v in pairs(StackMixin) do
		frame[k] = v
	end

	if self.RegisterThemeable then
		self:RegisterThemeable(frame)
	end
	return frame
end
