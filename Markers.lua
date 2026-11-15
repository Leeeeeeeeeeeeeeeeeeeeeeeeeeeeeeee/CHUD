local ADDON, ns = ...

-- Markers: icons on the compass that point toward quests, rares/treasures and gathering spots.
--
-- Data sources (all queried with pcall; a missing or changed API just means no markers of that kind):
--   tracked   super-tracked quest waypoint, or the map waypoint you are tracking
--   objective quests in your log that have a POI on the current map (turn-ins use the same option)
--   giver     quests you could pick up here
--   (When Questie is installed its map icons replace the game's own quest POIs for objective / turn-in / giver.)
--   rare / treasure   "vignettes": the game's own rare/treasure/event markers
--   herb / ore / box  spots RECORDED when you gather. There is no API for live nodes, so these
--                     are places you have gathered before, not nodes that exist right now.
--
-- How a bearing is found: the player's and the target's position on one map, scaled by that map's
-- size in yards, gives a vector. bearing = atan2(east, north). Targets on another map are moved
-- onto the player's map through world coordinates, so no world-axis conventions are needed.

-- If the game ever drops one of these API tables, an empty stand-in keeps every call below harmless
-- (Try() skips a missing function) instead of raising an error.
local C_Map, C_QuestLog, C_VignetteInfo = C_Map or {}, C_QuestLog or {}, C_VignetteInfo or {}

local floor, abs, min, max, sqrt = math.floor, math.abs, math.min, math.max, math.sqrt
local deg = math.deg
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local MAX_ICONS = 24
local FOCUS_SCALE = 1.3   -- the focused (primary) icon is this much larger than a normal one, but never taller than the bar
local FADE_SHRINK = 0.30  -- a quest giver or objective at its fade distance is this much smaller than normal ...
local FADE_ALPHA = 0.50    -- ... and this much more transparent (both ease in with distance)
-- Which setting holds the fade distance for each kind, and its default (yards).
local FADE_RANGE = { giver = { "mk_giverRange", 300 }, objective = { "mk_objRange", 300 } }
local FAR_SCALE = 0.6     -- an icon at its maximum range is this fraction of normal size (when Smaller When Far is on)
local TICK = 0.25       -- seconds between bearing updates
local REFRESH = 4.0     -- seconds between full re-queries (events and the Questie callback also trigger one)
local MAX_NODES = 500   -- recorded spots kept per kind per map
local DEDUPE = 15       -- yards: a new gather within this of a recorded spot is the same spot

-- Which setting turns each kind on.
local OPTION = {
  tracked = "mk_tracked", objective = "mk_objectives", turnin = "mk_objectives", giver = "mk_givers",
  rare = "mk_rares", treasure = "mk_treasures", herb = "mk_herbs", ore = "mk_ore", box = "mk_containers",
}

-- Icons: atlases are tried in order, then the fallback file. Vignettes bring their own atlas.
local ICON = {
  tracked   = { atlases = { "Waypoint-MapPin-Tracked", "Waypoint-MapPin-ChatIcon" }, file = "Interface\\Icons\\INV_Misc_Map_01", crop = true },
  objective = { atlases = { "QuestObjective", "QuestNormal" }, file = "Interface\\GossipFrame\\AvailableQuestIcon" },
  turnin    = { atlases = { "QuestTurnin" }, file = "Interface\\GossipFrame\\ActiveQuestIcon" },
  giver     = { atlases = { "QuestNormal" }, file = "Interface\\GossipFrame\\AvailableQuestIcon" },
  rare      = { atlases = { "VignetteKill" }, file = "Interface\\Icons\\INV_Misc_Bone_Skull_01", crop = true },
  treasure  = { atlases = { "VignetteLoot" }, file = "Interface\\Icons\\INV_Misc_Bag_10", crop = true },
  herb      = { file = "Interface\\Icons\\Trade_Herbalism", crop = true },
  ore       = { file = "Interface\\Icons\\Trade_Mining", crop = true },
  box       = { file = "Interface\\Icons\\INV_Box_01", crop = true },
}

local targets = {}   -- every candidate: { kind, mapID, x, y, label, atlas?, primary? }
local active = {}    -- candidates in range this tick, primary first then nearest first
local icons = {}     -- frame pool
local needRebuild = true

local function Try(fn, ...)
  if type(fn) ~= "function" then return end
  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end
end
local function Num(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) end
local function On(kind) local db = ns.db; return db and db[OPTION[kind]] end
local function AnyOn()
  local db = ns.db
  if not db then return false end
  for _, key in pairs(OPTION) do if db[key] then return true end end
  return false
end
local function XY(vec)
  if not vec then return end
  local ok, x, y = pcall(vec.GetXY, vec)
  if ok and Num(x) and Num(y) then return x, y end
end

-- Questie ------------------------------------------------------------------------------------
-- When Questie is installed, its map icons are the source for quest objectives, turn-ins and quest
-- givers. Questie's public API (Questie.API) only offers readiness and quest-change callbacks, so
-- icon positions come from its map frame registry (QuestieMap.questIdFrames). That table is internal
-- to Questie: every access is guarded, so if it changes, Questie support quietly turns itself off
-- and the game's own quest data is used instead.
-- CHUD only READS Questie's data. The one thing it hands Questie is a callback through Questie's own
-- RegisterForQuestUpdates, which is how Questie asks other addons to listen.
local Q = { map = nil, kinds = nil, hooked = false }
local qcache = setmetatable({}, { __mode = "k" })   -- Questie icon frame -> its reusable target table
local questieActive = false

local function QuestieReady()
  local Qe = _G.Questie
  if not (type(Qe) == "table" and type(Qe.API) == "table" and Qe.API.isReady) then return end
  if not Q.map then
    local L = _G.QuestieLoader
    if type(L) == "table" and L.ImportModule then
      Q.map = Try(L.ImportModule, L, "QuestieMap")
    end
    if type(Q.map) ~= "table" then Q.map = nil; return end
  end
  if not Q.kinds then
    -- Questie icon type number -> the marker kind CHUD uses. Types not listed (glows, nodes, chests...) are ignored.
    local k = {}
    local function set(names, kind)
      for _, n in ipairs(names) do
        local v = Qe[n]
        if type(v) == "number" then k[v] = kind end
      end
    end
    set({ "ICON_TYPE_AVAILABLE", "ICON_TYPE_AVAILABLE_GRAY", "ICON_TYPE_REPEATABLE", "ICON_TYPE_EVENTQUEST",
      "ICON_TYPE_PVPQUEST" }, "giver")
    set({ "ICON_TYPE_COMPLETE", "ICON_TYPE_REPEATABLE_COMPLETE", "ICON_TYPE_EVENTQUEST_COMPLETE",
      "ICON_TYPE_PVPQUEST_COMPLETE" }, "turnin")
    set({ "ICON_TYPE_SLAY", "ICON_TYPE_LOOT", "ICON_TYPE_EVENT", "ICON_TYPE_OBJECT", "ICON_TYPE_TALK",
      "ICON_TYPE_INTERACT" }, "objective")
    Q.kinds = k
  end
  if not Q.hooked then
    Q.hooked = true
    -- Questie tells us when a quest is accepted, updated, turned in or abandoned.
    Try(Qe.API.RegisterForQuestUpdates, function()
      needRebuild = true
      -- Questie draws its icons a moment after the event, so look again shortly after.
      if C_Timer and C_Timer.After then C_Timer.After(1, function() needRebuild = true end) end
    end)
  end
  return Qe
end

local function UseQuestie() return ns.db and ns.db.mk_questie ~= false and QuestieReady() end

-- The quest the player has focused. The game's super-tracked quest is the single source of truth: Questie
-- follows it, and so does CHUD, so the two can never disagree. Questie's own focus (read only) is used just
-- when the client has no super-tracking at all.
local function FocusedQuest()
  local ST = C_SuperTrack
  if ST and type(ST.GetSuperTrackedQuestID) == "function" then
    local sq = Try(ST.GetSuperTrackedQuestID)
    if Num(sq) and sq > 0 then return sq end
    return nil
  end
  local Qe = _G.Questie
  local f = type(Qe) == "table" and type(Qe.db) == "table" and type(Qe.db.char) == "table" and Qe.db.char.TrackerFocus
  if Num(f) and f > 0 then return f end
end

-- Does the client tell us whether the player is inside a quest's area (the blue blob on the map)?
-- C_Minimap.IsInsideQuestBlob is how retail reports it; if this client lacks it, the glow just never shows.
local function AreaApi()
  return C_Minimap and type(C_Minimap.IsInsideQuestBlob) == "function"
end
ns.QuestAreaSupported = AreaApi

-- Target collection (runs on events and every REFRESH seconds) ----------------------------------

-- The player's map, plus up to two parent zone maps, so quests shown on the zone map are found
-- while standing in a sub-area. Stops before continent level.
local function MapChain(mapID)
  local list, cur = { mapID }, mapID
  for _ = 1, 2 do
    local info = Try(C_Map.GetMapInfo, cur)
    if not info or not info.parentMapID or info.parentMapID == 0 then break end
    local pinfo = Try(C_Map.GetMapInfo, info.parentMapID)
    if not pinfo or (pinfo.mapType and pinfo.mapType <= 2) then break end   -- 2 = continent
    cur = info.parentMapID
    list[#list + 1] = cur
  end
  return list
end

local function QuestWaypoint(qid, pm)
  local a, b, c = Try(C_QuestLog and C_QuestLog.GetNextWaypoint, qid)
  if Num(a) and Num(b) and Num(c) then return a, b, c end
  local x, y = Try(C_QuestLog and C_QuestLog.GetNextWaypointForMap, qid, pm)
  if Num(x) and Num(y) then return pm, x, y end
  local list = Try(C_QuestLog and C_QuestLog.GetQuestsOnMap, pm)
  if type(list) == "table" then
    for _, q in ipairs(list) do
      if q.questID == qid and Num(q.x) and Num(q.y) then return pm, q.x, q.y end
    end
  end
end

local trackedQuest
local function AddTracked(pm)
  trackedQuest = nil
  local ST = C_SuperTrack
  if not ST then return end
  if Try(ST.IsSuperTrackingUserWaypoint) then
    local pt = Try(C_Map.GetUserWaypoint)
    if pt and pt.uiMapID and pt.position then
      local x, y = XY(pt.position)
      if x then
        targets[#targets + 1] = { kind = "tracked", mapID = pt.uiMapID, x = x, y = y, label = "Waypoint", primary = true }
        return
      end
    end
  end
  local qid = Try(ST.GetSuperTrackedQuestID)
  if Num(qid) and qid > 0 then
    local mapID, x, y = QuestWaypoint(qid, pm)
    if mapID then
      trackedQuest = qid
      targets[#targets + 1] = { kind = "tracked", mapID = mapID, x = x, y = y, primary = true, questID = qid,
        label = Try(C_QuestLog.GetTitleForQuestID, qid) or "Tracked Quest" }
    end
  end
end

local function AddQuests(chain)
  local seen = {}
  for _, mapID in ipairs(chain) do
    local list = Try(C_QuestLog and C_QuestLog.GetQuestsOnMap, mapID)
    if type(list) == "table" then
      for _, q in ipairs(list) do
        local qid = q.questID
        if Num(qid) and not seen[qid] and qid ~= trackedQuest and Num(q.x) and Num(q.y) then
          seen[qid] = true
          local kind
          if Try(C_QuestLog.IsOnQuest, qid) then
            kind = Try(C_QuestLog.IsComplete, qid) and "turnin" or "objective"
          elseif q.isQuestStart then
            kind = "giver"
          end
          if kind and On(kind) then
            targets[#targets + 1] = { kind = kind, mapID = mapID, x = q.x, y = q.y, questID = qid,
              label = Try(C_QuestLog.GetTitleForQuestID, qid) }
          end
        end
      end
    end
  end
end

-- Questie's icons for the player's map. Questie draws one icon per spawn (on both the world map and the
-- minimap, and an icon can be hidden on one but not the other), so each quest and icon type is grouped here and
-- Tick keeps only the nearest of each group, which keeps the bar readable.
-- The focused quest keeps all of its icons like any other quest. When the game gave no waypoint for it, its
-- nearest icon is also promoted to the large primary marker (Tick does that, since "nearest" changes as you move).
local function AddQuestie(chain, focus)
  local Qe = _G.Questie
  local frames = Q.map.questIdFrames
  if type(frames) ~= "table" then return end
  local onMap = {}
  for _, m in ipairs(chain) do onMap[m] = true end
  local focusOnly = ns.db.mk_qFocusOnly
  local trackedOn = On("tracked")
  for qid, names in pairs(frames) do
    if Num(qid) and (qid == focus or not focusOnly) and type(names) == "table" then
      local promote = trackedOn and qid == focus and qid ~= trackedQuest   -- no game waypoint for it: Questie provides the primary
      local title   -- looked up once per quest, not once per icon
      for _, name in pairs(names) do
        local fr = _G[name]
        local d = type(fr) == "table" and fr.data
        if d and not fr.hidden and onMap[fr.UiMapID] and Num(fr.x) and Num(fr.y) then
          local kind = Q.kinds[d.Icon]
          local shows = kind and On(kind)
          if kind and (shows or promote) then
            local t = qcache[fr]
            if not t then t = {}; qcache[fr] = t end
            t.kind, t.baseKind, t.shows = kind, kind, shows
            t.mapID, t.x, t.y, t.questID, t.src = fr.UiMapID, fr.x / 100, fr.y / 100, qid, "questie"
            t.focus, t.primary = promote or nil, nil
            t.file = type(Qe.usedIcons) == "table" and Qe.usedIcons[d.Icon] or nil   -- Questie's art for this objective type (bag, sword...)
            if t.gq ~= qid or t.gi ~= d.Icon then   -- the group key is a string, so build it only when it changes
              t.gq, t.gi = qid, d.Icon
              t.group = "q" .. qid .. ":" .. tostring(d.Icon)
            end
            if title == nil then
              local qd = d.QuestData
              title = Try(C_QuestLog.GetTitleForQuestID, qid) or (type(qd) == "table" and type(qd.name) == "string" and qd.name) or false
            end
            t.label = title or nil
            targets[#targets + 1] = t
          end
        end
      end
    end
  end
end

local function AddVignettes(pm)
  local V = C_VignetteInfo
  if not V then return end
  local guids = Try(V.GetVignettes)
  if type(guids) ~= "table" then return end
  for _, guid in ipairs(guids) do
    local info = Try(V.GetVignetteInfo, guid)
    if info and not info.isDead and type(info.atlasName) == "string" and not (issecretvalue and issecretvalue(info.atlasName)) then
      local a = info.atlasName:lower()
      local kind
      if a:find("kill") or a:find("elite") or a:find("rare") then kind = "rare"
      elseif a:find("loot") or a:find("chest") or a:find("treasure") then kind = "treasure" end
      if kind and On(kind) then
        local x, y = XY(Try(V.GetVignettePosition, guid, pm))
        if x then
          targets[#targets + 1] = { kind = kind, mapID = pm, x = x, y = y, label = info.name, atlas = info.atlasName }
        end
      end
    end
  end
end

local function AddNodes(pm)
  local nodes = ns.db and ns.db.nodes
  if not nodes then return end
  for _, kind in ipairs({ "herb", "ore", "box" }) do
    local perMap = nodes[kind] and nodes[kind][pm]
    if perMap and On(kind) then
      for i = 1, #perMap do
        local n = perMap[i]
        targets[#targets + 1] = { kind = kind, mapID = pm, x = n.x, y = n.y, label = n.name }
      end
    end
  end
end

local Rebuild
function Rebuild()
  needRebuild = false
  wipe(targets)
  if not ns.db or not AnyOn() then return end
  local pm = Try(C_Map.GetBestMapForUnit, "player")
  if not Num(pm) then return end
  if On("tracked") then AddTracked(pm) else trackedQuest = nil end
  questieActive = UseQuestie() and true or false
  if questieActive then
    if On("objective") or On("giver") or On("tracked") then AddQuestie(MapChain(pm), FocusedQuest()) end
  elseif On("objective") or On("giver") then
    AddQuests(MapChain(pm))
  end
  if On("rare") or On("treasure") then AddVignettes(pm) end
  AddNodes(pm)
end

-- Bearing update (every TICK seconds) --------------------------------------------------------

-- A target's position on the player's map: its own when it is on that map, else moved through world
-- coordinates (cached per player map).
local function TargetXY(t, pm)
  if t.mapID == pm then return t.x, t.y end
  if t.cmap ~= pm or t.cfrom ~= t.mapID then
    t.cmap, t.cfrom, t.cx, t.cy = pm, t.mapID, nil, nil
    local cont, wp = Try(C_Map.GetWorldPosFromMapPos, t.mapID, CreateVector2D(t.x, t.y))
    if cont and wp then
      t.cx, t.cy = XY(Try(C_Map.GetMapPosFromWorldPos, cont, wp, pm))
    end
  end
  return t.cx, t.cy
end

-- Distance (yards) from the player to a point on the same map, plus the east/north offsets the bearing is made from.
-- Every target needs its distance each tick, but the bearing (atan2) is only worked out for the few that are kept.
local function Dist(tx, ty, px, py, w, h)
  local east, north = (tx - px) * w, -(ty - py) * h   -- map y grows southward
  return sqrt(east * east + north * north), east, north
end
local function Bearing(east, north) return (deg(atan2(east, north))) % 360 end

local function SortFn(a, b)
  if a.primary ~= b.primary then return a.primary end
  return a.dist < b.dist
end

local lastCount, tickNo = 0, 0
local lastPm, lastW, lastH   -- the player's map and its size in yards, as of the last full Tick (FastTick reuses them)
local lastPX, lastPY   -- the player's map position at the last full Tick or FastTick (FastTick skips when it is unchanged)
local best = {}   -- nearest candidate per group, rebuilt every tick
local function Tick()
  local changed = false   -- did anything visible move since the last redraw?
  tickNo = tickNo + 1
  wipe(active)
  local db = ns.db
  if db and #targets > 0 then
    local pm = Try(C_Map.GetBestMapForUnit, "player")
    local px, py = XY(pm and Try(C_Map.GetPlayerMapPosition, pm, "player"))
    local w, h = Try(C_Map.GetMapWorldSize, pm)
    if px and Num(w) and Num(h) and w > 0 and h > 0 then
      lastPX, lastPY = px, py
      lastPm, lastW, lastH = pm, w, h
      local range, qRange = db.mk_range or 500, db.mk_qRange or 600
      wipe(best)
      local fNear   -- nearest icon of the focused quest (when Questie supplies its primary marker)
      for i = 1, #targets do
        local t = targets[i]
        local tx, ty = TargetXY(t, pm)
        if tx then
          local dist, east, north = Dist(tx, ty, px, py, w, h)
          local limit = (t.src == "questie") and qRange or range
          if t.focus then
            -- An icon of the focused quest: it shows like any other (nearest per type, within range), and the
            -- nearest one overall, however far, becomes the primary marker below.
            t.dist, t.limit, t.east, t.north = dist, limit, east, north
            t.primary, t.kind = nil, t.baseKind
            if not fNear or dist < fNear.dist then fNear = t end
            if t.shows and dist <= limit then
              local cur = best[t.group]
              if not cur or dist < cur.dist then best[t.group] = t end
            end
          elseif t.primary or dist <= limit then
            t.dist, t.limit, t.east, t.north = dist, limit, east, north
            local g = t.group
            if g then
              local cur = best[g]
              if not cur or dist < cur.dist then best[g] = t end
            else
              active[#active + 1] = t
            end
          end
        end
      end
      if fNear then
        fNear.primary, fNear.kind = true, "tracked"
        best[fNear.group] = fNear
      end
      for _, t in pairs(best) do active[#active + 1] = t end
      table.sort(active, SortFn)
      for i = #active, MAX_ICONS + 1, -1 do active[i] = nil end
      for i = 1, #active do
        local t = active[i]
        t.bearing = Bearing(t.east, t.north)
        -- Only worth a redraw if the icon is new to the bar, moved at least 0.15 degrees, or its 5-yard distance label changed.
        local d5 = floor(t.dist / 5)
        if t.seen ~= tickNo - 1 or not t.drawn or abs(t.bearing - t.drawn) > 0.15 or d5 ~= t.drawnD then
          t.drawn, t.drawnD, changed = t.bearing, d5, true
        end
        t.seen = tickNo
        -- Quest-area glow: only the focused quest's marker, and only where the client can tell us.
        local inside
        if t.primary and t.questID and db.mk_areaGlow ~= false and AreaApi() then
          inside = Try(C_Minimap.IsInsideQuestBlob, t.questID) and true or false
        end
        if inside ~= t.inArea then t.inArea = inside; changed = true end
      end
    end
  end
  -- Redraw only when an icon actually moved or the set of icons changed, so standing still costs nothing.
  if (changed or #active ~= lastCount) and ns.Redraw then ns.Redraw() end
  lastCount = #active
end

Rebuild = ns.Perf("Rebuild", Rebuild)
Tick = ns.Perf("Tick", Tick)

-- Drawing (called from the compass layout, only when the compass redraws) --------------------

local KIND_LABEL = {
  tracked = "Tracked Quest", objective = "Quest Objective", turnin = "Quest Turn-In", giver = "Quest Giver",
  rare = "Rare Elite", treasure = "Treasure", herb = "Herb (Saved Spot)", ore = "Ore (Saved Spot)",
  box = "Container (Saved Spot)",
}

-- Clicking a quest icon focuses that quest by setting the game's super-tracked quest. Questie follows that
-- on its own (when its "follow super tracking" option is on); CHUD never writes to Questie.
local function Focusable(t)
  return t and t.questID and not t.primary and (t.kind == "objective" or t.kind == "turnin")
end
local function FocusQuest(qid)
  local ST = C_SuperTrack
  if ST and ST.SetSuperTrackedQuestID then pcall(ST.SetSuperTrackedQuestID, qid) end
  needRebuild = true
end

-- Hover tooltip for a marker: what it is, the quest's objectives, and how far away it is.
local function ShowTip(ic)
  local t = ic.t
  if not t then return end
  GameTooltip:SetOwner(ic, "ANCHOR_BOTTOM")
  GameTooltip:AddLine(t.label or KIND_LABEL[t.kind] or "Marker", 1, 0.82, 0)
  local kind = KIND_LABEL[t.kind] or ""
  if t.kind == "tracked" and not t.questID then kind = "Waypoint" end
  GameTooltip:AddLine(kind, 0.7, 0.7, 0.7)
  if t.questID then
    if t.kind == "turnin" or Try(C_QuestLog.IsComplete, t.questID) then
      GameTooltip:AddLine("Ready to turn in", 0.3, 1, 0.3)
    end
    local objs = Try(C_QuestLog.GetQuestObjectives, t.questID)
    if type(objs) == "table" then
      for _, o in ipairs(objs) do
        local text = o and o.text
        if type(text) == "string" and text ~= "" and not (issecretvalue and issecretvalue(text)) then
          if o.finished then GameTooltip:AddLine("- " .. text, 0.3, 1, 0.3, true)
          else GameTooltip:AddLine("- " .. text, 1, 1, 1, true) end
        end
      end
    end
  end
  if t.dist then GameTooltip:AddLine(format("%d yd away", t.dist), 0.7, 0.7, 0.7) end
  if Focusable(t) then GameTooltip:AddLine("Click to focus this quest", 0.5, 0.8, 1) end
  GameTooltip:Show()
end

local styleVer = 1   -- bumped whenever an icon style setting changes, so icons restyle once

-- Style settings (size, color, shadow) changed, or a theme was applied.
function ns.MarkersStyle()
  styleVer = styleVer + 1
  if ns.Redraw then ns.Redraw() end
end

local dragged = false   -- set while the bar is being dragged by an icon, so letting go is not a click
local function GetIcon(i)
  local ic = icons[i]
  if not ic then
    ic = CreateFrame("Frame", nil, ns.contentTop)
    ic:EnableMouse(true)
    ic:RegisterForDrag("LeftButton")
    ic:SetScript("OnEnter", ShowTip)
    ic:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- The icon is on top of the compass, so pass clicks and drags through to it, except a plain
    -- left click on a quest icon, which focuses that quest.
    ic:SetScript("OnMouseDown", function() dragged = false end)
    ic:SetScript("OnMouseUp", function(self, button)
      if button == "LeftButton" and not dragged and Focusable(self.t) then FocusQuest(self.t.questID); return end
      ns.root:GetScript("OnMouseUp")(ns.root, button)
    end)
    ic:SetScript("OnDragStart", function() dragged = true; ns.root:GetScript("OnDragStart")(ns.root) end)
    ic:SetScript("OnDragStop", function() ns.root:GetScript("OnDragStop")(ns.root) end)
    -- Drawn bottom to top: quest-area glow, drop shadow, then the icon itself.
    ic.glow = ic:CreateTexture(nil, "BACKGROUND", nil, -1)
    ic.glow:SetTexture("Interface\\Cooldown\\star4"); ic.glow:SetBlendMode("ADD")
    ic.glow:SetPoint("CENTER"); ic.glow:SetAlpha(0.7); ic.glow:Hide()
    -- A slow pulse run by the game's animation system (no per-frame addon code). Without it the glow is static.
    local ok, ag = pcall(function()
      local g = ic.glow:CreateAnimationGroup(); g:SetLooping("BOUNCE")
      local a = g:CreateAnimation("Alpha")
      a:SetFromAlpha(0.25); a:SetToAlpha(0.9); a:SetDuration(0.8); a:SetSmoothing("IN_OUT")
      return g
    end)
    ic.glowAnim = ok and ag or nil
    ic.shadow = ic:CreateTexture(nil, "BACKGROUND", nil, 0)
    ic.tex = ic:CreateTexture(nil, "ARTWORK"); ic.tex:SetAllPoints()
    ic.dist = ic:CreateFontString(nil, "OVERLAY")
    ic.dist:SetFont(STANDARD_TEXT_FONT, 9, "")
    ic.dist:SetPoint("TOP", ic, "BOTTOM", 0, 1)
    icons[i] = ic
  end
  return ic
end

local function SetIcon(tex, t)
  if t.file then tex:SetTexture(t.file); tex:SetTexCoord(0, 1, 0, 1); return end   -- Questie's own icon art
  local spec = ICON[t.kind] or {}
  local list = t.atlas and { t.atlas } or spec.atlases
  if list and C_Texture and C_Texture.GetAtlasInfo then
    for _, a in ipairs(list) do
      if C_Texture.GetAtlasInfo(a) then tex:SetAtlas(a, false); tex:SetTexCoord(0, 1, 0, 1); return end
    end
  end
  tex:SetTexture(spec.file or "Interface\\Icons\\INV_Misc_QuestionMark")
  if spec.crop then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) else tex:SetTexCoord(0, 1, 0, 1) end
end

-- Paints one texture as a flat-colored silhouette of the icon (desaturate, then tint).
local function Tinted(tex, t, r, g, b, a)
  SetIcon(tex, t)
  tex:SetDesaturated(true)
  tex:SetVertexColor(r, g, b, 1)
  tex:SetAlpha(a)
end

-- Applies color and shadow to one icon (its size is set per draw in LayoutMarkers). Runs when settings or the icon's target change.
local function Restyle(ic, t)
  local db = ns.db
  local c, native = db.mk_color, db.mk_native
  SetIcon(ic.tex, t)
  if native then
    ic.tex:SetDesaturated(false); ic.tex:SetVertexColor(1, 1, 1, 1); ic.tex:SetAlpha(1)   -- the game's own colors
  else
    ic.tex:SetDesaturated(true); ic.tex:SetVertexColor(c[1], c[2], c[3], 1); ic.tex:SetAlpha(c[4])
  end
  local base = native and 1 or c[4]
  if native then ic.glow:SetVertexColor(1, 0.82, 0, 1) else ic.glow:SetVertexColor(c[1], c[2], c[3], 1) end

  local sa = db.mk_shadowAlpha or 0
  if sa > 0 then
    local off = db.mk_shadowDist or 1.5
    Tinted(ic.shadow, t, 0, 0, 0, sa * base)
    ic.shadow:ClearAllPoints()   -- anchored to both corners, so it follows the icon's size
    ic.shadow:SetPoint("TOPLEFT", ic, "TOPLEFT", off, -off)
    ic.shadow:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", off, -off)
    ic.shadow:Show()
  else
    ic.shadow:Hide()
  end

  local tc = db.textColor
  -- The distance text only gets the game's black outline on themes that outline their text.
  -- Light themes (dark text, no outline) would otherwise be unreadable.
  local flag = ((db.outlineWidth or 0) > 0) and "OUTLINE" or ""
  local path = (db.fontPath and db.fontPath ~= "") and db.fontPath or STANDARD_TEXT_FONT
  if not ic.dist:SetFont(path, 9, flag) then ic.dist:SetFont(STANDARD_TEXT_FONT, 9, flag) end
  ic.dist:SetTextColor(tc[1], tc[2], tc[3], 1)
  ic.dist:SetAlpha(tc[4])
end

-- Which way "outside the bar" is: below it when the bar is in the upper half of the screen (the usual
-- place), above it when it is in the lower half, so the icons are never pushed off the screen.
local function OutsideDir()
  local _, cy = ns.root:GetCenter()
  if type(cy) == "number" and UIParent and cy < UIParent:GetHeight() / 2 then return 1 end
  return -1
end

local lastLayoutAt = -1   -- GetTime() of the last LayoutMarkers, so FastTick does not repeat a layout done this frame
local lastB, lastPpd, lastHalf, lastFade, lastZone   -- the compass's latest layout, so icons can be re-placed alone
function ns.LayoutMarkers(b, ppd, half, fade, fadeZone)
  lastB, lastPpd, lastHalf, lastFade, lastZone = b, ppd, half, fade, fadeZone
  lastLayoutAt = GetTime()
  local db = ns.db
  local base = db.mk_size or 16
  local maxSize = max(base, db.height - 2)   -- the focused icon never makes the bar taller
  local depth = db.mk_depth ~= false
  local outside = db.mk_outside
  local dir = outside and OutsideDir() or 0   -- +1 above the bar, -1 below it
  local shown = 0
  for i = 1, #active do
    local t = active[i]
    local ic = GetIcon(shown + 1)
    local size, dim = base, 1
    if t.primary then
      size = min(base * FOCUS_SCALE, maxSize)
    elseif FADE_RANGE[t.kind] then
      -- Quest givers and objectives shrink and fade the farther away they are; each has its own distance.
      local spec = FADE_RANGE[t.kind]
      local f = min(t.dist / max(db[spec[1]] or spec[2], 1), 1)
      size, dim = base * (1 - FADE_SHRINK * f), 1 - FADE_ALPHA * f
    elseif depth and t.limit and t.limit > 0 then
      -- Farther icons are smaller, down to FAR_SCALE of normal at the edge of their range.
      size = max(6, base * (1 - (1 - FAR_SCALE) * min(t.dist / t.limit, 1)))
    end
    size = floor(size * 2 + 0.5) / 2   -- half-pixel steps, so the size is not re-set for tiny changes
    if ic.sz ~= size then ic.sz = size; ic:SetSize(size, size) end
    local y
    if outside then
      y = (db.height / 2 + size / 2 + 1) * dir   -- just beyond the bar's edge
    else
      -- Icons sit along the edge opposite the ticks, inside the bar.
      y = db.height / 2 - size / 2 - 1
      if db.flipTicks then y = -y end
    end
    local showDist = t.primary and db.mk_distance
    local reach = size
    if showDist then
      -- Measure the distance text first: when pinned to the edge, the text must stay inside the bar too.
      local d5 = floor(t.dist / 5 + 0.5) * 5
      if ic.dt ~= t or ic.d5 ~= d5 then ic.dt = t; ic.d5 = d5; ic.dist:SetText(d5 .. " yd") end
      reach = max(size, ic.dist:GetStringWidth())
    end
    local lim = half - reach / 2 - 2
    local x = (((t.bearing - b + 540) % 360) - 180) * ppd
    local show = true
    if abs(x) > lim then
      if t.primary then x = (x > 0) and lim or -lim      -- pinned to the edge: turn this way
      else show = false end
    end
    if show then
      -- One fade rule for every position, including when pinned, so an icon is exactly as faded at
      -- the edge as it will be the moment it slides back in.
      local alpha = 1
      if fade then alpha = max(0, min(1, (half - abs(x)) / fadeZone)) end
      shown = shown + 1
      if ic.ver ~= styleVer or ic.t ~= t then ic.ver = styleVer; ic.t = t; Restyle(ic, t) end
      -- Distance text goes on the inner side of the icon (toward the bar's middle) inside the bar, and on the
      -- outer side when the icons are outside it.
      local flip                      -- true = distance text above the icon, false = below it
      if outside then flip = (dir == 1) else flip = db.flipTicks and true or false end
      if ic.flip ~= flip then
        ic.flip = flip
        ic.dist:ClearAllPoints()
        if flip then ic.dist:SetPoint("BOTTOM", ic, "TOP", 0, -1) else ic.dist:SetPoint("TOP", ic, "BOTTOM", 0, 1) end
      end
      if t.inArea then
        ic.glow:SetSize(min(size * 2, db.height), min(size * 2, db.height))   -- never spills outside the bar
        ic.glow:Show()
        if ic.glowAnim and not ic.glowAnim:IsPlaying() then ic.glowAnim:Play() end
      else
        ic.glow:Hide()
        if ic.glowAnim then ic.glowAnim:Stop() end
      end
      ic:ClearAllPoints()
      ic:SetPoint("CENTER", ns.strip, "CENTER", x, y)
      ic:SetAlpha(alpha * dim)
      ic:Show()
      ic.dist:SetShown(showDist)
    end
  end
  for i = shown + 1, #icons do icons[i]:Hide(); icons[i].t = nil end   -- hiding the icon hides its glow too
end

ns.LayoutMarkers = ns.Perf("LayoutMarkers", ns.LayoutMarkers)

-- Smooth movement for close-up icons ---------------------------------------------------------------
-- The full Tick (every TICK seconds) re-scans every target. A nearby icon swings quickly as you move, so
-- at that rate it jumps. While you move and any shown icon is within NEAR yards, only the icons on the bar
-- are re-aimed, at the rate the player chose (mk_rate), and only the icons are re-placed, not the whole
-- compass. Standing still costs nothing: the player's position is unchanged, so it returns at once.
local NEAR = 150
local function FastTick()
  if not lastB or #active == 0 or not lastPm then return end
  local near = false
  for i = 1, #active do
    if active[i].dist < NEAR then near = true; break end
  end
  if not near then return end
  local px, py = XY(Try(C_Map.GetPlayerMapPosition, lastPm, "player"))
  if not px or (px == lastPX and py == lastPY) then return end
  lastPX, lastPY = px, py
  for i = 1, #active do
    local t = active[i]
    local tx, ty = TargetXY(t, lastPm)
    if tx then
      local dist, east, north = Dist(tx, ty, px, py, lastW, lastH)
      t.dist, t.bearing = dist, Bearing(east, north)
      t.drawn, t.drawnD = t.bearing, floor(dist / 5)   -- keep Tick's change detection in step
    end
  end
  if lastLayoutAt == GetTime() then return end   -- the compass already redrew the icons this frame, with these positions
  ns.LayoutMarkers(lastB, lastPpd, lastHalf, lastFade, lastZone)
end
FastTick = ns.Perf("FastTick", FastTick)

-- Gather recording ------------------------------------------------------------------------------
-- The cast that starts a gather is matched by spell NAME (works across expansions and locales
-- because the base spells' names are looked up from the game). When the cast succeeds, the
-- player's position is saved as a spot.

local gatherKind = {}
local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then return Try(C_Spell.GetSpellName, id) end
  return Try(GetSpellInfo, id)
end
local function BuildGatherNames()
  wipe(gatherKind)
  gatherKind[SpellName(2366) or "Herb Gathering"] = "herb"
  gatherKind[SpellName(2575) or "Mining"] = "ore"
  gatherKind[SpellName(3365) or "Opening"] = "box"
end

local pending
local function Record(p)
  local db = ns.db
  if not db then return end
  local pm = Try(C_Map.GetBestMapForUnit, "player")
  local x, y = XY(pm and Try(C_Map.GetPlayerMapPosition, pm, "player"))
  local w, h = Try(C_Map.GetMapWorldSize, pm)
  if not (x and Num(w) and Num(h) and w > 0) then return end
  db.nodes = db.nodes or {}
  local byKind = db.nodes[p.kind]; if not byKind then byKind = {}; db.nodes[p.kind] = byKind end
  local list = byKind[pm]; if not list then list = {}; byKind[pm] = list end
  for i = 1, #list do
    local n = list[i]
    local dx, dy = (n.x - x) * w, (n.y - y) * h
    if dx * dx + dy * dy <= DEDUPE * DEDUPE then n.name = p.name or n.name; return end
  end
  if #list >= MAX_NODES then table.remove(list, 1) end   -- drop the oldest
  list[#list + 1] = { x = floor(x * 1e5 + 0.5) / 1e5, y = floor(y * 1e5 + 0.5) / 1e5, name = p.name }
  needRebuild = true
end

-- Events and timing ---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
  "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "SUPER_TRACKING_CHANGED", "USER_WAYPOINT_UPDATED",
  "VIGNETTES_UPDATED", "VIGNETTE_MINIMAP_UPDATED" }) do
  pcall(ev.RegisterEvent, ev, e)   -- an event this client does not have is simply skipped
end
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SENT", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_INTERRUPTED", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_FAILED", "player")

ev:SetScript("OnEvent", function(_, event, ...)
  if event == "UNIT_SPELLCAST_SENT" then
    local _, target, _, spellID = ...
    local name = Num(spellID) and SpellName(spellID) or nil
    local tname = (type(target) == "string" and not (issecretvalue and issecretvalue(target))) and target or nil
    ns.lastCast = { id = spellID, name = name, target = tname }
    local kind = name and gatherKind[name]
    pending = kind and { kind = kind, spell = spellID, name = tname } or nil
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local _, _, spellID = ...
    if pending and pending.spell == spellID then Record(pending); pending = nil end
  elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
    pending = nil
  else
    needRebuild = true
  end
end)

local acc, accRefresh, accFast = 0, 0, 0
ev:SetScript("OnUpdate", ns.Perf("Markers", function(_, elapsed)
  if not ns.db then return end
  if not next(gatherKind) then BuildGatherNames() end
  acc = acc + elapsed; accRefresh = accRefresh + elapsed; accFast = accFast + elapsed
  if acc < TICK then
    -- Between full ticks: keep close-up icons smooth, at the chosen rate.
    if accFast >= 1 / max(ns.db.mk_rate or 30, 1) then accFast = 0; FastTick() end
    return
  end
  acc, accFast = 0, 0
  if needRebuild or accRefresh >= REFRESH then accRefresh = 0; Rebuild() end
  Tick()
end))

-- Called by the menu whenever an option changes.
function ns.MarkersChanged()
  needRebuild = true
  acc = TICK   -- run at the next frame
end

function ns.MarkerDebug()
  local db = ns.db
  local pm = Try(C_Map.GetBestMapForUnit, "player")
  local x, y = XY(pm and Try(C_Map.GetPlayerMapPosition, pm, "player"))
  print("CHUD markers: map", tostring(pm), "| position", x and format("%.3f, %.3f", x, y) or "unavailable",
    "| targets", #targets, "| on compass", #active)
  local counts = {}
  for _, t in ipairs(targets) do counts[t.kind] = (counts[t.kind] or 0) + 1 end
  for k, n in pairs(counts) do print("  ", k, n) end
  local rec = {}
  for _, kind in ipairs({ "herb", "ore", "box" }) do
    local n = 0
    for _, list in pairs((db.nodes and db.nodes[kind]) or {}) do n = n + #list end
    rec[#rec + 1] = kind .. "=" .. n
  end
  print("  recorded spots:", table.concat(rec, "  "))
  local lc = ns.lastCast
  print("  last cast:", lc and (tostring(lc.id) .. " " .. tostring(lc.name) .. " -> " .. tostring(lc.target)) or "none yet")
  local fnames = { "C_QuestLog.GetQuestsOnMap", "C_QuestLog.GetNextWaypoint", "C_SuperTrack.GetSuperTrackedQuestID",
    "C_VignetteInfo.GetVignettes", "C_Map.GetPlayerMapPosition", "C_Map.GetMapWorldSize", "C_Map.GetWorldPosFromMapPos",
    "C_Map.GetMapPosFromWorldPos", "C_Map.GetUserWaypoint" }
  local missing = {}
  for _, n in ipairs(fnames) do
    local t, key = n:match("^(.-)%.(.+)$")
    if not (_G[t] and _G[t][key]) then missing[#missing + 1] = n end
  end
  print("  missing APIs:", #missing == 0 and "none" or table.concat(missing, ", "))
  local qstate = "not installed"
  if _G.Questie then
    if not QuestieReady() then qstate = "installed, not ready yet"
    elseif db.mk_questie == false then qstate = "installed, turned off in the menu"
    else qstate = "in use" end
  end
  print("  questie:", qstate)
  if _G.Questie and Q.map and type(Q.map.questIdFrames) == "table" then
    local n = { total = 0, hidden = 0, mini = 0, other = 0 }
    local byKind = {}
    for _, names in pairs(Q.map.questIdFrames) do
      if type(names) == "table" then
        for _, name in pairs(names) do
          local fr = _G[name]
          local d = type(fr) == "table" and fr.data
          if d then
            n.total = n.total + 1
            if fr.hidden then n.hidden = n.hidden + 1 end
            if fr.miniMapIcon then n.mini = n.mini + 1 end
            local k = Q.kinds and Q.kinds[d.Icon]
            if k and not fr.hidden then byKind[k] = (byKind[k] or 0) + 1 else n.other = n.other + 1 end
          end
        end
      end
    end
    print("  questie icons:", "total", n.total, "| hidden by Questie", n.hidden, "| minimap copies", n.mini,
      "| usable: objective", byKind.objective or 0, "giver", byKind.giver or 0, "turnin", byKind.turnin or 0, "| skipped", n.other)
  end
  -- Quest givers: where do they drop out? (read only; counts every step for the player's current map)
  if _G.Questie and Q.map and Q.kinds and type(Q.map.questIdFrames) == "table" then
    local chain = {}
    for _, m in ipairs(pm and MapChain(pm) or {}) do chain[m] = true end
    local w, h = Try(C_Map.GetMapWorldSize, pm)
    local g = { all = 0, shown = 0, hiddenWorld = 0, hiddenMini = 0, onMap = 0, near = 0 }
    local byMap, nearest, nearestQuest = {}, nil, nil
    for qid, names in pairs(Q.map.questIdFrames) do
      if type(names) == "table" then
        for _, name in pairs(names) do
          local fr = _G[name]
          local d = type(fr) == "table" and fr.data
          if d and Q.kinds[d.Icon] == "giver" then
            g.all = g.all + 1
            if fr.hidden then
              if fr.miniMapIcon then g.hiddenMini = g.hiddenMini + 1 else g.hiddenWorld = g.hiddenWorld + 1 end
            else
              g.shown = g.shown + 1
              byMap[fr.UiMapID or 0] = (byMap[fr.UiMapID or 0] or 0) + 1
              if chain[fr.UiMapID] and Num(fr.x) and Num(fr.y) then
                g.onMap = g.onMap + 1
                if x and Num(w) and Num(h) and fr.UiMapID == pm then
                  local dx, dy = (fr.x / 100 - x) * w, (fr.y / 100 - y) * h
                  local dist = sqrt(dx * dx + dy * dy)
                  if not nearest or dist < nearest then nearest, nearestQuest = dist, qid end
                  if dist <= (db.mk_qRange or 600) then g.near = g.near + 1 end
                end
              end
            end
          end
        end
      end
    end
    print("  questie givers:", "total", g.all, "| hidden (world map copy)", g.hiddenWorld, "(minimap copy)", g.hiddenMini,
      "| shown", g.shown, "| on this map", g.onMap, "| within", db.mk_qRange or 600, "yd", g.near,
      "| nearest", nearest and format("%d yd (quest %s)", floor(nearest), tostring(nearestQuest)) or "none on this map")
    local list = {}
    for m, n in pairs(byMap) do list[#list + 1] = { m = m, n = n } end
    table.sort(list, function(a, b) return a.n > b.n end)
    local parts = {}
    for i = 1, math.min(#list, 8) do parts[i] = list[i].m .. "=" .. list[i].n end
    print("  shown giver icons by map id:", #parts > 0 and table.concat(parts, " ") or "none",
      "| this map and parents:", pm and table.concat(MapChain(pm), ",") or "?",
      "| Quest Givers option:", db.mk_givers and "on" or "OFF", "| Use Questie:", db.mk_questie ~= false and "on" or "off")
    local qp = type(_G.Questie.db) == "table" and _G.Questie.db.profile
    if type(qp) == "table" then
      print("  Questie settings (read only): enableMapIcons", tostring(qp.enableMapIcons), "| enableMiniMapIcons", tostring(qp.enableMiniMapIcons),
        "| showAvailableQuests", tostring(qp.showAvailableQuests), "| enableAvailable", tostring(qp.enableAvailable),
        "| hideUnexploredMapIcons", tostring(qp.hideUnexploredMapIcons))
    end
  end
  print("  quest area glow:", AreaApi() and "supported" or "not supported by this client")
end
