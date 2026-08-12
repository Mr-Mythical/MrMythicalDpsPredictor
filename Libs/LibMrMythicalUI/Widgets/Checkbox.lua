--[[
Checkbox.lua - Simple check button with SVG/text chrome
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local CheckboxMixin = {}

function CheckboxMixin:SetLabel(text)
	if self.Label then
		self.Label:SetText(text or "")
	end
end

function CheckboxMixin:SetEnabled(enabled)
	if enabled then
		self:Enable()
	else
		self:Disable()
	end
end

function CheckboxMixin:SetChecked(checked)
	self._checked = not not checked
	self:_Refresh()
end

function CheckboxMixin:GetChecked()
	return self._checked
end

function CheckboxMixin:_Refresh()
	if self.BoxFill then
		if self._checked then
			Theme.ApplyColorTexture(self.BoxFill, Theme.COLORS.ACCENT)
			self.BoxFill:SetAlpha(1)
		else
			Theme.ApplyColorTexture(self.BoxFill, Theme.COLORS.BUTTON_BG)
			self.BoxFill:SetAlpha(1)
		end
	end
end

--- @param parent Frame
--- @param opts table|nil { text, checked, onClick, width, height }
function lib:CreateCheckbox(parent, opts)
	opts = opts or {}
	local height = opts.height or Theme.LAYOUT.BUTTON_HEIGHT or 30
	local button = CreateFrame("Button", opts.name, parent)
	button:SetSize(opts.width or 180, height)
	button._lib = self
	button._checked = not not opts.checked

	local boxSize = height <= 22 and 14 or 16
	local fillSize = height <= 22 and 10 or 12
	local box = button:CreateTexture(nil, "ARTWORK")
	box:SetSize(boxSize, boxSize)
	box:SetPoint("LEFT", 2, 0)
	Theme.ApplyColorTexture(box, Theme.COLORS.BUTTON_BORDER)
	button.BoxBorder = box

	local fill = button:CreateTexture(nil, "OVERLAY")
	fill:SetSize(fillSize, fillSize)
	fill:SetPoint("CENTER", box, "CENTER")
	button.BoxFill = fill

	local label = button:CreateFontString(
		nil,
		"OVERLAY",
		height <= 22 and "GameFontHighlightSmall" or "GameFontNormal"
	)
	label:SetPoint("LEFT", box, "RIGHT", 6, 0)
	label:SetPoint("RIGHT", button, "RIGHT", -2, 0)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(false)
	label:SetText(opts.text or "")
	Theme.ApplyVertexColor(label, Theme.COLORS.TEXT)
	button.Label = label

	button:SetScript("OnClick", function(self)
		self._checked = not self._checked
		self:_Refresh()
		if opts.onClick then
			opts.onClick(self, self._checked)
		end
	end)

	for k, v in pairs(CheckboxMixin) do
		button[k] = v
	end
	button:_Refresh()
	return button
end
