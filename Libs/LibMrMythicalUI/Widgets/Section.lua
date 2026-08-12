--[[
Section.lua - Titled content container
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local SectionMixin = {}

function SectionMixin:SetTitle(text)
	if self.Title then
		self.Title:SetText(text or "")
	end
end

function SectionMixin:GetContent()
	return self.Content
end

--- @param parent Frame
--- @param opts table|nil { title, width, height, name }
function lib:CreateSection(parent, opts)
	opts = opts or {}
	local width = opts.width or 300
	local height = opts.height or 120
	local titleH = Theme.LAYOUT.LARGE_ROW_HEIGHT or 30

	local frame = CreateFrame("Frame", opts.name, parent)
	frame:SetSize(width, height)
	frame._lib = self

	local bg = self:CreateColorTexture(frame, Theme.COLORS.NAV_BACKGROUND, "BACKGROUND")
	bg:SetAllPoints()
	frame.Background = bg

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", Theme.LAYOUT.PADDING or 10, -(Theme.LAYOUT.PADDING or 8))
	title:SetText(opts.title or "Section")
	Theme.ApplyVertexColor(title, Theme.COLORS.ACCENT)
	frame.Title = title

	local divider = self:CreateDivider(frame, { width = width - (Theme.LAYOUT.PADDING or 10) * 2 })
	divider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	frame.Divider = divider

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -6)
	content:SetPoint("BOTTOMRIGHT", -(Theme.LAYOUT.PADDING or 10), Theme.LAYOUT.PADDING or 10)
	frame.Content = content

	for k, v in pairs(SectionMixin) do
		frame[k] = v
	end

	return frame
end
