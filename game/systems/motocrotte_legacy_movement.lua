-- Preserves the pre-modular Playground movement for side-by-side comparison.
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

function Movement.update(hero, intent, definition, level_definition, dt)
  local config = definition.movement
  local bounds = level_definition.hero_bounds
  local acceleration = config.acceleration
  local deceleration = config.deceleration or config.coast_deceleration
  local max_speed = config.max_speed
  local vertical_speed = config.vertical_speed or max_speed
  assert(type(acceleration) == "number", "legacy movement acceleration is required")
  assert(type(deceleration) == "number", "legacy movement deceleration is required")
  assert(type(max_speed) == "number", "legacy movement max_speed is required")

  hero.motocrotte_motion = hero.motocrotte_motion or {}
  local motion = hero.motocrotte_motion
  local horizontal = intent.horizontal or 0
  local vertical = intent.vertical or 0
  local length = math.sqrt(horizontal * horizontal + vertical * vertical)
  if length > 1 then
    horizontal, vertical = horizontal / length, vertical / length
  end
  if horizontal ~= 0 and hero.facing_enabled ~= false then
    hero.facing = horizontal > 0 and 1 or -1
  end

  local target_vx, target_vy = horizontal * max_speed, vertical * vertical_speed
  local drift = definition.drift or {}
  local active = drift.enabled == true and intent.drift_active == true
  local traction = active and (drift.traction or drift.drift_grip or 1) or 1
  local step_x = (horizontal == 0 and deceleration or acceleration) * dt * traction
  local step_y = (vertical == 0 and deceleration or acceleration) * dt * traction
  motion.vx = approach(motion.vx or 0, target_vx, step_x)
  motion.vy = approach(motion.vy or 0, target_vy, step_y)

  local speed = math.sqrt(motion.vx * motion.vx + motion.vy * motion.vy)
  local desired_heading = motion.heading or 0
  if length > 0 then desired_heading = math.atan2(vertical, horizontal) end
  if speed > 0.001 then motion.heading = math.atan2(motion.vy, motion.vx) end
  motion.desired_heading = desired_heading
  motion.slip_angle = normalize_angle((motion.heading or 0) - desired_heading)
  motion.drift_active = active
  motion.drift_phase = active and "holding" or "normal"
  motion.drift_amount = active and math.min(1, math.abs(motion.slip_angle) / math.pi) or 0

  local spin_direction = motion.drift_spin_direction or drift.spin_default_direction or 1
  local spin_phase = motion.drift_spin_phase or 0
  if active then
    local pivot = (drift.directional_views or {}).directional_pivot or {}
    if not motion._legacy_was_drifting then
      spin_phase = (motion.heading or 0) - (pivot.facing_offset or math.pi)
    end
    local steering_delta = normalize_angle(desired_heading - (motion.heading or 0))
    if math.abs(steering_delta) >= (drift.spin_steering_threshold or math.rad(10)) then
      spin_direction = steering_delta >= 0 and 1 or -1
    end
    spin_phase = spin_phase + spin_direction * (drift.spin_speed or math.pi * 2) * dt
  end
  motion._legacy_was_drifting = active
  motion.drift_spin_phase = spin_phase
  motion.drift_spin_direction = spin_direction
  motion.drift_variant_index = nil
  motion.turn_rate = 0
  motion.turning_radius = 0
  motion.braking = false
  motion.speed = speed

  local animation_name = config.animation
  if animation_name and hero.animation then
    if length > 0 then
      if not hero.animation:is_playing() or hero.animation.current_name ~= animation_name then
        local animation = hero.animation.animations[animation_name]
        assert(animation, "Configured MotoCrotte movement animation is missing: " .. animation_name)
        animation.loop = config.animation_loop == true
        hero.animation:play(animation_name)
      end
    elseif hero.animation:is_playing() and config.animation_idle ~= true then
      hero.animation:stop()
    end
    hero.animation:update(dt)
  end
  if hero.position.x <= bounds.left and motion.vx < 0 then motion.vx = 0 end
  if hero.position.x >= bounds.right and motion.vx > 0 then motion.vx = 0 end
  if hero.position.ground_y <= bounds.top and motion.vy < 0 then motion.vy = 0 end
  if hero.position.ground_y >= bounds.bottom and motion.vy > 0 then motion.vy = 0 end
  motion.grounded = true
  motion.jump_pressed = intent.jump_pressed == true
end

return Movement
