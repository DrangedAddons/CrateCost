-- Crates and writs you own across characters, for the Owned views. Where the counts come from,
-- first one that has data wins (never added together, so nothing counts twice):
--   1. Syndicator (Baganator's data): every character's bags, bank and mail.
--   2. EllesmereUI Bags' offline bank (EllesmereUIBagsInventoryDB): every character's bags and
--      bank, saved by EllesmereUI when its offline bank or tooltip counts are on.
--   3. CrateCost's own records: each character's bags + bank, saved when it logs in and when its
--      bags change, so an alt shows up once it has logged in with CrateCost.
-- This character's bags and bank are always read live. The warband bank too, if the client has one.
local _, ns = ...

local function Key()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

-- Every crate and writ item ID we know.
local function Ids()
  local ids = {}
  for _, id in pairs(ns.CrateIDs or {}) do ids[id] = true end
  if type(CrateCostDB) == "table" and type(CrateCostDB.ids) == "table" then
    for _, id in pairs(CrateCostDB.ids) do ids[id] = true end
  end
  for _, w in ipairs(ns.Writs or {}) do ids[w[1]] = true end
  return ids
end

-- Bags + bank on this character; with `warband`, plus the warband bank (clients without one
-- ignore the extra argument and return the same count).
local function Count(id, warband)
  if not (id and C_Item and C_Item.GetItemCount) then return 0 end
  local ok, n = pcall(C_Item.GetItemCount, id, true, false, false, warband or false)
  return ok and n or 0
end

function ns.ScanInventory()
  if type(CrateCostDB) ~= "table" then CrateCostDB = {} end
  CrateCostDB.inv = CrateCostDB.inv or {}
  local items = {}
  for id in pairs(Ids()) do
    local n = Count(id)
    if n > 0 then items[id] = n end
  end
  CrateCostDB.inv[Key()] = { name = UnitName("player"), items = items }
end

-- Syndicator's answer for `id`: total and where, or nil if it isn't loaded.
local function FromSyndicator(id)
  local api = Syndicator and Syndicator.API and Syndicator.API.GetInventoryInfoByItemID
  if not api then return nil end
  local ok, info = pcall(api, id, false, false)
  if not (ok and type(info) == "table") then return nil end
  local me = UnitName("player")
  local myRealm = GetNormalizedRealmName and GetNormalizedRealmName()
  local here = Count(id)   -- this character live (bags change between Syndicator saves)
  local total, where, sawMe = 0, {}, false
  for _, c in ipairs(info.characters or {}) do
    local n = (c.bags or 0) + (c.bank or 0) + (c.mail or 0)
    local isMe = c.character == me and (not myRealm or c.realmNormalized == myRealm)
    if isMe then
      sawMe = true
      -- live bags + bank, plus mail (and Syndicator's bank count, if the client's is lower)
      n = math.max(here, (c.bags or 0) + (c.bank or 0)) + (c.mail or 0)
      if n > 0 then table.insert(where, 1, { name = "here", n = n, bank = c.bank, mail = c.mail }) end
    elseif n > 0 then
      where[#where + 1] = { name = c.character, n = n, alt = true, bank = c.bank, mail = c.mail }
    end
    total = total + n
  end
  if not sawMe and here > 0 then
    total = total + here
    table.insert(where, 1, { name = "here", n = here })
  end
  local wb = info.warband and info.warband[1] or 0
  if wb > 0 then
    total = total + wb
    where[#where + 1] = { name = "warband bank", n = wb }
  end
  return total, where
end

-- EllesmereUI Bags' saved inventories, indexed once (rebuilt after INDEX_TTL seconds):
-- index[itemID] = { {name, bags, bank, me}, ... }. nil if EllesmereUI hasn't saved any.
local INDEX_TTL = 3
local euiIndex, euiTime
local function ItemIDOf(s)
  if type(s) ~= "string" then return nil end
  return tonumber(s:match("^item:(%d+)") or s:match("|Hitem:(%d+)"))
end
local function EllesmereIndex()
  local db = _G.EllesmereUIBagsInventoryDB
  if not (type(db) == "table" and type(db.chars) == "table" and next(db.chars)) then return nil end
  if euiIndex and GetTime() - euiTime < INDEX_TTL then return euiIndex end
  local want = Ids()
  local guid = UnitGUID and UnitGUID("player")
  local index = {}
  for key, c in pairs(db.chars) do
    if type(c) == "table" then
      local per = {}
      local function Add(list, field)
        if type(list) ~= "table" then return end
        for _, box in ipairs(list) do
          if type(box) == "table" and type(box.items) == "table" then
            for slot, s in pairs(box.items) do
              local id = ItemIDOf(s)
              if id and want[id] then
                local n = (type(box.counts) == "table" and box.counts[slot]) or 1
                per[id] = per[id] or { bags = 0, bank = 0 }
                per[id][field] = per[id][field] + n
              end
            end
          end
        end
      end
      Add(c.bags, "bags")
      Add(c.bank, "bank")
      local name = type(c.name) == "string" and c.name:match("^(%S+)") or tostring(key)
      local me = (guid and (c.guid == guid or key == guid)) or false
      for id, t in pairs(per) do
        index[id] = index[id] or {}
        table.insert(index[id], { name = name, bags = t.bags, bank = t.bank, me = me })
      end
    end
  end
  euiIndex, euiTime = index, GetTime()
  return index
end

local function FromEllesmere(id)
  local index = EllesmereIndex()
  if not index then return nil end
  local here = Count(id)
  local total, where, sawMe = 0, {}, false
  for _, c in ipairs(index[id] or {}) do
    if c.me then
      sawMe = true
      local n = math.max(here, c.bags + c.bank)
      if n > 0 then
        total = total + n
        table.insert(where, 1, { name = "here", n = n, bank = c.bank })
      end
    else
      local n = c.bags + c.bank
      if n > 0 then
        total = total + n
        where[#where + 1] = { name = c.name, n = n, alt = true, bank = c.bank }
      end
    end
  end
  if not sawMe and here > 0 then
    total = total + here
    table.insert(where, 1, { name = "here", n = here })
  end
  return total, where
end

-- How many of `id` you own, and where: { {name, n}, ... }, this character ("here") first, then
-- alts and the warband bank. See the top of the file for where the counts come from.
function ns.OwnedWhere(id)
  local where = {}
  if not id then return 0, where end
  local total, swhere = FromSyndicator(id)
  if total then return total, swhere end
  total, swhere = FromEllesmere(id)
  if total then return total, swhere end
  local here = Count(id)
  local total = here
  if here > 0 then where[#where + 1] = { name = "here", n = here } end
  local wb = Count(id, true) - here
  if wb > 0 then
    total = total + wb
    where[#where + 1] = { name = "warband bank", n = wb }
  end
  local inv = type(CrateCostDB) == "table" and CrateCostDB.inv
  if inv then
    local me = Key()
    for key, rec in pairs(inv) do
      local n = key ~= me and rec.items and rec.items[id]
      if n and n > 0 then
        total = total + n
        where[#where + 1] = { name = rec.name or key, n = n, alt = true }
      end
    end
  end
  return total, where
end

-- Who has it, short, for the Owned views' Who column: the first holder's name (this
-- character's in green), "+N" for the others. "" when nobody has it.
function ns.WhoText(where)
  local first = where and where[1]
  if not first then return "" end
  local name
  if first.name == "here" then name = "|cff40ff40" .. (UnitName("player") or "you") .. "|r"
  elseif first.alt then name = first.name
  else name = "Warband" end
  if #where > 1 then name = name .. " |cff808080+" .. (#where - 1) .. "|r" end
  return name
end

-- The Who column's sort key: this character first, then by name.
function ns.WhoSort(where)
  local first = where and where[1]
  if not first then return nil end
  if first.name == "here" then return " " end
  return first.name:lower()
end

-- "2 here, 1 on Moonlight (bank), 1 in the warband bank"
function ns.WhereText(where)
  local parts = {}
  for _, w in ipairs(where) do
    local spot = {}
    if (w.bank or 0) > 0 then spot[#spot + 1] = "bank" end
    if (w.mail or 0) > 0 then spot[#spot + 1] = "mail" end
    local tail = #spot > 0 and (" (" .. table.concat(spot, ", ") .. ")") or ""
    if w.name == "here" then parts[#parts + 1] = w.n .. " here" .. tail
    elseif w.alt then parts[#parts + 1] = w.n .. " on " .. w.name .. tail
    else parts[#parts + 1] = w.n .. " in the " .. w.name end
  end
  return table.concat(parts, ", ")
end

local f = CreateFrame("Frame")
local pending = false
local function Later()
  if pending then return end
  pending = true
  C_Timer.After(1, function()
    pending = false
    ns.ScanInventory()
  end)
end
for _, ev in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED" }) do
  if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(ev) then
    pcall(f.RegisterEvent, f, ev)
  end
end
f:SetScript("OnEvent", Later)
