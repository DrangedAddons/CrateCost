local _, ns = ...

-- The buy panel: docked to the auction house, it works through the last shopping list CrateCost
-- made (a plan's, or the cart's), one item at a time. For the current item it searches the AH,
-- shows what buying the rest of it costs right now against what the plan expected, and Buy buys
-- it: a commodity in one purchase for the whole amount, an auction one at a time. Then the next.
-- A running total compares what you've spent with what those items were planned to cost.
--
-- Buying needs a click (the game only allows a purchase from one), so it's one click per item,
-- or per auction for items sold as separate auctions.

-- C_AuctionHouse, looked up when used (not when this file loads)
local AH = setmetatable({}, { __index = function(_, k) return C_AuctionHouse and C_AuctionHouse[k] end })
local W, ROW_H, ROWS = 300, 18, 14
local GREY, GREEN, RED, GOLD = "|cff8a8a8a", "|cff40ff40", "|cffff5050", "|cffffd100"
local ICON_DONE = "Interface\\RaidFrame\\ReadyCheck-Ready"

local panel
-- what's going on with the current item:
--   phase: idle | search | price (waiting for the AH's quote) | ready | buying | start (the
--   quote needs a click first) | none (not on sale) | done (list finished)
local state = { phase = "idle" }

local function Num(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end
local function Print(msg) if ns.Print then ns.Print(msg) end end

local function List()
  return type(CrateCostCharDB) == "table" and CrateCostCharDB.buyList or nil
end

-- A new list to buy (Cart.lua, when a shopping list is made): { { id, name, qty, planned }, ... }
function ns.SetBuyList(name, items)
  if type(CrateCostCharDB) ~= "table" then CrateCostCharDB = {} end
  local l = { name = name, items = {} }
  for _, it in ipairs(items) do
    if it.id and (it.qty or 0) > 0 then
      l.items[#l.items + 1] = { id = it.id, name = it.name, qty = it.qty, planned = it.planned, bought = 0, spent = 0 }
    end
  end
  CrateCostCharDB.buyList = l
  state = { phase = "idle" }
  -- at the AH already: open the panel on the new list
  if ns.Depth and ns.Depth.atAH then
    C_Timer.After(0.2, ns.ShowBuyPanel)
  elseif panel and panel:IsShown() then
    ns.RefreshBuyPanel()
  end
end

local function Current()
  local l = List()
  if not l then return nil end
  for i, it in ipairs(l.items) do
    if not it.skipped and it.bought < it.qty then return it, i end
  end
end

-- What's still planned for an item: its planned cost for the part not bought yet.
local function PlannedLeft(it)
  if not it.planned then return nil end
  return it.planned * (it.qty - it.bought) / it.qty
end

local function Diff(actual, planned)
  if not (actual and planned) then return "" end
  local d = actual - planned
  if math.abs(d) < 1 then return GREY .. "as planned|r" end
  if d > 0 then return RED .. "+" .. ns.Money(d) .. " over|r" end
  return GREEN .. ns.Money(-d) .. " under|r"
end

------------------------------------------------------------------------------------------------
-- Searching, quoting and buying

local SORTS
local function Sorts()
  if not SORTS then
    SORTS = { { sortOrder = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0,
      reverseSort = false } }
  end
  return SORTS
end

local function Ready()
  return not (AH and AH.IsThrottledMessageSystemReady) or AH.IsThrottledMessageSystemReady()
end

local Refresh

local function Search()
  local it = Current()
  if not it then
    state = { phase = "done" }
    Refresh()
    return
  end
  if not AH.SendSearchQuery then return end
  if ns.Depth and ns.Depth.state == "running" then
    state = { phase = "idle", note = "Waiting for the AH scan to finish." }
    Refresh()
    return
  end
  state = { phase = "search", id = it.id }
  Refresh()
  if not Ready() then
    state.waiting = true   -- sent when the AH is ready (AUCTION_HOUSE_THROTTLED_SYSTEM_READY)
    return
  end
  pcall(AH.SendSearchQuery, AH.MakeItemKey(it.id), Sorts(), true)
end

-- Commodity listings for what's left of the item: what the cheapest of them would cost.
local function OnCommodity(id)
  local it = Current()
  if not (it and state.id == id and (state.phase == "search" or state.phase == "none")) then return end
  local need = it.qty - it.bought
  local total, left = 0, need
  for i = 1, (AH.GetNumCommoditySearchResults(id) or 0) do
    local r = AH.GetCommoditySearchResultInfo(id, i)
    if r and r.unitPrice and r.quantity then
      local qty = r.quantity - (r.containsOwnerItem and (r.numOwnerItems or r.quantity) or 0)
      local take = math.min(qty, left)
      if take > 0 then total, left = total + take * r.unitPrice, left - take end
      if left == 0 then break end
    end
  end
  if left == need then
    state = { phase = "none", id = id, kind = "commodity" }
    Refresh()
    return
  end
  state = { phase = "price", id = id, kind = "commodity", need = need - left, estimate = total, short = left > 0 }
  -- ask the AH for the exact price (the purchase itself still needs your click)
  local ok = AH.StartCommoditiesPurchase and pcall(AH.StartCommoditiesPurchase, id, state.need)
  if not ok then state.phase = "start" end   -- the quote needs a click first
  Refresh()
end

-- Separate auctions: the cheapest one with a buyout that isn't yours.
local function OnItem(itemKey)
  local it = Current()
  if not (it and itemKey and state.id == itemKey.itemID and state.phase == "search") then return end
  local best
  for i = 1, (AH.GetNumItemSearchResults(itemKey) or 0) do
    local r = AH.GetItemSearchResultInfo(itemKey, i)
    if r and r.buyoutAmount and r.buyoutAmount > 0 and not r.containsOwnerItem then
      local per = r.buyoutAmount / math.max(1, r.quantity or 1)
      if not best or per < best.per then
        best = { auctionID = r.auctionID, buyout = r.buyoutAmount, qty = r.quantity or 1, per = per }
      end
    end
  end
  if not best then
    state = { phase = "none", id = itemKey.itemID, kind = "item" }
  else
    state = { phase = "ready", id = itemKey.itemID, kind = "item", auction = best, quote = best.buyout,
      need = math.min(best.qty, it.qty - it.bought) }
  end
  Refresh()
end

local function Bought(amount, paid)
  local it = Current()
  local l = List()
  if not (it and l) then return end
  it.bought = math.min(it.qty, it.bought + amount)
  it.spent = it.spent + (paid or 0)
  Search()
end

-- The Buy button (a click: the game only buys from one).
local function BuyClick()
  local it = Current()
  if not it then return end
  if state.phase == "start" and state.kind == "commodity" then
    if pcall(AH.StartCommoditiesPurchase, state.id, state.need) then state.phase = "price" end
    Refresh()
  elseif state.phase == "ready" and state.kind == "commodity" then
    if GetMoney and state.quote and GetMoney() < state.quote then
      Print("not enough gold for that.")
      return
    end
    state.phase = "buying"
    pcall(AH.ConfirmCommoditiesPurchase, state.id, state.need)
    Refresh()
  elseif state.phase == "ready" and state.kind == "item" and state.auction then
    if GetMoney and GetMoney() < state.auction.buyout then
      Print("not enough gold for that.")
      return
    end
    state.phase = "buying"
    pcall(AH.PlaceBid, state.auction.auctionID, state.auction.buyout)
    Refresh()
  elseif state.phase == "none" or state.phase == "idle" then
    Search()
  end
end

local function Skip()
  local it = Current()
  if it then it.skipped = true end
  Search()
end

------------------------------------------------------------------------------------------------
-- The panel

Refresh = function()
  if not (panel and panel:IsShown()) then return end
  local l = List()
  local it, idx = Current()
  if not l or #l.items == 0 then
    panel.title:SetText("Shopping")
    panel.summary:SetText(GREY .. "No shopping list yet: make one from a plan (Create shopping list).|r")
    panel.item:SetText("") panel.itemInfo:SetText("") panel.icon:Hide()
    panel.buy:Disable() panel.buy:SetText("Buy") panel.skip:Disable()
    for _, r in ipairs(panel.rows) do r:Hide() end
    return
  end
  panel.title:SetText(l.name or "Shopping")
  -- summary: planned, spent, and how the bought part compares with its plan
  local planned, spent, plannedDone, doneN, plannedLeft = 0, 0, 0, 0, 0
  for _, x in ipairs(l.items) do
    planned = planned + (x.planned or 0)
    spent = spent + x.spent
    if x.qty > 0 and x.bought > 0 and x.planned then plannedDone = plannedDone + x.planned * x.bought / x.qty end
    if x.bought >= x.qty or x.skipped then doneN = doneN + 1 end
    if not x.skipped then plannedLeft = plannedLeft + (PlannedLeft(x) or 0) end
  end
  panel.progress:SetText(GOLD .. doneN .. " / " .. #l.items .. "|r")
  panel.summary:SetText(string.format("Planned  %s\nSpent    %s   %s\nLeft     %s",
    ns.Money(planned), ns.Money(spent), spent > 0 and Diff(spent, plannedDone) or "", ns.Money(plannedLeft)))
  -- the current item
  if it then
    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(it.id)
    panel.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    panel.icon:Show()
    panel.item:SetText((it.name or "?") .. GREY .. "  x" .. (it.qty - it.bought) .. "|r")
    local pl = PlannedLeft(it)
    local lines = { "Planned " .. (pl and ns.Money(pl) or "?") }
    local ph = state.phase
    if ph == "search" then lines[#lines + 1] = GREY .. "Searching the AH...|r"
    elseif ph == "price" then lines[#lines + 1] = "Now ~" .. ns.Money(state.estimate or 0) .. "  " .. Diff(state.estimate, pl)
      lines[#lines + 1] = GREY .. "Getting the exact price...|r"
    elseif ph == "start" then lines[#lines + 1] = "Now ~" .. ns.Money(state.estimate or 0) .. "  " .. Diff(state.estimate, pl)
    elseif ph == "ready" and state.kind == "commodity" then
      lines[#lines + 1] = "Now " .. ns.Money(state.quote or 0) .. "  " .. Diff(state.quote, pl)
      if state.short then lines[#lines + 1] = RED .. "Only " .. state.need .. " on the AH.|r" end
    elseif ph == "ready" and state.kind == "item" then
      local per = state.auction and state.auction.per or 0
      local plPer = pl and (pl / math.max(1, it.qty - it.bought)) or nil
      lines[#lines + 1] = "This auction: " .. state.need .. " for " .. ns.Money(state.quote or 0)
      lines[#lines + 1] = "Each " .. ns.Money(per) .. "  " .. Diff(per, plPer)
    elseif ph == "buying" then lines[#lines + 1] = GREY .. "Buying...|r"
    elseif ph == "none" then lines[#lines + 1] = RED .. "None on the AH.|r"
    elseif state.note then lines[#lines + 1] = GREY .. state.note .. "|r" end
    panel.itemInfo:SetText(table.concat(lines, "\n"))
  else
    panel.icon:Hide()
    panel.item:SetText(GREEN .. "All bought.|r")
    panel.itemInfo:SetText("")
  end
  -- the button
  local ph = state.phase
  if not it then
    panel.buy:SetText("Done") panel.buy:Disable()
  elseif ph == "ready" then
    panel.buy:SetText("Buy " .. (state.need or "") .. "  " .. ns.Money(state.quote or 0)) panel.buy:Enable()
  elseif ph == "start" then
    panel.buy:SetText("Get price") panel.buy:Enable()
  elseif ph == "none" or ph == "idle" then
    panel.buy:SetText("Search again") panel.buy:Enable()
  else
    panel.buy:SetText("...") panel.buy:Disable()
  end
  panel.skip:SetEnabled(it ~= nil)
  -- the list: done, current, to come
  local n = #l.items
  panel.offset = math.max(0, math.min(panel.offset, n - ROWS))
  if not panel.scrolled and idx then panel.offset = math.max(0, math.min(idx - 3, n - ROWS)) end
  for i, r in ipairs(panel.rows) do
    local x = l.items[panel.offset + i]
    if not x then
      r:Hide()
    else
      local done = x.bought >= x.qty
      r.check:SetShown(done)
      local name = (x.name or "?") .. " x" .. x.qty
      if x == it then
        r.text:SetText(GOLD .. name .. "|r")
        r.bg:SetColorTexture(1, 0.82, 0, 0.08)
      elseif done then
        r.text:SetText(GREY .. name .. "|r")
        r.bg:SetColorTexture(0.1, 0.5, 0.15, 0.08)
      elseif x.skipped then
        r.text:SetText(GREY .. name .. " (skipped)|r")
        r.bg:SetColorTexture(0, 0, 0, 0)
      else
        r.text:SetText("|cffdddddd" .. name .. "|r")
        r.bg:SetColorTexture(0, 0, 0, 0)
      end
      r.cost:SetText(done and (x.planned and Diff(x.spent, x.planned) or ns.Money(x.spent))
        or (x.planned and (GREY .. ns.Money(x.planned) .. "|r") or ""))
      r:Show()
    end
  end
end

local function Build()
  local p = CreateFrame("Frame", "CrateCostBuyPanel", UIParent, "BackdropTemplate")
  panel = p
  p:SetSize(W, 470)
  p:SetFrameStrata("HIGH")
  p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  p:SetBackdropColor(0.03, 0.03, 0.04, 0.94)
  p:SetBackdropBorderColor(0.4, 0.33, 0.18, 1)
  p:EnableMouse(true)
  p.offset = 0
  p.title = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  p.title:SetPoint("TOPLEFT", 10, -10)
  p.title:SetPoint("RIGHT", -60, 0)
  p.title:SetJustifyH("LEFT")
  p.title:SetWordWrap(false)
  p.progress = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  p.progress:SetPoint("TOPRIGHT", -28, -11)
  local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
  close:SetSize(22, 22)
  close:SetPoint("TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function() p:Hide() end)
  -- summary
  p.summary = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  p.summary:SetPoint("TOPLEFT", 12, -34)
  p.summary:SetPoint("RIGHT", -12, 0)
  p.summary:SetJustifyH("LEFT")
  p.summary:SetSpacing(3)
  local rule = p:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", 8, -88)
  rule:SetPoint("TOPRIGHT", -8, -88)
  rule:SetColorTexture(1, 0.82, 0, 0.25)
  -- the current item
  p.icon = p:CreateTexture(nil, "ARTWORK")
  p.icon:SetSize(30, 30)
  p.icon:SetPoint("TOPLEFT", 12, -98)
  p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  p.item = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  p.item:SetPoint("TOPLEFT", p.icon, "TOPRIGHT", 8, 0)
  p.item:SetPoint("RIGHT", -12, 0)
  p.item:SetJustifyH("LEFT")
  p.item:SetWordWrap(false)
  p.itemInfo = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  p.itemInfo:SetPoint("TOPLEFT", p.item, "BOTTOMLEFT", 0, -4)
  p.itemInfo:SetPoint("RIGHT", -12, 0)
  p.itemInfo:SetJustifyH("LEFT")
  p.itemInfo:SetSpacing(2)
  -- Buy, Skip
  p.buy = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  p.buy:SetSize(W - 90, 28)
  p.buy:SetPoint("TOPLEFT", 10, -170)
  p.buy:SetScript("OnClick", BuyClick)
  p.skip = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  p.skip:SetSize(62, 28)
  p.skip:SetPoint("LEFT", p.buy, "RIGHT", 6, 0)
  p.skip:SetText("Skip")
  p.skip:SetScript("OnClick", Skip)
  ns.UI.Tip(p.skip, "Skip", "Move on without buying this one.")
  -- the list
  local lt = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  lt:SetPoint("TOPLEFT", 12, -208)
  lt:SetText("The list")
  p.rows = {}
  for i = 1, ROWS do
    local r = CreateFrame("Frame", nil, p)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 6, -224 - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", p, "RIGHT", -6, 0)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.check = r:CreateTexture(nil, "ARTWORK")
    r.check:SetSize(12, 12)
    r.check:SetPoint("LEFT", 4, 0)
    r.check:SetTexture(ICON_DONE)
    r.cost = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.cost:SetPoint("RIGHT", -4, 0)
    r.cost:SetJustifyH("RIGHT")
    r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 20, 0)
    r.text:SetPoint("RIGHT", r.cost, "LEFT", -6, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(_, d) p.offset = p.offset - d * 3 p.scrolled = true Refresh() end)
    p.rows[i] = r
  end
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, d) p.offset = p.offset - d * 3 p.scrolled = true Refresh() end)
  local clear = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  clear:SetSize(110, 20)
  clear:SetPoint("BOTTOMLEFT", 10, 8)
  clear:SetText("Forget list")
  clear:SetScript("OnClick", function()
    if type(CrateCostCharDB) == "table" then CrateCostCharDB.buyList = nil end
    state = { phase = "idle" }
    Refresh()
  end)
  ns.UI.Tip(clear, "Forget list", "Drop this shopping list from the panel. (Auctionator's list stays.)")
  p:Hide()
end

local function Dock()
  local ahf = _G.AuctionHouseFrame
  panel:ClearAllPoints()
  if ahf and ahf:IsShown() then
    panel:SetPoint("TOPLEFT", ahf, "TOPRIGHT", 4, 0)
  else
    panel:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
  end
end

-- Opens the panel (at the auction house); `fresh` starts the first item's search again.
function ns.RefreshBuyPanel(fresh)
  if not panel then Build() end
  if fresh and panel:IsShown() then Search() return end
  Refresh()
end

function ns.ShowBuyPanel()
  if not panel then Build() end
  Dock()
  panel.scrolled = false
  panel:Show()
  local l = List()
  if l and Current() and ns.Depth and ns.Depth.atAH then Search() else Refresh() end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
  "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED", "ITEM_SEARCH_RESULTS_UPDATED",
  "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
  "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR" }) do
  if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e) then
    pcall(ev.RegisterEvent, ev, e)
  end
end
ev:SetScript("OnEvent", function(_, e, a, b)
  if e == "AUCTION_HOUSE_SHOW" then
    -- a list still to buy: the panel opens beside the AH
    local l = List()
    if l and Current() then C_Timer.After(0.5, ns.ShowBuyPanel) end
    return
  elseif e == "AUCTION_HOUSE_CLOSED" then
    if panel then panel:Hide() end
    state = { phase = "idle" }
    return
  end
  if not (panel and panel:IsShown()) then return end
  if e == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    if state.phase == "search" and state.waiting then
      state.waiting = nil
      pcall(AH.SendSearchQuery, AH.MakeItemKey(state.id), Sorts(), true)
    end
  elseif e == "COMMODITY_SEARCH_RESULTS_UPDATED" or e == "COMMODITY_SEARCH_RESULTS_ADDED" then
    OnCommodity(a)
  elseif e == "ITEM_SEARCH_RESULTS_UPDATED" then
    OnItem(a)
  elseif e == "COMMODITY_PRICE_UPDATED" then
    -- the AH's quote: a, b = unit price, total
    if state.phase == "price" then
      state.quote, state.unit = b, a
      state.phase = "ready"
      Refresh()
    end
  elseif e == "COMMODITY_PRICE_UNAVAILABLE" then
    if state.phase == "price" then state = { phase = "none", id = state.id } Refresh() end
  elseif e == "COMMODITY_PURCHASE_SUCCEEDED" then
    if state.phase == "buying" then Bought(state.need or 0, state.quote) end
  elseif e == "COMMODITY_PURCHASE_FAILED" or e == "AUCTION_HOUSE_SHOW_ERROR" then
    if state.phase == "buying" or state.phase == "price" then
      Print("the purchase didn't go through; searching again.")
      Search()
    end
  elseif e == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
    if state.phase == "buying" and state.kind == "item" and state.auction and a == state.auction.auctionID then
      Bought(state.need or 0, state.auction.buyout)
    end
  end
end)
