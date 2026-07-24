local ADDON_NAME, NS = ...

local DEFAULT_BAG_SCAN_YIELD_EVERY = 40
local COMBO_COUNT_YIELD_EVERY = 15000
local MAX_LOADOUT_ITEM_DATA_RETRIES = 20
local LOADOUT_ITEM_DATA_RETRY_DELAY = 0.05
local LOADOUT_SCAN_SLICE_BUDGET_MS = 20
local bagComboEstimateRunner = nil
local bagComboEstimateToken = 0
local cancelBagComboEstimate
local BAG_SCAN_SLOT_ORDER = { 16, 17, 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12 }
local BAG_NONWEAPON_SLOT_ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12 }

local SLOT_ID_LABELS = NS.SLOT_ID_LABELS

local SLOT_ID_ORDER = {
  [1] = 1,
  [2] = 2,
  [3] = 3,
  [15] = 4,
  [5] = 5,
  [9] = 6,
  [10] = 7,
  [6] = 8,
  [7] = 9,
  [8] = 10,
  [11] = 11,
  [12] = 12,
  [13] = 13,
  [14] = 14,
  [16] = 15,
  [17] = 16,
}

local function makeZeroStats()
  return NS.makeZeroStats()
end

local function getItemStatVector(itemLink)
  local out = makeZeroStats()
  if not itemLink or not (C_Item and C_Item.GetItemStats) then
    return out
  end
  local ok, stats = pcall(C_Item.GetItemStats, itemLink)
  if not ok or type(stats) ~= "table" then
    return out
  end
  NS.applyItemStatMods(out, stats, 1)
  return out
end

local TIER_SET_SLOT_IDS = { [1] = true, [3] = true, [5] = true, [7] = true, [10] = true }
local MIN_TIER_SET_PIECES = 4
local REQUIRED_EMBELLISHMENTS = 2

local function parseItemLinkExtraEnchantID(link)
  if not link then
    return 0
  end
  local itemString = link:match("item[%-]?([^|]+)")
  if not itemString then
    return 0
  end
  local item = { strsplit(":", itemString) }
  if #item < 13 then
    return 0
  end

  local idx = 13
  local numBonusIDs = tonumber(item[idx])
  if numBonusIDs and numBonusIDs > 0 then
    idx = idx + numBonusIDs + 1
  else
    idx = idx + 1
  end

  local numModifiers = tonumber(item[idx])
  if numModifiers and numModifiers > 0 then
    idx = idx + numModifiers * 2 + 1
  else
    idx = idx + 1
  end

  for _ = 1, 3 do
    local relicNum = tonumber(item[idx])
    if relicNum and relicNum > 0 then
      idx = idx + relicNum + 1
    else
      idx = idx + 1
    end
  end

  if item[idx] and item[idx] ~= "" then
    idx = idx + 1
  end

  return tonumber(item[idx]) or 0
end

local function itemHasEmbellishment(link)
  if parseItemLinkExtraEnchantID(link) > 0 then
    return true
  end
  if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
    if ok and data and data.lines then
      for _, line in ipairs(data.lines) do
        local text = line.leftText or line.rightText or ""
        if text ~= "" and text:upper():find("EMBELLISH", 1, true) then
          return true
        end
      end
    end
  end
  return false
end

local function getPlayerSpecializationID()
  if not GetSpecialization then
    return nil
  end
  local specIndex = GetSpecialization()
  if not specIndex then
    return nil
  end
  if GetSpecializationInfo then
    return GetSpecializationInfo(specIndex)
  end
  return nil
end

local function primeItemForSetLookup(linkOrItemID)
  local itemID = type(linkOrItemID) == "number" and linkOrItemID
    or tonumber(linkOrItemID and linkOrItemID:match("item:(%d+)"))
  if not itemID then
    return itemID
  end
  if C_Item then
    if C_Item.RequestLoadItemDataByID then
      C_Item.RequestLoadItemDataByID(itemID)
    end
    if type(linkOrItemID) == "string" and C_Item.GetItemInfo then
      C_Item.GetItemInfo(linkOrItemID)
    elseif C_Item.GetItemInfo then
      C_Item.GetItemInfo(itemID)
    end
  elseif GetItemInfo then
    GetItemInfo(itemID)
  end
  return itemID
end

local function readItemInfoFields(linkOrItemID)
  primeItemForSetLookup(linkOrItemID)
  local info
  if C_Item and C_Item.GetItemInfo then
    info = { C_Item.GetItemInfo(linkOrItemID) }
  elseif GetItemInfo then
    info = { GetItemInfo(linkOrItemID) }
  end
  if not info or not info[1] then
    return nil
  end
  return info
end

local function readItemSetID(linkOrItemID)
  local info = readItemInfoFields(linkOrItemID)
  local setID = info and tonumber(info[16]) or 0
  if setID and setID > 0 then
    return setID
  end
  return 0
end

local function getItemSetBonusSpellKey(itemID, specID)
  if not itemID or not specID then
    return nil
  end
  if not (C_Item and C_Item.GetSetBonusesForSpecializationByItemID) then
    return nil
  end
  local ok, spells = pcall(C_Item.GetSetBonusesForSpecializationByItemID, specID, itemID)
  if not ok or type(spells) ~= "table" or #spells == 0 then
    return nil
  end
  local copy = {}
  for i = 1, #spells do
    copy[i] = spells[i]
  end
  table.sort(copy)
  return table.concat(copy, ":")
end

local function normalizeSetName(name)
  if not name or name == "" then
    return nil
  end
  return name:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function readSetNameFromItemSetAPI(setID)
  if not setID or setID <= 0 then
    return nil
  end
  if C_Item and C_Item.GetItemSetInfo then
    local ok, setName = pcall(C_Item.GetItemSetInfo, setID)
    if ok and setName and setName ~= "" then
      return setName
    end
  end
  if GetItemSetInfo then
    local setName = GetItemSetInfo(setID)
    if setName and setName ~= "" then
      return setName
    end
  end
  return nil
end

local function extractSetNameFromTooltipLine(text)
  if not text or text == "" then
    return nil
  end
  local trimmed = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local fromSetPrefix = trimmed:match("^Set:%s*(.+)%s*%(%d+/%d+%)%s*$")
  if fromSetPrefix and fromSetPrefix ~= "" then
    return fromSetPrefix:gsub("^%s+", ""):gsub("%s+$", "")
  end
  local fromCountSuffix = trimmed:match("^(.+)%s*%(%d+/%d+%)%s*$")
  if fromCountSuffix then
    local normalized = fromCountSuffix:gsub("^%s+", ""):gsub("%s+$", "")
    if normalized:find(":", 1, true) then
      local afterClass = normalized:match(":%s*(.+)$")
      if afterClass and afterClass ~= "" then
        return afterClass
      end
    end
    if normalized:find("Set", 1, true) or normalized:find(":", 1, true) then
      return normalized
    end
  end
  local fromClassPrefix = trimmed:match("^[%a%s]+:%s*(.+)$")
  if fromClassPrefix and fromClassPrefix ~= "" then
    local normalized = fromClassPrefix:gsub("^%s+", ""):gsub("%s+$", "")
    if normalized:find("Armor", 1, true) or normalized:find("Vestments", 1, true)
      or normalized:find("Regalia", 1, true) or normalized:find("Battlegear", 1, true)
      or normalized:find("Raiment", 1, true) or normalized:find("Garments", 1, true)
      or normalized:find("Trappings", 1, true) or normalized:find("Harness", 1, true)
      or normalized:find("Vestments", 1, true) then
      return normalized
    end
  end
  return nil
end

local function readSetNameFromTooltip(link)
  if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then
    return nil
  end
  local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
  if not ok or not data or not data.lines then
    return nil
  end
  for _, line in ipairs(data.lines) do
    local setName = extractSetNameFromTooltipLine(line.leftText)
    if setName then
      return setName
    end
    setName = extractSetNameFromTooltipLine(line.rightText)
    if setName then
      return setName
    end
  end
  return nil
end

local function getTierSetMatchKey(setID, setName, setBonusKey)
  if setBonusKey and setBonusKey ~= "" then
    return "bonuses:" .. setBonusKey
  end
  if setID and setID > 0 then
    local apiName = readSetNameFromItemSetAPI(setID)
    if apiName then
      return normalizeSetName(apiName)
    end
    return "id:" .. tostring(setID)
  end
  return normalizeSetName(setName)
end

local function getItemTierSetProfile(linkOrItemID)
  if not linkOrItemID then
    return {
      set_id = 0,
      set_name = nil,
      set_bonus_key = nil,
      is_tier_piece = false,
      match_key = nil,
    }
  end

  local itemID = type(linkOrItemID) == "number" and linkOrItemID
    or tonumber(linkOrItemID:match("item:(%d+)"))
  if not itemID then
    return {
      set_id = 0,
      set_name = nil,
      set_bonus_key = nil,
      is_tier_piece = false,
      match_key = nil,
    }
  end

  local specID = getPlayerSpecializationID()
  local setBonusKey = getItemSetBonusSpellKey(itemID, specID)
  local setID = readItemSetID(linkOrItemID)
  local setName = (setID and setID > 0) and readSetNameFromItemSetAPI(setID) or nil
  if not setName and type(linkOrItemID) == "string" then
    setName = readSetNameFromTooltip(linkOrItemID)
  end

  local matchKey = getTierSetMatchKey(setID, setName, setBonusKey)
  local isTierPiece = (setBonusKey ~= nil) or (setID and setID > 0) or (setName ~= nil)

  return {
    set_id = (setID and setID > 0) and setID or 0,
    set_name = setName,
    set_bonus_key = setBonusKey,
    is_tier_piece = isTierPiece,
    match_key = matchKey,
  }
end

local function getTierProfileForCandidate(cand)
  if not cand then
    return getItemTierSetProfile(nil)
  end
  local profile = getItemTierSetProfile(cand.link)
  if not profile.is_tier_piece and cand.preview_link and cand.preview_link ~= cand.link then
    profile = getItemTierSetProfile(cand.preview_link)
  end
  if not profile.is_tier_piece and cand.item_id then
    profile = getItemTierSetProfile(cand.item_id)
  end
  return profile
end

local function tierKeyMatchesTarget(cand, targetTier, targetKeys)
  if not cand or not cand.is_tier_piece then
    return false
  end
  if targetKeys and cand.tier_match_key and targetKeys[cand.tier_match_key] then
    return true
  end
  if targetTier and targetTier.set_bonus_key and cand.tier_set_bonus_key
    and cand.tier_set_bonus_key == targetTier.set_bonus_key then
    return true
  end
  if not targetTier then
    return false
  end
  if targetTier.match_key and cand.tier_match_key and cand.tier_match_key == targetTier.match_key then
    return true
  end
  if targetTier.set_id and targetTier.set_id > 0 and cand.tier_set_id == targetTier.set_id then
    return true
  end
  local targetName = normalizeSetName(targetTier.set_name)
  local candName = normalizeSetName(cand.tier_set_name)
  if targetName and candName and targetName == candName then
    return true
  end
  return false
end

local function tierProfilesMatch(cand, targetTier, targetKeys)
  return tierKeyMatchesTarget(cand, targetTier, targetKeys)
end

local function countMatchingTierInAssign(assign, targetTier, targetKeys, equippedBySlot)
  local count = 0
  for slotId in pairs(TIER_SET_SLOT_IDS) do
    local pick = assign[slotId]
    if not pick and equippedBySlot then
      pick = equippedBySlot[slotId]
    end
    if tierKeyMatchesTarget(pick, targetTier, targetKeys) then
      count = count + 1
    end
  end
  return count
end

local function collectEquippedTierMatchKeys(equippedBySlot)
  local keys = {}
  for slotId in pairs(TIER_SET_SLOT_IDS) do
    local eq = equippedBySlot[slotId]
    if eq and eq.is_tier_piece then
      if eq.tier_match_key then
        keys[eq.tier_match_key] = true
      end
      if eq.tier_set_bonus_key then
        keys["bonuses:" .. eq.tier_set_bonus_key] = true
      end
    end
  end
  return keys
end

