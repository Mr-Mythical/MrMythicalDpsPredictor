--[[
DataRow.lua - Multi-column list / table row
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)
local Theme = lib.Theme

local DataRowMixin = {}

local function applyTextColor(fs, color)
	if not fs or not color then
		return
	end
	if type(color) == "string" then
		local themeColor = Theme.COLORS[color]
		if themeColor then
			Theme.ApplyVertexColor(fs, themeColor)
		end
		return
	end
	if color.r then
		fs:SetTextColor(color.r, color.g or color.r, color.b or color.r, color.a or 1)
	elseif color[1] then
		fs:SetTextColor(color[1], color[2] or color[1], color[3] or color[1], color[4] or 1)
	end
end

function DataRowMixin:SetSelected(selected)
	self._selected = not not selected
	self:_Refresh()
end

function DataRowMixin:GetSelected()
	return self._selected
end

function DataRowMixin:SetEven(even)
	self._even = not not even
	self:_Refresh()
end

function DataRowMixin:GetColumn(index)
	return self.Columns and self.Columns[index]
end

function DataRowMixin:SetColumnText(index, text)
	local col = self:GetColumn(index)
	if not col then
		return
	end
	if col.Label then
		col.Label:SetText(text or "")
	elseif col.SetLabel then
		col:SetLabel(text or "")
	elseif col.SetText then
		col:SetText(text or "")
	end
end

function DataRowMixin:SetColumnTexture(index, texture)
	local col = self:GetColumn(index)
	if not col then
		return
	end
	local graphic = col.Graphic or col.Icon or col
	if graphic and graphic.SetTexture and texture then
		graphic:SetTexture(texture)
	end
end

function DataRowMixin:_Refresh()
	local bg = self.Background
	if not bg then
		return
	end
	if self._selected then
		Theme.ApplyColorTexture(bg, Theme.COLORS.BUTTON_BG_ACTIVE)
	elseif self._even then
		Theme.ApplyColorTexture(bg, Theme.COLORS.EVEN_ROW)
	else
		Theme.ApplyColorTexture(bg, Theme.COLORS.ODD_ROW)
	end
end

--- @param parent Frame
--- @param opts table|nil {
---   width, height, even, selected, name,
---   columns = {
---     { kind="icon", size, texture, borderColor },
---     { kind="text", text, width, justifyH, color, font },
---     { kind="button", text, width, height, onClick },
---   },
---   onClick, onEnter, onLeave,
--- }
function lib:CreateDataRow(parent, opts)
	opts = opts or {}
	local width = opts.width or 280
	local height = opts.height or Theme.LAYOUT.LARGE_ROW_HEIGHT or 30
	local columns = opts.columns or {}

	local row = CreateFrame("Button", opts.name, parent)
	row:SetSize(width, height)
	row._lib = self
	row._selected = not not opts.selected
	row._even = opts.even ~= false
	row.Columns = {}

	local bg = self:CreateColorTexture(row, Theme.COLORS.EVEN_ROW, "BACKGROUND")
	bg:SetAllPoints()
	row.Background = bg

	local x = 8
	local gap = 6
	for i, spec in ipairs(columns) do
		local kind = spec.kind or "text"
		local widget

		if kind == "icon" then
			local size = spec.size or Theme.LAYOUT.ICON_SIZE or 24
			local iconFrame = CreateFrame("Frame", nil, row)
			iconFrame:SetSize(size, size)
			iconFrame:SetPoint("LEFT", row, "LEFT", x, 0)

			if spec.borderColor then
				local border = iconFrame:CreateTexture(nil, "BACKGROUND")
				border:SetAllPoints()
				local c = spec.borderColor
				if c.r then
					border:SetColorTexture(c.r, c.g or c.r, c.b or c.r, c.a or 1)
				elseif c[1] then
					border:SetColorTexture(c[1], c[2] or c[1], c[3] or c[1], c[4] or 1)
				end
				iconFrame.Border = border
			end

			local tex = iconFrame:CreateTexture(nil, "OVERLAY")
			if spec.borderColor then
				tex:SetPoint("TOPLEFT", 1, -1)
				tex:SetPoint("BOTTOMRIGHT", -1, 1)
			else
				tex:SetAllPoints()
			end
			if spec.texture then
				tex:SetTexture(spec.texture)
			end
			iconFrame.Graphic = tex
			iconFrame.Icon = tex
			widget = iconFrame
			x = x + size + gap

		elseif kind == "button" then
			local btnW = spec.width or 60
			local btnH = spec.height or math.min(height - 6, Theme.LAYOUT.BUTTON_HEIGHT - 4)
			local btn = self:CreateButton(row, {
				text = spec.text or "",
				width = btnW,
				height = btnH,
				onClick = spec.onClick,
			})
			btn:SetPoint("LEFT", row, "LEFT", x, 0)
			widget = btn
			x = x + btnW + gap

		else -- text
			local colW = spec.width or 80
			local fs = row:CreateFontString(nil, "OVERLAY", spec.font or "GameFontHighlightSmall")
			fs:SetPoint("LEFT", row, "LEFT", x, 0)
			fs:SetWidth(colW)
			fs:SetJustifyH(spec.justifyH or "LEFT")
			fs:SetWordWrap(false)
			fs:SetText(spec.text or "")
			if spec.color then
				applyTextColor(fs, spec.color)
			else
				Theme.ApplyVertexColor(fs, Theme.COLORS.TEXT)
			end
			local holder = CreateFrame("Frame", nil, row)
			holder:SetSize(colW, height)
			holder:SetPoint("LEFT", row, "LEFT", x, 0)
			holder.Label = fs
			fs:SetParent(holder)
			fs:ClearAllPoints()
			fs:SetAllPoints(holder)
			fs:SetJustifyH(spec.justifyH or "LEFT")
			widget = holder
			x = x + colW + gap
		end

		row.Columns[i] = widget
	end

	row:SetScript("OnClick", function(self)
		if opts.onClick then
			opts.onClick(self)
		end
	end)
	row:SetScript("OnEnter", function(self)
		if not self._selected then
			Theme.ApplyColorTexture(self.Background, Theme.COLORS.BUTTON_BG_HOVER)
		end
		if opts.onEnter then
			opts.onEnter(self)
		end
	end)
	row:SetScript("OnLeave", function(self)
		self:_Refresh()
		if opts.onLeave then
			opts.onLeave(self)
		end
	end)

	for k, v in pairs(DataRowMixin) do
		row[k] = v
	end
	row:_Refresh()
	return row
end
