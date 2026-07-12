local ADDON_NAME, NS = ...
NS.Predictor = NS.Predictor or {}
local function getEquipSlotCandidates(itemRef)
  local itemLink = NS.itemRefToLink(itemRef)
  local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)
  if not equipLoc then
    return nil
  end
  return NS.INVTYPE_TO_SLOT_IDS[equipLoc]
end

local function getSlotItemRef(slotId)
  local invSlot = GetInventorySlotInfo(NS.SLOT_ID_TO_NAME[slotId])
  if not invSlot then
    return nil
  end
  local link = GetInventoryItemLink("player", invSlot)
  if not link then
    return nil
  end
  local guid
  if slotId == 16 or slotId == 17 then
    guid = NS.getGuidFromEquipmentSlot(slotId)
  end
  return { link = link, guid = guid, slotId = slotId }
end

local function is2HWeapon(itemLink)
  if not itemLink then return false end
  local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)
  return equipLoc == "INVTYPE_2HWEAPON"
end

local WEAPON_SUBCLASS = {
  AXE1 = 0,
  AXE2 = 1,
  MACE1 = 4,
  MACE2 = 5,
  POLEARM = 6,
  SWORD1 = 7,
  SWORD2 = 8,
  STAFF = 10,
  FIST = 13,
  DAGGER = 15,
  BOW = 2,
  GUN = 3,
  CROSSBOW = 18,
  WAND = 19,
  WARGLAIVE = 9,
}

local CLASS_WEAPON_RULES = {
  DEATHKNIGHT = {
    weapon_subclasses = {
      [WEAPON_SUBCLASS.AXE1] = true, [WEAPON_SUBCLASS.AXE2] = true,
      [WEAPON_SUBCLASS.MACE1] = true, [WEAPON_SUBCLASS.MACE2] = true,
      [WEAPON_SUBCLASS.SWORD1] = true, [WEAPON_SUBCLASS.SWORD2] = true,
      [WEAPON_SUBCLASS.POLEARM] = true,
    },
    allow_shield = false,
    allow_holdable = false,
  },
  DEMONHUNTER = {
    weapon_subclasses = {
      [WEAPON_SUBCLASS.AXE1] = true,
      [WEAPON_SUBCLASS.SWORD1] = true,
      [WEAPON_SUBCLASS.FIST] = true,
      [WEAPON_SUBCLASS.WARGLAIVE] = true,
    },
    allow_shield = false,
    allow_holdable = false,
  },
  DRUID = {
    weapon_subclasses = {
      [WEAPON_SUBCLASS.DAGGER] = true,
      [WEAPON_SUBCLASS.FIST] = true,
      [WEAPON_SUBCLASS.MACE1] = true,
      [WEAPON_SUBCLASS.MACE2] = true,
      [WEAPON_SUBCLASS.POLEARM] = true,
      [WEAPON_SUBCLASS.STAFF] = true,
    },
    allow_shield = false,
    allow_holdable = false,
  },
  EVOKER = {
    weapon_subclasses = {
      [WEAPON_SUBCLASS.AXE1] = true,
      [WEAPON_SUBCLASS.DAGGER] = true,
      [WEAPON_SUBCLASS.FIST] = true,
      [WEAPON_SUBCLASS.MACE1] = true,
      [WEAPON_SUBCLASS.SWORD1] = true,
      [WEAPON_SUBCLASS.STAFF] = true,
    },
    allow_shield = false,
    allow_holdable = true,
  },
  HUNTER = {
    weapon_subclasses = {
      [WEAPON_SUBCLASS.AXE1] = true, [WEAPON_SUBCLASS.AXE2] = true,
      [WEAPON_SUBCLASS.SWORD1] = true, [WEAPON_SUBCLASS.SWORD2] = true,
      [WEAPON_SUBCLASS.POLEARM] = true,
      [WEAPON_SUBCLASS.STAFF] = true,
      [WEAPON_SUBCLASS.BOW] = true,
      [WEAPON_SUBCLASS.GUN] = true,
      [WEAPON_SUBCLASS.CROSSBOW] = true,
    },
    allow_shield = false,
    allow_holdable = false,
  },
  MAGE = {
    weapon_subclasses = {
      [WEAPON_SUBCLASS.DAGGER] = true,
      [WEAPON_SUBCLASS.SWORD1] = true,
      [WEAPON_SUBCLASS.STAFF] = true,
      [WEAPON_SUBCLASS.WAND] = true,
    },
    allow_shield = false,
    allow_holdable = true,
  },
  MONK = {
    weapon_subclasses = {
      [WEAPON_SUBCLASS.AXE1] = true,
      [WEAPON_SUBCLASS.MACE1] = true,
      [WEAPON_SUBCLASS.SWORD1] = true,
      [WEAPON_SUBCLASS.POLEARM] = true,
      [WEAPON_SUBCLASS.STAFF] = true,
      [WEAPON_SUBCLASS.FIST] = true,
    },
    allow_shield = false,
    allow_holdable = false,
  },
  PALADIN = {
    weapon_subclasses = {
      [WEAPON_SUBCLASS.AXE1] = true, [WEAPON_SUBCLASS.AXE2] = true,
      [WEAPON_SUBCLASS.MACE1] = true, [WEAPON_SUBCLASS.MACE2] = true,
      [WEAPON_SUBCLASS.SWORD1] = true, [WEAPON_SUBCLASS.SWORD2] = true,
      [WEAPON_SUBCLASS.POLEARM] = true,
    },
    allow_shield = true,
    allow_holdable = false,
  },
  PRIEST = {
    weapon_subclasses = {
      [WEAPON_SUBCLASS.DAGGER] = true,
      [WEAPON_SUBCLASS.MACE1] = true,
      [WEAPON_SUBCLASS.STAFF] = true,
      [WEAPON_SUBCLASS.WAND] = true,
    },
    allow_shield = false,
    allow_holdable = true,
  },
  ROGUE = {
    weapon_subclasses = {
      [WEAPON_SUBCLASS.AXE1] = true,
      [WEAPON_SUBCLASS.MACE1] = true,
      [WEAPON_SUBCLASS.SWORD1] = true,
      [WEAPON_SUBCLASS.DAGGER] = true,
      [WEAPON_SUBCLASS.FIST] = true,
    },
    allow_shield = false,
    allow_holdable = false,
  },
  SHAMAN = {
    weapon_subclasses = {
      [WEAPON_SUBCLASS.AXE1] = true, [WEAPON_SUBCLASS.AXE2] = true,
      [WEAPON_SUBCLASS.MACE1] = true, [WEAPON_SUBCLASS.MACE2] = true,
      [WEAPON_SUBCLASS.STAFF] = true,
      [WEAPON_SUBCLASS.DAGGER] = true,
      [WEAPON_SUBCLASS.FIST] = true,
    },
    allow_shield = true,
    allow_holdable = true,
  },
  WARLOCK = {
    weapon_subclasses = {
      [WEAPON_SUBCLASS.DAGGER] = true,
      [WEAPON_SUBCLASS.SWORD1] = true,
      [WEAPON_SUBCLASS.STAFF] = true,
      [WEAPON_SUBCLASS.WAND] = true,
    },
    allow_shield = false,
    allow_holdable = true,
  },
  WARRIOR = {
    weapon_subclasses = {
      [WEAPON_SUBCLASS.AXE1] = true, [WEAPON_SUBCLASS.AXE2] = true,
      [WEAPON_SUBCLASS.MACE1] = true, [WEAPON_SUBCLASS.MACE2] = true,
      [WEAPON_SUBCLASS.SWORD1] = true, [WEAPON_SUBCLASS.SWORD2] = true,
      [WEAPON_SUBCLASS.POLEARM] = true,
      [WEAPON_SUBCLASS.STAFF] = true,
      [WEAPON_SUBCLASS.DAGGER] = true,
      [WEAPON_SUBCLASS.FIST] = true,
    },
    allow_shield = true,
    allow_holdable = false,
  },
}

