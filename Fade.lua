local ADDON, ns = ...

-- Fade: lets the bar fade out when it is not needed and come back when it is.
--
-- It is off by default. When "Fade Out When Idle" is on, the bar fades to the Faded Opacity unless one of the situations ticked
-- in "Show When" is happening: you are in combat, the map or quest log is open, the mouse is over the bar or the minimap,
-- you are running by hand, you are autorunning (or following, or on a flight path), or you are dead. The bar always stays fully shown while the settings or
-- marker menu is open and while it is unlocked for moving, so it can be set up. Master Opacity applies all the time, fade or not.
--
-- Only the opacity of the bar's frame (and the Next Node arrow beside it) changes. Nothing is hidden, so markers, the XP bar and the tooltip keep working underneath.

local HOLD = 1.5       -- seconds the bar stays up after the last reason to show it ends
local FADE_IN = 0.18   -- seconds to come back to full opacity
local FADE_OUT = 0.8   -- seconds to fade away
local POLL = 0.1       -- how often the situations are checked

-- Frames whose being open means "the map or quest log is open" (whichever of these exist on this client).
local WINDOWS = { "WorldMapFrame", "QuestLogFrame", "QuestMapFrame" }

local cur = 1          -- the opacity applied now
local lastWanted = 0   -- GetTime() when a reason to show the bar was last seen
local acc = POLL

local function Shown(name)
  local f = _G[name]
  return f and f.IsShown and f:IsShown() or false
end

-- True while the settings or marker menu is open or the bar is unlocked, so it can be set up without fading away.
local function Editing()
  local db = ns.db
  return not db.locked or Shown("CHUDMarkerMenu") or (Shown("CHUDInstall") and not (ns.TourOnFadePage and ns.TourOnFadePage())) or Shown("SettingsPanel") or Shown("InterfaceOptionsFrame")
end

-- True while a movement key is held or both mouse buttons are down (steering by hand).
local MOVE_BINDINGS = { "MOVEFORWARD", "MOVEBACKWARD", "STRAFELEFT", "STRAFERIGHT" }
local function HandsOn()
  if IsMouseButtonDown and IsMouseButtonDown("LeftButton") and IsMouseButtonDown("RightButton") then return true end
  if not (GetBindingKey and IsKeyDown) then return false end
  for _, name in ipairs(MOVE_BINDINGS) do
    local k1, k2 = GetBindingKey(name)
    if (k1 and IsKeyDown(k1)) or (k2 and IsKeyDown(k2)) then return true end
  end
  return false
end

local lastMoving = false   -- the last readable answer to "is the player moving?"
-- True when something ticked in "Show When" is happening.
local function Wanted()
  local db = ns.db
  if db.fadeCombat and (InCombatLockdown() or (UnitAffectingCombat and UnitAffectingCombat("player"))) then return true end
  if db.fadeMap then
    for _, name in ipairs(WINDOWS) do if Shown(name) then return true end end
  end
  if db.fadeMouse then
    if ns.root and ns.root:IsMouseOver() then return true end
    if Minimap and Minimap.IsMouseOver and Minimap:IsMouseOver() then return true end
  end
  if (db.fadeRun or db.fadeAuto) and GetUnitSpeed then
    -- The game has no autorun check, so autorun is moving with no movement key or mouse steering held. Following another
    -- player and flight paths move you the same way, so they count as autorun too.
    local ok, speed = pcall(GetUnitSpeed, "player")
    -- In combat the game can hand back a secret value that addons may not compare; then the last readable answer is kept, so
    -- starting a fight while running does not change the bar.
    local readable = ok and type(speed) == "number" and not (issecretvalue and issecretvalue(speed))
    local taxi = false
    if UnitOnTaxi then
      local ok2, v = pcall(UnitOnTaxi, "player")
      taxi = ok2 and not (issecretvalue and issecretvalue(v)) and v and true or false
    end
    local moving
    if readable then moving = speed > 0 or taxi; lastMoving = moving else moving = lastMoving end
    if moving then
      if HandsOn() then
        if db.fadeRun then return true end
      elseif db.fadeAuto then
        return true
      end
    end
  end
  if db.fadeDead and UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return true end
  return false
end

-- The opacity the bar should have right now.
local function Target()
  local db = ns.db
  local master = db.masterAlpha or 1
  if not db.fadeOn or Editing() then return master end
  if Wanted() then lastWanted = GetTime() end
  if GetTime() - lastWanted < HOLD then return master end
  return math.min(db.fadeAlpha or 0, master)
end

local f = CreateFrame("Frame")
local target = 1
f:SetScript("OnUpdate", function(_, elapsed)
  if not (ns.db and ns.root) then return end
  acc = acc + elapsed
  if acc >= POLL then acc = 0; target = Target() end
  if cur == target then return end
  -- linear steps: a full 0-to-1 change takes FADE_IN going up and FADE_OUT going down
  local step = elapsed / (target > cur and FADE_IN or FADE_OUT)
  if target > cur then cur = math.min(target, cur + step) else cur = math.max(target, cur - step) end
  ns.root:SetAlpha(cur)
  ns.barAlpha = cur
  if ns.SetHintAlpha then ns.SetHintAlpha(cur) end   -- the arrow beside the bar is its own frame
end)
