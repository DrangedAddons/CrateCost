local _, ns = ...

-- /crates: every Waylaid Crate with its cheapest bundle at current Auctionator prices.
-- Cost = the crate's own AH price + the cheapest bundle. Click a header to sort, type to
-- search crate or material names, filter by crate type or by the profession the material
-- comes from (then only that profession's bundles count). Hover a row for every bundle.

local ROW_H, WIDTH, TOP = 18, 1070, 84
-- money columns show gold / silver / copper in fixed right-aligned slots so units line up
local SUB = 28
local CART_ATLAS, CART_FILE = "Perks-ShoppingCart", "Interface\\AddOns\\CrateCost\\cart"
local COLS = {
  { key = "name",   title = "Crate",       x = 10,  w = 165, justify = "LEFT"  },
  { key = "n",      title = "Crates",      x = 175, w = 40,  justify = "RIGHT", desc = false },
  { key = "crate",  title = "Crate cost",  x = 220, w = 92,  justify = "RIGHT", desc = false, money = true },
  { key = "best",   title = "Best bundle", x = 327, w = 240, justify = "LEFT"  },
  { key = "bundle", title = "Bundle cost", x = 572, w = 92,  justify = "RIGHT", desc = false, money = true },
  { key = "cost",   title = "Total cost",  x = 669, w = 96,  justify = "RIGHT", desc = false, money = true },
  { key = "favor",  title = "Favor",       x = 770, w = 50,  justify = "RIGHT", desc = true  },
  { key = "per",    title = "Per favor",   x = 825, w = 92,  justify = "RIGHT", desc = false, money = true },
  { key = "rating", title = "Rating",      x = 922, w = 55,  justify = "RIGHT", desc = true  },
  { key = "have",   title = "Have",        x = 982, w = 35,  justify = "RIGHT", desc = true  },
}
local TYPES = { "Textiles", "Ore", "Herbs", "Curiosities", "Fabrics", "Ingots", "Parts" }
local RANK_ORDER = { Apprentice = 1, Journeyman = 2, Expert = 3, Artisan = 4 }
local RANK_COLOR = {
  Apprentice = "|cffffffff", Journeyman = "|cff1eff00", Expert = "|cff0070dd", Artisan = "|cffa335ee",
}

local frame, rows, headers = nil, {}, {}
-- filter: nil = all crates; { group = "type" | "prof", value = ... }
local view = { sort = "per", desc = false, search = "", filter = nil }

-- "market": objective best at full AH prices. "mine": what it costs you now - a crate you
-- own is free and materials in your bags/bank are subtracted. Per character (it's about
-- what this character owns).
local function Mode()
  if type(CrateCostCharDB) ~= "table" then CrateCostCharDB = {} end
  return CrateCostCharDB.mode == "mine" and "mine" or "market"
end

-- Target Merchant's Favor (nil = off: one crate each). Per character.
local function Target()
  if type(CrateCostCharDB) ~= "table" then CrateCostCharDB = {} end
  local t = tonumber(CrateCostCharDB.target)
  return t and t > 0 and t or nil
end

local function Owned(id)
  if not (id and C_Item and C_Item.GetItemCount) then return 0 end
  return C_Item.GetItemCount(id, true) or 0
end

local function DB()
  if type(CrateCostDB) ~= "table" then CrateCostDB = {} end
  CrateCostDB.crates = CrateCostDB.crates or {}
  CrateCostDB.ids = CrateCostDB.ids or {}
  return CrateCostDB
end

---------------------------------------------------------------------------------------------
-- Crate item IDs. The crates seen so far are 248686-248705, so a range around them is asked
-- for by ID and matched by name ("Waylaid Crate: <name>"). Uncached items arrive later via
-- GET_ITEM_INFO_RECEIVED. Hovering a crate also records its ID.
local SCAN_FROM, SCAN_TO = 248600, 248800
local refreshPending = false
local function QueueRefresh()
  if refreshPending or not (frame and frame:IsShown()) then return end
  refreshPending = true
  C_Timer.After(0.3, function()
    refreshPending = false
    if frame and frame:IsShown() then ns.RefreshWindow() end
  end)
end

local function Record(id, name)
  local crate = type(name) == "string" and name:match("^Waylaid Crate:%s*(.+)$")
  if crate and DB().ids[crate] ~= id then
    DB().ids[crate] = id
    ns.InvalidateCrates()
    QueueRefresh()
  end
end

local function ItemName(id)
  if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
  return GetItemInfo and (GetItemInfo(id))
end

-- force: the Refresh button. At login the scan is skipped once every crate's ID is saved,
-- so it doesn't ask the server about 200 items (and field 200 replies) each session.
local function ScanIDs(force)
  if not force then
    local ids, missing = DB().ids, false
    for _, c in ipairs(ns.Crates) do
      if not (ids[c[1]] or ns.CrateIDs[c[1]]) then missing = true break end
    end
    if not missing then return end
  end
  for id = SCAN_FROM, SCAN_TO do
    local name = ItemName(id)
    if name then
      Record(id, name)
    elseif C_Item and C_Item.RequestLoadItemDataByID then
      C_Item.RequestLoadItemDataByID(id)
    end
  end
end

local events = CreateFrame("Frame")
local function Valid(e) return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e) end
for _, e in ipairs({ "PLAYER_LOGIN", "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED" }) do
  if Valid(e) then events:RegisterEvent(e) end