local SPEC_OFFHAND_WEAPON_ALLOWED = {
  Death_Knight_Frost = true,
  Demon_Hunter_Havoc = true,
  Demon_Hunter_Vengeance = true,
  Monk_Brewmaster = true,
  Monk_Windwalker = true,
  Rogue_Assassination = true,
  Rogue_Outlaw = true,
  Rogue_Subtlety = true,
  Shaman_Enhancement = true,
  Warrior_Fury = true,
}

local function getItemTypeInfo(itemLink)
  if not itemLink then
    return nil, nil, nil
  end

  local _, _, _, itemEquipLoc, _, itemClassID, itemSubClassID = GetItemInfoInstant(itemLink)
  if itemEquipLoc and itemEquipLoc ~= "" then
    return itemClassID, itemSubClassID, itemEquipLoc
  end

  local _, _, _, _, _, itemClassID2, itemSubClassID2, _, equipLoc2 = GetItemInfo(itemLink)
  return itemClassID2, itemSubClassID2, equipLoc2
end

local function isWeaponSubclassAllowedForClass(classToken, subClassID)
  local rules = CLASS_WEAPON_RULES[classToken]
  if not rules or type(rules.weapon_subclasses) ~= "table" then
    return false
  end
  return rules.weapon_subclasses[subClassID] == true
end

local function isSpecAllowedWeaponOffhand(specKey)
  local classPart, specPart = NS.getClassSpecPair(specKey)
  if not classPart or not specPart then
    return false
  end
  return SPEC_OFFHAND_WEAPON_ALLOWED[classPart .. "_" .. specPart] == true
end

local function isOffhandTypeAllowedForClass(classToken, equipLoc)
  local rules = CLASS_WEAPON_RULES[classToken]
  if not rules then
    return false
  end
  if equipLoc == "INVTYPE_SHIELD" then
    return rules.allow_shield == true
  end
  if equipLoc == "INVTYPE_HOLDABLE" then
    return rules.allow_holdable == true
  end
  return false
end

local function isItemAllowedForMainHand(classToken, itemClassID, itemSubClassID, equipLoc)
  if not classToken then
    return false
  end
  if equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then
    return false
  end
  if itemClassID ~= 2 then -- Weapon
    return false
  end
  return isWeaponSubclassAllowedForClass(classToken, itemSubClassID)
end

