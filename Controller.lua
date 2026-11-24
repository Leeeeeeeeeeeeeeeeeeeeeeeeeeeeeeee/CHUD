local _, ns = ...

local UPDATE_INTERVAL = 1 / 20
local MOVE_DEADZONE = 0.15
local LOOK_DEADZONE = 0.05
local CIRCLE = 2 * math.pi
local abs, atan2 = math.abs, math.atan2
local elapsedSinceSample, heading, yawRate = 0, nil, nil
local yawSamples = 0
local lastNorth, lastWest, lastMap, lastMove
local lastMeasured, lastTurn, lastFacing
local stickCount, moveIndex, cameraIndex

-- Checks the type before using a value that the client may have made unreadable.
local function Readable(value, kind)
  return type(value) == kind and not (issecretvalue and issecretvalue(value))
end

-- Returns the shortest signed change between two headings in radians.
local function AngleDelta(a, b) return (a - b + math.pi) % CIRCLE - math.pi end

-- Clears the old heading when switching input or entering a different world.
function ns.ResetGamepadHeading()
  elapsedSinceSample, heading = 0, nil
  lastNorth, lastWest, lastMap, lastMove = nil, nil, nil, nil
  lastMeasured, lastTurn, lastFacing = nil, nil, nil
end

-- Reads the mapped movement direction and horizontal camera input without capturing controller events.
local function ReadSticks()
  local state = C_GamePad.GetDeviceMappedState()
  if not Readable(state, "table") or not Readable(state.sticks, "table")
    or not Readable(state.stickCount, "number") then return end
  if state.stickCount ~= stickCount then
    stickCount, moveIndex, cameraIndex = state.stickCount, nil, nil
    for i = 1, stickCount do
      local name = C_GamePad.StickIndexToConfigName(i - 1)
      if name == "Movement" then moveIndex = i end
      if name == "Camera" then cameraIndex = i end
    end
  end
  local move, camera = state.sticks[moveIndex], state.sticks[cameraIndex]
  if not Readable(move, "table") or not Readable(camera, "table") then
    stickCount = nil
    return
  end
  local x, y, turn = move.x, move.y, camera.x
  if not (Readable(x, "number") and Readable(y, "number") and Readable(turn, "number")) then return end
  local moveAngle = x * x + y * y >= MOVE_DEADZONE * MOVE_DEADZONE and atan2(x, y) or nil
  if abs(turn) >= LOOK_DEADZONE and C_CVar and C_CVar.GetCVarBool then
    local inverted = C_CVar.GetCVarBool("gamepadInvertYaw")
    if Readable(inverted, "boolean") and inverted then turn = -turn end
  end
  return abs(turn) >= LOOK_DEADZONE and turn or 0, moveAngle
end

-- Infers world-camera heading from travel direction and camera-relative stick direction.
local function MeasureHeading(moveAngle, elapsed)
  local north, west, map, measured
  if moveAngle then
    local ok, x, y, _, id = pcall(UnitPosition, "player")
    if ok and Readable(x, "number") and Readable(y, "number") and Readable(id, "number") then
      north, west, map = x, y, id
      if lastNorth and map == lastMap and abs(AngleDelta(moveAngle, lastMove)) < 0.15 then
        local dn, dw = north - lastNorth, west - lastWest
        local distanceSquared = dn * dn + dw * dw
        if distanceSquared >= 0.0025 and distanceSquared <= (elapsed * 60) ^ 2 then
          measured = (atan2(dw, dn) + moveAngle) % CIRCLE
        end
      end
    end
  end
  lastNorth, lastWest, lastMap, lastMove = north, west, map, moveAngle
  return measured
end

-- Estimates camera heading when gamepad input is active. Nil keeps the ordinary character heading.
function ns.GamepadHeading(facing, elapsed)
  if facing == nil then
    if heading or elapsedSinceSample > 0 then ns.ResetGamepadHeading() end
    return
  end
  elapsedSinceSample = elapsedSinceSample + elapsed
  if elapsedSinceSample < UPDATE_INTERVAL then return heading end
  elapsed = elapsedSinceSample
  elapsedSinceSample = 0
  if not (C_GamePad and C_GamePad.GetDeviceMappedState and C_GamePad.StickIndexToConfigName
    and IsUsingGamepad and IsUsingGamepad()) then
    ns.ResetGamepadHeading()
    return
  end
  if (IsGamePadCursorControlEnabled and IsGamePadCursorControlEnabled())
    or (WorldMapFrame and WorldMapFrame:IsShown()) or (GameMenuFrame and GameMenuFrame:IsShown()) then
    lastNorth, lastMeasured, lastTurn, lastFacing = nil, nil, nil, nil
    return heading
  end
  local ok, turn, moveAngle = pcall(ReadSticks)
  if not ok or turn == nil then
    ns.ResetGamepadHeading()
    return
  end
  if elapsed > 0.25 then
    lastNorth, lastMeasured, lastTurn, lastFacing = nil, nil, nil, nil
    return heading
  end

  local measured = MeasureHeading(moveAngle, elapsed)
  if not measured and not moveAngle and lastFacing and turn ~= 0 then
    -- Native gamepad controls can turn the character with the camera during combat or casting.
    local delta = AngleDelta(facing, lastFacing)
    if abs(delta) > 0.002 and abs(delta) < 0.6 and delta * turn < 0 then measured = facing end
  end
  if measured and lastMeasured and lastTurn and abs(turn) > 0.45 and abs(turn - lastTurn) < 0.15 then
    local rate = -AngleDelta(measured, lastMeasured) / ((turn + lastTurn) * 0.5 * elapsed)
    if rate > 0.2 and rate < 18 then
      yawRate = yawRate and (yawRate * 0.8 + rate * 0.2) or rate
      yawSamples = math.min(yawSamples + 1, 3)
    end
  end

  if measured then
    heading = measured
  elseif yawSamples >= 3 and turn ~= 0 then
    heading = ((heading or facing) - turn * yawRate * elapsed) % CIRCLE
  elseif heading and lastFacing and not moveAngle and abs(AngleDelta(facing, lastFacing)) > 0.5 then
    heading = nil
  end
  lastMeasured, lastTurn, lastFacing = measured, turn, facing
  return heading
end

if hooksecurefunc and type(CenterCamera) == "function" then
  hooksecurefunc("CenterCamera", ns.ResetGamepadHeading)
end
