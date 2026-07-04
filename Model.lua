local ADDON_NAME, NS = ...
local Model = NS.Model
local didWarnComparisonError = false

local function dot(row, vec, bias)
  local s = bias
  local n = #row
  for i = 1, n do
    s = s + row[i] * vec[i]
  end
  return s
end

-- Pre-allocated ping-pong buffers to avoid table creation per layer.
local buf_a = {}
local buf_b = {}
for i = 1, 1024 do buf_a[i] = 0; buf_b[i] = 0 end

local function linear_into(layer_w, layer_b, input, out, out_size)
  for i = 1, out_size do
    out[i] = dot(layer_w[i], input, layer_b[i])
  end
end

local function batchnorm_precomputed(x, bn_s, bn_o, size)
  -- Precomputed: y = scale * x + offset (no sqrt at runtime)
  for i = 1, size do
    x[i] = bn_s[i] * x[i] + bn_o[i]
  end
end

local function forwardModel(input, specKey, modelDef)
  local scaler = Model.scaler
  local n_in = Model.n_stat_features or #input
  local layers = modelDef.layers
  local n_layers = #layers
  local x_mean = scaler.x_mean
  local x_scale = scaler.x_scale
  local y_scale = scaler.y_scale
  local y_mean = scaler.y_mean
  local spec_bias = modelDef.prebaked and modelDef.prebaked[specKey] or nil

  for i = 1, n_in do
    buf_a[i] = (input[i] - x_mean[i]) / x_scale[i]
  end

  local src = buf_a
  local dst = buf_b

  for li = 1, n_layers do
    local layer = layers[li]
    local layer_w = layer.w
    local layer_b = layer.b
    local out_size = #layer_w
    local bn_s = layer.bn_s
    local bn_o = layer.bn_o

    if li == 1 and spec_bias then
      for i = 1, out_size do
        dst[i] = dot(layer_w[i], src, spec_bias[i])
      end
    else
      linear_into(layer_w, layer_b, src, dst, out_size)
    end

    for j = 1, out_size do
      if dst[j] <= 0 then dst[j] = 0 end
    end

    batchnorm_precomputed(dst, bn_s, bn_o, out_size)

    src, dst = dst, src
  end

  local output = modelDef.output
  local y_scaled = dot(output.w, src, output.b)
  local y = y_scaled * y_scale + y_mean

  if MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.debug and debugprofilestop then
    NS.forwardProfile = NS.forwardProfile or { count = 0, totalMs = 0 }
    -- forwardProfile timing is recorded by callers when batching; count forwards here.
    NS.forwardProfile.count = NS.forwardProfile.count + 1
  end

  return y
end

local function forward(input, specKey)
  return forwardModel(input, specKey, Model.single_model)
end

local function getPrimaryStatValue()
  local specIndex = GetSpecialization()
  if not specIndex then
    return 0
  end

  local _, _, _, _, _, _, primaryStat = GetSpecializationInfo(specIndex)
  if primaryStat == LE_UNIT_STAT_STRENGTH then
    local v = UnitStat("player", LE_UNIT_STAT_STRENGTH)
    return v or 0
  elseif primaryStat == LE_UNIT_STAT_AGILITY then
    local v = UnitStat("player", LE_UNIT_STAT_AGILITY)
    return v or 0
  end

  local v = UnitStat("player", LE_UNIT_STAT_INTELLECT)
  return v or 0
end

local function getPlayerStatVector()
  return {
    primary_stat = getPrimaryStatValue(),
    crit = GetCombatRating(CR_CRIT_MELEE) or 0,
    haste = GetCombatRating(CR_HASTE_MELEE) or 0,
    mastery = GetCombatRating(CR_MASTERY) or 0,
    versatility = GetCombatRating(CR_VERSATILITY_DAMAGE_DONE) or 0,
  }
end

local function itemRefToLink(itemRef)
  if type(itemRef) == "table" then
    return itemRef.link or itemRef.itemLink or itemRef.hyperlink
  end
  return itemRef
end

local function getGuidFromEquipmentSlot(slotId)
  if C_Item and C_Item.GetItemGUID and ItemLocation and ItemLocation.CreateFromEquipmentSlot then
    local okLoc, loc = pcall(ItemLocation.CreateFromEquipmentSlot, slotId)
    if okLoc and loc then
      local okGuid, guid = pcall(C_Item.GetItemGUID, loc)
      if okGuid and guid then
        return guid
      end
    end
  end

  local getInventoryItemGUID = rawget(_G, "GetInventoryItemGUID")
  if getInventoryItemGUID then
    local invSlot = GetInventorySlotInfo(NS.SLOT_ID_TO_NAME[slotId])
    if invSlot then
      local okGuid, guid = pcall(getInventoryItemGUID, "player", invSlot)
      if okGuid and guid then
        return guid
      end
    end
  end

  return nil