local function isItemAllowedForOffHand(classToken, specKey, itemClassID, itemSubClassID, equipLoc)
  if not classToken then
    return false
  end
  if equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then
    return isOffhandTypeAllowedForClass(classToken, equipLoc)
  end
  if itemClassID ~= 2 then -- Weapon
    return false
  end
  if not isWeaponSubclassAllowedForClass(classToken, itemSubClassID) then
    return false
  end
  return isSpecAllowedWeaponOffhand(specKey)
end

local function isArmorCandidateAllowedForClass(classToken, itemClassID, itemSubClassID)
  if itemClassID ~= 4 then
    return true
  end
  if itemSubClassID == 0 or itemSubClassID == 6 then
    return true
  end
  local primaryArmor = NS.CLASS_PRIMARY_ARMOR[classToken]
  return (not primaryArmor) or itemSubClassID == primaryArmor
end

local function makeStatsBuffer()
  return {
    primary_stat = 0,
    crit = 0,
    haste = 0,
    mastery = 0,
    versatility = 0,
  }
end

local function refreshPredictionContext(context)
  context.generation = NS.predictionContextGeneration or 0
  context.baseStats = NS.getPlayerStatVector()
  context.basePredBySpec = {}
  context.equippedRefs = {}
  context.ownedWeaponCandidates = nil
  context.predictionStats = context.predictionStats or makeStatsBuffer()
  context.weaponDeltaStats = context.weaponDeltaStats or makeStatsBuffer()
  return context
end

local function createPredictionContext()
  return refreshPredictionContext({})
end

local function ensurePredictionContext(context)
  if context and (
    context.generation ~= (NS.predictionContextGeneration or 0)
      or not context.baseStats
      or not context.basePredBySpec
      or not context.equippedRefs
      or not context.predictionStats
      or not context.weaponDeltaStats
  ) then
    refreshPredictionContext(context)
  end
  return context
end

local function getContextSlotItemRef(context, slotId)
  if not context then
    return getSlotItemRef(slotId)
  end
  ensurePredictionContext(context)
  local cached = context.equippedRefs[slotId]
  if cached == nil then
    cached = getSlotItemRef(slotId) or false
    context.equippedRefs[slotId] = cached
  end
  return cached or nil
end

local function getContextBase(context, specKey)
  if not context then
    local baseStats = NS.getPlayerStatVector()
    return baseStats, NS.getCachedBaseDps(baseStats, specKey)
  end
  ensurePredictionContext(context)
  local basePred = context.basePredBySpec[specKey]
  if basePred == nil then
    basePred = NS.getCachedBaseDps(context.baseStats, specKey)
    context.basePredBySpec[specKey] = basePred
  end
  return context.baseStats, basePred
end

local function statsWithDelta(base, delta, context)
  if context and NS.addStatsInto then
    return NS.addStatsInto(context.predictionStats, base, delta, 1)
  end
  return NS.addStats(base, delta, 1)
end

local function isSameItemRef(a, b)
  if not a or not b then
    return false
  end
  local aGuid = a.guid or a.itemGUID
  local bGuid = b.guid or b.itemGUID
  if aGuid and bGuid then
    return aGuid == bGuid
  end
  return NS.itemRefToLink(a) == NS.itemRefToLink(b)
end

local function isWeaponLikeEquipLoc(equipLoc)
  return equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_2HWEAPON"
    or equipLoc == "INVTYPE_WEAPONMAINHAND" or equipLoc == "INVTYPE_WEAPONOFFHAND"
    or equipLoc == "INVTYPE_HOLDABLE" or equipLoc == "INVTYPE_SHIELD"
end

local function collectOwnedWeaponCandidates(context)
  if context then
    ensurePredictionContext(context)
    if context.ownedWeaponCandidates then
      return context.ownedWeaponCandidates
    end
  end

  local out = {}

  local mh = getContextSlotItemRef(context, 16)
  if mh and mh.link then
    mh.itemClassID, mh.itemSubClassID, mh.equipLoc = getItemTypeInfo(mh.link)
    table.insert(out, mh)
  end
  local oh = getContextSlotItemRef(context, 17)
  if oh and oh.link then
    oh.itemClassID, oh.itemSubClassID, oh.equipLoc = getItemTypeInfo(oh.link)
    table.insert(out, oh)
  end

  if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
    for bag = 0, 4 do
      for slot = 1, C_Container.GetContainerNumSlots(bag) do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.hyperlink then
          local itemClassID, itemSubClassID, equipLoc = getItemTypeInfo(info.hyperlink)
          if isWeaponLikeEquipLoc(equipLoc) then
            table.insert(out, {
              link = info.hyperlink,
              guid = info["itemGUID"] or info["guid"] or NS.getGuidFromBagSlot(bag, slot),
              bag = bag,
              slot = slot,
              itemClassID = itemClassID,
              itemSubClassID = itemSubClassID,
              equipLoc = equipLoc,
            })
          end
        end
      end
    end
  end

  if context then
    context.ownedWeaponCandidates = out
  end
  return out
end

local ZERO_STATS = NS.ZERO_STATS

local function clearStatsBuffer(stats)
  stats.primary_stat = 0
  stats.crit = 0
  stats.haste = 0
  stats.mastery = 0
  stats.versatility = 0
  return stats
end

local function returnWeaponDelta(delta, out)
  if not out then
    return delta or ZERO_STATS
  end
  clearStatsBuffer(out)
  if delta and NS.addStatsInto then
    NS.addStatsInto(out, out, delta, 1)
  end
  return out
