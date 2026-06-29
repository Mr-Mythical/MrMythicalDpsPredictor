local ADDON_NAME, NS = ...

-- Midnight S1 tier tokens (The Voidspire). Maps token item ID -> class -> tier piece item ID.
-- Maintained manually from Encounter Journal loot; update each tier season.
local TIER_TOKEN_PIECES = {
  -- Voidspire tier 1 (Dreadful / Mystic / Venerated / Zenith)
  [237581] = { DEATHKNIGHT = 237631, DEMONHUNTER = 237694, WARLOCK = 237703 },
  [237585] = { DEATHKNIGHT = 237629, DEMONHUNTER = 237692, WARLOCK = 237701 },
  [237589] = { DEATHKNIGHT = 237628, DEMONHUNTER = 237691, WARLOCK = 237700 },
  [237593] = { DEATHKNIGHT = 237627, DEMONHUNTER = 237690, WARLOCK = 237699 },
  [237597] = { DEATHKNIGHT = 237626, DEMONHUNTER = 237689, WARLOCK = 237698 },
  [237582] = { DRUID = 237685, HUNTER = 237649, MAGE = 237721 },
  [237586] = { DRUID = 237683, HUNTER = 237647, MAGE = 237719 },
  [237590] = { DRUID = 237682, HUNTER = 237646, MAGE = 237718 },
  [237594] = { DRUID = 237681, HUNTER = 237645, MAGE = 237717 },
  [237598] = { DRUID = 237680, HUNTER = 237644, MAGE = 237716 },
  [237583] = { PALADIN = 237622, PRIEST = 237712, SHAMAN = 237640 },
  [237587] = { PALADIN = 237620, PRIEST = 237710, SHAMAN = 237638 },
  [237591] = { PALADIN = 237619, PRIEST = 237709, SHAMAN = 237637 },
  [237595] = { PALADIN = 237618, PRIEST = 237708, SHAMAN = 237636 },
  [237599] = { PALADIN = 237617, PRIEST = 237707, SHAMAN = 237635 },
  [237584] = { EVOKER = 237658, MONK = 237676, ROGUE = 237667, WARRIOR = 237613 },
  [237588] = { EVOKER = 237656, MONK = 237674, ROGUE = 237665, WARRIOR = 237611 },
  [237592] = { EVOKER = 237655, MONK = 237673, ROGUE = 237664, WARRIOR = 237610 },
  [237596] = { EVOKER = 237654, MONK = 237672, ROGUE = 237663, WARRIOR = 237609 },
  [237600] = { EVOKER = 237653, MONK = 237671, ROGUE = 237662, WARRIOR = 237608 },
  -- Voidspire tier 2 (Nullcore / Riftbloom families)
  [249354] = { WARRIOR = 249953, PALADIN = 249962, DEATHKNIGHT = 249971 },
  [249358] = { WARRIOR = 249952, PALADIN = 249961, DEATHKNIGHT = 249970 },
  [249362] = { WARRIOR = 249951, PALADIN = 249960, DEATHKNIGHT = 249969 },
  [249366] = { WARRIOR = 249950, PALADIN = 249959, DEATHKNIGHT = 249968 },
  [249352] = { ROGUE = 250007, MONK = 250016, DRUID = 250025, DEMONHUNTER = 250034 },
  [249356] = { ROGUE = 250006, MONK = 250015, DRUID = 250024, DEMONHUNTER = 250033 },
  [249360] = { ROGUE = 250005, MONK = 250014, DRUID = 250023, DEMONHUNTER = 250032 },
  [249364] = { ROGUE = 250004, MONK = 250013, DRUID = 250022, DEMONHUNTER = 250031 },
  [249353] = { HUNTER = 249989, SHAMAN = 249980, EVOKER = 249998 },
  [249357] = { HUNTER = 249988, SHAMAN = 249979, EVOKER = 249997 },
  [249361] = { HUNTER = 249987, SHAMAN = 249978, EVOKER = 249996 },
  [249365] = { HUNTER = 249986, SHAMAN = 249977, EVOKER = 249995 },
  [249351] = { PRIEST = 250052, MAGE = 250061, WARLOCK = 250043 },
  [249355] = { PRIEST = 250051, MAGE = 250060, WARLOCK = 250042 },
  [249359] = { PRIEST = 250050, MAGE = 250059, WARLOCK = 250041 },
  [249363] = { PRIEST = 250049, MAGE = 250058, WARLOCK = 250040 },
  [249350] = { WARRIOR = 249955, PALADIN = 249964, DEATHKNIGHT = 249973 },
  [249348] = { ROGUE = 250009, MONK = 250018, DRUID = 250027, DEMONHUNTER = 250036 },
  [249349] = { HUNTER = 249991, SHAMAN = 249982, EVOKER = 250000 },
  [249347] = { PRIEST = 250054, MAGE = 250063, WARLOCK = 250045 },
}

