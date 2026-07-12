local ADDON_NAME, NS = ...

local resolvePreviewLootLink
local isLootLinkUsableForPlayer
local isLootLinkPendingData

local SLOT_ID_LABELS = NS.SLOT_ID_LABELS

local VAULT_TYPE_LABELS = {}
local VAULT_TYPE_BUILT = false

local VAULT_TYPE_ENUM_KEYS = {
  { key = "Activities", label = "Activities Vault" },
  { key = "MythicPlus", label = "M+ Vault" },
  { key = "Raid", label = "Raid Vault" },
  { key = "RankedPvP", label = "PvP Vault" },
  { key = "World", label = "World Vault" },
}

local function addVaultTypeLabel(enumValue, label)
  if enumValue ~= nil and label then
    VAULT_TYPE_LABELS[enumValue] = label
  end
end

local function buildVaultTypeLabels()
  if VAULT_TYPE_BUILT then return end
  VAULT_TYPE_BUILT = true
  local enumTable = Enum and Enum.WeeklyRewardChestThresholdType
  if not enumTable then return end
  for _, cfg in ipairs(VAULT_TYPE_ENUM_KEYS) do
    addVaultTypeLabel(enumTable[cfg.key], cfg.label)
  end
end

local function getVaultThresholdTypes()
  buildVaultTypeLabels()
  local types = {}
  local seen = {}
  local enumTable = Enum and Enum.WeeklyRewardChestThresholdType
  if not enumTable then return types end
  for _, cfg in ipairs(VAULT_TYPE_ENUM_KEYS) do
    local value = enumTable[cfg.key]
    if value ~= nil and not seen[value] then
      seen[value] = true
      table.insert(types, value)
    end
  end
  return types
end

local function getItemIlvl(itemLink)
  if not itemLink then return 0 end
  if C_Item and C_Item.GetDetailedItemLevelInfo then
    local ilvl = C_Item.GetDetailedItemLevelInfo(itemLink)
    if ilvl and ilvl > 0 then return ilvl end
  end
  local _, _, _, ilvl = GetItemInfo(itemLink)
  return tonumber(ilvl) or 0
end

function NS.getItemIlvl(itemLink)
  return getItemIlvl(itemLink)
end

local function getItemMeta(link)
  local name, _, quality, _, _, _, _, _, equipLoc = GetItemInfo(link)
  return {
    name = name or link,
    quality = quality or -1,
    equipLoc = equipLoc,
    ilvl = getItemIlvl(link),
  }
end

local function primeItemInfo(link, itemID)
  if itemID and GetItemInfoInstant then
    GetItemInfoInstant(itemID)
  end
  if itemID and C_Item and C_Item.RequestLoadItemDataByID then
    local cached = false
    if C_Item.IsItemDataCachedByID then
      local okCached, isCached = pcall(C_Item.IsItemDataCachedByID, itemID)
      cached = okCached and isCached == true
    end
    if not cached then
      pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
  end
  if link and C_Item and C_Item.GetItemInfo then
    C_Item.GetItemInfo(link)
  elseif link and GetItemInfo then
    GetItemInfo(link)
  elseif itemID and GetItemInfo then
    GetItemInfo(itemID)
  end
end

local function resolveItemTypeInfo(link)
  local itemClassID, itemSubClassID, equipLoc = NS.getItemTypeInfo(link)
  if equipLoc and equipLoc ~= "" then
    return itemClassID, itemSubClassID, equipLoc
  end

  local itemID = tonumber(link and link:match("item:(%d+)"))
  if not itemID then
    return itemClassID, itemSubClassID, equipLoc
  end

  primeItemInfo(link, itemID)

  if GetItemInfoInstant then
    local _, _, _, instantEquipLoc, _, instantClassID, instantSubClassID = GetItemInfoInstant(itemID)
    if instantEquipLoc and instantEquipLoc ~= "" then
      return instantClassID, instantSubClassID, instantEquipLoc
    end
  end

  itemClassID, itemSubClassID, equipLoc = NS.getItemTypeInfo(link)
  if equipLoc and equipLoc ~= "" then
    return itemClassID, itemSubClassID, equipLoc
  end

  local _, _, _, _, _, classID2, subClassID2, _, equipLoc2 = GetItemInfo(itemID)
  return classID2, subClassID2, equipLoc2
end

local function isTrinketEquipLoc(equipLoc)
  return equipLoc == "INVTYPE_TRINKET"
end

local function isTrinketLink(link)
  local _, _, equipLoc = resolveItemTypeInfo(link)
  return isTrinketEquipLoc(equipLoc)
end

function NS.isTrinketLink(link)
  return isTrinketLink(link)
end

local function pickBestPrediction(pred)
  if not pred then return nil end
  if pred.dps_delta ~= nil then return pred end
  if pred[1] then
    local best = pred[1]
    for i = 2, #pred do
      if (pred[i].dps_delta or 0) > (best.dps_delta or 0) then
        best = pred[i]
      end
    end
    return best
  end
  return nil
end

local function vaultActivityLabel(activity, fallback)
  buildVaultTypeLabels()
  local typeLabel = VAULT_TYPE_LABELS[activity.type] or fallback or "Vault"
  local detail = ""
  if activity.level and activity.level > 0 then
    detail = " lvl " .. tostring(activity.level)
  elseif activity.raidString and activity.raidString ~= "" then
    detail = " " .. activity.raidString
  end
  local status = ""
  if activity.threshold and activity.progress then
    if activity.progress >= activity.threshold then
      status = " (earned)"
    else
      status = string.format(" (%d/%d)", activity.progress, activity.threshold)
    end
  end
  return typeLabel .. detail .. status
end

local function addUniqueRef(refs, seen, link, meta)
  meta = meta or {}
  if not link or link == "" or isTrinketLink(link) then
    return
  end
  local itemID = meta.item_id or tonumber(link:match("item:(%d+)"))
  local seenKey = meta.seen_key or link
  if seen[seenKey] then
    return
  end
  seen[seenKey] = true
  local itemMeta = getItemMeta(link)
  table.insert(refs, {
    link = link,
    item_id = itemID,
    source = meta.source or "unknown",
    source_label = meta.source_label or meta.source or "Unknown",
    claimable = meta.claimable,
    preview = meta.preview,
    instance_id = meta.instance_id,
    instance_name = meta.instance_name,
    instance_kind = meta.instance_kind,
    token_item_id = meta.token_item_id,
    token_link = meta.token_link,
    name = itemMeta.name,
    quality = itemMeta.quality,
    ilvl = itemMeta.ilvl,
    equipLoc = itemMeta.equipLoc,
    vault_activity_id = meta.vault_activity_id,
  })
end

local function isEquippableEquipLoc(equipLoc)
  if not equipLoc or equipLoc == "" then
    return false
  end
  if equipLoc == "INVTYPE_NON_EQUIP_IGNORE" or equipLoc:find("NON_EQUIP", 1, true) then
    return false
  end
  return true
end

local function isLikelyTierTokenLoot(info, itemID)
  if NS.isArmorTokenItem and NS.isArmorTokenItem(itemID) then
    return true
  end
  if not info then
    return false
  end
  if info.displayAsPerPlayerLoot and info.armorType and info.armorType ~= "" then
    return true
  end
  if info.filterType == 14 and info.armorType and info.armorType ~= "" then
    return true
  end
  return false
end

local function isSkippableOtherLoot(info, itemID)
  if not info or info.filterType ~= 14 then
    return false
  end
  return not isLikelyTierTokenLoot(info, itemID)
end

local function tryAddInstanceLootRef(refs, seen, journalLink, info, journalInstanceId, instanceName, resolvedKind, specKey, previewPreset)
  if not journalLink or not info or not info.itemID then
    return false, false, nil
  end

  local tokenItemID = info.itemID
  local lootLink = journalLink
  local lootItemID = tokenItemID
  local tokenLink = nil
  local likelyToken = isLikelyTierTokenLoot(info, tokenItemID)
  local _, classToken = UnitClass("player")

  local function pendingItemIds()
    local ids = {}
    local idSeen = {}
    local function track(id)
      if id and not idSeen[id] then
        idSeen[id] = true
        ids[#ids + 1] = id
      end
    end
    track(tokenItemID)
    if lootItemID ~= tokenItemID then
      track(lootItemID)
    end
    return #ids > 0 and ids or nil
  end

  if NS.resolveArmorTokenLootLink then
    local pieceLink, pieceItemID = NS.resolveArmorTokenLootLink(tokenItemID, journalLink, classToken)
    if pieceLink and pieceItemID then
      tokenLink = journalLink
      lootLink = pieceLink
      lootItemID = pieceItemID
    end
  end

  primeItemInfo(lootLink, lootItemID)

  local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(lootLink)
  if not isEquippableEquipLoc(equipLoc) and not tokenLink and not likelyToken then
    return false, false, nil
  end

  local checkLink = lootLink
  if previewPreset and previewPreset.key ~= "journal" and lootItemID and resolvePreviewLootLink then
    local previewLink = resolvePreviewLootLink(
      journalInstanceId,
      lootItemID,
      previewPreset,
      resolvedKind,
      lootLink,
      instanceName
    )
    if previewLink and previewLink ~= "" then
      primeItemInfo(previewLink, lootItemID)
      checkLink = previewLink
    end
  end

  if isLootLinkUsableForPlayer and isLootLinkUsableForPlayer(checkLink, specKey) then
    local sourceLabel = instanceName or ("Instance " .. tostring(journalInstanceId))
    if tokenLink then
      sourceLabel = sourceLabel .. " (tier token)"
    end
    addUniqueRef(refs, seen, lootLink, {
      source = "loot",
      source_label = sourceLabel,
      instance_id = journalInstanceId,
      instance_name = instanceName,
      instance_kind = resolvedKind,
      item_id = lootItemID,
      token_item_id = tokenLink and tokenItemID or nil,
      token_link = tokenLink,
      seen_key = string.format("%d:%d", journalInstanceId, tokenItemID or 0),
    })
    return true, false, nil
  end

  if tokenLink then
    requestLootItemData(lootItemID)
  elseif likelyToken then
    requestLootItemData(tokenItemID)
    requestLootItemData(lootItemID)
  end

  if isLootLinkPendingData and (isLootLinkPendingData(checkLink) or isLootLinkPendingData(lootLink) or isLootLinkPendingData(journalLink)) then
    return false, true, pendingItemIds()
  end
  if likelyToken and not tokenLink then
    return false, true, pendingItemIds()
  end
  return false, false, nil
end

local MAX_VAULT_SLOT_INDEX = 3

local function isEquippableVaultLink(link)
  if not link then
    return false
  end
  local itemMeta = getItemMeta(link)
  local equipLoc = itemMeta.equipLoc
  return equipLoc and equipLoc ~= "" and NS.INVTYPE_TO_SLOT_IDS and NS.INVTYPE_TO_SLOT_IDS[equipLoc] ~= nil
end

local function isVisibleVaultActivity(activity)
  if not activity or not activity.type or not activity.index then
    return false
  end
  if activity.index < 1 or activity.index > MAX_VAULT_SLOT_INDEX then
    return false
  end
  local enumTable = Enum and Enum.WeeklyRewardChestThresholdType
  if not enumTable then
    return true
  end
  local activityType = activity.type
  return activityType == enumTable.Activities
    or activityType == enumTable.Raid
    or activityType == enumTable.World
    or activityType == enumTable.RankedPvP
end

local function isVaultItemReward(reward)
  if not reward or not reward.itemDBID then
    return false
  end
  local rewardType = Enum and Enum.CachedRewardType
  if rewardType and reward.type and reward.type ~= rewardType.Item then
    return false
  end
  if reward.id and C_Item and C_Item.IsItemKeystoneByID and C_Item.IsItemKeystoneByID(reward.id) then
    return false
  end
  return true
end

local function pickPrimaryVaultReward(activity)
  local bestReward = nil
  local bestQuality = -1
  local bestLevel = -1
  for _, rewardInfo in ipairs(activity.rewards or {}) do
    if isVaultItemReward(rewardInfo) then
      local itemQuality, itemLevel = 0, 0
      if rewardInfo.id and C_Item and C_Item.GetItemInfo then
        local _, _, quality, level = C_Item.GetItemInfo(rewardInfo.id)
        itemQuality = quality or 0
        itemLevel = level or 0
      elseif rewardInfo.id and GetItemInfo then
        local _, _, quality, level = GetItemInfo(rewardInfo.id)
        itemQuality = quality or 0
        itemLevel = level or 0
      end
      if itemQuality > bestQuality or (itemQuality == bestQuality and itemLevel > bestLevel) then
        bestQuality = itemQuality
        bestLevel = itemLevel
        bestReward = rewardInfo
      end
    end
  end
  return bestReward
end

local function addVaultDisplayedReward(refs, seen, activity, label, itemDBID)
  if not itemDBID or not C_WeeklyRewards.GetItemHyperlink then
    return false
  end
  local link = C_WeeklyRewards.GetItemHyperlink(itemDBID)
  if not link or not isEquippableVaultLink(link) then
    return false
  end
  addUniqueRef(refs, seen, link, {
    source = "vault",
    source_label = label,
    claimable = true,
    preview = false,
    vault_activity_id = activity.id,
    seen_key = string.format("vault:%s:%s", tostring(activity.id), tostring(itemDBID)),
  })
  return true
end

local function collectVaultEntriesFromOpenFrame()
  local vaultFrame = WeeklyRewardsFrame
  if not vaultFrame or not vaultFrame.IsShown or not vaultFrame:IsShown() or not vaultFrame.Activities then
    return nil
  end

  local entries = {}
  for _, activityFrame in ipairs(vaultFrame.Activities) do
    if activityFrame
      and activityFrame.IsShown and activityFrame:IsShown()
      and activityFrame.hasRewards
      and activityFrame.info
      and isVisibleVaultActivity(activityFrame.info) then
      table.insert(entries, {
        activity = activityFrame.info,
        activityFrame = activityFrame,
        label = vaultActivityLabel(activityFrame.info, VAULT_TYPE_LABELS[activityFrame.info.type]),
      })
    end
  end
  return entries
end

local function collectVaultEntriesFromAPI()
  local activities = C_WeeklyRewards.GetActivities()
  if not activities then
    return {}
  end

  local entries = {}
  for _, activity in ipairs(activities) do
    if isVisibleVaultActivity(activity) and activity.rewards and #activity.rewards > 0 then
      table.insert(entries, {
        activity = activity,
        activityFrame = nil,
        label = vaultActivityLabel(activity, VAULT_TYPE_LABELS[activity.type]),
      })
    end
  end
  return entries
end

local function resolveVaultItemDBID(entry)
  local activity = entry.activity
  local itemFrame = entry.activityFrame and entry.activityFrame.ItemFrame
  if itemFrame and itemFrame.displayedItemDBID then
    return itemFrame.displayedItemDBID
  end
  local reward = pickPrimaryVaultReward(activity)
  return reward and reward.itemDBID or nil
end

function NS.collectVaultRewardRefs()
  local refs = {}
  local seen = {}
  if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities) then
    return refs, "Great Vault API unavailable"
  end

  buildVaultTypeLabels()

  local entries = collectVaultEntriesFromOpenFrame()
  if not entries or #entries == 0 then
    entries = collectVaultEntriesFromAPI()
  end

  for _, entry in ipairs(entries) do
    local itemDBID = resolveVaultItemDBID(entry)
    addVaultDisplayedReward(refs, seen, entry.activity, entry.label, itemDBID)
  end

  if #refs == 0 then
    local note = "No vault rewards found"
    if C_WeeklyRewards.HasAvailableRewards and C_WeeklyRewards.HasAvailableRewards() then
      note = "Rescan with vault open."
    end
    return refs, note
  end
  return refs, nil
end

NS.LOOT_ALL_INSTANCES = "all"

local function getCurrentEjTierId()
  return (EJ_GetNumTiers and EJ_GetNumTiers()) or 1
end

local function normalizeInstanceName(name)
  return (name or ""):lower():gsub("[%s'%-%.]", "")
end

local function parseEjInstanceByIndex(index, isRaid)
  if not EJ_GetInstanceByIndex then
    return nil
  end
  local journalId, name, _, _, _, _, dungeonUiMapID, _, _, _, instanceMapId = EJ_GetInstanceByIndex(index, isRaid)
  if not journalId then
    return nil
  end
  return {
    journalId = journalId,
    name = name,
    instanceMapId = instanceMapId,
    uiMapId = dungeonUiMapID,
    isRaid = isRaid,
  }
end

local ejDungeonLookupCache = nil

local function invalidateEjDungeonLookup()
  ejDungeonLookupCache = nil
end
NS.invalidateEjDungeonLookup = invalidateEjDungeonLookup

function NS.ensureEncounterJournalLoaded()
  if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.LoadAddOn then
    if not C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then
      C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
      NS.invalidateEjDungeonLookup()
      if NS.invalidateLootUpgradePresets then
        NS.invalidateLootUpgradePresets()
      end
    end
  end
  if C_MythicPlus and C_MythicPlus.RequestMapInfo then
    C_MythicPlus.RequestMapInfo()
  end
end

local function getEjDungeonLookup()
  if ejDungeonLookupCache then
    return ejDungeonLookupCache
  end
  local lookup = { byNormName = {}, byId = {} }
  if not (EJ_SelectTier and EJ_GetInstanceByIndex and EJ_GetNumTiers) then
    ejDungeonLookupCache = lookup
    return lookup
  end

  EJ_SelectTier(getCurrentEjTierId())
  local numTiers = (EJ_GetNumTiers and EJ_GetNumTiers()) or 1
  for tier = 1, numTiers do
    EJ_SelectTier(tier)
    local index = 1
    while true do
      local entry = parseEjInstanceByIndex(index, false)
      if not entry then
        break
      end
      if entry.name then
        local norm = normalizeInstanceName(entry.name)
        lookup.byNormName[norm] = { journalId = entry.journalId, name = entry.name }
      end
      if entry.uiMapId and entry.uiMapId > 0 then
        lookup.byId[entry.uiMapId] = entry.journalId
      end
      if entry.instanceMapId and entry.instanceMapId > 0 then
        lookup.byId[entry.instanceMapId] = entry.journalId
      end
      index = index + 1
    end
  end

  EJ_SelectTier(getCurrentEjTierId())
  ejDungeonLookupCache = lookup
  return lookup
end

local function namesLikelyMatch(a, b)
  if not a or not b then
    return false
  end
  local normA = normalizeInstanceName(a)
  local normB = normalizeInstanceName(b)
  return normA == normB or a == b
