local ADDON, ns = ...

-- Custom XP tooltip. The settings that control it are in Settings.lua.
--
-- This is CHUD's own frame. The game's GameTooltip is never restyled, so other addons' tooltips are untouched.
-- Every effect runs from one OnUpdate on the tooltip frame, which only runs while the tooltip is on screen.
-- Images (ring, glow, shade, scanlines, brackets, shimmer) are small .tga files in the addon's media folder.
-- If building or showing the tooltip ever fails, CHUD falls back to the game's own tooltip.

local floor, max, min, sin, pi = math.floor, math.max, math.min, math.sin, math.pi

local W = 240            -- tooltip width in pixels
local PAD = 14           -- left/right padding
local BARW = W - PAD * 2 -- XP bar width
local ROW = 15           -- row height
local MEDIA = "Interface\\AddOns\\CHUD\\media\\"

-- Every adjustable number, with its default. Saved in CHUDDB.tipP; missing keys use these.
local DEFAULTS = {
  slideDur = 0.7, slideDist = 24, growDur = 0.5, linesDur = 0.5, fillDur = 1.2,
  shimmerSpeed = 1, pulseSpeed = 1, spinSpeed = 1, spinRamp = 6, spinShake = 2, ringSpeed = 1,
  glowAlpha = 0.50, shadeAlpha = 0.45, scanAlpha = 0.30, scanSpeed = 8, bracketAlpha = 0.80,
  scale = 1, borderStyle = 2, sampleXP = 0.37,
}

-- Effects that are a look rather than motion: they ignore the master animation switch and do not replay the sample.
local STILL = { glow = true, shade = true, scan = true, brackets = true }

-- A tooltip effect setting, falling back to its default.
local function P(key)
  local db = ns.db
  local v = db and db.tipP and db.tipP[key]
  if v == nil then return DEFAULTS[key] end
  return v
end
-- True when this tooltip effect is switched on.
local function FX(key)
  local db = ns.db
  if not db then return false end
  if key == "scan" then return db.scanlines ~= false end   -- one Scanlines switch in the main settings covers the bar and this tooltip
  if db.tipAnim == false and not STILL[key] then return false end
  local fx = db.tipFx
  return fx == nil or fx[key] ~= false
end

-- Easing -----------------------------------------------------------------------------------------
local function Clamp01(x) if x < 0 then return 0 elseif x > 1 then return 1 end return x end
-- Easing curves: each takes progress 0-1 and returns the eased value 0-1.
local function EaseOutExpo(x) x = Clamp01(x); if x >= 1 then return 1 end return 1 - 2 ^ (-10 * x) end
local function EaseOutCubic(x) x = Clamp01(x); return 1 - (1 - x) ^ 3 end
local function EaseInOutExpo(x)
  x = Clamp01(x)
  if x <= 0 then return 0 elseif x >= 1 then return 1 end
  if x < 0.5 then return 2 ^ (20 * x - 10) / 2 end
  return (2 - 2 ^ (-20 * x + 10)) / 2
end

-- Frame ------------------------------------------------------------------------------------------
local tip

-- Applies the chosen font, size and outline to a tooltip label.
local function SetFont(fs, size)
  local db = ns.db
  local path = (db and db.fontPath and db.fontPath ~= "") and db.fontPath or STANDARD_TEXT_FONT
  local flag = (db and (db.outlineWidth or 0) > 0) and "OUTLINE" or ""
  if not fs:SetFont(path, size, flag) then fs:SetFont(STANDARD_TEXT_FONT, size, flag) end
end

