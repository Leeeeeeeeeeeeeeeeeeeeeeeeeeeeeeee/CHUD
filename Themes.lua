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
  "Tactical", "Tactical Minimal", "Frost", "Frost Minimal", "Ember", "Ember Minimal",
  "Catppuccin", "Tokyo Night" }

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

-- Catppuccin Mocha and Tokyo Night: two of the most used editor palettes right now. The colors are their
-- published base, text and accent values; only the colors are borrowed.
BUILTIN.Catppuccin = Theme({ bg = { 0.118, 0.118, 0.180 }, accent = { 0.796, 0.651, 0.969 },
  text = { 0.804, 0.839, 0.957 }, north = { 0.953, 0.545, 0.659 }, xp = { 0.537, 0.706, 0.980 } },
  { bgMode = "solid", bgSolid = { 0.118, 0.118, 0.180, 0.92 }, fadeEdges = true, fadeAmount = 0.30,
    markerStyle = "notch", outlineWidth = 1, outlineColor = { 0.07, 0.07, 0.11, 1 } })
BUILTIN["Tokyo Night"] = Theme({ bg = { 0.102, 0.106, 0.149 }, accent = { 0.478, 0.635, 0.969 },
  text = { 0.753, 0.792, 0.961 }, north = { 0.969, 0.463, 0.557 }, xp = { 0.733, 0.604, 0.969 } },
  { fadeAmount = 0.50, showDegrees = true, outlineWidth = 1, outlineColor = { 0.04, 0.04, 0.08, 1 } })

-- Daylight is a toggle, not a theme: while it is on, the colors follow the game's clock in half-hour steps and the color
-- controls are locked. Turning it off puts back the colors the player had. Each keyframe is { hour, bg, accent, text,
-- north, xp }; the half-hour in between is blended from its two neighbours.
local DAY = {
  { 0.0,  { 0.03, 0.04, 0.10 }, { 0.55, 0.62, 0.95 }, { 0.80, 0.84, 0.95 }, { 0.95, 0.55, 0.60 }, { 0.35, 0.40, 0.85 } },  -- midnight
  { 5.5,  { 0.18, 0.10, 0.18 }, { 1.00, 0.62, 0.45 }, { 1.00, 0.90, 0.85 }, { 1.00, 0.85, 0.60 }, { 0.95, 0.50, 0.40 } },  -- dawn
  { 8.0,  { 0.10, 0.16, 0.24 }, { 1.00, 0.85, 0.45 }, { 0.95, 0.96, 1.00 }, { 1.00, 1.00, 0.90 }, { 0.40, 0.70, 0.95 } },  -- morning
  { 12.0, { 0.08, 0.20, 0.32 }, { 1.00, 0.92, 0.55 }, { 1.00, 1.00, 1.00 }, { 1.00, 0.95, 0.80 }, { 0.30, 0.75, 1.00 } },  -- noon
  { 17.0, { 0.24, 0.13, 0.06 }, { 1.00, 0.70, 0.25 }, { 1.00, 0.93, 0.80 }, { 1.00, 0.85, 0.50 }, { 1.00, 0.60, 0.20 } },  -- golden hour
  { 19.5, { 0.20, 0.08, 0.22 }, { 0.95, 0.50, 0.60 }, { 1.00, 0.88, 0.92 }, { 1.00, 0.75, 0.55 }, { 0.80, 0.35, 0.60 } },  -- dusk
  { 22.0, { 0.05, 0.06, 0.14 }, { 0.60, 0.65, 1.00 }, { 0.82, 0.86, 0.98 }, { 0.95, 0.55, 0.60 }, { 0.40, 0.45, 0.90 } },  -- night
  { 24.0, { 0.03, 0.04, 0.10 }, { 0.55, 0.62, 0.95 }, { 0.80, 0.84, 0.95 }, { 0.95, 0.55, 0.60 }, { 0.35, 0.40, 0.85 } },  -- midnight again
}
local function Mix(a, b, f)
  return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f }
end
-- The half-hour of the game's day (0-47). GetGameTime is the realm clock the in-game UI shows.
local function DayBucket()
  local h, m = 12, 0
  if GetGameTime then
    local ok, hh, mm = pcall(GetGameTime)
    if ok and type(hh) == "number" and type(mm) == "number" then h, m = hh, mm end
  end
  return h * 2 + (m >= 30 and 1 or 0)
