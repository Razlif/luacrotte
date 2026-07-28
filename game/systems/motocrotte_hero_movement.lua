-- Data-driven free-map movement for the MotoCrotte hero.
local Movement = {}

local function approach(value, target, amount)
  if value < target then return math.min(value + amount, target) end
  if value > target then return math.max(value - amount, target) end
  return target
end

local function required_number(table_value, key, label)
  local value = table_value and table_value[key]
  assert(type(value) == "number", label .. "." .. key .. " must be configured")
  return value
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function Movement.update(hero, intent, definition, level_definition, dt)
  assert(hero and hero.position, "MotoCrotte hero position is required")
  assert(definition and definition.movement, "MotoCrotte hero movement data is required")
  assert(level_definition and level_definition.hero_bounds, "MotoCrotte hero bounds are required")
  assert(type(dt) == "number" and dt >= 0, "Delta time must be non-negative")

  local config = definition.movement
  local bounds = level_definition.hero_bounds
  local acceleration = required_number(config, "acceleration", "hero movement")
  local deceleration = required_number(config, "deceleration", "hero movement")
  local max_speed = required_number(config, "max_speed", "hero movement")
  local vertical_speed = required_number(config, "vertical_speed", "hero movement")
  assert(bounds.left and bounds.right and bounds.top and bounds.bottom, "Hero movement bounds must be configured")

  hero.motocrotte_motion = hero.motocrotte_motion or { vx = 0, vy = 0 }
  local motion = hero.motocrotte_motion
  local horizontal = intent.horizontal or 0
  local vertical = intent.vertical or 0
  if horizontal ~= 0 and hero.facing_enabled ~= false then
    hero.facing = horizontal > 0 and 1 or -1
  end
  local length = math.sqrt(horizontal * horizontal + vertical * vertical)
  if length > 1 then
    horizontal = horizontal / length
    vertical = vertical / length
  end

  local target_vx = horizontal * max_speed
  local target_vy = vertical * vertical_speed
  local acceleration_step = acceleration * dt
  local deceleration_step = deceleration * dt
  motion.vx = approach(motion.vx, target_vx, horizontal == 0 and deceleration_step or acceleration_step)
  motion.vy = approach(motion.vy, target_vy, vertical == 0 and deceleration_step or acceleration_step)

  hero.position.x = clamp(hero.position.x + motion.vx * dt, bounds.left, bounds.right)
  hero.position.ground_y = clamp(hero.position.ground_y + motion.vy * dt, bounds.top, bounds.bottom)
  motion.grounded = true
  motion.jump_pressed = intent.jump_pressed == true
end

return Movement
