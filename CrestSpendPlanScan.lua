local ADDON_NAME, NS = ...

local COLLECT_YIELD_EVERY = 1
local CHAIN_YIELD_EVERY = 2
local SEARCH_YIELD_EVERY = 75

function NS.cancelCrestSpendPlanScan(handle)
  if handle then
    handle.cancelled = true
  end
end

function NS.startCrestSpendPlanScan(specKey, opts)
  opts = opts or {}
  NS._crestSpendPlanScanSerial = (NS._crestSpendPlanScanSerial or 0) + 1
  local handle = { cancelled = false, id = NS._crestSpendPlanScanSerial }

  local counts = { collect = 0, chains = 0, optimize = 0 }
  local thresholds = {
    collect = COLLECT_YIELD_EVERY,
    chains = CHAIN_YIELD_EVERY,
    optimize = SEARCH_YIELD_EVERY,
  }

  local function clearYieldHook()
    NS._crestScanYield = nil
  end

  local function installYieldHook()
    NS._crestScanYield = function(phase)
      if not coroutine.running() then
        return
      end
      phase = phase or "optimize"
      counts[phase] = (counts[phase] or 0) + 1
      local every = thresholds[phase] or SEARCH_YIELD_EVERY
      if counts[phase] >= every then
        counts[phase] = 0
        coroutine.yield({ kind = "progress", phase = phase })
      end
    end
  end

  local function isAlive()
    return not handle.cancelled
  end

  local co = coroutine.create(function()
    installYieldHook()
    local rows = opts.rows
    local note = opts.note
    if not rows then
      rows, note = NS.collectCrestUpgradeOpportunities(specKey)
    end

    if opts.collectOnly then
      clearYieldHook()
      return {
        kind = "complete",
        plan = {},
        spent = {},
        totalDps = 0,
        rows = rows or {},
        note = note,
        chains = {},
      }
    end

    NS.refreshCrestRowAffordability(rows)
    local hasAffordable = false
    for _, row in ipairs(rows or {}) do
      if row.can_afford then
        hasAffordable = true
        break
      end
    end
    if not hasAffordable then
      clearYieldHook()
      return {
        kind = "complete",
        plan = {},
        spent = {},
        totalDps = 0,
        rows = rows or {},
        note = note,
        chains = {},
      }
    end

    coroutine.yield({ kind = "progress", phase = "optimize" })
    local plan, spent, totalDps, chains = NS.optimizeCrestSpendPlan(rows, specKey)
    clearYieldHook()
    return {
      kind = "complete",
      plan = plan or {},
      spent = spent or {},
      totalDps = totalDps or 0,
      rows = rows or {},
      note = note,
      chains = chains or {},
    }
  end)

  local function pump()
    if not isAlive() then
      clearYieldHook()
      return
    end

    local ok, payload = coroutine.resume(co)
    if not isAlive() then
      clearYieldHook()
      return
    end

    if not ok then
      clearYieldHook()
      if opts.onError then
        opts.onError(tostring(payload))
      end
      return
    end

    if coroutine.status(co) == "dead" then
      clearYieldHook()
      if payload and payload.kind == "complete" then
        if opts.onComplete then
          opts.onComplete(
            payload.plan,
            payload.spent,
            payload.totalDps,
            payload.rows,
            payload.note,
            payload.chains
          )
        end
      end
      return
    end

    if payload and payload.kind == "progress" and opts.onProgress then
      opts.onProgress(payload.phase, payload.detail)
    end

    if NS.scheduleScanPump then
      NS.scheduleScanPump(0, pump)
    else
      C_Timer.After(0, pump)
    end
  end

  if NS.scheduleScanPump then
    NS.scheduleScanPump(0, pump)
  else
    C_Timer.After(0, pump)
  end
  return handle
end
