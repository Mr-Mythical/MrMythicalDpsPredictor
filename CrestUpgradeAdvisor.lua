local ADDON_NAME, NS = ...

local litePanel = nil
local liteRows = {}
local litePlan = nil
local liteSummary = nil
local liteScanScheduleToken = 0
local liteScanWorkToken = 0
local liteScanInProgress = false
local liteActiveInvSlot = nil

local LITE_WIDTH = 340
local LITE_ROW_H = 50
local LITE_VISIBLE_ROWS = 7
local LITE_SCROLL_H = LITE_ROW_H * LITE_VISIBLE_ROWS

local function isItemUpgradeFrameOpen()
  return NS.isItemUpgradeFrameOpen and NS.isItemUpgradeFrameOpen()
end

local function getItemUpgradeFrame()
  return _G.ItemUpgradeFrame
end

local function positionLitePanel()
  if not litePanel or not litePanel:IsShown() then
    return
  end
  local upgradeFrame = getItemUpgradeFrame()
  litePanel:ClearAllPoints()
  if upgradeFrame and upgradeFrame:IsShown() then
    litePanel:SetPoint("TOPLEFT", upgradeFrame, "TOPRIGHT", 10, 0)
  else
    litePanel:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
  end
end

local function setLiteStatus(text, r, g, b)
  if not litePanel then
    return
  end
  local showMessage = text ~= nil and text ~= ""
  if litePanel.statusText then
    litePanel.statusText:SetShown(showMessage)
    litePanel.statusText:SetText(text or "")
    litePanel.statusText:SetTextColor(r or 0.75, g or 0.78, b or 0.85)
  end
  if litePanel.scrollFrame then
    litePanel.scrollFrame:SetShown(not showMessage)
  end
end

local function readUpgradeFrameInvSlot()
  local frame = getItemUpgradeFrame()
  if not frame or not frame:IsShown() or not litePlan then
    return nil
  end
  local loc = frame.itemLocation or frame.ItemLocation
  if loc and loc.IsValid and loc:IsValid() and loc.GetEquipmentSlotIndex then
    local ok, slot = pcall(loc.GetEquipmentSlotIndex, loc)
    if ok and slot then
      return slot
    end
  end
  if C_ItemUpgrade and C_ItemUpgrade.GetItemHyperlink then
    local ok, link = pcall(C_ItemUpgrade.GetItemHyperlink)
    if ok and link then
      local itemID = tonumber(link:match("item:(%d+)"))
      for _, step in ipairs(litePlan) do
        if step.link == link or step.preview_link == link then
          return step.inv_slot
        end
        local stepID = step.link and tonumber(step.link:match("item:(%d+)"))
        if itemID and stepID and itemID == stepID then
          return step.inv_slot
        end
      end
    end
  end
  if C_ItemUpgrade and C_ItemUpgrade.GetItemUpgradeItemInfo then
    local ok, info = pcall(C_ItemUpgrade.GetItemUpgradeItemInfo)
    if ok and info and info.name then
      for _, step in ipairs(litePlan) do
        if step.name == info.name or step.preview_name == info.name then
          return step.inv_slot
        end
      end
    end
  end
  return nil
end

local function clearLiteRows()
  for _, row in ipairs(liteRows) do
    if row then
      row:Hide()
      row:SetParent(nil)
    end
  end
  liteRows = {}
end

