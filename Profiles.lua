local ADDON_NAME, NS = ...
local Model = NS.Model

-- English model prefixes keyed by specialization ID (locale-independent).
-- Do NOT build prefixes from GetSpecializationInfo()'s localized name.
local SPEC_ID_TO_MODEL_PREFIX = {
  [250] = "MID1_Death_Knight_Blood",
  [251] = "MID1_Death_Knight_Frost",
  [252] = "MID1_Death_Knight_Unholy",
  [1480] = "MID1_Demon_Hunter_Devourer",
  [577] = "MID1_Demon_Hunter_Havoc",
  [581] = "MID1_Demon_Hunter_Vengeance",
  [102] = "MID1_Druid_Balance",
  [103] = "MID1_Druid_Feral",
  [104] = "MID1_Druid_Guardian",
  [1467] = "MID1_Evoker_Devastation",
  [253] = "MID1_Hunter_Beast_Mastery",
  [254] = "MID1_Hunter_Marksmanship",
  [255] = "MID1_Hunter_Survival",
  [62] = "MID1_Mage_Arcane",
  [63] = "MID1_Mage_Fire",
  [64] = "MID1_Mage_Frost",
  [268] = "MID1_Monk_Brewmaster",
  [269] = "MID1_Monk_Windwalker",
  [66] = "MID1_Paladin_Protection",
  [70] = "MID1_Paladin_Retribution",
  [258] = "MID1_Priest_Shadow",
  [259] = "MID1_Rogue_Assassination",
  [260] = "MID1_Rogue_Outlaw",
  [261] = "MID1_Rogue_Subtlety",
  [262] = "MID1_Shaman_Elemental",
  [263] = "MID1_Shaman_Enhancement",
  [265] = "MID1_Warlock_Affliction",
  [266] = "MID1_Warlock_Demonology",
  [267] = "MID1_Warlock_Destruction",
  [71] = "MID1_Warrior_Arms",
  [72] = "MID1_Warrior_Fury",
  [73] = "MID1_Warrior_Protection",
}

local function buildSpecPrefixFromLocalizedName(classToken, specName)
  local classKey = NS.CLASS_TOKEN_TO_KEY[classToken]
  if not classKey or not specName then return nil end
  return "MID1_" .. classKey .. "_" .. specName:gsub(" ", "_")
end

