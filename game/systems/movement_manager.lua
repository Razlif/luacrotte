-- Applies simple horizontal movement to an entity.
local MovementManager = {}
local PositionManager = require("game.systems.position_manager")

local function clamp_to_bounds(entity, settings)
  local bounds = settings and settings.bounds
  if not bounds then
    return
  end
  entity.position.x = math.max(bounds.left, math.min(bounds.right, entity.position.x))
  if bounds.top then
    entity.position.ground_y = math.max(bounds.top, math.min(bounds.bottom or bounds.top, entity.position.ground_y))
  end
end

function MovementManager.move_by(entity, dx, dground_y, settings)
  PositionManager.move(entity.position, dx or 0, dground_y or 0, 0)
  clamp_to_bounds(entity, settings or {})
end

function MovementManager.update(entity, intent, settings, dt)
  local movement = settings or {}
  local horizontal_speed = intent.horizontal_speed or movement.horizontal_speed or movement.speed or 0
  local vertical_speed = intent.vertical_speed or movement.vertical_speed or movement.speed or 0
  MovementManager.move_by(
    entity,
    (intent.horizontal or 0) * horizontal_speed * dt,
    (intent.vertical or 0) * vertical_speed * dt,
    movement
  )
end

return MovementManager
