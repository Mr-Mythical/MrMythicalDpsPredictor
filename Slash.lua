local ADDON_NAME, NS = ...

local SLASH_MODES = {
  bags = "bags",
  bag = "bags",
  loot = "loot",
  crests = "crests",
  crest = "crests",
}

function MrMythicalDpsPredictor_OpenDashboard()
  if NS.openGearAdvisor then
    NS.openGearAdvisor()
  end
end

SLASH_MYTHICALDPS1 = NS.DASHBOARD_SLASH
SlashCmdList.MYTHICALDPS = function(msg)
  msg = strtrim(msg or ""):lower()

  if msg == "" then
    MrMythicalDpsPredictor_OpenDashboard()
    return
  end

  if msg == "debug" then
    MR_MYTHICAL_DPS_CONFIG.debug = not MR_MYTHICAL_DPS_CONFIG.debug
    NS.brandPrint(MR_MYTHICAL_DPS_CONFIG.debug and "Debug enabled." or "Debug disabled.")
    return
  end

  local mode = SLASH_MODES[msg]
  if mode then
    NS.openGearAdvisor(nil, mode)
    return
  end

  NS.brandPrint(string.format(
    "Unknown command '%s'. Usage: %s [bags|loot|crests|debug]",
    msg,
    NS.DASHBOARD_SLASH
  ))
end
