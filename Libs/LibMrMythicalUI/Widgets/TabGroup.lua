--[[
TabGroup.lua - Horizontal tabs with a shared content pane
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local TabGroupMixin = {}

function TabGroupMixin:GetSelected()
	return self._selected
end

function TabGroupMixin:GetContent()
	return self.Content
end

function TabGroupMixin:SetSelected(key)
	if not key then
		return
	end
	self._selected = key
	for _, tab in ipairs(self._tabs or {}) do
		local active = tab._key == key
		tab:SetSelected(active)
		if tab.Page then
			tab.Page:SetShown(active)
		end
	end
	if self._onSelect then
		self._onSelect(key)
	end
end

--- @param parent Frame
--- @param opts table|nil {
---   tabs = { { text, key }, ... },
---   width, height, selected, onSelect, name, tabWidth
--- }
function lib:CreateTabGroup(parent, opts)
	opts = opts or {}
	local width = opts.width or 360
	local height = opts.height or 180
	local tabH = Theme.LAYOUT.BUTTON_HEIGHT or 30
	local tabW = opts.tabWidth or Theme.LAYOUT.NAV_TAB_WIDTH or 100
	local entries = opts.tabs or {
		{ text = "Tab 1", key = "tab1" },
		{ text = "Tab 2", key = "tab2" },
	}

	local frame = CreateFrame("Frame", opts.name, parent)
	frame:SetSize(width, height)
	frame._lib = self
	frame._onSelect = opts.onSelect
	frame._tabs = {}

	local bar = CreateFrame("Frame", nil, frame)
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	bar:SetHeight(tabH)
	frame.TabBar = bar

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", 0, -tabH - 4)
	content:SetPoint("BOTTOMRIGHT")
	local contentBg = self:CreateColorTexture(content, Theme.COLORS.NAV_BACKGROUND, "BACKGROUND")
	contentBg:SetAllPoints()
	frame.Content = content

	local selected = opts.selected or (entries[1] and (entries[1].key or "tab1"))

	for i, entry in ipairs(entries) do
		local key = entry.key or ("tab" .. i)
		local tab = self:CreateNavTab(bar, {
			text = entry.text or ("Tab " .. i),
			width = tabW,
			height = tabH,
			selected = key == selected,
		})
		tab._key = key
		tab:SetPoint("TOPLEFT", (i - 1) * (tabW + 4), 0)
		tab:SetScript("OnClick", function()
			frame:SetSelected(key)
		end)

		local page = CreateFrame("Frame", nil, content)
		page:SetAllPoints()
		page:SetShown(key == selected)
		tab.Page = page

		frame._tabs[i] = tab
	end

	for k, v in pairs(TabGroupMixin) do
		frame[k] = v
	end

	frame._selected = selected
	return frame
end
