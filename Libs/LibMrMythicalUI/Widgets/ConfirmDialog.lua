--[[
ConfirmDialog.lua - Branded confirm / cancel dialog
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local DialogMixin = {}

function DialogMixin:SetTitle(text)
	if self.Title then
		self.Title:SetText(text or "")
	end
end

function DialogMixin:SetMessage(text)
	if self.Message then
		self.Message:SetText(text or "")
	end
end

function DialogMixin:SetConfirmText(text)
	if self.ConfirmButton and self.ConfirmButton.SetLabel then
		self.ConfirmButton:SetLabel(text or "OK")
	end
end

function DialogMixin:SetCancelText(text)
	if self.CancelButton and self.CancelButton.SetLabel then
		self.CancelButton:SetLabel(text or "Cancel")
	end
end

function DialogMixin:ShowDialog()
	self:Show()
	self:Raise()
	if self._blocker then
		self._blocker:Show()
	end
end

function DialogMixin:HideDialog()
	self:Hide()
	if self._blocker then
		self._blocker:Hide()
	end
end

function DialogMixin:Confirm()
	local cb = self._onConfirm
	self:HideDialog()
	if cb then
		cb(self)
	end
end

function DialogMixin:Cancel()
	local cb = self._onCancel
	self:HideDialog()
	if cb then
		cb(self)
	end
end

function DialogMixin:_RefreshTheme()
	if self.Message then
		Theme.ApplyVertexColor(self.Message, Theme.COLORS.INFO_TEXT)
	end
	if self.Title then
		Theme.ApplyVertexColor(self.Title, Theme.COLORS.TEXT)
	end
	if self.ConfirmButton and self.ConfirmButton._RefreshVisual then
		self.ConfirmButton:_RefreshVisual()
	end
	if self.CancelButton and self.CancelButton._RefreshVisual then
		self.CancelButton:_RefreshVisual()
	end
end

--- @param parent Frame|nil defaults to UIParent
--- @param opts table|nil {
---   title, message, confirmText, cancelText,
---   onConfirm, onCancel, width, height, name, hideCancel
--- }
function lib:CreateConfirmDialog(parent, opts)
	opts = opts or {}
	parent = parent or UIParent

	local width = opts.width or 360
	local height = opts.height or 180

	local blocker = CreateFrame("Button", nil, parent)
	blocker:SetAllPoints(parent)
	blocker:SetFrameStrata("FULLSCREEN_DIALOG")
	blocker:SetFrameLevel(490)
	blocker:EnableMouse(true)
	blocker:Hide()
	local dim = self:CreateColorTexture(blocker, { r = 0, g = 0, b = 0, a = 0.45 }, "BACKGROUND")
	dim:SetAllPoints()

	local frame = self:CreatePanel(parent, {
		name = opts.name,
		title = opts.title or "Confirm",
		width = width,
		height = height,
		frameStrata = "FULLSCREEN_DIALOG",
	})
	frame:SetFrameLevel(500)
	frame:SetPoint("CENTER")
	frame:EnableMouse(true)
	frame:Hide()
	frame._lib = self
	frame._onConfirm = opts.onConfirm
	frame._onCancel = opts.onCancel
	frame._blocker = blocker

	local message = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	message:SetPoint("TOPLEFT", Theme.LAYOUT.LARGE_PADDING or 20, -48)
	message:SetPoint("TOPRIGHT", -(Theme.LAYOUT.LARGE_PADDING or 20), -48)
	message:SetJustifyH("LEFT")
	message:SetJustifyV("TOP")
	message:SetWordWrap(true)
	message:SetText(opts.message or "")
	Theme.ApplyVertexColor(message, Theme.COLORS.INFO_TEXT)
	frame.Message = message

	local btnW = 110
	local confirm = self:CreateButton(frame, {
		text = opts.confirmText or "OK",
		width = btnW,
		variant = "active",
		onClick = function()
			frame:Confirm()
		end,
	})
	confirm:SetPoint("BOTTOMRIGHT", -(Theme.LAYOUT.PADDING or 10), Theme.LAYOUT.PADDING or 10)
	frame.ConfirmButton = confirm

	if not opts.hideCancel then
		local cancel = self:CreateButton(frame, {
			text = opts.cancelText or "Cancel",
			width = btnW,
			onClick = function()
				frame:Cancel()
			end,
		})
		cancel:SetPoint("RIGHT", confirm, "LEFT", -8, 0)
		frame.CancelButton = cancel
	end

	blocker:SetScript("OnClick", function()
		frame:Cancel()
	end)

	frame:SetScript("OnKeyDown", function(self, key)
		if key == "ESCAPE" then
			self:Cancel()
		end
	end)
	if frame.SetPropagateKeyboardInput then
		frame:SetPropagateKeyboardInput(false)
	end
	frame:EnableKeyboard(true)

	frame:SetScript("OnShow", function(self)
		if self._blocker then
			self._blocker:Show()
		end
	end)
	frame:SetScript("OnHide", function(self)
		if self._blocker then
			self._blocker:Hide()
		end
	end)

	for k, v in pairs(DialogMixin) do
		frame[k] = v
	end

	if self.RegisterThemeable then
		self:RegisterThemeable(frame)
	end

	return frame
end
