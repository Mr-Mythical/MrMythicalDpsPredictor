local ADDON_NAME, NS = ...

local advisorFrame = nil
local advisorRows = {}
local advisorScanRunner = nil
local profileCallout = nil
local currentMode = "bags"
local upgradeRows = {}
local crestRows = {}
local crestAllRows = {}
local crestSpendPlan = nil
local crestPlanSummary = nil
local candidateRows = {}
local loadoutRows = {}
local loadoutSummary = nil
local candidatesBySlot = nil
local flatRefs = nil
local scanComplete = false
local estimatedCombinations = nil
local comboEstimateRunner = nil
local comboEstimateToken = 0
local comboEstimateScheduleToken = 0
local lastComboSelectionKey = nil
local comboCountInProgress = false
local comboCountProgress = nil
local statusNote = nil
local lootControls = NS.createLootControlState({
  lootUpgradeConfigKey = "gear_advisor_loot_upgrade",
  instanceConfigKey = "gear_advisor_instance_id",
})
local loadoutVaultWinnerKey = nil
local lastLoadoutScanOptsKey = nil
local loadoutEquipState = {}
local pendingEquips = {}
local advisorScanScheduleToken = 0
local modeScanCache = {}
local isAdvisorScanActive
local isLoadoutSearchActive

local VAULT_BORDER = { 0.62, 0.38, 0.95 }
local VAULT_BORDER_SELECTED = { 0.82, 0.58, 1 }
local VAULT_WINNER_BORDER = { 1, 0.85, 0.25 }

local GA_WIDTH = 920
local GA_HEIGHT = 700
local GA_PADDING = 14
local GA_SCROLL_INSET = 42
local GA_ACTION_H = 56
local GA_STATUS_H = 36
local GA_HEADER_H = 26
local GA_LOADOUT_CURRENT_X = 100
local GA_LOADOUT_REC_X = 380
local GA_LOADOUT_ITEM_ICON = 22
local GA_CREST_CURRENT_X = 100
local GA_CREST_STEP_X = 248
local GA_CREST_STEP_WIDTH = 178
local GA_CREST_AFTER_X = GA_CREST_STEP_X + GA_CREST_STEP_WIDTH + 8
local GA_CREST_ROW_H = 52
local GA_CREST_DPS_RIGHT = 8
local GA_CREST_DPS_WIDTH = 120
local GA_CREST_COST_WIDTH = 140
local GA_CREST_COL_GAP = 10
local GA_CREST_COST_RIGHT = GA_CREST_DPS_RIGHT + GA_CREST_DPS_WIDTH + GA_CREST_COL_GAP
local LOOT_COLLECT_BATCH = 2

