local ADDON, ns = ...

-- Waylaid Crate tooltips list their bundles as "- 20 Wool Cloth" lines (usually inside the
-- one wrapped "Use:" line). This appends the Auctionator value to each bundle line, marks the
-- cheapest one green, and adds a Merchant's Favor line with the cost per favor.

local CALLER = "CrateCost"
local RANKS = { "Apprentice", "Journeyman", "Expert", "Artisan" }

local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
local GOLD, SILVER, COPPER = COIN:format("Gold"), COIN:format("Silver"), COIN:format("Copper")
-- Money split into gold / silver / copper strings (nil = leave that slot empty), so callers
-- can put each unit in its own right-aligned column. Copper is always shown, and a unit after
-- a larger one is zero-padded ("1g 05s 00c"), so no slot is ever left floating.
local function MoneyParts(copper)
  copper = math.floor(copper + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local gs = g > 0 and ((BreakUpLargeNumbers and BreakUpLargeNumbers(g) or g) .. GOLD) or nil
  local ss = (g > 0 and string.format("%02d", s) or (s > 0 and tostring(s) or nil))
  ss = ss and (ss .. SILVER)
  local cs = ((g > 0 or s > 0) and string.format("%02d", c) or tostring(c)) .. COPPER
  return gs, ss, cs
end

local function Money(copper)
  local g, s, c = MoneyParts(copper)
  local parts = {}
  if g then parts[#parts + 1] = g end
  if s then parts[#parts + 1] = s end
  parts[#parts + 1] = c
  return table.concat(parts, " ")
end

ns.MoneyParts = MoneyParts
ns.SILVER_SAMPLE, ns.COPPER_SAMPLE = "99" .. SILVER, "99" .. COPPER

-- Settings (Config.lua edits them). Account-wide: they're display preferences. Every
-- toggle defaults to on = the normal behaviour.
local DEFAULTS = { tooltip = true, sortTooltip = true, highlight = true, favorLine = true, rating = true }
function ns.Settings()
  if type(CrateCostDB) ~= "table" then CrateCostDB = {} end
  local st = CrateCostDB.settings
  if type(st) ~= "table" then st = {} CrateCostDB.settings = st end
  for k, v in pairs(DEFAULTS) do if st[k] == nil then st[k] = v end end
  CrateCostDB.minimap = CrateCostDB.minimap or { hide = false }
  return st
end
local function On(key) return ns.Settings()[key] ~= false end

local function Print(msg) print("|cffd4a017CrateCost:|r " .. msg) end

local function Strip(s)
  return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Prices are kept for a second: one crate list refresh, its ratings and a crate tooltip ask
-- for the same items many times over, and Auctionator's data doesn't move that fast.
local PRICE_TTL = 1
local priceCache, priceTime = {}, 0
local function Price(itemID)
  if not (Auctionator and Auctionator.API and Auctionator.API.v1) then return nil end
  local now = GetTime()
  if now - priceTime >= PRICE_TTL then
    wipe(priceCache)
    priceTime = now
  end
  local p = priceCache[itemID]
  if p == nil then
    local ok, v = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, CALLER, itemID)
    p = (ok and type(v) == "number" and v > 0) and v or false
    priceCache[itemID] = p
  end
  return p or nil
end

-- "Waylaid Crate: Journeyman Textiles" -> "Journeyman", "Textiles"
-- "Waylaid Crate: Earthly Expert Herbs" -> "Expert", "Herbs"
local function ParseCrate(title)
  local rest = title:match("^Waylaid Crate:%s*(.+)$")
  if not rest then return end
  -- the rating adds blank rows under the name; never let them into the crate's name
  rest = rest:match("^(.-)%s*$")
  local rank
  for _, r in ipairs(RANKS) do
    if rest:find(r, 1, true) then rank = r break end
  end
  return rank, rest:match("(%S+)%s*$"), rest
end

local function FavorFor(rank, kind)
  if not rank or not kind then return nil end
  local t = ns.CraftedKinds[kind] and ns.Favor.crafted or ns.Favor.raw
  return t[rank]
end

local function LeftLines(tooltip)
  local name = tooltip:GetName()
  local i = 1
  return function()
    local fs = name and _G[name .. "TextLeft" .. i]
    i = i + 1
    if fs and i - 1 <= tooltip:NumLines() then return fs end
  end
end

local debugNext = false

-- Merchant's Favor currency (ID from wow-professions.com's currency links). Empty string if
-- the client doesn't know it, so the text still reads fine.
local FAVOR_CURRENCY = 3402
local favorIcon
local function FavorIcon()
  if favorIcon then return favorIcon end
  local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
    and C_CurrencyInfo.GetCurrencyInfo(FAVOR_CURRENCY)
  local file = info and (info.iconFileID or info.icon)
  if not file then return "" end
  favorIcon = " |T" .. file .. ":0:0:0:0|t"
  return favorIcon
end

local GAP, PAD, SUBGAP = 14, 10, 3
-- gold: the bundle text is already green, so the best pick needs a different colour
local BEST = "|cffffd100"
local columns, widened = {}, {}

local measure
local function MeasureWidth(fs, text)
  if not measure then
    measure = UIParent:CreateFontString(nil, "BACKGROUND")
    measure:Hide()
  end
  local font, size, flags = fs:GetFont()
  if font then measure:SetFont(font, size, flags) end
  measure:SetText(text)
  return (measure.GetUnboundedStringWidth and measure:GetUnboundedStringWidth()) or measure:GetStringWidth()
end

-- One reusable one-line price label per (tooltip, index).
local function Label(tooltip, i, fs)
  columns[tooltip] = columns[tooltip] or {}
  local lbl = columns[tooltip][i]
  if not lbl then
    lbl = tooltip:CreateFontString(nil, "ARTWORK")
    lbl:SetJustifyH("RIGHT")
    lbl:SetWordWrap(false)
    columns[tooltip][i] = lbl
  end
  local font, size, flags = fs:GetFont()
  if font then lbl:SetFont(font, size, flags) end
  return lbl
end

-- Height of one text row in fs, spacing included. Only valid after the tooltip laid out.
local function RowStep(fs)
  local sp = fs.GetSpacing and fs:GetSpacing() or 0
  local n = fs.GetNumLines and fs:GetNumLines()
  local h = fs:GetStringHeight()
  if n and n > 0 and h and h > 0 then return (h + sp) / n end
  local _, size = fs:GetFont()
  return (size or 12) + sp
end

local function ClearColumns(tooltip)
  if columns[tooltip] then
    for _, col in ipairs(columns[tooltip]) do col:Hide() end
  end
  if widened[tooltip] then
    widened[tooltip] = nil
    tooltip:SetMinimumWidth(0)
  end
end

local function Process(tooltip, itemID)
  ClearColumns(tooltip)
  local name = tooltip:GetName()
  local title = name and _G[name .. "TextLeft1"]
  local titleText = title and title:GetText()
  if type(titleText) ~= "string" then return end
  local rank, kind, crateName = ParseCrate(Strip(titleText))
  if not rank then return end

  if debugNext then
    debugNext = false
    for fs in LeftLines(tooltip) do
      Print("line: " .. (fs:GetText() or "nil"):gsub("\n", "\\n"):gsub("|", "||"))
    end
  end

  -- Pass 1: find every bundle and its price, so the cheapest can be marked.
  local bundles, best = {}, nil
  for fs in LeftLines(tooltip) do
    local text = fs:GetText()
    if type(text) == "string" and text:find("%-%s*%d+%s") and not text:find("|TInterface\\MoneyFrame", 1, true) then
      for seg in text:gmatch("[^\n]+") do
        local qty, item = Strip(seg):match("^%s*%-%s*(%d+)%s+(.-)%s*$")
        if qty then
          local id = ns.ItemIDs[item]
          local unit = id and Price(id)
          local b = { item = item, qty = tonumber(qty), id = id, total = unit and unit * tonumber(qty) }
          bundles[#bundles + 1] = b
          if b.total and (not best or b.total < best.total) then best = b end
        end
      end
    end
  end
  if #bundles == 0 then return end

  -- Remember the live amounts (and the crate's item ID) for the /crates window.
  if type(CrateCostDB) ~= "table" then CrateCostDB = {} end
  CrateCostDB.crates = CrateCostDB.crates or {}
  -- only write (and drop the cached ratings) when something actually changed: the game
  -- re-runs a hovered item's tooltip over and over
  local old = CrateCostDB.crates[crateName]
  local same = old and old.id == itemID and #old == #bundles
  if same then
    for i, b in ipairs(bundles) do
      if not old[i] or old[i][1] ~= b.item or old[i][2] ~= b.qty then same = false break end
    end
  end
  if not same then
    local saved = { id = itemID }
    for i, b in ipairs(bundles) do saved[i] = { b.item, b.qty } end
    CrateCostDB.crates[crateName] = saved
    if ns.InvalidateCrates then ns.InvalidateCrates() end
  end
  if not On("tooltip") then return end
  if not On("highlight") then best = nil end

  -- Pass 2: a one-line price label per bundle, right-aligned on that bundle's row.
  -- Appending to the text let word wrap push prices onto their own rows. The bundles are
  -- the last rows of their line, so each label sits k rows up from the line's bottom,
  -- k = rows below it. (One overlay holding all prices drifted: its two anchors fought.)
  local n, segWidth, goldWidth, placed = 0, 0, 0, {}
  for fs in LeftLines(tooltip) do
    local text = fs:GetText()
    if type(text) == "string" and text:find("%-%s*%d+%s") and not text:find("|TInterface\\MoneyFrame", 1, true) then
      local out, mine = {}, {}
      for seg in (text .. "\n"):gmatch("([^\n]*)\n") do
        if Strip(seg):match("^%s*%-%s*%d+%s+.-%s*$") then
          n = n + 1
          local b = bundles[n]
          local m = { seg = #out + 1, color = b == best and BEST or "|cffffffff", total = b.total }
          if not b.id then
            m.note = "|cff808080unknown item|r"
          elseif not b.total then
            m.note = "|cff808080no price|r"
          else
            m.g, m.s, m.c = MoneyParts(b.total)
            if m.g then goldWidth = math.max(goldWidth, MeasureWidth(fs, m.g)) end
          end
          if m.note then goldWidth = math.max(goldWidth, MeasureWidth(fs, m.note) - 60) end
          mine[#mine + 1] = m
          segWidth = math.max(segWidth, MeasureWidth(fs, seg))
          -- the best bundle's own row takes the price's colour
          -- Keep trailing whitespace (the game's "\r" before our "\n") outside the colour:
          -- "\r|r\n" renders as two line breaks and pushed every row above down a line.
          if b == best then
            local core, tail = Strip(seg):match("^(.-)(%s*)$")
            seg = BEST .. core .. "|r" .. tail
          end
        end
        out[#out + 1] = seg
      end
      -- Cheapest bundle first (unpriced last): the bundle lines swap places. Each slot keeps
      -- its own trailing whitespace, so a "\r" never moves away from its "\n".
      local slots, moved = {}, {}
      local sortOn = On("sortTooltip")
      for k, m in ipairs(mine) do
        slots[k] = m.seg
        moved[k] = { m = m, core = out[m.seg]:match("^(.-)%s*$"), order = k }
      end
      table.sort(moved, function(a, b)
        if not sortOn then return a.order < b.order end
        local ta, tb = a.m.total, b.m.total
        if ta and tb and ta ~= tb then return ta < tb end
        if (ta ~= nil) ~= (tb ~= nil) then return ta ~= nil end
        return a.order < b.order
      end)
      for k, slot in ipairs(slots) do
        local tail = out[slot]:match("(%s*)$")
        moved[k].tail = tail
        moved[k].slot = slot
      end
      for _, e in ipairs(moved) do
        out[e.slot] = e.core .. e.tail
        e.m.seg = e.slot
      end
      fs:SetText(table.concat(out, "\n"))
      for _, m in ipairs(mine) do
        m.fs, m.below = fs, #out - m.seg
        placed[#placed + 1] = m
      end
    end
  end
  -- price slots: gold | silver | copper, each right-aligned at a fixed x
  local refFs = placed[1] and placed[1].fs
  local cW = refFs and MeasureWidth(refFs, ns.COPPER_SAMPLE) or 30
  local sW = refFs and MeasureWidth(refFs, ns.SILVER_SAMPLE) or 30
  if #placed > 0 then
    tooltip:SetMinimumWidth(math.ceil(segWidth + GAP + goldWidth + sW + cW + SUBGAP * 2 + PAD * 2))
    widened[tooltip] = true
  end

  -- Favor is the same whichever bundle you use.
  local favor = FavorFor(rank, kind)
  local icon = FavorIcon()
  if On("favorLine") then
    tooltip:AddLine(" ")
    if favor then
      tooltip:AddDoubleLine("Merchant's Favor", favor .. icon, 0.4, 0.8, 1, 1, 1, 1)
    else
      tooltip:AddDoubleLine("Merchant's Favor", "unknown yet", 0.4, 0.8, 1, 0.5, 0.5, 0.5)
    end
  end
  -- how this crate's favor price compares with every other crate's (Window.lua)
  -- the score sits on the title row, right of the crate's name; the detail line goes below
  if On("rating") and ns.AddRatingLines then
    ns.SetTitleRating(tooltip, crateName)
    if not On("favorLine") then tooltip:AddLine(" ") end
    ns.AddRatingLines(tooltip, crateName)
  end
  tooltip:Show()

  -- the lines have their final wrap now, so row heights are known
  local k = 0
  local function Put(m, text, x)
    if not text then return end
    k = k + 1
    local lbl = Label(tooltip, k, m.fs)
    lbl:SetText(text)
    lbl:ClearAllPoints()
    lbl:SetPoint("BOTTOMRIGHT", m.fs, "BOTTOMRIGHT", x, m.below * RowStep(m.fs))
    lbl:Show()
  end
  for _, m in ipairs(placed) do
    if m.note then
      Put(m, m.note, 0)
    else
      Put(m, m.c and (m.color .. m.c .. "|r"), 0)
      Put(m, m.s and (m.color .. m.s .. "|r"), -(cW + SUBGAP))
      Put(m, m.g and (m.color .. m.g .. "|r"), -(cW + sW + SUBGAP * 2))
    end
  end
end

local reported = false
local function Safe(tooltip, itemID)
  local ok, err = pcall(Process, tooltip, itemID)
  if not ok and not reported then
    reported = true
    Print("|cffff4040tooltip error:|r " .. tostring(err))
  end
end

-- Waylaid Crates are items 248682-248713 (Data.lua ns.CrateIDs); Window.lua scans the same
-- wider range by name in case new ones appear.
local CRATE_ID_MIN, CRATE_ID_MAX = 248600, 248800

local function ItemIDFromTooltip(tooltip)
  local _, link = tooltip:GetItem()
  return link and tonumber(link:match("item:(%d+)"))
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    -- runs for every item tooltip: leave anything outside the crates' item ID range alone
    -- before touching the tooltip (an unknown ID still goes through the title check)
    local id = data and data.id
    if id and (id < CRATE_ID_MIN or id > CRATE_ID_MAX) then return end
    Safe(tooltip, id or ItemIDFromTooltip(tooltip))
  end)
else
  for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
    pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self) Safe(self, ItemIDFromTooltip(self)) end)
  end
end

for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
  pcall(tt.HookScript, tt, "OnTooltipCleared", ClearColumns)
  pcall(tt.HookScript, tt, "OnHide", ClearColumns)
end

SLASH_CRATECOST1 = "/cratecost"
SLASH_CRATECOST2 = "/crates"
SLASH_CRATECOST3 = "/crate"
SlashCmdList.CRATECOST = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "debug" then
    debugNext = true
    Print("hover a Waylaid Crate: its tooltip lines will be printed once.")
  elseif msg == "" then
    ns.ToggleWindow()
  elseif msg == "config" or msg == "options" or msg == "settings" then
    ns.ToggleConfig()
  elseif msg == "cart" then
    ns.ShowCart()
  elseif msg == "merchant" or msg == "recipes" or msg == "recipe" then
    ns.ToggleRecipes()
  else
    Print("/crates - crate list sorted by cost per favor")
    Print("/crates merchant - everything Merchant's Favor buys")
    Print("/cratecost config - settings")
    Print("/cratecost cart - the shopping cart")
    Print("/cratecost debug - print the next crate tooltip's raw lines")
  end
end

-- shared with Window.lua
ns.Price, ns.Money, ns.FavorFor, ns.FavorIcon, ns.ParseCrate = Price, Money, FavorFor, FavorIcon, ParseCrate
ns.BEST, ns.Print = BEST, Print
