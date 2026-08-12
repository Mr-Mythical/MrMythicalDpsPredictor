local ADDON_NAME, NS = ...

NS.CREST_UPGRADE_COST_AMOUNT = 20
NS.CREST_ACCOUNT_DISCOUNT_MULTIPLIER = 0.5

-- Midnight Season 2 Mistcrests (SimC / ATT / SavedInstances: 3442-3446).
NS.CREST_CURRENCY_IDS = { 3442, 3443, 3444, 3445, 3446 }

NS.CREST_CURRENCY_ID_SET = {
  [3442] = true, -- Adventurer Mistcrest
  [3443] = true, -- Veteran Mistcrest
  [3444] = true, -- Champion Mistcrest
  [3445] = true, -- Hero Mistcrest
  [3446] = true, -- Myth Mistcrest
}

-- Bonus IDs used by Midnight Season 2 Mistcrest upgrade tracks (for link parsing only).
-- Verified via Wowhead PTR tooltips on 12.1 (bonus → Upgrade Level + ilvl).
local CREST_BONUS_ID_MIN = 12817
local CREST_BONUS_ID_MAX = 12854

-- trackStringID -> { currencyId, maxLevel, ranks[level] = { itemLevel, bonusId, rank } }
-- Track string IDs reused from Midnight S1 (ATT UPGRADETRACKS still maps Champion=973 etc.).
-- Bonus IDs + Mistcrest currencies + ilvl ladder are Season 2.
local MIDNIGHT_CREST_TRACKS = {
  [971] = {
    currencyId = 3442,
    maxLevel = 6,
    ranks = {
      [1] = { itemLevel = 266, bonusId = 12817, rank = 2 },
      [2] = { itemLevel = 269, bonusId = 12818, rank = 2 },
      [3] = { itemLevel = 272, bonusId = 12819, rank = 2 },
      [4] = { itemLevel = 276, bonusId = 12820, rank = 2 },
      [5] = { itemLevel = 279, bonusId = 12821, rank = 2 },
      [6] = { itemLevel = 282, bonusId = 12822, rank = 2 },
    },
  },
  [972] = {
    currencyId = 3443,
    maxLevel = 6,
    ranks = {
      [1] = { itemLevel = 279, bonusId = 12825, rank = 3 },
      [2] = { itemLevel = 282, bonusId = 12826, rank = 3 },
      [3] = { itemLevel = 285, bonusId = 12827, rank = 3 },
      [4] = { itemLevel = 289, bonusId = 12828, rank = 3 },
      [5] = { itemLevel = 292, bonusId = 12829, rank = 3 },
      [6] = { itemLevel = 295, bonusId = 12830, rank = 3 },
    },
  },
  [973] = {
    currencyId = 3444,
    maxLevel = 6,
    ranks = {
      [1] = { itemLevel = 292, bonusId = 12833, rank = 4 },
      [2] = { itemLevel = 295, bonusId = 12834, rank = 4 },
      [3] = { itemLevel = 298, bonusId = 12835, rank = 4 },
      [4] = { itemLevel = 302, bonusId = 12836, rank = 4 },
      [5] = { itemLevel = 305, bonusId = 12837, rank = 4 },
      [6] = { itemLevel = 308, bonusId = 12838, rank = 4 },
    },
  },
  [974] = {
    currencyId = 3445,
    maxLevel = 6,
    ranks = {
      [1] = { itemLevel = 305, bonusId = 12841, rank = 5 },
      [2] = { itemLevel = 308, bonusId = 12842, rank = 5 },
      [3] = { itemLevel = 311, bonusId = 12843, rank = 5 },
      [4] = { itemLevel = 315, bonusId = 12844, rank = 5 },
      [5] = { itemLevel = 318, bonusId = 12845, rank = 5 },
      [6] = { itemLevel = 321, bonusId = 12846, rank = 5 },
    },
  },
  [978] = {
    currencyId = 3446,
    maxLevel = 6,
    ranks = {
      [1] = { itemLevel = 318, bonusId = 12849, rank = 6 },
      [2] = { itemLevel = 321, bonusId = 12850, rank = 6 },
      [3] = { itemLevel = 324, bonusId = 12851, rank = 6 },
      [4] = { itemLevel = 328, bonusId = 12852, rank = 6 },
      [5] = { itemLevel = 331, bonusId = 12853, rank = 6 },
      [6] = { itemLevel = 334, bonusId = 12854, rank = 6 },
    },
  },
}

