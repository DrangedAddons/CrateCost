local _, ns = ...

-- Plan checklists: a small window per plan (rep, favor) with just the steps, ticked as you do
-- them. Steps the game can see tick themselves (a quest handed in, a writ done today, Sealed
-- Crates handed in, the target reached); the rest (buying receipts, crates) you tick by clicking.
-- Hover a step for its details. The ticks belong to the plan they were made for: a new plan
-- (Regenerate, another target) starts the list fresh.

local W, ROW_H, ROWS, TOP = 300, 18, 18, 30
local GREY = "|cff808080"
local GREEN = "|cff40ff40"

local function Num(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end

local function Ticks(kind, stamp)
  if type(CrateCostCharDB) ~= "table" then CrateCostCharDB = {} end
  CrateCostCharDB.checklist = CrateCostCharDB.checklist or {}
  local t = CrateCostCharDB.checklist[kind]
  if not t or t.stamp ~= stamp then
    t = { stamp = stamp }
    CrateCostCharDB.checklist[kind] = t
  end
  return t
end

local function FavorHave()
  local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(3402)
  return (info and info.quantity) or 0
end

local function Horde() return UnitFactionGroup and UnitFactionGroup("player") == "Horde" end

-- steps: { { id, text, done (auto), tip = { lines } }, ... }, stamp, title
local function RepSteps()
  local ws = ns.WritStatus and ns.WritStatus()
  local p = ws and ws.plan
  if not p then return nil end
  local steps = {}
  local function Add(s) steps[#steps + 1] = s end
  if p.label then
    Add({ id = "label", text = "Do the Shipping Label quest", done = ws.labelDone,
      tip = { "Shipping Label quest: +2,000 rep, 50 Merchant's Favor.",
        "Start your first writ (or fill a crate) to get the label, then deliver it to "
          .. (Horde() and "Dokimi" or "Marcy Baker") .. "." } })
  end
  local function Writs(stage)
    for _, it in ipairs(p.list) do
      if not it.spent and (it.stage or 2) == stage then
        local e = it.e
        Add({ id = "writ:" .. e.writ, text = "Fulfil writ: " .. e.name, done = e.done,
          tip = { e.name .. " (" .. e.rank .. ", " .. e.rep .. " rep)",
            (it.owned and "Have the writ" or "Buy the writ") .. ", " .. (it.crafted and "craft" or "buy") .. " "
              .. (e.qty > 1 and (e.qty .. "x ") or "") .. "the item: " .. ns.Money(it.cost),
            e.recipient ~= "" and ("Deliver to " .. e.recipient) or nil } })
      end
    end
  end
  Writs(1)
  local c = p.containers
  if c then
    local favorDone = FavorHave() >= c.favor
    if c.src then
      Add({ id = "favor", text = "Buy + fill " .. c.src.n .. " " .. c.src.name .. ", hand in", done = favorDone,
        tip = { "Earn " .. Num(c.earn) .. " Merchant's Favor for the receipts.",
          "Buy " .. c.src.n .. " Waylaid Crate: " .. c.src.name .. ", fill each with " .. c.src.qty .. " " .. c.src.bundle
            .. ", hand them in.", "Ticks itself when you have " .. Num(c.favor) .. " favor." } })
    end
    Add({ id = "receipts", text = "Buy " .. c.n .. " Forged Delivery Receipts",
      tip = { Num(c.favor) .. " favor from " .. (Horde() and "Kurvelk Shadowhoof" or "Dianne Softstep") .. ".",
        "Click to tick when done." } })
    Add({ id = "crates", text = "Buy " .. c.n .. " empty Waylaid Crates",
      tip = { "The cheapest on the AH: any crate takes a receipt.", "Click to tick when done." } })
    Add({ id = "handin", text = "Hand in " .. c.n .. " containers", done = ws.need == nil,
      tip = { "Use a receipt on each empty crate, hand them to " .. (Horde() and "Dokimi" or "Marcy Baker") .. ".",
        "50 rep each. Click to tick, or it ticks at the target." } })
  end
  Writs(2)
  if ws.targetName then
    Add({ id = "target", text = "Reach " .. ws.targetName, done = ws.need == nil,
      tip = { ws.need and (Num(ws.need) .. " rep to go.") or "Reached." } })
  end
  local stamp = (ws.target or 0) .. ":" .. #p.list .. ":" .. math.floor(p.cost or 0)
  return steps, stamp, "Rep plan" .. (ws.targetName and (" to " .. ws.targetName) or "")
end

local function FavorSteps()
  local fs = ns.FavorStatus and ns.FavorStatus()
  local p = fs and fs.plan
  if not p then return nil end
  local steps = {}
  local function Add(s) steps[#steps + 1] = s end
  if p.sealed > 0 then
    Add({ id = "sealed", text = "Hand in " .. p.sealed .. " Sealed Crates", done = fs.sealed == 0,
      tip = { "Already filled, in your bags: " .. Num(p.sealedFavor) .. " favor.", "Ticks itself when they're gone." } })
  end
  if p.label then
    Add({ id = "label", text = "Do the Shipping Label quest", done = fs.labelDone,
      tip = { "Your first filled crate gives a Shipping Label: 50 favor (and 2,000 rep).",
        "Deliver it to " .. (Horde() and "Dokimi" or "Marcy Baker") .. "." } })
  end
  for _, pick in ipairs(p.picks) do
    local c = pick.c
    Add({ id = "pick:" .. c.name, text = "Buy + fill " .. pick.n .. " " .. c.name .. ", hand in",
      tip = { pick.n .. " Waylaid Crate: " .. c.name .. (pick.held > 0 and (" (" .. pick.held .. " you have)") or ""),
        "Fill each with " .. pick.qty .. " " .. pick.bundle .. ": " .. Num(pick.n * c.favor) .. " favor.",
        "Costs " .. ns.Money(pick.upFront or pick.cost) .. ". Click to tick when done." } })
  end
  Add({ id = "target", text = "Reach " .. Num(p.target) .. " favor", done = fs.have >= p.target,
    tip = { "You have " .. Num(fs.have) .. "." } })
  local stamp = p.target .. ":" .. #p.picks .. ":" .. math.floor(p.cost or 0)
  return steps, stamp, "Favor plan to " .. Num(p.target)
end

local SOURCES = { rep = RepSteps, favor = FavorSteps }
local windows = {}

local function Fill(w)
  local steps, stamp, title = SOURCES[w.kind]()
  if not steps then
    w.title:SetText(w.kind == "rep" and "Rep plan" or "Favor plan")
    w.progress:SetText("")
    w.empty:Show()
    for _, r in ipairs(w.rows) do r:Hide() end
    return
  end
  w.empty:Hide()
  local ticks = Ticks(w.kind, stamp)
  local done = 0
  for _, s in ipairs(steps) do
    s.checked = s.done or ticks[s.id] or false
    if s.checked then done = done + 1 end
  end
  w.title:SetText(title)
  w.progress:SetText((done == #steps and GREEN or "") .. done .. " / " .. #steps .. (done == #steps and "|r" or ""))
  -- start at the first step not done, the rest scrolls
  if not w.scrolled then
    local first = 1
    for i, s in ipairs(steps) do if not s.checked then first = i break end end
    w.offset = math.max(0, first - 2)
  end
  w.offset = math.max(0, math.min(w.offset, #steps - ROWS))
  for i = 1, ROWS do
    local r, s = w.rows[i], steps[w.offset + i]
    r.step, r.ticks = s or false, ticks
    if s then
      r.check:SetChecked(s.checked)
      r.text:SetText(s.checked and (GREY .. s.text .. "|r") or s.text)
      r:Show()
    else
      r:Hide()
    end
  end
end

local function Build(kind)
  local w = CreateFrame("Frame", "CrateCostChecklist" .. kind, UIParent, "BackdropTemplate")
  w.kind, w.offset, w.rows = kind, 0, {}
  w:SetSize(W, TOP + ROWS * ROW_H + 10)
  w:SetFrameStrata("MEDIUM")
  w:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  w:SetBackdropColor(0.05, 0.05, 0.07, 0.85)
  w:SetBackdropBorderColor(0.35, 0.3, 0.22, 1)
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
    w:SetPoint("RIGHT", UIParent, "RIGHT", kind == "rep" and -340 or -20, 120)
  end
  w.title = w:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  w.title:SetPoint("TOPLEFT", 10, -9)
  w.progress = w:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  w.progress:SetPoint("TOPRIGHT", -28, -10)
  local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
  close:SetSize(22, 22)
  close:SetPoint("TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function() w:Hide() end)
  w.empty = w:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  w.empty:SetPoint("TOP", 0, -TOP - 6)
  w.empty:SetText(kind == "rep" and "No rep plan: pick a target." or "No favor plan: type a target.")
  for i = 1, ROWS do
    local r = CreateFrame("Frame", nil, w)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 6, -TOP - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", w, "RIGHT", -6, 0)
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(18, 18)
    r.check:SetPoint("LEFT", 0, 0)
    r.check:SetScript("OnClick", function(self)
      local s = r.step
      if s then
        -- a step the game ticks stays ticked; the rest follow your click
        if not s.done then r.ticks[s.id] = self:GetChecked() and true or nil end
        w.scrolled = true
        Fill(w)
      end
    end)
    r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
    r.text:SetPoint("RIGHT", 0, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
      local s = self.step
      if not s then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(s.text)
      for _, l in ipairs(s.tip or {}) do GameTooltip:AddLine(l, 1, 1, 1, true) end
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
  -- the game ticks steps as you go
  for _, ev in ipairs({ "QUEST_TURNED_IN", "BAG_UPDATE_DELAYED", "CURRENCY_DISPLAY_UPDATE", "UPDATE_FACTION" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(ev) then
      pcall(w.RegisterEvent, w, ev)
    end
  end
  local pending = false
  w:SetScript("OnEvent", function()
    if pending or not w:IsShown() then return end
    pending = true
    C_Timer.After(0.5, function() pending = false if w:IsShown() then Fill(w) end end)
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