end

local function getGuidFromBagSlot(bag, slot)
  if C_Item and C_Item.GetItemGUID and ItemLocation and ItemLocation.CreateFromBagAndSlot then
    local okLoc, loc = pcall(ItemLocation.CreateFromBagAndSlot, bag, slot)
    if okLoc and loc then
      local okGuid, guid = pcall(C_Item.GetItemGUID, loc)
      if okGuid and guid then
        return guid
      end
    end
  end

  return nil
end

local function getNativeComparisonItemFromTooltipData(data)
  if type(data) == "table" and type(data.item) == "table" then
    return data.item
  end
  if type(data) == "table" and (data.guid or data.itemGUID or data.hyperlink or data.id or data.type) then
    return data
  end
  return nil
end

local function getNativeComparisonItemForInventorySlot(slotId)
  if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then
    return nil
  end
  local invSlot = GetInventorySlotInfo(NS.SLOT_ID_TO_NAME[slotId])
  if not invSlot then
    return nil
  end
  local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", invSlot)
  if not ok then
    return nil
  end
  return getNativeComparisonItemFromTooltipData(data)
end

local function getNativeComparisonItemForBagSlot(bag, slot)
  if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then
    return nil
  end
  local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
  if not ok then
    return nil
  end
  return getNativeComparisonItemFromTooltipData(data)
end

local function getItemRefFromInventoryByLink(itemLink)
  if not itemLink then
    return nil
  end
  for slotId, slotName in pairs(NS.SLOT_ID_TO_NAME) do
    local invSlot = GetInventorySlotInfo(slotName)
    if invSlot then
      local link = GetInventoryItemLink("player", invSlot)
      if link == itemLink then
        local guid = getGuidFromEquipmentSlot(slotId)
        local comparisonItem = getNativeComparisonItemForInventorySlot(slotId)
        return { link = link, guid = guid, slotId = slotId, comparisonItem = comparisonItem }
      end
    end
  end
  return nil
end

local function getItemRefFromBagsByLink(itemLink)
  if not itemLink or not C_Container or not C_Container.GetContainerNumSlots or not C_Container.GetContainerItemInfo then
    return nil
  end
  for bag = 0, 4 do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.hyperlink == itemLink then
        local guid = info["itemGUID"] or info["guid"] or getGuidFromBagSlot(bag, slot)
        local comparisonItem = getNativeComparisonItemForBagSlot(bag, slot)
        return { link = itemLink, guid = guid, bag = bag, slot = slot, comparisonItem = comparisonItem }
      end
    end
  end
  return nil
end

local function resolveOwnedItemRef(itemRef)
  if type(itemRef) == "table" then
    local link = itemRef.link or itemRef.itemLink or itemRef.hyperlink
    local guid = itemRef.guid or itemRef.itemGUID
    local comparisonItem = itemRef.comparisonItem
    if guid then
      return {
        link = link,
        guid = guid,
        itemGUID = itemRef.itemGUID,
        comparisonItem = comparisonItem,
        slotId = itemRef.slotId,
        bag = itemRef.bag,
        slot = itemRef.slot,
      }
    end
    if link then
      local bagRef = getItemRefFromBagsByLink(link)
      if bagRef then
        bagRef.comparisonItem = comparisonItem
        return bagRef
      end
      local invRef = getItemRefFromInventoryByLink(link)
      if invRef then
        invRef.comparisonItem = comparisonItem
        return invRef
      end
      return { link = link, comparisonItem = comparisonItem }
    end
    return itemRef
  end

  local link = itemRef
  if not link then
    return nil
  end
  local bagRef = getItemRefFromBagsByLink(link)
  if bagRef then return bagRef end
  local invRef = getItemRefFromInventoryByLink(link)
  if invRef then return invRef end
  return { link = link }
end