-- Creates a tooltip label.
local function Text(parent, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

local STAR_X, STAR_Y = -(PAD + 6), -19   -- the star and ring sit here (center, from the content's top right); the level and percent line up with it

-- Builds the tooltip frame and all its parts (created on first use).
local function Build()
  local f = CreateFrame("Frame", "CHUDTip", UIParent)
  f:SetFrameStrata("TOOLTIP"); f:SetClampedToScreen(true); f:Hide()
  f:SetSize(W, 100)
  if f.SetClipsChildren then f:SetClipsChildren(true) end   -- grow resizes the frame; the content is clipped, not squashed

  -- Backgrounds, scanlines and shade are drawn by the frame itself, below its border lines, and kept 1-2 px inside
  -- them, so nothing is ever drawn on top of the border.
  f.glow = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  f.glow:SetTexture(MEDIA .. "glow.tga")
  f.glow:SetPoint("TOPLEFT", -18, 18); f.glow:SetPoint("BOTTOMRIGHT", 18, -18)
  f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints()
  f.shade = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  f.shade:SetTexture(MEDIA .. "shade.tga"); f.shade:SetPoint("TOPLEFT", 2, -1); f.shade:SetPoint("TOPRIGHT", -2, -1); f.shade:SetHeight(50)
  f.scan = f:CreateTexture(nil, "BACKGROUND", nil, 2)
  f.scan:SetTexture(MEDIA .. "scan.tga", "REPEAT", "REPEAT")   -- a 16 x 4 pixel tile, repeated in TipUpdate
  f.scan:SetPoint("TOPLEFT", 2, -1); f.scan:SetPoint("BOTTOMRIGHT", -2, 1)

  f.top = f:CreateTexture(nil, "BORDER");    f.top:SetHeight(1)
  f.bottom = f:CreateTexture(nil, "BORDER"); f.bottom:SetHeight(1)
  f.left = f:CreateTexture(nil, "ARTWORK");  f.left:SetWidth(2)    -- the two side lines are the accent color, same thickness
  f.right = f:CreateTexture(nil, "ARTWORK"); f.right:SetWidth(2)

  -- Everything else lives on a fixed-size child so grow clips it instead of squashing it.
  local c = CreateFrame("Frame", nil, f)
  c:SetSize(W, 100)
  f.c = c

  c.brackets = {}
  for i = 1, 4 do
    local b = c:CreateTexture(nil, "OVERLAY", nil, 2)
    b:SetTexture(MEDIA .. "bracket.tga"); b:SetSize(10, 10)
    c.brackets[i] = b
  end
  c.brackets[1]:SetPoint("TOPLEFT", c, "TOPLEFT", 4, -4)
  c.brackets[2]:SetPoint("TOPRIGHT", c, "TOPRIGHT", -4, -4);      c.brackets[2]:SetTexCoord(1, 0, 0, 1)
  c.brackets[3]:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 4, 4);    c.brackets[3]:SetTexCoord(0, 1, 1, 0)
  c.brackets[4]:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -4, 4); c.brackets[4]:SetTexCoord(1, 0, 1, 0)

  -- One center line: the level, the percentage and the star/ring all sit on it.
  c.title = Text(c); c.title:SetPoint("LEFT", c, "TOPLEFT", PAD, STAR_Y)
  c.ring = c:CreateTexture(nil, "ARTWORK"); c.ring:SetTexture(MEDIA .. "ring.tga"); c.ring:SetBlendMode("ADD")
  c.ring:SetSize(26, 26); c.ring:SetPoint("CENTER", c, "TOPRIGHT", STAR_X, STAR_Y)
  c.spin = c:CreateTexture(nil, "ARTWORK", nil, 1); c.spin:SetTexture("Interface\\Cooldown\\star4"); c.spin:SetBlendMode("ADD")
  c.spin:SetSize(15, 15); c.spin:SetPoint("CENTER", c, "TOPRIGHT", STAR_X, STAR_Y)
  c.pct = Text(c, "RIGHT"); c.pct:SetPoint("RIGHT", c.ring, "LEFT", -8, 0)

  c.track = c:CreateTexture(nil, "ARTWORK"); c.track:SetPoint("TOPLEFT", PAD, -34); c.track:SetSize(BARW, 6)
  c.fill = c:CreateTexture(nil, "ARTWORK", nil, 1); c.fill:SetPoint("TOPLEFT", c.track, "TOPLEFT"); c.fill:SetSize(1, 6)
  c.restedFrame = CreateFrame("Frame", nil, c)
  c.restedFrame:SetHeight(6)
  if c.restedFrame.SetClipsChildren then c.restedFrame:SetClipsChildren(true) end
  c.rested = c.restedFrame:CreateTexture(nil, "ARTWORK"); c.rested:SetAllPoints()
  c.shimmer = c.restedFrame:CreateTexture(nil, "OVERLAY"); c.shimmer:SetBlendMode("ADD"); c.shimmer:SetSize(28, 6)
  c.shimmer:SetTexture(MEDIA .. "shimmer.tga")

  c.rows = {}
  for i = 1, 4 do
    local l, v = Text(c), Text(c, "RIGHT")
    c.rows[i] = { l = l, v = v }
  end

  f:SetScript("OnUpdate", function(self, dt) ns.TipUpdate(self, dt) end)
  return f
