local _, ns = ...

-- Crate actions: doing the plan's steps for you, after you say how much.
--   Fill crates     pick a crate you hold, see what fills it, fill as many as you like.
--   Containers      put Forged Delivery Receipts on empty crates (Notarized Shipping Containers).
--   Receipts        at the receipt vendor: how many to buy, then buys them.
--   Hand in         at Dokimi / Marcy Baker: what to hand in, then talks through every quest.
--
-- Using an item (filling a crate, a receipt on a crate) is protected: an addon can only do it
-- from a click on a secure button. So those run as one click per item on the Runner's button,
-- which works out the next item each time. Buying and quest dialogs aren't protected and run
-- on their own.

local GREY, GREEN, GOLD, RED = "|cff8a8a8a", "|cff40ff40", "|cffffd100", "|cffff4040"
local RECEIPT, CONTAINER = "Forged Delivery Receipt", "Notarized Shipping Container"
local RECEIPT_FAVOR = 15
local HANDIN_NPCS = { ["Dokimi"] = true, ["Marcy Baker"] = true }
-- quest titles that can be a crate or container hand-in (only these are ever accepted)
local HANDIN_TITLES = { "crate", "container", "shipment", "shipping" }
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function Num(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end
local function Horde() return UnitFactionGroup and UnitFactionGroup("player") == "Horde" end
local function NPCName() return Horde() and "Dokimi" or "Marcy Baker" end
local function On(key) return not (ns.Settings and ns.Settings()[key] == false) end
local function Combat() return InCombatLockdown and InCombatLockdown() end

local function DB()
  if type(CrateCostDB) ~= "table" then CrateCostDB = {} end
  CrateCostDB.handin = CrateCostDB.handin or {}      -- questID -> itemID it takes
  if not CrateCostDB.handinV then
    -- 0.57.0 saved "none of ours" when a quest's item wasn't loaded yet: forget those
    for q, v in pairs(CrateCostDB.handin) do if v == false then CrateCostDB.handin[q] = nil end end
    CrateCostDB.handinV = 2
  end
  return CrateCostDB
end

------------------------------------------------------------------------------------------------
-- Bags

local function NameOf(id)
  if not id then return nil end
  local ok, name = pcall(C_Item and C_Item.GetItemNameByID or GetItemInfo, id)
  return ok and name or nil
end

local function IconOf(id)
  local ok, icon = pcall(C_Item and C_Item.GetItemIconByID or GetItemIcon, id)
  return ok and icon or nil
end

local function QualityHex(id)
  local ok, _, _, q = pcall(C_Item and C_Item.GetItemInfo or GetItemInfo, id)
  local c = ok and q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  return c and c.hex or "|cffffffff"
end

-- Every stack in your bags: { bag, slot, id, count }.
local function Bags()
  local out = {}
  local C = C_Container
  local last = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0)
  for bag = 0, last do
    local okN, n = pcall(C and C.GetContainerNumSlots or GetContainerNumSlots, bag)
    n = (okN and tonumber(n)) or 0
    for slot = 1, n do
      local id, count
      if C and C.GetContainerItemInfo then
        local ok, info = pcall(C.GetContainerItemInfo, bag, slot)
        if ok and type(info) == "table" then id, count = info.itemID, info.stackCount end
      elseif GetContainerItemInfo then
        local ok, _, c, _, _, _, _, _, _, _, iid = pcall(GetContainerItemInfo, bag, slot)
        if ok then id, count = iid, c end
      end
      if id then out[#out + 1] = { bag = bag, slot = slot, id = id, count = count or 1 } end
    end
  end
  return out
end

local function BagCount(id, bags)
  local n = 0
  for _, s in ipairs(bags or Bags()) do if s.id == id then n = n + s.count end end
  return n
end

local function BagCountByName(name, bags)
  local n = 0
  for _, s in ipairs(bags or Bags()) do if NameOf(s.id) == name then n = n + s.count end end
  return n
end

local function FirstSlot(test, bags)
  for _, s in ipairs(bags or Bags()) do if test(s) then return s end end
end

-- crate item ID -> crate entry (name, bundles, id), for the crates in your bags. Crates whose ID
-- isn't known yet are matched by name ("Waylaid Crate: Journeyman Ore").
local function CrateIndex(bags)
  local byID, byName = {}, {}
  for _, c in ipairs(ns.CrateEntries and ns.CrateEntries() or {}) do
    if c.id then byID[c.id] = c end
    byName[c.name] = c
  end
  for _, s in ipairs(bags) do
    if not byID[s.id] then
      local n = NameOf(s.id)
      local short = n and n:match("^Waylaid Crate:%s*(.+)$")
      if short and byName[short] then byID[s.id] = byName[short] end
    end
  end
  return byID
end

-- The empty crates in your bags, one entry per kind: { id, c, n }.
local function Empties(bags)
  local idx, kinds, order = CrateIndex(bags), {}, {}
  for _, s in ipairs(bags) do
    local c = idx[s.id]
    if c then
      if not kinds[s.id] then kinds[s.id] = { id = s.id, c = c, n = 0 } order[#order + 1] = kinds[s.id] end
      kinds[s.id].n = kinds[s.id].n + s.count
    end
  end
  table.sort(order, function(a, b) return a.c.name < b.c.name end)
  return order
end

------------------------------------------------------------------------------------------------
-- Filling: a crate takes one bundle, from a single stack that holds the whole amount.

-- For crate `c`: its bundles with what your bags hold, cheapest (market value) first.
-- { name, id, qty, have, fills (stacks that can fill it), short (enough in all, no stack big enough) }
local function FillOptions(c, bags)
  local out = {}
  for _, b in ipairs(c.bundles or {}) do
    local id = ns.ItemIDs and ns.ItemIDs[b[1]]
    if id and b[2] and b[2] > 0 then
      local have, fills = 0, 0
      for _, s in ipairs(bags) do
        if s.id == id then
          have = have + s.count
          fills = fills + math.floor(s.count / b[2])
        end
      end
      -- an item that stacks smaller than the bundle can't come from one stack: count it all
      local okM, maxStack = pcall(C_Item and C_Item.GetItemMaxStackSizeByID or function() end, id)
      local multi = okM and type(maxStack) == "number" and maxStack > 0 and maxStack < b[2]
      if multi then fills = math.floor(have / b[2]) end
      local unit = ns.Price and ns.Price(id)
      out[#out + 1] = { name = b[1], id = id, qty = b[2], have = have, fills = fills, multi = multi,
        short = fills == 0 and have >= b[2], value = (unit or 0) * b[2] }
    end
  end
  table.sort(out, function(a, b)
    if (a.fills > 0) ~= (b.fills > 0) then return a.fills > 0 end
    return a.value < b.value
  end)
  return out
end

local function Fillable(opts)
  local n = 0
  for _, o in ipairs(opts) do n = n + o.fills end
  return n
end

------------------------------------------------------------------------------------------------
-- Small dark frames

local function Panel(name, w, h, title)
  local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  f:SetSize(w, h)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  f:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
  f:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 12, -10)
  f.title:SetText(title)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetScript("OnClick", function() f:Hide() end)
  close:SetPoint("TOPRIGHT", 2, 2)
  f.close = close
  if name then tinsert(UISpecialFrames, name) end
  f:Hide()
  return f
end

local function Button(parent, text, w, onClick, tip)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  if tip and ns.UI then ns.UI.Tip(b, text, tip) end
  return b
end

local function Text(parent, font)
  local t = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
  t:SetJustifyH("LEFT")
  return t
end

local function NumBox(parent, w)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w or 44, 18)
  e:SetAutoFocus(false)
  e:SetNumeric(true)
  e:SetMaxLetters(5)
  e:SetJustifyH("CENTER")
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return e
end

