---------------------------------------------------------
--  ShoppingDock - the dock (embeddable core)
--  Author: Dranged
---------------------------------------------------------
-- A panel docked to the auction house's right edge that works through an Auctionator shopping
-- list one item at a time. For the current item it searches the AH, shows what buying the rest
-- costs now against what the list expected, and Buy buys it: a commodity in one purchase for
-- the whole amount, an auction one stack at a time. Then the next item.
--
-- Lists are read from Auctionator's saved lists, never changed. What an item was expected to
-- cost comes from the plan the list's maker registered (ShoppingDock.SetListPlan), else from
-- Auctionator's price when the dock first saw the list ("Listed at").
--
-- This file runs on its own: other addons can copy it in. Every copy loads, but only one runs.
-- The newest MINOR takes the global ShoppingDock table (the same MINOR: whichever loaded first),
-- and every handler below checks Active() first, so copies never fight over the dock.
-- Progress and plans live in the SavedVariable ShoppingDockDB, which each host declares.
--
-- Buying needs a click (the game only allows a purchase from one). A commodity is two clicks:
-- Buy now asks the AH for the exact price (StartCommoditiesPurchase), then Confirm buys at it.

local MINOR = 5

local _, NS = ...
NS = type(NS) == "table" and NS or {}

local old = _G.ShoppingDock
if type(old) == "table" and (tonumber(old.MINOR) or 0) >= MINOR then return end

local SD = { MINOR = MINOR, OpenSettings = old and old.OpenSettings }
_G.ShoppingDock = SD
if old and type(old._Retire) == "function" then pcall(old._Retire) end

local function Active() return _G.ShoppingDock == SD end

local CALLER = "ShoppingDock"
-- C_AuctionHouse, looked up when used (not when this file loads)
local AH = setmetatable({}, { __index = function(_, k) return C_AuctionHouse and C_AuctionHouse[k] end })
local W, ROW_H, MAX_ROWS, LIST_TOP, FOOT = 380, 18, 40, 268, 40
local GREY, GREEN, RED, GOLD = "|cff8a8a8a", "|cff40ff40", "|cffff5050", "|cffffd100"
local ICON_DONE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local BUY_TIMEOUT = 10 -- seconds before a purchase with no answer counts as failed
local SCAN_TIMEOUT = 5 -- seconds a list rescan waits on one item before moving on

local panel, tab
local atAH = false
-- the current item: phase = idle | find (looking up an unknown item's ID) | search | start
-- (a commodity: Buy now asks for the quote) | price (waiting for the quote) | ready | buying | none
local state = { phase = "idle" }

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffffd100ShoppingDock|r: " .. tostring(msg))
end

-- errors inside handlers: the first few go to chat, the rest are dropped
local errors = 0
local function Log(where, err)
  errors = errors + 1
  if errors <= 3 then Print("|cffff5050error in " .. where .. ":|r " .. tostring(err)) end
end

local function Money(copper)
  copper = math.floor((copper or 0) + 0.5)
  if GetMoneyString then return GetMoneyString(copper, true) end
  return tostring(copper) .. "c"
end

local function Tip(frame, title, text)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h)
  b:SetText(text)
  if onClick then b:SetScript("OnClick", onClick) end
  -- the host's house kit skins it, when there is one
  if NS.ThemeRegisterButton then pcall(NS.ThemeRegisterButton, b) end
  return b
end

------------------------------------------------------------------------------------------------
-- Saved data: ShoppingDockDB = { enabled, active = listName, lists = { [listName] = L }, ... }
--   L = { items = { [key] = rec }, plan = { [itemID] = { qty, planned, name } }, forgotten,
--         focus = key of the item picked from the plan rows, source = the addon that made it }
--   rec = { id, bought, spent, base (price each when first seen), want (amount set here), skipped }
-- Only touched from PLAYER_LOGIN on: SavedVariables load after this file runs.

function SD.DB()
  local db = _G.ShoppingDockDB
  if type(db) ~= "table" then
    db = {}
    _G.ShoppingDockDB = db
  end
  if type(db.lists) ~= "table" then db.lists = {} end
  return db
end
local Store = SD.DB

local function Track(name, fresh)
  local s = Store()
  if fresh or not s.lists[name] then s.lists[name] = { items = {}, plan = {} } end
  local L = s.lists[name]
  L.items, L.plan = L.items or {}, L.plan or {}
  return L
end

function SD.IsEnabled() return Store().enabled ~= false end

------------------------------------------------------------------------------------------------
-- Auctionator's lists (read only)

