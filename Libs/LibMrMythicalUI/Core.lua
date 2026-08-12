--[[
Core.lua - LibMrMythicalUI-1.0 registration and asset root resolution
]]

local hostAddon = ...
local MAJOR, MINOR = "LibMrMythicalUI-1.0", 10
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
	return
end

lib.hostAddon = hostAddon

if hostAddon == "LibMrMythicalUI" then
	lib.assetRoot = "Interface\\AddOns\\LibMrMythicalUI\\Assets\\"
else
	lib.assetRoot = ("Interface\\AddOns\\%s\\Libs\\LibMrMythicalUI\\Assets\\"):format(hostAddon)
end

--- Set the Assets directory (trailing backslash optional).
function lib:SetAssetRoot(path)
	if path and path ~= "" then
		if not path:find("\\$") then
			path = path .. "\\"
		end
		self.assetRoot = path
	end
end

function lib:GetAssetRoot()
	return self.assetRoot
end

function lib:GetVersion()
	return MAJOR, MINOR
end