local function setupAdvisorCheckbox(check, label, allowWrap)
  check:SetSize(24, 24)
  local text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("LEFT", check, "RIGHT", 4, 0)
  text:SetText(label)
  if allowWrap then
    text:SetPoint("TOP", check, "TOP", 4, 0)
    text:SetPoint("RIGHT", check:GetParent(), "RIGHT", 0, 0)
    text:SetWordWrap(true)
    text:SetJustifyH("LEFT")
  else
    text:SetPoint("TOP", check, "TOP", 4, 0)
    text:SetPoint("BOTTOM", check, "BOTTOM", 4, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("MIDDLE")
  end
  check.text = text
end

local GA_ICON_SIZE = 32
local GA_ICON_SPACING = 6
local GA_SLOT_COL_WIDTH = 100
local GA_ICONS_COL_X = 112

local SOURCE_LABELS = {
  bag = "Bags",
  loot = "Dungeons & Raids",
  vault = "Great Vault",
}

local function addAdvisorTooltipLine(lines, text, r, g, b)
  lines[#lines + 1] = { text = text, r = r, g = g, b = b }
end

local function buildCandidateTooltipExtraLines(cand, iconInfo, isVault, isVaultWinner, slotId)
  local lines = {}
  if not iconInfo.is_equipped then
    local sourceLabel = cand.source_label or SOURCE_LABELS[cand.source] or cand.source
    if isVault then
      addAdvisorTooltipLine(lines, sourceLabel or "Great Vault", 0.75, 0.65, 0.95)
      addAdvisorTooltipLine(lines, NS.MSG_VAULT_PICK_ONE, 0.55, 0.6, 0.7)
      if isVaultWinner then
        addAdvisorTooltipLine(lines, NS.MSG_VAULT_LOADOUT_WINNER, 1, 0.88, 0.45)
      end
    elseif sourceLabel then
      addAdvisorTooltipLine(lines, sourceLabel, 0.65, 0.7, 0.8)
    end
    if cand.dps_delta ~= nil then
      local dpsLine = NS.formatDelta(cand.dps_delta) .. " DPS"
      if cand.weapon_pair_scored and (slotId == 16 or slotId == 17) then
        dpsLine = dpsLine .. " (1H pair)"
      end
      addAdvisorTooltipLine(lines, dpsLine, NS.getDpsDeltaColor(cand.dps_delta))
    end
  elseif cand.source_label or cand.source == "equipped" then
    addAdvisorTooltipLine(lines, "Currently equipped", 0.95, 0.82, 0.25)
  end
  if iconInfo.is_selected then
    addAdvisorTooltipLine(lines, "Included in loadout search", 0.2, 0.85, 0.25)
  elseif iconInfo.is_equipped_duplicate then
    addAdvisorTooltipLine(lines, "Same as equipped (ilvl & track)", 0.55, 0.55, 0.6)
    addAdvisorTooltipLine(lines, "Not included in loadout search", 0.55, 0.55, 0.6)
  else
    addAdvisorTooltipLine(lines, "Click to include in loadout search", 0.7, 0.2, 0.2)
  end
  return lines
end

local MODE_TABS = {
  { id = "bags", label = "Bags" },
  { id = "loot", label = "Dungeons & Raids" },
  { id = "crests", label = "Crest Upgrades" },
}

local function isLoadoutMode(modeId)
  modeId = modeId or currentMode
  return modeId == "bags" or modeId == "loot" or modeId == "loadout"
end

local function normalizeAdvisorMode(modeId)
  if modeId == "loadout" then
    return "bags"
  end
  if modeId == "bags" or modeId == "loot" or modeId == "crests" then
    return modeId
  end
  return "bags"
end

local function resetLoadoutEquipState()
  wipe(loadoutEquipState)
  wipe(pendingEquips)
end

local function resetLoadoutScanState()
  scanComplete = false
  estimatedCombinations = nil
  loadoutSummary = nil
  loadoutRows = {}
  upgradeRows = {}
  candidateRows = {}
  candidatesBySlot = nil
  flatRefs = nil
  statusNote = nil
  loadoutVaultWinnerKey = nil
  lastLoadoutScanOptsKey = nil
  resetLoadoutEquipState()
end

local function clearModeScanCache()
  wipe(modeScanCache)
end

local function saveModeScanSnapshot(modeId)
  modeId = normalizeAdvisorMode(modeId)
  local specKey = NS.getActiveProfileKey()
  if not specKey then
    modeScanCache[modeId] = nil
    return
  end
  if modeId == "crests" then
    if isAdvisorScanActive() and currentMode == "crests" then
      return
    end
    modeScanCache[modeId] = {
      specKey = specKey,
      crestRows = crestRows,
      crestAllRows = crestAllRows,
      crestSpendPlan = crestSpendPlan,
      crestPlanSummary = crestPlanSummary,
    }
    return
  end
  if isLoadoutMode(modeId) then
    if isAdvisorScanActive() and not scanComplete then
      return
    end
    if not scanComplete and not candidatesBySlot then
      return
    end
    modeScanCache[modeId] = {
      specKey = specKey,
      scanComplete = scanComplete,
      estimatedCombinations = estimatedCombinations,
      candidatesBySlot = candidatesBySlot,
      flatRefs = flatRefs,
      upgradeRows = upgradeRows,
      candidateRows = candidateRows,
      loadoutSummary = loadoutSummary,
      loadoutRows = loadoutRows,
      loadoutVaultWinnerKey = loadoutVaultWinnerKey,
      lastLoadoutScanOptsKey = lastLoadoutScanOptsKey,
      lastComboSelectionKey = lastComboSelectionKey,
      statusNote = statusNote,
    }
  end
end

local function restoreModeScanSnapshot(modeId)
  modeId = normalizeAdvisorMode(modeId)
  local snap = modeScanCache[modeId]
  local specKey = NS.getActiveProfileKey()
  if not snap or snap.specKey ~= specKey then
    return false
  end
  if modeId == "crests" then
    crestRows = snap.crestRows or {}
    crestAllRows = snap.crestAllRows or {}
    crestSpendPlan = snap.crestSpendPlan
    crestPlanSummary = snap.crestPlanSummary
    return true
  end
  scanComplete = snap.scanComplete == true
  estimatedCombinations = snap.estimatedCombinations
  candidatesBySlot = snap.candidatesBySlot
  flatRefs = snap.flatRefs
  upgradeRows = snap.upgradeRows or {}
  candidateRows = snap.candidateRows or {}
  loadoutSummary = snap.loadoutSummary
  loadoutRows = snap.loadoutRows or {}
  loadoutVaultWinnerKey = snap.loadoutVaultWinnerKey
  lastLoadoutScanOptsKey = snap.lastLoadoutScanOptsKey
  lastComboSelectionKey = snap.lastComboSelectionKey
  statusNote = snap.statusNote
  return true
end

local function modeScanCacheHasResults(modeId)
  modeId = normalizeAdvisorMode(modeId)
  local snap = modeScanCache[modeId]
  local specKey = NS.getActiveProfileKey()
  if not snap or snap.specKey ~= specKey then
    return false
  end
  if modeId == "crests" then
    return snap.crestAllRows and #snap.crestAllRows > 0
  end
  return snap.scanComplete == true
end

local getScanOpts
local syncAdvisorStatusText
local countLoadoutEquipsByState
local syncLoadoutEquipStatusText

local function getVaultKeyFromLoadoutRow(row)
  if not row or row.source ~= "vault" then
    return nil
  end
  if row.key then
    return row.key
  end
  if not row.link then
    return nil
  end
  local itemID = tonumber(row.link:match("item:(%d+)"))
  if not itemID then
    return nil
  end
  local actId = row.vault_activity_id or 0
  return string.format("vault:%s:%d", tostring(actId), itemID)
end

local function findLoadoutVaultWinnerRow()
  for _, row in ipairs(loadoutRows) do
    if row.is_upgrade and row.source == "vault" then
      return row
    end
  end
  return nil
end

local function setLoadoutVaultWinnerFromRows()
  loadoutVaultWinnerKey = nil
  local winner = findLoadoutVaultWinnerRow()
  if winner then
    loadoutVaultWinnerKey = getVaultKeyFromLoadoutRow(winner)
  end
end

local function addLoadoutItemBlock(row, startX, link, name, quality, maxNameWidth, muted, opts)
  opts = opts or {}
  local iconSize = GA_LOADOUT_ITEM_ICON
  local iconBtn
  if opts.vaultBorder then
    iconBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
    iconBtn:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8X8",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 8, edgeSize = 10,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    local br, bg, bb = VAULT_BORDER[1], VAULT_BORDER[2], VAULT_BORDER[3]
    if opts.vaultWinner then
      br, bg, bb = VAULT_WINNER_BORDER[1], VAULT_WINNER_BORDER[2], VAULT_WINNER_BORDER[3]
    end
    iconBtn:SetBackdropBorderColor(br, bg, bb, 1)
    iconBtn:SetBackdropColor(0, 0, 0, 0.35)
    iconSize = GA_LOADOUT_ITEM_ICON + 4
  else
    iconBtn = CreateFrame("Button", nil, row)
  end
  iconBtn:SetSize(iconSize, iconSize)
  iconBtn:SetPoint("LEFT", row, "LEFT", startX, 0)
  local tex = iconBtn:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints(iconBtn)
  if link then
    local iconTexture = GetItemIcon(link)
    if iconTexture then
      tex:SetTexture(iconTexture)
    end
  end
  if muted then
    tex:SetVertexColor(0.7, 0.7, 0.7, 1)
  end

  local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  nameText:SetPoint("LEFT", iconBtn, "RIGHT", 4, 0)
  nameText:SetWidth(maxNameWidth)
  nameText:SetJustifyH("LEFT")
  nameText:SetText(name or link or "-")
  local r, g, b = NS.getItemQualityRgb(quality)
  if muted then
    nameText:SetTextColor(0.65, 0.65, 0.7)
  else
    nameText:SetTextColor(r, g, b)
  end

  if opts.vaultWinner then
    local badge = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badge:SetPoint("LEFT", nameText, "RIGHT", 6, 0)
    badge:SetText("Vault pick")
    badge:SetTextColor(1, 0.88, 0.45)
  elseif opts.vaultBorder then
    local badge = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badge:SetPoint("LEFT", nameText, "RIGHT", 6, 0)
    badge:SetText("Vault")
    badge:SetTextColor(0.85, 0.7, 1)
  end

  if link then
    iconBtn:SetScript("OnClick", function()
      HandleModifiedItemClick(link)
    end)
    local function showItemTooltip(self)
      self.mrMythicalAdvisorItemTooltip = true
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(link)
    end
    iconBtn:SetScript("OnEnter", showItemTooltip)
    iconBtn:SetScript("OnLeave", function()
      iconBtn.mrMythicalAdvisorItemTooltip = nil
      GameTooltip:Hide()
    end)
    nameText:EnableMouse(true)
    nameText:SetScript("OnEnter", showItemTooltip)
    nameText:SetScript("OnLeave", function()
      nameText.mrMythicalAdvisorItemTooltip = nil
      GameTooltip:Hide()
    end)
  end
end

local updateScanProgressDisplay = function(text, color)
  NS.AdvisorScanProgress.updateDisplay(text, color)
end
local hideScanProgressPopup = function()
  NS.AdvisorScanProgress.hide()
end
local onAdvisorScanEnded = function(wasCancelled, completionMessage, completionColor)
  NS.AdvisorScanProgress.onScanEnded(wasCancelled, completionMessage, completionColor)
end
local setScanProgressBar = function(current, total)
  NS.AdvisorScanProgress.setBar(current, total)
end
local clearScanProgressBar = function()
  NS.AdvisorScanProgress.clearBar()
end
local startScanProgressTiming = function()
  NS.AdvisorScanProgress.startTiming()
end
local syncScanProgressModeButton = function()
  NS.AdvisorScanProgress.syncModeButton()
end
local syncActionButtons
local renderAdvisorRows
local isShowingLoadoutResults
local applyPostScanStatus

isAdvisorScanActive = function()
  return advisorScanRunner ~= nil and not advisorScanRunner.cancelled
end

isLoadoutSearchActive = function()
  return scanComplete and isLoadoutMode() and isAdvisorScanActive()
end

local function setStatusText(text, color)
  if advisorFrame and advisorFrame.summaryText and advisorFrame:IsShown() then
    advisorFrame.summaryText:SetText(text or "")
    if color then
      advisorFrame.summaryText:SetTextColor(color[1], color[2], color[3])
    elseif advisorScanRunner then
      advisorFrame.summaryText:SetTextColor(0.95, 0.85, 0.45)
    elseif loadoutSummary then
      advisorFrame.summaryText:SetTextColor(0.55, 1, 0.65)
    elseif scanComplete then
      advisorFrame.summaryText:SetTextColor(0.55, 1, 0.65)
    else
      advisorFrame.summaryText:SetTextColor(0.75, 0.9, 1)
    end
  end
  if isAdvisorScanActive() and updateScanProgressDisplay then
    updateScanProgressDisplay(text, color)
  end
end

local function isComboEstimateActive()
  return comboCountInProgress
end

local function cancelComboEstimate()
  if comboEstimateRunner then
    comboEstimateRunner.cancelled = true
    comboEstimateRunner = nil
  end
  comboCountInProgress = false
  comboCountProgress = nil
end

local function cancelAdvisorScan()
  if advisorScanRunner then
    if advisorScanRunner.lootRunner then
      advisorScanRunner.lootRunner.cancelled = true
    end
    advisorScanRunner.cancelled = true
  end
end

local function stopAdvisorScan()
  if not advisorScanRunner or advisorScanRunner.cancelled then
    return
  end
  advisorScanScheduleToken = advisorScanScheduleToken + 1
  local wasLoadoutSearch = scanComplete and isLoadoutMode() and not isShowingLoadoutResults()
  cancelAdvisorScan()
  advisorScanRunner = nil
  syncActionButtons()
  renderAdvisorRows()
  if wasLoadoutSearch then
    setStatusText("Loadout search cancelled.", { 0.95, 0.85, 0.45 })
    applyPostScanStatus()
    saveModeScanSnapshot(currentMode)
  elseif scanComplete then
    applyPostScanStatus()
  elseif isLoadoutMode() then
    setStatusText("Scan cancelled.", { 0.95, 0.85, 0.45 })
  elseif currentMode == "crests" then
    setStatusText("Scan cancelled.", { 0.95, 0.85, 0.45 })
  end
  local cancelMsg = wasLoadoutSearch and "Loadout search cancelled." or "Scan cancelled."
  onAdvisorScanEnded(true, cancelMsg, { 0.95, 0.85, 0.45 })
end

local runAdvisorScan
local runCrestScan
local scheduleAdvisorScan
local syncLootControls
local syncScanPerfControls
local toggleAdvisorScanPerformance
local syncUpgradeFilterControls
local syncCrestFilterControls
local updatePostScanStatusIfIdle
local refreshLoadoutComboEstimate

local function isVaultCandidate(cand)
  return cand and cand.source == "vault" and not cand.is_equipped_baseline
end

local function collectVaultCandidates()
  local vault = {}
  if not candidatesBySlot then
    return vault
  end
  local seen = {}
  for _, list in pairs(candidatesBySlot) do
    for _, cand in ipairs(list) do
      if isVaultCandidate(cand) and cand.key and cand.link and not seen[cand.key] then
        seen[cand.key] = true
        table.insert(vault, cand)
      end
    end
  end
  table.sort(vault, function(a, b)
    return (a.dps_delta or 0) > (b.dps_delta or 0)
  end)
  return vault
end

local function deselectOtherVaultCandidates(keepCand)
  if not keepCand or not keepCand.key then
    return
  end
  for _, cand in ipairs(collectVaultCandidates()) do
    if cand.key ~= keepCand.key then
      NS.setAdvisorCandidateSelected(cand, false)
    end
  end
end

local function syncVaultTrinketDisclaimer()
  if not advisorFrame or not advisorFrame.vaultStatusText then return end
  if currentMode ~= "bags" or not NS.isGreatVaultFrameOpen() then
    advisorFrame.vaultStatusText:Hide()
    return
  end
  advisorFrame.vaultStatusText:SetText(NS.MSG_VAULT_TRINKET_DISCLAIMER)
  advisorFrame.vaultStatusText:SetTextColor(0.75, 0.68, 0.45)
  advisorFrame.vaultStatusText:Show()
end

local function onVaultVisibilityChanged()
  syncVaultTrinketDisclaimer()
  if not advisorFrame or not advisorFrame:IsShown() or currentMode ~= "bags" then
    return
  end
  scheduleAdvisorScan()
end

local function setupVaultFrameHooks()
  if NS.setupVaultAdvisor then
    NS.setupVaultAdvisor()
  end
  if not WeeklyRewardsFrame or WeeklyRewardsFrame.MrMythicalAdvisorRescanHooked then
    return
  end
  WeeklyRewardsFrame:HookScript("OnShow", onVaultVisibilityChanged)
  WeeklyRewardsFrame:HookScript("OnHide", onVaultVisibilityChanged)
  WeeklyRewardsFrame:HookScript("OnEvent", function(_, event)
    if event == "WEEKLY_REWARDS_UPDATE" then
      onVaultVisibilityChanged()
    end
  end)
  WeeklyRewardsFrame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
  WeeklyRewardsFrame.MrMythicalAdvisorRescanHooked = true
end

local function syncModeTabs()
  if not advisorFrame or not advisorFrame.modeButtons then return end
  local tabsLocked = isLoadoutSearchActive()
  for modeId, btn in pairs(advisorFrame.modeButtons) do
    local label = modeId
    for _, mode in ipairs(MODE_TABS) do
      if mode.id == modeId then
        label = mode.label
        break
      end
    end
    if modeScanCacheHasResults(modeId) and modeId ~= currentMode then
      btn.text:SetText(label .. " •")
    else
      btn.text:SetText(label)
    end
    if modeId == currentMode then
      btn:SetBackdropColor(0.22, 0.24, 0.32, 1)
      btn.text:SetTextColor(1, 0.92, 0.55)
    else
      btn:SetBackdropColor(0.14, 0.14, 0.18, 0.9)
      btn.text:SetTextColor(0.75, 0.78, 0.85)
    end
    if tabsLocked then
      btn:Disable()
      if modeId ~= currentMode then
        btn.text:SetTextColor(0.45, 0.48, 0.52)
      end
    else
      btn:Enable()
    end
  end
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_mode = currentMode
end

local function syncModeUI()
  if not advisorFrame then return end

  syncLootControls()
  syncScanPerfControls()
  syncVaultTrinketDisclaimer()
  syncUpgradeFilterControls()
  syncCrestFilterControls()
  syncActionButtons()
end

local function applyCrestRowFilter()
  crestRows = {}
  for _, row in ipairs(crestAllRows) do
    if row.can_afford then
      table.insert(crestRows, row)
    end
  end
end

local function crestPlanIsActive()
  return crestSpendPlan ~= nil and #crestSpendPlan > 0
end

local function crestColumnRight(_listWidth, column)
  if column == "cost" then
    return -GA_CREST_COST_RIGHT
  end
  return -GA_CREST_DPS_RIGHT
end

local function crestItemNameWidth(listWidth)
  local iconPad = GA_LOADOUT_ITEM_ICON + 6
  local rightEdge = listWidth - GA_CREST_COST_RIGHT - GA_CREST_COST_WIDTH - GA_CREST_COL_GAP
  local afterNameMax = rightEdge - GA_CREST_AFTER_X - iconPad
  local currentNameMax = GA_CREST_STEP_X - GA_CREST_CURRENT_X - iconPad - 6
  return math.max(64, math.min(afterNameMax, currentNameMax))
end

local function refreshCrestChrome()
  if not advisorFrame then
    return
  end
  if advisorFrame.crestBalanceText then
    local balanceLine = NS.formatCrestBalancesLine and NS.formatCrestBalancesLine() or ""
    advisorFrame.crestBalanceText:SetText(balanceLine)
  end
end

syncCrestFilterControls = function()
  if not advisorFrame then return end
  local crestMode = currentMode == "crests"
  if advisorFrame.crestFilterFrame then
    advisorFrame.crestFilterFrame:SetShown(crestMode and not isAdvisorScanActive())
  end
  if advisorFrame.actionBar then
    advisorFrame.actionBar:SetHeight(GA_ACTION_H)
  end
  refreshCrestChrome()
end

syncUpgradeFilterControls = function()
  if not advisorFrame then return end
  if advisorFrame.upgradeFilterFrame then
    advisorFrame.upgradeFilterFrame:SetShown(
      isLoadoutMode() and currentMode ~= "crests"
      and not isShowingLoadoutResults() and not isAdvisorScanActive()
    )
  end
  local upgradesOn = MR_MYTHICAL_DPS_CONFIG.gear_advisor_upgrades_only == true
  if advisorFrame.sidegradeCheck then
    advisorFrame.sidegradeCheck:SetEnabled(upgradesOn)
    local r, g, b = 0.75, 0.78, 0.85
    if not upgradesOn then
      r, g, b = 0.45, 0.48, 0.52
    end
    advisorFrame.sidegradeCheck.text:SetTextColor(r, g, b)
  end
end

local function onUpgradeFilterChanged()
  lastComboSelectionKey = nil
  syncUpgradeFilterControls()
  NS.applyAdvisorSelectionDefaults(candidateRows, candidatesBySlot)
  renderAdvisorRows()
  if isLoadoutMode() then
    refreshLoadoutComboEstimate()
  end
end

local function selectMode(modeId)
  modeId = normalizeAdvisorMode(modeId)
  if currentMode == modeId then return end
  if isLoadoutSearchActive() then
    return
  end
  saveModeScanSnapshot(currentMode)
  local fromMode = currentMode
  cancelAdvisorScan()
  cancelComboEstimate()
  advisorScanRunner = nil
  if fromMode == "crests" or modeId == "crests" then
    if modeId ~= "crests" then
      crestSpendPlan = nil
      crestPlanSummary = nil
    end
  end
  currentMode = modeId
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_mode = modeId
  if not restoreModeScanSnapshot(modeId) then
    resetLoadoutScanState()
    crestRows = {}
    crestAllRows = {}
    if fromMode == "loot" and modeId == "bags" and NS.purgeStaleLootSelections then
      NS.purgeStaleLootSelections()
    end
  end
  syncModeTabs()
  syncModeUI()
  syncAdvisorStatusText()
  renderAdvisorRows()
  scheduleAdvisorScan()
end

syncLootControls = function()
  if not advisorFrame then return end
  if not isLoadoutMode() then
    if advisorFrame.instanceDropdown then advisorFrame.instanceDropdown:Hide() end
    if advisorFrame.ilvlDropdown then advisorFrame.ilvlDropdown:Hide() end
    if advisorFrame.lootHint then advisorFrame.lootHint:Hide() end
    return
  end
  local showLoot = currentMode == "loot"
  if advisorFrame.instanceDropdown then advisorFrame.instanceDropdown:SetShown(showLoot) end
  if advisorFrame.ilvlDropdown then advisorFrame.ilvlDropdown:SetShown(showLoot) end
  if advisorFrame.lootHint then advisorFrame.lootHint:SetShown(showLoot) end
end

syncScanPerfControls = function()
  if not advisorFrame then return end

  local loadoutSearch = isLoadoutSearchActive()
  local showPerfDropdown = isLoadoutMode() and currentMode ~= "crests"
    and scanComplete and not isAdvisorScanActive()
  local showPerfToggle = loadoutSearch
  local perfDropdown = advisorFrame.perfDropdown
  local perfToggleBtn = advisorFrame.perfToggleBtn
  local perfControl = nil

  if perfDropdown then
    perfDropdown:SetShown(showPerfDropdown)
    if showPerfDropdown then
      UIDropDownMenu_SetText(perfDropdown, NS.getScanPerformanceDropdownLabel())
      perfControl = perfDropdown
    end
  end
  if perfToggleBtn then
    perfToggleBtn:SetShown(showPerfToggle)
    if showPerfToggle then
      perfToggleBtn:SetText(NS.getScanPerformanceToggleButtonLabel())
      perfControl = perfToggleBtn
    end
  end
  syncScanProgressModeButton()

  local showPerfControls = showPerfDropdown or showPerfToggle
  local showLoot = isLoadoutMode() and currentMode == "loot"
  local actionBar = advisorFrame.actionBar
  local instanceDropdown = advisorFrame.instanceDropdown
  local ilvlDropdown = advisorFrame.ilvlDropdown
  local upgradeFilterFrame = advisorFrame.upgradeFilterFrame
  local findLoadoutBtn = advisorFrame.findLoadoutBtn

  if showLoot and actionBar and instanceDropdown then
    instanceDropdown:ClearAllPoints()
    instanceDropdown:SetPoint("RIGHT", actionBar, "RIGHT", -8, -2)
  end
  if showLoot and ilvlDropdown and instanceDropdown then
    ilvlDropdown:ClearAllPoints()
    ilvlDropdown:SetPoint("RIGHT", instanceDropdown, "LEFT", -8, 0)
  end
  if showPerfControls and perfControl and actionBar then
    perfControl:ClearAllPoints()
    if showLoot and ilvlDropdown and ilvlDropdown:IsShown() then
      perfControl:SetPoint("RIGHT", ilvlDropdown, "LEFT", -8, 0)
    else
      perfControl:SetPoint("TOPRIGHT", actionBar, "TOPRIGHT", -8, -4)
    end
  end
  if showLoot and advisorFrame.lootHint then
    advisorFrame.lootHint:ClearAllPoints()
    local leftAnchor = (showPerfControls and perfControl and perfControl:IsShown()) and perfControl or ilvlDropdown
    if leftAnchor then
      advisorFrame.lootHint:SetPoint("RIGHT", leftAnchor, "LEFT", -8, 0)
    end
  end
  if upgradeFilterFrame and findLoadoutBtn and upgradeFilterFrame:IsShown() then
    upgradeFilterFrame:ClearAllPoints()
    upgradeFilterFrame:SetPoint("TOPLEFT", findLoadoutBtn, "TOPRIGHT", 12, 0)
    if showPerfControls and perfControl and perfControl:IsShown() then
      upgradeFilterFrame:SetPoint("TOPRIGHT", perfControl, "TOPLEFT", -12, 0)
    else
      upgradeFilterFrame:SetPoint("RIGHT", actionBar, "RIGHT", -140, 0)
    end
    upgradeFilterFrame:SetHeight(56)
  end
end

toggleAdvisorScanPerformance = function()
  if not isLoadoutSearchActive() then
    return
  end
  local newMode = NS.toggleScanPerformanceMode()
  syncScanPerfControls()
  if isAdvisorScanActive() then
    local preset = NS.SCAN_PERFORMANCE_PRESETS[newMode]
    local label = preset and preset.label or newMode
    setStatusText(string.format("Scan speed: %s", label), { 0.75, 0.9, 1 })
  end
end

local function forEachComboSelectionCandidate(fn)
  if not fn then
    return
  end
  local seen = {}
  local specKey = NS.getActiveProfileKey()
  if specKey and candidatesBySlot then
    local _, equippedBySlot = NS.buildSlotCandidates(specKey, candidatesBySlot, {
      respect_selection = false,
      include_bags = false,
    })
    for _, eqCand in pairs(equippedBySlot or {}) do
      if eqCand and eqCand.key and not seen[eqCand.key] then
        seen[eqCand.key] = true
        fn(eqCand)
      end
    end
  end
  for _, cand in ipairs(candidateRows or {}) do
    if cand and cand.key and not seen[cand.key] then
      seen[cand.key] = true
      fn(cand)
    end
  end
end

local function countSelectedCandidates()
  local n = 0
  forEachComboSelectionCandidate(function(cand)
    if NS.isAdvisorCandidateSelected(cand) then
      n = n + 1
    end
  end)
  return n
end

local function countSelectedAlternatives()
  local n = 0
  for _, cand in ipairs(candidateRows or {}) do
    if cand and NS.isAdvisorCandidateSelected(cand) then
      n = n + 1
    end
  end
  return n
end

local function formatComboCount(n)
  return NS.formatLargeNumber(n)
end

local function getActiveScanTypeLabel()
  if scanComplete and isLoadoutMode() and isAdvisorScanActive() then
    return "Find Loadout"
  end
  for _, mode in ipairs(MODE_TABS) do
    if mode.id == currentMode then
      return mode.label
    end
  end
  return "Gear scan"
end

local function setNoProfileStatus()
  setStatusText(NS.MSG_NO_PROFILE_ACTION, { 1, 0.6, 0.4 })
end

local function comboCountWarningSuffix(count)
  if NS.isHighLoadoutComboCount and NS.isHighLoadoutComboCount(count) then
    return " (large search)"
  end
  return ""
end

local function getComboSelectionKey()
  local parts = {}
  forEachComboSelectionCandidate(function(cand)
    parts[#parts + 1] = cand.key .. "=" .. (NS.isAdvisorCandidateSelected(cand) and "1" or "0")
  end)
  table.sort(parts)
  return table.concat(parts, "\31")
end

local function finishComboEstimate(token, total)
  if token ~= comboEstimateToken then
    return false
  end
  comboEstimateRunner = nil
  comboCountInProgress = false
  comboCountProgress = nil
  estimatedCombinations = total
  lastComboSelectionKey = getComboSelectionKey()
  applyPostScanStatus()
  syncActionButtons()
  return true
end

local function runLoadoutComboEstimateNow()
  if not scanComplete or not candidatesBySlot then
    return
  end
  local specKey = NS.getActiveProfileKey()
  if not specKey then
    return
  end

  local selectionKey = getComboSelectionKey()
  if selectionKey == lastComboSelectionKey and estimatedCombinations ~= nil then
    return
  end

  comboEstimateScheduleToken = comboEstimateScheduleToken + 1
  if comboEstimateRunner then
    comboEstimateRunner.cancelled = true
    comboEstimateRunner = nil
  end

  comboEstimateToken = comboEstimateToken + 1
  local token = comboEstimateToken

  local total = NS.countAdvisorLoadoutCombinationsSync(specKey, candidatesBySlot)
  if total ~= nil then
    finishComboEstimate(token, total)
    return
  end

  comboCountInProgress = true
  comboCountProgress = estimatedCombinations
  applyPostScanStatus()

  local runner = { cancelled = false }
  comboEstimateRunner = runner

  NS.beginAdvisorLoadoutCombinationCount(specKey, candidatesBySlot, {
    runner = runner,
    refresh_flags = false,
    onProgress = function(payload)
      if token ~= comboEstimateToken or runner.cancelled then
        return
      end
      comboCountProgress = payload.total or 0
      applyPostScanStatus()
    end,
  }, function(cancelled, err, payload)
    if token ~= comboEstimateToken then
      return
    end
    if cancelled or err or not payload or payload.kind ~= "done" then
      comboEstimateRunner = nil
      comboCountInProgress = false
      comboCountProgress = nil
      applyPostScanStatus()
      syncActionButtons()
      return
    end
    finishComboEstimate(token, payload.total or 0)
  end)
end

refreshLoadoutComboEstimate = function()
  comboEstimateScheduleToken = comboEstimateScheduleToken + 1
  local scheduleToken = comboEstimateScheduleToken
  C_Timer.After(0.35, function()
    if scheduleToken ~= comboEstimateScheduleToken then
      return
    end
    runLoadoutComboEstimateNow()
  end)
end

local function formatPostScanStatus()
  local scoredCount = #upgradeRows
  local selectedAltCount = countSelectedAlternatives()
  local vaultNote = ""
  if currentMode == "bags" and NS.isGreatVaultFrameOpen() then
    vaultNote = " " .. NS.MSG_VAULT_TRINKET_DISCLAIMER
  end
  local noteSuffix = ""
  if statusNote and currentMode == "loot" then
    noteSuffix = ", " .. statusNote
  end
  local comboPart
  local highCombo = false
  if comboCountInProgress then
    if estimatedCombinations and estimatedCombinations > 0 then
      comboPart = string.format(
        NS.MSG_SCAN_RECALC,
        formatComboCount(estimatedCombinations),
        NS.MSG_FIND_LOADOUT_HINT
      )
    else
      comboPart = string.format(
        NS.MSG_SCAN_COUNTING,
        formatComboCount(comboCountProgress or 0),
        NS.MSG_FIND_LOADOUT_HINT
      )
    end
  elseif selectedAltCount == 0 then
    comboPart = NS.MSG_FIND_LOADOUT_HINT
  elseif estimatedCombinations and estimatedCombinations > 0 then
    highCombo = NS.isHighLoadoutComboCount(estimatedCombinations)
    comboPart = string.format(
      NS.MSG_SCAN_COMBOS,
      formatComboCount(estimatedCombinations),
      comboCountWarningSuffix(estimatedCombinations),
      NS.MSG_FIND_LOADOUT_HINT
    )
  else
    comboPart = NS.MSG_SCAN_NO_COMBOS
  end
  return string.format(
    NS.MSG_SCAN_STATUS,
    formatComboCount(scoredCount),
    formatComboCount(selectedAltCount),
    comboPart
  ) .. vaultNote .. noteSuffix, highCombo
end

applyPostScanStatus = function()
  local text, highCombo = formatPostScanStatus()
  local color = { 0.55, 1, 0.65 }
  if highCombo then
    color = { 1, 0.65, 0.35 }
  end
  setStatusText(text, color)
end

local function formatLoadoutResultMessage(summary, rows)
  if not summary then
    return ""
  end
  local vaultNote = ""
  for _, row in ipairs(rows or {}) do
    if row.is_upgrade and row.source == "vault" then
      vaultNote = string.format(" · Vault: %s", row.name or "reward")
      break
    end
  end
  return string.format(
    "Best loadout: %.0f -> %.0f (%s)%s",
    summary.dps_base or 0,
    summary.dps_new or 0,
    NS.formatDelta(summary.dps_delta or 0),
    vaultNote
  )
end

syncAdvisorStatusText = function()
  if not advisorFrame or not advisorFrame.summaryText then
    return
  end
  if isAdvisorScanActive() then
    return
  end
  if currentMode == "crests" then
    if crestPlanSummary then
      setStatusText(crestPlanSummary, { 0.55, 1, 0.65 })
    elseif advisorScanRunner then
      setStatusText(NS.MSG_CREST_SCANNING, { 0.95, 0.85, 0.45 })
    else
      setStatusText(NS.MSG_CREST_MODE_HINT)
    end
    return
  end
  if isShowingLoadoutResults() and loadoutSummary then
    if next(pendingEquips) or countLoadoutEquipsByState("done") > 0 or countLoadoutEquipsByState("failed") > 0 then
      syncLoadoutEquipStatusText()
    else
      setStatusText(formatLoadoutResultMessage(loadoutSummary, loadoutRows), { 0.55, 1, 0.65 })
    end
    return
  end
  if scanComplete and isLoadoutMode() then
    applyPostScanStatus()
    return
  end
  if currentMode == "loot" then
    setStatusText(NS.MSG_LOOT_MODE_HINT)
  else
    setStatusText(NS.MSG_FIND_LOADOUT_HINT)
  end
end

updatePostScanStatusIfIdle = function()
  if scanComplete and isLoadoutMode() and not isAdvisorScanActive() then
    applyPostScanStatus()
  end
end

local function candidateMatchesCurrentMode(cand)
  if not cand or not cand.source then
    return true
  end
  if currentMode == "loot" then
    return cand.source == "loot"
  end
  if currentMode == "bags" then
    return cand.source == "bag" or cand.source == "vault"
  end
  return true
end

local function candidateVisibleInOverview(cand)
  if not candidateMatchesCurrentMode(cand) then
    return false
  end
  if MR_MYTHICAL_DPS_CONFIG.gear_advisor_upgrades_only ~= true then
    return true
  end
  if cand.is_upgrade then
    return true
  end
  if NS.getAdvisorIncludeSidegrades() then
    local dpsDelta = cand.dps_delta
    return dpsDelta ~= nil and dpsDelta >= NS.ADVISOR_SIDEGRADE_DPS_FLOOR
  end
  return false
end

local function buildAdvisorSlotOverviewRows()
  if not scanComplete or not candidatesBySlot then
    return {}
  end
  local specKey = NS.getActiveProfileKey()
  if not specKey then
    return {}
  end

  local slotCandidates, equippedBySlot, slotOrder = NS.buildSlotCandidates(specKey, candidatesBySlot, {
    respect_selection = false,
    include_bags = false,
  })

  local rows = {}
  for _, slotId in ipairs(slotOrder) do
    local equipped = equippedBySlot[slotId]
    local eqKey = equipped and equipped.key or nil
    local options = {}
    for _, cand in ipairs(slotCandidates[slotId] or {}) do
      local key = cand and cand.key or nil
      local showEquippedDuplicate = NS.candidateMatchesEquippedGear
        and NS.candidateMatchesEquippedGear(cand, slotId)
      if cand and cand.link and key and key ~= eqKey and not cand.is_equipped_baseline
        and (candidateVisibleInOverview(cand) or showEquippedDuplicate) then
        table.insert(options, cand)
      end
    end
    table.sort(options, function(a, b)
      return (a.dps_delta or 0) > (b.dps_delta or 0)
    end)
    table.insert(rows, {
      slot_id = slotId,
      slot_label = NS.SLOT_ID_LABELS[slotId] or tostring(slotId),
      equipped = equipped,
      options = options,
    })
  end
  return rows
end

isShowingLoadoutResults = function()
  return loadoutSummary ~= nil and #loadoutRows > 0
end

local function isLootLoadoutResults()
  return currentMode == "loot" and isShowingLoadoutResults()
end

local function getLootLoadoutSourceText(item)
  if not item or not item.is_upgrade then
    return NS.LOADOUT_ROW_EQUIPPED
  end
  return item.instance_name or item.source_label or "-"
end

local function loadoutRowEquipKey(item)
  if not item then
    return nil
  end
  if item.key then
    return item.key
  end
  return string.format("%s:%s", tostring(item.slot_id or "?"), tostring(item.link or item.name or ""))
end

local function pendingEquipMatchesSlot(pending)
  if not pending or not pending.slot_id or not NS.getSlotItemRef then
    return false
  end
  local eqRef = NS.getSlotItemRef(pending.slot_id)
  if not eqRef or not eqRef.link then
    return false
  end
  if pending.guid and eqRef.guid and pending.guid == eqRef.guid then
    return true
  end
  if pending.link and eqRef.link then
    local pendingId = tonumber(pending.link:match("item:(%d+)"))
    local eqId = tonumber(eqRef.link:match("item:(%d+)"))
    if pendingId and eqId and pendingId == eqId then
      return true
    end
  end
  return false
end

countLoadoutEquipsByState = function(state)
  local count = 0
  for _, equipState in pairs(loadoutEquipState) do
    if equipState == state then
      count = count + 1
    end
  end
  return count
end

syncLoadoutEquipStatusText = function(lastMessage, color)
  if not isShowingLoadoutResults() then
    return
  end
  local doneCount = countLoadoutEquipsByState("done")
  local pendingCount = countLoadoutEquipsByState("pending")
  local upgradeCount = 0
  for _, row in ipairs(loadoutRows) do
    if row.is_upgrade and row.can_equip then
      upgradeCount = upgradeCount + 1
    end
  end
  local text = lastMessage
  if not text and doneCount > 0 then
    text = string.format("Equipped %d/%d changes.", doneCount, upgradeCount)
  end
  if not text and pendingCount > 0 then
    text = NS.MSG_EQUIP_PENDING
  end
  if text then
    setStatusText(text, color or { 0.55, 1, 0.65 })
  end
end

local function refreshLoadoutEquipFeedback(lastMessage, color)
  if isShowingLoadoutResults() then
    renderAdvisorRows()
  end
  syncLoadoutEquipStatusText(lastMessage, color)
end

local function failPendingEquip(key, pending)
  loadoutEquipState[key] = "failed"
  pendingEquips[key] = nil
  local label = pending and pending.name or "item"
  refreshLoadoutEquipFeedback(string.format(NS.MSG_EQUIP_STATUS_FAILED, label), { 1, 0.5, 0.5 })
  NS.brandPrint(string.format(NS.MSG_EQUIP_STATUS_FAILED, label))
end

local function completePendingEquip(key, pending)
  loadoutEquipState[key] = "done"
  pendingEquips[key] = nil
  local label = pending and pending.name or "item"
  refreshLoadoutEquipFeedback(string.format(NS.MSG_EQUIP_STATUS_DONE, label), { 0.55, 1, 0.65 })
  NS.brandPrint(string.format(NS.MSG_EQUIP_STATUS_DONE, label))
end

local function verifyPendingEquips()
  if not next(pendingEquips) then
    return
  end
  local now = GetTime()
  for key, pending in pairs(pendingEquips) do
    if pendingEquipMatchesSlot(pending) then
      completePendingEquip(key, pending)
    elseif pending.started and (now - pending.started) >= 2.5 then
      failPendingEquip(key, pending)
    end
  end
end

local function tryEquipLoadoutItem(item)
  if not item or item.bag == nil or item.slot == nil then
    return
  end
  if InCombatLockdown and InCombatLockdown() then
    NS.brandPrint(NS.MSG_EQUIP_COMBAT)
    setStatusText(NS.MSG_EQUIP_COMBAT, { 1, 0.55, 0.45 })
    return
  end
  local key = loadoutRowEquipKey(item)
  if not key or loadoutEquipState[key] == "pending" or loadoutEquipState[key] == "done" then
    return
  end
  loadoutEquipState[key] = "pending"
  pendingEquips[key] = {
    key = key,
    bag = item.bag,
    slot = item.slot,
    slot_id = item.slot_id,
    link = item.link,
    guid = item.guid,
    name = item.name,
    started = GetTime(),
  }
  if C_Container and C_Container.UseContainerItem then
    C_Container.UseContainerItem(item.bag, item.slot)
  end
  refreshLoadoutEquipFeedback(string.format(NS.MSG_EQUIP_STATUS_PENDING, item.name or "item"), { 0.95, 0.85, 0.45 })
  C_Timer.After(0.15, verifyPendingEquips)
  C_Timer.After(2.5, verifyPendingEquips)
end

local function returnToSelectionView()
  loadoutSummary = nil
  loadoutRows = {}
  resetLoadoutEquipState()
  renderAdvisorRows()
  syncActionButtons()
  updatePostScanStatusIfIdle()
  saveModeScanSnapshot(currentMode)
end

local function syncAdvisorListHeader()
  if not advisorFrame then return end
  local slotHdr = advisorFrame.headerSlot
  local detailHdr = advisorFrame.headerDetail
  local recHdr = advisorFrame.headerRec
  local metricHdr = advisorFrame.headerMetric
  if not slotHdr or not detailHdr or not metricHdr then return end

  slotHdr:Hide()
  detailHdr:Hide()
  if recHdr then recHdr:Hide() end
  metricHdr:Hide()
  if advisorFrame.headerCost then advisorFrame.headerCost:Hide() end
  if advisorFrame.headerUpgradeStep then advisorFrame.headerUpgradeStep:Hide() end

  if currentMode == "crests" then
    if crestPlanIsActive() then
      slotHdr:SetText("Step / Slot")
    else
      slotHdr:SetText("Slot")
    end
    slotHdr:Show()
    detailHdr:SetPoint("LEFT", advisorFrame.headerFrame, "LEFT", GA_CREST_CURRENT_X, 0)
    detailHdr:SetText(NS.LOADOUT_CURRENT_LABEL)
    detailHdr:Show()
    if advisorFrame.headerUpgradeStep then
      advisorFrame.headerUpgradeStep:ClearAllPoints()
      advisorFrame.headerUpgradeStep:SetPoint("LEFT", advisorFrame.headerFrame, "LEFT", GA_CREST_STEP_X, 0)
      advisorFrame.headerUpgradeStep:SetText(NS.CREST_HEADER_STEP)
      advisorFrame.headerUpgradeStep:Show()
    end
    if recHdr then
      recHdr:SetPoint("LEFT", advisorFrame.headerFrame, "LEFT", GA_CREST_AFTER_X, 0)
      recHdr:SetText(NS.CREST_AFTER_UPGRADE_LABEL)
      recHdr:Show()
    end
    if advisorFrame.headerCost then
      advisorFrame.headerCost:ClearAllPoints()
      advisorFrame.headerCost:SetPoint("RIGHT", advisorFrame.headerFrame, "RIGHT", -GA_CREST_COST_RIGHT, 0)
      advisorFrame.headerCost:SetText(NS.CREST_HEADER_COST)
      advisorFrame.headerCost:Show()
    end
    metricHdr:ClearAllPoints()
    metricHdr:SetPoint("RIGHT", advisorFrame.headerFrame, "RIGHT", -8, 0)
    metricHdr:SetText(NS.CREST_HEADER_DPS)
    metricHdr:Show()
  elseif isLoadoutMode() and isShowingLoadoutResults() then
    slotHdr:SetText("Slot")
    slotHdr:Show()
    detailHdr:SetPoint("LEFT", advisorFrame.headerFrame, "LEFT", GA_LOADOUT_CURRENT_X, 0)
    detailHdr:SetText(NS.LOADOUT_CURRENT_LABEL)
    detailHdr:Show()
    if recHdr then
      recHdr:SetPoint("LEFT", advisorFrame.headerFrame, "LEFT", GA_LOADOUT_REC_X, 0)
      recHdr:SetText(NS.LOADOUT_RECOMMENDED_LABEL)
      recHdr:Show()
    end
    metricHdr:SetPoint("RIGHT", advisorFrame.headerFrame, "RIGHT", -10, 0)
    if currentMode == "loot" then
      metricHdr:SetText(NS.LOADOUT_LOOT_SOURCE_LABEL)
    else
      metricHdr:SetText(NS.LOADOUT_RESULT_STATUS_LABEL)
    end
    metricHdr:Show()
  elseif isLoadoutMode() then
    slotHdr:SetText("Slot")
    slotHdr:Show()
    detailHdr:SetPoint("LEFT", advisorFrame.headerFrame, "LEFT", GA_ICONS_COL_X, 0)
    if currentMode == "bags" and NS.isGreatVaultFrameOpen() then
      detailHdr:SetText("Equipped and alternatives (purple border = vault)")
    else
      detailHdr:SetText("Equipped and alternatives (click to toggle)")
    end
    detailHdr:Show()
  end
end

local function renderAdvisorSlotOverviewRow(itemList, listWidth, slotRow, rowIndex, yOffset, iconsPerLine)
  local baseR, baseG, baseB = 0.11, 0.11, 0.14
  if rowIndex % 2 == 0 then baseR, baseG, baseB = 0.15, 0.15, 0.19 end

  local slotId = slotRow.slot_id
  if slotId == 13 or slotId == 14 then
    local row = CreateFrame("Frame", nil, itemList, "BackdropTemplate")
    table.insert(advisorRows, row)
    row:SetSize(listWidth, 30)
    row:SetPoint("TOPLEFT", itemList, "TOPLEFT", 0, -yOffset)
    row:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", tile = true, tileSize = 16 })
    row:SetBackdropColor(baseR, baseG, baseB, 0.65)
    local slotText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slotText:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -8)
    slotText:SetText(slotRow.slot_label or "")
    slotText:SetTextColor(0.55, 0.55, 0.6)
    local note = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("LEFT", row, "LEFT", GA_ICONS_COL_X, 0)
    note:SetText(NS.MSG_TRINKET_BASELINE)
    note:SetTextColor(0.5, 0.5, 0.55)
    return yOffset + 34
  end

  local icons = {}
  if slotRow.equipped then
    table.insert(icons, {
      candidate = slotRow.equipped,
      is_equipped = true,
      is_selected = NS.isAdvisorCandidateSelected(slotRow.equipped),
    })
  end
  for _, cand in ipairs(slotRow.options or {}) do
    table.insert(icons, {
      candidate = cand,
      is_equipped = false,
      is_selected = NS.isAdvisorCandidateSelected(cand),
      is_equipped_duplicate = NS.candidateMatchesEquippedGear
        and NS.candidateMatchesEquippedGear(cand, slotId) or false,
    })
  end

  local iconCount = #icons
  local lines = math.max(1, math.ceil(math.max(1, iconCount) / iconsPerLine))
  local showWeaponDps = (slotId == 16 or slotId == 17)
  local dpsLineExtra = showWeaponDps and 12 or 0
  local rowHeight = math.max(38, lines * (GA_ICON_SIZE + GA_ICON_SPACING + dpsLineExtra) + 10)

  local row = CreateFrame("Frame", nil, itemList, "BackdropTemplate")
  table.insert(advisorRows, row)
  row:SetSize(listWidth, rowHeight)
  row:SetPoint("TOPLEFT", itemList, "TOPLEFT", 0, -yOffset)
  row:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", tile = true, tileSize = 16 })
  row:SetBackdropColor(baseR, baseG, baseB, 0.65)

  local optionCount = #(slotRow.options or {})
  local slotLabel = slotRow.slot_label or "Slot"
  if optionCount > 0 then
    slotLabel = string.format("%s (%d)", slotLabel, optionCount)
  end

  local slotText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  slotText:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -10)
  slotText:SetText(slotLabel)
  slotText:SetWidth(GA_SLOT_COL_WIDTH)
  slotText:SetJustifyH("LEFT")
  slotText:SetTextColor(0.9, 0.9, 0.95)

  if iconCount == 0 or (iconCount == 1 and icons[1] and icons[1].is_equipped) then
    local emptyText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local emptyX = GA_ICONS_COL_X
    if iconCount == 1 and icons[1] and icons[1].is_equipped then
      emptyX = GA_ICONS_COL_X + GA_ICON_SIZE + 10
    end
    emptyText:SetPoint("TOPLEFT", row, "TOPLEFT", emptyX, -10)
    emptyText:SetText("No alternate items for this slot")
    emptyText:SetTextColor(0.45, 0.45, 0.5)
  end

  for iconIndex, iconInfo in ipairs(icons) do
    local col = (iconIndex - 1) % iconsPerLine
    local line = math.floor((iconIndex - 1) / iconsPerLine)
    local x = GA_ICONS_COL_X + col * (GA_ICON_SIZE + GA_ICON_SPACING)
    local y = -6 - line * (GA_ICON_SIZE + GA_ICON_SPACING)
    local cand = iconInfo.candidate

    local borderR, borderG, borderB = 0.35, 0.35, 0.35
    local bgA = 0.25
    local edgeSize = 10
    local isVault = isVaultCandidate(cand)
    local isVaultWinner = isVault and loadoutVaultWinnerKey and cand.key == loadoutVaultWinnerKey
    if iconInfo.is_equipped then
      borderR, borderG, borderB = 0.95, 0.82, 0.25
      bgA = iconInfo.is_selected and 0.45 or 0.18
      if not iconInfo.is_selected then
        borderR, borderG, borderB = 0.7, 0.2, 0.2
      end
    elseif isVaultWinner then
      borderR, borderG, borderB = VAULT_WINNER_BORDER[1], VAULT_WINNER_BORDER[2], VAULT_WINNER_BORDER[3]
      bgA = 0.45
      edgeSize = 12
    elseif isVault and iconInfo.is_selected then
      borderR, borderG, borderB = VAULT_BORDER_SELECTED[1], VAULT_BORDER_SELECTED[2], VAULT_BORDER_SELECTED[3]
      bgA = 0.4
      edgeSize = 12
    elseif isVault then
      borderR, borderG, borderB = VAULT_BORDER[1], VAULT_BORDER[2], VAULT_BORDER[3]
      bgA = 0.32
      edgeSize = 12
    elseif iconInfo.is_selected then
      borderR, borderG, borderB = 0.2, 0.85, 0.25
      bgA = 0.35
    else
      borderR, borderG, borderB = 0.7, 0.2, 0.2
      bgA = 0.18
    end

    local iconBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
    iconBtn:SetSize(GA_ICON_SIZE, GA_ICON_SIZE)
    iconBtn:SetPoint("TOPLEFT", row, "TOPLEFT", x, y)
    iconBtn:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8X8",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 8, edgeSize = edgeSize,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    iconBtn:SetBackdropColor(0, 0, 0, bgA)
    iconBtn:SetBackdropBorderColor(borderR, borderG, borderB, 1)

    local tex = iconBtn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(iconBtn)
    local iconTexture = cand and cand.link and GetItemIcon(cand.link) or nil
    if iconTexture then
      tex:SetTexture(iconTexture)
    end
    if not iconInfo.is_selected and not isVault then
      tex:SetVertexColor(0.45, 0.45, 0.45, 0.9)
    elseif not iconInfo.is_selected and isVault then
      tex:SetVertexColor(0.55, 0.55, 0.55, 0.85)
    else
      tex:SetVertexColor(1, 1, 1, 1)
    end

    if iconInfo.is_equipped then
      local tag = iconBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      tag:SetPoint("BOTTOMRIGHT", iconBtn, "BOTTOMRIGHT", -1, 1)
      tag:SetText("E")
      if iconInfo.is_selected then
        tag:SetTextColor(1, 0.95, 0.5)
      else
        tag:SetTextColor(0.45, 0.45, 0.45)
      end
    elseif isVaultWinner then
      local tag = iconBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      tag:SetPoint("BOTTOMRIGHT", iconBtn, "BOTTOMRIGHT", -1, 1)
      tag:SetText("★")
      tag:SetTextColor(1, 0.88, 0.45)
    elseif isVault then
      local tag = iconBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      tag:SetPoint("BOTTOMRIGHT", iconBtn, "BOTTOMRIGHT", -1, 1)
      tag:SetText("V")
      tag:SetTextColor(0.9, 0.75, 1)
    end

    if not iconInfo.is_equipped and cand and cand.dps_delta ~= nil then
      local dpsTag = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      dpsTag:SetPoint("TOP", iconBtn, "BOTTOM", 0, -1)
      dpsTag:SetWidth(GA_ICON_SIZE + 4)
      dpsTag:SetJustifyH("CENTER")
      local dpsLabel = NS.formatDelta(cand.dps_delta)
      if cand.weapon_pair_scored then
        dpsLabel = dpsLabel .. "*"
      end
      dpsTag:SetText(dpsLabel)
      NS.setDpsDeltaTextColor(dpsTag, cand.dps_delta)
    end

    iconBtn:SetScript("OnClick", function()
      local selected = NS.isAdvisorCandidateSelected(cand)
      if not selected and NS.candidateMatchesEquippedGear and NS.candidateMatchesEquippedGear(cand, slotId) then
        return
      end
      local force = (not selected) and not NS.advisorCandidateIncludedByDefault(cand)
      NS.setAdvisorCandidateSelected(cand, not selected, force)
      if isVault and NS.isAdvisorCandidateSelected(cand) then
        deselectOtherVaultCandidates(cand)
      end
      if isShowingLoadoutResults() then
        loadoutSummary = nil
        loadoutRows = {}
        saveModeScanSnapshot(currentMode)
      end
      renderAdvisorRows()
      applyPostScanStatus()
      refreshLoadoutComboEstimate()
      syncVaultTrinketDisclaimer()
    end)
    iconBtn:SetScript("OnEnter", function(self)
      self:SetBackdropBorderColor(1, 1, 1, 1)
      if cand and cand.link then
        self.mrMythicalAdvisorItemTooltip = true
        self.mrMythicalTooltipExtraLines = buildCandidateTooltipExtraLines(
          cand, iconInfo, isVault, isVaultWinner, slotId
        )
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(cand.link)
      end
    end)
    iconBtn:SetScript("OnLeave", function(self)
      self:SetBackdropBorderColor(borderR, borderG, borderB, 1)
      self.mrMythicalAdvisorItemTooltip = nil
      self.mrMythicalTooltipExtraLines = nil
      GameTooltip:Hide()
    end)
  end

  return yOffset + rowHeight + 4
end

local function rebuildCandidateRowsFromSlots()
  candidateRows = {}
  local seen = {}
  if not candidatesBySlot then return end
  for _, list in pairs(candidatesBySlot) do
    for _, cand in ipairs(list) do
      if cand and cand.key and not cand.is_equipped_baseline and not seen[cand.key]
        and candidateMatchesCurrentMode(cand) then
        seen[cand.key] = true
        table.insert(candidateRows, cand)
      end
    end
  end
  table.sort(candidateRows, function(a, b)
    return (a.dps_delta or 0) > (b.dps_delta or 0)
  end)
end

local function attachScoredRowsToCandidates(rows)
  local byKey = {}
  for _, row in ipairs(rows) do
    local itemID = row.link and tonumber(row.link:match("item:(%d+)"))
    if row.source == "vault" and itemID then
      byKey["vault:" .. itemID] = row
      if row.vault_activity_id then
        byKey[string.format("vault:%s:%d", tostring(row.vault_activity_id), itemID)] = row
      end
    elseif row.source == "loot" and row.instance_id and itemID then
      byKey[string.format("loot:%d:%d", row.instance_id, itemID)] = row
    elseif row.source == "crest" and itemID then
      local rank = row.upgrade_rank or "0"
      rank = tostring(rank):gsub("[^%d/]", ""):match("(%d+)") or "0"
      byKey[string.format("crest:%d:%s", itemID, rank)] = row
    elseif row.source == "bag" then
      -- matched later by link/guid
    end
    if row.link then
      byKey["link:" .. row.link] = row
    end
  end

  if not candidatesBySlot then return end
  for slotId, list in pairs(candidatesBySlot) do
    for i, cand in ipairs(list) do
      if not cand.is_equipped_baseline then
        local scored = cand.key and byKey[cand.key]
        if not scored and cand.link then
          scored = byKey["link:" .. cand.link]
        end
        if scored then
          if scored.source and cand.source and scored.source ~= cand.source then
            scored = nil
          end
        end
        if scored then
          cand.dps_delta = scored.dps_delta
          cand.is_upgrade = scored.is_upgrade
          cand.slot_id = scored.slot_id or cand.slot_id
          cand.slot_label = scored.slot_label or cand.slot_label
          cand.dps_per_crest = scored.dps_per_crest or cand.dps_per_crest
          list[i] = cand
        end
      end
    end
  end
end

syncActionButtons = function()
  if not advisorFrame then return end
  local loadout = isLoadoutMode()
  local showingResults = isShowingLoadoutResults()
  local scanning = isAdvisorScanActive()
  local findBtn = advisorFrame.findLoadoutBtn
  local changeBtn = advisorFrame.changeSelectionBtn
  local stopBtn = advisorFrame.stopScanBtn
  if stopBtn then
    stopBtn:SetShown(scanning)
  end
  if findBtn then
    findBtn:SetShown(loadout and not showingResults and not scanning)
    findBtn:SetEnabled(
      loadout and scanComplete and not scanning and not showingResults and not comboCountInProgress
    )
  end
  if changeBtn then
    changeBtn:SetShown(loadout and showingResults and not scanning)
  end
  if advisorFrame.upgradeFilterFrame then
    advisorFrame.upgradeFilterFrame:SetShown(
      isLoadoutMode() and currentMode ~= "crests"
      and not showingResults and not scanning
    )
  end
  syncCrestFilterControls()
  syncScanPerfControls()
  syncModeTabs()
end

local function renderLoadoutVaultWinnerBanner(itemList, listWidth, winnerRow, yOffset)
  if currentMode ~= "bags" or not winnerRow then
    return yOffset
  end

  local row = CreateFrame("Frame", nil, itemList, "BackdropTemplate")
  table.insert(advisorRows, row)
  row:SetSize(listWidth, 54)
  row:SetPoint("TOPLEFT", itemList, "TOPLEFT", 0, -yOffset)
  row:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  row:SetBackdropColor(0.14, 0.1, 0.2, 0.95)
  row:SetBackdropBorderColor(VAULT_WINNER_BORDER[1], VAULT_WINNER_BORDER[2], VAULT_WINNER_BORDER[3], 1)

  local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -8)
  title:SetText(NS.MSG_VAULT_LOADOUT_WINNER)
  title:SetTextColor(1, 0.88, 0.45)

  local iconBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
  iconBtn:SetSize(30, 30)
  iconBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -26)
  iconBtn:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  iconBtn:SetBackdropBorderColor(VAULT_BORDER[1], VAULT_BORDER[2], VAULT_BORDER[3], 1)
  iconBtn:SetBackdropColor(0, 0, 0, 0.35)
  local tex = iconBtn:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints(iconBtn)
  if winnerRow.link then
    tex:SetTexture(GetItemIcon(winnerRow.link))
    iconBtn:SetScript("OnEnter", function(self)
      self.mrMythicalAdvisorItemTooltip = true
      self.mrMythicalTooltipExtraLines = {
        { text = NS.MSG_VAULT_LOADOUT_WINNER, r = 1, g = 0.88, b = 0.45 },
      }
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(winnerRow.link)
    end)
    iconBtn:SetScript("OnLeave", function(self)
      self.mrMythicalAdvisorItemTooltip = nil
      self.mrMythicalTooltipExtraLines = nil
      GameTooltip:Hide()
    end)
  end

  local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  nameText:SetPoint("LEFT", iconBtn, "RIGHT", 8, 4)
  nameText:SetWidth(listWidth - 120)
  nameText:SetJustifyH("LEFT")
  nameText:SetText(winnerRow.name or "?")
  local lr, lg, lb = NS.getItemQualityRgb(winnerRow.quality)
  nameText:SetTextColor(lr, lg, lb)

  local activityText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  activityText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
  activityText:SetWidth(listWidth - 120)
  activityText:SetJustifyH("LEFT")
  activityText:SetText(winnerRow.source_label or "Great Vault")
  activityText:SetTextColor(0.75, 0.7, 0.85)

  return yOffset + 60
