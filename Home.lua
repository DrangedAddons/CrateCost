local _, ns = ...

-- Home: the landing view of the one window. Four cards in a 2x2 grid, Crates and Favor plan,
-- Writs and Rep plan, each with a few lines on where you stand and a button into its view.
-- /crates and the minimap button open it; the nav bar's Home button comes back to it.

local CARD_W, CARD_H, GAP, TOP = 420, 168, 12, 40
local LINE_H = 20

-- Card art, faint behind the text like the profession window's: the first of these atlases
-- the client has (checked, so a missing one is skipped), else the stone background other
-- frames use. One profession per card.
local ART = {
  { "Professions-Specializations-Background-Tailoring", "Professions-Specializations-Background-Leatherworking" },
  { "Professions-Specializations-Background-Enchanting", "Professions-Specializations-Background-Jewelcrafting" },
  { "Professions-Specializations-Background-Inscription", "Professions-Specializations-Background-Alchemy" },
  { "Professions-Specializations-Background-Blacksmithing", "Professions-Specializations-Background-Engineering" },
}
local ROCK = "Interface\\FrameGeneral\\UI-Background-Rock"

local function Art(c, i)
  local tex = c:CreateTexture(nil, "BACKGROUND", nil, 1)
  tex:SetPoint("TOPLEFT", 1, -1)
  tex:SetPoint("BOTTOMRIGHT", -1, 1)
  local done = false
  if C_Texture and C_Texture.GetAtlasInfo then
    for _, atlas in ipairs(ART[i] or {}) do
      if C_Texture.GetAtlasInfo(atlas) then
        tex:SetAtlas(atlas)
        tex:SetAlpha(0.65)
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
  -- darker on the left, where the text is
  local shade = c:CreateTexture(nil, "BACKGROUND", nil, 2)
  shade:SetPoint("TOPLEFT", 1, -1)
  shade:SetPoint("BOTTOMRIGHT", -1, 1)
  shade:SetColorTexture(0, 0, 0, 1)
  local ok = CreateColor and pcall(shade.SetGradient, shade, "HORIZONTAL", CreateColor(0, 0, 0, 0.55),
    CreateColor(0, 0, 0, 0))
  if not ok then shade:SetAlpha(0.3) end
end
local LINES = 6
local GREY = "|cff808080"

local frame, cards

