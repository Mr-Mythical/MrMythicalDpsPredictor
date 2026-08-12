--[[
MultiLineEditBox.lua - ScrollFrame + multi-line EditBox for notes / paste
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local MultiMixin = {}

function MultiMixin:SetText(text)
	if self.EditBox then
		self.EditBox:SetText(text or "")
	end
end

function MultiMixin:GetText()
	return self.EditBox and self.EditBox:GetText() or ""
end

function MultiMixin:SetMaxLetters(n)
	if self.EditBox and self.EditBox.SetMaxLetters then
		self.EditBox:SetMaxLetters(n or 0)
	end
end

function MultiMixin:ClearFocus()
	if self.EditBox then
		self.EditBox:ClearFocus()
	end
end

function MultiMixin:SetFocus()
	if self.EditBox then
		self.EditBox:SetFocus()
	end
end

function MultiMixin:_RefreshTheme()
	if self.Border then
		Theme.ApplyColorTexture(self.Border, Theme.COLORS.BUTTON_BORDER)
	end
	if self.Background then
		Theme.ApplyColorTexture(self.Background, Theme.COLORS.BUTTON_BG)
	end
	if self.EditBox then
		local tc = Theme.COLORS.TEXT
		self.EditBox:SetTextColor(tc.r, tc.g, tc.b, tc.a or 1)
	end
end

--- @param parent Frame
--- @param opts table|nil {
---   text, width, height, onChange, maxLetters, name
--- }
function lib:CreateMultiLineEditBox(parent, opts)
	opts = opts or {}
	local width = opts.width or 280
	local height = opts.height or 100

	local frame = CreateFrame("Frame", opts.name, parent)
	frame:SetSize(width, height)
	frame._lib = self

	local border = self:CreateColorTexture(frame, Theme.COLORS.BUTTON_BORDER, "BACKGROUND")
	border:SetAllPoints()
	frame.Border = border

	local bg = self:CreateColorTexture(frame, Theme.COLORS.BUTTON_BG, "ARTWORK")
	bg:SetPoint("TOPLEFT", 1, -1)
	bg:SetPoint("BOTTOMRIGHT", -1, 1)
	frame.Background = bg

	local scroll = self:CreateScrollFrame(frame, {
		width = width - 4,
		height = height - 4,
	})
	scroll:SetPoint("TOPLEFT", 2, -2)
	frame.ScrollFrame = scroll

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetFontObject("GameFontHighlight")
	edit:SetAutoFocus(false)
	edit:SetTextInsets(6, 6, 4, 4)
	edit:SetWidth(width - 24)
	edit:SetText(opts.text or "")
	if opts.maxLetters then
		edit:SetMaxLetters(opts.maxLetters)
	end
	local tc = Theme.COLORS.TEXT
	edit:SetTextColor(tc.r, tc.g, tc.b, tc.a or 1)
	edit:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	edit:SetScript("OnTextChanged", function(self, userInput)
		local lineH = 14
		if self.GetFont then
			local _, fontSize = self:GetFont()
			if fontSize and fontSize > 0 then
				lineH = fontSize + 2
			end
		end
		local lines = (self.GetNumLines and self:GetNumLines()) or 1
		local needed = math.max(height - 8, lines * lineH + 16)
		self:SetHeight(needed)
		if scroll._UpdateScrollRange then
			scroll:_UpdateScrollRange()
		end
		if userInput and opts.onChange then
			opts.onChange(frame, self:GetText())
		end
	end)
	edit:SetScript("OnCursorChanged", function(self, x, y, w, h)
		-- Keep cursor roughly in view
		local offset = scroll._scroll and scroll._scroll:GetVerticalScroll() or 0
		local viewH = scroll:GetHeight() or height
		local cursorTop = -y
		local cursorBottom = cursorTop + (h or 12)
		if cursorTop < offset then
			scroll:SetVerticalScroll(math.max(0, cursorTop))
		elseif cursorBottom > offset + viewH then
			scroll:SetVerticalScroll(cursorBottom - viewH)
		end
	end)

	-- Initial height so scroll child is valid
	edit:SetHeight(math.max(height - 8, 40))
	scroll:SetScrollChild(edit)
	frame.EditBox = edit

	-- Click chrome to focus
	frame:EnableMouse(true)
	frame:SetScript("OnMouseDown", function()
		edit:SetFocus()
	end)

	for k, v in pairs(MultiMixin) do
		frame[k] = v
	end

	if self.RegisterThemeable then
		self:RegisterThemeable(frame)
	end

	return frame
end
