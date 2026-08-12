--[[
NavTab.lua - Navigation tab button for sidebar layouts
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local NavTabMixin = {}

function NavTabMixin:SetLabel(text)
	if self.Label then
		self.Label:SetText(text or "")
	end
end

function NavTabMixin:SetSelected(selected)
	self._selected = not not selected
	self:_RefreshVisual()
	if self.Label then
		local h = self:GetHeight() or 30
		local active = selected and (h <= 26 and "GameFontHighlightSmall" or "GameFontHighlight")
			or (h <= 26 and "GameFontNormalSmall" or "GameFontNormal")
		self.Label:SetFontObject(active)
	end
end

function NavTabMixin:IsSelected()
	return self._selected
end

function NavTabMixin:_RefreshVisual()
	local libRef = self._lib
	if not self.Background then
		return
	end
	if self._bgKind == "fallback" then
		local color = self._selected and Theme.COLORS.BUTTON_BG_ACTIVE or Theme.COLORS.NAV_BACKGROUND
		Theme.ApplyColorTexture(self.Background, color)
	else
		local asset = self._selected and libRef.Assets.NAV_TAB_ACTIVE or libRef.Assets.NAV_TAB
		libRef:SetSVG(self.Background, asset)
	end
end

--- @param parent Frame
--- @param opts table|nil { text, width, height, onClick, id, selected }
function lib:CreateNavTab(parent, opts)
	opts = opts or {}
	local width = opts.width or Theme.LAYOUT.NAV_TAB_WIDTH or (Theme.FRAME.NAV_PANEL_WIDTH - Theme.LAYOUT.PADDING * 2)
	local height = opts.height or Theme.LAYOUT.BUTTON_HEIGHT

	local button = CreateFrame("Button", opts.name, parent)
	button:SetSize(width, height)
	button._lib = self
	button._selected = not not opts.selected
	button.id = opts.id

	local bg, bgKind = self:CreateSVG(button, self.Assets.NAV_TAB, "BACKGROUND")
	if bg then
		bg:SetAllPoints()
		button.Background = bg
		button._bgKind = bgKind
	end

	local label = button:CreateFontString(nil, "OVERLAY", height <= 26 and "GameFontHighlightSmall" or "GameFontNormal")
	label:SetPoint("CENTER")
	label:SetText(opts.text or "")
	Theme.ApplyVertexColor(label, Theme.COLORS.TEXT)
	button.Label = label
	button.text = label

	if opts.onClick then
		button:SetScript("OnClick", opts.onClick)
	end

	for k, v in pairs(NavTabMixin) do
		button[k] = v
	end

	button:SetSelected(button._selected)
	return button
end
