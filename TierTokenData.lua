local ADDON_NAME, NS = ...

-- Midnight S2 tier tokens (Venomous Abyss — Tier 36).
-- Maps token item ID -> class -> tier piece item ID.
-- Sources: ATT The Venomous Abyss.lua + RCLootCouncil tokenData (12.1).
-- Armor groups: Woven=cloth, Cured=leather, Cast=mail, Forged=plate.
local TIER_TOKEN_PIECES = {
  -- Hands (Idol) — Entombed Sentinels
  [270913] = { WARRIOR = 271457, PALADIN = 271466, DEATHKNIGHT = 271475 }, -- Venomforged Idol
  [270911] = { ROGUE = 271511, MONK = 271520, DRUID = 271529, DEMONHUNTER = 271538 }, -- Venomcured Idol
  [270912] = { HUNTER = 271493, SHAMAN = 271484, EVOKER = 271502 }, -- Venomcast Idol (Evoker hands: Ebon Greathorns)
  [270910] = { PRIEST = 271556, MAGE = 271565, WARLOCK = 271547 }, -- Venomwoven Idol
  -- Shoulders (Remnant) — The Lost Explorers
  [270925] = { WARRIOR = 271454, PALADIN = 271463, DEATHKNIGHT = 271472 }, -- Venomforged Remnant
  [270923] = { ROGUE = 271508, MONK = 271517, DRUID = 271526, DEMONHUNTER = 271535 }, -- Venomcured Remnant
  [270924] = { HUNTER = 271490, SHAMAN = 271481, EVOKER = 271499 }, -- Venomcast Remnant
  [270922] = { PRIEST = 271553, MAGE = 271562, WARLOCK = 271544 }, -- Venomwoven Remnant
  -- Chest (Icon) — Vashnik the Malignant
  [270929] = { WARRIOR = 271459, PALADIN = 271468, DEATHKNIGHT = 271477 }, -- Venomforged Icon
  [270927] = { ROGUE = 271513, MONK = 271522, DRUID = 271531, DEMONHUNTER = 271540 }, -- Venomcured Icon
  [270928] = { HUNTER = 271495, SHAMAN = 271486, EVOKER = 271504 }, -- Venomcast Icon (Evoker chest: Searing Caldera)
  [270926] = { PRIEST = 271558, MAGE = 271567, WARLOCK = 271549 }, -- Venomwoven Icon
  -- Legs (Relic) — Sszorak
  [270921] = { WARRIOR = 271455, PALADIN = 271464, DEATHKNIGHT = 271473 }, -- Venomforged Relic
  [270919] = { ROGUE = 271509, MONK = 271518, DRUID = 271527, DEMONHUNTER = 271536 }, -- Venomcured Relic
  [270920] = { HUNTER = 271491, SHAMAN = 271482, EVOKER = 271500 }, -- Venomcast Relic
  [270918] = { PRIEST = 271554, MAGE = 271563, WARLOCK = 271545 }, -- Venomwoven Relic
  -- Head (Effigy) — The Twin Fangs
  [270917] = { WARRIOR = 271456, PALADIN = 271465, DEATHKNIGHT = 271474 }, -- Venomforged Effigy
  [270915] = { ROGUE = 271510, MONK = 271519, DRUID = 271528, DEMONHUNTER = 271537 }, -- Venomcured Effigy
  [270916] = { HUNTER = 271492, SHAMAN = 271483, EVOKER = 271501 }, -- Venomcast Effigy
  [270914] = { PRIEST = 271555, MAGE = 271564, WARLOCK = 271546 }, -- Venomwoven Effigy
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

  local function readFromCountIndex(countIndex)
    local numBonus = tonumber(fields[countIndex]) or 0
    if numBonus <= 0 or numBonus > 10 then
      return nil
    end
    local bonusIDs = {}
    for i = 1, numBonus do
      local bonusID = tonumber(fields[countIndex + i])
      if bonusID then
        bonusIDs[i] = bonusID
      end
    end
    return #bonusIDs > 0 and bonusIDs or nil
  end

  -- Standard: creation context at 12, bonus count at 13. Some links pack context at 13 with count at 14.
  local bonusIDs = readFromCountIndex(13)
  if bonusIDs then
    return bonusIDs
  end
  return readFromCountIndex(14)
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

  local creationContext = tokenFields[12] or "0"
  if tonumber(tokenFields[13]) and tonumber(tokenFields[13]) > 10 then
    creationContext = tokenFields[13]
  end

  local out = { tostring(pieceItemID) }
  for i = 2, 11 do
    out[i] = tokenFields[i] or "0"
  end
  out[12] = creationContext
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
