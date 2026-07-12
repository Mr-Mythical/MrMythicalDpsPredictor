local ADDON_NAME, NS = ...

NS.BRAND = "Mr. Mythical: DPS Predictor"
NS.DASHBOARD_SLASH = "/mrdps"
NS.DISCLAIMER_SHORT = "Estimates only."

function NS.brandMsg(message)
  if message and message ~= "" then
    return NS.BRAND .. ": " .. message
  end
  return NS.BRAND
end

function NS.brandPrint(message)
  print(NS.brandMsg(message))
end

-- Informative tooltip line: profile label only when comparing multiple builds.
function NS.formatTooltipDelta(profileLabel, modeStr, deltaText, showProfileLabel)
  local slotHint = ""
  if modeStr and modeStr ~= "" then
    slotHint = modeStr
  end
  local deltaLine = deltaText .. " DPS"
  if showProfileLabel and profileLabel and profileLabel ~= "" then
    if slotHint ~= "" then
      return string.format("%s: %s%s", profileLabel, deltaLine, slotHint)
    end
    return string.format("%s: %s", profileLabel, deltaLine)
  end
  if slotHint ~= "" then
    return deltaLine .. slotHint
  end
  return deltaLine
end

NS.Model = _G.MrMythicalDpsModelData
if type(NS.Model) ~= "table" then
  NS.brandPrint("Model data missing. Reinstall the addon from a full release package.")
  return
end

MR_MYTHICAL_DPS_CONFIG = MR_MYTHICAL_DPS_CONFIG or {
  loadout_scan_yield_every = 40,
  scan_performance_mode = "balanced",
  profile_by_prefix = {},
  profile_mode = "auto",
  debug = false,
  gear_advisor_point = nil,
  gear_advisor_sources = { bag = true, loot = false },
  gear_advisor_mode = "bags",
  gear_advisor_upgrades_only = false,
  gear_advisor_include_sidegrades = false,
  gear_advisor_item_selection = {},
  gear_advisor_instance_id = "all",
  gear_advisor_loot_upgrade = "hero_3",
  scan_progress_point = nil,
}

if type(MR_MYTHICAL_DPS_CONFIG.bag_item_selection) ~= "table" then
  MR_MYTHICAL_DPS_CONFIG.bag_item_selection = {}
end
if type(MR_MYTHICAL_DPS_CONFIG.profile_by_prefix) ~= "table" then
  MR_MYTHICAL_DPS_CONFIG.profile_by_prefix = {}
end

-- Migrate legacy saved vars.
if MR_MYTHICAL_DPS_CONFIG.spec_key and type(MR_MYTHICAL_DPS_CONFIG.spec_key) == "string" then
  local legacy = MR_MYTHICAL_DPS_CONFIG.spec_key
  local prefix = legacy:match("^(MID1_[^_]+_[^_]+_[^_]+)")
  if prefix and not MR_MYTHICAL_DPS_CONFIG.profile_by_prefix[prefix] then
    MR_MYTHICAL_DPS_CONFIG.profile_by_prefix[prefix] = legacy
  end
  MR_MYTHICAL_DPS_CONFIG.spec_key = nil
end
MR_MYTHICAL_DPS_CONFIG.seen_disclaimer = nil
MR_MYTHICAL_DPS_CONFIG.loadout_polish_enabled = nil
MR_MYTHICAL_DPS_CONFIG.loadout_deep_search = nil
MR_MYTHICAL_DPS_CONFIG.loadout_trim_enabled = nil
MR_MYTHICAL_DPS_CONFIG.loadout_trim_auto = nil
MR_MYTHICAL_DPS_CONFIG.loadout_per_slot_cap = nil
MR_MYTHICAL_DPS_CONFIG.loadout_weapon_pair_cap = nil

if MR_MYTHICAL_DPS_CONFIG.scan_performance_mode == nil then
  local legacyYield = tonumber(MR_MYTHICAL_DPS_CONFIG.loadout_scan_yield_every)
    or tonumber(MR_MYTHICAL_DPS_CONFIG.bag_scan_yield_every)
  if legacyYield and legacyYield ~= 40 then
    MR_MYTHICAL_DPS_CONFIG.scan_performance_mode = "custom"
    MR_MYTHICAL_DPS_CONFIG.loadout_scan_yield_every = legacyYield
  else
    MR_MYTHICAL_DPS_CONFIG.scan_performance_mode = "balanced"
  end
end
if MR_MYTHICAL_DPS_CONFIG.loadout_scan_yield_every == nil then
  MR_MYTHICAL_DPS_CONFIG.loadout_scan_yield_every = tonumber(MR_MYTHICAL_DPS_CONFIG.bag_scan_yield_every) or 40
end
MR_MYTHICAL_DPS_CONFIG.bag_scan_yield_every = nil
if MR_MYTHICAL_DPS_CONFIG.scan_performance_mode == "fast"
  or MR_MYTHICAL_DPS_CONFIG.scan_performance_mode == "maximum" then
  MR_MYTHICAL_DPS_CONFIG.scan_performance_mode = "balanced"
end

if MR_MYTHICAL_DPS_CONFIG.gear_finder_loot_ilvl and not MR_MYTHICAL_DPS_CONFIG.gear_finder_loot_upgrade then
  local legacyMap = {
    [250] = "champion_2",
    [253] = "champion_3",
    [256] = "champion_4",
    [259] = "hero_1",
    [263] = "hero_2",
    [266] = "hero_3",
  }
  MR_MYTHICAL_DPS_CONFIG.gear_finder_loot_upgrade = legacyMap[tonumber(MR_MYTHICAL_DPS_CONFIG.gear_finder_loot_ilvl)] or "hero_3"