end

-- Sporefall uses discrete raid ilvls instead of the standard upgrade track ladder.
local SPOREFALL_RAID_ILVLS = { 259, 272, 285, 298 }

local function isSporefallInstance(instanceId, instanceName)
  local name = normalizeInstanceName(instanceName)
  if name:find("sporefall", 1, true) then
    return true
  end
  if instanceId and EJ_GetInstanceInfo then
    local ejName = normalizeInstanceName(select(1, EJ_GetInstanceInfo(instanceId)))
    if ejName:find("sporefall", 1, true) then
      return true
    end
  end
  return false
end

local function roundUpSporefallIlvl(presetIlvl)
  if not presetIlvl or presetIlvl <= 0 then
    return presetIlvl
  end
  for _, ilvl in ipairs(SPOREFALL_RAID_ILVLS) do
    if presetIlvl <= ilvl then
      return ilvl
    end
  end
  return SPOREFALL_RAID_ILVLS[#SPOREFALL_RAID_ILVLS]
end

local function getPreviewTargetIlvl(presetIlvl, instanceId, instanceName, instanceKind)
  if not presetIlvl or presetIlvl <= 0 then
    return presetIlvl
  end
  if instanceKind == "Raid" and isSporefallInstance(instanceId, instanceName) then
    return roundUpSporefallIlvl(presetIlvl)
  end
  return presetIlvl
end

local function getPreviewTargetTrack(previewPreset, instanceId, instanceName, instanceKind)
  if not previewPreset then
    return nil
  end
  -- Sporefall uses fixed raid difficulties rather than upgrade-track ranks.
  -- Requiring the dropdown track there rejects otherwise-correct raid links.
  if instanceKind == "Raid" and isSporefallInstance(instanceId, instanceName) then
    return nil
  end
  return previewPreset.track
end

-- Midnight S1 M+ map IDs (fallback when API filters are incomplete).
local SEASON_CHALLENGE_MAP_IDS = { 402, 558, 560, 559, 556, 239, 161, 557 }

local function getEjInstanceName(journalId)
  if not journalId or not EJ_GetInstanceInfo then
    return nil
  end
  return select(1, EJ_GetInstanceInfo(journalId))
end

local function resolveJournalForChallengeMap(mapId, mapName)
  if not mapId or not mapName then
    return nil
  end

  NS.ensureEncounterJournalLoaded()
  if not (EJ_SelectTier and EJ_GetInstanceByIndex) then
    return nil
  end

  local numTiers = (EJ_GetNumTiers and EJ_GetNumTiers()) or 1
  local currentTier = getCurrentEjTierId()

  -- Newest tiers first: map API, then exact name match.
  for tier = numTiers, 1, -1 do
    EJ_SelectTier(tier)
    if EJ_GetInstanceForMap then
      local journalId = EJ_GetInstanceForMap(mapId)
      if journalId and journalId > 0 then
        local ejName = getEjInstanceName(journalId)
        if ejName and namesLikelyMatch(mapName, ejName) then
          EJ_SelectTier(currentTier)
          return journalId
        end
      end
    end
  end

  for tier = numTiers, 1, -1 do
    EJ_SelectTier(tier)
    local index = 1
    while true do
      local entry = parseEjInstanceByIndex(index, false)
      if not entry then
        break
      end
      if entry.name and namesLikelyMatch(mapName, entry.name) then
        EJ_SelectTier(currentTier)
        return entry.journalId
      end
      index = index + 1
    end
  end

  local lookup = getEjDungeonLookup()
  local byName = lookup.byNormName[normalizeInstanceName(mapName)]
  if byName and byName.journalId then
    EJ_SelectTier(currentTier)
    return byName.journalId
  end

  if lookup.byId[mapId] then
    local journalId = lookup.byId[mapId]
    local ejName = getEjInstanceName(journalId)
    if not ejName or namesLikelyMatch(mapName, ejName) then
      EJ_SelectTier(currentTier)
      return journalId
    end
  end

  EJ_SelectTier(currentTier)
  return nil
end

local function getSeasonChallengeMapIds()
  local ids = {}
  local seen = {}
  local mapTable = C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable() or {}
  for _, mapId in ipairs(mapTable) do
    local include = true
    if C_MythicPlus and C_MythicPlus.IsDungeonScorable then
      include = C_MythicPlus.IsDungeonScorable(mapId) == true
    end
    if include and not seen[mapId] then
      seen[mapId] = true
      table.insert(ids, mapId)
    end
  end

  if #ids == 0 then
    for _, mapId in ipairs(mapTable) do
      if not seen[mapId] then
        seen[mapId] = true
        table.insert(ids, mapId)
      end
    end
  end

  for _, mapId in ipairs(SEASON_CHALLENGE_MAP_IDS) do
    if not seen[mapId] then
      seen[mapId] = true
      table.insert(ids, mapId)
    end
  end

  return ids
end

local function collectSeasonDungeonInstances()
  NS.ensureEncounterJournalLoaded()
  local dungeons = {}
  local seenMapIds = {}

  local function addDungeon(journalId, name, mapId)
    if not journalId or not name or not mapId or seenMapIds[mapId] then
      return
    end
    seenMapIds[mapId] = true
    table.insert(dungeons, {
      id = journalId,
      journalId = journalId,
      name = name,
      mapId = mapId,
    })
  end

  for _, mapId in ipairs(getSeasonChallengeMapIds()) do
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
      local mapName = select(1, C_ChallengeMode.GetMapUIInfo(mapId))
      if mapName and mapName ~= "" then
        local journalId = resolveJournalForChallengeMap(mapId, mapName)
        if journalId then
          addDungeon(journalId, mapName, mapId)
        end
      end
    end
  end

  table.sort(dungeons, function(a, b)
    return a.name < b.name
  end)

  return dungeons
end

local function collectCurrentTierRaidInstances()
  local raids = {}
  local seen = {}
  for startIndex = 2, 1, -1 do
    local index = startIndex
    while true do
      local entry = parseEjInstanceByIndex(index, true)
      if not entry then
        break
      end
      if not seen[entry.journalId] then
        seen[entry.journalId] = true
        table.insert(raids, {
          id = entry.journalId,
          journalId = entry.journalId,
          name = entry.name or ("Raid " .. tostring(entry.journalId)),
        })
      end
      index = index + 1
    end
    if #raids > 0 then
      break
    end
  end
  return raids
end

function NS.collectEncounterJournalInstances()
  NS.ensureEncounterJournalLoaded()
  local instances = {}
  local seen = {}

  local function addInstance(journalId, name, kind, mapId)
    if not journalId or not name then
      return
    end
    local uniqueKey = (kind == "Dungeon" and mapId) or journalId
    if not uniqueKey or seen[uniqueKey] then
      return
    end
    seen[uniqueKey] = true
    table.insert(instances, {
      id = journalId,
      name = name,
      kind = kind,
      mapId = mapId,
      label = kind .. ": " .. name,
    })
  end

  for _, dungeon in ipairs(collectSeasonDungeonInstances()) do
    addInstance(dungeon.journalId or dungeon.id, dungeon.name, "Dungeon", dungeon.mapId)
  end

  for _, raid in ipairs(collectCurrentTierRaidInstances()) do
    addInstance(raid.journalId or raid.id, raid.name, "Raid", nil)
  end

  table.sort(instances, function(a, b)
    if a.kind ~= b.kind then
      return a.kind == "Dungeon"
    end
    return a.name < b.name
  end)

  return instances
end

local function applyEncounterJournalPlayerLootFilters()
  local _, _, classID = UnitClass("player")
  local specIndex = GetSpecialization and GetSpecialization() or nil
  local specID = specIndex and GetSpecializationInfo(specIndex) or nil
  if EJ_SetLootFilter and classID and specID then
    EJ_SetLootFilter(classID, specID)
  elseif EJ_ResetLootFilter then
    EJ_ResetLootFilter()
  end
  if C_EncounterJournal and C_EncounterJournal.SetSlotFilter then
    C_EncounterJournal.SetSlotFilter(15)
  elseif EJ_SetSlotFilter then
    EJ_SetSlotFilter(15)
  end
end

local function getPlayerPrimaryStatKind()
  local specIndex = GetSpecialization and GetSpecialization() or nil
  if not specIndex then
    return nil
  end
  local _, _, _, _, _, _, primaryStat = GetSpecializationInfo(specIndex)
  if primaryStat == LE_UNIT_STAT_STRENGTH then
    return "strength"
  end
  if primaryStat == LE_UNIT_STAT_AGILITY then
    return "agility"
  end
  if primaryStat == LE_UNIT_STAT_INTELLECT then
    return "intellect"
  end
  return nil
end

local function accumulatePrimaryStatTotals(stats, totals)
  if type(stats) ~= "table" then
    return
  end
  for key, value in pairs(stats) do
    if type(key) == "string" and type(value) == "number" and value > 0 then
      local upper = key:upper()
      if upper:find("STRENGTH", 1, true) and not upper:find("VERSATILITY", 1, true) then
        totals.strength = totals.strength + value
      elseif upper:find("AGILITY", 1, true) then
        totals.agility = totals.agility + value
      elseif upper:find("INTELLECT", 1, true) then
        totals.intellect = totals.intellect + value
      end
    end
  end
end

local function getItemPrimaryStatTotals(link)
  local totals = { strength = 0, agility = 0, intellect = 0 }
  if not link then
    return totals
  end

  local itemID = tonumber(link:match("item:(%d+)"))
  primeItemInfo(link, itemID)

  if C_Item and C_Item.GetItemStats then
    local ok, stats = pcall(C_Item.GetItemStats, link)
    if ok then
      accumulatePrimaryStatTotals(stats, totals)
    end
  end
  if GetItemStats then
    local ok, currentStats = pcall(GetItemStats, link)
    if ok then
      accumulatePrimaryStatTotals(currentStats, totals)
    end
  end

  return totals
end

local function primaryStatTotalsHaveWrongWeaponStat(totals, wantedKind)
  local wantedAmount = totals[wantedKind] or 0
  local hasWrong = false
  for kind, amount in pairs(totals) do
    if kind ~= wantedKind and amount > 0 then
      hasWrong = true
      break
    end
  end
  if hasWrong and wantedAmount <= 0 then
    return true
  end
  return hasWrong
end

local function itemHasUsablePrimaryStat(link)
  local wantedKind = getPlayerPrimaryStatKind()
  if not wantedKind then
    return true
  end

  local itemClassID = select(1, resolveItemTypeInfo(link))
  local totals = getItemPrimaryStatTotals(link)
  local totalPrimary = totals.strength + totals.agility + totals.intellect

  if totalPrimary > 0 then
    if primaryStatTotalsHaveWrongWeaponStat(totals, wantedKind) then
      if itemClassID == 2 then
        return false
      end
      if (totals[wantedKind] or 0) <= 0 then
        return false
      end
    end
    return true
  end

  local itemID = tonumber(link and link:match("item:(%d+)"))
  if itemID and C_Item and C_Item.RequestLoadItemDataByID then
    if C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
      C_Item.RequestLoadItemDataByID(itemID)
    end
    if C_Item.IsItemDataCachedByID and C_Item.IsItemDataCachedByID(itemID) then
      totals = getItemPrimaryStatTotals(link)
      totalPrimary = totals.strength + totals.agility + totals.intellect
      if totalPrimary > 0 then
        if primaryStatTotalsHaveWrongWeaponStat(totals, wantedKind) then
          if itemClassID == 2 then
            return false
          end
          if (totals[wantedKind] or 0) <= 0 then
            return false
          end
        end
        return true
      end
    end
  end

  if itemClassID == 2 then
    if C_Item and C_Item.IsUsableItem then
      local ok, usable = pcall(C_Item.IsUsableItem, link)
      if ok and usable == false then
        return false
      end
    end
    if itemID and C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
      return false
    end
  end

  return true
end

local function isWeaponUsableForPlayer(classToken, specKey, itemClassID, itemSubClassID, equipLoc)
  if NS.isItemAllowedForMainHand(classToken, itemClassID, itemSubClassID, equipLoc) then
    return true
  end
  if NS.isItemAllowedForOffHand(classToken, specKey, itemClassID, itemSubClassID, equipLoc) then
    return true
  end
  return false
end

isLootLinkUsableForPlayer = function(link, specKey)
  if not link then
    return false
  end
  if isTrinketLink(link) then
    return false
  end

  primeItemInfo(link, tonumber(link:match("item:(%d+)")))
  local itemClassID, itemSubClassID, equipLoc = resolveItemTypeInfo(link)
  if not equipLoc or equipLoc == "" then
    return false
  end

  local _, classToken = UnitClass("player")
  if itemClassID == 4 then
    if not NS.isArmorCandidateAllowedForClass(classToken, itemClassID, itemSubClassID) then
      return false
    end
  elseif itemClassID == 2 then
    if not isWeaponUsableForPlayer(classToken, specKey, itemClassID, itemSubClassID, equipLoc) then
      return false
    end
  end

  if not itemHasUsablePrimaryStat(link) then
    return false
  end

  return true
end

function NS.isGearLinkUsableForPlayer(link, specKey)
  return isLootLinkUsableForPlayer(link, specKey)
end

local lootUpgradePresetsCache = nil
local previewLinkCache = {}
local itemIlvlPreviewCache = {}
local authoritativePreviewCache = {}
local previewContextHintCache = {}
local function previewContextHintKey(targetIlvl, instanceKind, targetTrack)
  return string.format("%s:%d:%s", instanceKind or "Dungeon", targetIlvl or 0, targetTrack or "")
end

local function clearPreviewCaches()
  previewLinkCache = {}
  authoritativePreviewCache = {}
  previewContextHintCache = {}
  itemIlvlPreviewCache = {}
end

-- Shared ilvls must never use an ilvl-only cache or an unreadable track.
local AMBIGUOUS_TRACK_ILVLS = {
  [259] = true,
  [263] = true,
  [272] = true,
  [276] = true,
}
local CONTEXT_ENUM_FALLBACK
local getCreationContextValue
local getStaticContextForIlvl
local getContextValueForIlvl
local getPresetDungeonContextEnum
local trackToPresetKey
local getPreviewLinkForContext
local previewLinkPassesTrackCheck
local getPresetCrestBonusId

local function normalizeTrackLabel(track)
  if not track or track == "" then
    return nil
  end
  return (track:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function previewTrackCacheKey(targetIlvl, targetTrack)
  local normalized = normalizeTrackLabel(targetTrack)
  return string.format("%d|%s", targetIlvl or 0, normalized and normalized:lower() or "")
end

local function parseTrackTierAndRank(track)
  if not track or track == "" then
    return nil, nil
  end
  local tier, rank = track:match("^(%a+)%s*(%d+)$")
  if tier then
    return tier, tonumber(rank)
  end
  return track, nil
end

local function trackLabelsMatch(linkTrack, targetTrack)
  local linkTier, linkRank = parseTrackTierAndRank(normalizeTrackLabel(linkTrack))
  local targetTier, targetRank = parseTrackTierAndRank(normalizeTrackLabel(targetTrack))
  if not targetTier then
    return true
  end
  if not linkTier then
    return false
  end
  if linkTier:lower() ~= targetTier:lower() then
    return false
  end
  if targetRank and linkRank then
    return targetRank == linkRank
  end
  if targetRank and not linkRank then
    return false
  end
  return true
end

local function getUpgradeTrackFromLink(link)
  if not link or not (C_Item and C_Item.GetItemUpgradeInfo) then
    return nil
  end
  local ok, info = pcall(C_Item.GetItemUpgradeInfo, link)
  if ok and info and info.trackString and info.trackString ~= "" then
    local rank = tonumber(info.currentLevel)
    if rank and rank > 0 then
      return string.format("%s %d", info.trackString, rank)
    end
    return info.trackString
  end
  return nil
end

function NS.getItemUpgradeTrackLabel(link)
  return getUpgradeTrackFromLink(link)
end

function NS.itemUpgradeTracksMatch(trackA, trackB)
  return trackLabelsMatch(trackA, trackB)
end

local function splitItemPayload(link)
  if not link then
    return nil
  end
  local payload = link:match("|H(item:[^|]+)|")
  if not payload and LinkUtil and LinkUtil.ExtractLink then
    local _, options = LinkUtil.ExtractLink(link)
    if options and options:find("^item:") then
      payload = options
    end
  end
  if not payload then
    return nil
  end
  return { strsplit(":", payload) }
end

local function padItemParts(parts, minLen)
  if not parts then
    return nil
  end
  while #parts < minLen do
    table.insert(parts, "")
  end
  return parts
end

local function rebuildItemLink(baseLink, parts)
  if not baseLink or not parts then
    return nil
  end
  local payload = table.concat(parts, ":")
  if baseLink:find("|Hitem:") then
    return baseLink:gsub("|Hitem:[^|]+|", "|H" .. payload .. "|", 1)
  end
  return nil
end

-- Midnight dungeon upgrade presets align 1:1 with crest track ranks (973/974/978).
local LOOT_TRACK_CREST_IDS = {
  champion = 973,
  hero = 974,
  myth = 978,
}

local function getLootPresetCrestStep(targetTrack)
  if not targetTrack then
    return nil
  end
  local tier, rank = parseTrackTierAndRank(normalizeTrackLabel(targetTrack))
  if not tier or not rank then
    return nil
  end
  local trackId = LOOT_TRACK_CREST_IDS[tier:lower()]
  if not trackId then
    return nil
  end
  return trackId, rank
end

local function isBonusCountField(value)
  local n = tonumber(value)
  return n and n >= 0 and n <= 10
end

local function readBonusIdsFromCountIndex(parts, countIndex)
  if not parts or not countIndex then
    return nil
  end
  local numBonus = tonumber(parts[countIndex]) or 0
  if numBonus <= 0 or numBonus > 10 then
    return nil
  end
  local bonusIDs = {}
  for i = 1, numBonus do
    local bonusID = tonumber(parts[countIndex + i])
    if not bonusID then
      return nil
    end
    bonusIDs[i] = bonusID
  end
  return #bonusIDs > 0 and bonusIDs or nil
end

local function getUpgradeFieldLayout(parts)
  if not parts then
    return nil
  end
  -- Match TierTokenData: validate bonus list at count field before picking layout.
  if readBonusIdsFromCountIndex(parts, 14) then
    return {
      extended = false,
      contextIndex = 13,
      numBonusIndex = 14,
      firstBonusIndex = 15,
    }
  end
  if readBonusIdsFromCountIndex(parts, 13) then
    return {
      extended = false,
      contextIndex = 12,
      numBonusIndex = 13,
      firstBonusIndex = 14,
    }
  end
  local gapField = parts[13]
  local hasGap = gapField == nil or gapField == "" or gapField == "0"
  if hasGap and tonumber(parts[14]) and readBonusIdsFromCountIndex(parts, 15) then
    return {
      extended = true,
      contextIndex = 14,
      numBonusIndex = 15,
      firstBonusIndex = 16,
    }
  end
  -- Raid journal without gap: link level at 12, context at 14, count at 15.
  if tonumber(parts[14]) and readBonusIdsFromCountIndex(parts, 15) then
    return {
      extended = false,
      contextIndex = 14,
      numBonusIndex = 15,
      firstBonusIndex = 16,
    }
  end
  return {
    extended = false,
    contextIndex = 13,
    numBonusIndex = 14,
    firstBonusIndex = 15,
  }
end

local function collectBindBonusesFromParts(parts)
  if not parts then
    return nil
  end
  local layout = getUpgradeFieldLayout(parts)
  local kept = {}
  local seen = {}
  local function tryKeep(bid)
    bid = tonumber(bid)
    if bid and not NS.isCrestUpgradeBonusId(bid) and not seen[bid] then
      seen[bid] = true
      kept[#kept + 1] = bid
    end
  end
  local numBonus = tonumber(parts[layout.numBonusIndex]) or 0
  if numBonus > 10 then
    numBonus = 0
  end
  if numBonus > 0 then
    for i = 1, numBonus do
      tryKeep(parts[layout.firstBonusIndex + i - 1])
    end
  else
    for i = layout.firstBonusIndex, #parts do
      tryKeep(parts[i])
    end
  end
  return kept
end

local function linkHasOnlyExpectedCrestBonus(link, targetTrack)
  if not link or not targetTrack then
    return false
  end
  local expectedBonus = getPresetCrestBonusId(targetTrack)
  if not expectedBonus or not NS.isCrestUpgradeBonusId then
    return false
  end
  local parts = splitItemPayload(link)
  if not parts then
    return false
  end
  local foundExpected = false
  for i = 13, #parts do
    local bid = tonumber(parts[i])
    if bid and NS.isCrestUpgradeBonusId(bid) then
      if bid == expectedBonus then
        foundExpected = true
      else
        return false
      end
    end
  end
  return foundExpected
end

local function linkContainsBonusId(link, bonusId)
  if not link or not bonusId then
    return false
  end
  local parts = splitItemPayload(link)
  if not parts then
    return false
  end
  for i = 13, #parts do
    if tonumber(parts[i]) == bonusId then
      return true
    end
  end
  return false
end

local UPGRADE_LAYOUT_CANDIDATES = {
  { contextIndex = 13, numBonusIndex = 14, firstBonusIndex = 15 },
  { contextIndex = 14, numBonusIndex = 15, firstBonusIndex = 16 },
  { contextIndex = 12, numBonusIndex = 13, firstBonusIndex = 14 },
}

getPresetCrestBonusId = function(targetTrack)
  if not targetTrack then
    return nil
  end
  local trackId, upgradeLevel = getLootPresetCrestStep(targetTrack)
  if trackId and NS.ensureCrestTrackCached then
    NS.ensureCrestTrackCached(trackId)
  end
  return trackId and upgradeLevel and NS.findCrestBonusIdForGroupLevel(trackId, upgradeLevel) or nil
end

local function encodePresetUpgradeOnPartsWithLayout(parts, expectedCtx, targetTrack, layout, bindBonuses)
  if not parts or parts[1] ~= "item" or not layout then
    return nil
  end
  bindBonuses = bindBonuses or collectBindBonusesFromParts(parts) or {}
  local crestBonusId = getPresetCrestBonusId(targetTrack)
  local merged = {}
  for i = 1, layout.firstBonusIndex - 1 do
    merged[i] = parts[i] or ""
  end
  merged[layout.contextIndex] = tostring(expectedCtx or tonumber(parts[layout.contextIndex]) or 0)
  local allBonuses = {}
  for _, bid in ipairs(bindBonuses) do
    allBonuses[#allBonuses + 1] = tostring(bid)
  end
  if crestBonusId then
    allBonuses[#allBonuses + 1] = tostring(crestBonusId)
  elseif targetTrack then
    return nil
  end
  merged[layout.numBonusIndex] = tostring(#allBonuses)
  for i, bid in ipairs(allBonuses) do
    merged[layout.firstBonusIndex + i - 1] = bid
  end
  return merged
end

local function encodePresetUpgradeOnParts(parts, expectedCtx, targetTrack)
  if not parts or parts[1] ~= "item" then
    return nil
  end
  return encodePresetUpgradeOnPartsWithLayout(parts, expectedCtx, targetTrack, getUpgradeFieldLayout(parts))
end

local function getCreationContextValueSet()
  local values = {}
  if CONTEXT_ENUM_FALLBACK then
    for _, value in pairs(CONTEXT_ENUM_FALLBACK) do
      values[value] = true
    end
  end
  return values
end

local function linkHasOnlyExpectedCreationContext(link, expectedCtx)
  if not link or not expectedCtx then
    return false
  end
  local parts = splitItemPayload(link)
  if not parts then
    return false
  end
  local contextValues = getCreationContextValueSet()
  local foundExpected = false
  for i = 12, 16 do
    local value = tonumber(parts[i])
    if value and contextValues[value] then
      if value == expectedCtx then
        foundExpected = true
      else
        return false
      end
    end
  end
  return foundExpected
end

-- Dungeon previews: keep API link header/context, replace ilvl bonuses with preset crest only.
-- Keeping journal/API bind bonuses (e.g. 3524) stacks a second "Heroic" label on ChallengeMode contexts.
local function encodeDungeonPreviewOnPartsWithLayout(parts, expectedCtx, targetTrack, layout)
  if not parts or parts[1] ~= "item" or not layout then
    return nil
  end
  local crestBonusId = getPresetCrestBonusId(targetTrack)
  if not crestBonusId then
    return nil
  end
  local contextValues = getCreationContextValueSet()
  local merged = {}
  for i = 1, layout.firstBonusIndex - 1 do
    local value = parts[i] or ""
    local bid = tonumber(value)
    if bid and NS.isCrestUpgradeBonusId and NS.isCrestUpgradeBonusId(bid) then
      value = ""
    elseif i ~= layout.contextIndex and i ~= layout.numBonusIndex and bid then
      if contextValues[bid] or (bid >= 1 and bid <= 10) then
        value = ""
      end
    end
    merged[i] = value
  end
  merged[layout.contextIndex] = tostring(expectedCtx)
  merged[layout.numBonusIndex] = "1"
  merged[layout.firstBonusIndex] = tostring(crestBonusId)
  return merged
end

local function encodeDungeonPreviewOnParts(parts, expectedCtx, targetTrack)
  if not parts or parts[1] ~= "item" then
    return nil
  end
  return encodeDungeonPreviewOnPartsWithLayout(parts, expectedCtx, targetTrack, getUpgradeFieldLayout(parts))
end

local function dungeonEncodedLinkPassesChecks(link, expectedCtx, targetTrack)
  return link
    and linkHasOnlyExpectedCrestBonus(link, targetTrack)
    and linkHasOnlyExpectedCreationContext(link, expectedCtx)
end

local function applyDungeonPreviewEncoding(link, expectedCtx, targetTrack)
  if not link then
    return nil
  end
  local parts = splitItemPayload(link)
  if not parts then
    return nil
  end
  parts = padItemParts(parts, 16)
  local detectedLayout = getUpgradeFieldLayout(parts)
  local layouts = { detectedLayout }
  for _, layout in ipairs(UPGRADE_LAYOUT_CANDIDATES) do
    if layout.contextIndex ~= detectedLayout.contextIndex
      or layout.numBonusIndex ~= detectedLayout.numBonusIndex then
      layouts[#layouts + 1] = layout
    end
  end
  for _, layout in ipairs(layouts) do
    local merged = encodeDungeonPreviewOnPartsWithLayout(parts, expectedCtx, targetTrack, layout)
    if merged then
      local rebuilt = rebuildItemLink(link, merged)
      if rebuilt and dungeonEncodedLinkPassesChecks(rebuilt, expectedCtx, targetTrack) then
        primeItemInfo(rebuilt, tonumber(merged[2]))
        return rebuilt
      end
    end
  end
  return nil
end

local function applyPresetUpgradeEncoding(link, expectedCtx, targetTrack)
  if not link then
    return nil
  end
  local parts = splitItemPayload(link)
  if not parts then
    return nil
  end
  parts = padItemParts(parts, 16)
  local detectedLayout = getUpgradeFieldLayout(parts)
  local layouts = { detectedLayout }
  for _, layout in ipairs(UPGRADE_LAYOUT_CANDIDATES) do
    if layout.contextIndex ~= detectedLayout.contextIndex
      or layout.numBonusIndex ~= detectedLayout.numBonusIndex then
      layouts[#layouts + 1] = layout
    end
  end
  local bindBonuses = collectBindBonusesFromParts(parts) or {}
  for i, layout in ipairs(layouts) do
    local merged = encodePresetUpgradeOnPartsWithLayout(
      parts,
      expectedCtx,
      targetTrack,
      layout,
      i == 1 and bindBonuses or {}
    )
    if merged then
      local rebuilt = rebuildItemLink(link, merged)
      if rebuilt then
        local crestBonusId = getPresetCrestBonusId(targetTrack)
        if not targetTrack or (crestBonusId and linkContainsBonusId(rebuilt, crestBonusId)) then
          primeItemInfo(rebuilt, tonumber(merged[2]))
          return rebuilt
        end
      end
    end
  end
  return nil
end

-- Raid/tier: preserve journal link structure; only patch creation context + crest bonus.
local function applyRaidLootPreviewEncoding(link, expectedCtx, targetTrack)
  if not link then
    return nil
  end
  local parts = splitItemPayload(link)
  if not parts or parts[1] ~= "item" then
    return nil
  end
  local layout = getUpgradeFieldLayout(parts)
  local crestId = getPresetCrestBonusId(targetTrack)
  if not crestId then
    return nil
  end

  if expectedCtx then
    parts[layout.contextIndex] = tostring(expectedCtx)
  end

  local numBonus = tonumber(parts[layout.numBonusIndex]) or 0
  if numBonus > 10 then
    numBonus = 0
  end

  local replaced = false
  if numBonus > 0 then
    for i = 1, numBonus do
      local idx = layout.firstBonusIndex + i - 1
      local bid = tonumber(parts[idx])
      if bid and NS.isCrestUpgradeBonusId(bid) then
        parts[idx] = tostring(crestId)
        replaced = true
        break
      end
    end
  end
  if not replaced then
    for i = layout.firstBonusIndex, #parts do
      local bid = tonumber(parts[i])
      if bid and NS.isCrestUpgradeBonusId(bid) then
        parts[i] = tostring(crestId)
        replaced = true
        break
      end
    end
  end
  if not replaced then
    numBonus = numBonus + 1
    parts[layout.numBonusIndex] = tostring(numBonus)
    parts[layout.firstBonusIndex + numBonus - 1] = tostring(crestId)
  end

  local rebuilt = rebuildItemLink(link, parts)
  if not rebuilt then
    return nil
  end
  primeItemInfo(rebuilt, tonumber(parts[2]))
  return rebuilt
end

local function replaceCrestBonusOnLink(link, bonusId)
  if not link or not bonusId or not NS.isCrestUpgradeBonusId then
    return nil
  end
  local parts = padItemParts(splitItemPayload(link), 14)
  if not parts then
    return nil
  end
  local bindBonuses = collectBindBonusesFromParts(parts) or {}
  local merged = {}
  for i = 1, 12 do
    merged[i] = parts[i] or ""
  end
  merged[13] = parts[13] or "0"
  local allBonuses = {}
  for _, bid in ipairs(bindBonuses) do
    allBonuses[#allBonuses + 1] = tostring(bid)
  end
  allBonuses[#allBonuses + 1] = tostring(bonusId)
  merged[14] = tostring(#allBonuses)
  for i, bid in ipairs(allBonuses) do
    merged[14 + i] = bid
  end
  local rebuilt = rebuildItemLink(link, merged)
  if not rebuilt then
    return nil
  end
  primeItemInfo(rebuilt, tonumber(merged[2]))
  return rebuilt
end

local function applyUpgradeBonusIdToLink(link, bonusId)
  if not link or not bonusId or not NS.isCrestUpgradeBonusId then
    return nil
  end
  return replaceCrestBonusOnLink(link, bonusId)
end

-- Same-item journal encoding only; never graft upgrade fields from another item.
local function linkHasExpectedCreationContext(link, targetIlvl, targetTrack, instanceKind, instanceId, instanceName)
  if not link or not targetIlvl or targetIlvl <= 0 then
    return false
  end
  local expectedCtx = getContextValueForIlvl(targetIlvl, instanceKind or "Dungeon", instanceId, instanceName, targetTrack)
  if not expectedCtx then
    return false
  end
  local parts = padItemParts(splitItemPayload(link), 14)
  if not parts then
    return false
  end
  local layout = getUpgradeFieldLayout(parts)
  return tonumber(parts[layout.contextIndex]) == expectedCtx
end

local function linkHasExpectedCrestBonus(link, targetTrack)
  if not link or not targetTrack then
    return false
  end
  local expectedBonus = getPresetCrestBonusId(targetTrack)
  return expectedBonus and linkContainsBonusId(link, expectedBonus) or false
end

local function getBareItemLink(itemID)
  if not itemID or not (C_Item and C_Item.GetItemLinkByID) then
    return nil
  end
  local ok, link = pcall(C_Item.GetItemLinkByID, itemID)
  if ok and link and link ~= "" then
    primeItemInfo(link, itemID)
    return link
  end
  return nil
end

local function dungeonEncodedLinkReady(link, targetTrack)
  if not link or not targetTrack or not linkHasOnlyExpectedCrestBonus(link, targetTrack) then
    return false
  end
  local linkTrack = getUpgradeTrackFromLink(link)
  if linkTrack then
    return trackLabelsMatch(linkTrack, targetTrack)
  end
  return true
end

local function buildDungeonLootPreviewLink(journalLink, itemID, expectedCtx, targetTrack, apiLink)
  if not itemID or not targetTrack or not expectedCtx then
    return nil
  end
  local baseLink = apiLink
  if (not baseLink or tonumber(baseLink:match("item:(%d+)")) ~= itemID)
    and journalLink and tonumber(journalLink:match("item:(%d+)")) == itemID then
    baseLink = journalLink
  end
  if not baseLink or tonumber(baseLink:match("item:(%d+)")) ~= itemID then
    return nil
  end

  local encoded = applyDungeonPreviewEncoding(baseLink, expectedCtx, targetTrack)
  if encoded and dungeonEncodedLinkPassesChecks(encoded, expectedCtx, targetTrack) then
    primeItemInfo(encoded, itemID)
    if dungeonEncodedLinkReady(encoded, targetTrack) then
      return encoded
    end
    return encoded
  end
  return nil
end

local function isSporefallLoot(instanceKind, instanceId, instanceName)
  return instanceKind == "Raid" and isSporefallInstance(instanceId, instanceName)
end

local function dungeonLootLinkStructurallyValid(link, itemID, targetIlvl, targetTrack, instanceKind, instanceId, instanceName)
  if not link or not itemID then
    return false
  end
  if tonumber(link:match("item:(%d+)")) ~= itemID then
    return false
  end
  if targetTrack then
    if linkHasOnlyExpectedCrestBonus(link, targetTrack) then
      return true
    end
    return false
  end
  return linkHasExpectedCreationContext(link, targetIlvl, targetTrack, instanceKind, instanceId, instanceName)
end

local function buildJournalLootPreviewLink(journalLink, itemID, targetIlvl, targetTrack, instanceKind, instanceId, instanceName, apiLink)
  if not itemID or not targetIlvl or targetIlvl <= 0 then
    return nil
  end
  local kind = instanceKind or "Dungeon"
  local expectedCtx = getContextValueForIlvl(targetIlvl, kind, instanceId, instanceName, targetTrack)
  if not expectedCtx then
    return nil
  end

  -- Dungeon: patch API/journal upgrade encoding in-place (same crest model as raid).
  if kind == "Dungeon" and targetTrack then
    return buildDungeonLootPreviewLink(journalLink, itemID, expectedCtx, targetTrack, apiLink)
  end

  if not journalLink then
    return nil
  end

  local journalParts = splitItemPayload(journalLink)
  if not journalParts or journalParts[1] ~= "item" then
    journalParts = nil
  else
    journalParts = padItemParts(journalParts, 16)
  end

  if journalParts and tostring(journalParts[2]) ~= tostring(itemID) then
    -- Tier tokens: keep journal upgrade/bind encoding, swap only the item id.
    journalParts[2] = tostring(itemID)
    local swapped = rebuildItemLink(journalLink, journalParts)
    if swapped then
      journalLink = swapped
      journalParts = padItemParts(splitItemPayload(journalLink), 16)
    end
  end

  if not journalParts or journalParts[1] ~= "item" or tostring(journalParts[2]) ~= tostring(itemID) then
    local fallbackLink = journalLink
    if C_Item and C_Item.GetItemLinkByID then
      local ok, base = pcall(C_Item.GetItemLinkByID, itemID)
      if ok and base and base ~= "" then
        fallbackLink = base
      end
    end
    journalParts = padItemParts(splitItemPayload(fallbackLink), 16)
    if not journalParts or journalParts[1] ~= "item" or tostring(journalParts[2]) ~= tostring(itemID) then
      return nil
    end
    journalLink = fallbackLink
  end

  local rebuilt = applyPresetUpgradeEncoding(journalLink, expectedCtx, targetTrack)
  if not rebuilt then
    return nil
  end

  primeItemInfo(rebuilt, itemID)
  return rebuilt
end

local function readLinkIlvl(link, itemID)
  if not link then
    return 0
  end
  primeItemInfo(link, itemID or tonumber(link:match("item:(%d+)")))
  local ilvl = getItemIlvl(link)
  if ilvl and ilvl > 0 then
    return ilvl
  end
  if C_Item and C_Item.GetDetailedItemLevelInfo then
    ilvl = C_Item.GetDetailedItemLevelInfo(link)
    if ilvl and ilvl > 0 then
      return ilvl
    end
  end
  return 0
end

local function markTrustedPreviewLink(itemID, targetIlvl, targetTrack, link)
  if not itemID or not targetIlvl or not link then
    return
  end
  local perItem = authoritativePreviewCache[itemID]
  if not perItem then
    perItem = {}
    authoritativePreviewCache[itemID] = perItem
  end
  perItem[previewTrackCacheKey(targetIlvl, targetTrack)] = link
end

local function isTrustedPreviewLink(itemID, targetIlvl, targetTrack, link)
  if not itemID or not targetIlvl or not link then
    return false
  end
  local perItem = authoritativePreviewCache[itemID]
  return perItem and perItem[previewTrackCacheKey(targetIlvl, targetTrack)] == link
end

local function registerResolvedPreviewLink(itemID, link, instanceKind, ilvlOverride, targetTrack, forceIlvlOverride)
  if not itemID or not link then
    return
  end
  local measured = readLinkIlvl(link, itemID)
  local ilvl = measured > 0 and measured or (ilvlOverride or 0)
  if forceIlvlOverride and ilvlOverride and ilvlOverride > 0 then
    ilvl = ilvlOverride
  elseif measured > 0 and ilvlOverride and ilvlOverride > 0 and measured ~= ilvlOverride then
    ilvl = measured
  end
  if not ilvl or ilvl <= 0 then
    return
  end

  local perItem = itemIlvlPreviewCache[itemID]
  if not perItem then
    perItem = {}
    itemIlvlPreviewCache[itemID] = perItem
  end
  local actualTrack = getUpgradeTrackFromLink(link)
  local cacheTrack = actualTrack or targetTrack
  if cacheTrack or not AMBIGUOUS_TRACK_ILVLS[ilvl] then
    perItem[previewTrackCacheKey(ilvl, cacheTrack)] = link
  end
  if not AMBIGUOUS_TRACK_ILVLS[ilvl] and not targetTrack then
    perItem[previewTrackCacheKey(ilvl, nil)] = link
  end
end

getContextValueForIlvl = function(targetIlvl, instanceKind, instanceId, instanceName, targetTrack)
  local enumName
  local kind = instanceKind or "Dungeon"
  if targetTrack and not isSporefallInstance(instanceId, instanceName) then
    if kind == "Dungeon" or kind == "Raid" then
      -- Per-rank contexts distinguish Myth 1-6; RaidMythic alone cannot.
      enumName = getPresetDungeonContextEnum(targetTrack)
    end
  end
  if not enumName then
    enumName = getStaticContextForIlvl(targetIlvl, kind, instanceId, instanceName)
  end
  if not enumName then
    return nil
  end
  return getCreationContextValue(enumName, CONTEXT_ENUM_FALLBACK[enumName])
end

previewLinkPassesTrackCheck = function(link, targetIlvl, targetTrack, instanceKind, instanceId, instanceName)
  if not targetTrack then
    return true
  end
  if linkHasExpectedCrestBonus(link, targetTrack) then
    return true
  end
  local linkTrack = getUpgradeTrackFromLink(link)
  if linkTrack then
    return trackLabelsMatch(linkTrack, targetTrack)
  end
  return false
end

local function lootPreviewLinkMatchesPresetTrack(link, targetTrack)
  if not link or not targetTrack then
    return true
  end
  if linkHasExpectedCrestBonus(link, targetTrack) then
    return true
  end
  local linkTrack = getUpgradeTrackFromLink(link)
  return linkTrack and trackLabelsMatch(linkTrack, targetTrack) or false
end

local function lootPreviewHasScoringStats(link, itemID)
  if not link or not NS.statsFromItemLink then
    return false
  end
  if itemID then
    local linkItemID = tonumber(link:match("item:(%d+)"))
    if linkItemID and linkItemID ~= itemID then
      return false
    end
  end
  return NS.statsFromItemLink(link) ~= nil
end

local function lootPreviewAcceptableForUse(link, itemID, targetIlvl, targetTrack, instanceKind, instanceId, instanceName)
  if not link or tonumber(link:match("item:(%d+)")) ~= itemID then
    return false
  end
  if isSporefallLoot(instanceKind, instanceId, instanceName) and not targetTrack then
    if lootPreviewHasScoringStats(link, itemID) then
      return true
    end
    local measured = readLinkIlvl(link, itemID)
    return measured > 0 and (not targetIlvl or targetIlvl <= 0 or measured == targetIlvl)
  end
  return dungeonLootLinkStructurallyValid(link, itemID, targetIlvl, targetTrack, instanceKind, instanceId, instanceName)
end

local function apiLootLinkAcceptable(link, itemID, targetIlvl, targetTrack, instanceKind, instanceId, instanceName)
  if not link or not targetIlvl or targetIlvl <= 0 then
    return false
  end
  if itemID then
    local linkItemID = tonumber(link:match("item:(%d+)"))
    if linkItemID and linkItemID ~= itemID then
      return false
    end
  end
  local kind = instanceKind or "Dungeon"
  primeItemInfo(link, itemID or tonumber(link:match("item:(%d+)")))
  if kind == "Dungeon" and targetTrack and linkHasExpectedCrestBonus(link, targetTrack) then
    return true
  end
  if isSporefallLoot(kind, instanceId, instanceName) and not targetTrack then
    return lootPreviewAcceptableForUse(link, itemID, targetIlvl, targetTrack, kind, instanceId, instanceName)
  end
  if targetTrack and not lootPreviewLinkMatchesPresetTrack(link, targetTrack) then
    return false
  end
  if linkHasExpectedCreationContext(link, targetIlvl, targetTrack, kind, instanceId, instanceName)
    and (not targetTrack or linkHasExpectedCrestBonus(link, targetTrack)) then
    if lootPreviewHasScoringStats(link, itemID) then
      return true
    end
    if targetTrack and getLootPresetCrestStep(targetTrack) then
      return true
    end
  end
  if lootPreviewHasScoringStats(link, itemID) then
    local measured = readLinkIlvl(link, itemID)
    if measured > 0 and measured ~= targetIlvl and measured >= 200 then
      return false
    end
    return previewLinkPassesTrackCheck(link, targetIlvl, targetTrack, kind, instanceId, instanceName)
  end
  local measured = readLinkIlvl(link, itemID)
  if measured > 0 and measured ~= targetIlvl then
    return false
  end
  return previewLinkPassesTrackCheck(link, targetIlvl, targetTrack, kind, instanceId, instanceName)
end

local function lootPreviewLinkMatchesTarget(link, itemID, targetIlvl, targetTrack, instanceKind, instanceId, instanceName, _journalLink)
  return apiLootLinkAcceptable(link, itemID, targetIlvl, targetTrack, instanceKind, instanceId, instanceName)
end

local function acceptsPreviewLinkForTarget(link, targetIlvl, targetTrack, itemID, instanceKind, instanceId, instanceName)
  return lootPreviewLinkMatchesTarget(link, itemID, targetIlvl, targetTrack, instanceKind, instanceId, instanceName)
end

local function previewLinkUsableForScoring(link, targetIlvl, targetTrack, itemID, instanceKind, instanceId, instanceName)
  if lootPreviewAcceptableForUse(link, itemID, targetIlvl, targetTrack, instanceKind, instanceId, instanceName) then
    return true
  end
  if acceptsPreviewLinkForTarget(link, targetIlvl, targetTrack, itemID, instanceKind, instanceId, instanceName) then
    return true
  end
  return false
end

-- Midnight S1 ilvl -> preferred ItemCreationContext (dungeon / raid).
local STATIC_DUNGEON_ILVL_CONTEXT = {
  [246] = "DungeonMythic",
  [250] = "ChallengeMode_1",
  [253] = "ChallengeMode_2",
  [256] = "ChallengeMode_3",
  [259] = "ChallengeMode_4",
  [263] = "DungeonBonus_1",
  [266] = "DungeonBonus_2",
  [269] = "DungeonBonus_3",
  [272] = "DungeonBonus_4",
  [276] = "DungeonBonus_5",
  [279] = "DungeonBonus_6",
  [282] = "DungeonBonus_7",
  [285] = "DungeonBonus_8",
  [289] = "DungeonBonus_9",
}

-- Shared ilvls map to different creation contexts depending on track.
local PRESET_DUNGEON_CONTEXT = {
  champion_1 = "DungeonMythic",
  champion_2 = "ChallengeMode_1",
  champion_3 = "ChallengeMode_2",
  champion_4 = "ChallengeMode_3",
  champion_5 = "DungeonLevelUp_Champion5",
  champion_6 = "DungeonLevelUp_Champion6",
  hero_1 = "ChallengeMode_4",
  hero_2 = "DungeonBonus_1",
  hero_3 = "DungeonBonus_2",
  hero_4 = "DungeonBonus_3",
  hero_5 = "DungeonLevelUp_Hero5",
  hero_6 = "DungeonLevelUp_Hero6",
  myth_1 = "DungeonBonus_4",
  myth_2 = "DungeonBonus_5",
  myth_3 = "DungeonBonus_6",
  myth_4 = "DungeonBonus_7",
  myth_5 = "DungeonBonus_8",
  myth_6 = "DungeonBonus_9",
}

trackToPresetKey = function(track)
  local normalized = (track or ""):lower()
  local tier, rank = normalized:match("([a-z]+)%s*(%d+)")
  if tier and rank then
    return tier .. "_" .. rank
  end
  return normalized:gsub("%s+", "_"):gsub("/.*", "")
end

getPresetDungeonContextEnum = function(targetTrack)
  if not targetTrack then
    return nil
  end
  return PRESET_DUNGEON_CONTEXT[trackToPresetKey(targetTrack)]
end

local STATIC_RAID_ILVL_CONTEXT = {
  [246] = "RaidNormal",
  [250] = "RaidNormal",
  [253] = "RaidNormal",
  [256] = "RaidNormal",
  [259] = "RaidNormal",
  [263] = "RaidHeroic",
  [266] = "RaidHeroic",
  [269] = "RaidHeroic",
  [272] = "RaidMythic",
  [276] = "RaidMythic",
  [279] = "RaidMythic",
  [282] = "RaidMythic",
  [285] = "RaidMythic",
  [289] = "RaidMythic",
}

local STATIC_SPOREFALL_ILVL_CONTEXT = {
  [259] = "RaidNormal",
  [272] = "RaidMythic",
  [285] = "RaidMythic",
  [298] = "RaidMythic",
}

-- Midnight S1 upgrade track item levels (ranks 1/6 through 6/6).
local UPGRADE_TRACK_ILVLS = {
  Champion = { 246, 250, 253, 256, 259, 263 },
  Hero = { 259, 263, 266, 269, 272, 276 },
  Myth = { 272, 276, 279, 282, 285, 289 },
}

local UPGRADE_TRACK_ORDER = { "Champion", "Hero", "Myth" }

local function formatPresetLabel(track, ilvl)
  if track and track ~= "" and ilvl and ilvl > 0 then
    return string.format("%s · ilvl %d", track, math.floor(ilvl))
  end
  return track or "Unknown"
end

getCreationContextValue = function(enumName, fallback)
  if Enum and Enum.ItemCreationContext and Enum.ItemCreationContext[enumName] ~= nil then
    return Enum.ItemCreationContext[enumName]
  end
  return fallback
end

CONTEXT_ENUM_FALLBACK = {
  DungeonMythic = 23,
  ChallengeMode_1 = 16,
  ChallengeMode_2 = 33,
  ChallengeMode_3 = 34,
  ChallengeMode_4 = 87,
  ChallengeModeJackpot = 35,
  DungeonBonus_1 = 139,
  DungeonBonus_2 = 140,
  DungeonBonus_3 = 141,
  DungeonBonus_4 = 142,
  DungeonBonus_5 = 143,
  DungeonBonus_6 = 144,
  DungeonBonus_7 = 145,
  DungeonBonus_8 = 146,
  DungeonBonus_9 = 147,
  RaidNormal = 3,
  RaidFinder = 4,
  RaidHeroic = 5,
  RaidMythic = 6,
  DungeonLevelUp_Champion5 = 201,
  DungeonLevelUp_Champion6 = 202,
  DungeonLevelUp_Hero5 = 203,
  DungeonLevelUp_Hero6 = 204,
}

getStaticContextForIlvl = function(targetIlvl, instanceKind, instanceId, instanceName)
  if instanceKind == "Raid" and isSporefallInstance(instanceId, instanceName) then
    return STATIC_SPOREFALL_ILVL_CONTEXT[targetIlvl]
  end
  local map = instanceKind == "Raid" and STATIC_RAID_ILVL_CONTEXT or STATIC_DUNGEON_ILVL_CONTEXT
  return map[targetIlvl]
end

getPreviewLinkForContext = function(itemID, creationContext, enumName)
  if not itemID or not creationContext or not (C_Item and C_Item.GetDelvePreviewItemLink) then
    return nil
  end
  local ctx = creationContext
  if enumName and Enum and Enum.ItemCreationContext and Enum.ItemCreationContext[enumName] ~= nil then
    ctx = Enum.ItemCreationContext[enumName]
  end
  local ok, link = pcall(C_Item.GetDelvePreviewItemLink, itemID, ctx)
  if ok and type(link) == "string" and link ~= "" then
    primeItemInfo(link, itemID)
    return link
  end
  return nil
end

local function previewLinkCacheKey(itemID, targetIlvl, targetTrack, instanceKind, instanceId, instanceName)
  local kind = instanceKind or "Dungeon"
  return string.format(
    "%d:api:%d:%s:%s:%s",
    itemID or 0,
    targetIlvl or 0,
    kind,
    targetTrack or "",
    isSporefallInstance(instanceId, instanceName) and "sf" or "std"
  )
end

local function clearPreviewCacheMiss(itemID, targetIlvl, targetTrack, instanceKind, instanceId, instanceName)
  if not itemID then
    return
  end
  previewLinkCache[previewLinkCacheKey(itemID, targetIlvl, targetTrack, instanceKind, instanceId, instanceName)] = nil
end

local function finalizeResolvedLootPreviewLink(itemID, scoreLink, displayLink, targetIlvl, targetTrack, instanceKind, instanceId, instanceName, expectedCtx)
  local kind = instanceKind or "Dungeon"
  previewContextHintCache[previewContextHintKey(targetIlvl, kind, targetTrack)] = expectedCtx
  registerResolvedPreviewLink(itemID, scoreLink, kind, targetIlvl, targetTrack)
  markTrustedPreviewLink(itemID, targetIlvl, targetTrack, scoreLink)
  previewLinkCache[previewLinkCacheKey(itemID, targetIlvl, targetTrack, kind, instanceId, instanceName)] = {
    score = scoreLink,
    display = displayLink or scoreLink,
  }
  return scoreLink, displayLink or scoreLink
end

local function pickLootDisplayPreviewLink(apiLink, scoreLink, itemID, targetIlvl, targetTrack, instanceKind, instanceId, instanceName)
  local kind = instanceKind or "Dungeon"
  if scoreLink and (kind == "Dungeon" or kind == "Raid") then
    return scoreLink
  end
  if apiLink and itemID and targetIlvl and targetIlvl > 0
    and tonumber(apiLink:match("item:(%d+)")) == itemID
    and targetTrack and linkHasExpectedCrestBonus(apiLink, targetTrack)
    and readLinkIlvl(apiLink, itemID) == targetIlvl then
    return apiLink
  end
  return scoreLink
end

local function resolveApiLootPreviewLink(itemID, targetIlvl, targetTrack, instanceKind, instanceId, instanceName, journalLink)
  if not itemID or not targetIlvl or targetIlvl <= 0 then
    return nil, nil
  end

  local kind = instanceKind or "Dungeon"
  local cacheKey = previewLinkCacheKey(itemID, targetIlvl, targetTrack, kind, instanceId, instanceName)
  if previewLinkCache[cacheKey] ~= nil then
    local cached = previewLinkCache[cacheKey]
    if type(cached) == "table" then
      local scoreOk = cached.score
        and lootPreviewAcceptableForUse(cached.score, itemID, targetIlvl, targetTrack, kind, instanceId, instanceName)
      if scoreOk then
        return cached.score, cached.display or cached.score
      end
      previewLinkCache[cacheKey] = nil
    else
      return nil, nil
    end
  end

  primeItemInfo(journalLink, itemID)

  local expectedCtx = getContextValueForIlvl(targetIlvl, kind, instanceId, instanceName, targetTrack)
  if not expectedCtx then
    return nil, nil
  end

  local contextEnumName
  if kind == "Dungeon" or kind == "Raid" then
    contextEnumName = getPresetDungeonContextEnum(targetTrack)
  end
  if not contextEnumName then
    contextEnumName = getStaticContextForIlvl(targetIlvl, kind, instanceId, instanceName)
  end
  local apiLink = getPreviewLinkForContext(itemID, expectedCtx, contextEnumName)

  if isSporefallLoot(kind, instanceId, instanceName) and not targetTrack then
    local baseLink = apiLink or journalLink or getBareItemLink(itemID)
    if baseLink then
      local built = applyPresetUpgradeEncoding(baseLink, expectedCtx, nil)
      if built then
        return finalizeResolvedLootPreviewLink(
          itemID, built, built, targetIlvl, targetTrack, kind, instanceId, instanceName, expectedCtx
        )
      end
    end
    return nil, nil
  end

  local built
  if journalLink or kind == "Dungeon" then
    built = buildJournalLootPreviewLink(
      journalLink,
      itemID,
      targetIlvl,
      targetTrack,
      kind,
      instanceId,
      instanceName,
      apiLink
    )
  end

  if built and (kind == "Dungeon" or kind == "Raid" or lootPreviewAcceptableForUse(built, itemID, targetIlvl, targetTrack, kind, instanceId, instanceName)) then
    local displayLink = pickLootDisplayPreviewLink(apiLink, built, itemID, targetIlvl, targetTrack, kind, instanceId, instanceName)
    return finalizeResolvedLootPreviewLink(
      itemID, built, displayLink, targetIlvl, targetTrack, kind, instanceId, instanceName, expectedCtx
    )
  end

  if apiLink and tonumber(apiLink:match("item:(%d+)")) == itemID and targetTrack then
    local merged
    if kind == "Dungeon" then
      merged = applyDungeonPreviewEncoding(apiLink, expectedCtx, targetTrack)
    else
      merged = applyPresetUpgradeEncoding(apiLink, expectedCtx, targetTrack)
    end
    if merged and lootPreviewAcceptableForUse(merged, itemID, targetIlvl, targetTrack, kind, instanceId, instanceName) then
      return finalizeResolvedLootPreviewLink(
        itemID, merged, merged, targetIlvl, targetTrack, kind, instanceId, instanceName, expectedCtx
      )
    end
  end

  return nil, nil
end

local function resolveLootJournalBase(ref, itemID, journalLink)
  if ref and ref.token_link and ref.item_id == itemID then
    -- Tier: use the compact piece link grafted from the token (upgrade encoding already aligned).
    if ref.link and tonumber(ref.link:match("item:(%d+)")) == itemID then
      return ref.link
    end
    return ref.token_link
  end
  if journalLink then
    return journalLink
  end
  if not ref then
    return nil
  end
  if ref.link then
    local linkItemID = tonumber(ref.link:match("item:(%d+)"))
    if linkItemID == itemID then
      return ref.link
    end
  end
  if ref.token_link and NS.resolveArmorTokenLootLink then
    local tokenID = ref.token_item_id or tonumber(ref.token_link:match("item:(%d+)"))
    if tokenID then
      local _, classToken = UnitClass("player")
      local pieceLink = NS.resolveArmorTokenLootLink(tokenID, ref.token_link, classToken)
      if pieceLink then
        return pieceLink
      end
    end
  end
  return ref.link
end

local function applyLootPreviewToRef(ref, journalLink, itemID, targetIlvl, targetTrack, instanceKind, instanceId, instanceName)
  local journalBase = resolveLootJournalBase(ref, itemID, journalLink)
  local scoreLink, displayLink = resolveApiLootPreviewLink(
    itemID,
    targetIlvl,
    targetTrack,
    instanceKind,
    instanceId,
    instanceName,
    journalBase or ref.link
  )
  if not scoreLink then
    return nil, nil
  end
  ref.resolved_link = scoreLink
  ref.preview_link = displayLink or scoreLink
  return scoreLink, displayLink
end

local function findPreviewLinkForIlvlWithJournal(journalLink, itemID, targetIlvl, targetTrack, instanceKind, instanceId, instanceName)
  local scoreLink = resolveApiLootPreviewLink(
    itemID, targetIlvl, targetTrack, instanceKind, instanceId, instanceName, journalLink
  )
  return scoreLink
end

local function syncLootPreviewMetadata(ref, previewPreset, scoreLink, displayLink)
  if not ref or ref.source ~= "loot" or not previewPreset or previewPreset.key == "journal" then
    return
  end
  local targetIlvl = getPreviewTargetIlvl(
    previewPreset.ilvl,
    ref.instance_id,
    ref.instance_name,
    ref.instance_kind
  )
  local targetTrack = getPreviewTargetTrack(
    previewPreset,
    ref.instance_id,
    ref.instance_name,
    ref.instance_kind
  )
  local itemID = ref.item_id or tonumber(ref.link and ref.link:match("item:(%d+)"))
  if not scoreLink or not itemID then
    return
  end
  ref.preview_ilvl = targetIlvl
  ref.upgrade_track = targetTrack
  ref.preview_link = pickLootDisplayPreviewLink(displayLink, scoreLink, itemID, targetIlvl, targetTrack, ref.instance_kind, ref.instance_id, ref.instance_name) or scoreLink
end

local function resolveLootPreviewForRef(ref, previewPreset, journalInstanceId, instanceNameOverride)
  if not ref or not ref.link then
    return nil, nil
  end
  if ref.source ~= "loot" or not previewPreset or previewPreset.key == "journal" or not previewPreset.ilvl or previewPreset.ilvl <= 0 then
    return ref.link, ref.link
  end
  local itemID = ref.item_id or tonumber(ref.link:match("item:(%d+)"))
  if not itemID then
    return nil, nil
  end
  local instanceId = journalInstanceId or ref.instance_id
  local instanceName = instanceNameOverride or ref.instance_name
  local targetIlvl = getPreviewTargetIlvl(previewPreset.ilvl, instanceId, instanceName, ref.instance_kind)
  local targetTrack = getPreviewTargetTrack(previewPreset, instanceId, instanceName, ref.instance_kind)
  local scoreLink, displayLink = applyLootPreviewToRef(
    ref, nil, itemID, targetIlvl, targetTrack, ref.instance_kind, instanceId, instanceName
  )
  syncLootPreviewMetadata(ref, previewPreset, scoreLink, displayLink)
  return scoreLink, displayLink
end

local function warmPreviewTemplates(refs, previewPreset)
  if not previewPreset or previewPreset.key == "journal" or not previewPreset.ilvl or previewPreset.ilvl <= 0 then
    return
  end

  for _, ref in ipairs(refs or {}) do
    if ref.source == "loot" and ref.link then
      local itemID = ref.item_id or tonumber(ref.link:match("item:(%d+)"))
      if itemID then
        local targetIlvl = getPreviewTargetIlvl(previewPreset.ilvl, ref.instance_id, ref.instance_name, ref.instance_kind)
        local targetTrack = getPreviewTargetTrack(previewPreset, ref.instance_id, ref.instance_name, ref.instance_kind)
        local trusted = isTrustedPreviewLink(itemID, targetIlvl, targetTrack, ref.resolved_link)
        if not trusted and not (ref.resolved_link and previewLinkUsableForScoring(
            ref.resolved_link,
            targetIlvl,
            targetTrack,
            itemID,
            ref.instance_kind,
            ref.instance_id,
            ref.instance_name
          )) then
          clearPreviewCacheMiss(itemID, targetIlvl, targetTrack, ref.instance_kind, ref.instance_id, ref.instance_name)
          resolveLootPreviewForRef(ref, previewPreset)
        end
      end
    end
  end
end

local function getInstanceKind(journalInstanceId, fallbackKind)
  if fallbackKind then
    return fallbackKind
  end
  if EJ_GetInstanceInfo then
    local _, _, _, _, _, _, _, _, _, _, isRaid = EJ_GetInstanceInfo(journalInstanceId)
    if isRaid then
      return "Raid"
    end
  end
  return "Dungeon"
end

resolvePreviewLootLink = function(journalInstanceId, itemID, previewPreset, instanceKind, journalLink, instanceName, ref)
  if not itemID or not previewPreset or previewPreset.key == "journal" or not previewPreset.key then
    return nil
  end
  if previewPreset.ilvl and previewPreset.ilvl > 0 then
    if ref then
      local scoreLink = resolveLootPreviewForRef(ref, previewPreset, journalInstanceId, instanceName)
      return scoreLink
    end
    local targetIlvl = getPreviewTargetIlvl(previewPreset.ilvl, journalInstanceId, instanceName, instanceKind)
    local targetTrack = getPreviewTargetTrack(previewPreset, journalInstanceId, instanceName, instanceKind)
    return findPreviewLinkForIlvlWithJournal(
      journalLink,
      itemID,
      targetIlvl,
      targetTrack,
      instanceKind,
      journalInstanceId,
      instanceName
    )
  end
  return nil
end

local function resolveLootRefLink(ref, previewPreset)
  if not ref or not ref.link then
    return nil
  end
  if ref.source ~= "loot" or not previewPreset or previewPreset.key == "journal" then
    return ref.link
  end
  local scoreLink = resolveLootPreviewForRef(ref, previewPreset)
  return scoreLink
end

local function buildLootUpgradePresets()
  local presets = {}

  for _, trackName in ipairs(UPGRADE_TRACK_ORDER) do
    local ilvls = UPGRADE_TRACK_ILVLS[trackName]
    for rank = 1, 6 do
      local track = string.format("%s %d", trackName, rank)
      local ilvl = ilvls[rank]
      table.insert(presets, {
        key = trackToPresetKey(track),
        track = track,
        ilvl = ilvl,
        label = formatPresetLabel(track, ilvl),
      })
    end
  end

  return presets
end

local function getLootInfoByIndex(index)
  if C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex then
    return C_EncounterJournal.GetLootInfoByIndex(index)
  end
  if EJ_GetLootInfoByIndex then
    local name, icon, slotFilter, armorType, itemID, link, encounterID = EJ_GetLootInfoByIndex(index)
    return { name = name, itemID = itemID, link = link, encounterID = encounterID }
  end
  return nil
end

local function resolveLootEntryLink(info)
  if info.link and info.link ~= "" then
    return info.link
  end
  local itemID = info.itemID
  if not itemID then
    return nil
  end
  primeItemInfo(nil, itemID)
  if C_Item and C_Item.GetItemLinkByID then
    local ok, link = pcall(C_Item.GetItemLinkByID, itemID)
    if ok and link and link ~= "" then
      return link
    end
  end
  local _, link = GetItemInfo(itemID)
  if link and link ~= "" then
    return link
  end
  return nil
end

local function requestLootItemData(itemID)
  if not itemID then
    return
  end
  if C_Item and C_Item.RequestLoadItemDataByID then
    if not C_Item.IsItemDataCachedByID or not C_Item.IsItemDataCachedByID(itemID) then
      C_Item.RequestLoadItemDataByID(itemID)
    end
  elseif GetItemInfo then
    GetItemInfo(itemID)
  end
end

isLootLinkPendingData = function(link)
  local itemID = tonumber(link and link:match("item:(%d+)"))
  if not itemID or not C_Item or not C_Item.IsItemDataCachedByID then
    return false
  end
  if C_Item.IsItemDataCachedByID(itemID) then
    return false
  end
  requestLootItemData(itemID)
  return true
end

function NS.getLootUpgradePresets()
  if not lootUpgradePresetsCache then
    lootUpgradePresetsCache = buildLootUpgradePresets()
    NS.LOOT_UPGRADE_PRESETS = lootUpgradePresetsCache
  end
  return lootUpgradePresetsCache
end

NS.LOOT_UPGRADE_PRESETS = {}

function NS.invalidateLootUpgradePresets()
  lootUpgradePresetsCache = nil
  clearPreviewCaches()
  invalidateEjDungeonLookup()
  NS.LOOT_UPGRADE_PRESETS = NS.getLootUpgradePresets()
end

function NS.getLootUpgradePreset(keyOrIlvl)
  local presets = NS.getLootUpgradePresets()
  if type(keyOrIlvl) == "string" and (keyOrIlvl == "" or keyOrIlvl == "journal") then
    keyOrIlvl = NS.DEFAULT_LOOT_UPGRADE_KEY
  end
  if type(keyOrIlvl) == "string" and keyOrIlvl ~= "" then
    local searchKey = keyOrIlvl:lower():gsub("%s+", "_")
    for _, preset in ipairs(presets) do
      if preset.key == searchKey then
        return preset
      end
    end
    for _, preset in ipairs(presets) do
      if preset.key and preset.key:find(searchKey, 1, true) then
        return preset
      end
    end
    local trackPrefix, trackRank = searchKey:match("^(%a+)_(%d+)$")
    if trackPrefix and trackRank then
      trackRank = tonumber(trackRank)
      for _, preset in ipairs(presets) do
        if preset.track then
          local presetTrack = preset.track:lower()
          if presetTrack:find(trackPrefix, 1, true) then
            local presetRank = tonumber(presetTrack:match("(%d+)[^%d]*$"))
            if presetRank == trackRank then
              return preset
            end
          end
        end
      end
    end
  end
  local numeric = tonumber(keyOrIlvl)
  if numeric and numeric > 0 then
    for _, preset in ipairs(presets) do
      if preset.ilvl == numeric then
        return preset
      end
    end
  end
  return presets[1] or NS.getLootUpgradePreset(NS.DEFAULT_LOOT_UPGRADE_KEY)
end

function NS.syncLootUpgradeKey(savedKey)
  if savedKey == "journal" then
    savedKey = NS.DEFAULT_LOOT_UPGRADE_KEY
  end
  local preset = NS.getLootUpgradePreset(savedKey)
  return preset and preset.key or NS.DEFAULT_LOOT_UPGRADE_KEY
end

function NS.resolveLootPreviewPreset(scanOpts)
  if scanOpts and scanOpts.preset then
    if scanOpts.preset.key == "journal" then
      return NS.getLootUpgradePreset(NS.DEFAULT_LOOT_UPGRADE_KEY)
    end
    return scanOpts.preset
  end
  if scanOpts and scanOpts.upgrade_key then
    return NS.getLootUpgradePreset(scanOpts.upgrade_key)
  end
  return NS.getLootUpgradePreset(NS.DEFAULT_LOOT_UPGRADE_KEY)
end

local function collectLootRefsForInstance(journalInstanceId, globalSeen, expectedName, specKey, instanceKind, previewPreset, collectOpts)
  local refs = {}
  local seen = globalSeen or {}
  local meta = { needs_ej_loot = false, pending_item_ids = {} }
  local pendingSeen = {}
  collectOpts = collectOpts or {}

  NS.ensureEncounterJournalLoaded()
  if not (EJ_SelectTier and EJ_SelectInstance and EJ_GetNumLoot) then
    return refs, nil, meta
  end

  EJ_SelectTier(getCurrentEjTierId())
  EJ_SelectInstance(journalInstanceId)
  if not collectOpts.skipLootFilterApply then
    applyEncounterJournalPlayerLootFilters()
  end
  local resolvedKind = getInstanceKind(journalInstanceId, instanceKind)

  local instanceName = expectedName
  if EJ_GetInstanceInfo then
    local selectedName = select(1, EJ_GetInstanceInfo(journalInstanceId))
    if selectedName and selectedName ~= "" then
      instanceName = selectedName
      if expectedName and not namesLikelyMatch(expectedName, selectedName) then
        return refs, string.format(
          "Instance mismatch: expected '%s' but journal returned '%s'. Re-select from the dropdown.",
          expectedName,
          selectedName
        ), meta
      end
    end
  end

  local function appendLootAtIndex(i)
    local info = getLootInfoByIndex(i)
    if not info or not info.itemID then
      return
    end
    if isSkippableOtherLoot(info, info.itemID) then
      return
    end
    local journalLink = resolveLootEntryLink(info)
    if not journalLink then
      if not pendingSeen[info.itemID] then
        pendingSeen[info.itemID] = true
        table.insert(meta.pending_item_ids, info.itemID)
        requestLootItemData(info.itemID)
      end
      return
    end
    local added, pending, pendingIds = tryAddInstanceLootRef(
      refs, seen, journalLink, info, journalInstanceId, instanceName, resolvedKind, specKey, previewPreset
    )
    if not added and pending then
      local ids = pendingIds or { info.itemID }
      for _, itemID in ipairs(ids) do
        if not pendingSeen[itemID] then
          pendingSeen[itemID] = true
          table.insert(meta.pending_item_ids, itemID)
          requestLootItemData(itemID)
        end
      end
    end
  end

  local function collectLootForCurrentSelection()
    local numLoot = EJ_GetNumLoot() or 0
    for i = 1, numLoot do
      appendLootAtIndex(i)
    end
    return numLoot
  end

  local totalLootEntries = collectLootForCurrentSelection()

  if totalLootEntries == 0 and EJ_GetEncounterInfoByIndex and EJ_SelectEncounter then
    local encIndex = 1
    while true do
      local encName, _, encID = EJ_GetEncounterInfoByIndex(encIndex)
      if not encName or not encID then
        break
      end
      EJ_SelectEncounter(encID)
      totalLootEntries = totalLootEntries + collectLootForCurrentSelection()
      encIndex = encIndex + 1
    end
    EJ_SelectInstance(journalInstanceId)
  end

  if totalLootEntries == 0 and (#refs == 0) and not (meta.pending_item_ids and #meta.pending_item_ids > 0) then
    if not EJ_IsLootListOutOfDate or EJ_IsLootListOutOfDate() then
      meta.needs_ej_loot = true
    end
  end

  if #meta.pending_item_ids == 0 then
    meta.pending_item_ids = nil
  end
  return refs, instanceName, meta
end

local function mergeLootRefList(target, source)
  for _, ref in ipairs(source or {}) do
    table.insert(target, ref)
  end
end

local function trackPendingLootItemIds(runner, pendingItemIds)
  if not pendingItemIds or #pendingItemIds == 0 then
    return false
  end
  runner.pendingItemIds = runner.pendingItemIds or {}
  for _, itemID in ipairs(pendingItemIds) do
    runner.pendingItemIds[itemID] = true
    requestLootItemData(itemID)
  end
  runner.waiting = "items"
  runner.itemWaitAttempts = (runner.itemWaitAttempts or 0) + 1
  return true
end

function NS.beginEncounterJournalLootRunner(specKey, instanceId, instanceName, scanOpts)
  NS.ensureEncounterJournalLoaded()
  applyEncounterJournalPlayerLootFilters()

  local mode = (instanceId == NS.LOOT_ALL_INSTANCES) and "all" or "single"
  local runner = {
    cancelled = false,
    specKey = specKey,
    instanceId = instanceId,
    instanceName = instanceName,
    scanOpts = scanOpts or {},
    previewPreset = NS.resolveLootPreviewPreset(scanOpts),
    allRefs = {},
    seen = {},
    index = 1,
    waiting = nil,
    ejWaitAttempts = 0,
    itemWaitAttempts = 0,
    pendingItemIds = nil,
    statusNote = nil,
    mode = mode,
    instanceList = nil,
    lootFiltersApplied = true,
  }
  if mode == "all" then
    runner.instanceList = NS.collectEncounterJournalInstances()
  end
  return runner
end

local LOOT_COLLECT_OPTS = { skipLootFilterApply = true }

-- Returns: "complete", "continue", "wait_ej", "wait_items", or "cancelled".
function NS.pumpEncounterJournalLootRunner(runner, onStatus)
  if not runner or runner.cancelled then
    return "cancelled"
  end

  local previewPreset = runner.previewPreset

  if runner.mode == "single" then
    if onStatus then
      onStatus("Scanning instance loot…")
    end
    local instRefs, note, meta = collectLootRefsForInstance(
      runner.instanceId,
      runner.seen,
      runner.instanceName,
      runner.specKey,
      nil,
      previewPreset,
      LOOT_COLLECT_OPTS
    )
    if note and note:find("Instance mismatch", 1, true) then
      runner.statusNote = note
      mergeLootRefList(runner.allRefs, instRefs)
      return "complete"
    end
    if meta and meta.needs_ej_loot then
      runner.waiting = "ej"
      runner.ejWaitAttempts = (runner.ejWaitAttempts or 0) + 1
      if onStatus then
        onStatus("Waiting for journal loot data…")
      end
      if runner.ejWaitAttempts < 15 then
        return "wait_ej"
      end
      runner.waiting = nil
      runner.ejWaitAttempts = 0
    else
      runner.ejWaitAttempts = 0
    end
    mergeLootRefList(runner.allRefs, instRefs)
    if trackPendingLootItemIds(runner, meta and meta.pending_item_ids) then
      if onStatus then
        onStatus("Loading item details…")
      end
      if runner.itemWaitAttempts < 25 then
        return "wait_items"
      end
      runner.pendingItemIds = nil
      runner.itemWaitAttempts = 0
      runner.waiting = nil
    else
      runner.itemWaitAttempts = 0
    end
    return "complete"
  end

  local list = runner.instanceList or {}
  if runner.index > #list then
    return "complete"
  end

  local inst = list[runner.index]
  if onStatus then
    onStatus(string.format("Scanning loot %d/%d: %s…", runner.index, #list, inst.name))
  end

  local instRefs, note, meta = collectLootRefsForInstance(
    inst.id,
    runner.seen,
    inst.name,
    runner.specKey,
    inst.kind,
    previewPreset,
    LOOT_COLLECT_OPTS
  )
  if note and note:find("Instance mismatch", 1, true) then
    runner.statusNote = note
  end
  if meta and meta.needs_ej_loot then
    runner.waiting = "ej"
    runner.ejWaitAttempts = (runner.ejWaitAttempts or 0) + 1
    if onStatus then
      onStatus(string.format("Waiting for loot data: %s…", inst.name))
    end
    if runner.ejWaitAttempts < 15 then
      return "wait_ej"
    end
    runner.waiting = nil
    runner.ejWaitAttempts = 0
  else
    runner.ejWaitAttempts = 0
  end

  mergeLootRefList(runner.allRefs, instRefs)
  if trackPendingLootItemIds(runner, meta and meta.pending_item_ids) then
    runner.waitingInstanceIndex = runner.index
    if onStatus then
      onStatus("Loading item details…")
    end
    if runner.itemWaitAttempts < 25 then
      return "wait_items"
    end
    runner.pendingItemIds = nil
    runner.itemWaitAttempts = 0
    runner.waiting = nil
    runner.waitingInstanceIndex = nil
    runner.index = runner.index + 1
  else
    runner.itemWaitAttempts = 0
    runner.waitingInstanceIndex = nil
    runner.index = runner.index + 1
  end

  if runner.index <= #list then
    return "continue"
  end
  return "complete"
end

function NS.collectEncounterJournalLootRefs(instanceId, expectedName, specKey, scanOpts)
  local refs = {}
  if not instanceId then
    return refs, "Select a dungeon or raid first", nil
  end

  local previewPreset = NS.resolveLootPreviewPreset(scanOpts)
  local aggregateMeta = { needs_ej_loot = false, pending_item_ids = {} }
  local pendingSeen = {}

  local function mergeMeta(meta)
    if not meta then
      return
    end
    if meta.needs_ej_loot then
      aggregateMeta.needs_ej_loot = true
    end
    for _, itemID in ipairs(meta.pending_item_ids or {}) do
      if not pendingSeen[itemID] then
        pendingSeen[itemID] = true
        table.insert(aggregateMeta.pending_item_ids, itemID)
      end
    end
  end

  if instanceId == NS.LOOT_ALL_INSTANCES then
    local instances = NS.collectEncounterJournalInstances()
    if #instances == 0 then
      return refs, "No current-season instances found. Open the Encounter Journal (J), then try again.", aggregateMeta
    end
    local seen = {}
    for _, inst in ipairs(instances) do
      local instRefs, _, meta = collectLootRefsForInstance(inst.id, seen, inst.name, specKey, inst.kind, previewPreset)
      mergeMeta(meta)
      for _, ref in ipairs(instRefs) do
        table.insert(refs, ref)
      end
    end
    if #refs == 0 then
      return refs, "No loot found across instances (data may still be loading; try again).", aggregateMeta
    end
    if #aggregateMeta.pending_item_ids == 0 then
      aggregateMeta.pending_item_ids = nil
    end
    return refs, nil, aggregateMeta
  end

  local seen = {}
  local noteOrName
  local meta
  refs, noteOrName, meta = collectLootRefsForInstance(instanceId, seen, expectedName, specKey, nil, previewPreset)
  mergeMeta(meta)
  if type(noteOrName) == "string" and noteOrName:find("Instance mismatch", 1, true) then
    return refs, noteOrName, aggregateMeta
  end
  if #refs == 0 then
    return refs, "No loot found for this instance (data may still be loading; try again).", aggregateMeta
  end
  if #aggregateMeta.pending_item_ids == 0 then
    aggregateMeta.pending_item_ids = nil
  end
  return refs, nil, aggregateMeta
end

function NS.collectLootRefsForInstance(instanceId, globalSeen, expectedName, specKey, instanceKind, previewPreset)
  return collectLootRefsForInstance(instanceId, globalSeen, expectedName, specKey, instanceKind, previewPreset)
end

local UPGRADE_SLOT_IDS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 15, 16, 17 }

local function getCurrencyLabel(currencyID)
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if info and info.name then return info.name end
  end
  return "Currency " .. tostring(currencyID)
end

local function isCrestCurrencyId(currencyId)
  local set = NS.CREST_CURRENCY_ID_SET
  return currencyId and set and set[currencyId] == true
end

function NS.getCrestCurrencyBalance(currencyId)
  if not currencyId or not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then
    return 0
  end
  local info = C_CurrencyInfo.GetCurrencyInfo(currencyId)
  return (info and info.quantity) or 0
end

function NS.getCrestCurrencyBalances()
  local balances = {}
  for _, currencyId in ipairs(NS.CREST_CURRENCY_IDS or {}) do
    balances[currencyId] = NS.getCrestCurrencyBalance(currencyId)
  end
  return balances
end

function NS.formatCrestBalancesLine()
  local parts = {}
  for _, currencyId in ipairs(NS.CREST_CURRENCY_IDS or {}) do
    local qty = NS.getCrestCurrencyBalance(currencyId)
    local name = getCurrencyLabel(currencyId)
    name = name:gsub(" Dawncrests", ""):gsub(" Crests", ""):gsub(" Crest", "")
    parts[#parts + 1] = string.format("%s %d", name, qty or 0)
  end
  if #parts == 0 then
    return ""
  end
  return (NS.MSG_CREST_BALANCES_PREFIX or "Owned:") .. " " .. table.concat(parts, "  /  ")
end

local function clearItemUpgradeContext()
  if C_ItemUpgrade and C_ItemUpgrade.ClearItemUpgrade then
    pcall(C_ItemUpgrade.ClearItemUpgrade)
  end
end

local function findNextUpgradeLevelInfo(itemInfo)
  if not itemInfo or not itemInfo.upgradeLevelInfos then
    return nil
  end
  local targetLevel = itemInfo.currUpgrade and (itemInfo.currUpgrade + 1) or nil
  if targetLevel then
    for _, info in ipairs(itemInfo.upgradeLevelInfos) do
      if info.upgradeLevel == targetLevel then
        return info
      end
    end
  end
  return itemInfo.upgradeLevelInfos[1]
end

local function fetchItemUpgradeItemInfo(itemLocation)
  if not (C_ItemUpgrade and C_ItemUpgrade.GetItemUpgradeItemInfo) then
    return nil
  end
  if itemLocation then
    local ok, info = pcall(C_ItemUpgrade.GetItemUpgradeItemInfo, itemLocation)
    if ok and info then
      return info
    end
  end
  local ok, info = pcall(C_ItemUpgrade.GetItemUpgradeItemInfo)
  if ok and info then
    return info
  end
  return nil
end

local function extractCrestCostFromUpgradeInfo(itemInfo, expectedCurrencyId)
  if not itemInfo then
    return nil
  end

  local levelInfo = findNextUpgradeLevelInfo(itemInfo)
  if not levelInfo or not levelInfo.currencyCostsToUpgrade then
    return nil
  end

  local fallback
  for _, entry in ipairs(levelInfo.currencyCostsToUpgrade) do
    local currencyId = entry.currencyID or entry.currencyId
    if isCrestCurrencyId(currencyId) then
      local baseCost = NS.CREST_UPGRADE_COST_AMOUNT or 20
      local cost = entry.cost
      if cost == nil then
        cost = baseCost
      end
      local discounted = cost < baseCost or cost <= 0
      if entry.discountInfo then
        if entry.discountInfo.isDiscounted then
          discounted = true
        end
        if entry.discountInfo.doesCurrentCharacterMeetHighWatermark == true and cost <= 0 then
          discounted = true
        end
      end
      local info = {
        crest_cost = cost,
        crest_cost_base = baseCost,
        currency_id = currencyId,
        crest_discounted = discounted,
      }
      if expectedCurrencyId and currencyId == expectedCurrencyId then
        return info
      end
      if not fallback then
        fallback = info
      end
    end
  end
  return fallback
end

local function itemLocationCanUseUpgradeContext(itemLocation, link)
  if C_ItemUpgrade and C_ItemUpgrade.CanUpgradeItem then
    local canUpgrade = C_ItemUpgrade.CanUpgradeItem(itemLocation)
    if canUpgrade then
      return true
    end
  end
  if link and C_Item and C_Item.GetItemUpgradeInfo then
    local ok, upInfo = pcall(C_Item.GetItemUpgradeInfo, link)
    if ok and upInfo and upInfo.currentLevel and upInfo.maxLevel and upInfo.currentLevel < upInfo.maxLevel then
      return true
    end
  end
  return false
end

local function beginEquippedUpgradeContext(invSlot, link)
  if not invSlot or not ItemLocation then
    return nil
  end
  if NS.isItemUpgradeFrameOpen and NS.isItemUpgradeFrameOpen() then
    return nil
  end
  if not (C_ItemUpgrade and C_ItemUpgrade.GetItemUpgradeItemInfo) then
    return nil
  end
  local itemLocation = ItemLocation:CreateFromEquipmentSlot(invSlot)
  if not itemLocation or not itemLocation.IsValid or not itemLocation:IsValid() then
    return nil
  end
  if not itemLocationCanUseUpgradeContext(itemLocation, link) then
    return nil
  end

  if C_ItemUpgrade.SetItemUpgradeFromLocation then
    if not pcall(C_ItemUpgrade.SetItemUpgradeFromLocation, itemLocation) then
      clearItemUpgradeContext()
      return nil
    end
  end

  local itemInfo = fetchItemUpgradeItemInfo(itemLocation)
  if not itemInfo then
    clearItemUpgradeContext()
    return nil
  end
  return itemLocation, itemInfo
end

local function queryEquippedCrestCost(invSlot, link, expectedCurrencyId)
  local itemLocation, itemInfo = beginEquippedUpgradeContext(invSlot, link)
  if not itemInfo then
    return nil
  end

  local costInfo = extractCrestCostFromUpgradeInfo(itemInfo, expectedCurrencyId)
  if itemInfo.highWatermarkSlot then
    costInfo = costInfo or {}
    costInfo.high_watermark_slot = itemInfo.highWatermarkSlot
  end
  if itemInfo.currUpgrade and itemInfo.maxUpgrade then
    costInfo = costInfo or {}
    costInfo.current_level = itemInfo.currUpgrade
    costInfo.max_level = itemInfo.maxUpgrade
    costInfo.steps_remaining = math.max(0, itemInfo.maxUpgrade - itemInfo.currUpgrade)
  end
  clearItemUpgradeContext()
  return costInfo
end

local function getItemCostLabel(itemID)
  local name = GetItemInfo(itemID)
  return name or ("Item " .. tostring(itemID))
end

local function getEquippedItemLink(invSlot)
  if invSlot and ItemLocation and C_Item and C_Item.GetItemLink then
    local loc = ItemLocation:CreateFromEquipmentSlot(invSlot)
    if loc and loc.IsValid and loc:IsValid() then
      local ok, itemLink = pcall(C_Item.GetItemLink, loc)
      if ok and type(itemLink) == "string" and itemLink ~= "" then
        return itemLink
      end
    end
  end
  return GetInventoryItemLink("player", invSlot)
end

local function lookupCrestUpgradeStepFromLink(link, invSlot)
  if not (C_Item and C_Item.GetItemUpgradeInfo) then
    return nil
  end
  local ok, upInfo = pcall(C_Item.GetItemUpgradeInfo, link)
  if not ok or not upInfo then
    return nil
  end

  local currentLevel = upInfo.currentLevel
  local maxLevel = upInfo.maxLevel
  if not currentLevel or not maxLevel or currentLevel >= maxLevel then
    return nil
  end

  local trackId = upInfo.trackStringID
  if not trackId or not NS.findCrestBonusInfoForGroupLevel then
    return nil
  end

  if invSlot and NS.ingestCrestUpgradeTrackFromItemInfo then
    local itemLocation, itemInfo = beginEquippedUpgradeContext(invSlot, link)
    if itemInfo then
      NS.ingestCrestUpgradeTrackFromItemInfo(trackId, itemInfo, link)
      clearItemUpgradeContext()
    end
  end
  NS.ensureCrestTrackCached(trackId)

  local current = NS.findCrestBonusInfoForGroupLevel(trackId, currentLevel)
  local nextInfo = NS.findCrestBonusInfoForGroupLevel(trackId, currentLevel + 1)
  if not current or not nextInfo then
    return nil
  end

  local ilvlGain = (nextInfo.itemLevel or 0) - (current.itemLevel or 0)
  if ilvlGain <= 0 then
    return nil
  end

  local currencyId = nextInfo.currencyId
  local crestCostBase = NS.CREST_UPGRADE_COST_AMOUNT or 20
  local crestDiscounted = false
  local stepsRemaining = maxLevel - currentLevel
  local hwmSlotHint
  local crestCost
  local usedApiCost = false

  local apiCost = invSlot and queryEquippedCrestCost(invSlot, link, currencyId) or nil
  if apiCost then
    if apiCost.high_watermark_slot then
      hwmSlotHint = apiCost.high_watermark_slot
    end
    if apiCost.crest_cost ~= nil then
      crestCost = apiCost.crest_cost
      usedApiCost = true
      if apiCost.crest_cost_base then
        crestCostBase = apiCost.crest_cost_base
      end
      if apiCost.currency_id then
        currencyId = apiCost.currency_id
      end
      crestDiscounted = apiCost.crest_discounted == true or crestCost < crestCostBase or crestCost <= 0
    end
    if apiCost.steps_remaining then
      stepsRemaining = apiCost.steps_remaining
    end
    if apiCost.current_level then
      currentLevel = apiCost.current_level
    end
    if apiCost.max_level then
      maxLevel = apiCost.max_level
    end
  end

  if not usedApiCost then
    crestCost, crestCostBase, crestDiscounted = NS.computeCrestUpgradeCost(
      link, invSlot, nextInfo.itemLevel, crestCostBase, { hwmSlot = hwmSlotHint })
  end

  if crestCost <= 0 then
    crestDiscounted = true
  elseif crestCost < crestCostBase then
    crestDiscounted = true
  end

  if crestCost < 0 then
    return nil
  end

  local crestLabel = NS.formatCrestCostLabel(crestCost, crestCostBase, currencyId, crestDiscounted)
  local rankLabel = string.format("%d/%d", currentLevel, maxLevel)
  if upInfo.trackString and upInfo.trackString ~= "" then
    rankLabel = string.format("%s %s", upInfo.trackString, rankLabel)
  end

  return {
    current = current,
    next = nextInfo,
    crest_cost = crestCost,
    crest_cost_base = crestCostBase,
    crest_discounted = crestDiscounted,
    currency_id = currencyId,
    crest_label = crestLabel,
    ilvl_gain = ilvlGain,
    preview_ilvl = nextInfo.itemLevel,
    upgrade_track = upInfo.trackString,
    upgrade_rank = rankLabel,
    current_level = currentLevel,
    max_level = maxLevel,
    steps_remaining = stepsRemaining,
    upgrade_group = trackId,
  }
end

local function previewEquippedCrestUpgradeLink(invSlot, link, itemID, targetIlvl)
  if not invSlot or not link or not itemID or not ItemLocation then
    return nil
  end
  if NS.isItemUpgradeFrameOpen and NS.isItemUpgradeFrameOpen() then
    return nil
  end
  if not (C_ItemUpgrade and C_ItemUpgrade.SetItemUpgradeFromLocation and C_ItemUpgrade.GetItemHyperlink) then
    return nil
  end

  local itemLocation = ItemLocation:CreateFromEquipmentSlot(invSlot)
  if not itemLocationCanUseUpgradeContext(itemLocation, link) then
    return nil
  end
  if not pcall(C_ItemUpgrade.SetItemUpgradeFromLocation, itemLocation) then
    if C_ItemUpgrade.ClearItemUpgrade then
      pcall(C_ItemUpgrade.ClearItemUpgrade)
    end
    return nil
  end

  local candidate
  local okLink, upgradedLink = pcall(C_ItemUpgrade.GetItemHyperlink)
  if okLink and type(upgradedLink) == "string" and upgradedLink ~= "" then
    candidate = upgradedLink
  end
  if C_ItemUpgrade.ClearItemUpgrade then
    pcall(C_ItemUpgrade.ClearItemUpgrade)
  end
  if not candidate or candidate == link then
    return nil
  end

  primeItemInfo(link, itemID)
  primeItemInfo(candidate, itemID)
  local currentIlvl = readLinkIlvl(link, itemID)
  local newIlvl = readLinkIlvl(candidate, itemID)
  if currentIlvl > 0 and newIlvl > 0 and newIlvl <= currentIlvl then
    return nil
  end
  if targetIlvl and newIlvl > 0 and newIlvl < targetIlvl then
    return nil
  end
  return candidate
end

local function buildCrestPreviewLinkFromBonusStep(link, crestStep)
  if not link or not crestStep or not crestStep.next then
    return nil
  end
  local nextBonusId = NS.findCrestBonusIdForGroupLevel(crestStep.next.upgradeGroup, crestStep.next.upgradeLevel)
  if not nextBonusId then
    return nil
  end

  local parts = padItemParts(splitItemPayload(link), 14)
  if not parts then
    return nil
  end
  local itemID = tonumber(parts[2])
  local numBonus = tonumber(parts[14]) or 0
  local replaced = false
  local currentBonusId = crestStep.current
    and NS.findCrestBonusIdForGroupLevel(crestStep.current.upgradeGroup, crestStep.current.upgradeLevel)

  if currentBonusId then
    for i = 1, numBonus do
      if tonumber(parts[14 + i]) == currentBonusId then
        parts[14 + i] = tostring(nextBonusId)
        replaced = true
        break
      end
    end
  end
  if not replaced then
    for i = 1, numBonus do
      local bid = tonumber(parts[14 + i])
      if bid and NS.isCrestUpgradeBonusId and NS.isCrestUpgradeBonusId(bid) then
        parts[14 + i] = tostring(nextBonusId)
        replaced = true
        break
      end
    end
  end
  if not replaced then
    numBonus = numBonus + 1
    parts[14] = tostring(numBonus)
    parts[14 + numBonus] = tostring(nextBonusId)
  end

  local rebuilt = rebuildItemLink(link, parts)
  if not rebuilt or rebuilt == link then
    return nil
  end
  primeItemInfo(rebuilt, itemID)
  return rebuilt
end

local function buildCrestPreviewLink(invSlot, link, itemID, targetIlvl, targetTrack, crestStep)
  if not link or not itemID or not targetIlvl then
    return nil
  end

  local predLink = previewEquippedCrestUpgradeLink(invSlot, link, itemID, targetIlvl)
  if not predLink and crestStep then
    predLink = buildCrestPreviewLinkFromBonusStep(link, crestStep)
  end
  if not predLink or predLink == link then
    return nil
  end
  primeItemInfo(predLink, itemID)
  return predLink
end

local function analyzeEquippedCrestUpgrade(invSlot, link, slotId, specKey)
  if not link or not invSlot or not slotId then
    return nil
  end

  local crestStep = lookupCrestUpgradeStepFromLink(link, invSlot)
  if not crestStep then
    return nil
  end

  local itemMeta = getItemMeta(link)
  local itemID = tonumber(link:match("item:(%d+)"))
  if not itemID or not crestStep.preview_ilvl then
    return nil
  end

  local predLink = buildCrestPreviewLink(invSlot, link, itemID, crestStep.preview_ilvl, crestStep.upgrade_track, crestStep)
  local previewMeta = predLink and getItemMeta(predLink) or nil
  local dpsDelta = 0
  local dpsPerCrest = 0
  if predLink and specKey then
    primeItemInfo(link, itemID)
    primeItemInfo(predLink, itemID)
    local pred = NS.Predictor.PredictItemDelta({ link = predLink }, specKey)
    pred = pickBestPrediction(pred)
    if pred then
      dpsDelta = pred.dps_delta or 0
      if crestStep.crest_cost > 0 then
        dpsPerCrest = dpsDelta / crestStep.crest_cost
      elseif dpsDelta > 0 then
        dpsPerCrest = dpsDelta
      end
    end
  end

  local crestCost = crestStep.crest_cost
  local currencyId = crestStep.currency_id
  local crestOwned = currencyId and NS.getCrestCurrencyBalance(currencyId) or 0
  local canAfford = crestCost <= crestOwned

  return {
    link = link,
    preview_link = predLink or link,
    preview_name = previewMeta and previewMeta.name or nil,
    preview_quality = previewMeta and previewMeta.quality or nil,
    preview_ilvl = crestStep.preview_ilvl,
    source = "crest",
    source_label = "Equipped",
    name = itemMeta.name,
    quality = itemMeta.quality,
    ilvl = itemMeta.ilvl,
    upgrade_track = crestStep.upgrade_track,
    upgrade_rank = crestStep.upgrade_rank,
    crest_cost = crestCost,
    crest_cost_base = crestStep.crest_cost_base,
    crest_discounted = crestStep.crest_discounted,
    currency_id = currencyId,
    crest_owned = crestOwned,
    can_afford = canAfford,
    steps_remaining = crestStep.steps_remaining,
    current_level = crestStep.current_level,
    max_level = crestStep.max_level,
    upgrade_group = crestStep.upgrade_group,
    crest_label = crestStep.crest_label,
    ilvl_gain = crestStep.ilvl_gain,
    dps_delta = dpsDelta,
    dps_per_crest = dpsPerCrest,
    slot_id = slotId,
    inv_slot = invSlot,
    slot_label = SLOT_ID_LABELS[slotId] or tostring(slotId),
    is_upgrade = dpsDelta > 0.5,
    crest_plan_order = nil,
    crest_plan_steps = 0,
  }
end

function NS.refreshCrestRowAffordability(rows)
  for _, row in ipairs(rows or {}) do
    if row.currency_id then
      row.crest_owned = NS.getCrestCurrencyBalance(row.currency_id)
      row.can_afford = (row.crest_cost or 0) <= row.crest_owned
    end
  end
end

local function buildCrestPreviewAtGroupLevel(invSlot, link, itemID, group, level, trackString)
  local currentInfo = NS.findCrestBonusInfoForGroupLevel(group, level - 1)
  local nextInfo = NS.findCrestBonusInfoForGroupLevel(group, level)
  if not nextInfo then
    return nil
  end
  return buildCrestPreviewLink(invSlot, link, itemID, nextInfo.itemLevel, trackString, {
    current = currentInfo,
    next = nextInfo,
  })
end

local function predictCrestPreviewDpsDelta(predLink, specKey)
  if not predLink or not specKey then
    return 0
  end
  local pred = NS.Predictor.PredictItemDelta({ link = predLink }, specKey)
  pred = pickBestPrediction(pred)
  return pred and (pred.dps_delta or 0) or 0
end

local function computeCrestStepCostWithWatermark(link, invSlot, targetIlvl, currencyId, wmState)
  local baseCost = NS.CREST_UPGRADE_COST_AMOUNT or 20
  local cost, base, discounted = NS.computeCrestUpgradeCost(
    link, invSlot, targetIlvl, baseCost, { wmState = wmState })
  return cost, base, discounted, NS.formatCrestCostLabel(cost, base, currencyId, discounted)
end

local function buildCrestPlanStepDisplay(chain, step, costInfo, order, chainIdx)
  local itemID = chain.link and tonumber(chain.link:match("item:(%d+)"))
  local group = chain.upgrade_group
  local link = chain.link
  local name = chain.name
  local quality = chain.quality
  local ilvl

  if itemID and group then
    local fromInfo = NS.findCrestBonusInfoForGroupLevel(group, step.from_level)
    if fromInfo and fromInfo.itemLevel then
      ilvl = fromInfo.itemLevel
    end
    if step.from_level > chain.start_level then
      local fromPreview = buildCrestPreviewAtGroupLevel(
        chain.inv_slot, chain.link, itemID, group, step.from_level, chain.upgrade_track)
      if fromPreview then
        link = fromPreview
        local fromMeta = getItemMeta(fromPreview)
        name = fromMeta.name or name
        quality = fromMeta.quality or quality
        ilvl = fromMeta.ilvl or ilvl
      end
    elseif link then
      local itemMeta = getItemMeta(link)
      name = itemMeta.name or name
      quality = itemMeta.quality or quality
      ilvl = itemMeta.ilvl or ilvl
    end
  end

  local predLink
  local previewName, previewQuality
  if itemID and group then
    predLink = buildCrestPreviewAtGroupLevel(
      chain.inv_slot, chain.link, itemID, group, step.to_level, chain.upgrade_track)
    if predLink then
      local previewMeta = getItemMeta(predLink)
      previewName = previewMeta and previewMeta.name
      previewQuality = previewMeta and previewMeta.quality
    end
  end

  local marginal = step.marginal_dps or 0
  local cost = costInfo.cost or 0
  local dpsPerCrest = 0
  if cost > 0 then
    dpsPerCrest = marginal / cost
  elseif marginal > 0 then
    dpsPerCrest = marginal
  end

  return {
    order = order,
    chain_idx = chainIdx,
    slot_id = chain.slot_id,
    slot_label = chain.slot_label,
    name = name,
    link = link,
    quality = quality,
    ilvl = ilvl,
    preview_link = predLink,
    preview_name = previewName,
    preview_quality = previewQuality,
    preview_ilvl = step.target_ilvl,
    crest_cost = costInfo.cost,
    crest_cost_base = costInfo.base,
    crest_discounted = costInfo.discounted,
    crest_label = costInfo.label,
    currency_id = step.currency_id,
    dps_delta = marginal,
    dps_per_crest = dpsPerCrest,
    upgrade_rank = step.upgrade_rank,
    ilvl_gain = step.ilvl_gain,
    target_ilvl = step.target_ilvl,
    from_level = step.from_level,
    to_level = step.to_level,
    max_level = chain.max_level,
    upgrade_track = chain.upgrade_track,
    inv_slot = chain.inv_slot,
    upgrade_group = chain.upgrade_group,
    can_afford = true,
    is_plan_step = true,
    is_upgrade = marginal > 0,
    crest_plan_order = order,
  }
end

function NS.buildCrestUpgradeChains(rows, specKey)
  local chains = {}
  for _, row in ipairs(rows or {}) do
    local link = row.link
    local invSlot = row.inv_slot
    local group = row.upgrade_group
    local startLevel = row.current_level
    local maxLevel = row.max_level
    if link and invSlot and group and startLevel and maxLevel and startLevel < maxLevel then
      local itemID = tonumber(link:match("item:(%d+)"))
      if itemID then
        local trackString = row.upgrade_track
        local dpsByLevel = {}
        dpsByLevel[startLevel] = 0
        local steps = {}
        for level = startLevel + 1, maxLevel do
          local nextInfo = NS.findCrestBonusInfoForGroupLevel(group, level)
          local prevInfo = NS.findCrestBonusInfoForGroupLevel(group, level - 1)
          if nextInfo and prevInfo then
            local predLink = buildCrestPreviewAtGroupLevel(invSlot, link, itemID, group, level, trackString)
            if predLink then
              primeItemInfo(predLink, itemID)
              dpsByLevel[level] = predictCrestPreviewDpsDelta(predLink, specKey)
            else
              dpsByLevel[level] = dpsByLevel[level - 1] or 0
            end
            local marginal = (dpsByLevel[level] or 0) - (dpsByLevel[level - 1] or 0)
            local rankLabel = string.format("%d/%d", level, maxLevel)
            if trackString and trackString ~= "" then
              rankLabel = string.format("%s %s", trackString, rankLabel)
            end
            steps[#steps + 1] = {
              from_level = level - 1,
              to_level = level,
              target_ilvl = nextInfo.itemLevel,
              ilvl_gain = (nextInfo.itemLevel or 0) - (prevInfo.itemLevel or 0),
              currency_id = nextInfo.currencyId,
              upgrade_rank = rankLabel,
              marginal_dps = marginal,
            }
          end
        end
        if #steps > 0 then
          chains[#chains + 1] = {
            slot_id = row.slot_id,
            slot_label = row.slot_label,
            inv_slot = invSlot,
            link = link,
            name = row.name,
            quality = row.quality,
            upgrade_group = group,
            upgrade_track = trackString,
            start_level = startLevel,
            max_level = maxLevel,
            steps = steps,
            row = row,
          }
        end
      end
    end
  end
  return chains
end

local function copyCurrencyBalances(balances)
  local copy = {}
  for currencyId, qty in pairs(balances or {}) do
    copy[currencyId] = qty
  end
  return copy
end

local function copyWatermarkState(wmState)
  local copy = {}
  for slot, ilvl in pairs(wmState or {}) do
    copy[slot] = ilvl
  end
  return copy
end

local function encodePlanSearchKey(levels, balances, wmState)
  local levelParts = {}
  for i = 1, #levels do
    levelParts[#levelParts + 1] = tostring(levels[i] or 0)
  end
  local balParts = {}
  for _, currencyId in ipairs(NS.CREST_CURRENCY_IDS or {}) do
    balParts[#balParts + 1] = tostring(balances[currencyId] or 0)
  end
  local wmParts = {}
  for slot, ilvl in pairs(wmState or {}) do
    wmParts[#wmParts + 1] = tostring(slot) .. ":" .. tostring(ilvl)
  end
  table.sort(wmParts)
  return table.concat(levelParts, ",") .. "|" .. table.concat(balParts, ",") .. "|" .. table.concat(wmParts, ",")
end

local function sumPlanDps(plan)
  local total = 0
  for _, step in ipairs(plan or {}) do
    total = total + (step.dps_delta or 0)
  end
  return total
end

local function sumCrestSpendFromPlan(plan)
  local spent = {}
  for _, step in ipairs(plan or {}) do
    local cur = step.currency_id
    local cost = tonumber(step.crest_cost) or 0
    if cur and cost > 0 then
      spent[cur] = (spent[cur] or 0) + cost
    end
  end
  return spent
end

function NS.optimizeCrestSpendPlan(rows, specKey)
  NS.refreshCrestRowAffordability(rows)

  for _, row in ipairs(rows or {}) do
    row.crest_plan_order = nil
    row.crest_plan_steps = 0
  end

  local chains = NS.buildCrestUpgradeChains(rows, specKey)
  if #chains == 0 then
    return {}, {}, 0, {}
  end

  local balances = NS.getCrestCurrencyBalances()
  local wmState = {}
  for _, chain in ipairs(chains) do
    local hwmSlot = NS.resolveCrestHighWatermarkSlot(chain.link, chain.inv_slot)
    if hwmSlot then
      local apiWm = NS.getCharacterCrestHighWatermark(chain.link, chain.inv_slot, hwmSlot)
      wmState[hwmSlot] = math.max(wmState[hwmSlot] or 0, apiWm or 0)
    end
  end

  local levels = {}
  for i, chain in ipairs(chains) do
    levels[i] = chain.start_level
  end

  local best = { dps = -1, plan = {} }
  local memo = {}
  local maxDepth = 0
  for _, chain in ipairs(chains) do
    maxDepth = maxDepth + (#chain.steps or 0)
  end
  maxDepth = math.min(maxDepth, 48)

  local function applyStep(chainIdx, step, costInfo, plan, spent, wm, bal)
    local chain = chains[chainIdx]
    local order = #plan + 1
    plan[#plan + 1] = buildCrestPlanStepDisplay(chain, step, costInfo, order, chainIdx)
    local cur = step.currency_id
    if cur then
      bal[cur] = (bal[cur] or 0) - costInfo.cost
      spent[cur] = (spent[cur] or 0) + costInfo.cost
    end
    local hwmSlot = NS.resolveCrestHighWatermarkSlot(chain.link, chain.inv_slot)
    if hwmSlot and step.target_ilvl then
      wm[hwmSlot] = math.max(wm[hwmSlot] or 0, step.target_ilvl)
    end
    levels[chainIdx] = step.to_level
  end

  local function undoStep(chainIdx, step, costInfo, plan, spent, wm, bal, prevLevel, prevWm)
    plan[#plan] = nil
    local cur = step.currency_id
    if cur then
      bal[cur] = (bal[cur] or 0) + costInfo.cost
      spent[cur] = (spent[cur] or 0) - costInfo.cost
      if spent[cur] <= 0 then
        spent[cur] = nil
      end
    end
    if prevWm ~= nil then
      local hwmSlot = NS.resolveCrestHighWatermarkSlot(chains[chainIdx].link, chains[chainIdx].inv_slot)
      if hwmSlot then
        wm[hwmSlot] = prevWm
      end
    end
    levels[chainIdx] = prevLevel
  end

  local function search(plan, spent, wm, bal, depth)
    local totalDps = sumPlanDps(plan)
    local key = encodePlanSearchKey(levels, bal, wm)
    if memo[key] and memo[key] >= totalDps then
      return
    end
    memo[key] = totalDps

    if totalDps > best.dps then
      best.dps = totalDps
      best.plan = {}
      for i, step in ipairs(plan) do
        best.plan[i] = step
      end
    end
    if depth >= maxDepth then
      return
    end

    local candidates = {}
    for chainIdx, chain in ipairs(chains) do
      local curLevel = levels[chainIdx]
      if curLevel < chain.max_level then
        local stepIndex = curLevel - chain.start_level + 1
        local step = chain.steps[stepIndex]
        if step then
          local cost, base, discounted, label = computeCrestStepCostWithWatermark(
            chain.link, chain.inv_slot, step.target_ilvl, step.currency_id, wm)
          local owned = step.currency_id and (bal[step.currency_id] or 0) or 0
          if cost <= owned then
            local score = cost == 0 and ((step.marginal_dps or 0) * 1000 + (step.ilvl_gain or 0))
              or ((step.marginal_dps or 0) / cost)
            if score <= 0 and (step.ilvl_gain or 0) > 0 then
              score = (step.ilvl_gain or 0) / math.max(cost, 1)
            end
            candidates[#candidates + 1] = {
              chainIdx = chainIdx,
              step = step,
              score = score,
              costInfo = { cost = cost, base = base, discounted = discounted, label = label },
            }
          end
        end
      end
    end

    table.sort(candidates, function(a, b)
      return (a.score or 0) > (b.score or 0)
    end)

    for _, cand in ipairs(candidates) do
      if (cand.score or 0) > 0 or cand.costInfo.cost == 0 or (cand.step.ilvl_gain or 0) > 0 then
        local chainIdx = cand.chainIdx
        local step = cand.step
        local prevLevel = levels[chainIdx]
        local hwmSlot = NS.resolveCrestHighWatermarkSlot(chains[chainIdx].link, chains[chainIdx].inv_slot)
        local prevWm = hwmSlot and wm[hwmSlot] or nil
        applyStep(chainIdx, step, cand.costInfo, plan, spent, wm, bal)
        search(plan, spent, wm, bal, depth + 1)
        undoStep(chainIdx, step, cand.costInfo, plan, spent, wm, bal, prevLevel, prevWm)
      end
    end
  end

  local workingPlan = {}
  local spent = {}
  local workingWm = copyWatermarkState(wmState)
  local workingBal = copyCurrencyBalances(balances)
  search(workingPlan, spent, workingWm, workingBal, 0)

  if best.dps < 0 then
    best.plan = {}
    best.dps = 0
  end

  local slotPlanCounts = {}
  for order, step in ipairs(best.plan) do
    step.order = order
    local slotId = step.slot_id
    slotPlanCounts[slotId] = (slotPlanCounts[slotId] or 0) + 1
    local chain = chains[step.chain_idx]
    if chain and chain.row then
      local row = chain.row
      if not row.crest_plan_order then
        row.crest_plan_order = order
      end
      row.crest_plan_steps = slotPlanCounts[slotId]
    end
  end

  return best.plan, sumCrestSpendFromPlan(best.plan), best.dps, chains
end

function NS.computeGreedyCrestSpendPlan(rows, specKey)
  local plan, spent, totalDps = NS.optimizeCrestSpendPlan(rows, specKey)
  return plan, spent, totalDps
end

function NS.formatCrestSpendPlanSummary(plan, spent, totalDps)
  if not plan or #plan == 0 then
    return "No spending plan: no affordable upgrades with positive value, or crest balance too low."
  end
  local planSpent = sumCrestSpendFromPlan(plan)
  if not next(planSpent) and spent and next(spent) then
    planSpent = spent
  end
  local parts = {}
  for _, currencyId in ipairs(NS.CREST_CURRENCY_IDS or {}) do
    local amount = planSpent[currencyId]
    if amount and amount > 0 then
      table.insert(parts, string.format("%d %s", amount, getCurrencyLabel(currencyId)))
    end
  end
  local spendText = #parts > 0 and table.concat(parts, ", ") or "0 crests"
  return string.format(
    "Plan: %d step(s) - spend %s - %s total DPS",
    #plan,
    spendText,
    NS.formatDelta(totalDps or 0)
  )
end

function NS.formatCrestPlanStepLine(step)
  if not step then
    return ""
  end
  local costLabel = step.crest_label or tostring(step.crest_cost or 0)
  return string.format(
    "Step %d: %s - %s - %s - %s",
    step.order or 0,
    step.slot_label or "?",
    step.upgrade_rank or "?",
    costLabel,
    NS.formatDelta(step.dps_delta or 0)
  )
end

function NS.collectCrestUpgradeOpportunities(specKey)
  local results = {}
  if not NS.crestUpgradeDataReady or not NS.crestUpgradeDataReady() then
    return results, "Crest upgrade data unavailable"
  end
  for _, slotId in ipairs(UPGRADE_SLOT_IDS) do
    local slotName = NS.SLOT_ID_TO_NAME[slotId]
    if slotName then
      local invSlot = GetInventorySlotInfo(slotName)
      if invSlot then
        local link = getEquippedItemLink(invSlot)
        if link then
          primeItemInfo(link, tonumber(link:match("item:(%d+)")))
          local row = analyzeEquippedCrestUpgrade(invSlot, link, slotId, specKey)
          if row then
            table.insert(results, row)
          end
        end
      end
    end
  end

  table.sort(results, function(a, b)
    return (a.dps_per_crest or 0) > (b.dps_per_crest or 0)
  end)

  if #results == 0 then
    return results, "No upgradeable equipped gear with crest costs found."
  end
  return results, nil
end

local MAX_ITEM_STAT_READY_RETRIES = 20

local function scoreOneGearRef(session, ref)
  local specKey = session.specKey
  local previewPreset = session.previewPreset
  local useTrackPreview = session.useTrackPreview

  if not ref.link then
    return "skipped"
  end
  if isTrinketLink(ref.link) or (ref.preview_link and isTrinketLink(ref.preview_link)) then
    return "skipped"
  end
  local usabilityLink = ref.resolved_link or ref.link

  local scoreLink = usabilityLink
  local targetTrack
  local targetIlvl
  local hasValidTrackPreview = not (ref.source == "loot" and useTrackPreview)

  if ref.source == "loot" and useTrackPreview then
    targetTrack = getPreviewTargetTrack(previewPreset, ref.instance_id, ref.instance_name, ref.instance_kind)
    local itemID = ref.item_id or tonumber(ref.link:match("item:(%d+)"))
    targetIlvl = getPreviewTargetIlvl(previewPreset.ilvl, ref.instance_id, ref.instance_name, ref.instance_kind)
    local previewLink = ref.resolved_link
    if previewLink and isTrustedPreviewLink(itemID, targetIlvl, targetTrack, previewLink)
      and lootPreviewLinkMatchesTarget(
        previewLink,
        itemID,
        targetIlvl,
        targetTrack,
        ref.instance_kind,
        ref.instance_id,
        ref.instance_name,
        ref.link
      ) then
      scoreLink = previewLink
      ref.resolved_link = previewLink
      hasValidTrackPreview = true
    elseif not previewLink or not previewLinkUsableForScoring(
        previewLink,
        targetIlvl,
        targetTrack,
        itemID,
        ref.instance_kind,
        ref.instance_id,
        ref.instance_name
      ) then
      clearPreviewCacheMiss(itemID, targetIlvl, targetTrack, ref.instance_kind, ref.instance_id, ref.instance_name)
      previewLink = resolvePreviewLootLink(
        ref.instance_id,
        itemID,
        previewPreset,
        ref.instance_kind,
        nil,
        ref.instance_name,
        ref
      )
    end
    if not hasValidTrackPreview then
      if not previewLink or not previewLinkUsableForScoring(
          previewLink,
          targetIlvl,
          targetTrack,
          itemID,
          ref.instance_kind,
          ref.instance_id,
          ref.instance_name
        ) then
        -- The score session will yield and retry while preview data resolves.
      else
        scoreLink = previewLink
        ref.resolved_link = previewLink
        hasValidTrackPreview = true
      end
    end
  elseif ref.source == "loot" and ref.resolved_link and ref.resolved_link ~= ref.link then
    scoreLink = ref.resolved_link
  end

  if not hasValidTrackPreview then
    return "pending"
  end
  if NS.statsFromItemLink and not NS.statsFromItemLink(scoreLink) then
    return "pending"
  end
  if specKey and scoreLink and not isLootLinkUsableForPlayer(scoreLink, specKey) then
    return "skipped"
  end

  local itemIlvl = getItemIlvl(scoreLink)
  if not targetIlvl or targetIlvl <= 0 then
    targetIlvl = getPreviewTargetIlvl(previewPreset.ilvl, ref.instance_id, ref.instance_name, ref.instance_kind)
  end
  local displayIlvl = (ref.source == "loot" and useTrackPreview and targetIlvl and targetIlvl > 0)
    and targetIlvl
    or (itemIlvl > 0 and itemIlvl or targetIlvl or itemIlvl)
  if not displayIlvl or displayIlvl <= 0 then
    displayIlvl = targetIlvl or itemIlvl
  end
  ref.resolved_link = scoreLink
  syncLootPreviewMetadata(ref, previewPreset, scoreLink, ref.preview_link)
  local displayLink = ref.preview_link or scoreLink
  ref.preview_link = displayLink

  local pred, predErr = NS.Predictor.PredictItemDelta({ link = scoreLink }, specKey, session.predictionContext)
  if pred then
    local best = pickBestPrediction(pred)
    if best then
      local equippedRef = best.slot_id and NS.getSlotItemRef(best.slot_id) or nil
      local equippedName = equippedRef and select(1, GetItemInfo(NS.itemRefToLink(equippedRef))) or nil
      local displayIlvl = targetIlvl or ref.preview_ilvl
      local displayTrack = targetTrack
        or ref.upgrade_track
        or getUpgradeTrackFromLink(scoreLink)
        or (previewPreset and previewPreset.track)
      table.insert(session.rows, {
        link = scoreLink,
        preview_display_link = displayLink,
        journal_link = ref.link,
        name = ref.name or select(1, GetItemInfo(displayLink)) or select(1, GetItemInfo(scoreLink)) or scoreLink,
        quality = ref.quality or select(3, GetItemInfo(displayLink)) or select(3, GetItemInfo(scoreLink)) or -1,
        ilvl = displayIlvl,
        preview_ilvl = displayIlvl,
        upgrade_track = displayTrack,
        source = ref.source,
        source_label = ref.source_label,
        claimable = ref.claimable,
        preview = ref.preview,
        instance_id = ref.instance_id,
        instance_name = ref.instance_name,
        dps_base = best.dps_base,
        dps_new = best.dps_new,
        dps_delta = best.dps_delta,
        slot_id = best.slot_id,
        slot_label = SLOT_ID_LABELS[best.slot_id] or tostring(best.slot_id or "?"),
        mode = best.mode,
        equipped_name = equippedName,
        is_upgrade = (best.dps_delta or 0) > 0.5,
      })
      return "scored"
    end
    return "skipped"
  else
    if type(predErr) == "string" and predErr:find("data not ready", 1, true) then
      return "pending"
    end
    session.errors = session.errors + 1
    return "error"
  end
end

local function finalizeGearRefScoreSession(session)
  table.sort(session.rows, function(a, b)
    return (a.dps_delta or 0) > (b.dps_delta or 0)
  end)

  if session.profileStart and not session.profileReported and debugprofilestop then
    session.profileReported = true
    local cacheEnd = NS.getPredictionCacheSnapshot and NS.getPredictionCacheSnapshot() or {}
    local cacheStart = session.cacheStatsStart or {}
    local statEnd = NS.statDeltaStats or {}
    local statStart = session.statStatsStart or {}
    local function delta(after, before, key)
      local value = (after[key] or 0) - (before[key] or 0)
      if value < 0 then
        return after[key] or 0
      end
      return value
    end
    NS.lastGearScoreStats = {
      items = session.index - 1,
      elapsed_ms = debugprofilestop() - session.profileStart,
      cache_hits = delta(cacheEnd, cacheStart, "hits"),
      cache_misses = delta(cacheEnd, cacheStart, "misses"),
      forward_calls = delta(cacheEnd, cacheStart, "forward_count"),
      forward_ms = delta(cacheEnd, cacheStart, "forward_ms"),
      cache_lookup_ms = delta(cacheEnd, cacheStart, "lookup_ms"),
      stat_delta_ms = delta(statEnd, statStart, "totalMs"),
      stat_delta_cache_hits = delta(statEnd, statStart, "cache_hits"),
      stat_delta_cache_misses = delta(statEnd, statStart, "cache_misses"),
    }
    NS.debugPrint(string.format(
      "gear scoring: %d items in %.1fms, forward %.1fms/%d, cache %d/%d, stat delta %.1fms",
      NS.lastGearScoreStats.items,
      NS.lastGearScoreStats.elapsed_ms,
      NS.lastGearScoreStats.forward_ms,
      NS.lastGearScoreStats.forward_calls,
      NS.lastGearScoreStats.cache_hits,
      NS.lastGearScoreStats.cache_hits + NS.lastGearScoreStats.cache_misses,
      NS.lastGearScoreStats.stat_delta_ms
    ))
  end

  return session.rows, session.errors
end

function NS.createGearRefScoreSession(refs, specKey, opts)
  opts = opts or {}
  local previewPreset = NS.resolveLootPreviewPreset(opts)
  local useTrackPreview = previewPreset and previewPreset.key ~= "journal"
  local profileStart
  local cacheStatsStart
  local statStatsStart
  if MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.debug and debugprofilestop then
    profileStart = debugprofilestop()
    cacheStatsStart = NS.getPredictionCacheSnapshot and NS.getPredictionCacheSnapshot() or {}
    local statStats = NS.statDeltaStats or {}
    statStatsStart = {
      totalMs = statStats.totalMs or 0,
      cache_hits = statStats.cache_hits or 0,
      cache_misses = statStats.cache_misses or 0,
    }
  end
  local session = {
    refs = refs or {},
    specKey = specKey,
    opts = opts,
    index = 1,
    rows = {},
    errors = 0,
    previewPreset = previewPreset,
    useTrackPreview = useTrackPreview,
    pendingAttempts = {},
    previewWarmedRefs = {},
    predictionContext = NS.createPredictionContext and NS.createPredictionContext() or nil,
    profileStart = profileStart,
    cacheStatsStart = cacheStatsStart,
    statStatsStart = statStatsStart,
  }
  return session
end

function NS.scoreGearRefSessionStep(session, batchSize)
  if not session or not session.refs then
    return 0, true
  end
  batchSize = batchSize or 10
  if batchSize < 1 then
    batchSize = 10
  end

  local startIdx = session.index
  local endIdx = math.min(startIdx + batchSize - 1, #session.refs)
  if session.pendingAttempts[session.refs[startIdx]] then
    endIdx = startIdx
  end
  if endIdx < startIdx then
    return 0, true
  end

  if session.useTrackPreview then
    local batchRefs = {}
    for i = startIdx, endIdx do
      local ref = session.refs[i]
      if not session.previewWarmedRefs[ref] then
        session.previewWarmedRefs[ref] = true
        batchRefs[#batchRefs + 1] = ref
      end
    end
    if #batchRefs > 0 then
      warmPreviewTemplates(batchRefs, session.previewPreset)
    end
  end

  for i = startIdx, endIdx do
    local ref = session.refs[i]
    local status = scoreOneGearRef(session, ref)
    if status == "pending" then
      local attempts = (session.pendingAttempts[ref] or 0) + 1
      session.pendingAttempts[ref] = attempts
      if attempts < MAX_ITEM_STAT_READY_RETRIES then
        session.index = i
        return i - startIdx, false, true
      end
      session.errors = session.errors + 1
    else
      session.pendingAttempts[ref] = nil
    end
  end
  session.index = endIdx + 1
  return endIdx - startIdx + 1, session.index > #session.refs, false
end

function NS.finalizeGearRefScoreSession(session)
  if not session then
    return {}, 0
  end
  return finalizeGearRefScoreSession(session)
end

function NS.scoreGearRefs(refs, specKey, opts)
  local session = NS.createGearRefScoreSession(refs, specKey, opts)
  while session.index <= #session.refs do
    NS.scoreGearRefSessionStep(session, #session.refs)
  end
  return finalizeGearRefScoreSession(session)
end

local function collectBagGearRefs(specKey)
  local refs = {}
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
    return refs
  end
  local seen = {}
  for bag = 0, 4 do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.hyperlink and not isTrinketLink(info.hyperlink)
        and isLootLinkUsableForPlayer(info.hyperlink, specKey) then
        local guid = info["itemGUID"] or info["guid"] or NS.getGuidFromBagSlot(bag, slot)
        local key = guid and ("guid:" .. tostring(guid)) or string.format("bag:%d:%d", bag, slot)
        if not seen[key] then
          seen[key] = true
          table.insert(refs, {
            link = info.hyperlink,
            guid = guid,
            bag = bag,
            slot = slot,
            source = "bag",
            source_label = "In bags",
            seen_key = key,
          })
        end
      end
    end
  end
  return refs
end

local function crestRowToRef(row)
  if not row or not row.link then
    return nil
  end
  local itemID = tonumber(row.link:match("item:(%d+)"))
  local rank = row.upgrade_rank or "0"
  rank = tostring(rank):gsub("[^%d/]", ""):match("(%d+)") or "0"
  return {
    link = row.link,
    preview_link = row.preview_link,
    item_id = itemID,
    source = "crest",
    source_label = row.source_label or "Crest upgrade",
    crest_cost = row.crest_cost,
    crest_label = row.crest_label,
    dps_delta = row.dps_delta,
    dps_per_crest = row.dps_per_crest,
    is_upgrade = row.is_upgrade,
    slot_id = row.slot_id,
    slot_label = row.slot_label,
    bag = row.bag,
    slot = row.slot,
    upgrade_rank = row.upgrade_rank,
    seen_key = itemID and string.format("crest:%d:%s", itemID, rank) or row.link,
  }
end

function NS.collectGearCandidates(specKey, opts)
  opts = opts or {}
  local sources = opts.sources or NS.getAdvisorSources and NS.getAdvisorSources() or {
    bag = true, vault = false, loot = false, crest = false,
  }
  local flatRefs = {}
  local notes = {}
  local candidatesBySlot = {}
  local slotOrder = NS.BAG_SCAN_SLOT_ORDER or { 16, 17, 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12 }

  for _, slotId in ipairs(slotOrder) do
    candidatesBySlot[slotId] = {}
  end

  if sources.bag then
    local bagRefs = collectBagGearRefs(specKey)
    for _, ref in ipairs(bagRefs) do
      table.insert(flatRefs, ref)
    end
  end

  if sources.vault then
    local vaultRefs, vaultNote = NS.collectVaultRewardRefs()
    if vaultNote then
      table.insert(notes, vaultNote)
    end
    if NS.purgeStaleVaultSelections then
      NS.purgeStaleVaultSelections(vaultRefs)
    end
    for _, ref in ipairs(vaultRefs) do
      table.insert(flatRefs, ref)
    end
  end

  if sources.crest then
    local crestRows, crestNote = NS.collectCrestUpgradeOpportunities(specKey)
    if crestNote then
      table.insert(notes, crestNote)
    end
    for _, row in ipairs(crestRows) do
      local ref = crestRowToRef(row)
      if ref then
        table.insert(flatRefs, ref)
      end
    end
  end

  if sources.loot then
    clearPreviewCaches()
    local instanceId = opts.instance_id or MR_MYTHICAL_DPS_CONFIG.gear_advisor_instance_id or NS.LOOT_ALL_INSTANCES
    local scanOpts = {
      upgrades_only = opts.upgrades_only,
      upgrade_key = opts.loot_upgrade or MR_MYTHICAL_DPS_CONFIG.gear_advisor_loot_upgrade,
      preset = opts.preset,
    }
    local previewPreset = NS.resolveLootPreviewPreset(scanOpts)
    local lootRefs
    local lootNote
    if opts.loot_refs ~= nil then
      lootRefs = opts.loot_refs
      lootNote = opts.loot_note
    else
      lootRefs, lootNote = NS.collectEncounterJournalLootRefs(instanceId, opts.instance_name, specKey, scanOpts)
    end
    if lootNote then
      table.insert(notes, lootNote)
    end
    for _, ref in ipairs(lootRefs) do
      resolveLootPreviewForRef(ref, previewPreset)
      table.insert(flatRefs, ref)
    end
    if NS.purgeStaleLootSelections then
      NS.purgeStaleLootSelections(lootRefs)
    end
  end

  local seenCandKeys = {}
  for _, ref in ipairs(flatRefs) do
    local cand = NS.makeCandidateFromGearRef(ref)
    if cand and cand.key and not seenCandKeys[cand.key] then
      seenCandKeys[cand.key] = true
      local slots = NS.INVTYPE_TO_SLOT_IDS[cand.equipLoc or ""]
      if slots then
        for _, slotId in ipairs(slots) do
          if candidatesBySlot[slotId] then
            local dup = false
            for _, existing in ipairs(candidatesBySlot[slotId]) do
              if existing.key == cand.key then
                dup = true
                break
              end
            end
            if not dup then
              table.insert(candidatesBySlot[slotId], cand)
            end
          end
        end
      end
    end
  end

  local filteredFlatRefs = {}
  for _, ref in ipairs(flatRefs) do
    if ref.link and not isTrinketLink(ref.link)
      and not (ref.preview_link and isTrinketLink(ref.preview_link)) then
      table.insert(filteredFlatRefs, ref)
    end
  end

  local noteText = #notes > 0 and table.concat(notes, " ") or nil
  return candidatesBySlot, filteredFlatRefs, noteText
end