------------------------------------------------------------------------------------------------
-- How many? A small prompt: text, a number (default `def`, at most `max`), Max, OK, Cancel.

local ask
local function Ask(title, text, def, max, onOK)
  if not ask then
    ask = Panel("CrateCostAsk", 320, 132, "")
    ask.text = Text(ask)
    ask.text:SetPoint("TOPLEFT", 14, -32)
    ask.text:SetWidth(292)
    ask.box = NumBox(ask, 60)
    ask.box:SetPoint("TOPLEFT", 18, -76)
    ask.of = Text(ask)
    ask.of:SetPoint("LEFT", ask.box, "RIGHT", 8, 0)
    ask.maxBtn = Button(ask, "Max", 50, function() ask.box:SetText(tostring(ask.max)) end)
    ask.maxBtn:SetPoint("LEFT", ask.of, "RIGHT", 8, 0)
    local function OK()
      local n = math.min(ask.max, math.max(0, tonumber(ask.box:GetText()) or 0))
      ask:Hide()
      if n > 0 and ask.onOK then ask.onOK(n) end
    end
    ask.box:SetScript("OnEnterPressed", OK)
    ask.ok = Button(ask, "OK", 80, OK)
    ask.ok:SetPoint("BOTTOMRIGHT", -100, 10)
    ask.cancel = Button(ask, "Cancel", 80, function() ask:Hide() end)
    ask.cancel:SetPoint("LEFT", ask.ok, "RIGHT", 6, 0)
  end
  ask.title:SetText(title)
  ask.text:SetText(text)
  ask.max, ask.onOK = math.max(0, max), onOK
  ask.of:SetText("of " .. Num(ask.max))
  ask.box:SetText(tostring(math.max(0, math.min(def, max))))
  ask:Show()
  ask:Raise()
  ask.box:SetFocus()
  ask.box:HighlightText()
end

------------------------------------------------------------------------------------------------
-- Running a job: a section with a secure button, one item per click, and a progress bar. A job is
--   { title, verb, total, start(bags) -> state, done(bags, state) -> n, next(bags, state) -> macro }
-- A section can sit in any window (the fill window has one); the runner is a small window with one.

local sections = {}
local RefreshFill, RefreshContainers   -- forward: windows refresh as the bags change

local function SecUpdate(sec)
  local job = sec.job
  if job then
    local bags = Bags()
    local done = job.done(bags, job.state)
    local nextMacro = done < job.total and job.next(bags, job.state)
    if done >= job.total or not nextMacro then
      sec.job = false
      ns.Print(string.format("%s: %d of %d done.", job.title, done, job.total)
        .. ((done < job.total) and (" " .. (job.stop or "Nothing left to do it with.")) or ""))
      if job.after then pcall(job.after, done) end
      if sec.onFinish then pcall(sec.onFinish, job, done) end
    else
      sec.progress:SetText(string.format("%d of %d done", done, job.total))
      sec.bar:SetWidth(math.max(1, sec.trackW * done / job.total))
      sec.bar:Show()
      sec.run:SetText(string.format("%s %d of %d", job.verb, done + 1, job.total))
    end
  end
  if not sec.job then
    sec.bar:Hide()
    sec.progress:SetText("")
    if sec.idle then sec.idle(sec) end
  end
end

local function Begin(sec, j)
  j.state = j.start and j.start(Bags()) or {}
  sec.job = j
  SecUpdate(sec)
end

