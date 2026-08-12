local ADDON_NAME, NS = ...

-- Shared instance / loot-upgrade dropdown state for Gear Advisor.
function NS.createLootControlState(opts)
  opts = opts or {}
  local lootUpgradeConfigKey = opts.lootUpgradeConfigKey or "gear_advisor_loot_upgrade"
  local instanceConfigKey = opts.instanceConfigKey or "gear_advisor_instance_id"
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
    self.selectedLootUpgradeKey = NS.syncLootUpgradeKey(self.selectedLootUpgradeKey)
    MR_MYTHICAL_DPS_CONFIG[lootUpgradeConfigKey] = self.selectedLootUpgradeKey
  end

  function state:getSelectedLootUpgradePreset()
    self:ensureSelectedLootUpgrade()
    return NS.getLootUpgradePreset(self.selectedLootUpgradeKey) or NS.LOOT_UPGRADE_PRESETS[1]
  end

  function state:getLootUpgradeLabel(key)
    local preset = NS.getLootUpgradePreset(key)
    if preset and preset.label then
      return preset.label
    end
    local fallback = NS.getLootUpgradePreset(NS.DEFAULT_LOOT_UPGRADE_KEY)
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
      self.selectedInstanceId = MR_MYTHICAL_DPS_CONFIG[instanceConfigKey] or NS.LOOT_ALL_INSTANCES
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
    if instanceId == NS.LOOT_ALL_INSTANCES then
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
    if self.selectedInstanceId == NS.LOOT_ALL_INSTANCES then
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
    self.selectedInstanceId = NS.LOOT_ALL_INSTANCES
    MR_MYTHICAL_DPS_CONFIG[instanceConfigKey] = NS.LOOT_ALL_INSTANCES
  end

  --- @return table[] { {text, value}, ... }
  function state:getIlvlItems()
    local items = {}
    for _, preset in ipairs(NS.getLootUpgradePresets() or {}) do
      table.insert(items, { text = preset.label, value = preset.key })
    end
    return items
  end

  --- @return table[] { {text, value}, ... }
  function state:getInstanceItems()
    self.instanceList = NS.collectEncounterJournalInstances()
    self:validateSelectedInstance()
    local items = {
      { text = "All current season", value = NS.LOOT_ALL_INSTANCES },
    }
    for _, inst in ipairs(self.instanceList or {}) do
      table.insert(items, { text = inst.label, value = inst.id })
    end
    return items
  end

  local function isLibDropdown(dropdown)
    return dropdown and type(dropdown.SetItems) == "function" and type(dropdown.SetValue) == "function"
  end

  function state:syncIlvlDropdownText(dropdown)
    if not dropdown then return end
    self:ensureSelectedLootUpgrade()
    local label = self:getLootUpgradeLabel(self.selectedLootUpgradeKey)
    if isLibDropdown(dropdown) then
      dropdown:SetValue(self.selectedLootUpgradeKey, true)
      if dropdown.Button and dropdown.Button.SetLabel then
        dropdown.Button:SetLabel(label)
      end
    else
      UIDropDownMenu_SetText(dropdown, label)
    end
  end

  function state:populateIlvlDropdown(dropdown, onChanged)
    if not dropdown then return end
    self:ensureSelectedLootUpgrade()
    if isLibDropdown(dropdown) then
      dropdown:SetItems(self:getIlvlItems())
      dropdown._onChanged = function(_, value)
        self.selectedLootUpgradeKey = value
        MR_MYTHICAL_DPS_CONFIG[lootUpgradeConfigKey] = value
        self:syncIlvlDropdownText(dropdown)
        if onChanged then onChanged() end
      end
      self:syncIlvlDropdownText(dropdown)
      return
    end
    UIDropDownMenu_Initialize(dropdown, function(_, level)
      local info = UIDropDownMenu_CreateInfo()
      info.notCheckable = true
      for _, preset in ipairs(NS.getLootUpgradePresets() or {}) do
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
    local label = self:getInstanceLabel(self.selectedInstanceId)
    if isLibDropdown(dropdown) then
      dropdown:SetValue(self.selectedInstanceId, true)
      if dropdown.Button and dropdown.Button.SetLabel then
        dropdown.Button:SetLabel(label)
      end
    else
      UIDropDownMenu_SetText(dropdown, label)
    end
  end

  function state:populateInstanceDropdown(dropdown, onChanged)
    if not dropdown then return end
    if isLibDropdown(dropdown) then
      dropdown:SetItems(self:getInstanceItems())
      dropdown._onChanged = function(_, value)
        self.selectedInstanceId = value
        MR_MYTHICAL_DPS_CONFIG[instanceConfigKey] = value
        self:syncInstanceDropdownText(dropdown)
        if onChanged then onChanged() end
      end
      self:syncInstanceDropdownText(dropdown)
      return
    end
    self.instanceList = NS.collectEncounterJournalInstances()
    self:validateSelectedInstance()
    UIDropDownMenu_Initialize(dropdown, function(_, level)
      local info = UIDropDownMenu_CreateInfo()
      info.notCheckable = true
      info.text = "All current season"
      info.func = function()
        self.selectedInstanceId = NS.LOOT_ALL_INSTANCES
        MR_MYTHICAL_DPS_CONFIG[instanceConfigKey] = NS.LOOT_ALL_INSTANCES
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
