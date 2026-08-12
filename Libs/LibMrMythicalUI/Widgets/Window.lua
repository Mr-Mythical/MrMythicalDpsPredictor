--[[
Window.lua - Movable frame persistence (LibWindow-inspired)
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)

local function nearestCornerPosition(frame)
	local left = frame:GetLeft()
	local right = frame:GetRight()
	local top = frame:GetTop()
	local bottom = frame:GetBottom()
	if not left or not right or not top or not bottom then
		local point, _, relativePoint, x, y = frame:GetPoint(1)
		if point then
			return {
				point = point,
				relativePoint = relativePoint or point,
				x = x or 0,
				y = y or 0,
			}
		end
		return nil
	end

	local parent = frame:GetParent() or UIParent
	local width = parent:GetWidth() or UIParent:GetWidth() or 0
	local height = parent:GetHeight() or UIParent:GetHeight() or 0
	if width <= 0 or height <= 0 then
		return nil
	end

	local xCenter = (left + right) / 2
	local yCenter = (top + bottom) / 2
	local point, x, y
	if yCenter >= height / 2 then
		y = top - height
		if xCenter >= width / 2 then
			point = "TOPRIGHT"
			x = right - width
		else
			point = "TOPLEFT"
			x = left
		end
	else
		y = bottom
		if xCenter >= width / 2 then
			point = "BOTTOMRIGHT"
			x = right - width
		else
			point = "BOTTOMLEFT"
			x = left
		end
	end

	return {
		point = point,
		relativePoint = point,
		x = x,
		y = y,
	}
end

local MovableMixin = {}

function MovableMixin:SaveLibPosition()
	local opts = self._libMovableOpts
	if not opts or not opts.set then
		return
	end
	local pos = nearestCornerPosition(self)
	if pos then
		opts.set(pos)
	end
end

function MovableMixin:RestoreLibPosition()
	local opts = self._libMovableOpts
	if not opts or not opts.get then
		return false
	end
	local pos = opts.get()
	if not pos or not pos.point then
		return false
	end
	self:ClearAllPoints()
	self:SetPoint(
		pos.point,
		UIParent,
		pos.relativePoint or pos.point,
		pos.x or 0,
		pos.y or 0
	)
	return true
end

function MovableMixin:SetLibMovingEnabled(enabled)
	local opts = self._libMovableOpts
	if not opts then
		return
	end
	opts._enabled = not not enabled
	if enabled then
		self:SetMovable(true)
		self:EnableMouse(true)
		self:RegisterForDrag(opts.dragButton or "LeftButton")
	else
		self:StopMovingOrSizing()
		self:RegisterForDrag()
		if opts.disableMouseWhenLocked then
			self:EnableMouse(false)
		end
		self:SetMovable(false)
	end
end

function MovableMixin:IsLibMovingEnabled()
	local opts = self._libMovableOpts
	return opts and opts._enabled == true
end

--- Persist drag position with quadrant-aware save (nearest screen corner).
--- @param frame Frame
--- @param opts table|nil {
---   get = function() -> {point, relativePoint, x, y}|nil,
---   set = function(pos),
---   clamped = boolean (default true),
---   dragButton = string (default "LeftButton"),
---   enabled = boolean (default true) — start with drag on,
---   disableMouseWhenLocked = boolean (default false),
--- }
function lib:RegisterMovable(frame, opts)
	if not frame then
		return frame
	end
	opts = opts or {}
	opts.dragButton = opts.dragButton or "LeftButton"
	opts._enabled = opts.enabled ~= false

	frame._libMovableOpts = opts
	for k, v in pairs(MovableMixin) do
		frame[k] = v
	end

	frame:SetClampedToScreen(opts.clamped ~= false)
	frame:RestoreLibPosition()

	frame:SetScript("OnDragStart", function(self)
		if self._libMovableOpts and self._libMovableOpts._enabled then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SaveLibPosition()
	end)

	frame:SetLibMovingEnabled(opts._enabled)
	return frame
end
