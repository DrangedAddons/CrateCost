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

local PROWS, ROW_H, TOP, FOOT = 26, 18, 84, 70
local LEVEL = { Apprentice = 10, Journeyman = 10, Expert = 20, Artisan = 35 }
local LABEL_QUESTS, LABEL_FAVOR = { 98247, 98248 }, 50
local GREY = "|cff808080"

local f, plan

local function Num(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end

local function CharDB()
  if type(CrateCostCharDB) ~= "table" then CrateCostCharDB = {} end
  return CrateCostCharDB
end

-- The favor target (per character), or nil.
local function Target()
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
local function Sealed()
  local n, favor = 0, 0
  for id, sc in pairs(ns.SealedCrates or {}) do
    local k = Count(id)
    if k > 0 then
      n = n + k
      favor = favor + k * (ns.FavorFor(sc[1], sc[2] == "crafted" and "Fabrics" or "Ore") or 0)
    end
  end
  return n, favor
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
  local k = { c = c, held = Count(c.id), memo = {} }
  function k.Cost(n)
    local m = k.memo[n]
    if m then return m[1], m[2], m[3] end
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
        local need = math.max(0, b[2] * n - Count(id))
        local bc, bh = 0, {}
        if need > 0 then bc, bh = ns.FillCost(id, need) end
        if bc and not bh.short and (not best or bc < best) then
          best, bi, bguess = bc, i, need > 0 and (bh.guess or not bh.depth) or false
        end
      end
    end
    if not best then k.memo[n] = { nil } return nil end
    local cost = math.max(0, crateCost + best - (c.pay1 or 0) * n)
    k.memo[n] = { cost, bi, guess or bguess }
    return cost, bi, guess or bguess
  end
  return k
end

-- { target, have, sealed, sealedFavor, label (favor or nil), need, favor (planned), cost, guess,
-- short, picks = { { c, n, cost, bundle, held, guess }, ... } }
local function MakePlan(target)
  local have = FavorHave()
  local sealedN, sealedFavor = Sealed()
  local label = not LabelDone() and LABEL_FAVOR or nil
  local p = { target = target, have = have, sealed = sealedN, sealedFavor = sealedFavor, label = label,
    favor = 0, cost = 0, picks = {} }
  p.need = math.max(0, target - have - sealedFavor - (label or 0))
  local level = UnitLevel and UnitLevel("player") or 60
  local kinds = {}
  for _, c in ipairs(ns.CrateEntries and ns.CrateEntries() or {}) do
    if c.id and c.favor and (LEVEL[c.rank] or 0) <= level then kinds[#kinds + 1] = Kind(c) end
  end
  local counts, spent = {}, {}
  local got = 0
  while got < p.need do
    local left = p.need - got
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
  p.short = got < p.need
  for i, n in pairs(counts) do
    local k = kinds[i]
    local cost, bi, guess = k.Cost(n)
    local b = k.c.bundles[bi]
    table.insert(p.picks, { c = k.c, n = n, cost = cost, bundle = b[1], qty = b[2], bundleID = ns.ItemIDs[b[1]],
      held = math.min(n, k.held), guess = guess })
    p.cost = p.cost + cost
    p.favor = p.favor + n * k.c.favor
    if guess then p.guess = true end
  end
  table.sort(p.picks, function(a, b) return a.cost / (a.n * a.c.favor) < b.cost / (b.n * b.c.favor) end)
  return p
end

local function Regenerate()
  local t = Target()
  plan = t and MakePlan(t) or nil
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
  if p.sealed > 0 then lines[#lines + 1] = { sealed = true } end
  if p.label then lines[#lines + 1] = { label = true } end
  for _, pick in ipairs(p.picks) do lines[#lines + 1] = { pick = pick } end
  return lines
end

local function PickItems(pick, items)
  local c = pick.c
  local buy = pick.n - pick.held
  if buy > 0 then items[#items + 1] = { id = c.id, name = "Waylaid Crate: " .. c.name, qty = buy } end
  local need = math.max(0, pick.qty * pick.n - Count(pick.bundleID))
  if need > 0 then items[#items + 1] = { id = pick.bundleID, name = pick.bundle, qty = need } end
end

local function Fill()
  local p = plan
  local t = Target()
  if not f.box:HasFocus() then f.box:SetText(t and tostring(t) or "") end
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
    r.kind = (ln and ((ln.sealed and "sealed") or (ln.label and "label"))) or false
    if not ln then
      r:Hide()
    else
      r.add:Hide()
      r.per:SetText("")
      if ln.sealed then
        r.name:SetText("   |cffffd100Hand in " .. p.sealed .. " Sealed Crates|r")
        r.how:SetText(GREY .. "already filled, in your bags|r")
        r.favor:SetText(Num(p.sealedFavor))
        r.cost:SetText(GREY .. "free|r")
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
        r.how:SetText(GREY .. pick.qty .. " " .. pick.bundle .. " each|r")
        r.favor:SetText(Num(pick.n * c.favor))
        r.per:SetText(ns.Money(math.floor(pick.cost / (pick.n * c.favor) + 0.5)))
        r.cost:SetText((pick.guess and "|cffff9933~|r" or "") .. ns.Money(pick.cost))
        r.add:Show()
      end
      r:Show()
    end
  end
  if p then
    local extra = (p.sealed > 0 and p.sealedFavor or 0) + (p.label or 0)
    f.total:SetText(string.format("%d crates, %s favor%s   Total %s%s", (function()
        local n = 0 for _, k in ipairs(p.picks) do n = n + k.n end return n end)(),
      Num(p.favor + extra), p.short and " |cffff4040(not enough crates on the AH)|r" or "",
      p.guess and "|cffff9933~|r" or "", ns.Money(p.cost)))
    f.note:SetText(p.guess and "|cffff9933~ = more than the AH scan read, so the price is too low: Scan AH "
      .. "reads what this plan needs, then remakes it.|r"
      or "Crates you hold and materials in your bags are used first. Prices: AH listings when scanned, else Auctionator.")
  else
    f.total:SetText(t and "No crate has a price yet." or "Type how much Merchant's Favor you want.")
    f.note:SetText("")
  end
end

local function UpdateScan()
  local b, d = f and f.scan, ns.Depth
  if not (b and d) then return end
  if d.state == "running" then
    b:SetText(string.format("Stop scan %d/%d", d.done, math.max(d.total, d.done)))
    b:Enable()
  else
    b:SetText("Scan AH")
    b:SetEnabled(d.atAH and true or false)
  end
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
  f = UI.Window("CrateCostFavorPlan", "Favor plan", UI.WIDTH, TOP + PROWS * ROW_H + FOOT, UI.POS_KEY)
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
  tl:SetPoint("TOPLEFT", 18, UI.FILTER_Y - 3)
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
    Regenerate()
    f.offset = 0
    Fill()
  end
  box:SetScript("OnEnterPressed", function(self) Save(self) self:ClearFocus() end)
  box:SetScript("OnEditFocusLost", Save)
  box:SetScript("OnEscapePressed", function(self) self:SetText(Target() and tostring(Target()) or "") self:ClearFocus() end)
  UI.Tip(box, "Target favor", "How much Merchant's Favor you want in all (what you have counts). Enter to plan.")
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
  UI.PlanAtAHCheck(f, regen)

  f.offset, f.rows = 0, {}
  for i = 1, PROWS do
    local r = CreateFrame("Frame", nil, f)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 12, -TOP - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    local function Text(w, justify)
      local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetWidth(w)
      fs:SetJustifyH(justify)
      fs:SetWordWrap(false)
      return fs
    end
    r.name = Text(420, "LEFT")
    r.name:SetPoint("LEFT", 0, 0)
    r.how = Text(300, "LEFT")
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
    r.cost = Text(110, "RIGHT")
    r.cost:SetPoint("RIGHT", add, "LEFT", -6, 0)
    r.per = Text(80, "RIGHT")
    r.per:SetPoint("RIGHT", r.cost, "LEFT", -10, 0)
    r.favor = Text(60, "RIGHT")
    r.favor:SetPoint("RIGHT", r.per, "LEFT", -10, 0)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if self.kind == "sealed" then
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
        GameTooltip:AddDoubleLine("Cost", ns.Money(pick.cost), 1, 0.82, 0, 1, 1, 1)
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
  f.total = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.total:SetPoint("BOTTOMLEFT", 14, 42)
  local all = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  all:SetSize(130, 22)
  all:SetPoint("BOTTOMLEFT", 12, 12)
  all:SetText("Add plan to cart")
  all:SetScript("OnClick", function()
    if not plan then return end
    local items = {}
    for _, pick in ipairs(plan.picks) do PickItems(pick, items) end
    ns.Print(string.format("added %d to the cart.", ns.CartAdd(items)))
  end)
  UI.Tip(all, "Add plan to cart", "Every crate to buy and the bundle materials not in your bags.")
  f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.note:SetPoint("LEFT", all, "RIGHT", 12, 0)
  f.note:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  f.note:SetJustifyH("LEFT")
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
  UpdateScan()
  ns.UI.Open(f)
end
