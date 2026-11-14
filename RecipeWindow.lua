local _, ns = ...

-- Merchant list: every recipe (and the mount, pet, tabard, title and certifications) the
-- Durotar Supply / Azeroth Commerce vendors sell for Merchant's Favor. Search matches name,
-- profession, type, slot, effect and the crafted item's Equip / Use lines. Filter by
-- profession, stats (with a minimum), learned, affordable and favorites. Click a header to sort.

local ROW_H, VISIBLE, WIDTH, TOP = 18, 24, 1000, 84
local COLS = {
  { key = "fav",    title = "",           x = 10,  w = 16,  justify = "CENTER", desc = true },
  { key = "name",   title = "Recipe",     x = 30,  w = 185, justify = "LEFT"  },
  { key = "prof",   title = "Profession", x = 220, w = 88,  justify = "LEFT"  },
  { key = "type",   title = "Type",       x = 312, w = 62,  justify = "LEFT"  },
  { key = "skill",  title = "Skill",      x = 378, w = 32,  justify = "RIGHT", desc = false },
  { key = "level",  title = "Level",      x = 414, w = 32,  justify = "RIGHT", desc = false },
  { key = "slot",   title = "Slot",       x = 456, w = 100, justify = "LEFT"  },
  { key = "effect", title = "Effect",     x = 560, w = 232, justify = "LEFT"  },
  { key = "rep",    title = "Reputation", x = 796, w = 60,  justify = "LEFT",  desc = false },
  { key = "cost",   title = "Favor",      x = 858, w = 52,  justify = "RIGHT", desc = false },
  { key = "known",  title = "Learned",    x = 916, w = 44,  justify = "CENTER", desc = true },
}
local REP_NAME = { [0] = "", "Friendly", "Honored", "Revered", "Exalted" }
local REP_COLOR = { [0] = "|cffffffff", "|cff40c040", "|cff40bf80", "|cff00c0c0", "|cff00ffff" }
local PROFS = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering",
  "Leatherworking", "Tailoring", "Other" }
local FAVOR_CURRENCY = 3402
local STAR_ATLAS, STAR_FILE = "PetJournal-FavoritesIcon", "Interface\\Common\\FavoritesIcon"

local frame, rows, headers, all = nil, {}, {}, nil
-- prof: nil = all, "mine" = this character's professions, else a profession name.
-- stats: { key = true (any amount) | minimum }
-- statSort: a stat key to order by (overrides the column sort until a header is clicked);
-- statLow: lowest first instead of highest.
local view = { sort = "prof", desc = false, search = "", prof = nil, hideKnown = false,
  afford = false, favOnly = false, stats = {}, offset = 0, statSort = nil, statLow = false }

-- Favorites are per character: what this character is saving favor for.
local function Favorites()
  if type(CrateCostCharDB) ~= "table" then CrateCostCharDB = {} end
  CrateCostCharDB.favorites = CrateCostCharDB.favorites or {}
  return CrateCostCharDB.favorites
end

local function FavKey(e)
  return e.spell and ("s" .. e.spell) or ("i" .. tostring(e.item))
end

local function Entries()
  if all then return all end
  all = {}
  for _, r in ipairs(ns.Recipes) do
    all[#all + 1] = { name = r[1], prof = r[2], type = r[3], skill = r[4], cost = r[5],
      rep = r[6], level = r[7], effect = r[8], slot = r[9], spell = r[10],
      craft = r[11] ~= 0 and r[11] or nil }
  end
  for _, r in ipairs(ns.FavorItems) do
    all[#all + 1] = { name = r[1], prof = "Other", type = r[5], skill = 0, cost = r[2],
      rep = r[3], level = r[4], effect = r[6], slot = "", item = r[7] }
  end
  for _, e in ipairs(all) do
    -- the certifications are a profession's own reward
    local p = e.name:match("^(%a+) Certification$")
    if p then e.prof, e.skill = p, 300 end
    e.text = table.concat({ e.name, e.prof, e.type, e.slot, e.effect }, "\n"):lower()
    e.lname = e.name:lower()
    e.key = FavKey(e)
  end
  return all
end

local function Favor()
  local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
    and C_CurrencyInfo.GetCurrencyInfo(FAVOR_CURRENCY)
  return info and info.quantity or 0
end

