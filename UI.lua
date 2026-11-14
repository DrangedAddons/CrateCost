-- Shared window pieces for the Crates, Writs and Merchant windows, so all three have the
-- same shell, title row, nav bar, filter row widgets and footer.
local _, ns = ...

local UI = {}
ns.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8X8"
UI.GREY = "|cff808080"
UI.WIDTH = 1194         -- Crates and Writs: same width, so they line up side by side
UI.HEADER_Y = -64       -- column headers
UI.FILTER_Y = -34       -- search / dropdowns / toggles

local function Backdrop(f, bg, border)
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
  f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

-- Tooltip on hover: a white first line, then grey wrapped text.
function UI.Tip(w, title, text)
  w:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(title, 1, 1, 1)
    if text then GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
  end)
  w:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- The window: dark panel, movable, Esc closes, close button, title at the top left. `posKey`
-- remembers where it was dragged to (CrateCostDB[posKey], account-wide).
function UI.Window(name, titleText, width, height, posKey)
  local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  f:SetSize(width, height)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)   -- clicking one brings it in front of the others
  Backdrop(f, { 0.05, 0.05, 0.07, 0.95 }, { 0.3, 0.3, 0.35, 1 })
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if posKey and type(CrateCostDB) == "table" and self:GetLeft() then
      CrateCostDB[posKey] = { x = self:GetLeft(), y = self:GetTop() }
    end
  end)
  tinsert(UISpecialFrames, name)

  f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 12, -10)
  f.title:SetText(titleText)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  -- hide directly: the template's HideUIPanel path doesn't close unmanaged frames on Forever
  close:SetScript("OnClick", function() f:Hide() end)
  close:SetPoint("TOPRIGHT", 2, 2)
  return f
end

-- Puts `f` where it was last dragged to (CrateCostDB[posKey]), else centred.
function UI.Place(f, posKey)
  f:ClearAllPoints()
  local pos = posKey and type(CrateCostDB) == "table" and CrateCostDB[posKey]
  if pos and pos.x and pos.y then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
  else
    f:SetPoint("CENTER")
  end
end

