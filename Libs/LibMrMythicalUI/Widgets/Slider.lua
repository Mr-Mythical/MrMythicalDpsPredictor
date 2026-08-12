--[[
Slider.lua - Custom slider (no OptionsSliderTemplate)
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local SliderMixin = {}

function SliderMixin:SetMinMaxValues(minV, maxV)
	self._min = minV or 0
	self._max = maxV or 1
	if self._max <= self._min then
		self._max = self._min + 1
	end
	self:_RefreshThumb()
end

function SliderMixin:SetValueStep(step)
	self._step = step or 1
end

function SliderMixin:SetValue(value)
	value = tonumber(value) or self._min
	if value < self._min then value = self._min end
	if value > self._max then value = self._max end
	if self._step and self._step > 0 then
		value = math.floor((value - self._min) / self._step + 0.5) * self._step + self._min
		if value > self._max then value = self._max end
	end
	self._value = value
	self:_RefreshThumb()
	if self.ValueText then
		if self._format then
			self.ValueText:SetText(self._format(value))
		else
			self.ValueText:SetText(tostring(value))
		end
	end
	if self._onChanged then
		self._onChanged(self, value)
	end
end

function SliderMixin:GetValue()
	return self._value or self._min
end

function SliderMixin:SetLabel(text)
	if self.Label then
		self.Label:SetText(text or "")
	end
end

function SliderMixin:_Fraction()
	local span = self._max - self._min
	if span <= 0 then return 0 end
	return (self._value - self._min) / span
end

function SliderMixin:_RefreshThumb()
	if not self.Thumb then return end
	local trackW = self:GetWidth()
	local thumbW = self.Thumb:GetWidth()
	local x = self:_Fraction() * math.max(0, trackW - thumbW)
	self.Thumb:ClearAllPoints()
	self.Thumb:SetPoint("LEFT", self.Track, "LEFT", x, 0)
end

function SliderMixin:_ValueFromCursor()
	local left = self.Track:GetLeft()
	local width = self.Track:GetWidth()
	if not left or not width or width <= 0 then
		return self._value
	end
	local cursorX = GetCursorPosition()
	local scale = self.Track:GetEffectiveScale() or UIParent:GetEffectiveScale() or 1
	local x = cursorX / scale
	local frac = (x - left) / width
	if frac < 0 then frac = 0 end
	if frac > 1 then frac = 1 end
	return self._min + frac * (self._max - self._min)
end

--- @param parent Frame
--- @param opts table|nil { width, min, max, step, value, label, lowText, highText, format, onValueChanged }
function lib:CreateSlider(parent, opts)
	opts = opts or {}
	local width = opts.width or 200
	local height = 28

	local frame = CreateFrame("Frame", opts.name, parent)
	frame:SetSize(width, height + (opts.label and 18 or 0))
	frame._lib = self
	frame._min = opts.min or 0
	frame._max = opts.max or 100
	frame._step = opts.step or 1
	frame._value = opts.value or frame._min
	frame._format = opts.format
	frame._onChanged = opts.onValueChanged

	local y = 0
	if opts.label then
		local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("TOPLEFT")
		label:SetText(opts.label)
		Theme.ApplyVertexColor(label, Theme.COLORS.TEXT)
		frame.Label = label
		y = -16
	end

	local track = CreateFrame("Frame", nil, frame)
	track:SetPoint("TOPLEFT", 0, y)
	track:SetSize(width, 16)
	frame.Track = track

	local trackBg = self:CreateColorTexture(track, Theme.COLORS.PROGRESS_TRACK, "BACKGROUND")
	trackBg:SetPoint("LEFT", 0, 0)
	trackBg:SetSize(width, 6)

	local thumb = CreateFrame("Button", nil, track)
	thumb:SetSize(14, 14)
	local thumbTex = self:CreateColorTexture(thumb, Theme.COLORS.ACCENT, "ARTWORK")
	thumbTex:SetAllPoints()
	frame.Thumb = thumb

	local valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	valueText:SetPoint("LEFT", track, "RIGHT", 8, 0)
	Theme.ApplyVertexColor(valueText, Theme.COLORS.ACCENT)
	frame.ValueText = valueText

	if opts.lowText then
		local low = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		low:SetPoint("TOPLEFT", track, "BOTTOMLEFT", 0, -2)
		low:SetText(opts.lowText)
		frame.LowText = low
	end
	if opts.highText then
		local high = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		high:SetPoint("TOPRIGHT", track, "BOTTOMRIGHT", 0, -2)
		high:SetText(opts.highText)
		frame.HighText = high
	end

	local function beginDrag()
		frame._dragging = true
		frame:SetScript("OnUpdate", function()
			if frame._dragging then
				frame:SetValue(frame:_ValueFromCursor())
			end
		end)
	end
	local function endDrag()
		frame._dragging = false
		frame:SetScript("OnUpdate", nil)
	end

	thumb:EnableMouse(true)
	thumb:RegisterForDrag("LeftButton")
	thumb:SetScript("OnDragStart", beginDrag)
	thumb:SetScript("OnDragStop", endDrag)
	thumb:SetScript("OnMouseUp", endDrag)

	track:EnableMouse(true)
	track:SetScript("OnMouseDown", function()
		frame:SetValue(frame:_ValueFromCursor())
		beginDrag()
	end)
	track:SetScript("OnMouseUp", endDrag)
	frame:EnableMouse(true)
	frame:SetScript("OnMouseUp", endDrag)

	for k, v in pairs(SliderMixin) do
		frame[k] = v
	end

	frame:SetValue(frame._value)
	return frame
end
