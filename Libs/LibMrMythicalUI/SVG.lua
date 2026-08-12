--[[
SVG.lua - VectorGraphics / Texture SVG helpers for WoW 12.1+
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)

local warnedOnce = false

local function warnOnce(msg)
	if warnedOnce then
		return
	end
	warnedOnce = true
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cffccaa00LibMrMythicalUI:|r " .. msg)
	end
end

--- @return boolean
function lib:SupportsVectorGraphics()
	if self._supportsVG ~= nil then
		return self._supportsVG
	end
	local frame = CreateFrame("Frame")
	self._supportsVG = type(frame.CreateVectorGraphics) == "function"
	return self._supportsVG
end

--- @return boolean
function lib:SupportsTextureSVG()
	if self._supportsTextureSVG ~= nil then
		return self._supportsTextureSVG
	end
	local texture = CreateFrame("Frame"):CreateTexture()
	self._supportsTextureSVG = type(texture.SetSVG) == "function"
	return self._supportsTextureSVG
end

function lib:SupportsSVG()
	return self:SupportsVectorGraphics() or self:SupportsTextureSVG()
end

--- @param pathOrKey string Absolute Interface path or Assets-relative key
--- @return string|nil
function lib:ResolveAssetPath(pathOrKey)
	if not pathOrKey then
		return nil
	end
	if pathOrKey:find("^[Ii]nterface[\\/]") or pathOrKey:find("^FileDataID") then
		return pathOrKey
	end
	local root = self.assetRoot or ""
	local relative = pathOrKey:gsub("^/+", ""):gsub("/", "\\")
	return root .. relative
end

--- @return boolean success
function lib:SetSVG(region, pathOrKey)
	if not region then
		return false
	end
	local path = self:ResolveAssetPath(pathOrKey)
	if not path then
		return false
	end

	if type(region.SetSVG) == "function" then
		local ok = region:SetSVG(path)
		return ok ~= false
	end

	if type(region.SetTexture) == "function" then
		region:SetTexture(path)
		return true
	end

	return false
end

function lib:ClearSVG(region)
	if not region then
		return
	end
	if type(region.ClearSVG) == "function" then
		region:ClearSVG()
	elseif type(region.SetTexture) == "function" then
		region:SetTexture(nil)
	end
end

--- @param parent Frame
--- @param pathOrKey string|nil
--- @param layer string|nil
--- @param subLevel number|nil
--- @return Region|nil, string kind "vector"|"texture"|"fallback"|"none"
function lib:CreateSVG(parent, pathOrKey, layer, subLevel)
	if not parent then
		return nil, "none"
	end
	layer = layer or "ARTWORK"

	local region
	local kind

	if self:SupportsVectorGraphics() then
		region = parent:CreateVectorGraphics(nil, layer, nil, subLevel)
		kind = "vector"
	else
		region = parent:CreateTexture(nil, layer, nil, subLevel)
		kind = self:SupportsTextureSVG() and "texture" or "fallback"
		if kind == "fallback" and pathOrKey then
			warnOnce("SVG APIs unavailable (need WoW 12.1+). Using solid-color fallbacks where possible.")
		end
	end

	if region and pathOrKey then
		self:SetSVG(region, pathOrKey)
	end

	return region, kind
end

--- @param parent Frame
--- @param color table|nil {r,g,b,a}
--- @param layer string|nil
--- @param subLevel number|nil
--- @return Texture|nil
function lib:CreateColorTexture(parent, color, layer, subLevel)
	if not parent then
		return nil
	end
	local texture = parent:CreateTexture(nil, layer or "BACKGROUND", nil, subLevel)
	if color then
		self.Theme.ApplyColorTexture(texture, color)
	end
	return texture
end

lib.Assets = {
	PANEL_BG = "chrome/panel-bg.svg",
	PANEL_BORDER = "chrome/panel-border.svg",
	NAV_PANEL_BG = "chrome/nav-panel-bg.svg",
	BUTTON_NORMAL = "chrome/button-normal.svg",
	BUTTON_HOVER = "chrome/button-hover.svg",
	BUTTON_ACTIVE = "chrome/button-active.svg",
	NAV_TAB = "chrome/nav-tab.svg",
	NAV_TAB_ACTIVE = "chrome/nav-tab-active.svg",
	CLOSE = "chrome/close.svg",
	LOGO = "icons/logo.tga",
	PROGRESS_RING = "chrome/progress-ring.svg",
	SCROLLBAR = "chrome/scrollbar.svg",
	SLIDER_TRACK = "chrome/slider-track.svg",
}
