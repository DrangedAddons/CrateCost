-- CrateCost minimap button: a LibDBIcon button (so minimap addons can collect it).
-- Left-click opens the crate list, shift- or middle-click the merchant list, right-click the settings.

local ADDON, ns = ...

local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBI = LibStub and LibStub("LibDBIcon-1.0", true)

function ns.SetMinimapShown(on)
  ns.Settings()
  CrateCostDB.minimap.hide = not on
  if not DBI then return end
  if on then DBI:Show("CrateCost") else DBI:Hide("CrateCost") end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
  if not (LDB and DBI) then return end
  ns.Settings()
  local launcher = LDB:NewDataObject("CrateCost", {
    type = "launcher",
    text = "CrateCost",
    icon = ns.ICON,
    OnClick = function(_, button)
      if button == "RightButton" then ns.ToggleConfig()
      elseif button == "MiddleButton" or IsShiftKeyDown() then ns.ToggleRecipes()
      else ns.ToggleWindow() end
    end,
    OnTooltipShow = function(tt)
      tt:AddLine("CrateCost")
      tt:AddLine("|cffffd100Left-click|r: crate list", 1, 1, 1)
      tt:AddLine("|cffffd100Shift-click|r or |cffffd100middle-click|r: merchant (what Merchant's Favor buys)", 1, 1, 1)
      tt:AddLine("|cffffd100Right-click|r: settings", 1, 1, 1)
      tt:AddLine("|cffffd100Drag|r to move this button", 1, 1, 1)
    end,
  })
  DBI:Register("CrateCost", launcher, CrateCostDB.minimap)
end)