end

local function renderLoadoutRow(itemList, listWidth, item, i, yOffset)
  local baseR, baseG, baseB = 0.11, 0.11, 0.14
  if i % 2 == 0 then baseR, baseG, baseB = 0.15, 0.15, 0.19 end
  local isVaultWinner = item.source == "vault" and item.is_upgrade
    and loadoutVaultWinnerKey and getVaultKeyFromLoadoutRow(item) == loadoutVaultWinnerKey

  local row = CreateFrame("Frame", nil, itemList, "BackdropTemplate")
  table.insert(advisorRows, row)
  row:SetSize(listWidth, 40)
  row:SetPoint("TOPLEFT", itemList, "TOPLEFT", 0, -yOffset)
  if isVaultWinner then
    row:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    row:SetBackdropColor(0.14, 0.1, 0.2, 0.9)
    row:SetBackdropBorderColor(VAULT_WINNER_BORDER[1], VAULT_WINNER_BORDER[2], VAULT_WINNER_BORDER[3], 1)
  else
    row:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", tile = true, tileSize = 16 })
    if item.is_upgrade then
      row:SetBackdropColor(baseR * 0.55, math.min(1, baseG + 0.22), baseB * 0.55, 0.82)
    else
      row:SetBackdropColor(baseR, baseG, baseB, 0.65)
    end
  end

  local slotText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  slotText:SetPoint("LEFT", row, "LEFT", 10, 0)
  slotText:SetWidth(90)
  slotText:SetText(item.slot_label or "")
  slotText:SetTextColor(0.85, 0.85, 0.9)

  local rightReserve = isLootLoadoutResults() and 210 or 90
  local nameColWidth = math.max(100, math.floor((listWidth - GA_LOADOUT_REC_X - rightReserve) / 2))

  if item.is_upgrade then
    addLoadoutItemBlock(
      row,
      GA_LOADOUT_CURRENT_X,
      item.equipped_link,
      item.equipped_name,
      item.equipped_quality,
      nameColWidth,
      true
    )
    local arrow = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("LEFT", row, "LEFT", GA_LOADOUT_REC_X - 14, 0)
    arrow:SetText(">")
    arrow:SetTextColor(0.55, 0.55, 0.6)
    local recOpts = nil
    if item.source == "vault" then
      recOpts = { vaultBorder = true, vaultWinner = isVaultWinner }
    end
    addLoadoutItemBlock(row, GA_LOADOUT_REC_X, item.link, item.name, item.quality, nameColWidth, false, recOpts)
  else
    local eqLink = item.equipped_link or item.link
    local eqName = item.equipped_name or item.name
    local eqQuality = item.equipped_quality
    if eqQuality == nil then
      eqQuality = item.quality
    end
    addLoadoutItemBlock(row, GA_LOADOUT_CURRENT_X, eqLink, eqName, eqQuality, nameColWidth, false)
    local optimalText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    optimalText:SetPoint("LEFT", row, "LEFT", GA_LOADOUT_REC_X, 0)
    optimalText:SetText(NS.LOADOUT_ROW_ALREADY_OPTIMAL)
    optimalText:SetTextColor(0.5, 0.75, 0.55)
  end

  if isLootLoadoutResults() then
    local sourceText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sourceText:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    sourceText:SetWidth(200)
    sourceText:SetJustifyH("RIGHT")
    sourceText:SetText(getLootLoadoutSourceText(item))
    if item.is_upgrade then
      sourceText:SetTextColor(0.75, 0.8, 0.9)
    else
      sourceText:SetTextColor(0.5, 0.75, 0.55)
    end
    return yOffset + 44
  end

  local statusFrame = CreateFrame("Frame", nil, row)
  local statusWidth = (item.source == "vault" and item.is_upgrade) and 200 or 70
  statusFrame:SetSize(statusWidth, 20)
  statusFrame:SetPoint("RIGHT", row, "RIGHT", -10, 0)
  local statusText = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  statusText:SetPoint("RIGHT", statusFrame, "RIGHT", 0, 0)
  statusText:SetWidth(statusWidth)
  statusText:SetJustifyH("RIGHT")
  if item.source == "vault" and item.is_upgrade then
    statusText:SetText(isVaultWinner and "Vault pick" or (item.source_label or "Great Vault"))
    statusText:SetTextColor(isVaultWinner and 1 or 0.85, isVaultWinner and 0.88 or 0.7, isVaultWinner and 0.45 or 1)
  elseif item.is_upgrade then
    if item.dps_delta ~= nil then
      local label = NS.formatDpsVsEquipped(item.dps_delta)
      if item.weapon_pair_dps then
        label = label .. " (pair)"
      end
      statusText:SetText(label)
      statusText:SetWidth(120)
      statusFrame:SetWidth(120)
      NS.setDpsDeltaTextColor(statusText, item.dps_delta)
    else
      statusText:SetText(NS.LOADOUT_ROW_CHANGE)
      statusText:SetTextColor(0.55, 1, 0.65)
    end
  else
    statusText:SetText(NS.LOADOUT_ROW_KEEP)
    statusText:SetTextColor(0.5, 0.5, 0.55)
  end

  if item.is_upgrade and item.bag ~= nil and item.slot ~= nil then
    local equipKey = loadoutRowEquipKey(item)
    local equipState = equipKey and loadoutEquipState[equipKey]
    if equipState == "done" then
      statusText:SetText(NS.MSG_EQUIP_DONE)
      statusText:SetTextColor(0.45, 0.95, 0.55)
    elseif equipState == "failed" then
      local equipBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
      equipBtn:SetSize(60, 22)
      equipBtn:SetPoint("RIGHT", row, "RIGHT", -88, 0)
      equipBtn:SetText("Retry")
      equipBtn:SetScript("OnClick", function()
        loadoutEquipState[equipKey] = nil
        tryEquipLoadoutItem(item)
      end)
      statusText:SetText(NS.MSG_EQUIP_FAILED)
      statusText:SetTextColor(1, 0.45, 0.45)
    else
      local equipBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
      equipBtn:SetSize(60, 22)
      equipBtn:SetPoint("RIGHT", row, "RIGHT", -88, 0)
      if equipState == "pending" then
        equipBtn:SetText("...")
        equipBtn:Disable()
        statusText:SetText(NS.MSG_EQUIP_PENDING)
        statusText:SetTextColor(0.95, 0.85, 0.45)
      else
        equipBtn:SetText("Equip")
        equipBtn:SetScript("OnClick", function()
          tryEquipLoadoutItem(item)
        end)
      end
    end
  elseif item.is_upgrade and item.source == "vault" then
    local vaultTag = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    vaultTag:SetPoint("RIGHT", row, "RIGHT", -88, 0)
    vaultTag:SetText("Claim in Vault")
    vaultTag:SetTextColor(0.75, 0.65, 0.95)
  end

  return yOffset + 44
