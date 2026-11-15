local _, ns = ...

-- AH depth: the real listings for crates and bundle materials, so a fill that needs 40 units
-- is priced up the listings instead of 40 x the cheapest one. Auctionator only keeps each
-- item's lowest price, so the /crates "Scan AH" button searches the AH itself:
--   1. Survey: one browse search per 50 items (SearchForItemKeys) gives each item's lowest
--      price and how many are listed. Anything it doesn't see isn't on sale.
--   2. Each listed item is searched for its listings, a page at a time, until the listings
--      cover what the crate list needs of it (Window.lua ns.DepthWants), with 25% to spare.
-- The AH answers one throttled message at a time, so one search goes out at a time; a
-- dropped one is sent again, an unanswered one once more, then left out.
-- Listings are saved per realm with the time they were read, and used for DEPTH_TTL.
-- Approach after Waylaid Auction Helper's scanner (MIT), written for CrateCost's data.
local Depth = { state = "idle", queue = {}, done = 0, total = 0 }
ns.Depth = Depth

Depth.TTL = 30 * 60       -- listings older than this fall back to Auctionator's price
Depth.TIMEOUT = 5         -- seconds to wait for an answer
Depth.RETRIES = 1         -- times to ask again before leaving it out
Depth.MAX_PAGES = 10      -- "more results" requests per item
Depth.CHUNK = 50          -- item keys per survey search
Depth.FLOOR = 100         -- read at least this many units of a material (full depth for ratings)

local AH = C_AuctionHouse

local function Realm() return (GetRealmName and GetRealmName()) or "?" end

local function Store()
  if type(CrateCostDB) ~= "table" then CrateCostDB = {} end
  CrateCostDB.depth = CrateCostDB.depth or {}
  local realm = Realm()
  CrateCostDB.depth[realm] = CrateCostDB.depth[realm] or { items = {} }
  return CrateCostDB.depth[realm]
end

-- Seconds since the last finished scan on this realm, or nil.
function Depth.Age()
  local s = type(CrateCostDB) == "table" and CrateCostDB.depth and CrateCostDB.depth[Realm()]
  return s and s.t and (time() - s.t) or nil
end

local function Fresh(id)
  local s = type(CrateCostDB) == "table" and CrateCostDB.depth and CrateCostDB.depth[Realm()]
  local it = s and s.items[id]
  if it and it.t and time() - it.t < Depth.TTL then return it end
end

-- The fresh scanned listings for `id` ({ {unit price, units}, ... } cheapest first) and whether
-- that's all of them; nil without a fresh scan.
function Depth.Rows(id)
  local it = Fresh(id)
  if it then return it.rows, it.full end
end

-- Cost of `n` units of `id`, and how it was priced:
--   { depth = true } walked the scanned listings, cheapest first;
--     .short = fewer listed than needed (the rest priced at the dearest listing),
--     .none = none listed (cost nil)
--   {} = no fresh scan: Auctionator's lowest price x n.
-- nil cost = no price at all.
function ns.FillCost(id, n)
  if not id then return nil, {} end
  if n <= 0 then return 0, {} end
  local it = Fresh(id)
  if it then
    local rows = it.rows
    if #rows == 0 then return nil, { depth = true, none = true } end
    local cost, left, last = 0, n, rows[1][1]
    for _, r in ipairs(rows) do
      local take = math.min(r[2], left)
      cost, left, last = cost + take * r[1], left - take, r[1]
      if left == 0 then break end
    end
    -- past what was read: at the dearest price seen. Short only when that was every listing.
    if left > 0 then cost = cost + left * last end
    return cost, { depth = true, short = left > 0 and it.full }
  end
  local p = ns.Price and ns.Price(id)
  return p and p * n, {}
end

------------------------------------------------------------------------------------------------
-- Scanning
------------------------------------------------------------------------------------------------
local SORTS
local function Sorts()
  if not SORTS then
    local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
    SORTS = { { sortOrder = order, reverseSort = false } }
  end
  return SORTS
end

local function Changed()
  if ns.OnDepthChanged then ns.OnDepthChanged() end
end

local function Units(rows)
  local n = 0
  for _, r in ipairs(rows) do n = n + r[2] end
  return n
end

local pending, lastSend
local function Ready()
  return not AH.IsThrottledMessageSystemReady or AH.IsThrottledMessageSystemReady()
end

local function Send(fn)
  if not Ready() then
    pending = fn
    C_Timer.After(Depth.TIMEOUT, function()   -- in case the ready event never comes
      if pending ~= fn then return end
      pending, lastSend = nil, fn
      fn()
    end)
    return
  end
  lastSend = fn
  fn()