local function Known(e)
  if not e.spell then return false end
  local ok, known = pcall(IsPlayerSpell, e.spell)
  return ok and known and true or false
end

-- This character's professions by name (empty if the API isn't there).
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

-- Effect column: the guide's text, plus the crafted item's Equip / Use effects.
local function EffectShown(e)
  local fx = e.craft and ns.ItemEffectDisplay(e.craft) or ""
  if fx == "" then return e.effect end
  if e.effect == "" then return fx end
  return e.effect .. "; " .. fx
end

local function SortValue(e, key, favs)
  if key == "known" then return e.known and 1 or 0 end
  if key == "fav" then return favs[e.key] and 1 or 0 end
  if key == "rep" or key == "skill" or key == "level" or key == "cost" then return e[key] or 0 end
  if key == "effect" then return EffectShown(e):lower() end
  return (e[key] or ""):lower()
end

-- e.sortValue is filled once per refresh for the shown rows, so the comparator doesn't
-- rebuild strings O(n log n) times
local function Compare(a, b)
  local va, vb = a.sortValue, b.sortValue
  if view.statSort then
    -- rows without the stat always go last, whichever direction
    if va == nil and vb ~= nil then return false end
    if vb == nil and va ~= nil then return true end
    if va ~= vb then
      if view.statLow then return va < vb end
      return va > vb
    end
  elseif va ~= vb then
    if view.desc then return va > vb end
    return va < vb
  end
  -- ties: profession, then skill, then name
  if a.prof ~= b.prof then return a.prof < b.prof end
  if a.skill ~= b.skill then return a.skill < b.skill end
  return a.name < b.name
end

local function ShowRowTooltip(row)
  local e = row.entry
  if not e then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  -- the crafted item shows its stats; enchants only have the spell
  local shown = false
  local item = e.craft or e.item
  if item then
    shown = pcall(GameTooltip.SetItemByID, GameTooltip, item) and GameTooltip:NumLines() > 0
  elseif e.spell then
    shown = pcall(GameTooltip.SetSpellByID, GameTooltip, e.spell) and GameTooltip:NumLines() > 0
  end
  if not shown then
    GameTooltip:ClearLines()
    GameTooltip:AddLine(e.name)
    if e.effect ~= "" then GameTooltip:AddLine(e.effect, 1, 1, 1, true) end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine("Merchant's Favor", e.cost .. ns.FavorIcon(), 1, 0.82, 0, 1, 1, 1)
  if e.rep > 0 then
    GameTooltip:AddDoubleLine("Reputation", REP_NAME[e.rep], 1, 0.82, 0, 1, 1, 1)
  end
  if e.skill > 0 then
    GameTooltip:AddDoubleLine(e.prof, e.skill, 1, 0.82, 0, 1, 1, 1)
  end
  if e.level > 0 then
    GameTooltip:AddDoubleLine("Required level", e.level, 1, 0.82, 0, 1, 1, 1)
  end
  GameTooltip:Show()
end

local function SetStar(tex)
  if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(STAR_ATLAS) then
    tex:SetAtlas(STAR_ATLAS)
  else
    tex:SetTexture(STAR_FILE)
  end
end

local function PaintStar(star, on)
  star.tex:SetDesaturated(not on)
  star.tex:SetAlpha(on and 1 or (star:IsMouseOver() and 0.6 or 0.15))
end

local list = {}
local Draw