-- `name` for the secure button; `w` wide. sec.makeJob() (optional) makes the job on the first click.
local function RunSection(parent, name, w)
  local sec = CreateFrame("Frame", nil, parent)
  sec:SetSize(w, 52)
  sec.trackW, sec.job = w, false
  local run = CreateFrame("Button", name, sec, "SecureActionButtonTemplate,UIPanelButtonTemplate")
  run:SetSize(w, 26)
  run:SetPoint("TOP", 0, 0)
  run:RegisterForClicks("AnyUp")
  run:SetAttribute("useOnKeyDown", false)
  run:SetAttribute("type", "macro")
  run:SetAttribute("macrotext", "")
  -- the next item, worked out from the bags as they are now
  run:SetScript("PreClick", function(self)
    if Combat() then return end
    if not sec.job and sec.makeJob then
      local j = sec.makeJob()
      if j then Begin(sec, j) end
    end
    local m = sec.job and sec.job.next(Bags(), sec.job.state)
    self:SetAttribute("macrotext", m or "")
  end)
  sec.run = run
  local track = sec:CreateTexture(nil, "ARTWORK")
  track:SetPoint("TOPLEFT", run, "BOTTOMLEFT", 0, -6)
  track:SetSize(w, 6)
  track:SetColorTexture(0.12, 0.12, 0.12, 1)
  sec.bar = sec:CreateTexture(nil, "OVERLAY")
  sec.bar:SetPoint("TOPLEFT", track, "TOPLEFT")
  sec.bar:SetSize(1, 6)
  sec.bar:SetColorTexture(1, 0.82, 0, 0.9)
  sec.bar:Hide()
  sec.progress = Text(sec)
  sec.progress:SetPoint("TOPLEFT", track, "BOTTOMLEFT", 0, -3)
  sections[#sections + 1] = sec
  return sec
end

local bagWatch = CreateFrame("Frame")
bagWatch:RegisterEvent("BAG_UPDATE_DELAYED")
bagWatch:SetScript("OnEvent", function()
  C_Timer.After(0.1, function()
    for _, sec in ipairs(sections) do if sec.job then SecUpdate(sec) end end
    if RefreshFill then RefreshFill() end
    if RefreshContainers then RefreshContainers() end
  end)
end)

-- The runner: a small window with a section, for jobs started elsewhere (containers).
local runner
local function StartJob(j)
  if Combat() then ns.Print("not in combat.") return end
  if not runner then
    runner = Panel("CrateCostRunner", 300, 128, "")
    runner.note = Text(runner, "GameFontDisableSmall")
    runner.note:SetPoint("TOPLEFT", 14, -30)
    runner.note:SetWidth(272)
    runner.note:SetText("The game lets an addon use an item only on a click: click once per item. "
      .. "The button works out the next one each time.")
    runner.sec = RunSection(runner, "CrateCostRunButton", 272)
    runner.sec:SetPoint("BOTTOM", 0, 6)
    runner.sec.onFinish = function() if not Combat() then runner:Hide() end end
    runner.close:SetScript("OnClick", function()
      if Combat() then return end
      runner.sec.job = false
      runner:Hide()
    end)
  end
  runner.title:SetText(j.title)
  runner:ClearAllPoints()
  runner:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
  runner:Show()
  runner:Raise()
  Begin(runner.sec, j)
end

local function Use(s) return "/use " .. s.bag .. " " .. s.slot end

------------------------------------------------------------------------------------------------
-- Fill crates window: the crates in your bags on top (scrolling), the one you pick below with
-- how many and the Fill button.

local fillWin
local FILL_W, FILL_ROWS, FILL_ROW_H = 640, 8, 30
local LIST_TOP = 32
local PANEL_H = 112

-- The stack to fill from: one that holds the whole bundle, else (an item that stacks smaller than
-- the bundle) the biggest.
local function FillStack(o, bags)
  local best
  for _, s in ipairs(bags) do
    if s.id == o.id then
      if s.count >= o.qty then return s end
      if o.multi and (not best or s.count > best.count) then best = s end
    end
  end
  return best
end

local function FillJob(e, n)
  return {
    title = "Fill " .. e.c.name, verb = "Fill crate", total = n,
    stop = "Out of a bundle that fills it.",
    start = function(bags) return { have = BagCount(e.id, bags) } end,
    done = function(bags, st) return math.max(0, st.have - BagCount(e.id, bags)) end,
    next = function(bags)
      local crate = FirstSlot(function(s) return s.id == e.id end, bags)
      if not crate then return nil end
      for _, o in ipairs(FillOptions(e.c, bags)) do
        if o.fills > 0 then
          local stack = FillStack(o, bags)
          if stack then return Use(crate) .. "\n" .. Use(stack) end
        end
      end
    end,
  }
end

local function Selected(f)
  for _, e in ipairs(f.list or {}) do if e.id == f.selID then return e end end
end

local function SelectCrate(f, e)
  if f.sec.job and f.selID ~= (e and e.id) then f.sec.job = false end
  f.selID = e and e.id or false
  f.qty = e and e.can or 0
  f.box:SetText(tostring(f.qty))
  RefreshFill()
end

local function FillRow(f, i)
  local r = CreateFrame("Button", nil, f)
  r:SetSize(FILL_W - 24 - 12, FILL_ROW_H - 2)
  r:SetPoint("TOPLEFT", 12, -LIST_TOP - (i - 1) * FILL_ROW_H)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints()
  r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
  r.sel = r:CreateTexture(nil, "BORDER")
  r.sel:SetAllPoints()
  r.sel:SetColorTexture(1, 0.82, 0, 0.18)
  r.sel:Hide()
  r.hl = r:CreateTexture(nil, "HIGHLIGHT")
  r.hl:SetAllPoints()
  r.hl:SetColorTexture(1, 1, 1, 0.08)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(22, 22)
  r.icon:SetPoint("LEFT", 2, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.crate = Text(r, "GameFontHighlight")
  r.crate:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.crate:SetWidth(200)
  r.crate:SetWordWrap(false)
  r.arrow = Text(r, "GameFontNormal")
  r.arrow:SetPoint("LEFT", r.crate, "RIGHT", 4, 0)
  r.arrow:SetText("->")
  r.matIcon = r:CreateTexture(nil, "ARTWORK")
  r.matIcon:SetSize(18, 18)
  r.matIcon:SetPoint("LEFT", r.arrow, "RIGHT", 6, 0)
  r.matIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.fill = Button(r, "Fill", 60, function() if r.entry then SelectCrate(f, r.entry) end end)
  r.fill:SetPoint("RIGHT", -2, 0)
  r.count = Text(r)
  r.count:SetPoint("RIGHT", r.fill, "LEFT", -8, 0)
  r.count:SetWidth(54)
  r.count:SetJustifyH("RIGHT")
  r.mat = Text(r)
  r.mat:SetPoint("LEFT", r.matIcon, "RIGHT", 4, 0)
  r.mat:SetPoint("RIGHT", r.count, "LEFT", -6, 0)
  r.mat:SetWordWrap(false)
  r:SetScript("OnClick", function() if r.entry then SelectCrate(f, r.entry) end end)
  r:SetScript("OnEnter", function(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Waylaid Crate: " .. e.c.name, 1, 1, 1)
    for _, o in ipairs(e.opts) do
      local col = o.fills > 0 and GREEN or (o.short and GOLD or GREY)
      GameTooltip:AddDoubleLine(o.qty .. " " .. o.name, col .. Num(o.have) .. " in bags"
        .. (o.fills > 0 and (" (" .. o.fills .. ")") or (o.short and ", no stack big enough" or "")) .. "|r",
        0.9, 0.9, 0.9)
    end
    GameTooltip:AddLine("A bundle comes from one stack that holds the whole amount.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end

-- the picked crate's section: what it is, how many, the Fill button
local function RefreshPicked(f, e)
  local p = f.picked
  if not e then
    p.icon:Hide()
    p.name:SetText("")
    p.how:SetText("")
    p.hint:SetText(GREY .. "Pick a crate above: click its row or Fill.|r")
    p.qtyRow:Hide()
    if not Combat() then f.sec:Hide() end
    return
  end
  p.hint:SetText("")
  p.icon:SetTexture(IconOf(e.id))
  p.icon:Show()
  p.name:SetText(QualityHex(e.id) .. "Waylaid Crate: " .. e.c.name .. "|r  " .. GREY .. "x" .. e.n .. "|r")
  local o = e.opts[1]
  if o and o.fills > 0 then
    p.how:SetText("-> " .. o.qty .. " " .. o.name .. GREY .. "  (" .. Num(o.have) .. " in bags)|r"
      .. "   " .. GREEN .. "fills " .. e.can .. "|r")
  else
    p.how:SetText(o and (GREY .. "-> needs " .. o.qty .. " " .. o.name .. (o.short and " in one stack" or "") .. "|r")
      or (GREY .. "bundles not known: hover the crate in your bags|r"))
  end
  p.qtyRow:Show()
  p.of:SetText("of " .. e.can)
  local busy = f.sec.job and true or false
  if not busy and not f.box:HasFocus() then
    f.qty = math.min(f.qty or e.can, e.can)
    f.box:SetText(tostring(f.qty))
  end
  if not Combat() then f.sec:Show() end
  if not busy and not Combat() then
    if e.can > 0 and (f.qty or 0) > 0 then
      f.sec.run:Enable()
      f.sec.run:SetText("Fill 1 of " .. f.qty)
    else
      f.sec.run:Disable()
      f.sec.run:SetText(e.can > 0 and "Fill" or "Nothing to fill with")
    end
  end
end

RefreshFill = function()
  local f = fillWin
  if not (f and f:IsShown()) then return end
  local bags = Bags()
  local list = {}
  for _, e in ipairs(Empties(bags)) do
    e.opts = FillOptions(e.c, bags)
    e.can = math.min(e.n, Fillable(e.opts))
    list[#list + 1] = e
  end
  table.sort(list, function(a, b)
    if (a.can > 0) ~= (b.can > 0) then return a.can > 0 end
    return a.c.name < b.c.name
  end)
  f.list = list
  local maxOff = math.max(0, #list - FILL_ROWS)
  f.offset = math.min(f.offset or 0, maxOff)
  for i = 1, FILL_ROWS do
    local r, e = f.rows[i], list[f.offset + i]
    r.entry = e or false
    if e then
      r.sel:SetShown(e.id == f.selID)
      r.icon:SetTexture(IconOf(e.id))
      r.crate:SetText(QualityHex(e.id) .. e.c.name .. "|r  " .. GREY .. "x" .. e.n .. "|r")
      local o = e.opts[1]
      if o and o.fills > 0 then
        r.matIcon:SetTexture(IconOf(o.id))
        r.matIcon:Show()
        local more = 0
        for k = 2, #e.opts do if e.opts[k].fills > 0 then more = more + 1 end end
        r.mat:SetText(o.qty .. " " .. o.name .. (more > 0 and (GREY .. "  +" .. more .. " more|r") or ""))
        r.count:SetText(GREEN .. "fills " .. e.can .. "|r")
        r.fill:Enable()
      else
        r.matIcon:SetShown(o ~= nil)
        if o then r.matIcon:SetTexture(IconOf(o.id)) end
        r.mat:SetText(o and (GREY .. "needs " .. o.qty .. " " .. o.name .. (o.short and " in one stack" or "") .. "|r")
          or (GREY .. "bundles not known: hover the crate|r"))
        r.count:SetText(GREY .. "fills 0|r")
        r.fill:Disable()
      end
      r:Show()
    else
      r:Hide()
    end
  end
  -- the scrollbar: only when the list doesn't fit
  if maxOff > 0 then
    local trackH = FILL_ROWS * FILL_ROW_H - 2
    local thumbH = math.max(16, trackH * FILL_ROWS / #list)
    f.thumb:SetHeight(thumbH)
    f.thumb:SetPoint("TOP", f.track, "TOP", 0, -(trackH - thumbH) * f.offset / maxOff)
    f.track:Show()
    f.thumb:Show()
  else
    f.track:Hide()
    f.thumb:Hide()
  end
  f.empty:SetShown(#list == 0)
  local e = Selected(f)
  if not e and f.selID and not f.sec.job then f.selID = false end
  RefreshPicked(f, e)
  local receipts = BagCountByName(RECEIPT, bags)
  f.containers:SetShown(#list > 0)
  f.containers:SetText("Make containers" .. (receipts > 0 and (" (" .. receipts .. ")") or ""))
end

function ns.ShowFillCrates()
  if not fillWin then
    local listH = FILL_ROWS * FILL_ROW_H
    local f = Panel("CrateCostFill", FILL_W, LIST_TOP + listH + 10 + PANEL_H + 40, "Fill crates")
    f.offset, f.selID, f.qty, f.list = 0, false, 0, false
    f.rows = {}
    for i = 1, FILL_ROWS do f.rows[i] = FillRow(f, i) end
    f.track = f:CreateTexture(nil, "ARTWORK")
    f.track:SetPoint("TOPRIGHT", -12, -LIST_TOP)
    f.track:SetSize(6, listH - 2)
    f.track:SetColorTexture(0.12, 0.12, 0.12, 1)
    f.thumb = f:CreateTexture(nil, "OVERLAY")
    f.thumb:SetWidth(6)
    f.thumb:SetColorTexture(0.55, 0.55, 0.55, 1)
    f.empty = Text(f, "GameFontDisable")
    f.empty:SetPoint("TOP", 0, -60)
    f.empty:SetText("No Waylaid Crates in your bags.")
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, d)
      self.offset = math.max(0, (self.offset or 0) - d)
      RefreshFill()
    end)

    -- the picked crate, below the list
    local p = CreateFrame("Frame", nil, f, "BackdropTemplate")
    p:SetPoint("TOPLEFT", 12, -LIST_TOP - listH - 10)
    p:SetPoint("TOPRIGHT", -12, -LIST_TOP - listH - 10)
    p:SetHeight(PANEL_H)
    p:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    p:SetBackdropColor(0.03, 0.03, 0.035, 0.95)
    p:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
    f.picked = p
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetSize(36, 36)
    p.icon:SetPoint("TOPLEFT", 10, -10)
    p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p.name = Text(p, "GameFontNormalLarge")
    p.name:SetPoint("TOPLEFT", p.icon, "TOPRIGHT", 10, -1)
    p.name:SetWidth(330)
    p.name:SetWordWrap(false)
    p.how = Text(p)
    p.how:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -5)
    p.how:SetWidth(330)
    p.how:SetWordWrap(false)
    p.hint = Text(p, "GameFontHighlight")
    p.hint:SetPoint("CENTER")
    -- How many [n] of N [Max]
    p.qtyRow = CreateFrame("Frame", nil, p)
    p.qtyRow:SetSize(330, 24)
    p.qtyRow:SetPoint("BOTTOMLEFT", 56, 12)
    local lbl = Text(p.qtyRow, "GameFontHighlight")
    lbl:SetPoint("LEFT", 0, 0)
    lbl:SetText("How many")
    f.box = NumBox(p.qtyRow, 54)
    f.box:SetPoint("LEFT", lbl, "RIGHT", 12, 0)
    p.of = Text(p.qtyRow)
    p.of:SetPoint("LEFT", f.box, "RIGHT", 8, 0)
    local function SaveQty()
      local e = Selected(f)
      local n = math.max(0, math.min(e and e.can or 0, tonumber(f.box:GetText()) or 0))
      f.qty = n
      f.box:SetText(tostring(n))
      -- while filling: the new amount is where it stops
      if f.sec.job then f.sec.job.total = math.max(n, f.sec.job.done(Bags(), f.sec.job.state)) SecUpdate(f.sec) end
      RefreshFill()
    end
    f.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    f.box:SetScript("OnEditFocusLost", SaveQty)
    p.max = Button(p.qtyRow, "Max", 50, function()
      local e = Selected(f)
      f.box:SetText(tostring(e and e.can or 0))
      SaveQty()
    end)
    p.max:SetPoint("LEFT", p.of, "RIGHT", 10, 0)
    -- the Fill button and its progress, on the right
    f.sec = RunSection(p, "CrateCostFillButton", 200)
    f.sec:SetPoint("TOPRIGHT", -12, -14)
    f.sec.makeJob = function()
      local e = Selected(f)
      if e and e.can > 0 and (f.qty or 0) > 0 then return FillJob(e, math.min(f.qty, e.can)) end
    end
    f.sec.idle = function() RefreshPicked(f, Selected(f)) end
    f.sec.onFinish = function()
      f.qty = false   -- back to all it can fill
    end
    local note = Text(p, "GameFontDisableSmall")
    note:SetPoint("TOPRIGHT", f.sec, "BOTTOMRIGHT", 0, -20)
    note:SetWidth(200)
    note:SetJustifyH("RIGHT")
    note:SetText("One click per crate: the game only lets an addon use an item on a click.")

    f.containers = Button(f, "Make containers", 140, function() ns.ShowContainers() end,
      "Put Forged Delivery Receipts on empty crates: Notarized Shipping Containers for "
        .. NPCName() .. ", 50 rep each.")
    f.containers:SetPoint("BOTTOMLEFT", 12, 10)
    local hint = Text(f, "GameFontDisableSmall")
    hint:SetPoint("LEFT", f.containers, "RIGHT", 12, 0)
    hint:SetText("Each crate uses its cheapest bundle in your bags. Hover a row for every bundle.")
    f:SetScript("OnShow", function() RefreshFill() end)
    f:SetScript("OnHide", function() if not Combat() then f.sec.job = false end end)
    fillWin = f
  end
  fillWin:Show()
  fillWin:Raise()
  RefreshFill()
end

------------------------------------------------------------------------------------------------
-- Containers: a receipt on each empty crate you pick.

local contWin
local CONT_ROWS = 10

-- receipts still wanted by the rep plan (its containers less what's in your bags), or nil
local function PlanReceipts(bags)
  local ws = ns.WritStatus and ns.WritStatus()
  local c = ws and ws.plan and ws.plan.containers
  if not c then return nil end
  return math.max(0, c.n - BagCountByName(RECEIPT, bags) - BagCountByName(CONTAINER, bags))
end

-- Gives `receipts` to the kinds: crates you can't fill first, cheapest first.
local function DefaultSplit(list, receipts)
  local order = {}
  for _, e in ipairs(list) do order[#order + 1] = e end
  table.sort(order, function(a, b)
    if (a.can > 0) ~= (b.can > 0) then return a.can == 0 end
    return (a.price or math.huge) < (b.price or math.huge)
  end)
  local left = receipts
  for _, e in ipairs(order) do
    e.pick = math.min(e.n, left)
    e.on = e.pick > 0
    left = left - e.pick
  end
end

local function ContainerJob(picks)
  local total = 0
  for _, p in ipairs(picks) do total = total + p.n end
  return {
    title = "Make Notarized Shipping Containers", verb = "Make container", total = total,
    stop = "Out of receipts or picked crates.",
    start = function(bags)
      local have = {}
      for _, p in ipairs(picks) do have[p.id] = BagCount(p.id, bags) end
      return { have = have }
    end,
    done = function(bags, st)
      local n = 0
      for _, p in ipairs(picks) do n = n + math.min(p.n, math.max(0, st.have[p.id] - BagCount(p.id, bags))) end
      return n
    end,
    next = function(bags, st)
      local receipt = FirstSlot(function(s) return NameOf(s.id) == RECEIPT end, bags)
      if not receipt then return nil end
      for _, p in ipairs(picks) do
        if st.have[p.id] - BagCount(p.id, bags) < p.n then
          local crate = FirstSlot(function(s) return s.id == p.id end, bags)
          if crate then return Use(receipt) .. "\n" .. Use(crate) end
        end
      end
    end,
    after = function(n)
      if n > 0 then ns.Print("hand the containers to " .. NPCName() .. ": CrateCost asks what to hand in when you talk to them.") end
    end,
  }
end

RefreshContainers = function(reset)
  local f = contWin
  if not (f and f:IsShown()) then return end
  local bags = Bags()
  local receipts = BagCountByName(RECEIPT, bags)
  if reset or not f.list then
    local list = {}
    for _, e in ipairs(Empties(bags)) do
      e.can = math.min(e.n, Fillable(FillOptions(e.c, bags)))
      e.price = ns.Price and ns.Price(e.id)
      list[#list + 1] = e
    end
    local want = PlanReceipts(bags)
    DefaultSplit(list, receipts)
    f.list = list
    f.planNote = want or false
  else
    -- keep the picks, refresh what you hold
    local now = {}
    for _, e in ipairs(Empties(bags)) do now[e.id] = e.n end
    for _, e in ipairs(f.list) do
      e.n = now[e.id] or 0
      e.pick = math.min(e.pick or 0, e.n)
    end
  end
  local chosen = 0
  for i = 1, CONT_ROWS do
    local r, e = f.rows[i], f.list[i]
    r.entry = e or false
    if e then
      r.check:SetChecked(e.on and true or false)
      r.icon:SetTexture(IconOf(e.id))
      r.name:SetText(QualityHex(e.id) .. e.c.name .. "|r"
        .. (e.can > 0 and (GREY .. "  (you can fill " .. e.can .. ")|r") or ""))
      if not r.box:HasFocus() then r.box:SetText(tostring(e.pick or 0)) end
      r.of:SetText(GREY .. "of " .. e.n .. "|r")
      if e.on then chosen = chosen + (e.pick or 0) end
      r:Show()
    else
      r:Hide()
    end
  end
  f.empty:SetShown(#f.list == 0)
  local over = chosen > receipts
  f.summary:SetText("Receipts in your bags: " .. (receipts > 0 and Num(receipts) or (RED .. "none|r"))
    .. "     Containers to make: " .. (over and RED or GOLD) .. chosen .. "|r"
    .. (over and (RED .. "  (more than your receipts)|r") or "")
    .. (f.planNote and (GREY .. "\nThe rep plan wants " .. f.planNote .. " more receipts than you hold.|r") or ""))
  f.go:SetEnabled(chosen > 0 and receipts > 0)
  f.go:SetText("Make " .. math.min(chosen, receipts) .. " containers")
end

local function ContRow(f, i)
  local r = CreateFrame("Frame", nil, f)
  r:SetSize(f:GetWidth() - 24, 24)
  r:SetPoint("TOPLEFT", 12, -70 - (i - 1) * 26)
  r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
  r.check:SetSize(22, 22)
  r.check:SetPoint("LEFT", 0, 0)
  r.check:SetScript("OnClick", function(self)
    local e = r.entry
    if e then
      e.on = self:GetChecked() and true or false
      if e.on and (e.pick or 0) == 0 then e.pick = e.n end
      RefreshContainers()
    end
  end)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(20, 20)
  r.icon:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = Text(r, "GameFontHighlight")
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.name:SetWidth(300)
  r.name:SetWordWrap(false)
  r.of = Text(r)
  r.of:SetPoint("RIGHT", -4, 0)
  r.of:SetWidth(44)
  r.box = NumBox(r, 44)
  r.box:SetPoint("RIGHT", r.of, "LEFT", -6, 0)
  local function Save(self)
    local e = r.entry
    if not e then return end
    e.pick = math.min(e.n, math.max(0, tonumber(self:GetText()) or 0))
    e.on = e.pick > 0
    RefreshContainers()
  end
  r.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  r.box:SetScript("OnEditFocusLost", Save)
  return r
end

function ns.ShowContainers()
  if not contWin then
    local f = Panel("CrateCostContainers", 480, 70 + CONT_ROWS * 26 + 44, "Notarized Shipping Containers")
    f.list, f.planNote = false, false
    f.summary = Text(f)
    f.summary:SetPoint("TOPLEFT", 14, -32)
    f.summary:SetWidth(452)
    f.rows = {}
    for i = 1, CONT_ROWS do f.rows[i] = ContRow(f, i) end
    f.empty = Text(f, "GameFontDisable")
    f.empty:SetPoint("TOP", 0, -90)
    f.empty:SetText("No empty Waylaid Crates in your bags.")
    f.go = Button(f, "Make containers", 170, function()
      local picks, receipts = {}, BagCountByName(RECEIPT)
      for _, e in ipairs(f.list or {}) do
        if e.on and (e.pick or 0) > 0 and receipts > 0 then
          local n = math.min(e.pick, receipts)
          picks[#picks + 1] = { id = e.id, n = n }
          receipts = receipts - n
        end
      end
      if #picks > 0 then StartJob(ContainerJob(picks)) end
    end, "Puts a receipt on each picked crate, one click each.")
    f.go:SetPoint("BOTTOMRIGHT", -12, 10)
    local hint = Text(f, "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 14, 16)
    hint:SetText("Any crate takes a receipt: crates you can't fill go first, cheapest first.")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:SetScript("OnEvent", function() C_Timer.After(0.2, function() RefreshContainers() end) end)
    contWin = f
  end
  contWin:Show()
  contWin:Raise()
  RefreshContainers(true)
end

------------------------------------------------------------------------------------------------
-- Receipts: at the vendor that sells them, ask how many, then buy them.

local function FavorHave()
  local ok, fi = pcall(C_CurrencyInfo.GetCurrencyInfo, 3402)
  return (ok and fi and fi.quantity) or 0
end

local function AskReceipts(slot)
  local bags = Bags()
  local afford = math.floor(FavorHave() / RECEIPT_FAVOR)
  if afford <= 0 then return end
  local held = BagCountByName(RECEIPT, bags)
  local want = PlanReceipts(bags)
  local empties = 0
  for _, e in ipairs(Empties(bags)) do empties = empties + e.n end
  local def = want or math.max(0, empties - held)
  if def <= 0 then def = 0 end   -- nothing needs one: type how many
  Ask("Forged Delivery Receipts", RECEIPT_FAVOR .. " Merchant's Favor each. You have " .. Num(FavorHave())
    .. " favor (" .. afford .. " receipts), " .. held .. " receipts and " .. empties .. " empty crates in your bags."
    .. (want and ("\nThe rep plan wants " .. want .. " more.") or ""),
    math.min(def, afford), afford, function(n)
      local i = ns.MerchantFind(RECEIPT) or slot
      local bought = ns.MerchantBuy(i, n)
      ns.Print("buying " .. bought .. " " .. RECEIPT .. (bought == 1 and "." or "s."))
      if empties > 0 then C_Timer.After(1.5, function() ns.ShowContainers() end) end
    end)
end

local askedHere = false
if ns.UI and ns.UI.OnMerchant then
  ns.UI.OnMerchant(function()
    if not ns.MerchantOpen() then askedHere = false return end
    if askedHere or not On("receiptPrompt") then return end
    local i = ns.MerchantFind(RECEIPT)
    if i then
      askedHere = true
      AskReceipts(i)
    end
  end)
end
function ns.AskReceipts() local i = ns.MerchantFind(RECEIPT) if i then AskReceipts(i) end end

------------------------------------------------------------------------------------------------
-- Hand in: at Dokimi / Marcy Baker, pick what to hand in, then it talks through the quests.
-- Which quest takes which item is learned from the quest's required items the first time
-- (CrateCostDB.handin[questID]), so later visits go straight to the right one.

local handWin, hand   -- hand = the running hand-in: { left = { [itemID] = n }, tried = {} }
local HAND_ROWS = 10

-- What you could hand in: Sealed Crates and Notarized Shipping Containers in your bags.
local function HandInItems(bags)
  local seen, out = {}, {}
  for _, s in ipairs(bags) do
    if not seen[s.id] then
      local sc = ns.SealedCrates and ns.SealedCrates[s.id]
      local name = NameOf(s.id)
      if sc or name == CONTAINER then
        seen[s.id] = true
        out[#out + 1] = { id = s.id, n = BagCount(s.id, bags), sealed = sc,
          sort = sc and ({ Apprentice = 1, Journeyman = 2, Expert = 3, Artisan = 4 })[sc[1]] or 9 }
      end
    end
  end
  table.sort(out, function(a, b) if a.sort ~= b.sort then return a.sort < b.sort end return a.id < b.id end)
  return out
end

-- the status line under the list; `big`: the large gold line, for what you have to do next
local function Status(text, big)
  if not handWin then return end
  handWin.status:SetText(big and "" or (text or ""))
  handWin.wait:SetText(big and (text or "") or "")
end

local function ItemOfLink(link)
  return link and tonumber(link:match("item:(%d+)"))
end

local function LooksLikeHandIn(title)
  local t = (title or ""):lower()
  for _, w in ipairs(HANDIN_TITLES) do if t:find(w, 1, true) then return true end end
  return false
end

-- the quests the NPC offers: { title, questID, active, index }
local function NPCQuests()
  local out = {}
  local G = C_GossipInfo
  if GossipFrame and GossipFrame:IsShown() and G and G.GetActiveQuests then
    for i, q in ipairs(G.GetActiveQuests() or {}) do
      out[#out + 1] = { title = q.title, questID = q.questID, active = true, index = i, gossip = true,
        complete = q.isComplete }
    end
    for i, q in ipairs(G.GetAvailableQuests and G.GetAvailableQuests() or {}) do
      out[#out + 1] = { title = q.title, questID = q.questID, active = false, index = i, gossip = true }
    end
  else
    for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
      local title, complete = GetActiveTitle(i)
      out[#out + 1] = { title = title, questID = GetActiveQuestID and GetActiveQuestID(i), active = true,
        index = i, complete = complete }
    end
    for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
      out[#out + 1] = { title = GetAvailableTitle(i), active = false, index = i }
    end
  end
  return out
end

local function Left()
  local n = 0
  if hand then for _, k in pairs(hand.left) do n = n + k end end
  return n
end

local function StopHand(msg)
  if hand and msg then ns.Print(msg) end
  hand = nil
  if handWin then
    handWin.go:Enable()
    handWin.go:SetText("Hand in")
  end
end

local function RefreshHand()
  local f = handWin
  if not (f and f:IsShown()) then return end
  local bags = Bags()
  local held = {}
  for _, it in ipairs(HandInItems(bags)) do held[it.id] = it.n end
  if not f.list then
    f.list = HandInItems(bags)
    for _, it in ipairs(f.list) do it.on, it.pick = true, it.n end
  end
  local total = 0
  for i = 1, HAND_ROWS do
    local r, it = f.rows[i], f.list[i]
    r.entry = it or false
    if it then
      it.n = held[it.id] or 0
      if hand then it.pick = math.min(it.pick, hand.left[it.id] or 0) end
      it.pick = math.min(it.pick or 0, it.n)
      r.check:SetChecked(it.on and true or false)
      r.icon:SetTexture(IconOf(it.id))
      local name = NameOf(it.id) or ("item " .. it.id)
      local fav = it.sealed and ns.FavorFor and ns.FavorFor(it.sealed[1], it.sealed[2] == "crafted" and "Fabrics" or "Ore")
      r.name:SetText(QualityHex(it.id) .. name .. "|r"
        .. (fav and (GREY .. "  " .. fav .. " favor|r") or (it.sealed and "" or (GREY .. "  50 rep|r"))))
      if not r.box:HasFocus() then r.box:SetText(tostring(it.pick)) end
      r.of:SetText(GREY .. "of " .. it.n .. "|r")
      if it.on then total = total + it.pick end
      r:Show()
    else
      r:Hide()
    end
  end
  if not hand then
    f.go:SetEnabled(total > 0)
    f.go:SetText(total > 0 and ("Hand in " .. total) or "Hand in")
  else
    f.go:Disable()
    f.go:SetText(Left() .. " to go")
  end
end

local function Continue()
  if not hand then return end
  if Left() <= 0 then
    StopHand("handed in everything you picked.")
    RefreshHand()
    if handWin then Status(GREEN .. "All handed in.|r") end
    return
  end
  local db = DB()
  local pick
  for _, q in ipairs(NPCQuests()) do
    local item = q.questID and db.handin[q.questID]
    if item and (hand.left[item] or 0) > 0 then pick = q break end
  end
  if not pick then
    -- not learned yet: a hand-in title, ones the game marks ready first
    for pass = 1, 2 do
      for _, q in ipairs(NPCQuests()) do
        local known = q.questID and db.handin[q.questID]
        local key = q.questID or q.title
        if known == nil and not hand.tried[key] and LooksLikeHandIn(q.title)
          and (pass == 2 or q.complete) then pick = q break end
      end
      if pick then break end
    end
  end
  if not pick then
    StopHand()
    Status(GOLD .. "Nothing more here takes what's left (" .. Num(Left()) .. ").|r")
    RefreshHand()
    return
  end
  hand.current = pick
  hand.waiting = false
  hand.item = false
  Status("Handing in: " .. (pick.title or "?"))
  if pick.gossip then
    if pick.active then C_GossipInfo.SelectActiveQuest(pick.questID)
    else C_GossipInfo.SelectAvailableQuest(pick.questID) end
  else
    if pick.active then SelectActiveQuest(pick.index) else SelectAvailableQuest(pick.index) end
  end
end

-- The quest window shows what it takes: hand it in if that's one of the picked items.
-- What the quest window asks for: { id, name, quality }. The item ID comes from the quest info,
-- else the link; the link is nil while the item isn't loaded yet, so the name is kept too.
local function Required()
  local out = {}
  for i = 1, (GetNumQuestItems and GetNumQuestItems() or 0) do
    local ok, name, _, _, quality, _, itemID = pcall(GetQuestItemInfo, "required", i)
    if not ok then name, quality, itemID = nil, nil, nil end
    local id = (type(itemID) == "number" and itemID > 0 and itemID)
      or ItemOfLink(GetQuestItemLink and GetQuestItemLink("required", i))
    out[#out + 1] = { id = id, name = name, quality = quality }
  end
  return out
end

local function QualityOf(id)
  local ok, q = pcall(C_Item and C_Item.GetItemQualityByID or function() end, id)
  return ok and q or nil
end

-- The picked item a required item is: by ID, else by name (and quality, as the white and green
-- Sealed Crates of a rank share a name).
local function Match(req)
  for _, r in ipairs(req) do
    if r.id and (hand.left[r.id] or 0) > 0 then return r.id end
  end
  for _, r in ipairs(req) do
    if not r.id and r.name then
      for item, n in pairs(hand.left) do
        if n > 0 and NameOf(item) == r.name and (not r.quality or not QualityOf(item) or QualityOf(item) == r.quality) then
          return item
        end
      end
    end
  end
end

local function OnProgress()
  local id = GetQuestID and GetQuestID()
  local req = Required()
  local item = Match(req)
  local db = DB()
  local ready = not IsQuestCompletable or IsQuestCompletable()
  if item and ready then
    if id then db.handin[id] = item end
    hand.item = item
    CompleteQuest()
    return
  end
  -- learn it only from an item ID that was read, never from an item not loaded yet
  if id and not item and req[1] and req[1].id then db.handin[id] = req[1].id end
  hand.tried[id or (hand.current and hand.current.title) or "?"] = true
  local asks = {}
  for _, r in ipairs(req) do asks[#asks + 1] = (r.name or "?") .. " (" .. tostring(r.id or "not loaded") .. ")" end
  ns.Print(string.format("closed quest %s \"%s\": %s. It asks for: %s.", tostring(id),
    tostring(hand.current and hand.current.title or (GetTitleText and GetTitleText()) or "?"),
    item and "not ready to hand in" or "not one of the picked items",
    #asks > 0 and table.concat(asks, ", ") or "nothing listed"))
  if CloseQuest then CloseQuest() end
  Status("Right-click " .. NPCName() .. " to carry on.", true)
end

local function OnComplete()
  local n = GetNumQuestChoices and GetNumQuestChoices() or 0
  if n > 1 then
    Status(GOLD .. "Pick a reward, then it carries on.|r")
    return
  end
  GetQuestReward(n)
end

local function OnTurnedIn(questID)
  local item = (questID and DB().handin[questID]) or hand.item
  if item and hand.left[item] then hand.left[item] = math.max(0, hand.left[item] - 1) end
  hand.item = false
  hand.waiting = true
  RefreshHand()
  -- the NPC usually comes straight back; if not, it carries on when you talk to them again
  C_Timer.After(1.2, function()
    if hand and hand.waiting then
      if Left() <= 0 then Continue()
      else Status("Right-click " .. NPCName() .. " for the next one (" .. Left() .. " left).", true) end
    end
  end)
end

local function HandRow(f, i)
  local r = CreateFrame("Frame", nil, f)
  r:SetSize(f:GetWidth() - 24, 24)
  r:SetPoint("TOPLEFT", 12, -54 - (i - 1) * 26)
  r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
  r.check:SetSize(22, 22)
  r.check:SetPoint("LEFT", 0, 0)
  r.check:SetScript("OnClick", function(self)
    local it = r.entry
    if it and not hand then
      it.on = self:GetChecked() and true or false
      if it.on and it.pick == 0 then it.pick = it.n end
      RefreshHand()
    end
  end)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(20, 20)
  r.icon:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = Text(r, "GameFontHighlight")
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.name:SetWidth(230)
  r.name:SetWordWrap(false)
  r.of = Text(r)
  r.of:SetPoint("RIGHT", -4, 0)
  r.of:SetWidth(40)
  r.box = NumBox(r, 40)
  r.box:SetPoint("RIGHT", r.of, "LEFT", -6, 0)
  r.box:SetScript("OnEditFocusLost", function(self)
    local it = r.entry
    if not it or hand then return end
    it.pick = math.min(it.n, math.max(0, tonumber(self:GetText()) or 0))
    it.on = it.pick > 0
    RefreshHand()
  end)
  r:EnableMouse(true)
  r:SetScript("OnEnter", function(self)
    if not r.entry then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetItemByID, GameTooltip, r.entry.id)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end

local function BuildHand()
  local f = Panel("CrateCostHandIn", 400, 54 + HAND_ROWS * 26 + 92, "Hand in")
  f.ask = Text(f)
  f.ask:SetPoint("TOPLEFT", 14, -30)
  f.ask:SetWidth(372)
  f.ask:SetText("You have these to hand in. Which would you like to hand in?")
  f.rows = {}
  for i = 1, HAND_ROWS do f.rows[i] = HandRow(f, i) end
  f.wait = Text(f, "GameFontNormalLarge")
  f.wait:SetPoint("BOTTOMLEFT", 14, 62)
  f.wait:SetWidth(372)
  f.status = Text(f, "GameFontHighlightSmall")
  f.status:SetPoint("BOTTOMLEFT", 14, 40)
  f.status:SetWidth(372)
  f.go = Button(f, "Hand in", 130, function()
    if hand then return end
    local left = {}
    for _, it in ipairs(f.list or {}) do
      if it.on and it.pick > 0 then left[it.id] = it.pick end
    end
    if not next(left) then return end
    hand = { left = left, tried = {}, current = false, item = false, waiting = false }
    RefreshHand()
    Continue()
  end, "Talks through each hand-in quest until everything ticked is handed in.")
  f.go:SetPoint("BOTTOMRIGHT", -12, 10)
  local later = Button(f, "Not now", 90, function() f:Hide() end)
  later:SetPoint("RIGHT", f.go, "LEFT", -6, 0)
  f:SetScript("OnHide", function() if hand then StopHand("hand-in stopped.") end end)
  handWin = f
end

local function ShowHand()
  if not handWin then BuildHand() end
  -- the quest window reads the crates' item data: ask for it now
  if C_Item and C_Item.RequestLoadItemDataByID then
    for id in pairs(ns.SealedCrates or {}) do pcall(C_Item.RequestLoadItemDataByID, id) end
  end
  handWin.list = false
  Status("")
  handWin:ClearAllPoints()
  local anchor = (GossipFrame and GossipFrame:IsShown() and GossipFrame) or (QuestFrame and QuestFrame:IsShown() and QuestFrame)
  if anchor then handWin:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0) else handWin:SetPoint("CENTER") end
  handWin:Show()
  RefreshHand()
end

local function AtHandInNPC()
  local name = UnitName and UnitName("npc")
  if name and HANDIN_NPCS[name] then return true end
  -- or an NPC whose quests are ones CrateCost learned take a crate or container
  local db = DB()
  for _, q in ipairs(NPCQuests()) do
    if q.questID and db.handin[q.questID] then return true end
  end
  return false
end

local qf = CreateFrame("Frame")
for _, ev in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
  "QUEST_TURNED_IN", "GOSSIP_CLOSED", "QUEST_FINISHED" }) do
  if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(ev) then
    pcall(qf.RegisterEvent, qf, ev)
  end
end
qf:SetScript("OnEvent", function(_, ev, a1)
  if ev == "GOSSIP_SHOW" or ev == "QUEST_GREETING" then
    if hand then
      hand.waiting = false
      C_Timer.After(0.1, Continue)
    elseif handWin and handWin:IsShown() then
      RefreshHand()   -- the NPC coming back after a hand-in: keep the window as it is
    elseif On("handinPrompt") and AtHandInNPC() and #HandInItems(Bags()) > 0 then
      ShowHand()
    end
  elseif not hand then
    if ev == "GOSSIP_CLOSED" and handWin and handWin:IsShown() then
      C_Timer.After(0.3, function()
        local open = (GossipFrame and GossipFrame:IsShown()) or (QuestFrame and QuestFrame:IsShown())
        if not open and not hand and handWin then handWin:Hide() end
      end)
    end
  elseif ev == "QUEST_DETAIL" then
    -- an offered hand-in: only the one we picked, and only a hand-in title
    if hand.current and LooksLikeHandIn(GetTitleText and GetTitleText()) then AcceptQuest()
    else StopHand("stopped: an unexpected quest came up.") end
  elseif ev == "QUEST_PROGRESS" then
    if hand.current then OnProgress() end
  elseif ev == "QUEST_COMPLETE" then
    -- only the quest it just completed for you; any other is yours to finish
    if hand.item then OnComplete() end
  elseif ev == "QUEST_TURNED_IN" then
    OnTurnedIn(a1)
  end
end)

function ns.ShowHandIn() ShowHand() end
