-- Shared window pieces for the Crates, Writs and Merchant windows, so all three have the
-- same shell, title row, nav bar, filter row widgets and footer.
local _, ns = ...

local UI = {}
ns.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8X8"
UI.GREY = "|cff808080"
UI.WIDTH = 1194         -- Crates and Writs: same width, so they line up side by side
UI.HEADER_Y = -64       -- column headers
UI.FILTER_Y = -34       -- search / dropdowns / toggles

local function Backdrop(f, bg, border)
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
  f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

-- Tooltip on hover: a white first line, then grey wrapped text.
function UI.Tip(w, title, text)
  w:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(title, 1, 1, 1)
    if text then GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
  end)
  w:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- every view of the one window (UI.RegisterView), declared before UI.Window uses it
local views = {}

-- The window: dark panel, movable, Esc closes, close button, title at the top left. `posKey`
-- remembers where it was dragged to (CrateCostDB[posKey], account-wide).
function UI.Window(name, titleText, width, height, posKey)
  local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  f:SetSize(width, height)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)   -- clicking one brings it in front of the others
  Backdrop(f, { 0.05, 0.05, 0.07, 0.95 }, { 0.3, 0.3, 0.35, 1 })
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if posKey and type(CrateCostDB) == "table" and self:GetLeft() then
      CrateCostDB[posKey] = { x = self:GetLeft(), y = self:GetTop() }
    end
  end)
  tinsert(UISpecialFrames, name)
  UI.RegisterView(f)
  -- closing a view (its X or Escape) goes back to Home; closing Home closes the window
  f:HookScript("OnHide", function(self)
    if UI.switching or self.isHome or not ns.ShowHome then return end
    C_Timer.After(0, function()
      for _, v in ipairs(views) do if v:IsShown() then return end end
      ns.ShowHome(self)
    end)
  end)

  f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 12, -10)
  f.title:SetText(titleText)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  -- hide directly: the template's HideUIPanel path doesn't close unmanaged frames on Forever
  close:SetScript("OnClick", function() f:Hide() end)
  close:SetPoint("TOPRIGHT", 2, 2)
  return f
end