local crestTrackLevels = {}
local crestBonusIdIndex = {}

local function isCrestCurrencyId(currencyId)
  return currencyId and NS.CREST_CURRENCY_ID_SET[currencyId] == true
end

local function storeTrackLevel(trackId, level, info)
  if not trackId or not level or not info then
    return
  end
  crestTrackLevels[trackId] = crestTrackLevels[trackId] or {}
  crestTrackLevels[trackId][level] = info
  if info.bonusId then
    crestBonusIdIndex[info.bonusId] = info
  end
end

local function rankInfoToEntry(trackId, level, rankInfo, maxLevel, currencyId)
  return {
    upgradeGroup = trackId,
    upgradeLevel = level,
    maxUpgradeLevel = maxLevel,
    rank = rankInfo.rank,
    itemLevel = rankInfo.itemLevel,
    currencyId = currencyId,
    bonusId = rankInfo.bonusId,
  }
end

local function seedTrackFromFallback(trackId)
  local track = MIDNIGHT_CREST_TRACKS[trackId]
  if not track or crestTrackLevels[trackId] then
    return
  end
  for level, rankInfo in pairs(track.ranks) do
    storeTrackLevel(trackId, level, rankInfoToEntry(trackId, level, rankInfo, track.maxLevel, track.currencyId))
  end
end

local function readCrestCurrencyFromLevelInfo(levelInfo)
  for _, entry in ipairs(levelInfo.currencyCostsToUpgrade or {}) do
    local currencyId = entry.currencyID or entry.currencyId
    if isCrestCurrencyId(currencyId) then
      return currencyId, entry.cost
    end
  end
  return nil
end

local function splitItemLinkPayload(link)
  if not link then
    return nil
  end
  local payload = link:match("|H(item:[^|]+)|") or link:match("^(item:[^|]+)")
  if not payload then
    return nil
  end
  return { strsplit(":", payload) }
end

local function parseCrestBonusIdFromLink(link)
  local parts = splitItemLinkPayload(link)
  if not parts then
    return nil
  end
  local numBonus = tonumber(parts[14]) or 0
  for i = 1, numBonus do
    local bonusId = tonumber(parts[14 + i])
    if bonusId and NS.isCrestUpgradeBonusId(bonusId) then
      return bonusId
    end
  end
  return nil
end

function NS.isCrestUpgradeBonusId(bonusId)
  bonusId = tonumber(bonusId)
  if not bonusId then
    return false
  end
  if crestBonusIdIndex[bonusId] then
    return true
  end
  return bonusId >= CREST_BONUS_ID_MIN and bonusId <= CREST_BONUS_ID_MAX
end

function NS.crestUpgradeDataReady()
  return next(MIDNIGHT_CREST_TRACKS) ~= nil
end

function NS.ingestCrestUpgradeTrackFromItemInfo(trackStringID, itemInfo, link)
  if not trackStringID or not itemInfo or not itemInfo.upgradeLevelInfos then
    return
  end

  local runningIlvl = itemInfo.minItemLevel or 0
  local maxLevel = itemInfo.maxUpgrade or #itemInfo.upgradeLevelInfos
  local defaultCurrencyId = MIDNIGHT_CREST_TRACKS[trackStringID] and MIDNIGHT_CREST_TRACKS[trackStringID].currencyId

  for _, levelInfo in ipairs(itemInfo.upgradeLevelInfos) do
    local level = levelInfo.upgradeLevel
    if level then
      if levelInfo.itemLevelIncrement and levelInfo.itemLevelIncrement > 0 then
        runningIlvl = runningIlvl + levelInfo.itemLevelIncrement
      end
      local currencyId = readCrestCurrencyFromLevelInfo(levelInfo) or defaultCurrencyId
      local entry = {
        upgradeGroup = trackStringID,
        upgradeLevel = level,
        maxUpgradeLevel = maxLevel,
        rank = levelInfo.displayQuality,
        itemLevel = runningIlvl > 0 and runningIlvl or nil,
        currencyId = currencyId,
      }
      local existing = crestTrackLevels[trackStringID] and crestTrackLevels[trackStringID][level]
      if existing and existing.bonusId then
        entry.bonusId = existing.bonusId
      end
      storeTrackLevel(trackStringID, level, entry)
    end
  end

  if link and itemInfo.currUpgrade then
    local bonusId = parseCrestBonusIdFromLink(link)
    if bonusId and crestTrackLevels[trackStringID] and crestTrackLevels[trackStringID][itemInfo.currUpgrade] then
      crestTrackLevels[trackStringID][itemInfo.currUpgrade].bonusId = bonusId
      crestBonusIdIndex[bonusId] = crestTrackLevels[trackStringID][itemInfo.currUpgrade]
    end
  end
