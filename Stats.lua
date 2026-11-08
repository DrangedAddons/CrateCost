local _, ns = ...

-- Stats for the Merchant list's search and stat filter, ported from CraftRoute's Search.lua.
-- Sources: the effect text in Recipes.lua (the crafted item's base stats, or a potion /
-- enchant effect) and the crafted item's Equip / Use lines, read from its tooltip once the
-- client has the item cached.

-- Short forms players type. Each maps to the start of a word in the text.
local ALIAS = {
  int = "intellect", agi = "agility", str = "strength", sta = "stamina", stam = "stamina",
  spi = "spirit", def = "defense", crit = "critical", heal = "healing", res = "resistance",
  resist = "resistance", sp = "spell", mp5 = "mana", ap = "attack",
}

-- Order here is the order in the Stats dropdown.
ns.STATS = {
  { "armor", "Armor" }, { "sta", "Stamina" }, { "str", "Strength" }, { "agi", "Agility" },
  { "int", "Intellect" }, { "spi", "Spirit" },
  { "heal", "Healing" }, { "spell", "Spell damage" }, { "fire", "Fire spell damage" },
  { "frost", "Frost spell damage" }, { "shadow", "Shadow spell damage" }, { "nature", "Nature spell damage" },
  { "arcane", "Arcane spell damage" }, { "holy", "Holy spell damage" },
  { "mp5", "Mana per 5 sec" }, { "hp5", "Health per 5 sec" },
  { "crit", "Crit %" }, { "hit", "Hit %" }, { "scrit", "Spell crit %" }, { "shit", "Spell hit %" },
  { "ap", "Attack power" }, { "rap", "Ranged attack power" },
  { "def", "Defense" }, { "dodge", "Dodge %" }, { "parry", "Parry %" }, { "block", "Block" },
  { "rfire", "Fire resistance" }, { "rfrost", "Frost resistance" }, { "rnature", "Nature resistance" },
  { "rshadow", "Shadow resistance" }, { "rarcane", "Arcane resistance" },
  { "slots", "Bag slots" },
}
local PRIMARY = { stamina = "sta", strength = "str", agility = "agi", intellect = "int", spirit = "spi",
  defense = "def" }
local SCHOOL = { fire = true, frost = true, shadow = true, nature = true, arcane = true, holy = true }

------------------------------------------------------------------------------------------------
-- item tooltip effect lines

local itemText = {}   -- itemID -> lowercased Equip / Use lines ("" when none)
local itemShow = {}   -- itemID -> the Equip / Use effects as the game words them, for display
local pending = {}    -- itemID -> true while waiting for GET_ITEM_INFO_RECEIVED
local KEEP = { "^equip:", "^use:", "^chance on hit:", "^%+%d", "resistance", "block" }

local function Keep(line)
  local l = line:lower()
  for _, p in ipairs(KEEP) do if l:find(p) then return l end end
end

local shown
local function Collect(out, text)
  local k = text and Keep(text)
  if not k then return end
  out[#out + 1] = k
  -- base stats are already in the Effect column; keep the Equip / Use effects for display
  if k:find("^equip:") or k:find("^use:") or k:find("^chance on hit:") then
    shown[#shown + 1] = (text:gsub("^Equip: ", ""))
  end
end

local scanTip
local function TooltipLines(id)
  local out = {}
  if C_TooltipInfo and C_TooltipInfo.GetItemByID then
    local data = C_TooltipInfo.GetItemByID(id)
    if not data or not data.lines then return nil end
    for i = 2, #data.lines do Collect(out, data.lines[i].leftText) end
    return out
  end
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "CrateCostScanTip", nil, "GameTooltipTemplate")
  end
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  scanTip:SetItemByID(id)
  for i = 2, scanTip:NumLines() do
    local fs = _G["CrateCostScanTipTextLeft" .. i]
    Collect(out, fs and fs:GetText())
  end
  scanTip:Hide()
  return out
end

local function Cached(id)
  if C_Item and C_Item.IsItemDataCachedByID then return C_Item.IsItemDataCachedByID(id) end
  return GetItemInfo and GetItemInfo(id) ~= nil
end

-- The item's effect lines, or nil while the client is still fetching it.
function ns.ItemEffectText(id)
  if not id then return "" end
  local t = itemText[id]
  if t then return t end
  if not Cached(id) then
    if not pending[id] then
      pending[id] = true
      if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id)
      elseif GetItemInfo then GetItemInfo(id) end
    end
    return nil
  end
  shown = {}
  local ok, lines = pcall(TooltipLines, id)
  if not ok or not lines then return nil end
  t = table.concat(lines, "\n")
  itemText[id] = t
  itemShow[id] = table.concat(shown, "; ")
  return t