-- The Crates, Writs and Merchant views act as one window: they share one saved position, and
-- opening one swaps it in where the shown one was.
UI.POS_KEY = "windowPos"
function UI.RegisterView(f) views[#views + 1] = f end

function UI.Open(f)
  local from
  for _, v in ipairs(views) do
    if v ~= f and v:IsShown() then from = v end
  end
  f:ClearAllPoints()
  local left, top = from and from:GetLeft(), from and from:GetTop()
  if left and top then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
  else
    UI.Place(f, UI.POS_KEY)
  end
  UI.switching = true   -- swapping views isn't closing one
  for _, v in ipairs(views) do
    if v ~= f then v:Hide() end
  end
  UI.switching = false
  f:Show()
  f:Raise()
end

-- Opens view `f`, or closes it if it's the one showing.
function UI.ToggleView(f)
  if f:IsShown() then f:Hide() else UI.Open(f) end
end

-- Puts `f` where it was last dragged to (CrateCostDB[posKey]), else centred. Centred means
-- the top edge sits at the same height whatever the view's height, so swapping views lines up.
function UI.Place(f, posKey)
  f:ClearAllPoints()
  local pos = posKey and type(CrateCostDB) == "table" and CrateCostDB[posKey]
  if pos and pos.x and pos.y then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
  else
    f:SetPoint("TOP", UIParent, "CENTER", 0, 330)
  end
end

-- The bar at the top right: Home (the way between views), Cart (n) and Refresh. The window's own
-- button is greyed out.
local cartButtons = {}
function UI.NavBar(f, current, onRefresh)
  local items = {
    { "home", "Home", 58, function() ns.ToggleHome() end, "Your favor, writs and rep, and the way to every view" },
  }
  items[#items + 1] = { "cart", "Cart", 72, function() ns.ShowCart() end, "The shopping list" }
  items[#items + 1] = { "refresh", "Refresh", 66, onRefresh, "Read prices again" }
  local prev
  for i = #items, 1, -1 do
    local it = items[i]
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(it[3], 20)
    if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("TOPRIGHT", -30, -6) end
    b:SetText(it[2])
    b:SetScript("OnClick", it[4])
    UI.Tip(b, it[2], it[5])
    if it[1] == current then b:Disable() end
    if it[1] == "cart" then cartButtons[#cartButtons + 1] = b end
    prev = b
  end
  UI.UpdateCartButtons()
  -- the view's count ("30 of 30 crates") sits bottom right: the title row is full
  f.count = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.count:SetPoint("BOTTOMRIGHT", -14, 9)
  f.count:SetJustifyH("RIGHT")
  return prev
end

-- "Open the plan with the AH" (per character, on by default): opening the auction house opens
-- the plan you used last (rep or favor). One setting, shown on Home and both plan views.
local ahChecks = {}
local function PlanAtAH()
  return not (type(CrateCostCharDB) == "table" and CrateCostCharDB.planAtAH == false)
end
function UI.PlanAtAHCheck(f, anchor, x)
  local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  cb:SetPoint("RIGHT", anchor, "LEFT", x or -190, 0)
  local l = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  l:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  l:SetText("Open the plan with the AH")
  cb:SetChecked(PlanAtAH())
  cb:SetScript("OnClick", function(self)
    if type(CrateCostCharDB) ~= "table" then CrateCostCharDB = {} end
    CrateCostCharDB.planAtAH = self:GetChecked() and true or false
    for _, other in ipairs(ahChecks) do other:SetChecked(PlanAtAH()) end
  end)
  cb:SetScript("OnShow", function(self) self:SetChecked(PlanAtAH()) end)
  UI.Tip(cb, "Open the plan with the AH", "When you open the auction house, open the plan you used last "
    .. "(rep or favor), ready to Scan AH and buy.")
  ahChecks[#ahChecks + 1] = cb
  return cb
end
local ahFrame = CreateFrame("Frame")
pcall(ahFrame.RegisterEvent, ahFrame, "AUCTION_HOUSE_SHOW")
ahFrame:SetScript("OnEvent", function()
  if not PlanAtAH() then return end
  C_Timer.After(0.3, function()
    local last = type(CrateCostCharDB) == "table" and CrateCostCharDB.lastPlan
    if last == "favor" then
      if ns.ShowFavorPlan then ns.ShowFavorPlan() end
    elseif ns.ShowWritPlan then
      ns.ShowWritPlan()
    end
  end)
end)

-- The plans' footer, centred: a summary line, the money as a little sum (up front, minus the
-- turn-in silver that comes back later, = net) a size up, and a big Add plan to cart button. A
-- note sits at the bottom left. Fills f.summary, f.moneyL/R (3 rows), f.add, f.note.
UI.PLAN_FOOT = 150
local SUM_W = 300   -- the sum's width: labels on the left, amounts right-aligned
function UI.PlanFooter(f, onAdd, tip, checklist)
  f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.summary:SetPoint("BOTTOM", 0, 124)
  f.moneyL, f.moneyR = {}, {}
  for i = 1, 3 do
    local y = 50 + (3 - i) * 22 + (i == 3 and 0 or 4)
    local l = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    l:SetPoint("BOTTOMLEFT", f, "BOTTOM", -SUM_W / 2, y)
    l:SetJustifyH("LEFT")
    local r = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    r:SetPoint("BOTTOMRIGHT", f, "BOTTOM", SUM_W / 2, y)
    r:SetJustifyH("RIGHT")
    f.moneyL[i], f.moneyR[i] = l, r
  end
  -- the rule above the net
  f.moneyRule = f:CreateTexture(nil, "OVERLAY")
  f.moneyRule:SetHeight(1)
  f.moneyRule:SetPoint("BOTTOMLEFT", f, "BOTTOM", -SUM_W / 2, 70)
  f.moneyRule:SetPoint("BOTTOMRIGHT", f, "BOTTOM", SUM_W / 2, 70)
  f.moneyRule:SetColorTexture(1, 0.82, 0, 0.5)
  local add = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  add:SetSize(260, 32)
  add:SetPoint("BOTTOM", 0, 12)
  add:SetText("Add plan to cart")
  if add.GetFontString and add:GetFontString() then pcall(add.SetNormalFontObject, add, "GameFontNormalLarge") end
  add:SetScript("OnClick", onAdd)
  UI.Tip(add, "Add plan to cart", tip)
  f.add = add
  -- the step-by-step checklist popout, beside the cart button
  if checklist then
    local cl = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cl:SetSize(110, 26)
    cl:SetPoint("LEFT", add, "RIGHT", 10, 0)
    cl:SetText("Checklist")
    cl:SetScript("OnClick", function() if ns.ToggleChecklist then ns.ToggleChecklist(checklist) end end)
    UI.Tip(cl, "Checklist", "A small window with just the plan's steps, ticked as you do them. Hover a step for details.")
    f.checklistBtn = cl
  end
  -- the bottom left holds the plan's tickboxes; notes go bottom right
  f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.note:SetPoint("BOTTOMRIGHT", -14, 34)
  f.note:SetWidth(200)
  f.note:SetJustifyH("RIGHT")
  f.note:SetWordWrap(true)
end

-- The sum, top to bottom:   Up front      45g
--                           Turn-ins pay back   -3g
--                           -----------------------
--                           Net           42g
-- Just "Total" when nothing comes back; nothing with no `upFront`. `guess`: a "~" in front, the
-- prices go past what the AH scan read.
function UI.PlanMoney(f, upFront, back, guess)
  local L, R = f.moneyL, f.moneyR
  for i = 1, 3 do L[i]:SetText("") R[i]:SetText("") end
  f.moneyRule:Hide()
  if not upFront then return end
  local g = guess and "|cffff9933~|r" or ""
  if back and back > 0 then
    local net = upFront - back
    L[1]:SetText("Up front")
    R[1]:SetText("|cffffffff" .. g .. ns.Money(upFront) .. "|r")
    L[2]:SetText("Turn-ins pay back")
    R[2]:SetText("|cff40ff40-" .. ns.Money(back) .. "|r")
    f.moneyRule:Show()
    if net >= 0 then
      L[3]:SetText("Net")
      R[3]:SetText("|cffffffff" .. g .. ns.Money(net) .. "|r")
    else
      L[3]:SetText("|cff40ff40Net profit|r")
      R[3]:SetText("|cff40ff40+" .. ns.Money(-net) .. "|r")
    end
  else
    L[3]:SetText("Total")
    R[3]:SetText("|cffffffff" .. g .. ns.Money(upFront) .. "|r")
  end
end

-- The plans' options (per character, shared by the rep and favor plans, on by default):
--   use what you have: writs you hold (rep plan) and crates you hold, Sealed Crates included
--     (favor plan, and the containers' favor crates) count before buying any;
--   use materials: items and bundle materials in your bags and bank count; off = buy all on the AH.
local function Opt(key)
  return not (type(CrateCostCharDB) == "table" and CrateCostCharDB[key] == false)
end
function ns.PlanUseOwned() return Opt("planUseOwned") end
-- Buy | Craft (per character, shared, Craft by default): Craft makes what your professions can
-- (a writ's item at its skill, a crafted crate's bundle) when that's cheaper; Buy buys it all.
function ns.PlanCraft() return Opt("planCraft") end

local craftToggles = {}
-- The Buy | Craft switch, left of `anchor` in a plan's filter row; `onChange` remakes that plan.
function UI.CraftToggle(f, anchor, onChange)
  local g = UI.Toggle(f, {
    { false, "Buy", "Buy everything on the AH: no crafting." },
    { true, "Craft", "Craft what your professions can make (a writ's item at its skill, Fabrics, Ingots "
      .. "and Parts bundles) when that's cheaper; the rest is bought." },
  }, 54, ns.PlanCraft, function(v)
    if type(CrateCostCharDB) ~= "table" then CrateCostCharDB = {} end
    CrateCostCharDB.planCraft = v and true or false
    for _, t in ipairs(craftToggles) do t:Refresh() end
    onChange()
  end)
  for _, b in ipairs(g.buttons) do b:ClearAllPoints() end
  g.last:SetPoint("RIGHT", anchor, "LEFT", -12, 0)
  for i = #g.buttons - 1, 1, -1 do g.buttons[i]:SetPoint("RIGHT", g.buttons[i + 1], "LEFT", 1, 0) end
  craftToggles[#craftToggles + 1] = g
  return g
end
function ns.PlanUseMats() return Opt("planUseMats") end

local optChecks = {}
-- The two tickboxes, stacked up from (x, y) at the bottom left of a plan (the footer). `onChange`
-- remakes that plan; the other plan's boxes follow. Returns the top one.
function UI.PlanOptions(f, x, y, onChange)
  local function Box(key, label, tip, below)
    local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    if below then cb:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, -2) else cb:SetPoint("BOTTOMLEFT", x, y) end
    local l = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l:SetPoint("LEFT", cb, "RIGHT", 1, 0)
    l:SetText(label)
    cb:SetChecked(Opt(key))
    cb:SetScript("OnClick", function(self)
      if type(CrateCostCharDB) ~= "table" then CrateCostCharDB = {} end
      CrateCostCharDB[key] = self:GetChecked() and true or false
      for _, o in ipairs(optChecks) do o.box:SetChecked(Opt(o.key)) end
      onChange()
    end)
    cb:SetScript("OnShow", function(self) self:SetChecked(Opt(key)) end)
    UI.Tip(cb, label, tip)
    optChecks[#optChecks + 1] = { box = cb, key = key }
    return cb
  end
  local mats = Box("planUseMats", "Use materials in bags & bank",
    "Items and bundle materials already in your bags and bank count. Untick to buy them all on the AH.")
  return Box("planUseOwned", "Use writs/crates you have",
    "Writs you hold (any character) are free in the rep plan; crates you hold and Sealed Crates in your bags "
      .. "count in the favor plan. Untick to plan as if you had none.", mats)
end

-- The plans' width: narrower than the lists.
UI.PLAN_W = 860

-- Buying from the open vendor (as CraftRoute does): find an item on its list by item ID, or by
-- name (a recipe "Mender's Potion" matches "Recipe: Mender's Potion"), and buy n of it, in
-- bundles or stacks as the vendor sells it. Listeners hear when a vendor opens, changes or closes.
local merchantOpen = false
local merchantListeners = {}
function UI.OnMerchant(fn) merchantListeners[#merchantListeners + 1] = fn end
function ns.MerchantOpen() return merchantOpen end

local function SlotName(i)
  if GetMerchantItemInfo then
    local ok, name = pcall(GetMerchantItemInfo, i)
    if ok and type(name) == "string" then return name end
  end
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
    if ok and type(info) == "table" then return info.name end
  end
end

-- price, batch (sold in), available (-1 = unlimited)
local function SlotInfo(i)
  if GetMerchantItemInfo then
    local ok, _, _, price, quantity, avail = pcall(GetMerchantItemInfo, i)
    if ok then return price, quantity, avail end
  end
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
    if ok and type(info) == "table" then return info.price, info.stackCount, info.numAvailable end
  end
end

function ns.MerchantFind(match)
  if not merchantOpen or not match then return nil end
  local n = (GetMerchantNumItems and GetMerchantNumItems()) or 0
  local m = type(match) == "string" and match:lower()
  for i = 1, n do
    if type(match) == "number" then
      if GetMerchantItemID and GetMerchantItemID(i) == match then return i end
    else
      local name = SlotName(i)
      if name then
        local l = name:lower()
        if l == m or l:sub(-(#m + 2)) == ": " .. m then return i end
      end
    end
  end
end

-- Buys `count` of slot i (capped by stock); returns how many purchases went out.
function ns.MerchantBuy(i, count)
  if not (i and count and count > 0 and BuyMerchantItem) then return 0 end
  local _, batch, avail = SlotInfo(i)
  batch = math.max(1, batch or 1)
  local purchases = math.ceil(count / batch)
  if avail and avail >= 0 then purchases = math.min(purchases, avail) end
  if purchases <= 0 then return 0 end
  if batch > 1 then
    for _ = 1, purchases do BuyMerchantItem(i) end   -- sold in bundles: one call per bundle
  else
    local maxStack = math.max(1, GetMerchantItemMaxStack and GetMerchantItemMaxStack(i) or 1)
    local left = purchases
    while left > 0 do
      local k = math.min(left, maxStack)
      BuyMerchantItem(i, k)
      left = left - k
    end
  end
  return purchases
end

local mFrame = CreateFrame("Frame")
for _, ev in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE" }) do pcall(mFrame.RegisterEvent, mFrame, ev) end
mFrame:SetScript("OnEvent", function(_, ev)
  if ev == "MERCHANT_SHOW" then merchantOpen = true elseif ev == "MERCHANT_CLOSED" then merchantOpen = false end
  C_Timer.After(0.2, function()
    for _, fn in ipairs(merchantListeners) do pcall(fn) end
  end)
end)

-- A small Buy button for a row: shown while the open vendor sells `match`, buys `count` on click.
function UI.BuyButton(parent)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(40, 17)
  b:SetText("Buy")
  b:Hide()
  b:SetScript("OnClick", function(self)
    local i = self.match and ns.MerchantFind(self.match)
    if i then
      ns.MerchantBuy(i, self.count or 1)
    end
  end)
  UI.Tip(b, "Buy", "Buys it from the vendor you have open.")
  return b
end

-- Shows `b` for `match` x `count` when the open vendor sells it; returns whether it's shown.
function UI.SetBuy(b, match, count)
  b.match, b.count = match, count
  local ok = match and count and count > 0 and ns.MerchantFind(match) ~= nil
  b:SetShown(ok and true or false)
  return ok
end

function UI.UpdateCartButtons()
  local n = ns.CartCount and ns.CartCount() or 0
  for _, b in ipairs(cartButtons) do b:SetText("Cart (" .. n .. ")") end
end

-- Search box at the start of the filter row, with a grey hint while empty. `onChange` gets the
-- trimmed, lower-case text whenever it changes.
function UI.Search(f, hint, width, onChange)
  local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  search:SetSize(width or 170, 20)
  search:SetPoint("TOPLEFT", 18, UI.FILTER_Y)
  search:SetAutoFocus(false)
  search:SetMaxLetters(40)
  local h = search:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  h:SetPoint("LEFT", 2, 0)
  h:SetText(hint)
  local last = ""
  local function OnSearch(self)
    local t = self:GetText() or ""
    h:SetShown(t == "" and not self:HasFocus())
    t = t:lower():match("^%s*(.-)%s*$")
    if t ~= last then
      last = t
      onChange(t)
    end
  end
  search:SetScript("OnTextChanged", OnSearch)
  search:SetScript("OnEditFocusGained", function() h:Hide() end)
  search:SetScript("OnEditFocusLost", OnSearch)
  search:SetScript("OnEscapePressed", search.ClearFocus)
  search:SetScript("OnEnterPressed", search.ClearFocus)
  return search
end

-- A dropdown button (our own: UIDropDownMenu isn't reliable on Forever).
function UI.DropButton(f, w, anchor, x)
  local b = CreateFrame("Button", nil, f, "BackdropTemplate")
  b:SetSize(w, 20)
  b:SetPoint("LEFT", anchor, "RIGHT", x, 0)
  Backdrop(b, { 0.12, 0.12, 0.15, 1 }, { 0.35, 0.35, 0.4, 1 })
  b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  b.text:SetPoint("LEFT", 6, 0)
  b.text:SetPoint("RIGHT", -18, 0)
  b.text:SetJustifyH("LEFT")
  local arrow = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  arrow:SetPoint("RIGHT", -6, 0)
  arrow:SetText("v")
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.06)
  return b
end

-- Its menu: `choices` = { {label, value}, "-" (a gap), {heading = "text"}, ... }. Picking one
-- calls onPick(value). Hidden when the window hides.
function UI.Menu(f, btn, choices, w, onPick)
  local m = CreateFrame("Frame", nil, btn, "BackdropTemplate")
  m:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
  m:SetFrameStrata("DIALOG")
  Backdrop(m, { 0.08, 0.08, 0.1, 0.98 }, { 0.35, 0.35, 0.4, 1 })
  m:EnableMouse(true)
  m:Hide()
  local y = -4
  for _, c in ipairs(choices) do
    if c == "-" then
      y = y - 4
    elseif c.heading then
      local h = m:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
      h:SetPoint("TOPLEFT", 8, y)
      h:SetText(c.heading)
      y = y - 16
    else
      local it = CreateFrame("Button", nil, m)
      it:SetSize(w - 4, 16)
      it:SetPoint("TOPLEFT", 2, y)
      local t = it:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      t:SetPoint("LEFT", 8, 0)
      t:SetText(c[1])
      local hl = it:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints()
      hl:SetColorTexture(1, 1, 1, 0.1)
      it:SetScript("OnClick", function()
        m:Hide()
        onPick(c[2])
      end)
      y = y - 16
    end
  end
  m:SetSize(w, -y + 4)
  btn:SetScript("OnClick", function() m:SetShown(not m:IsShown()) end)
  f:HookScript("OnHide", function() m:Hide() end)
  return m
end

-- A checkbox with its label to the right. Returns the label (anchor for the next widget).
function UI.Check(f, label, anchor, x, tip, get, set)
  local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  cb:SetPoint("LEFT", anchor, "RIGHT", x, 0)
  local fs = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", cb, "RIGHT", 1, 0)
  fs:SetText(label)
  cb:SetChecked(get())
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  if tip then UI.Tip(cb, label, tip) end
  return fs
end

-- A two-or-more-way toggle: joined buttons, the active one gold. `options` = { {value, label,
-- tip}, ... }; get() returns the active value, set(value) changes it. Call :Refresh() after.
function UI.Toggle(f, options, width, get, set)
  local group = { buttons = {} }
  for i, o in ipairs(options) do
    local b = CreateFrame("Button", nil, f, "BackdropTemplate")
    b:SetSize(width, 20)
    if i > 1 then b:SetPoint("LEFT", group.buttons[i - 1], "RIGHT", -1, 0) end
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(o[2])
    b.value = o[1]
    b:SetScript("OnClick", function(self) set(self.value) end)
    UI.Tip(b, o[2], o[3])
    group.buttons[i] = b
  end
  group.first, group.last = group.buttons[1], group.buttons[#options]
  function group:Refresh()
    local v = get()
    for _, b in ipairs(self.buttons) do
      local on = b.value == v
      b:SetBackdropColor(on and 0.25 or 0.12, on and 0.22 or 0.12, on and 0.1 or 0.15, 1)
      b:SetBackdropBorderColor(on and 1 or 0.35, on and 0.82 or 0.35, on and 0 or 0.4, 1)
      b.text:SetTextColor(on and 1 or 0.6, on and 1 or 0.6, on and 1 or 0.6)
    end
  end
  group:Refresh()
  return group
end

-- Toggles on the right end of the filter row, right to left: the first group ends at the
-- window's right edge, each next one sits left of the previous.
function UI.PlaceToggles(f, groups)
  local prev
  for _, g in ipairs(groups) do
    for _, b in ipairs(g.buttons) do b:ClearAllPoints() end
    if prev then
      g.last:SetPoint("RIGHT", prev.first, "LEFT", -12, 0)
    else
      g.last:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, UI.FILTER_Y)
    end
    -- chain the rest leftwards from the last button
    for i = #g.buttons - 1, 1, -1 do
      g.buttons[i]:SetPoint("RIGHT", g.buttons[i + 1], "LEFT", 1, 0)
    end
    prev = g
  end
end

-- Sortable column headers. `sort` = { key = current, desc = bool }; onClick(col) re-sorts.
function UI.Headers(f, cols, xoff, onClick)
  local headers = {}
  for _, col in ipairs(cols) do
    local h = CreateFrame("Button", nil, f)
    h:SetSize(col.w, 16)
    h:SetPoint("TOPLEFT", f, "TOPLEFT", col.x + (xoff or 0), UI.HEADER_Y)
    h.col = col
    h.text = h:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    h.text:SetAllPoints()
    h.text:SetJustifyH(col.justify)
    local hl = h:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    h:SetScript("OnClick", function() onClick(col) end)
    headers[#headers + 1] = h
  end
  return headers
end

-- The Owned views move a few columns: a column with .ownedX (and .ownedJustify) sits there while
-- `owned`, at .x otherwise. Re-anchors those columns' headers and row cells (money slots too).
local SUB = 28
function UI.Relayout(rows, headers, cols, owned)
  for _, col in ipairs(cols) do
    if col.ownedX then
      local x = owned and col.ownedX or col.x
      local j = owned and col.ownedJustify or col.justify
      for _, h in ipairs(headers) do
        if h.col == col then
          h:ClearAllPoints()
          h:SetPoint("TOPLEFT", h:GetParent(), "TOPLEFT", x, UI.HEADER_Y)
          h.text:SetJustifyH(j)
        end
      end
      for _, row in ipairs(rows) do
        local fs = row.cells and row.cells[col.key]
        if fs then
          fs:ClearAllPoints()
          fs:SetPoint("LEFT", row, "LEFT", x - 10, 0)
          fs:SetJustifyH(j)
        end
        local m = row.money and row.money[col.key]
        if m then
          m.g:ClearAllPoints()
          m.g:SetPoint("LEFT", row, "LEFT", x - 10, 0)
          m.s:ClearAllPoints()
          m.s:SetPoint("LEFT", row, "LEFT", x - 10 + col.w - SUB * 2, 0)
          m.c:ClearAllPoints()
          m.c:SetPoint("LEFT", row, "LEFT", x - 10 + col.w - SUB, 0)
        end
      end
    end
  end
end

-- Header text: the sorted one white with its arrow.
function UI.HeaderText(h, title, sorted, desc)
  h.text:SetText((sorted and "|cffffffff" or "") .. title .. (sorted and ((desc and " v" or " ^") .. "|r") or ""))
end

-- The grey footer line at the bottom left.
function UI.Footer(f)
  local fs = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  fs:SetPoint("BOTTOMLEFT", 12, 8)
  fs:SetPoint("RIGHT", f, "RIGHT", -230, 0)   -- room for the count, bottom right
  fs:SetJustifyH("LEFT")
  return fs
end
