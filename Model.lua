local ADDON_NAME, NS = ...
local Model = NS.Model
local didWarnComparisonError = false

-- The exported model is immutable for the lifetime of the addon. Bind its hot
-- fields once so each inference does not repeatedly walk the model tables.
local modelDef = Model.single_model
local scaler = Model.scaler
local layers = modelDef.layers
local outputLayer = modelDef.output
local specBiasByKey = modelDef.prebaked
local xMean = scaler.x_mean
local xScale = scaler.x_scale
local yScale = scaler.y_scale
local yMean = scaler.y_mean
local nLayers = #layers

-- Pre-allocated ping-pong buffers avoid all hidden-layer allocations.
local buf_a = {}
local buf_b = {}
local maxForwardWidth = Model.n_stat_features or 5
for li = 1, nLayers do
  local width = #layers[li].w
  if width > maxForwardWidth then
    maxForwardWidth = width
  end
end
for i = 1, maxForwardWidth do
  buf_a[i] = 0
  buf_b[i] = 0
end

NS.forwardProfile = NS.forwardProfile or { count = 0, totalMs = 0 }

local function forwardModelStats(stats, specKey)
  local profileStart
  if MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.debug and debugprofilestop then
    profileStart = debugprofilestop()
  end

  -- The current model has exactly five named inputs. Writing them straight to
  -- the normalized buffer avoids constructing a temporary positional table.
  buf_a[1] = ((stats.primary_stat or 0) - xMean[1]) / xScale[1]
  buf_a[2] = ((stats.crit or 0) - xMean[2]) / xScale[2]
  buf_a[3] = ((stats.haste or 0) - xMean[3]) / xScale[3]
  buf_a[4] = ((stats.mastery or 0) - xMean[4]) / xScale[4]
  buf_a[5] = ((stats.versatility or 0) - xMean[5]) / xScale[5]

  local src = buf_a
  local dst = buf_b
  local inputSize = 5
  local specBias = specBiasByKey and specBiasByKey[specKey] or nil

  for li = 1, nLayers do
    local layer = layers[li]
    local layerW = layer.w
    local layerB = (li == 1 and specBias) or layer.b
    local outSize = #layerW
    local bnS = layer.bn_s
    local bnO = layer.bn_o

    if inputSize == 5 then
      -- The first layer is fixed-width. Keep the same left-to-right sum order
      -- as the old dot() loop while removing 200 function/loop dispatches.
      local x1, x2, x3, x4, x5 = src[1], src[2], src[3], src[4], src[5]
      for i = 1, outSize do
        local row = layerW[i]
        local s = layerB[i]
        s = s + row[1] * x1
        s = s + row[2] * x2
        s = s + row[3] * x3
        s = s + row[4] * x4
        s = s + row[5] * x5
        if s <= 0 then
          s = 0
        end
        dst[i] = bnS[i] * s + bnO[i]
      end
    elseif inputSize == 200 then
      -- The second dense layer dominates inference time. Unroll its fixed
      -- 200-wide dot product while preserving the original addition order.
      for i = 1, outSize do
        local row = layerW[i]
        local s = layerB[i]
        local j = 1
        while j <= 200 do
          s = s + row[j] * src[j]
          s = s + row[j + 1] * src[j + 1]
          s = s + row[j + 2] * src[j + 2]
          s = s + row[j + 3] * src[j + 3]
          s = s + row[j + 4] * src[j + 4]
          s = s + row[j + 5] * src[j + 5]
          s = s + row[j + 6] * src[j + 6]
          s = s + row[j + 7] * src[j + 7]
          j = j + 8
        end
        if s <= 0 then
          s = 0
        end
        dst[i] = bnS[i] * s + bnO[i]
      end
    else
      for i = 1, outSize do
        local row = layerW[i]
        local s = layerB[i]
        for j = 1, inputSize do
          s = s + row[j] * src[j]
        end
        if s <= 0 then
          s = 0
        end
        dst[i] = bnS[i] * s + bnO[i]
      end
    end

    inputSize = outSize
    src, dst = dst, src
  end

  local outputW = outputLayer.w
  local yScaled = outputLayer.b
  local outputSize = #outputW
  local i = 1
  while i <= outputSize - 7 do
    yScaled = yScaled + outputW[i] * src[i]
    yScaled = yScaled + outputW[i + 1] * src[i + 1]
    yScaled = yScaled + outputW[i + 2] * src[i + 2]
    yScaled = yScaled + outputW[i + 3] * src[i + 3]
    yScaled = yScaled + outputW[i + 4] * src[i + 4]
    yScaled = yScaled + outputW[i + 5] * src[i + 5]
    yScaled = yScaled + outputW[i + 6] * src[i + 6]
    yScaled = yScaled + outputW[i + 7] * src[i + 7]
    i = i + 8
  end
  while i <= outputSize do
    yScaled = yScaled + outputW[i] * src[i]
    i = i + 1
  end
  local y = yScaled * yScale + yMean

  if profileStart then
    NS.forwardProfile.count = NS.forwardProfile.count + 1
    NS.forwardProfile.totalMs = NS.forwardProfile.totalMs + (debugprofilestop() - profileStart)
  end

  return y
