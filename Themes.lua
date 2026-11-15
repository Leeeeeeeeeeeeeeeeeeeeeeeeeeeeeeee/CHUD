local ADDON, ns = ...

-- A theme is a snapshot of the "look": every color and layout/behavior key, except things
-- that are not part of a look (position, width, lock state, the CPU setting, the themes list itself).
local EXCLUDE = { locked = true, optimize = true, glitchFx = true, xpPulse = true, width = true }
local KEYS = {}
for _, list in ipairs({ ns.COLOR_KEYS, ns.BEHAVIOR_KEYS }) do
  for _, k in ipairs(list) do
    if not EXCLUDE[k] then KEYS[#KEYS + 1] = k end
  end
end
ns.THEME_KEYS = KEYS

-- Palettes ---------------------------------------------------------------------------------
-- A theme is described by a few colors; everything else is derived so themes stay consistent:
--   bg      background tint (gradient center at `alpha`, fading to transparent at the edges)
--   accent  E/S/W letters and center marker (override the marker with `marker`)
--   text    numbers, diagonals and the degree readout; ticks use it at lower opacity
--   north   the N letter           xp   the XP bar fill
local function Palette(p)
  local bg, ac, tx = p.bg, p.accent, p.text
  return {
    bgSolid = { bg[1], bg[2], bg[3], 0.55 },
    bgCenter = { bg[1], bg[2], bg[3], p.alpha or 0.90 },
    bgEdge = { bg[1], bg[2], bg[3], 0.00 },
    textColor = { tx[1], tx[2], tx[3], 1 },
    cardinalColor = { ac[1], ac[2], ac[3], 1 },
    northColor = { p.north[1], p.north[2], p.north[3], 1 },
    tickColor = { tx[1], tx[2], tx[3], 0.55 },
    markerColor = { (p.marker or ac)[1], (p.marker or ac)[2], (p.marker or ac)[3], 1 },
    degreeColor = { tx[1], tx[2], tx[3], 1 },
    xpColor = { p.xp[1], p.xp[2], p.xp[3], 1 },
    outlineColor = { 0, 0, 0, 1 },
    mk_color = { ac[1], ac[2], ac[3], 1 },        -- marker icons take the theme's accent
    edgeColor = { ac[1], ac[2], ac[3], 0.9 },        -- hairline edge lines use the accent
  }
end

-- Palette plus optional layout/behavior overrides (marker style, XP bar height, ...).
local function Theme(p, extra)
  local t = Palette(p)
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end

-- Thin solid bar: no ticks or diagonals, degrees inside the bar, notch marker.
-- Keeps the base theme's colors and font, but resets the layout so all Minimal variants match.
local function MinimalOf(base, solid)
  local t = ns.Copy(base)
  t.bgMode = "solid"; t.bgSolid = solid
  t.height = 30; t.fontSize = 14; t.span = 180
  t.fadeEdges = true; t.fadeAmount = 0.5
  t.flipTicks = false
  t.showTicks = false; t.showIntercardinals = false
  t.showDegrees = (base.showDegrees == true); t.degreeInline = true; t.showNumbers = (base.showNumbers == true)
  t.markerStyle = "notch"
  return t
end

-- Faction-aware defaults ---------------------------------------------------------------------
-- The default look follows the character's faction. This runs at ADDON_LOADED, before saved
-- variables are merged, so a fresh install, "Reset", and the built-in Default theme all agree.
local WARM_WHITE = { 1.00, 0.96, 0.85 }    -- North in the default look: set apart without clashing
local FACTION = {
  Alliance = Palette({ bg = { 0.05, 0.09, 0.18 }, alpha = 0.88, accent = { 0.96, 0.78, 0.30 },
    text = { 0.92, 0.94, 0.98 }, north = WARM_WHITE, xp = { 0.25, 0.50, 0.95 } }),
  Horde = Palette({ bg = { 0.16, 0.05, 0.05 }, alpha = 0.88, accent = { 0.95, 0.72, 0.25 },
    marker = { 0.90, 0.25, 0.18 }, text = { 0.96, 0.91, 0.88 }, north = WARM_WHITE, xp = { 0.80, 0.15, 0.12 } }),
  Neutral = Palette({ bg = { 0.08, 0.08, 0.10 }, alpha = 0.88, accent = { 1.00, 0.82, 0.00 },
    text = { 0.95, 0.95, 0.95 }, north = WARM_WHITE, xp = { 0.58, 0.00, 0.55 } }),
}
function ns.ApplyFactionDefaults()
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  local pal = FACTION[faction] or FACTION.Neutral
  for k, v in pairs(pal) do ns.defaults[k] = ns.Copy(v) end
end

-- Built-in themes (cannot be deleted). Default is empty: it is the faction-aware defaults.
ns.BuiltinNames = { "Default", "Dark", "High Contrast", "Assassins", "Alliance", "Horde", "UNSC", "Nordic", "Azeroth", "Pink",
  "Tactical", "Tactical Minimal", "Frost", "Frost Minimal", "Ember", "Ember Minimal" }

-- Fonts that ship with the game, so themes can use them without any other addon.
local ARIAL    = { fontName = "Arial Narrow",  fontPath = "Fonts\\ARIALN.TTF" }
local MORPHEUS = { fontName = "Morpheus",      fontPath = "Fonts\\MORPHEUS.ttf" }
local function With(font, t) for k, v in pairs(font) do t[k] = v end return t end

-- Each theme pairs a palette with a different mix of features:
--   Dark      crisp solid bar, short fade          Assassins light plate, no outline, XP on top
--   Alliance  tighter view, chunkier XP bar        Horde     flipped: ticks on top, notch marker
--   UNSC      amber on olive, narrow font, notch
--   Nordic    very soft edges, quiet, narrow font  Azeroth   fantasy font, big gold XP bar
--   Pink      wide view, spotlight fade           Tactical  solid HUD plate, narrow font, notch
--   Frost     full 360 degree view, soft fade      Ember     tall bar with large letters
local BUILTIN = {
  Default = {},
  Dark = Theme({ bg = { 0.05, 0.05, 0.05 }, accent = { 0.92, 0.92, 0.92 },
    text = { 0.80, 0.80, 0.80 }, north = { 0.85, 0.30, 0.30 }, xp = { 0.45, 0.45, 0.52 } },
    { bgMode = "solid", bgSolid = { 0.04, 0.04, 0.04, 0.90 }, fadeEdges = true, fadeAmount = 0.30 }),
  -- High Contrast: opaque black plate, pure white letters and ticks, yellow cardinals, red North,
  -- larger text, degrees and numbers on, and a bright green XP fill. Meant for readability over any scene.
  ["High Contrast"] = Theme({ bg = { 0, 0, 0 }, accent = { 1.00, 0.90, 0.00 },
    text = { 1, 1, 1 }, north = { 1.00, 0.30, 0.25 }, xp = { 0.20, 1.00, 0.40 } },
    { bgMode = "solid", bgSolid = { 0, 0, 0, 1 }, tickColor = { 1, 1, 1, 1 }, fadeEdges = true, fadeAmount = 0.20,
      fontSize = 16, height = 40, span = 150, markerStyle = "short", showDegrees = true, showNumbers = true,
      mk_size = 18 }),
  -- Assassins: a light plate with dark text and no text outline. The center stays crisp; only
  -- the outer 35% of each half fades.
  Assassins = Theme({ bg = { 0.95, 0.94, 0.89 }, accent = { 0.10, 0.20, 0.45 },
    text = { 0.12, 0.12, 0.16 }, north = { 0.75, 0.10, 0.10 }, xp = { 0.20, 0.45, 0.85 } },
    { bgMode = "solid", bgSolid = { 0.95, 0.94, 0.89, 0.67 }, fadeEdges = true, fadeAmount = 0.35,
      outlineWidth = 0, markerStyle = "notch",
      mk_color = { 0.769, 0.035, 0.122, 1 } }),   -- icon color #C4091F
  Alliance = Theme({ bg = { 0.04, 0.10, 0.25 }, accent = { 1.00, 0.82, 0.20 },
    text = { 0.90, 0.93, 1.00 }, north = { 1, 1, 1 }, xp = { 0.20, 0.45, 0.95 } },
    { span = 150, fadeAmount = 0.40, outlineWidth = 1, outlineColor = { 0.02, 0.05, 0.15, 1 } }),
  Horde = Theme({ bg = { 0.25, 0.04, 0.04 }, accent = { 0.90, 0.15, 0.10 },
    text = { 0.95, 0.85, 0.80 }, north = { 1.00, 0.75, 0.20 }, xp = { 0.75, 0.10, 0.10 } },
    { flipTicks = true, markerStyle = "notch", outlineWidth = 1, outlineColor = { 0.12, 0.02, 0.02, 1 } }),
  UNSC = Theme({ bg = { 0.08, 0.10, 0.07 }, accent = { 1.00, 0.72, 0.15 },
    text = { 0.78, 0.85, 0.70 }, north = { 1.00, 0.40, 0.15 }, xp = { 0.55, 0.78, 0.30 } },
    With(ARIAL, { bgMode = "solid", bgSolid = { 0.07, 0.09, 0.06, 0.88 }, fadeAmount = 0.25, height = 34,
      span = 130, markerStyle = "notch", showDegrees = true, showNumbers = true })),
  Nordic = Theme({ bg = { 0.12, 0.15, 0.18 }, accent = { 0.55, 0.70, 0.78 },
    text = { 0.82, 0.87, 0.90 }, north = { 0.75, 0.40, 0.35 }, xp = { 0.45, 0.62, 0.70 } },
    With(ARIAL, { markerStyle = "notch", showIntercardinals = false, fadeAmount = 0.80 })),
  Azeroth = Theme({ bg = { 0.28, 0.20, 0.10 }, accent = { 1.00, 0.82, 0.00 },
    text = { 0.95, 0.88, 0.70 }, north = { 0.90, 0.25, 0.15 }, xp = { 0.90, 0.65, 0.15 } },
    With(MORPHEUS, { height = 42, fontSize = 15, span = 140, outlineWidth = 1, outlineColor = { 0.12, 0.07, 0.02, 1 }, mk_size = 18 })),
  Pink = Theme({ bg = { 0.35, 0.10, 0.25 }, accent = { 1.00, 0.50, 0.75 },
    text = { 1.00, 0.90, 0.95 }, north = { 1, 1, 1 }, xp = { 1.00, 0.40, 0.70 } },
    { span = 240, fadeAmount = 1.00, markerStyle = "notch", outlineWidth = 1, outlineColor = { 0.20, 0.03, 0.12, 1 } }),
  Tactical = Theme({ bg = { 0.04, 0.12, 0.05 }, accent = { 0.30, 1.00, 0.30 },
    text = { 0.70, 1.00, 0.70 }, north = { 1.00, 0.25, 0.20 }, xp = { 0.30, 0.90, 0.30 } },
    With(ARIAL, { bgMode = "solid", bgSolid = { 0.03, 0.10, 0.04, 0.80 }, fadeEdges = true, fadeAmount = 0.25, height = 32,
      span = 120, markerStyle = "notch", showDegrees = true, showNumbers = true })),
  Frost = Theme({ bg = { 0.05, 0.12, 0.20 }, accent = { 0.45, 0.80, 1.00 },
    text = { 0.85, 0.95, 1.00 }, north = { 1, 1, 1 }, xp = { 0.30, 0.65, 1.00 } },
    { span = 360, fadeAmount = 0.90, outlineWidth = 1, outlineColor = { 0.01, 0.05, 0.12, 1 } }),
  Ember = Theme({ bg = { 0.18, 0.06, 0.02 }, accent = { 1.00, 0.55, 0.15 },
    text = { 1.00, 0.90, 0.80 }, north = { 1.00, 0.20, 0.10 }, xp = { 1.00, 0.45, 0.10 } },
    { height = 44, fontSize = 16, mk_size = 18, outlineWidth = 1, outlineColor = { 0.12, 0.02, 0.00, 1 } }),
}
BUILTIN["Tactical Minimal"] = MinimalOf(BUILTIN.Tactical, { 0.02, 0.08, 0.03, 0.45 })
BUILTIN["Frost Minimal"]    = MinimalOf(BUILTIN.Frost,    { 0.03, 0.08, 0.14, 0.45 })
BUILTIN["Ember Minimal"]    = MinimalOf(BUILTIN.Ember,    { 0.12, 0.04, 0.01, 0.45 })

local function Equal(a, b)
  if type(a) == "table" and type(b) == "table" then
    for k, v in pairs(a) do if not Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
  elseif type(a) == "number" and type(b) == "number" then
    return math.abs(a - b) < 0.0005          -- slider/color-picker floats
  end
  return a == b
end

function ns.IsBuiltin(name) return BUILTIN[name] ~= nil end

-- Full key set for a theme. Missing keys fall back to defaults, so themes saved by an older
-- version still work after new settings are added.
function ns.GetThemeData(name)
  local src = BUILTIN[name] or (ns.db.themes and ns.db.themes[name])
  if not src then return nil end
  local data = {}
  for _, k in ipairs(KEYS) do
    local v = src[k]
    if v == nil then v = ns.defaults[k] end
    data[k] = ns.Copy(v)
  end
  return data
end

function ns.UserThemeNames()
  local names = {}
  for n in pairs(ns.db.themes or {}) do names[#names + 1] = n end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  return names
end

function ns.SnapshotTheme()
  local snap = {}
  for _, k in ipairs(KEYS) do snap[k] = ns.Copy(ns.db[k]) end
  return snap
end

-- Name of the saved/built-in theme the current settings equal, or nil if they match none.
function ns.MatchTheme()
  local snap = ns.SnapshotTheme()
  for _, n in ipairs(ns.BuiltinNames) do
    if Equal(snap, ns.GetThemeData(n)) then return n end
  end
  for _, n in ipairs(ns.UserThemeNames()) do
    if Equal(snap, ns.GetThemeData(n)) then return n end
  end
  return nil
end

function ns.ApplyTheme(name)
  local data = ns.GetThemeData(name)
  if not data then return end
  for _, k in ipairs(KEYS) do ns.db[k] = data[k] end
  ns.Apply()
  if ns.RefreshSettings then ns.RefreshSettings() end
end

function ns.SaveTheme(name)
  ns.db.themes = ns.db.themes or {}
  ns.db.themes[name] = ns.SnapshotTheme()
  if ns.OnSettingsChanged then ns.OnSettingsChanged() end
end

function ns.DeleteTheme(name)
  if BUILTIN[name] then return end            -- built-ins are protected
  if ns.db.themes then ns.db.themes[name] = nil end
  if ns.OnSettingsChanged then ns.OnSettingsChanged() end
end
