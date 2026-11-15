local _, ns = ...

-- Home: the landing view of the one window. Rep across the top (your standing with the trade
-- camp, the target and the rep plan), then three tiles: Crates, Merchant's Favor and Writs,
-- each with a few lines on where you stand and a button into its view.
-- /crates and the minimap button open it; the nav bar's Home button comes back to it.

local TILE_W, TILE_H, HERO_H, GAP, TOP = 228, 156, 128, 12, 40
local LINE_H, LINES = 18, 5
local WIDTH = 3 * TILE_W + 4 * GAP
local GREY = "|cff808080"

-- Card art, behind the text like the profession window's: the first of these atlases the client
-- has (checked, so a missing one is skipped), else the stone background other frames use.
local ART = {
  rep = { "Professions-Specializations-Background-Blacksmithing", "Professions-Specializations-Background-Engineering" },
  crates = { "Professions-Specializations-Background-Tailoring", "Professions-Specializations-Background-Leatherworking" },
  favor = { "Professions-Specializations-Background-Enchanting", "Professions-Specializations-Background-Jewelcrafting" },
  writs = { "Professions-Specializations-Background-Inscription", "Professions-Specializations-Background-Alchemy" },
}
local ROCK = "Interface\\FrameGeneral\\UI-Background-Rock"
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"

local frame, hero, tiles

