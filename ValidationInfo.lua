local ADDON_NAME, NS = ...

local function validationData()
  if NS.Model and NS.Model.validation then
    return NS.Model.validation
  end
  return _G.MrMythicalValidationExport
end

function NS.hasValidationData()
  local v = validationData()
  return v and v.has_data == true
end

function NS.getValidationRun()
  local v = validationData()
  if not v or not v.has_data then
    return nil
  end
  return v.overall, v
end

function NS.getValidationForProfile(profileKey)
  local v = validationData()
  if not v or not v.has_data then
    return nil, nil
  end
  if profileKey and v.by_spec and v.by_spec[profileKey] then
    return v.by_spec[profileKey], v
  end
  return nil, v
end

local function fmtPct(value)
  if value == nil then
    return "—"
  end
  return string.format("%.0f%%", value)
end

local function fmtErrorPct(value, digits)
  if value == nil then
    return "—"
  end
  return string.format("%." .. tostring(digits or 2) .. "f%%", value)
end

local function pctColor(value)
  if value == nil then
    return 0.82, 0.84, 0.88
  end
  if value >= 95 then
    return 0.45, 0.95, 0.55
  end
  if value >= 85 then
    return 1, 0.92, 0.55
  end
  return 0.95, 0.55, 0.45
end

function NS.showValidationTooltip(owner, profileKey)
  if not NS.hasValidationData() then
    return
  end
  local profileRow, v = NS.getValidationForProfile(profileKey)
  local overall = v.overall or {}
  local displayRow = profileRow or overall
  local scopeLabel = "all specs in this model"
  if profileRow and profileKey then
    scopeLabel = (NS.getProfileLabel and NS.getProfileLabel(profileKey)) or profileKey
  end

  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText("Prediction accuracy", 1, 0.92, 0.55)
  GameTooltip:AddLine(
    "Before this model shipped, we ran fresh independent sims on realistic gear swaps the model never trained on. These numbers show how closely in-game predictions match those sims.",
    0.82, 0.84, 0.88, true
  )

  GameTooltip:AddLine(" ", 1, 1, 1)
  GameTooltip:AddLine("Results for: " .. scopeLabel, 0.7, 0.72, 0.76)

  GameTooltip:AddLine(" ", 1, 1, 1)
  GameTooltip:AddDoubleLine(
    "Upgrade picks",
    fmtPct(displayRow.upgrade_picks_pct),
    0.75, 0.78, 0.82, 1, 0.92, 0.55
  )
  GameTooltip:AddLine(
    "Hover a candidate piece: does the addon call the same winner as a full sim? Pairs too close for the reference sim to reliably decide are skipped.",
    0.65, 0.67, 0.7, true
  )

  GameTooltip:AddLine(" ", 1, 1, 1)
  GameTooltip:AddDoubleLine(
    "Gap error",
    fmtErrorPct(displayRow.upgrade_size_error_pct, 2),
    0.75, 0.78, 0.82, 1, 1, 1
  )
  GameTooltip:AddLine(
    "How far off the predicted DPS difference is from a full sim — the +X DPS you see when comparing two items. Shown as % of your DPS.",
    0.65, 0.67, 0.7, true
  )

  GameTooltip:AddLine(" ", 1, 1, 1)
  GameTooltip:AddDoubleLine(
    "DPS read error",
    fmtErrorPct(displayRow.dps_read_error_pct, 2),
    0.75, 0.78, 0.82, 1, 1, 1
  )
  GameTooltip:AddLine(
    "At a single gear profile (no item swap), how far off is the predicted DPS number vs a full sim?",
    0.65, 0.67, 0.7, true
  )

  GameTooltip:Show()
end

local function bindValidationTooltip(frame, profileKeyFn)
  frame:EnableMouse(true)
  frame:SetScript("OnEnter", function(self)
    NS.showValidationTooltip(self, profileKeyFn and profileKeyFn())
  end)
  frame:SetScript("OnLeave", GameTooltip_Hide)
end

local function pctHex(value)
  local r, g, b = pctColor(value)
  return string.format("|cff%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

local function formatCompactMetrics(row)
  local picks = fmtPct(row.upgrade_picks_pct)
  local gap = fmtErrorPct(row.upgrade_size_error_pct, 2)
  local dps = fmtErrorPct(row.dps_read_error_pct, 2)
  return string.format(
    "Prediction accuracy · %s%s|r picks · %s gap · %s DPS",
    pctHex(row.upgrade_picks_pct),
    picks,
    gap,
    dps
  )
end

function NS.refreshValidationChrome(parentFrame)
  if not parentFrame or not parentFrame.validationBlock then
    return
  end
  local block = parentFrame.validationBlock
  if not NS.hasValidationData() then
    block:Hide()
    if parentFrame.profileSectionLabel and parentFrame.validationAnchor then
      parentFrame.profileSectionLabel:ClearAllPoints()
      parentFrame.profileSectionLabel:SetPoint("TOPLEFT", parentFrame.validationAnchor, "BOTTOMLEFT", 0, -4)
    end
    return
  end
  block:Show()

  local profileKey = NS.getActiveProfileKey and NS.getActiveProfileKey()
  local profileRow, v = NS.getValidationForProfile(profileKey)
  local overall = v.overall or {}
  local row = profileRow or overall

  if block.metricsText then
    block.metricsText:SetText(formatCompactMetrics(row))
  end

  if parentFrame.profileSectionLabel and parentFrame.validationAnchor then
    parentFrame.profileSectionLabel:ClearAllPoints()
    parentFrame.profileSectionLabel:SetPoint("TOPLEFT", block, "BOTTOMLEFT", 0, -4)
  end
end

function NS.attachValidationButton(parentFrame, anchorFrame)
  if not parentFrame or not anchorFrame or parentFrame.validationBlock then
    return
  end

  local blockWidth = math.max(300, anchorFrame:GetWidth() or 300)
  local block = CreateFrame("Frame", nil, parentFrame)
  block:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
  block:SetSize(blockWidth, 18)
  parentFrame.validationBlock = block

  local infoBtn = CreateFrame("Button", nil, block)
  infoBtn:SetSize(14, 14)
  infoBtn:SetPoint("LEFT", block, "LEFT", 0, 0)
  infoBtn:SetNormalTexture("Interface\\Common\\help-i")
  infoBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  bindValidationTooltip(infoBtn, function()
    return NS.getActiveProfileKey and NS.getActiveProfileKey()
  end)
  block.infoBtn = infoBtn

  local metricsText = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  metricsText:SetPoint("LEFT", infoBtn, "RIGHT", 4, 0)
  metricsText:SetPoint("RIGHT", block, "RIGHT", 0, 0)
  metricsText:SetJustifyH("LEFT")
  metricsText:SetText("Prediction accuracy · —")
  metricsText:SetTextColor(0.72, 0.74, 0.78)
  block.metricsText = metricsText

  NS.refreshValidationChrome(parentFrame)
end
