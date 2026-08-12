--[[
ListRow.lua - Selectable list / table row
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local RowMixin = {}

function RowMixin:SetText(text)
	if self.Label then
		self.Label:SetText(text or "")
	end
end

function RowMixin:SetSecondary(text)
	if self.Secondary then
		self.Secondary:SetText(text or "")
		self.Secondary:SetShown(text and text ~= "")
	end
end

function RowMixin:SetSelected(selected)
	self._selected = not not selected
	self:_Refresh()
end

function RowMixin:GetSelected()
	return self._selected
end

function RowMixin:_Refresh()
	local bg = self.Background
	if not bg then
		return
	end
	if self._selected then
		Theme.ApplyColorTexture(bg, Theme.COLORS.BUTTON_BG_ACTIVE)
	elseif self._even then
		Theme.ApplyColorTexture(bg, Theme.COLORS.EVEN_ROW)
	else
		Theme.ApplyColorTexture(bg, Theme.COLORS.ODD_ROW)
	end
end

--- @param parent Frame
--- @param opts table|nil { text, secondary, width, height, selected, even, onClick, name }
function lib:CreateListRow(parent, opts)
	opts = opts or {}
	local width = opts.width or 280
	local height = opts.height or Theme.LAYOUT.ROW_HEIGHT or 25

	local button = CreateFrame("Button", opts.name, parent)
	button:SetSize(width, height)
	button._lib = self
	button._selected = not not opts.selected
	button._even = opts.even ~= false

	local bg = self:CreateColorTexture(button, Theme.COLORS.EVEN_ROW, "BACKGROUND")
	bg:SetAllPoints()
	button.Background = bg

	local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("LEFT", 8, 0)
	label:SetPoint("RIGHT", -8, 0)
	label:SetJustifyH("LEFT")
	label:SetText(opts.text or "")
	Theme.ApplyVertexColor(label, Theme.COLORS.TEXT)
	button.Label = label

	if opts.secondary then
		label:ClearAllPoints()
		label:SetPoint("LEFT", 8, 4)
		label:SetPoint("RIGHT", -8, 4)
		local secondary = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		secondary:SetPoint("LEFT", 8, -6)
		secondary:SetPoint("RIGHT", -8, -6)
		secondary:SetJustifyH("LEFT")
		secondary:SetText(opts.secondary)
		button.Secondary = secondary
		button:SetHeight(math.max(height, 36))
	end

	button:SetScript("OnClick", function(self)
		if opts.onClick then
			opts.onClick(self)
		end
	end)
	button:SetScript("OnEnter", function(self)
		if not self._selected then
			Theme.ApplyColorTexture(self.Background, Theme.COLORS.BUTTON_BG_HOVER)
		end
	end)
	button:SetScript("OnLeave", function(self)
		self:_Refresh()
	end)

	for k, v in pairs(RowMixin) do
		button[k] = v
	end
	button:_Refresh()
	return button
end