end

-- Border -----------------------------------------------------------------------------------------
-- Style 1, Sweep:      top and bottom draw left to right; the right edge only appears once they are done.
-- Style 2, Center Out: all four edges grow outward from their middles at the same time.
-- Style 3, Trace:      the top draws across while both sides run down, then the bottom closes it.
local function Borders(f, p, h)
  local style = P("borderStyle")
  local top, bottom, left, right = f.top, f.bottom, f.left, f.right
  if style == 2 then
    local hw, vh = max(1, floor(W * p + 0.5)), max(1, floor(h * p + 0.5))
    top:ClearAllPoints();    top:SetPoint("TOP");       top:SetWidth(hw)
    bottom:ClearAllPoints(); bottom:SetPoint("BOTTOM"); bottom:SetWidth(hw)
    left:ClearAllPoints();   left:SetPoint("LEFT");     left:SetHeight(vh)
    right:ClearAllPoints();  right:SetPoint("RIGHT");   right:SetHeight(vh)
    left:Show(); right:Show()
  elseif style == 3 then
    local tw = max(1, floor(W * Clamp01(p * 2) + 0.5))
    local bw = max(1, floor(W * Clamp01(p * 2 - 1) + 0.5))
    local vh = max(1, floor(h * p + 0.5))
    top:ClearAllPoints();    top:SetPoint("TOPLEFT");        top:SetWidth(tw)
    bottom:ClearAllPoints(); bottom:SetPoint("BOTTOMLEFT");  bottom:SetWidth(bw); bottom:SetShown(p > 0.5)
    left:ClearAllPoints();   left:SetPoint("TOPLEFT");       left:SetHeight(vh)
    right:ClearAllPoints();  right:SetPoint("TOPRIGHT");     right:SetHeight(vh)
    left:Show(); right:Show()
  else
    local lw = max(1, floor(W * p + 0.5))
    top:ClearAllPoints();    top:SetPoint("TOPLEFT");        top:SetWidth(lw)
    bottom:ClearAllPoints(); bottom:SetPoint("BOTTOMLEFT");  bottom:SetWidth(lw)
    left:ClearAllPoints();   left:SetPoint("TOPLEFT");       left:SetPoint("BOTTOMLEFT")
    right:ClearAllPoints();  right:SetPoint("TOPRIGHT");     right:SetPoint("BOTTOMRIGHT")
    left:Show(); right:SetShown(p >= 1)
  end
  top:SetShown(true)
  if style ~= 3 then bottom:Show() end
end

-- Per-frame animation ------------------------------------------------------------------------------
local function Place(f, slide)
  local a = f.anchor
  if not a then return end
  local s = f:GetScale()
  if not s or s <= 0 then s = 1 end
  f:ClearAllPoints()
  -- dir: -1 = the tooltip hangs below the bar. It starts nearer the bar and moves outward by `slide` pixels.
  f:SetPoint(a.point, a.owner, a.rel, a.x / s, (a.y - a.dir * slide) / s)
end