local function Num(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end

local function Age(s)
  if not s then return GREY .. "not scanned|r" end
  local txt = s < 3600 and (math.floor(s / 60) .. "m ago") or (math.floor(s / 3600) .. "h ago")
  if ns.Depth and s >= ns.Depth.TTL then txt = txt .. GREY .. " (too old)|r" end
  return txt
end

local function Card(i, title, button, tip, onClick)
  local UI = ns.UI
  local c = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  c:SetSize(CARD_W, CARD_H)
  local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
  c:SetPoint("TOPLEFT", frame, "TOPLEFT", GAP + col * (CARD_W + GAP), -TOP - row * (CARD_H + GAP))
  c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  c:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
  c:SetBackdropBorderColor(0.35, 0.3, 0.22, 1)
  Art(c, i)
  c.title = c:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  c.title:SetPoint("TOPLEFT", 12, -10)
  c.title:SetText(title)
  c.left, c.right = {}, {}
  for k = 1, LINES do
    local l = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    l:SetPoint("TOPLEFT", 14, -38 - (k - 1) * LINE_H)
    l:SetJustifyH("LEFT")
    local r = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r:SetPoint("TOPRIGHT", -14, -38 - (k - 1) * LINE_H)
    r:SetPoint("LEFT", l, "RIGHT", 8, 0)
    r:SetJustifyH("RIGHT")
    r:SetWordWrap(false)
    c.left[k], c.right[k] = l, r
  end
  local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
  -- in the title row, so the lines have the card's height
  b:SetSize(170, 22)
  b:SetPoint("TOPRIGHT", -10, -8)
  b:SetText(button)
  b:SetScript("OnClick", onClick)
  UI.Tip(b, button, tip)
  c.button = b
  return c
end

-- lines: { {left, right}, ... }; the rest are cleared
local function Fill(c, lines)
  for k = 1, LINES do
    local ln = lines[k]
    c.left[k]:SetText(ln and ln[1] or "")
    c.right[k]:SetText(ln and ln[2] or "")
  end
end

function ns.RefreshHome()
  if not (frame and frame:IsShown()) then return end
  local icon = ns.FavorIcon and ns.FavorIcon() or ""

  local cs = ns.CrateStatus and ns.CrateStatus()
  if cs then
    Fill(cards[1], {
      { "Merchant's Favor", Num(cs.favor) .. icon },
      { "Crates you have", cs.owned > 0 and Num(cs.owned) or (GREY .. "none|r") },
      { "Sealed Crates to hand in", cs.sealed > 0 and (cs.sealed .. "  (" .. Num(cs.sealedFavor) .. icon .. ")")
        or (GREY .. "none|r") },
      { "Cheapest favor", cs.best and (cs.best .. "  " .. ns.Money(math.floor(cs.bestPer + 0.5))) or (GREY .. "no prices|r") },
      { "AH scan", Age(cs.scanAge) },
    })
  end

  local fs = ns.FavorStatus and ns.FavorStatus()
  if fs then
    local lines = {
      { "Merchant's Favor", Num(fs.have) .. icon .. (fs.sealed > 0 and ("  + " .. Num(fs.sealedFavor) .. " sealed") or "") },
      { "Target", fs.target and (function()
          local left = fs.target - fs.have - fs.sealedFavor
          return left > 0 and (Num(left) .. " to go to " .. Num(fs.target)) or ("|cff40ff40" .. Num(fs.target) .. " reached|r")
        end)() or (GREY .. "none: type one in the favor plan|r") },
    }
    local p = fs.plan
    if p and #p.picks > 0 then
      local n = 0
      for _, k in ipairs(p.picks) do n = n + k.n end
      lines[#lines + 1] = { "Plan", n .. " crates, " .. #p.picks .. (#p.picks == 1 and " kind" or " kinds") }
      lines[#lines + 1] = { "Plan cost", (p.guess and "|cffff9933~|r" or "") .. ns.Money(p.cost)
        .. (p.short and " |cffff4040(short)|r" or "") }
      lines[#lines + 1] = { "Best crate", p.picks[1].c.name .. "  " .. ns.Money(math.floor(p.picks[1].cost
        / (p.picks[1].n * p.picks[1].c.favor) + 0.5)) .. " per favor" }
    end
    Fill(cards[2], lines)
  end

  local ws = ns.WritStatus and ns.WritStatus()
  if ws then
    Fill(cards[3], {
      { "Done today", ws.done .. " of " .. ws.total },
      { "Writs you have", ws.held > 0 and Num(ws.held) or (GREY .. "none|r") },
      { "Cheapest rep", ws.best and (ws.best.name .. "  " .. ns.Money(math.floor(ws.best.per + 0.5)))
        or (GREY .. "no prices|r") },
    })

    local p = ws.plan
    local lines = {
      { "Standing", ws.standingText },
      { "Target", ws.targetName and (ws.need and (Num(ws.need) .. " rep to " .. ws.targetName)
        or ("|cff40ff40" .. ws.targetName .. " reached|r")) or (GREY .. "none: pick one in the plan|r") },
      { "Shipping Label quest", ws.labelDone and "|cff40ff40done|r" or "|cffffd100not done: +2,000 rep|r" },
    }
    if p then
      local c = p.containers
      local guess = c and (c.crateGuess or c.favorGuess)
      lines[#lines + 1] = { "Plan", ws.planCount .. " writs" .. (c and (" + " .. c.n .. " containers") or "") }
      lines[#lines + 1] = { "Plan cost", (guess and "|cffff9933~|r" or "") .. ns.Money(p.cost)
        .. (p.short and " |cffff4040(short)|r" or "") }
      if (p.spent or 0) > 0 then
        lines[#lines + 1] = { "Best writs used today", "|cffff4040" .. p.spent .. "|r" }
      end
    end
    Fill(cards[4], lines)
  end
end

local function Build()
  local UI = ns.UI
  -- narrower than the list views: just the two columns of cards
  frame = UI.Window("CrateCostHome", "CrateCost", 2 * CARD_W + 3 * GAP, TOP + 2 * CARD_H + GAP + 44, UI.POS_KEY)
  frame:Hide()
  -- faint stone behind the cards, so the window isn't flat
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
  cards = {
    Card(1, "Crates", "Open crates", "Every Waylaid Crate by cost per favor.", function() ns.ToggleWindow() end),
    Card(2, "Merchant's Favor", "Open the favor plan", "The cheapest crates to your Merchant's Favor target.",
      function() ns.ShowFavorPlan() end),
    Card(3, "Writs", "Open writs", "Every Craftsman's Writ by cost per rep.", function() ns.ToggleWrits() end),
    Card(4, "Rep", "Open the rep plan", "The cheapest way to your rep target, step by step.",
      function() ns.ShowWritPlan() end),
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
