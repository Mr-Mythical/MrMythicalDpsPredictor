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
  local short = specKey:gsub("^MID1_", "")
  local parts = {}
  for token in short:gmatch("[^_]+") do
    table.insert(parts, token)
  end
  if #parts < 2 then
    return nil, nil
  end

  local classPart = parts[1]
  local specPart = parts[2]
  if classPart == "Death" and parts[2] == "Knight" and parts[3] then
    classPart = "Death_Knight"
    specPart = parts[3]
  elseif classPart == "Demon" and parts[2] == "Hunter" and parts[3] then
    classPart = "Demon_Hunter"
    specPart = parts[3]
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

function NS.applyItemStatMods(targetStats, sourceTable, sign)
  sign = sign or 1
  if type(targetStats) ~= "table" or type(sourceTable) ~= "table" then
    return
  end
  for k, v in pairs(sourceTable) do
    if type(k) == "string" and type(v) == "number" then
      local feature = NS.ITEM_STAT_KEY_TO_FEATURE[k]
      if feature then
        targetStats[feature] = (targetStats[feature] or 0) + sign * v
      end
    end
  end
end
