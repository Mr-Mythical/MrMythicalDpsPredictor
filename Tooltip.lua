local ADDON_NAME, NS = ...
local didWarnTooltipError = false
do
  local HEADER_TEXT = NS.BRAND or "Mr. Mythical: DPS Predictor & Gearing Dashboard"
  local HEADER_COLOR = { 1, 0.92, 0.55 }

  local function ownerHasMouse(owner)
    if not owner then
      return false
    end
    if owner.IsMouseOver and owner:IsMouseOver() then
      return true
    end
    if owner.IsMouseMotionFocus and owner:IsMouseMotionFocus() then
      return true
    end
    local focus = rawget(_G, "GetMouseFocus") and GetMouseFocus() or nil
    local frame = focus
    while frame do
      if frame == owner then
        return true
      end
      frame = frame.GetParent and frame:GetParent() or nil
    end
    return false
  end

  local function isRealHoverTooltip(tooltip)
    if not tooltip or tooltip ~= GameTooltip then
      return false
    end
    if tooltip.IsShown and not tooltip:IsShown() then
      return false
    end
    if not tooltip.GetOwner then
      return false
    end
    return ownerHasMouse(tooltip:GetOwner())
  end

  local CACHE_SIZE = 64
  local predictionCache = {}
  local cacheOrder = 0
  local cacheCount = 0
  NS.tooltipPredictionCacheStats = NS.tooltipPredictionCacheStats or { hits = 0, misses = 0 }

  local function evictOldestCache()
    if cacheCount <= CACHE_SIZE then return end
    local oldest_key, oldest_order = nil, math.huge
    for k, v in pairs(predictionCache) do
      if v.order < oldest_order then
        oldest_key = k
        oldest_order = v.order
      end
    end
    if oldest_key then
      predictionCache[oldest_key] = nil
      cacheCount = cacheCount - 1
    end
  end

  local function clearPredictionCache()
    predictionCache = {}
    cacheCount = 0
    cacheOrder = 0
    NS.tooltipPredictionCacheStats.hits = 0
    NS.tooltipPredictionCacheStats.misses = 0
  end

  NS._clearPredictionCache = clearPredictionCache

  local function tooltipCacheKey(itemLink, specKeys)
    local ilvl = NS.getItemIlvl(itemLink)
    local specPart = table.concat(specKeys or {}, ",")
    return string.format("%s|%s|%d", itemLink, specPart, ilvl)
  end

  local function getTooltipTextLine(tooltip, index)
    local base = tooltip and tooltip.GetName and tooltip:GetName()
    if not base then
      return nil
    end
    return _G[base .. "TextLeft" .. index]
  end

  local function tooltipAlreadyHasBlock(tooltip)
    if not tooltip or not tooltip.NumLines then
      return false
    end
    for i = 1, tooltip:NumLines() do
      local line = getTooltipTextLine(tooltip, i)
      if line and line.GetText and line:GetText() == HEADER_TEXT then
        return true
      end
    end
    return false
  end

  local function collectOwnerExtraLines(tooltip)
    local owner = tooltip.GetOwner and tooltip:GetOwner()
    if owner and owner.mrMythicalTooltipExtraLines then
      return owner.mrMythicalTooltipExtraLines
    end
    return nil
  end

  local function extraLinesBlockSuffix(extraLines)
    if not extraLines or #extraLines == 0 then
      return ""
    end
    local parts = {}
    for _, line in ipairs(extraLines) do
      parts[#parts + 1] = line.text or ""
    end
    return table.concat(parts, "\31")
  end

  local function shouldBuildPredictionSynchronously(tooltip)
    local owner = tooltip.GetOwner and tooltip:GetOwner()
    if not owner then
      return false
    end
    if owner.mrMythicalAdvisorItemTooltip or owner.mrMythicalTooltipExtraLines then
      return true
    end
    return false
  end

  -- Resize backdrop after late AddLine without GameTooltip:Show().
  -- Show() re-runs TooltipDataProcessor, clears custom lines, and can hide the tip.
  local function refreshTooltipLayout(tooltip)
    if not tooltip or not tooltip.IsShown or not tooltip:IsShown() then
      return
    end
    if tooltip.mrMythicalRefreshingLayout then
      return
    end
    tooltip.mrMythicalRefreshingLayout = true
    if tooltip.SetPadding then
      local right, bottom, left, top = 0, 0, 0, 0
      if tooltip.GetPadding then
        right, bottom, left, top = tooltip:GetPadding()
      end
      tooltip:SetPadding(right, bottom, left, top)
    elseif GameTooltip_CalculatePadding then
      GameTooltip_CalculatePadding(tooltip)
    end
    tooltip.mrMythicalRefreshingLayout = nil
  end

  local function appendUnifiedBlock(tooltip, blockKey, lines)
    if not tooltip or not lines or #lines == 0 then
      return
    end
    if tooltipAlreadyHasBlock(tooltip) then
      tooltip.mrMythicalBlockKey = blockKey
      return
    end
    tooltip.mrMythicalBlockKey = blockKey
    tooltip:AddLine(" ")
    tooltip:AddLine(HEADER_TEXT, HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3])
    for _, line in ipairs(lines) do
      tooltip:AddLine(line.text, line.r, line.g, line.b)
    end
    refreshTooltipLayout(tooltip)
  end

  local function hookTooltipLifecycle(tooltip)
    if not tooltip or tooltip.mrMythicalTooltipLifecycleHooked then
      return
    end
    tooltip:HookScript("OnHide", function(self)
      self.mrMythicalBlockKey = nil
    end)
    tooltip.mrMythicalTooltipLifecycleHooked = true
  end

  local function buildPredictionLines(itemLink, itemGuid, itemData, specKeys)
    local profileStart
    local cacheStart
    if MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.debug and debugprofilestop then
      profileStart = debugprofilestop()
      cacheStart = NS.getPredictionCacheSnapshot and NS.getPredictionCacheSnapshot() or {}
    end
    local lines = {}
    local showProfileLabel = #specKeys > 1
    local predictionContext = NS.createPredictionContext and NS.createPredictionContext() or nil

    for _, specKey in ipairs(specKeys) do
      local pred = NS.Predictor.PredictItemDelta({
        link = itemLink,
        guid = itemGuid,
      }, specKey, predictionContext)
      if pred then
        if type(pred) == "table" and pred[1] then
          for _, p in ipairs(pred) do
            local deltaText = NS.formatDelta(p.dps_delta)
            local candidateR, candidateG, candidateB = NS.getDpsDeltaColor(p.dps_delta)
            local label = (NS.active_spec_prefix and NS.getProfileLabel(specKey, NS.active_spec_prefix)) or specKey
            local modeStr = ""
            if p.mode == "mh_replacement" then
              modeStr = " (mainhand)"
            elseif p.mode == "2h_replacement" then
              modeStr = " (2H)"
            elseif p.mode == "dw_pair_replacement" then
              modeStr = " (paired 1H set)"
            elseif p.mode == "oh_replacement" then
              modeStr = " (offhand)"
            elseif p.mode == "ring1" then
              modeStr = " (ring 1)"
            elseif p.mode == "ring2" then
              modeStr = " (ring 2)"
            end
            lines[#lines + 1] = {
              text = NS.formatTooltipDelta(label, modeStr, deltaText, showProfileLabel),
              r = candidateR, g = candidateG, b = candidateB,
            }
          end
        else
          local deltaText = NS.formatDelta(pred.dps_delta)
          local candidateR, candidateG, candidateB = NS.getDpsDeltaColor(pred.dps_delta)
          local label = (NS.active_spec_prefix and NS.getProfileLabel(specKey, NS.active_spec_prefix)) or specKey
          lines[#lines + 1] = {
            text = NS.formatTooltipDelta(label, nil, deltaText, showProfileLabel),
            r = candidateR, g = candidateG, b = candidateB,
          }
        end
      end
    end

    if #lines > 0 and NS.getProfileMatchInfo and NS.getProfileMatchInfo().lowConfidence and #specKeys == 1 then
      lines[#lines + 1] = {
        text = NS.MSG_PROFILE_LOW_CONFIDENCE,
        r = 0.85, g = 0.75, b = 0.35,
      }
    end

    if profileStart then
      local cacheEnd = NS.getPredictionCacheSnapshot and NS.getPredictionCacheSnapshot() or {}
      local function delta(key)
        local value = (cacheEnd[key] or 0) - (cacheStart[key] or 0)
        if value < 0 then
          return cacheEnd[key] or 0
        end
        return value
      end
      NS.lastTooltipInferenceStats = {
        cache_hit = false,
        elapsed_ms = debugprofilestop() - profileStart,
        forward_calls = delta("forward_count"),
        forward_ms = delta("forward_ms"),
        cache_hits = delta("hits"),
        cache_misses = delta("misses"),
      }
      NS.debugPrint(string.format(
        "tooltip inference: cold %.2fms, forward %.2fms/%d, cache %d/%d",
        NS.lastTooltipInferenceStats.elapsed_ms,
        NS.lastTooltipInferenceStats.forward_ms,
        NS.lastTooltipInferenceStats.forward_calls,
        NS.lastTooltipInferenceStats.cache_hits,
        NS.lastTooltipInferenceStats.cache_hits + NS.lastTooltipInferenceStats.cache_misses
      ))
    end

    return lines
  end

  local function appendTooltipBlockForItem(tooltip, itemLink, itemGuid, itemData)
    if not tooltip or not itemLink or itemLink == "" then
      return
    end

    if tooltipAlreadyHasBlock(tooltip) then
      return
    end

    local extraLines = collectOwnerExtraLines(tooltip)
    local specKeys = NS.getTooltipProfileKeys()
    if not specKeys or #specKeys == 0 then
      if extraLines and #extraLines > 0 then
        appendUnifiedBlock(tooltip, "extra|" .. extraLinesBlockSuffix(extraLines), extraLines)
      elseif not NS._didWarnNoProfileTooltip then
        NS._didWarnNoProfileTooltip = true
        appendUnifiedBlock(tooltip, "no-profile", {
          { text = NS.MSG_NO_PROFILE_LABEL, r = 0.55, g = 0.55, b = 0.55 },
        })
      end
      return
    end

    if not NS.profileDetectionDoneRef[1] and #NS.active_spec_keys == 0 then
      NS.detectAndCacheProfiles()
    end

    specKeys = NS.getTooltipProfileKeys()
    if not specKeys or #specKeys == 0 then
      if extraLines and #extraLines > 0 then
        appendUnifiedBlock(tooltip, "extra|" .. extraLinesBlockSuffix(extraLines), extraLines)
      end
      return
    end

    local cacheKey = tooltipCacheKey(itemLink, specKeys)
    local blockKey = cacheKey .. "|" .. extraLinesBlockSuffix(extraLines)
    -- Only trust visible header text, not mrMythicalBlockKey: a layout refresh can
    -- wipe lines without OnHide, leaving a stale key that would skip re-append.
    local predictionLines = nil
    local lookupStart
    if MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.debug and debugprofilestop then
      lookupStart = debugprofilestop()
    end
    local cached = predictionCache[cacheKey]
    if cached then
      NS.tooltipPredictionCacheStats.hits = NS.tooltipPredictionCacheStats.hits + 1
      cached.order = cacheOrder
      cacheOrder = cacheOrder + 1
      predictionLines = cached.lines
      if lookupStart then
        NS.lastTooltipInferenceStats = {
          cache_hit = true,
          elapsed_ms = debugprofilestop() - lookupStart,
          forward_calls = 0,
          forward_ms = 0,
          cache_hits = 1,
          cache_misses = 0,
        }
        NS.debugPrint(string.format(
          "tooltip inference: warm cache hit in %.2fms",
          NS.lastTooltipInferenceStats.elapsed_ms
        ))
      end
    else
      NS.tooltipPredictionCacheStats.misses = NS.tooltipPredictionCacheStats.misses + 1
    end

    local function publishBlock(lines)
      local blockLines = {}
      if lines then
        for _, line in ipairs(lines) do
          blockLines[#blockLines + 1] = line
        end
      end
      if extraLines then
        for _, line in ipairs(extraLines) do
          blockLines[#blockLines + 1] = line
        end
      end
      if #blockLines > 0 then
        appendUnifiedBlock(tooltip, blockKey, blockLines)
      end
    end

    if predictionLines then
      publishBlock(predictionLines)
      return
    end

    if shouldBuildPredictionSynchronously(tooltip) then
      predictionLines = buildPredictionLines(itemLink, itemGuid, itemData, specKeys)
      if #predictionLines > 0 then
        cacheCount = cacheCount + 1
        predictionCache[cacheKey] = { lines = predictionLines, order = cacheOrder }
        cacheOrder = cacheOrder + 1
        evictOldestCache()
      end
      publishBlock(predictionLines)
      return
    end

    C_Timer.After(0, function()
      if not tooltip:IsShown() then
        return
      end
      if tooltipAlreadyHasBlock(tooltip) then
        tooltip.mrMythicalBlockKey = blockKey
        return
      end
      local currentLink
      if tooltip.GetItem then
        local ok2, _, link = pcall(tooltip.GetItem, tooltip)
        if ok2 then
          currentLink = link
        end
      end
      if currentLink ~= itemLink then
        return
      end
      if tooltip == GameTooltip and not isRealHoverTooltip(tooltip) then
        return
      end

      predictionLines = buildPredictionLines(itemLink, itemGuid, itemData, specKeys)
      if #predictionLines > 0 then
        cacheCount = cacheCount + 1
        predictionCache[cacheKey] = { lines = predictionLines, order = cacheOrder }
        cacheOrder = cacheOrder + 1
        evictOldestCache()
      end
      publishBlock(predictionLines)
    end)
  end

  local function addPredictionLinesToTooltip(tooltip, itemLink, itemGuid, itemData)
    if not tooltip or not itemLink or itemLink == "" then
      return
    end

    local isEquippable = rawget(_G, "IsEquippableItem")
    if isEquippable and not isEquippable(itemLink) then
      return
    end

    local itemClassID, itemSubClassID, equipLoc
    if C_Item and C_Item.GetItemInfoInstant then
      local _, _, _, loc, _, cid, sid = C_Item.GetItemInfoInstant(itemLink)
      itemClassID, itemSubClassID, equipLoc = cid, sid, loc
    else
      local _, _, _, _, _, _, _, _, loc, _, _, cid, sid = GetItemInfo(itemLink)
      itemClassID, itemSubClassID, equipLoc = cid, sid, loc
    end

    if equipLoc == "INVTYPE_TRINKET" then
      return
    end

    if itemClassID == 4 and itemSubClassID and itemSubClassID ~= 0 and itemSubClassID ~= 6 then
      local _, classToken = UnitClass("player")
      local primaryArmor = NS.CLASS_PRIMARY_ARMOR[classToken]
      if primaryArmor and itemSubClassID ~= primaryArmor then
        return
      end
    end

    local ok, err = pcall(function()
      appendTooltipBlockForItem(tooltip, itemLink, itemGuid, itemData)
    end)

    if not ok and not didWarnTooltipError then
      didWarnTooltipError = true
      NS.lastError = tostring(err)
      NS.debugPrint(NS.brandMsg("Tooltip prediction error: " .. tostring(err)))
    end
  end

  local hooked = false
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    hookTooltipLifecycle(GameTooltip)
    hookTooltipLifecycle(ItemRefTooltip)

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
      if not tooltip then
        return
      end

      if tooltip == GameTooltip then
        if not isRealHoverTooltip(tooltip) then
          return
        end
      elseif tooltip ~= ItemRefTooltip then
        return
      end

      local itemLink = data and data.hyperlink
      if not itemLink and tooltip.GetItem then
        local ok2, _, link = pcall(tooltip.GetItem, tooltip)
        if ok2 and link then
          itemLink = link
        end
      end

      if itemLink then
        local itemGuid = type(data) == "table" and (data["guid"] or data["itemGUID"]) or nil
        addPredictionLinesToTooltip(tooltip, itemLink, itemGuid, data)
      end
    end)
    hooked = true
  end

  if not hooked then
    NS.debugPrint(NS.brandMsg("TooltipDataProcessor unavailable; tooltip predictions disabled."))
  else
    NS.debugPrint(NS.brandMsg("Tooltip hooks active."))
  end
end