local function makeLoadoutConstraintHelpers(pruneRules, nonWeaponSlotOrder)
  local slotHasTier = pruneRules and pruneRules.slot_has_tier
  local slotHasEmbellished = pruneRules and pruneRules.slot_has_embellished
  local minTier = pruneRules and pruneRules.min_tier_set_pieces
  local minEmb = pruneRules and pruneRules.min_embellishments
  local targetTier = pruneRules and pruneRules.target_tier
  local targetTierKeys = pruneRules and pruneRules.target_tier_keys
  local tierSlotIds = pruneRules and pruneRules.tier_set_slot_ids

  local function remainingTierSlotsAfter(idx)
    local remaining = 0
    for i = idx + 1, #nonWeaponSlotOrder do
      local slotId = nonWeaponSlotOrder[i]
      if slotHasTier and slotHasTier[slotId] then
        remaining = remaining + 1
      end
    end
    return remaining
  end

  local function allowNonTierPick(idx, slotId, tierCount)
    if not minTier then
      return true
    end
    if not tierSlotIds or not tierSlotIds[slotId] then
      return true
    end
    if not slotHasTier or not slotHasTier[slotId] then
      return true
    end
    return tierCount + remainingTierSlotsAfter(idx) >= minTier
  end

  local function candTierAdds(cand, slotId)
    if not minTier or not tierSlotIds or not tierSlotIds[slotId] then
      return 0
    end
    if tierKeyMatchesTarget(cand, targetTier, targetTierKeys) then
      return 1
    end
    return 0
  end

  local function candEmbAdds(cand)
    if cand and cand.is_embellished then
      return 1
    end
    return 0
  end

  local function countTierInAssign(assign)
    return countMatchingTierInAssign(assign, targetTier, targetTierKeys)
  end

  local function maxPossibleTierCount(idx, tierCount, slotId)
    if not minTier then
      return tierCount
    end
    local remaining = remainingTierSlotsAfter(idx)
    if slotId and tierSlotIds and tierSlotIds[slotId] and slotHasTier and slotHasTier[slotId] then
      return tierCount + remaining + 1
    end
    return tierCount + remaining
  end

  local function canStillSatisfy(idx, tierCount, embCount, slotId)
    if idx > #nonWeaponSlotOrder then
      return true
    end
    if minTier then
      if maxPossibleTierCount(idx, tierCount, slotId) < minTier then
        return false
      end
    end
    if minEmb then
      local maxEmb = embCount
      for i = idx, #nonWeaponSlotOrder do
        local embSlotId = nonWeaponSlotOrder[i]
        if slotHasEmbellished and slotHasEmbellished[embSlotId] then
          maxEmb = maxEmb + 1
        end
      end
      if maxEmb < minEmb then
        return false
      end
    end
    return true
  end

  local function satisfiesAssign(assign, embCount)
    if minTier and countTierInAssign(assign) < minTier then
      return false
    end
    if minEmb and embCount < minEmb then
      return false
    end
    return true
  end

  return {
    candTierAdds = candTierAdds,
    candEmbAdds = candEmbAdds,
    canStillSatisfy = canStillSatisfy,
    satisfiesAssign = satisfiesAssign,
    allowNonTierPick = allowNonTierPick,
    countTierInAssign = countTierInAssign,
    maxPossibleTierCount = maxPossibleTierCount,
    tierKeyMatchesTarget = function(cand)
      return tierKeyMatchesTarget(cand, targetTier, targetTierKeys)
    end,
  }
end

local function annotateCandidateLoadoutFlags(cand)
  if not cand then
    return cand
  end
  if not cand.link and not cand.preview_link and not cand.item_id then
    cand.tier_set_id = 0
    cand.tier_set_name = nil
    cand.tier_set_bonus_key = nil
    cand.tier_match_key = nil
    cand.is_tier_piece = false
    cand.is_embellished = false
    return cand
  end
  local tierProfile = getTierProfileForCandidate(cand)
  cand.tier_set_id = tierProfile.set_id
  cand.tier_set_name = tierProfile.set_name
  cand.tier_set_bonus_key = tierProfile.set_bonus_key
  cand.is_tier_piece = tierProfile.is_tier_piece
  cand.tier_match_key = tierProfile.match_key
  local embLink = cand.link or cand.preview_link
  cand.is_embellished = itemHasEmbellishment(embLink)
  return cand
end

local function refreshAllCandidateLoadoutFlags(slotCandidates, equippedBySlot)
  for slotId in pairs(TIER_SET_SLOT_IDS) do
    local eq = equippedBySlot and equippedBySlot[slotId]
    if eq and (eq.link or eq.item_id) then
      primeItemForSetLookup(eq.link or eq.item_id)
    end
    for _, cand in ipairs((slotCandidates and slotCandidates[slotId]) or {}) do
      if cand.link then
        primeItemForSetLookup(cand.link)
      end
      if cand.item_id then
        primeItemForSetLookup(cand.item_id)
      end
    end
  end
  for _, list in pairs(slotCandidates) do
    for i, cand in ipairs(list) do
      list[i] = annotateCandidateLoadoutFlags(cand)
    end
  end
  if equippedBySlot then
    for slotId, eq in pairs(equippedBySlot) do
      equippedBySlot[slotId] = annotateCandidateLoadoutFlags(eq)
    end
  end
end

local function getDominantEquippedTierProfile(equippedBySlot)
  local counts = {}
  for slotId in pairs(TIER_SET_SLOT_IDS) do
    local eq = equippedBySlot[slotId]
    if eq and eq.is_tier_piece then
      local key = eq.tier_match_key or ("bonus:" .. tostring(eq.tier_set_bonus_key or ""))
      if not counts[key] then
        counts[key] = {
          count = 0,
          set_id = eq.tier_set_id or 0,
          set_name = eq.tier_set_name,
          set_bonus_key = eq.tier_set_bonus_key,
          match_key = eq.tier_match_key,
        }
      end
      counts[key].count = counts[key].count + 1
    end
  end
  local best = nil
  for _, entry in pairs(counts) do
    if not best or entry.count > best.count then
      best = entry
    end
  end
  if not best then
    return nil, 0, {}
  end
  return {
    set_id = best.set_id,
    set_name = best.set_name,
    set_bonus_key = best.set_bonus_key,
    match_key = best.match_key,
  }, best.count, collectEquippedTierMatchKeys(equippedBySlot)
end

local function countTierKeysInPool(slotCandidates)
  local keySlotCounts = {}
  local keyProfiles = {}
  for slotId in pairs(TIER_SET_SLOT_IDS) do
    local keysInSlot = {}
    for _, cand in ipairs(slotCandidates[slotId] or {}) do
      if cand.is_tier_piece and cand.tier_match_key then
        keysInSlot[cand.tier_match_key] = cand
      end
    end
    for key, cand in pairs(keysInSlot) do
      keySlotCounts[key] = (keySlotCounts[key] or 0) + 1
      if not keyProfiles[key] then
        keyProfiles[key] = {
          set_id = cand.tier_set_id or 0,
          set_name = cand.tier_set_name,
          set_bonus_key = cand.tier_set_bonus_key,
          match_key = cand.tier_match_key,
        }
      end
    end
  end
  return keySlotCounts, keyProfiles
end

local function collectPoolTierKeysForTarget(slotCandidates, targetTier, seedKeys)
  local keys = {}
  if seedKeys then
    for key in pairs(seedKeys) do
      keys[key] = true
    end
  end
  if targetTier and targetTier.match_key then
    keys[targetTier.match_key] = true
  end
  for slotId in pairs(TIER_SET_SLOT_IDS) do
    for _, cand in ipairs(slotCandidates[slotId] or {}) do
      if cand.is_tier_piece and tierKeyMatchesTarget(cand, targetTier, keys) and cand.tier_match_key then
        keys[cand.tier_match_key] = true
      end
    end
  end
  return keys
end

local function countMatchingTierSlots(slotCandidates, targetTier, targetKeys)
  local count = 0
  for slotId in pairs(TIER_SET_SLOT_IDS) do
    for _, cand in ipairs(slotCandidates[slotId] or {}) do
      if tierKeyMatchesTarget(cand, targetTier, targetKeys) then
        count = count + 1
        break
      end
    end
  end
  return count
end

local function chooseTargetTierProfile(equippedBySlot, slotCandidates)
  local poolCounts, poolProfiles = countTierKeysInPool(slotCandidates)
  local eqProfile, eqCount, eqKeys = getDominantEquippedTierProfile(equippedBySlot)

  if eqProfile then
    local poolForEquipped = countMatchingTierSlots(slotCandidates, eqProfile, eqKeys)
    if poolForEquipped >= MIN_TIER_SET_PIECES then
      return eqProfile, poolForEquipped, eqKeys
    end
  end

  local bestKey, bestCount = nil, 0
  for key, count in pairs(poolCounts) do
    if count > bestCount then
      bestKey = key
      bestCount = count
    end
  end
  if bestKey and bestCount >= MIN_TIER_SET_PIECES then
    return poolProfiles[bestKey], bestCount, { [bestKey] = true }
  end

  if eqProfile and eqCount > 0 then
    return eqProfile, eqCount, eqKeys
  end
  return nil, 0, {}
end