local function MakeRow(i)
  local row = CreateFrame("Button", nil, frame)
  row:SetSize(WIDTH - 36, ROW_H)
  row:SetPoint("TOPLEFT", 8, -TOP - (i - 1) * ROW_H)
  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)
  row.cells = {}
  for _, col in ipairs(COLS) do
    if col.key ~= "fav" then
      local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      fs:SetPoint("LEFT", row, "LEFT", col.x - 8 + 2, 0)
      fs:SetWidth(col.w)
      fs:SetJustifyH(col.justify)
      fs:SetWordWrap(false)
      row.cells[col.key] = fs
    end
  end

  -- favorite star: click to toggle
  local star = CreateFrame("Button", nil, row)
  star:SetSize(16, 16)
  star:SetPoint("LEFT", row, "LEFT", COLS[1].x - 8 + 2, 0)
  star.tex = star:CreateTexture(nil, "ARTWORK")
  star.tex:SetAllPoints()
  SetStar(star.tex)
  star:SetScript("OnClick", function()
    local e = row.entry
    if not e then return end
    local favs, k = Favorites(), e.key
    favs[k] = (not favs[k]) and true or nil
    if view.favOnly or view.sort == "fav" then ns.RefreshRecipes() else Draw() end
  end)
  star:SetScript("OnEnter", function(self)
    local e = row.entry
    PaintStar(self, e and Favorites()[e.key])
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(e and Favorites()[e.key] and "Remove from favorites" or "Add to favorites", 1, 1, 1)
    GameTooltip:Show()
  end)
  star:SetScript("OnLeave", function(self)
    local e = row.entry
    GameTooltip:Hide()
    PaintStar(self, e and Favorites()[e.key])
  end)
  row.star = star

  row:SetScript("OnEnter", ShowRowTooltip)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:SetScript("OnClick", function(self)
    -- shift-click links the item (or the enchant's spell) in chat, or types its name into a
    -- focused search box
    local e = self.entry
    if not (e and IsModifiedClick("CHATLINK")) then return end
    local link
    local item = e.craft or e.item
    if item then
      ns.SearchAuctionator(item, e.name)   -- loads the item first if it isn't cached
      return
    elseif e.spell then
      local ok, l = pcall(function()
        return (C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(e.spell))
          or (GetSpellLink and GetSpellLink(e.spell))
      end)
      link = ok and l
    end
    ns.InsertLink(link, e.name)
  end)
  rows[i] = row
  return row
end

local function UpdateHeaders()
  for _, h in ipairs(headers) do
    local t = h.col.title
    if view.statSort then
      if h.col.key == "effect" then
        t = t .. "  |cffffffff(" .. ns.StatLabel(view.statSort) .. (view.statLow and " ^" or " v") .. ")|r"
      end
    elseif view.sort == h.col.key then
      t = t .. (view.desc and " v" or " ^")
    end
    h.text:SetText(t)
  end
  if frame.statSortBtn then
    frame.statSortBtn.text:SetText(view.statSort and ("Sort: " .. ns.StatLabel(view.statSort)) or "Sort by stat")
  end
end

function Draw()
  local maxOff = math.max(0, #list - VISIBLE)
  if view.offset > maxOff then view.offset = maxOff end
  if view.offset < 0 then view.offset = 0 end
  local have, favs = Favor(), Favorites()
  for i = 1, VISIBLE do
    local row = rows[i] or MakeRow(i)
    local e = list[view.offset + i]
    row.entry = e
    if e then
      local c = row.cells
      c.name:SetText(e.known and ("|cff808080" .. e.name .. "|r") or e.name)
      c.prof:SetText(e.prof)
      c.type:SetText(e.type)
      c.skill:SetText(e.skill > 0 and e.skill or "")
      c.level:SetText(e.level > 0 and e.level or "")
      c.slot:SetText(e.slot)
      -- sorting by a stat: its value leads the Effect cell
      local lead = ""
      if view.statSort and e.sortValue then
        lead = "|cffffd100" .. e.sortValue .. " " .. ns.StatLabel(view.statSort) .. "|r  "
      end
      c.effect:SetText(lead .. "|cffc0c0c0" .. EffectShown(e) .. "|r")
      c.rep:SetText(REP_COLOR[e.rep] .. REP_NAME[e.rep] .. "|r")
      c.cost:SetText((have >= e.cost and "|cff40ff40" or "|cffffffff") .. e.cost .. "|r" .. ns.FavorIcon())
      c.known:SetText(e.known and "|cff40ff40yes|r" or "")
      PaintStar(row.star, favs[e.key])
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

local function StatsOn()
  local n = 0
  for _ in pairs(view.stats) do n = n + 1 end
  return n
end

-- Learned state only changes when you learn something: worked out on open and on the learn
-- events, not on every keystroke in the search box.
local knownDirty = true
local lastFavor

function ns.RefreshRecipes()
  if not (frame and frame:IsShown()) then return end
  local mine = view.prof == "mine" and MyProfessions() or nil
  local have, favs = Favor(), Favorites()
  lastFavor = have
  local statFilter = next(view.stats) ~= nil
  local entries = Entries()
  if knownDirty then
    knownDirty = false
    for _, e in ipairs(entries) do e.known = Known(e) end
  end
  wipe(list)
  for _, e in ipairs(entries) do
    local ok = true
    if view.prof == "mine" then ok = mine[e.prof] or false
    elseif view.prof then ok = e.prof == view.prof end
    if ok and view.favOnly and not favs[e.key] then ok = false end
    if ok and view.hideKnown and e.known then ok = false end
    if ok and view.afford and e.cost > have then ok = false end
    if ok and statFilter then
      -- every ticked stat, at least its minimum (true = any amount)
      local st = ns.EntryStats(e)
      for k, min in pairs(view.stats) do
        local v = st[k]
        if not v or v < (type(min) == "number" and min or 1) then ok = false break end
      end
    end
    if ok and not ns.EntryMatches(e, view.search) then ok = false end
    if ok then
      list[#list + 1] = e
      if view.statSort then
        e.sortValue = ns.EntryStats(e)[view.statSort]
      else
        e.sortValue = SortValue(e, view.sort, favs)
      end
    end
  end
  table.sort(list, Compare)
  frame.count:SetText(string.format("%d shown  |  You have %d%s", #list, have, ns.FavorIcon()))
  frame.filterBtn.text:SetText(view.prof == "mine" and "My professions" or view.prof or "All professions")
  local n = StatsOn()
  frame.statsBtn.text:SetText(n > 0 and ("Stats (" .. n .. ")") or "Stats")
  UpdateHeaders()
  Draw()
end

local function Check(label, key, anchor, x)
  local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  cb:SetPoint("LEFT", anchor, "RIGHT", x, 0)
  local fs = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", cb, "RIGHT", 1, 0)
  fs:SetText(label)
  cb:SetChecked(view[key])
  cb:SetScript("OnClick", function(self)
    view[key] = self:GetChecked() and true or false
    view.offset = 0
    ns.RefreshRecipes()
  end)
  return fs
end

local function DropButton(w, anchor, x)
  local b = CreateFrame("Button", nil, frame, "BackdropTemplate")
  b:SetSize(w, 20)
  b:SetPoint("LEFT", anchor, "RIGHT", x, 0)
  b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  b:SetBackdropColor(0.12, 0.12, 0.15, 1)
  b:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
  b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  b.text:SetPoint("LEFT", 6, 0)
  b.text:SetPoint("RIGHT", -18, 0)
  b.text:SetJustifyH("LEFT")
  local arrow = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  arrow:SetPoint("RIGHT", -6, 0)
  arrow:SetText("v")
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.06)
  return b
end

local function Popup(owner)
  local m = CreateFrame("Frame", nil, owner, "BackdropTemplate")
  m:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
  m:SetFrameStrata("DIALOG")
  m:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  m:SetBackdropColor(0.08, 0.08, 0.1, 0.98)
  m:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
  m:EnableMouse(true)
  m:Hide()
  return m
end

-- Stats dropdown: a tick and an optional minimum per stat, only stats some entry has.
local function BuildStatsMenu(sb)
  local menu = Popup(sb)
  local lines = {}
  for i, s in ipairs(ns.STATS) do
    local cb = CreateFrame("CheckButton", nil, menu, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb.key = s[1]
    cb.label = menu:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.label:SetText(s[2])
    cb:SetScript("OnClick", function(self)
      view.stats[self.key] = self:GetChecked() and (tonumber(self.min:GetText()) or true) or nil
      if not self:GetChecked() then self.min:SetText("") end
      view.offset = 0
      ns.RefreshRecipes()
    end)
    local m = CreateFrame("EditBox", nil, cb, "InputBoxTemplate")
    m:SetSize(32, 18)
    m:SetPoint("LEFT", cb, "LEFT", 158, 0)
    m:SetAutoFocus(false)
    m:SetNumeric(true)
    m:SetMaxLetters(4)
    m:SetJustifyH("CENTER")
    m.hint = m:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    m.hint:SetPoint("CENTER")
    m.hint:SetText("min")
    -- typing a minimum ticks the stat; clearing it leaves "any amount"
    m:SetScript("OnTextChanged", function(self)
      self.hint:SetShown(self:GetText() == "" and not self:HasFocus())
      if not self:HasFocus() then return end
      local n = tonumber(self:GetText())
      view.stats[cb.key] = (n and n > 0) and n or (cb:GetChecked() and true or nil)
      cb:SetChecked(view.stats[cb.key] ~= nil)
      view.offset = 0
      ns.RefreshRecipes()
    end)
    m:SetScript("OnEditFocusGained", function(self) self.hint:Hide() self:HighlightText() end)
    m:SetScript("OnEditFocusLost", function(self) self.hint:SetShown(self:GetText() == "") end)
    m:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    m:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    cb.min = m
    lines[i] = cb
  end
  local clear = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
  clear:SetSize(80, 18)
  clear:SetText("Clear")
  clear:SetScript("OnClick", function()
    wipe(view.stats)
    for _, cb in ipairs(lines) do cb:SetChecked(false) cb.min:SetText("") end
    view.offset = 0
    ns.RefreshRecipes()
  end)

  function menu:Layout()
    local present = {}
    for _, e in ipairs(Entries()) do
      for k in pairs(ns.EntryStats(e)) do present[k] = true end
    end
    local y = -6
    for _, cb in ipairs(lines) do
      if present[cb.key] or view.stats[cb.key] then
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", 6, y)
        local v = view.stats[cb.key]
        cb:SetChecked(v ~= nil)
        if not cb.min:HasFocus() then cb.min:SetText(type(v) == "number" and tostring(v) or "") end
        cb.min.hint:SetShown(cb.min:GetText() == "")
        cb:Show()
        y = y - 20
      else
        cb:Hide()
      end
    end
    clear:ClearAllPoints()
    clear:SetPoint("TOPLEFT", 10, y - 4)
    self:SetSize(200, -y + 30)
  end

  sb:SetScript("OnClick", function()
    if menu:IsShown() then menu:Hide() return end
    menu:Layout()
    menu:Show()
  end)
  sb:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Stats")
    local any = false
    for _, s in ipairs(ns.STATS) do
      local v = view.stats[s[1]]
      if v then
        any = true
        GameTooltip:AddLine(type(v) == "number" and string.format("%s %d+", s[2], v) or s[2], 1, 1, 1)
      end
    end
    if not any then
      GameTooltip:AddLine("Show only items with the stats you tick. Type a minimum to need at least that much.",
        0.8, 0.8, 0.8, true)
    end
    GameTooltip:Show()
  end)
  sb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return menu
end

-- Sort by stat: pick a stat (under CraftRoute's group headings, only stats some row has) and
-- the list orders by its value. One Highest / Lowest first switch at the top. Rows without
-- the stat go last. Clicking a column header goes back to column sorting.
local function BuildStatSortMenu(btn)
  local menu = Popup(btn)
  local W = 170

  local dir = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
  dir:SetSize(W - 12, 18)
  dir:SetPoint("TOPLEFT", 6, -6)
  local function DirText() dir:SetText(view.statLow and "Lowest first" or "Highest first") end
  dir:SetScript("OnClick", function()
    view.statLow = not view.statLow
    DirText()
    view.offset = 0
    ns.RefreshRecipes()
  end)

  local function Pick(key)
    view.statSort = key
    view.offset = 0
    menu:Hide()
    ns.RefreshRecipes()
  end
  local function MenuItem(label)
    local it = CreateFrame("Button", nil, menu)
    it:SetSize(W - 4, 16)
    it.text = it:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    it.text:SetPoint("LEFT", 14, 0)
    it.text:SetText(label)
    local hl = it:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.1)
    return it
  end

  local none = MenuItem("None (column sort)")
  none:SetScript("OnClick", function() Pick(nil) end)
  local heads, items = {}, {}
  for _, s in ipairs(ns.STATS) do
    if not heads[s[3]] then
      local h = menu:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
      h:SetText(s[3])
      heads[s[3]] = h
    end
    local it = MenuItem(s[2])
    it.key, it.group = s[1], s[3]
    it:SetScript("OnClick", function(self) Pick(self.key) end)
    items[#items + 1] = it
  end

  function menu:Layout()
    DirText()
    local present = {}
    for _, e in ipairs(Entries()) do
      for k in pairs(ns.EntryStats(e)) do present[k] = true end
    end
    local y = -28
    none:ClearAllPoints()
    none:SetPoint("TOPLEFT", 2, y)
    none.text:SetTextColor(1, view.statSort and 1 or 0.82, view.statSort and 1 or 0)
    y = y - 18
    local lastGroup
    for _, h in pairs(heads) do h:Hide() end
    for _, it in ipairs(items) do
      if present[it.key] then
        if it.group ~= lastGroup then
          lastGroup = it.group
          local h = heads[it.group]
          h:ClearAllPoints()
          h:SetPoint("TOPLEFT", 8, y - 2)
          h:Show()
          y = y - 16
        end
        it:ClearAllPoints()
        it:SetPoint("TOPLEFT", 2, y)
        local on = view.statSort == it.key
        it.text:SetTextColor(1, on and 0.82 or 1, on and 0 or 1)
        it:Show()
        y = y - 16
      else
        it:Hide()
      end
    end
    self:SetSize(W, -y + 6)
  end

  btn:SetScript("OnClick", function()
    if menu:IsShown() then menu:Hide() return end
    menu:Layout()
    menu:Show()
  end)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Sort by stat")
    GameTooltip:AddLine("Order the list by a stat, highest (or lowest) first. Its value shows at the "
      .. "start of the Effect column. Click a column header to go back.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return menu
end

local function Build()
  frame = CreateFrame("Frame", "CrateCostRecipes", UIParent, "BackdropTemplate")
  frame:SetSize(WIDTH, TOP + VISIBLE * ROW_H + 28)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)   -- clicking it brings it in front of the crate list
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
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- remember where it was put (account-wide, like the minimap button)
    if type(CrateCostDB) == "table" and self:GetLeft() then
      CrateCostDB.merchantPos = { x = self:GetLeft(), y = self:GetTop() }
    end
  end)
  frame:SetScript("OnShow", function()
    knownDirty = true
    ns.RefreshRecipes()
  end)
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta)
    view.offset = view.offset - delta * 3
    Draw()
  end)
  -- RegisterEvent throws on events the client doesn't have (LEARNED_SPELL_IN_TAB is gone
  -- from retail-based clients), which aborted Build and left a blank, unclosable frame.
  for _, ev in ipairs({ "CURRENCY_DISPLAY_UPDATE", "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_TAB" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(ev) then
      pcall(frame.RegisterEvent, frame, ev)
    end
  end
  frame:SetScript("OnEvent", function(_, event)
    if event ~= "CURRENCY_DISPLAY_UPDATE" then knownDirty = true end
    if not frame:IsShown() then return end
    -- CURRENCY_DISPLAY_UPDATE fires for every currency: only Merchant's Favor matters here
    if event == "CURRENCY_DISPLAY_UPDATE" and Favor() == lastFavor then return end
    ns.RefreshRecipes()
  end)
  tinsert(UISpecialFrames, "CrateCostRecipes")

  local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("Merchant - what Merchant's Favor buys")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  -- hide directly: the template's HideUIPanel path doesn't close unmanaged frames on Forever
  close:SetScript("OnClick", function() frame:Hide() end)
  close:SetPoint("TOPRIGHT", 2, 2)

  -- the same nav bar as the Crates and Writs windows (it also makes frame.count)
  ns.UI.NavBar(frame, "merchant", function() knownDirty = true ns.RefreshRecipes() end)

  local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  search:SetSize(170, 20)
  search:SetPoint("TOPLEFT", 18, -34)
  search:SetAutoFocus(false)
  search:SetMaxLetters(40)
  local hint = search:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("LEFT", 2, 0)
  hint:SetText("Search name, slot or stat")
  local function OnSearch(self)
    local t = self:GetText() or ""
    hint:SetShown(t == "" and not self:HasFocus())
    t = t:lower():match("^%s*(.-)%s*$")
    if t ~= view.search then
      view.search, view.offset = t, 0
      ns.RefreshRecipes()
    end
  end
  search:SetScript("OnTextChanged", OnSearch)
  search:SetScript("OnEditFocusGained", function() hint:Hide() end)
  search:SetScript("OnEditFocusLost", OnSearch)
  search:SetScript("OnEscapePressed", search.ClearFocus)
  search:SetScript("OnEnterPressed", search.ClearFocus)
  search:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Search", 1, 1, 1)
    GameTooltip:AddLine("Name, profession, type, slot or effect. Short forms work (int, agi, sp, mp5), "
      .. "and \"+6 int\" finds that amount.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  search:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- profession dropdown (own widget, like the crate list's)
  local fb = DropButton(140, search, 12)
  frame.filterBtn = fb
  local menu = Popup(fb)
  local my = -4
  local function Item(label, value)
    local it = CreateFrame("Button", nil, menu)
    it:SetSize(146, 16)
    it:SetPoint("TOPLEFT", 2, my)
    local t = it:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    t:SetPoint("LEFT", 8, 0)
    t:SetText(label)
    local hl = it:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.1)
    it:SetScript("OnClick", function()
      view.prof, view.offset = value, 0
      menu:Hide()
      ns.RefreshRecipes()
    end)
    my = my - 16
  end
  Item("All professions", nil)
  Item("My professions", "mine")
  my = my - 4
  for _, p in ipairs(PROFS) do Item(p == "Other" and "Mount, pet, tabard, title" or p, p) end
  menu:SetSize(150, -my + 4)
  fb:SetScript("OnClick", function() menu:SetShown(not menu:IsShown()) end)

  local sb = DropButton(90, fb, 8)
  frame.statsBtn = sb
  local statsMenu = BuildStatsMenu(sb)

  local ssb = DropButton(150, sb, 8)
  frame.statSortBtn = ssb
  local sortMenu = BuildStatSortMenu(ssb)
  frame:HookScript("OnHide", function() menu:Hide() statsMenu:Hide() sortMenu:Hide() end)

  local l1 = Check("Favorites only", "favOnly", ssb, 12)
  local l2 = Check("Hide learned", "hideKnown", l1, 8)
  Check("Affordable", "afford", l2, 8)

  for _, col in ipairs(COLS) do
    local h = CreateFrame("Button", nil, frame)
    h:SetSize(col.w, 16)
    h:SetPoint("TOPLEFT", frame, "TOPLEFT", col.x + 2, -64)
    h.col = col
    h.text = h:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    h.text:SetAllPoints()
    h.text:SetJustifyH(col.justify)
    if col.key == "fav" then
      local icon = h:CreateTexture(nil, "ARTWORK")
      icon:SetSize(14, 14)
      icon:SetPoint("CENTER")
      SetStar(icon)
      h:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Favorites first", 1, 1, 1)
        GameTooltip:Show()
      end)
      h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local hl = h:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    h:SetScript("OnClick", function()
      if view.statSort then
        -- a header click goes back to column sorting
        view.statSort = nil
        view.sort, view.desc = col.key, col.desc or false
      elseif view.sort == col.key then
        view.desc = not view.desc
      else
        view.sort, view.desc = col.key, col.desc or false
      end
      view.offset = 0
      ns.RefreshRecipes()
    end)
    headers[#headers + 1] = h
  end

  -- scroll bar: a plain slider so it works without the retail scroll templates
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

  local footer = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  footer:SetPoint("BOTTOMLEFT", 12, 8)
  footer:SetText("|cff808080Click the star to favorite. Hover for the item's tooltip, shift-click to link it. "
    .. "|cff40ff40Green|r|cff808080 favor = you can afford it. Data: wow-professions.com, CraftRoute.|r")
end

-- Where the window opens: where you last dragged it; otherwise, with the crate list open,
-- below and right of it so the crate list's title and rows stay visible; otherwise centred.
-- SetClampedToScreen keeps it on screen either way.
local function Place()
  frame:ClearAllPoints()
  local pos = type(CrateCostDB) == "table" and CrateCostDB.merchantPos
  if pos and pos.x and pos.y then
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    return
  end
  local crates = _G.CrateCostFrame
  if crates and crates:IsShown() and crates:GetLeft() then
    -- anchored to the screen, not the crate list, so moving one doesn't drag the other
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", crates:GetLeft() + 80, crates:GetTop() - 120)
  else
    frame:SetPoint("CENTER")
  end
end

function ns.ToggleRecipes()
  if not frame then
    local ok, err = pcall(Build)
    if not ok then
      -- never leave a half-built window stuck on screen
      if frame then frame:Hide() end
      frame = nil
      wipe(headers)
      wipe(rows)
      ns.Print("couldn't open the Merchant list: " .. tostring(err))
      return
    end
    frame:Hide()
  end
  if frame:IsShown() then frame:Hide() return end
  Place()
  frame:Show()
  frame:Raise()
end