local function getSpecKeyList()
  if Model.spec_keys then
    return Model.spec_keys
  end
  local list = {}
  for _, sfName in ipairs(Model.spec_feature_names or {}) do
    list[#list + 1] = sfName:gsub("^spec_", "")
  end
  return list
end

local function findSpecProfiles(prefix)
  local matches = {}
  for _, specKey in ipairs(getSpecKeyList()) do
    if specKey == prefix or specKey:sub(1, #prefix + 1) == prefix .. "_" then
      table.insert(matches, specKey)
    end
  end
  return matches
end

function NS.getProfileLabel(specKey, prefix)
  prefix = prefix or NS.active_spec_prefix
  if not prefix then
    return specKey
  end
  if specKey == prefix then
    return (prefix:match("[^_]+$") or specKey):gsub("_", " ")
  end
  return specKey:sub(#prefix + 2):gsub("_", " ")
end

function NS.detectAndCacheProfiles()
  NS.profileDetectionDoneRef[1] = true
  local _, classToken = UnitClass("player")
  local specIndex = GetSpecialization()
  if not classToken or not specIndex then
    NS.active_spec_keys = {}
    NS.active_spec_prefix = nil
    return
  end

  local specID, specName = GetSpecializationInfo(specIndex)
  -- Prefer specialization ID -> English model prefix (works on every client language).
  local prefix = specID and SPEC_ID_TO_MODEL_PREFIX[specID] or nil
  -- enUS fallback only: localized name happens to match English model tokens.
  if not prefix then
    prefix = buildSpecPrefixFromLocalizedName(classToken, specName)
  end

  if not prefix then
    NS.active_spec_keys = {}
    NS.active_spec_prefix = nil
    return
  end

  local matches = findSpecProfiles(prefix)
  if #matches == 0 and specName then
    -- Last resort: localized-name prefix (should only help enUS / unchanged names).
    local alt = buildSpecPrefixFromLocalizedName(classToken, specName)
    if alt and alt ~= prefix then
      matches = findSpecProfiles(alt)
      if #matches > 0 then
        prefix = alt
      end
    end
  end

  NS.active_spec_prefix = prefix
  NS.active_spec_keys = matches
end

local function normalizeHeroToken(name)
  if not name or name == "" then
    return nil
  end
  return name:gsub("[%s%-%.]", "_"):gsub("_+", "_")
end

local function getActiveHeroSpecID()
  if C_ClassTalents and C_ClassTalents.GetActiveHeroTalentSpec then
    return C_ClassTalents.GetActiveHeroTalentSpec()
  end
  return nil
end

local function getActiveHeroTalentName()
  if not (C_ClassTalents and GetSpecialization) then
    return nil
  end

  local specIndex = GetSpecialization()
  if not specIndex then
    return nil
  end

  local specID = GetSpecializationInfo(specIndex)
  if not specID then
    return nil
  end

  local heroSpecID = getActiveHeroSpecID()
  if heroSpecID and C_ClassTalents.GetHeroTalentSpecsForClassSpec then
    local _, classID = UnitClassBase("player")
    if classID then
      local heroSpecs = C_ClassTalents.GetHeroTalentSpecsForClassSpec(classID, specID)
      if heroSpecs then
        for _, info in ipairs(heroSpecs) do
          if info and info.heroSpecID == heroSpecID then
            return normalizeHeroToken(info.name or info.heroSpecName)
          end
        end
      end
    end
  end

  if C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo then
    local configID = C_ClassTalents.GetActiveConfigID()
    if configID then
      local info = C_Traits.GetConfigInfo(configID)
      if info and info.name then
        return normalizeHeroToken(info.name)
      end
    end
  end

  return nil
end

local function listHeroProfileKeys(prefix)
  local heroKeys = {}
  for _, profileKey in ipairs(NS.active_spec_keys or {}) do
    if profileKey ~= prefix and profileKey:sub(1, #prefix + 1) == prefix .. "_" then
      table.insert(heroKeys, profileKey)
    end
  end
  return heroKeys
end

NS.profileMatchInfo = {
  bestKey = nil,
  bestScore = 0,
  secondScore = 0,
  ambiguous = false,
  lowConfidence = false,
}

function NS.getProfileMatchInfo()
  return NS.profileMatchInfo
end

local function updateProfileMatchInfo(bestKey, bestScore, secondScore)
  NS.profileMatchInfo.bestKey = bestKey
  NS.profileMatchInfo.bestScore = bestScore or 0
  NS.profileMatchInfo.secondScore = secondScore or 0
  NS.profileMatchInfo.ambiguous = (not bestKey) or (bestScore or 0) <= 0
  NS.profileMatchInfo.lowConfidence = (bestKey ~= nil)
    and (bestScore or 0) > 0
    and (secondScore or 0) > 0
    and (bestScore - secondScore) <= 2
end

local function scoreProfileMatch(profileKey, heroToken, heroSpecID)
  if not profileKey then
    return 0
  end
  local prefix = NS.active_spec_prefix
  local suffix = profileKey
  if prefix and profileKey:sub(1, #prefix + 1) == prefix .. "_" then
    suffix = profileKey:sub(#prefix + 2)
  elseif prefix and profileKey == prefix then
    suffix = ""
  end
  suffix = suffix:lower()

  -- Locale-safe primary: remembered heroSpecID -> profile mapping.
  if heroSpecID and MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.hero_spec_profile_map then
    if MR_MYTHICAL_DPS_CONFIG.hero_spec_profile_map[heroSpecID] == profileKey then
      return 100
    end
  end

  local best = 0
  if heroToken and heroToken ~= "" then
    local hero = heroToken:lower()
    for token in suffix:gmatch("[^_]+") do
      if token ~= "" and hero:find(token, 1, true) then
        best = math.max(best, #token)
      end
      -- English-only weak aliases (fallback when client language matches tokens).
      if token == "pl" and hero:find("pack", 1, true) then
        best = math.max(best, 4)
      end
      if token == "dw" or token == "2h" then
        best = math.max(best, 1)
      end
    end
    for token in hero:gmatch("[^_]+") do
      if token ~= "" and suffix:find(token, 1, true) then
        best = math.max(best, #token)
      end
    end
  end

  -- When a hero tree is selected and only one hero-variant profile exists, prefer it.
  if heroSpecID and suffix ~= "" then
    local heroKeys = listHeroProfileKeys(prefix)
    if #heroKeys == 1 and heroKeys[1] == profileKey then
      best = math.max(best, 50)
    end
  end

  -- Prefer the base profile when no hero talent is selected.
  if (not heroSpecID) and suffix == "" then
    best = math.max(best, 20)
  end

  return best
end

function NS.tryAutoMatchProfile()
  if MR_MYTHICAL_DPS_CONFIG.profile_mode == "manual" then
    return
  end
  local prefix = NS.active_spec_prefix
  if not prefix or #NS.active_spec_keys <= 1 then
    updateProfileMatchInfo(nil, 0, 0)
    return
  end
  if MR_MYTHICAL_DPS_CONFIG.profile_by_prefix[prefix] then
    updateProfileMatchInfo(MR_MYTHICAL_DPS_CONFIG.profile_by_prefix[prefix], 100, 0)
    return
  end

  local heroSpecID = getActiveHeroSpecID()
  local heroToken = getActiveHeroTalentName()

  -- Prefer persisted heroSpecID mapping (works on every client language).
  if heroSpecID and MR_MYTHICAL_DPS_CONFIG.hero_spec_profile_map then
    local mapped = MR_MYTHICAL_DPS_CONFIG.hero_spec_profile_map[heroSpecID]
    if mapped then
      for _, profileKey in ipairs(NS.active_spec_keys) do
        if profileKey == mapped then
          updateProfileMatchInfo(mapped, 100, 0)
          MR_MYTHICAL_DPS_CONFIG.profile_by_prefix[prefix] = mapped
          return
        end
      end
    end
  end

  if not heroToken and not heroSpecID then
    updateProfileMatchInfo(nil, 0, 0)
    return
  end

  local bestKey, bestScore, secondScore = nil, 0, 0
  for _, profileKey in ipairs(NS.active_spec_keys) do
    local score = scoreProfileMatch(profileKey, heroToken, heroSpecID)
    if score > bestScore then
      secondScore = bestScore
      bestScore = score
      bestKey = profileKey
    elseif score > secondScore then
      secondScore = score
    end
  end

  updateProfileMatchInfo(bestKey, bestScore, secondScore)

  if bestKey and bestScore > 0 and bestScore > secondScore then
    MR_MYTHICAL_DPS_CONFIG.profile_by_prefix[prefix] = bestKey
    if heroSpecID then
      MR_MYTHICAL_DPS_CONFIG.hero_spec_profile_map = MR_MYTHICAL_DPS_CONFIG.hero_spec_profile_map or {}
      MR_MYTHICAL_DPS_CONFIG.hero_spec_profile_map[heroSpecID] = bestKey
    end
    NS.debugPrint(string.format(
      "%s: auto-matched hero talent profile to %s",
      NS.BRAND,
      NS.getProfileLabel(bestKey, prefix)
    ))
  end
end

function NS.getActiveProfileKey()
  local prefix = NS.active_spec_prefix
  if prefix and MR_MYTHICAL_DPS_CONFIG.profile_by_prefix[prefix] then
    local saved = MR_MYTHICAL_DPS_CONFIG.profile_by_prefix[prefix]
    for _, k in ipairs(NS.active_spec_keys) do
      if k == saved then
        return saved
      end
    end
  end

  if #NS.active_spec_keys == 1 then
    return NS.active_spec_keys[1]
  end

  if MR_MYTHICAL_DPS_CONFIG.profile_mode ~= "manual" then
    NS.tryAutoMatchProfile()
    if prefix and MR_MYTHICAL_DPS_CONFIG.profile_by_prefix[prefix] then
      return MR_MYTHICAL_DPS_CONFIG.profile_by_prefix[prefix]
    end
  end

  return nil
end

function NS.setActiveProfileKey(profileKey)
  local prefix = NS.active_spec_prefix
  if not prefix then
    return false
  end
  if profileKey == nil or profileKey == "" then
    MR_MYTHICAL_DPS_CONFIG.profile_by_prefix[prefix] = nil
    MR_MYTHICAL_DPS_CONFIG.profile_mode = "auto"
    NS.onProfileContextChanged()
    return true
  end
  for _, k in ipairs(NS.active_spec_keys) do
    if k == profileKey then
      MR_MYTHICAL_DPS_CONFIG.profile_by_prefix[prefix] = profileKey
      MR_MYTHICAL_DPS_CONFIG.profile_mode = "manual"
      NS.onProfileContextChanged()
      return true
    end
  end
  return false
end

function NS.isProfileAmbiguous()
  return NS.active_spec_prefix and #NS.active_spec_keys > 1 and not NS.getActiveProfileKey()
end

function NS.getTooltipProfileKeys()
  local active = NS.getActiveProfileKey()
  if active then
    return { active }
  end
  return nil
end