end

local function isEmptyWeaponCandidate(cand)
  if not cand or not cand.key then
    return true
  end
  return cand.key:sub(1, 6) == "empty:"
end

local function predictDelta(base, stats, specKey, basePred)
  local pred = NS.getCachedPrediction(stats, specKey)
  return pred, pred - basePred
end

-- Combined MH+OH stat delta for loadout search (matches tooltip weapon math).
function NS.computeWeaponLoadoutDelta(mhCand, ohCand, eqMh, eqOh, specKey, out)
  mhCand = mhCand or eqMh
  ohCand = ohCand or eqOh
  local mhRef = NS.candidateRefFromCand(mhCand, 16)
  local ohRef = NS.candidateRefFromCand(ohCand, 17)
  local eqMhRef = NS.candidateRefFromCand(eqMh, 16)
  local eqOhRef = NS.candidateRefFromCand(eqOh, 17)

  local mhLink = mhRef and NS.itemRefToLink(mhRef)
  local ohLink = ohRef and NS.itemRefToLink(ohRef)
  local eqMhLink = eqMhRef and NS.itemRefToLink(eqMhRef)
  local eqOhLink = eqOhRef and NS.itemRefToLink(eqOhRef)

  local mhEmpty = isEmptyWeaponCandidate(mhCand)
  local ohEmpty = isEmptyWeaponCandidate(ohCand)

  if mhEmpty and ohEmpty then
    return returnWeaponDelta(nil, out)
  end

  local mhSame = eqMh and mhCand and eqMh.key and mhCand.key and eqMh.key == mhCand.key
  local ohSame = eqOh and ohCand and eqOh.key and ohCand.key and eqOh.key == ohCand.key
  if mhSame and ohSame then
    return returnWeaponDelta(nil, out)
  end

  local newIs2H = mhLink and NS.is2HWeapon(mhLink)
  local eqIs2H = eqMhLink and NS.is2HWeapon(eqMhLink)

  if newIs2H then
    if eqMhRef and eqMhLink then
      if eqOhRef and eqOhLink and not eqIs2H then
        local delta = NS.computeStatDelta(mhRef, eqMhRef, { pairedRef = eqOhRef, addPaired = false })
        return returnWeaponDelta(delta, out)
      end
      local delta = NS.computeStatDelta(mhRef, eqMhRef)
      return returnWeaponDelta(delta, out)
    end
    return returnWeaponDelta(nil, out)
  end

  if eqIs2H and eqMhRef then
    if ohEmpty or not ohRef then
      return returnWeaponDelta(nil, out)
    end
    local delta = NS.computeStatDelta(mhRef, eqMhRef, { pairedRef = ohRef, addPaired = true })
    return returnWeaponDelta(delta, out)
  end

  local total = clearStatsBuffer(out or makeStatsBuffer())
  if not mhEmpty and mhRef and eqMhRef and not mhSame then
    local delta = NS.computeStatDelta(mhRef, eqMhRef)
    if delta then
      NS.addStatsInto(total, total, delta, 1)
    end
  end
  if not ohEmpty and ohRef then
    if eqOhRef and not ohSame then
      local delta = NS.computeStatDelta(ohRef, eqOhRef)
      if delta then
        NS.addStatsInto(total, total, delta, 1)
      end
    elseif not eqOhRef then
      local ohStats = ohCand and ohCand.stats
      if not ohStats and ohLink then
        ohStats = NS.statsFromItemLink(ohLink)
      end
      if ohStats then
        NS.addStatsInto(total, total, ohStats, 1)
      end
    end
  end
  return total
end

function NS.computeWeaponPairDpsDelta(mhCand, ohCand, eqMh, eqOh, specKey, context)
  if not specKey or not NS.computeWeaponLoadoutDelta then
    return nil
  end
  local baseStats, basePred = getContextBase(context, specKey)
  local out = context and context.weaponDeltaStats or nil
  local wdelta = NS.computeWeaponLoadoutDelta(mhCand, ohCand, eqMh, eqOh, specKey, out)
  local stats = statsWithDelta(baseStats, wdelta, context)
  return NS.getCachedPrediction(stats, specKey) - basePred
end

