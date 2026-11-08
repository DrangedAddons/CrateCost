local _, ns = ...

-- Merchant's Favor recipe list: every recipe (and the mount, pet, tabard, title and
-- certifications) the Durotar Supply / Azeroth Commerce vendors sell for Merchant's Favor.
-- Search matches name, profession, type and effect/slot. Click a header to sort.

local ROW_H, VISIBLE, WIDTH, TOP = 18, 24, 975, 84
local COLS = {
  { key = "name",  title = "Recipe",     x = 10,  w = 205, justify = "LEFT"  },
  { key = "prof",  title = "Profession", x = 220, w = 95,  justify = "LEFT"  },
  { key = "type",  title = "Type",       x = 320, w = 75,  justify = "LEFT"  },
  { key = "skill", title = "Skill",      x = 400, w = 36,  justify = "RIGHT", desc = false },
  { key = "level", title = "Level",      x = 440, w = 36,  justify = "RIGHT", desc = false },
  { key = "info",  title = "Effect / slot", x = 486, w = 285, justify = "LEFT" },
  { key = "rep",   title = "Reputation", x = 776, w = 64,  justify = "LEFT",  desc = false },
  { key = "cost",  title = "Favor",      x = 842, w = 62,  justify = "RIGHT", desc = false },
  { key = "known", title = "Learned",    x = 908, w = 44,  justify = "CENTER", desc = true },
}
local REP_NAME = { [0] = "", "Friendly", "Honored", "Revered", "Exalted" }
local REP_COLOR = { [0] = "|cffffffff", "|cff40c040", "|cff40bf80", "|cff00c0c0", "|cff00ffff" }
local PROFS = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering",
  "Leatherworking", "Tailoring", "Other" }
local FAVOR_CURRENCY = 3402

local frame, rows, headers, all = nil, {}, {}, nil
-- prof: nil = all, "mine" = this character's professions, else a profession name
local view = { sort = "prof", desc = false, search = "", prof = nil, hideKnown = false,
  afford = false, offset = 0 }

local function Entries()
  if all then return all end
  all = {}
  for _, r in ipairs(ns.Recipes) do
    all[#all + 1] = { name = r[1], prof = r[2], type = r[3], skill = r[4], cost = r[5],
      rep = r[6], level = r[7], info = r[8], spell = r[9] }
  end
  for _, r in ipairs(ns.FavorItems) do
    local kind = r[5]:match("^(%a+)") or "Item"
    if kind == "Needs" then kind = "Title" end
    all[#all + 1] = { name = r[1], prof = "Other", type = kind, skill = 0, cost = r[2],
      rep = r[3], level = r[4], info = r[5], item = r[6] }
  end
  for _, e in ipairs(all) do
    -- the certifications are a profession's own reward
    local p = e.name:match("^(%a+) Certification$")
    if p then e.prof, e.type, e.skill = p, "Title", 300 end
    e.search = (e.name .. "\n" .. e.prof .. "\n" .. e.type .. "\n" .. e.info):lower()
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

local function SortValue(e, key)
  if key == "known" then return e.known and 1 or 0 end
  if key == "rep" or key == "skill" or key == "level" or key == "cost" then return e[key] or 0 end
  return (e[key] or ""):lower()
end

local function Compare(a, b)
  local k = view.sort
  local va, vb = SortValue(a, k), SortValue(b, k)
  if va ~= vb then
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
  local shown = false
  if e.spell then
    shown = pcall(GameTooltip.SetSpellByID, GameTooltip, e.spell) and GameTooltip:NumLines() > 0
  elseif e.item then
    shown = pcall(GameTooltip.SetItemByID, GameTooltip, e.item) and GameTooltip:NumLines() > 0
  end
  if not shown then
    GameTooltip:ClearLines()
    GameTooltip:AddLine(e.name)
    if e.info ~= "" then GameTooltip:AddLine(e.info, 1, 1, 1, true) end
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
    local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", row, "LEFT", col.x - 8 + 2, 0)
    fs:SetWidth(col.w)
    fs:SetJustifyH(col.justify)
    fs:SetWordWrap(false)
    row.cells[col.key] = fs
  end
  row:SetScript("OnEnter", ShowRowTooltip)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:SetScript("OnClick", function(self)
    -- shift-click links the recipe in chat
    local e = self.entry
    if not (e and IsModifiedClick("CHATLINK")) then return end
    local link
    if e.spell then
      local ok, l = pcall(function()
        return (C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(e.spell))
          or (GetSpellLink and GetSpellLink(e.spell))
      end)
      link = ok and l
    elseif e.item then
      link = select(2, C_Item.GetItemInfo(e.item))
    end
    if link then ChatEdit_InsertLink(link) end
  end)
  rows[i] = row
  return row