end

-- Within a fixed first-layer ReLU activation pattern, the first two dense
-- layers collapse to a 5-input affine transform. Keep a few reference
-- patterns per spec and apply only the neurons that changed from the nearest
-- reference. This bounds memory while avoiding the 200-wide second-layer dot.
local MAX_FUSED_REFERENCES_PER_SPEC = 8
local NEW_FUSED_REFERENCE_DISTANCE = 16
local fusedReferencesBySpec = {}
local fusedActive = {}
local fusedPreactivation = {}
local fusedChangedIndices = {}
local fusedChangedValues = {}
local fusedInvariantOffsets = {}
local fusedFirstWidth = layers[1] and #layers[1].w or 0
local fusedSecondWidth = layers[2] and #layers[2].w or 0
NS.fusedForwardProfile = NS.fusedForwardProfile or {
  hits = 0,
  misses = 0,
  evictions = 0,
  changed_neurons = 0,
  max_changed_neurons = 0,
}

local fusedTopologyAvailable = nLayers == 2
  and layers[1]
  and layers[2]
  and fusedFirstWidth == 200
  and fusedSecondWidth > 0
  and layers[2].w[1]
  and #layers[2].w[1] == fusedFirstWidth
  and #outputLayer.w == fusedSecondWidth

if fusedTopologyAvailable then
  local layer1BnO = layers[1].bn_o
  local layer2 = layers[2]
  for outputIndex = 1, fusedSecondWidth do
    local row = layer2.w[outputIndex]
    local value = layer2.b[outputIndex]
    for inputIndex = 1, fusedFirstWidth do
      value = value + row[inputIndex] * layer1BnO[inputIndex]
    end
    fusedInvariantOffsets[outputIndex] = value
  end
end

local function buildFusedPattern(specBias, active)
  local layer1 = layers[1]
  local layer2 = layers[2]
  local c0, c1, c2, c3, c4, c5 = {}, {}, {}, {}, {}, {}
  for outputIndex = 1, fusedSecondWidth do
    local row = layer2.w[outputIndex]
    local bias = fusedInvariantOffsets[outputIndex]
    local w1, w2, w3, w4, w5 = 0, 0, 0, 0, 0
    for inputIndex = 1, fusedFirstWidth do
      if active[inputIndex] then
        local factor = row[inputIndex] * layer1.bn_s[inputIndex]
        bias = bias + factor * specBias[inputIndex]
        local inputRow = layer1.w[inputIndex]
        w1 = w1 + factor * inputRow[1]
        w2 = w2 + factor * inputRow[2]
        w3 = w3 + factor * inputRow[3]
        w4 = w4 + factor * inputRow[4]
        w5 = w5 + factor * inputRow[5]
      end
    end
    c0[outputIndex] = bias
    c1[outputIndex] = w1
    c2[outputIndex] = w2
    c3[outputIndex] = w3
    c4[outputIndex] = w4
    c5[outputIndex] = w5
  end
  return { c0 = c0, c1 = c1, c2 = c2, c3 = c3, c4 = c4, c5 = c5 }
