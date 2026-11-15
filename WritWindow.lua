local _, ns = ...

-- Writs: every Craftsman's Writ with what it costs to do at current Auctionator prices.
-- Cost = the writ's own AH price + the cheaper way to get the required item: buy it on the AH,
-- or craft it (reagents at Auctionator's vendor or AH price, or crafted themselves when that's
-- cheaper). Recipes come from endgametools.com via tools/writs.py; no other addon is needed.
-- Rated by cost per reputation, with the same tiers as the crates. The Sealed envelopes (a
-- random writ of a rank) are rated on their price plus the average cost to fill that rank.

local ROW_H, VISIBLE, WIDTH, TOP = 18, 24, 1194, 84
local SUB = 28
-- grouped: the writ | the route (Buy / Craft toggle: the item, total, per rep, rating)
-- | the rep target | what you have
local COLS = {
  { key = "name", title = "Writ", x = 10, ownedX = 107, w = 175, justify = "LEFT" },
  { key = "prof", title = "Profession", x = 190, ownedX = 287, w = 84, justify = "LEFT" },
  { key = "rank", title = "Rank", x = 279, ownedX = 376, w = 66, justify = "LEFT", desc = false },
  { key = "skill", title = "Skill", x = 350, ownedX = 447, w = 30, justify = "RIGHT", desc = false },
  { key = "rep", title = "Rep", x = 385, ownedX = 482, w = 30, justify = "RIGHT", desc = true },
  { key = "writ", title = "Writ cost", ownedTitle = "Who", ownedX = 10, ownedJustify = "LEFT", x = 420, w = 92, justify = "RIGHT", desc = false, money = true },
  { key = "item", title = "Buy item", craftTitle = "Craft item", x = 530, w = 92, justify = "RIGHT", desc = false, money = true },
  { key = "total", title = "Total cost", x = 627, w = 96, justify = "RIGHT", desc = false, money = true },
  { key = "per", title = "Per rep", x = 728, w = 92, justify = "RIGHT", desc = false, money = true },
  { key = "rating", title = "Rating", x = 825, w = 55, justify = "RIGHT", desc = true },
  { key = "need", title = "Writs", x = 898, w = 40, justify = "RIGHT", desc = false },
  { key = "target", title = "To target", x = 943, w = 100, justify = "RIGHT", desc = false, money = true },
  { key = "have", title = "Have", x = 1061, w = 36, justify = "RIGHT", desc = true },
  { key = "done", title = "Today", x = 1102, w = 52, justify = "CENTER", desc = true },
}
local RANKS = { "Journeyman", "Expert", "Artisan" }
local RANK_ORDER = { Journeyman = 1, Expert = 2, Artisan = 3 }
local RANK_COLOR = { Journeyman = "|cff1eff00", Expert = "|cff0070dd", Artisan = "|cffa335ee" }
local PROFS = { "Alchemy", "Blacksmithing", "Engineering", "Leatherworking", "Tailoring" }
local GREY = "|cff808080"
local CALC_TTL = 5      -- seconds before prices are worked out again
-- Sealed envelopes: tiers in order, for the odds of each. Best / Worst = within this many copper
-- per rep of the cheapest / dearest writ (as the crate list does).
local TIER_ORDER = { "Best", "Great", "Good", "Fair", "Poor", "Worst" }
local EXTREME_MARGIN = 10
local MAX_DEPTH = 4     -- how far down crafted reagents are followed

-- Reputation with the trade camp (Azeroth Commerce Authority / Durotar Supply and Logistics).
-- Standings by reaction, with where each starts on the game's absolute scale.
local STANDINGS = {
  { 1, "Hated",      -42000, "|cffcc2222" }, { 2, "Hostile",   -6000, "|cffff0000" },
  { 3, "Unfriendly", -3000,  "|cffee6622" }, { 4, "Neutral",    0,    "|cffffff00" },
  { 5, "Friendly",   3000,   "|cff00ff00" }, { 6, "Honored",    9000, "|cff00ff88" },
  { 7, "Revered",    21000,  "|cff00ffcc" }, { 8, "Exalted",   42000, "|cff00ffff" },
}
local FACTION_IDS = { 2586, 2587 }   -- Season of Discovery's IDs for the two camps; checked by name
local FACTION_NAMES = { ["Azeroth Commerce Authority"] = true, ["Durotar Supply and Logistics"] = true }

local frame, rows, headers, all = nil, {}, {}, nil
local list, sealed = {}, {}
-- prof: nil = all, "mine" = this character's professions, else a profession; rank likewise
local view = { sort = "per", desc = false, search = "", prof = nil, rank = nil,
  priced = false, owned = false, hideDone = false, offset = 0 }

local function Entries()
  if all then return all end
  all = {}
  for _, w in ipairs(ns.Writs) do
    local e = { writ = w[1], quest = w[2], name = w[3], prof = w[4], rank = w[5], skill = w[6],
      rep = w[7], item = w[8], qty = w[9], recipient = w[10] }
    e.text = table.concat({ e.name, e.prof, e.rank, e.recipient }, "\n"):lower()
    all[#all + 1] = e
  end
  return all
end

-- writ / sealed envelope item ID -> entry (or rank name), for the item tooltips
local byItem
local function ByItem()
  if byItem then return byItem end
  byItem = {}
  for _, e in ipairs(Entries()) do byItem[e.writ] = e end
  for rank, r in pairs(ns.WritRanks) do byItem[r.sealed] = rank end
  return byItem
end

---------------------------------------------------------------------------------------------
-- Pricing. One pass works out every writ; it's kept for CALC_TTL seconds (search, filters
-- and scrolling reuse it) and the per-item answers are shared within the pass.

local memo, memoTime = {}, nil
local CraftCost

-- Cheapest way to get one `id`: a vendor's price, else the AH, or crafting it if cheaper.
local function MatCost(id, depth)
  local m = memo[id]
  if m ~= nil then return m or nil end
  local best = ns.VendorPrice(id)
  if not best then
    best = ns.Price(id)
    if depth < MAX_DEPTH then
      local c = CraftCost(id, depth + 1)
      if c and (not best or c < best) then best = c end
    end
  end
  memo[id] = best or false
  return best
end

-- What making one `id` costs from its reagents (nil if it isn't craftable or a reagent has
-- no price). A recipe that makes several splits the cost.
function CraftCost(id, depth)
  local r = ns.Crafts[id]
  if not r then return nil end
  local sum = 0
  for i = 3, #r do
    local unit = MatCost(r[i][1], depth or 0)
    if not unit then return nil end
    sum = sum + unit * r[i][2]
  end
  return sum / r[1]
end

