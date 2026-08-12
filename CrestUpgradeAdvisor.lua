local ADDON_NAME, NS = ...

local litePanel = nil
local liteRows = {}
local litePlan = nil
local liteScanScheduleToken = 0
local liteScanWorkToken = 0
local liteScanInProgress = false
local liteScanHandle = nil
local liteActiveInvSlot = nil

local LITE_WIDTH = 340
local LITE_ROW_H = 48
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
  if litePanel.balanceBar and NS.fillCrestBalanceContainer then
    NS.fillCrestBalanceContainer(litePanel.balanceBar, {
      iconSize = 14,
      textColor = { 0.58, 0.64, 0.6 },
    })
  elseif litePanel.balanceText and NS.formatCrestBalancesLine then
    litePanel.balanceText:SetText(NS.formatCrestBalancesLine() or "")
  end

  local itemList = litePanel.itemList
  local listWidth = (itemList:GetWidth() or LITE_WIDTH) - 8
  local yOffset = 2

  local COST_COL_W = 88
  local DPS_COL_W = 100
  local ICON_SIZE = 28
  local leftPad = 8
  local textLeft = leftPad + ICON_SIZE + 6
  local textWidth = math.max(80, listWidth - textLeft - COST_COL_W - 12)

  for _, step in ipairs(litePlan) do
    local isActive = liteActiveInvSlot and step.inv_slot and step.inv_slot == liteActiveInvSlot
    local iconLink = step.preview_link or step.link
    local iconTexture = iconLink and GetItemIcon(iconLink) or nil
    local itemName = step.preview_name or step.name or ""
    local nameLine
    if itemName ~= "" then
      nameLine = string.format("#%d %s - %s", step.order or 0, step.slot_label or "", itemName)
    else
      nameLine = string.format("#%d %s", step.order or 0, step.slot_label or "")
    end
    local costLabel = step.crest_label
    if NS.formatCrestCostCompact then
      costLabel = NS.formatCrestCostCompact(step.crest_cost, step.crest_cost_base, step.currency_id, step.crest_discounted)
    end
    costLabel = costLabel or tostring(step.crest_cost or 0)
    local dpsLabel = NS.formatDelta(step.dps_delta or 0) .. " DPS"
    local nameColor = isActive and { 0.55, 1, 0.65 } or { 0.62, 0.66, 0.7 }

    -- Keep the hand-laid row: cost/DPS sit on the right in a stack and fit LITE_WIDTH.
    -- CreateDataRow's left-to-right columns overflow this narrow panel.
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

    local iconBtn = CreateFrame("Button", nil, row)
    iconBtn:SetSize(ICON_SIZE, ICON_SIZE)
    iconBtn:SetPoint("LEFT", row, "LEFT", leftPad, 0)
    local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints(iconBtn)
    if iconTexture then
      iconTex:SetTexture(iconTexture)
    end
    if iconLink then
      iconBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(iconLink)
        GameTooltip:Show()
      end)
      iconBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
    end

    local stepBadge = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stepBadge:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -4)
    stepBadge:SetWidth(textWidth)
    stepBadge:SetJustifyH("LEFT")
    stepBadge:SetWordWrap(false)
    stepBadge:SetText(nameLine)
    stepBadge:SetTextColor(nameColor[1], nameColor[2], nameColor[3])

    local upgradeLine = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    upgradeLine:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -20)
    upgradeLine:SetWidth(textWidth)
    upgradeLine:SetJustifyH("LEFT")
    upgradeLine:SetWordWrap(false)
    upgradeLine:SetText(NS.formatCrestUpgradeStepLine(step))
    upgradeLine:SetTextColor(0.68, 0.72, 0.78)

    local costIcon
    if step.currency_id and NS.createCrestCurrencyIcon then
      costIcon = NS.createCrestCurrencyIcon(row, step.currency_id, 14)
      costIcon:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
    end

    local costText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if costIcon then
      costText:SetPoint("RIGHT", costIcon, "LEFT", -3, 0)
    else
      costText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
    end
    costText:SetWidth(COST_COL_W - 18)
    costText:SetJustifyH("RIGHT")
    costText:SetWordWrap(false)
    costText:SetText(costLabel)
    NS.setCrestCostTextColor(costText, step)

    local dpsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dpsText:SetPoint("TOPRIGHT", costIcon or costText, "BOTTOMRIGHT", 0, -2)
    dpsText:SetWidth(DPS_COL_W)
    dpsText:SetJustifyH("RIGHT")
    dpsText:SetWordWrap(false)
    dpsText:SetText(dpsLabel)
    NS.setDpsDeltaTextColor(dpsText, step.dps_delta)

    yOffset = yOffset + LITE_ROW_H
  end

  local contentHeight = math.max(LITE_SCROLL_H, yOffset + 4)
  itemList:SetHeight(contentHeight)
  if litePanel.scrollFrame and litePanel.scrollFrame._UpdateScrollRange then
    litePanel.scrollFrame:_UpdateScrollRange()
  end
