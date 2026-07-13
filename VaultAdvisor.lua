local ADDON_NAME, NS = ...

local vaultPopup = nil
local vaultScanRunner = nil

local function cancelVaultScan()
  if vaultScanRunner then
    vaultScanRunner.cancelled = true
    vaultScanRunner = nil
  end
end

local function positionVaultPopup()
  if not vaultPopup or not vaultPopup:IsShown() then
    return
  end
  if WeeklyRewardsFrame and WeeklyRewardsFrame:IsShown() then
    vaultPopup:ClearAllPoints()
    vaultPopup:SetPoint("TOPLEFT", WeeklyRewardsFrame, "TOPRIGHT", 12, -24)
  else
    vaultPopup:ClearAllPoints()
    vaultPopup:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
  end
end

local function syncVaultPopupHint(hasTrinketRewards)
  if not vaultPopup or not vaultPopup.swapHint then
    return
  end
  local hint = NS.MSG_VAULT_SWAP_HINT
  if hasTrinketRewards then
    hint = hint .. " " .. NS.MSG_VAULT_TRINKET_DISCLAIMER
  end
  vaultPopup.swapHint:SetText(hint)
end

local function setVaultPopupBody(text, r, g, b)
  if not vaultPopup or not vaultPopup.bodyText then
    return
  end
  vaultPopup.bodyText:SetText(text or "")
  vaultPopup.bodyText:SetTextColor(r or 0.85, g or 0.85, b or 0.9)
  if vaultPopup.resultFrame then
    vaultPopup.resultFrame:Hide()
  end
  if vaultPopup.pickNote then
    vaultPopup.pickNote:Show()
  end
end

local function showVaultPopupResult(row)
  if not vaultPopup or not vaultPopup.resultFrame then
    return
  end
  vaultPopup.bodyText:SetText("")
  vaultPopup.resultFrame:Show()

  local link = row.link
  if vaultPopup.resultIcon then
    if link then
      vaultPopup.resultIcon:SetTexture(GetItemIcon(link))
      vaultPopup.resultIcon:Show()
    else
      vaultPopup.resultIcon:Hide()
    end
  end

  local lr, lg, lb = NS.getItemQualityRgb(row.quality)
  if vaultPopup.resultName then
    vaultPopup.resultName:SetText(row.name or "?")
    vaultPopup.resultName:SetTextColor(lr, lg, lb)
  end
  if vaultPopup.resultSlot then
    vaultPopup.resultSlot:SetText(row.slot_label or "")
    vaultPopup.resultSlot:SetTextColor(0.55, 0.58, 0.65)
  end
  if vaultPopup.pickNote then
    vaultPopup.pickNote:Hide()
  end
  if vaultPopup.resultDelta then
    if row.dps_delta ~= nil then
      vaultPopup.resultDelta:SetText(NS.formatDelta(row.dps_delta) .. " DPS")
      NS.setDpsDeltaTextColor(vaultPopup.resultDelta, row.dps_delta)
    else
      vaultPopup.resultDelta:SetText("-")
      vaultPopup.resultDelta:SetTextColor(0.5, 0.5, 0.55)
    end
  end
end

