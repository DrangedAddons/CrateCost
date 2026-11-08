-- CrateCost settings window: /cratecost config, right-click the minimap button, or
-- Options > AddOns > CrateCost.

local ADDON, ns = ...

ns.ICON = "Interface\\AddOns\\CrateCost\\icon"

local frame
local refreshers = {}

local function Track(w)
  refreshers[#refreshers + 1] = w
  return w
end

function ns.RefreshConfig()
  if not frame then return end
  for _, w in ipairs(refreshers) do w:Refresh() end
end

local function Text(parent, text, template)
  local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
  fs:SetText(text)
  return fs
end

local function Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function Tip(widget, text)
  if not text then return end
  widget:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- get() returns the current state, set(on) stores it.
local function Check(parent, label, get, set, x, y, tip)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", x, y)
  local fs = Text(parent, label)
  fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  Tip(cb, tip)
  function cb:Refresh() self:SetChecked(get() and true or false) end
  return Track(cb)
end

local function Setting(key)
  return function() return ns.Settings()[key] ~= false end,
    function(on) ns.Settings()[key] = on end
end

local function Build()
  frame = CreateFrame("Frame", "CrateCostConfig", UIParent, "BackdropTemplate")
  frame:SetSize(420, 330)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetScript("OnShow", ns.RefreshConfig)
  tinsert(UISpecialFrames, "CrateCostConfig")

  local title = Text(frame, "CrateCost", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -18)
  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20)
  icon:SetTexture(ns.ICON)
  icon:SetPoint("RIGHT", title, "LEFT", -6, 0)
  local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local version = Text(frame, "v" .. (getMeta and getMeta(ADDON, "Version") or "?"), "GameFontDisableSmall")
  version:SetPoint("TOPLEFT", 20, -20)
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  -- hide directly: the template's HideUIPanel path doesn't close unmanaged frames on Forever
  close:SetScript("OnClick", function() frame:Hide() end)
  close:SetPoint("TOPRIGHT", -6, -6)

  local L = 24
  Text(frame, "Crate tooltips", "GameFontNormal"):SetPoint("TOPLEFT", L, -50)
  local get, set = Setting("tooltip")
  Check(frame, "Show bundle prices", get, set, L, -68,
    "Auctionator prices next to each bundle on a Waylaid Crate's tooltip.")
  get, set = Setting("sortTooltip")
  Check(frame, "List the cheapest bundle first", get, set, L, -94,
    "Re-orders the bundle lines by price. Unchecked keeps the game's order.")
  get, set = Setting("highlight")
  Check(frame, "Highlight the best bundle in gold", get, set, L, -120)
  get, set = Setting("favorLine")
  Check(frame, "Show the Merchant's Favor line", get, set, L, -146)

  Text(frame, "General", "GameFontNormal"):SetPoint("TOPLEFT", L, -182)
  Check(frame, "Show minimap button",
    function() return not (CrateCostDB.minimap and CrateCostDB.minimap.hide) end,
    function(on) ns.SetMinimapShown(on) end, L, -200)

  local note = Text(frame, "Prices come from Auctionator. Hovering a crate in your bags saves its real "
    .. "bundle amounts for the crate list.", "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", L + 4, -236)
  note:SetWidth(372)
  note:SetJustifyH("LEFT")

  local list = Button(frame, "Crate list", 110, 24, function() ns.ToggleWindow() end)
  list:SetPoint("BOTTOMLEFT", 24, 20)
  Tip(list, "/crates")
  local cart = Button(frame, "Cart", 80, 24, function() ns.ShowCart() end)
  cart:SetPoint("LEFT", list, "RIGHT", 10, 0)
  local rec = Button(frame, "Recipes", 90, 24, function() ns.ToggleRecipes() end)
  rec:SetPoint("LEFT", cart, "RIGHT", 10, 0)
  Tip(rec, "/crates recipes")
end

function ns.ToggleConfig()
  if not frame then Build() frame:Hide() end
  frame:SetShown(not frame:IsShown())
end

-- Options > AddOns entry: points at the window.
local reg = CreateFrame("Frame")
reg:RegisterEvent("PLAYER_LOGIN")
reg:SetScript("OnEvent", function()
  if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
  local panel = CreateFrame("Frame")
  local t = Text(panel, "CrateCost", "GameFontNormalLarge")
  t:SetPoint("TOPLEFT", 16, -16)
  local open = Button(panel, "Open settings", 140, 24, function()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    if not (frame and frame:IsShown()) then ns.ToggleConfig() end
  end)
  open:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -12)
  local crates = Button(panel, "Crate list", 140, 24, function()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    ns.ToggleWindow()
  end)
  crates:SetPoint("LEFT", open, "RIGHT", 10, 0)
  local rec = Button(panel, "Recipes", 140, 24, function()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    ns.ToggleRecipes()
  end)
  rec:SetPoint("LEFT", crates, "RIGHT", 10, 0)
  local category = Settings.RegisterCanvasLayoutCategory(panel, "CrateCost")
  Settings.RegisterAddOnCategory(category)
end)

-- AddOn compartment (the minimap's addon menu)
function CrateCost_OnCompartmentClick(_, button)
  if button == "RightButton" then ns.ToggleConfig()
  elseif button == "MiddleButton" or IsShiftKeyDown() then ns.ToggleRecipes()
  else ns.ToggleWindow() end
end