end
if not MR_MYTHICAL_DPS_CONFIG.gear_finder_loot_upgrade then
  MR_MYTHICAL_DPS_CONFIG.gear_finder_loot_upgrade = "hero_3"
end

-- Gear Advisor config migration (legacy keys -> unified advisor keys).
if type(MR_MYTHICAL_DPS_CONFIG.gear_advisor_item_selection) ~= "table" then
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_item_selection = {}
end
if type(MR_MYTHICAL_DPS_CONFIG.gear_advisor_sources) ~= "table" then
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_sources = { bag = true, loot = false }
else
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_sources.vault = nil
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_sources.crest = nil
end
if not MR_MYTHICAL_DPS_CONFIG.gear_advisor_mode then
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_mode = "bags"
elseif MR_MYTHICAL_DPS_CONFIG.gear_advisor_mode == "loadout" then
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_mode = "bags"
end
if MR_MYTHICAL_DPS_CONFIG.gear_advisor_upgrades_only == nil and MR_MYTHICAL_DPS_CONFIG.gear_finder_upgrades_only ~= nil then
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_upgrades_only = MR_MYTHICAL_DPS_CONFIG.gear_finder_upgrades_only
end
if MR_MYTHICAL_DPS_CONFIG.gear_advisor_instance_id == nil and MR_MYTHICAL_DPS_CONFIG.gear_finder_instance_id ~= nil then
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_instance_id = MR_MYTHICAL_DPS_CONFIG.gear_finder_instance_id
end
if MR_MYTHICAL_DPS_CONFIG.gear_advisor_loot_upgrade == nil and MR_MYTHICAL_DPS_CONFIG.gear_finder_loot_upgrade ~= nil then
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_loot_upgrade = MR_MYTHICAL_DPS_CONFIG.gear_finder_loot_upgrade
end
if MR_MYTHICAL_DPS_CONFIG.gear_advisor_point == nil and MR_MYTHICAL_DPS_CONFIG.gear_finder_point ~= nil then
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_point = MR_MYTHICAL_DPS_CONFIG.gear_finder_point
end
if not MR_MYTHICAL_DPS_CONFIG.gear_advisor_loot_upgrade then
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_loot_upgrade = MR_MYTHICAL_DPS_CONFIG.gear_finder_loot_upgrade or "hero_3"
end
if MR_MYTHICAL_DPS_CONFIG.gear_finder_loot_upgrade == "journal" then
  MR_MYTHICAL_DPS_CONFIG.gear_finder_loot_upgrade = "hero_3"
end
if MR_MYTHICAL_DPS_CONFIG.gear_advisor_loot_upgrade == "journal" then
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_loot_upgrade = "hero_3"
end
if not MR_MYTHICAL_DPS_CONFIG.gear_advisor_instance_id then
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_instance_id = MR_MYTHICAL_DPS_CONFIG.gear_finder_instance_id or "all"
end
if not MR_MYTHICAL_DPS_CONFIG.gear_advisor_point and MR_MYTHICAL_DPS_CONFIG.dashboard_point then
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_point = MR_MYTHICAL_DPS_CONFIG.dashboard_point
end
if MR_MYTHICAL_DPS_CONFIG.gear_advisor_include_sidegrades == nil then
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_include_sidegrades = false
end

local function migrateBagSelectionToAdvisor()
  local legacy = MR_MYTHICAL_DPS_CONFIG.bag_item_selection
  local advisor = MR_MYTHICAL_DPS_CONFIG.gear_advisor_item_selection
  if type(legacy) ~= "table" then
    return
  end
  for key, value in pairs(legacy) do
    if advisor[key] == nil then
      advisor[key] = value
    end
  end
end
migrateBagSelectionToAdvisor()
MR_MYTHICAL_DPS_CONFIG.bag_item_selection = nil
MR_MYTHICAL_DPS_CONFIG.bag_scanner_point = nil
MR_MYTHICAL_DPS_CONFIG.bag_scan_upgrades_only = nil
MR_MYTHICAL_DPS_CONFIG.dashboard_point = nil
MR_MYTHICAL_DPS_CONFIG.gear_finder_point = nil
MR_MYTHICAL_DPS_CONFIG.gear_finder_tab = nil
MR_MYTHICAL_DPS_CONFIG.gear_finder_instance_id = nil
MR_MYTHICAL_DPS_CONFIG.gear_finder_upgrades_only = nil
MR_MYTHICAL_DPS_CONFIG.gear_finder_loot_upgrade = nil
MR_MYTHICAL_DPS_CONFIG.gear_finder_loot_ilvl = nil
MR_MYTHICAL_DPS_CONFIG.minimap_button_point = nil

function NS.getAdvisorItemSelectionTable()
  if type(MR_MYTHICAL_DPS_CONFIG.gear_advisor_item_selection) ~= "table" then
    MR_MYTHICAL_DPS_CONFIG.gear_advisor_item_selection = {}
  end
  return MR_MYTHICAL_DPS_CONFIG.gear_advisor_item_selection
end

function NS.purgeStaleVaultSelections(vaultRefs)
  local selection = NS.getAdvisorItemSelectionTable()
  local valid = {}
  for _, ref in ipairs(vaultRefs or {}) do
    if ref and ref.source == "vault" and ref.item_id then
      local actId = ref.vault_activity_id or 0
      valid[string.format("vault:%s:%d", tostring(actId), ref.item_id)] = true
    end
  end
  for key, _ in pairs(selection) do
    if type(key) == "string" and key:match("^vault:") and not valid[key] then
      selection[key] = nil
    end
  end
end

NS.ADVISOR_SIDEGRADE_DPS_FLOOR = -500
NS.DEFAULT_LOOT_UPGRADE_KEY = "hero_3"