end
events:SetScript("OnEvent", function(_, event, id, ok)
  if event == "PLAYER_LOGIN" then
    ScanIDs()
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    if ok ~= false and type(id) == "number" and id >= SCAN_FROM and id <= SCAN_TO then
      Record(id, ItemName(id))
    end
  else
    QueueRefresh()
  end
end)

---------------------------------------------------------------------------------------------
-- Live amounts from hovered tooltips win over the guide's.
-- The crates themselves (names, bundles, item IDs, favor) only change when a hovered crate
-- shows new amounts or a new ID turns up, so the list is built once and kept. Prices and
-- what you own are worked out again on each refresh (Evaluate), into the same tables.
local crateList

function ns.InvalidateCrates()
  crateList = nil
  if ns.InvalidateRatings then ns.InvalidateRatings() end
end

local function CrateList()
  if crateList then return crateList end
  local db = DB()
  local list, seen = {}, {}
  local function add(name, bundles, live)
    local rank, kind = ns.ParseCrate("Waylaid Crate: " .. name)
    local s = db.crates[name]
    list[#list + 1] = { name = name, rank = rank, kind = kind, bundles = bundles, live = live,
                        id = (s and s.id) or db.ids[name] or ns.CrateIDs[name],
                        favor = ns.FavorFor(rank, kind),
                        prices = {}, owned = {}, allowed = {}, req = {}, units = {} }
    seen[name] = true
  end
  for _, c in ipairs(ns.Crates) do
    local s = db.crates[c[1]]
    if s and #s > 0 then add(c[1], s, true) else add(c[1], c[2], false) end
  end
  for name, s in pairs(db.crates) do
    if not seen[name] and #s > 0 then add(name, s, true) end
  end
  crateList = list
  return list
end

local function Evaluate(c, mine)
  c.have = c.id and Owned(c.id) or nil
  -- crates needed to reach the target (one without a target, or when favor is unknown)
  local target = Target()
  c.n = (target and c.favor) and math.ceil(target / c.favor) or 1
  c.nUnknown = target and not c.favor
  wipe(c.prices) wipe(c.owned) wipe(c.allowed) wipe(c.req) wipe(c.units)
  c.best = nil
  local prof = view.filter and view.filter.group == "prof" and view.filter.value
  for i, b in ipairs(c.bundles) do
    c.allowed[i] = not prof or ns.MatProf[b[1]] == prof
    local id = ns.ItemIDs[b[1]]
    local unit = id and ns.Price(id)
    c.req[i] = b[2] * c.n
    local need = c.req[i]
    if mine then
      c.owned[i] = Owned(id)
      need = math.max(0, c.req[i] - c.owned[i])
    end
    local total = need == 0 and 0 or (unit and unit * need)
    c.prices[i] = total
    c.units[i] = unit
    if c.allowed[i] and total and (not c.best or total < c.prices[c.best]) then c.best = i end
  end
  c.crate = c.id and ns.Price(c.id)
  c.crateNeed = mine and math.max(0, c.n - (c.have or 0)) or c.n
  c.ownCrate = mine and c.crateNeed == 0
  local crateCost = c.crateNeed == 0 and 0 or (c.crate and c.crate * c.crateNeed)
  c.crateCost = crateCost
  c.crateUnknown = crateCost == nil
  local bundle = c.best and c.prices[c.best]
  c.bundleCost = bundle
  c.cost = bundle and (bundle + (crateCost or 0))
  c.per = c.cost and c.favor and c.cost / (c.favor * c.n)
  c.bestName = c.best and c.bundles[c.best][1]
end