end

function NS.ensureCrestTrackCached(trackStringID)
  if not trackStringID then
    return
  end
  if not crestTrackLevels[trackStringID] then
    seedTrackFromFallback(trackStringID)
  end
end

function NS.findCrestBonusInfoForGroupLevel(trackStringID, upgradeLevel)
  if not trackStringID or not upgradeLevel then
    return nil
  end
  NS.ensureCrestTrackCached(trackStringID)
  local track = crestTrackLevels[trackStringID]
  return track and track[upgradeLevel] or nil
end

function NS.findCrestBonusIdForGroupLevel(trackStringID, upgradeLevel)
  local info = NS.findCrestBonusInfoForGroupLevel(trackStringID, upgradeLevel)
  return info and info.bonusId or nil
end

-- Legacy alias: some call sites still refer to upgradeGroup; keys are trackStringID values.
NS.CREST_TRACK_STRING_ID_TO_GROUP = setmetatable({}, {
  __index = function(_, trackStringID)
    return trackStringID
  end,
})

-- Kept for call sites that iterate known crest bonus IDs on item links.
NS.CREST_BONUS_LOOKUP = setmetatable({}, {
  __index = function(_, bonusId)
    bonusId = tonumber(bonusId)
    if crestBonusIdIndex[bonusId] then
      return crestBonusIdIndex[bonusId]
    end
    if not NS.isCrestUpgradeBonusId(bonusId) then
      return nil
    end
    for trackId, track in pairs(MIDNIGHT_CREST_TRACKS) do
      for level, rankInfo in pairs(track.ranks) do
        if rankInfo.bonusId == bonusId then
          return rankInfoToEntry(trackId, level, rankInfo, track.maxLevel, track.currencyId)
        end
      end
    end
    return nil
  end,
})

local function redundancySlotContains(list, slot)
  if not slot then
    return false
  end
  for _, value in ipairs(list) do
    if value == slot then
      return true
    end
  end
  return false
end

local function safeItemUpgradeCall(fn, ...)
  if not fn then
    return nil
  end
  local ok, result = pcall(fn, ...)
  if ok then
    return result
  end
  return nil
end

