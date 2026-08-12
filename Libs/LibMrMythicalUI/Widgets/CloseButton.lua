--[[
CloseButton.lua - SVG close button
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

--- @param parent Frame
--- @param onClick function|nil
function lib:CreateCloseButton(parent, onClick)
	local size = Theme.LAYOUT.CLOSE_SIZE
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size, size)
	button._lib = self

	local graphic, kind = self:CreateSVG(button, self.Assets.CLOSE, "ARTWORK")
	if graphic then
		graphic:SetAllPoints()
		button.Graphic = graphic
		if kind == "fallback" then
			Theme.ApplyColorTexture(graphic, Theme.COLORS.BUTTON_BG)
			local x = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			x:SetPoint("CENTER")
			x:SetText("X")
			button.Label = x
		end
	end

	button:SetScript("OnEnter", function(self)
		if self.Graphic and self.Graphic.SetVertexColor then
			self.Graphic:SetVertexColor(1, 1, 1, 1)
		end
	end)
	button:SetScript("OnLeave", function(self)
		if self.Graphic and self.Graphic.SetVertexColor then
			self.Graphic:SetVertexColor(0.85, 0.85, 0.85, 1)
		end
	end)

	button:SetScript("OnClick", function(self, ...)
		if onClick then
			onClick(self, ...)
		elseif parent and parent.Hide then
			parent:Hide()
		end
	end)

	return button
end