local function buildLoadoutPruneRules(equippedBySlot, slotCandidates, nonWeaponSlotOrder)
  local rules = {
    active = false,
    tier_set_slot_ids = TIER_SET_SLOT_IDS,
  }

  local targetTier, _, targetTierKeys = chooseTargetTierProfile(equippedBySlot, slotCandidates)

  if targetTier then
    targetTierKeys = collectPoolTierKeysForTarget(slotCandidates, targetTier, targetTierKeys)
    local maxTier = 0
    local slotHasTier = {}
    for slotId in pairs(TIER_SET_SLOT_IDS) do
      for _, cand in ipairs(slotCandidates[slotId] or {}) do
        if tierKeyMatchesTarget(cand, targetTier, targetTierKeys) then
          maxTier = maxTier + 1
          slotHasTier[slotId] = true
          break
        end
      end
    end
    if maxTier >= MIN_TIER_SET_PIECES then
      rules.active = true
      rules.target_tier = targetTier
      rules.target_tier_keys = targetTierKeys
      rules.min_tier_set_pieces = MIN_TIER_SET_PIECES
      rules.slot_has_tier = slotHasTier
    end
  end

  local maxEmb = 0
  local slotHasEmbellished = {}
  local scanSlots = { 16, 17 }
  for _, slotId in ipairs(nonWeaponSlotOrder) do
    scanSlots[#scanSlots + 1] = slotId
  end
  for _, slotId in ipairs(scanSlots) do
    for _, cand in ipairs(slotCandidates[slotId] or {}) do
      if cand.is_embellished then
        maxEmb = maxEmb + 1
        slotHasEmbellished[slotId] = true
        break
      end
    end
  end
  if maxEmb >= REQUIRED_EMBELLISHMENTS then
    rules.active = true
    rules.min_embellishments = REQUIRED_EMBELLISHMENTS
    rules.slot_has_embellished = slotHasEmbellished
  end

  return rules
end

function NS.describeLoadoutPruneRules(rules)
  if not rules or not rules.active then
    return nil
  end
  local parts = {}
  if rules.min_tier_set_pieces then
    table.insert(parts, string.format("%d-piece tier set", rules.min_tier_set_pieces))
  end
  if rules.min_embellishments then
    table.insert(parts, string.format("%d embellishments", rules.min_embellishments))
  end
  if #parts == 0 then
    return nil
  end
  return table.concat(parts, ", ")
end

local function countSelectedEmbellishments(slotCandidates, nonWeaponSlotOrder)
  local count = 0
  local scanSlots = { 16, 17 }
  for _, slotId in ipairs(nonWeaponSlotOrder) do
    scanSlots[#scanSlots + 1] = slotId
  end
  for _, slotId in ipairs(scanSlots) do
    for _, cand in ipairs(slotCandidates[slotId] or {}) do
      if cand.is_embellished then
        count = count + 1
        break
      end
    end
  end
  return count
end

function NS.getLoadoutPruneConstraintWarning(specKey, candidatesBySlot)
  if not specKey or not candidatesBySlot then
    return nil
  end

  local buildOpts = {
    respect_selection = true,
    include_bags = candidatesBySlot == nil,
  }
  local slotCandidates, equippedBySlot = NS.buildSlotCandidates(specKey, candidatesBySlot, buildOpts)
  if NS.slotCandidatesNeedLoadoutFlags(slotCandidates) then
    refreshAllCandidateLoadoutFlags(slotCandidates, equippedBySlot)
  end

  local targetTier, _, targetTierKeys = chooseTargetTierProfile(equippedBySlot, slotCandidates)
  if targetTier then
    targetTierKeys = collectPoolTierKeysForTarget(slotCandidates, targetTier, targetTierKeys)
  end
  local tierSlots = targetTier and countMatchingTierSlots(slotCandidates, targetTier, targetTierKeys) or 0
  local embCount = countSelectedEmbellishments(slotCandidates, BAG_NONWEAPON_SLOT_ORDER)

  local issues = {}
  if tierSlots < MIN_TIER_SET_PIECES then
    issues[#issues + 1] = string.format(
      "%d-piece tier set (only %d tier slot%s available)",
      MIN_TIER_SET_PIECES,
      tierSlots,
      tierSlots == 1 and "" or "s"
    )
  end
  if embCount < REQUIRED_EMBELLISHMENTS then
    issues[#issues + 1] = string.format(
      "%d embellishments (only %d available)",
      REQUIRED_EMBELLISHMENTS,
      embCount
    )
  end

  if #issues == 0 then
    return nil
  end
  return "Cannot build a loadout with " .. table.concat(issues, " or ")
end

local STAT_KEYS = { "primary_stat", "crit", "haste", "mastery", "versatility" }

local function candidateStatTotal(cand)
  local stats = cand and cand.stats
  if not stats then
    return 0
  end
  local total = 0
  for _, key in ipairs(STAT_KEYS) do
    total = total + (stats[key] or 0)
  end
  return total
end

local function candidateQuickScore(cand)
  if not cand then
    return -math.huge
  end
  if cand.key and cand.key:sub(1, 6) == "empty:" then
    return -math.huge + 1
  end
  if not cand.link then
    return -math.huge
  end
  return candidateStatTotal(cand)
end

local function candidateDominates(dom, sub)
  if not dom or not sub or dom.key == sub.key then
    return false
  end
  if not dom.link or not sub.link then
    return false
  end
  if dom.key:sub(1, 6) == "empty:" then
    return false
  end
  local domStats, subStats = dom.stats, sub.stats
  if not domStats or not subStats then
    return false
  end
  local strictlyBetter = false
  for _, key in ipairs(STAT_KEYS) do
    if (domStats[key] or 0) < (subStats[key] or 0) then
      return false
    end
    if (domStats[key] or 0) > (subStats[key] or 0) then
      strictlyBetter = true
    end
  end
  return strictlyBetter
end

local function pruneDominatedSlotCandidates(slotCandidates)
  for slotId, list in pairs(slotCandidates) do
    if type(slotId) == "number" and list and #list > 1 then
      local filtered = {}
      for i, cand in ipairs(list) do
        local dominated = false
        if cand and cand.link then
          for j, other in ipairs(list) do
            if i ~= j and candidateDominates(other, cand) then
              dominated = true
              break
            end
          end
        end
        if not dominated then
          filtered[#filtered + 1] = cand
        end
      end
      slotCandidates[slotId] = filtered
    end
  end
end

local function statsDiff(a, b)
  return {
    primary_stat = (a.primary_stat or 0) - (b.primary_stat or 0),
    crit = (a.crit or 0) - (b.crit or 0),
    haste = (a.haste or 0) - (b.haste or 0),
    mastery = (a.mastery or 0) - (b.mastery or 0),
    versatility = (a.versatility or 0) - (b.versatility or 0),
  }
end

local function buildCandidateKey(ref)
  if not ref then return nil end
  if ref.key then return ref.key end
  if ref.guid then return "guid:" .. tostring(ref.guid) end
  if ref.bag and ref.slot then return "bag:" .. tostring(ref.bag) .. ":" .. tostring(ref.slot) end
  if ref.slotId then return "eq:" .. tostring(ref.slotId) end
  if ref.link then return "link:" .. tostring(ref.link) end
  return nil
end

local function getItemScanSignals(itemLink)
  local ilvl = 0
  local getDetailedItemLevelInfo = rawget(_G, "GetDetailedItemLevelInfo")
  if getDetailedItemLevelInfo then
    local okIlvl, v = pcall(getDetailedItemLevelInfo, itemLink)
    if okIlvl and type(v) == "number" then
      ilvl = v
    end
  end

  if ilvl <= 0 then
    local _, _, _, fallbackIlvl = GetItemInfo(itemLink)
    if type(fallbackIlvl) == "number" then
      ilvl = fallbackIlvl
    end
  end

  local weaponDps = 0
  if C_Item and C_Item.GetItemStats then
    local okStats, stats = pcall(C_Item.GetItemStats, itemLink)
    if okStats and type(stats) == "table" then
      weaponDps = (stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT or 0) + (stats.ITEM_MOD_DAMAGE_PER_SECOND or 0)
    end
  end

  return ilvl or 0, weaponDps or 0
end

local function makeCandidateFromRef(ref)
  local link = NS.itemRefToLink(ref)
  if not link or link == "" then
    return nil
  end
  if NS.isTrinketLink and NS.isTrinketLink(link) then
    return nil
  end
  local specKey = NS.getActiveProfileKey()
  if specKey and NS.isGearLinkUsableForPlayer and not NS.isGearLinkUsableForPlayer(link, specKey) then
    return nil
  end
  local guid = ref and (ref.guid or ref.itemGUID) or nil
  local name, _, quality = GetItemInfo(link)
  local _, _, equipLoc = NS.getItemTypeInfo(link)
  local ilvl, weaponDps = getItemScanSignals(link)
  return annotateCandidateLoadoutFlags({
    key = buildCandidateKey(ref),
    link = link,
    guid = guid,
    item_id = tonumber(link:match("item:(%d+)")),
    name = name or (link or "Unknown Item"),
    quality = quality or -1,
    equipLoc = equipLoc,
    stats = getItemStatVector(link),
    ilvl = ilvl,
    weapon_dps = weaponDps,
    bag = ref and ref.bag,
    slot = ref and ref.slot,
    slotId = ref and ref.slotId,
  })
end

function NS.makeCandidateFromGearRef(ref)
  if not ref then
    return nil
  end

  local scoreLink = ref.resolved_link or ref.preview_link or ref.link
  if ref.source == "loot" and ref.resolved_link then
    scoreLink = ref.resolved_link
  end
  if not scoreLink or scoreLink == "" then
    return nil
  end
  if NS.isTrinketLink and NS.isTrinketLink(scoreLink) then
    return nil
  end
  local specKey = NS.getActiveProfileKey()
  if specKey and NS.isGearLinkUsableForPlayer and not NS.isGearLinkUsableForPlayer(scoreLink, specKey) then
    return nil
  end

  local itemID = ref.item_id or tonumber(scoreLink:match("item:(%d+)"))
  local displayLink = ref.preview_link or scoreLink
  if ref.source == "loot" and ref.link and ref.link ~= displayLink then
    displayLink = ref.preview_link or scoreLink
  end
  local cand = makeCandidateFromRef({
    link = scoreLink,
    guid = ref.guid,
    bag = ref.bag,
    slot = ref.slot,
    slotId = ref.slot_id,
  })
  if not cand then
    return nil
  end

  if ref.source == "vault" and itemID then
    local actId = ref.vault_activity_id or 0
    cand.key = string.format("vault:%s:%d", tostring(actId), itemID)
    cand.vault_activity_id = ref.vault_activity_id
    cand.is_vault = true
  elseif ref.source == "crest" and itemID then
    local rank = ref.upgrade_rank or ref.upgrade_track or "0"
    rank = tostring(rank):gsub("[^%d/]", ""):match("(%d+)") or "0"
    cand.key = string.format("crest:%d:%s", itemID, rank)
  elseif ref.source == "loot" and itemID then
    local journalId = ref.instance_id or 0
    cand.key = string.format("loot:%d:%d", journalId, itemID)
  elseif ref.source == "bag" then
    if cand.guid then
      cand.key = "guid:" .. tostring(cand.guid)
    elseif ref.bag and ref.slot then
      cand.key = string.format("bag:%d:%d", ref.bag, ref.slot)
    end
  end

  cand.source = ref.source
  cand.source_label = ref.source_label
  cand.claimable = ref.claimable
  cand.preview = ref.preview
  cand.crest_cost = ref.crest_cost
  cand.crest_label = ref.crest_label
  cand.dps_per_crest = ref.dps_per_crest
  cand.ilvl_gain = ref.ilvl_gain
  cand.preview_ilvl = ref.preview_ilvl
  local displayIlvl = ref.preview_ilvl
  if ref.source == "loot" and displayIlvl and displayIlvl > 0 then
    cand.ilvl = displayIlvl
    cand.preview_ilvl = displayIlvl
  elseif not displayIlvl or displayIlvl <= 0 then
    displayIlvl = NS.getItemIlvl and NS.getItemIlvl(displayLink) or 0
    if displayIlvl and displayIlvl > 0 then
      cand.ilvl = displayIlvl
      cand.preview_ilvl = displayIlvl
    end
  end
  cand.upgrade_track = ref.upgrade_track
    or (NS.getItemUpgradeTrackLabel and NS.getItemUpgradeTrackLabel(displayLink))
  cand.upgrade_rank = ref.upgrade_rank
  cand.journal_link = ref.journal_link or (ref.source == "loot" and ref.link ~= scoreLink and ref.link) or nil
  cand.instance_id = ref.instance_id
  cand.instance_name = ref.instance_name
  cand.dps_delta = ref.dps_delta
  cand.is_upgrade = ref.is_upgrade
  cand.slot_id = ref.slot_id or cand.slot_id
  cand.slot_label = ref.slot_label
  cand.item_id = itemID
  cand.preview_link = displayLink
  if ref.name then
    cand.name = ref.name
  end
  if ref.quality then
    cand.quality = ref.quality
  end
  return annotateCandidateLoadoutFlags(cand)
end

NS.BAG_SCAN_SLOT_ORDER = BAG_SCAN_SLOT_ORDER
NS.BAG_NONWEAPON_SLOT_ORDER = BAG_NONWEAPON_SLOT_ORDER

local slotCanUseCandidate
local makeEmptyCandidate

function NS.buildSlotCandidates(specKey, externalCandidatesBySlot, opts)
  opts = opts or {}
  local _, classToken = UnitClass("player")
  local loadout = NS.getWeaponLoadoutForSpec(specKey)
  local slotOrder = BAG_SCAN_SLOT_ORDER
  local slotCandidates = {}
  local slotSeen = {}
  local equippedBySlot = {}

  for _, slotId in ipairs(slotOrder) do
    slotCandidates[slotId] = {}
    slotSeen[slotId] = {}
    local eqRef = NS.getSlotItemRef(slotId)
    local eqCand = eqRef and makeCandidateFromRef(eqRef) or makeEmptyCandidate(slotId)
    if eqCand then
      eqCand.is_equipped_baseline = true
      eqCand.source = eqCand.source or "equipped"
      eqCand.source_label = eqCand.source_label or "Equipped"
      equippedBySlot[slotId] = eqCand
      if eqCand.key then
        local includeEquipped = opts.respect_selection == false or NS.isAdvisorCandidateSelected(eqCand)
        if includeEquipped then
          table.insert(slotCandidates[slotId], eqCand)
          slotSeen[slotId][eqCand.key] = true
        end
      end
    end
  end

  local function addCandidateToSlot(slotId, cand)
    if not cand or not cand.key then
      return
    end
    if slotSeen[slotId][cand.key] then
      return
    end
    if not slotCanUseCandidate(slotId, cand, classToken, specKey, loadout) then
      return
    end
    if opts.respect_selection ~= false then
      if NS.isAdvisorCandidateSelected and not NS.isAdvisorCandidateSelected(cand) then
        return
      end
    end
    table.insert(slotCandidates[slotId], cand)
    slotSeen[slotId][cand.key] = true
  end

  for slotId, list in pairs(externalCandidatesBySlot or {}) do
    slotId = tonumber(slotId)
    if slotId and slotCandidates[slotId] then
      for _, cand in ipairs(list) do
        addCandidateToSlot(slotId, cand)
      end
    end
  end

  if opts.include_bags ~= false and not externalCandidatesBySlot then
    for bag = 0, 4 do
      for slot = 1, C_Container.GetContainerNumSlots(bag) do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.hyperlink then
          local cand = makeCandidateFromRef({
            link = info.hyperlink,
            guid = info["itemGUID"] or info["guid"] or NS.getGuidFromBagSlot(bag, slot),
            bag = bag,
            slot = slot,
          })
          if cand and cand.equipLoc and cand.equipLoc ~= "" and cand.equipLoc ~= "INVTYPE_AMMO" then
            cand.source = "bag"
            cand.source_label = "In bags"
            if cand.guid then
              cand.key = "guid:" .. tostring(cand.guid)
            else
              cand.key = string.format("bag:%d:%d", bag, slot)
            end
            local candidateSlots = NS.INVTYPE_TO_SLOT_IDS[cand.equipLoc]
            if candidateSlots then
              for _, targetSlotId in ipairs(candidateSlots) do
                if slotCandidates[targetSlotId] then
                  addCandidateToSlot(targetSlotId, cand)
                end
              end
            end
          end
        end
      end
    end
  end

  if #slotCandidates[17] == 0 then
    local emptyOffhand = makeEmptyCandidate(17)
    table.insert(slotCandidates[17], emptyOffhand)
    slotSeen[17][emptyOffhand.key] = true
  end

  refreshAllCandidateLoadoutFlags(slotCandidates, equippedBySlot)

  return slotCandidates, equippedBySlot, slotOrder, classToken, loadout
end

local function findBagSlotForItem(link, guid)
  if not link or not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
    return nil, nil
  end
  for bag = 0, 4 do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.hyperlink then
        local infoGuid = info["itemGUID"] or info["guid"]
        if guid and infoGuid and infoGuid == guid then
          return bag, slot
        end
        if info.hyperlink == link then
          return bag, slot
        end
      end
    end
  end
  return nil, nil
end

makeEmptyCandidate = function(slotId)
  return annotateCandidateLoadoutFlags({
    key = "empty:" .. tostring(slotId),
    link = nil,
    guid = nil,
    name = "(Empty)",
    quality = -1,
    equipLoc = nil,
    stats = makeZeroStats(),
    ilvl = 0,
    weapon_dps = 0,
  })
end

slotCanUseCandidate = function(slotId, cand, classToken, specKey, loadout)
  if not cand then return false end
  if not cand.link then
    return slotId == 17 or slotId == 11 or slotId == 12 or slotId == 13 or slotId == 14
  end

  if specKey and NS.isGearLinkUsableForPlayer and not NS.isGearLinkUsableForPlayer(cand.link, specKey) then
    return false
  end

  local itemClassID, itemSubClassID, equipLoc = NS.getItemTypeInfo(cand.link)
  if not equipLoc then return false end

  if slotId == 16 then
    if not NS.isMainHandEquipLocAllowed or not NS.isMainHandEquipLocAllowed(equipLoc, specKey) then
      return false
    end
    if equipLoc == "INVTYPE_2HWEAPON" then
      return loadout.two_handed == true
        and NS.isItemAllowedForMainHand(classToken, itemClassID, itemSubClassID, equipLoc)
    end
    return NS.isItemAllowedForMainHand(classToken, itemClassID, itemSubClassID, equipLoc)
  end

  if slotId == 17 then
    if not loadout.dual_wield then
      return false
    end
    if equipLoc == "INVTYPE_2HWEAPON" then
      return NS.isTitansGripSpec
        and NS.isTitansGripSpec(specKey)
        and NS.isItemAllowedForMainHand(classToken, itemClassID, itemSubClassID, equipLoc)
    end
    return NS.isItemAllowedForOffHand(classToken, specKey, itemClassID, itemSubClassID, equipLoc)
  end

  if slotId == 11 or slotId == 12 then
    return equipLoc == "INVTYPE_FINGER"
  end

  if slotId == 13 or slotId == 14 then
    return equipLoc == "INVTYPE_TRINKET"
  end

  local slots = NS.INVTYPE_TO_SLOT_IDS[equipLoc]
  if not slots then return false end
  local fits = false
  for _, sid in ipairs(slots) do
    if sid == slotId then
      fits = true
      break
    end
  end
  if not fits then return false end

  return NS.isArmorCandidateAllowedForClass(classToken, itemClassID, itemSubClassID)
end

function NS.isValidWeaponCombo(mhCand, ohCand, classToken, specKey, loadout, requireOffhandFor1H)
  if not mhCand or not mhCand.link then
    return false
  end

  local mhIs2H = NS.is2HWeapon(mhCand.link)
  local ohIs2H = ohCand and ohCand.link and NS.is2HWeapon(ohCand.link)
  if mhIs2H then
    if not loadout.two_handed then
      return false
    end
    if ohIs2H then
      if not loadout.dual_wield then
        return false
      end
      if not (NS.isTitansGripSpec and NS.isTitansGripSpec(specKey)) then
        return false
      end
      local ohClassID, ohSubClassID, ohEquipLoc = NS.getItemTypeInfo(ohCand.link)
      return NS.isItemAllowedForMainHand(classToken, ohClassID, ohSubClassID, ohEquipLoc)
    end
    return (not ohCand) or (not ohCand.link)
  end

  local mhClassID, mhSubClassID, mhEquipLoc = NS.getItemTypeInfo(mhCand.link)
  if not NS.isMainHandEquipLocAllowed or not NS.isMainHandEquipLocAllowed(mhEquipLoc, specKey) then
    return false
  end
  if not NS.isItemAllowedForMainHand(classToken, mhClassID, mhSubClassID, mhEquipLoc) then
    return false
  end

  if ohCand and ohCand.link then
    if not loadout.dual_wield then
      return false
    end
    local ohClassID, ohSubClassID, ohEquipLoc = NS.getItemTypeInfo(ohCand.link)
    return NS.isItemAllowedForOffHand(classToken, specKey, ohClassID, ohSubClassID, ohEquipLoc)
  end

  if requireOffhandFor1H and loadout.dual_wield then
    return false
  end

  return true
end
local isValidWeaponCombo = NS.isValidWeaponCombo

local function countVaultItemsInAssign(assign)
  local n = 0
  if not assign then
    return n
  end
  for _, cand in pairs(assign) do
    if cand and cand.source == "vault" then
      n = n + 1
    end
  end
  return n
end

local function slotListsShareItemKeys(slotCandidates)
  local seen = {}
  for slotId, list in pairs(slotCandidates or {}) do
    for _, cand in ipairs(list or {}) do
      local key = cand and cand.key
      if key and key:sub(1, 6) ~= "empty:" then
        if seen[key] then
          local prevSlot = seen[key]
          local ringSlotsOnly = (prevSlot == 11 or prevSlot == 12) and (slotId == 11 or slotId == 12)
          if not ringSlotsOnly then
            return true
          end
        else
          seen[key] = slotId
        end
      end
    end
  end
  return false
end

local function slotListsHaveVaultItems(slotCandidates)
  for _, list in pairs(slotCandidates or {}) do
    for _, cand in ipairs(list or {}) do
      if cand and cand.source == "vault" then
        return true
      end
    end
  end
  return false
end

local function countRingPairCombinations(list11, list12)
  local total = 0
  for _, c1 in ipairs(list11 or {}) do
    for _, c2 in ipairs(list12 or {}) do
      local k1 = c1 and c1.key
      local k2 = c2 and c2.key
      local e1 = not k1 or k1:sub(1, 6) == "empty:"
      local e2 = not k2 or k2:sub(1, 6) == "empty:"
      if not e1 and not e2 and k1 == k2 then
        -- Same physical item cannot occupy both ring slots.
      elseif k1 and k2 and not e1 and not e2 and k1 > k2 then
        -- Mirror of DFS ordering: only count ring1 <= ring2.
      else
        total = total + 1
      end
    end
  end
  return total
end

local function countWeaponCombinations(slotCandidates, classToken, specKey, loadout, requireOffhandFor1H)
  local total = 0
  local mhList = slotCandidates[16] or {}
  local ohList = slotCandidates[17] or {}
  for _, mhCand in ipairs(mhList) do
    for _, ohCand in ipairs(ohList) do
      local mhKey = mhCand and mhCand.key or nil
      local ohKey = ohCand and ohCand.key or nil
      local ohIsEmpty = ohKey and ohKey:sub(1, 6) == "empty:"
      if ((not mhKey) or (not ohKey) or ohIsEmpty or mhKey ~= ohKey)
        and isValidWeaponCombo(mhCand, ohCand, classToken, specKey, loadout, requireOffhandFor1H) then
        local assign = { [16] = mhCand, [17] = ohCand }
        if countVaultItemsInAssign(assign) <= 1 then
          total = total + 1
        end
      end
    end
  end
  return total
end

local function countLoadoutCombinationsProduct(slotCandidates, classToken, specKey, loadout, nonWeaponSlotOrder)
  local strictRequireOffhandFor1H = false
  for _, cand in ipairs(slotCandidates[17] or {}) do
    if cand and cand.link then
      strictRequireOffhandFor1H = true
      break
    end
  end

  local function countSimple(requireOffhandFor1H)
    local weaponTotal = countWeaponCombinations(
      slotCandidates, classToken, specKey, loadout, requireOffhandFor1H
    )
    if weaponTotal <= 0 then
      return 0
    end

    local total = weaponTotal
    for _, slotId in ipairs(nonWeaponSlotOrder) do
      if slotId ~= 11 and slotId ~= 12 then
        total = total * math.max(1, #(slotCandidates[slotId] or {}))
        if total <= 0 then
          return 0
        end
      end
    end

    local ringTotal = countRingPairCombinations(slotCandidates[11], slotCandidates[12])
    if ringTotal <= 0 then
      return 0
    end
    return total * ringTotal
  end

  local total = countSimple(strictRequireOffhandFor1H)
  if total == 0 and strictRequireOffhandFor1H then
    total = countSimple(false)
  end
  return total
end

local function cloneSlotCandidatesWithoutVault(slotCandidates, forcedVaultSlot, forcedVaultCand)
  local copy = {}
  for slotId, list in pairs(slotCandidates or {}) do
    copy[slotId] = {}
    if forcedVaultSlot and slotId == forcedVaultSlot and forcedVaultCand then
      table.insert(copy[slotId], forcedVaultCand)
    else
      for _, cand in ipairs(list or {}) do
        if cand.source ~= "vault" then
          table.insert(copy[slotId], cand)
        end
      end
    end
  end
  return copy
end

local function countLoadoutCombinationsWithVaultProduct(slotCandidates, classToken, specKey, loadout, nonWeaponSlotOrder)
  local total = countLoadoutCombinationsProduct(
    cloneSlotCandidatesWithoutVault(slotCandidates), classToken, specKey, loadout, nonWeaponSlotOrder
  )
  for slotId, list in pairs(slotCandidates or {}) do
    for _, cand in ipairs(list or {}) do
      if cand.source == "vault" then
        total = total + countLoadoutCombinationsProduct(
          cloneSlotCandidatesWithoutVault(slotCandidates, slotId, cand),
          classToken, specKey, loadout, nonWeaponSlotOrder
        )
      end
    end
  end
  return total
end

local function encodeCountState(tier, emb, vault, ring1Key)
  return string.format("%d,%d,%d,%s", tier or 0, emb or 0, vault or 0, ring1Key or "")
end

local function decodeCountState(stateKey)
  local tier, emb, vault, ring1 = stateKey:match("^(%d+),(%d+),(%d+),(.*)$")
  return tonumber(tier) or 0, tonumber(emb) or 0, tonumber(vault) or 0, ring1 or ""
end

local function countLoadoutCombinationsDp(slotCandidates, classToken, specKey, loadout, nonWeaponSlotOrder, pruneRules)
  local constraints = makeLoadoutConstraintHelpers(pruneRules, nonWeaponSlotOrder)
  local minTier = (pruneRules and pruneRules.min_tier_set_pieces) or 0
  local minEmb = (pruneRules and pruneRules.min_embellishments) or 0

  local function runCount(requireOffhandFor1H)
    local dp = { [encodeCountState(0, 0, 0, "")] = 1 }

    local mhList = slotCandidates[16] or {}
    local ohList = slotCandidates[17] or {}
    local weaponDp = {}
    for stateKey, ways in pairs(dp) do
      local tier, emb, vault, ring1 = decodeCountState(stateKey)
      for _, mhCand in ipairs(mhList) do
        for _, ohCand in ipairs(ohList) do
          local mhKey = mhCand and mhCand.key or nil
          local ohKey = ohCand and ohCand.key or nil
          local ohIsEmpty = ohKey and ohKey:sub(1, 6) == "empty:"
          if ((not mhKey) or (not ohKey) or ohIsEmpty or mhKey ~= ohKey)
            and isValidWeaponCombo(mhCand, ohCand, classToken, specKey, loadout, requireOffhandFor1H) then
            local vaultUsed = vault
            if mhCand and mhCand.source == "vault" then
              vaultUsed = vaultUsed + 1
            end
            if ohCand and ohCand.source == "vault" then
              vaultUsed = vaultUsed + 1
            end
            if vaultUsed <= 1 then
              local nextTier = tier
                + constraints.candTierAdds(mhCand, 16)
                + constraints.candTierAdds(ohCand, 17)
              local nextEmb = emb
                + constraints.candEmbAdds(mhCand)
                + constraints.candEmbAdds(ohCand)
              local nextKey = encodeCountState(nextTier, nextEmb, vaultUsed, ring1)
              weaponDp[nextKey] = (weaponDp[nextKey] or 0) + ways
            end
          end
        end
      end
    end
    dp = weaponDp
    if not next(dp) then
      return 0
    end

    for idx, slotId in ipairs(nonWeaponSlotOrder) do
      local nextDp = {}
      for stateKey, ways in pairs(dp) do
        local tier, emb, vault, ring1 = decodeCountState(stateKey)
        if not constraints.canStillSatisfy(idx, tier, emb, slotId) then
          -- prune impossible branch
        else
          local list = slotCandidates[slotId] or {}
          if #list == 0 then
            local emptyCand = makeEmptyCandidate(slotId)
            local nextTier = tier + constraints.candTierAdds(emptyCand, slotId)
            local nextEmb = emb + constraints.candEmbAdds(emptyCand)
            local nextKey = encodeCountState(nextTier, nextEmb, vault, ring1)
            nextDp[nextKey] = (nextDp[nextKey] or 0) + ways
          else
            for _, cand in ipairs(list) do
              local key = cand and cand.key
              local isEmpty = key and key:sub(1, 6) == "empty:"
              local skip = false
              if cand.source == "vault" and vault >= 1 then
                skip = true
              elseif slotId == 12 and ring1 ~= "" and key and not isEmpty then
                if key == ring1 or ring1 > key then
                  skip = true
                end
              end
              if not skip
                and (constraints.tierKeyMatchesTarget(cand)
                  or constraints.allowNonTierPick(idx, slotId, tier)) then
                local nextVault = vault + ((cand.source == "vault") and 1 or 0)
                if nextVault <= 1 then
                  local nextTier = tier + constraints.candTierAdds(cand, slotId)
                  local nextEmb = emb + constraints.candEmbAdds(cand)
                  local nextRing1 = ring1
                  if slotId == 11 then
                    nextRing1 = (key and not isEmpty) and key or ""
                  end
                  local nextKey = encodeCountState(nextTier, nextEmb, nextVault, nextRing1)
                  nextDp[nextKey] = (nextDp[nextKey] or 0) + ways
                end
              end
            end
          end
        end
      end
      dp = nextDp
      if not next(dp) then
        return 0
      end
    end

    local total = 0
    for stateKey, ways in pairs(dp) do
      local tier, emb = decodeCountState(stateKey)
      if tier >= minTier and emb >= minEmb then
        total = total + ways
      end
    end
    return total
  end

  local strictRequireOffhandFor1H = false
  for _, cand in ipairs(slotCandidates[17] or {}) do
    if cand and cand.link then
      strictRequireOffhandFor1H = true
      break
    end
  end

  local total = runCount(strictRequireOffhandFor1H)
  if total == 0 and strictRequireOffhandFor1H then
    total = runCount(false)
  end
  return total
end

-- Count valid loadouts by formula (product / inclusion) or DP, not full enumeration.
local function countLoadoutCombinationsFormula(slotCandidates, classToken, specKey, loadout, nonWeaponSlotOrder, pruneRules)
  if slotListsShareItemKeys(slotCandidates) then
    return nil
  end

  local hasVault = slotListsHaveVaultItems(slotCandidates)
  local constrained = pruneRules and pruneRules.active

  if not constrained and not hasVault then
    return countLoadoutCombinationsProduct(slotCandidates, classToken, specKey, loadout, nonWeaponSlotOrder)
  end
  if not constrained and hasVault then
    return countLoadoutCombinationsWithVaultProduct(slotCandidates, classToken, specKey, loadout, nonWeaponSlotOrder)
  end
  return countLoadoutCombinationsDp(slotCandidates, classToken, specKey, loadout, nonWeaponSlotOrder, pruneRules)
end

local function tryFastLoadoutCombinationCount(slotCandidates, classToken, specKey, loadout, nonWeaponSlotOrder, pruneRules)
  return countLoadoutCombinationsFormula(slotCandidates, classToken, specKey, loadout, nonWeaponSlotOrder, pruneRules)
end

local function createLoadoutCountCoroutine(slotCandidates, classToken, specKey, loadout, nonWeaponSlotOrder, pruneRules, opts)
  opts = opts or {}
  local comboPerf = NS.getComboCountPerformanceSettings and NS.getComboCountPerformanceSettings() or {}
  local yieldEvery = math.max(
    1000,
    math.floor(tonumber(opts.yield_every) or comboPerf.yield_every or COMBO_COUNT_YIELD_EVERY)
  )
  local cancelFn = opts.cancelFn

  return coroutine.create(function()
    local fastTotal = countLoadoutCombinationsFormula(
      slotCandidates, classToken, specKey, loadout, nonWeaponSlotOrder, pruneRules
    )
    if fastTotal ~= nil then
      if cancelFn and cancelFn() then
        return { kind = "cancelled" }
      end
      return { kind = "done", total = fastTotal }
    end

    local aborted = false
    local stepsSinceYield = 0

    local function maybeYield(runningTotal)
      if aborted then
        coroutine.yield({ kind = "cancelled" })
      end
      stepsSinceYield = stepsSinceYield + 1
      if stepsSinceYield >= yieldEvery then
        stepsSinceYield = 0
        coroutine.yield({ kind = "progress", total = runningTotal })
        if cancelFn and cancelFn() then
          aborted = true
          coroutine.yield({ kind = "cancelled" })
        end
      elseif cancelFn and (stepsSinceYield % 128) == 0 and cancelFn() then
        aborted = true
        coroutine.yield({ kind = "cancelled" })
      end
    end

    local strictRequireOffhandFor1H = false
    for _, cand in ipairs(slotCandidates[17] or {}) do
      if cand and cand.link then
        strictRequireOffhandFor1H = true
        break
      end
    end

    local constraints = makeLoadoutConstraintHelpers(pruneRules, nonWeaponSlotOrder)

    local function countSearch(requireOffhandFor1H)
      if aborted or (cancelFn and cancelFn()) then
        aborted = true
        return nil
      end
      local total = 0
      local usedKeys = {}
      local currentAssign = {}

      local function dfs(idx, tierCount, embCount)
        maybeYield(total)
        if aborted then
          return
        end
        if idx > #nonWeaponSlotOrder then
          local ring1 = currentAssign[11]
          local ring2 = currentAssign[12]
          local ring1Key = ring1 and ring1.key or nil
          local ring2Key = ring2 and ring2.key or nil
          if ring1Key and ring2Key and ring1Key > ring2Key then
            return
          end
          if constraints.satisfiesAssign(currentAssign, embCount) then
            total = total + 1
            maybeYield(total)
          end
          return
        end

        local slotId = nonWeaponSlotOrder[idx]
        local list = slotCandidates[slotId]
        if not constraints.canStillSatisfy(idx, tierCount, embCount, slotId) then
          return
        end

        if not list or #list == 0 then
          currentAssign[slotId] = makeEmptyCandidate(slotId)
          dfs(idx + 1, tierCount, embCount)
          currentAssign[slotId] = nil
          return
        end

        for _, cand in ipairs(list) do
          local key = cand.key
          local isEmpty = key and key:sub(1, 6) == "empty:"
          if cand.source == "vault" and countVaultItemsInAssign(currentAssign) >= 1 then
            -- Great Vault: at most one reward per loadout
          elseif isEmpty or not usedKeys[key] then
            if not constraints.tierKeyMatchesTarget(cand)
              and not constraints.allowNonTierPick(idx, slotId, tierCount) then
              -- skip off-set pick that would make 4pc impossible
            else
              currentAssign[slotId] = cand
              if not isEmpty then
                usedKeys[key] = true
              end
              dfs(
                idx + 1,
                tierCount + constraints.candTierAdds(cand, slotId),
                embCount + constraints.candEmbAdds(cand)
              )
              if not isEmpty then
                usedKeys[key] = nil
              end
              currentAssign[slotId] = nil
            end
          end
        end
      end

      local mhList = slotCandidates[16] or {}
      local ohList = slotCandidates[17] or {}
      for _, mhCand in ipairs(mhList) do
        if aborted then
          return nil
        end
        for _, ohCand in ipairs(ohList) do
          if aborted then
            return nil
          end
          local mhKey = mhCand and mhCand.key or nil
          local ohKey = ohCand and ohCand.key or nil
          local ohIsEmpty = ohKey and ohKey:sub(1, 6) == "empty:"
          if ((not mhKey) or (not ohKey) or ohIsEmpty or mhKey ~= ohKey)
            and isValidWeaponCombo(mhCand, ohCand, classToken, specKey, loadout, requireOffhandFor1H) then
            currentAssign[16] = mhCand
            currentAssign[17] = ohCand
            if countVaultItemsInAssign(currentAssign) > 1 then
              currentAssign[16] = nil
              currentAssign[17] = nil
            else
              local mhIsEmpty = mhKey and mhKey:sub(1, 6) == "empty:"
              local ohIsEmpty2 = ohKey and ohKey:sub(1, 6) == "empty:"
              if mhKey and not mhIsEmpty then
                usedKeys[mhKey] = true
              end
              if ohKey and not ohIsEmpty2 then
                usedKeys[ohKey] = true
              end
              dfs(
                1,
                constraints.candTierAdds(mhCand, 16) + constraints.candTierAdds(ohCand, 17),
                constraints.candEmbAdds(mhCand) + constraints.candEmbAdds(ohCand)
              )
              if aborted then
                return nil
              end
              if mhKey and not mhIsEmpty then
                usedKeys[mhKey] = nil
              end
              if ohKey and not ohIsEmpty2 then
                usedKeys[ohKey] = nil
              end
              currentAssign[16] = nil
              currentAssign[17] = nil
              maybeYield(total)
            end
          end
        end
      end

      if aborted then
        return nil
      end
      return total
    end

    local total = countSearch(strictRequireOffhandFor1H)
    if total == nil or aborted then
      return { kind = "cancelled" }
    end
    if total == 0 and strictRequireOffhandFor1H then
      total = countSearch(false)
      if total == nil or aborted then
        return { kind = "cancelled" }
      end
    end
    return { kind = "done", total = total or 0 }
  end)
end

local function pumpLoadoutCombinationCount(countCo, opts, onComplete)
  opts = opts or {}
  local runner = opts.runner or { cancelled = false }
  local progressInterval = tonumber(opts.progress_interval_sec) or 0.1
  local lastProgressAt = 0

  local function getPumpSettings()
    local comboPerf = NS.getComboCountPerformanceSettings and NS.getComboCountPerformanceSettings() or {}
    return {
      batch_delay_sec = tonumber(opts.batch_delay_sec) or 0,
      resumes_per_pump = math.max(1, math.floor(tonumber(opts.resumes_per_pump) or comboPerf.resumes_per_pump or 1)),
    }
  end

  local function maybeReportProgress(payload)
    if not opts.onProgress or type(payload) ~= "table" or payload.kind ~= "progress" then
      return
    end
    local now = (GetTime and GetTime()) or 0
    if progressInterval <= 0 or (now - lastProgressAt) >= progressInterval then
      lastProgressAt = now
      opts.onProgress(payload)
    end
  end

  local function pump()
    if runner.cancelled then
      if onComplete then
        onComplete(true, nil)
      end
      return
    end

    local pumpSettings = getPumpSettings()
    for _ = 1, pumpSettings.resumes_per_pump do
      local ok, payload = coroutine.resume(countCo)
      if not ok then
        if onComplete then
          onComplete(false, payload)
        end
        return
      end
      if type(payload) == "table" and payload.kind == "cancelled" then
        if onComplete then
          onComplete(true, nil)
        end
        return
      end
      if coroutine.status(countCo) == "dead" then
        if onComplete then
          onComplete(false, nil, payload)
        end
        return
      end
      maybeReportProgress(payload)
    end

    if NS.scheduleScanPump then
      NS.scheduleScanPump(pumpSettings.batch_delay_sec, pump)
    else
      C_Timer.After(0, pump)
    end
  end

  if NS.scheduleScanPump then
    NS.scheduleScanPump(0, pump)
  else
    C_Timer.After(0, pump)
  end
  return runner
end

function NS.beginLoadoutCombinationCount(slotCandidates, classToken, specKey, loadout, nonWeaponSlotOrder, pruneRules, opts, onComplete)
  opts = opts or {}
  local runner = opts.runner or { cancelled = false }
  local comboPerf = NS.getComboCountPerformanceSettings and NS.getComboCountPerformanceSettings() or {}

  local fastTotal = countLoadoutCombinationsFormula(
    slotCandidates, classToken, specKey, loadout, nonWeaponSlotOrder, pruneRules
  )
  if fastTotal ~= nil then
    if runner.cancelled then
      if onComplete then
        onComplete(true, nil)
      end
      return runner
    end
    if onComplete then
      onComplete(false, nil, { kind = "done", total = fastTotal })
    end
    return runner
  end

  local countOpts = {
    yield_every = comboPerf.yield_every,
    cancelFn = function()
      return runner.cancelled
    end,
  }
  local countCo = createLoadoutCountCoroutine(
    slotCandidates, classToken, specKey, loadout, nonWeaponSlotOrder, pruneRules, countOpts
  )
  local pumpOpts = {
    runner = runner,
    batch_delay_sec = 0,
    resumes_per_pump = comboPerf.resumes_per_pump,
    progress_interval_sec = comboPerf.progress_interval_sec,
    onProgress = opts.onProgress,
  }
  pumpLoadoutCombinationCount(countCo, pumpOpts, onComplete)
  return runner
end

function NS.beginAdvisorLoadoutCombinationCount(specKey, candidatesBySlot, opts, onComplete)
  opts = opts or {}
  local buildOpts = {
    respect_selection = true,
    include_bags = candidatesBySlot == nil,
  }
  local slotCandidates, equippedBySlot, _, classToken, loadout =
    NS.buildSlotCandidates(specKey, candidatesBySlot, buildOpts)
  if opts.refresh_flags == true or NS.slotCandidatesNeedLoadoutFlags(slotCandidates) then
    refreshAllCandidateLoadoutFlags(slotCandidates, equippedBySlot)
  end
  local pruneRules = buildLoadoutPruneRules(equippedBySlot, slotCandidates, BAG_NONWEAPON_SLOT_ORDER)
  NS.lastLoadoutPruneRules = pruneRules
  return NS.beginLoadoutCombinationCount(
    slotCandidates, classToken, specKey, loadout, BAG_NONWEAPON_SLOT_ORDER, pruneRules, opts, onComplete
  )
end

function NS.slotCandidatesNeedLoadoutFlags(slotCandidates)
  for _, list in pairs(slotCandidates or {}) do
    for _, cand in ipairs(list or {}) do
      if cand and cand.link and cand.is_tier_piece == nil then
        return true
      end
    end
  end
  return false
end

function NS.countAdvisorLoadoutCombinationsSync(specKey, candidatesBySlot, opts)
  opts = opts or {}
  local buildOpts = {
    respect_selection = true,
    include_bags = candidatesBySlot == nil,
  }
  local slotCandidates, equippedBySlot, _, classToken, loadout =
    NS.buildSlotCandidates(specKey, candidatesBySlot, buildOpts)
  if opts.refresh_flags == true or NS.slotCandidatesNeedLoadoutFlags(slotCandidates) then
    refreshAllCandidateLoadoutFlags(slotCandidates, equippedBySlot)
  end
  local pruneRules = buildLoadoutPruneRules(equippedBySlot, slotCandidates, BAG_NONWEAPON_SLOT_ORDER)
  NS.lastLoadoutPruneRules = pruneRules
  return countLoadoutCombinationsFormula(
    slotCandidates, classToken, specKey, loadout, BAG_NONWEAPON_SLOT_ORDER, pruneRules
  )
end

function NS.estimateAdvisorLoadoutCombinations(specKey, candidatesBySlot, opts)
  -- Synchronous exact counts can exceed the WoW script time limit. Use
  -- NS.beginAdvisorLoadoutCombinationCount for UI/status updates instead.
  return nil
end

function NS.runBestLoadoutScan(specKey, candidatesBySlot, opts, onComplete)
  opts = opts or {}
  local runner = opts.runner or { cancelled = false }
  opts.runner = runner

  local function completeCancelled()
    if onComplete then
      onComplete(true, nil)
    end
  end

  C_Timer.After(0, function()
    if runner.cancelled then
      completeCancelled()
      return
    end

  local scanStartTime = (debugprofilestop and debugprofilestop()) or GetTime()
  local buildOpts = {
    respect_selection = true,
    include_bags = candidatesBySlot == nil,
  }
  local slotCandidates, equippedBySlot, slotOrder, classToken, loadout =
    NS.buildSlotCandidates(specKey, candidatesBySlot, buildOpts)

  if NS.statsFromItemLink then
    local itemDataReady = true
    local seenLinks = {}
    local function checkCandidate(cand)
      local link = cand and cand.link
      if link and not seenLinks[link] then
        seenLinks[link] = true
        if not NS.statsFromItemLink(link) then
          itemDataReady = false
        end
      end
    end
    for _, list in pairs(slotCandidates or {}) do
      for _, cand in ipairs(list or {}) do
        checkCandidate(cand)
      end
    end
    for _, cand in pairs(equippedBySlot or {}) do
      checkCandidate(cand)
    end

    if not itemDataReady then
      local attempt = (tonumber(opts.item_data_retry_count) or 0) + 1
      if attempt <= MAX_LOADOUT_ITEM_DATA_RETRIES then
        opts.item_data_retry_count = attempt
        C_Timer.After(LOADOUT_ITEM_DATA_RETRY_DELAY, function()
          if runner.cancelled then
            completeCancelled()
          else
            NS.runBestLoadoutScan(specKey, candidatesBySlot, opts, onComplete)
          end
        end)
      elseif onComplete then
        onComplete(false, "Item data did not finish loading; please retry the loadout scan.")
      end
      return
    end
    opts.item_data_retry_count = nil
  end

  refreshAllCandidateLoadoutFlags(slotCandidates, equippedBySlot)

  local nonWeaponSlotOrder = BAG_NONWEAPON_SLOT_ORDER
  local pruneRules = buildLoadoutPruneRules(equippedBySlot, slotCandidates, nonWeaponSlotOrder)

  local baseStats = NS.getPlayerStatVector()
  local basePred = NS.getCachedBaseDps(baseStats, specKey)
  if NS.resetStatDeltaStats then
    NS.resetStatDeltaStats()
  end
  local cacheStatsStart = NS.getPredictionCacheSnapshot and NS.getPredictionCacheSnapshot() or {
    hits = 0,
    misses = 0,
    evictions = 0,
    lookup_ms = 0,
    insert_ms = 0,
    eviction_ms = 0,
    forward_count = 0,
    forward_ms = 0,
  }
  local fusedProfileStart = {
    hits = NS.fusedForwardProfile and NS.fusedForwardProfile.hits or 0,
    misses = NS.fusedForwardProfile and NS.fusedForwardProfile.misses or 0,
    changed_neurons = NS.fusedForwardProfile and NS.fusedForwardProfile.changed_neurons or 0,
  }
  local zeroStats = makeZeroStats()
  local deltaCacheBySlot = {}
  local weaponDeltaCache = {}
  local weaponScoreCache = {}
  local perfState = {
    yield_every = DEFAULT_BAG_SCAN_YIELD_EVERY,
    batch_delay_sec = 0,
    resumes_per_pump = 1,
  }

  local function refreshPerfState()
    local perf = NS.getScanPerformanceSettings and NS.getScanPerformanceSettings()
    if not perf then
      return
    end
    if tonumber(opts.yield_every) then
      perfState.yield_every = math.max(1, math.floor(opts.yield_every))
    else
      perfState.yield_every = math.max(1, math.floor(perf.yield_every or DEFAULT_BAG_SCAN_YIELD_EVERY))
    end
    if tonumber(opts.batch_delay_sec) then
      perfState.batch_delay_sec = math.max(0, opts.batch_delay_sec)
    else
      perfState.batch_delay_sec = math.max(0, perf.batch_delay_sec or 0)
    end
    perfState.resumes_per_pump = math.max(1, math.floor(perf.resumes_per_pump or 1))
  end
  refreshPerfState()

  local function weaponCacheKeys(mhCand, ohCand)
    local mhKey = mhCand and mhCand.key or "<nil-mh>"
    local ohKey = ohCand and ohCand.key or "<nil-oh>"
    return mhKey, ohKey
  end

  local function getWeaponDelta(mhCand, ohCand)
    local mhKey, ohKey = weaponCacheKeys(mhCand, ohCand)
    local byOffhand = weaponDeltaCache[mhKey]
    if not byOffhand then
      byOffhand = {}
      weaponDeltaCache[mhKey] = byOffhand
    end
    local cached = byOffhand[ohKey]
    if cached then
      return cached
    end
    cached = NS.computeWeaponLoadoutDelta(
      mhCand,
      ohCand,
      equippedBySlot[16],
      equippedBySlot[17],
      specKey
    )
    byOffhand[ohKey] = cached
    return cached
  end

  local function candidateToItemRef(cand)
    if not cand or not cand.link then
      return nil
    end
    return {
      link = cand.link,
      guid = cand.guid,
      bag = cand.bag,
      slot = cand.slot,
    }
  end

  local function getCandidateDelta(slotId, cand)
    if not cand or not cand.key then
      return zeroStats
    end
    local slotCache = deltaCacheBySlot[slotId]
    if not slotCache then
      slotCache = {}
      deltaCacheBySlot[slotId] = slotCache
    end
    local cached = slotCache[cand.key]
    if cached then
      return cached
    end
    local equipped = equippedBySlot[slotId]
    if equipped and equipped.key and cand.key == equipped.key then
      cached = zeroStats
      slotCache[cand.key] = cached
      return cached
    end

    if NS.computeStatDelta and equipped then
      local candRef = candidateToItemRef(cand)
      local eqRef = candidateToItemRef(equipped)
      if candRef and eqRef then
        local delta = NS.computeStatDelta(candRef, eqRef)
        if delta then
          slotCache[cand.key] = delta
          return delta
        end
      end
    end

    local candStats = cand.stats
    if cand.link and NS.statsFromItemLink then
      candStats = NS.statsFromItemLink(cand.link)
    end
    local eqStats = equipped and equipped.stats or zeroStats
    if equipped and equipped.link and NS.statsFromItemLink then
      eqStats = NS.statsFromItemLink(equipped.link)
    end
    if not candStats or (equipped and not eqStats) then
      -- Returning a conservative zero without caching lets a later pass retry
      -- once item data is ready; stale/empty snapshots must not become scores.
      return zeroStats
    end
    if MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.debug then
      NS.debugPrint(string.format(
        "%s: raw stat fallback for slot %s candidate %s",
        NS.BRAND or "MrMythical",
        tostring(slotId),
        tostring(cand.key)
      ))
    end

    cached = {
      primary_stat = (candStats.primary_stat or 0) - (eqStats.primary_stat or 0),
      crit = (candStats.crit or 0) - (eqStats.crit or 0),
      haste = (candStats.haste or 0) - (eqStats.haste or 0),
      mastery = (candStats.mastery or 0) - (eqStats.mastery or 0),
      versatility = (candStats.versatility or 0) - (eqStats.versatility or 0),
    }
    slotCache[cand.key] = cached
    return cached
  end

  local scoreStatsTmp = {
    primary_stat = 0, crit = 0, haste = 0, mastery = 0, versatility = 0,
  }

  local function getWeaponScore(mhCand, ohCand)
    local mhKey, ohKey = weaponCacheKeys(mhCand, ohCand)
    local byOffhand = weaponScoreCache[mhKey]
    if not byOffhand then
      byOffhand = {}
      weaponScoreCache[mhKey] = byOffhand
    end
    local cached = byOffhand[ohKey]
    if cached ~= nil then
      return cached
    end
    local wdelta = getWeaponDelta(mhCand, ohCand)
    scoreStatsTmp.primary_stat = (baseStats.primary_stat or 0) + (wdelta.primary_stat or 0)
    scoreStatsTmp.crit = (baseStats.crit or 0) + (wdelta.crit or 0)
    scoreStatsTmp.haste = (baseStats.haste or 0) + (wdelta.haste or 0)
    scoreStatsTmp.mastery = (baseStats.mastery or 0) + (wdelta.mastery or 0)
    scoreStatsTmp.versatility = (baseStats.versatility or 0) + (wdelta.versatility or 0)
    cached = NS.getCachedPrediction(scoreStatsTmp, specKey) - basePred
    byOffhand[ohKey] = cached
    return cached
  end

  local function candStatScore(cand)
    local s = cand.stats
    if not s then return 0 end
    return (s.primary_stat or 0) + (s.crit or 0) + (s.haste or 0)
      + (s.mastery or 0) + (s.versatility or 0)
  end

  local function sortSlotCandidates(slotId)
    local list = slotCandidates[slotId]
    if not list or #list <= 1 then
      return
    end
    local equippedKey = equippedBySlot[slotId] and equippedBySlot[slotId].key or nil
    local scores = {}
    for _, cand in ipairs(list) do
      -- Sorting only changes traversal order; use the allocation-free raw-stat
      -- score here so scan setup does not run a synchronous model burst.
      scores[cand] = candidateQuickScore(cand)
    end
    table.sort(list, function(a, b)
      local scoreA = scores[a]
      local scoreB = scores[b]
      if scoreA ~= scoreB then
        return scoreA > scoreB
      end
      local aIsEquipped = equippedKey and a.key == equippedKey or false
      local bIsEquipped = equippedKey and b.key == equippedKey or false
      if aIsEquipped ~= bIsEquipped then
        return aIsEquipped
      end
      return candStatScore(a) > candStatScore(b)
    end)
  end

  for _, slotId in ipairs(slotOrder) do
    sortSlotCandidates(slotId)
  end

  local totalCombinations = 0

  local function beginLoadoutSearch()
    if runner.cancelled then
      completeCancelled()
      return
    end

  local strictRequireOffhandFor1H = false
  for _, cand in ipairs(slotCandidates[17] or {}) do
    if cand and cand.link then
      strictRequireOffhandFor1H = true
      break
    end
  end

  local function buildWeaponPairs(requireOffhandFor1H)
    local pairs = {}
    local mhList = slotCandidates[16] or {}
    local ohList = slotCandidates[17] or {}
    for _, mhCand in ipairs(mhList) do
      for _, ohCand in ipairs(ohList) do
        local mhKey = mhCand and mhCand.key or nil
        local ohKey = ohCand and ohCand.key or nil
        local ohIsEmpty = ohKey and ohKey:sub(1, 6) == "empty:"
        if (not mhKey) or (not ohKey) or ohIsEmpty or mhKey ~= ohKey then
          if isValidWeaponCombo(mhCand, ohCand, classToken, specKey, loadout, requireOffhandFor1H) then
            local pairScore
            local pairDelta
            if NS.computeWeaponLoadoutDelta then
              pairDelta = getWeaponDelta(mhCand, ohCand)
              pairScore = candStatScore(mhCand) + candStatScore(ohCand)
            else
              pairScore = candStatScore(mhCand) + candStatScore(ohCand)
            end
            table.insert(pairs, {
              mh = mhCand,
              oh = ohCand,
              score = pairScore,
              delta = pairDelta,
            })
          end
        end
      end
    end
    table.sort(pairs, function(a, b) return a.score > b.score end)
    return pairs
  end

  local function assignChangeCount(assign)
    local n = 0
    for _, sid in ipairs(slotOrder) do
      local chosen = assign[sid] or equippedBySlot[sid]
      local eq = equippedBySlot[sid]
      if chosen and eq and chosen.key and eq.key and chosen.key ~= eq.key then
        n = n + 1
      end
    end
    return n
  end

  local function isBetterLoadout(pred, assign, bestPred, bestAssign)
    if not bestPred then
      return true
    end
    if pred > bestPred + 1e-9 then
      return true
    end
    if math.abs(pred - bestPred) <= 1e-9 then
      return assignChangeCount(assign) < assignChangeCount(bestAssign)
    end
    return false
  end

  local function countVaultInAssign(assign)
    local n = 0
    for _, sid in ipairs(slotOrder) do
      local c = assign and assign[sid]
      if c and c.source == "vault" then
        n = n + 1
      end
    end
    return n
  end

  local searchCo = coroutine.create(function()
    local constraints = makeLoadoutConstraintHelpers(pruneRules, nonWeaponSlotOrder)

    local function runSearch(requireOffhandFor1H)
      local bestPredLocal, bestAssignLocal, checkedLocal = nil, nil, 0
      local usedKeys = {}
      local currentAssign = {}
      local basePrimary = baseStats.primary_stat or 0
      local baseCrit = baseStats.crit or 0
      local baseHaste = baseStats.haste or 0
      local baseMastery = baseStats.mastery or 0
      local baseVersatility = baseStats.versatility or 0
      local runningDelta = {
        primary = 0, crit = 0, haste = 0, mastery = 0, versatility = 0,
      }
      local evalStatsTmp = {
        primary_stat = 0, crit = 0, haste = 0, mastery = 0, versatility = 0,
      }
      local fastBestPred = -math.huge
      local fastTolerance = tonumber(NS.FUSED_PREDICTION_ERROR_TOLERANCE) or 1e-5
      local contenders = {}

      local function applyDeltaToRunning(d, sign)
        runningDelta.primary = runningDelta.primary + sign * (d.primary_stat or 0)
        runningDelta.crit = runningDelta.crit + sign * (d.crit or 0)
        runningDelta.haste = runningDelta.haste + sign * (d.haste or 0)
        runningDelta.mastery = runningDelta.mastery + sign * (d.mastery or 0)
        runningDelta.versatility = runningDelta.versatility + sign * (d.versatility or 0)
      end

      local function resetRunningDeltaForWeapons(weaponDelta)
        runningDelta.primary = 0
        runningDelta.crit = 0
        runningDelta.haste = 0
        runningDelta.mastery = 0
        runningDelta.versatility = 0
        if NS.computeWeaponLoadoutDelta then
          local wdelta = weaponDelta
          if not wdelta then
            local mhPick = currentAssign[16] or equippedBySlot[16]
            local ohPick = currentAssign[17] or equippedBySlot[17]
            wdelta = getWeaponDelta(mhPick, ohPick)
          end
          runningDelta.primary = wdelta.primary_stat or 0
          runningDelta.crit = wdelta.crit or 0
          runningDelta.haste = wdelta.haste or 0
          runningDelta.mastery = wdelta.mastery or 0
          runningDelta.versatility = wdelta.versatility or 0
        else
          for _, sid in ipairs({ 16, 17 }) do
            local chosen = currentAssign[sid] or equippedBySlot[sid]
            applyDeltaToRunning(getCandidateDelta(sid, chosen), 1)
          end
        end
      end

      local function pruneFastContenders()
        local threshold = fastBestPred - fastTolerance
        local writeIndex = 1
        for readIndex = 1, #contenders do
          local contender = contenders[readIndex]
          if contender.fast_pred >= threshold then
            contenders[writeIndex] = contender
            writeIndex = writeIndex + 1
          end
        end
        for index = writeIndex, #contenders do
          contenders[index] = nil
        end
      end

      local function recordFastContender(pred)
        if pred > fastBestPred then
          fastBestPred = pred
          pruneFastContenders()
        end
        if pred < fastBestPred - fastTolerance then
          return
        end
        local contender = {
          fast_pred = pred,
          stats = {
            primary_stat = evalStatsTmp.primary_stat,
            crit = evalStatsTmp.crit,
            haste = evalStatsTmp.haste,
            mastery = evalStatsTmp.mastery,
            versatility = evalStatsTmp.versatility,
          },
          assign = {},
        }
        for _, sid in ipairs(slotOrder) do
          contender.assign[sid] = currentAssign[sid]
        end
        contenders[#contenders + 1] = contender
      end

      local sliceStart = debugprofilestop and debugprofilestop() or nil
      local checkedAtLastYield = 0
      local function maybeYield(force, explicitTimeCheck)
        if runner.cancelled then
          coroutine.yield({ kind = "cancelled" })
        end
        local countBudgetReached = checkedLocal - checkedAtLastYield >= perfState.yield_every
        local timeBudgetReached = false
        if sliceStart and (force or explicitTimeCheck or (checkedLocal % 8) == 0) then
          timeBudgetReached = (debugprofilestop() - sliceStart) >= LOADOUT_SCAN_SLICE_BUDGET_MS
        end
        if force or countBudgetReached or timeBudgetReached then
          coroutine.yield({ kind = "progress", checked = checkedLocal, total = totalCombinations })
          checkedAtLastYield = checkedLocal
          sliceStart = debugprofilestop and debugprofilestop() or nil
        end
      end

      local function evalCurrent(embCount)
        local mh = currentAssign[16]
        local oh = currentAssign[17]
        if not isValidWeaponCombo(mh, oh, classToken, specKey, loadout, requireOffhandFor1H) then
          return
        end
        local ring1 = currentAssign[11]
        local ring2 = currentAssign[12]
        local ring1Key = ring1 and ring1.key or nil
        local ring2Key = ring2 and ring2.key or nil
        if ring1Key and ring2Key and ring1Key > ring2Key then
          return
        end
        if not constraints.satisfiesAssign(currentAssign, embCount) then
          return
        end
        evalStatsTmp.primary_stat = basePrimary + runningDelta.primary
        evalStatsTmp.crit = baseCrit + runningDelta.crit
        evalStatsTmp.haste = baseHaste + runningDelta.haste
        evalStatsTmp.mastery = baseMastery + runningDelta.mastery
        evalStatsTmp.versatility = baseVersatility + runningDelta.versatility
        local predict = NS.predictWithStatsFused or NS.predictWithStats or NS.getCachedPrediction
        local pred = predict(evalStatsTmp, specKey)
        checkedLocal = checkedLocal + 1
        recordFastContender(pred)
        maybeYield()
      end

      local weaponPairs = buildWeaponPairs(requireOffhandFor1H)
      if #weaponPairs == 0 then
        return nil, nil, 0, false
      end

      local traversalNodesUntilTimeCheck = 256
      local function dfsNonWeapon(idx, tierCount, embCount)
        if runner.cancelled then
          return
        end
        traversalNodesUntilTimeCheck = traversalNodesUntilTimeCheck - 1
        if traversalNodesUntilTimeCheck <= 0 then
          traversalNodesUntilTimeCheck = 256
          maybeYield(false, true)
        end
        if idx > #nonWeaponSlotOrder then
          evalCurrent(embCount)
          return
        end

        local slotId = nonWeaponSlotOrder[idx]
        local list = slotCandidates[slotId]
        if not constraints.canStillSatisfy(idx, tierCount, embCount, slotId) then
          return
        end

        if not list or #list == 0 then
          local emptyCand = makeEmptyCandidate(slotId)
          currentAssign[slotId] = emptyCand
          local d = getCandidateDelta(slotId, emptyCand)
          applyDeltaToRunning(d, 1)
          dfsNonWeapon(idx + 1, tierCount, embCount)
          applyDeltaToRunning(d, -1)
          currentAssign[slotId] = nil
          return
        end
        for _, cand in ipairs(list) do
          local key = cand.key
          local isEmpty = key and key:sub(1, 6) == "empty:"
          if cand.source == "vault" and countVaultInAssign(currentAssign) >= 1 then
            -- Great Vault: at most one reward per loadout
          elseif isEmpty or not usedKeys[key] then
            if not constraints.tierKeyMatchesTarget(cand)
              and not constraints.allowNonTierPick(idx, slotId, tierCount) then
              -- skip
            else
              currentAssign[slotId] = cand
              local d = getCandidateDelta(slotId, cand)
              applyDeltaToRunning(d, 1)
              if not isEmpty then usedKeys[key] = true end
              dfsNonWeapon(
                idx + 1,
                tierCount + constraints.candTierAdds(cand, slotId),
                embCount + constraints.candEmbAdds(cand)
              )
              if not isEmpty then usedKeys[key] = nil end
              applyDeltaToRunning(d, -1)
              currentAssign[slotId] = nil
            end
          end
        end
      end

      for _, pair in ipairs(weaponPairs) do
        if runner.cancelled then
          coroutine.yield({ kind = "cancelled" })
          break
        end
        currentAssign[16] = pair.mh
        currentAssign[17] = pair.oh
        resetRunningDeltaForWeapons(pair.delta)
        local mhKey = pair.mh and pair.mh.key or nil
        local ohKey = pair.oh and pair.oh.key or nil
        local mhIsEmpty = mhKey and mhKey:sub(1, 6) == "empty:"
        local ohIsEmpty = ohKey and ohKey:sub(1, 6) == "empty:"
        if countVaultInAssign(currentAssign) > 1 then
          currentAssign[16] = nil
          currentAssign[17] = nil
        else
        if mhKey and not mhIsEmpty then usedKeys[mhKey] = true end
        if ohKey and not ohIsEmpty then usedKeys[ohKey] = true end
        dfsNonWeapon(
          1,
          constraints.candTierAdds(pair.mh, 16) + constraints.candTierAdds(pair.oh, 17),
          constraints.candEmbAdds(pair.mh) + constraints.candEmbAdds(pair.oh)
        )
        maybeYield(true)
        if mhKey and not mhIsEmpty then usedKeys[mhKey] = nil end
        if ohKey and not ohIsEmpty then usedKeys[ohKey] = nil end
        currentAssign[16] = nil
        currentAssign[17] = nil
        end
      end

      local exactPredict = NS.predictWithStats or NS.getCachedPrediction
      for index, contender in ipairs(contenders) do
        local pred = exactPredict(contender.stats, specKey)
        if isBetterLoadout(pred, contender.assign, bestPredLocal, bestAssignLocal) then
          bestPredLocal = pred
          bestAssignLocal = contender.assign
        end
        if (index % 8) == 0 then
          maybeYield(true)
        end
      end
      return bestPredLocal, bestAssignLocal, checkedLocal, false
    end

    local bestPred, bestAssign, checked, wasCapped = runSearch(strictRequireOffhandFor1H)
    local usedRelaxedWeaponFallback = false
    if not bestAssign and strictRequireOffhandFor1H then
      local relaxedPred, relaxedAssign, relaxedChecked, relaxedWasCapped = runSearch(false)
      if relaxedAssign then
        bestPred = relaxedPred
        bestAssign = relaxedAssign
        checked = relaxedChecked
        wasCapped = relaxedWasCapped
        usedRelaxedWeaponFallback = true
      end
    end

    if not bestAssign then
      return { kind = "done", hasResult = false }
    end

    local slotRows = {}
    for _, slotId in ipairs(slotOrder) do
      local chosen = bestAssign[slotId]
      if chosen and chosen.link then
        local equipped = equippedBySlot[slotId]
        local isUpgrade = true
        if equipped and equipped.key and chosen.key and equipped.key == chosen.key then
          isUpgrade = false
        end
        local bag, slot = chosen.bag, chosen.slot
        if bag == nil or slot == nil then
          bag, slot = findBagSlotForItem(chosen.link, chosen.guid)
        end
        local row = {
          slot_order = SLOT_ID_ORDER[slotId] or 999,
          slot_label = SLOT_ID_LABELS[slotId] or tostring(slotId),
          slot_id = slotId,
          name = chosen.name,
          link = chosen.link,
          guid = chosen.guid,
          quality = chosen.quality,
          equipped_name = equipped and (equipped.name or equipped.link) or "(Empty)",
          equipped_link = equipped and equipped.link or nil,
          equipped_quality = equipped and equipped.quality or -1,
          is_upgrade = isUpgrade,
          bag = bag,
          slot = slot,
          source = chosen.source,
          source_label = chosen.source_label,
          instance_name = chosen.instance_name,
          instance_id = chosen.instance_id,
          vault_activity_id = chosen.vault_activity_id,
          key = chosen.key,
        }
        row.can_equip = isUpgrade and bag ~= nil and slot ~= nil
        table.insert(slotRows, row)
      end
    end

    if NS.computeWeaponPairDpsDelta or NS.computeWeaponLoadoutDelta then
      local loadout = NS.getWeaponLoadoutForSpec and NS.getWeaponLoadoutForSpec(specKey)
      local mh = bestAssign[16]
      local oh = bestAssign[17]
      local is2H = mh and mh.link and NS.is2HWeapon and NS.is2HWeapon(mh.link)
      local pairDps
      if NS.computeWeaponLoadoutDelta then
        pairDps = getWeaponScore(mh, oh)
      else
        pairDps = NS.computeWeaponPairDpsDelta(mh, oh, equippedBySlot[16], equippedBySlot[17], specKey)
      end
      local usePairLabel = loadout and loadout.dual_wield and not is2H
      if pairDps ~= nil then
        for _, row in ipairs(slotRows) do
          if (row.slot_id == 16 or row.slot_id == 17) and row.is_upgrade then
            row.dps_delta = pairDps
            row.weapon_pair_dps = usePairLabel
          end
        end
      end
    end

    local summary = {
      dps_base = basePred,
      dps_new = bestPred,
      dps_delta = (bestPred or basePred) - basePred,
      combinations_checked = checked,
      combinations_total = totalCombinations,
      combinations_capped = wasCapped,
      used_relaxed_weapon_fallback = usedRelaxedWeaponFallback,
      prune_rules_active = pruneRules and pruneRules.active or false,
      prune_min_tier_pieces = pruneRules and pruneRules.min_tier_set_pieces or nil,
      prune_min_embellishments = pruneRules and pruneRules.min_embellishments or nil,
      prune_target_tier_name = pruneRules and pruneRules.target_tier and pruneRules.target_tier.set_name or nil,
      tier_pieces_in_loadout = countMatchingTierInAssign(
        bestAssign,
        pruneRules and pruneRules.target_tier,
        pruneRules and pruneRules.target_tier_keys,
        equippedBySlot
      ),
      spec_key = specKey,
      stat_delta_native = NS.statDeltaStats and NS.statDeltaStats.native or nil,
      stat_delta_fallback = NS.statDeltaStats and NS.statDeltaStats.fallback or nil,
      stat_delta_cache_hits = NS.statDeltaStats and NS.statDeltaStats.cache_hits or nil,
      stat_delta_cache_misses = NS.statDeltaStats and NS.statDeltaStats.cache_misses or nil,
    }

    local scanEndTime = (debugprofilestop and debugprofilestop()) or GetTime()
    local scanElapsed = scanEndTime - scanStartTime
    if scanElapsed <= 0 then scanElapsed = 1e-6 end
    local cacheStatsEnd = NS.getPredictionCacheSnapshot and NS.getPredictionCacheSnapshot() or {}
    local function counterDelta(field)
      local startValue = cacheStatsStart[field] or 0
      local endValue = cacheStatsEnd[field] or 0
      local delta = endValue - startValue
      if delta < 0 then
        return endValue
      end
      return delta
    end
    local statStats = NS.statDeltaStats or {}
    local fusedStats = NS.fusedForwardProfile or {}
    local fusedHits = math.max(0, (fusedStats.hits or 0) - fusedProfileStart.hits)
    local fusedMisses = math.max(0, (fusedStats.misses or 0) - fusedProfileStart.misses)
    local fusedChanged = math.max(
      0,
      (fusedStats.changed_neurons or 0) - fusedProfileStart.changed_neurons
    )
    NS.lastLoadoutScanStats = {
      combinations_checked = checked,
      elapsed_ms = debugprofilestop and scanElapsed or (scanElapsed * 1000),
      combos_per_sec = checked / (debugprofilestop and (scanElapsed / 1000) or scanElapsed),
      cache_hits = counterDelta("hits"),
      cache_misses = counterDelta("misses"),
      cache_evictions = counterDelta("evictions"),
      cache_lookup_ms = counterDelta("lookup_ms"),
      cache_insert_ms = counterDelta("insert_ms"),
      cache_eviction_ms = counterDelta("eviction_ms"),
      cache_size = cacheStatsEnd.current_size or 0,
      cache_peak_size = cacheStatsEnd.peak_size or 0,
      forward_calls = counterDelta("forward_count"),
      forward_ms = counterDelta("forward_ms"),
      stat_delta_ms = statStats.totalMs or 0,
      stat_delta_cache_hits = statStats.cache_hits or 0,
      stat_delta_cache_misses = statStats.cache_misses or 0,
      fused_reference_hits = fusedHits,
      fused_reference_builds = fusedMisses,
      fused_avg_changed_neurons = checked > 0 and (fusedChanged / checked) or 0,
    }
    if MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.debug then
      NS.debugPrint(string.format(
        "loadout scan: %d combos in %.1fms (%.0f/s) cache %d/%d, %d evictions",
        checked,
        NS.lastLoadoutScanStats.elapsed_ms,
        NS.lastLoadoutScanStats.combos_per_sec,
        NS.lastLoadoutScanStats.cache_hits,
        (NS.lastLoadoutScanStats.cache_hits or 0) + (NS.lastLoadoutScanStats.cache_misses or 0),
        NS.lastLoadoutScanStats.cache_evictions
      ))
      NS.debugPrint(string.format(
        "inference phases: forward %.1fms/%d, lookup %.1fms, insert %.1fms, evict %.1fms, stat delta %.1fms (%d/%d cache)",
        NS.lastLoadoutScanStats.forward_ms,
        NS.lastLoadoutScanStats.forward_calls,
        NS.lastLoadoutScanStats.cache_lookup_ms,
        NS.lastLoadoutScanStats.cache_insert_ms,
        NS.lastLoadoutScanStats.cache_eviction_ms,
        NS.lastLoadoutScanStats.stat_delta_ms,
        NS.lastLoadoutScanStats.stat_delta_cache_hits,
        NS.lastLoadoutScanStats.stat_delta_cache_hits + NS.lastLoadoutScanStats.stat_delta_cache_misses
      ))
      NS.debugPrint(string.format(
        "fused inference: %d reference hits, %d builds, %.1f changed neurons/call",
        NS.lastLoadoutScanStats.fused_reference_hits,
        NS.lastLoadoutScanStats.fused_reference_builds,
        NS.lastLoadoutScanStats.fused_avg_changed_neurons
      ))
    end

    return { kind = "done", hasResult = true, summary = summary, slotRows = slotRows }
  end)

  local function pump()
    if runner.cancelled then
      completeCancelled()
      return
    end
    refreshPerfState()
    local maxResumes = perfState.resumes_per_pump
    for _ = 1, maxResumes do
      if runner.cancelled then
        completeCancelled()
        return
      end
      local ok, payload = coroutine.resume(searchCo)
      if not ok then
        if onComplete then onComplete(false, payload) end
        return
      end
      if type(payload) == "table" and payload.kind == "cancelled" then
        completeCancelled()
        return
      end
      if coroutine.status(searchCo) == "dead" then
        if onComplete then onComplete(false, nil, payload) end
        return
      end
      if type(payload) == "table" and payload.kind == "progress" and opts.onProgress then
        opts.onProgress(payload)
      end
    end
    if NS.scheduleScanPump then
      NS.scheduleScanPump(perfState.batch_delay_sec, pump)
    else
      C_Timer.After(0, pump)
    end
  end

  if NS.scheduleScanPump then
    NS.scheduleScanPump(perfState.batch_delay_sec, pump)
  else
    C_Timer.After(0, pump)
  end
  end

  NS.beginLoadoutCombinationCount(
    slotCandidates, classToken, specKey, loadout, nonWeaponSlotOrder, pruneRules,
    {
      runner = runner,
      onProgress = opts.onCountProgress,
    },
    function(cancelled, err, payload)
      if cancelled or runner.cancelled then
        completeCancelled()
        return
      end
      if err or not payload or payload.kind ~= "done" then
        if onComplete then
          onComplete(false, err)
        end
        return
      end
      totalCombinations = payload.total or 0
      if opts.onReady then
        opts.onReady({ total = totalCombinations })
      end
      beginLoadoutSearch()
    end
  )
  end)

  return runner
end

