-- CrateValue minimap button: a LibDBIcon button (so minimap addons can collect it).
-- Left-click opens the crate list, right-click the settings.

local ADDON, ns = ...

local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBI = LibStub and LibStub("LibDBIcon-1.0", true)

function ns.SetMinimapShown(on)
  ns.Settings()
  CrateValueDB.minimap.hide = not on
  if not DBI then return end
  if on then DBI:Show("CrateValue") else DBI:Hide("CrateValue") end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
  if not (LDB and DBI) then return end
  ns.Settings()
  local launcher = LDB:NewDataObject("CrateValue", {
    type = "launcher",
    text = "CrateValue",
    icon = ns.ICON,
    OnClick = function(_, button)
      if button == "RightButton" then ns.ToggleConfig() else ns.ToggleWindow() end
    end,
    OnTooltipShow = function(tt)
      tt:AddLine("CrateValue")
      tt:AddLine("|cffffd100Left-click|r: crate list", 1, 1, 1)
      tt:AddLine("|cffffd100Right-click|r: settings", 1, 1, 1)
      tt:AddLine("|cffffd100Drag|r to move this button", 1, 1, 1)
    end,
  })
  DBI:Register("CrateValue", launcher, CrateValueDB.minimap)
end)