-- Per-frame update of the tooltip's animation and its hide delay.
function ns.TipUpdate(f, dt)
  -- A short grace period after the mouse leaves: moving across a marker icon leaves and re-enters the bar
  -- within a moment, and that should not restart the animation.
  if f.pendingHide then
    f.pendingHide = f.pendingHide - dt
    if f.pendingHide <= 0 then
      f.pendingHide = nil; f.hideAt = GetTime(); f:Hide()
      -- The effects panel is open: bring the sample back where the real tooltip just was.
      if ns.TipLabOpen and ns.TipLabOpen() then ns.TipPreview(true) end
      return
    end
  end
  local t = f.t + dt
  f.t = t
  local c = f.c
  local H = f.H

  -- slide and fade
  local alpha = FX("slide") and Clamp01(t / (P("slideDur") * 0.5)) or 1
  if f.al ~= alpha then f.al = alpha; f:SetAlpha(alpha) end
  local slide = 0
  if FX("slide") then slide = (1 - EaseOutExpo(t / P("slideDur"))) * P("slideDist") end
  if f.sl ~= slide then f.sl = slide; Place(f, slide) end

  -- grow (height)
  local h = H
  if FX("grow") then h = max(2, floor(H * EaseOutCubic(t / P("growDur")) + 0.5)) end
  if f.h ~= h then
    f.h = h; f:SetHeight(h)
    f.shade:SetHeight(max(1, min(50, h - 2)))
  end

  -- border
  local p = FX("lines") and EaseInOutExpo((t - 0.05) / P("linesDur")) or 1
  if f.bp ~= p or f.bh ~= h or f.bs ~= P("borderStyle") then
    f.bp, f.bh, f.bs = p, h, P("borderStyle")
    Borders(f, p, h)
  end

  -- accent lines (left and right) pulse together
  local pa = FX("pulse") and (0.55 + 0.45 * (0.5 + 0.5 * sin(t * 2 * pi * P("pulseSpeed") / 1.8))) or 1
  f.left:SetAlpha(pa); f.right:SetAlpha(pa)

  -- scanlines: tile the 16 x 4 image across the tooltip, drifting downward
  if FX("scan") then
    local v0 = ((ns.db.tipAnim == false) and 0 or (t * P("scanSpeed") / 4)) % 1
    f.scan:SetTexCoord(0, (W - 4) / 16, -v0, (h - 2) / 4 - v0)
  end

  -- XP bar
  if f.hasBar then
    local pf = FX("fill") and EaseOutExpo((t - 0.12) / P("fillDur")) or 1
    local fw = floor(BARW * f.pct * pf + 0.5)
    if f.fw ~= fw then
      f.fw = fw
      c.fill:SetWidth(max(fw, 0.001)); c.fill:SetShown(fw > 0)
      local rw = max(0, min(f.restedW, BARW - fw))
      c.restedFrame:ClearAllPoints()
      c.restedFrame:SetPoint("LEFT", c.track, "LEFT", fw, 0)
      c.restedFrame:SetWidth(max(rw, 0.001)); c.restedFrame:SetShown(rw > 0.5)
      f.rw = rw
    end
    if f.rw and f.rw > 0.5 then
      if FX("shimmer") then
        local x = ((t * 0.55 * P("shimmerSpeed")) % 1.6 / 1.6) * (f.rw + 56) - 28
        c.shimmer:ClearAllPoints(); c.shimmer:SetPoint("LEFT", c.restedFrame, "LEFT", x, 0); c.shimmer:Show()
      else
        c.shimmer:Hide()
      end
    end
  end

  -- star and ring: both turn faster the closer you are to the next level (1x just after a level up, up to
  -- "Speed At Level-Up" just before the next), and the star starts to shake near the end.
  local prog = f.hasBar and f.pct or 0
  local ramp = 1 + (P("spinRamp") - 1) * prog
  if FX("spin") then
    c.spin:Show()
    f.spinAng = (f.spinAng or 0) + dt * 0.63 * P("spinSpeed") * ramp
    if c.spin.SetRotation then c.spin:SetRotation(f.spinAng) end
    local amp = P("spinShake") * prog * prog * prog
    if amp > 0.05 then
      local dx = amp * (sin(t * 53) + 0.6 * sin(t * 37 + 1))
      local dy = amp * (sin(t * 47 + 2) + 0.6 * sin(t * 29))
      c.spin:ClearAllPoints(); c.spin:SetPoint("CENTER", c, "TOPRIGHT", STAR_X + dx, STAR_Y + dy)
      f.shaking = true
    elseif f.shaking then
      f.shaking = false
      c.spin:ClearAllPoints(); c.spin:SetPoint("CENTER", c, "TOPRIGHT", STAR_X, STAR_Y)
    end
  else
    c.spin:Hide()
  end
  if FX("ring") then
    c.ring:Show()
    f.ringAng = (f.ringAng or 0) - dt * 0.8 * P("ringSpeed") * ramp
    if c.ring.SetRotation then c.ring:SetRotation(f.ringAng) end
  else
    c.ring:Hide()
  end