local function crestItemRefCandidates(link, invSlot)
  local refs = {}
  local seen = {}
  local function addRef(ref)
    if ref and ref ~= "" and not seen[ref] then
      seen[ref] = true
      refs[#refs + 1] = ref
    end
  end

  if invSlot then
    addRef(GetInventoryItemLink("player", invSlot))
  end
  addRef(link)
  if invSlot and ItemLocation and C_Item and C_Item.GetItemLink then
    local loc = ItemLocation:CreateFromEquipmentSlot(invSlot)
    if loc and loc.IsValid and loc:IsValid() then
      addRef(safeItemUpgradeCall(C_Item.GetItemLink, loc))
    end
  end
  if link then
    local itemID = tonumber(link:match("item:(%d+)"))
    if itemID then
      addRef(itemID)
    end
  end
  return refs
end

local function invSlotToRedundancySlot(invSlot)
  if not invSlot or not Enum or not Enum.ItemRedundancySlot then
    return nil
  end
  local map = {
    [1] = Enum.ItemRedundancySlot.Head,
    [2] = Enum.ItemRedundancySlot.Neck,
    [3] = Enum.ItemRedundancySlot.Shoulder,
    [4] = Enum.ItemRedundancySlot.Chest,
    [5] = Enum.ItemRedundancySlot.Chest,
    [6] = Enum.ItemRedundancySlot.Waist,
    [7] = Enum.ItemRedundancySlot.Legs,
    [8] = Enum.ItemRedundancySlot.Feet,
    [9] = Enum.ItemRedundancySlot.Wrist,
    [10] = Enum.ItemRedundancySlot.Hand,
    [11] = Enum.ItemRedundancySlot.Finger,
    [12] = Enum.ItemRedundancySlot.FingerSecondary or Enum.ItemRedundancySlot.Finger,
    [13] = Enum.ItemRedundancySlot.Trinket,
    [14] = Enum.ItemRedundancySlot.TrinketSecondary,
    [15] = Enum.ItemRedundancySlot.Back,
    [16] = Enum.ItemRedundancySlot.MainhandWeapon,
    [17] = Enum.ItemRedundancySlot.Offhand,
  }
  return map[invSlot]
end

function NS.resolveCrestHighWatermarkSlot(link, invSlot, hwmSlotOverride)
  if hwmSlotOverride then
    return hwmSlotOverride
  end
  local getHwmSlot = C_ItemUpgrade and C_ItemUpgrade.GetHighWatermarkSlotForItem
  if getHwmSlot then
    for _, ref in ipairs(crestItemRefCandidates(link, invSlot)) do
      local slot = safeItemUpgradeCall(getHwmSlot, ref)
      if slot then
        return slot
      end
    end
  end
  if link and Enum and Enum.ItemRedundancySlot then
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
    if equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" then
      return Enum.ItemRedundancySlot.Twohand
    elseif equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" then
      return Enum.ItemRedundancySlot.MainhandWeapon
    elseif equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then
      return Enum.ItemRedundancySlot.Offhand
    end
  end
  return invSlotToRedundancySlot(invSlot)
end

local function readCharacterAndAccountWatermarkForSlot(hwmSlot)
  local getSlotHwm = C_ItemUpgrade and C_ItemUpgrade.GetHighWatermarkForSlot
  if not getSlotHwm or not hwmSlot then
    return 0, 0
  end
  local ok, characterHwm, accountHwm = pcall(getSlotHwm, hwmSlot)
  if not ok then
    return 0, 0
  end
  return characterHwm or 0, accountHwm or 0
end

local function getRedundancySlotPeers(hwmSlot)
  if not hwmSlot then
    return {}
  end
  if not Enum or not Enum.ItemRedundancySlot then
    return { hwmSlot }
  end
  local fingerSecondary = Enum.ItemRedundancySlot.FingerSecondary or Enum.ItemRedundancySlot.Finger
  local trinketSecondary = Enum.ItemRedundancySlot.TrinketSecondary or Enum.ItemRedundancySlot.Trinket
  if hwmSlot == Enum.ItemRedundancySlot.Finger or hwmSlot == fingerSecondary then
    return { Enum.ItemRedundancySlot.Finger, fingerSecondary }
  end
  if hwmSlot == Enum.ItemRedundancySlot.Trinket or hwmSlot == trinketSecondary then
    return { Enum.ItemRedundancySlot.Trinket, trinketSecondary }
  end
  return { hwmSlot }
end

local function readWatermarkForSlotGroup(hwmSlot)
  local characterMax = 0
  local accountMax = 0
  for _, slot in ipairs(getRedundancySlotPeers(hwmSlot)) do
    local characterHwm, accountHwm = readCharacterAndAccountWatermarkForSlot(slot)
    if characterHwm > characterMax then
      characterMax = characterHwm
    end
    if accountHwm > accountMax then
      accountMax = accountHwm
    end
  end
  return characterMax, accountMax
end

function NS.getCharacterCrestUpgradeWatermarks(link, invSlot, hwmSlotOverride, wmState)
  if not C_ItemUpgrade then
    return 0, 0
  end

  local getSlotHwm = C_ItemUpgrade.GetHighWatermarkForSlot
  local getItemHwm = C_ItemUpgrade.GetHighWatermarkForItem
  if not getSlotHwm and not getItemHwm then
    return 0, 0
  end

  local weaponSlots = {}
  if Enum and Enum.ItemRedundancySlot then
    weaponSlots = {
      Enum.ItemRedundancySlot.Twohand,
      Enum.ItemRedundancySlot.OnehandWeapon,
      Enum.ItemRedundancySlot.MainhandWeapon,
      Enum.ItemRedundancySlot.Offhand,
    }
  end

  local hwmSlot = NS.resolveCrestHighWatermarkSlot(link, invSlot, hwmSlotOverride)
  local characterHWM = 0
  local accountHWM = 0

  if hwmSlot and getSlotHwm and #weaponSlots > 0 and redundancySlotContains(weaponSlots, hwmSlot) then
    local twoHandCharacter, twoHandAccount = readCharacterAndAccountWatermarkForSlot(Enum.ItemRedundancySlot.Twohand)
    local oneHandCharacter, oneHandAccount = readCharacterAndAccountWatermarkForSlot(Enum.ItemRedundancySlot.OnehandWeapon)
    local mainHandCharacter, mainHandAccount = readCharacterAndAccountWatermarkForSlot(Enum.ItemRedundancySlot.MainhandWeapon)
    local offHandCharacter, offHandAccount = readCharacterAndAccountWatermarkForSlot(Enum.ItemRedundancySlot.Offhand)

    local highestCharacter = 0
    local highestAccount = 0
    if twoHandCharacter > highestCharacter then
      highestCharacter = twoHandCharacter
    end
    if twoHandAccount > highestAccount then
      highestAccount = twoHandAccount
    end
    if oneHandCharacter > highestCharacter then
      highestCharacter = oneHandCharacter
    end
    if oneHandAccount > highestAccount then
      highestAccount = oneHandAccount
    end
    if mainHandCharacter > highestCharacter and offHandCharacter > highestCharacter then
      highestCharacter = math.min(mainHandCharacter, offHandCharacter)
    end
    if mainHandAccount > highestAccount and offHandAccount > highestAccount then
      highestAccount = math.min(mainHandAccount, offHandAccount)
    end

    characterHWM, accountHWM = readWatermarkForSlotGroup(hwmSlot)
    if highestCharacter > characterHWM then
      characterHWM = highestCharacter
    end
    if highestAccount > accountHWM then
      accountHWM = highestAccount
    end
  elseif hwmSlot and getSlotHwm then
    characterHWM, accountHWM = readWatermarkForSlotGroup(hwmSlot)
  elseif getItemHwm then
    for _, ref in ipairs(crestItemRefCandidates(link, invSlot)) do
      local ok, itemCharHwm, itemAccountHwm = pcall(getItemHwm, ref)
      if ok then
        if itemCharHwm and itemCharHwm > characterHWM then
          characterHWM = itemCharHwm
        end
        if itemAccountHwm and itemAccountHwm > accountHWM then
          accountHWM = itemAccountHwm
        end
      end
    end
  end

  if wmState and hwmSlot and wmState[hwmSlot] then
    characterHWM = math.max(characterHWM, wmState[hwmSlot])
  end

  return characterHWM or 0, accountHWM or 0
end

function NS.getCharacterCrestHighWatermark(link, invSlot, hwmSlotOverride)
  local characterHWM = NS.getCharacterCrestUpgradeWatermarks(link, invSlot, hwmSlotOverride)
  return characterHWM
end

function NS.computeCrestUpgradeCost(link, invSlot, targetItemLevel, baseCost, opts)
  opts = opts or {}
  baseCost = baseCost or NS.CREST_UPGRADE_COST_AMOUNT or 20
  if not targetItemLevel then
    return baseCost, baseCost, false
  end

  local characterHWM, accountHWM = NS.getCharacterCrestUpgradeWatermarks(
    link, invSlot, opts.hwmSlot, opts.wmState)

  if characterHWM > 0 and targetItemLevel <= characterHWM then
    return 0, baseCost, true
  end

  if accountHWM > 0 and targetItemLevel <= accountHWM then
    local discounted = math.floor(baseCost * (NS.CREST_ACCOUNT_DISCOUNT_MULTIPLIER or 0.5) + 0.5)
    return discounted, baseCost, discounted < baseCost
  end

  return baseCost, baseCost, false
end

function NS.applyCrestWatermarkDiscount(link, targetItemLevel, baseCost, invSlot, hwmSlotOverride, wmState)
  return NS.computeCrestUpgradeCost(link, invSlot, targetItemLevel, baseCost, {
    hwmSlot = hwmSlotOverride,
    wmState = wmState,
  })
end