local function lookupPieceItemID(tokenItemID, classToken)
  local byClass = TIER_TOKEN_PIECES[tokenItemID]
  if not byClass or not classToken then
    return nil
  end
  return byClass[classToken]
end

local function splitItemLinkPayload(link)
  if not link then
    return nil
  end
  local payload = link:match("|Hitem:([^|]+)") or link:match("item:([^|]+)")
  if not payload then
    return nil
  end
  local fields = {}
  for part in payload:gmatch("[^:]+") do
    fields[#fields + 1] = part
  end
  return fields
end

local function readBonusIDsFromLink(link)
  local fields = splitItemLinkPayload(link)
  if not fields then
    return nil
  end
  local numBonus = tonumber(fields[13]) or 0
  if numBonus <= 0 then
    return nil
  end
  local bonusIDs = {}
  for i = 1, numBonus do
    local bonusID = tonumber(fields[13 + i])
    if bonusID then
      bonusIDs[i] = bonusID
    end
  end
  return #bonusIDs > 0 and bonusIDs or nil
end

local function buildPieceLinkFromToken(tokenLink, pieceItemID)
  if not pieceItemID then
    return nil
  end
  local tokenFields = splitItemLinkPayload(tokenLink)
  local bonusIDs = readBonusIDsFromLink(tokenLink)
  if not tokenFields or not bonusIDs then
    if C_Item and C_Item.GetItemLinkByID then
      local ok, link = pcall(C_Item.GetItemLinkByID, pieceItemID)
      if ok and link and link ~= "" then
        return link
      end
    end
    local name = GetItemInfo(pieceItemID)
    return string.format("|Hitem:%d|h[%s]|h", pieceItemID, name or pieceItemID)
  end

  local out = { tostring(pieceItemID) }
  for i = 2, 12 do
    out[i] = tokenFields[i] or "0"
  end
  out[13] = tostring(#bonusIDs)
  for i, bonusID in ipairs(bonusIDs) do
    out[13 + i] = tostring(bonusID)
  end
  local label = GetItemInfo(pieceItemID) or pieceItemID
  return string.format("|Hitem:%s|h[%s]|h", table.concat(out, ":"), label)
end

local function findEquippableLinkInTooltip(itemID, itemLink)
  if not (C_TooltipInfo and itemID) then
    return nil
  end

  local ok, data
  if itemLink and C_TooltipInfo.GetHyperlink then
    ok, data = pcall(C_TooltipInfo.GetHyperlink, itemLink)
  end
  if (not ok or not data) and C_TooltipInfo.GetItemByID then
    ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
  end
  if not ok or not data then
    return nil
  end

  local function tryLink(candidateLink)
    if not candidateLink or candidateLink == itemLink then
      return nil
    end
    local linkItemID = tonumber(candidateLink:match("item:(%d+)"))
    if not linkItemID or linkItemID == itemID then
      return nil
    end
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(candidateLink)
    if equipLoc and equipLoc ~= "" then
      return candidateLink, linkItemID
    end
    return nil
  end

  local foundLink, foundID = tryLink(data.hyperlink)
  if foundLink then
    return foundLink, foundID
  end

  for _, line in ipairs(data.lines or {}) do
    for _, text in ipairs({ line.leftText, line.rightText }) do
      if text and text ~= "" then
        local fragment = text:match("|H(item:[^|]+|h[^|]+|h)")
        if fragment then
          foundLink, foundID = tryLink("|" .. fragment)
          if foundLink then
            return foundLink, foundID
          end
        end
      end
    end
  end
  return nil
end

local function tokenAppliesToPlayer(tokenItemID)
  if not (C_Item and C_Item.DoesItemContainSpec and tokenItemID) then
    return true
  end
  local _, _, classID = UnitClass("player")
  local specIndex = GetSpecialization and GetSpecialization() or nil
  local specID = specIndex and GetSpecializationInfo(specIndex) or 0
  if not classID then
    return true
  end
  return C_Item.DoesItemContainSpec(tokenItemID, classID, specID or 0) == true
end

function NS.isArmorTokenItem(itemID)
  return itemID ~= nil and TIER_TOKEN_PIECES[itemID] ~= nil
end

function NS.resolveArmorTokenLootLink(tokenItemID, tokenLink, classToken)
  if not tokenItemID then
    return nil, nil
  end

  local pieceItemID = lookupPieceItemID(tokenItemID, classToken)
  if pieceItemID then
    local pieceLink = buildPieceLinkFromToken(tokenLink, pieceItemID)
    if pieceLink then
      return pieceLink, pieceItemID
    end
  end

  if tokenAppliesToPlayer(tokenItemID) then
    local tooltipLink, tooltipItemID = findEquippableLinkInTooltip(tokenItemID, tokenLink)
    if tooltipLink and tooltipItemID then
      if tokenLink and tokenLink ~= tooltipLink then
        local grafted = buildPieceLinkFromToken(tokenLink, tooltipItemID)
        if grafted then
          return grafted, tooltipItemID
        end
      end
      return tooltipLink, tooltipItemID
    end
  end

  return nil, nil
end