end

-- The item's Equip / Use effects as the game words them ("" when none or not loaded yet).
function ns.ItemEffectDisplay(id)
  if not id then return "" end
  if not itemShow[id] then ns.ItemEffectText(id) end
  return itemShow[id] or ""
end

------------------------------------------------------------------------------------------------
-- parsing

local function Add(t, k, v)
  v = tonumber(v)
  if k and v then t[k] = (t[k] or 0) + v end
end

-- One stat part or tooltip line (lowercased), in the item's own wording. True if it found one.
local function ParseLine(t, l)
  local n, w = l:match("^%+(%d+) (%a+)$")
  if n and PRIMARY[w] then Add(t, PRIMARY[w], n) return true end
  n, w = l:match("^%+?(%d+) (%a+) resistance")
  if n then Add(t, "r" .. w, n) return true end
  n = l:match("^(%d+) armor$") if n then Add(t, "armor", n) return true end
  n = l:match("^(%d+) block$") if n then Add(t, "block", n) return true end
  n = l:match("^(%d+) slot") if n then Add(t, "slots", n) return true end
  if not l:find("^equip:") then return false end
  n = l:match("damage and healing done by magical spells and effects by up to (%d+)")
  if n then Add(t, "heal", n) Add(t, "spell", n) return true end
  n = l:match("healing done by up to (%d+)") or l:match("healing done by spells and effects by up to (%d+)")
  if n then Add(t, "heal", n) end
  n = l:match("and damage done by up to (%d+)")
  if n then Add(t, "spell", n) end
  local school
  school, n = l:match("damage done by (%a+) spells and effects by up to (%d+)")
  if school and SCHOOL[school] then Add(t, school, n) end
  Add(t, "mp5", l:match("restores (%d+) mana per 5"))
  Add(t, "hp5", l:match("restores (%d+) health per 5"))
  if l:find("critical strike with spells") then Add(t, "scrit", l:match("by (%d+)%%"))
  elseif l:find("critical strike") then Add(t, "crit", l:match("by (%d+)%%")) end
  if l:find("hit with spells") then Add(t, "shit", l:match("by (%d+)%%"))
  elseif l:find("chance to hit") then Add(t, "hit", l:match("by (%d+)%%")) end
  Add(t, "rap", l:match("%+(%d+) ranged attack power"))
  if not l:find("ranged attack power") then Add(t, "ap", l:match("%+(%d+) attack power")) end
  Add(t, "def", l:match("increased defense %+(%d+)"))
  Add(t, "dodge", l:match("chance to dodge an attack by (%d+)%%"))
  Add(t, "parry", l:match("chance to parry an attack by (%d+)%%"))
  Add(t, "block", l:match("block value of your shield by (%d+)"))
  return true
end

