local ADDON_NAME, NS = ...

NS.AdvisorScanProgress = NS.AdvisorScanProgress or {}

local SCAN_POPUP_WIDTH = 420
local SCAN_POPUP_HEIGHT = 172

local scanProgressFrame = nil
local scanProgressCompleteTimer = nil
local scanProgressCurrent = nil
local scanProgressTotal = nil
local scanProgressLastText = nil
local scanProgressLastColor = nil
local scanProgressStartTime = nil
local scanProgressTimerTicker = nil

local function handlers()
  return NS.AdvisorScanProgress._handlers or {}
end

function NS.AdvisorScanProgress.register(h)
  NS.AdvisorScanProgress._handlers = h
end

local function formatScanDuration(seconds)
  seconds = math.max(0, math.floor((seconds or 0) + 0.5))
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, s)
  end
  return string.format("%d:%02d", m, s)
end

local function getScanTimeInfo()
  if not scanProgressStartTime then
    return nil, nil
  end
  local elapsed = GetTime() - scanProgressStartTime
  local remaining = nil
  if scanProgressCurrent and scanProgressTotal and scanProgressTotal > 0 and scanProgressCurrent > 0 then
    remaining = elapsed * (scanProgressTotal - scanProgressCurrent) / scanProgressCurrent
  end
  return elapsed, remaining
end

local function formatScanTimerLine()
  local h = handlers()
  if not h.isScanActive or not h.isScanActive() then
    return ""
  end
  local elapsed, remaining = getScanTimeInfo()
  if not elapsed then
    return ""
  end
  local line = "Elapsed: " .. formatScanDuration(elapsed)
  if remaining then
    line = line .. "  ·  Est. remaining: " .. formatScanDuration(remaining)
  else
    line = line .. "  ·  Est. remaining: —"
  end
  return line
end

local function stopScanProgressTimingTicker()
  if scanProgressTimerTicker then
    scanProgressTimerTicker:Cancel()
    scanProgressTimerTicker = nil
  end
end

local function refreshScanProgressTimerDisplay()
  local line = formatScanTimerLine()
  local h = handlers()
  local showTimer = h.isScanActive and h.isScanActive() and line ~= ""

  if scanProgressFrame and scanProgressFrame.timerText then
    local f = scanProgressFrame
    if showTimer and f:IsShown() then
      if f.progressBar and f.progressBar:IsShown() then
        f.timerText:SetPoint("TOPLEFT", f.progressBar, "BOTTOMLEFT", 0, -18)
      else
        f.timerText:SetPoint("TOPLEFT", f.statusText, "BOTTOMLEFT", 0, -4)
      end
      f.timerText:SetText(line)
      f.timerText:Show()
    else
      f.timerText:Hide()
    end
  end

  local advisorFrame = h.getAdvisorFrame and h.getAdvisorFrame()
  if advisorFrame and advisorFrame.scanTimerText then
    if showTimer and advisorFrame:IsShown() then
      advisorFrame.scanTimerText:SetText(line)
      advisorFrame.scanTimerText:Show()
    else
      advisorFrame.scanTimerText:Hide()
    end
  end
end

function NS.AdvisorScanProgress.clearTiming()
  scanProgressStartTime = nil
  stopScanProgressTimingTicker()
  if scanProgressFrame and scanProgressFrame.timerText then
    scanProgressFrame.timerText:Hide()
  end
  local advisorFrame = handlers().getAdvisorFrame and handlers().getAdvisorFrame()
  if advisorFrame and advisorFrame.scanTimerText then
    advisorFrame.scanTimerText:Hide()
  end
end

function NS.AdvisorScanProgress.startTiming()
  scanProgressStartTime = GetTime()
  stopScanProgressTimingTicker()
  refreshScanProgressTimerDisplay()
  scanProgressTimerTicker = C_Timer.NewTicker(1, function()
    local h = handlers()
    if h.isScanActive and h.isScanActive() then
      refreshScanProgressTimerDisplay()
    else
      stopScanProgressTimingTicker()
    end
  end)
end

function NS.AdvisorScanProgress.clearBar()
  scanProgressCurrent = nil
  scanProgressTotal = nil
end

function NS.AdvisorScanProgress.setBar(current, total)
  scanProgressCurrent = current
  scanProgressTotal = total
  if scanProgressFrame and scanProgressFrame.progressBar then
    local bar = scanProgressFrame.progressBar
    if current and total and total > 0 then
      bar:SetMinMaxValues(0, total)
      bar:SetValue(current)
      bar:Show()
      if scanProgressFrame.progressLabel then
        scanProgressFrame.progressLabel:SetText(string.format(
          "%s / %s",
          NS.formatLargeNumber(current),
          NS.formatLargeNumber(total)
        ))
        scanProgressFrame.progressLabel:Show()
      end
    else
      bar:Hide()
      if scanProgressFrame.progressLabel then
        scanProgressFrame.progressLabel:Hide()
      end
    end
  end
  refreshScanProgressTimerDisplay()