local function ensureVaultPopup()
  if vaultPopup then
    return vaultPopup
  end

  local f = CreateFrame("Frame", "MrMythicalVaultAdvisorPopup", UIParent, "BackdropTemplate")
  f:SetSize(300, 132)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  f:SetBackdropColor(0.08, 0.07, 0.12, 0.97)
  f:SetBackdropBorderColor(0.55, 0.35, 0.85, 1)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12)
  title:SetText("Great Vault")
  title:SetTextColor(0.9, 0.78, 1)

  local brand = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  brand:SetPoint("TOPRIGHT", f, "TOPRIGHT", -36, -14)
  brand:SetText(NS.BRAND)
  brand:SetTextColor(0.5, 0.52, 0.58)

  local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
  closeBtn:SetScript("OnClick", function()
    f:Hide()
  end)

  local swapHint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  swapHint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  swapHint:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  swapHint:SetJustifyH("LEFT")
  swapHint:SetWordWrap(true)
  swapHint:SetText(NS.MSG_VAULT_SWAP_HINT)
  swapHint:SetTextColor(0.62, 0.64, 0.72)
  f.swapHint = swapHint

  local bodyText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  bodyText:SetPoint("TOPLEFT", swapHint, "BOTTOMLEFT", 0, -8)
  bodyText:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  bodyText:SetJustifyH("LEFT")
  bodyText:SetWordWrap(true)
  f.bodyText = bodyText

  local resultFrame = CreateFrame("Frame", nil, f)
  resultFrame:SetPoint("TOPLEFT", swapHint, "BOTTOMLEFT", 0, -6)
  resultFrame:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  resultFrame:SetHeight(52)
  resultFrame:Hide()
  f.resultFrame = resultFrame

  local resultIcon = resultFrame:CreateTexture(nil, "ARTWORK")
  resultIcon:SetSize(40, 40)
  resultIcon:SetPoint("TOPLEFT", resultFrame, "TOPLEFT", 0, 0)
  f.resultIcon = resultIcon

  local resultName = resultFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  resultName:SetPoint("TOPLEFT", resultIcon, "TOPRIGHT", 8, -2)
  resultName:SetPoint("RIGHT", resultFrame, "RIGHT", 0, 0)
  resultName:SetJustifyH("LEFT")
  resultName:SetWordWrap(true)
  f.resultName = resultName

  local resultSlot = resultFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  resultSlot:SetPoint("TOPLEFT", resultName, "BOTTOMLEFT", 0, -2)
  resultSlot:SetJustifyH("LEFT")
  f.resultSlot = resultSlot

  local resultDelta = resultFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  resultDelta:SetPoint("LEFT", resultSlot, "RIGHT", 8, 0)
  resultDelta:SetJustifyH("LEFT")
  f.resultDelta = resultDelta

  local advisorBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  advisorBtn:SetSize(130, 22)
  advisorBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
  advisorBtn:SetText("Gearing Dashboard")
  advisorBtn:SetScript("OnClick", function()
    NS.openGearAdvisor()
  end)
  f.advisorBtn = advisorBtn

  local pickNote = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  pickNote:SetPoint("BOTTOMLEFT", advisorBtn, "TOPLEFT", 0, 4)
  pickNote:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  pickNote:SetJustifyH("LEFT")
  pickNote:SetWordWrap(true)
  pickNote:SetText(NS.MSG_VAULT_PICK_ONE)
  pickNote:SetTextColor(0.55, 0.58, 0.65)
  f.pickNote = pickNote

  vaultPopup = f
  return f
end

local function finishVaultPopupScan(runner, rows, errors, collectNote, hasTrinketRewards)
  if vaultScanRunner ~= runner then
    return
  end
  vaultScanRunner = nil

  if not vaultPopup or not vaultPopup:IsShown() then
    return
  end

  syncVaultPopupHint(hasTrinketRewards)

  if collectNote and #rows == 0 then
    setVaultPopupBody(collectNote, 0.85, 0.55, 0.55)
    return
  end

  if #rows == 0 then
    if hasTrinketRewards then
      setVaultPopupBody(NS.MSG_VAULT_TRINKET_ONLY, 0.75, 0.68, 0.45)
    else
      setVaultPopupBody(NS.MSG_VAULT_NO_SCORABLE, 0.85, 0.55, 0.55)
    end
    if errors and errors > 0 then
      vaultPopup.bodyText:SetText((vaultPopup.bodyText:GetText() or "") .. string.format(NS.MSG_VAULT_SCORE_ERRORS, errors))
    end
    return
  end

  showVaultPopupResult(rows[1])
  if errors and errors > 0 then
    vaultPopup.bodyText:SetText(string.format(NS.MSG_VAULT_UNSCORED, errors))
    vaultPopup.bodyText:SetTextColor(0.75, 0.6, 0.45)
  end
