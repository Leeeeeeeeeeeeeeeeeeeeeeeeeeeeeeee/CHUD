local ADDON, ns = ...

local refreshers = {}
local function Refresh()
  for _, f in ipairs(refreshers) do
    local ok, err = pcall(f)
    if not ok then geterrorhandler()(err) end   -- report it, but keep refreshing the rest
  end
end
ns.RefreshSettings = Refresh

local BORDER = { 0.6, 0.5, 0.3, 1 }
local RULE = { 0.55, 0.42, 0.24, 0.8 }

-- Widgets ----------------------------------------------------------------------
local function Label(parent, text, x, y, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  fs:SetPoint("TOPLEFT", x, y); fs:SetText(text); fs:SetJustifyH("LEFT")
  return fs
end

local function Header(parent, text, x, y, w)
  Label(parent, text, x, y, "GameFontNormalLarge")
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetPoint("TOPLEFT", x, y - 22); line:SetSize(w, 1); line:SetColorTexture(unpack(RULE))
end

local function Check(parent, text, x, y, get, set)
  local b = CreateFrame("CheckButton", nil, parent)
  b:SetSize(18, 18); b:SetPoint("TOPLEFT", x + 2, y - 2)
  local border = b:CreateTexture(nil, "BACKGROUND", nil, -1)
  border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1); border:SetColorTexture(unpack(BORDER))
  local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.08, 0.08, 0.08, 1)
  b:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  b:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("LEFT", b, "RIGHT", 6, 0); fs:SetText(text)
  b:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); Refresh() end)
  refreshers[#refreshers + 1] = function() b:SetChecked(get()) end
  return b
end

local function Button(parent, text, x, y, w, fn)
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetSize(w, 24); btn:SetPoint("TOPLEFT", x, y); btn:SetText(text)
  btn:SetScript("OnClick", fn)
  return btn
end

-- Slider with optional title above it. When `editable`, the value sits in a box: click the box,
-- type a number and press Enter. `scale` is 100 for percent sliders (typed 55 = 0.55).
-- `maxFn` lets the slider's upper bound follow something dynamic (e.g. the screen width).
-- The idle value is a plain FontString (reliable to render); an EditBox only appears while typing.
local function Slider(parent, text, x, y, width, minv, maxv, step, get, set, fmt, editable, scale, maxFn, default)
  scale = scale or 1
  if text then Label(parent, text, x, y, "GameFontNormal") end
  local s = CreateFrame("Slider", nil, parent)
  s:SetOrientation("HORIZONTAL"); s:SetSize(width, 14)
  s:SetPoint("TOPLEFT", x, text and (y - 20) or y)
  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(4); track:SetColorTexture(0.25, 0.25, 0.25, 1)
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  s:GetThumbTexture():SetSize(14, 22)
  s:SetMinMaxValues(minv, maxFn and maxFn() or maxv); s:SetValueStep(step); s:SetObeyStepOnDrag(true)

  local val, box, edit, setBorder
  if editable then
    box = CreateFrame("Button", nil, parent)
    box:SetSize(50, 20); box:SetPoint("LEFT", s, "RIGHT", 8, 0)
    local border = box:CreateTexture(nil, "BACKGROUND", nil, -1)
    border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1)
    local fill = box:CreateTexture(nil, "BACKGROUND"); fill:SetAllPoints(); fill:SetColorTexture(0.08, 0.08, 0.08, 1)
    setBorder = function(c) border:SetColorTexture(c[1], c[2], c[3], c[4]) end
    setBorder(BORDER)
    val = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    val:SetPoint("CENTER")

    edit = CreateFrame("EditBox", nil, box)
    edit:SetAllPoints(box); edit:SetAutoFocus(false); edit:SetFontObject("GameFontHighlightSmall")
    edit:SetJustifyH("CENTER"); edit:SetMaxLetters(8); edit:Hide()
    local ef = edit:CreateTexture(nil, "BACKGROUND"); ef:SetAllPoints(); ef:SetColorTexture(0.12, 0.12, 0.12, 1)

    box:SetScript("OnEnter", function(self)
      setBorder({ 1, 0.82, 0, 1 })
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Click To Type A Value", 1, 1, 1)
      if default ~= nil then GameTooltip:AddLine("Default: " .. fmt(default), 0.7, 0.7, 0.7) end
      GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function()
      if not edit:IsShown() then setBorder(BORDER) end
      GameTooltip:Hide()
    end)
  else
    val = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    val:SetPoint("LEFT", s, "RIGHT", 8, 0)
  end

  local function show() val:SetText(fmt(get())) end
  local refreshing = false
  s:SetScript("OnValueChanged", function(_, v)
    val:SetText(fmt(v))
    if refreshing then return end
    set(v)
  end)

  if editable then
    box:SetScript("OnClick", function()
      val:Hide()
      edit:SetText(format("%d", scale == 100 and (get() * 100 + 0.5) or get()))
      edit:Show(); edit:SetFocus(); edit:HighlightText()
      setBorder({ 1, 0.82, 0, 1 })
    end)
    edit:SetScript("OnEnterPressed", function(self)
      local n = tonumber((self:GetText() or ""):match("[%d%.]+"))
      if n then
        local lo, hi = s:GetMinMaxValues()
        n = n / scale
        n = math.max(lo, math.min(hi, floor(n / step + 0.5) * step))   -- clamp, then snap to step
        s:SetValue(n)                                                   -- fires OnValueChanged -> set()
      end
      self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEditFocusLost", function(self)
      self:Hide(); val:Show(); show(); setBorder(BORDER)
    end)
  end
  show()
  refreshers[#refreshers + 1] = function()
    refreshing = true
    if maxFn then s:SetMinMaxValues(minv, maxFn()) end
    s:SetValue(get()); show()
    refreshing = false
  end
  return s
end

local function Plain(v) return format("%d", v) end
local function Px(v) return format("%.1f px", v) end
local function Pct(v) return format("%d%%", v * 100 + 0.5) end

-- Color swatch + label + opacity slider on one row.
local function ColorRow(parent, text, key, x, y)
  local sw = CreateFrame("Button", nil, parent)
  sw:SetSize(18, 18); sw:SetPoint("TOPLEFT", x + 2, y - 2)   -- same size and inset as the checkboxes
  local border = sw:CreateTexture(nil, "BACKGROUND"); border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1)
  border:SetColorTexture(unpack(BORDER))
  local tex = sw:CreateTexture(nil, "ARTWORK"); tex:SetAllPoints()
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("LEFT", sw, "RIGHT", 8, 0); fs:SetWidth(108); fs:SetJustifyH("LEFT"); fs:SetText(text)
  sw:SetScript("OnClick", function()
    local c = ns.db[key]
    local prev = { c[1], c[2], c[3] }
    -- The marker menu sits in FULLSCREEN_DIALOG; lift the picker above it so it can be clicked.
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG"); ColorPickerFrame:SetToplevel(true); ColorPickerFrame:Raise()
    ColorPickerFrame:SetupColorPickerAndShow({
      r = c[1], g = c[2], b = c[3], hasOpacity = false,
      swatchFunc = function() c[1], c[2], c[3] = ColorPickerFrame:GetColorRGB(); Refresh(); ns.Apply() end,
      cancelFunc = function() c[1], c[2], c[3] = prev[1], prev[2], prev[3]; Refresh(); ns.Apply() end,
    })
  end)
  refreshers[#refreshers + 1] = function() local c = ns.db[key]; tex:SetColorTexture(c[1], c[2], c[3], 1) end
  Slider(parent, nil, x + 144, y - 4, 44, 0, 1, 0.05,
    function() return ns.db[key][4] end,
    function(v) ns.db[key][4] = v; ns.Apply() end, Pct, false)
  return sw
end

-- Font dropdown -----------------------------------------------------------------
-- WoW cannot enumerate font files, so the list is the stock fonts plus whatever other
-- addons registered with LibSharedMedia. Each entry previews in its own typeface.
local fontTest
local function FontList()
  local list, seen = {}, {}
  fontTest = fontTest or UIParent:CreateFontString(nil, "OVERLAY")
  local function add(name, path)
    if not name or not path or path == "" then return end
    local key = path:lower()
    if seen[key] then return end
    local ok = pcall(function() return fontTest:SetFont(path, 12, "") end)
    if not ok or fontTest:SetFont(path, 12, "") == false then return end   -- skip unusable files
    seen[key] = true
    list[#list + 1] = { name = name, path = path }
  end
  add("Default (Game Font)", STANDARD_TEXT_FONT)
  add("Friz Quadrata", "Fonts\\FRIZQT__.TTF")
  add("Arial Narrow", "Fonts\\ARIALN.TTF")
  add("Morpheus", "Fonts\\MORPHEUS.ttf")
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  if LSM then
    for _, n in ipairs(LSM:List("font")) do add(n, LSM:Fetch("font", n)) end
  end
  return list
end

local function FontDropdown(parent, x, y, width)
  Label(parent, "Font", x, y, "GameFontNormal")
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(width, 24); btn:SetPoint("TOPLEFT", x, y - 20)
  local border = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
  border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1); border:SetColorTexture(unpack(BORDER))
  local bg = btn:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.08, 0.08, 0.08, 1)
  btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  local arrow = btn:CreateTexture(nil, "ARTWORK")
  arrow:SetSize(18, 18); arrow:SetPoint("RIGHT", -3, 0)
  arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
  local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", 8, 0); text:SetPoint("RIGHT", arrow, "LEFT", -2, 0); text:SetJustifyH("LEFT")

  -- Popup list: scrollable, lives above the settings window, closes on outside click / Esc.
  local ROW = 22
  local popup = CreateFrame("Frame", "CHUDFontPopup", UIParent)
  popup:SetSize(width, 300); popup:SetFrameStrata("FULLSCREEN_DIALOG"); popup:SetClampedToScreen(true)
  popup:Hide()
  local pb = popup:CreateTexture(nil, "BACKGROUND", nil, -1)
  pb:SetPoint("TOPLEFT", -1, 1); pb:SetPoint("BOTTOMRIGHT", 1, -1); pb:SetColorTexture(unpack(BORDER))
  local pg = popup:CreateTexture(nil, "BACKGROUND"); pg:SetAllPoints(); pg:SetColorTexture(0.06, 0.06, 0.07, 0.98)
  tinsert(UISpecialFrames, "CHUDFontPopup")
  local scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -4); scroll:SetPoint("BOTTOMRIGHT", -26, 4)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(width - 32, 10); scroll:SetScrollChild(child)

  local catcher = CreateFrame("Frame", nil, UIParent)
  catcher:SetAllPoints(UIParent); catcher:SetFrameStrata("FULLSCREEN"); catcher:EnableMouse(true); catcher:Hide()
  catcher:SetScript("OnMouseDown", function() popup:Hide() end)
  popup:SetScript("OnShow", function() catcher:Show() end)
  popup:SetScript("OnHide", function() catcher:Hide() end)

  local rows = {}
  local function Populate()
    local list = FontList()
    child:SetHeight(math.max(#list * ROW, 10))
    for i, f in ipairs(list) do
      local r = rows[i]
      if not r then
        r = CreateFrame("Button", nil, child)
        r:SetSize(width - 32, ROW); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        r:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:SetColorTexture(1, 0.82, 0, 0.15)
        -- Sample of what the compass draws (a letter, digits, degree sign) in the row's own font,
        -- so a font missing a glyph is obvious before you pick it.
        r.sample = r:CreateFontString(nil, "OVERLAY")
        r.sample:SetPoint("RIGHT", -4, 0); r.sample:SetJustifyH("RIGHT"); r.sample:SetWidth(46)
        r.fs = r:CreateFontString(nil, "OVERLAY")
        r.fs:SetPoint("LEFT", 6, 0); r.fs:SetPoint("RIGHT", r.sample, "LEFT", -4, 0); r.fs:SetJustifyH("LEFT")
        r:SetScript("OnClick", function(self)
          ns.db.fontName, ns.db.fontPath = self.name, self.path
          ns.Apply(); Refresh(); popup:Hide()
        end)
        rows[i] = r
      end
      r.name, r.path = f.name, f.path
      if r.fs:SetFont(f.path, 13, "") == false then r.fs:SetFont(STANDARD_TEXT_FONT, 13, "") end
      if r.sample:SetFont(f.path, 13, "") == false then r.sample:SetFont(STANDARD_TEXT_FONT, 13, "") end
      r.fs:SetText(f.name); r.fs:SetTextColor(1, 1, 1)
      r.sample:SetText("N 90\194\176"); r.sample:SetTextColor(0.85, 0.85, 0.85)
      r.sel:SetShown(f.name == ns.db.fontName)
      r:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    popup:SetHeight(math.min(#list * ROW + 8, 300))
  end

  btn:SetScript("OnClick", function()
    if popup:IsShown() then popup:Hide() return end
    Populate()
    popup:ClearAllPoints(); popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    scroll:SetVerticalScroll(0)
    popup:Show()
  end)
  refreshers[#refreshers + 1] = function()
    local path = (ns.db.fontPath ~= "" and ns.db.fontPath) or STANDARD_TEXT_FONT
    if text:SetFont(path, 12, "") == false then text:SetFont(STANDARD_TEXT_FONT, 12, "") end
    text:SetText(ns.db.fontName)
  end
  return btn, popup
end

-- Modal dialog (used for naming a theme and confirming a delete) ------------------------
local dialog
local function GetDialog()
  if dialog then return dialog end
  local f = CreateFrame("Frame", "CHUDDialog", UIParent)
  f:SetSize(320, 140); f:SetPoint("CENTER", 0, 80)
  f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true); f:EnableMouse(true); f:Hide()
  local b = f:CreateTexture(nil, "BACKGROUND", nil, -1)
  b:SetPoint("TOPLEFT", -1, 1); b:SetPoint("BOTTOMRIGHT", 1, -1); b:SetColorTexture(unpack(BORDER))
  local g = f:CreateTexture(nil, "BACKGROUND"); g:SetAllPoints(); g:SetColorTexture(0.06, 0.06, 0.07, 0.98)
  tinsert(UISpecialFrames, "CHUDDialog")

  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.text:SetPoint("TOP", 0, -14); f.text:SetWidth(290)

  local e = CreateFrame("EditBox", nil, f)
  e:SetSize(280, 22); e:SetPoint("TOP", f.text, "BOTTOM", 0, -10)
  e:SetAutoFocus(false); e:SetFontObject("GameFontHighlight"); e:SetMaxLetters(24); e:SetTextInsets(6, 6, 0, 0)
  local eb = e:CreateTexture(nil, "BACKGROUND", nil, -1)
  eb:SetPoint("TOPLEFT", -1, 1); eb:SetPoint("BOTTOMRIGHT", 1, -1); eb:SetColorTexture(unpack(BORDER))
  local ef = e:CreateTexture(nil, "BACKGROUND"); ef:SetAllPoints(); ef:SetColorTexture(0.08, 0.08, 0.08, 1)
  f.edit = e

  f.err = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.err:SetPoint("TOP", e, "BOTTOM", 0, -6); f.err:SetWidth(290); f.err:SetTextColor(1, 0.35, 0.3)

  local function accept()
    local msg = f.onYes and f.onYes(e:GetText() or "")
    if msg then f.err:SetText(msg) else f:Hide() end
  end
  f.yes = Button(f, "OK", 0, 0, 100, accept)
  f.yes:ClearAllPoints(); f.yes:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 14)
  f.no = Button(f, "Cancel", 0, 0, 100, function() f:Hide() end)
  f.no:ClearAllPoints(); f.no:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 14)
  e:SetScript("OnEnterPressed", accept)
  e:SetScript("OnEscapePressed", function() f:Hide() end)

  -- Full-screen click blocker so the dialog is modal.
  local c = CreateFrame("Frame", nil, UIParent)
  c:SetAllPoints(UIParent); c:SetFrameStrata("FULLSCREEN"); c:EnableMouse(true); c:Hide()
  f:SetScript("OnShow", function() c:Show() end)
  f:SetScript("OnHide", function() c:Hide() end)
  dialog = f
  return f
end

-- opts: text, edit (show a text box), default, yes (button label), onYes(text) -> error string or nil
local function ShowDialog(opts)
  local f = GetDialog()
  f.text:SetText(opts.text)
  f.onYes = opts.onYes
  f.pendingOverwrite = nil
  f.err:SetText("")
  f.yes:SetText(opts.yes or "OK")
  local h = 14 + f.text:GetStringHeight() + 10 + 16 + 24 + 14
  if opts.edit then
    f.edit:Show(); f.edit:SetText(opts.default or ""); h = h + 22 + 6 + 14
  else
    f.edit:Hide()
  end
  f:SetHeight(h)
  f:Show()
  if opts.edit then f.edit:SetFocus(); f.edit:HighlightText() end
end

-- Generic scrolling dropdown. getItems() -> { {text, value, selected, header}, ... }
local function ListDropdown(parent, x, y, width, getLabel, getItems, onPick, popupName)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(width, 24); btn:SetPoint("TOPLEFT", x, y)
  local border = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
  border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1); border:SetColorTexture(unpack(BORDER))
  local bg = btn:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.08, 0.08, 0.08, 1)
  btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  local arrow = btn:CreateTexture(nil, "ARTWORK")
  arrow:SetSize(18, 18); arrow:SetPoint("RIGHT", -3, 0)
  arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
  local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", 8, 0); text:SetPoint("RIGHT", arrow, "LEFT", -2, 0); text:SetJustifyH("LEFT")

  local ROW = 22
  local popup = CreateFrame("Frame", popupName, UIParent)
  popup:SetSize(width, 200); popup:SetFrameStrata("FULLSCREEN_DIALOG"); popup:SetClampedToScreen(true); popup:Hide()
  local pb = popup:CreateTexture(nil, "BACKGROUND", nil, -1)
  pb:SetPoint("TOPLEFT", -1, 1); pb:SetPoint("BOTTOMRIGHT", 1, -1); pb:SetColorTexture(unpack(BORDER))
  local pg = popup:CreateTexture(nil, "BACKGROUND"); pg:SetAllPoints(); pg:SetColorTexture(0.06, 0.06, 0.07, 0.98)
  tinsert(UISpecialFrames, popupName)
  local scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -4); scroll:SetPoint("BOTTOMRIGHT", -26, 4)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(width - 32, 10); scroll:SetScrollChild(child)
  local catcher = CreateFrame("Frame", nil, UIParent)
  catcher:SetAllPoints(UIParent); catcher:SetFrameStrata("FULLSCREEN"); catcher:EnableMouse(true); catcher:Hide()
  catcher:SetScript("OnMouseDown", function() popup:Hide() end)
  popup:SetScript("OnShow", function() catcher:Show() end)
  popup:SetScript("OnHide", function() catcher:Hide() end)

  local rows = {}
  local function Populate()
    local items = getItems()
    child:SetHeight(math.max(#items * ROW, 10))
    for i, it in ipairs(items) do
      local r = rows[i]
      if not r then
        r = CreateFrame("Button", nil, child)
        r:SetSize(width - 32, ROW); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        r:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:SetColorTexture(1, 0.82, 0, 0.15)
        r.fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.fs:SetPoint("LEFT", 6, 0); r.fs:SetPoint("RIGHT", -4, 0); r.fs:SetJustifyH("LEFT")
        r:SetScript("OnClick", function(self)
          if self.value ~= nil then onPick(self.value); popup:Hide() end
        end)
        rows[i] = r
      end
      r.value = it.value
      r.fs:SetText(it.text)
      if it.header then
        r.fs:SetFontObject("GameFontNormalSmall"); r.fs:SetTextColor(0.7, 0.6, 0.3)
        r:EnableMouse(false); r.sel:Hide()
      else
        r.fs:SetFontObject("GameFontHighlight")
        r:EnableMouse(true); r.sel:SetShown(it.selected and true or false)
      end
      r:Show()
    end
    for i = #items + 1, #rows do rows[i]:Hide() end
    popup:SetHeight(math.min(#items * ROW + 8, 300))
  end

  btn:SetScript("OnClick", function()
    if popup:IsShown() then popup:Hide() return end
    Populate()
    popup:ClearAllPoints(); popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    scroll:SetVerticalScroll(0)
    popup:Show()
  end)
  local function update() text:SetText(getLabel()) end
  update()
  return btn, popup, update
end

-- Panel ----------------------------------------------------------------------------
-- Marker menu ----------------------------------------------------------------------------
-- Opens when the compass is right-clicked: checkboxes for what to point at, plus icon size and range.
local markerMenu
local function BuildMarkerMenu()
  local f = CreateFrame("Frame", "CHUDMarkerMenu", UIParent)
  f:SetSize(500, 596); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
  f:EnableMouse(true); f:SetClampedToScreen(true); f:Hide()
  local b = f:CreateTexture(nil, "BACKGROUND", nil, -1)
  b:SetPoint("TOPLEFT", -1, 1); b:SetPoint("BOTTOMRIGHT", 1, -1); b:SetColorTexture(unpack(BORDER))
  local g = f:CreateTexture(nil, "BACKGROUND"); g:SetAllPoints(); g:SetColorTexture(0.06, 0.06, 0.07, 0.97)
  tinsert(UISpecialFrames, "CHUDMarkerMenu")   -- Esc closes it

  -- Full-screen catcher behind the menu: a click anywhere else closes it.
  local c = CreateFrame("Button", nil, UIParent)
  c:SetAllPoints(UIParent); c:SetFrameStrata("FULLSCREEN"); c:Hide()
  c:SetScript("OnClick", function() f:Hide() end)
  f:SetScript("OnShow", function() c:Show(); Refresh() end)
  f:SetScript("OnHide", function() c:Hide() end)

  -- Hover explanation for an option: what data it uses and when it shows up.
  local function Tip(w, title, text)
    w:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(f, "ANCHOR_NONE")
      GameTooltip:SetPoint("TOPLEFT", f, "TOPRIGHT", 6, 0)
      GameTooltip:AddLine(title, 1, 0.82, 0)
      GameTooltip:AddLine(text, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    w:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  local function opt(key) return function() return ns.db[key] end, function(v) ns.db[key] = v; ns.MarkersChanged() end end
  local function C(text, key, y, tip)
    local g2, s2 = opt(key)
    local b = Check(f, text, 14, y, g2, s2)
    b:SetHitRectInsets(0, -190, 0, 0)   -- hovering the label counts too
    Tip(b, text, tip)
  end
  local function Section(text, y) Header(f, text, 14, y, 224) end

  Label(f, "C.H.U.D. MARKERS", 14, -12, "GameFontNormalLarge")
  local rule = f:CreateTexture(nil, "ARTWORK")
  rule:SetPoint("TOPLEFT", 14, -36); rule:SetSize(472, 1); rule:SetColorTexture(unpack(RULE))

  Section("Quests", -50)
  C("Tracked Quest / Waypoint", "mk_tracked", -86,
    "Points to the quest you are tracking (click a quest in the tracker or quest log to track it) or the map waypoint you are tracking. It shows whenever the game provides a position for it, and sticks to the edge of the bar when it is off to the side, so you know which way to turn. Not available in dungeons.")
  C("Quest Objectives & Turn-Ins", "mk_objectives", -109,
    "Quests in your log that have a marker on this zone's map: objective areas, and turn-in spots for quests you have completed. The positions come from the same data as the world map's quest markers, so a quest with no map marker will not show. Updates when your quest log changes. Limited by Max Distance.")
  C("Quest Givers", "mk_givers", -132,
    "Quests you could pick up in this zone (the same ones the world map marks). Only quest givers the map shows will appear. Limited by Max Distance.")
  Section("World", -164)
  C("Rare Elites", "mk_rares", -200,
    "Rare elites the game is currently reporting, the same ones that appear as map and minimap markers when you are in range. They show only while the game reports them and disappear once killed. Limited by Max Distance.")
  C("Treasures & Chests", "mk_treasures", -223,
    "Treasure and chest markers the game is currently reporting nearby. Only objects the game flags this way appear, not every chest in the world. Limited by Max Distance.")
  Section("Gathering (Saved Spots)", -255)
  C("Herbs", "mk_herbs", -291,
    "Spots where YOU have picked herbs before. Each time a Herb Gathering cast succeeds, CHUD saves your position. The game gives addons no way to see live nodes, so this is a memory of past finds: it fills in as you gather, and a spot may be empty if the node has not respawned. Limited by Max Distance.")
  C("Ore", "mk_ore", -314,
    "Spots where YOU have mined before. Each time a Mining cast succeeds, CHUD saves your position. The game gives addons no way to see live nodes, so this is a memory of past finds: it fills in as you gather, and a spot may be empty if the vein has not respawned. Limited by Max Distance.")
  C("Containers", "mk_containers", -337,
    "Spots where you have opened something with the Opening cast (chests and similar objects). CHUD saves your position when the cast succeeds, so this only knows places you have been. Limited by Max Distance.")
  local note = Label(f, "Spots are saved as you gather them.", 14, -366, "GameFontHighlightSmall")
  note:SetTextColor(0.65, 0.65, 0.65)
  Section("Questie", -392)
  local qs = Label(f, "", 14, -418, "GameFontHighlightSmall")
  refreshers[#refreshers + 1] = function()
    if _G.Questie then qs:SetText("Questie detected"); qs:SetTextColor(0.4, 0.9, 0.4)
    else qs:SetText("Questie not detected"); qs:SetTextColor(0.65, 0.65, 0.65) end
  end
  C("Use Questie Markers", "mk_questie", -436,
    "When Questie is installed, quest objectives, turn-ins and quest givers come from Questie's map icons instead of the game's. Turned on automatically once Questie is detected. Untick it to go back to the game's own quest markers. Quest Objectives and Quest Givers above still decide which kinds show.")
  C("Focused Quest Only", "mk_qFocusOnly", -459,
    "Shows Questie icons only for the quest you have focused (click a quest icon on the bar, or focus it in Questie's tracker or the quest log). Every other quest icon is hidden.")
  local qr = Slider(f, "Questie Max Distance", 14, -492, 130, 20, 500, 10,
    function() return ns.db.mk_qRange end, function(v) ns.db.mk_qRange = v; ns.MarkersChanged() end,
    function(v) return format("%d yd", v) end, true)
  Tip(qr, "Questie Max Distance", "Questie icons farther away than this are hidden. Questie draws one icon per spawn, so only the nearest icon of each quest is shown. The focused quest's marker ignores this and always shows.")
  Button(f, "Open Settings", 14, -556, 224, function()
    f:Hide()
    if ns.categoryID then Settings.OpenToCategory(ns.categoryID) end
  end)

  -- Right column: display options and icon style. Style settings are saved with themes.
  local X = 262
  local function CR(text, key, y, tip)
    local g2, s2 = opt(key)
    local b = Check(f, text, X, y, g2, s2)
    b:SetHitRectInsets(0, -190, 0, 0)
    Tip(b, text, tip)
  end
  local function StyleCheck(text, key, y, tip)
    local b = Check(f, text, X, y, function() return ns.db[key] end,
      function(v) ns.db[key] = v; ns.MarkersStyle() end)
    b:SetHitRectInsets(0, -190, 0, 0)
    Tip(b, text, tip)
  end
  Header(f, "Display", X, -50, 224)
  CR("Show Distance", "mk_distance", -86, "Shows the distance in yards under the tracked marker's icon.")
  local unlock = Check(f, "Unlock (Drag To Move)", X, -109, function() return not ns.db.locked end,
    function(v) ns.db.locked = not v; ns.Apply() end)
  unlock:SetHitRectInsets(0, -190, 0, 0)
  Tip(unlock, "Unlock (Drag To Move)", "Lets you drag CHUD to a new position with the left mouse button. The same as /chud unlock and /chud lock. Untick it to lock the position again.")
  Button(f, "Center", X, -138, 108, function() ns.CenterHorizontal() end)
  Button(f, "Reset Position", X + 116, -138, 108, function() ns.ResetPosition() end)
  local rg = Slider(f, "Max Distance", X, -174, 130, 100, 1500, 50,
    function() return ns.db.mk_range end, function(v) ns.db.mk_range = v; ns.MarkersChanged() end,
    function(v) return format("%d yd", v) end, true)
  Tip(rg, "Max Distance", "Markers farther away than this are hidden. The tracked quest or waypoint marker ignores this and always shows. Questie icons use their own Questie Max Distance.")

  Header(f, "Icon Style", X, -232, 224)
  local sz = Slider(f, "Icon Size", X, -268, 130, 10, 28, 1,
    function() return ns.db.mk_size end, function(v) ns.db.mk_size = v; ns.MarkersStyle() end, Plain, true)
  Tip(sz, "Icon Size", "How big the marker icons are, in pixels. Icon style is saved with themes.")
  local sw = ColorRow(f, "Icon Color", "mk_color", X, -322)
  Tip(sw, "Icon Color", "Tints every marker icon. The slider sets opacity. New themes start with their accent color here.")
  StyleCheck("Original Icon Colors", "mk_native", -352,
    "Keeps the game's own icon colors (gold quest marks, skulls, etc.) instead of tinting them with Icon Color.")
  local sa = Slider(f, "Shadow Opacity (0 = Off)", X, -384, 130, 0, 1, 0.05,
    function() return ns.db.mk_shadowAlpha end, function(v) ns.db.mk_shadowAlpha = v; ns.MarkersStyle() end, Pct, true, 100)
  Tip(sa, "Shadow Opacity", "How dark the drop shadow under each icon is. 0 turns it off.")
  local sd = Slider(f, "Shadow Distance", X, -434, 130, 0, 4, 0.5,
    function() return ns.db.mk_shadowDist end, function(v) ns.db.mk_shadowDist = v; ns.MarkersStyle() end, Px, true)
  Tip(sd, "Shadow Distance", "How far the shadow is offset down and to the right of the icon, in pixels.")
  StyleCheck("Smaller When Far", "mk_depth", -490,
    "Icons shrink the farther away they are, down to about 60% of Icon Size at the edge of their range. The focused quest's icon is always the largest, and no icon makes the bar taller.")
  if ns.QuestAreaSupported and ns.QuestAreaSupported() then
    StyleCheck("Glow In Quest Area", "mk_areaGlow", -513,
      "The focused quest's icon pulses with a soft glow while you are inside that quest's area (the blue zone on the map).")
  end
  return f
end

function ns.ToggleMarkerMenu()
  if not ns.db then return end
  markerMenu = markerMenu or BuildMarkerMenu()
  if markerMenu:IsShown() then markerMenu:Hide(); return end
  markerMenu:ClearAllPoints()
  markerMenu:SetPoint("TOP", ns.root, "BOTTOM", 0, -8)
  markerMenu:Show()
end

function ns.BuildSettings()
  local panel = CreateFrame("Frame")
  panel.name = "CHUD"
  local db = ns.db
  local function bind(key) return function() return db[key] end, function(v) db[key] = v; ns.Apply() end end

  Label(panel, "CHUD Settings", 16, -14, "GameFontNormalHuge")
  Label(panel, "/chud [unlock | lock | center | resetpos | resetcolors | resetbehavior | reset]",
    16, -44, "GameFontHighlightSmall")

  -- Theme row: dropdown + Save + Delete -------------------------------------------------
  Label(panel, "Theme", 236, -17, "GameFontNormal")
  local themeBtn, themePopup, themeUpdate
  local saveBtn, delBtn
  local function tip(btn, title, body)
    btn:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:SetText(title, 1, 1, 1)
      GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  themeBtn, themePopup, themeUpdate = ListDropdown(panel, 290, -12, 150,
    function() return ns.MatchTheme() or "Custom (Unsaved)" end,
    function()
      local match = ns.MatchTheme()
      local items = { { text = "Built-In", header = true } }
      for _, n in ipairs(ns.BuiltinNames) do items[#items + 1] = { text = n, value = n, selected = (n == match) } end
      local user = ns.UserThemeNames()
      if #user > 0 then
        items[#items + 1] = { text = "Saved", header = true }
        for _, n in ipairs(user) do items[#items + 1] = { text = n, value = n, selected = (n == match) } end
      end
      return items
    end,
    function(name) ns.ApplyTheme(name) end,
    "CHUDThemePopup")

  saveBtn = Button(panel, "Save", 446, -12, 60, function()
    if ns.MatchTheme() then return end    -- identical to an existing theme: nothing to save
    ShowDialog({
      text = "Name your new theme:", edit = true, default = "", yes = "Save",
      onYes = function(name)
        name = strtrim(name)
        if name == "" then return "Enter a name." end
        if ns.IsBuiltin(name) then return "That name belongs to a built-in theme." end
        local f = GetDialog()
        if ns.db.themes[name] and f.pendingOverwrite ~= name then
          f.pendingOverwrite = name
          return "A theme with that name exists. Press Save again to overwrite it."
        end
        ns.SaveTheme(name)
        Refresh()
      end,
    })
  end)
  tip(saveBtn, "Save Theme", "Saves the current look as a new theme. Disabled while your settings already match a theme.")

  delBtn = Button(panel, "Delete", 512, -12, 66, function()
    local name = ns.MatchTheme()
    if not name or ns.IsBuiltin(name) then return end
    ShowDialog({
      text = 'Delete theme "' .. name .. '"?', yes = "Delete",
      onYes = function() ns.DeleteTheme(name); Refresh() end,
    })
  end)
  tip(delBtn, "Delete Theme", "Deletes the selected saved theme. Built-in themes cannot be deleted.")

  local function themeRefresh()
    themeUpdate()
    local match = ns.MatchTheme()
    if match then saveBtn:Disable() else saveBtn:Enable() end
    if match and not ns.IsBuiltin(match) then delBtn:Enable() else delBtn:Disable() end
  end
  refreshers[#refreshers + 1] = themeRefresh
  ns.OnSettingsChanged = themeRefresh

  -- The settings canvas is ~650 units wide and ~610 tall; columns are sized to fit, with the
  -- vertical space spread out so nothing feels compressed.
  -- Column A: size, font, fade ---------------------------------------------------
  local ax, y = 16, -72
  Header(panel, "Size & Fade", ax, y, 196)
  local _, popup = FontDropdown(panel, ax, -108, 196)
  y = -164
  local function S(text, key, a, b, step, fmt, maxFn)
    local g, set = bind(key)
    fmt = fmt or Plain
    Slider(panel, text, ax, y, 132, a, b, step, g, set, fmt, true, (fmt == Pct) and 100 or 1, maxFn, ns.defaults[key])
    y = y - 48
  end
  -- Width's upper bound is the real UI width, so it can span the whole top of the screen.
  S("Width", "width", 200, 1200, 10, Plain, function() return math.max(400, floor(UIParent:GetWidth())) end)
  S("Height", "height", 20, 80, 1)
  S("Visible Degrees", "span", 60, 360, 10)
  S("Font Size", "fontSize", 8, 24, 1)
  S("Edge Fade Amount", "fadeAmount", 0.05, 1, 0.05, Pct)
  S("Background Opacity", "bgOpacity", 0, 1, 0.05, Pct)
  S("XP Fill Strength", "xpFillStrength", 0, 1, 0.05, Pct)
  S("Outline Thickness (0 = Off)", "outlineWidth", 0, 2, 0.5, Px)

  -- Column B: display toggles + position -----------------------------------------
  local ROW = 24   -- vertical step for every checkbox and color row, in all columns, so the spacing matches
  local bx = 228
  Header(panel, "Display", bx, -72, 170)
  y = -108
  local function C(text, key)
    local g, set = bind(key); Check(panel, text, bx, y, g, set); y = y - ROW
  end
  C("Show Degree Readout", "showDegrees")
  C("Degrees Inside Bar", "degreeInline")
  C("Show NE/SE/SW/NW", "showIntercardinals")
  C("Show Tick Marks", "showTicks")
  C("Show Number Labels", "showNumbers")
  C("Flip Ticks / Letters", "flipTicks")
  C("Fade Edges (Bar + BG)", "fadeEdges")
  C("Edge Hairlines", "edgeLines")
  C("Glitch Effect In Dungeons", "glitchFx")
  C("Low-CPU Rendering", "optimize")
  -- Turning the right-click menu off needs a confirmation: unlocking the bar and every marker option live there.
  Check(panel, "Right-Click Menu", bx, y, function() return db.rightClickMenu ~= false end,
    function(v)
      if v then db.rightClickMenu = true; return end
      ShowDialog({
        text = "Warning: very important functionality is locked behind the right-click menu: unlocking and moving the bar, centering it, and every quest, rare, treasure and gathering marker option.\n\nIf you turn it off, /chud unlock, /chud lock, /chud center and /chud menu still work.",
        yes = "Disable",
        onYes = function() db.rightClickMenu = false; Refresh() end,
      })
    end)   -- cancelling leaves the setting unchanged, and the Refresh after this click re-ticks the box
  y = y - ROW

  -- Everything about the XP fill in one place.
  Header(panel, "Experience Bar", bx, y - 12, 170)
  y = y - 48
  C("XP Bar + Hover Tooltip", "xpBar")
  Check(panel, "XP Bar Pulse On Gain", bx, y, function() return db.xpPulse end,
    function(v) db.xpPulse = v; ns.Apply(); if v then ns.PreviewXPPulse() end end)   -- plays once so you can see it
  y = y - ROW - 6
  -- Style and direction have several states, so each is one button that cycles (a checkbox group
  -- would let you tick two or none).
  local function Cycler(list, key, x, yy)
    local btn = Button(panel, "", x, yy, 170, function()
      local cur = 1
      for i, f in ipairs(list) do if f[1] == db[key] then cur = i end end
      db[key] = list[cur % #list + 1][1]
      ns.Apply(); Refresh()
    end)
    refreshers[#refreshers + 1] = function()
      local label = list[1][2]
      for _, f in ipairs(list) do if f[1] == db[key] then label = f[2] end end
      btn:SetText(label)
    end
    return btn
  end
  Cycler({ { "fadeCenter", "Style: Fade From Center" }, { "fadeBottom", "Style: Fade From Bottom" }, { "fadeTop", "Style: Fade From Top" },
    { "band", "Style: Short Band" }, { "full", "Style: Full Height" } },
    "xpFillStyle", bx, y)
  y = y - 32   -- 24 px button + 8 px gap
  Cycler({ { "left", "Fill: Left To Right" }, { "edges", "Fill: From Both Edges" }, { "center", "Fill: From Center" },
    { "up", "Fill: Bottom To Top" }, { "down", "Fill: Top To Bottom" } },
    "xpFillMode", bx, y)

  -- Column C: colors -------------------------------------------------------------
  local cx = 412
  Header(panel, "Background", cx, -72, 232)
  Check(panel, "Solid", cx, -108, function() return db.bgMode == "solid" end,
    function() db.bgMode = "solid"; ns.Apply() end)
  Check(panel, "Gradient", cx + 84, -108, function() return db.bgMode == "gradient" end,
    function() db.bgMode = "gradient"; ns.Apply() end)
  ColorRow(panel, "Solid Color", "bgSolid", cx, -108 - ROW)
  ColorRow(panel, "Gradient Center", "bgCenter", cx, -108 - 2 * ROW)
  ColorRow(panel, "Gradient Edge", "bgEdge", cx, -108 - 3 * ROW)

  y = -108 - 3 * ROW - 28
  Header(panel, "Elements", cx, y, 232)
  y = y - 36
  for _, r in ipairs({
    { "Text / Numbers", "textColor" }, { "E / S / W", "cardinalColor" }, { "North", "northColor" },
    { "Tick Marks", "tickColor" }, { "Center Marker", "markerColor" }, { "Degree Readout", "degreeColor" },
    { "Text Outline", "outlineColor" },
  }) do
    ColorRow(panel, r[1], r[2], cx, y); y = y - ROW
  end

  -- Marker style: two checkboxes that act as a pair (one is always on).
  Check(panel, "Marker: Short", cx, y, function() return db.markerStyle ~= "notch" end,
    function() db.markerStyle = "short"; ns.Apply() end)
  Check(panel, "Marker: Notch", cx + 116, y, function() return db.markerStyle == "notch" end,
    function() db.markerStyle = "notch"; ns.Apply() end)
  y = y - ROW - 4

  Header(panel, "XP & Edge Colors", cx, y, 232)
  y = y - 36
  ColorRow(panel, "XP Bar", "xpColor", cx, y)
  ColorRow(panel, "Edge Lines", "edgeColor", cx, y - ROW)

  -- Bottom bar: resets -------------------------------------------------------------
  local rule = panel:CreateTexture(nil, "ARTWORK")
  rule:SetPoint("TOPLEFT", 16, -556); rule:SetSize(628, 1); rule:SetColorTexture(unpack(RULE))
  Button(panel, "Reset Colors", 16, -570, 120, function() ns.ResetColors() end)
  Button(panel, "Reset Layout/Behavior", 142, -570, 160, function() ns.ResetBehavior() end)
  Button(panel, "Reset All Settings", 308, -570, 130, function() ns.Reset() end)
  local xpBtn
  xpBtn = Button(panel, "", 444, -570, 190, function()
    if not ns.BlizzXPFound() then print("|cffd9bf4dCHUD:|r could not find the default XP bar on this client."); return end
    ns.db.hideBlizzXP = not ns.db.hideBlizzXP
    ns.ApplyBlizzXP()
    Refresh()
  end)
  refreshers[#refreshers + 1] = function() xpBtn:SetText("Default XP Bar: " .. (ns.db.hideBlizzXP and "Hidden" or "Shown")) end

  panel:SetScript("OnShow", Refresh)
  panel:SetScript("OnHide", function()
    popup:Hide(); themePopup:Hide()
    if dialog then dialog:Hide() end
  end)
  local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
  Settings.RegisterAddOnCategory(category)
  ns.categoryID = category:GetID()
  Refresh()
end
