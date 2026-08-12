--[[
Customize.lua - Runtime theme overrides and custom asset registration

Consumers can restyle LibMrMythicalUI without forking widgets:

  local Lib = LibStub("LibMrMythicalUI-1.0")
  Lib:SetThemeColor("ACCENT", 0.2, 0.7, 1, 1)
  Lib:SetLayoutValue("BUTTON_HEIGHT", 28)
  Lib:RegisterAsset("LOGO", "Interface\\AddOns\\MyAddon\\Media\\logo.tga")
  Lib:ApplyRect(myButton, { x = 16, y = -60, w = 120, h = 30 })
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)

local function shallowCopy(src)
	local dst = {}
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = shallowCopy(v)
		else
			dst[k] = v
		end
	end
	return dst
end

local function ensureDefaults()
	if lib._themeDefaults then
		return
	end
	lib._themeDefaults = {
		FRAME = shallowCopy(lib.Theme.FRAME),
		LAYOUT = shallowCopy(lib.Theme.LAYOUT),
		COLORS = shallowCopy(lib.Theme.COLORS),
	}
	lib._assetDefaults = shallowCopy(lib.Assets)
end

--- Merge a partial color table into Theme.COLORS.
--- @param colors table map of COLOR_KEY -> {r,g,b,a} or {r,g,b}
function lib:SetThemeColors(colors)
	ensureDefaults()
	if type(colors) ~= "table" then
		return
	end
	for key, color in pairs(colors) do
		if type(color) == "table" and color.r and color.g and color.b then
			self.Theme.COLORS[key] = {
				r = color.r,
				g = color.g,
				b = color.b,
				a = color.a or 1,
			}
		end
	end
end

--- Set a single theme color.
function lib:SetThemeColor(key, r, g, b, a)
	ensureDefaults()
	if not key then
		return
	end
	self.Theme.COLORS[key] = { r = r or 1, g = g or 1, b = b or 1, a = a or 1 }
end

--- Merge FRAME / LAYOUT numeric overrides.
--- @param which "FRAME"|"LAYOUT"
--- @param values table
function lib:SetThemeSection(which, values)
	ensureDefaults()
	local section = self.Theme[which]
	if type(section) ~= "table" or type(values) ~= "table" then
		return
	end
	for k, v in pairs(values) do
		if type(v) == "number" then
			section[k] = v
		end
	end
end

function lib:SetLayoutValue(key, value)
	ensureDefaults()
	if key and type(value) == "number" then
		self.Theme.LAYOUT[key] = value
	end
end

function lib:SetFrameValue(key, value)
	ensureDefaults()
	if key and type(value) == "number" then
		self.Theme.FRAME[key] = value
	end
end

--- Restore Theme + Assets to values captured at first customization call / load.
function lib:ResetTheme()
	ensureDefaults()
	self.Theme.FRAME = shallowCopy(self._themeDefaults.FRAME)
	self.Theme.LAYOUT = shallowCopy(self._themeDefaults.LAYOUT)
	self.Theme.COLORS = shallowCopy(self._themeDefaults.COLORS)
	self.Assets = shallowCopy(self._assetDefaults)
end

--- Register or override an asset key.
--- pathOrKey may be a relative Assets/ key ("icons/foo.svg") or absolute Interface\ path.
function lib:RegisterAsset(key, pathOrKey)
	ensureDefaults()
	if not key or not pathOrKey then
		return
	end
	self.Assets[key] = pathOrKey
end

function lib:GetAsset(key)
	return self.Assets and self.Assets[key]
end

--- Apply a customization profile.
--- @param profile table { colors?, layout?, frame?, assets?, assetRoot? }
function lib:ApplyProfile(profile)
	if type(profile) ~= "table" then
		return
	end
	ensureDefaults()
	if profile.assetRoot then
		self:SetAssetRoot(profile.assetRoot)
	end
	if profile.colors then
		self:SetThemeColors(profile.colors)
	end
	if profile.layout then
		self:SetThemeSection("LAYOUT", profile.layout)
	end
	if profile.frame then
		self:SetThemeSection("FRAME", profile.frame)
	end
	if profile.assets then
		for k, v in pairs(profile.assets) do
			self:RegisterAsset(k, v)
		end
	end
end

--- Apply a rect to a region. rect = { x, y, w?, h?, size? }; point defaults to TOPLEFT.
--- @param region Region|Frame
--- @param rect table
--- @param point string|nil
function lib:ApplyRect(region, rect, point)
	if not region or type(rect) ~= "table" then
		return
	end
	point = point or "TOPLEFT"
	if rect.size and type(region.SetSize) == "function" then
		region:SetSize(rect.size, rect.size)
	elseif rect.w and rect.h and type(region.SetSize) == "function" then
		region:SetSize(rect.w, rect.h)
	end
	if rect.x ~= nil and rect.y ~= nil and type(region.SetPoint) == "function" then
		region:ClearAllPoints()
		region:SetPoint(point, rect.x, rect.y)
	end
end

lib._themeables = lib._themeables or {}

--- Register a widget so RefreshTheme can restyle it after SetThemeColor / ApplyProfile.
--- @param frame Frame
function lib:RegisterThemeable(frame)
	if not frame then
		return
	end
	frame._libThemeable = true
	local list = self._themeables
	for i = 1, #list do
		if list[i] == frame then
			return
		end
	end
	list[#list + 1] = frame
end

local function refreshOne(frame)
	if not frame then
		return
	end
	if type(frame._RefreshTheme) == "function" then
		frame:_RefreshTheme()
	elseif type(frame._RefreshVisual) == "function" then
		frame:_RefreshVisual()
	elseif type(frame._Refresh) == "function" then
		frame:_Refresh()
	end
end

local function isDescendantOf(frame, root)
	local cur = frame
	while cur do
		if cur == root then
			return true
		end
		cur = cur.GetParent and cur:GetParent() or nil
	end
	return false
end

local function walkThemeableChildren(frame)
	if not frame then
		return
	end
	if frame._libThemeable then
		refreshOne(frame)
	end
	if type(frame.GetChildren) ~= "function" then
		return
	end
	local children = { frame:GetChildren() }
	for i = 1, #children do
		walkThemeableChildren(children[i])
	end
end

--- Re-apply theme colors/visuals to registered widgets.
--- @param rootFrame Frame|nil when set, only widgets under this root (plus a child walk)
function lib:RefreshTheme(rootFrame)
	local list = self._themeables
	local alive = {}
	for i = 1, #list do
		local frame = list[i]
		if frame and frame.GetObjectType then
			alive[#alive + 1] = frame
			if not rootFrame or isDescendantOf(frame, rootFrame) then
				refreshOne(frame)
			end
		end
	end
	self._themeables = alive

	if rootFrame then
		walkThemeableChildren(rootFrame)
	end
end

-- Snapshot theme defaults after load
ensureDefaults()
