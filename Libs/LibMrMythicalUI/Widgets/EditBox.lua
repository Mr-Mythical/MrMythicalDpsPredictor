--[[
EditBox.lua - Themed single-line text input
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local EditMixin = {}

function EditMixin:SetText(text)
	if self.EditBox then
		self.EditBox:SetText(text or "")
	end
	self:_RefreshPlaceholder()
end

function EditMixin:GetText()
	return self.EditBox and self.EditBox:GetText() or ""
end

function EditMixin:SetPlaceholder(text)
	self._placeholder = text or ""
	if self.Placeholder then
		self.Placeholder:SetText(self._placeholder)
		self:_RefreshPlaceholder()
	end
end

function EditMixin:_RefreshPlaceholder()
	if not self.Placeholder or not self.EditBox then
		return
	end
	local empty = (self:GetText() or "") == ""
	self.Placeholder:SetShown(empty and not self.EditBox:HasFocus())
end

--- @param parent Frame
--- @param opts table|nil { text, placeholder, width, height, onChange, name, numeric }
function lib:CreateEditBox(parent, opts)
	opts = opts or {}
	local width = opts.width or 200
	local height = opts.height or Theme.LAYOUT.BUTTON_HEIGHT or 30

	local frame = CreateFrame("Frame", opts.name, parent)
	frame:SetSize(width, height)
	frame._lib = self
	frame._placeholder = opts.placeholder or ""

	local border = self:CreateColorTexture(frame, Theme.COLORS.BUTTON_BORDER, "BACKGROUND")
	border:SetAllPoints()
	frame.Border = border

	local bg = self:CreateColorTexture(frame, Theme.COLORS.BUTTON_BG, "ARTWORK")
	bg:SetPoint("TOPLEFT", 1, -1)
	bg:SetPoint("BOTTOMRIGHT", -1, 1)
	frame.Background = bg

	local edit = CreateFrame("EditBox", nil, frame)
	edit:SetPoint("TOPLEFT", 8, -4)
	edit:SetPoint("BOTTOMRIGHT", -8, 4)
	edit:SetFontObject("GameFontHighlight")
	edit:SetAutoFocus(false)
	edit:SetText(opts.text or "")
	if opts.numeric then
		edit:SetNumeric(true)
	end
	local tc = Theme.COLORS.TEXT
	edit:SetTextColor(tc.r, tc.g, tc.b, tc.a or 1)
	frame.EditBox = edit

	local placeholder = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	placeholder:SetPoint("LEFT", edit, "LEFT")
	placeholder:SetPoint("RIGHT", edit, "RIGHT")
	placeholder:SetJustifyH("LEFT")
	placeholder:SetText(frame._placeholder)
	frame.Placeholder = placeholder

	edit:SetScript("OnTextChanged", function(self, userInput)
		frame:_RefreshPlaceholder()
		if userInput and opts.onChange then
			opts.onChange(frame, self:GetText())
		end
	end)
	edit:SetScript("OnEditFocusGained", function()
		frame:_RefreshPlaceholder()
	end)
	edit:SetScript("OnEditFocusLost", function()
		frame:_RefreshPlaceholder()
	end)
	edit:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	edit:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)

	for k, v in pairs(EditMixin) do
		frame[k] = v
	end
	frame:_RefreshPlaceholder()
	return frame
end
