local ADDON_NAME, NS = ...

--[[
  Droptimizer-style farm priority from single-swap Δs (web rankSeasonInstancesFromEstimates).
  EV = mean of max(0, Δ) over unique drops; Best = max Δ; priority only when EV > 0.
]]

local FARM_ICON_CAP = 6
local EV_EPS = 1e-9

local function trim(s)
  if type(s) ~= "string" then
    return ""
  end
  return (s:match("^%s*(.-)%s*$")) or ""
end

local function bossKeyOf(cand)
  local instanceName = trim(cand.instance_name)
  if instanceName == "" then
    instanceName = "Unknown"
  end
  local instanceKind = trim(cand.instance_kind)
  if instanceKind == "" then
    instanceKind = "Dungeon"
  end
  local encounterName = trim(cand.encounter_name)
  if encounterName == "" then
    encounterName = instanceName
  end
  return encounterName, instanceName, instanceKind
end

local function pieceIdentity(cand)
  if cand.key and cand.key ~= "" then
    return cand.key
  end
  if cand.link and cand.link ~= "" then
    return cand.link
  end
  local itemId = cand.item_id or (cand.link and tonumber(cand.link:match("item:(%d+)")))
  return "id:" .. tostring(itemId or 0)
end

--- Rank bosses from scored loot candidates (post weapon-pair scoring).
--- @param candidates table[] flat list with dps_delta, slot_id, item fields
--- @return table[] farm ranks (all bosses; priority nil when EV == 0)
function NS.rankLootFarmPriorityFromCandidates(candidates)
  local byBoss = {}

  for _, cand in ipairs(candidates or {}) do
    if cand and not cand.is_equipped_baseline then
      local delta = cand.dps_delta
      if type(delta) == "number" then
        local encounterName, instanceName, instanceKind = bossKeyOf(cand)
        local bossKey = instanceKind .. "\0" .. instanceName .. "\0" .. encounterName
        local acc = byBoss[bossKey]
        if not acc then
          acc = {
            encounter_name = encounterName,
            instance_name = instanceName,
            instance_kind = instanceKind,
            by_piece = {},
          }
          byBoss[bossKey] = acc
        end
        local id = pieceIdentity(cand)
        local prev = acc.by_piece[id]
        local slotId = cand.slot_id or 0
        if not prev or delta > prev.delta then
          acc.by_piece[id] = {
            delta = delta,
            slot_id = slotId,
            slot_label = cand.slot_label
              or (NS.SLOT_ID_LABELS and NS.SLOT_ID_LABELS[slotId])
              or tostring(slotId),
            candidate = cand,
          }
        end
      end
    end
  end

  local ranks = {}
  for _, acc in pairs(byBoss) do
    local hits = {}
    for _, hit in pairs(acc.by_piece) do
      hits[#hits + 1] = hit
    end
    local n = #hits
    if n > 0 then
      local sumPos = 0
      local bestDps = 0
      local bestBySlot = {}
      for _, hit in ipairs(hits) do
        if hit.delta > 0 then
          sumPos = sumPos + hit.delta
        end
        if hit.delta > bestDps then
          bestDps = hit.delta
        end
        local slotId = hit.slot_id or 0
        local prev = bestBySlot[slotId]
        if not prev or hit.delta > prev.estimate_delta then
          bestBySlot[slotId] = {
            slot_id = slotId,
            slot_label = hit.slot_label,
            candidate = hit.candidate,
            estimate_delta = hit.delta,
          }
        end
      end

      local drops = {}
      for _, drop in pairs(bestBySlot) do
        drops[#drops + 1] = drop
      end
      table.sort(drops, function(a, b)
        local aUp = a.estimate_delta > 0 and 1 or 0
        local bUp = b.estimate_delta > 0 and 1 or 0
        if aUp ~= bUp then
          return aUp > bUp
        end
        if a.estimate_delta ~= b.estimate_delta then
          return a.estimate_delta > b.estimate_delta
        end
        return (a.slot_id or 0) < (b.slot_id or 0)
      end)

      ranks[#ranks + 1] = {
        encounter_name = acc.encounter_name,
        instance_name = acc.instance_name,
        instance_kind = acc.instance_kind,
        expected_value_dps = sumPos / n,
        best_dps = bestDps,
        priority = nil,
        drop_count = n,
        drops = drops,
      }
    end
  end

  table.sort(ranks, function(a, b)
    if math.abs(b.expected_value_dps - a.expected_value_dps) > 1e-6 then
      return b.expected_value_dps > a.expected_value_dps
    end
    if math.abs(b.best_dps - a.best_dps) > 1e-6 then
      return b.best_dps > a.best_dps
    end
    return (a.encounter_name or "") < (b.encounter_name or "")
  end)

  local priority = 0
  for _, row in ipairs(ranks) do
    if row.expected_value_dps > EV_EPS then
      priority = priority + 1
      row.priority = priority
    else
      row.priority = nil
    end
  end

  return ranks
end

--- Flatten slot map → farm ranks (selected loot only when respectSelection).
function NS.rankLootFarmPriorityFromSlotMap(candidatesBySlot, opts)
  opts = opts or {}
  local flat = {}
  for _, list in pairs(candidatesBySlot or {}) do
    for _, cand in ipairs(list) do
      if cand and not cand.is_equipped_baseline and type(cand.dps_delta) == "number" then
        if opts.respect_selection == false
          or not NS.isAdvisorCandidateSelected
          or NS.isAdvisorCandidateSelected(cand)
        then
          flat[#flat + 1] = cand
        end
      end
    end
  end
  return NS.rankLootFarmPriorityFromCandidates(flat)
end

--- Bosses with EV > 0 only (web Farm priority list).
function NS.filterFarmPriorityRanks(ranks)
  local out = {}
  for _, row in ipairs(ranks or {}) do
    if row.priority ~= nil then
      out[#out + 1] = row
    end
  end
  return out
end

NS.FARM_SORT_OPTIONS = {
  { key = "ev", label = "Expected Value" },
  { key = "best", label = "Best upgrade" },
  { key = "name", label = "Boss name" },
}

function NS.getFarmSortLabel(sortKey)
  for _, opt in ipairs(NS.FARM_SORT_OPTIONS) do
    if opt.key == sortKey then
      return opt.label
    end
  end
  return "Expected Value"
end

function NS.normalizeFarmSortKey(sortKey)
  if sortKey == "best" or sortKey == "name" or sortKey == "ev" then
    return sortKey
  end
  return "ev"
end

--- Same order as web `compareFarmBosses` (EV/Best high→low; name A→Z).
--- Lua table.sort wants true when `a` must come before `b`.
function NS.compareFarmBosses(a, b, sortKey)
  sortKey = NS.normalizeFarmSortKey(sortKey)
  local aEv = a.expected_value_dps or 0
  local bEv = b.expected_value_dps or 0
  local aBest = a.best_dps or 0
  local bBest = b.best_dps or 0
  local aName = a.encounter_name or ""
  local bName = b.encounter_name or ""

  if sortKey == "best" then
    if math.abs(aBest - bBest) > 1e-6 then
      return aBest > bBest
    end
    if math.abs(aEv - bEv) > 1e-6 then
      return aEv > bEv
    end
    return aName < bName
  end

  if sortKey == "name" then
    if aName ~= bName then
      return aName < bName
    end
    return (a.priority or 999) < (b.priority or 999)
  end

  if math.abs(aEv - bEv) > 1e-6 then
    return aEv > bEv
  end
  if math.abs(aBest - bBest) > 1e-6 then
    return aBest > bBest
  end
  return aName < bName
end

function NS.sortFarmPriorityRanks(ranks, sortKey)
  local out = {}
  for i, row in ipairs(ranks or {}) do
    out[i] = row
  end
  table.sort(out, function(a, b)
    return NS.compareFarmBosses(a, b, sortKey)
  end)
  return out
end

--- Group EV>0 bosses by instance (web `seasonFarmGroupedRanks`).
function NS.groupFarmPriorityByInstance(ranks, sortKey)
  sortKey = NS.normalizeFarmSortKey(sortKey)
  local map = {}
  local order = {}
  for _, boss in ipairs(ranks or {}) do
    local key = (boss.instance_kind or "Dungeon") .. "\0" .. (boss.instance_name or "Unknown")
    local group = map[key]
    if not group then
      group = {
        instance_kind = boss.instance_kind or "Dungeon",
        instance_name = boss.instance_name or "Unknown",
        bosses = {},
        group_ev = 0,
        group_best = 0,
      }
      map[key] = group
      order[#order + 1] = key
    end
    group.bosses[#group.bosses + 1] = boss
    local ev = boss.expected_value_dps or 0
    local best = boss.best_dps or 0
    if ev > group.group_ev then
      group.group_ev = ev
    end
    if best > group.group_best then
      group.group_best = best
    end
  end

  local groups = {}
  for _, key in ipairs(order) do
    groups[#groups + 1] = map[key]
  end

  for _, group in ipairs(groups) do
    table.sort(group.bosses, function(a, b)
      return NS.compareFarmBosses(a, b, sortKey)
    end)
  end

  table.sort(groups, function(a, b)
    if sortKey == "name" then
      local ak = a.instance_kind == "Raid" and 0 or 1
      local bk = b.instance_kind == "Raid" and 0 or 1
      if ak ~= bk then
        return ak < bk
      end
      return (a.instance_name or "") < (b.instance_name or "")
    end
    if sortKey == "best" then
      if math.abs(a.group_best - b.group_best) > 1e-6 then
        return a.group_best > b.group_best
      end
      return a.group_ev > b.group_ev
    end
    if math.abs(a.group_ev - b.group_ev) > 1e-6 then
      return a.group_ev > b.group_ev
    end
    return a.group_best > b.group_best
  end)

  return groups
end

function NS.getFarmPriorityIconCap()
  return FARM_ICON_CAP
end