end

local function buildFusedReference(specBias, active)
  local reference = buildFusedPattern(specBias, active)
  reference.active = {}
  for i = 1, fusedFirstWidth do
    reference.active[i] = active[i]
  end
  return reference
end

local function forwardModelStatsFused(stats, specKey)
  local specBias = specBiasByKey and specBiasByKey[specKey] or nil
  if not fusedTopologyAvailable or not specBias then
    return forwardModelStats(stats, specKey)
  end

  local profileStart
  if MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.debug and debugprofilestop then
    profileStart = debugprofilestop()
  end

  local x1 = ((stats.primary_stat or 0) - xMean[1]) / xScale[1]
  local x2 = ((stats.crit or 0) - xMean[2]) / xScale[2]
  local x3 = ((stats.haste or 0) - xMean[3]) / xScale[3]
  local x4 = ((stats.mastery or 0) - xMean[4]) / xScale[4]
  local x5 = ((stats.versatility or 0) - xMean[5]) / xScale[5]
  local layer1W = layers[1].w
  for i = 1, fusedFirstWidth do
    local row = layer1W[i]
    local value = specBias[i]
    value = value + row[1] * x1
    value = value + row[2] * x2
    value = value + row[3] * x3
    value = value + row[4] * x4
    value = value + row[5] * x5
    fusedPreactivation[i] = value
    fusedActive[i] = value > 0
  end

  local references = fusedReferencesBySpec[specKey]
  if not references then
    references = {}
    fusedReferencesBySpec[specKey] = references
  end
  local fused
  local bestDistance
  for _, reference in ipairs(references) do
    local distance = 0
    for i = 1, fusedFirstWidth do
      if reference.active[i] ~= fusedActive[i] then
        distance = distance + 1
      end
    end
    if not bestDistance or distance < bestDistance then
      fused = reference
      bestDistance = distance
      if distance == 0 then
        break
      end
    end
  end
  if not fused
    or (bestDistance > NEW_FUSED_REFERENCE_DISTANCE and #references < MAX_FUSED_REFERENCES_PER_SPEC) then
    fused = buildFusedReference(specBias, fusedActive)
    references[#references + 1] = fused
    bestDistance = 0
    NS.fusedForwardProfile.misses = NS.fusedForwardProfile.misses + 1
  else
    NS.fusedForwardProfile.hits = NS.fusedForwardProfile.hits + 1
  end

  local changedCount = 0
  if bestDistance > 0 then
    local layer1BnS = layers[1].bn_s
    for i = 1, fusedFirstWidth do
      if fused.active[i] ~= fusedActive[i] then
        changedCount = changedCount + 1
        fusedChangedIndices[changedCount] = i
        local sign = fusedActive[i] and 1 or -1
        fusedChangedValues[changedCount] = sign * layer1BnS[i] * fusedPreactivation[i]
      end
    end
  end
  NS.fusedForwardProfile.changed_neurons = NS.fusedForwardProfile.changed_neurons + changedCount
  if changedCount > NS.fusedForwardProfile.max_changed_neurons then
    NS.fusedForwardProfile.max_changed_neurons = changedCount
  end

  local layer2 = layers[2]
  local outputW = outputLayer.w
  local yScaled = outputLayer.b
  for i = 1, fusedSecondWidth do
    local value = fused.c0[i]
    value = value + fused.c1[i] * x1
    value = value + fused.c2[i] * x2
    value = value + fused.c3[i] * x3
    value = value + fused.c4[i] * x4
    value = value + fused.c5[i] * x5
    local row = layer2.w[i]
    for changedIndex = 1, changedCount do
      value = value + row[fusedChangedIndices[changedIndex]] * fusedChangedValues[changedIndex]
    end
    if value <= 0 then
      value = 0
    end
    local hidden = layer2.bn_s[i] * value + layer2.bn_o[i]
    yScaled = yScaled + outputW[i] * hidden
  end
  local y = yScaled * yScale + yMean

  if profileStart then
    NS.forwardProfile.count = NS.forwardProfile.count + 1
    NS.forwardProfile.totalMs = NS.forwardProfile.totalMs + (debugprofilestop() - profileStart)
  end
  return y
end

local function predictWithStats(stats, specKey)
  return forwardModelStats(stats, specKey)
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
        return { link = link, guid = guid, slotId = slotId }
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
        return { link = itemLink, guid = guid, bag = bag, slot = slot }
      end
    end
  end
  return nil
end

local function resolveOwnedItemRef(itemRef)
  if type(itemRef) == "table" then
    local link = itemRef.link or itemRef.itemLink or itemRef.hyperlink
    local guid = itemRef.guid or itemRef.itemGUID
    if guid then
      return {
        link = link,
        guid = guid,
        itemGUID = itemRef.itemGUID,
        slotId = itemRef.slotId,
        bag = itemRef.bag,
        slot = itemRef.slot,
      }
    end
    if link then
      local bagRef = getItemRefFromBagsByLink(link)
      if bagRef then
        return bagRef
      end
      local invRef = getItemRefFromInventoryByLink(link)
      if invRef then
        return invRef
      end
      return { link = link }
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

local function makeZeroStats()
  return {
    primary_stat = 0,
    crit = 0,
    haste = 0,
    mastery = 0,
    versatility = 0,
  }
end

local ZERO_STATS = makeZeroStats()

local function addStatsInto(dst, a, b, sign)
  sign = sign or 1
  dst.primary_stat = (a.primary_stat or 0) + sign * (b.primary_stat or 0)
  dst.crit = (a.crit or 0) + sign * (b.crit or 0)
  dst.haste = (a.haste or 0) + sign * (b.haste or 0)
  dst.mastery = (a.mastery or 0) + sign * (b.mastery or 0)
  dst.versatility = (a.versatility or 0) + sign * (b.versatility or 0)
  return dst
end

local function addStats(a, b, sign)
  return addStatsInto(makeZeroStats(), a, b, sign)
end

-- Small fixed-size FIFO caches are sufficient for immutable full item links.
-- They avoid an O(n) eviction scan and never cache a transient API failure.
local function makeBoundedCache(limit)
  return {
    values = {},
    order = {},
    nextSlot = 1,
    count = 0,
    limit = limit,
  }
end

local function boundedCacheGet(cache, key)
  return cache.values[key]
end

local function boundedCachePut(cache, key, value)
  if cache.values[key] ~= nil then
    cache.values[key] = value
    return
  end

  local slot = cache.nextSlot
  local oldKey = cache.order[slot]
  if oldKey ~= nil then
    cache.values[oldKey] = nil
  else
    cache.count = cache.count + 1
  end

  cache.order[slot] = key
  cache.values[key] = value
  cache.nextSlot = (slot % cache.limit) + 1
end

local ITEM_STATS_CACHE_SIZE = 1024
local STAT_DELTA_CACHE_SIZE = 2048
local itemStatsCache = makeBoundedCache(ITEM_STATS_CACHE_SIZE)
local statDeltaCache = makeBoundedCache(STAT_DELTA_CACHE_SIZE)

local function clearStatCaches()
  itemStatsCache = makeBoundedCache(ITEM_STATS_CACHE_SIZE)
  statDeltaCache = makeBoundedCache(STAT_DELTA_CACHE_SIZE)
end

local function getItemIDFromLink(link)
  if type(link) == "number" then
    return link
  end
  if type(link) ~= "string" then
    return nil
  end
  return tonumber(link:match("item:(%d+)")) or tonumber(link)
end

local function isItemDataReadyForStats(link)
  local itemID = getItemIDFromLink(link)
  if not itemID or not C_Item or not C_Item.IsItemDataCachedByID then
    return true
  end

  local okCached, cached = pcall(C_Item.IsItemDataCachedByID, itemID)
  if okCached and not cached then
    if C_Item.RequestLoadItemDataByID then
      pcall(C_Item.RequestLoadItemDataByID, itemID)
    elseif GetItemInfo then
      GetItemInfo(itemID)
    end
    return false
  end
  if C_Item.GetDetailedItemLevelInfo then
    local okIlvl, ilvl = pcall(C_Item.GetDetailedItemLevelInfo, link)
    if okIlvl and (type(ilvl) ~= "number" or ilvl <= 0) then
      if C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
      end
      return false
    end
  end
  return true
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

  local stats = makeZeroStats()

  -- Primary comparison is always explicit: comparison item minus equipped item.
  local okDelta, statDelta = pcall(C_Item.GetItemStatDelta, comparisonLink, equippedLink)
  if not okDelta or type(statDelta) ~= "table" then
    if not didWarnComparisonError then
      didWarnComparisonError = true
      NS.brandPrint("GetItemStatDelta failed for compared/equipped links")
    end
    return nil, "failed to compute item stat delta"
  end
  NS.applyItemStatMods(stats, statDelta, 1)

  -- Optional paired item adjustment is explicit numeric math.
  -- addPairedStats=true: include paired stats; false/nil: subtract paired stats.
  if pairedLink then
    local okPaired, pairedStats = pcall(C_Item.GetItemStats, pairedLink)
    if not okPaired or type(pairedStats) ~= "table" then
      return nil, "failed to read paired item stats"
    end
    local pairedSign = (addPairedStats == true) and 1 or -1
    NS.applyItemStatMods(stats, pairedStats, pairedSign)
  end

  return stats, nil
end

NS.statDeltaStats = NS.statDeltaStats or {
  native = 0,
  fallback = 0,
  cache_hits = 0,
  cache_misses = 0,
  item_stats_hits = 0,
  item_stats_misses = 0,
  totalMs = 0,
}

local function statsFromItemLink(link)
  if not link or not (C_Item and C_Item.GetItemStats) then
    return nil
  end
  local cached = boundedCacheGet(itemStatsCache, link)
  if cached then
    NS.statDeltaStats.item_stats_hits = (NS.statDeltaStats.item_stats_hits or 0) + 1
    return cached
  end
  NS.statDeltaStats.item_stats_misses = (NS.statDeltaStats.item_stats_misses or 0) + 1
  if not isItemDataReadyForStats(link) then
    return nil
  end
  local ok, statTable = pcall(C_Item.GetItemStats, link)
  if not ok or type(statTable) ~= "table" then
    return nil
  end
  local stats = makeZeroStats()
  NS.applyItemStatMods(stats, statTable, 1)
  if stats.primary_stat == 0
    and stats.crit == 0
    and stats.haste == 0
    and stats.mastery == 0
    and stats.versatility == 0 then
    -- GetItemStats can return an empty table while a synthetic item link is
    -- still resolving. Do not poison the cache with that transient result.
    return nil
  end
  boundedCachePut(itemStatsCache, link, stats)
  return stats
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
    slotId = slotId,
  }
  return ref
end

local function finishStatDelta(profileStart, value, detail)
  if profileStart then
    NS.statDeltaStats.totalMs = (NS.statDeltaStats.totalMs or 0) + (debugprofilestop() - profileStart)
  end
  return value, detail
end

-- Unified stat delta: native GetItemStatDelta first, then raw stat subtraction fallback.
local function computeStatDelta(candRef, eqRef, opts)
  local profileStart
  if MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.debug and debugprofilestop then
    profileStart = debugprofilestop()
  end

  local pairedRef = opts and opts.pairedRef or nil
  local addPaired = opts and opts.addPaired or nil
  local candLink = itemRefToLink(candRef)
  local eqLink = itemRefToLink(eqRef)
  local pairLink = itemRefToLink(pairedRef)

  if not candLink then
    return finishStatDelta(profileStart, nil, "missing candidate link")
  end

  local cacheKey = candLink
    .. "\30" .. (eqLink or "")
    .. "\30" .. (pairLink or "")
    .. "\30" .. (addPaired == true and "1" or "0")
  local cached = boundedCacheGet(statDeltaCache, cacheKey)
  if cached then
    NS.statDeltaStats.cache_hits = (NS.statDeltaStats.cache_hits or 0) + 1
    -- Cached stat vectors are immutable; callers combine them into separate
    -- destination buffers via addStatsInto.
    return finishStatDelta(profileStart, cached.delta, cached.source)
  end
  NS.statDeltaStats.cache_misses = (NS.statDeltaStats.cache_misses or 0) + 1

  -- Validate every participating link before trusting either API path. A
  -- successful API call can still contain empty data while item information is
  -- loading, and caching that result makes the entire scan consistently wrong.
  local candStats = statsFromItemLink(candLink)
  if not candStats then
    return finishStatDelta(profileStart, nil, "candidate item data not ready")
  end
  local eqStats = eqLink and statsFromItemLink(eqLink) or ZERO_STATS
  if eqLink and not eqStats then
    return finishStatDelta(profileStart, nil, "equipped item data not ready")
  end
  local pairStats = pairLink and statsFromItemLink(pairLink) or nil
  if pairLink and not pairStats then
    return finishStatDelta(profileStart, nil, "paired item data not ready")
  end

  if eqLink then
    local delta = getItemStatDeltas(candLink, eqLink, pairLink, addPaired)
    if delta then
      NS.statDeltaStats.native = (NS.statDeltaStats.native or 0) + 1
      boundedCachePut(statDeltaCache, cacheKey, { delta = delta, source = "native" })
      return finishStatDelta(profileStart, delta, "native")
    end
  end

  NS.statDeltaStats.fallback = (NS.statDeltaStats.fallback or 0) + 1
  if MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.debug then
    NS.debugPrint(string.format(
      "%s: stat delta fallback for %s (native API failed)",
      NS.BRAND or "MrMythical",
      candLink:match("item:%d+") or "item"
    ))
  end

  local fb = addStatsInto(makeZeroStats(), candStats, eqStats, -1)
  if pairLink then
    local sign = (addPaired == true) and 1 or -1
    addStatsInto(fb, fb, pairStats, sign)
  end
  return finishStatDelta(profileStart, fb, "fallback")
end

local function resetStatDeltaStats()
  NS.statDeltaStats.native = 0
  NS.statDeltaStats.fallback = 0
  NS.statDeltaStats.cache_hits = 0
  NS.statDeltaStats.cache_misses = 0
  NS.statDeltaStats.item_stats_hits = 0
  NS.statDeltaStats.item_stats_misses = 0
  NS.statDeltaStats.totalMs = 0
end

local function getStatCacheSnapshot()
  return {
    item_stats_size = itemStatsCache.count,
    stat_delta_size = statDeltaCache.count,
  }
end

-- Prediction cache: collision-checked numeric tuples, grouped by spec, with an
-- O(1) doubly linked LRU. The 2k cap covers common scan working sets while
-- remaining small relative to the model data itself.
local MAX_PREDICTION_CACHE_SIZE = 2048
local HASH_MOD = 2147483647
local HASH_MULT = 65599
local predictionBucketsBySpec = {}
local predictionCacheHead = nil
local predictionCacheTail = nil
local predictionCacheSize = 0
NS.predictionCacheStats = {
  hits = 0,
  misses = 0,
  evictions = 0,
  peak_size = 0,
  lookupMs = 0,
  insertMs = 0,
  evictionMs = 0,
}

local function cacheInteger(value)
  value = tonumber(value) or 0
  if value < 0 then
    return math.ceil(value)
  end
  return math.floor(value)
end

local function predictionTuple(stats)
  return cacheInteger(stats.primary_stat),
    cacheInteger(stats.crit),
    cacheInteger(stats.haste),
    cacheInteger(stats.mastery),
    cacheInteger(stats.versatility)
end

local function predictionTupleHash(primary, crit, haste, mastery, versatility)
  local hash = primary % HASH_MOD
  hash = (hash * HASH_MULT + crit) % HASH_MOD
  hash = (hash * HASH_MULT + haste) % HASH_MOD
  hash = (hash * HASH_MULT + mastery) % HASH_MOD
  hash = (hash * HASH_MULT + versatility) % HASH_MOD
  return hash
end

local function unlinkPrediction(entry)
  local prev = entry.prev
  local nextEntry = entry.next
  if prev then
    prev.next = nextEntry
  else
    predictionCacheHead = nextEntry
  end
  if nextEntry then
    nextEntry.prev = prev
  else
    predictionCacheTail = prev
  end
  entry.prev = nil
  entry.next = nil
end

local function appendPrediction(entry)
  entry.prev = predictionCacheTail
  entry.next = nil
  if predictionCacheTail then
    predictionCacheTail.next = entry
  else
    predictionCacheHead = entry
  end
  predictionCacheTail = entry
end

local function touchPrediction(entry)
  if predictionCacheTail == entry then
    return
  end
  unlinkPrediction(entry)
  appendPrediction(entry)
end

local function removePredictionFromBucket(entry)
  local specBuckets = predictionBucketsBySpec[entry.specKey]
  if not specBuckets then
    return
  end
  local current = specBuckets[entry.hash]
  local previous = nil
  while current do
    if current == entry then
      if previous then
        previous.bucketNext = current.bucketNext
      else
        specBuckets[entry.hash] = current.bucketNext
      end
      current.bucketNext = nil
      return
    end
    previous = current
    current = current.bucketNext
  end
end

local function evictOldestPrediction()
  if predictionCacheSize <= MAX_PREDICTION_CACHE_SIZE or not predictionCacheHead then
    return
  end
  local profileStart
  if MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.debug and debugprofilestop then
    profileStart = debugprofilestop()
  end
  local oldest = predictionCacheHead
  unlinkPrediction(oldest)
  removePredictionFromBucket(oldest)
  predictionCacheSize = predictionCacheSize - 1
  NS.predictionCacheStats.evictions = NS.predictionCacheStats.evictions + 1
  if profileStart then
    NS.predictionCacheStats.evictionMs = NS.predictionCacheStats.evictionMs
      + (debugprofilestop() - profileStart)
  end
end

local function findPrediction(specKey, hash, primary, crit, haste, mastery, versatility)
  local specBuckets = predictionBucketsBySpec[specKey]
  local entry = specBuckets and specBuckets[hash] or nil
  while entry do
    if entry.primary == primary
      and entry.crit == crit
      and entry.haste == haste
      and entry.mastery == mastery
      and entry.versatility == versatility
    then
      return entry
    end
    entry = entry.bucketNext
  end
  return nil
end

local function clearPredictionCaches()
  predictionBucketsBySpec = {}
  predictionCacheHead = nil
  predictionCacheTail = nil
  predictionCacheSize = 0
  NS.predictionCacheStats.hits = 0
  NS.predictionCacheStats.misses = 0
  NS.predictionCacheStats.evictions = 0
  NS.predictionCacheStats.peak_size = 0
  NS.predictionCacheStats.lookupMs = 0
  NS.predictionCacheStats.insertMs = 0
  NS.predictionCacheStats.evictionMs = 0
end

local function getCachedPrediction(stats, specKey)
  if NS.baseDpsCacheDirty then
    clearPredictionCaches()
    NS.baseDpsCacheDirty = false
  end

  specKey = specKey or ""
  local lookupStart
  if MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.debug and debugprofilestop then
    lookupStart = debugprofilestop()
  end
  local primary, crit, haste, mastery, versatility = predictionTuple(stats)
  local hash = predictionTupleHash(primary, crit, haste, mastery, versatility)
  local cached = findPrediction(specKey, hash, primary, crit, haste, mastery, versatility)
  if cached then
    touchPrediction(cached)
    NS.predictionCacheStats.hits = NS.predictionCacheStats.hits + 1
    if lookupStart then
      NS.predictionCacheStats.lookupMs = NS.predictionCacheStats.lookupMs
        + (debugprofilestop() - lookupStart)
    end
    return cached.dps
  end
  if lookupStart then
    NS.predictionCacheStats.lookupMs = NS.predictionCacheStats.lookupMs
      + (debugprofilestop() - lookupStart)
  end

  NS.predictionCacheStats.misses = NS.predictionCacheStats.misses + 1
  local dps = predictWithStats(stats, specKey)
  local insertStart
  if MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.debug and debugprofilestop then
    insertStart = debugprofilestop()
  end
  local specBuckets = predictionBucketsBySpec[specKey]
  if not specBuckets then
    specBuckets = {}
    predictionBucketsBySpec[specKey] = specBuckets
  end
  local entry = {
    specKey = specKey,
    hash = hash,
    primary = primary,
    crit = crit,
    haste = haste,
    mastery = mastery,
    versatility = versatility,
    dps = dps,
    bucketNext = specBuckets[hash],
  }
  specBuckets[hash] = entry
  appendPrediction(entry)
  predictionCacheSize = predictionCacheSize + 1
  if insertStart then
    NS.predictionCacheStats.insertMs = NS.predictionCacheStats.insertMs
      + (debugprofilestop() - insertStart)
  end
  evictOldestPrediction()
  if predictionCacheSize > NS.predictionCacheStats.peak_size then
    NS.predictionCacheStats.peak_size = predictionCacheSize
  end
  return dps
end

local function getPredictionCacheSnapshot()
  return {
    hits = NS.predictionCacheStats.hits or 0,
    misses = NS.predictionCacheStats.misses or 0,
    evictions = NS.predictionCacheStats.evictions or 0,
    peak_size = NS.predictionCacheStats.peak_size or 0,
    current_size = predictionCacheSize,
    max_size = MAX_PREDICTION_CACHE_SIZE,
    lookup_ms = NS.predictionCacheStats.lookupMs or 0,
    insert_ms = NS.predictionCacheStats.insertMs or 0,
    eviction_ms = NS.predictionCacheStats.evictionMs or 0,
    forward_count = NS.forwardProfile.count or 0,
    forward_ms = NS.forwardProfile.totalMs or 0,
  }
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
NS.isItemDataReadyForStats = isItemDataReadyForStats
NS.candidateRefFromCand = candidateRefFromCand
NS.resetStatDeltaStats = resetStatDeltaStats
NS.addStats = addStats
NS.addStatsInto = addStatsInto
NS.resolveOwnedItemRef = resolveOwnedItemRef
NS.getGuidFromEquipmentSlot = getGuidFromEquipmentSlot
NS.getGuidFromBagSlot = getGuidFromBagSlot
NS.predictWithStats = predictWithStats
NS.predictWithStatsFused = forwardModelStatsFused
NS.FUSED_PREDICTION_ERROR_TOLERANCE = 1e-5
NS.getCachedPrediction = getCachedPrediction
NS.getCachedBaseDps = getCachedBaseDps
NS.getPredictionCacheSnapshot = getPredictionCacheSnapshot
NS.getStatCacheSnapshot = getStatCacheSnapshot
NS.clearStatCaches = clearStatCaches