local function Num(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end

local function Age(s)
  if not s then return GREY .. "not scanned|r" end
  local txt = s < 3600 and (math.floor(s / 60) .. "m ago") or (math.floor(s / 3600) .. "h ago")
  if ns.Depth and s >= ns.Depth.TTL then txt = txt .. GREY .. " (old)|r" end
  return txt
end

local function Art(c, key)
  local tex = c:CreateTexture(nil, "BACKGROUND", nil, 1)
  tex:SetPoint("TOPLEFT", 1, -1)
  tex:SetPoint("BOTTOMRIGHT", -1, 1)
  local done = false
  if C_Texture and C_Texture.GetAtlasInfo then
    for _, atlas in ipairs(ART[key] or {}) do
      if C_Texture.GetAtlasInfo(atlas) then
        tex:SetAtlas(atlas)
        tex:SetAlpha(0.7)
        done = true
        break
      end
    end
  end
  if not done then
    tex:SetTexture(ROCK, "REPEAT", "REPEAT")
    pcall(tex.SetHorizTile, tex, true)
    pcall(tex.SetVertTile, tex, true)
    tex:SetAlpha(0.9)
  end
  -- a light shade under the text on the left, clear on the right so the art shows
  local shade = c:CreateTexture(nil, "BACKGROUND", nil, 2)
  shade:SetPoint("TOPLEFT", 1, -1)
  shade:SetPoint("BOTTOMRIGHT", -1, 1)
  shade:SetColorTexture(0, 0, 0, 1)
  local ok = CreateColor and pcall(shade.SetGradient, shade, "HORIZONTAL", CreateColor(0, 0, 0, 0.3),
    CreateColor(0, 0, 0, 0))
  if not ok then shade:SetAlpha(0.15) end
end

local function Panel(w, h, key)
  local c = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  c:SetSize(w, h)
  c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  c:SetBackdropColor(0.06, 0.06, 0.08, 0.5)
  c:SetBackdropBorderColor(0.35, 0.3, 0.22, 1)
  Art(c, key)
  c.title = c:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  c.title:SetPoint("TOPLEFT", 12, -10)
  return c
end

-- A line: label on the left, value on the right; a line with no value runs the full width.
local function Line(c, x, y, w)
  local l = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  l:SetPoint("TOPLEFT", x, y)
  l:SetWidth(w)
  l:SetJustifyH("LEFT")
  l:SetWordWrap(false)
  local r = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  r:SetPoint("TOPRIGHT", c, "TOPLEFT", x + w, y)
  r:SetJustifyH("RIGHT")
  r:SetWordWrap(false)
  return l, r
end

local function Button(c, text, tip, onClick, w, h)
  local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
  b:SetSize(w, h)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  ns.UI.Tip(b, text, tip)
  return b
end

local function Tile(i, key, title, button, tip, onClick)
  local c = Panel(TILE_W, TILE_H, key)
  c:SetPoint("TOPLEFT", frame, "TOPLEFT", GAP + (i - 1) * (TILE_W + GAP), -TOP - HERO_H - GAP)
  c.title:SetText(title)
  c.left, c.right = {}, {}
  for k = 1, LINES do
    c.left[k], c.right[k] = Line(c, 12, -36 - (k - 1) * LINE_H, TILE_W - 24)
  end
  local b = Button(c, button, tip, onClick, TILE_W - 24, 22)
  b:SetPoint("BOTTOM", 0, 10)
  c.button = b
  return c
end

-- lines: { {left, right}, ... }; the rest are cleared
local function Fill(c, lines)
  for k = 1, #c.left do
    local ln = lines[k]
    c.left[k]:SetText(ln and ln[1] or "")
    c.right[k]:SetText(ln and ln[2] or "")
  end
end

local function Hero()
  local c = Panel(WIDTH - 2 * GAP, HERO_H, "rep")
  c:SetPoint("TOPLEFT", frame, "TOPLEFT", GAP, -TOP)
  c.title:SetText("Reputation")
  local b = Button(c, "Open the rep plan", "The cheapest way to your rep target, step by step.",
    function() ns.ShowWritPlan() end, 190, 24)
  b:SetPoint("TOPRIGHT", -10, -8)
  c.button = b
  -- standing bar
  local bar = CreateFrame("StatusBar", nil, c)
  bar:SetPoint("TOPLEFT", 12, -38)
  bar:SetPoint("TOPRIGHT", -12, -38)
  bar:SetHeight(16)
  bar:SetStatusBarTexture(BAR)
  bar:SetMinMaxValues(0, 1)
  local bbg = bar:CreateTexture(nil, "BACKGROUND")
  bbg:SetAllPoints()
  bbg:SetColorTexture(0, 0, 0, 0.5)
  bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.text:SetPoint("CENTER")
  c.bar = bar
  -- two columns of lines under it
  local half = (WIDTH - 2 * GAP - 36) / 2
  c.left, c.right = {}, {}
  for k = 1, 3 do
    c.left[k], c.right[k] = Line(c, 12, -64 - (k - 1) * LINE_H, half)
    c.left[k + 3], c.right[k + 3] = Line(c, 24 + half, -64 - (k - 1) * LINE_H, half)
  end
  return c
end

-- "|cffRRGGBB" -> r, g, b
local function RGB(code)
  local hex = code and code:match("|cff(%x%x%x%x%x%x)")
  if not hex then return 0.3, 0.6, 1 end
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

function ns.RefreshHome()
  if not (frame and frame:IsShown()) then return end
  local icon = ns.FavorIcon and ns.FavorIcon() or ""

  local ws = ns.WritStatus and ns.WritStatus()
  if ws then
    local s = ws.standing
    hero.title:SetText((s and s.name) or "Reputation")
    if s then
      local span = s.max and (s.max - s.min) or 1
      hero.bar:SetValue(s.max and math.min(1, (s.value - s.min) / span) or 1)
      hero.bar:SetStatusBarColor(RGB(s.color))
      hero.bar.text:SetText(s.label .. (s.max and ("  " .. Num(s.value - s.min) .. " / " .. Num(span)) or ""))
    end
    local p = ws.plan
    local lines = {
      { "Target", ws.targetName and (ws.need and (Num(ws.need) .. " rep to " .. ws.targetName)
        or ("|cff40ff40" .. ws.targetName .. " reached|r")) or (GREY .. "none: pick one in the rep plan|r") },
      { "Shipping Label quest", ws.labelDone and "|cff40ff40done|r" or "|cffffd100not done: +2,000 rep|r" },
      (p and (p.spent or 0) > 0) and { "Best writs used today", "|cffff4040" .. p.spent .. "|r" } or {},
    }
    if p then
      local c = p.containers
      local guess = c and (c.crateGuess or c.favorGuess)
      lines[4] = { "Plan", ws.planCount .. " writs" .. (c and (" + " .. c.n .. " containers") or "") }
      lines[5] = { "Plan cost (net)", (guess and "|cffff9933~|r" or "") .. ns.Money(p.cost)
        .. (p.short and " |cffff4040(short)|r" or "") }
    end
    Fill(hero, lines)
  end

  local cs = ns.CrateStatus and ns.CrateStatus()
  if cs then
    Fill(tiles[1], {
      { "Crates you have", cs.owned > 0 and Num(cs.owned) or (GREY .. "none|r") },
      { "Sealed to hand in", cs.sealed > 0 and (cs.sealed .. " (" .. Num(cs.sealedFavor) .. icon .. ")") or (GREY .. "none|r") },
      { "Cheapest favor", cs.bestPer and ns.Money(math.floor(cs.bestPer + 0.5)) or (GREY .. "no prices|r") },
      { GREY .. (cs.best or "") .. "|r" },
      { "AH scan", Age(cs.scanAge) },
    })
  end

  local fs = ns.FavorStatus and ns.FavorStatus()
  if fs then
    local lines = {
      { "You have", Num(fs.have) .. icon },
      { "Target", fs.target and (function()
          local left = fs.target - fs.have - fs.sealedFavor
          return left > 0 and (Num(left) .. " to go") or "|cff40ff40reached|r"
        end)() or (GREY .. "none set|r") },
    }
    local p = fs.plan
    if p and #p.picks > 0 then
      local n = 0
      for _, k in ipairs(p.picks) do n = n + k.n end
      lines[3] = { "Plan", n .. " crates" }
      lines[4] = { "Plan cost (net)", (p.guess and "|cffff9933~|r" or "") .. ns.Money(p.cost)
        .. (p.short and " |cffff4040(short)|r" or "") }
      lines[5] = { GREY .. "Best: " .. p.picks[1].c.name .. "|r" }
    end
    Fill(tiles[2], lines)
  end

  if ws then
    Fill(tiles[3], {
      { "Done today", ws.done .. " of " .. ws.total },
      { "Writs you have", ws.held > 0 and Num(ws.held) or (GREY .. "none|r") },
      { "Cheapest rep", ws.best and ns.Money(math.floor(ws.best.per + 0.5)) or (GREY .. "no prices|r") },
      { GREY .. (ws.best and ws.best.name or "") .. "|r" },
    })
  end
end

local function Build()
  local UI = ns.UI
  frame = UI.Window("CrateCostHome", "CrateCost", WIDTH, TOP + HERO_H + GAP + TILE_H + 40, UI.POS_KEY)
  frame:Hide()
  -- stone behind everything, so the window isn't flat
  local bg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
  bg:SetPoint("TOPLEFT", 1, -1)
  bg:SetPoint("BOTTOMRIGHT", -1, 1)
  bg:SetTexture(ROCK, "REPEAT", "REPEAT")
  pcall(bg.SetHorizTile, bg, true)
  pcall(bg.SetVertTile, bg, true)
  bg:SetAlpha(0.5)
  UI.NavBar(frame, "home", function()
    if ns.InvalidateCrates then ns.InvalidateCrates() end
    if ns.InvalidateWrits then ns.InvalidateWrits() end
    ns.RefreshHome()
  end)
  hero = Hero()
  tiles = {
    Tile(1, "crates", "Crates", "Open crates", "Every Waylaid Crate by cost per favor.", function() ns.ToggleWindow() end),
    Tile(2, "favor", "Merchant's Favor", "Open the favor plan", "The cheapest crates to your Merchant's Favor target.",
      function() ns.ShowFavorPlan() end),
    Tile(3, "writs", "Writs", "Open writs", "Every Craftsman's Writ by cost per rep.", function() ns.ToggleWrits() end),
  }
  local ah = UI.PlanAtAHCheck(frame, frame)
  ah:ClearAllPoints()
  ah:SetPoint("BOTTOMRIGHT", -180, 10)
  local foot = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  foot:SetPoint("BOTTOMLEFT", 16, 14)
  foot:SetText("Merchant and Cart are in the bar at the top.")
  frame:SetScript("OnShow", function() ns.RefreshHome() end)
  -- keep the numbers current while it's open
  for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "CURRENCY_DISPLAY_UPDATE", "QUEST_TURNED_IN", "UPDATE_FACTION" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(ev) then
      pcall(frame.RegisterEvent, frame, ev)
    end
  end
  local pending = false
  frame:SetScript("OnEvent", function()
    if pending or not frame:IsShown() then return end
    pending = true
    C_Timer.After(0.5, function() pending = false ns.RefreshHome() end)
  end)
end

function ns.ToggleHome()
  if not frame then
    local ok, err = pcall(Build)
    if not ok then
      frame = nil
      ns.Print("couldn't open the home view: " .. tostring(err))
      return
    end
  end
  ns.UI.ToggleView(frame)
end