end

local list = {}

local function UpdateHeaders()
  for _, h in ipairs(headers) do
    local t = h.col.title
    if view.sort == h.col.key then t = t .. (view.desc and " v" or " ^") end
    h.text:SetText(t)
  end
end

local function Draw()
  local maxOff = math.max(0, #list - VISIBLE)
  if view.offset > maxOff then view.offset = maxOff end
  if view.offset < 0 then view.offset = 0 end
  local have = Favor()
  for i = 1, VISIBLE do
    local row = rows[i] or MakeRow(i)
    local e = list[view.offset + i]
    row.entry = e
    if e then
      local c = row.cells
      local grey = e.known and "|cff808080" or ""
      c.name:SetText(grey ~= "" and (grey .. e.name .. "|r") or e.name)
      c.prof:SetText(e.prof)
      c.type:SetText(e.type)
      c.skill:SetText(e.skill > 0 and e.skill or "")
      c.level:SetText(e.level > 0 and e.level or "")
      c.info:SetText("|cffc0c0c0" .. e.info .. "|r")
      c.rep:SetText(REP_COLOR[e.rep] .. REP_NAME[e.rep] .. "|r")
      c.cost:SetText((have >= e.cost and "|cff40ff40" or "|cffffffff") .. e.cost .. "|r" .. ns.FavorIcon())
      c.known:SetText(e.known and "|cff40ff40yes|r" or "")
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

function ns.RefreshRecipes()
  if not (frame and frame:IsShown()) then return end
  local mine = view.prof == "mine" and MyProfessions() or nil
  local have = Favor()
  wipe(list)
  for _, e in ipairs(Entries()) do
    e.known = Known(e)
    local ok = true
    if view.prof == "mine" then ok = mine[e.prof] or false
    elseif view.prof then ok = e.prof == view.prof end
    if ok and view.hideKnown and e.known then ok = false end
    if ok and view.afford and e.cost > have then ok = false end
    if ok and view.search ~= "" and not e.search:find(view.search, 1, true) then ok = false end
    if ok then list[#list + 1] = e end
  end
  table.sort(list, Compare)
  frame.count:SetText(string.format("%d shown  |  You have %d%s", #list, have, ns.FavorIcon()))
  frame.filterBtn.text:SetText(view.prof == "mine" and "My professions" or view.prof or "All professions")
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

local function Build()
  frame = CreateFrame("Frame", "CrateCostRecipes", UIParent, "BackdropTemplate")
  frame:SetSize(WIDTH, TOP + VISIBLE * ROW_H + 28)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
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
  frame:SetScript("OnShow", ns.RefreshRecipes)
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
  frame:SetScript("OnEvent", function() ns.RefreshRecipes() end)
  tinsert(UISpecialFrames, "CrateCostRecipes")

  local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("Merchant - what Merchant's Favor buys")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  -- hide directly: the template's HideUIPanel path doesn't close unmanaged frames on Forever
  close:SetScript("OnClick", function() frame:Hide() end)
  close:SetPoint("TOPRIGHT", 2, 2)

  local crates = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  crates:SetSize(80, 20)
  crates:SetPoint("TOPRIGHT", -30, -6)
  crates:SetText("Crates")
  crates:SetScript("OnClick", function() ns.ToggleWindow() end)

  frame.count = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  frame.count:SetPoint("RIGHT", crates, "LEFT", -12, 0)

  local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  search:SetSize(180, 20)
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

  -- profession dropdown (own widget, like the crate list's)
  local fb = CreateFrame("Button", nil, frame, "BackdropTemplate")
  fb:SetSize(150, 20)
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
  frame:HookScript("OnHide", function() menu:Hide() end)

  local l1 = Check("Hide learned", "hideKnown", fb, 14)
  Check("Only what I can afford", "afford", l1, 10)

  for _, col in ipairs(COLS) do
    local h = CreateFrame("Button", nil, frame)
    h:SetSize(col.w, 16)
    h:SetPoint("TOPLEFT", frame, "TOPLEFT", col.x + 2, -64)
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
  frame.empty:SetText("No recipes match.")

  local footer = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  footer:SetPoint("BOTTOMLEFT", 12, 8)
  footer:SetText("|cff808080Hover for the recipe's tooltip. Shift-click to link it. "
    .. "|cff40ff40Green|r|cff808080 favor = you can afford it. Data: wow-professions.com.|r")
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
      ns.Print("couldn't open the recipe list: " .. tostring(err))
      return
    end
    frame:Hide()
  end
  frame:SetShown(not frame:IsShown())
end