-- Extract stat deltas using numeric item stat APIs.
-- Optional pairedItemLink supports explicit dual-slot math (e.g. 2H vs MH+OH).
local function getItemStatDeltas(itemLink, equippedItemLink, pairedItemLink, addPairedStats)
  if not (C_Item and C_Item.GetItemStatDelta and C_Item.GetItemStats) then
    return nil, "item stat API unavailable"
  end

  local comparisonLink = itemRefToLink(itemLink)
  local equippedLink = itemRefToLink(equippedItemLink)
  local pairedLink = itemRefToLink(pairedItemLink)

  if not comparisonLink or not equippedLink then
    return nil, "missing item link context"
  end

  local stats = {
    primary_stat = 0,
    crit = 0,
    haste = 0,
    mastery = 0,
    versatility = 0,
  }

  local function applyStatTable(deltaTable, sign)
    NS.applyItemStatMods(stats, deltaTable, sign)
  end

  -- Primary comparison is always explicit: comparison item minus equipped item.
  local okDelta, statDelta = pcall(C_Item.GetItemStatDelta, comparisonLink, equippedLink)
  if not okDelta or type(statDelta) ~= "table" then
    if not didWarnComparisonError then
      didWarnComparisonError = true
      NS.brandPrint("GetItemStatDelta failed for compared/equipped links")
    end
    return nil, "failed to compute item stat delta"
  end
  applyStatTable(statDelta, 1)

  -- Optional paired item adjustment is explicit numeric math.
  -- addPairedStats=true: include paired stats; false/nil: subtract paired stats.
  if pairedLink then
    local okPaired, pairedStats = pcall(C_Item.GetItemStats, pairedLink)
    if not okPaired or type(pairedStats) ~= "table" then
      return nil, "failed to read paired item stats"
    end
    local pairedSign = (addPairedStats == true) and 1 or -1
    applyStatTable(pairedStats, pairedSign)
  end

  return stats, nil
end

NS.statDeltaStats = { native = 0, fallback = 0 }

local function statsFromItemLink(link)
  if not link or not (C_Item and C_Item.GetItemStats) then
    return nil
  end
  local ok, statTable = pcall(C_Item.GetItemStats, link)
  if not ok or type(statTable) ~= "table" then
    return nil
  end
  return {
    primary_stat = (statTable.ITEM_MOD_STRENGTH_SHORT or 0)
      + (statTable.ITEM_MOD_AGILITY_SHORT or 0)
      + (statTable.ITEM_MOD_INTELLECT_SHORT or 0),
    crit = (statTable.ITEM_MOD_CRIT_RATING_SHORT or 0) + (statTable.ITEM_MOD_CR_CRIT_SHORT or 0),
    haste = statTable.ITEM_MOD_HASTE_RATING_SHORT or 0,
    mastery = statTable.ITEM_MOD_MASTERY_RATING_SHORT or 0,
    versatility = (statTable.ITEM_MOD_VERSATILITY or 0) + (statTable.ITEM_MOD_VERSATILITY_SHORT or 0),
  }
end

local function subtractStats(a, b)
  return {
    primary_stat = (a.primary_stat or 0) - (b.primary_stat or 0),
    crit = (a.crit or 0) - (b.crit or 0),
    haste = (a.haste or 0) - (b.haste or 0),
    mastery = (a.mastery or 0) - (b.mastery or 0),
    versatility = (a.versatility or 0) - (b.versatility or 0),
  }
end

local function candidateRefFromCand(cand, slotId)
  if not cand or not cand.link then
    return nil
  end
  local ref = {
    link = cand.link,
    guid = cand.guid,
    bag = cand.bag,
    slot = cand.slot,
    comparisonItem = cand.comparisonItem,
    slotId = slotId,
  }
  if resolveOwnedItemRef then
    return resolveOwnedItemRef(ref) or ref
  end
  return ref
end

-- Unified stat delta: native GetItemStatDelta first, then raw stat subtraction fallback.
local function computeStatDelta(candRef, eqRef, opts)
  opts = opts or {}
  local pairedRef = opts.pairedRef
  local addPaired = opts.addPaired

  local resolvedCand = candRef and (resolveOwnedItemRef(candRef) or candRef) or nil
  local resolvedEq = eqRef and (resolveOwnedItemRef(eqRef) or eqRef) or nil
  local candLink = itemRefToLink(resolvedCand)
  local eqLink = itemRefToLink(resolvedEq)

  if not candLink then
    return nil, "missing candidate link"
  end

  if resolvedEq and eqLink then
    local delta, err = getItemStatDeltas(
      resolvedCand, resolvedEq, pairedRef and (resolveOwnedItemRef(pairedRef) or pairedRef) or nil, addPaired
    )
    if delta then
      NS.statDeltaStats.native = (NS.statDeltaStats.native or 0) + 1
      return delta, "native"
    end
  end

  local candStats = statsFromItemLink(candLink)
  if not candStats then
    return nil, "failed to read candidate stats"
  end
  local eqStats = eqLink and statsFromItemLink(eqLink) or {
    primary_stat = 0, crit = 0, haste = 0, mastery = 0, versatility = 0,
  }
  if eqLink and not eqStats then
    return nil, "failed to read equipped stats"
  end

  NS.statDeltaStats.fallback = (NS.statDeltaStats.fallback or 0) + 1
  if MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.debug then
    NS.debugPrint(string.format(
      "%s: stat delta fallback for %s (native API failed)",
      NS.BRAND or "MrMythical",
      candLink:match("item:%d+") or "item"
    ))
  end

  local fb = subtractStats(candStats, eqStats)
  if pairedRef then
    local pairLink = itemRefToLink(resolveOwnedItemRef(pairedRef) or pairedRef)
    local pairStats = pairLink and statsFromItemLink(pairLink)
    if pairStats then
      local sign = (addPaired == true) and 1 or -1
      fb = addStats(fb, pairStats, sign)
    end
  end
  return fb, "fallback"