end
local function DaylightPalette(bucket)
  local t = bucket / 2
  local a, b = DAY[1], DAY[#DAY]
  for i = 1, #DAY - 1 do
    if t >= DAY[i][1] and t <= DAY[i + 1][1] then a, b = DAY[i], DAY[i + 1]; break end
  end
  local f = (t - a[1]) / max(b[1] - a[1], 0.001)
  return Palette({ bg = Mix(a[2], b[2], f), accent = Mix(a[3], b[3], f), text = Mix(a[4], b[4], f),
    north = Mix(a[5], b[5], f), xp = Mix(a[6], b[6], f) })
end

-- Daylight changes colors only. Icon color (mk_color) is left alone: it has its own control in the marker menu.
local function ApplyDaylightColors()
  local bucket = DayBucket()
  for k, v in pairs(DaylightPalette(bucket)) do
    if k ~= "mk_color" then ns.db[k] = v end
  end
  ns.db.dayBucket = bucket
end

function ns.DaylightOn() return ns.db and ns.db.daylight == true end
function ns.SetDaylight(on)
  local db = ns.db
  if on and not db.daylight then
    local keep = {}
    for _, k in ipairs(ns.COLOR_KEYS) do keep[k] = ns.Copy(db[k]) end
    db.preDaylight, db.daylight = keep, true
    ApplyDaylightColors()
  elseif not on and db.daylight then
    for k, v in pairs(db.preDaylight or {}) do db[k] = ns.Copy(v) end
    db.preDaylight, db.daylight, db.dayBucket = nil, nil, nil
  end
  ns.Apply()
  if ns.RefreshSettings then ns.RefreshSettings() end
end

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
  ns.db.daylight, ns.db.preDaylight, ns.db.dayBucket = nil, nil, nil   -- a theme sets every color itself, so Daylight turns off
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

-- /chud daydemo: sweeps the Daylight colors through a whole day in DEMO_SECONDS, with a clock under the bar, for
-- recording a GIF. It loops until you run the command again, which puts your own colors (or the live Daylight colors) back.
-- One caption shared by both demos, sitting under the bar. It has its own frame in a high strata so nothing the bar
-- draws can cover it, and an outlined font so it reads over any background.
local captionFS
local function Caption(text)
  if not captionFS then
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetAllPoints(UIParent)
    captionFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    captionFS:SetFont(STANDARD_TEXT_FONT, 22, "OUTLINE")
    captionFS:SetPoint("TOP", ns.root, "BOTTOM", 0, -14)
    captionFS:SetTextColor(1, 1, 1)
    captionFS.frame = f
  end
  captionFS:SetText(text or "")
  captionFS.frame:SetShown(text ~= nil)
end

local DEMO_SECONDS = 16
local demo = CreateFrame("Frame")
demo:Hide()
local demoSaved, demoT
demo:SetScript("OnUpdate", function(self, elapsed)
  demoT = demoT + elapsed
  if demoT >= DEMO_SECONDS then demoT = demoT - DEMO_SECONDS end   -- loops until stopped
  local hour = demoT / DEMO_SECONDS * 24
  for k, v in pairs(DaylightPalette(hour * 2)) do
    if k ~= "mk_color" then ns.db[k] = v end
  end
  ns.Apply()
  Caption(format("%02d:%02d", floor(hour), floor((hour % 1) * 60 / 30) * 30))   -- half-hour steps, like the real thing
end)
function ns.StopDaylightDemo()
  if not demoSaved then return end
  demo:Hide()
  for k, v in pairs(demoSaved) do ns.db[k] = v end
  demoSaved = nil
  Caption(nil)
  if ns.db.daylight then ApplyDaylightColors() end   -- if Daylight is on, go straight back to the current time's colors
  ns.Apply()
  if ns.RefreshSettings then ns.RefreshSettings() end
end
function ns.DaylightDemo()
  if demoSaved then ns.StopDaylightDemo(); return end
  if ns.StopThemeDemo then ns.StopThemeDemo() end
  demoSaved = {}
  for _, k in ipairs(ns.COLOR_KEYS) do demoSaved[k] = ns.Copy(ns.db[k]) end
  demoT = 0
  Caption("00:00")
  demo:Show()
end

-- /chud themedemo: shows every built-in theme in turn, THEME_SECONDS each, with its name under the bar, for recording a
-- GIF. It loops until you run the command again, which puts everything back (including Daylight if it was on).
local THEME_SECONDS = 2
local tdemo = CreateFrame("Frame")
tdemo:Hide()
local tdSaved, tdT, tdIndex
tdemo:SetScript("OnUpdate", function(_, elapsed)
  tdT = tdT + elapsed
  if tdT < THEME_SECONDS then return end
  tdT = 0
  tdIndex = tdIndex + 1
  if tdIndex > #ns.BuiltinNames then tdIndex = 1 end   -- loops until stopped
  local name = ns.BuiltinNames[tdIndex]
  Caption(name)   -- first, so the name shows even if applying the theme hits a problem
  local ok, err = pcall(ns.ApplyTheme, name)
  if not ok then print("|cffd9bf4dCHUD:|r theme demo could not apply " .. name .. ": " .. tostring(err)) end
end)
function ns.StopThemeDemo()
  if not tdSaved then return end
  tdemo:Hide()
  Caption(nil)
  for k, v in pairs(tdSaved.snap) do ns.db[k] = v end
  ns.db.daylight, ns.db.preDaylight, ns.db.dayBucket = tdSaved.daylight, tdSaved.pre, tdSaved.bucket
  tdSaved = nil
  ns.Apply()
  if ns.RefreshSettings then ns.RefreshSettings() end
end
function ns.ThemeDemo()
  if tdSaved then ns.StopThemeDemo(); return end
  if demoSaved then ns.StopDaylightDemo() end
  tdSaved = { snap = ns.SnapshotTheme(), daylight = ns.db.daylight, pre = ns.db.preDaylight, bucket = ns.db.dayBucket }
  tdIndex, tdT = 0, THEME_SECONDS   -- the first theme shows on the next frame
  Caption("")
  tdemo:Show()
end

-- Keeps Daylight in step with the game clock: when the half-hour has changed, the new colors are applied. The first check
-- runs right away (so login catches up), then one every 30 real seconds.
local dayAcc = 30
local dayFrame = CreateFrame("Frame")
dayFrame:SetScript("OnUpdate", function(_, elapsed)
  dayAcc = dayAcc + elapsed
  if dayAcc < 30 then return end
  local db = ns.db
  if not db then return end
  dayAcc = 0
  if db.daylight and not demoSaved and not tdSaved and db.dayBucket ~= DayBucket() then
    ApplyDaylightColors()
    ns.Apply()
    if ns.RefreshSettings then ns.RefreshSettings() end
  end
end)