function NS.getAdvisorIncludeSidegrades()
  return MR_MYTHICAL_DPS_CONFIG.gear_advisor_include_sidegrades == true
end

function NS.setAdvisorIncludeSidegrades(value)
  MR_MYTHICAL_DPS_CONFIG.gear_advisor_include_sidegrades = value and true or false
end

function NS.advisorCandidateIncludedByDefault(candidate)
  if not candidate then
    return false
  end
  if candidate.is_equipped_baseline then
    return true
  end
  if MR_MYTHICAL_DPS_CONFIG.gear_advisor_upgrades_only ~= true then
    return true
  end
  if candidate.is_upgrade then
    return true
  end
  if not NS.getAdvisorIncludeSidegrades() then
    return false
  end
  local dpsDelta = candidate.dps_delta
  if dpsDelta == nil then
    return false
  end
  return dpsDelta >= NS.ADVISOR_SIDEGRADE_DPS_FLOOR
end

function NS.isAdvisorCandidateSelected(candidate)
  if not candidate then
    return false
  end
  local key = candidate.key
  if not key then
    return true
  end
  local selection = NS.getAdvisorItemSelectionTable()
  if selection[key] == false then
    return false
  end
  if selection[key] == true then
    return true
  end
  return NS.advisorCandidateIncludedByDefault(candidate)
end

function NS.setAdvisorCandidateSelected(candidateOrKey, selected, forceInclude)
  local key = candidateOrKey
  if type(candidateOrKey) == "table" then
    key = candidateOrKey.key
  end
  if not key then
    return
  end
  local selection = NS.getAdvisorItemSelectionTable()
  if selected then
    if forceInclude then
      selection[key] = true
    else
      selection[key] = nil
    end
  else
    selection[key] = false
  end
end

local function gearIdentityMatchesEquipped(cand, eqRef)
  if not cand or not eqRef or not cand.link or not eqRef.link then
    return false
  end
  if cand.guid and eqRef.guid and cand.guid == eqRef.guid then
    return true
  end
  local candId = cand.item_id or tonumber(cand.link:match("item:(%d+)"))
  local eqId = tonumber(eqRef.link:match("item:(%d+)"))
  if not candId or not eqId or candId ~= eqId then
    return false
  end
  local candIlvl = cand.ilvl
  if not candIlvl or candIlvl <= 0 then
    candIlvl = NS.getItemIlvl and NS.getItemIlvl(cand.link) or 0
  end
  local eqIlvl = NS.getItemIlvl and NS.getItemIlvl(eqRef.link) or 0
  if candIlvl ~= eqIlvl then
    return false
  end
  local candTrack = cand.upgrade_track or cand.upgrade_rank
  if not candTrack and NS.getItemUpgradeTrackLabel then
    candTrack = NS.getItemUpgradeTrackLabel(cand.link)
  end
  local eqTrack = NS.getItemUpgradeTrackLabel and NS.getItemUpgradeTrackLabel(eqRef.link) or nil
  if NS.itemUpgradeTracksMatch then
    return NS.itemUpgradeTracksMatch(candTrack, eqTrack)
  end
  return (candTrack or "") == (eqTrack or "")
end

function NS.candidateMatchesEquippedGear(cand, slotId)
  if not cand or not cand.link or cand.is_equipped_baseline then
    return false
  end

  local slotsToCheck = {}
  if slotId then
    slotsToCheck[1] = slotId
  elseif cand.slot_id then
    slotsToCheck[1] = cand.slot_id
  elseif cand.equipLoc and NS.INVTYPE_TO_SLOT_IDS and NS.INVTYPE_TO_SLOT_IDS[cand.equipLoc] then
    slotsToCheck = NS.INVTYPE_TO_SLOT_IDS[cand.equipLoc]
  else
    return false
  end

  if not NS.getSlotItemRef then
    return false
  end
  for _, sid in ipairs(slotsToCheck) do
    local eqRef = NS.getSlotItemRef(sid)
    if eqRef and gearIdentityMatchesEquipped(cand, eqRef) then
      return true
    end
  end
  return false
end

function NS.deselectEquippedDuplicateCandidates(candidatesBySlot)
  if not candidatesBySlot then
    return
  end
  for slotId, list in pairs(candidatesBySlot) do
    for _, cand in ipairs(list or {}) do
      if cand and not cand.is_equipped_baseline and cand.key and cand.link then
        if NS.candidateMatchesEquippedGear(cand, slotId) then
          NS.setAdvisorCandidateSelected(cand, false)
        end
      end
    end
  end
end

function NS.applyAdvisorCandidateDefaults(candidates)
  local upgradesOnly = MR_MYTHICAL_DPS_CONFIG.gear_advisor_upgrades_only == true
  for _, cand in ipairs(candidates or {}) do
    if cand and not cand.is_equipped_baseline and cand.key then
      if NS.advisorCandidateIncludedByDefault(cand) then
        -- When not filtering to upgrades, clear stale deselects from prior scans/migration.
        NS.setAdvisorCandidateSelected(cand, true, not upgradesOnly)
      else
        NS.setAdvisorCandidateSelected(cand, false)
      end
    end
  end
end

function NS.applyAdvisorSelectionDefaults(candidates, candidatesBySlot, opts)
  opts = opts or {}
  if opts.reset_equipped_baselines then
    NS.resetEquippedBaselineSelections()
  end
  NS.applyAdvisorCandidateDefaults(candidates)
  if candidatesBySlot then
    NS.deselectEquippedDuplicateCandidates(candidatesBySlot)
  end
end

