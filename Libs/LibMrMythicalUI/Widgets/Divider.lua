--[[
Divider.lua - Horizontal rule
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

--- @param parent Frame
--- @param opts table|nil { width, height }
function lib:CreateDivider(parent, opts)
	opts = opts or {}
	local frame = CreateFrame("Frame", nil, parent)
	local width = opts.width or 200
	local height = opts.height or 2
	frame:SetSize(width, height)

	local line = frame:CreateTexture(nil, "ARTWORK")
	line:SetAllPoints()
	Theme.ApplyColorTexture(line, Theme.COLORS.PANEL_BORDER)
	frame.Line = line

	return frame
end