local function renderLitePlan()
  if not litePanel or not litePanel.itemList then
    return
  end
  clearLiteRows()

  liteActiveInvSlot = readUpgradeFrameInvSlot()

  if not litePlan or #litePlan == 0 then
    setLiteStatus(NS.MSG_CREST_EMPTY_AFFORDABLE, 0.55, 0.6, 0.65)
    return
  end

  setLiteStatus(nil)
  if litePanel.summaryText then
    litePanel.summaryText:SetText(liteSummary or "")
  end
  if litePanel.balanceText then
    litePanel.balanceText:SetText(NS.formatCrestBalancesLine and NS.formatCrestBalancesLine() or "")
  end

  local itemList = litePanel.itemList
  local listWidth = (itemList:GetWidth() or LITE_WIDTH) - 8
  local yOffset = 2

  for _, step in ipairs(litePlan) do
    local isActive = liteActiveInvSlot and step.inv_slot and step.inv_slot == liteActiveInvSlot
    local row = CreateFrame("Frame", nil, itemList, "BackdropTemplate")
    table.insert(liteRows, row)
    row:SetSize(listWidth, LITE_ROW_H - 4)
    row:SetPoint("TOPLEFT", itemList, "TOPLEFT", 4, -yOffset)
    row:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", tile = true, tileSize = 16 })
    if isActive then
      row:SetBackdropColor(0.1, 0.22, 0.14, 0.95)
    elseif (step.order or 0) % 2 == 0 then
      row:SetBackdropColor(0.13, 0.13, 0.16, 0.85)
    else
      row:SetBackdropColor(0.1, 0.1, 0.13, 0.75)
    end

    if isActive then
      local accent = row:CreateTexture(nil, "ARTWORK")
      accent:SetColorTexture(0.35, 0.9, 0.45, 0.9)
      accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
      accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
      accent:SetWidth(3)
    end

    local stepBadge = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stepBadge:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -6)
    stepBadge:SetWidth(72)
    stepBadge:SetJustifyH("LEFT")
    stepBadge:SetText(string.format("#%d %s", step.order or 0, step.slot_label or ""))
    stepBadge:SetTextColor(isActive and 0.55 or 0.62, isActive and 1 or 0.66, isActive and 0.65 or 0.7)

    local upgradeLine = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    upgradeLine:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -22)
    upgradeLine:SetWidth(listWidth - 16)
    upgradeLine:SetJustifyH("LEFT")
    upgradeLine:SetText(NS.formatCrestUpgradeStepLine(step))
    upgradeLine:SetTextColor(0.68, 0.72, 0.78)

    local costText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    costText:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 4)
    costText:SetWidth(130)
    costText:SetJustifyH("RIGHT")
    costText:SetText(step.crest_label or tostring(step.crest_cost or 0))
    NS.setCrestCostTextColor(costText, step)

    local dpsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dpsText:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 4)
    dpsText:SetWidth(120)
    dpsText:SetJustifyH("LEFT")
    dpsText:SetText(NS.formatDelta(step.dps_delta or 0))
    NS.setDpsDeltaTextColor(dpsText, step.dps_delta)

    yOffset = yOffset + LITE_ROW_H
  end

  local contentHeight = math.max(LITE_SCROLL_H, yOffset + 4)
  itemList:SetHeight(contentHeight)
end

local function ensureLitePanel()
  if litePanel then
    return litePanel
  end

  local f = CreateFrame("Frame", "MrMythicalCrestUpgradeLite", UIParent, "BackdropTemplate")
  f:SetSize(LITE_WIDTH, 120 + LITE_SCROLL_H)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  f:SetBackdropColor(0.07, 0.09, 0.08, 0.97)
  f:SetBackdropBorderColor(0.28, 0.55, 0.38, 0.95)
  f:Hide()

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
  title:SetText(NS.MSG_CREST_LITE_TITLE)
  title:SetTextColor(0.55, 1, 0.65)

  local brand = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  brand:SetPoint("TOPRIGHT", f, "TOPRIGHT", -34, -12)
  brand:SetText(NS.BRAND)
  brand:SetTextColor(0.45, 0.5, 0.52)

  local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
  closeBtn:SetScript("OnClick", function()
    f:Hide()
  end)

  local balanceText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  balanceText:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -28)
  balanceText:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  balanceText:SetJustifyH("LEFT")
  balanceText:SetTextColor(0.58, 0.64, 0.6)
  f.balanceText = balanceText

  local summaryText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  summaryText:SetPoint("TOPLEFT", balanceText, "BOTTOMLEFT", 0, -2)
  summaryText:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  summaryText:SetJustifyH("LEFT")
  summaryText:SetTextColor(0.72, 0.88, 0.76)
  f.summaryText = summaryText

  local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  statusText:SetPoint("TOPLEFT", summaryText, "BOTTOMLEFT", 0, -8)
  statusText:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  statusText:SetJustifyH("LEFT")
  statusText:SetWordWrap(true)
  f.statusText = statusText

  local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -78)
  scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 36)
  f.scrollFrame = scrollFrame

  local itemList = CreateFrame("Frame", nil, scrollFrame)
  itemList:SetSize(LITE_WIDTH - 40, LITE_SCROLL_H)
  scrollFrame:SetScrollChild(itemList)
  f.itemList = itemList

  local advisorBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  advisorBtn:SetSize(108, 22)
  advisorBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)
  advisorBtn:SetText(NS.MSG_CREST_LITE_OPEN_ADVISOR)
  advisorBtn:SetScript("OnClick", function()
    if NS.openGearAdvisor then
      NS.openGearAdvisor(nil, "crests")
    end
  end)
  f.advisorBtn = advisorBtn

  litePanel = f
  return f