local function findBestPairScenario(
  candidateRef,
  mainHandRef,
  specKey,
  classToken,
  candidateIsOffHandOnly,
  base,
  basePred,
  context
)
  local best = nil
  local lastErr = nil

  for _, pairRef in ipairs(collectOwnedWeaponCandidates(context)) do
    if not isSameItemRef(pairRef, candidateRef) then
      local pairLink = NS.itemRefToLink(pairRef)
      if pairLink then
        local pairClassID = pairRef.itemClassID
        local pairSubClassID = pairRef.itemSubClassID
        local pairEquipLoc = pairRef.equipLoc
        if not pairEquipLoc then
          pairClassID, pairSubClassID, pairEquipLoc = getItemTypeInfo(pairLink)
        end
        local validPair = false

        if candidateIsOffHandOnly then
          -- Need a 1H mainhand-capable weapon to pair with the hovered offhand item.
          validPair = (not is2HWeapon(pairLink))
            and isItemAllowedForMainHand(classToken, pairClassID, pairSubClassID, pairEquipLoc)
        else
          -- Need a valid offhand item to pair with the hovered 1H mainhand item.
          validPair = isItemAllowedForOffHand(classToken, specKey, pairClassID, pairSubClassID, pairEquipLoc)
        end

        if validPair then
          local stats, err
          if candidateIsOffHandOnly then
            stats, err = NS.computeStatDelta(pairRef, mainHandRef, { pairedRef = candidateRef, addPaired = true })
          else
            stats, err = NS.computeStatDelta(candidateRef, mainHandRef, { pairedRef = pairRef, addPaired = true })
          end

          if stats then
            local newStats = statsWithDelta(base, stats, context)
            local pred, delta = predictDelta(base, newStats, specKey, basePred)
            if not best or delta > best.dps_delta then
              best = {
                dps_base = basePred,
                dps_new = pred,
                dps_delta = delta,
                slot_id = 16,
                mode = "dw_pair_replacement",
              }
            end
          else
            lastErr = err or lastErr
          end
        end
      end
    end
  end

  return best, lastErr
end

-- Weapon loadout profiles:
-- two_handed = spec can use a 2H loadout
-- dual_wield = spec can use a 2x1H loadout (including off-hand/shield/holdable in slot 17)
local SPEC_WEAPON_LOADOUTS = {
  Death_Knight_Blood = { two_handed = true, dual_wield = false },
  Death_Knight_Frost = { two_handed = true, dual_wield = true },
  Death_Knight_Unholy = { two_handed = true, dual_wield = false },

  Demon_Hunter_Havoc = { two_handed = false, dual_wield = true },
  Demon_Hunter_Vengeance = { two_handed = false, dual_wield = true },

  Druid_Balance = { two_handed = true, dual_wield = true },
  Druid_Feral = { two_handed = true, dual_wield = false },
  Druid_Guardian = { two_handed = true, dual_wield = false },

  Evoker_Devastation = { two_handed = true, dual_wield = true },

  Hunter_Beast_Mastery = { two_handed = true, dual_wield = false },
  Hunter_Marksmanship = { two_handed = true, dual_wield = false },
  Hunter_Survival = { two_handed = true, dual_wield = false },

  Mage_Arcane = { two_handed = true, dual_wield = true },
  Mage_Fire = { two_handed = true, dual_wield = true },
  Mage_Frost = { two_handed = true, dual_wield = true },

  Monk_Brewmaster = { two_handed = true, dual_wield = true },
  Monk_Windwalker = { two_handed = true, dual_wield = true },

  Paladin_Protection = { two_handed = false, dual_wield = true },
  Paladin_Retribution = { two_handed = true, dual_wield = false },

  Priest_Shadow = { two_handed = true, dual_wield = true },

  Rogue_Assassination = { two_handed = false, dual_wield = true },
  Rogue_Outlaw = { two_handed = false, dual_wield = true },
  Rogue_Subtlety = { two_handed = false, dual_wield = true },

  Shaman_Elemental = { two_handed = true, dual_wield = true },
  Shaman_Enhancement = { two_handed = false, dual_wield = true },

  Warlock_Affliction = { two_handed = true, dual_wield = true },
  Warlock_Demonology = { two_handed = true, dual_wield = true },
  Warlock_Destruction = { two_handed = true, dual_wield = true },

  Warrior_Arms = { two_handed = true, dual_wield = false },
  Warrior_Fury = { two_handed = true, dual_wield = true },
  Warrior_Protection = { two_handed = false, dual_wield = true },
}

local function getWeaponLoadoutForSpec(specKey)
  local classPart, specPart = NS.getClassSpecPair(specKey)
  if not classPart or not specPart then
    return { two_handed = true, dual_wield = true }
  end

  local key = classPart .. "_" .. specPart
  return SPEC_WEAPON_LOADOUTS[key] or { two_handed = true, dual_wield = true }
end

local function isWeaponEquipLoc(equipLoc)
  return equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_2HWEAPON"
    or equipLoc == "INVTYPE_WEAPONMAINHAND" or equipLoc == "INVTYPE_WEAPONOFFHAND"
    or equipLoc == "INVTYPE_HOLDABLE" or equipLoc == "INVTYPE_SHIELD"
end