end

local function startVaultPopupScan()
  cancelVaultScan()

  if not NS.isGreatVaultFrameOpen() then
    return
  end

  local popup = ensureVaultPopup()
  popup:Show()
  positionVaultPopup()

  if not NS.profileDetectionDoneRef[1] or #NS.active_spec_keys == 0 then
    NS.detectAndCacheProfiles()
  end
  local specKey = NS.getActiveProfileKey()
  if not specKey then
    setVaultPopupBody(NS.MSG_NO_PROFILE_ACTION, 1, 0.5, 0.5)
    return
  end

  local refs, collectNote = NS.collectVaultRewardRefs()
  local hasTrinketRewards = false
  local scoreableRefs = {}
  for _, ref in ipairs(refs or {}) do
    local isTrinket = (ref.link and NS.isTrinketLink(ref.link))
      or (ref.preview_link and NS.isTrinketLink(ref.preview_link))
    if isTrinket then
      hasTrinketRewards = true
    else
      table.insert(scoreableRefs, ref)
    end
  end

  syncVaultPopupHint(hasTrinketRewards)

  if #scoreableRefs == 0 then
    finishVaultPopupScan(nil, {}, 0, collectNote, hasTrinketRewards)
    return
  end

  setVaultPopupBody(NS.MSG_VAULT_SCORING, 0.95, 0.85, 0.45)

  local runner = {
    cancelled = false,
    specKey = specKey,
    hasTrinketRewards = hasTrinketRewards,
    collectNote = collectNote,
  }
  vaultScanRunner = runner
  runner.scoreSession = NS.createGearRefScoreSession(scoreableRefs, specKey, {
    sources = { vault = true },
    upgrades_only = false,
  })
  runner.scoreTotal = #scoreableRefs

  local function pumpScore()
    if vaultScanRunner ~= runner or runner.cancelled or not popup:IsShown() then
      return
    end
    local perf = NS.getScanPerformanceSettings()
    local session = runner.scoreSession
    local resumes = math.max(1, math.floor(perf.resumes_per_pump or 1))
    for _ = 1, resumes do
      if session.index > runner.scoreTotal then
        break
      end
      local _, _, waitingForItemData = NS.scoreGearRefSessionStep(session, perf.score_batch)
      if waitingForItemData then
        break
      end
    end
    local scored = math.min(session.index - 1, runner.scoreTotal)
    if session.index <= runner.scoreTotal then
      setVaultPopupBody(string.format(
        "%s %s/%s",
        NS.MSG_VAULT_SCORING,
        scored,
        runner.scoreTotal
      ), 0.95, 0.85, 0.45)
      NS.scheduleScanPump(perf.batch_delay_sec, pumpScore)
      return
    end
    local rows, errors = NS.finalizeGearRefScoreSession(session)
    finishVaultPopupScan(runner, rows, errors, runner.collectNote, runner.hasTrinketRewards)
  end

  NS.scheduleScanPump(0, pumpScore)
end

local function onVaultFrameShow()
  C_Timer.After(0.05, function()
    if NS.isGreatVaultFrameOpen() then
      startVaultPopupScan()
    end
  end)
end

local function onVaultFrameHide()
  cancelVaultScan()
  if vaultPopup then
    vaultPopup:Hide()
  end
end

function NS.setupVaultAdvisor()
  if not WeeklyRewardsFrame or WeeklyRewardsFrame.MrMythicalVaultAdvisorHooked then
    return
  end
  WeeklyRewardsFrame:HookScript("OnShow", onVaultFrameShow)
  WeeklyRewardsFrame:HookScript("OnHide", onVaultFrameHide)
  WeeklyRewardsFrame.MrMythicalVaultAdvisorHooked = true
  if WeeklyRewardsFrame:IsShown() then
    onVaultFrameShow()
  end
end