-- The nav bar at the top right, the same on every window: Crates, Writs, Merchant, Cart (n),
-- Refresh. The window's own button is greyed out. Returns the leftmost button (for the count).
local cartButtons = {}
function UI.NavBar(f, current, onRefresh)
  local items = {
    { "crates", "Crates", 66, function() ns.ToggleWindow() end, "Waylaid Crates by cost per favor" },
    { "writs", "Writs", 60, function() ns.ToggleWrits() end, "Craftsman's Writs by cost per reputation" },
    { "merchant", "Merchant", 76, function() ns.ToggleRecipes() end, "Every recipe sold for Merchant's Favor" },
    { "cart", "Cart", 72, function() ns.ShowCart() end, "The shopping list from the crate list's [+] buttons" },
    { "refresh", "Refresh", 66, onRefresh, "Read prices again" },
  }
  local prev
  for i = #items, 1, -1 do
    local it = items[i]
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(it[3], 20)
    if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("TOPRIGHT", -30, -6) end
    b:SetText(it[2])
    b:SetScript("OnClick", it[4])
    UI.Tip(b, it[2], it[5])
    if it[1] == current then b:Disable() end
    if it[1] == "cart" then cartButtons[#cartButtons + 1] = b end
    prev = b
  end
  UI.UpdateCartButtons()
  f.count = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.count:SetPoint("RIGHT", prev, "LEFT", -12, 0)
  return prev
end

function UI.UpdateCartButtons()
  local n = ns.CartCount and ns.CartCount() or 0
  for _, b in ipairs(cartButtons) do b:SetText("Cart (" .. n .. ")") end
end

-- Search box at the start of the filter row, with a grey hint while empty. `onChange` gets the
-- trimmed, lower-case text whenever it changes.
function UI.Search(f, hint, width, onChange)
  local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  search:SetSize(width or 170, 20)
  search:SetPoint("TOPLEFT", 18, UI.FILTER_Y)
  search:SetAutoFocus(false)
  search:SetMaxLetters(40)
  local h = search:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  h:SetPoint("LEFT", 2, 0)
  h:SetText(hint)
  local last = ""
  local function OnSearch(self)
    local t = self:GetText() or ""
    h:SetShown(t == "" and not self:HasFocus())
    t = t:lower():match("^%s*(.-)%s*$")
    if t ~= last then
      last = t
      onChange(t)
    end
  end
  search:SetScript("OnTextChanged", OnSearch)
  search:SetScript("OnEditFocusGained", function() h:Hide() end)
  search:SetScript("OnEditFocusLost", OnSearch)
  search:SetScript("OnEscapePressed", search.ClearFocus)
  search:SetScript("OnEnterPressed", search.ClearFocus)
  return search
end

-- A dropdown button (our own: UIDropDownMenu isn't reliable on Forever).
function UI.DropButton(f, w, anchor, x)
  local b = CreateFrame("Button", nil, f, "BackdropTemplate")
  b:SetSize(w, 20)
  b:SetPoint("LEFT", anchor, "RIGHT", x, 0)
  Backdrop(b, { 0.12, 0.12, 0.15, 1 }, { 0.35, 0.35, 0.4, 1 })
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

-- Its menu: `choices` = { {label, value}, "-" (a gap), {heading = "text"}, ... }. Picking one
-- calls onPick(value). Hidden when the window hides.
function UI.Menu(f, btn, choices, w, onPick)
  local m = CreateFrame("Frame", nil, btn, "BackdropTemplate")
  m:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
  m:SetFrameStrata("DIALOG")
  Backdrop(m, { 0.08, 0.08, 0.1, 0.98 }, { 0.35, 0.35, 0.4, 1 })
  m:EnableMouse(true)
  m:Hide()
  local y = -4
  for _, c in ipairs(choices) do
    if c == "-" then
      y = y - 4
    elseif c.heading then
      local h = m:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
      h:SetPoint("TOPLEFT", 8, y)
      h:SetText(c.heading)
      y = y - 16
    else
      local it = CreateFrame("Button", nil, m)
      it:SetSize(w - 4, 16)
      it:SetPoint("TOPLEFT", 2, y)
      local t = it:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      t:SetPoint("LEFT", 8, 0)
      t:SetText(c[1])
      local hl = it:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints()
      hl:SetColorTexture(1, 1, 1, 0.1)
      it:SetScript("OnClick", function()
        m:Hide()
        onPick(c[2])
      end)
      y = y - 16
    end
  end
  m:SetSize(w, -y + 4)
  btn:SetScript("OnClick", function() m:SetShown(not m:IsShown()) end)
  f:HookScript("OnHide", function() m:Hide() end)
  return m
end

-- A checkbox with its label to the right. Returns the label (anchor for the next widget).
function UI.Check(f, label, anchor, x, tip, get, set)
  local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  cb:SetPoint("LEFT", anchor, "RIGHT", x, 0)
  local fs = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", cb, "RIGHT", 1, 0)
  fs:SetText(label)
  cb:SetChecked(get())
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  if tip then UI.Tip(cb, label, tip) end
  return fs
end

-- A two-or-more-way toggle: joined buttons, the active one gold. `options` = { {value, label,
-- tip}, ... }; get() returns the active value, set(value) changes it. Call :Refresh() after.
function UI.Toggle(f, options, width, get, set)
  local group = { buttons = {} }
  for i, o in ipairs(options) do
    local b = CreateFrame("Button", nil, f, "BackdropTemplate")
    b:SetSize(width, 20)
    if i > 1 then b:SetPoint("LEFT", group.buttons[i - 1], "RIGHT", -1, 0) end
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(o[2])
    b.value = o[1]
    b:SetScript("OnClick", function(self) set(self.value) end)
    UI.Tip(b, o[2], o[3])
    group.buttons[i] = b
  end
  group.first, group.last = group.buttons[1], group.buttons[#options]
  function group:Refresh()
    local v = get()
    for _, b in ipairs(self.buttons) do
      local on = b.value == v
      b:SetBackdropColor(on and 0.25 or 0.12, on and 0.22 or 0.12, on and 0.1 or 0.15, 1)
      b:SetBackdropBorderColor(on and 1 or 0.35, on and 0.82 or 0.35, on and 0 or 0.4, 1)
      b.text:SetTextColor(on and 1 or 0.6, on and 1 or 0.6, on and 1 or 0.6)
    end
  end
  group:Refresh()
  return group
end

-- Toggles on the right end of the filter row, right to left: the first group ends at the
-- window's right edge, each next one sits left of the previous.
function UI.PlaceToggles(f, groups)
  local prev
  for _, g in ipairs(groups) do
    for _, b in ipairs(g.buttons) do b:ClearAllPoints() end
    if prev then
      g.last:SetPoint("RIGHT", prev.first, "LEFT", -12, 0)
    else
      g.last:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, UI.FILTER_Y)
    end
    -- chain the rest leftwards from the last button
    for i = #g.buttons - 1, 1, -1 do
      g.buttons[i]:SetPoint("RIGHT", g.buttons[i + 1], "LEFT", 1, 0)
    end
    prev = g
  end
end

-- Sortable column headers. `sort` = { key = current, desc = bool }; onClick(col) re-sorts.
function UI.Headers(f, cols, xoff, onClick)
  local headers = {}
  for _, col in ipairs(cols) do
    local h = CreateFrame("Button", nil, f)
    h:SetSize(col.w, 16)
    h:SetPoint("TOPLEFT", f, "TOPLEFT", col.x + (xoff or 0), UI.HEADER_Y)
    h.col = col
    h.text = h:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    h.text:SetAllPoints()
    h.text:SetJustifyH(col.justify)
    local hl = h:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    h:SetScript("OnClick", function() onClick(col) end)
    headers[#headers + 1] = h
  end
  return headers
end

-- Header text: the sorted one white with its arrow.
function UI.HeaderText(h, title, sorted, desc)
  h.text:SetText((sorted and "|cffffffff" or "") .. title .. (sorted and ((desc and " v" or " ^") .. "|r") or ""))
end

-- The grey footer line at the bottom left.
function UI.Footer(f)
  local fs = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  fs:SetPoint("BOTTOMLEFT", 12, 8)
  fs:SetJustifyH("LEFT")
  return fs
end