-- The guide's short effect wording: "+25 Agility and Intellect for 30 min", "+11 healing",
-- "+16 spell power", "6 mana every 5 sec", "+20 Nature damage".
local function ParseEffect(t, l)
  local n, a, b = l:match("%+(%d+) (%a+) and (%a+)")
  local both = n and PRIMARY[a] and PRIMARY[b]
  if both then Add(t, PRIMARY[a], n) Add(t, PRIMARY[b], n) end
  if not both then
    for m, w in l:gmatch("%+(%d+) (%a+)") do
      if PRIMARY[w] then Add(t, PRIMARY[w], m) end
    end
  end
  n = l:match("(%d+) spell damage and healing")
  if n then Add(t, "spell", n) Add(t, "heal", n)
  else
    Add(t, "spell", l:match("(%d+) spell damage"))
    Add(t, "heal", l:match("(%d+) healing"))
  end
  n = l:match("(%d+) spell power")
  if n then Add(t, "spell", n) Add(t, "heal", n) end
  local school
  n, school = l:match("%+(%d+) (%a+) spell damage")
  if not n then n, school = l:match("%+(%d+) (%a+) damage") end
  if school and SCHOOL[school] then Add(t, school, n) end
  if not l:find("ranged attack power") then Add(t, "ap", l:match("(%d+) attack power")) end
  Add(t, "crit", l:match("(%d+)%% crit"))
  Add(t, "armor", l:match("%+(%d+) armor"))
  Add(t, "def", l:match("%+(%d+) defense"))
  n = l:match("(%d+) health and %d+ mana every 5")
  if n then Add(t, "hp5", n) end
  Add(t, "mp5", l:match("(%d+) mana every 5"))
end

-- e: a Merchant list entry ({effect=..., item=...}). Cached once the item's lines are in.
function ns.EntryStats(e)
  if e.stats then return e.stats end
  local t = {}
  local text = (e.effect or ""):lower():gsub("\194\183", ",")
  for part in text:gmatch("[^,]+") do
    part = part:gsub("^%s+", ""):gsub("%s+$", "")
    if not ParseLine(t, part) then ParseEffect(t, part) end
  end
  local fx = e.craft and ns.ItemEffectText(e.craft)
  if fx then
    -- only the Equip lines: the base stats ("+8 Intellect") are already in the effect text
    for l in fx:gmatch("[^\n]+") do
      if l:find("^equip:") then ParseLine(t, l) end
    end
  end
  if fx or not e.craft then e.stats = t end   -- effects not in yet: work it out again later
  return t
end

-- Does `word` start a word in `text`? (so "int" finds Intellect but not "Glinting")
local function WordStart(text, word)
  if text == "" then return false end
  local s = 1
  while true do
    local a = text:find(word, s, true)
    if not a then return false end
    if a == 1 or not text:sub(a - 1, a - 1):match("[%w']") then return true end
    s = a + 1
  end
end

-- Words of the search. A number joins the word after it: "+6 int" is one term.
local function Terms(q)
  local words = {}
  for w in q:gmatch("[^%s,]+") do
    w = w:gsub("^%+", "")
    if w ~= "" then words[#words + 1] = w end
  end
  local out, i = {}, 1
  while i <= #words do
    local w = words[i]
    if w:match("^%d+$") and words[i + 1] then
      out[#out + 1] = { num = w, word = words[i + 1] }
      i = i + 2
    else
      out[#out + 1] = { word = w }
      i = i + 1
    end
  end
  return out
end

-- q: lowercased search. Matches when the whole text is in the name, or when every word starts
-- a word in the name, profession, type, slot, effect or the item's Equip / Use lines.
function ns.EntryMatches(e, q)
  if q == "" then return true end
  local name = e.name:lower()
  if not ALIAS[q] and name:find(q, 1, true) then return true end
  local text = e.text
  local fx = e.craft and ns.ItemEffectText(e.craft) or ""
  for _, t in ipairs(Terms(q)) do
    local s = ALIAS[t.word] or t.word
    local hit
    if t.num then
      s = t.num .. " " .. s
      hit = WordStart(text, s) or WordStart(fx, s)
    else
      hit = WordStart(text, s) or WordStart(fx, s)
    end
    if not hit then return false end
  end
  return true
end

-- Items that arrive while the list is open: refresh once things settle.
local ev = CreateFrame("Frame")
if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid("GET_ITEM_INFO_RECEIVED") then
  pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED")
end
local queued = false
ev:SetScript("OnEvent", function(_, _, id)
  if not (id and pending[id]) then return end
  pending[id] = nil
  if queued then return end
  queued = true
  C_Timer.After(0.3, function()
    queued = false
    if ns.RefreshRecipes then ns.RefreshRecipes(true) end
  end)
end)