end

local function resetStatDeltaStats()
  NS.statDeltaStats.native = 0
  NS.statDeltaStats.fallback = 0
end

local function addStats(a, b, sign)
  return {
    primary_stat = (a.primary_stat or 0) + sign * (b.primary_stat or 0),
    crit = (a.crit or 0) + sign * (b.crit or 0),
    haste = (a.haste or 0) + sign * (b.haste or 0),
    mastery = (a.mastery or 0) + sign * (b.mastery or 0),
    versatility = (a.versatility or 0) + sign * (b.versatility or 0),
  }
end

local function predictWithStats(stats, specKey)
  local x = {
    stats.primary_stat or 0,
    stats.crit or 0,
    stats.haste or 0,
    stats.mastery or 0,
    stats.versatility or 0,
  }
  return forward(x, specKey)
end

-- Prediction LRU cache: exact stat vector + specKey.
local predictionCache = {}
local predictionCacheOrder = 0
local MAX_PREDICTION_CACHE_SIZE = 512
NS.predictionCacheStats = { hits = 0, misses = 0 }

local function predictionCacheKey(stats, specKey)
  return string.format(
    "%d:%d:%d:%d:%d:%s",
    stats.primary_stat or 0,
    stats.crit or 0,
    stats.haste or 0,
    stats.mastery or 0,
    stats.versatility or 0,
    specKey or ""
  )
end

local function evictOldestPrediction()
  local count = 0
  for _ in pairs(predictionCache) do count = count + 1 end
  if count <= MAX_PREDICTION_CACHE_SIZE then return end

  local oldest_key, oldest_order = nil, math.huge
  for k, v in pairs(predictionCache) do
    if v.order < oldest_order then
      oldest_key = k
      oldest_order = v.order
    end
  end
  if oldest_key then
    predictionCache[oldest_key] = nil
  end
end

local function clearPredictionCaches()
  predictionCache = {}
  predictionCacheOrder = 0
  NS.predictionCacheStats.hits = 0
  NS.predictionCacheStats.misses = 0
end

local function getCachedPrediction(stats, specKey)
  if NS.baseDpsCacheDirty then
    clearPredictionCaches()
    NS.baseDpsCacheDirty = false
  end
  local key = predictionCacheKey(stats, specKey)
  local cached = predictionCache[key]
  if cached then
    cached.order = predictionCacheOrder
    predictionCacheOrder = predictionCacheOrder + 1
    NS.predictionCacheStats.hits = NS.predictionCacheStats.hits + 1
    return cached.dps
  end
  NS.predictionCacheStats.misses = NS.predictionCacheStats.misses + 1
  local dps = predictWithStats(stats, specKey)
  evictOldestPrediction()
  predictionCache[key] = { dps = dps, order = predictionCacheOrder }
  predictionCacheOrder = predictionCacheOrder + 1
  return dps
end

-- Base DPS: same LRU as getCachedPrediction (exact stat key).
NS.baseDpsCacheDirty = true

local function getCachedBaseDps(stats, specKey)
  return getCachedPrediction(stats, specKey)
end

NS.itemRefToLink = itemRefToLink
NS.getPlayerStatVector = getPlayerStatVector
NS.getItemStatDeltas = getItemStatDeltas
NS.computeStatDelta = computeStatDelta
NS.statsFromItemLink = statsFromItemLink
NS.candidateRefFromCand = candidateRefFromCand
NS.resetStatDeltaStats = resetStatDeltaStats
NS.addStats = addStats
NS.resolveOwnedItemRef = resolveOwnedItemRef
NS.getGuidFromEquipmentSlot = getGuidFromEquipmentSlot
NS.getGuidFromBagSlot = getGuidFromBagSlot
NS.getNativeComparisonItemForInventorySlot = getNativeComparisonItemForInventorySlot
NS.getNativeComparisonItemForBagSlot = getNativeComparisonItemForBagSlot
NS.predictWithStats = predictWithStats
NS.getCachedPrediction = getCachedPrediction
NS.getCachedBaseDps = getCachedBaseDps