local function evaluateWeaponItem(itemRef, itemLink, specKey, base, basePred, candidateEquipLoc, context)
    local lastErr = nil
    local _, classToken = UnitClass("player")
    local itemClassID, itemSubClassID = getItemTypeInfo(itemLink)
    local mainHandRef = getContextSlotItemRef(context, 16)
    local offHandRef = getContextSlotItemRef(context, 17)
    local currentIs2H = is2HWeapon(mainHandRef and mainHandRef.link)
    local candidateIs2H = is2HWeapon(itemLink)
    local candidateIsOffHandOnly = (candidateEquipLoc == "INVTYPE_WEAPONOFFHAND" or candidateEquipLoc == "INVTYPE_HOLDABLE" or candidateEquipLoc == "INVTYPE_SHIELD")
    local loadout = getWeaponLoadoutForSpec(specKey)
    local results = {}

    if candidateIsOffHandOnly then
      if not isItemAllowedForOffHand(classToken, specKey, itemClassID, itemSubClassID, candidateEquipLoc) then
        return nil, "off-hand item type is not allowed for this class/spec"
      end
    else
      if not isItemAllowedForMainHand(classToken, itemClassID, itemSubClassID, candidateEquipLoc) then
        return nil, "weapon type is not allowed for this class"
      end
    end

    -- Candidate is 2H: compare against current loadout if spec supports 2H.
    if candidateIs2H then
      if not loadout.two_handed then
        return nil, "2H weapons are not supported for this spec"
      end

      if mainHandRef then
        local stats, err
        if offHandRef and not currentIs2H then
          stats, err = NS.computeStatDelta(itemRef, mainHandRef, { pairedRef = offHandRef, addPaired = false })
        else
          stats, err = NS.computeStatDelta(itemRef, mainHandRef)
        end

        if stats then
          local withNew = statsWithDelta(base, stats, context)
          local pred, delta = predictDelta(base, withNew, specKey, basePred)
          table.insert(results, { dps_base = basePred, dps_new = pred, dps_delta = delta, slot_id = 16, mode = "2h_replacement" })
        else
          lastErr = err or lastErr
        end
      end

      if #results > 0 then
        return results
      end
      return nil, (lastErr or "native comparison unavailable for weapon")
    end

    -- Candidate is offhand-only: compare against offhand slot when dual loadout is supported.
    if candidateIsOffHandOnly then
      if not loadout.dual_wield then
        return nil, "off-hand weapons are not supported for this spec"
      end
      if currentIs2H then
        if mainHandRef then
          local pairResult, pairErr = findBestPairScenario(
            itemRef, mainHandRef, specKey, classToken, true, base, basePred, context
          )
          if pairResult then
            table.insert(results, pairResult)
            return results
          end
          return nil, (pairErr or "no compatible main-hand pair found for this off-hand item")
        end
        return nil, "native comparison unavailable for weapon"
      end
        if offHandRef then
        local ohStats, err = NS.computeStatDelta(itemRef, offHandRef)
        if ohStats then
          local withNew = statsWithDelta(base, ohStats, context)
          local pred, delta = predictDelta(base, withNew, specKey, basePred)
          table.insert(results, { dps_base = basePred, dps_new = pred, dps_delta = delta, slot_id = 17, mode = "oh_replacement" })
        else
          lastErr = err or lastErr
        end
        else
          local ohStats = NS.statsFromItemLink(itemLink) or {
            primary_stat = 0,
            crit = 0,
            haste = 0,
            mastery = 0,
            versatility = 0,
          }
          local withNew = statsWithDelta(base, ohStats, context)
          local pred, delta = predictDelta(base, withNew, specKey, basePred)
          table.insert(results, { dps_base = basePred, dps_new = pred, dps_delta = delta, slot_id = 17, mode = "oh_replacement" })
      end

      if #results > 0 then
        return results
      end
      return nil, (lastErr or "native comparison unavailable for weapon")
    end

    -- Candidate is 1H mainhand-compatible: evaluate dual-wield scenarios when supported.
    if loadout.dual_wield then
      -- Scenario 1: mainhand replacement (only when currently dual-wielding).
      if mainHandRef and not currentIs2H then
        local mhStats, err = NS.computeStatDelta(itemRef, mainHandRef)
        if mhStats then
          local newStats = statsWithDelta(base, mhStats, context)
          local pred1, delta1 = predictDelta(base, newStats, specKey, basePred)
          table.insert(results, { dps_base = basePred, dps_new = pred1, dps_delta = delta1, slot_id = 16, mode = "mh_replacement" })
        else
          lastErr = err or lastErr
        end

        -- If the offhand slot is empty, also evaluate the best paired offhand.
        if not offHandRef then
          local pairResult, pairErr = findBestPairScenario(
            itemRef, mainHandRef, specKey, classToken, false, base, basePred, context
          )
          if pairResult then
            table.insert(results, pairResult)
          else
            lastErr = pairErr or lastErr
          end
        end
      end

      -- Scenario 1b: if currently using a 2H, also evaluate best dual-wield pair.
      if currentIs2H and mainHandRef then
        local pairResult, pairErr = findBestPairScenario(
          itemRef, mainHandRef, specKey, classToken, false, base, basePred, context
        )
        if pairResult then
          table.insert(results, pairResult)
        else
          lastErr = pairErr or lastErr
        end
      end

      -- Scenario 2: offhand replacement (when current loadout is dual).
      if offHandRef and not currentIs2H and isItemAllowedForOffHand(classToken, specKey, itemClassID, itemSubClassID, candidateEquipLoc) then
        local ohStats, err = NS.computeStatDelta(itemRef, offHandRef)
        if ohStats then
          local newStats = statsWithDelta(base, ohStats, context)
          local pred2, delta2 = predictDelta(base, newStats, specKey, basePred)
          table.insert(results, { dps_base = basePred, dps_new = pred2, dps_delta = delta2, slot_id = 17, mode = "oh_replacement" })
        else
          lastErr = err or lastErr
        end
      end
    elseif loadout.two_handed then
      -- 2H-only specs can still compare 1H items directly against mainhand,
      -- but no dual/offhand scenarios are evaluated.
      if mainHandRef then
        local mhStats, err = NS.computeStatDelta(itemRef, mainHandRef)
        if mhStats then
          local newStats = statsWithDelta(base, mhStats, context)
          local pred1, delta1 = predictDelta(base, newStats, specKey, basePred)
          table.insert(results, { dps_base = basePred, dps_new = pred1, dps_delta = delta1, slot_id = 16, mode = "mh_replacement" })
        else
          lastErr = err or lastErr
        end
      else
        return nil, "native comparison unavailable for weapon"
      end
    end

    if results and #results > 0 then
      return results
    end
    return nil, (lastErr or "native comparison unavailable for weapon")