end

local function renderCrestSectionDivider(itemList, listWidth, label, yOffset)
  local row = CreateFrame("Frame", nil, itemList, "BackdropTemplate")
  table.insert(advisorRows, row)
  row:SetSize(listWidth, 24)
  row:SetPoint("TOPLEFT", itemList, "TOPLEFT", 0, -yOffset)
  row:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", tile = true, tileSize = 16 })
  row:SetBackdropColor(0.1, 0.1, 0.13, 0.55)

  local text = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  text:SetPoint("LEFT", row, "LEFT", 10, 0)
  text:SetText(label)
  text:SetTextColor(0.5, 0.54, 0.58)
  return yOffset + 28
end

local function renderCrestPlanSection(itemList, listWidth, yOffset)
  if not crestPlanIsActive() then
    return yOffset
  end

  local panel = CreateFrame("Frame", nil, itemList, "BackdropTemplate")
  table.insert(advisorRows, panel)
  panel:SetSize(listWidth, 28)
  panel:SetPoint("TOPLEFT", itemList, "TOPLEFT", 0, -yOffset)
  panel:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  panel:SetBackdropColor(0.08, 0.14, 0.11, 0.95)
  panel:SetBackdropBorderColor(0.25, 0.55, 0.35, 0.9)

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("LEFT", panel, "LEFT", 10, 0)
  title:SetText(string.format("%s - %d step(s)", NS.CREST_PLAN_TITLE, #crestSpendPlan))
  title:SetTextColor(0.55, 1, 0.65)
  return yOffset + 32
end

local function sortCrestDisplayRows(rows)
  local copy = {}
  for i, row in ipairs(rows or {}) do
    copy[i] = row
  end
  table.sort(copy, function(a, b)
    local planA = a.crest_plan_order or 9999
    local planB = b.crest_plan_order or 9999
    if planA ~= planB then
      return planA < planB
    end
    return (a.dps_per_crest or 0) > (b.dps_per_crest or 0)
  end)
  return copy
end

local function crestRowsForDisplay()
  if crestPlanIsActive() then
    local other = {}
    for _, row in ipairs(crestRows) do
      if not row.crest_plan_order then
        table.insert(other, row)
      end
    end
    table.sort(other, function(a, b)
      return (a.dps_per_crest or 0) > (b.dps_per_crest or 0)
    end)
    return other
  end
  return sortCrestDisplayRows(crestRows)
end

local function renderCrestRow(itemList, listWidth, item, i, yOffset)
  local baseR, baseG, baseB = 0.11, 0.11, 0.14
  if i % 2 == 0 then baseR, baseG, baseB = 0.15, 0.15, 0.19 end
  local hasPreview = item.preview_link and item.preview_link ~= item.link
  local inPlan = item.is_plan_step == true or item.crest_plan_order ~= nil

  local row = CreateFrame("Frame", nil, itemList, "BackdropTemplate")
  table.insert(advisorRows, row)
  row:SetSize(listWidth, GA_CREST_ROW_H)
  row:SetPoint("TOPLEFT", itemList, "TOPLEFT", 0, -yOffset)
  row:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", tile = true, tileSize = 16 })
  if inPlan then
    row:SetBackdropColor(baseR * 0.45, math.min(1, baseG + 0.24), baseB * 0.5, 0.88)
  elseif item.is_upgrade then
    row:SetBackdropColor(baseR * 0.55, math.min(1, baseG + 0.18), baseB * 0.55, 0.82)
  elseif item.can_afford == false then
    row:SetBackdropColor(baseR * 0.85, baseG * 0.7, baseB * 0.7, 0.55)
  else
    row:SetBackdropColor(baseR, baseG, baseB, 0.65)
  end

  if inPlan then
    local accent = row:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(0.35, 0.9, 0.45, 0.85)
    accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    accent:SetWidth(3)
  end

  local slotText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  slotText:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -8)
  slotText:SetWidth(88)
  slotText:SetJustifyH("LEFT")
  local slotLabel = item.slot_label or ""
  if inPlan then
    local stepNum = item.crest_plan_order or item.order
    if stepNum then
      slotLabel = string.format("#%d - %s", stepNum, slotLabel)
    end
  end
  slotText:SetText(slotLabel)
  if inPlan then
    slotText:SetTextColor(0.55, 1, 0.65)
  else
    slotText:SetTextColor(0.55, 0.58, 0.62)
  end

  local nameColWidth = crestItemNameWidth(listWidth)
  addLoadoutItemBlock(row, GA_CREST_CURRENT_X, item.link, item.name, item.quality, nameColWidth, item.can_afford == false)

  local stepText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  stepText:SetPoint("LEFT", row, "LEFT", GA_CREST_STEP_X, 0)
  stepText:SetWidth(GA_CREST_STEP_WIDTH)
  stepText:SetJustifyH("LEFT")
  stepText:SetText(NS.formatCrestUpgradeStepLine(item))
  stepText:SetTextColor(0.68, 0.72, 0.78)

  if hasPreview then
    addLoadoutItemBlock(
      row,
      GA_CREST_AFTER_X,
      item.preview_link,
      item.preview_name or item.name,
      item.preview_quality or item.quality,
      nameColWidth,
      false
    )
  end

  local costText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  costText:SetPoint("RIGHT", row, "RIGHT", crestColumnRight(listWidth, "cost"), 2)
  costText:SetWidth(GA_CREST_COST_WIDTH)
  costText:SetJustifyH("RIGHT")
  local costLabel = item.crest_label or ""
  costText:SetText(costLabel)
  NS.setCrestCostTextColor(costText, item)

  local ownedText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ownedText:SetPoint("TOPRIGHT", costText, "BOTTOMRIGHT", 0, -1)
  ownedText:SetWidth(GA_CREST_COST_WIDTH)
  ownedText:SetJustifyH("RIGHT")
  if item.currency_id and item.crest_owned ~= nil then
    ownedText:SetText(string.format("%d owned", item.crest_owned))
    ownedText:SetTextColor(0.5, 0.54, 0.58)
  end

  local metricText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  metricText:SetPoint("RIGHT", row, "RIGHT", crestColumnRight(listWidth, "dps"), 0)
  metricText:SetWidth(GA_CREST_DPS_WIDTH)
  metricText:SetJustifyH("RIGHT")
  metricText:SetText(NS.formatDpsVsEquippedPerCrest(item.dps_delta, item.dps_per_crest))
  NS.setDpsDeltaTextColor(metricText, item.dps_delta)

  if item.crest_plan_steps and item.crest_plan_steps > 1 and not item.is_plan_step then
    local planNote = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    planNote:SetPoint("TOPRIGHT", metricText, "BOTTOMRIGHT", 0, -1)
    planNote:SetText(string.format("%d steps in plan", item.crest_plan_steps))
    planNote:SetTextColor(0.45, 0.95, 0.55)
  end

  return yOffset + GA_CREST_ROW_H + 4
end

renderAdvisorRows = function()
  if not advisorFrame or not advisorFrame.itemList or not advisorFrame:IsShown() then return end

  syncAdvisorListHeader()

  for _, row in ipairs(advisorRows) do
    if row then row:Hide(); row:SetParent(nil) end
  end
  advisorRows = {}

  local itemList = advisorFrame.itemList
  local listWidth = itemList:GetWidth() or (GA_WIDTH - GA_PADDING - GA_SCROLL_INSET)
  local yOffset = 4
  local iconsPerLine = math.max(1, math.floor((listWidth - GA_ICONS_COL_X) / (GA_ICON_SIZE + GA_ICON_SPACING)))

  if currentMode == "crests" then
    if #crestRows == 0 then
      local emptyRow = CreateFrame("Frame", nil, itemList)
      table.insert(advisorRows, emptyRow)
      emptyRow:SetSize(listWidth, 44)
      emptyRow:SetPoint("TOPLEFT", itemList, "TOPLEFT", 0, -yOffset)
      local emptyText = emptyRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      emptyText:SetPoint("LEFT", emptyRow, "LEFT", 10, 0)
      emptyText:SetWidth(listWidth - 20)
      emptyText:SetJustifyH("LEFT")
      if advisorScanRunner then
        emptyText:SetText(NS.MSG_CREST_EMPTY_SCANNING)
      elseif #crestAllRows > 0 then
        emptyText:SetText(NS.MSG_CREST_EMPTY_AFFORDABLE)
      else
        emptyText:SetText(NS.MSG_CREST_EMPTY)
      end
      emptyText:SetTextColor(0.55, 0.6, 0.65)
      yOffset = yOffset + 48
    else
      yOffset = renderCrestPlanSection(itemList, listWidth, yOffset)
      if crestPlanIsActive() then
        for i, step in ipairs(crestSpendPlan) do
          yOffset = renderCrestRow(itemList, listWidth, step, i, yOffset)
        end
        yOffset = yOffset + 4
      end
      local displayRows = crestRowsForDisplay()
      if crestPlanIsActive() and #displayRows > 0 then
        yOffset = renderCrestSectionDivider(itemList, listWidth, NS.MSG_CREST_OTHER_UPGRADES, yOffset)
      end
      for i, item in ipairs(displayRows) do
        yOffset = renderCrestRow(itemList, listWidth, item, i, yOffset)
      end
    end
  elseif isShowingLoadoutResults() then
    local vaultWinner = findLoadoutVaultWinnerRow()
    if vaultWinner then
      yOffset = renderLoadoutVaultWinnerBanner(itemList, listWidth, vaultWinner, yOffset)
    end
    for i, item in ipairs(loadoutRows) do
      yOffset = renderLoadoutRow(itemList, listWidth, item, i, yOffset)
    end
  elseif scanComplete then
    local slotRows = buildAdvisorSlotOverviewRows()
    for i, slotRow in ipairs(slotRows) do
      yOffset = renderAdvisorSlotOverviewRow(itemList, listWidth, slotRow, i, yOffset, iconsPerLine)
    end
  else
    local emptyRow = CreateFrame("Frame", nil, itemList)
    table.insert(advisorRows, emptyRow)
    emptyRow:SetSize(listWidth, 28)
    emptyRow:SetPoint("TOPLEFT", itemList, "TOPLEFT", 0, -yOffset)
    local emptyText = emptyRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyText:SetPoint("LEFT", emptyRow, "LEFT", 10, 0)
    if advisorScanRunner then
      emptyText:SetText("Loading gear candidates…")
    elseif not scanComplete then
      emptyText:SetText("Collecting gear candidates…")
    else
      emptyText:SetText(NS.MSG_FIND_LOADOUT_HINT)
    end
    emptyText:SetTextColor(0.55, 0.6, 0.65)
    yOffset = yOffset + 32
  end

  syncActionButtons()

  itemList:SetHeight(math.max(40, yOffset + 8))
  if advisorFrame.scrollFrame then
    advisorFrame.scrollFrame:UpdateScrollChildRect()
  end
end

getScanOpts = function()
  lootControls:ensureSelectedLootUpgrade()
  return {
    upgrades_only = MR_MYTHICAL_DPS_CONFIG.gear_advisor_upgrades_only == true,
    instance_id = lootControls.selectedInstanceId,
    instance_name = lootControls:getInstanceName(lootControls.selectedInstanceId),
    upgrade_key = lootControls.selectedLootUpgradeKey,
    loot_upgrade = lootControls.selectedLootUpgradeKey,
    preset = lootControls:getSelectedLootUpgradePreset(),
    advisor_mode = currentMode,
    sources = NS.getAdvisorSources(currentMode),
  }
end

local function getScanOptsKey(opts)
  opts = opts or getScanOpts()
  local sources = opts.sources or NS.getAdvisorSources(opts.advisor_mode or currentMode) or {}
  return string.format(
    "%s|%s|%s|%s",
    tostring(opts.advisor_mode or currentMode),
    tostring(opts.instance_id),
    tostring(opts.upgrade_key or opts.loot_upgrade),
    NS.serializeAdvisorSources(sources)
  )
end

local function needsLoadoutRescan()
  if not scanComplete or not candidatesBySlot then
    return true
  end
  if not lastLoadoutScanOptsKey then
    return true
  end
  return getScanOptsKey() ~= lastLoadoutScanOptsKey
end

local function ensureAdvisorScan()
  if not advisorFrame or not advisorFrame:IsShown() then
    return
  end
  if advisorScanRunner then
    return
  end
  if not NS.profileDetectionDoneRef[1] or #NS.active_spec_keys == 0 then
    NS.detectAndCacheProfiles()
  end
  local specKey = NS.getActiveProfileKey()
  if not specKey then
    setNoProfileStatus()
    return
  end
  if currentMode == "crests" then
    runCrestScan()
  elseif isLoadoutMode() then
    if needsLoadoutRescan() then
      runAdvisorScan()
    else
      syncActionButtons()
      syncAdvisorStatusText()
      renderAdvisorRows()
    end
  end
end

scheduleAdvisorScan = function()
  if not advisorFrame or not advisorFrame:IsShown() then
    return
  end
  advisorScanScheduleToken = advisorScanScheduleToken + 1
  local token = advisorScanScheduleToken
  C_Timer.After(0, function()
    if token ~= advisorScanScheduleToken then
      return
    end
    ensureAdvisorScan()
  end)
end

local function finishRankScan(runner, rows, errors)
  if advisorScanRunner ~= runner then return end

  upgradeRows = rows or {}
  attachScoredRowsToCandidates(upgradeRows)
  if NS.applyPairedWeaponCandidateScoring then
    NS.applyPairedWeaponCandidateScoring(candidatesBySlot, runner.specKey)
  end
  rebuildCandidateRowsFromSlots()
  NS.applyAdvisorSelectionDefaults(candidateRows, candidatesBySlot, { reset_equipped_baselines = true })
  loadoutVaultWinnerKey = nil

  scanComplete = true
  loadoutSummary = nil
  loadoutRows = {}
  lastLoadoutScanOptsKey = getScanOptsKey(getScanOpts())

  advisorScanRunner = nil
  lastComboSelectionKey = nil
  saveModeScanSnapshot(currentMode)
  syncActionButtons()
  renderAdvisorRows()
  syncVaultTrinketDisclaimer()
  refreshLoadoutComboEstimate()
  local text, highCombo = formatPostScanStatus()
  local color = { 0.55, 1, 0.65 }
  if highCombo then
    color = { 1, 0.65, 0.35 }
  end
  onAdvisorScanEnded(false, text, color)
end

local function startRankScan(runner, refs)
  runner.scoreSession = NS.createGearRefScoreSession(refs, runner.specKey, getScanOpts())
  runner.scoreTotal = #(refs or {})

  local function pumpScore()
    if runner.cancelled or not advisorScanRunner or advisorScanRunner ~= runner then
      return
    end
    local perf = NS.getInitialGearScanPerformanceSettings()
    local session = runner.scoreSession
    local resumes = math.max(1, math.floor(perf.resumes_per_pump or 1))
    for _ = 1, resumes do
      if session.index > runner.scoreTotal then
        break
      end
      NS.scoreGearRefSessionStep(session, perf.score_batch)
    end
    local scored = math.min(session.index - 1, runner.scoreTotal)
    if session.index <= runner.scoreTotal then
      setScanProgressBar(scored, runner.scoreTotal)
      setStatusText(string.format("Scoring %s/%s…", formatComboCount(scored), formatComboCount(runner.scoreTotal)), { 0.95, 0.85, 0.45 })
      NS.scheduleScanPump(perf.batch_delay_sec, pumpScore)
      return
    end
    local rows, errors = NS.finalizeGearRefScoreSession(session)
    finishRankScan(runner, rows, errors)
  end

  setScanProgressBar(0, runner.scoreTotal)
  setStatusText(string.format("Scoring %s/%s…", formatComboCount(0), formatComboCount(runner.scoreTotal)), { 0.95, 0.85, 0.45 })
  NS.scheduleScanPump(0, pumpScore)
end

local function runCrestSpendOptimization()
  local specKey = NS.getActiveProfileKey()
  local plan, spent, totalDps = NS.optimizeCrestSpendPlan(crestAllRows, specKey)
  crestSpendPlan = plan
  crestPlanSummary = NS.formatCrestSpendPlanSummary(plan, spent, totalDps)
  return plan, spent, totalDps
end

local function applyCrestSpendPlanView(opts)
  opts = opts or {}
  if #crestAllRows == 0 then
    return false
  end
  for _, row in ipairs(crestAllRows) do
    row.crest_plan_order = nil
    row.crest_plan_steps = 0
  end
  NS.refreshCrestRowAffordability(crestAllRows)
  runCrestSpendOptimization()
  applyCrestRowFilter()
  refreshCrestChrome()
  renderAdvisorRows()
  if crestPlanSummary then
    setStatusText(crestPlanSummary, { 0.55, 1, 0.65 })
    if opts.flash and crestSpendPlan and #crestSpendPlan > 0 and UIFrameFlash and advisorFrame and advisorFrame.summaryText then
      UIFrameFlash(advisorFrame.summaryText, 0.2, 0.6, 2, false, 0, 0)
    end
  end
  return crestSpendPlan ~= nil and #crestSpendPlan > 0
end

runCrestScan = function()
  local specKey = NS.getActiveProfileKey()
  if not specKey then
    setNoProfileStatus()
    return
  end

  cancelAdvisorScan()
  crestRows = {}
  crestAllRows = {}
  crestSpendPlan = nil
  crestPlanSummary = nil
  clearScanProgressBar()
  renderAdvisorRows()
  setStatusText(NS.MSG_CREST_SCANNING, { 0.95, 0.85, 0.45 })

  advisorScanRunner = { cancelled = false, specKey = specKey }
  local runner = advisorScanRunner
  startScanProgressTiming()
  syncActionButtons()

  C_Timer.After(0, function()
    if not advisorScanRunner or advisorScanRunner.cancelled or advisorScanRunner ~= runner then
      return
    end
    local rows, note = NS.collectCrestUpgradeOpportunities(specKey)
    if not advisorScanRunner or advisorScanRunner.cancelled or advisorScanRunner ~= runner then
      return
    end

    crestAllRows = rows or {}
    for _, row in ipairs(crestAllRows) do
      row.crest_plan_order = nil
      row.crest_plan_steps = 0
    end
    applyCrestRowFilter()
    refreshCrestChrome()

    local upgradeCount = 0
    local affordableCount = 0
    for _, row in ipairs(crestAllRows) do
      if row.is_upgrade then upgradeCount = upgradeCount + 1 end
      if row.can_afford then affordableCount = affordableCount + 1 end
    end

    local statusMsg = string.format(
      "Crests: %s options, %s affordable, %s upgrades%s",
      formatComboCount(#crestAllRows), formatComboCount(affordableCount), formatComboCount(upgradeCount),
      note and (", " .. note) or ""
    )
    advisorScanRunner = nil
    syncActionButtons()
    saveModeScanSnapshot(currentMode)
    if #crestRows > 0 then
      applyCrestSpendPlanView()
      if crestPlanSummary then
        onAdvisorScanEnded(false, crestPlanSummary, { 0.55, 1, 0.65 })
      else
        onAdvisorScanEnded(false, statusMsg, { 0.55, 1, 0.65 })
      end
    else
      setStatusText(statusMsg, { 0.55, 1, 0.65 })
      renderAdvisorRows()
      onAdvisorScanEnded(false, statusMsg, { 0.55, 1, 0.65 })
    end
  end)
end

local function finishCandidateGather(runner, lootRefs, lootNote)
  if not advisorScanRunner or advisorScanRunner ~= runner or runner.cancelled then
    return
  end
  local specKey = runner.specKey
  local opts = runner.scanOpts or getScanOpts()
  opts.loot_refs = lootRefs or {}
  opts.loot_note = lootNote
  candidatesBySlot, flatRefs, statusNote = NS.collectGearCandidates(specKey, opts)
  if lootNote and lootNote ~= "" then
    statusNote = statusNote and (statusNote .. " " .. lootNote) or lootNote
  end
  startRankScan(runner, flatRefs or {})
end

local function pumpAdvisorLootScan(runner)
  if runner.cancelled or not advisorScanRunner or advisorScanRunner ~= runner then
    return
  end
  local lootRunner = runner.lootRunner
  if not lootRunner or lootRunner.cancelled then
    return
  end

  local result = NS.pumpEncounterJournalLootRunner(lootRunner, function(msg)
    setStatusText(msg, { 0.95, 0.85, 0.45 })
  end)

  if result == "wait_ej" or result == "wait_items" then
    C_Timer.After(0.25, function()
      pumpAdvisorLootScan(runner)
    end)
    return
  end
  if result == "cancelled" then
    if advisorScanRunner == runner then
      advisorScanRunner = nil
      syncActionButtons()
      setStatusText("Scan cancelled.", { 0.95, 0.85, 0.45 })
      onAdvisorScanEnded(true, "Scan cancelled.", { 0.95, 0.85, 0.45 })
    end
    return
  end
  if result == "continue" then
    C_Timer.After(0, function()
      pumpAdvisorLootScan(runner)
    end)
    return
  end
  if result == "complete" then
    runner.lootRunner = nil
    finishCandidateGather(runner, lootRunner.allRefs, lootRunner.statusNote)
  end
end

runAdvisorScan = function()
  local specKey = NS.getActiveProfileKey()
  if not specKey then
    setNoProfileStatus()
    return
  end

  cancelComboEstimate()
  lastComboSelectionKey = nil
  cancelAdvisorScan()
  clearScanProgressBar()
  scanComplete = false
  estimatedCombinations = nil
  loadoutSummary = nil
  loadoutRows = {}
  upgradeRows = {}
  candidateRows = {}
  statusNote = nil

  advisorScanRunner = { cancelled = false, specKey = specKey }
  local runner = advisorScanRunner
  local scanOpts = getScanOpts()
  runner.scanOpts = scanOpts
  startScanProgressTiming()
  syncActionButtons()
  renderAdvisorRows()
  setStatusText("Collecting gear candidates…", { 0.95, 0.85, 0.45 })

  if scanOpts.sources and scanOpts.sources.loot then
    lootControls:ensureSelectedInstance()
    runner.lootRunner = NS.beginEncounterJournalLootRunner(
      specKey,
      scanOpts.instance_id,
      scanOpts.instance_name,
      scanOpts
    )
    if runner.lootRunner.mode == "all" and #(runner.lootRunner.instanceList or {}) == 0 then
      statusNote = "No current-season instances found. Open the Encounter Journal (J), then try again."
      candidatesBySlot = {}
      flatRefs = {}
      advisorScanRunner = nil
      scanComplete = true
      syncActionButtons()
      setStatusText(statusNote, { 1, 0.75, 0.4 })
      renderAdvisorRows()
      onAdvisorScanEnded(false, statusNote, { 1, 0.75, 0.4 })
      return
    end
    C_Timer.After(0, function()
      pumpAdvisorLootScan(runner)
    end)
    return
  end

  C_Timer.After(0, function()
    if not advisorScanRunner or advisorScanRunner.cancelled or advisorScanRunner ~= runner then
      return
    end
    lootControls:ensureSelectedInstance()
    candidatesBySlot, flatRefs, statusNote = NS.collectGearCandidates(specKey, scanOpts)
    if not advisorScanRunner or advisorScanRunner.cancelled then
      return
    end
    startRankScan(runner, flatRefs or {})
  end)
end

local function startFindLoadoutScan()
  if not scanComplete or not candidatesBySlot then
    return
  end
  local specKey = NS.getActiveProfileKey()
  if not specKey then return end

  cancelAdvisorScan()
  clearScanProgressBar()
  local selectedCount = countSelectedCandidates()
  loadoutVaultWinnerKey = nil
  resetLoadoutEquipState()

  advisorScanRunner = { cancelled = false, specKey = specKey }
  local runner = advisorScanRunner
  startScanProgressTiming()
  syncActionButtons()

  NS.runBestLoadoutScan(specKey, candidatesBySlot, {
    runner = runner,
    onReady = function(info)
      setScanProgressBar(0, info.total or 0)
      setStatusText(string.format(
        "Finding best loadout… %s items selected, %s combinations to check",
        formatComboCount(selectedCount), formatComboCount(info.total or 0)
      ), { 0.95, 0.85, 0.45 })
    end,
    onProgress = function(payload)
      setScanProgressBar(payload.checked or 0, payload.total or 0)
      setStatusText(string.format(
        "Finding best loadout… %s / %s combinations checked",
        formatComboCount(payload.checked or 0), formatComboCount(payload.total or 0)
      ), { 0.95, 0.85, 0.45 })
    end,
  }, function(cancelled, err, payload)
    if not cancelled and not runner.cancelled and advisorScanRunner ~= runner then return end
    if advisorScanRunner == runner then
      advisorScanRunner = nil
    end
    syncActionButtons()

    if cancelled or runner.cancelled then
      applyPostScanStatus()
      if not runner.cancelled then
        onAdvisorScanEnded(true, "Loadout search cancelled.", { 0.95, 0.85, 0.45 })
      end
      return
    end
    if err then
      setStatusText("Loadout search failed.", { 1, 0.5, 0.5 })
      onAdvisorScanEnded(false, "Loadout search failed.", { 1, 0.5, 0.5 })
      return
    end

    if payload and payload.hasResult then
      loadoutSummary = payload.summary
      loadoutRows = payload.slotRows or {}
      setLoadoutVaultWinnerFromRows()
      local resultMsg = formatLoadoutResultMessage(loadoutSummary, loadoutRows)
      setStatusText(resultMsg, { 0.55, 1, 0.65 })
      onAdvisorScanEnded(false, resultMsg, { 0.55, 1, 0.65 })
    else
      loadoutSummary = nil
      loadoutRows = {}
      loadoutVaultWinnerKey = nil
      local failMsg = "No valid loadout for the current selection."
      setStatusText(failMsg, { 0.85, 0.55, 0.55 })
      onAdvisorScanEnded(false, failMsg, { 0.85, 0.55, 0.55 })
    end
    renderAdvisorRows()
    syncActionButtons()
    saveModeScanSnapshot(currentMode)
  end)
end

local function runFindLoadout()
  if not scanComplete or not candidatesBySlot then
    return
  end
  if comboCountInProgress then
    return
  end
  startFindLoadoutScan()
end

local function setupScanPerfDropdownTooltip(dropdown)
  if not dropdown or dropdown.mrMythicalTooltipHooked then
    return
  end
  local btn = dropdown.Button or _G[dropdown:GetName() .. "Button"]
  if not btn then
    return
  end
  dropdown.mrMythicalTooltipHooked = true
  btn:HookScript("OnEnter", function(self)
    local title, body = NS.getScanPerformanceButtonTooltip()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 0.92, 0.55)
    GameTooltip:AddLine(body, 0.85, 0.85, 0.85, true)
    GameTooltip:Show()
  end)
  btn:HookScript("OnLeave", function()
    GameTooltip:Hide()
  end)
end

local function populateScanPerfDropdown()
  if not advisorFrame or not advisorFrame.perfDropdown then
    return
  end
  local perfDropdown = advisorFrame.perfDropdown
  UIDropDownMenu_Initialize(perfDropdown, function(_, level)
    for _, modeId in ipairs(NS.SCAN_PERFORMANCE_USER_MODES) do
      local preset = NS.SCAN_PERFORMANCE_PRESETS[modeId]
      local info = UIDropDownMenu_CreateInfo()
      info.text = preset.label
      info.tooltipTitle = preset.label
      info.tooltipText = preset.hint
      info.notCheckable = true
      info.func = function()
        NS.setScanPerformanceMode(modeId)
        syncScanPerfControls()
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  setupScanPerfDropdownTooltip(perfDropdown)
end

local function populateIlvlDropdown()
  if not advisorFrame or not advisorFrame.ilvlDropdown then return end
  lootControls:populateIlvlDropdown(advisorFrame.ilvlDropdown, function()
    if currentMode == "loot" then
      scheduleAdvisorScan()
    end
  end)
end

local function populateInstanceDropdown()
  if not advisorFrame or not advisorFrame.instanceDropdown then return end
  lootControls:populateInstanceDropdown(advisorFrame.instanceDropdown, function()
    if currentMode == "loot" then
      scheduleAdvisorScan()
    end
  end)
end

local function resolveAdvisorOpenMode(prefillSources, prefillMode)
  if prefillMode then
    return normalizeAdvisorMode(prefillMode)
  end
  if prefillSources then
    if prefillSources.loot == true then
      return "loot"
    end
    if prefillSources.bag == true then
      return "bags"
    end
  end
  return normalizeAdvisorMode(MR_MYTHICAL_DPS_CONFIG.gear_advisor_mode or "bags")
end

local function createGearAdvisorFrame(prefillSources, prefillMode)
  local openMode = resolveAdvisorOpenMode(prefillSources, prefillMode)
  if advisorFrame then
    NS.refreshGearAdvisorChrome()
    if currentMode ~= openMode then
      selectMode(openMode)
    else
      syncModeTabs()
      syncModeUI()
      syncAdvisorStatusText()
      if advisorFrame:IsShown() then
        scheduleAdvisorScan()
      end
    end
    syncVaultTrinketDisclaimer()
    return advisorFrame
  end

  local f = CreateFrame("Frame", "MrMythicalDpsGearAdvisorFrame", UIParent, "BackdropTemplate")
  f:SetSize(GA_WIDTH, GA_HEIGHT)
  f:SetFrameStrata("DIALOG")
  f:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  f:SetBackdropColor(0.08, 0.08, 0.1, 0.96)
  f:SetBackdropBorderColor(0.45, 0.45, 0.55, 1)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    MR_MYTHICAL_DPS_CONFIG.gear_advisor_point = { point, relPoint, x, y }
  end)
  f:SetScript("OnShow", function()
    if isAdvisorScanActive() then
      local lastText, lastColor = NS.AdvisorScanProgress.getLastStatus()
      if lastText then
        setStatusText(lastText, lastColor)
      end
    else
      syncAdvisorStatusText()
    end
    NS.AdvisorScanProgress.refreshTimerDisplay()
    hideScanProgressPopup()
    syncVaultTrinketDisclaimer()
    NS.refreshGearAdvisorChrome()
    syncScanPerfControls()
    scheduleAdvisorScan()
  end)
  f:SetScript("OnHide", function()
    comboEstimateScheduleToken = comboEstimateScheduleToken + 1
    if isComboEstimateActive() then
      cancelComboEstimate()
    end
    if isAdvisorScanActive() then
      NS.AdvisorScanProgress.showIfScanActive()
    end
  end)

  if MR_MYTHICAL_DPS_CONFIG.gear_advisor_point then
    local p = MR_MYTHICAL_DPS_CONFIG.gear_advisor_point
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  elseif MR_MYTHICAL_DPS_CONFIG.dashboard_point then
    local p = MR_MYTHICAL_DPS_CONFIG.dashboard_point
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    f:SetPoint("CENTER")
  end

  local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", GA_PADDING, -10)
  title:SetText(NS.BRAND)
  title:SetTextColor(1, 0.92, 0.55)

  local versionText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  versionText:SetPoint("LEFT", title, "RIGHT", 8, 0)
  versionText:SetText("v" .. NS.getAddonVersion())
  versionText:SetTextColor(0.55, 0.6, 0.65)
  f.versionText = versionText

  local disclaimerText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  disclaimerText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
  disclaimerText:SetWidth(GA_WIDTH - GA_PADDING * 2 - 40)
  disclaimerText:SetJustifyH("LEFT")
  disclaimerText:SetText(NS.DISCLAIMER_HEADER)
  disclaimerText:SetTextColor(0.5, 0.52, 0.58)

  local profileSectionLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  profileSectionLabel:SetPoint("TOPLEFT", disclaimerText, "BOTTOMLEFT", 0, -6)
  profileSectionLabel:SetText("Hero talent profile:")
  profileSectionLabel:SetTextColor(0.75, 0.8, 0.85)

  profileCallout = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  profileCallout:SetPoint("TOPLEFT", profileSectionLabel, "BOTTOMLEFT", 0, -2)
  profileCallout:SetWidth(420)
  profileCallout:SetJustifyH("LEFT")
  profileCallout:SetTextColor(1, 0.82, 0.2)
  profileCallout:Hide()

  local profileDropdown = CreateFrame("Frame", "MrMythicalDpsAdvisorProfileDropdown", f, "UIDropDownMenuTemplate")
  profileDropdown:SetPoint("TOPLEFT", profileSectionLabel, "BOTTOMLEFT", -16, -16)
  f.profileDropdown = profileDropdown

  local modeBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
  modeBar:SetPoint("TOP", profileDropdown, "BOTTOM", 0, -8)
  modeBar:SetPoint("LEFT", f, "LEFT", GA_PADDING, 0)
  modeBar:SetPoint("RIGHT", f, "RIGHT", -GA_PADDING, 0)
  modeBar:SetHeight(26)
  modeBar:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", tile = true, tileSize = 16 })
  modeBar:SetBackdropColor(0.12, 0.12, 0.16, 0.8)
  f.modeBar = modeBar
  f.modeButtons = {}

  local MODE_TAB_WIDTHS = { bags = 120, loot = 210, crests = 155 }
  local mx = 6
  for _, mode in ipairs(MODE_TABS) do
    local btn = CreateFrame("Button", nil, modeBar, "BackdropTemplate")
    local tabWidth = MODE_TAB_WIDTHS[mode.id] or 150
    btn:SetSize(tabWidth, 22)
    btn:SetPoint("LEFT", modeBar, "LEFT", mx, 0)
    btn:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", tile = true, tileSize = 8 })
    btn:SetBackdropColor(0.14, 0.14, 0.18, 0.9)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(mode.label)
    btn:SetScript("OnClick", function() selectMode(mode.id) end)
    f.modeButtons[mode.id] = btn
    mx = mx + tabWidth + 6
  end

  local statusFrame = CreateFrame("Frame", nil, f)
  statusFrame:SetPoint("TOP", modeBar, "BOTTOM", 0, -4)
  statusFrame:SetPoint("LEFT", f, "LEFT", GA_PADDING, 0)
  statusFrame:SetPoint("RIGHT", f, "RIGHT", -GA_PADDING, 0)
  statusFrame:SetHeight(GA_STATUS_H)
  f.statusFrame = statusFrame

  local summaryText = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  summaryText:SetPoint("TOPLEFT", statusFrame, "TOPLEFT", 0, 0)
  summaryText:SetPoint("TOPRIGHT", statusFrame, "TOPRIGHT", 0, 0)
  summaryText:SetJustifyH("LEFT")
  summaryText:SetWordWrap(true)
  summaryText:SetText(NS.MSG_FIND_LOADOUT_HINT)
  f.summaryText = summaryText

  local scanTimerText = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  scanTimerText:SetPoint("TOPLEFT", summaryText, "BOTTOMLEFT", 0, 0)
  scanTimerText:SetPoint("TOPRIGHT", summaryText, "BOTTOMRIGHT", 0, 0)
  scanTimerText:SetJustifyH("LEFT")
  scanTimerText:SetTextColor(0.6, 0.75, 0.85)
  scanTimerText:Hide()
  f.scanTimerText = scanTimerText

  local actionBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
  actionBar:SetPoint("TOP", statusFrame, "BOTTOM", 0, -2)
  actionBar:SetPoint("LEFT", f, "LEFT", GA_PADDING, 0)
  actionBar:SetPoint("RIGHT", f, "RIGHT", -GA_PADDING, 0)
  actionBar:SetHeight(GA_ACTION_H)
  actionBar:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", tile = true, tileSize = 16 })
  actionBar:SetBackdropColor(0.14, 0.14, 0.18, 0.75)
  f.actionBar = actionBar

  local vaultStatusText = actionBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  vaultStatusText:SetPoint("RIGHT", actionBar, "RIGHT", -8, 0)
  vaultStatusText:SetWidth(340)
  vaultStatusText:SetJustifyH("RIGHT")
  f.vaultStatusText = vaultStatusText

  local findLoadoutBtn = CreateFrame("Button", nil, actionBar, "UIPanelButtonTemplate")
  findLoadoutBtn:SetSize(110, 24)
  findLoadoutBtn:SetPoint("TOPLEFT", actionBar, "TOPLEFT", 8, -4)
  findLoadoutBtn:SetText("Find Loadout")
  findLoadoutBtn:SetScript("OnClick", runFindLoadout)
  f.findLoadoutBtn = findLoadoutBtn

  local changeSelectionBtn = CreateFrame("Button", nil, actionBar, "UIPanelButtonTemplate")
  changeSelectionBtn:SetSize(120, 24)
  changeSelectionBtn:SetPoint("TOPLEFT", actionBar, "TOPLEFT", 8, -4)
  changeSelectionBtn:SetText("Change Selection")
  changeSelectionBtn:Hide()
  changeSelectionBtn:SetScript("OnClick", returnToSelectionView)
  f.changeSelectionBtn = changeSelectionBtn

  local stopScanBtn = CreateFrame("Button", nil, actionBar, "UIPanelButtonTemplate")
  stopScanBtn:SetSize(90, 24)
  stopScanBtn:SetPoint("TOPLEFT", actionBar, "TOPLEFT", 8, -4)
  stopScanBtn:SetText("Stop Scan")
  stopScanBtn:Hide()
  stopScanBtn:SetScript("OnClick", stopAdvisorScan)
  f.stopScanBtn = stopScanBtn

  local upgradeFilterFrame = CreateFrame("Frame", nil, actionBar)
  upgradeFilterFrame:SetPoint("TOPLEFT", findLoadoutBtn, "TOPRIGHT", 12, 0)
  upgradeFilterFrame:SetHeight(56)
  f.upgradeFilterFrame = upgradeFilterFrame

  local upgradesOnlyCheck = CreateFrame("CheckButton", nil, upgradeFilterFrame, "UICheckButtonTemplate")
  upgradesOnlyCheck:SetPoint("TOPLEFT", upgradeFilterFrame, "TOPLEFT", 0, 0)
  setupAdvisorCheckbox(upgradesOnlyCheck, "Upgrades only", false)
  upgradesOnlyCheck:SetChecked(MR_MYTHICAL_DPS_CONFIG.gear_advisor_upgrades_only == true)
  upgradesOnlyCheck:SetScript("OnClick", function(self)
    MR_MYTHICAL_DPS_CONFIG.gear_advisor_upgrades_only = self:GetChecked() and true or false
    onUpgradeFilterChanged()
  end)
  f.upgradesOnlyCheck = upgradesOnlyCheck

  local sidegradeCheck = CreateFrame("CheckButton", nil, upgradeFilterFrame, "UICheckButtonTemplate")
  sidegradeCheck:SetPoint("TOPLEFT", upgradesOnlyCheck, "BOTTOMLEFT", 0, 6)
  setupAdvisorCheckbox(sidegradeCheck, "Include sidegrades & small downgrades", true)
  sidegradeCheck:SetChecked(MR_MYTHICAL_DPS_CONFIG.gear_advisor_include_sidegrades == true)
  sidegradeCheck:SetScript("OnClick", function(self)
    NS.setAdvisorIncludeSidegrades(self:GetChecked())
    onUpgradeFilterChanged()
  end)
  f.sidegradeCheck = sidegradeCheck

  local crestFilterFrame = CreateFrame("Frame", nil, actionBar)
  crestFilterFrame:SetPoint("LEFT", actionBar, "LEFT", 8, 0)
  crestFilterFrame:SetSize(700, 24)
  crestFilterFrame:Hide()
  f.crestFilterFrame = crestFilterFrame

  local crestBalanceText = crestFilterFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  crestBalanceText:SetPoint("LEFT", crestFilterFrame, "LEFT", 0, 0)
  crestBalanceText:SetPoint("RIGHT", crestFilterFrame, "RIGHT", 0, 0)
  crestBalanceText:SetJustifyH("LEFT")
  crestBalanceText:SetTextColor(0.62, 0.68, 0.74)
  f.crestBalanceText = crestBalanceText

  local instanceDropdown = CreateFrame("Frame", "MrMythicalDpsAdvisorInstanceDropdown", actionBar, "UIDropDownMenuTemplate")
  instanceDropdown:SetPoint("RIGHT", actionBar, "RIGHT", -8, -2)
  UIDropDownMenu_SetWidth(instanceDropdown, 180)
  instanceDropdown:Hide()
  f.instanceDropdown = instanceDropdown

  local ilvlDropdown = CreateFrame("Frame", "MrMythicalDpsAdvisorIlvlDropdown", actionBar, "UIDropDownMenuTemplate")
  ilvlDropdown:SetPoint("RIGHT", instanceDropdown, "LEFT", -8, 0)
  UIDropDownMenu_SetWidth(ilvlDropdown, 130)
  ilvlDropdown:Hide()
  f.ilvlDropdown = ilvlDropdown

  local perfDropdown = CreateFrame("Frame", "MrMythicalDpsAdvisorPerfDropdown", actionBar, "UIDropDownMenuTemplate")
  perfDropdown:SetPoint("TOPRIGHT", actionBar, "TOPRIGHT", -8, -2)
  UIDropDownMenu_SetWidth(perfDropdown, 118)
  f.perfDropdown = perfDropdown

  local perfToggleBtn = CreateFrame("Button", nil, actionBar, "UIPanelButtonTemplate")
  perfToggleBtn:SetSize(132, 24)
  perfToggleBtn:SetPoint("TOPRIGHT", actionBar, "TOPRIGHT", -8, -4)
  perfToggleBtn:Hide()
  perfToggleBtn:SetScript("OnClick", function()
    toggleAdvisorScanPerformance()
  end)
  f.perfToggleBtn = perfToggleBtn

  local lootHint = actionBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  lootHint:SetPoint("RIGHT", ilvlDropdown, "LEFT", -8, 0)
  lootHint:SetText("")
  lootHint:Hide()
  f.lootHint = lootHint

  local headerFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
  headerFrame:SetPoint("TOP", actionBar, "BOTTOM", 0, -4)
  headerFrame:SetPoint("LEFT", f, "LEFT", GA_PADDING, 0)
  headerFrame:SetPoint("RIGHT", f, "RIGHT", -GA_SCROLL_INSET, 0)
  headerFrame:SetHeight(GA_HEADER_H)
  headerFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 1,
  })
  headerFrame:SetBackdropColor(0.18, 0.18, 0.22, 0.9)
  f.headerFrame = headerFrame

  local headerSlot = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  headerSlot:SetPoint("LEFT", headerFrame, "LEFT", 10, 0)
  headerSlot:SetText("Slot")
  headerSlot:SetTextColor(0.85, 0.85, 0.9)
  f.headerSlot = headerSlot

  local headerDetail = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  headerDetail:SetPoint("LEFT", headerFrame, "LEFT", GA_ICONS_COL_X, 0)
  headerDetail:SetText("Item")
  headerDetail:SetTextColor(0.85, 0.85, 0.9)
  f.headerDetail = headerDetail

  local headerMetric = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  headerMetric:SetPoint("RIGHT", headerFrame, "RIGHT", -10, 0)
  headerMetric:SetText(NS.DPS_VS_EQUIPPED_LABEL)
  headerMetric:SetTextColor(0.85, 0.85, 0.9)
  f.headerMetric = headerMetric

  local headerRec = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  headerRec:SetPoint("LEFT", headerFrame, "LEFT", GA_LOADOUT_REC_X, 0)
  headerRec:SetText(NS.LOADOUT_RECOMMENDED_LABEL)
  headerRec:SetTextColor(0.85, 0.85, 0.9)
  headerRec:Hide()
  f.headerRec = headerRec

  local headerUpgradeStep = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  headerUpgradeStep:SetPoint("LEFT", headerFrame, "LEFT", GA_CREST_STEP_X, 0)
  headerUpgradeStep:SetText(NS.CREST_HEADER_STEP)
  headerUpgradeStep:SetTextColor(0.85, 0.85, 0.9)
  headerUpgradeStep:Hide()
  f.headerUpgradeStep = headerUpgradeStep

  local headerCost = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  headerCost:SetPoint("RIGHT", headerFrame, "RIGHT", -GA_CREST_COST_RIGHT, 0)
  headerCost:SetText(NS.CREST_HEADER_COST)
  headerCost:SetTextColor(0.85, 0.85, 0.9)
  headerCost:Hide()
  f.headerCost = headerCost

  local scrollFrame = CreateFrame("ScrollFrame", "MrMythicalDpsGearAdvisorScroll", f, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -4)
  scrollFrame:SetPoint("TOPRIGHT", headerFrame, "BOTTOMRIGHT", 0, -4)
  scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -GA_SCROLL_INSET, GA_PADDING)
  f.scrollFrame = scrollFrame

  local itemList = CreateFrame("Frame", nil, scrollFrame)
  itemList:SetSize(scrollFrame:GetWidth() or (GA_WIDTH - GA_PADDING - GA_SCROLL_INSET), 1)
  scrollFrame:SetScrollChild(itemList)
  f.itemList = itemList

  UIDropDownMenu_Initialize(profileDropdown, function(_, level)
    local info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true
    info.text = "Select profile"
    info.func = function()
      clearModeScanCache()
      NS.setActiveProfileKey(nil)
      NS.refreshGearAdvisorChrome()
      scheduleAdvisorScan()
    end
    UIDropDownMenu_AddButton(info, level)

    for _, profileKey in ipairs(NS.active_spec_keys) do
      info = UIDropDownMenu_CreateInfo()
      info.notCheckable = true
      local label = NS.getProfileLabel(profileKey)
      if MR_MYTHICAL_DPS_CONFIG.debug then
        label = label .. " (" .. profileKey .. ")"
      end
      info.text = label
      info.func = function()
        clearModeScanCache()
        NS.setActiveProfileKey(profileKey)
        NS.refreshGearAdvisorChrome()
        scheduleAdvisorScan()
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  advisorFrame = f
  lootControls.selectedInstanceId = MR_MYTHICAL_DPS_CONFIG.gear_advisor_instance_id or NS.GEAR_FINDER_ALL_INSTANCES
  lootControls:ensureSelectedLootUpgrade()
  NS.ensureEncounterJournalLoaded()
  populateInstanceDropdown()
  populateIlvlDropdown()
  populateScanPerfDropdown()
  currentMode = openMode
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_mode = openMode
  syncModeTabs()
  syncModeUI()
  syncAdvisorStatusText()
  setupVaultFrameHooks()
  NS.refreshGearAdvisorChrome()
  syncActionButtons()
  renderAdvisorRows()

  return f
end

function NS.createGearAdvisorFrame(prefillSources, prefillMode)
  return createGearAdvisorFrame(prefillSources, prefillMode)
end

function NS.refreshGearAdvisorChrome(highlightAmbiguous)
  if not advisorFrame then
    return
  end
  local f = advisorFrame

  if f.versionText then
    f.versionText:SetText("v" .. NS.getAddonVersion())
  end

  local active = NS.getActiveProfileKey()
  local dropLabel = "Select profile…"
  if active then
    dropLabel = NS.getProfileLabel(active)
    if MR_MYTHICAL_DPS_CONFIG.debug then
      dropLabel = dropLabel .. " (" .. active .. ")"
    end
  end
  if f.profileDropdown then
    UIDropDownMenu_SetText(f.profileDropdown, dropLabel)
  end

  if profileCallout then
    if highlightAmbiguous or NS.isProfileAmbiguous() then
      profileCallout:SetText("Pick a hero talent build that matches your current talents.")
      profileCallout:Show()
    elseif NS.getProfileMatchInfo and NS.getProfileMatchInfo().lowConfidence then
      profileCallout:SetText(NS.MSG_PROFILE_LOW_CONFIDENCE)
      profileCallout:Show()
    else
      profileCallout:Hide()
    end
  end

end

function NS.refreshDashboard()
  NS.refreshGearAdvisorChrome()
end

function NS.hideGearAdvisorFrame()
  if advisorFrame then advisorFrame:Hide() end
end

function NS.openGearAdvisor(prefillSources, prefillMode, highlightAmbiguous)
  hideScanProgressPopup()
  local frame = createGearAdvisorFrame(prefillSources, prefillMode)
  frame:Show()
  NS.refreshGearAdvisorChrome(highlightAmbiguous)
  scheduleAdvisorScan()
  return frame
end

function NS.openDashboard(highlightAmbiguous)
  return NS.openGearAdvisor(nil, nil, highlightAmbiguous)
end

function NS.getCachedCrestSpendPlanData()
  if crestSpendPlan and #crestSpendPlan > 0 then
    return crestSpendPlan, crestPlanSummary
  end
  return nil
end

-- Legacy wrappers
function NS.createGearFinderFrame()
  return NS.createGearAdvisorFrame(nil, "loot")
end

function NS.createBagComparisonFrame()
  return NS.createGearAdvisorFrame(nil, "bags")
end

NS.AdvisorScanProgress.register({
  isScanActive = isAdvisorScanActive,
  isLoadoutSearchActive = isLoadoutSearchActive,
  getAdvisorFrame = function() return advisorFrame end,
  getScanTypeLabel = getActiveScanTypeLabel,
  onStopScan = stopAdvisorScan,
  onTogglePerformance = toggleAdvisorScanPerformance,
})

local advisorLootEventFrame = CreateFrame("Frame")
advisorLootEventFrame:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
advisorLootEventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
advisorLootEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
advisorLootEventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
advisorLootEventFrame:SetScript("OnEvent", function(_, event, itemID)
  if event == "PLAYER_EQUIPMENT_CHANGED" then
    if next(pendingEquips) then
      C_Timer.After(0.05, verifyPendingEquips)
    end
    return
  end
  if event == "PLAYER_ENTERING_WORLD" then
    if currentMode == "loot" and NS.invalidateEjDungeonLookup then
      NS.invalidateEjDungeonLookup()
    end
    return
  end
  if currentMode ~= "loot" or not advisorScanRunner or advisorScanRunner.cancelled then
    return
  end
  local runner = advisorScanRunner
  local lootRunner = runner.lootRunner
  if not lootRunner or lootRunner.cancelled then
    return
  end
  if event == "EJ_LOOT_DATA_RECIEVED" and lootRunner.waiting == "ej" then
    lootRunner.waiting = nil
    pumpAdvisorLootScan(runner)
    return
  end
  if event == "ITEM_DATA_LOAD_RESULT" and lootRunner.waiting == "items" and lootRunner.pendingItemIds then
    if itemID then
      lootRunner.pendingItemIds[itemID] = nil
    end
    if not next(lootRunner.pendingItemIds) then
      lootRunner.waiting = nil
      pumpAdvisorLootScan(runner)
    end
  end
end)
