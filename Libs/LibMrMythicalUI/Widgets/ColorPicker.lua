--[[
ColorPicker.lua - Theme-styled color swatch that opens ColorPickerFrame
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local ColorMixin = {}

function ColorMixin:GetColor()
	return self._r, self._g, self._b, self._a
end

function ColorMixin:SetColor(r, g, b, a, silent)
	self._r = r or 1
	self._g = g or 1
	self._b = b or 1
	if a ~= nil then
		self._a = a
	elseif self._a == nil then
		self._a = 1
	end
	self:_RefreshSwatch()
	if not silent and self._onChanged then
		self._onChanged(self, self._r, self._g, self._b, self._a)
	end
end

function ColorMixin:SetHasAlpha(hasAlpha)
	self._hasAlpha = not not hasAlpha
end

function ColorMixin:SetLabel(text)
	if self.Label then
		self.Label:SetText(text or "")
	end
end

function ColorMixin:_RefreshSwatch()
	if self.Swatch then
		self.Swatch:SetColorTexture(self._r or 1, self._g or 1, self._b or 1, self._a or 1)
	end
end

function ColorMixin:_RefreshTheme()
	if self.Border then
		Theme.ApplyColorTexture(self.Border, Theme.COLORS.BUTTON_BORDER)
	end
	if self.Label then
		Theme.ApplyVertexColor(self.Label, Theme.COLORS.TEXT)
	end
	self:_RefreshSwatch()
end

function ColorMixin:OpenPicker()
	local selfRef = self
	local r0, g0, b0, a0 = self._r, self._g, self._b, self._a or 1

	local function applyFromPicker()
		local r, g, b = ColorPickerFrame:GetColorRGB()
		local a = a0
		if selfRef._hasAlpha and ColorPickerFrame.GetColorAlpha then
			a = ColorPickerFrame:GetColorAlpha()
		end
		selfRef:SetColor(r, g, b, a)
	end

	local function onCancel()
		if ColorPickerFrame.GetPreviousValues then
			local pr, pg, pb, pa = ColorPickerFrame:GetPreviousValues()
			if pr then
				selfRef:SetColor(pr, pg, pb, pa or a0, true)
				if selfRef._onChanged then
					selfRef._onChanged(selfRef, pr, pg, pb, pa or a0)
				end
				return
			end
		end
		selfRef:SetColor(r0, g0, b0, a0)
	end

	if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r0,
			g = g0,
			b = b0,
			opacity = a0,
			hasOpacity = selfRef._hasAlpha,
			swatchFunc = applyFromPicker,
			opacityFunc = selfRef._hasAlpha and applyFromPicker or nil,
			cancelFunc = onCancel,
		})
		return
	end

	-- Fallback for older ColorPickerFrame shapes
	if not ColorPickerFrame then
		return
	end
	ColorPickerFrame.func = applyFromPicker
	ColorPickerFrame.opacityFunc = selfRef._hasAlpha and applyFromPicker or nil
	ColorPickerFrame.cancelFunc = onCancel
	ColorPickerFrame.hasOpacity = selfRef._hasAlpha
	if selfRef._hasAlpha then
		ColorPickerFrame.opacity = a0
	end
	ColorPickerFrame:SetColorRGB(r0, g0, b0)
	ColorPickerFrame:Show()
end

--- @param parent Frame
--- @param opts table|nil {
---   r, g, b, a, hasAlpha, label, width, height, swatchSize, onChanged, name
--- }
function lib:CreateColorPicker(parent, opts)
	opts = opts or {}
	local height = opts.height or Theme.LAYOUT.BUTTON_HEIGHT or 30
	local swatchSize = opts.swatchSize or (height - 6)
	local width = opts.width or (swatchSize + 8 + (opts.label and 120 or 0))

	local frame = CreateFrame("Button", opts.name, parent)
	frame:SetSize(width, height)
	frame._lib = self
	frame._r = opts.r or 1
	frame._g = opts.g or 1
	frame._b = opts.b or 1
	frame._a = opts.a
	if frame._a == nil then
		frame._a = 1
	end
	frame._hasAlpha = opts.hasAlpha
	if frame._hasAlpha == nil then
		frame._hasAlpha = true
	end
	frame._onChanged = opts.onChanged

	local border = self:CreateColorTexture(frame, Theme.COLORS.BUTTON_BORDER, "BACKGROUND")
	border:SetSize(swatchSize, swatchSize)
	border:SetPoint("LEFT", 2, 0)
	frame.Border = border

	local swatch = frame:CreateTexture(nil, "ARTWORK")
	swatch:SetPoint("TOPLEFT", border, "TOPLEFT", 1, -1)
	swatch:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -1, 1)
	frame.Swatch = swatch

	if opts.label then
		local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("LEFT", border, "RIGHT", 8, 0)
		label:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
		label:SetJustifyH("LEFT")
		label:SetText(opts.label)
		Theme.ApplyVertexColor(label, Theme.COLORS.TEXT)
		frame.Label = label
	end

	frame:SetScript("OnClick", function(self)
		self:OpenPicker()
	end)

	for k, v in pairs(ColorMixin) do
		frame[k] = v
	end

	frame:_RefreshSwatch()

	if self.RegisterThemeable then
		self:RegisterThemeable(frame)
	end

	return frame
end