end

local function invalidateLiteScan()
  liteScanScheduleToken = liteScanScheduleToken + 1
  liteScanWorkToken = liteScanWorkToken + 1
  liteScanInProgress = false
end

local function tryUseCachedPlan()
  if not NS.getCachedCrestSpendPlanData then
    return false
  end
  local plan, summary = NS.getCachedCrestSpendPlanData()
  if not plan or #plan == 0 then
    return false
  end
  litePlan = plan
  liteSummary = summary
  renderLitePlan()
  return true
end

local function finishLiteScanEmpty(note, panel)
  litePlan = {}
  liteSummary = nil
  local msg = NS.MSG_CREST_EMPTY_AFFORDABLE
  if note then
    msg = msg .. " (" .. note .. ")"
  end
  setLiteStatus(msg, 0.55, 0.6, 0.65)
  if panel and panel.balanceText then
    panel.balanceText:SetText(NS.formatCrestBalancesLine and NS.formatCrestBalancesLine() or "")
  end
end

local function runLiteScanWork(workToken, panel, specKey)
  if workToken ~= liteScanWorkToken or not panel:IsShown() or not isItemUpgradeFrameOpen() then
    liteScanInProgress = false
    return
  end

  local rows, note
  local ok, err = pcall(function()
    rows, note = NS.collectCrestUpgradeOpportunities(specKey)
  end)
  if not ok then
    liteScanInProgress = false
    setLiteStatus("Crest scan failed: " .. tostring(err), 1, 0.4, 0.4)
    return
  end
  if workToken ~= liteScanWorkToken or not panel:IsShown() then
    liteScanInProgress = false
    return
  end

  C_Timer.After(0, function()
    if workToken ~= liteScanWorkToken or not panel:IsShown() or not isItemUpgradeFrameOpen() then
      liteScanInProgress = false
      return
    end

    NS.refreshCrestRowAffordability(rows)
    local affordable = {}
    for _, row in ipairs(rows or {}) do
      if row.can_afford then
        table.insert(affordable, row)
      end
    end

    if #affordable == 0 then
      liteScanInProgress = false
      finishLiteScanEmpty(note, panel)
      return
    end

    setLiteStatus("Building spending plan...", 0.95, 0.85, 0.45)

    C_Timer.After(0, function()
      if workToken ~= liteScanWorkToken or not panel:IsShown() or not isItemUpgradeFrameOpen() then
        liteScanInProgress = false
        return
      end

      local plan, spent, totalDps
      local planOk, planErr = pcall(function()
        plan, spent, totalDps = NS.optimizeCrestSpendPlan(rows, specKey)
      end)
      liteScanInProgress = false

      if not planOk then
        setLiteStatus("Plan optimization failed: " .. tostring(planErr), 1, 0.4, 0.4)
        return
      end
      if workToken ~= liteScanWorkToken or not panel:IsShown() then
        return
      end

      litePlan = plan or {}
      liteSummary = NS.formatCrestSpendPlanSummary(litePlan, spent, totalDps)
      renderLitePlan()
    end)
  end)