end

local function evaluateRingItem(itemRef, specKey, base, basePred, context)
  local ring1Ref = getContextSlotItemRef(context, 11)
  local ring2Ref = getContextSlotItemRef(context, 12)
  local results = {}
  local lastErr = nil

  if ring1Ref then
      local ring1Stats, err = NS.computeStatDelta(itemRef, ring1Ref)
      if ring1Stats then
        local newStats = statsWithDelta(base, ring1Stats, context)
        local pred1, delta1 = predictDelta(base, newStats, specKey, basePred)
        table.insert(results, { dps_base = basePred, dps_new = pred1, dps_delta = delta1, slot_id = 11, mode = "ring1" })
      else
        lastErr = err or lastErr
      end
    end

    -- Ring slot 2
    if ring2Ref then
      local ring2Stats, err = NS.computeStatDelta(itemRef, ring2Ref)
      if ring2Stats then
        local newStats = statsWithDelta(base, ring2Stats, context)
        local pred2, delta2 = predictDelta(base, newStats, specKey, basePred)
        table.insert(results, { dps_base = basePred, dps_new = pred2, dps_delta = delta2, slot_id = 12, mode = "ring2" })
      else
        lastErr = err or lastErr
      end
    end

    if results and #results > 0 then
      return results
    end
    return nil, (lastErr or "native comparison unavailable for rings")
end

local function evaluateArmorItem(itemRef, specKey, base, basePred, slots, context)
  local best = nil
  local lastErr = nil
  for _, slotId in ipairs(slots) do
    local eqRef = getContextSlotItemRef(context, slotId)
    if eqRef then
      local itemStats, err = NS.computeStatDelta(itemRef, eqRef)
      if itemStats then
        local newStats = statsWithDelta(base, itemStats, context)
        local newPred, delta = predictDelta(base, newStats, specKey, basePred)

        if not best or delta > best.dps_delta then
          best = {
            dps_base = basePred,
            dps_new = newPred,
            dps_delta = delta,
            slot_id = slotId,
            mode = "replacement",
          }
        end
      else
        lastErr = err or lastErr
      end
    end
  end

  if best then
    return best
  end
  return nil, (lastErr or "native comparison unavailable")
end

local function evaluateItem(itemRef, specKey, context)
  ensurePredictionContext(context)
  local itemLink = NS.itemRefToLink(itemRef)
  local slots = getEquipSlotCandidates(itemRef)
  local _, _, candidateEquipLoc = getItemTypeInfo(itemLink)

  if not slots or #slots == 0 then
    return nil, "unknown equip slot"
  end

  local base, basePred = getContextBase(context, specKey)
  if isWeaponEquipLoc(candidateEquipLoc) then
    local candidateGuid = type(itemRef) == "table" and (itemRef.guid or itemRef.itemGUID) or nil
    if not candidateGuid and NS.resolveOwnedItemRef then
      itemRef = NS.resolveOwnedItemRef(itemRef) or itemRef
    end
    return evaluateWeaponItem(itemRef, itemLink, specKey, base, basePred, candidateEquipLoc, context)
  end
  if slots[1] == 11 and slots[2] == 12 then
    return evaluateRingItem(itemRef, specKey, base, basePred, context)
  end
  return evaluateArmorItem(itemRef, specKey, base, basePred, slots, context)
end

function NS.Predictor.PredictItemDelta(itemRef, specKey, context)
  -- Resolve: explicit arg > active profile from dashboard.
  specKey = specKey or NS.getActiveProfileKey()
  local itemLink = NS.itemRefToLink(itemRef)
  if not itemLink then
    return nil, "missing item link"
  end
  if not specKey or specKey == "" then
    return nil, NS.MSG_NO_PROFILE_ACTION
  end

  local pred, err = evaluateItem(itemRef, specKey, context)
  if not pred then
    return nil, err or "prediction failed"
  end
  return pred
end

local function equippedCandidateForSlot(slotId, context)
  local ref = getContextSlotItemRef(context, slotId)
  if not ref or not ref.link then
    return { key = "empty:" .. tostring(slotId), link = nil, stats = ZERO_STATS }
  end
  if NS.makeCandidateFromGearRef then
    local cand = NS.makeCandidateFromGearRef({
      link = ref.link,
      guid = ref.guid,
      source = "equipped",
      source_label = "Equipped",
    })
    if cand then
      cand.is_equipped_baseline = true
      return cand
    end
  end
  return { key = "empty:" .. tostring(slotId), link = nil, stats = ZERO_STATS }
end

local function weaponLoadoutDpsDelta(mhPick, ohPick, eqMh, eqOh, specKey, baseStats, basePred, context)
  local out = context and context.weaponDeltaStats or nil
  local wdelta = NS.computeWeaponLoadoutDelta(mhPick, ohPick, eqMh, eqOh, specKey, out)
  local stats = statsWithDelta(baseStats, wdelta, context)
  local pred = NS.getCachedPrediction(stats, specKey)
  return pred - basePred