end

-- Content ----------------------------------------------------------------------------------------

-- Colors --------------------------------------------------------------------------------------------
-- By default the tooltip colors follow the current theme. Every text color is nudged toward white or black
-- until it reads clearly on the tooltip's own background, so light themes get dark value colors.
local function Chan(v) if v <= 0.03928 then return v / 12.92 end return ((v + 0.055) / 1.055) ^ 2.4 end
-- Relative luminance of a color, and the contrast ratio between two colors.
local function Lum(c) return 0.2126 * Chan(c[1]) + 0.7152 * Chan(c[2]) + 0.0722 * Chan(c[3]) end
local function Ratio(a, b)
  local x, y = Lum(a), Lum(b)
  if x < y then x, y = y, x end
  return (x + 0.05) / (y + 0.05)
end
-- Nudges a color toward black or white until it has enough contrast against bg.
local function Ensure(c, bg, want)
  local r = { c[1], c[2], c[3], c[4] or 1 }
  if Ratio(r, bg) >= want then return r end
  local target = (Lum(bg) > 0.4) and 0 or 1
  for i = 1, 10 do
    local f = i / 10
    local m = { c[1] + (target - c[1]) * f, c[2] + (target - c[2]) * f, c[3] + (target - c[3]) * f, c[4] or 1 }
    if Ratio(m, bg) >= want then return m end
  end
  return { target, target, target, c[4] or 1 }
end
-- Blends two colors: f = 0 gives a, f = 1 gives b.
local function Mix(a, b, f) return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f, 1 } end
-- Picks readable tooltip text colors for the current background.
function ns.TipAutoColors()
  local db = ns.db
  local bgc = (db.bgMode == "solid") and db.bgSolid or db.bgCenter
  local bg = { bgc[1], bgc[2], bgc[3], 1 }
  return {
    bg = bg,
    edge = { db.edgeColor[1], db.edgeColor[2], db.edgeColor[3], 1 },
    accent = Ensure(db.markerColor or db.cardinalColor, bg, 3),
    title = Ensure(db.cardinalColor, bg, 4.5),
    text = Ensure(db.textColor, bg, 4.5),
    -- "Remaining" is a positive green pulled toward the theme's title color; "Rested" follows the XP color.
    good = Ensure(Mix({ 0.45, 0.95, 0.50 }, db.cardinalColor, 0.40), bg, 4.5),
    rest = Ensure(Mix(db.xpColor, { 1, 1, 1 }, 0.25), bg, 4.5),
  }
end
-- The tooltip's colors: automatic, or the player's own.
local function Colors()
  local db = ns.db
  local c
  if db.tipAuto == false and db.tipBg then
    local function rgb(x) return { x[1], x[2], x[3], 1 } end
    c = { bg = rgb(db.tipBg), edge = rgb(db.tipEdge), accent = rgb(db.tipAccent), title = rgb(db.tipTitle), text = rgb(db.tipText),
      good = rgb(db.tipGood or db.tipTitle), rest = rgb(db.tipRest or db.tipAccent) }
  else
    c = ns.TipAutoColors()
  end
  c.good = Ensure(c.good, c.bg, 4.5)
  c.rest = Ensure(c.rest, c.bg, 4.5)
  c.mute = Ensure({ c.text[1] * 0.65, c.text[2] * 0.65, c.text[3] * 0.65 }, c.bg, 3.5)
  c.hint = Ensure({ 0.6, 0.6, 0.6 }, c.bg, 3)
  return c
end