end

local function scheduleLiteScan(delay)
  delay = delay or 0.15
  liteScanScheduleToken = liteScanScheduleToken + 1
  local scheduleToken = liteScanScheduleToken

  local panel = ensureLitePanel()
  panel:Show()
  positionLitePanel()

  if not NS.profileDetectionDoneRef[1] or #NS.active_spec_keys == 0 then
    NS.detectAndCacheProfiles()
  end
  local specKey = NS.getActiveProfileKey()
  if not specKey then
    litePlan = nil
    liteSummary = nil
    setLiteStatus(NS.MSG_NO_PROFILE_ACTION, 1, 0.5, 0.5)
    return
  end

  if tryUseCachedPlan() then
    return
  end

  litePlan = nil
  liteSummary = nil
  clearLiteRows()
  setLiteStatus(NS.MSG_CREST_SCANNING, 0.95, 0.85, 0.45)

  C_Timer.After(delay, function()
    if scheduleToken ~= liteScanScheduleToken then
      return
    end
    if not panel:IsShown() or not isItemUpgradeFrameOpen() then
      return
    end

    liteScanWorkToken = liteScanWorkToken + 1
    local workToken = liteScanWorkToken
    liteScanInProgress = true

    C_Timer.After(0, function()
      runLiteScanWork(workToken, panel, specKey)
    end)
  end)
end

local function onUpgradeFrameShow()
  scheduleLiteScan(0.05)
end

local function onUpgradeFrameHide()
  invalidateLiteScan()
  litePlan = nil
  liteSummary = nil
  liteActiveInvSlot = nil
  if litePanel then
    litePanel:Hide()
    clearLiteRows()
  end
end

local function onUpgradeItemChanged()
  if not isItemUpgradeFrameOpen() then
    return
  end
  if litePanel and litePanel:IsShown() and litePlan and #litePlan > 0 then
    renderLitePlan()
  end
end

function NS.setupCrestUpgradeAdvisor()
  local upgradeFrame = getItemUpgradeFrame()
  if not upgradeFrame then
    if not _G.MrMythicalCrestUpgradeDefer then
      local defer = CreateFrame("Frame")
      defer:RegisterEvent("ADDON_LOADED")
      defer:SetScript("OnEvent", function(self, _, name)
        if name == "Blizzard_ItemUpgradeUI" or getItemUpgradeFrame() then
          self:UnregisterEvent("ADDON_LOADED")
          _G.MrMythicalCrestUpgradeDefer = nil
          NS.setupCrestUpgradeAdvisor()
        end
      end)
      _G.MrMythicalCrestUpgradeDefer = defer
    end
    return
  end
  if upgradeFrame.MrMythicalCrestUpgradeHooked then
    return
  end

  upgradeFrame:HookScript("OnShow", onUpgradeFrameShow)
  upgradeFrame:HookScript("OnHide", onUpgradeFrameHide)
  upgradeFrame.MrMythicalCrestUpgradeHooked = true

  local eventFrame = CreateFrame("Frame")
  eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
  if eventFrame.RegisterEvent then
    pcall(eventFrame.RegisterEvent, eventFrame, "ITEM_UPGRADE_MASTER_SET_ITEM")
    pcall(eventFrame.RegisterEvent, eventFrame, "ITEM_UPGRADE_MASTER_UPDATE")
  end
  eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_EQUIPMENT_CHANGED" then
      if isItemUpgradeFrameOpen() and litePanel and litePanel:IsShown() and not liteScanInProgress then
        scheduleLiteScan(0.25)
      end
    else
      onUpgradeItemChanged()
    end
  end)

  if upgradeFrame:IsShown() then
    onUpgradeFrameShow()
  end
end