end

local Next, Ask

local function Save(id, rows, full)
  local s = Store()
  s.items[id] = { t = time(), full = full, rows = rows }
end

local function Finished(entry)
  if entry.timer then entry.timer:Cancel() end
  Depth.current = nil
  Depth.done = Depth.done + 1
end

local function Unanswered(entry)
  entry.tries = entry.tries + 1
  if entry.tries <= Depth.RETRIES then
    entry.more = nil
    entry.pages = 0
    Ask(entry)
    return
  end
  Finished(entry)
  if entry.survey then
    -- no survey answer: search each of its items on its own
    for _, k in ipairs(entry.keys) do
      table.insert(Depth.queue, { id = k.itemID, want = Depth.wants[k.itemID] or 1, tries = 0, pages = 0 })
    end
    Depth.total = Depth.total + #entry.keys
  else
    Depth.failed = Depth.failed + 1
    -- what the survey saw is better than nothing: its lowest price, not the depth
    local seen = Depth.seen and Depth.seen[entry.id]
    if seen then Save(entry.id, { { seen.min, seen.total } }, false) end
  end
  Next()
end

Ask = function(entry)
  Depth.current = entry
  pending = nil
  Send(function()
    if entry.timer then entry.timer:Cancel() end
    entry.timer = C_Timer.NewTimer(Depth.TIMEOUT, function()
      if Depth.current == entry then Unanswered(entry) end
    end)
    if entry.survey then
      if entry.more then AH.RequestMoreBrowseResults() else AH.SearchForItemKeys(entry.keys, Sorts()) end
    elseif entry.more == "commodity" then
      AH.RequestMoreCommoditySearchResults(entry.id)
    elseif entry.more == "item" then
      AH.RequestMoreItemSearchResults(AH.MakeItemKey(entry.id))
    else
      AH.SendSearchQuery(AH.MakeItemKey(entry.id), Sorts(), true)
    end
  end)
end

-- Survey answer: lowest price and units listed for every item it covers.
local function OnBrowse()
  local entry = Depth.current
  if not (entry and entry.survey) then return end
  for _, r in ipairs(AH.GetBrowseResults() or {}) do
    local id = r.itemKey and r.itemKey.itemID
    if id and Depth.wants[id] and r.minPrice and (r.totalQuantity or 0) > 0 then
      Depth.seen[id] = { min = r.minPrice, total = r.totalQuantity }
    end
  end
  if AH.HasFullBrowseResults and not AH.HasFullBrowseResults() and entry.pages < Depth.MAX_PAGES then
    entry.pages, entry.more = entry.pages + 1, true
    Ask(entry)
    return
  end
  Finished(entry)
  -- items the survey didn't see aren't on sale
  for _, k in ipairs(entry.keys) do
    if not Depth.seen[k.itemID] then Save(k.itemID, {}, true) end
  end
  Next()
end