end

local function bestMainHandPairDelta(
  mhCand, ohOptions, eqMh, eqOh, classToken, specKey, loadout, baseStats, basePred, context
)
  if not NS.isValidWeaponCombo then
    return nil
  end
  local bestDelta = nil
  for _, ohPick in ipairs(ohOptions) do
    if NS.isValidWeaponCombo(mhCand, ohPick, classToken, specKey, loadout, false) then
      local delta = weaponLoadoutDpsDelta(mhCand, ohPick, eqMh, eqOh, specKey, baseStats, basePred, context)
      if bestDelta == nil or delta > bestDelta then
        bestDelta = delta
      end
    end
  end
  return bestDelta
end

local function bestOffHandPairDelta(
  ohCand, mhOptions, eqMh, eqOh, classToken, specKey, loadout, baseStats, basePred, context
)
  if not NS.isValidWeaponCombo then
    return nil
  end
  local bestDelta = nil
  for _, mhPick in ipairs(mhOptions) do
    if NS.isValidWeaponCombo(mhPick, ohCand, classToken, specKey, loadout, false) then
      local delta = weaponLoadoutDpsDelta(mhPick, ohCand, eqMh, eqOh, specKey, baseStats, basePred, context)
      if bestDelta == nil or delta > bestDelta then
        bestDelta = delta
      end
    end
  end
  return bestDelta
end

-- Re-score weapon candidates using the best valid opposite-hand pairing (gear advisor list/filtering).
function NS.applyPairedWeaponCandidateScoring(candidatesBySlot, specKey, context)
  if not candidatesBySlot or not specKey then
    return
  end
  local loadout = getWeaponLoadoutForSpec(specKey)
  if not loadout then
    return
  end

  context = ensurePredictionContext(context or createPredictionContext())
  local _, classToken = UnitClass("player")
  local baseStats, basePred = getContextBase(context, specKey)
  local eqMh = equippedCandidateForSlot(16, context)
  local eqOh = equippedCandidateForSlot(17, context)

  local ohOptions = {}
  local mhOptions = {}
  local ohSeen = {}
  local mhSeen = {}

  local function addOhOption(cand)
    if cand and cand.key and not ohSeen[cand.key] then
      ohSeen[cand.key] = true
      table.insert(ohOptions, cand)
    end
  end

  local function addMhOption(cand)
    if not cand or not cand.key or mhSeen[cand.key] then
      return
    end
    if cand.link and is2HWeapon(cand.link) then
      return
    end
    mhSeen[cand.key] = true
    table.insert(mhOptions, cand)
  end

  for _, cand in ipairs(candidatesBySlot[17] or {}) do
    addOhOption(cand)
  end
  addOhOption(eqOh)
  if loadout.dual_wield then
    addOhOption({ key = "empty:17", link = nil, stats = ZERO_STATS })
  end

  for _, cand in ipairs(candidatesBySlot[16] or {}) do
    addMhOption(cand)
  end
  addMhOption(eqMh)

  local function applyPairedScore(cand, slotId)
    if not cand or not cand.link or cand.is_equipped_baseline then
      return
    end

    local bestDelta
    if slotId == 16 and is2HWeapon(cand.link) then
      if not loadout.two_handed then
        return
      end
      bestDelta = weaponLoadoutDpsDelta(cand, nil, eqMh, eqOh, specKey, baseStats, basePred, context)
    elseif slotId == 16 then
      if not loadout.dual_wield then
        return
      end
      bestDelta = bestMainHandPairDelta(
        cand, ohOptions, eqMh, eqOh, classToken, specKey, loadout, baseStats, basePred, context
      )
    elseif slotId == 17 then
      if not loadout.dual_wield then
        return
      end
      bestDelta = bestOffHandPairDelta(
        cand, mhOptions, eqMh, eqOh, classToken, specKey, loadout, baseStats, basePred, context
      )
    end

    if bestDelta ~= nil then
      cand.dps_delta = bestDelta
      cand.is_upgrade = bestDelta > 0.5
      if slotId == 16 or slotId == 17 then
        local is2H = slotId == 16 and cand.link and is2HWeapon(cand.link)
        cand.weapon_pair_scored = loadout.dual_wield and not is2H
      end
    end
  end

  for _, cand in ipairs(candidatesBySlot[16] or {}) do
    applyPairedScore(cand, 16)
  end
  for _, cand in ipairs(candidatesBySlot[17] or {}) do
    applyPairedScore(cand, 17)
  end
end
NS.getItemTypeInfo = getItemTypeInfo
NS.is2HWeapon = is2HWeapon
NS.getSlotItemRef = getSlotItemRef
NS.getEquipSlotCandidates = getEquipSlotCandidates
NS.getWeaponLoadoutForSpec = getWeaponLoadoutForSpec
NS.isItemAllowedForMainHand = isItemAllowedForMainHand
NS.isItemAllowedForOffHand = isItemAllowedForOffHand
NS.isArmorCandidateAllowedForClass = isArmorCandidateAllowedForClass
NS.createPredictionContext = createPredictionContext

