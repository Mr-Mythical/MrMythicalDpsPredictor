local ADDON_NAME, NS = ...

function NS.getItemQualityRgb(quality)
  quality = tonumber(quality)
  if quality and quality >= 0 then
    if C_Item and C_Item.GetItemQualityColor then
      local r, g, b = C_Item.GetItemQualityColor(quality)
      if r then return r, g, b end
    elseif GetItemQualityColor then
      local r, g, b = GetItemQualityColor(quality)
      if r then return r, g, b end
    end
  end
  return 1, 1, 1
end

function NS.getClassSpecPair(specKey)
  if type(specKey) ~= "string" then
    return nil, nil
  end
  local short = specKey:gsub("^MID%d+_", "")
  local parts = {}
  for token in short:gmatch("[^_]+") do
    table.insert(parts, token)
  end
  if #parts < 2 then
    return nil, nil
  end

  local classPart = parts[1]
  local specStart = 2
  if classPart == "Death" and parts[2] == "Knight" and parts[3] then
    classPart = "Death_Knight"
    specStart = 3
  elseif classPart == "Demon" and parts[2] == "Hunter" and parts[3] then
    classPart = "Demon_Hunter"
    specStart = 3
  end

  if not parts[specStart] then
    return nil, nil
  end

  -- Multi-token base specs (must not collapse Beast_Mastery → Beast).
  local specPart = parts[specStart]
  if parts[specStart] == "Beast" and parts[specStart + 1] == "Mastery" then
    specPart = "Beast_Mastery"
  elseif parts[specStart] == "Survival"
    and parts[specStart + 1] == "PL"
    and parts[specStart + 2] == "DW" then
    specPart = "Survival_PL_DW"
  end

  return classPart, specPart
end

NS.ZERO_STATS = {
  primary_stat = 0,
  crit = 0,
  haste = 0,
  mastery = 0,
  versatility = 0,
}

function NS.makeZeroStats()
  return {
    primary_stat = 0,
    crit = 0,
    haste = 0,
    mastery = 0,
    versatility = 0,
  }
end

NS.ITEM_STAT_KEY_TO_FEATURE = {
  ITEM_MOD_STRENGTH_SHORT = "primary_stat",
  ITEM_MOD_AGILITY_SHORT = "primary_stat",
  ITEM_MOD_INTELLECT_SHORT = "primary_stat",
  ITEM_MOD_CRIT_RATING_SHORT = "crit",
  ITEM_MOD_CR_CRIT_SHORT = "crit",
  ITEM_MOD_HASTE_RATING_SHORT = "haste",
  ITEM_MOD_MASTERY_RATING_SHORT = "mastery",
  ITEM_MOD_VERSATILITY = "versatility",
  ITEM_MOD_VERSATILITY_SHORT = "versatility",
}

local PRIMARY_STAT_ITEM_KEY = {
  [LE_UNIT_STAT_STRENGTH or 1] = "ITEM_MOD_STRENGTH_SHORT",
  [LE_UNIT_STAT_AGILITY or 2] = "ITEM_MOD_AGILITY_SHORT",
  [LE_UNIT_STAT_INTELLECT or 4] = "ITEM_MOD_INTELLECT_SHORT",
}

function NS.getActivePrimaryStatItemKey()
  if not GetSpecialization or not GetSpecializationInfo then
    return nil
  end
  local specIndex = GetSpecialization()
  if not specIndex then
    return nil
  end
  local primaryStat = select(7, GetSpecializationInfo(specIndex))
  return PRIMARY_STAT_ITEM_KEY[primaryStat]
end

function NS.applyItemStatMods(targetStats, sourceTable, sign)
  sign = sign or 1
  if type(targetStats) ~= "table" or type(sourceTable) ~= "table" then
    return
  end
  local activePrimaryKey = NS.getActivePrimaryStatItemKey()
  for k, v in pairs(sourceTable) do
    if type(k) == "string" and type(v) == "number" then
      local feature = NS.ITEM_STAT_KEY_TO_FEATURE[k]
      if feature and (feature ~= "primary_stat" or not activePrimaryKey or k == activePrimaryKey) then
        targetStats[feature] = (targetStats[feature] or 0) + sign * v
      end
    end
  end
end