function NS.resetEquippedBaselineSelections()
  if not NS.getSlotItemRef then
    return
  end
  local slotOrder = NS.BAG_SCAN_SLOT_ORDER
  if not slotOrder or #slotOrder == 0 then
    return
  end
  local selection = NS.getAdvisorItemSelectionTable()
  for _, slotId in ipairs(slotOrder) do
    local eqRef = NS.getSlotItemRef(slotId)
    if eqRef then
      local keys = {}
      if eqRef.key then
        keys[#keys + 1] = eqRef.key
      end
      if eqRef.guid then
        keys[#keys + 1] = "guid:" .. tostring(eqRef.guid)
      end
      keys[#keys + 1] = "eq:" .. tostring(eqRef.slotId or slotId)
      if eqRef.link then
        keys[#keys + 1] = "link:" .. tostring(eqRef.link)
      end
      for _, key in ipairs(keys) do
        if selection[key] == false then
          selection[key] = nil
        end
      end
    end
  end
end

function NS.isGreatVaultFrameOpen()
  return WeeklyRewardsFrame and WeeklyRewardsFrame.IsShown and WeeklyRewardsFrame:IsShown()
end

function NS.isItemUpgradeFrameOpen()
  local frame = _G.ItemUpgradeFrame
  return frame and frame.IsShown and frame:IsShown()
end

function NS.getAdvisorLoadoutSourceConfig()
  local sources = MR_MYTHICAL_DPS_CONFIG.gear_advisor_sources
  if type(sources) ~= "table" then
    sources = { bag = true, loot = false }
    MR_MYTHICAL_DPS_CONFIG.gear_advisor_sources = sources
  end
  return sources
end

function NS.getAdvisorSources(mode)
  mode = mode or MR_MYTHICAL_DPS_CONFIG.gear_advisor_mode or "bags"
  if mode == "loadout" then
    mode = "bags"
  end
  if mode == "loot" then
    return {
      bag = false,
      loot = true,
      vault = false,
      crest = false,
    }
  end
  if mode == "bags" then
    return {
      bag = true,
      loot = false,
      vault = NS.isGreatVaultFrameOpen(),
      crest = false,
    }
  end
  return {
    bag = false,
    loot = false,
    vault = false,
    crest = false,
  }
end

function NS.serializeAdvisorSources(sources)
  sources = sources or {}
  local parts = {}
  for _, key in ipairs({ "bag", "loot", "vault", "crest" }) do
    if sources[key] then
      parts[#parts + 1] = key
    end
  end
  return table.concat(parts, ",")
end

function NS.purgeStaleLootSelections(lootRefs)
  local selection = NS.getAdvisorItemSelectionTable()
  local valid = {}
  for _, ref in ipairs(lootRefs or {}) do
    if ref and ref.source == "loot" then
      local itemID = ref.item_id or (ref.link and tonumber(ref.link:match("item:(%d+)")))
      local instanceId = ref.instance_id
      if itemID and instanceId then
        valid[string.format("loot:%d:%d", instanceId, itemID)] = true
      end
      if ref.seen_key then
        valid[ref.seen_key] = true
      end
      if ref.link then
        valid["link:" .. ref.link] = true
      end
    end
  end
  for key, _ in pairs(selection) do
    if type(key) == "string" and key:match("^loot:") and not valid[key] then
      selection[key] = nil
    end
  end
end

NS.active_spec_keys = {}
NS.active_spec_prefix = nil
NS.profileDetectionDoneRef = { false }
NS.baseDpsCacheDirty = true
NS.lastError = nil

NS.CLASS_TOKEN_TO_KEY = {
  DEATHKNIGHT = "Death_Knight",
  DEMONHUNTER = "Demon_Hunter",
  DRUID       = "Druid",
  EVOKER      = "Evoker",
  HUNTER      = "Hunter",
  MAGE        = "Mage",
  MONK        = "Monk",
  PALADIN     = "Paladin",
  PRIEST      = "Priest",
  ROGUE       = "Rogue",
  SHAMAN      = "Shaman",
  WARLOCK     = "Warlock",
  WARRIOR     = "Warrior",
}

NS.CLASS_PRIMARY_ARMOR = {
  WARRIOR     = 4, PALADIN     = 4, DEATHKNIGHT = 4,
  HUNTER      = 3, SHAMAN      = 3, EVOKER      = 3,
  ROGUE       = 2, DRUID       = 2, MONK        = 2, DEMONHUNTER = 2,
  MAGE        = 1, WARLOCK     = 1, PRIEST      = 1,
}

NS.INVTYPE_TO_SLOT_IDS = {
  INVTYPE_HEAD = {1},
  INVTYPE_NECK = {2},
  INVTYPE_SHOULDER = {3},
  INVTYPE_CLOAK = {15},
  INVTYPE_CHEST = {5},
  INVTYPE_ROBE = {5},
  INVTYPE_WRIST = {9},
  INVTYPE_HAND = {10},
  INVTYPE_WAIST = {6},
  INVTYPE_LEGS = {7},
  INVTYPE_FEET = {8},
  INVTYPE_FINGER = {11, 12},
  INVTYPE_TRINKET = {13, 14},
  INVTYPE_WEAPON = {16, 17},
  INVTYPE_2HWEAPON = {16},
  INVTYPE_WEAPONMAINHAND = {16},
  INVTYPE_WEAPONOFFHAND = {17},
  INVTYPE_HOLDABLE = {17},
  INVTYPE_SHIELD = {17},
  INVTYPE_RANGED = {16},
  INVTYPE_RANGEDRIGHT = {16},
}

NS.SLOT_ID_TO_NAME = {
  [1] = "HeadSlot", [2] = "NeckSlot", [3] = "ShoulderSlot", [5] = "ChestSlot",
  [6] = "WaistSlot", [7] = "LegsSlot", [8] = "FeetSlot", [9] = "WristSlot",
  [10] = "HandsSlot", [11] = "Finger0Slot", [12] = "Finger1Slot", [13] = "Trinket0Slot",
  [14] = "Trinket1Slot", [15] = "BackSlot", [16] = "MainHandSlot", [17] = "SecondaryHandSlot",
}

NS.SLOT_ID_LABELS = {
  [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist",
  [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Ring 1",
  [12] = "Ring 2", [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back",
  [16] = "Main Hand", [17] = "Off Hand",
}

function NS.debugPrint(...)
  if MR_MYTHICAL_DPS_CONFIG.debug then
    print(...)
  end
end

function NS.formatDelta(v)
  if v >= 0 then
    return string.format("+%.0f", v)
  end
  return string.format("%.0f", v)
end

NS.DPS_VS_EQUIPPED_LABEL = "DPS"
NS.DPS_VS_EQUIPPED_CREST_LABEL = "DPS/crest"
NS.LOADOUT_RESULT_STATUS_LABEL = "Change"
NS.LOADOUT_ROW_KEEP = "Keep"
NS.LOADOUT_ROW_CHANGE = "Change"
NS.LOADOUT_LOOT_SOURCE_LABEL = "Source"
NS.LOADOUT_CURRENT_LABEL = "Current"
NS.LOADOUT_RECOMMENDED_LABEL = "Recommended"
NS.CREST_AFTER_UPGRADE_LABEL = "After"
NS.CREST_HEADER_STEP = "Upgrade"
NS.CREST_HEADER_COST = "Cost"
NS.CREST_HEADER_DPS = "DPS/crest"
NS.CREST_PLAN_TITLE = "Plan"
NS.MSG_CREST_LITE_TITLE = "Crest plan"
NS.MSG_CREST_LITE_OPEN_ADVISOR = "Gear Advisor"
NS.MSG_CREST_OTHER_UPGRADES = "Other upgrades"
NS.MSG_CREST_MODE_HINT = "Crest spending plan."
NS.MSG_CREST_SCANNING = "Scanning…"
NS.MSG_CREST_BALANCES_PREFIX = "Owned:"
NS.MSG_CREST_EMPTY = "Nothing to upgrade."
NS.MSG_CREST_EMPTY_AFFORDABLE = "Nothing affordable."
NS.MSG_CREST_EMPTY_SCANNING = "Scanning…"
NS.MSG_TRINKET_BASELINE = "Trinkets excluded"
NS.MSG_LOADOUT_MODEL_SCOPE = "Set bonuses & trinket procs not modeled."
NS.DISCLAIMER_HEADER = NS.DISCLAIMER_SHORT .. " " .. NS.MSG_LOADOUT_MODEL_SCOPE
NS.MSG_PROFILE_LOW_CONFIDENCE = "Uncertain profile match"
NS.LOADOUT_ROW_EQUIPPED = "Equipped"
NS.LOADOUT_ROW_ALREADY_OPTIMAL = "Already optimal"

NS.MSG_NO_PROFILE_LABEL = "No profile — " .. NS.DASHBOARD_SLASH
NS.MSG_NO_PROFILE_ACTION = "Select a profile in " .. NS.DASHBOARD_SLASH .. "."
NS.MSG_FIND_LOADOUT_HINT = "Toggle items, then Find Loadout."
NS.MSG_LOOT_MODE_HINT = "Pick instance & track, then Find Loadout."
NS.MSG_SCAN_STATUS = "%s scored · %s selected. %s"
NS.MSG_SCAN_NO_COMBOS = "No valid combinations."
NS.MSG_SCAN_COUNTING = "Counting… %s. %s"
NS.MSG_SCAN_RECALC = "Recalculating… (%s). %s"
NS.MSG_SCAN_COMBOS = "%s combos%s. %s"
NS.MSG_VAULT_PICK_ONE = "One pick per week."
NS.MSG_VAULT_SWAP_HINT = "Single swap vs equipped."
NS.MSG_VAULT_TRINKET_DISCLAIMER = "Trinkets not scored."
NS.MSG_VAULT_LOADOUT_WINNER = "Best vault pick"
NS.MSG_VAULT_SCORING = "Scoring…"
NS.MSG_VAULT_TRINKET_ONLY = "Trinkets only."
NS.MSG_VAULT_NO_SCORABLE = "No scorable rewards."
NS.MSG_VAULT_UNSCORED = "%d unscored."
NS.MSG_VAULT_SCORE_ERRORS = " (%d errors)"
NS.MSG_EQUIP_PENDING = "Equipping…"
NS.MSG_EQUIP_DONE = "Equipped"
NS.MSG_EQUIP_FAILED = "Failed"
NS.MSG_EQUIP_COMBAT = "Can't equip in combat."
NS.MSG_EQUIP_STATUS_DONE = "Equipped %s."
NS.MSG_EQUIP_STATUS_PENDING = "Equipping %s…"
NS.MSG_EQUIP_STATUS_FAILED = "Couldn't equip %s."
NS.ADVISOR_SUBTITLE = ""

function NS.getDpsDeltaColor(delta)
  local d = tonumber(delta) or 0
  if d > 0 then
    return 0.2, 1, 0.2
  elseif d < 0 then
    return 1, 0.2, 0.2
  end
  return 0.55, 0.55, 0.6
end

function NS.setDpsDeltaTextColor(fontString, delta)
  fontString:SetTextColor(NS.getDpsDeltaColor(delta))
end

function NS.formatDpsVsEquipped(delta)
  return NS.formatDelta(delta or 0) .. " DPS"
end

function NS.formatDpsVsEquippedPerCrest(delta, perCrest)
  return string.format(
    "%s DPS (%s/crest)",
    NS.formatDelta(delta or 0),
    NS.formatDelta(perCrest or 0)
  )
end

function NS.formatCrestCostLabel(cost, baseCost, currencyId, discounted)
  local amount = tonumber(cost) or 0
  local base = tonumber(baseCost) or NS.CREST_UPGRADE_COST_AMOUNT or 20
  local name = "Crests"
  if currencyId and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyId)
    if info and info.name then
      name = info.name
    end
  end
  if amount <= 0 then
    return string.format("Free (%s)", name)
  end
  return string.format("%d %s", amount, name)
end

function NS.formatCrestIlvlLine(item)
  if not item then
    return ""
  end
  local cur = item.ilvl
  local nextIlvl = item.preview_ilvl
  local gain = item.ilvl_gain or 0
  if cur and nextIlvl and cur > 0 and nextIlvl > cur then
    return string.format("%d -> %d (+%d)", cur, nextIlvl, gain)
  end
  if gain > 0 then
    return string.format("+%d ilvl", gain)
  end
  return ""
end

local function crestRankLabel(track, level, maxLevel)
  if not level or not maxLevel then
    return nil
  end
  local rank = string.format("%d/%d", level, maxLevel)
  if track and track ~= "" then
    return string.format("%s %s", track, rank)
  end
  return rank
end

function NS.formatCrestUpgradeStepLine(item)
  if not item then
    return ""
  end
  local gain = tonumber(item.ilvl_gain) or 0
  local curIlvl = tonumber(item.ilvl)
  local nextIlvl = tonumber(item.preview_ilvl)
  if gain <= 0 and curIlvl and nextIlvl and nextIlvl > curIlvl then
    gain = nextIlvl - curIlvl
  end
  local track = item.upgrade_track
  local maxLevel = item.max_level
  local fromRank = item.upgrade_rank_from
  local toRank = item.upgrade_rank_to
  local curLevel = item.from_level or item.current_level
  local toLevel = item.to_level
  if not toLevel and curLevel and maxLevel then
    toLevel = curLevel + 1
  end
  if item.upgrade_group and NS.findCrestBonusInfoForGroupLevel then
    if curLevel then
      local fromInfo = NS.findCrestBonusInfoForGroupLevel(item.upgrade_group, curLevel)
      if fromInfo and fromInfo.itemLevel then
        curIlvl = fromInfo.itemLevel
      end
    end
    if toLevel then
      local toInfo = NS.findCrestBonusInfoForGroupLevel(item.upgrade_group, toLevel)
      if toInfo and toInfo.itemLevel then
        nextIlvl = toInfo.itemLevel
        gain = nextIlvl - (curIlvl or 0)
      end
    end
  end
  if not fromRank and curLevel and maxLevel then
    fromRank = crestRankLabel(track, curLevel, maxLevel)
  end
  if not toRank and toLevel and maxLevel then
    toRank = crestRankLabel(track, toLevel, maxLevel)
  end
  if not fromRank and item.upgrade_rank and item.current_level and maxLevel then
    fromRank = item.upgrade_rank
    toRank = toRank or crestRankLabel(track, item.current_level + 1, maxLevel)
  end
  local gainText = gain > 0 and string.format(" (+%d)", math.floor(gain + 0.5)) or ""
  if curIlvl and nextIlvl and fromRank and toRank then
    return string.format("%d %s > %d %s%s", curIlvl, fromRank, nextIlvl, toRank, gainText)
  end
  if fromRank and toRank then
    return string.format("%s > %s%s", fromRank, toRank, gainText)
  end
  return item.upgrade_rank or ""
end

function NS.setCrestCostTextColor(fontString, item)
  if not fontString or not item then
    return
  end
  if item.can_afford == false then
    fontString:SetTextColor(0.95, 0.42, 0.42)
  elseif item.crest_discounted or (item.crest_cost or 0) <= 0 then
    fontString:SetTextColor(0.45, 0.95, 0.55)
  else
    fontString:SetTextColor(0.92, 0.86, 0.58)
  end
end

NS.LOADOUT_COMBO_WARNING_LIMIT = 20000

NS.SCAN_PERF_YIELD_DEFAULT = 40
NS.SCAN_PERF_SCORE_BATCH_DEFAULT = 10
NS.SCAN_PERF_DELAY_DEFAULT = 0
NS.SCAN_PERF_MAX_YIELD_EVERY = 400
NS.SCAN_PERF_MAX_SCORE_BATCH = 50
NS.SCAN_PERF_MAX_RESUMES_PER_PUMP = 3
NS.COMBO_COUNT_MAX_RESUMES_PER_PUMP = 14
NS.SCAN_PERFORMANCE_USER_MODES = { "background", "balanced" }

NS.SCAN_PERFORMANCE_PRESETS = {
  background = {
    label = "Background",
    hint = "Smallest batches. Best while playing.",
    yield_every = 8,
    score_batch = 4,
    batch_delay_sec = 0.05,
    resumes_per_pump = 1,
  },
  balanced = {
    label = "Balanced",
    hint = "Faster. May lag briefly.",
    yield_every = 50,
    score_batch = 12,
    batch_delay_sec = 0,
    resumes_per_pump = 1,
  },
  custom = {
    label = "Custom",
    hint = "Manual debug values.",
    resumes_per_pump = 1,
  },
}

function NS.normalizeScanPerformanceMode(mode)
  mode = type(mode) == "string" and string.lower(mode) or "balanced"
  if mode == "fast" or mode == "maximum" then
    return "balanced"
  end
  if NS.SCAN_PERFORMANCE_PRESETS[mode] then
    return mode
  end
  return "balanced"
end

function NS.getAlternateScanPerformanceMode(mode)
  mode = NS.normalizeScanPerformanceMode(mode or NS.getScanPerformanceMode())
  if mode == "background" then
    return "balanced"
  end
  if mode == "balanced" then
    return "background"
  end
  return "balanced"
end

function NS.getScanPerformanceToggleButtonLabel(mode)
  local alternate = NS.getAlternateScanPerformanceMode(mode)
  local preset = NS.SCAN_PERFORMANCE_PRESETS[alternate]
  if preset and preset.label then
    return "Use " .. preset.label
  end
  return "Switch speed"
end

function NS.toggleScanPerformanceMode()
  local current = NS.getScanPerformanceMode()
  if current ~= "background" and current ~= "balanced" then
    current = "balanced"
  end
  local nextMode = NS.getAlternateScanPerformanceMode(current)
  NS.setScanPerformanceMode(nextMode)
  return nextMode
end

function NS.getScanPerformanceMode()
  return NS.normalizeScanPerformanceMode(MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.scan_performance_mode)
end

function NS.setScanPerformanceMode(mode)
  MR_MYTHICAL_DPS_CONFIG.scan_performance_mode = NS.normalizeScanPerformanceMode(mode)
end

function NS.getLoadoutScanYieldEvery(value)
  local yieldEvery = tonumber(value)
  if yieldEvery == nil then
    yieldEvery = tonumber(MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.loadout_scan_yield_every)
      or tonumber(MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.bag_scan_yield_every)
  end
  yieldEvery = yieldEvery and math.floor(yieldEvery) or NS.SCAN_PERF_YIELD_DEFAULT
  return math.max(1, math.min(5000, yieldEvery))
end

function NS.setLoadoutScanYieldEvery(value)
  local yieldEvery = NS.getLoadoutScanYieldEvery(value)
  MR_MYTHICAL_DPS_CONFIG.loadout_scan_yield_every = yieldEvery
  MR_MYTHICAL_DPS_CONFIG.scan_performance_mode = "custom"
  return yieldEvery
end

function NS.getGearScoreBatchSize(value)
  local batch = tonumber(value)
  if batch == nil then
    batch = tonumber(MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.gear_score_batch_size)
  end
  batch = batch and math.floor(batch) or NS.SCAN_PERF_SCORE_BATCH_DEFAULT
  return math.max(1, math.min(500, batch))
end

function NS.getScanBatchDelaySec(value)
  local delay = tonumber(value)
  if delay == nil then
    delay = tonumber(MR_MYTHICAL_DPS_CONFIG and MR_MYTHICAL_DPS_CONFIG.scan_batch_delay_sec)
  end
  delay = delay or NS.SCAN_PERF_DELAY_DEFAULT
  return math.max(0, math.min(1, delay))
end

local function clampScanResumesPerPump(mode, resumes)
  resumes = math.max(1, math.floor(tonumber(resumes) or 1))
  local cap = NS.SCAN_PERF_MAX_RESUMES_PER_PUMP or 3
  return math.min(cap, resumes)
end

function NS.clampScanPerformanceSettings(settings)
  settings = settings or {}
  local mode = settings.mode or "balanced"
  return {
    mode = mode,
    label = settings.label,
    hint = settings.hint,
    yield_every = math.max(1, math.min(
      NS.SCAN_PERF_MAX_YIELD_EVERY or 400,
      math.floor(tonumber(settings.yield_every) or NS.SCAN_PERF_YIELD_DEFAULT)
    )),
    score_batch = math.max(1, math.min(
      NS.SCAN_PERF_MAX_SCORE_BATCH or 50,
      math.floor(tonumber(settings.score_batch) or NS.SCAN_PERF_SCORE_BATCH_DEFAULT)
    )),
    batch_delay_sec = settings.batch_delay_sec,
    resumes_per_pump = clampScanResumesPerPump(mode, settings.resumes_per_pump),
  }
end

function NS.getScanPerformanceSettings()
  local mode = NS.getScanPerformanceMode()
  if mode ~= "custom" then
    local preset = NS.SCAN_PERFORMANCE_PRESETS[mode]
    return NS.clampScanPerformanceSettings({
      mode = mode,
      label = preset.label,
      hint = preset.hint,
      yield_every = preset.yield_every,
      score_batch = preset.score_batch,
      batch_delay_sec = preset.batch_delay_sec,
      resumes_per_pump = preset.resumes_per_pump or 1,
    })
  end
  local custom = NS.SCAN_PERFORMANCE_PRESETS.custom
  return NS.clampScanPerformanceSettings({
    mode = "custom",
    label = custom.label,
    hint = custom.hint,
    yield_every = NS.getLoadoutScanYieldEvery(),
    score_batch = NS.getGearScoreBatchSize(),
    batch_delay_sec = NS.getScanBatchDelaySec(),
    resumes_per_pump = custom.resumes_per_pump or 1,
  })
end

function NS.getInitialGearScanPerformanceSettings()
  local preset = NS.SCAN_PERFORMANCE_PRESETS.balanced
  return NS.clampScanPerformanceSettings({
    mode = "balanced",
    label = preset.label,
    hint = preset.hint,
    yield_every = preset.yield_every,
    score_batch = preset.score_batch,
    batch_delay_sec = preset.batch_delay_sec,
    resumes_per_pump = preset.resumes_per_pump or 1,
  })
end

function NS.getScanPerformanceDropdownLabel()
  return NS.getScanPerformanceSettings().label or NS.SCAN_PERFORMANCE_PRESETS.balanced.label
end

function NS.getScanPerformanceMenuHeader()
  return "Scan speed"
end

function NS.getScanPerformanceButtonTooltip()
  local title = NS.getScanPerformanceMenuHeader()
  local blocks = {}
  for _, modeId in ipairs(NS.SCAN_PERFORMANCE_USER_MODES) do
    local preset = NS.SCAN_PERFORMANCE_PRESETS[modeId]
    if preset then
      local block = preset.label
      if preset.hint and preset.hint ~= "" then
        block = block .. "\n" .. preset.hint
      end
      blocks[#blocks + 1] = block
    end
  end
  return title, table.concat(blocks, "\n\n")
end

-- Combination counting uses larger batches and never applies gameplay throttling delays.
NS.COMBO_COUNT_PERF_PRESETS = {
  background = { yield_every = 8000, resumes_per_pump = 6 },
  balanced = { yield_every = 20000, resumes_per_pump = 10 },
  custom = { yield_every = 20000, resumes_per_pump = 10 },
}

function NS.getComboCountPerformanceSettings()
  local mode = NS.getScanPerformanceMode()
  local preset = NS.COMBO_COUNT_PERF_PRESETS[mode] or NS.COMBO_COUNT_PERF_PRESETS.balanced
  local resumes = math.max(1, math.floor(tonumber(preset.resumes_per_pump) or 1))
  local cap = NS.COMBO_COUNT_MAX_RESUMES_PER_PUMP or 14
  return {
    mode = mode,
    yield_every = preset.yield_every,
    resumes_per_pump = math.min(cap, resumes),
    batch_delay_sec = 0,
    progress_interval_sec = 0.1,
  }
end

function NS.scheduleScanPump(delaySec, fn)
  local delay = tonumber(delaySec) or 0
  if delay > 0 then
    C_Timer.After(delay, fn)
  else
    C_Timer.After(0, fn)
  end
end

local function formatLargeNumberFallback(n)
  n = math.abs(math.floor(n + 0.5))
  if n >= 1000000 then
    local v = n / 1000000
    if v == math.floor(v) then
      return string.format("%dm", v)
    end
    return string.format("%.1fm", v):gsub("%.0m$", "m")
  end
  if n >= 10000 then
    local v = n / 1000
    if v == math.floor(v) then
      return string.format("%dk", v)
    end
    return string.format("%.1fk", v):gsub("%.0k$", "k")
  end
  return tostring(n)
end

function NS.formatLargeNumber(value)
  local n = tonumber(value)
  if not n then
    return tostring(value or "0")
  end
  n = math.floor(n + 0.5)
  local negative = n < 0
  n = math.abs(n)
  if n < 10000 then
    return negative and ("-" .. tostring(n)) or tostring(n)
  end
  local formatted = formatLargeNumberFallback(n)
  return negative and ("-" .. formatted) or formatted
end

function NS.isHighLoadoutComboCount(count)
  count = tonumber(count) or 0
  return count > NS.LOADOUT_COMBO_WARNING_LIMIT
end

function NS.getAddonVersion()
  local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if not getMetadata then
    return "?"
  end
  local version = getMetadata(ADDON_NAME, "Version") or "?"
  if version ~= "?" and version:sub(1, 1) ~= "v" then
    version = "v" .. version
  end
  return version
end

function NS.getCharacterSpecLabel()
  local _, classToken = UnitClass("player")
  local specIndex = GetSpecialization()
  if not classToken or not specIndex then
    return "Unknown"
  end
  local _, specName = GetSpecializationInfo(specIndex)
  if not specName then
    return classToken
  end
  return specName .. " (" .. classToken .. ")"
end

function NS.onProfileContextChanged()
  NS.predictionContextGeneration = (NS.predictionContextGeneration or 0) + 1
  if NS.clearStatCaches then
    NS.clearStatCaches()
  end
  NS.baseDpsCacheDirty = true
  if NS._clearPredictionCache then
    NS._clearPredictionCache()
  end
  if NS.refreshDashboard then
    NS.refreshDashboard()
  end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
if C_ClassTalents then
  eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
end
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")

eventFrame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    NS.detectAndCacheProfiles()
    NS.tryAutoMatchProfile()
    if NS.setupVaultAdvisor then
      NS.setupVaultAdvisor()
    end
    if NS.setupCrestUpgradeAdvisor then
      NS.setupCrestUpgradeAdvisor()
    end
    if MR_MYTHICAL_DPS_CONFIG.debug and NS.Model then
      local specCount = NS.Model.spec_keys and #NS.Model.spec_keys
        or (NS.Model.spec_feature_names and #NS.Model.spec_feature_names)
        or 0
      NS.debugPrint(string.format(
        "model %s (%d specs, forward calls=%d)",
        tostring(NS.Model.model_version),
        specCount,
        (NS.forwardProfile and NS.forwardProfile.count) or 0
      ))
    end
    NS.debugPrint(string.format(
      "%s loaded (%s). Type %s to open Gear Advisor.",
      NS.BRAND,
      NS.getAddonVersion(),
      NS.DASHBOARD_SLASH
    ))
  elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
    NS.profileDetectionDoneRef[1] = false
    NS.detectAndCacheProfiles()
    NS.tryAutoMatchProfile()
    NS.onProfileContextChanged()
    if NS.openGearAdvisor and #NS.active_spec_keys > 1 and not NS.getActiveProfileKey() then
      NS.openGearAdvisor(nil, nil, true)
    end
  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    NS.onProfileContextChanged()
  elseif event == "TRAIT_CONFIG_UPDATED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
    if MR_MYTHICAL_DPS_CONFIG.profile_mode ~= "manual" then
      NS.tryAutoMatchProfile()
    end
    NS.onProfileContextChanged()
  end
end)
