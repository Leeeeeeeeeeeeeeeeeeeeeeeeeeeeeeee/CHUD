local ADDON, ns = ...

-- Markers: icons on the compass that point toward quests, rares/treasures and gathering spots.
--
-- Data sources (all queried with pcall; a missing or changed API just means no markers of that kind):
--   tracked   super-tracked quest waypoint, or the map waypoint you are tracking
--   objective quests in your log that have a POI on the current map (turn-ins use the same option)
--   giver     quests you could pick up here
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
local TICK = 0.25       -- seconds between bearing updates
local REFRESH = 2.0     -- seconds between full re-queries (events also trigger one)
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
  if On("objective") or On("giver") then AddQuests(MapChain(pm)) end
  if On("rare") or On("treasure") then AddVignettes(pm) end
  AddNodes(pm)
end

-- Bearing update (every TICK seconds) --------------------------------------------------------

local function SortFn(a, b)
  if a.primary ~= b.primary then return a.primary end
  return a.dist < b.dist
end

local lastCount = 0
local function Tick()
  local changed = false   -- did anything visible move since the last redraw?
  wipe(active)
  local db = ns.db
  if db and #targets > 0 then
    local pm = Try(C_Map.GetBestMapForUnit, "player")
    local px, py = XY(pm and Try(C_Map.GetPlayerMapPosition, pm, "player"))
    local w, h = Try(C_Map.GetMapWorldSize, pm)
    if px and Num(w) and Num(h) and w > 0 and h > 0 then
      local range = db.mk_range or 500
      for i = 1, #targets do
        local t = targets[i]
        local tx, ty
        if t.mapID == pm then
          tx, ty = t.x, t.y
        else
          -- Another map: go through world coordinates onto the player's map (cached per player map).
          if t.cmap ~= pm then
            t.cmap, t.cx, t.cy = pm, nil, nil
            local cont, wp = Try(C_Map.GetWorldPosFromMapPos, t.mapID, CreateVector2D(t.x, t.y))
            if cont and wp then
              t.cx, t.cy = XY(Try(C_Map.GetMapPosFromWorldPos, cont, wp, pm))
            end
          end
          tx, ty = t.cx, t.cy
        end
        if tx then
          local east, north = (tx - px) * w, -(ty - py) * h   -- map y grows southward
          local dist = sqrt(east * east + north * north)
          if t.primary or dist <= range then
            t.dist = dist
            t.bearing = (deg(atan2(east, north))) % 360
            -- Only worth a redraw if the icon moved at least 0.15 degrees, or its 5-yard distance label changed.
            local d5 = floor(dist / 5)
            if not t.drawn or abs(t.bearing - t.drawn) > 0.15 or d5 ~= t.drawnD then
              t.drawn, t.drawnD, changed = t.bearing, d5, true
            end
            active[#active + 1] = t
          end
        end
      end
      table.sort(active, SortFn)
      for i = #active, MAX_ICONS + 1, -1 do active[i] = nil end
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
  GameTooltip:Show()
end

local styleVer = 1   -- bumped whenever an icon style setting changes, so icons restyle once

-- Style settings (size, color, shadow) changed, or a theme was applied.
function ns.MarkersStyle()
  styleVer = styleVer + 1
  if ns.Redraw then ns.Redraw() end
end

local function GetIcon(i)
  local ic = icons[i]
  if not ic then
    ic = CreateFrame("Frame", nil, ns.contentTop)
    ic:EnableMouse(true)
    ic:RegisterForDrag("LeftButton")
    ic:SetScript("OnEnter", ShowTip)
    ic:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- The icon is on top of the compass, so pass clicks and drags through to it.
    ic:SetScript("OnMouseUp", function(_, button) ns.root:GetScript("OnMouseUp")(ns.root, button) end)
    ic:SetScript("OnDragStart", function() ns.root:GetScript("OnDragStart")(ns.root) end)
    ic:SetScript("OnDragStop", function() ns.root:GetScript("OnDragStop")(ns.root) end)
    -- Drawn bottom to top: drop shadow, then the icon itself.
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

-- Applies size, color, outline and shadow to one icon. Runs when settings or the icon's target change.
local function Restyle(ic, t)
  local db = ns.db
  local size = db.mk_size or 16
  ic:SetSize(size, size)
  local c, native = db.mk_color, db.mk_native
  SetIcon(ic.tex, t)
  if native then
    ic.tex:SetDesaturated(false); ic.tex:SetVertexColor(1, 1, 1, 1); ic.tex:SetAlpha(1)   -- the game's own colors
  else
    ic.tex:SetDesaturated(true); ic.tex:SetVertexColor(c[1], c[2], c[3], 1); ic.tex:SetAlpha(c[4])
  end
  local base = native and 1 or c[4]

  local sa = db.mk_shadowAlpha or 0
  if sa > 0 then
    local off = db.mk_shadowDist or 1.5
    Tinted(ic.shadow, t, 0, 0, 0, sa * base)
    ic.shadow:ClearAllPoints(); ic.shadow:SetPoint("CENTER", ic, "CENTER", off, -off)
    ic.shadow:SetSize(size, size); ic.shadow:Show()
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

function ns.LayoutMarkers(b, ppd, half, fade, fadeZone)
  local db = ns.db
  local size = db.mk_size or 16
  -- Icons sit along the edge opposite the ticks, inside the bar.
  local y = db.height / 2 - size / 2 - 1
  if db.flipTicks then y = -y end
  local shown = 0
  for i = 1, #active do
    local t = active[i]
    local ic = GetIcon(shown + 1)
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
      -- Distance text goes on the inner side of the icon (toward the bar's middle), never outside the bar
      -- where it would be clipped.
      local flip = db.flipTicks and true or false
      if ic.flip ~= flip then
        ic.flip = flip
        ic.dist:ClearAllPoints()
        if flip then ic.dist:SetPoint("BOTTOM", ic, "TOP", 0, -1) else ic.dist:SetPoint("TOP", ic, "BOTTOM", 0, 1) end
      end
      ic:ClearAllPoints()
      ic:SetPoint("CENTER", ns.strip, "CENTER", x, y)
      ic:SetAlpha(alpha)
      ic:Show()
      ic.dist:SetShown(showDist)
    end
  end
  for i = shown + 1, #icons do icons[i]:Hide(); icons[i].t = nil end
end

ns.LayoutMarkers = ns.Perf("LayoutMarkers", ns.LayoutMarkers)

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

local acc, accRefresh = 0, 0
ev:SetScript("OnUpdate", ns.Perf("Markers", function(_, elapsed)
  if not ns.db then return end
  if not next(gatherKind) then BuildGatherNames() end
  acc = acc + elapsed; accRefresh = accRefresh + elapsed
  if acc < TICK then return end
  acc = 0
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
end
