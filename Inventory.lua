-- Crates and writs you own across characters, for the Owned views. Each character's counts
-- (bags + bank) are saved account-wide when it logs in and whenever its bags change, so an alt
-- shows up once it has logged in with this version. The warband bank, if this client has one,
-- is read live.
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

-- How many of `id` you own, and where: { {name, n}, ... }, this character ("here") first, then
-- the warband bank, then alts as of their last login.
function ns.OwnedWhere(id)
  local where = {}
  if not id then return 0, where end
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

-- "2 here, 1 on Moonlight, 1 in the warband bank"
function ns.WhereText(where)
  local parts = {}
  for _, w in ipairs(where) do
    if w.name == "here" then parts[#parts + 1] = w.n .. " here"
    elseif w.alt then parts[#parts + 1] = w.n .. " on " .. w.name
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
