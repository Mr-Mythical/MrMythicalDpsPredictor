--[[
Panel.lua - SVG-backed panel / dialog chrome
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local PanelMixin = {}

function PanelMixin:SetTitle(text)
	if self.Title then
		self.Title:SetText(text or "")
	end
end

function PanelMixin:GetTitle()
	return self.Title and self.Title:GetText() or ""
end

local function addEdgeBorder(frame, color)
	local thickness = 2
	local textures = {}
	local top = frame:CreateTexture(nil, "BORDER")
	top:SetColorTexture(color.r, color.g, color.b, color.a or 1)
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(thickness)
	textures.top = top
	local bottom = frame:CreateTexture(nil, "BORDER")
	bottom:SetColorTexture(color.r, color.g, color.b, color.a or 1)
	bottom:SetPoint("BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT")
	bottom:SetHeight(thickness)
	textures.bottom = bottom
	local left = frame:CreateTexture(nil, "BORDER")
	left:SetColorTexture(color.r, color.g, color.b, color.a or 1)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(thickness)
	textures.left = left
	local right = frame:CreateTexture(nil, "BORDER")
	right:SetColorTexture(color.r, color.g, color.b, color.a or 1)
	right:SetPoint("TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT")
	right:SetWidth(thickness)
	textures.right = right
	return textures
end

--- @param parent Frame
--- @param opts table|nil { width, height, title, name, movable, frameStrata }
function lib:CreatePanel(parent, opts)
	opts = opts or {}
	parent = parent or UIParent

	local width = opts.width or Theme.FRAME.WIDTH
	local height = opts.height or Theme.FRAME.HEIGHT

	local frame = CreateFrame("Frame", opts.name, parent)
	frame:SetSize(width, height)
	frame:SetFrameStrata(opts.frameStrata or "DIALOG")

	-- PANEL_BG includes fill + stroke
	local bg, bgKind = self:CreateSVG(frame, self.Assets.PANEL_BG, "BACKGROUND")
	if bg then
		bg:SetAllPoints()
		frame.Background = bg
		if bgKind == "fallback" then
			Theme.ApplyColorTexture(bg, Theme.COLORS.PANEL_BG)
			frame.BorderTextures = addEdgeBorder(frame, Theme.COLORS.PANEL_BORDER)
		end
	end

	if opts.title then
		local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		title:SetPoint("TOP", 0, -Theme.LAYOUT.PADDING)
		title:SetText(opts.title)
		Theme.ApplyVertexColor(title, Theme.COLORS.TEXT)
		frame.Title = title
	end

	if opts.movable then
		frame:SetMovable(true)
		frame:EnableMouse(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", frame.StartMoving)
		frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	end

	for k, v in pairs(PanelMixin) do
		frame[k] = v
	end

	return frame
end
