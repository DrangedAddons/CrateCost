local _, ns = ...

-- Plan checklists: a small window per plan (rep, favor) with just the steps, ticking themselves
-- as you do them. A progress bar on top (rep to the target, or favor), then each step with a
-- count where it has one ("12 / 90 crates") that rises as you go. Hover a step for details.
--
-- Everything is read from the game; nothing is ticked by hand:
--   quests and writs: handed in (a writ done during the plan stays done past the daily reset);
--   Sealed Crates: how many have left your bags;
--   receipts, notarized containers: counted in your bags by name;
--   empty crates: Waylaid Crates in your bags;
--   favor earned and containers handed in: from your favor and rep since the plan was made,
--     less what the plan's other steps account for.
-- The progress belongs to the plan it was made for: a new plan (Regenerate, another target)
-- starts again from where you stand.

local W, ROW_H, ROWS, HEAD = 330, 20, 18, 64
local GREY = "|cff8a8a8a"
local GREEN = "|cff40ff40"
local GOLD = "|cffffd100"
local ROCK = "Interface\\FrameGeneral\\UI-Background-Rock"
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local ICON_DONE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ICON_WAIT = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local RECEIPT, CONTAINER = "Forged Delivery Receipt", "Notarized Shipping Container"
local CONTAINER_REP, RECEIPT_FAVOR, LABEL_REP, LABEL_FAVOR = 50, 15, 2000, 50

