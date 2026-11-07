local _, ns = ...

-- The cart: crates and their best bundles added from /crates, merged by item. Ported from
-- CraftRoute's cart: tick items on/off, change amounts, remove them, name the list, then
-- Create Shopping List makes an Auctionator list (exact searches with quantities).
-- Kept per character in CrateValueCharDB.cart until it's cleared or turned into a list.

local CALLER = "CrateValue"
local ROWS, ROW_H = 12, 22
local TOP, FOOT = 36, 110

local function Cart()
  if type(CrateValueCharDB) ~= "table" then CrateValueCharDB = {} end
  CrateValueCharDB.cart = CrateValueCharDB.cart or {}
  return CrateValueCharDB.cart
end

local function ItemName(id, fallback)
  local name = id and C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)
  return name or fallback
end

local function Icon(id)
  if id and C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function Key(it) return it.id or it.name end

-- items: { { id = n|nil, name = "..", qty = n } }; same item adds up.
function ns.CartAdd(items)
  local cart = Cart()
  local added = 0
  for _, new in ipairs(items) do
    if new.qty and new.qty > 0 then
      local found
      for _, it in ipairs(cart) do
        if Key(it) == Key(new) then found = it break end
      end
      if found then
        found.qty = found.qty + new.qty
        found.on = true
      else
        cart[#cart + 1] = { id = new.id, name = new.name, qty = new.qty, on = true }
      end
      added = added + 1
    end
  end
  if ns.OnCartChanged then ns.OnCartChanged() end
  return added
end

function ns.CartCount() return #Cart() end

local function UnitPrice(it) return it.id and ns.Price(it.id) end
local function Cost(it)
  local p = UnitPrice(it)
  return p and p * it.qty or nil
end

-- The list CrateValue made last time is replaced, unless you named it yourself.
local function RemovePrevious()
  if type(CrateValueDB) ~= "table" then return end
  local old = CrateValueDB.lastList
  CrateValueDB.lastList = nil
  if type(old) ~= "string" then return end
  local lm = Auctionator.Shopping and Auctionator.Shopping.ListManager
  if lm and lm.GetIndexForName and lm.Delete then
    pcall(function() if lm:GetIndexForName(old) then lm:Delete(old) end end)
  end
end

local function CreateList(name, suggested, chosen)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and api.CreateShoppingList) then
    ns.Print("Auctionator's shopping list API isn't available.")
    return false
  end
  local terms = {}
  for _, it in ipairs(chosen) do
    local n = ItemName(it.id, it.name)
    local ok, str = pcall(api.ConvertToSearchString, CALLER,
      { searchString = n, isExact = true, categoryKey = "", quantity = it.qty })
    terms[#terms + 1] = ok and str or ('"' .. n .. '"')
  end
  if #terms == 0 then ns.Print("Nothing ticked - no shopping list made.") return false end
  RemovePrevious()
  local ok, err = pcall(api.CreateShoppingList, CALLER, name, terms)
  if not ok then
    ns.Print("Couldn't create the shopping list: " .. tostring(err))
    return false
  end
  if type(CrateValueDB) ~= "table" then CrateValueDB = {} end
  CrateValueDB.lastList = (name == suggested) and name or nil
  ns.Print(string.format("Auctionator shopping list '%s' created with %d item%s.",
    name, #terms, #terms == 1 and "" or "s"))
  return true
end

local f
local function Build()
  f = CreateFrame("Frame", "CrateValueCart", UIParent, "BackdropTemplate")
  f:SetSize(440, TOP + ROWS * ROW_H + FOOT)
  f:SetPoint("CENTER", 0, 80)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  f:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
  f:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  tinsert(UISpecialFrames, "CrateValueCart")

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText("Crate shopping cart")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  f.empty:SetPoint("TOP", 0, -TOP - 20)
  f.empty:SetText("Empty. Use + on a /crates row to add a crate and its best bundle.")

  f.offset, f.rows = 0, {}
  for i = 1, ROWS do
    local r = CreateFrame("Frame", nil, f)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 10, -TOP - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    r.tick = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.tick:SetSize(20, 20)
    r.tick:SetPoint("LEFT", 0, 0)
    r.tick:SetScript("OnClick", function(self)
      if r.it then r.it.on = self:GetChecked() and true or false end
      f:Fill()
    end)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", r.tick, "RIGHT", 2, 0)
    r.remove = CreateFrame("Button", nil, r, "UIPanelCloseButton")
    r.remove:SetSize(20, 20)
    r.remove:SetPoint("RIGHT", 0, 0)
    r.remove:SetScript("OnClick", function()
      local cart = Cart()
      for k, it in ipairs(cart) do
        if it == r.it then table.remove(cart, k) break end
      end
      if ns.OnCartChanged then ns.OnCartChanged() end
      f:Fill()
    end)
    r.cost = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.cost:SetPoint("RIGHT", r.remove, "LEFT", -4, 0)
    r.cost:SetWidth(100)
    r.cost:SetJustifyH("RIGHT")
    r.qty = CreateFrame("EditBox", nil, r, "InputBoxTemplate")
    r.qty:SetSize(44, 18)
    r.qty:SetPoint("RIGHT", r.cost, "LEFT", -8, 0)
    r.qty:SetAutoFocus(false)
    r.qty:SetNumeric(true)
    r.qty:SetMaxLetters(5)
    r.qty:SetJustifyH("CENTER")
    -- (HasFocus, not the userInput flag: that flag isn't passed on Forever)
    local function SaveQty(self)
      local n = tonumber(self:GetText())
      if r.it and n then
        r.it.qty = n
        local c = Cost(r.it)
        r.cost:SetText(c and ns.Money(c) or "|cff808080?|r")
        f:Totals()
      end
    end
    r.qty:SetScript("OnTextChanged", function(self) if self:HasFocus() then SaveQty(self) end end)
    r.qty:SetScript("OnEditFocusLost", SaveQty)
    r.qty:SetScript("OnEnterPressed", function(self) SaveQty(self) self:ClearFocus() end)
    r.qty:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", r.qty, "LEFT", -8, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
      if not (self.it and self.it.id) then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(self.it.id)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(_, delta) f.offset = f.offset - delta * 3 f:Fill() end)
    f.rows[i] = r
  end
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(self, delta) self.offset = self.offset - delta * 3 self:Fill() end)

  f.more = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.total = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.total:SetJustifyH("RIGHT")
  f.totalLine = f:CreateTexture(nil, "ARTWORK")
  f.totalLine:SetHeight(1)
  f.totalLine:SetColorTexture(1, 0.82, 0.35, 0.35)

  local nameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  nameLabel:SetPoint("BOTTOMLEFT", 14, 50)
  nameLabel:SetText("List name:")
  f.box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  f.box:SetHeight(22)
  f.box:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0)
  f.box:SetPoint("RIGHT", f, "RIGHT", -16, 0)
  f.box:SetAutoFocus(false)
  f.box:SetMaxLetters(80)

  local function Create()
    local name = strtrim(f.box:GetText() or "")
    if name == "" then name = f.suggested end
    local chosen = {}
    for _, it in ipairs(Cart()) do
      if it.on and it.qty > 0 then chosen[#chosen + 1] = it end
    end
    if CreateList(name, f.suggested, chosen) then
      -- what went on the list leaves the cart; unticked items stay
      local keep = {}
      for _, it in ipairs(Cart()) do
        if not (it.on and it.qty > 0) then keep[#keep + 1] = it end
      end
      CrateValueCharDB.cart = keep
      if ns.OnCartChanged then ns.OnCartChanged() end
      f:Hide()
    end
  end
  f.box:SetScript("OnEnterPressed", Create)
  f.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  local function Btn(text, w)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    return b
  end
  local clear = Btn("Clear", 80)
  clear:SetPoint("BOTTOMLEFT", 14, 12)
  clear:SetScript("OnClick", function()
    CrateValueCharDB.cart = {}
    if ns.OnCartChanged then ns.OnCartChanged() end
    f:Fill()
  end)
  local closeBtn = Btn("Close", 80)
  closeBtn:SetPoint("BOTTOMRIGHT", -14, 12)
  closeBtn:SetScript("OnClick", function() f:Hide() end)
  f.create = Btn("Create Shopping List", 170)
  f.create:SetPoint("BOTTOM", 0, 12)
  f.create:SetScript("OnClick", Create)

  function f:Totals()
    local n, total, unknown = 0, 0, false
    for _, it in ipairs(Cart()) do
      if it.on and it.qty > 0 then
        n = n + 1
        local c = Cost(it)
        if c then total = total + c else unknown = true end
      end
    end
    self.summary:SetText(string.format("%d item%s", n, n == 1 and "" or "s"))
    self.total:SetText(ns.Money(total) .. (unknown and " |cff808080+?|r" or ""))
    self.create:SetEnabled(n > 0)
  end

  function f:Fill()
    local items = Cart()
    self.offset = math.max(0, math.min(self.offset, #items - ROWS))
    for i = 1, ROWS do
      local r = self.rows[i]
      local it = items[self.offset + i]
      r.it = it
      if it then
        r.tick:SetChecked(it.on)
        r.icon:SetTexture(Icon(it.id))
        r.name:SetText(ItemName(it.id, it.name) or "?")
        r.name:SetAlpha(it.on and 1 or 0.45)
        if not r.qty:HasFocus() then r.qty:SetText(tostring(it.qty)) end
        local c = Cost(it)
        r.cost:SetText(c and ns.Money(c) or "|cff808080?|r")
        r.cost:SetAlpha(it.on and 1 or 0.45)
        r:Show()
      else
        r:Hide()
      end
    end
    self.empty:SetShown(#items == 0)
    local shown = math.min(#items, ROWS)
    local rowsH = math.max(3, shown) * ROW_H
    self:SetHeight(TOP + rowsH + FOOT)
    local y = -TOP - rowsH - 4
    self.totalLine:ClearAllPoints()
    self.totalLine:SetPoint("TOPRIGHT", self, "TOPRIGHT", -36, y)
    self.totalLine:SetWidth(100)
    self.total:ClearAllPoints()
    self.total:SetPoint("TOPRIGHT", self, "TOPRIGHT", -36, y - 4)
    self.summary:ClearAllPoints()
    self.summary:SetPoint("TOPLEFT", self, "TOPLEFT", 14, y - 5)
    self.more:ClearAllPoints()
    self.more:SetPoint("TOP", self, "TOP", 0, y - 5)
    self.more:SetShown(#items > ROWS)
    self.more:SetText(string.format("%d-%d of %d  (scroll)", self.offset + 1,
      math.min(#items, self.offset + ROWS), #items))
    self:Totals()
  end
end

function ns.ShowCart()
  if not f then Build() end
  f.suggested = "CrateValue crates (" .. date("%H:%M") .. ")"
  f.box:SetText(f.suggested)
  f.box:HighlightText()
  f.offset = 0
  f:Show()
  f:Fill()
end

function ns.RefreshCart()
  if f and f:IsShown() then f:Fill() end
end
