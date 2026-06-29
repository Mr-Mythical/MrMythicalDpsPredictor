local ADDON_NAME, NS = ...
local Model = NS.Model

local function buildSpecPrefix(classToken, specName)
  local classKey = NS.CLASS_TOKEN_TO_KEY[classToken]
  if not classKey then return nil end
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
  local _, specName = GetSpecializationInfo(specIndex)
  if not specName then
    NS.active_spec_keys = {}
    NS.active_spec_prefix = nil
    return
  end
  local prefix = buildSpecPrefix(classToken, specName)
  if not prefix then
    NS.active_spec_keys = {}
    NS.active_spec_prefix = nil
    return
  end
  NS.active_spec_prefix = prefix
  NS.active_spec_keys = findSpecProfiles(prefix)
end

local function normalizeHeroToken(name)
  if not name or name == "" then
    return nil
  end
  return name:gsub("[%s%-%.]", "_"):gsub("_+", "_")
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

  if C_ClassTalents.GetActiveHeroTalentSpec then
    local heroSpecID = C_ClassTalents.GetActiveHeroTalentSpec()
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

local function scoreProfileMatch(profileKey, heroToken)
  if not heroToken or not profileKey then
    return 0
  end
  local suffix = profileKey
  if NS.active_spec_prefix and profileKey:sub(1, #NS.active_spec_prefix + 1) == NS.active_spec_prefix .. "_" then
    suffix = profileKey:sub(#NS.active_spec_prefix + 2)
  end
  suffix = suffix:lower()
  local hero = heroToken:lower()

  local best = 0
  for token in suffix:gmatch("[^_]+") do
    if token ~= "" and hero:find(token, 1, true) then
      best = math.max(best, #token)
    end
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

  local heroToken = getActiveHeroTalentName()
  if not heroToken then
    updateProfileMatchInfo(nil, 0, 0)
    return
  end

  local bestKey, bestScore, secondScore = nil, 0, 0
  for _, profileKey in ipairs(NS.active_spec_keys) do
    local score = scoreProfileMatch(profileKey, heroToken)
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
