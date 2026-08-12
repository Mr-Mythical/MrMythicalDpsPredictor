--[[
Icon.lua - Icon region (TGA/BLP texture or SVG)
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local function isRasterPath(path)
	if not path or type(path) ~= "string" then
		return false
	end
	local lower = path:lower()
	return lower:find("%.tga$")
		or lower:find("%.blp$")
		or lower:find("%.png$")
		or lower:find("%.jpg$")
		or lower:find("%.jpeg$")
end

local IconMixin = {}

function IconMixin:SetAsset(pathOrKey)
	local libRef = self._lib
	self._asset = pathOrKey
	if not self.Graphic then
		return
	end
	local path = libRef:ResolveAssetPath(pathOrKey) or pathOrKey
	if self._kind == "texture" or isRasterPath(path) then
		if type(self.Graphic.SetTexture) == "function" then
			self.Graphic:SetTexture(path)
		end
	elseif self._kind == "fallback" then
		Theme.ApplyColorTexture(self.Graphic, Theme.COLORS.ACCENT)
	else
		libRef:SetSVG(self.Graphic, pathOrKey)
	end
end

function IconMixin:SetIconSize(size)
	self:SetSize(size, size)
end

--- @param parent Frame
--- @param assetKeyOrPath string|nil
--- @param size number|nil
function lib:CreateIcon(parent, assetKeyOrPath, size)
	size = size or Theme.LAYOUT.ICON_SIZE
	assetKeyOrPath = assetKeyOrPath or self.Assets.LOGO

	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(size, size)
	frame._lib = self

	local resolved = self:ResolveAssetPath(assetKeyOrPath) or assetKeyOrPath
	local graphic
	local kind

	if isRasterPath(resolved) or isRasterPath(assetKeyOrPath) then
		graphic = frame:CreateTexture(nil, "ARTWORK")
		graphic:SetAllPoints()
		graphic:SetTexture(resolved)
		kind = "texture"
	else
		graphic, kind = self:CreateSVG(frame, assetKeyOrPath, "ARTWORK")
		if graphic then
			graphic:SetAllPoints()
			if kind == "fallback" then
				Theme.ApplyColorTexture(graphic, Theme.COLORS.ACCENT)
			end
		end
	end

	frame.Graphic = graphic
	frame._kind = kind
	frame._asset = assetKeyOrPath

	for k, v in pairs(IconMixin) do
		frame[k] = v
	end

	return frame
end