-- d = { level, cur, mx, isMax, rested, drag }. Returns true when it handled the request.
-- restart = true replays the animation even if it is already open; preview = true marks the effects panel's sample.
function ns.TipShow(owner, d, point, restart, preview)
  local db = ns.db
  if not db then return false end
  tip = tip or Build()
  local f, c = tip, tip.c

  local hasLevel = d.level ~= nil
  if not hasLevel and not d.drag then f:Hide(); return true end

  -- Already open for this owner (an XP update refreshing it), or the mouse only slipped across a marker icon
  -- a moment ago: keep the animation where it is instead of replaying it.
  local keep = not restart and f.lastOwner == owner and f.lastPoint == point
    and (f:IsShown() or (f.hideAt and GetTime() - f.hideAt < 0.4))
  f.lastOwner, f.lastPoint = owner, point
  f.pendingHide = nil
  f.previewMode = preview and true or false   -- the sample shown by the effects panel stays up when the mouse leaves the bar

  -- colors from the current theme
  local K = Colors()
  local bgc = (db.bgMode == "solid") and db.bgSolid or db.bgCenter
  local op = db.bgOpacity or 1
  f.bg:SetColorTexture(K.bg[1], K.bg[2], K.bg[3], max(0.88, min(1, (bgc[4] or 1) * op)))
  local ec = K.edge
  f.top:SetColorTexture(ec[1], ec[2], ec[3], 0.9); f.bottom:SetColorTexture(ec[1], ec[2], ec[3], 0.9)
  local ac = K.accent
  f.left:SetColorTexture(ac[1], ac[2], ac[3], 1)
  f.right:SetColorTexture(ac[1], ac[2], ac[3], 1)
  local tc, cc = K.text, K.title

  f.glow:SetShown(FX("glow")); f.glow:SetVertexColor(ac[1], ac[2], ac[3], P("glowAlpha"))
  f.shade:SetShown(FX("shade")); f.shade:SetVertexColor(0, 0, 0, P("shadeAlpha"))
  f.scan:SetShown(FX("scan")); f.scan:SetVertexColor(Lum(K.bg) > 0.4 and 0.3 or 0, Lum(K.bg) > 0.4 and 0.3 or 0, Lum(K.bg) > 0.4 and 0.3 or 0, P("scanAlpha"))
  local nb = FX("brackets")
  for i = 1, 4 do c.brackets[i]:SetShown(nb); c.brackets[i]:SetVertexColor(ac[1], ac[2], ac[3], P("bracketAlpha")) end

  local fs = db.fontSize or 14
  SetFont(c.title, fs + 2); c.title:SetTextColor(cc[1], cc[2], cc[3], 1)
  SetFont(c.pct, fs); c.pct:SetTextColor(tc[1], tc[2], tc[3], 0.85)
  c.spin:SetVertexColor(ac[1], ac[2], ac[3], 0.9)
  c.ring:SetVertexColor(ac[1], ac[2], ac[3], 0.9)

  local rows = {}
  f.hasBar = false
  local y = 34
  if hasLevel then
    if d.isMax then
      c.title:SetText("Level " .. d.level .. " (Max Level)")
      c.pct:SetText("")
      c.track:Hide(); c.fill:Hide(); c.restedFrame:Hide()
    else
      c.title:SetText("Level " .. d.level)
      local pct = d.mx > 0 and d.cur / d.mx or 0
      c.pct:SetText(format("%.1f%%", pct * 100))
      f.hasBar, f.pct = true, Clamp01(pct)
      local rested = d.rested and d.rested > 0
      f.restedW = (rested and d.mx > 0) and floor(BARW * d.rested / d.mx + 0.5) or 0
      local xc = Ensure(db.xpColor, K.bg, 3)
      c.track:SetColorTexture(0, 0, 0, 0.55); c.track:Show()
      c.fill:SetColorTexture(min(1, xc[1] * 1.3 + 0.1), min(1, xc[2] * 1.3 + 0.1), min(1, xc[3] * 1.3 + 0.1), 1)
      c.rested:SetColorTexture(K.rest[1], K.rest[2], K.rest[3], 0.85)
      f.fw = nil
      y = 50
      rows[#rows + 1] = { "XP", format("%s / %s", BreakUpLargeNumbers(d.cur), BreakUpLargeNumbers(d.mx)), K.text[1], K.text[2], K.text[3] }
      rows[#rows + 1] = { "Remaining", BreakUpLargeNumbers(d.mx - d.cur), K.good[1], K.good[2], K.good[3] }
      if rested then
        rows[#rows + 1] = { "Rested", format("%s (%.1f%%)", BreakUpLargeNumbers(d.rested), d.rested / d.mx * 100), K.rest[1], K.rest[2], K.rest[3] }
      else
        -- With no rested XP left, the line shows how fast XP is coming in this session instead.
        rows[#rows + 1] = { "XP/h", d.perHour and BreakUpLargeNumbers(floor(d.perHour + 0.5)) or "--", K.rest[1], K.rest[2], K.rest[3] }
      end
    end
  else
    c.title:SetText(""); c.pct:SetText("")
    c.track:Hide(); c.fill:Hide(); c.restedFrame:Hide()
    y = 12
  end
  if d.drag then rows[#rows + 1] = { "Drag To Move", nil, K.hint[1], K.hint[2], K.hint[3] } end

  for i = 1, 4 do
    local r, row = c.rows[i], rows[i]
    if row then
      SetFont(r.l, fs - 1); SetFont(r.v, fs - 1)
      r.l:ClearAllPoints(); r.l:SetPoint("TOPLEFT", PAD, -(y + (i - 1) * ROW))
      r.v:ClearAllPoints(); r.v:SetPoint("TOPRIGHT", -PAD, -(y + (i - 1) * ROW))
      if row[2] then
        r.l:SetTextColor(K.mute[1], K.mute[2], K.mute[3], 1); r.l:SetText(row[1])
        r.v:SetTextColor(row[3], row[4], row[5], 1); r.v:SetText(row[2])
      else
        r.l:SetTextColor(row[3], row[4], row[5], 1); r.l:SetText(row[1]); r.v:SetText("")
      end
      r.l:Show(); r.v:Show()
    else
      r.l:Hide(); r.v:Hide()
    end
  end

  local H = y + #rows * ROW + 12
  f.H = H
  c:SetSize(W, H)

  -- Where it goes: just under the bar, or just above it when the bar is in the lower half of the screen.
  -- It is anchored by a left corner and the content is pinned to the same edge, so the grow opens away from the bar.
  local _, cy = owner:GetCenter()
  local below = not (type(cy) == "number" and cy < UIParent:GetHeight() / 2)
  local corner
  if below then
    f.anchor = { point = "TOPLEFT", owner = owner, rel = "BOTTOM", x = -W / 2, y = -6, dir = -1 }; corner = "TOPLEFT"
  else
    f.anchor = { point = "BOTTOMLEFT", owner = owner, rel = "TOP", x = -W / 2, y = 6, dir = 1 }; corner = "BOTTOMLEFT"
  end
  c:ClearAllPoints(); c:SetPoint(corner, f, corner)
  f:SetWidth(W)
  f:SetScale(P("scale"))

  if not keep then
    f.t, f.al, f.sl, f.h, f.bp, f.rw = 0, nil, nil, nil, nil, nil
    f.spinAng, f.ringAng = 0, 0
  else
    f.sl, f.h, f.bp = nil, nil, nil   -- re-apply the current state with the new content
  end
  f:Show()
  ns.TipUpdate(f, 0)
  return true
end

-- Leaving the bar: hide after a moment (cancelled if the mouse is back), or at once with `now`.
function ns.TipHide(now)
  if not tip or not tip:IsShown() then return end
  if tip.previewMode and not now then return end
  if now then tip.pendingHide = nil; tip.hideAt = GetTime(); tip:Hide() else tip.pendingHide = 0.12 end
end

-- A sample tooltip for the effects panel, shown exactly where the real one appears (under or over the bar).
-- Uses your real level and rested XP; the XP progress is the panel's "Sample XP" slider so the level-up speed-up and
-- shake can be judged at any point. restart = true replays the animation, false just updates what is showing.
function ns.TipPreview(restart)
  local d = { drag = ns.db and not ns.db.locked }
  local level, mx = UnitLevel("player"), UnitXPMax("player")
  d.level, d.mx = level or 1, (mx and mx > 0) and mx or 1000
  d.cur = floor(d.mx * P("sampleXP"))
  local r = GetXPExhaustion and GetXPExhaustion()
  d.rested = (r and r > 0) and r or floor(d.mx * 0.12)
  d.isMax = false
  ns.TipShow(ns.root or UIParent, d, "preview", restart and true or false, true)
end
