--[[
Theme.lua - Shared design tokens for LibMrMythicalUI
Generated from design/tokens.json — prefer editing tokens, not this file.
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)

lib.Theme = lib.Theme or {}
local Theme = lib.Theme

Theme.FRAME = {
	WIDTH = 850,
	HEIGHT = 500,
	NAV_PANEL_WIDTH = 140,
	CONTENT_WIDTH = 680,
}

Theme.LAYOUT = {
	ROW_HEIGHT = 25,
	LARGE_ROW_HEIGHT = 30,
	BUTTON_HEIGHT = 30,
	PADDING = 10,
	LARGE_PADDING = 20,
	ICON_SIZE = 24,
	CLOSE_SIZE = 24,
	BUTTON_WIDTH = 120,
	NAV_TAB_WIDTH = 120,
}

Theme.COLORS = {
	PANEL_BG = { r = 0.05, g = 0.05, b = 0.07, a = 0.92 },
	PANEL_BORDER = { r = 0.35, g = 0.35, b = 0.4, a = 1 },
	NAV_BACKGROUND = { r = 0.1, g = 0.1, b = 0.1, a = 0.8 },
	EVEN_ROW = { r = 0.1, g = 0.1, b = 0.1, a = 0.3 },
	ODD_ROW = { r = 0.15, g = 0.15, b = 0.15, a = 0.3 },
	BUTTON_BG = { r = 0.18, g = 0.18, b = 0.22, a = 1 },
	BUTTON_BG_HOVER = { r = 0.28, g = 0.28, b = 0.34, a = 1 },
	BUTTON_BG_ACTIVE = { r = 0.35, g = 0.32, b = 0.2, a = 1 },
	BUTTON_BORDER = { r = 0.45, g = 0.45, b = 0.5, a = 1 },
	TEXT = { r = 0.9, g = 0.9, b = 0.9, a = 1 },
	INFO_TEXT = { r = 0.8, g = 0.8, b = 0.8, a = 1 },
	DISABLED = { r = 0.5, g = 0.5, b = 0.5, a = 1 },
	ACCENT = { r = 0.85, g = 0.7, b = 0.25, a = 1 },
	SUCCESS_HIGH = { r = 0, g = 1, b = 0, a = 1 },
	SUCCESS_MEDIUM = { r = 1, g = 1, b = 0, a = 1 },
	SUCCESS_LOW = { r = 1, g = 0, b = 0, a = 1 },
	PROGRESS_TRACK = { r = 0.15, g = 0.15, b = 0.18, a = 1 },
	PROGRESS_FILL = { r = 0.85, g = 0.7, b = 0.25, a = 1 },
}

--- Apply an RGBA color table via SetVertexColor.
function Theme.ApplyVertexColor(region, color)
	if not region or not color then
		return
	end
	if type(region.SetVertexColor) == "function" then
		region:SetVertexColor(color.r, color.g, color.b, color.a or 1)
	end
end

--- Apply an RGBA color table via SetColorTexture.
function Theme.ApplyColorTexture(texture, color)
	if not texture or not color then
		return
	end
	if type(texture.SetColorTexture) == "function" then
		texture:SetColorTexture(color.r, color.g, color.b, color.a or 1)
	elseif type(texture.SetVertexColor) == "function" then
		texture:SetVertexColor(color.r, color.g, color.b, color.a or 1)
	end
end
