--[[
Dropdown.lua - Custom dropdown (no UIDropDownMenuTemplate)
Trigger uses an inset field + chevron, not a push-button chrome.
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local DEFAULT_MAX_MENU_HEIGHT = 280

local function truncateFontString(fs, text, maxWidth)
	text = text or ""
	if not fs then
		return
	end
	fs:SetText(text)
	if not maxWidth or maxWidth <= 8 then
		return
	end
	-- GetStringWidth can be 0 before the font string is laid out; do not treat that as "fits".
	local measured = fs:GetStringWidth()
	if not measured or measured <= 0 then
		return
	end
	if measured <= maxWidth then
		return
	end

	local ellipsis = "…"
	fs:SetText(ellipsis)
	local ellipsisW = fs:GetStringWidth() or 0
	local budget = maxWidth - ellipsisW
	if budget <= 0 then
		fs:SetText(ellipsis)
		return
	end

	-- Shrink from the end (UTF-8 safe enough for Latin track names).
	local s = text
	while #s > 0 do
		local trimmed = s:match("^(.-)[%z\1-\127\194-\244][\128-\191]*$")
		if not trimmed or trimmed == s then
			s = s:sub(1, math.max(0, #s - 1))
		else
			s = trimmed
		end
		fs:SetText(s .. ellipsis)
		local w = fs:GetStringWidth() or 0
		if w > 0 and w <= maxWidth then
			return
		end
	end
	fs:SetText(ellipsis)
end

local function fieldColors(hovered, enabled)
	if not enabled then
		return Theme.COLORS.DISABLED, Theme.COLORS.BUTTON_BORDER
	end
	if hovered then
		return Theme.COLORS.BUTTON_BG_HOVER or Theme.COLORS.BUTTON_BG, Theme.COLORS.ACCENT
	end
	-- Darker inset than push buttons
	local bg = Theme.COLORS.PANEL_BG or Theme.COLORS.BUTTON_BG
	return {
		r = math.min(1, (bg.r or 0.05) + 0.04),
		g = math.min(1, (bg.g or 0.05) + 0.04),
		b = math.min(1, (bg.b or 0.07) + 0.04),
		a = bg.a or 0.95,
	}, Theme.COLORS.BUTTON_BORDER
end

local DropdownMixin = {}

function DropdownMixin:SetWidth(width)
	width = width or self:GetWidth() or 120
	local height = self:GetHeight() or Theme.LAYOUT.BUTTON_HEIGHT
	self:SetSize(width, height)
	if self.Button then
		self.Button:SetSize(width, height)
		if self.Button.RefreshTruncation then
			self.Button:RefreshTruncation()
		elseif self._fullLabel and self.Button.SetLabel then
			self.Button:SetLabel(self._fullLabel)
		end
	end
end

function DropdownMixin:SetItems(items)
	self._items = items or {}
	if self.Menu and self.Menu:IsShown() then
		self:_RebuildMenu()
	end
end

function DropdownMixin:GetItems()
	return self._items
end

function DropdownMixin:SetValue(value, silent)
	self._value = value
	local label = tostring(value)
	for _, item in ipairs(self._items or {}) do
		if item.value == value then
			label = item.text or tostring(value)
			break
		end
	end
	self._fullLabel = label
	if self.Button and self.Button.SetLabel then
		self.Button:SetLabel(label)
	elseif self.Button and self.Button.Label then
		truncateFontString(
			self.Button.Label,
			label,
			math.max(20, (self:GetWidth() or 120) - 32)
		)
	end
	if not silent and self._onChanged then
		self._onChanged(self, value)
	end
end

function DropdownMixin:GetValue()
	return self._value
end

function DropdownMixin:CloseMenu()
	if self.Menu then
		self.Menu:Hide()
	end
	if self._closer then
		self._closer:Hide()
	end
	if self.Button and self.Button.Chevron then
		self.Button.Chevron:SetText("▼")
	end
end

function DropdownMixin:ToggleMenu()
	if not self.Menu then
		return
	end
	if self.Menu:IsShown() then
		self:CloseMenu()
	else
		self:_RebuildMenu()
		self.Menu:Show()
		if self._closer then
			self._closer:Show()
		end
		if self.Button and self.Button.Chevron then
			self.Button.Chevron:SetText("▲")
		end
	end
end

function DropdownMixin:_EnsurePool()
	self._rowPool = self._rowPool or {}
end

function DropdownMixin:_AcquireRow(host, width, height)
	self:_EnsurePool()
	local row = table.remove(self._rowPool)
	local libRef = self._lib
	if row then
		row:SetParent(host)
		row:ClearAllPoints()
		row:SetSize(width, height)
		row:Show()
		return row
	end
	row = libRef:CreateButton(host, {
		text = "",
		width = width,
		height = height,
	})
	return row
end

function DropdownMixin:_ReleaseRows()
	self:_EnsurePool()
	if self._activeRows then
		for _, row in ipairs(self._activeRows) do
			row:Hide()
			row:ClearAllPoints()
			row:SetParent(self.Menu)
			row:SetScript("OnClick", nil)
			if row.SetActive then
				row:SetActive(false)
			end
			if row.SetLabel then
				row:SetLabel("")
			end
			self._rowPool[#self._rowPool + 1] = row
		end
		wipe(self._activeRows)
	else
		self._activeRows = {}
	end
end

function DropdownMixin:_ClearMenuChrome()
	local menu = self.Menu
	if not menu then
		return
	end
	self:_ReleaseRows()
	if self._menuScroll then
		self._menuScroll:Hide()
		self._menuScroll:SetParent(nil)
		self._menuScroll = nil
	end
	if self._menuContent then
		self._menuContent:Hide()
		self._menuContent:SetParent(nil)
		self._menuContent = nil
	end
end

function DropdownMixin:_RebuildMenu()
	local menu = self.Menu
	local libRef = self._lib
	self:_ClearMenuChrome()

	local triggerWidth = math.max(self:GetWidth() or 0, 80)
	local items = self._items or {}
	local rowH = Theme.LAYOUT.BUTTON_HEIGHT

	-- Prefer a wider menu when labels are long (instance names, etc.).
	local width = math.max(triggerWidth, self._minMenuWidth or triggerWidth)
	if not self._probeLabel then
		self._probeLabel = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		self._probeLabel:Hide()
	end
	local pad = 24
	for _, item in ipairs(items) do
		local text = item.text or tostring(item.value or "")
		self._probeLabel:SetText(text)
		local needed = (self._probeLabel:GetStringWidth() or 0) + pad
		if needed > width then
			width = needed
		end
	end
	width = math.min(width, self._maxMenuWidth or 420)

	local count = #items
	local contentHeight = count * rowH + 8
	local maxH = self._maxMenuHeight or DEFAULT_MAX_MENU_HEIGHT
	local needsScroll = contentHeight > maxH

	local host = menu
	if needsScroll then
		local scroll = libRef:CreateScrollFrame(menu, {
			width = width,
			height = maxH,
		})
		scroll:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)
		local content = CreateFrame("Frame", nil, scroll)
		content:SetSize(width - 16, contentHeight)
		scroll:SetScrollChild(content)
		self._menuScroll = scroll
		self._menuContent = content
		host = content
		menu:SetHeight(maxH)
	else
		menu:SetHeight(math.max(contentHeight, rowH + 8))
	end
	menu:SetWidth(width)

	self._activeRows = self._activeRows or {}
	local y = -4
	local rowWidth = width - (needsScroll and 20 or 8)
	local rowHeight = rowH - 4
	for _, item in ipairs(items) do
		local captured = item
		local row = self:_AcquireRow(host, rowWidth, rowHeight)
		if row.SetClipsChildren then
			row:SetClipsChildren(true)
		end
		if row.Label then
			row.Label:ClearAllPoints()
			row.Label:SetPoint("LEFT", 8, 0)
			row.Label:SetPoint("RIGHT", -8, 0)
			row.Label:SetJustifyH("LEFT")
			row.Label:SetWordWrap(false)
		end
		local rowText = captured.text or tostring(captured.value)
		if row.SetLabel then
			row:SetLabel(rowText)
		end
		if row.Label then
			truncateFontString(row.Label, rowText, math.max(40, rowWidth - 16))
		end
		row:SetPoint("TOPLEFT", 4, y)
		if row.SetActive then
			row:SetActive(captured.value == self._value)
		end
		row:SetScript("OnClick", function()
			self:SetValue(captured.value)
			self:CloseMenu()
		end)
		self._activeRows[#self._activeRows + 1] = row
		y = y - rowH
	end

	if self._menuScroll and self._menuScroll._UpdateScrollRange then
		self._menuScroll:_UpdateScrollRange()
	end
end

function DropdownMixin:_RefreshTheme()
	if self.Button and self.Button._RefreshField then
		self.Button:_RefreshField()
	end
	if self.MenuBg then
		Theme.ApplyColorTexture(self.MenuBg, Theme.COLORS.PANEL_BG)
	end
	if self.MenuBorder then
		for _, edge in pairs(self.MenuBorder) do
			if edge then
				Theme.ApplyColorTexture(edge, Theme.COLORS.BUTTON_BORDER)
			end
		end
	end
	if self._activeRows then
		for _, row in ipairs(self._activeRows) do
			if row._RefreshVisual then
				row:_RefreshVisual()
			end
		end
	end
end

local function addEdgeBorder(frame, color)
	local thickness = 1
	local textures = {}
	local function edge(pointA, pointB, isHoriz)
		local t = frame:CreateTexture(nil, "BORDER")
		Theme.ApplyColorTexture(t, color)
		t:SetPoint(pointA)
		t:SetPoint(pointB)
		if isHoriz then
			t:SetHeight(thickness)
		else
			t:SetWidth(thickness)
		end
		return t
	end
	textures.top = edge("TOPLEFT", "TOPRIGHT", true)
	textures.bottom = edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
	textures.left = edge("TOPLEFT", "BOTTOMLEFT", false)
	textures.right = edge("TOPRIGHT", "BOTTOMRIGHT", false)
	return textures
end

local function createDropdownField(libRef, parent, width, height, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, height)
	button._lib = libRef
	button._hovered = false
	if button.SetClipsChildren then
		button:SetClipsChildren(true)
	end

	local bg = libRef:CreateColorTexture(button, Theme.COLORS.PANEL_BG, "BACKGROUND")
	bg:SetAllPoints()
	button.Background = bg
	button.Border = addEdgeBorder(button, Theme.COLORS.BUTTON_BORDER)

	local label = button:CreateFontString(nil, "OVERLAY", height <= 26 and "GameFontHighlightSmall" or "GameFontHighlight")
	label:SetPoint("LEFT", 10, 0)
	label:SetPoint("RIGHT", -22, 0)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(false)
	Theme.ApplyVertexColor(label, Theme.COLORS.TEXT)
	button.Label = label

	local chevron = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	chevron:SetPoint("RIGHT", -8, 0)
	chevron:SetText("▼")
	Theme.ApplyVertexColor(chevron, Theme.COLORS.INFO_TEXT or Theme.COLORS.TEXT)
	button.Chevron = chevron

	function button:SetLabel(text)
		self._fullLabel = text or ""
		local maxWidth = math.max(20, (self:GetWidth() or width or 120) - 32)
		truncateFontString(label, self._fullLabel, maxWidth)
	end

	function button:GetLabel()
		return self._fullLabel or label:GetText() or ""
	end

	function button:RefreshTruncation()
		if self._fullLabel then
			self:SetLabel(self._fullLabel)
		end
	end

	button.SetText = button.SetLabel
	button.GetText = button.GetLabel

	function button:_RefreshField()
		local fill, border = fieldColors(self._hovered, self:IsEnabled())
		Theme.ApplyColorTexture(self.Background, fill)
		if self.Border then
			for _, edge in pairs(self.Border) do
				Theme.ApplyColorTexture(edge, border)
			end
		end
		local textColor = self:IsEnabled() and Theme.COLORS.TEXT or Theme.COLORS.DISABLED
		Theme.ApplyVertexColor(label, textColor)
		Theme.ApplyVertexColor(chevron, self:IsEnabled() and (Theme.COLORS.INFO_TEXT or Theme.COLORS.TEXT) or Theme.COLORS.DISABLED)
	end

	button:SetScript("OnEnter", function(self)
		self._hovered = true
		self:_RefreshField()
	end)
	button:SetScript("OnLeave", function(self)
		self._hovered = false
		self:_RefreshField()
	end)
	button:SetScript("OnShow", function(self)
		if self.RefreshTruncation then
			self:RefreshTruncation()
		end
	end)
	button:SetScript("OnSizeChanged", function(self)
		if self.RefreshTruncation then
			self:RefreshTruncation()
		end
	end)
	button:SetScript("OnEnable", function(self)
		self:_RefreshField()
	end)
	button:SetScript("OnDisable", function(self)
		self:_RefreshField()
	end)
	button:SetScript("OnClick", onClick)

	button:_RefreshField()
	return button
end

--- @param parent Frame
--- @param opts table|nil { width, height, items={{text,value}}, value, onValueChanged, maxMenuHeight, minMenuWidth, maxMenuWidth, name }
function lib:CreateDropdown(parent, opts)
	opts = opts or {}
	local width = opts.width or 120
	local height = opts.height or Theme.LAYOUT.BUTTON_HEIGHT

	local frame = CreateFrame("Frame", opts.name, parent)
	frame:SetSize(width, height)
	frame._lib = self
	frame._items = opts.items or {}
	frame._onChanged = opts.onValueChanged
	frame._maxMenuHeight = opts.maxMenuHeight or DEFAULT_MAX_MENU_HEIGHT
	frame._minMenuWidth = opts.minMenuWidth
	frame._maxMenuWidth = opts.maxMenuWidth or 420
	frame._rowPool = {}
	frame._activeRows = {}

	local button = createDropdownField(self, frame, width, height, function()
		frame:ToggleMenu()
	end)
	button:SetAllPoints()
	frame.Button = button

	local menu = CreateFrame("Frame", nil, UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetFrameLevel(400)
	menu:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
	local menuBg = self:CreateColorTexture(menu, Theme.COLORS.PANEL_BG, "BACKGROUND")
	menuBg:SetAllPoints()
	menu:EnableMouse(true)
	menu:Hide()
	frame.Menu = menu
	frame.MenuBg = menuBg
	frame.MenuBorder = addEdgeBorder(menu, Theme.COLORS.BUTTON_BORDER)

	local closer = CreateFrame("Button", nil, UIParent)
	closer:SetFrameStrata("FULLSCREEN_DIALOG")
	closer:SetFrameLevel(399)
	closer:SetAllPoints(UIParent)
	closer:Hide()
	closer:SetScript("OnClick", function()
		frame:CloseMenu()
	end)
	frame._closer = closer

	for k, v in pairs(DropdownMixin) do
		frame[k] = v
	end

	local initial = opts.value
	if initial == nil and frame._items[1] then
		initial = frame._items[1].value
	end
	if initial ~= nil then
		frame:SetValue(initial, true)
	end

	if self.RegisterThemeable then
		self:RegisterThemeable(frame)
	end

	return frame
end