local function Num(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end

local function Count(id)
  if not (id and C_Item and C_Item.GetItemCount) then return 0 end
  local ok, n = pcall(C_Item.GetItemCount, id, true)
  return (ok and type(n) == "number") and n or 0
end

-- By name: the receipt and container (their item IDs aren't known); works for items you hold.
local function CountByName(name)
  local n = Count(name)
  if n == 0 and GetItemCount then
    local ok, m = pcall(GetItemCount, name, true)
    if ok and type(m) == "number" then n = m end
  end
  return n
end

local function FavorHave()
  local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(3402)
  return (info and info.quantity) or 0
end

local function Horde() return UnitFactionGroup and UnitFactionGroup("player") == "Horde" end

-- Per plan: where you stood when it was made, and the steps seen done (they stay done).
local function State(kind, stamp, start)
  if type(CrateCostCharDB) ~= "table" then CrateCostCharDB = {} end
  CrateCostCharDB.checklist = CrateCostCharDB.checklist or {}
  local t = CrateCostCharDB.checklist[kind]
  if not t or t.stamp ~= stamp or not t.start then
    t = { stamp = stamp, start = start(), seen = {} }
    CrateCostCharDB.checklist[kind] = t
  end
  t.seen = t.seen or {}
  return t
end

-- A step: { id, text, have, need (counts; optional), done, tip = { lines } }
local function Mark(st, s)
  if s.need and s.have then
    s.have = math.max(0, math.min(s.need, math.floor(s.have)))
    if s.have >= s.need then s.done = true end
  end
  if s.done then st.seen[s.id] = true end
  if st.seen[s.id] then
    s.done = true
    if s.need then s.have = s.need end
  end
  return s
end

------------------------------------------------------------------------------------------------
-- Rep plan

local function RepSteps()
  local ws = ns.WritStatus and ns.WritStatus()
  local p = ws and ws.plan
  if not p then return nil end
  local stand = ws.standing
  local stamp = (ws.target or 0) .. ":" .. #p.list .. ":" .. math.floor(p.cost or 0)
  local st = State("rep", stamp, function()
    return { rep = stand.value, favor = FavorHave(), label = ws.labelDone,
      target = stand.value + (ws.need or 0) }
  end)
  local start = st.start
  local steps = {}
  local function Add(s) steps[#steps + 1] = Mark(st, s) end

  if p.label then
    Add({ id = "label", text = "Do the Shipping Label quest", done = ws.labelDone,
      tip = { "+2,000 rep and 50 Merchant's Favor, once.",
        "Start your first writ (or fill a crate) to get the label, then deliver it to "
          .. (Horde() and "Dokimi" or "Marcy Baker") .. "." } })
  end
  local writRep = 0
  local function Writs(stage)
    for _, it in ipairs(p.list) do
      if not it.spent and (it.stage or 2) == stage then
        local e = it.e
        local s = Add({ id = "writ:" .. e.writ, text = "Fulfil writ: " .. e.name, done = e.done,
          tip = { e.name .. " (" .. e.rank .. ", " .. e.rep .. " rep)",
            (it.owned and "Have the writ" or "Buy the writ") .. ", " .. (it.crafted and "craft" or "buy") .. " "
              .. (e.qty > 1 and (e.qty .. "x ") or "") .. "the item: " .. ns.Money(it.cost),
            e.recipient ~= "" and ("Deliver to " .. e.recipient) or nil } })
        if steps[#steps].done then writRep = writRep + e.rep end
      end
    end
  end
  Writs(1)
  -- the containers: worked out from rep, favor and what's in your bags
  local c = p.containers
  if c then
    local labelGain = (p.label and st.seen.label and not start.label) and LABEL_REP or 0
    local repGain = stand.value - start.rep
    -- stage-2 writs come after the containers, but count what's done so far
    for _, it in ipairs(p.list) do
      if not it.spent and (it.stage or 2) == 2 and (it.e.done or st.seen["writ:" .. it.e.writ]) then
        writRep = writRep + it.e.rep
      end
    end
    local handed = math.max(0, math.floor((repGain - writRep - labelGain) / CONTAINER_REP))
    local notarized = CountByName(CONTAINER)
    local receipts = CountByName(RECEIPT)
    local empty = 0
    for _, id in pairs(ns.CrateIDs or {}) do empty = empty + Count(id) end
    if c.src then
      -- favor earned since the plan: what you have now, plus what the receipts cost you
      local labelFavor = (p.label and st.seen.label and not start.label) and LABEL_FAVOR or 0
      local earned = FavorHave() - start.favor - labelFavor + RECEIPT_FAVOR * (receipts + notarized + handed)
      Add({ id = "favor", text = "Fill " .. c.src.name .. " crates, hand in", unit = "crates",
        have = earned / c.src.favor, need = c.src.n,
        tip = { "Earn " .. Num(c.earn) .. " Merchant's Favor for the receipts.",
          "Buy " .. c.src.n .. " Waylaid Crate: " .. c.src.name .. ", fill each with " .. c.src.qty .. " "
            .. c.src.bundle .. ", hand them in (" .. c.src.favor .. " favor each)." } })
    end
    Add({ id = "receipts", text = "Buy Forged Delivery Receipts", unit = "",
      have = receipts + notarized + handed, need = c.n,
      tip = { "15 favor each from " .. (Horde() and "Kurvelk Shadowhoof" or "Dianne Softstep") .. ". Needs Friendly.",
        "Counted in your bags, with the containers you've made and handed in." } })
    Add({ id = "crates", text = "Buy empty Waylaid Crates", unit = "",
      have = empty + notarized + handed, need = c.n,
      tip = { "The cheapest on the AH: any crate takes a receipt.",
        "Counted in your bags (any Waylaid Crate), with the containers made and handed in." } })
    Add({ id = "handin", text = "Hand in containers", unit = "",
      have = handed, need = c.n,
      tip = { "Use a receipt on each empty crate, hand them to " .. (Horde() and "Dokimi" or "Marcy Baker") .. ".",
        "50 rep each: counted from your rep since the plan was made." } })
  end
  Writs(2)
  if ws.targetName then
    Add({ id = "target", text = "Reach " .. ws.targetName, done = ws.need == nil,
      tip = { ws.need and (Num(ws.need) .. " rep to go.") or "Reached." } })
  end
  -- the bar: from where you stood to the target
  local span = math.max(1, start.target - start.rep)
  local bar = {
    value = math.max(0, math.min(1, (stand.value - start.rep) / span)),
    color = stand.color,
    text = stand.label .. (stand.max and ("  " .. Num(stand.value - stand.min) .. " / " .. Num(stand.max - stand.min)) or "")
      .. (ws.need and ("   " .. Num(ws.need) .. " to " .. ws.targetName) or (ws.targetName and ("   " .. ws.targetName .. " reached") or "")),
  }
  return steps, "Rep plan" .. (ws.targetName and (" to " .. ws.targetName) or ""), bar
end

------------------------------------------------------------------------------------------------
-- Favor plan

local function FavorSteps()
  local fs = ns.FavorStatus and ns.FavorStatus()
  local p = fs and fs.plan
  if not p then return nil end
  local stamp = p.target .. ":" .. #p.picks .. ":" .. math.floor(p.cost or 0)
  local st = State("favor", stamp, function()
    return { favor = fs.have, sealed = p.sealed, label = fs.labelDone }
  end)
  local start = st.start
  local steps = {}
  local function Add(s) steps[#steps + 1] = Mark(st, s) end
  local earned = fs.have - start.favor
  if p.sealed > 0 then
    local handed = math.max(0, (start.sealed or p.sealed) - fs.sealed)
    Add({ id = "sealed", text = "Hand in Sealed Crates", unit = "", have = handed, need = p.sealed,
      tip = { "Already filled, in your bags: " .. Num(p.sealedFavor) .. " favor.", "Counted as they leave your bags." } })
    earned = earned - handed * (p.sealedFavor / p.sealed)
  end
  if p.label then
    Add({ id = "label", text = "Do the Shipping Label quest", done = fs.labelDone,
      tip = { "Your first filled crate gives a Shipping Label: 50 favor (and 2,000 rep).",
        "Deliver it to " .. (Horde() and "Dokimi" or "Marcy Baker") .. "." } })
    if fs.labelDone and not start.label then earned = earned - LABEL_FAVOR end
  end
  -- the crates: the favor earned since the plan, given to them in order
  for _, pick in ipairs(p.picks) do
    local c = pick.c
    local n = math.max(0, math.min(pick.n, math.floor(earned / c.favor)))
    earned = earned - n * c.favor
    Add({ id = "pick:" .. c.name, text = "Fill " .. c.name .. " crates, hand in", unit = "",
      have = n, need = pick.n,
      tip = { pick.n .. " Waylaid Crate: " .. c.name .. (pick.held > 0 and (" (" .. pick.held .. " you have)") or ""),
        "Fill each with " .. pick.qty .. " " .. pick.bundle .. ": " .. Num(pick.n * c.favor) .. " favor.",
        "Costs " .. ns.Money(pick.upFront or pick.cost) .. ". Counted from the favor you earn." } })
  end
  Add({ id = "target", text = "Reach " .. Num(p.target) .. " favor", done = fs.have >= p.target,
    tip = { "You have " .. Num(fs.have) .. "." } })
  local bar = {
    value = math.max(0, math.min(1, fs.have / math.max(1, p.target))),
    color = "|cffffd100",
    text = Num(fs.have) .. " / " .. Num(p.target) .. " Merchant's Favor",
  }
  return steps, "Favor plan to " .. Num(p.target), bar
end

------------------------------------------------------------------------------------------------
-- The window

local SOURCES = { rep = RepSteps, favor = FavorSteps }
local windows = {}

local function RGB(code)
  local hex = code and code:match("|cff(%x%x%x%x%x%x)")
  if not hex then return 1, 0.82, 0 end
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

local function Fill(w)
  local steps, title, bar = SOURCES[w.kind]()
  if not steps then
    w.title:SetText(w.kind == "rep" and "Rep plan" or "Favor plan")
    w.progress:SetText("")
    w.bar:SetValue(0)
    w.bar.text:SetText("")
    w.empty:Show()
    for _, r in ipairs(w.rows) do r:Hide() end
    return
  end
  w.empty:Hide()
  local done, current = 0, nil
  for i, s in ipairs(steps) do
    if s.done then done = done + 1 elseif not current then current = i end
  end
  w.title:SetText(title)
  w.progress:SetText((done == #steps and GREEN or GOLD) .. done .. " / " .. #steps .. "|r")
  w.bar:SetValue(bar.value)
  w.bar:SetStatusBarColor(RGB(bar.color))
  w.bar.text:SetText(bar.text)
  if not w.scrolled then w.offset = math.max(0, (current or #steps) - 3) end
  w.offset = math.max(0, math.min(w.offset, #steps - ROWS))
  for i = 1, ROWS do
    local idx = w.offset + i
    local r, s = w.rows[i], steps[idx]
    r.step = s or false
    if not s then
      r:Hide()
    else
      local isCur = idx == current
      local count = s.need and (s.have .. " / " .. s.need) or ""
      if s.done then
        r.icon:SetTexture(ICON_DONE)
        r.icon:SetAlpha(1)
        r.text:SetText(GREY .. s.text .. "|r")
        r.count:SetText(GREEN .. count .. "|r")
        r.bg:SetColorTexture(0.1, 0.5, 0.15, 0.16)
        r.accent:Hide()
      elseif isCur then
        r.icon:SetTexture(ICON_WAIT)
        r.icon:SetAlpha(1)
        r.text:SetText(GOLD .. s.text .. "|r")
        r.count:SetText("|cffffffff" .. count .. "|r")
        r.bg:SetColorTexture(1, 0.82, 0, 0.14)
        r.accent:Show()
      else
        r.icon:SetTexture(ICON_WAIT)
        r.icon:SetAlpha(0.3)
        r.text:SetText("|cffdddddd" .. s.text .. "|r")
        r.count:SetText(GREY .. count .. "|r")
        r.bg:SetColorTexture(0, 0, 0, 0)
        r.accent:Hide()
      end
      -- a step with a count fills as it goes
      local frac = (s.need and s.need > 0 and not s.done) and (s.have / s.need) or 0
      if frac > 0 then
        r.fill:SetWidth(math.max(1, (W - 12) * frac))
        r.fill:Show()
      else
        r.fill:Hide()
      end
      r:Show()
    end
  end
end

local function Build(kind)
  local w = CreateFrame("Frame", "CrateCostChecklist" .. kind, UIParent, "BackdropTemplate")
  w.kind, w.offset, w.rows = kind, 0, {}
  w:SetSize(W, HEAD + ROWS * ROW_H + 10)
  w:SetFrameStrata("MEDIUM")
  w:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  w:SetBackdropColor(0.04, 0.04, 0.05, 0.75)
  w:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
  -- stone, and a warm band behind the header
  local rock = w:CreateTexture(nil, "BACKGROUND", nil, 1)
  rock:SetPoint("TOPLEFT", 1, -1)
  rock:SetPoint("BOTTOMRIGHT", -1, 1)
  rock:SetTexture(ROCK, "REPEAT", "REPEAT")
  pcall(rock.SetHorizTile, rock, true)
  pcall(rock.SetVertTile, rock, true)
  rock:SetAlpha(0.6)
  local band = w:CreateTexture(nil, "BACKGROUND", nil, 2)
  band:SetPoint("TOPLEFT", 1, -1)
  band:SetPoint("TOPRIGHT", -1, -1)
  band:SetHeight(HEAD - 4)
  band:SetColorTexture(1, 1, 1, 1)
  local ok = CreateColor and pcall(band.SetGradient, band, "VERTICAL", CreateColor(0.25, 0.18, 0.05, 0.1),
    CreateColor(0.55, 0.4, 0.1, 0.45))
  if not ok then band:SetColorTexture(0.45, 0.33, 0.1, 0.25) end
  local rule = w:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", 6, -HEAD + 4)
  rule:SetPoint("TOPRIGHT", -6, -HEAD + 4)
  rule:SetColorTexture(1, 0.82, 0, 0.45)

  w:SetMovable(true)
  w:SetClampedToScreen(true)
  w:EnableMouse(true)
  w:RegisterForDrag("LeftButton")
  w:SetScript("OnDragStart", w.StartMoving)
  local posKey = "checklistPos" .. kind
  w:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if type(CrateCostDB) == "table" and self:GetLeft() then CrateCostDB[posKey] = { x = self:GetLeft(), y = self:GetTop() } end
  end)
  local pos = type(CrateCostDB) == "table" and CrateCostDB[posKey]
  if pos and pos.x then
    w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
  else
    w:SetPoint("RIGHT", UIParent, "RIGHT", kind == "rep" and -370 or -20, 120)
  end

  w.title = w:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  w.title:SetPoint("TOPLEFT", 10, -9)
  w.progress = w:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  w.progress:SetPoint("TOPRIGHT", -28, -10)
  local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
  close:SetSize(22, 22)
  close:SetPoint("TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function() ns.ToggleChecklist(kind) end)

  -- the progress bar: rep to the target, or favor
  local bar = CreateFrame("StatusBar", nil, w)
  bar:SetPoint("TOPLEFT", 10, -30)
  bar:SetPoint("TOPRIGHT", -10, -30)
  bar:SetHeight(18)
  bar:SetStatusBarTexture(BAR)
  bar:SetMinMaxValues(0, 1)
  local bbg = bar:CreateTexture(nil, "BACKGROUND")
  bbg:SetAllPoints()
  bbg:SetColorTexture(0, 0, 0, 0.55)
  local bborder = CreateFrame("Frame", nil, bar, "BackdropTemplate")
  bborder:SetPoint("TOPLEFT", -1, 1)
  bborder:SetPoint("BOTTOMRIGHT", 1, -1)
  bborder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  bborder:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
  bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.text:SetPoint("CENTER")
  w.bar = bar

  w.empty = w:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  w.empty:SetPoint("TOP", 0, -HEAD - 6)
  w.empty:SetText(kind == "rep" and "No rep plan: pick a target." or "No favor plan: type a target.")

  for i = 1, ROWS do
    local r = CreateFrame("Frame", nil, w)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 6, -HEAD - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", w, "RIGHT", -6, 0)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.fill = r:CreateTexture(nil, "BORDER")
    r.fill:SetPoint("TOPLEFT")
    r.fill:SetPoint("BOTTOMLEFT")
    r.fill:SetColorTexture(0.25, 0.55, 1, 0.22)
    r.accent = r:CreateTexture(nil, "ARTWORK")
    r.accent:SetPoint("TOPLEFT")
    r.accent:SetPoint("BOTTOMLEFT")
    r.accent:SetWidth(2)
    r.accent:SetColorTexture(1, 0.82, 0, 0.9)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("LEFT", 6, 0)
    r.count = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.count:SetPoint("RIGHT", -6, 0)
    r.count:SetJustifyH("RIGHT")
    r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetPoint("RIGHT", r.count, "LEFT", -6, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
      local s = self.step
      if not s then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(s.text)
      for _, l in ipairs(s.tip or {}) do GameTooltip:AddLine(l, 1, 1, 1, true) end
      if s.need then GameTooltip:AddLine(s.have .. " of " .. s.need .. " done.", 0.6, 0.8, 1) end
      if s.done then GameTooltip:AddLine("Done.", 0.25, 1, 0.25) end
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(_, d) w.offset = w.offset - d * 3 w.scrolled = true Fill(w) end)
    w.rows[i] = r
  end
  w:EnableMouseWheel(true)
  w:SetScript("OnMouseWheel", function(_, d) w.offset = w.offset - d * 3 w.scrolled = true Fill(w) end)
  -- the game moves the steps along
  for _, ev in ipairs({ "QUEST_TURNED_IN", "BAG_UPDATE_DELAYED", "CURRENCY_DISPLAY_UPDATE", "UPDATE_FACTION" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(ev) then
      pcall(w.RegisterEvent, w, ev)
    end
  end
  local pending = false
  w:SetScript("OnEvent", function()
    if pending or not w:IsShown() then return end
    pending = true
    C_Timer.After(0.5, function() pending = false if w:IsShown() then w.scrolled = false Fill(w) end end)
  end)
  w:SetScript("OnShow", function() w.scrolled = false Fill(w) end)
  w:Hide()
  return w
end

-- Opens or closes the checklist for `kind` ("rep" or "favor"); open per character across reloads.
function ns.ToggleChecklist(kind)
  local w = windows[kind]
  if not w then
    local ok, res = pcall(Build, kind)
    if not ok then
      ns.Print("couldn't open the checklist: " .. tostring(res))
      return
    end
    w = res
    windows[kind] = w
  end
  if type(CrateCostCharDB) ~= "table" then CrateCostCharDB = {} end
  CrateCostCharDB.checklistOpen = CrateCostCharDB.checklistOpen or {}
  if w:IsShown() then
    w:Hide()
    CrateCostCharDB.checklistOpen[kind] = nil
  else
    w:Show()
    CrateCostCharDB.checklistOpen[kind] = true
  end
end

-- A plan changed (Regenerate, new target): refresh an open checklist.
function ns.RefreshChecklists()
  for _, w in pairs(windows) do
    if w:IsShown() then w.scrolled = false Fill(w) end
  end
end

-- reopen the checklists that were open
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  C_Timer.After(2, function()
    local open = type(CrateCostCharDB) == "table" and CrateCostCharDB.checklistOpen
    for kind in pairs(open or {}) do
      if not (windows[kind] and windows[kind]:IsShown()) then
        CrateCostCharDB.checklistOpen[kind] = nil
        ns.ToggleChecklist(kind)
      end
    end
  end)
end)
