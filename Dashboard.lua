local ADDON_NAME, NS = ...

local LOGO_TEXTURE = string.format("Interface\\AddOns\\%s\\Logo.tga", ADDON_NAME)

local minimapBtn = nil

local function createMinimapButton()
  if minimapBtn then
    return minimapBtn
  end

  local btn = CreateFrame("Button", "MrMythicalDpsMinimapButton", Minimap)
  btn:SetSize(32, 32)
  btn:SetFrameStrata("MEDIUM")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local icon = btn:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER")
  icon:SetTexture(LOGO_TEXTURE)
  btn.icon = icon
  btn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:SetScript("OnClick", function()
    NS.openGearAdvisor()
  end)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(NS.BRAND)
    GameTooltip:AddLine(string.format("%s opens Gear Advisor", NS.DASHBOARD_SLASH), 1, 1, 1)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", GameTooltip_Hide)

  minimapBtn = btn
  return btn
end

if AddonCompartmentFrame then
  AddonCompartmentFrame:RegisterAddon({
    text = NS.BRAND,
    icon = LOGO_TEXTURE,
    notCheckable = true,
    func = function()
      NS.openGearAdvisor()
    end,
    funcOnEnter = function(frame)
      GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
      GameTooltip:SetText(NS.BRAND)
      GameTooltip:AddLine("Open Gear Advisor", 1, 1, 1)
      GameTooltip:Show()
    end,
    funcOnLeave = GameTooltip_Hide,
  })
end

createMinimapButton()