end

local function ensureLitePanel()
  if litePanel then
    return litePanel
  end

  local Lib = NS.getUILib and NS.getUILib() or nil
  local f
  if Lib then
    f = Lib:CreatePanel(UIParent, {
      name = "MrMythicalCrestUpgradeLite",
      title = NS.MSG_CREST_LITE_TITLE,
      width = LITE_WIDTH,
      height = 112 + LITE_SCROLL_H,
      frameStrata = "FULLSCREEN_DIALOG",
    })
    f:Hide()
    local closeBtn = Lib:CreateCloseButton(f, function()
      f:Hide()
    end)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    f.CloseButton = closeBtn
    if f.Title then
      f.Title:ClearAllPoints()
      f.Title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
      f.Title:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
      f.Title:SetJustifyH("LEFT")
      f.Title:SetFontObject("GameFontNormal")
      f.Title:SetTextColor(0.55, 1, 0.65)
    end
  else
    f = CreateFrame("Frame", "MrMythicalCrestUpgradeLite", UIParent, "BackdropTemplate")
    f:SetSize(LITE_WIDTH, 112 + LITE_SCROLL_H)
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

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
      f:Hide()
    end)
    f.CloseButton = closeBtn

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    title:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    title:SetJustifyH("LEFT")
    title:SetText(NS.MSG_CREST_LITE_TITLE)
    title:SetTextColor(0.55, 1, 0.65)
    f.Title = title
  end

  local title = f.Title

  local brand = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  brand:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -1)
  brand:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  brand:SetJustifyH("LEFT")
  brand:SetText("Mr. Mythical")
  brand:SetTextColor(0.45, 0.5, 0.52)
  local balanceBar = CreateFrame("Frame", nil, f)
  balanceBar:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 0, -3)
  balanceBar:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  balanceBar:SetHeight(18)
  f.balanceBar = balanceBar

  local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  statusText:SetPoint("TOPLEFT", balanceBar, "BOTTOMLEFT", 0, -10)
  statusText:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  statusText:SetJustifyH("LEFT")
  statusText:SetWordWrap(true)
  f.statusText = statusText

  local scrollFrame
  local itemList
  if Lib then
    scrollFrame = Lib:CreateScrollFrame(f, {
      width = LITE_WIDTH - 40,
      height = LITE_SCROLL_H,
    })
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", balanceBar, "BOTTOMLEFT", -4, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 36)
    itemList = CreateFrame("Frame", nil, scrollFrame)
    itemList:SetSize(LITE_WIDTH - 52, LITE_SCROLL_H)
    scrollFrame:SetScrollChild(itemList)
  else
    scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", balanceBar, "BOTTOMLEFT", -4, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 36)
    itemList = CreateFrame("Frame", nil, scrollFrame)
    itemList:SetSize(LITE_WIDTH - 40, LITE_SCROLL_H)
    scrollFrame:SetScrollChild(itemList)
  end
  f.scrollFrame = scrollFrame
  f.itemList = itemList

  local advisorBtn = NS.createUIButton(f, {
    text = NS.MSG_CREST_LITE_OPEN_ADVISOR,
    width = 140,
    height = 24,
    onClick = function()
      if NS.openGearAdvisor then
        NS.openGearAdvisor(nil, "crests")
      end
    end,
  })
  advisorBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)
  f.advisorBtn = advisorBtn

  litePanel = f
  return f
end

