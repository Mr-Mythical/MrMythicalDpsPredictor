local ADDON_NAME, NS = ...

-- Shared instance / loot-upgrade dropdown state for Gear Finder and Gear Advisor.
function NS.createLootControlState(opts)
  opts = opts or {}
  local lootUpgradeConfigKey = opts.lootUpgradeConfigKey or "gear_finder_loot_upgrade"
  local instanceConfigKey = opts.instanceConfigKey or "gear_finder_instance_id"
  local defaultLootUpgrade = opts.defaultLootUpgrade or "hero_3"

  local state = {
    selectedLootUpgradeKey = nil,
    selectedInstanceId = nil,
    instanceList = nil,
  }

  function state:ensureSelectedLootUpgrade()
    if self.selectedLootUpgradeKey == nil then
      self.selectedLootUpgradeKey = MR_MYTHICAL_DPS_CONFIG[lootUpgradeConfigKey] or defaultLootUpgrade
    end
    self.selectedLootUpgradeKey = NS.syncGearFinderLootUpgradeKey(self.selectedLootUpgradeKey)
    MR_MYTHICAL_DPS_CONFIG[lootUpgradeConfigKey] = self.selectedLootUpgradeKey
  end

  function state:getSelectedLootUpgradePreset()
    self:ensureSelectedLootUpgrade()
    return NS.getGearFinderLootUpgradePreset(self.selectedLootUpgradeKey) or NS.GEAR_FINDER_LOOT_ILVL_PRESETS[1]
  end

  function state:getLootUpgradeLabel(key)
    local preset = NS.getGearFinderLootUpgradePreset(key)
    if preset and preset.label then
      return preset.label
    end
    local fallback = NS.getGearFinderLootUpgradePreset(NS.DEFAULT_LOOT_UPGRADE_KEY)
    return fallback and fallback.label or "Hero 3"
  end

  function state:getLootScanOpts(upgradesOnly)
    return {
      upgrades_only = upgradesOnly,
      preset = self:getSelectedLootUpgradePreset(),
    }
  end

  function state:ensureSelectedInstance()
    if self.selectedInstanceId == nil then
      self.selectedInstanceId = MR_MYTHICAL_DPS_CONFIG[instanceConfigKey] or NS.GEAR_FINDER_ALL_INSTANCES
    end
  end

  function state:getInstanceName(instanceId)
    if self.instanceList then
      for _, inst in ipairs(self.instanceList) do
        if inst.id == instanceId then
          return inst.name
        end
      end
    end
    return nil
  end

  function state:getInstanceLabel(instanceId)
    if instanceId == NS.GEAR_FINDER_ALL_INSTANCES then
      return "All current season"
    end
    if self.instanceList then
      for _, inst in ipairs(self.instanceList) do
        if inst.id == instanceId then
          return inst.label
        end
      end
    end
    return "Instance"
  end

  function state:validateSelectedInstance()
    if self.selectedInstanceId == NS.GEAR_FINDER_ALL_INSTANCES then
      return
    end
    if not self.instanceList then
      return
    end
    for _, inst in ipairs(self.instanceList) do
      if inst.id == self.selectedInstanceId then
        return
      end
    end
    self.selectedInstanceId = NS.GEAR_FINDER_ALL_INSTANCES
    MR_MYTHICAL_DPS_CONFIG[instanceConfigKey] = NS.GEAR_FINDER_ALL_INSTANCES
  end

  function state:syncIlvlDropdownText(dropdown)
    if not dropdown then return end
    self:ensureSelectedLootUpgrade()
    UIDropDownMenu_SetText(dropdown, self:getLootUpgradeLabel(self.selectedLootUpgradeKey))
  end

  function state:populateIlvlDropdown(dropdown, onChanged)
    if not dropdown then return end
    self:ensureSelectedLootUpgrade()
    UIDropDownMenu_Initialize(dropdown, function(_, level)
      local info = UIDropDownMenu_CreateInfo()
      info.notCheckable = true
      for _, preset in ipairs(NS.getGearFinderLootUpgradePresets() or {}) do
        info.text = preset.label
        info.func = function()
          self.selectedLootUpgradeKey = preset.key
          MR_MYTHICAL_DPS_CONFIG[lootUpgradeConfigKey] = preset.key
          self:syncIlvlDropdownText(dropdown)
          if onChanged then onChanged() end
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end)
    self:syncIlvlDropdownText(dropdown)
  end

  function state:syncInstanceDropdownText(dropdown)
    if not dropdown then return end
    self:ensureSelectedInstance()
    UIDropDownMenu_SetText(dropdown, self:getInstanceLabel(self.selectedInstanceId))
  end

  function state:populateInstanceDropdown(dropdown, onChanged)
    if not dropdown then return end
    self.instanceList = NS.collectEncounterJournalInstances()
    self:validateSelectedInstance()
    UIDropDownMenu_Initialize(dropdown, function(_, level)
      local info = UIDropDownMenu_CreateInfo()
      info.notCheckable = true
      info.text = "All current season"
      info.func = function()
        self.selectedInstanceId = NS.GEAR_FINDER_ALL_INSTANCES
        MR_MYTHICAL_DPS_CONFIG[instanceConfigKey] = NS.GEAR_FINDER_ALL_INSTANCES
        self:syncInstanceDropdownText(dropdown)
        if onChanged then onChanged() end
      end
      UIDropDownMenu_AddButton(info, level)

      for _, inst in ipairs(self.instanceList) do
        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.text = inst.label
        info.func = function()
          self.selectedInstanceId = inst.id
          MR_MYTHICAL_DPS_CONFIG[instanceConfigKey] = inst.id
          self:syncInstanceDropdownText(dropdown)
          if onChanged then onChanged() end
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end)
    self:syncInstanceDropdownText(dropdown)
  end

  return state
end
