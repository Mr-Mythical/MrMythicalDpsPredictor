--[[
Label.lua - Themed font string wrapper
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

--- @param parent Frame
--- @param opts table|nil { text, width, height, color, font, justifyH }
function lib:CreateLabel(parent, opts)
	opts = opts or {}
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(opts.width or 200, opts.height or Theme.LAYOUT.ROW_HEIGHT or 25)

	local fs = frame:CreateFontString(nil, "OVERLAY", opts.font or "GameFontNormal")
	fs:SetAllPoints()
	fs:SetJustifyH(opts.justifyH or "LEFT")
	fs:SetText(opts.text or "")
	local color = Theme.COLORS[opts.color or "TEXT"] or Theme.COLORS.TEXT
	Theme.ApplyVertexColor(fs, color)
	frame.FontString = fs

	function frame:SetText(value)
		fs:SetText(value or "")
	end

	function frame:SetTextColorKey(key)
		local c = Theme.COLORS[key or "TEXT"] or Theme.COLORS.TEXT
		Theme.ApplyVertexColor(fs, c)
	end

	return frame
end