---------------------------------------------------------------------------------------------
-- Rating: how good a crate's Merchant's Favor price is next to every other crate's.
-- Market cost per favor p = (crate AH price + cheapest bundle) / favor, for each crate with
-- a known favor and a priced bundle. Each crate is rated by how many times the cheapest
-- favor it costs (ratio = p / best p), in four tiers with fixed, distinct colours:
--   Great  up to 1.25x the cheapest   (blue)
--   Good   up to 1.75x                (yellow)
--   Fair   up to 3x                   (orange)
--   Poor   over 3x                    (red)
-- Tiers by ratio (not by spread between best and worst) keep each tier tight: one very
-- expensive crate can't drag mid-priced crates up a tier. Each tier's top is about 1.4-1.7x
-- its bottom, so crates sharing a label cost roughly the same per favor.
-- Best and Worst are kept for the single cheapest and dearest crate, plus any within
-- EXTREME_MARGIN copper per favor of them (a near-tie shouldn't lose the label).
local TIERS = {
  { 1.25,      "Great", "|cff4da6ff" },
  { 1.75,      "Good",  "|cffffe14d" },
  { 3,         "Fair",  "|cffff9426" },
  { math.huge, "Poor",  "|cffff3b3b" },
}
local EXTREME_MARGIN = 10
local BEST = { "Best", "|cffc77dff" }     -- purple, like an epic item
local WORST = { "Worst", "|cffb3122e" }   -- deep crimson, darker than Poor

-- Cached: one crate tooltip asks twice (title + detail line), and the game re-runs item
-- tooltips while you hover. Dropped when crate data changes (ns.InvalidateRatings) and
-- after RATING_TTL seconds so new Auctionator prices come through.
local RATING_TTL = 5
local ratingCache, ratingTime

function ns.InvalidateRatings() ratingCache = nil end

function ns.CrateRatings()
  if ratingCache and GetTime() - ratingTime < RATING_TTL then return ratingCache end
  local rated = {}
  for _, c in ipairs(CrateList()) do
    local favor = c.favor
    local bundle
    for _, b in ipairs(c.bundles) do
      local id = ns.ItemIDs[b[1]]
      local unit = id and ns.Price(id)
      if unit and (not bundle or unit * b[2] < bundle) then bundle = unit * b[2] end
    end
    if favor and bundle then
      local crate = c.id and ns.Price(c.id)
      rated[#rated + 1] = { name = c.name, per = (bundle + (crate or 0)) / favor, noCrate = crate == nil }
    end
  end
  table.sort(rated, function(a, b) return a.per < b.per end)
  local out = {}
  local best = rated[1] and rated[1].per
  local worst = rated[#rated] and rated[#rated].per
  for i, r in ipairs(rated) do
    r.rank, r.total = i, #rated
    r.ratio = r.per / best
    if r.per - best <= EXTREME_MARGIN then
      r.label, r.color = BEST[1], BEST[2]
    elseif #rated > 1 and worst - r.per <= EXTREME_MARGIN then
      r.label, r.color = WORST[1], WORST[2]
    else
      for _, t in ipairs(TIERS) do
        if r.ratio <= t[1] then r.label, r.color = t[2], t[3] break end
      end
    end
    out[r.name] = r
  end
  ratingCache, ratingTime = out, GetTime()
  return out
end

-- Tier colour and label. Blue for the best rather than green, so it doesn't look like the
-- game's own green tooltip text.
function ns.RatingText(r)
  return r.color, r.label
end

-- Two tooltip lines for crate `name`. Returns true if it had a rating.
-- The label for the tooltip's title row ("Great", coloured), or nil if the crate isn't rated.
function ns.RatingTitle(name)
  local r = ns.CrateRatings()[name]
  if not r then return nil end
  local color, label = ns.RatingText(r)
  return color .. label .. "|r"
end

-- Puts the label right under the crate's name, bigger than the title and outlined.
-- A tooltip line can only have one font size, so the title gets blank rows added below the
-- name to make room, and our own font string sits in that gap. It's hidden again when the
-- tooltip is cleared or hidden (the game resets the title text itself).
local TITLE_GROW = 8
local labels = {}   -- tooltip -> its rating font string
local function Restore(tooltip)
  local l = labels[tooltip]
  if l then l:Hide() end
end

function ns.SetTitleRating(tooltip, name)
  local tn = tooltip.GetName and tooltip:GetName()
  local left = tn and _G[tn .. "TextLeft1"]
  local text = ns.RatingTitle(name)
  local title = left and left:GetText()
  if not (text and type(title) == "string") then return false end
  local font, size = left:GetFont()
  if not (font and size) then return false end

  local l = labels[tooltip]
  if not l then
    l = tooltip:CreateFontString(nil, "OVERLAY")
    labels[tooltip] = l
    pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", Restore)
    pcall(tooltip.HookScript, tooltip, "OnHide", Restore)
  end
  if l:IsShown() then return true end   -- already placed on this tooltip
  l:SetFont(font, size + TITLE_GROW, "OUTLINE")

  -- enough blank title rows for the bigger text (a row is about the font size plus spacing)
  local rows = math.ceil((size + TITLE_GROW + 2) / (size + 2))
  left:SetText(title .. string.rep("\n ", rows))
  l:ClearAllPoints()
  l:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, 1)
  l:SetText(text)
  l:Show()
  return true
end

-- After the tooltip is shown (widths known): slide the label right so it ends where the
-- bundle prices end, i.e. it sits in the gap under the name, above the price column.
-- `edge` is the price column's anchor region (the bundle line); nil = the tooltip's text edge.
local EDGE_PAD = 10
function ns.AlignTitleRating(tooltip, edge)
  local l = labels[tooltip]
  if not (l and l:IsShown()) then return end
  local tn = tooltip:GetName()
  local left = tn and _G[tn .. "TextLeft1"]
  local right = edge and edge:GetRight() or (tooltip:GetRight() and tooltip:GetRight() - EDGE_PAD)
  local x0 = left and left:GetLeft()
  if not (right and x0) then return end
  l:ClearAllPoints()
  l:SetPoint("BOTTOMRIGHT", left, "BOTTOMLEFT", right - x0, 1)
end

-- The detail line under the favor line (the label itself sits above the prices).
function ns.AddRatingLines(tooltip, name)
  local r = ns.CrateRatings()[name]
  if not r then
    tooltip:AddDoubleLine("Rating", "not rated (no price or favor yet)", 0.4, 0.8, 1, 0.5, 0.5, 0.5)
    return false
  end
  local how = r.rank == 1 and "cheapest favor of all crates"
    or string.format("%.1fx the cheapest favor", r.ratio)
  tooltip:AddDoubleLine(string.format("#%d of %d crates", r.rank, r.total),
    ns.Money(math.floor(r.per + 0.5)) .. " per favor, " .. how
    .. (r.noCrate and " (crate not priced)" or ""), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
  return true
end

local function Matches(c)
  local f = view.filter
  if f and f.group == "type" and c.kind ~= f.value then return false end
  if f and f.group == "prof" then
    local any = false
    for i in ipairs(c.bundles) do any = any or c.allowed[i] end
    if not any then return false end
  end
  local q = view.search
  if q == "" then return true end
  if c.name:lower():find(q, 1, true) then return true end
  for _, b in ipairs(c.bundles) do
    if b[1]:lower():find(q, 1, true) then return true end
  end
  return false
end

-- Sort value per column; nil always goes last whichever direction.
local function SortValue(c, key)
  if key == "name" then return (RANK_ORDER[c.rank] or 9) * 1000 end
  if key == "best" then return c.bestName and c.bestName:lower() end
  if key == "have" then return c.have or 0 end
  if key == "bundle" then return c.bundleCost end
  if key == "crate" then return c.crateCost end
  if key == "rating" then return c.rating and -c.rating.ratio end   -- higher = better
  return c[key]
end

local function Compare(a, b)
  local va, vb = SortValue(a, view.sort), SortValue(b, view.sort)
  if va == nil and vb ~= nil then return false end
  if vb == nil and va ~= nil then return true end
  if va ~= nil and va ~= vb then
    if view.desc then return va > vb end
    return va < vb
  end
  -- ties: cheapest per favor, then name
  if view.sort ~= "per" and a.per ~= b.per then
    if a.per == nil then return false end
    if b.per == nil then return true end
    return a.per < b.per
  end
  if view.desc and view.sort == "name" then return a.name > b.name end
  return a.name < b.name
end

---------------------------------------------------------------------------------------------
local function ShowRowTooltip(row)
  local c = row.crate
  if not c then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine((RANK_COLOR[c.rank] or "") .. "Waylaid Crate: " .. c.name .. "|r")
  ns.SetTitleRating(GameTooltip, c.name)
  GameTooltip:AddDoubleLine("Crate on the AH", c.crate and ns.Money(c.crate)
    or "|cff808080" .. (c.id and "no price" or "item not found yet") .. "|r", 0.4, 0.8, 1, 1, 1, 1)
  if Target() then
    GameTooltip:AddLine(c.nUnknown and "Favor unknown: priced for 1 crate."
      or string.format("%d crate%s for %d favor (target %d)", c.n, c.n == 1 and "" or "s",
        c.n * c.favor, Target()), 1, 0.82, 0)
  end
  if c.have and c.have > 0 and Mode() == "mine" then
    GameTooltip:AddLine("You own " .. c.have .. ": " .. (c.ownCrate and "no crates to buy."
      or ("buy " .. c.crateNeed .. ".")), 0.25, 1, 0.25)
  end
  GameTooltip:AddLine(" ")
  -- best first, then cheapest first, unpriced last
  local order = {}
  for i in ipairs(c.bundles) do order[#order + 1] = i end
  table.sort(order, function(x, y)
    if x == c.best or y == c.best then return x == c.best end
    local px, py = c.prices[x], c.prices[y]
    if px and py and px ~= py then return px < py end
    if (px ~= nil) ~= (py ~= nil) then return px ~= nil end
    return x < y
  end)
  for _, i in ipairs(order) do
    local b = c.bundles[i]
    local label = c.req[i] .. " " .. b[1]
    if c.owned[i] and c.owned[i] > 0 then
      label = label .. "  |cff40ff40(have " .. math.min(c.owned[i], c.req[i]) .. ")|r"
    end
    local val = c.prices[i] and ns.Money(c.prices[i]) or "|cff808080no price|r"
    if i == c.best then
      GameTooltip:AddDoubleLine(ns.BEST .. label .. "|r", ns.BEST .. val .. "|r")
    elseif not c.allowed[i] then
      GameTooltip:AddDoubleLine(label, val, 0.45, 0.45, 0.45, 0.45, 0.45, 0.45)
    else
      GameTooltip:AddDoubleLine(label, val, 1, 1, 1, 1, 1, 1)
    end
  end
  GameTooltip:AddLine(" ")
  ns.AddRatingLines(GameTooltip, c.name)
  if not c.live then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Amounts from the beta guide. Hover this crate in your bags to use its real amounts.",
      0.6, 0.6, 0.6, true)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Shift-click: search in Auctionator (bundle columns = material, rest = crate)",
    0.6, 0.6, 0.6, true)
  GameTooltip:Show()
  ns.AlignTitleRating(GameTooltip)   -- over the prices on the right
end

-- Shift-click sends a link through the game's insert-link path, the same as shift-clicking
-- a bag item: Auctionator's Shopping tab hooks it and searches (or it links into an open
-- chat box). Falls back to the plain name if the item isn't cached yet.
local MATERIAL_COLS = { best = true, bundle = true }
local function ColumnAtCursor(row)
  local left = row:GetLeft()
  if not left then return end
  local x = GetCursorPosition() / row:GetEffectiveScale() - left
  for _, col in ipairs(COLS) do
    if x >= col.x - 10 and x < col.x - 10 + col.w then return col.key end
  end
end

local function SearchAuctionator(itemID, name)
  local link = itemID and C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(itemID))
  local text = link or name
  local shop = AuctionatorShoppingFrame and AuctionatorShoppingFrame:IsVisible()
  if Auctionator and Auctionator.Utilities and Auctionator.Utilities.InsertLink then
    Auctionator.Utilities.InsertLink(text)
  elseif ChatFrameUtil and ChatFrameUtil.InsertLink then
    ChatFrameUtil.InsertLink(text)
  end
  if not shop and not GetCurrentKeyBoardFocus() then
    ns.Print("open the Auctionator Shopping tab at the AH, then shift-click again.")
  end