end

function NS.AdvisorScanProgress.syncModeButton()
  if not scanProgressFrame or not scanProgressFrame.scanModeBtn then
    return
  end
  local h = handlers()
  local btn = scanProgressFrame.scanModeBtn
  local showToggle = h.isLoadoutSearchActive and h.isLoadoutSearchActive()
  if showToggle and h.isScanActive and h.isScanActive() and scanProgressFrame:IsShown() then
    btn:SetText(NS.getScanPerformanceToggleButtonLabel())
    btn:Show()
  else
    btn:Hide()
  end
end

local function createScanProgressFrame()
  if scanProgressFrame then
    return scanProgressFrame
  end

  local f = CreateFrame("Frame", "MrMythicalDpsScanProgressFrame", UIParent, "BackdropTemplate")
  f:SetSize(SCAN_POPUP_WIDTH, SCAN_POPUP_HEIGHT)
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
    MR_MYTHICAL_DPS_CONFIG.scan_progress_point = { point, relPoint, x, y }
  end)

  if MR_MYTHICAL_DPS_CONFIG.scan_progress_point then
    local p = MR_MYTHICAL_DPS_CONFIG.scan_progress_point
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -120)
  end

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
  title:SetText("Scan in progress")
  title:SetTextColor(1, 0.92, 0.55)

  local scanTypeText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  scanTypeText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  scanTypeText:SetTextColor(0.75, 0.8, 0.85)
  f.scanTypeText = scanTypeText

  local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  statusText:SetPoint("TOPLEFT", scanTypeText, "BOTTOMLEFT", 0, -6)
  statusText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, 0)
  statusText:SetJustifyH("LEFT")
  statusText:SetWordWrap(true)
  statusText:SetHeight(44)
  f.statusText = statusText

  local progressBar = CreateFrame("StatusBar", nil, f)
  progressBar:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -8)
  progressBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, 0)
  progressBar:SetHeight(14)
  progressBar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
  progressBar:SetStatusBarColor(0.45, 0.85, 0.55)
  progressBar:SetMinMaxValues(0, 1)
  progressBar:SetValue(0)
  progressBar:Hide()
  f.progressBar = progressBar

  local progressBg = progressBar:CreateTexture(nil, "BACKGROUND")
  progressBg:SetAllPoints(progressBar)
  progressBg:SetColorTexture(0.12, 0.12, 0.16, 0.9)

  local progressLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  progressLabel:SetPoint("TOP", progressBar, "BOTTOM", 0, -2)
  progressLabel:SetTextColor(0.65, 0.7, 0.75)
  progressLabel:Hide()
  f.progressLabel = progressLabel

  local timerText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  timerText:SetPoint("TOPLEFT", progressBar, "BOTTOMLEFT", 0, -18)
  timerText:SetTextColor(0.6, 0.75, 0.85)
  timerText:Hide()
  f.timerText = timerText

  local showDashboardBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  showDashboardBtn:SetSize(110, 24)
  showDashboardBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
  showDashboardBtn:SetText("Show Dashboard")
  showDashboardBtn:SetScript("OnClick", function()
    NS.openGearAdvisor()
  end)
  f.showDashboardBtn = showDashboardBtn

  local scanModeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  scanModeBtn:SetSize(132, 24)
  scanModeBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
  scanModeBtn:SetScript("OnClick", function()
    local hh = handlers()
    if hh.onTogglePerformance then
      hh.onTogglePerformance()
    end
  end)
  scanModeBtn:Hide()
  f.scanModeBtn = scanModeBtn

  local stopBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  stopBtn:SetSize(90, 24)
  stopBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
  stopBtn:SetText("Stop Scan")
  stopBtn:SetScript("OnClick", function()
    local hh = handlers()
    if hh.onStopScan then
      hh.onStopScan()
    end
  end)
  f.stopBtn = stopBtn

  f:Hide()
  scanProgressFrame = f
  return f
end

function NS.AdvisorScanProgress.hide()
  if scanProgressCompleteTimer then
    scanProgressCompleteTimer:Cancel()
    scanProgressCompleteTimer = nil
  end
  if scanProgressFrame then
    scanProgressFrame:Hide()
    if scanProgressFrame.scanModeBtn then
      scanProgressFrame.scanModeBtn:Hide()
    end
  end
end

