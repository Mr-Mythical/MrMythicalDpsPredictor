--[[
Header.lua - Section header label
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

--- @param parent Frame
--- @param opts table|nil { text, width, font }
function lib:CreateHeader(parent, opts)
	opts = opts or {}
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(opts.width or 200, Theme.LAYOUT.LARGE_ROW_HEIGHT or 30)

	local text = frame:CreateFontString(nil, "OVERLAY", opts.font or "GameFontNormalLarge")
	text:SetPoint("LEFT")
	text:SetText(opts.text or "")
	Theme.ApplyVertexColor(text, Theme.COLORS.ACCENT)
	frame.Label = text

	function frame:SetText(value)
		text:SetText(value or "")
	end

	return frame
end
