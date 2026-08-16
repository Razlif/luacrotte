-- Converts controller intent into a desired velocity. Final position changes
-- belong to the active physics world.
local MovementManager = {}

local function set_velocity(entity, velocity_x, velocity_y)
  entity.physics_intent_velocity = entity.physics_intent_velocity or { x = 0, y = 0 }
  entity.physics_intent_velocity.x = velocity_x or 0
  entity.physics_intent_velocity.y = velocity_y or 0
  local motion = entity.motocrotte_motion
  if motion then
    motion.vx = velocity_x or 0
    motion.vy = velocity_y or 0
    motion.speed = math.sqrt(motion.vx * motion.vx + motion.vy * motion.vy)
  end
end

function MovementManager.set_velocity(entity, velocity_x, velocity_y)
  set_velocity(entity, velocity_x, velocity_y)
end

function MovementManager.move_by(entity, dx, dground_y, _settings, dt)
  dt = tonumber(dt) or (1 / 60)
  if dt <= 0 then
    set_velocity(entity, 0, 0)
    return
  end
  set_velocity(entity, (dx or 0) / dt, (dground_y or 0) / dt)
end

function MovementManager.update(entity, intent, settings, _dt)
  local movement = settings or {}
  local horizontal_speed = intent.horizontal_speed or movement.horizontal_speed or movement.speed or 0
  local vertical_speed = intent.vertical_speed or movement.vertical_speed or movement.speed or 0
  set_velocity(
    entity,
    (intent.horizontal or 0) * horizontal_speed,
    (intent.vertical or 0) * vertical_speed
  )
end

return MovementManager