local function showScanProgressPopup()
  local h = handlers()
  if not h.isScanActive or not h.isScanActive() then
    return
  end
  if scanProgressCompleteTimer then
    scanProgressCompleteTimer:Cancel()
    scanProgressCompleteTimer = nil
  end
  local f = createScanProgressFrame()
  if h.getScanTypeLabel then
    f.scanTypeText:SetText(h.getScanTypeLabel())
  end
  if scanProgressLastText and f.statusText then
    f.statusText:SetText(scanProgressLastText)
    if scanProgressLastColor then
      f.statusText:SetTextColor(
        scanProgressLastColor[1], scanProgressLastColor[2], scanProgressLastColor[3]
      )
    else
      f.statusText:SetTextColor(0.95, 0.85, 0.45)
    end
  end
  NS.AdvisorScanProgress.setBar(scanProgressCurrent, scanProgressTotal)
  refreshScanProgressTimerDisplay()
  NS.AdvisorScanProgress.syncModeButton()
  f:Show()
end

local function notifyScanProgressComplete(message, color)
  local elapsed = scanProgressStartTime and (GetTime() - scanProgressStartTime)
  NS.AdvisorScanProgress.clearBar()
  local h = handlers()
  local advisorFrame = h.getAdvisorFrame and h.getAdvisorFrame()
  if advisorFrame and advisorFrame:IsShown() then
    NS.AdvisorScanProgress.hide()
    return
  end
  local f = createScanProgressFrame()
  f.scanTypeText:SetText("Scan finished")
  f.statusText:SetText(message or "Scan complete.")
  if color then
    f.statusText:SetTextColor(color[1], color[2], color[3])
  else
    f.statusText:SetTextColor(0.55, 1, 0.65)
  end
  if f.progressBar then f.progressBar:Hide() end
  if f.progressLabel then f.progressLabel:Hide() end
  if f.scanModeBtn then f.scanModeBtn:Hide() end
  if f.timerText then
    if elapsed then
      f.timerText:SetText("Elapsed: " .. formatScanDuration(elapsed))
      f.timerText:Show()
    else
      f.timerText:Hide()
    end
  end
  f:Show()
  if UIFrameFlash and f.statusText then
    UIFrameFlash(f.statusText, 0.2, 0.6, 2, false, 0, 0)
  end
  if scanProgressCompleteTimer then
    scanProgressCompleteTimer:Cancel()
  end
  scanProgressCompleteTimer = C_Timer.NewTimer(2.5, function()
    scanProgressCompleteTimer = nil
    NS.AdvisorScanProgress.hide()
  end)
end

function NS.AdvisorScanProgress.onScanEnded(wasCancelled, completionMessage, completionColor)
  NS.AdvisorScanProgress.clearBar()
  scanProgressLastText = nil
  scanProgressLastColor = nil
  local h = handlers()
  local advisorFrame = h.getAdvisorFrame and h.getAdvisorFrame()
  local dashboardHidden = not advisorFrame or not advisorFrame:IsShown()
  if dashboardHidden then
    notifyScanProgressComplete(
      completionMessage or (wasCancelled and "Scan cancelled." or "Scan complete."),
      completionColor or (wasCancelled and { 0.95, 0.85, 0.45 } or { 0.55, 1, 0.65 })
    )
  else
    NS.AdvisorScanProgress.hide()
  end
  NS.AdvisorScanProgress.clearTiming()
end

function NS.AdvisorScanProgress.updateDisplay(text, color)
  local h = handlers()
  if not h.isScanActive or not h.isScanActive() then
    return
  end
  scanProgressLastText = text
  scanProgressLastColor = color
  local advisorFrame = h.getAdvisorFrame and h.getAdvisorFrame()
  if advisorFrame and not advisorFrame:IsShown() then
    showScanProgressPopup()
  end
  local f = scanProgressFrame
  if not f then
    return
  end
  if f.scanTypeText and h.getScanTypeLabel then
    f.scanTypeText:SetText(h.getScanTypeLabel())
  end
  if f.statusText then
    f.statusText:SetText(text or "")
    if color then
      f.statusText:SetTextColor(color[1], color[2], color[3])
    else
      f.statusText:SetTextColor(0.95, 0.85, 0.45)
    end
  end
  NS.AdvisorScanProgress.setBar(scanProgressCurrent, scanProgressTotal)
  refreshScanProgressTimerDisplay()
end

function NS.AdvisorScanProgress.showIfScanActive()
  showScanProgressPopup()
end

function NS.AdvisorScanProgress.getLastStatus()
  return scanProgressLastText, scanProgressLastColor
end

function NS.AdvisorScanProgress.refreshTimerDisplay()
  refreshScanProgressTimerDisplay()
end