-- Listings, cheapest first, your own left out: rows of { unit price, units }.
local function ReadCommodity(id)
  local rows = {}
  for i = 1, AH.GetNumCommoditySearchResults(id) or 0 do
    local r = AH.GetCommoditySearchResultInfo(id, i)
    if r and r.unitPrice and r.quantity then
      local qty = r.quantity - (r.containsOwnerItem and (r.numOwnerItems or r.quantity) or 0)
      if qty > 0 then rows[#rows + 1] = { r.unitPrice, qty } end
    end
  end
  return rows, AH.HasFullCommoditySearchResults(id), "commodity"
end

-- Non-commodity auctions sell whole; a stack counts at its price per unit.
local function ReadItem(itemKey)
  local rows = {}
  for i = 1, AH.GetNumItemSearchResults(itemKey) or 0 do
    local r = AH.GetItemSearchResultInfo(itemKey, i)
    if r and r.buyoutAmount and r.buyoutAmount > 0 and not r.containsOwnerItem then
      local qty = r.quantity or 1
      rows[#rows + 1] = { math.ceil(r.buyoutAmount / qty), qty }
    end
  end
  table.sort(rows, function(a, b) return a[1] < b[1] end)
  return rows, AH.HasFullItemSearchResults(itemKey), "item"
end

local function OnAnswer(id, rows, full, more)
  local entry = Depth.current
  if not entry or entry.survey or entry.id ~= id then return end
  if not full and Units(rows) < entry.want and entry.pages < Depth.MAX_PAGES then
    entry.pages, entry.more = entry.pages + 1, more
    Ask(entry)
    return
  end
  -- keep twice what's wanted at most, so the saved data stays small
  local keep, units = {}, 0
  for _, r in ipairs(rows) do
    keep[#keep + 1] = r
    units = units + r[2]
    if units >= entry.want * 2 then
      if #keep < #rows then full = false end
      break
    end
  end
  Finished(entry)
  Save(id, keep, full and true or false)
  Next()
end

Next = function()
  if Depth.state ~= "running" then return end
  if #Depth.queue == 0 and Depth.phase == "survey" then
    -- the survey is done: search every listed item for its listings
    Depth.phase = "listings"
    for id, seen in pairs(Depth.seen) do
      local want = Depth.wants[id] or 1
      if want <= 1 then
        -- one unit: the lowest price is exact
        Save(id, { { seen.min, seen.total } }, false)
      else
        table.insert(Depth.queue, { id = id, want = want, tries = 0, pages = 0 })
      end
    end
    Depth.total = Depth.done + #Depth.queue
  end
  local entry = table.remove(Depth.queue, 1)
  Changed()
  if entry then Ask(entry) else Depth.Finish() end
end

local function Print(msg) print("|cffd4a017CrateCost:|r " .. msg) end

-- `wants`: { [itemID] = units to read }.
function Depth.Start(wants)
  if Depth.state ~= "idle" then return end
  if not (Depth.atAH and AH and AH.SendSearchQuery) then
    Print("open the auction house first.")
    return
  end
  Depth.wants, Depth.seen, Depth.queue = wants, {}, {}
  Depth.done, Depth.failed = 0, 0
  Depth.state, Depth.started = "running", GetTime()
  local ids = {}
  for id in pairs(wants) do ids[#ids + 1] = id end
  table.sort(ids)
  if AH.SearchForItemKeys then
    Depth.phase = "survey"
    local keys = {}
    for _, id in ipairs(ids) do
      keys[#keys + 1] = AH.MakeItemKey(id)
      if #keys == Depth.CHUNK then
        table.insert(Depth.queue, { survey = true, keys = keys, tries = 0, pages = 0 })
        keys = {}
      end
    end
    if #keys > 0 then table.insert(Depth.queue, { survey = true, keys = keys, tries = 0, pages = 0 }) end
  else
    Depth.phase = "listings"
    for _, id in ipairs(ids) do
      table.insert(Depth.queue, { id = id, want = wants[id], tries = 0, pages = 0 })
    end
  end
  Depth.total = #Depth.queue
  Next()
end

function Depth.Finish()
  Depth.state = "idle"
  Store().t = time()
  Print(string.format("AH scan done in %ds: %d searches%s.", math.floor(GetTime() - Depth.started),
    Depth.done, Depth.failed > 0 and string.format(", %d unanswered", Depth.failed) or ""))
  if ns.InvalidateCrates then ns.InvalidateCrates() end
  Changed()
end

-- Stops a scan. What was read so far is kept.
function Depth.Stop(why)
  if Depth.state == "idle" then return end
  if Depth.current then Finished(Depth.current) end
  Depth.state, pending, Depth.queue = "idle", nil, {}
  Print("AH scan stopped" .. (why and (": " .. why) or "") .. ". Listings read so far are kept.")
  if ns.InvalidateCrates then ns.InvalidateCrates() end
  Changed()
end

local f = CreateFrame("Frame")
local EVENTS = {
  "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
  "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
  "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
  "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED",
  "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED",
}
for _, ev in ipairs(EVENTS) do
  if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(ev) then
    pcall(f.RegisterEvent, f, ev)
  end
end
f:SetScript("OnEvent", function(_, ev, a)
  if ev == "AUCTION_HOUSE_SHOW" then
    Depth.atAH = true
    Changed()
  elseif ev == "AUCTION_HOUSE_CLOSED" then
    Depth.atAH = false
    Depth.Stop("the auction house closed")
    Changed()
  elseif Depth.state ~= "running" then
    return
  elseif ev == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    local fn = pending
    pending = nil
    if fn then lastSend = fn fn() end
  elseif ev == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
    if Depth.current and lastSend and not pending then pending = lastSend end
  elseif ev == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or ev == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
    OnBrowse()
  elseif ev == "COMMODITY_SEARCH_RESULTS_UPDATED" or ev == "COMMODITY_SEARCH_RESULTS_ADDED" then
    if Depth.current and Depth.current.id == a then OnAnswer(a, ReadCommodity(a)) end
  elseif ev == "ITEM_SEARCH_RESULTS_UPDATED" or ev == "ITEM_SEARCH_RESULTS_ADDED" then
    if a and Depth.current and Depth.current.id == a.itemID then OnAnswer(a.itemID, ReadItem(a)) end
  end
end)