local function cancelLiteScanHandle()
  if liteScanHandle then
    if NS.cancelCrestSpendPlanScan then
      NS.cancelCrestSpendPlanScan(liteScanHandle)
    else
      liteScanHandle.cancelled = true
    end
    liteScanHandle = nil
  end
end

local function invalidateLiteScan()
  liteScanScheduleToken = liteScanScheduleToken + 1
  liteScanWorkToken = liteScanWorkToken + 1
  liteScanInProgress = false
  cancelLiteScanHandle()
end

local function tryUseCachedPlan()
  if not NS.getCachedCrestSpendPlanData then
    return false
  end
  local plan = NS.getCachedCrestSpendPlanData()
  if not plan or #plan == 0 then
    return false
  end
  litePlan = plan
  renderLitePlan()
  return true
end

local function finishLiteScanEmpty(note, panel)
  litePlan = {}
  local msg = NS.MSG_CREST_EMPTY_AFFORDABLE
  if note then
    msg = msg .. " (" .. note .. ")"
  end
  setLiteStatus(msg, 0.55, 0.6, 0.65)
  if panel and panel.balanceBar and NS.fillCrestBalanceContainer then
    NS.fillCrestBalanceContainer(panel.balanceBar, {
      iconSize = 14,
      textColor = { 0.58, 0.64, 0.6 },
    })
  elseif panel and panel.balanceText and NS.formatCrestBalancesLine then
    panel.balanceText:SetText(NS.formatCrestBalancesLine() or "")
  end
end

local function runLiteScanWork(workToken, panel, specKey)
  if workToken ~= liteScanWorkToken or not panel:IsShown() or not isItemUpgradeFrameOpen() then
    liteScanInProgress = false
    return
  end
  cancelLiteScanHandle()
  liteScanHandle = NS.startCrestSpendPlanScan(specKey, {
    onProgress = function(phase)
      if workToken ~= liteScanWorkToken or not panel:IsShown() then
        return
      end
      if phase == "optimize" or phase == "chains" then
        setLiteStatus("Building spending plan...", 0.95, 0.85, 0.45)
      else
        setLiteStatus(NS.MSG_CREST_SCANNING, 0.95, 0.85, 0.45)
      end
    end,
    onComplete = function(plan, spent, totalDps, rows, note)
      if workToken ~= liteScanWorkToken then
        return
      end
      liteScanInProgress = false
      liteScanHandle = nil
      if not panel:IsShown() or not isItemUpgradeFrameOpen() then
        return
      end

      NS.refreshCrestRowAffordability(rows)
      local hasAffordable = false
      for _, row in ipairs(rows or {}) do
        if row.can_afford then
          hasAffordable = true
          break
        end
      end
      if not hasAffordable or not plan or #plan == 0 then
        finishLiteScanEmpty(note, panel)
        return
      end

      litePlan = plan or {}
      renderLitePlan()
    end,
    onError = function(err)
      if workToken ~= liteScanWorkToken then
        return
      end
      liteScanInProgress = false
      liteScanHandle = nil
      if panel:IsShown() then
        setLiteStatus("Crest scan failed: " .. tostring(err), 1, 0.4, 0.4)
      end
    end,
  })
end

local function scheduleLiteScan(delay)
  delay = delay or 0.2
  liteScanScheduleToken = liteScanScheduleToken + 1
  local scheduleToken = liteScanScheduleToken
  cancelLiteScanHandle()

  local panel = ensureLitePanel()
  panel:Show()
  positionLitePanel()

  if not NS.profileDetectionDoneRef[1] or #NS.active_spec_keys == 0 then
    NS.detectAndCacheProfiles()
  end
  local specKey = NS.getActiveProfileKey()
  if not specKey then
    litePlan = nil
    setLiteStatus(NS.MSG_NO_PROFILE_ACTION, 1, 0.5, 0.5)
    return
  end

  if tryUseCachedPlan() then
    return
  end

  litePlan = nil
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
    runLiteScanWork(workToken, panel, specKey)
  end)
end

local function onUpgradeFrameShow()
  scheduleLiteScan(0.2)
end

local function onUpgradeFrameHide()
  invalidateLiteScan()
  litePlan = nil
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