local function RawLists()
  local t = AUCTIONATOR_SHOPPING_LISTS
  local out = {}
  if type(t) ~= "table" then return out end
  for _, l in ipairs(t) do
    if type(l) == "table" and type(l.name) == "string" and not l.isTemporary and type(l.items) == "table" then
      out[#out + 1] = l
    end
  end
  return out
end

local function FindRaw(name)
  for _, l in ipairs(RawLists()) do
    if l.name == name then return l end
  end
end

-- '"Linen Cloth";;;;;;;;;;;;;20' -> "Linen Cloth", 20 (the amount is nil when the list has none)
local function ParseTerm(str)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if api and api.ConvertFromSearchString then
    local ok, term = pcall(api.ConvertFromSearchString, CALLER, str)
    if ok and type(term) == "table" and type(term.searchString) == "string" then
      local name = term.searchString:gsub('^"(.*)"$', "%1")
      return name, tonumber(term.quantity)
    end
  end
  local name = str:match('^"([^"]+)"') or str:match("^([^;]+)")
  return name, nil
end

-- AuctionatorSync's name book, when it's installed: [itemID] = { name, quality, reqLevel }.
-- Read only. Unknown names fall back to the AH's browse-by-name search.
local function SyncNames()
  local db = _G.AuctionatorSyncDB
  return type(db) == "table" and type(db.names) == "table" and db.names or nil
end

-- item name (lower case) -> item ID: from plans, AuctionatorSync's name book and the item cache
local nameIndex
local function IndexName(name, id)
  if nameIndex and name and id then nameIndex[name:lower()] = id end
end

local function IdForName(name)
  if not name or name == "" then return nil end
  local lower = name:lower()
  if not nameIndex then
    nameIndex = {}
    for id, e in pairs(SyncNames() or {}) do
      local n = type(e) == "table" and (e[1] or e.name)
      if type(n) == "string" and tonumber(id) then nameIndex[n:lower()] = tonumber(id) end
    end
    for _, L in pairs(Store().lists) do
      for id, p in pairs(L.plan or {}) do
        if type(p) == "table" and type(p.name) == "string" then nameIndex[p.name:lower()] = id end
      end
    end
  end
  if nameIndex[lower] then return nameIndex[lower] end
  local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if info then
    local ok, id = pcall(info, name)
    if ok and type(id) == "number" then
      nameIndex[lower] = id
      return id
    end
  end
end

local function ItemName(id)
  local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
  if not n and GetItemInfo then n = GetItemInfo(id) end
  if not n then
    local book = SyncNames()
    local e = book and book[id]
    n = type(e) == "table" and e[1] or nil
  end
  return n
end

local function AuctionPrice(id)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (id and api and api.GetAuctionPriceByItemID) then return nil end
  local ok, p = pcall(api.GetAuctionPriceByItemID, CALLER, id)
  return ok and tonumber(p) or nil
end

-- The list as the dock works through it: { { key, name, qty, rec, plan }, ... } in list order.
-- Fills in what it can on the way: item IDs, and the price each when the list was first seen.
local function Items(name)
  local raw = name and FindRaw(name)
  if not raw then return nil end
  local L = Track(name)
  local out, byKey = {}, {}
  for _, str in ipairs(raw.items) do
    if type(str) == "string" then
      local itemName, qty = ParseTerm(str)
      if itemName and itemName ~= "" then
        local key = itemName:lower()
        local x = byKey[key]
        if x then
          if qty then x.qty = (x.qty or 0) + qty end -- the same item twice: one row, both amounts
        else
          local rec = L.items[key]
          if not rec then
            rec = { bought = 0, spent = 0 }
            L.items[key] = rec
          end
          rec.id = rec.id or IdForName(itemName)
          x = { key = key, name = itemName, qty = qty, rec = rec }
          byKey[key] = x
          out[#out + 1] = x
        end
      end
    end
  end
  for _, x in ipairs(out) do
    local rec = x.rec
    if rec.id then
      x.plan = L.plan[rec.id]
      if not rec.base then rec.base = AuctionPrice(rec.id) end
    end
  end
  return out, L
end

local function Want(x) return x.rec.want or x.qty or 1 end
local function IsDone(x) return x.rec.skipped or x.rec.bought >= Want(x) end

-- What the list expected one of this item to cost: the maker's plan, else the price when listed.
local function Each(x)
  local p = x.plan
  if p and p.planned and (p.qty or 0) > 0 then return p.planned / p.qty end
  return x.rec.base
end

local function PlannedFor(x, n)
  local each = Each(x)
  return each and each * n or nil
end

local function Diff(actual, planned)
  if not (actual and planned) then return "" end
  local d = actual - planned
  if math.abs(d) < 1 then return GREY .. "as expected|r" end
  if d > 0 then return RED .. "+" .. Money(d) .. " over|r" end
  return GREEN .. Money(-d) .. " under|r"
end

local function ActiveName()
  local s = Store()
  if s.active and FindRaw(s.active) then return s.active end
  s.active = nil
  return nil
end

-- The item the dock is on: the one picked from the plan rows (L.focus) while it has some left,
-- then the next unfinished one after it, wrapping round. Nothing picked: the first unfinished.
local function Current()
  local items, L = Items(ActiveName())
  if not items then return nil end
  local start = 1
  if L and L.focus then
    for i, x in ipairs(items) do
      if x.key == L.focus then start = i break end
    end
  end
  for k = 0, #items - 1 do
    local i = (start - 1 + k) % #items + 1
    if not IsDone(items[i]) then return items[i], i, items end
  end
  return nil, nil, items
end

local function Remaining(x) return Want(x) - x.rec.bought end

local function FindItem(key)
  for _, x in ipairs(Items(ActiveName()) or {}) do
    if x.key == key then return x end
  end
end

-- what buying the rest of x costs now: total copper and how many the AH could cover.
-- nowFor is the amount it was for; once that changes the price is stale.
local function NoteNow(x, total, covered)
  x.rec.now = covered > 0 and total or nil
  x.rec.nowN = covered
  x.rec.nowFor = Remaining(x)
end

local function FreshNow(x) return x.rec.nowFor ~= nil and x.rec.nowFor == Remaining(x) end

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
  return not AH.IsThrottledMessageSystemReady or AH.IsThrottledMessageSystemReady()
end

-- a quote we asked for and won't use: let the AH drop it
local function CancelQuote()
  if (state.phase == "price" or state.phase == "ready") and state.kind == "commodity" and AH.CancelCommoditiesPurchase then
    pcall(AH.CancelCommoditiesPurchase)
  end
end

local Refresh

local function SendQuery()
  if state.phase == "find" then
    if AH.SendBrowseQuery then
      pcall(AH.SendBrowseQuery, { searchString = state.name, sorts = Sorts(), filters = {}, itemClassFilters = {} })
    end
  elseif state.phase == "search" then
    if AH.SendSearchQuery and AH.MakeItemKey then
      pcall(function() AH.SendSearchQuery(AH.MakeItemKey(state.id), Sorts(), true) end)
    end
  end
end

local function Search()
  CancelQuote()
  local x = Current()
  if not x then
    state = { phase = "idle" }
    Refresh()
    return
  end
  if not (atAH and AH.SendSearchQuery) then
    state = { phase = "idle" }
    Refresh()
    return
  end
  if x.rec.id then
    state = { phase = "search", id = x.rec.id, key = x.key }
  else
    -- a name we can't turn into an item yet: ask the AH for it by name
    state = { phase = "find", name = x.name, key = x.key }
  end
  Refresh()
  if not Ready() then
    state.waiting = true -- sent on AUCTION_HOUSE_THROTTLED_SYSTEM_READY
    return
  end
  SendQuery()
end

local function OnBrowse()
  if state.phase ~= "find" then return end
  local x = Current()
  if not (x and x.key == state.key) then return end
  local results = AH.GetBrowseResults and AH.GetBrowseResults() or {}
  for _, r in ipairs(results) do
    local id = r.itemKey and r.itemKey.itemID
    local keyInfo = id and AH.GetItemKeyInfo and AH.GetItemKeyInfo(r.itemKey)
    local n = (keyInfo and keyInfo.itemName) or (id and ItemName(id))
    if n and n:lower() == x.key then
      x.rec.id = id
      IndexName(n, id)
      Search()
      return
    end
  end
  NoteNow(x, 0, 0)
  state = { phase = "none", key = x.key }
  Refresh()
end

-- What buying `need` costs from the commodity listings now (cheapest first, never your own):
-- total copper, and how many of `need` the AH has.
local function CommodityCover(id, need)
  local total, left = 0, need
  for i = 1, (AH.GetNumCommoditySearchResults(id) or 0) do
    local r = AH.GetCommoditySearchResultInfo(id, i)
    if r and r.unitPrice and r.quantity then
      local qty = r.quantity - (r.containsOwnerItem and (r.numOwnerItems or r.quantity) or 0)
      local take = math.min(qty, left)
      if take > 0 then total, left = total + take * r.unitPrice, left - take end
      if left <= 0 then break end
    end
  end
  return total, need - left
end

-- The same for separate auctions, whole stacks cheapest each first: total, how many it covers.
local function ItemCover(itemKey, need)
  local stacks = {}
  for i = 1, (AH.GetNumItemSearchResults(itemKey) or 0) do
    local r = AH.GetItemSearchResultInfo(itemKey, i)
    if r and r.buyoutAmount and r.buyoutAmount > 0 and not r.containsOwnerItem then
      local qty = math.max(1, r.quantity or 1)
      stacks[#stacks + 1] = { buyout = r.buyoutAmount, qty = qty, per = r.buyoutAmount / qty }
    end
  end
  table.sort(stacks, function(a, b) return a.per < b.per end)
  local total, got = 0, 0
  for _, s in ipairs(stacks) do
    if got >= need then break end
    total, got = total + s.buyout, got + s.qty
  end
  return total, math.min(got, need)
end

-- Commodity listings for what's left of the item: what the cheapest of them would cost.
-- The exact quote waits for the Buy now click (StartCommoditiesPurchase wants one).
local function OnCommodity(id)
  local x = Current()
  if not (x and state.id == id and (state.phase == "search" or state.phase == "none")) then return end
  local need = Remaining(x)
  local total, covered = CommodityCover(id, need)
  NoteNow(x, total, covered)
  if covered == 0 then
    state = { phase = "none", id = id, key = x.key, kind = "commodity" }
  else
    state = { phase = "start", id = id, key = x.key, kind = "commodity", need = covered, estimate = total,
      short = covered < need }
  end
  Refresh()
end

-- Separate auctions. Buying one buys its whole stack, so: the cheapest each among stacks that
-- don't overshoot what's left, else the cheapest stack outright. Never your own.
local function OnItem(itemKey)
  local x = Current()
  if not (x and type(itemKey) == "table" and state.id == itemKey.itemID and state.phase == "search") then return end
  local need = Remaining(x)
  NoteNow(x, ItemCover(itemKey, need))
  local fit, any
  for i = 1, (AH.GetNumItemSearchResults(itemKey) or 0) do
    local r = AH.GetItemSearchResultInfo(itemKey, i)
    if r and r.buyoutAmount and r.buyoutAmount > 0 and not r.containsOwnerItem then
      local qty = math.max(1, r.quantity or 1)
      local a = { auctionID = r.auctionID, buyout = r.buyoutAmount, qty = qty, per = r.buyoutAmount / qty }
      if qty <= need and (not fit or a.per < fit.per) then fit = a end
      if not any or a.buyout < any.buyout then any = a end
    end
  end
  local best = fit or any
  if not best then
    state = { phase = "none", id = itemKey.itemID, key = x.key, kind = "item" }
  else
    state = { phase = "ready", id = itemKey.itemID, key = x.key, kind = "item", auction = best, quote = best.buyout,
      need = best.qty }
  end
  Refresh()
end

local function Bought(amount, paid)
  local x = Current()
  if not x then return end
  x.rec.bought = x.rec.bought + amount
  x.rec.spent = x.rec.spent + (paid or 0)
  state = { phase = "idle" }
  Search()
end

-- a purchase that never answers: search again instead of sitting on "Buying..."
local function WatchPurchase()
  local st = state
  C_Timer.After(BUY_TIMEOUT, function()
    if Active() and state == st and st.phase == "buying" then
      Print("no answer from the auction house; searching again.")
      Search()
    end
  end)
end

-- The Buy button (a click: the game only buys from one).
local function BuyClick()
  if not Active() then return end
  local x = Current()
  if not x then return end
  local ph = state.phase
  if (ph == "start" or ph == "price") and state.kind == "commodity" then
    -- set "price" first: the quote can come back inside the call
    state.phase = "price"
    local ok = AH.StartCommoditiesPurchase and pcall(AH.StartCommoditiesPurchase, state.id, state.need)
    if not ok and state.phase == "price" then state.phase = "start" end
    Refresh()
  elseif ph == "ready" and state.kind == "commodity" then
    if GetMoney and state.quote and GetMoney() < state.quote then
      Print("not enough gold for that.")
      return
    end
    state.phase = "buying"
    pcall(AH.ConfirmCommoditiesPurchase, state.id, state.need)
    WatchPurchase()
    Refresh()
  elseif ph == "ready" and state.kind == "item" and state.auction then
    if GetMoney and GetMoney() < state.auction.buyout then
      Print("not enough gold for that.")
      return
    end
    state.phase = "buying"
    pcall(AH.PlaceBid, state.auction.auctionID, state.auction.buyout)
    WatchPurchase()
    Refresh()
  elseif ph == "none" or ph == "idle" or ph == "search" or ph == "find" then
    Search()
  end
end

local function Skip()
  if not Active() then return end
  local x = Current()
  if x then x.rec.skipped = true end
  Search()
end

-- Put the dock on another list.
local function SelectList(name)
  if not (Active() and type(name) == "string" and FindRaw(name)) then return end
  Store().active = name
  Track(name).forgotten = nil
  if panel then
    panel.scrolled = false
    panel.offset = 0
  end
  Search()
end

-- A plan row was clicked: work on that item next. A skipped item comes back; a bought one
-- has nothing left to work on. Not while a purchase is waiting for its answer.
local function FocusItem(key)
  local name = ActiveName()
  if not (Active() and name and key) or state.phase == "buying" then return end
  local x = FindItem(key)
  if not x then return end
  x.rec.skipped = nil
  if IsDone(x) then return end
  Track(name).focus = key
  if panel then panel.scrolled = true end
  Search()
end

------------------------------------------------------------------------------------------------
-- Rescanning the whole list: every item not yet bought is searched in turn, and what buying the
-- rest of it would cost now is kept on its row (rec.now). The current item's own search keeps
-- it up to date too. rec.nowFor is the amount that price was for: once the amount changes, the
-- price is stale and isn't shown.

local function ScanSend()
  local S = state.scan
  if S.mode == "find" then
    if AH.SendBrowseQuery then
      pcall(AH.SendBrowseQuery, { searchString = S.name, sorts = Sorts(), filters = {}, itemClassFilters = {} })
    end
  elseif AH.SendSearchQuery and AH.MakeItemKey then
    pcall(function() AH.SendSearchQuery(AH.MakeItemKey(S.id), Sorts(), true) end)
  end
end

local function ScanNext()
  local S = state.scan
  if state.phase ~= "scan" or not S then return end
  while true do
    S.i = S.i + 1
    local key = S.keys[S.i]
    if not key then
      -- done: back to the current item
      state = { phase = "idle" }
      Search()
      return
    end
    local x = FindItem(key)
    if x and not IsDone(x) then
      S.key, S.name, S.id = key, x.name, x.rec.id
      S.mode = x.rec.id and "search" or "find"
      break
    end
  end
  -- an item the AH never answers for doesn't stop the scan
  local token = {}
  S.token = token
  C_Timer.After(SCAN_TIMEOUT, function()
    if Active() and state.scan == S and S.token == token then ScanNext() end
  end)
  if Ready() then ScanSend() else S.waiting = true end
  Refresh()
end

local function StartScan()
  if not (Active() and atAH and AH.SendSearchQuery) then return end
  CancelQuote()
  local keys = {}
  for _, x in ipairs(Items(ActiveName()) or {}) do
    if not IsDone(x) then keys[#keys + 1] = x.key end
  end
  if #keys == 0 then return end
  state = { phase = "scan", scan = { keys = keys, i = 0 } }
  ScanNext()
end

local function StopScan()
  if state.phase == "scan" then
    state = { phase = "idle" }
    Search()
  end
end

-- scan answers; each returns true when it used the event
local function ScanBrowse()
  local S = state.scan
  if not (S and S.mode == "find") then return false end
  local x = FindItem(S.key)
  if x then
    for _, r in ipairs(AH.GetBrowseResults and AH.GetBrowseResults() or {}) do
      local id = r.itemKey and r.itemKey.itemID
      local keyInfo = id and AH.GetItemKeyInfo and AH.GetItemKeyInfo(r.itemKey)
      local n = (keyInfo and keyInfo.itemName) or (id and ItemName(id))
      if n and n:lower() == x.key then
        x.rec.id = id
        IndexName(n, id)
        S.mode, S.id = "search", id
        if Ready() then ScanSend() else S.waiting = true end
        return true
      end
    end
    NoteNow(x, 0, 0)
  end
  ScanNext()
  return true
end

local function ScanCommodity(id)
  local S = state.scan
  if not (S and S.mode == "search" and S.id == id) then return false end
  local x = FindItem(S.key)
  if x then NoteNow(x, CommodityCover(id, Remaining(x))) end
  ScanNext()
  return true
end

local function ScanItem(itemKey)
  local S = state.scan
  if not (S and S.mode == "search" and type(itemKey) == "table" and S.id == itemKey.itemID) then return false end
  local x = FindItem(S.key)
  if x then NoteNow(x, ItemCover(itemKey, Remaining(x))) end
  ScanNext()
  return true
end

------------------------------------------------------------------------------------------------
-- The panel

Refresh = function()
  if not (panel and panel:IsShown()) then return end
  local name = ActiveName()
  local x, idx, items = Current()
  local count = #RawLists()
  if not items then
    panel.listName:SetText(GREY .. (count > 0 and "Click to pick a list" or "No shopping lists") .. "|r")
    panel.progress:SetText("")
    panel.summary:SetText(GREY .. "Works through any Auctionator shopping list. Make one in Auctionator's "
      .. "Shopping tab or from an addon (CraftRoute, CrateCost...). New lists open here by themselves.|r")
    panel.item:SetText("") panel.itemInfo:SetText("") panel.icon:Hide()
    panel.buy:Disable() panel.buy:SetText("Buy") panel.skip:Disable() panel.amount:Hide()
    panel.rescanItem:Disable() panel.rescanList:Disable() panel.rescanList:SetText("Rescan list")
    for _, r in ipairs(panel.rows) do r:Hide() end
    return
  end
  panel.listName:SetText(GOLD .. name .. "|r")
  -- summary: expected, spent (against what the bought part was expected to cost), left
  local expected, spent, expectedDone, doneN, left, anyPlan, unknown = 0, 0, 0, 0, 0, false, 0
  for _, it in ipairs(items) do
    local want = Want(it)
    if it.plan then anyPlan = true end
    local each = Each(it)
    if each then expected = expected + each * want else unknown = unknown + 1 end
    spent = spent + it.rec.spent
    if it.rec.bought > 0 and each then expectedDone = expectedDone + each * it.rec.bought end
    if IsDone(it) then doneN = doneN + 1 end
    if not it.rec.skipped and each then left = left + each * math.max(0, want - it.rec.bought) end
  end
  -- what the rest costs now, for the items scanned at their current amount
  local nowTotal, nowPlan, scanned, unscanned, short = 0, 0, 0, 0, 0
  for _, it in ipairs(items) do
    if not IsDone(it) then
      if FreshNow(it) then
        scanned = scanned + 1
        nowTotal = nowTotal + (it.rec.now or 0)
        local pl = PlannedFor(it, it.rec.nowN or 0)
        if pl and nowPlan then nowPlan = nowPlan + pl else nowPlan = nil end
        if (it.rec.nowN or 0) < it.rec.nowFor then short = short + 1 end
      else
        unscanned = unscanned + 1
      end
    end
  end
  local nowLine = ""
  if scanned > 0 then
    nowLine = "\nNow " .. Money(nowTotal) .. "  " .. Diff(nowTotal, nowPlan)
      .. (short > 0 and (RED .. "  " .. short .. " short|r") or "")
      .. (unscanned > 0 and (GREY .. "  (" .. unscanned .. " not scanned)|r") or "")
  end
  panel.progress:SetText(GOLD .. doneN .. " / " .. #items .. "|r")
  panel.summary:SetText((anyPlan and "Planned " or "Listed at ") .. Money(expected)
    .. (unknown > 0 and (GREY .. "  (" .. unknown .. " unpriced)|r") or "")
    .. "\nSpent " .. Money(spent) .. "  " .. (spent > 0 and Diff(spent, expectedDone) or "")
    .. "\nLeft " .. Money(left) .. nowLine)
  -- the current item
  local ph = state.phase
  if x then
    local icon = x.rec.id and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(x.rec.id)
    panel.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    panel.icon:Show()
    local need = Want(x) - x.rec.bought
    panel.item:SetText(x.name .. ((x.qty or x.rec.want) and "" or (GREY .. "  (no amount on the list)|r")))
    panel.amount:Show()
    if not panel.amount:HasFocus() then panel.amount:SetText(tostring(need)) end
    local pl = PlannedFor(x, need)
    local lines = { (x.plan and "Planned " or "Listed at ") .. (pl and Money(pl) or "?") }
    if ph == "scan" then
      local S = state.scan
      lines[#lines + 1] = GREY .. "Rescanning the list: " .. S.i .. " / " .. #S.keys .. "  " .. (S.name or "") .. "|r"
    elseif ph == "search" then lines[#lines + 1] = GREY .. "Searching the AH...|r"
    elseif ph == "find" then lines[#lines + 1] = GREY .. "Looking the item up on the AH...|r"
    elseif ph == "start" or ph == "price" then
      lines[#lines + 1] = "Now ~" .. Money(state.estimate) .. "  " .. Diff(state.estimate, PlannedFor(x, state.need))
      lines[#lines + 1] = GREY .. (ph == "price" and "Asking the AH for the exact price...|r"
        or "Buy now asks for the exact price, then Confirm buys.|r")
      if state.short then lines[#lines + 1] = RED .. "Only " .. state.need .. " on the AH.|r" end
    elseif ph == "ready" and state.kind == "commodity" then
      lines[#lines + 1] = "Exact " .. Money(state.quote) .. "  " .. Diff(state.quote, PlannedFor(x, state.need))
      lines[#lines + 1] = GREY .. "Confirm to buy " .. state.need .. " at this price.|r"
      if state.short then lines[#lines + 1] = RED .. "Only " .. state.need .. " on the AH.|r" end
    elseif ph == "ready" and state.kind == "item" then
      local per = state.auction and state.auction.per or 0
      lines[#lines + 1] = "This auction: " .. state.need .. " for " .. Money(state.quote)
      lines[#lines + 1] = "Each " .. Money(per) .. "  " .. Diff(per, Each(x))
      if state.need > need then lines[#lines + 1] = GREY .. "The smallest stack up is more than you need.|r" end
    elseif ph == "buying" then lines[#lines + 1] = GREY .. "Buying...|r"
    elseif ph == "none" then lines[#lines + 1] = RED .. "None on the AH.|r"
    elseif not atAH then lines[#lines + 1] = GREY .. "Open the auction house to buy.|r" end
    panel.itemInfo:SetText(table.concat(lines, "\n"))
  else
    panel.icon:Hide()
    panel.amount:Hide()
    panel.item:SetText(GREEN .. "All bought.|r")
    panel.itemInfo:SetText("")
  end
  -- the button
  if not x then
    panel.buy:SetText("Done") panel.buy:Disable()
  elseif ph == "ready" and state.kind == "commodity" then
    panel.buy:SetText("Confirm  " .. Money(state.quote)) panel.buy:Enable()
  elseif ph == "ready" then
    panel.buy:SetText("Buy " .. state.need .. "  " .. Money(state.quote)) panel.buy:Enable()
  elseif ph == "start" then
    panel.buy:SetText("Buy now  ~" .. Money(state.estimate)) panel.buy:Enable()
  elseif ph == "price" then
    panel.buy:SetText("Ask again") panel.buy:Enable()
  elseif ph == "scan" then
    panel.buy:SetText("Rescanning...") panel.buy:Disable()
  elseif atAH and (ph == "none" or ph == "idle" or ph == "search" or ph == "find") then
    panel.buy:SetText("Search again") panel.buy:Enable()
  else
    panel.buy:SetText(atAH and "..." or "Buy") panel.buy:Disable()
  end
  panel.skip:SetEnabled(x ~= nil)
  panel.rescanItem:SetEnabled(atAH and x ~= nil and ph ~= "buying" and ph ~= "scan")
  panel.rescanList:SetText(ph == "scan" and "Stop" or "Rescan list")
  panel.rescanList:SetEnabled(atAH and x ~= nil and ph ~= "buying")
  -- the list: done, current, to come
  local n = #items
  local rows = panel.visible or 12
  if not panel.scrolled and idx then panel.offset = idx - 3 end
  panel.offset = math.max(0, math.min(panel.offset, n - rows))
  for i, r in ipairs(panel.rows) do
    local it = i <= rows and items[panel.offset + i]
    if not it then
      r:Hide()
    else
      local rec = it.rec
      local done = rec.bought >= Want(it)
      r.check:SetShown(done)
      local label = it.name .. " x" .. Want(it)
      r.key, r.label, r.done = it.key, label, done
      if it == x then
        r.text:SetText(GOLD .. label .. "|r")
        r.bg:SetColorTexture(1, 0.82, 0, 0.08)
      elseif done then
        r.text:SetText(GREY .. label .. "|r")
        r.bg:SetColorTexture(0.1, 0.5, 0.15, 0.08)
      elseif rec.skipped then
        r.text:SetText(GREY .. label .. " (skipped)|r")
        r.bg:SetColorTexture(0, 0, 0, 0)
      else
        r.text:SetText("|cffdddddd" .. label .. "|r")
        r.bg:SetColorTexture(0, 0, 0, 0)
      end
      local exp = PlannedFor(it, Want(it))
      if not done and not rec.skipped and FreshNow(it) then
        if (rec.nowN or 0) == 0 then
          r.cost:SetText(RED .. "none up|r")
        else
          local pl = PlannedFor(it, rec.nowN)
          local c = (pl and rec.now > pl + 1 and RED) or (pl and rec.now < pl - 1 and GREEN) or "|cffffffff"
          r.cost:SetText(c .. Money(rec.now) .. "|r" .. (rec.nowN < rec.nowFor and (RED .. " (" .. rec.nowN .. ")|r") or ""))
        end
      elseif rec.bought > 0 then
        r.cost:SetText(Each(it) and Diff(rec.spent, PlannedFor(it, rec.bought)) or Money(rec.spent))
      else
        r.cost:SetText(exp and (GREY .. Money(exp) .. "|r") or "")
      end
      r:Show()
    end
  end
end

local function SaveAmount(box)
  local n = tonumber(box:GetText())
  local x = Current()
  if x and n and n >= 1 and x.rec.bought + n ~= Want(x) then
    x.rec.want = x.rec.bought + math.floor(n)
    Search()
  else
    Refresh()
  end
end

-- The list picker: a dropdown under the list name with every Auctionator shopping list, grouped
-- under the addon that made it (CraftRoute, CrateCost...; lists made by hand go under "Other
-- lists"), with how far along each is. A click anywhere else closes it; the wheel scrolls it.
local MENU_ROWS, MENU_ROW_H = 18, 20
local OTHER = "Other lists"
local menu

local function CloseMenu()
  if menu then menu.catcher:Hide() end
end

local function AddonLoaded(name)
  local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if not f then return false end
  local ok, loaded = pcall(f, name)
  return ok and loaded and true or false
end

-- Which addon made a list: the one that called SetListPlan for it, else the name's first word
-- when that's a loaded addon ("CraftRoute: ...", "CrateCost crates ..."), else OTHER.
local function SourceOf(name)
  local L = Store().lists[name]
  if L and type(L.source) == "string" then return L.source end
  local word = name:match("^([%w_%-]+)")
  if word and AddonLoaded(word) then return word end
  return OTHER
end

-- headers and lists in menu order: sources A-Z (OTHER last), each source's lists A-Z
local function MenuEntries()
  local groups, order = {}, {}
  for _, l in ipairs(RawLists()) do
    local src = SourceOf(l.name)
    if not groups[src] then
      groups[src] = {}
      order[#order + 1] = src
    end
    table.insert(groups[src], l.name)
  end
  table.sort(order, function(a, b)
    if (a == OTHER) ~= (b == OTHER) then return b == OTHER end
    return a:lower() < b:lower()
  end)
  local out = {}
  for _, src in ipairs(order) do
    out[#out + 1] = { header = src }
    table.sort(groups[src], function(a, b) return a:lower() < b:lower() end)
    for _, n in ipairs(groups[src]) do out[#out + 1] = { name = n } end
  end
  return out
end

local function FillMenu()
  local entries = menu.entries
  menu.offset = math.max(0, math.min(menu.offset, #entries - MENU_ROWS))
  local cur = ActiveName()
  local shown = math.min(#entries, MENU_ROWS)
  for i, row in ipairs(menu.rows) do
    local e = entries[menu.offset + i]
    if i > shown or not e then
      row:Hide()
    elseif e.header then
      row.text:SetPoint("LEFT", 6, 0)
      row.text:SetText(GOLD .. e.header .. "|r")
      row.sel:Hide()
      row.name = nil
      row:EnableMouse(false)
      row:Show()
    else
      local items = Items(e.name) or {}
      local done = 0
      for _, it in ipairs(items) do
        if IsDone(it) then done = done + 1 end
      end
      row.text:SetPoint("LEFT", 18, 0)
      local L = Store().lists[e.name]
      local forgotten = L and L.forgotten
      row.text:SetText((e.name == cur and "|cffffffff" or forgotten and GREY or "|cffcccccc") .. e.name .. "|r"
        .. GREY .. "  " .. (forgotten and "forgotten" or (done .. " / " .. #items)) .. "|r")
      row.sel:SetShown(e.name == cur)
      row.name = e.name
      row:EnableMouse(true)
      row:Show()
    end
  end
  menu.bar:SetShown(#entries > MENU_ROWS)
  if #entries > MENU_ROWS then
    local trackH = shown * MENU_ROW_H
    local h = math.max(12, trackH * MENU_ROWS / #entries)
    menu.bar:SetHeight(h)
    menu.bar:SetPoint("TOPRIGHT", -2, -4 - (trackH - h) * menu.offset / (#entries - MENU_ROWS))
  end
  menu:SetHeight(math.max(1, shown) * MENU_ROW_H + 8)
  menu.empty:SetShown(#entries == 0)
end

local function BuildMenu()
  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN_DIALOG")
  catcher:SetScript("OnClick", function(self) self:Hide() end)
  catcher:Hide()
  local m = CreateFrame("Frame", nil, catcher)
  m:SetFrameStrata("FULLSCREEN_DIALOG")
  m:SetFrameLevel(catcher:GetFrameLevel() + 10)
  -- a solid fill and a 1px border, drawn as textures so nothing behind shows through
  local bg = m:CreateTexture(nil, "BACKGROUND", nil, -8)
  bg:SetAllPoints()
  bg:SetColorTexture(0.25, 0.25, 0.28, 1)
  local fill = m:CreateTexture(nil, "BACKGROUND", nil, -7)
  fill:SetPoint("TOPLEFT", 1, -1)
  fill:SetPoint("BOTTOMRIGHT", -1, 1)
  fill:SetColorTexture(0.03, 0.03, 0.035, 1)
  m:EnableMouse(true)
  m:EnableMouseWheel(true)
  m:SetScript("OnMouseWheel", function(_, d)
    m.offset = m.offset - d * 3
    FillMenu()
  end)
  m.catcher, m.offset, m.rows, m.entries = catcher, 0, {}, {}
  m.bar = m:CreateTexture(nil, "ARTWORK")
  m.bar:SetWidth(4)
  m.bar:SetColorTexture(0.55, 0.55, 0.55, 1)
  m.empty = m:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  m.empty:SetPoint("LEFT", 8, 0)
  m.empty:SetText(GREY .. "No shopping lists yet.|r")
  for i = 1, MENU_ROWS do
    local row = CreateFrame("Button", nil, m)
    row:SetHeight(MENU_ROW_H)
    row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * MENU_ROW_H)
    row:SetPoint("RIGHT", m, "RIGHT", -10, 0)
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(1, 0.82, 0, 0.25)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 18, 0)
    row.text:SetPoint("RIGHT", -6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
      if not self.name then return end
      catcher:Hide()
      SelectList(self.name)
    end)
    m.rows[i] = row
  end
  menu = m
end

local function ToggleMenu(anchor)
  if not Active() then return end
  if not menu then BuildMenu() end
  if menu.catcher:IsShown() then
    menu.catcher:Hide()
    return
  end
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
  menu.entries = MenuEntries()
  -- start with the current list in view
  menu.offset = 0
  local cur = ActiveName()
  for i, e in ipairs(menu.entries) do
    if e.name == cur then menu.offset = i - 4 end
  end
  FillMenu()
  menu.catcher:Show()
end

local function Build()
  local p = CreateFrame("Frame", "ShoppingDockPanel", UIParent, "BackdropTemplate")
  panel = p
  p:SetSize(W, 560)
  p:SetFrameStrata("HIGH")
  p:SetClampedToScreen(true)
  p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  p:SetBackdropColor(0.06, 0.06, 0.07, 0.95)
  p:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
  -- a solid fill under the backdrop (or a theme's shell), so the AH never shows through
  local base = p:CreateTexture(nil, "BACKGROUND", nil, -8)
  base:SetPoint("TOPLEFT", 4, -4)
  base:SetPoint("BOTTOMRIGHT", -4, 4)
  base:SetColorTexture(0.04, 0.04, 0.05, 0.97)
  p:EnableMouse(true)
  p.offset = 0
  p.nsTitle = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  p.nsTitle:SetPoint("TOPLEFT", 18, -16)
  p.nsTitle:SetText("Shopping list")
  p.progress = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  p.progress:SetPoint("TOPRIGHT", -36, -18)
  local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function() p:Hide() end)
  -- which list: a dropdown across the top
  p.pick = CreateFrame("Button", nil, p, "BackdropTemplate")
  p.pick:SetHeight(22)
  p.pick:SetPoint("TOPLEFT", 16, -44)
  p.pick:SetPoint("TOPRIGHT", -16, -44)
  p.pick:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  p.pick:SetBackdropColor(0.1, 0.1, 0.11, 1)
  p.pick:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
  local hl = p.pick:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)
  p.listName = p.pick:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  p.listName:SetPoint("LEFT", 6, 0)
  p.listName:SetPoint("RIGHT", -16, 0)
  p.listName:SetWordWrap(false)
  local arrow = p.pick:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  arrow:SetPoint("RIGHT", -5, 0)
  arrow:SetText("v")
  p.pick:SetScript("OnClick", function(self) ToggleMenu(self) end)
  Tip(p.pick, "Shopping lists", "Click to pick which Auctionator shopping list the dock works through.")
  -- summary
  p.summary = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  p.summary:SetPoint("TOPLEFT", 18, -74)
  -- Rescan list: top right of the summary
  p.rescanList = Button(p, "Rescan list", 96, 20, function()
    if state.phase == "scan" then StopScan() else StartScan() end
  end)
  p.rescanList:SetPoint("TOPRIGHT", -16, -72)
  Tip(p.rescanList, "Rescan list", "Search the AH for every item still to buy, one after another, and show what "
    .. "each costs now on its row. Red is over what the list expected, green under. A number in brackets "
    .. "is all the AH has.")
  p.summary:SetPoint("RIGHT", -18, 0)
  p.summary:SetJustifyH("LEFT")
  p.summary:SetSpacing(3)
  local rule = p:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", 16, -126)
  rule:SetPoint("TOPRIGHT", -16, -126)
  rule:SetColorTexture(1, 0.82, 0, 0.25)
  -- the current item
  p.icon = p:CreateTexture(nil, "ARTWORK")
  p.icon:SetSize(30, 30)
  p.icon:SetPoint("TOPLEFT", 18, -136)
  p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  -- Rescan item: top right of the item area
  p.rescanItem = Button(p, "Rescan item", 96, 20, function() if Active() then Search() end end)
  p.rescanItem:SetPoint("TOPRIGHT", -16, -134)
  Tip(p.rescanItem, "Rescan item", "Search the AH again for the item you're on.")
  p.item = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  p.item:SetPoint("TOPLEFT", p.icon, "TOPRIGHT", 8, 0)
  p.item:SetPoint("RIGHT", p.rescanItem, "LEFT", -6, 0)
  p.item:SetJustifyH("LEFT")
  p.item:SetWordWrap(false)
  p.itemInfo = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  p.itemInfo:SetPoint("TOPLEFT", p.item, "BOTTOMLEFT", 0, -4)
  p.itemInfo:SetPoint("RIGHT", -18, 0)
  p.itemInfo:SetJustifyH("LEFT")
  p.itemInfo:SetSpacing(2)
  -- Buy, amount, Skip
  p.buy = Button(p, "Buy", W - 152, 24, BuyClick)
  p.buy:SetPoint("TOPLEFT", 16, -218)
  p.amount = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  p.amount:SetSize(40, 22)
  p.amount:SetPoint("LEFT", p.buy, "RIGHT", 10, 0)
  p.amount:SetAutoFocus(false)
  p.amount:SetNumeric(true)
  p.amount:SetMaxLetters(5)
  -- saved on Enter and on focus loss; Esc puts the old amount back
  p.amount:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  p.amount:SetScript("OnEscapePressed", function(self) self.cancelled = true self:ClearFocus() end)
  p.amount:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  p.amount:SetScript("OnEditFocusLost", function(self)
    if self.cancelled then
      self.cancelled = nil
      Refresh()
    else
      SaveAmount(self)
    end
  end)
  Tip(p.amount, "Amount", "How many more of this item to buy. Type a number and press Enter.")
  p.skip = Button(p, "Skip", 62, 24, Skip)
  p.skip:SetPoint("TOPRIGHT", -16, -218)
  Tip(p.skip, "Skip", "Move on without buying this one.")
  -- the list
  local lt = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  lt:SetPoint("TOPLEFT", 18, -LIST_TOP + 16)
  lt:SetText("The plan")
  local function Wheel(_, d)
    p.offset = p.offset - d * 3
    p.scrolled = true
    Refresh()
  end
  p.rows = {}
  for i = 1, MAX_ROWS do
    local r = CreateFrame("Button", nil, p)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 14, -LIST_TOP - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", p, "RIGHT", -14, 0)
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
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    r:SetScript("OnClick", function(self) FocusItem(self.key) end)
    r:SetScript("OnEnter", function(self)
      if not self.key then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText(self.label or "")
      GameTooltip:AddLine(self.done and "Bought." or "Click to buy this one next.", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", Wheel)
    p.rows[i] = r
  end
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", Wheel)
  local forget = Button(p, "Forget list", 120, 22, function()
    local name = ActiveName()
    if not name then return end
    -- the dock drops this list's progress and stops opening for it; the plan's prices stay,
    -- and Auctionator's list isn't touched
    local L = Track(name)
    for _, rec in pairs(L.items) do
      rec.bought, rec.spent, rec.skipped, rec.want = 0, 0, nil, nil
    end
    L.focus, L.forgotten = nil, true
    Store().active = nil
    p.scrolled = false
    Search()
  end)
  forget:SetPoint("BOTTOMRIGHT", -16, 14)
  Tip(forget, "Forget list", "Drop what's been bought and skipped on this list, and stop opening the dock for it "
    .. "at the auction house. Auctionator's list isn't touched: pick it from the list menu to start it again.")
  p:SetScript("OnHide", function()
    CloseMenu()
    if state.phase == "scan" then state = { phase = "idle" } end
    CancelQuote()
    if state.phase == "price" or state.phase == "ready" or state.phase == "start" then state = { phase = "idle" } end
  end)
  p:Hide()
  -- the host's house kit skins the shell and fonts, when there is one
  if NS.ThemeRegisterWindow then pcall(NS.ThemeRegisterWindow, p) end
end

local function Dock()
  local ahf = _G.AuctionHouseFrame
  panel:ClearAllPoints()
  if ahf and ahf:IsShown() then
    panel:SetPoint("TOPLEFT", ahf, "TOPRIGHT", 4, -26)
    local h = tonumber(ahf:GetHeight())
    panel:SetHeight(h and h > 400 and h - 26 or 560)
  else
    panel:SetPoint("CENTER")
    panel:SetHeight(560)
  end
  local h = tonumber(panel:GetHeight()) or 560
  panel.visible = math.max(4, math.min(MAX_ROWS, math.floor((h - LIST_TOP - FOOT) / ROW_H)))
end

local function ShowDock()
  if not Active() then return end
  if not panel then Build() end
  Dock()
  panel.scrolled = false
  panel:Show()
  if NS.ApplyTheme then pcall(NS.ApplyTheme, panel) end
  if atAH and Current() then Search() else Refresh() end
end

function SD.Show() ShowDock() end
function SD.Hide() if panel then panel:Hide() end end
function SD.Toggle()
  if panel and panel:IsShown() then panel:Hide() else ShowDock() end
end

-- the Shopping list button on the AH window's right edge: opens and closes the dock
local function Tab()
  if not Active() then return end
  local ahf = _G.AuctionHouseFrame
  if not ahf then return end
  if not tab then
    tab = Button(ahf, "Shopping list", 120, 22, function() SD.Toggle() end)
    tab:SetPoint("TOPLEFT", ahf, "TOPRIGHT", 4, 0)
    Tip(tab, "Shopping list", "Works through an Auctionator shopping list one item at a time, with the live "
      .. "price against what the list expected.")
  end
  tab:SetShown(SD.IsEnabled())
end

-- The "Show shopping list dock" option: off hides the AH button and the dock, and stops the
-- dock opening by itself. The minimap button and slash command still open it.
function SD.SetEnabled(on)
  Store().enabled = on and true or false
  if tab then tab:SetShown(on and true or false) end
  if not on and panel then panel:Hide() end
  if on and atAH then Tab() end
end

-- A list was made or changed: the dock follows it, and opens if you're at the AH.
local function Follow(name, fresh)
  if type(name) ~= "string" then return end
  local L = Track(name, fresh)
  L.forgotten = nil
  Store().active = name
  if not fresh then
    -- items the list no longer has drop out of its progress
    local raw = FindRaw(name)
    if raw then
      local keep = {}
      for _, str in ipairs(raw.items) do
        local n = type(str) == "string" and ParseTerm(str)
        if n then keep[n:lower()] = true end
      end
      for key in pairs(L.items) do
        if not keep[key] then L.items[key] = nil end
      end
    end
  end
  Items(name) -- note what each item costs now: the "Listed at" prices
  if not SD.IsEnabled() then return end
  if panel and panel:IsShown() then
    panel.scrolled = false
    Search()
  elseif atAH then
    C_Timer.After(0.2, ShowDock)
  end
end

------------------------------------------------------------------------------------------------
-- The public API, for addons that make shopping lists (see README.md):
--
--   ShoppingDock.SetListPlan(listName, plan)
--     Call it right after Auctionator.API.v1.CreateShoppingList. plan is either a list
--     { { id = itemID, name = "Linen Cloth", qty = 20, planned = 12345 }, ... } or a map
--     { [itemID] = { qty = 20, planned = 12345 } }. planned is the total copper you expect
--     those qty to cost. The dock shows spending against it instead of the price when listed.
--
--   ShoppingDock.ShowShoppingList(listName)  opens the dock on that list.

-- The addon that called: the first stack line outside this file names its folder
-- (Interface/AddOns/<folder>/...). Read from the whole stack, so the level doesn't matter.
local function CallerAddon()
  if not debugstack then return nil end
  local ok, st = pcall(debugstack, 1, 12, 0)
  if not (ok and type(st) == "string") then return nil end
  for line in st:gmatch("[^\n]+") do
    if not line:find("ShoppingDock%.lua") then
      local folder = line:match("AddOns[/\\]([^/\\]+)[/\\]")
      if folder then return folder end
    end
  end
end

function SD.SetListPlan(listName, plan, source)
  if not (Active() and type(listName) == "string" and type(plan) == "table") then return false end
  local L = Track(listName)
  L.plan = {}
  -- which addon made the list, for the list picker's groups
  L.source = type(source) == "string" and source ~= "" and source or CallerAddon() or L.source
  local function Add(id, e)
    id = tonumber(id)
    if not (id and type(e) == "table") then return end
    local name = type(e.name) == "string" and e.name or ItemName(id)
    L.plan[id] = { qty = tonumber(e.qty), planned = tonumber(e.planned), name = name }
    IndexName(name, id)
    if name then
      local rec = L.items[name:lower()]
      if rec then rec.id = id end
    end
  end
  if plan[1] then
    for _, e in ipairs(plan) do Add(e.id or e.itemID, e) end
  else
    for id, e in pairs(plan) do Add(id, e) end
  end
  local ok, err = pcall(Follow, listName, false)
  if not ok then Log("SetListPlan", err) end
  return true
end

function SD.ShowShoppingList(listName)
  if not Active() then return end
  if type(listName) == "string" and FindRaw(listName) then
    Store().active = listName
    Track(listName).forgotten = nil
  end
  if SD.IsEnabled() then ShowDock() end
end

-- A newer copy took over: this one hides its frames and goes quiet.
function SD._Retire()
  if panel then panel:Hide() end
  if tab then tab:Hide() end
end

------------------------------------------------------------------------------------------------
-- Following Auctionator's lists. Its EventBus calls listeners in a plain loop with no error
-- guard, so everything here is wrapped. Runs inside the call on purpose: a maker's
-- SetListPlan right after CreateShoppingList must land after the list is reset, not before.

local listListener = {}
function listListener:ReceiveEvent(event, name)
  if not Active() then return end
  local ok, err = pcall(function()
    local ev = Auctionator.Shopping.Events
    if event == ev.ListImportFinished then
      Follow(name, true) -- a new list (or one replaced under the same name)
    elseif event == ev.ListItemChange and type(name) == "string" then
      Follow(name, false)
    elseif event == ev.ListMetaChange and type(name) == "string" and FindRaw(name) and not Store().lists[name] then
      Follow(name, true) -- made in Auctionator's Shopping tab
    end
    if panel and panel:IsShown() then Refresh() end
  end)
  if not ok then Log("list event", err) end
end

local function WatchLists()
  local ev = Auctionator and Auctionator.Shopping and Auctionator.Shopping.Events
  if listListener.on or not (ev and Auctionator.EventBus) then return end
  local names = {}
  for _, k in ipairs({ "ListImportFinished", "ListItemChange", "ListMetaChange" }) do
    if ev[k] then names[#names + 1] = ev[k] end
  end
  listListener.on = pcall(Auctionator.EventBus.Register, Auctionator.EventBus, listListener, names)
end

local function Init()
  if not Active() then return end
  WatchLists()
  -- progress for lists Auctionator no longer has goes
  local s = Store()
  for name in pairs(s.lists) do
    if not FindRaw(name) then s.lists[name] = nil end
  end
  ActiveName()
end

------------------------------------------------------------------------------------------------
-- Events

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
  "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED",
  "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
  "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_PURCHASE_COMPLETED",
  "AUCTION_HOUSE_SHOW_ERROR" }) do
  if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e) then
    pcall(ev.RegisterEvent, ev, e)
  end
end

local function OnEvent(e, a, b)
  if e == "PLAYER_LOGIN" then
    Init()
    return
  elseif e == "AUCTION_HOUSE_SHOW" then
    atAH = true
    if not SD.IsEnabled() then return end
    C_Timer.After(0.3, Tab)
    -- the list you're on still has things to buy: the dock opens beside the AH
    local name = ActiveName()
    if name and not Track(name).forgotten and Current() then C_Timer.After(0.5, ShowDock) end
    return
  elseif e == "AUCTION_HOUSE_CLOSED" then
    atAH = false
    if panel then panel:Hide() end
    state = { phase = "idle" }
    return
  end
  if not (panel and panel:IsShown()) then return end
  if e == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    if state.waiting then
      state.waiting = nil
      SendQuery()
    elseif state.scan and state.scan.waiting then
      state.scan.waiting = nil
      ScanSend()
    end
  elseif e == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
    if state.phase == "scan" then ScanBrowse() else OnBrowse() end
  elseif e == "COMMODITY_SEARCH_RESULTS_UPDATED" or e == "COMMODITY_SEARCH_RESULTS_ADDED" then
    if state.phase == "scan" then
      if e == "COMMODITY_SEARCH_RESULTS_UPDATED" then ScanCommodity(a) end
    else
      OnCommodity(a)
    end
  elseif e == "ITEM_SEARCH_RESULTS_UPDATED" then
    if state.phase == "scan" then ScanItem(a) else OnItem(a) end
  elseif e == "COMMODITY_PRICE_UPDATED" then
    -- the AH's quote: a, b = unit price, total
    if state.phase == "price" then
      state.quote, state.unit = b, a
      state.phase = "ready"
      Refresh()
    end
  elseif e == "COMMODITY_PRICE_UNAVAILABLE" then
    if state.phase == "price" then
      state = { phase = "none", id = state.id, key = state.key, kind = "commodity" }
      Refresh()
    end
  elseif e == "COMMODITY_PURCHASE_SUCCEEDED" then
    if state.phase == "buying" and state.kind == "commodity" then Bought(state.need or 0, state.quote) end
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
end

ev:SetScript("OnEvent", function(_, e, a, b)
  if not Active() then return end
  local ok, err = pcall(OnEvent, e, a, b)
  if not ok then Log(e, err) end
end)

-- a copy loaded after login (load on demand) starts at once
if IsLoggedIn and IsLoggedIn() then
  local ok, err = pcall(Init)
  if not ok then Log("init", err) end
  if _G.AuctionHouseFrame and _G.AuctionHouseFrame:IsShown() then pcall(OnEvent, "AUCTION_HOUSE_SHOW") end
end

------------------------------------------------------------------------------------------------
-- Slash command. Every copy sets the same one; it always goes to the active copy.

SLASH_SHOPPINGDOCK1 = "/shoppingdock"
SLASH_SHOPPINGDOCK2 = "/sdock"
SlashCmdList.SHOPPINGDOCK = function(msg)
  local sd = _G.ShoppingDock
  if type(sd) ~= "table" then return end
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if (msg == "config" or msg == "settings" or msg == "options") and sd.OpenSettings then
    sd.OpenSettings()
  else
    sd.Toggle()
  end
end