end

local function RowClick(row)
  if not IsShiftKeyDown() or not row.crate then return end
  local c = row.crate
  if MATERIAL_COLS[ColumnAtCursor(row)] and c.best then
    local mat = c.bundles[c.best][1]
    SearchAuctionator(ns.ItemIDs[mat], mat)
  else
    SearchAuctionator(c.id, "Waylaid Crate: " .. c.name)
  end
end

local function MakeRow(i)
  local row = CreateFrame("Button", nil, frame)
  row:SetSize(WIDTH - 20, ROW_H)
  row:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -TOP - (i - 1) * ROW_H)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)
  if i % 2 == 0 then
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.03)
  end
  row.cells, row.money = {}, {}
  local function Cell(x, w)
    local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", row, "LEFT", x, 0)
    fs:SetWidth(w)
    fs:SetJustifyH("RIGHT")
    fs:SetWordWrap(false)
    return fs
  end
  for _, col in ipairs(COLS) do
    local fs = Cell(col.x - 10, col.w)
    fs:SetJustifyH(col.justify)
    row.cells[col.key] = fs
    if col.money then
      local x = col.x - 10
      row.money[col.key] = {
        g = Cell(x, col.w - SUB * 2),
        s = Cell(x + col.w - SUB * 2, SUB),
        c = Cell(x + col.w - SUB, SUB),
      }
    end
    if col.key == "best" then
      -- three aligned parts, no headers: material | amount | unit price (g/s/c slots)
      local x = col.x - 10
      row.bestName = Cell(x, 120)
      row.bestName:SetJustifyH("LEFT")
      row.bestQty = Cell(x + 120, 36)
      row.cells.unit = Cell(x + 160, 80)
      row.money.unit = { g = Cell(x + 160, 24), s = Cell(x + 184, SUB), c = Cell(x + 212, SUB) }
    end
  end
  row:SetScript("OnClick", RowClick)

  -- [+cart]: the red panel button with a plus and the cart icon side by side. The cart is the
  -- game's Trading Post atlas if this client has it, else the addon's own cart.tga.
  local add = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  add:SetSize(34, 17)
  add:SetPoint("LEFT", row, "LEFT", WIDTH - 20 - 38, 0)
  add:SetText("")
  local plus = add:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  plus:SetPoint("LEFT", 6, 0)
  plus:SetText("+")
  local icon = add:CreateTexture(nil, "OVERLAY")
  icon:SetSize(13, 13)
  icon:SetPoint("LEFT", plus, "RIGHT", 2, 0)
  if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(CART_ATLAS) then
    icon:SetAtlas(CART_ATLAS)
  else
    icon:SetTexture(CART_FILE)
  end
  add:SetScript("OnClick", function() ns.AddRowToCart(row.crate) end)
  add:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Add to cart", 1, 1, 1)
    GameTooltip:AddLine(Mode() == "mine"
      and "The crates you still need and the best bundle's missing materials (for the target, if set)."
      or "The crate(s) and the best bundle's materials (for the target, if set).", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  add:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:SetScript("OnEnter", ShowRowTooltip)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = row
  return row
end

-- A money cell: amount in its g/s/c slots, or plain text (owned, ?) across the column.
local function SetMoney(row, key, copper, color, text)
  local m = row.money[key]
  if copper then
    local g, s, c = ns.MoneyParts(copper)
    color = color or ""
    m.g:SetText(g and (color .. g .. "|r") or "")
    m.s:SetText(s and (color .. s .. "|r") or "")
    m.c:SetText(c and (color .. c .. "|r") or "")
    row.cells[key]:SetText("")
  else
    m.g:SetText("") m.s:SetText("") m.c:SetText("")
    row.cells[key]:SetText(text or "")
  end
end

local function UpdateHeaders()
  for _, h in ipairs(headers) do
    local arrow = ""
    if h.col.key == view.sort then arrow = view.desc and " v" or " ^" end
    h.text:SetText((h.col.key == view.sort and "|cffffffff" or "") .. h.col.title .. arrow
      .. (h.col.key == view.sort and "|r" or ""))
  end
  if frame.filterBtn then
    local f = view.filter
    frame.filterBtn.text:SetText(f and f.value or "All crates")
  end
end

function ns.RefreshWindow()
  if not frame then return end
  local mine = Mode() == "mine"
  local all, list = CrateList(), {}
  local ratings = ns.CrateRatings()
  for _, c in ipairs(all) do
    Evaluate(c, mine)
    c.rating = ratings[c.name]
    if Matches(c) then list[#list + 1] = c end
  end
  table.sort(list, Compare)

  local icon = ns.FavorIcon()
  local anyGuide = false
  for i, c in ipairs(list) do
    local row = rows[i] or MakeRow(i)
    row.crate = c
    local cl = row.cells
    cl.name:SetText((RANK_COLOR[c.rank] or "") .. c.name .. "|r" .. (c.live and "" or " |cff808080*|r"))
    if not c.live then anyGuide = true end
    if c.best then
      local b = c.bundles[c.best]
      local own = mine and c.owned[c.best] or 0
      -- material | x20 (My cost: 12/20 owned) | unit price, each part in its own aligned slot
      cl.best:SetText("")
      row.bestName:SetText(ns.BEST .. b[1] .. "|r")
      local req = c.req[c.best]
      row.bestQty:SetText(own > 0 and ("|cff40ff40" .. math.min(own, req) .. "/" .. req .. "|r")
        or ("|cffaaaaaax" .. req .. "|r"))
      SetMoney(row, "unit", c.units[c.best], "|cffffffff", "|cff808080?|r")
      -- orange = crate price unknown, so the total is the bundle alone
      SetMoney(row, "bundle", c.bundleCost)
      SetMoney(row, "cost", c.cost, c.crateUnknown and "|cffff9933" or nil)
    else
      cl.best:SetText("|cff808080no prices|r")
      row.bestName:SetText("")
      row.bestQty:SetText("")
      SetMoney(row, "unit", nil, nil, "")
      SetMoney(row, "bundle", nil, nil, "")
      SetMoney(row, "cost", nil, nil, "")
    end
    if c.ownCrate then
      SetMoney(row, "crate", nil, nil, "|cff40ff40owned|r")
    else
      SetMoney(row, "crate", c.crateCost, nil, "|cff808080?|r")
    end
    cl.n:SetText(c.nUnknown and "|cff808080?|r" or ((c.n > 1 and "|cffffffff" or "|cff808080") .. c.n .. "|r"))
    cl.favor:SetText(c.favor and (c.favor .. icon) or "|cff808080?|r")
    SetMoney(row, "per", c.per, ns.BEST, "")
    if c.rating then
      local color, label = ns.RatingText(c.rating)
      cl.rating:SetText(color .. label .. "|r")
    else
      cl.rating:SetText("|cff808080?|r")
    end
    cl.have:SetText(c.have and c.have > 0 and c.have or "")
    row:Show()
  end
  for i = #list + 1, #rows do rows[i]:Hide() end

  frame:SetHeight(TOP + math.max(#all, 1) * ROW_H + 30)
  frame.empty:SetShown(#list == 0)
  frame.mode:SetText(mine and "View: My cost" or "View: Market")
  frame.footer:SetText("|cff808080" .. (mine
      and "My cost: owned crates are free, materials you have (bags + bank) are subtracted."
      or "Market: crate + cheapest bundle at full Auctionator prices.")
    .. "  |cffff9933Orange|r|cff808080 total = crate not priced yet."
    .. (anyGuide and "  * = guide amounts until you hover that crate." or "") .. "|r")
  UpdateHeaders()
end

local function Build()
  frame = CreateFrame("Frame", "CrateCostFrame", UIParent, "BackdropTemplate")
  frame:SetSize(WIDTH, 400)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)   -- clicking it brings it in front of the Merchant list
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
  })
  frame:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
  frame:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetScript("OnShow", ns.RefreshWindow)
  tinsert(UISpecialFrames, "CrateCostFrame")

  local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("Waylaid Crates - cheapest Merchant's Favor")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  -- hide directly: the template's HideUIPanel path doesn't close unmanaged frames on Forever
  close:SetScript("OnClick", function() frame:Hide() end)
  close:SetPoint("TOPRIGHT", 2, 2)

  local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  refresh:SetSize(70, 20)
  refresh:SetPoint("TOPRIGHT", -30, -6)
  refresh:SetText("Refresh")
  refresh:SetScript("OnClick", function() ns.InvalidateCrates() ScanIDs(true) ns.RefreshWindow() end)

  local mode = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  mode:SetSize(110, 20)
  mode:SetPoint("RIGHT", refresh, "LEFT", -4, 0)
  mode:SetScript("OnClick", function()
    Mode()
    CrateCostCharDB.mode = Mode() == "mine" and "market" or "mine"
    ns.RefreshWindow()
  end)
  mode:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Market: objective best at full AH prices.", 1, 1, 1)
    GameTooltip:AddLine("My cost: owned crates are free; materials you already have are subtracted.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  mode:SetScript("OnLeave", function() GameTooltip:Hide() end)
  frame.mode = mode

  local cartBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  cartBtn:SetSize(80, 20)
  cartBtn:SetPoint("RIGHT", mode, "LEFT", -4, 0)
  cartBtn:SetScript("OnClick", function() ns.ShowCart() end)
  frame.cartBtn = cartBtn
  ns.OnCartChanged()

  local recipes = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  recipes:SetSize(80, 20)
  recipes:SetPoint("RIGHT", cartBtn, "LEFT", -4, 0)
  recipes:SetText("Merchant")
  recipes:SetScript("OnClick", function() ns.ToggleRecipes() end)
  recipes:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Every recipe sold for Merchant's Favor", 1, 1, 1)
    GameTooltip:Show()
  end)
  recipes:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- search box
  local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  search:SetSize(150, 20)
  search:SetPoint("TOPLEFT", 18, -34)
  search:SetAutoFocus(false)
  search:SetMaxLetters(40)
  local hint = search:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("LEFT", 2, 0)
  hint:SetText("Search crate or material")
  local function OnSearch(self)
    local t = self:GetText() or ""
    hint:SetShown(t == "" and not self:HasFocus())
    t = t:lower():match("^%s*(.-)%s*$")
    if t ~= view.search then
      view.search = t
      ns.RefreshWindow()
    end
  end
  search:SetScript("OnTextChanged", OnSearch)
  search:SetScript("OnEditFocusGained", function() hint:Hide() end)
  search:SetScript("OnEditFocusLost", OnSearch)
  search:SetScript("OnEscapePressed", search.ClearFocus)
  search:SetScript("OnEnterPressed", search.ClearFocus)

  -- filter dropdown: crate type, or the profession a material comes from. Own widget
  -- because UIDropDownMenu isn't reliable on Forever.
  local fb = CreateFrame("Button", nil, frame, "BackdropTemplate")
  fb:SetSize(170, 20)
  fb:SetPoint("LEFT", search, "RIGHT", 14, 0)
  fb:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  fb:SetBackdropColor(0.12, 0.12, 0.15, 1)
  fb:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
  fb.text = fb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  fb.text:SetPoint("LEFT", 6, 0)
  fb.text:SetPoint("RIGHT", -18, 0)
  fb.text:SetJustifyH("LEFT")
  local arrow = fb:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  arrow:SetPoint("RIGHT", -6, 0)
  arrow:SetText("v")
  local fhl = fb:CreateTexture(nil, "HIGHLIGHT")
  fhl:SetAllPoints()
  fhl:SetColorTexture(1, 1, 1, 0.06)
  frame.filterBtn = fb

  local menu = CreateFrame("Frame", nil, fb, "BackdropTemplate")
  menu:SetPoint("TOPLEFT", fb, "BOTTOMLEFT", 0, -2)
  menu:SetFrameStrata("DIALOG")
  menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  menu:SetBackdropColor(0.08, 0.08, 0.1, 0.98)
  menu:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
  menu:EnableMouse(true)
  menu:Hide()
  local my = -4
  local function Heading(text)
    local h = menu:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    h:SetPoint("TOPLEFT", 8, my)
    h:SetText(text)
    my = my - 16
  end
  local function Item(label, filter)
    local it = CreateFrame("Button", nil, menu)
    it:SetSize(166, 16)
    it:SetPoint("TOPLEFT", 2, my)
    local t = it:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    t:SetPoint("LEFT", 14, 0)
    t:SetText(label)
    local hl = it:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.1)
    it:SetScript("OnClick", function()
      view.filter = filter
      menu:Hide()
      ns.RefreshWindow()
    end)
    my = my - 16
  end
  Item("All crates", nil)
  my = my - 4
  Heading("Crate type")
  for _, t in ipairs(TYPES) do Item(t, { group = "type", value = t }) end
  my = my - 4
  Heading("Material from")
  for _, p in ipairs(ns.Professions) do Item(p, { group = "prof", value = p }) end
  menu:SetSize(170, -my + 4)
  fb:SetScript("OnClick", function() menu:SetShown(not menu:IsShown()) end)
  frame:HookScript("OnHide", function() menu:Hide() end)

  -- target favor: costs and the cart scale to the crates needed to reach it
  local tl = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  tl:SetPoint("LEFT", fb, "RIGHT", 16, 0)
  tl:SetText("Target favor:")
  local tb = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  tb:SetSize(50, 20)
  tb:SetPoint("LEFT", tl, "RIGHT", 8, 0)
  tb:SetAutoFocus(false)
  tb:SetNumeric(true)
  tb:SetMaxLetters(5)
  tb:SetJustifyH("CENTER")
  tb:SetText(Target() and tostring(Target()) or "")
  local tickIcon = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  tickIcon:SetPoint("LEFT", tb, "RIGHT", 4, 0)
  tickIcon:SetText(ns.FavorIcon())
  local function OnTarget(self)
    local t = tonumber(self:GetText())
    if t == 0 then t = nil end
    if t == Target() then return end
    local was = Target()
    CrateCostCharDB.target = t
    -- with a target the question is the cheapest way to reach it: sort by total cost
    if t and not was and view.sort == "per" then view.sort, view.desc = "cost", false end
    ns.RefreshWindow()
  end
  tb:SetScript("OnTextChanged", function(self) if self:HasFocus() then OnTarget(self) end end)
  tb:SetScript("OnEditFocusLost", OnTarget)
  tb:SetScript("OnEnterPressed", function(self) OnTarget(self) self:ClearFocus() end)
  tb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  tb:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Target Merchant's Favor", 1, 1, 1)
    GameTooltip:AddLine("Costs and the cart cover the crates needed to reach it. Empty = one crate each.",
      0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  tb:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- sortable headers
  for _, col in ipairs(COLS) do
    local h = CreateFrame("Button", nil, frame)
    h:SetSize(col.w, 16)
    h:SetPoint("TOPLEFT", frame, "TOPLEFT", col.x + 10 - 10, -64)
    h.col = col
    h.text = h:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    h.text:SetAllPoints()
    h.text:SetJustifyH(col.justify)
    local hl = h:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    h:SetScript("OnClick", function()
      if view.sort == col.key then
        view.desc = not view.desc
      else
        view.sort, view.desc = col.key, col.desc or false
      end
      ns.RefreshWindow()
    end)
    headers[#headers + 1] = h
  end

  frame.empty = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  frame.empty:SetPoint("TOP", 0, -TOP - 10)
  frame.empty:SetText("No crates match.")

  frame.footer = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  frame.footer:SetPoint("BOTTOMLEFT", 12, 10)
end

function ns.OnCartChanged()
  if frame and frame.cartBtn then frame.cartBtn:SetText("Cart (" .. ns.CartCount() .. ")") end
  if ns.RefreshCart then ns.RefreshCart() end
end

-- c is a row's crate as Evaluate left it (best bundle, owned counts for My cost).
function ns.AddRowToCart(c)
  if not c then return end
  if not c.best then
    ns.Print("no priced bundle for " .. c.name .. " - nothing added.")
    return
  end
  local mine = Mode() == "mine"
  local items = {}
  if c.crateNeed > 0 then
    items[#items + 1] = { id = c.id, name = "Waylaid Crate: " .. c.name, qty = c.crateNeed }
  end
  local b = c.bundles[c.best]
  local qty = c.req[c.best]
  if mine then qty = math.max(0, qty - (c.owned[c.best] or 0)) end
  items[#items + 1] = { id = ns.ItemIDs[b[1]], name = b[1], qty = qty }
  local n = ns.CartAdd(items)
  if n == 0 then
    ns.Print("you already have everything for " .. c.name .. ".")
  else
    ns.Print(string.format("added %s%s to the cart.",
      c.crateNeed > 0 and (c.crateNeed .. " crate" .. (c.crateNeed == 1 and "" or "s") .. " + ") or "",
      qty > 0 and (qty .. " " .. b[1]) or "no materials (you have them)"))
  end
end

function ns.ToggleWindow()
  if not frame then Build() frame:Hide() end
  frame:SetShown(not frame:IsShown())
end