-- Making one `id` from its reagents, for the crate tooltips (crafted crates' bundles). Shares
-- the pricing memo, refreshed after CALC_TTL like the writ list.
function ns.ItemCraftCost(id)
  if not memoTime or GetTime() - memoTime > CALC_TTL then
    wipe(memo)
    memoTime = GetTime()
  end
  return CraftCost(id, 0)
end

local function Count(id)
  local ok, n = pcall(C_Item.GetItemCount, id, true)
  return ok and n or 0
end

local function DoneToday(e)
  if not (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then return false end
  local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, e.quest)
  return ok and done or false
end

local calcTime
function ns.InvalidateWrits() calcTime = nil end

local function Calc()
  if calcTime and GetTime() - calcTime < CALC_TTL then return end
  calcTime = GetTime()
  wipe(memo)
  memoTime = calcTime
  local rated = {}
  local fillSum, fillN = {}, {}
  for _, e in ipairs(Entries()) do
    -- one writ and one fill's worth of items, up the scanned AH listings when fresh (Depth.lua)
    e.writPrice = (ns.FillCost(e.writ, 1))
    local fill = (ns.FillCost(e.item, e.qty))
    e.buy = fill and fill / e.qty or nil
    e.craft = CraftCost(e.item, 0)
    -- the fill is the item bought on the AH: anyone can do that. Crafting needs the
    -- profession and the recipe, so it's shown on its own line instead of in the ratings.
    e.fill = e.buy and e.buy * e.qty or nil
    e.total = e.fill and (e.fill + (e.writPrice or 0)) or nil
    -- the same with the item crafted (needs the profession): its own column, not in the ratings
    e.totalCraft = e.craft and (e.craft * e.qty + (e.writPrice or 0)) or nil
    e.perCraft = e.totalCraft and e.totalCraft / e.rep or nil
    e.per = e.total and e.total / e.rep or nil
    e.label, e.color, e.ratio, e.place = nil, nil, nil, nil
    e.fillRating, e.craftRating, e.craftList, e.buyCraftRating = nil, nil, nil, nil
    if e.per then rated[#rated + 1] = e end
    if e.fill then
      fillSum[e.rank] = (fillSum[e.rank] or 0) + e.fill
      fillN[e.rank] = (fillN[e.rank] or 0) + 1
    end
  end
  -- RateList sets .rank, which here is the writ's rank name: rate copies
  local proxies = {}
  for i, e in ipairs(rated) do proxies[i] = { per = e.per, e = e } end
  ns.RateList(proxies)
  local best = proxies[1] and proxies[1].per
  local worst = proxies[#proxies] and proxies[#proxies].per
  for _, p in ipairs(proxies) do
    local e = p.e
    e.place, e.total_rated, e.ratio, e.label, e.color = p.rank, p.total, p.ratio, p.label, p.color
  end
  -- Craft mode's list rating: writ + crafted item per rep, against the same on every writ
  local crafted = {}
  for _, e in ipairs(Entries()) do
    if e.perCraft then crafted[#crafted + 1] = { per = e.perCraft, e = e } end
  end
  ns.RateList(crafted)
  for _, p in ipairs(crafted) do
    p.e.craftList = { ratio = p.ratio, label = p.label, color = p.color }
  end
  -- "to Fill": the fill alone per rep, for a writ you already have, against the cheapest rep
  -- you can buy outright (a writ priced on the AH + its fill): is filling it cheaper than
  -- buying rep elsewhere? Same for everyone, like the buy rating above.
  local bestBuy = ns.CheapestBuy(proxies, function(p) return p.e.writPrice ~= nil end)
  for _, e in ipairs(Entries()) do
    if e.fill then e.fillRating = ns.RateFill(e.fill / e.rep, bestBuy) end
    -- have the writ, craft the item (needs the profession)
    if e.craft then e.craftRating = ns.RateFill(e.craft * e.qty / e.rep, bestBuy) end
    -- buy the writ, craft the item
    if e.craft and e.writPrice then e.buyCraftRating = ns.RateFill(e.perCraft, bestBuy) end
  end
  -- Sealed envelopes hold a random writ of the rank, so there's no single rating: each writ
  -- of the rank is rated as if it came out of the envelope (envelope price + its fill, per rep,
  -- on the same scale as the writ list), and the envelope shows the odds of each tier.
  -- Assumes every writ of a rank is equally likely (no guide says otherwise).
  for _, rank in ipairs(RANKS) do
    local r = ns.WritRanks[rank]
    local s = sealed[rank] or {}
    sealed[rank] = s
    s.id, s.rep = r.sealed, r.rep
    s.price = ns.Price(r.sealed)
    s.avgFill = fillN[rank] and fillSum[rank] / fillN[rank] or nil
    s.n = fillN[rank] or 0
    s.per = s.avgFill and (s.avgFill + (s.price or 0)) / r.rep or nil
    s.odds = s.odds or {}
    wipe(s.odds)
    s.colors = s.colors or {}
    s.all, s.unpriced = 0, 0
    for _, e in ipairs(Entries()) do
      if e.rank == rank then
        s.all = s.all + 1
        if e.fill and best and best > 0 then
          local per = (e.fill + (s.price or 0)) / r.rep
          local label, color
          if per - best <= EXTREME_MARGIN then
            label, color = "Best", "|cffc77dff"
          elseif worst and per >= worst - EXTREME_MARGIN then
            label, color = "Worst", "|cffb3122e"
          else
            label, color = ns.TierFor(per / best)
          end
          s.odds[label] = (s.odds[label] or 0) + 1
          s.colors[label] = color
        else
          s.unpriced = s.unpriced + 1
        end
      end
    end
  end
end

-- These change without a price update: done flags (on quest turn-in) and bag counts.
local function Live()
  for _, e in ipairs(Entries()) do
    e.done = DoneToday(e)
    if ns.OwnedWhere then
      e.haveWrit, e.writWhere = ns.OwnedWhere(e.writ)
    else
      e.haveWrit, e.writWhere = Count(e.writ), {}
    end
    e.haveItem = Count(e.item)
  end
end

---------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------
-- Reputation

local factionID   -- found once, by ID or by name
local function FactionData(id)
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local ok, d = pcall(C_Reputation.GetFactionDataByID, id)
    if ok and type(d) == "table" and d.name then
      return d.name, d.reaction, d.currentStanding
    end
  end
  if GetFactionInfoByID then
    local ok, name, _, reaction, _, _, value = pcall(GetFactionInfoByID, id)
    if ok and name then return name, reaction, value end
  end
end

local function FindFaction()
  for _, id in ipairs(FACTION_IDS) do
    local name = FactionData(id)
    if name and FACTION_NAMES[name] then return id end
  end
  -- scan the reputation list by name
  local n = C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetNumFactions() or 0
  for i = 1, n do
    local ok, d = pcall(C_Reputation.GetFactionDataByIndex, i)
    if ok and type(d) == "table" and d.name and FACTION_NAMES[d.name] and d.factionID then
      return d.factionID
    end
  end
end

-- { name, reaction, value (absolute), label, color, min, max, known } - Neutral 0 if the camp
-- isn't in your reputation list yet.
local function Standing()
  factionID = factionID or FindFaction()
  local name, reaction, value
  if factionID then name, reaction, value = FactionData(factionID) end
  local st = { name = name, reaction = reaction or 4, value = value or 0, known = name ~= nil }
  local s = STANDINGS[st.reaction] or STANDINGS[4]
  st.label, st.color, st.min = s[2], s[4], s[3]
  st.max = STANDINGS[st.reaction + 1] and STANDINGS[st.reaction + 1][3] or nil
  return st
end

-- The standing this character is working towards (per character): a reaction 5-8, or nil.
local function Target()
  local t = type(CrateCostCharDB) == "table" and CrateCostCharDB.writTarget
  return STANDINGS[t] and t or nil
end

local function SetTarget(t)
  if type(CrateCostCharDB) ~= "table" then CrateCostCharDB = {} end
  CrateCostCharDB.writTarget = t
end

-- Craft mode (per character: it's about this character's professions): the list's item,
-- total, per rep, rating and target columns use the crafted item instead of the AH one.
local function Crafting()
  return type(CrateCostCharDB) == "table" and CrateCostCharDB.writCraft == true
end

-- The route's numbers for writ `e`: item cost, writ + item, per rep, list rating.
-- Owned view (per character): only writs you have (here, bank, warband bank, alts), costed
-- as the fill alone.
local function Owning()
  return type(CrateCostCharDB) == "table" and CrateCostCharDB.writOwned == true
end

local function Route(e)
  if Owning() then
    local r = Crafting() and e.craftRating or e.fillRating
    local item = Crafting() and (e.craft and e.craft * e.qty) or (e.buy and e.buy * e.qty)
    return item, item, item and item / e.rep, r and r.label, r and r.color, r and r.ratio
  end
  if Crafting() then
    local r = e.craftList
    return e.craft and e.craft * e.qty, e.totalCraft, e.perCraft, r and r.label, r and r.color, r and r.ratio
  end
  return e.buy and e.buy * e.qty, e.total, e.per, e.label, e.color, e.ratio
end

local standing, needRep   -- refreshed with the list; needRep nil = no target, or reached

local function UpdateNeed()
  standing = Standing()
  local t = Target()
  needRep = nil
  if t then
    local left = STANDINGS[t][3] - standing.value
    if left > 0 then needRep = left end
  end
end

-- How many of this writ reach the target, and what that costs.
local function ToTarget(e)
  if not needRep or Owning() then return nil end
  local n = math.ceil(needRep / e.rep)
  local total = select(2, Route(e))
  return n, total and total * n or nil
end

local function Num(n)
  return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end


---------------------------------------------------------------------------------------------

local function MyProfessions()
  local set = {}
  if not GetProfessions then return set end
  local ok, a, b, c, d, e = pcall(GetProfessions)
  if not ok then return set end
  for _, idx in pairs({ a, b, c, d, e }) do
    local name = idx and GetProfessionInfo and select(1, GetProfessionInfo(idx))
    if name then set[name] = true end
  end
  return set
end
ns.MyProfessions = MyProfessions


---------------------------------------------------------------------------------------------
-- Plan: the cheapest writs you can do now that reach the rep target. Each writ is a daily, so
-- each is used once and writs done today are left out; when they can't reach the target the
-- plan says how far they get, and Regenerate the next day plans the rest. The writs it would
-- have used if they weren't done yet are listed too, in red, outside the cost: they show when
-- the best writs are already used up. The plan is kept until Regenerate (or a new target).
-- A writ's k-th copy costs what k copies cost less what k-1 cost: writs you have first (free),
-- then bought up the AH listings (Depth.lua, else Auctionator's price); the item likewise,
-- minus the items in your bags, or crafted when you have the profession and that's cheaper.
-- Within a rank every writ gives the same rep, so the cheapest copies of each rank win; the
-- only choice is how many of each rank, tried exhaustively.


-- Cost of k copies of writ e, and whether the item is crafted. nil = can't get k.
local function CopiesCost(e, k, canCraft)
  if k <= 0 then return 0, false end
  local cost = 0
  local buyWrits = math.max(0, k - (e.haveWrit or 0))
  if buyWrits > 0 then
    local c, how = ns.FillCost(e.writ, buyWrits)
    if not c or how.short then return nil end
    cost = c
  end
  local items = math.max(0, k * e.qty - (e.haveItem or 0))
  local crafted = false
  if items > 0 then
    local ah, how = ns.FillCost(e.item, items)
    if how.short then ah = nil end
    local cr = canCraft and e.craft and e.craft * items or nil
    if cr and (not ah or cr < ah) then ah, crafted = cr, true end
    if not ah then return nil end
    cost = cost + ah
  end
  return cost, crafted
end

-- copies[rep] = { { e, k, cost }, ... } for up to `days` days, cheapest first per rank.
-- `cd`: writs done today miss day 1.
local function Copies(days, profs, cd)
  local groups, capacity = {}, 0
  for _, e in ipairs(Entries()) do
    local m = days - ((cd and e.done) and 1 or 0)
    local prev = 0
    for k = 1, m do
      local cum = CopiesCost(e, k, profs[e.prof])
      if not cum then break end
      groups[e.rep] = groups[e.rep] or {}
      table.insert(groups[e.rep], { e = e, k = k, cost = cum - prev })
      capacity = capacity + e.rep
      prev = cum
    end
  end
  for _, g in pairs(groups) do
    table.sort(g, function(a, b)
      if a.cost ~= b.cost then return a.cost < b.cost end
      if a.e ~= b.e then return a.e.writ < b.e.writ end
      return a.k < b.k
    end)
  end
  return groups, capacity
end

-- How many of each rank: every count of the smaller ranks, the biggest filling the rest.
local function Choose(groups, need)
  local reps = {}
  for r in pairs(groups) do reps[#reps + 1] = r end
  table.sort(reps)
  local prefix = {}
  for _, r in ipairs(reps) do
    local p = { [0] = 0 }
    for i, c in ipairs(groups[r]) do p[i] = p[i - 1] + c.cost end
    prefix[r] = p
  end
  local best, bestCost
  local counts = {}
  local function Try(i, got, cost)
    local r = reps[i]
    if i == #reps then
      local n = math.max(0, math.ceil((need - got) / r))
      if n > #groups[r] then return end
      local total = cost + prefix[r][n]
      if not bestCost or total < bestCost then
        bestCost = total
        best = {}
        for k, v in pairs(counts) do best[k] = v end
        best[r] = n
      end
      return
    end
    for n = 0, #groups[r] do
      counts[r] = n
      Try(i + 1, got + n * r, cost + prefix[r][n])
      if got + n * r >= need then break end   -- more of this rank only adds cost
    end
    counts[r] = nil
  end
  if #reps > 0 then Try(1, 0, 0) end
  return best, bestCost
end

local function SortPlan(list)
  table.sort(list, function(a, b)
    -- best value first: cost per rep
    local pa, pb = a.cost / a.e.rep, b.cost / b.e.rep
    if pa ~= pb then return pa < pb end
    if (a.spent or false) ~= (b.spent or false) then return a.spent or false end
    return a.e.name < b.e.name
  end)
end

-- { need, days, cost, rep, short, list = { { day, e, cost, crafted, owned }, ... } } or nil
-- `cd`: writs done today miss day 1 (their copies start on day 2).
local function BuildPlan(need, profs, cd)
  -- one day: each writ once. Regenerate tomorrow for the rest.
  local groups, capacity = Copies(1, profs, cd)
  local short = capacity < need
  local counts, cost = Choose(groups, math.min(need, capacity))
  if not counts then return nil end
  local plan = { need = need, days = 0, cost = cost or 0, rep = 0, short = short, list = {} }
  for r, n in pairs(counts) do
    for i = 1, n do
      local c = groups[r][i]
      local e = c.e
      local day = 1
      local _, crafted = CopiesCost(e, c.k, profs[e.prof])
      table.insert(plan.list, { day = day, e = e, cost = c.cost, crafted = crafted,
        owned = c.k <= (e.haveWrit or 0) })
      plan.rep = plan.rep + e.rep
      if day > plan.days then plan.days = day end
    end
  end
  return plan
end

-- The plan around today's cooldowns, plus `spent`: the writs done today that the plan would
-- have used today without the cooldowns. Those go in day 1 marked .spent, outside the cost,
-- rep and cart.
local function MakePlan(need)
  local profs = MyProfessions()
  local plan = BuildPlan(need, profs, true)
  if not plan then return nil end
  local ideal = BuildPlan(need, profs, false)
  plan.spent = 0
  for _, it in ipairs(ideal and ideal.list or {}) do
    if it.day == 1 and it.e.done then
      it.spent = true
      table.insert(plan.list, it)
      plan.spent = plan.spent + 1
    end
  end
  SortPlan(plan.list)
  return plan
end

-- The plan as made: kept (rep turned in, prices moving) until Regenerate or a new target.
local planMemo, planTarget
local function RegeneratePlan()
  planMemo = needRep and MakePlan(needRep) or false
  planTarget = Target()
end
local function CurrentPlan()
  if not needRep or Owning() then return nil end
  if planMemo == nil or planTarget ~= Target() then RegeneratePlan() end
  return planMemo or nil
end
ns.WritPlan = function() return CurrentPlan() end
ns.RegenerateWritPlan = function() Calc() Live() UpdateNeed() RegeneratePlan() end

-- The plan's writs that count: not the spent ones (done before the plan was made).
local function PlanCount(p)
  local n = 0
  for _, it in ipairs(p.list) do if not it.spent then n = n + 1 end end
  return n
end

local function SortValue(e, key)
  if key == "name" or key == "prof" then return e[key]:lower() end
  if key == "rank" then return RANK_ORDER[e.rank] * 1000 + e.skill end
  if key == "skill" or key == "rep" then return e[key] end
  if key == "writ" then
    if Owning() then return ns.WhoSort(e.writWhere) end
    return e.writPrice
  end
  if key == "rating" then
    local ratio = select(6, Route(e))
    return ratio and -ratio
  end
  if key == "item" then return (Route(e)) end
  if key == "total" then return select(2, Route(e)) end
  if key == "per" then return select(3, Route(e)) end
  if key == "have" then return e.haveWrit * 1000 + e.haveItem end
  if key == "done" then return e.done and 1 or 0 end
  if key == "need" then return (ToTarget(e)) end
  if key == "target" then return select(2, ToTarget(e)) end
  return e[key]
end

local function Compare(a, b)
  local va, vb = a.sortValue, b.sortValue
  -- unpriced rows always last
  if va == nil and vb ~= nil then return false end
  if vb == nil and va ~= nil then return true end
  if va ~= vb then
    if view.desc then return va > vb end
    return va < vb
  end
  if a.prof ~= b.prof then return a.prof < b.prof end
  if a.skill ~= b.skill then return a.skill < b.skill end
  return a.name < b.name
end

---------------------------------------------------------------------------------------------
-- Tooltips

local function ItemName(id)
  local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
  return n or ("item " .. id)
end

local function MoneyOr(copper, none)
  return copper and ns.Money(copper) or (GREY .. (none or "no price") .. "|r")
end

-- What the required item costs each way, then its reagents.
local function AddFillLines(tt, e)
  local qty = e.qty > 1 and (e.qty .. "x ") or ""
  tt:AddLine("Needs " .. qty .. ItemName(e.item), 1, 0.82, 0)
  local buyBest = e.buy and (not e.craft or e.buy <= e.craft)
  local function Line(label, v, best)
    local text = MoneyOr(v and v * e.qty)
    if best then tt:AddDoubleLine(ns.BEST .. label .. "|r", ns.BEST .. text .. "|r")
    else tt:AddDoubleLine(label, text, 1, 1, 1, 1, 1, 1) end
  end
  Line("  Buy on the AH", e.buy, buyBest)
  local r = ns.Crafts[e.item]
  if r then
    Line("  Craft it (" .. r[2] .. ")", e.craft, e.craft and not buyBest)
    for i = 3, #r do
      local id, n = r[i][1], r[i][2] * e.qty
      local unit = MatCost(id, 1)
      local src = ns.VendorPrice(id) and " (vendor)" or ""
      tt:AddDoubleLine("     " .. n .. " " .. ItemName(id) .. src,
        MoneyOr(unit and unit * n / r[1]), 0.75, 0.75, 0.75, 0.75, 0.75, 0.75)
    end
    if r[1] > 1 then tt:AddLine("     (makes " .. r[1] .. ")", 0.6, 0.6, 0.6) end
  else
    tt:AddDoubleLine("  Craft it", GREY .. "no recipe data|r")
  end
end

-- The four ways to do a writ: buy it or have it, then buy the item or craft it. Each is
-- { rating, per rep, why it's missing }. Ratings are against the cheapest rep you can buy
-- outright (buy writ + buy item), the same for everyone.
local function Ways(e)
  local craftable = ns.Crafts[e.item] ~= nil
  local function Way(r, per, missing)
    if r and per then return { r = r, per = per } end
    return { missing = missing }
  end
  local noWrit, noItem = "writ not on the AH", "item not on the AH"
  local noCraft = craftable and "reagents not priced" or "no recipe data"
  return {
    buyBuy = Way(e.writPrice and e.label and e, e.writPrice and e.per, e.writPrice and noItem or noWrit),
    buyCraft = Way(e.buyCraftRating, e.buyCraftRating and e.buyCraftRating.per,
      not e.writPrice and noWrit or noCraft),
    haveBuy = Way(e.fillRating, e.fillRating and e.fillRating.per, noItem),
    haveCraft = Way(e.craftRating, e.craftRating and e.craftRating.per, noCraft),
  }
end

local function Cell(w)
  if w.r then return w.r.color .. w.r.label .. "|r" end
  return GREY .. (w.missing == "no recipe data" and "-" or "?") .. "|r"
end

-- One cost line per way. Lines for your situation are white (have the writ or not; craft lines
-- only with the profession), the rest grey.
local function AddRatingLine(tt, e)
  local ways = Ways(e)
  local r = ns.Crafts[e.item]
  local prof = r and r[2]
  local owned = ns.OwnedWhere and (ns.OwnedWhere(e.writ)) or Count(e.writ)
  local own = owned > 0
  local canCraft = prof and MyProfessions()[prof]
  local function How(x)
    if x < 0.995 then return string.format("%.1fx the cheapest buy", x) end
    if x <= 1.005 then return "the cheapest buy" end
    return string.format("%.1fx the cheapest buy", x)
  end
  local function Line(label, w, haveRow, craftCol)
    local mine = (own == haveRow) and (not craftCol or canCraft)
    local c = mine and 1 or 0.6
    if w.r then
      local ratio = w.r.ratio or 1
      tt:AddDoubleLine(label, ns.Money(math.floor(w.per + 0.5)) .. " per rep, " .. How(ratio),
        c, c, c, c, c, c)
    else
      tt:AddDoubleLine(label, w.missing, c, c, c, 0.5, 0.5, 0.5)
    end
  end
  local craftName = prof and (" (" .. prof .. ")") or ""
  Line("Buy writ + buy item" .. (ways.buyBuy.r and string.format("  #%d of %d", e.place, e.total_rated) or ""),
    ways.buyBuy, false, false)
  Line("Buy writ + craft item" .. craftName, ways.buyCraft, false, true)
  Line(own and ("Have writ (" .. owned .. ") + buy item") or "Have writ + buy item", ways.haveBuy, true, false)
  Line((own and ("Have writ (" .. owned .. ")") or "Have writ") .. " + craft item" .. craftName,
    ways.haveCraft, true, true)
end

local function RatingText(e)
  return e.label and (e.color .. e.label .. "|r") or nil
end

-- The writ's own lines, under its item tooltip or in the list's row tooltip.
local function AddWritLines(tt, e, titled)
  Calc()
  -- the four ratings as a grid: writ (buy / have) x item (buy / craft)
  if not titled then
    local w = Ways(e)
    ns.SetTitleGrid(tt, { "", "Buy item", "Craft item" }, {
      { "Buy writ", Cell(w.buyBuy), Cell(w.buyCraft) },
      { "Have writ", Cell(w.haveBuy), Cell(w.haveCraft) },
    }, 4, -2)
  end
  tt:AddLine(" ")
  tt:AddDoubleLine(RANK_COLOR[e.rank] .. e.rank .. "|r writ", e.rep .. " reputation", 1, 1, 1, 1, 1, 1)
  if e.recipient ~= "" then tt:AddDoubleLine("Deliver to", e.recipient, 1, 0.82, 0, 1, 1, 1) end
  tt:AddDoubleLine("Writ on the AH", MoneyOr(e.writPrice), 0.4, 0.8, 1, 1, 1, 1)
  AddFillLines(tt, e)
  tt:AddDoubleLine("Total", MoneyOr(e.total), 1, 0.82, 0, 1, 1, 1)
  AddRatingLine(tt, e)
  UpdateNeed()
  local n, cost = ToTarget(e)
  if n then
    local t = STANDINGS[Target()]
    tt:AddDoubleLine("To " .. t[4] .. t[2] .. "|r: " .. Num(needRep) .. " rep",
      n .. " of this writ" .. (cost and (", " .. ns.Money(cost)) or "") .. " (" .. n .. " days, it's a daily)",
      1, 0.82, 0, 1, 1, 1)
  end
  if DoneToday(e) then tt:AddLine("Done today.", 0.25, 1, 0.25) end
end

-- The odds for envelope `s`, coloured: "Best 76%  Good 9%  Fair 16%" on one line, plus one
-- row per tier for the tooltip ({name, value, pct}). nil if no writ of the rank is priced yet.
local function OddsText(s)
  local priced = s.all - s.unpriced
  if priced <= 0 then return nil end
  local parts, rows = {}, {}
  for _, label in ipairs(TIER_ORDER) do
    local n = s.odds[label]
    if n then
      local c, p = s.colors[label], math.floor(n * 100 / priced + 0.5)
      parts[#parts + 1] = c .. label .. " " .. p .. "%|r"
      rows[#rows + 1] = { name = c .. label .. "|r", value = c .. p .. "%|r", pct = n }
    end
  end
  return table.concat(parts, "  "), rows
end

local function AddSealedLines(tt, rank)
  Calc()
  local s = sealed[rank]
  if not s then return end
  tt:AddLine(" ")
  tt:AddDoubleLine("Random " .. RANK_COLOR[rank] .. rank .. "|r writ", s.rep .. " reputation", 1, 1, 1, 1, 1, 1)
  tt:AddDoubleLine("Envelope on the AH", MoneyOr(s.price), 0.4, 0.8, 1, 1, 1, 1)
  tt:AddDoubleLine("Average fill (" .. s.n .. " writs priced)", MoneyOr(s.avgFill), 1, 0.82, 0, 1, 1, 1)
  if s.per then
    tt:AddDoubleLine("Average per rep", ns.Money(math.floor(s.per + 0.5)), 1, 0.82, 0, 1, 1, 1)
  end
  -- the odds go right under the name (the most useful part); the details stay down here
  local odds, rows = OddsText(s)
  if odds then
    -- one tier per line in quality order, the likeliest drawn bigger than the rest
    ns.SetTitleOdds(tt, rows, "100%")
    local priced = s.all - s.unpriced
    tt:AddLine("Odds above: the writ inside, rated on the envelope's price + its fill, from "
      .. priced .. " of " .. s.all .. " writs priced. Assumes each " .. rank .. " writ is equally likely.",
      0.6, 0.6, 0.6, true)
  end
  UpdateNeed()
  if needRep and s.per then
    local t = STANDINGS[Target()]
    local n = math.ceil(needRep / s.rep)
    tt:AddDoubleLine("To " .. t[4] .. t[2] .. "|r: " .. Num(needRep) .. " rep",
      n .. " envelopes, about " .. ns.Money(math.floor(s.per * n * s.rep + 0.5)), 1, 0.82, 0, 1, 1, 1)
  end
end

-- tooltip -> the writ / envelope item our hook already added lines for (cleared with the
-- tooltip), so the list's row tooltips don't add them twice
local shownOn, hooked = {}, {}
local function Forget(tooltip) shownOn[tooltip] = nil end

-- Item tooltip hook (CrateCost.lua): writs and sealed envelopes. True if it was one.
function ns.WritTooltip(tooltip, id)
  local e = ByItem()[id]
  if not e then return false end
  if shownOn[tooltip] == id then return true end   -- the game re-runs item tooltips
  if not hooked[tooltip] then
    hooked[tooltip] = true
    pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", Forget)
    pcall(tooltip.HookScript, tooltip, "OnHide", Forget)
  end
  shownOn[tooltip] = id
  if type(e) == "string" then AddSealedLines(tooltip, e) else AddWritLines(tooltip, e) end
  tooltip:Show()
  ns.AlignTitleRating(tooltip)
  return true
end

local function ShowRowTooltip(row)
  local e = row.entry
  if not e then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  -- the writ item's own tooltip runs our hook and adds the lines; without it, add them here
  local ok = pcall(GameTooltip.SetItemByID, GameTooltip, e.writ) and GameTooltip:NumLines() > 0
  if not ok then
    GameTooltip:ClearLines()
    GameTooltip:AddLine("|cff0070ddCraftsman's Writ: " .. e.name .. "|r")
  end
  if shownOn[GameTooltip] ~= e.writ then AddWritLines(GameTooltip, e) end
  GameTooltip:Show()
  ns.AlignTitleRating(GameTooltip)
end

local function ShowSealedTooltip(box)
  GameTooltip:SetOwner(box, "ANCHOR_TOP")
  local s = sealed[box.rank]
  local ok = s and pcall(GameTooltip.SetItemByID, GameTooltip, s.id) and GameTooltip:NumLines() > 0
  if not ok then
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Sealed " .. box.rank .. "'s Writ")
  end
  if s and shownOn[GameTooltip] ~= s.id then AddSealedLines(GameTooltip, box.rank) end
  GameTooltip:Show()
  ns.AlignTitleRating(GameTooltip)
end

---------------------------------------------------------------------------------------------
-- Rows

local ITEM_COLS = { item = true }
local function ColumnAtCursor(row)
  local left = row:GetLeft()
  if not left then return end
  local x = GetCursorPosition() / row:GetEffectiveScale() - left
  for _, col in ipairs(COLS) do
    if x >= col.x - 10 and x < col.x - 10 + col.w then return col.key end
  end
end

local function RowClick(row)
  local e = row.entry
  if not (e and IsShiftKeyDown()) then return end
  if ITEM_COLS[ColumnAtCursor(row)] then
    ns.SearchAuctionator(e.item, ItemName(e.item))
  else
    ns.SearchAuctionator(e.writ, "Craftsman's Writ: " .. e.name)
  end
end

local Draw

local function MakeRow(i)
  local row = CreateFrame("Button", nil, frame)
  row:SetSize(WIDTH - 30, ROW_H)
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
        g = Cell(x, col.w - SUB * 2), s = Cell(x + col.w - SUB * 2, SUB), c = Cell(x + col.w - SUB, SUB),
      }
    end
  end
  row:SetScript("OnClick", RowClick)
  row:SetScript("OnEnter", ShowRowTooltip)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = row
  return row
end

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

local NONE = GREY .. "?|r"

function Draw()
  local maxOff = math.max(0, #list - VISIBLE)
  if view.offset > maxOff then view.offset = maxOff end
  if view.offset < 0 then view.offset = 0 end
  for i = 1, VISIBLE do
    local row = rows[i] or MakeRow(i)
    local e = list[view.offset + i]
    row.entry = e
    if e then
      local c = row.cells
      c.name:SetText(e.done and (GREY .. e.name .. "|r") or e.name)
      c.prof:SetText(e.prof)
      c.rank:SetText(RANK_COLOR[e.rank] .. e.rank .. "|r")
      c.skill:SetText(e.skill)
      c.rep:SetText(e.rep)
      if Owning() then
        SetMoney(row, "writ", nil, nil, ns.WhoText(e.writWhere))
      else
        SetMoney(row, "writ", e.writPrice, nil, NONE)
      end
      local item, total, per, label, color = Route(e)
      -- craft mode, no recipe data: "-" (it can't be crafted as far as we know)
      local none = (Crafting() and not ns.Crafts[e.item]) and (GREY .. "-|r") or NONE
      SetMoney(row, "item", item, nil, none)
      SetMoney(row, "total", total, e.writPrice and "" or GREY, none)
      SetMoney(row, "per", per, e.writPrice and "" or GREY, none)
      local n, cost = ToTarget(e)
      c.need:SetText(n and (n .. "x") or "")
      SetMoney(row, "target", cost, e.writPrice and "" or GREY,
        Target() and (needRep and NONE or "|cff40ff40reached|r") or (GREY .. "-|r"))
      c.rating:SetText(label and (color .. label .. "|r" .. (e.writPrice and "" or GREY .. "*|r")) or "")
      local have = ""
      if e.haveWrit > 0 then have = "|cff40ff40W|r " end
      if e.haveItem > 0 then have = have .. e.haveItem end
      c.have:SetText(have)
      c.done:SetText(e.done and "|cff40ff40done|r" or "")
      row:Show()
    else
      row:Hide()
    end
  end
  local s = frame.scroll
  s.updating = true
  s:SetMinMaxValues(0, maxOff)
  s:SetValue(view.offset)
  s.updating = false
  s:SetShown(maxOff > 0)
  frame.empty:SetShown(#list == 0)
end

local function DrawSealed()
  for _, box in ipairs(frame.sealed) do
    local s = sealed[box.rank]
    local text = RANK_COLOR[box.rank] .. "Sealed " .. box.rank .. "|r  "
    local odds = s and OddsText(s)
    if s and s.per and odds then
      text = text .. (s.price and ns.Money(s.price) or (GREY .. "no price|r")) .. " + avg fill "
        .. ns.Money(s.avgFill) .. " = " .. ns.Money(math.floor(s.per + 0.5)) .. "/rep avg.   Odds:  " .. odds
      if s.unpriced > 0 then text = text .. GREY .. "   (" .. s.unpriced .. " unpriced)|r" end
    else
      text = text .. GREY .. "no prices yet|r"
    end
    box.text:SetText(text)
  end
end

local function UpdateHeaders()
  for _, h in ipairs(headers) do
    local title = (Owning() and h.col.ownedTitle) or (Crafting() and h.col.craftTitle) or h.col.title
    if h.col.key == "target" and Target() then title = "To " .. STANDINGS[Target()][2] end
    ns.UI.HeaderText(h, title, h.col.key == view.sort, view.desc)
  end
  frame.profBtn.text:SetText(view.prof == "mine" and "My professions" or view.prof or "All professions")
  local t = Target()
  frame.targetBtn.text:SetText(t and (STANDINGS[t][4] .. STANDINGS[t][2] .. "|r") or "No target")
  local st = standing
  local txt = "Standing: " .. st.color .. st.label .. "|r"
  if st.max then
    txt = txt .. string.format("  %s / %s", Num(st.value - st.min), Num(st.max - st.min))
  end
  if not st.known then txt = txt .. GREY .. " (camp not met yet)|r" end
  if t then
    txt = txt .. "   " .. (needRep and (Num(needRep) .. " rep to " .. STANDINGS[t][2])
      or ("|cff40ff40" .. STANDINGS[t][2] .. " reached|r"))
  end
  frame.standing:SetText(txt)
  frame.rankBtn.text:SetText(view.rank or "All ranks")
  frame.routeToggle:Refresh()
  frame.ownToggle:Refresh()
  if ns.OnDepthChangedWrits then
    local b = frame.scanBtn
    if b and ns.Depth.state ~= "running" then b:SetEnabled(ns.Depth.atAH and true or false) end
  end
  -- Owned view: Who (the writ cost column) first, Writ .. Rep moved right into its space
  ns.UI.Relayout(rows, headers, COLS, Owning())
  -- the target is about writs to buy: hidden in the Owned view
  frame.targetBtn:SetShown(not Owning())
  frame.targetLabel:SetShown(not Owning())
end

function ns.RefreshWrits()
  if not (frame and frame:IsShown()) then return end
  Calc()
  Live()
  UpdateNeed()
  local mine = view.prof == "mine" and MyProfessions() or nil
  wipe(list)
  local q = view.search
  for _, e in ipairs(Entries()) do
    local ok = true
    if view.prof == "mine" then ok = mine[e.prof] or false
    elseif view.prof then ok = e.prof == view.prof end
    if ok and view.rank and e.rank ~= view.rank then ok = false end
    if ok and view.priced and not e.writPrice then ok = false end
    if ok and Owning() and e.haveWrit == 0 then ok = false end
    if ok and view.hideDone and e.done then ok = false end
    if ok and q ~= "" and not e.text:find(q, 1, true) then ok = false end
    if ok then
      e.sortValue = SortValue(e, view.sort)
      list[#list + 1] = e
    end
  end
  table.sort(list, Compare)
  local done = 0
  for _, e in ipairs(Entries()) do if e.done then done = done + 1 end end
  frame.count:SetText(string.format("%d shown  |  %d done today", #list, done))
  -- target line: the cheapest shown writ to repeat daily until the target
  local plan = ""
  local t = Target()
  frame.planBtn:SetEnabled(needRep ~= nil and not Owning())
  if needRep and not Owning() then
    plan = STANDINGS[t][4] .. STANDINGS[t][2] .. "|r: " .. Num(needRep) .. " rep to go.  "
    local p = CurrentPlan()
    if p then
      plan = plan .. string.format("Plan: %d writs, %s%s%s.", PlanCount(p), ns.Money(p.cost),
        (p.spent or 0) > 0 and string.format(", |cffff4040%d of the best already done today|r", p.spent) or "",
        p.short and (" |cffff4040- gets " .. Num(p.rep) .. " rep; regenerate tomorrow for the rest|r") or "")
    else
      plan = plan .. GREY .. "No plan: no writ has a price yet.|r"
    end
  elseif needRep then
    plan = STANDINGS[t][4] .. STANDINGS[t][2] .. "|r: " .. Num(needRep) .. " rep to go."
  elseif t then
    plan = "|cff40ff40" .. STANDINGS[t][2] .. " reached.|r"
  end
  frame.plan:SetText(plan)
  UpdateHeaders()
  Draw()
  ns.UI.Relayout(rows, headers, COLS, Owning())   -- rows made by this Draw too
  DrawSealed()
end

---------------------------------------------------------------------------------------------
-- Window

local function Build()
  local UI = ns.UI
  frame = UI.Window("CrateCostWrits", "Craftsman's Writs - cheapest reputation", WIDTH,
    TOP + VISIBLE * ROW_H + 106, UI.POS_KEY)
  frame:SetScript("OnShow", function()
    -- every writ, filling item and envelope, so shift-click links them straight away
    local ids = {}
    for _, w in ipairs(ns.Writs) do
      ids[#ids + 1] = w[1]
      ids[#ids + 1] = w[8]
    end
    for _, r in pairs(ns.WritRanks) do ids[#ids + 1] = r.sealed end
    ns.PreloadItems(ids)
    ns.RefreshWrits()
  end)
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta)
    view.offset = view.offset - delta * 3
    Draw()
  end)
  -- bag counts and done-today flags; prices are re-read on their own timer
  local pending = false
  for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "QUEST_TURNED_IN", "UPDATE_FACTION" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(ev) then
      pcall(frame.RegisterEvent, frame, ev)
    end
  end
  frame:SetScript("OnEvent", function()
    if not frame:IsShown() or pending then return end
    pending = true
    C_Timer.After(0.2, function() pending = false ns.RefreshWrits() end)
  end)

  local function Reset() view.offset = 0 ns.RefreshWrits() end

  -- title row: reputation target (per character) and current standing, then the nav bar
  local tl = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  tl:SetPoint("LEFT", frame.title, "RIGHT", 24, 0)
  tl:SetText("Target:")
  frame.targetLabel = tl
  local tb = UI.DropButton(frame, 100, tl, 10)
  frame.targetBtn = tb
  local targetChoices = { { "No target", nil }, "-" }
  for i = 5, 8 do targetChoices[#targetChoices + 1] = { STANDINGS[i][4] .. STANDINGS[i][2] .. "|r", i } end
  UI.Menu(frame, tb, targetChoices, 100, function(v) SetTarget(v) Reset() end)
  frame.standing = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  frame.standing:SetPoint("LEFT", frame.title, "RIGHT", 196, 0)

  UI.NavBar(frame, "writs", function() ns.InvalidateWrits() ns.RefreshWrits() end)

  -- filter row: search, profession, rank, checks, then the Buy | Craft toggle on the right
  local search = UI.Search(frame, "Search writ or recipient", 170, function(t)
    view.search = t
    Reset()
  end)
  local pb = UI.DropButton(frame, 140, search, 12)
  frame.profBtn = pb
  local profChoices = { { "All professions", nil }, { "My professions", "mine" }, "-" }
  for _, p in ipairs(PROFS) do profChoices[#profChoices + 1] = { p, p } end
  UI.Menu(frame, pb, profChoices, 140, function(v) view.prof = v Reset() end)

  local rb = UI.DropButton(frame, 100, pb, 8)
  frame.rankBtn = rb
  local rankChoices = { { "All ranks", nil }, "-" }
  for _, r in ipairs(RANKS) do rankChoices[#rankChoices + 1] = { RANK_COLOR[r] .. r .. "|r", r } end
  UI.Menu(frame, rb, rankChoices, 100, function(v) view.rank = v Reset() end)

  local function Flag(key) return function() return view[key] end, function(v) view[key] = v Reset() end end
  local g1, s1 = Flag("priced")
  local l1 = UI.Check(frame, "Writ on the AH", rb, 12,
    "Only writs with an Auctionator price. The rest are rated on the item alone (marked *).", g1, s1)
  local g3, s3 = Flag("hideDone")
  local l2 = UI.Check(frame, "Hide done today", l1, 8, "Each writ is a daily quest.", g3, s3)

  -- Scan AH: the writs' and their items' listings (Depth.lua, shared with /crates)
  local scan = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  scan:SetSize(130, 20)
  scan:SetPoint("LEFT", l2, "RIGHT", 14, 0)
  frame.scanBtn = scan
  scan:SetScript("OnClick", function()
    if ns.Depth.state == "running" then ns.Depth.Stop() else ns.Depth.Start(ns.WritDepthWants()) end
  end)
  scan:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Scan AH")
    GameTooltip:AddLine("Reads the auction house listings for every writ and the item it wants, deep "
      .. "enough for the plan, so prices and the plan use the real listings instead of the cheapest "
      .. "price x amount.", 1, 1, 1, true)
    local age = ns.Depth.Age()
    GameTooltip:AddLine(age and string.format("Last scan: %dm ago%s.", math.floor(age / 60),
      age >= ns.Depth.TTL and " (too old, Auctionator prices in use)" or "") or "Not scanned yet.", 0.6, 0.6, 0.6, true)
    if not ns.Depth.atAH then GameTooltip:AddLine("Open the auction house to scan.", 1, 0.5, 0.25) end
    GameTooltip:Show()
  end)
  scan:SetScript("OnLeave", GameTooltip_Hide)

  -- Buy | Craft: which way the list gets the item (per character)
  frame.routeToggle = UI.Toggle(frame, {
    { false, "Buy items", "Item, total, per rep, rating and target use the item bought on the AH." },
    { true, "Craft items", "Item, total, per rep, rating and target use the item crafted from its "
      .. "reagents (needs the profession)." },
  }, 80, Crafting, function(v)
    if type(CrateCostCharDB) ~= "table" then CrateCostCharDB = {} end
    CrateCostCharDB.writCraft = v
    Reset()
  end)
  frame.ownToggle = UI.Toggle(frame, {
    { false, "Buy", "Writs to buy: writ + item." },
    { true, "Owned", "Only the writs you have (this character, bank, warband bank, alts): the cost "
      .. "of filling each one." },
  }, 60, Owning, function(v)
    if type(CrateCostCharDB) ~= "table" then CrateCostCharDB = {} end
    CrateCostCharDB.writOwned = v
    Reset()
  end)
  UI.PlaceToggles(frame, { frame.routeToggle, frame.ownToggle })

  for _, h in ipairs(UI.Headers(frame, COLS, 0, function(col)
    if view.sort == col.key then
      view.desc = not view.desc
    else
      view.sort, view.desc = col.key, col.desc or false
    end
    Reset()
  end)) do headers[#headers + 1] = h end

  local s = CreateFrame("Slider", nil, frame, "BackdropTemplate")
  s:SetOrientation("VERTICAL")
  s:SetSize(10, VISIBLE * ROW_H)
  s:SetPoint("TOPRIGHT", -10, -TOP)
  s:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  s:SetBackdropColor(1, 1, 1, 0.05)
  s:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
  local thumb = s:GetThumbTexture()
  thumb:SetSize(10, 40)
  thumb:SetVertexColor(0.5, 0.5, 0.55, 0.8)
  s:SetValueStep(1)
  s:SetObeyStepOnDrag(true)
  s:SetScript("OnValueChanged", function(self, v)
    if self.updating then return end
    view.offset = math.floor(v + 0.5)
    Draw()
  end)
  frame.scroll = s

  frame.empty = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  frame.empty:SetPoint("TOP", 0, -TOP - 10)
  frame.empty:SetText("Nothing matches.")

  -- the three sealed envelopes, under the list
  frame.sealed = {}
  local boxW = WIDTH - 24
  for i, rank in ipairs(RANKS) do
    local box = CreateFrame("Button", nil, frame)
    box:SetSize(boxW, 18)
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -TOP - VISIBLE * ROW_H - 6 - (i - 1) * 18)
    box.rank = rank
    box.text = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    box.text:SetAllPoints()
    box.text:SetJustifyH("LEFT")
    box.text:SetWordWrap(false)
    local hl = box:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    box:SetScript("OnEnter", ShowSealedTooltip)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    box:SetScript("OnClick", function(self)
      if IsShiftKeyDown() then
        ns.SearchAuctionator(ns.WritRanks[self.rank].sealed, "Sealed " .. self.rank .. "'s Writ")
      end
    end)
    frame.sealed[i] = box
  end

  local pbtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  pbtn:SetSize(70, 20)
  pbtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -TOP - VISIBLE * ROW_H - 58)
  pbtn:SetText("Plan")
  pbtn:SetScript("OnClick", function() ns.ShowWritPlan() end)
  UI.Tip(pbtn, "Plan", "The cheapest writs that reach your target in the fewest days: all today "
    .. "when today's writs can reach it. Writs you have come first; items are bought up the AH "
    .. "listings (Scan AH on /crates) or crafted when you have the profession and it's cheaper.")
  frame.planBtn = pbtn
  frame.plan = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  frame.plan:SetPoint("LEFT", pbtn, "RIGHT", 10, 0)
  frame.plan:SetJustifyH("LEFT")

  local footer = ns.UI.Footer(frame)
  footer:SetText(GREY .. "Buy: writ + item. Owned: only writs you have (incl. bank, warband bank, alts), "
    .. "the item alone. Buy items / Craft items: the item from the AH or made from its reagents. "
    .. "* = writ not priced. Have: W = you hold the writ, then the item count. Data: wow.gg, endgametools.com.|r")
end

---------------------------------------------------------------------------------------------
-- The plan's window: day by day, each writ, how to get it and its item, rep and cost.

local PROWS, PROW_H, PTOP, PFOOT = 22, 18, 58, 70
local pf, ShowCD
-- Show the writs already done today in the plan window (per character, default on).
ShowCD = function()
  return not (type(CrateCostCharDB) == "table" and CrateCostCharDB.planHideCD)
end

-- The plan's rows, best value first. Writs done today show only when ShowCD(); the footer has
-- the totals.
local function PlanLines(p)
  local lines = {}
  for _, it in ipairs(p.list) do
    if ShowCD() or not it.e.done then lines[#lines + 1] = { it = it } end
  end
  return lines
end

local function FillPlan()
  local p = CurrentPlan()
  local lines = p and PlanLines(p) or {}
  pf.offset = math.max(0, math.min(pf.offset, #lines - PROWS))
  for i = 1, PROWS do
    local r, ln = pf.rows[i], lines[pf.offset + i]
    r.it = ln and ln.it
    if not ln then
      r:Hide()
    else
      local it, e = ln.it, ln.it.e
      local per = ns.Money(math.floor(it.cost / e.rep + 0.5))
      if it.spent then
        -- one of the best, but already filled today: red, outside the cost
        r.name:SetText("   |cffff4040" .. e.name .. " (already filled today)|r")
        r.how:SetText("|cffff4040not in the cost|r")
        r.rep:SetText("|cffff4040" .. e.rep .. "|r")
        r.per:SetText("|cffff4040" .. per .. "|r")
        r.cost:SetText("|cffff4040" .. ns.Money(it.cost) .. "|r")
        r.addBtn:Hide()
      else
        -- handed in since the plan was made
        r.name:SetText("   " .. (RANK_COLOR[e.rank] or "") .. e.name .. "|r"
          .. ((e.done and it.day == 1) and " |cff40ff40(done)|r" or ""))
        r.how:SetText(GREY .. (it.owned and "have writ" or "buy writ") .. " + "
          .. (it.crafted and "craft" or "buy") .. " " .. (e.qty > 1 and (e.qty .. "x ") or "") .. "item|r")
        r.rep:SetText(e.rep)
        r.per:SetText(per)
        r.cost:SetText(ns.Money(it.cost))
        r.addBtn:Show()
      end
      r:Show()
    end
  end
  pf.showCD:SetChecked(ShowCD())
  local cd = p and p.spent or 0
  pf.cd:SetText(cd > 0 and string.format("|cffff4040%d of the best already filled today|r%s", cd,
    ShowCD() and "" or " (hidden)") or "")
  if p then
    pf.title:SetText(string.format("Plan to %s: %s rep", STANDINGS[Target()][2], Num(p.need)))
    pf.total:SetText(string.format("%d writs, %s rep%s   Total %s", PlanCount(p), Num(p.rep),
      p.short and " |cffff4040(short of the target: regenerate tomorrow)|r" or "", ns.Money(p.cost)))
  else
    pf.title:SetText("Plan")
    pf.total:SetText(needRep and "No writ has a price yet." or "Pick a target standing first.")
  end
end

-- One plan entry's buys: the writ (unless you have it) and its fill: the item, or when the plan
-- crafts it, the recipe's reagents for that many.
local function EntryItems(it, items)
  local e = it.e
  if not it.owned then items[#items + 1] = { id = e.writ, name = "Craftsman's Writ: " .. e.name, qty = 1 } end
  local r = it.crafted and ns.Crafts and ns.Crafts[e.item]
  if r then
    for i = 3, #r do
      local id, n = r[i][1], r[i][2]
      local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)
      items[#items + 1] = { id = id, name = name or ("item " .. id), qty = math.ceil(n * e.qty / r[1]) }
    end
  else
    items[#items + 1] = { id = e.item, name = e.name, qty = e.qty }
  end
end

-- Adds the whole plan's buys to the cart: not the writs already filled today.
local function PlanToCart(p)
  local items = {}
  for _, it in ipairs(p.list) do
    if not it.spent and not (it.e.done and it.day == 1) then EntryItems(it, items) end
  end
  local n = ns.CartAdd(items)
  ns.Print(string.format("added %d to the cart.", n))
end

local function RowToCart(it)
  local items = {}
  EntryItems(it, items)
  ns.CartAdd(items)
  ns.Print("added " .. it.e.name .. " to the cart.")
end

-- Units to read per item for a writ scan: as many writs as the plan has days (one without a
-- plan), their items for that many with 25% to spare.
function ns.WritDepthWants()
  local n = (planMemo and planMemo.days and planMemo.days > 0) and planMemo.days or 1
  local wants = {}
  for _, e in ipairs(Entries()) do
    wants[e.writ] = math.max(wants[e.writ] or 0, n)
    local items = e.qty * n
    if items > 1 then items = math.ceil(items * 1.25) end
    wants[e.item] = math.max(wants[e.item] or 0, items)
  end
  return wants
end

local function UpdateWritScan()
  local b = frame and frame.scanBtn
  if not (b and ns.Depth) then return end
  local dp = ns.Depth
  if dp.state == "running" then
    b:SetText(string.format("Stop scan %d/%d", dp.done, math.max(dp.total, dp.done)))
    b:Enable()
  else
    b:SetText("Scan AH")
    b:SetEnabled(dp.atAH and true or false)
  end
end
ns.OnDepthChangedWrits = function()
  UpdateWritScan()
  if ns.Depth.state == "idle" then
    ns.InvalidateWrits()
    if frame and frame:IsShown() then ns.RefreshWrits() end
  end
end

function ns.ShowWritPlan()
  if not pf then
    pf = CreateFrame("Frame", "CrateCostWritPlan", UIParent, "BackdropTemplate")
    pf:SetSize(720, PTOP + PROWS * PROW_H + PFOOT)
    pf:SetPoint("CENTER", 0, 80)
    pf:SetFrameStrata("FULLSCREEN_DIALOG")
    pf:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    pf:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
    pf:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    pf:EnableMouse(true)
    pf:SetMovable(true)
    pf:SetClampedToScreen(true)
    pf:RegisterForDrag("LeftButton")
    pf:SetScript("OnDragStart", pf.StartMoving)
    pf:SetScript("OnDragStop", pf.StopMovingOrSizing)
    tinsert(UISpecialFrames, "CrateCostWritPlan")
    pf.title = pf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pf.title:SetPoint("TOPLEFT", 14, -12)
    local close = CreateFrame("Button", nil, pf, "UIPanelCloseButton")
    close:SetScript("OnClick", function() pf:Hide() end)
    close:SetPoint("TOPRIGHT", 2, 2)
    -- Regenerate: a new plan from your rep, writs and prices as they are now
    local regen = CreateFrame("Button", nil, pf, "UIPanelButtonTemplate")
    regen:SetSize(90, 20)
    regen:SetPoint("TOPRIGHT", -30, -8)
    regen:SetText("Regenerate")
    regen:SetScript("OnClick", function()
      ns.RegenerateWritPlan()
      pf.offset = 0
      FillPlan()
      if frame and frame:IsShown() then ns.RefreshWrits() end
    end)
    ns.UI.Tip(regen, "Regenerate", "Make the plan again from your rep, writs and prices as they are now. "
      .. "The plan otherwise stays as it was made.")
    -- show / hide writs on cooldown (done today)
    local cb = CreateFrame("CheckButton", nil, pf, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("RIGHT", regen, "LEFT", -150, 0)
    local cbl = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cbl:SetText("Show writs done today")
    cb:SetScript("OnClick", function(self)
      if type(CrateCostCharDB) ~= "table" then CrateCostCharDB = {} end
      CrateCostCharDB.planHideCD = not self:GetChecked() or nil
      pf.offset = 0
      FillPlan()
    end)
    ns.UI.Tip(cb, "Show writs done today", "The writs the plan would have used today but you've already "
      .. "filled (red, outside the cost), and the ones handed in since the plan was made. Untick to hide them.")
    pf.showCD = cb
    -- cooldowns change as writs are handed in
    pcall(pf.RegisterEvent, pf, "QUEST_TURNED_IN")
    pf:SetScript("OnEvent", function()
      C_Timer.After(0.3, function() if pf:IsShown() then Live() FillPlan() end end)
    end)
    pf.offset, pf.rows = 0, {}
    for i = 1, PROWS do
      local r = CreateFrame("Frame", nil, pf)
      r:SetHeight(PROW_H)
      r:SetPoint("TOPLEFT", 12, -PTOP - (i - 1) * PROW_H)
      r:SetPoint("RIGHT", pf, "RIGHT", -12, 0)
      local function Text(w, justify)
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetWidth(w)
        fs:SetJustifyH(justify)
        fs:SetWordWrap(false)
        return fs
      end
      -- name and route from the left; the numbers from the right, each in its own slot, so a
      -- long amount ("100g 11s 21c") can't run into the next column
      r.name = Text(240, "LEFT")
      r.name:SetPoint("LEFT", 0, 0)
      r.how = Text(150, "LEFT")
      r.how:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
      r.cost = Text(110, "RIGHT")
      r.per = Text(80, "RIGHT")
      r.rep = Text(46, "RIGHT")
      -- [+cart]: this writ and its fill
      local add = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
      add:SetSize(34, 17)
      add:SetPoint("RIGHT", 0, 0)
      add:SetText("")
      local plus = add:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      plus:SetPoint("LEFT", 6, 0)
      plus:SetText("+")
      local icon = add:CreateTexture(nil, "OVERLAY")
      icon:SetSize(13, 13)
      icon:SetPoint("LEFT", plus, "RIGHT", 2, 0)
      if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Perks-ShoppingCart") then
        icon:SetAtlas("Perks-ShoppingCart")
      else
        icon:SetTexture("Interface\\AddOns\\CrateCost\\cart")
      end
      add:SetScript("OnClick", function() if r.it then RowToCart(r.it) end end)
      add:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Add to cart", 1, 1, 1)
        GameTooltip:AddLine("The writ (unless you have it) and its fill: the item, or its reagents when "
          .. "the plan crafts it.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
      end)
      add:SetScript("OnLeave", function() GameTooltip:Hide() end)
      r.addBtn = add
      r.cost:SetPoint("RIGHT", add, "LEFT", -6, 0)
      r.per:SetPoint("RIGHT", r.cost, "LEFT", -10, 0)
      r.rep:SetPoint("RIGHT", r.per, "LEFT", -10, 0)
      r:EnableMouse(true)
      -- the writ's full tooltip, as on the writ list, then its place in the plan
      r:SetScript("OnEnter", function(self)
        local it = self.it
        if not it then return end
        local e = it.e
        self.entry = e
        ShowRowTooltip(self)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("In the plan", 1, 0.82, 0)
        GameTooltip:AddDoubleLine((it.owned and "Have writ" or "Buy writ") .. " + "
          .. (it.crafted and "craft" or "buy") .. " " .. (e.qty > 1 and (e.qty .. "x ") or "") .. "item",
          ns.Money(it.cost), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Per rep", ns.Money(math.floor(it.cost / e.rep + 0.5)), 1, 1, 1, 1, 1, 1)
        if e.done then GameTooltip:AddLine("Done today: on cooldown until the daily reset.", 1, 0.5, 0.25) end
        GameTooltip:Show()
        ns.AlignTitleRating(GameTooltip)
      end)
      r:SetScript("OnLeave", function() GameTooltip:Hide() end)
      r:EnableMouseWheel(true)
      r:SetScript("OnMouseWheel", function(_, delta) pf.offset = pf.offset - delta * 3 FillPlan() end)
      pf.rows[i] = r
    end
    local r1 = pf.rows[1]
    for _, h in ipairs({ { r1.name, "Writ", "LEFT" }, { r1.how, "Writ + item", "LEFT" }, { r1.rep, "Rep", "RIGHT" },
      { r1.per, "Per rep", "RIGHT" }, { r1.cost, "Cost", "RIGHT" } }) do
      local fs = pf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      fs:SetPoint("BOTTOMLEFT", h[1], "TOPLEFT", 0, 4)
      fs:SetPoint("BOTTOMRIGHT", h[1], "TOPRIGHT", 0, 4)
      fs:SetJustifyH(h[3])
      fs:SetText(h[2])
    end
    pf:EnableMouseWheel(true)
    pf:SetScript("OnMouseWheel", function(_, delta) pf.offset = pf.offset - delta * 3 FillPlan() end)
    pf.total = pf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pf.total:SetPoint("BOTTOMLEFT", 14, 42)
    pf.cd = pf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pf.cd:SetPoint("BOTTOMRIGHT", -14, 44)
    local add = CreateFrame("Button", nil, pf, "UIPanelButtonTemplate")
    pf.add = add
    add:SetSize(130, 22)
    add:SetPoint("BOTTOMLEFT", 12, 12)
    add:SetText("Add plan to cart")
    add:SetScript("OnClick", function()
      local p = CurrentPlan()
      if p then PlanToCart(p) end
    end)
    ns.UI.Tip(add, "Add plan to cart", "The plan's writs to buy and their fills: the item, or its reagents "
      .. "when the plan crafts it. Not the writs already filled today.")
    local note = pf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("LEFT", add, "RIGHT", 12, 0)
    note:SetPoint("RIGHT", pf, "RIGHT", -12, 0)
    note:SetJustifyH("LEFT")
    note:SetText("Each writ is a daily. Prices: AH listings when scanned (Scan AH on /crates), else Auctionator.")
  end
  if frame and frame:IsShown() then ns.RefreshWrits() else Calc() Live() UpdateNeed() end
  pf.offset = 0
  FillPlan()
  pf:Show()
end

function ns.ToggleWrits()
  if not frame then
    local ok, err = pcall(Build)
    if not ok then
      if frame then frame:Hide() end
      frame = nil
      wipe(headers)
      wipe(rows)
      ns.Print("couldn't open the writ list: " .. tostring(err))
      return
    end
    frame:Hide()
  end
  ns.UI.ToggleView(frame)
end
