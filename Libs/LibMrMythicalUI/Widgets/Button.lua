--[[
Button.lua - SVG-backed push button
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local ButtonMixin = {}

function ButtonMixin:SetLabel(text)
	if self.Label then
		self.Label:SetText(text or "")
	end
end

function ButtonMixin:GetLabel()
	return self.Label and self.Label:GetText() or ""
end

-- Blizzard-ish aliases used by product call sites
ButtonMixin.SetText = ButtonMixin.SetLabel
ButtonMixin.GetText = ButtonMixin.GetLabel

function ButtonMixin:SetVariant(variant)
	self._variant = variant or "normal"
	self:_RefreshVisual()
end

function ButtonMixin:SetEnabledState(enabled)
	if enabled then
		self:Enable()
	else
		self:Disable()
	end
	self:_RefreshVisual()
end

function ButtonMixin:_AssetForState()
	local libRef = self._lib
	if self._variant == "active" or self._active then
		return libRef.Assets.BUTTON_ACTIVE
	end
	if self._hovered and self:IsEnabled() then
		return libRef.Assets.BUTTON_HOVER
	end
	return libRef.Assets.BUTTON_NORMAL
end

function ButtonMixin:_FallbackColor()
	if not self:IsEnabled() then
		return Theme.COLORS.DISABLED
	end
	if self._variant == "active" or self._active then
		return Theme.COLORS.BUTTON_BG_ACTIVE
	end
	if self._hovered then
		return Theme.COLORS.BUTTON_BG_HOVER
	end
	return Theme.COLORS.BUTTON_BG
end

function ButtonMixin:_RefreshVisual()
	local libRef = self._lib
	if self.Background then
		if self._bgKind == "fallback" then
			Theme.ApplyColorTexture(self.Background, self:_FallbackColor())
		else
			libRef:SetSVG(self.Background, self:_AssetForState())
		end
	end
	if self.Label then
		local color = self:IsEnabled() and Theme.COLORS.TEXT or Theme.COLORS.DISABLED
		Theme.ApplyVertexColor(self.Label, color)
	end
end

function ButtonMixin:SetActive(active)
	self._active = not not active
	self:_RefreshVisual()
end

--- @param parent Frame
--- @param opts table|nil { text, width, height, onClick, variant, name }
function lib:CreateButton(parent, opts)
	opts = opts or {}
	local width = opts.width or Theme.LAYOUT.BUTTON_WIDTH or 120
	local height = opts.height or Theme.LAYOUT.BUTTON_HEIGHT

	local button = CreateFrame("Button", opts.name, parent)
	button:SetSize(width, height)
	button._lib = self
	button._variant = opts.variant or "normal"
	button._active = false
	button._hovered = false

	local bg, bgKind = self:CreateSVG(button, self.Assets.BUTTON_NORMAL, "BACKGROUND")
	if bg then
		bg:SetAllPoints()
		button.Background = bg
		button._bgKind = bgKind
		if bgKind == "fallback" then
			Theme.ApplyColorTexture(bg, Theme.COLORS.BUTTON_BG)
		end
	end

	local label = button:CreateFontString(nil, "OVERLAY", height <= 26 and "GameFontHighlightSmall" or "GameFontNormal")
	label:SetPoint("CENTER")
	label:SetText(opts.text or "")
	Theme.ApplyVertexColor(label, Theme.COLORS.TEXT)
	button.Label = label

	if opts.icon then
		local icon = self:CreateIcon(button, opts.icon, Theme.LAYOUT.ICON_SIZE - 4)
		icon:SetPoint("LEFT", 6, 0)
		label:ClearAllPoints()
		label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
		label:SetPoint("RIGHT", -6, 0)
		button.Icon = icon
	end

	button:SetScript("OnEnter", function(self)
		self._hovered = true
		self:_RefreshVisual()
	end)
	button:SetScript("OnLeave", function(self)
		self._hovered = false
		self:_RefreshVisual()
	end)
	button:SetScript("OnEnable", function(self)
		self:_RefreshVisual()
	end)
	button:SetScript("OnDisable", function(self)
		self:_RefreshVisual()
	end)

	if opts.onClick then
		button:SetScript("OnClick", opts.onClick)
	end

	for k, v in pairs(ButtonMixin) do
		button[k] = v
	end

	button:_RefreshVisual()
	if self.RegisterThemeable then
		self:RegisterThemeable(button)
	end
	return button
end
