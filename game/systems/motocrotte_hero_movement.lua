-- Data-driven free-map movement for the MotoCrotte hero.
local Movement = {}

local function normalize_angle(angle)
  while angle > math.pi do angle = angle - math.pi * 2 end
  while angle < -math.pi do angle = angle + math.pi * 2 end
  return angle
end

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

  hero.motocrotte_motion = hero.motocrotte_motion or {
    vx = 0,
    vy = 0,
    heading = 0,
    slip_angle = 0,
    drift_amount = 0,
    visual_rotation = 0
  }
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
  local drift_config = definition.drift or {}
  local drift_active = drift_config.enabled == true and intent.drift_active == true
  local traction = drift_active and (drift_config.traction or 1) or 1
  local horizontal_step = horizontal == 0 and deceleration_step or acceleration_step
  local vertical_step = vertical == 0 and deceleration_step or acceleration_step
  motion.vx = approach(motion.vx, target_vx, horizontal_step * traction)
  motion.vy = approach(motion.vy, target_vy, vertical_step * traction)

  local speed = math.sqrt(motion.vx * motion.vx + motion.vy * motion.vy)
  local desired_heading = motion.heading
  if horizontal ~= 0 or vertical ~= 0 then
    desired_heading = math.atan2(vertical, horizontal)
  end
  if speed > 0.001 then
    motion.heading = math.atan2(motion.vy, motion.vx)
  end
  motion.slip_angle = normalize_angle(motion.heading - desired_heading)
  motion.drift_active = drift_active
  motion.drift_amount = drift_active and math.min(1, math.abs(motion.slip_angle) / math.pi) or 0
  local visual_target = drift_active and motion.slip_angle or 0
  local max_visual_angle = drift_config.max_visual_angle or math.rad(28)
  visual_target = math.max(-max_visual_angle, math.min(max_visual_angle, visual_target))
  local rotation_response = drift_config.rotation_response or 8
  motion.visual_rotation = approach(motion.visual_rotation or 0, visual_target, rotation_response * dt)

  local animation_name = config.animation
  if animation_name then
    local moving = horizontal ~= 0 or vertical ~= 0
    if moving then
      if not hero.animation:is_playing() or hero.animation.current_name ~= animation_name then
        local animation = hero.animation.animations[animation_name]
        assert(animation, "Configured MotoCrotte movement animation is missing: " .. animation_name)
        animation.loop = config.animation_loop == true
        hero.animation:play(animation_name)
      end
    elseif hero.animation:is_playing() then
      hero.animation:stop()
    end
  end
  hero.animation:update(dt)

  hero.position.x = clamp(hero.position.x + motion.vx * dt, bounds.left, bounds.right)
  hero.position.ground_y = clamp(hero.position.ground_y + motion.vy * dt, bounds.top, bounds.bottom)
  motion.grounded = true
  motion.jump_pressed = intent.jump_pressed == true
  motion.speed = speed
  motion.desired_heading = desired_heading
end

return Movement
