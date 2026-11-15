local _, ns = ...

-- Favor plan: the cheapest way to a Merchant's Favor target. What you already have counts
-- first: your favor, the Sealed Crates in your bags (filled, waiting to be handed in) and the
-- one-time Shipping Label quest (50 favor). The rest comes from buying and filling crates:
-- crates you hold and bundle materials in your bags first, then bought up the scanned AH
-- listings (Depth.lua, else Auctionator), less each crate's turn-in silver. Only crates your
-- level can fill.
-- Each next crate is the one with the lowest extra cost per favor; near the target, a crate
-- that finishes it for less wins even at a worse rate. Crate costs only rise with the listings,
-- so this stays close to the cheapest mix.

local PROWS, ROW_H, TOP, FOOT = 22, 18, 84, 150
-- the recipe browser down the left; the plan to its right
local LEFT_W = 330
local PLAN_W = 800
local LEVEL = { Apprentice = 10, Journeyman = 10, Expert = 20, Artisan = 35 }
local LABEL_QUESTS, LABEL_FAVOR = { 98247, 98248 }, 50
local GREY = "|cff808080"

local f, plan
local BuildBrowser, FillBrowser   -- the recipe browser, further down

local function Num(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end

local function CharDB()
  if type(CrateCostCharDB) ~= "table" then CrateCostCharDB = {} end
  return CrateCostCharDB
end

-- The favor target (per character), or nil.
-- The wanted list (the Merchant view's stars): still to buy, and the favor they cost together.
local function Wanted()
  local all = ns.WantedRecipes and ns.WantedRecipes() or {}
  local left, sum = {}, 0
  for _, r in ipairs(all) do
    if not r.done then
      left[#left + 1] = r
      sum = sum + r.cost
    end
  end
  return left, sum, all
end

-- The target from the wanted list (per character, on by default): what the wanted recipes cost.
local function FromWanted() return CharDB().favorFromWanted ~= false end

-- The favor target (per character), or nil: the wanted recipes' cost while there are any and
-- that's on, else the number typed.
local function Target()
  if FromWanted() then
    local _, sum = Wanted()
    if sum > 0 then return sum end
  end
  local t = CharDB().favorTarget
  return (type(t) == "number" and t > 0) and t or nil
end

local function Count(id)
  if not (id and C_Item and C_Item.GetItemCount) then return 0 end
  local ok, n = pcall(C_Item.GetItemCount, id, true)
  return ok and n or 0
end

local function FavorHave()
  local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(3402)
  return (info and info.quantity) or 0
end

-- Sealed Crates in your bags: how many, and the favor they'll pay.
-- Sealed Crates in your bags: how many, the favor they'll pay, and their turn-in silver.
local function Sealed()
  local n, favor, pay = 0, 0, 0
  for id, sc in pairs(ns.SealedCrates or {}) do
    local k = Count(id)
    if k > 0 then
      local kind = sc[2] == "crafted" and "Fabrics" or "Ore"
      n = n + k
      favor = favor + k * (ns.FavorFor(sc[1], kind) or 0)
      pay = pay + k * ((ns.TurnInPay and ns.TurnInPay(sc[1], kind)) or 0)
    end
  end
  return n, favor, pay
end

local function LabelDone()
  if not (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then return true end
  for _, q in ipairs(LABEL_QUESTS) do
    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, q)
    if not ok or done then return true end
  end
  return false
end

-- One crate kind: Cost(n) = what filling n of it costs (crates you hold and materials in your
-- bags first), the bundle used, and whether it's priced past what the AH scan read.
local function Kind(c)
  -- the plan options: crates you hold, materials in your bags (ns.PlanUseOwned / PlanUseMats)
  local mats = ns.PlanUseMats()
  -- Craft mode: a bundle your profession makes, at its reagents' cost when that's cheaper
  local craft = ns.PlanCraft() and (ns.MyProfessions and ns.MyProfessions() or {}) or nil
  local k = { c = c, held = ns.PlanUseOwned() and Count(c.id) or 0, memo = {} }
  function k.Cost(n)
    local m = k.memo[n]
    if m then return m[1], m[2], m[3], m[4] end
    local buy = math.max(0, n - k.held)
    local crateCost, guess = 0, false
    if buy > 0 then
      local how
      crateCost, how = ns.FillCost(c.id, buy)
      if not crateCost or how.short then k.memo[n] = { nil } return nil end
      guess = how.guess or not how.depth
    end
    local best, bi, bguess
    for i, b in ipairs(c.bundles) do
      local id = ns.ItemIDs[b[1]]
      if id then
        local need = math.max(0, b[2] * n - (mats and Count(id) or 0))
        local bc, bh = 0, {}
        if need > 0 then bc, bh = ns.FillCost(id, need) end
        if bh.short then bc = nil end
        local made = false
        local r = craft and need > 0 and ns.Crafts and ns.Crafts[id]
        if r and craft[r[2]] and ns.ItemCraftCost then
          local unit = ns.ItemCraftCost(id)
          if unit and (not bc or unit * need < bc) then bc, made, bh = unit * need, true, { depth = true } end
        end
        if bc and (not best or bc < best) then
          best, bi, bguess = bc, i, need > 0 and not made and (bh.guess or not bh.depth) or false
          k.madeBundle = k.madeBundle or {}
          k.madeBundle[n] = made
        end
      end
    end
    if not best then k.memo[n] = { nil } return nil end
    -- cost: net of the turn-in silver; upFront: what the crates and bundles cost to buy
    local upFront = crateCost + best
    local cost = math.max(0, upFront - (c.pay1 or 0) * n)
    k.memo[n] = { cost, bi, guess or bguess, upFront }
    return cost, bi, guess or bguess, upFront
  end
  return k
end

-- { target, have, sealed, sealedFavor, label (favor or nil), need, favor (planned), cost, guess,
-- short, picks = { { c, n, cost, bundle, held, guess }, ... } }
-- The cheapest crates for `need` favor, one crate at a time from a snapshot of the AH listings:
-- each next crate is the one with the lowest extra cost per favor (so a kind is dropped for
-- another once its cheap crates or bundles run out); near the end, a crate that finishes it for
-- less wins. { picks = { { c, n, cost, pay, upFront, bundle, qty, bundleID, held, guess, crafted } },
-- favor, cost (net), pay, upFront, guess, short }
local function Mix(need)
  local m = { picks = {}, favor = 0, cost = 0, pay = 0, upFront = 0 }
  local level = UnitLevel and UnitLevel("player") or 60
  local kinds = {}
  for _, c in ipairs(ns.CrateEntries and ns.CrateEntries() or {}) do
    if c.id and c.favor and (LEVEL[c.rank] or 0) <= level then kinds[#kinds + 1] = Kind(c) end
  end
  local counts, spent = {}, {}
  local got = 0
  while got < need do
    local left = need - got
    local rateK, rate, finK, fin
    for i, k in ipairs(kinds) do
      local n = (counts[i] or 0) + 1
      local cost = k.Cost(n)
      if cost then
        local extra = cost - (spent[i] or 0)
        local r = extra / k.c.favor
        if not rate or r < rate then rateK, rate = i, r end
        -- one crate that reaches the target
        if k.c.favor >= left and (not fin or extra < fin) then finK, fin = i, extra end
      end
    end
    local pick = rateK
    if finK and fin <= (rate or math.huge) * kinds[rateK].c.favor then pick = finK end
    if not pick then break end
    counts[pick] = (counts[pick] or 0) + 1
    spent[pick] = kinds[pick].Cost(counts[pick])
    got = got + kinds[pick].c.favor
  end
  m.short = got < need
  for i, n in pairs(counts) do
    local k = kinds[i]
    local cost, bi, guess, upFront = k.Cost(n)
    local b = k.c.bundles[bi]
    local pay = (k.c.pay1 or 0) * n
    local crafted = k.madeBundle and k.madeBundle[n] or false
    table.insert(m.picks, { c = k.c, n = n, cost = cost, pay = pay, upFront = upFront, bundle = b[1], qty = b[2],
      bundleID = ns.ItemIDs[b[1]], held = math.min(n, k.held), guess = guess, crafted = crafted })
    m.pay = m.pay + pay
    m.upFront = m.upFront + upFront
    m.cost = m.cost + cost
    m.favor = m.favor + n * k.c.favor
    if guess then m.guess = true end
  end
  table.sort(m.picks, function(a, b) return a.cost / (a.n * a.c.favor) < b.cost / (b.n * b.c.favor) end)
  return m
end
-- for the rep plan's container favor
ns.FavorMix = Mix

local function MakePlan(target)
  local have = FavorHave()
  local sealedN, sealedFavor, sealedPay = Sealed()
  if not ns.PlanUseOwned() then sealedN, sealedFavor, sealedPay = 0, 0, 0 end
  local label = not LabelDone() and LABEL_FAVOR or nil
  local p = { target = target, have = have, sealed = sealedN, sealedFavor = sealedFavor, sealedPay = sealedPay,
    label = label }
  p.need = math.max(0, target - have - sealedFavor - (label or 0))
  local m = Mix(p.need)
  p.picks, p.favor, p.cost, p.pay, p.upFront, p.guess, p.short = m.picks, m.favor, m.cost, m.pay, m.upFront, m.guess, m.short
  return p
end

local function Regenerate()
  local t = Target()
  plan = t and MakePlan(t) or nil
  if ns.RefreshChecklists then ns.RefreshChecklists() end
end

-- For the Home view.
function ns.FavorStatus()
  local sealedN, sealedFavor = Sealed()
  local st = { have = FavorHave(), sealed = sealedN, sealedFavor = sealedFavor, target = Target(),
    labelDone = LabelDone() }
  if st.target and (not plan or plan.target ~= st.target) then Regenerate() end
  st.plan = st.target and plan or nil
  return st
end

-- Units for a scan: every crate and its bundles, deep enough for what's left to earn.
local function Wants()
  local wants = {}
  local need = plan and plan.need or 0
  if need <= 0 and Target() then need = math.max(0, Target() - FavorHave()) end
  if ns.FavorDepthWants then ns.FavorDepthWants(math.max(need, 1), 0, wants) end
  return wants
end

------------------------------------------------------------------------------------------------
-- The view

local function Lines(p)
  local lines = {}
  -- what the favor is for: the wanted recipes (learned ones greyed), with a running total
  local _, sum, all = Wanted()
  if #all > 0 then
    lines[#lines + 1] = { head = "Wanted: " .. Num(sum) .. " favor still to buy" }
    local run = 0
    for _, w in ipairs(all) do
      if not w.done then run = run + w.cost end
      lines[#lines + 1] = { want = w, run = run }
    end
  end
  if p.need > 0 or #p.picks > 0 or p.sealed > 0 or p.label then
    lines[#lines + 1] = { head = "How to get it" }
  end
  if p.sealed > 0 then lines[#lines + 1] = { sealed = true } end
  if p.label then lines[#lines + 1] = { label = true } end
  for _, pick in ipairs(p.picks) do lines[#lines + 1] = { pick = pick } end
  return lines
end

local function PickItems(pick, items)
  local c = pick.c
  local buy = pick.n - pick.held
  if buy > 0 then items[#items + 1] = { id = c.id, name = "Waylaid Crate: " .. c.name, qty = buy } end
  local need = pick.crafted and 0 or math.max(0, pick.qty * pick.n - (ns.PlanUseMats() and Count(pick.bundleID) or 0))
  if need > 0 then items[#items + 1] = { id = pick.bundleID, name = pick.bundle, qty = need } end
end

local function Fill()
  local p = plan
  local t = Target()
  if not f.box:HasFocus() then f.box:SetText(t and tostring(t) or "") end
  local _, wsum = Wanted()
  f.wantedCheck:SetChecked(FromWanted() and wsum > 0)
  local sealedN, sealedFavor = Sealed()
  local have = FavorHave()
  local icon = ns.FavorIcon and ns.FavorIcon() or ""
  local txt = "You have " .. Num(have) .. icon
  if sealedN > 0 then txt = txt .. "  + " .. Num(sealedFavor) .. " in " .. sealedN .. " Sealed Crates" end
  if t then
    local left = t - have - sealedFavor
    txt = txt .. "   " .. (left > 0 and (Num(left) .. " to go") or "|cff40ff40target reached|r")
  end
  f.status:SetText(txt)
  local lines = p and Lines(p) or {}
  f.offset = math.max(0, math.min(f.offset, #lines - PROWS))
  for i = 1, PROWS do
    local r, ln = f.rows[i], lines[f.offset + i]
    r.pick = (ln and ln.pick) or false
    r.want = (ln and ln.want) or false
    r.kind = (ln and ((ln.sealed and "sealed") or (ln.label and "label"))) or false
    if not ln then
      r:Hide()
    else
      r.add:Hide()
      r.buy:Hide()
      r.per:SetText("")
      if ln.head then
        r.name:SetText("|cffffd100" .. ln.head .. "|r")
        r.how:SetText("")
        r.favor:SetText("")
        r.cost:SetText("")
      elseif ln.want then
        -- a wanted recipe: Buy while its vendor is open
        local w = ln.want
        local rep = ns.WantedRepName and ns.WantedRepName(w.rep) or ""
        if w.done then
          r.name:SetText("   " .. GREY .. w.name .. "  (learned)|r")
        else
          r.name:SetText("   " .. w.name)
        end
        r.how:SetText(GREY .. w.prof .. (rep ~= "" and (", " .. rep) or "") .. "|r")
        r.favor:SetText(w.done and (GREY .. Num(w.cost) .. "|r") or Num(w.cost))
        -- the running total of what's still to buy
        r.cost:SetText(w.done and "" or (GREY .. "total " .. "|r" .. Num(ln.run)))
        if not w.done then ns.UI.SetBuy(r.buy, w.item or w.name, 1) end
      elseif ln.sealed then
        r.name:SetText("   |cffffd100Hand in " .. p.sealed .. " Sealed Crates|r")
        r.how:SetText(GREY .. "already filled, in your bags|r")
        r.favor:SetText(Num(p.sealedFavor))
        r.cost:SetText((p.sealedPay or 0) > 0 and ("|cff40ff40+" .. ns.Money(p.sealedPay) .. "|r") or (GREY .. "free|r"))
      elseif ln.label then
        r.name:SetText("   |cffffd100Shipping Label quest (one time)|r")
        r.how:SetText(GREY .. "comes with your first filled crate|r")
        r.favor:SetText(Num(p.label))
        r.cost:SetText(GREY .. "free|r")
      else
        local pick = ln.pick
        local c = pick.c
        r.name:SetText("   Buy + fill " .. pick.n .. "x " .. c.name
          .. (pick.held > 0 and (GREY .. "  (" .. pick.held .. " you have)|r") or ""))
        r.how:SetText(GREY .. (pick.crafted and "craft " or "") .. pick.qty .. " " .. pick.bundle .. " each|r")
        r.favor:SetText(Num(pick.n * c.favor))
        r.per:SetText(ns.Money(math.floor(pick.cost / (pick.n * c.favor) + 0.5)))
        -- what you pay for the crates and bundles; per favor is net of the turn-in silver
        r.cost:SetText((pick.guess and "|cffff9933~|r" or "") .. ns.Money(pick.upFront))
        r.add:Show()
      end
      r:Show()
    end
  end
  if p then
    local extra = (p.sealed > 0 and p.sealedFavor or 0) + (p.label or 0)
    local n = 0
    for _, k in ipairs(p.picks) do n = n + k.n end
    f.total:SetText(string.format("%d crates to fill, %s favor%s", n, Num(p.favor + extra),
      p.short and " |cffff4040(not enough crates on the AH)|r" or ""))
    -- you buy everything first; the turn-in silver (and the Sealed Crates') comes back after
    local back = p.pay + (p.sealedPay or 0)
    ns.UI.PlanMoney(f, p.upFront or 0, back, p.guess)
    f.note:SetText(p.guess and "|cffff9933~ = more than the AH scan read, so the price is too low: Scan AH "
      .. "reads what this plan needs, then remakes it.|r"
      or "Crates you hold and materials in your bags are used first. Prices: AH listings when scanned, else Auctionator.")
  else
    f.total:SetText(t and "No crate has a price yet." or "Type how much Merchant's Favor you want.")
    ns.UI.PlanMoney(f)
    f.note:SetText("")
  end
end

local function UpdateScan()
  if f and f.scan then ns.UI.UpdateScan(f.scan) end
end

function ns.OnDepthChangedFavor()
  if not f then return end
  UpdateScan()
  if ns.Depth.state == "idle" and f:IsShown() then
    if ns.InvalidateCrates then ns.InvalidateCrates() end
    Regenerate()
    Fill()
  end
end

local function Build()
  local UI = ns.UI
  f = UI.Window("CrateCostFavorPlan", "Favor plan", LEFT_W + PLAN_W, TOP + PROWS * ROW_H + FOOT, UI.POS_KEY)
  f:Hide()
  UI.NavBar(f, "favor", function()
    if ns.InvalidateCrates then ns.InvalidateCrates() end
    Regenerate()
    f.offset = 0
    Fill()
  end)
  f.status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.status:SetPoint("LEFT", f.title, "RIGHT", 24, 0)

  -- filter row: the favor target, Scan AH, then open-with-the-AH and Regenerate on the right
  local tl = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  tl:SetPoint("TOPLEFT", LEFT_W + 18, UI.FILTER_Y - 3)
  tl:SetText("Target favor:")
  local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  box:SetSize(70, 20)
  box:SetPoint("LEFT", tl, "RIGHT", 10, 0)
  box:SetAutoFocus(false)
  box:SetNumeric(true)
  box:SetMaxLetters(6)
  box:SetJustifyH("CENTER")
  local function Save(self)
    local t = tonumber(self:GetText())
    if t == 0 then t = nil end
    if t == Target() then return end
    CharDB().favorTarget = t
    CharDB().favorFromWanted = false
    Regenerate()
    f.offset = 0
    Fill()
  end
  box:SetScript("OnEnterPressed", function(self) Save(self) self:ClearFocus() end)
  box:SetScript("OnEditFocusLost", Save)
  box:SetScript("OnEscapePressed", function(self) self:SetText(Target() and tostring(Target()) or "") self:ClearFocus() end)
  UI.Tip(box, "Target favor", "How much Merchant's Favor you want in all (what you have counts). Enter to "
    .. "plan. Typing one stops the target following the wanted recipes.")
  f.box = box

  local scan = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  scan:SetSize(130, 20)
  scan:SetPoint("LEFT", box, "RIGHT", 14, 0)
  scan:SetScript("OnClick", function()
    if ns.Depth.state == "running" then ns.Depth.Stop() else ns.Depth.Start(Wants()) end
  end)
  UI.Tip(scan, "Scan AH", "Reads the auction house listings for every crate and its bundles, deep enough for "
    .. "what's left to earn, then remakes the plan with them.")
  f.scan = scan
  -- the target from the wanted recipes, and the way to pick them (the Merchant view's stars)
  local wcb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  wcb:SetSize(22, 22)
  wcb:SetPoint("LEFT", scan, "RIGHT", 12, 0)
  local wl = wcb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  wl:SetPoint("LEFT", wcb, "RIGHT", 1, 0)
  wl:SetText("Target = wanted recipes")
  wcb:SetScript("OnClick", function(self)
    CharDB().favorFromWanted = self:GetChecked() and true or false
    Regenerate()
    f.offset = 0
    Fill()
  end)
  UI.Tip(wcb, "Target = wanted recipes", "The target is what your wanted recipes cost (the stars in the "
    .. "Merchant view). Untick to type your own.")
  f.wantedCheck = wcb

  -- use what you have / materials you have (shared with the rep plan)
  UI.PlanOptions(f, LEFT_W + 14, 34, function()
    Regenerate()
    f.offset = 0
    Fill()
  end)

  local regen = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  regen:SetSize(90, 20)
  regen:SetPoint("TOPRIGHT", -18, UI.FILTER_Y)
  regen:SetText("Regenerate")
  regen:SetScript("OnClick", function()
    if ns.InvalidateCrates then ns.InvalidateCrates() end
    Regenerate()
    f.offset = 0
    Fill()
  end)
  UI.Tip(regen, "Regenerate", "Make the plan again from your favor, crates, bags and prices as they are now.")
  -- Buy | Craft (shared with the rep plan)
  f.craftToggle = UI.CraftToggle(f, regen, function()
    if ns.InvalidateCrates then ns.InvalidateCrates() end
    Regenerate()
    f.offset = 0
    Fill()
  end)
  local ah = UI.PlanAtAHCheck(f, regen)
  ah:ClearAllPoints()
  ah:SetPoint("BOTTOMLEFT", LEFT_W + 14, 12)

  f.offset, f.rows = 0, {}
  for i = 1, PROWS do
    local r = CreateFrame("Frame", nil, f)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", LEFT_W + 12, -TOP - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    local function Text(w, justify)
      local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetWidth(w)
      fs:SetJustifyH(justify)
      fs:SetWordWrap(false)
      return fs
    end
    r.name = Text(240, "LEFT")
    r.name:SetPoint("LEFT", 0, 0)
    r.how = Text(150, "LEFT")
    r.how:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
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
    add:SetScript("OnClick", function()
      if not r.pick then return end
      local items = {}
      PickItems(r.pick, items)
      ns.CartAdd(items)
      ns.Print("added " .. r.pick.c.name .. " crates and bundles to the cart.")
    end)
    UI.Tip(add, "Add to cart", "The crates to buy (not the ones you hold) and the bundle materials not in your bags.")
    r.add = add
    r.buy = UI.BuyButton(r)
    r.buy:SetPoint("RIGHT", 0, 0)
    r.cost = Text(110, "RIGHT")
    r.cost:SetPoint("RIGHT", add, "LEFT", -6, 0)
    r.per = Text(80, "RIGHT")
    r.per:SetPoint("RIGHT", r.cost, "LEFT", -10, 0)
    r.favor = Text(60, "RIGHT")
    r.favor:SetPoint("RIGHT", r.per, "LEFT", -10, 0)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if self.want then
        local w = self.want
        if not (w.item and pcall(GameTooltip.SetItemByID, GameTooltip, w.item)) then GameTooltip:AddLine(w.name) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Favor", Num(w.cost), 1, 1, 1, 1, 1, 1)
        local rep = ns.WantedRepName and ns.WantedRepName(w.rep) or ""
        if rep ~= "" then GameTooltip:AddDoubleLine("Needs", rep, 1, 1, 1, 1, 1, 1) end
        GameTooltip:AddLine(w.done and "Learned." or "Buy it with Buy while its vendor is open. Right-click to drop it.",
          0.6, 0.8, 1, true)
        GameTooltip:Show()
        return
      elseif self.kind == "sealed" then
        GameTooltip:AddLine("Sealed Crates")
        GameTooltip:AddLine("Crates you've already filled. Hand them in at the camp for their favor.", 1, 1, 1, true)
      elseif self.kind == "label" then
        GameTooltip:AddLine("Shipping Label quest")
        GameTooltip:AddLine("Your first filled crate gives a Shipping Label. Deliver it at the camp for 50 "
          .. "Merchant's Favor (and 2,000 rep), once per character.", 1, 1, 1, true)
      elseif self.pick then
        local pick, c = self.pick, self.pick.c
        GameTooltip:AddLine("Waylaid Crate: " .. c.name)
        GameTooltip:AddDoubleLine("Crates", pick.n .. (pick.held > 0 and (" (" .. pick.held .. " you have)") or ""), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Fill each with", pick.qty .. " " .. pick.bundle, 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Favor", Num(pick.n * c.favor) .. " (" .. c.favor .. " each)", 1, 1, 1, 1, 1, 1)
        if (c.pay1 or 0) > 0 then
          GameTooltip:AddDoubleLine("Turn-in silver back", "-" .. ns.Money(c.pay1 * pick.n), 1, 1, 1, 0.25, 1, 0.25)
        end
        GameTooltip:AddDoubleLine("You pay", ns.Money(pick.upFront), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Net", ns.Money(pick.cost), 1, 0.82, 0, 1, 1, 1)
        if pick.guess then
          GameTooltip:AddLine("~ more than the AH scan read: Scan AH for the real price.", 1, 0.6, 0.2, true)
        end
      else
        return
      end
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(_, delta) f.offset = f.offset - delta * 3 Fill() end)
    r:SetScript("OnMouseUp", function(self, button)
      if button == "RightButton" and self.want and ns.UnwantRecipe then ns.UnwantRecipe(self.want.key) end
    end)
    f.rows[i] = r
  end
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta) f.offset = f.offset - delta * 3 Fill() end)
  -- column headings over row 1
  local r1 = f.rows[1]
  for _, h in ipairs({ { r1.name, "Step", "LEFT" }, { r1.how, "Fill with", "LEFT" }, { r1.favor, "Favor", "RIGHT" },
    { r1.per, "Per favor", "RIGHT" }, { r1.cost, "Cost", "RIGHT" } }) do
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("BOTTOMLEFT", h[1], "TOPLEFT", 0, 4)
    fs:SetPoint("BOTTOMRIGHT", h[1], "TOPRIGHT", 0, 4)
    fs:SetJustifyH(h[3])
    fs:SetText(h[2])
  end
  UI.PlanFooter(f, function()
    if not plan then return end
    local items = {}
    for _, pick in ipairs(plan.picks) do PickItems(pick, items) end
    ns.Print(string.format("added %d to the cart.", ns.CartAdd(items)))
  end, "Every crate to buy and the bundle materials not in your bags.", "favor", LEFT_W / 2)
  f.total = f.summary
  BuildBrowser()
  -- bags, favor and hand-ins change what's left
  for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "CURRENCY_DISPLAY_UPDATE" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(ev) then
      pcall(f.RegisterEvent, f, ev)
    end
  end
  local pending = false
  f:SetScript("OnEvent", function()
    if pending or not f:IsShown() then return end
    pending = true
    C_Timer.After(0.5, function() pending = false if f:IsShown() then Fill() end end)
  end)
end

------------------------------------------------------------------------------------------------
-- The recipe browser, down the left: the Merchant's list with Add (or Drop) on each. Adding
-- puts it on the wanted list, which the plan on the right saves for. Filters as on the Merchant
-- view and AuctionatorSync's price list: search, profession, type / slot, stats (with a
-- minimum), sort by a stat, and hide what you've learned.

local BROWSE_TOP, BROWSE_H = 98, 18
local browse = { search = "", prof = nil, kind = nil, hideKnown = true, stats = {}, statSort = nil,
  statLow = false, offset = 0 }

local function BrowseList()
  local mine = browse.prof == "mine" and ns.MyProfessions and ns.MyProfessions() or nil
  local out = {}
  for _, e in ipairs(ns.RecipeEntries and ns.RecipeEntries() or {}) do
    local ok = true
    if browse.hideKnown and e.known and not e.wanted then ok = false end
    if ok and mine and not mine[e.prof] then ok = false end
    if ok and browse.prof and browse.prof ~= "mine" and e.prof ~= browse.prof then ok = false end
    if ok and browse.kind then
      local v = browse.kind.group == "type" and e.type or e.slot
      if v ~= browse.kind.value then ok = false end
    end
    if ok and browse.search ~= "" and not e.text:find(browse.search, 1, true) then ok = false end
    if ok and (next(browse.stats) or browse.statSort) and ns.EntryStats then
      local st = ns.EntryStats(e)
      for k, min in pairs(browse.stats) do
        local v = st[k]
        if not v or (type(min) == "number" and v < min) then ok = false break end
      end
      e.sortValue = browse.statSort and st[browse.statSort] or nil
    end
    if ok then out[#out + 1] = e end
  end
  table.sort(out, function(a, b)
    if browse.statSort then
      local va, vb = a.sortValue, b.sortValue
      if (va ~= nil) ~= (vb ~= nil) then return va ~= nil end
      if va and va ~= vb then if browse.statLow then return va < vb end return va > vb end
    end
    if a.prof ~= b.prof then return a.prof < b.prof end
    if a.cost ~= b.cost then return a.cost < b.cost end
    return a.name < b.name
  end)
  return out
end

FillBrowser = function()
  local list = BrowseList()
  local rows = f.browseRows
  local n = #rows
  browse.offset = math.max(0, math.min(browse.offset, #list - n))
  f.browseCount:SetText(GREY .. #list .. " shown|r")
  -- the scrollbar: shown when there's more than fits
  if #list > n then
    local track = tonumber(f.browseTrack:GetHeight()) or (n * BROWSE_H)
    local th = math.max(16, track * n / #list)
    f.browseThumb:SetHeight(th)
    f.browseThumb:ClearAllPoints()
    f.browseThumb:SetPoint("TOP", f.browseTrack, "TOP", 0, -(track - th) * browse.offset / math.max(1, #list - n))
    f.browseTrack:Show()
    f.browseThumb:Show()
  else
    f.browseTrack:Hide()
    f.browseThumb:Hide()
  end
  for i, r in ipairs(rows) do
    local e = list[browse.offset + i]
    r.entry = e or false
    if not e then
      r:Hide()
    else
      local col = e.known and GREY or (e.wanted and "|cff40ff40" or "|cffffffff")
      r.name:SetText(col .. e.name .. "|r")
      -- sorting by a stat: its value in place of the profession
      if browse.statSort and e.sortValue and ns.StatLabel then
        r.prof:SetText("|cffffd100" .. e.sortValue .. " " .. ns.StatLabel(browse.statSort) .. "|r")
      else
        r.prof:SetText(GREY .. e.prof .. "|r")
      end
      r.cost:SetText(Num(e.cost))
      r.add:SetText(e.wanted and "Drop" or "Add")
      r.add:SetShown(not (e.known and not e.wanted))
      r:Show()
    end
  end
  -- the dropdowns' labels
  local p = browse.prof
  f.browseProf.text:SetText(p == "mine" and "My professions" or p or "All professions")
  f.browseKind.text:SetText(browse.kind and browse.kind.value or "All types")
  local ns_ = 0
  for _ in pairs(browse.stats) do ns_ = ns_ + 1 end
  f.browseStats:SetText(ns_ > 0 and ("Stats (" .. ns_ .. ")") or "Stats")
  f.browseSort:SetText(browse.statSort and ns.StatLabel and ns.StatLabel(browse.statSort) or "Sort")
end

BuildBrowser = function()
  local UI = ns.UI
  local function Refresh() FillBrowser() end
  -- the pane: a slightly lighter panel with a rule at its edge
  local pane = f:CreateTexture(nil, "BACKGROUND", nil, 2)
  pane:SetPoint("TOPLEFT", 1, -28)
  pane:SetPoint("BOTTOMLEFT", 1, 1)
  pane:SetWidth(LEFT_W - 4)
  pane:SetColorTexture(1, 1, 1, 0.03)
  local rule = f:CreateTexture(nil, "ARTWORK")
  rule:SetWidth(1)
  rule:SetPoint("TOPLEFT", LEFT_W - 3, -28)
  rule:SetPoint("BOTTOMLEFT", LEFT_W - 3, 6)
  rule:SetColorTexture(1, 0.82, 0, 0.25)

  -- row 1: search, hide learned
  local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  search:SetSize(170, 20)
  search:SetPoint("TOPLEFT", 18, UI.FILTER_Y)
  search:SetAutoFocus(false)
  local hint = search:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("LEFT", 2, 0)
  hint:SetText("Search recipes")
  search:SetScript("OnTextChanged", function(self)
    local t = (self:GetText() or ""):lower():match("^%s*(.-)%s*$")
    hint:SetShown(t == "" and not self:HasFocus())
    if t ~= browse.search then
      browse.search, browse.offset = t, 0
      FillBrowser()
    end
  end)
  search:SetScript("OnEditFocusGained", function() hint:Hide() end)
  search:SetScript("OnEditFocusLost", function(self) hint:SetShown((self:GetText() or "") == "") end)
  search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  local hk = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  hk:SetSize(20, 20)
  hk:SetPoint("LEFT", search, "RIGHT", 10, 0)
  local hkl = hk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hkl:SetPoint("LEFT", hk, "RIGHT", 0, 0)
  hkl:SetText("Hide learned")
  hk:SetChecked(browse.hideKnown)
  hk:SetScript("OnClick", function(self) browse.hideKnown = self:GetChecked() and true or false browse.offset = 0 FillBrowser() end)
  UI.Tip(hk, "Hide learned", "Leave out what you've learned already.")

  -- row 2: profession, type / slot, stats, sort by stat
  local y2 = UI.FILTER_Y - 26
  local anchor = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  anchor:SetPoint("TOPLEFT", 12, y2 - 3)
  anchor:SetText("")
  local pb = UI.DropButton(f, 104, anchor, 0)
  f.browseProf = pb
  local profChoices = { { "All professions", nil }, { "My professions", "mine" }, "-" }
  for _, pr in ipairs(ns.RecipeProfessions or {}) do profChoices[#profChoices + 1] = { pr, pr } end
  UI.Menu(f, pb, profChoices, 130, function(v) browse.prof, browse.offset = v, 0 FillBrowser() end)
  local kb = UI.DropButton(f, 84, pb, 4)
  f.browseKind = kb
  -- types and slots that some recipe has
  local types, slots, seenT, seenS = {}, {}, {}, {}
  for _, e in ipairs(ns.RecipeEntries and ns.RecipeEntries() or {}) do
    if e.type and e.type ~= "" and not seenT[e.type] then seenT[e.type] = true types[#types + 1] = e.type end
    if e.slot and e.slot ~= "" and not seenS[e.slot] then seenS[e.slot] = true slots[#slots + 1] = e.slot end
  end
  table.sort(types)
  table.sort(slots)
  local kindChoices = { { "All types", nil }, "-", { heading = "Type" } }
  for _, t in ipairs(types) do kindChoices[#kindChoices + 1] = { t, { group = "type", value = t } } end
  if #slots > 0 then
    kindChoices[#kindChoices + 1] = "-"
    kindChoices[#kindChoices + 1] = { heading = "Slot" }
    for _, sl in ipairs(slots) do kindChoices[#kindChoices + 1] = { sl, { group = "slot", value = sl } } end
  end
  UI.Menu(f, kb, kindChoices, 140, function(v) browse.kind, browse.offset = v, 0 FillBrowser() end)
  local sb = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  sb:SetSize(58, 20)
  sb:SetPoint("LEFT", kb, "RIGHT", 4, 0)
  sb:SetText("Stats")
  f.browseStats = sb
  local statsMenu = ns.BuildStatsMenu and ns.BuildStatsMenu(sb, browse, Refresh)
  local srt = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  srt:SetSize(58, 20)
  srt:SetPoint("LEFT", sb, "RIGHT", 2, 0)
  srt:SetText("Sort")
  f.browseSort = srt
  local sortMenu = ns.BuildStatSortMenu and ns.BuildStatSortMenu(srt, browse, Refresh)
  f:HookScript("OnHide", function()
    if statsMenu then statsMenu:Hide() end
    if sortMenu then sortMenu:Hide() end
  end)

  -- headings, on their own line
  local hName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hName:SetPoint("TOPLEFT", 14, -BROWSE_TOP + 14)
  hName:SetText("Merchant's recipes")
  f.browseCount = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.browseCount:SetPoint("LEFT", hName, "RIGHT", 8, 0)
  local hCost = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hCost:SetPoint("TOPRIGHT", f, "TOPLEFT", LEFT_W - 64, -BROWSE_TOP + 14)
  hCost:SetText("Favor")

  -- the scrollbar, at the pane's right edge
  local H = TOP + PROWS * ROW_H + FOOT
  f.browseTrack = f:CreateTexture(nil, "ARTWORK")
  f.browseTrack:SetWidth(4)
  f.browseTrack:SetPoint("TOPLEFT", LEFT_W - 12, -BROWSE_TOP)
  f.browseTrack:SetPoint("BOTTOMLEFT", LEFT_W - 12, 10)
  f.browseTrack:SetColorTexture(1, 1, 1, 0.08)
  f.browseThumb = f:CreateTexture(nil, "OVERLAY")
  f.browseThumb:SetWidth(4)
  f.browseThumb:SetColorTexture(1, 0.82, 0, 0.6)

  -- rows: as many as the height holds
  local n = math.floor((H - BROWSE_TOP - 12) / BROWSE_H)
  f.browseRows = {}
  for i = 1, n do
    local r = CreateFrame("Frame", nil, f)
    r:SetHeight(BROWSE_H)
    r:SetPoint("TOPLEFT", 10, -BROWSE_TOP - (i - 1) * BROWSE_H)
    r:SetWidth(LEFT_W - 28)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.07)
    r.add = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.add:SetSize(42, 16)
    r.add:SetPoint("RIGHT", 0, 0)
    r.add:SetScript("OnClick", function()
      local e = r.entry
      if e and ns.SetWanted then ns.SetWanted(e.key, not e.wanted) end
    end)
    r.cost = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.cost:SetPoint("RIGHT", r.add, "LEFT", -6, 0)
    r.cost:SetWidth(40)
    r.cost:SetJustifyH("RIGHT")
    r.name = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", 2, 0)
    r.name:SetWidth(150)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.prof = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.prof:SetPoint("LEFT", r.name, "RIGHT", 4, 0)
    r.prof:SetPoint("RIGHT", r.cost, "LEFT", -4, 0)
    r.prof:SetJustifyH("LEFT")
    r.prof:SetWordWrap(false)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
      local e = self.entry
      if not e then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      local shown = false
      if e.item then shown = pcall(GameTooltip.SetItemByID, GameTooltip, e.item) end
      if not shown and e.craft then shown = pcall(GameTooltip.SetItemByID, GameTooltip, e.craft) end
      if not shown and e.spell and GameTooltip.SetSpellByID then shown = pcall(GameTooltip.SetSpellByID, GameTooltip, e.spell) end
      if not shown then GameTooltip:AddLine(e.name) end
      GameTooltip:AddLine(" ")
      GameTooltip:AddDoubleLine(e.name, e.prof .. (e.type and e.type ~= "" and (", " .. e.type) or ""), 1, 0.82, 0, 1, 1, 1)
      GameTooltip:AddDoubleLine("Favor", Num(e.cost), 1, 1, 1, 1, 1, 1)
      local rep = ns.WantedRepName and ns.WantedRepName(e.rep) or ""
      if rep ~= "" then GameTooltip:AddDoubleLine("Needs", rep, 1, 1, 1, 1, 1, 1) end
      GameTooltip:AddLine(e.wanted and "On your wanted list." or (e.known and "Learned." or "Add: the plan saves for it."),
        0.6, 0.8, 1, true)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(_, dl) browse.offset = browse.offset - dl * 3 FillBrowser() end)
    f.browseRows[i] = r
  end
end

function ns.OnWantedChanged()
  Regenerate()
  if f and f:IsShown() then Fill() FillBrowser() end
  if ns.RefreshHome then ns.RefreshHome() end
end

ns.UI.OnMerchant(function()
  if f and f:IsShown() then Fill() end
end)

function ns.ShowFavorPlan()
  if not f then
    local ok, err = pcall(Build)
    if not ok then
      f = nil
      ns.Print("couldn't open the favor plan: " .. tostring(err))
      return
    end
  end
  CharDB().lastPlan = "favor"
  if not plan or plan.target ~= Target() then Regenerate() end
  f.offset = 0
  Fill()
  FillBrowser()
  UpdateScan()
  ns.UI.Open(f)
end

-- For Home: set the favor target from there; the plan follows.
function ns.SetFavorTarget(t)
  if t == 0 then t = nil end
  CharDB().favorTarget = t
  Regenerate()
  if f and f:IsShown() then f.offset = 0 Fill() end
end
