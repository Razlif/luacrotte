-- Orchestrates profile-driven locomotion and drift without exposing internal modules.
local Locomotion = require("game.systems.motocrotte_locomotion")
local Drift = require("game.systems.motocrotte_drift")
local Dash = require("game.systems.motocrotte_dash")
local LegacyMovement = require("game.systems.motocrotte_legacy_movement")

local Movement = {}

local function normalize_angle(angle)
  while angle > math.pi do angle = angle - math.pi * 2 end
  while angle < -math.pi do angle = angle + math.pi * 2 end
  return angle
end

local function prepare_control_intent(intent, motion, config, controls, dt)
  if controls and (controls.schema == "throttle_steering" or controls.schema == "gas_steering" or controls.schema == "gas_steering_fd") then
    local throttle = intent.throttle or 0
    local steering = intent.steering or 0
    local turn_rate = config.steering_rate or config.max_turn_rate or math.rad(180)
    local heading = motion.steering_heading or motion.heading or 0
    heading = heading + steering * turn_rate * dt
    motion.steering_heading = heading
    intent.horizontal = math.cos(heading) * throttle
    intent.vertical = math.sin(heading) * throttle
  end
  if config.constraint == "heading_cone" and not intent.drift_active then
    local x = intent.horizontal or 0
    local y = intent.vertical or 0
    local length = math.sqrt(x * x + y * y)
    if length > 0 then
      local current = motion.heading or 0
      local delta = normalize_angle(math.atan2(y, x) - current)
      local cone = config.cone_angle or math.rad(45)
      delta = math.max(-cone, math.min(cone, delta))
      local target = current + delta
      intent.horizontal = math.cos(target) * length
      intent.vertical = math.sin(target) * length
    end
  end
  return intent
end

local function required_number(table_value, key, label)
  local value = table_value and table_value[key]
  assert(type(value) == "number", label .. "." .. key .. " must be configured")
  return value
end

function Movement.update(hero, intent, definition, level_definition, dt)
  assert(hero and hero.position, "MotoCrotte hero position is required")
  assert(definition and definition.movement, "MotoCrotte hero movement data is required")
  assert(level_definition and level_definition.hero_bounds, "MotoCrotte hero bounds are required")
  assert(type(dt) == "number" and dt >= 0, "Delta time must be non-negative")

  if definition.movement.solver == "legacy_direct_drift" then
    return LegacyMovement.update(hero, intent, definition, level_definition, dt)
  end

  local config = definition.movement
  required_number(config, "acceleration", "hero movement")
  required_number(config, "max_speed", "hero movement")
  assert(config.coast_deceleration or config.deceleration, "hero movement.coast_deceleration is required")
  local bounds = level_definition.hero_bounds

  hero.motocrotte_motion = hero.motocrotte_motion or {
    vx = 0, vy = 0, speed = 0, heading = 0, desired_heading = 0,
    slip_angle = 0, drift_amount = 0, visual_rotation = 0,
    drift_spin_phase = 0, drift_spin_direction = 1, drift_phase = "normal"
  }
  local motion = hero.motocrotte_motion
  prepare_control_intent(intent, motion, config, definition.controls, dt)
  local was_wheelie_spin_active = motion.wheelie_spin_active == true
  local dash_context = Dash.update(motion, intent, definition, dt, {
    x = hero.position.x,
    y = hero.position.ground_y
  })
  local drift_context = Drift.update(motion, intent, definition, dt, {
    x = hero.position.x,
    y = hero.position.ground_y
  })
  local horizontal, vertical, input_length = Locomotion.update(motion, intent, config, drift_context, dt)

  if dash_context.velocity_x and not drift_context.active then
    motion.vx = dash_context.velocity_x
    motion.vy = dash_context.velocity_y
    motion.speed = math.sqrt(motion.vx * motion.vx + motion.vy * motion.vy)
    motion.heading = dash_context.heading
    motion.desired_heading = dash_context.heading
  end

  local braking_visual = definition.braking_visual or {}
  local steering_input = intent.steering or 0
  motion.braking = intent.brake == true and motion.speed > (braking_visual.minimum_speed or 5)
  motion.braking_tilt_direction = motion.braking and (steering_input < 0 and -1 or steering_input > 0 and 1 or 0) or 0
  motion.braking_tilt_angle = braking_visual.enabled ~= false and motion.braking_tilt_direction ~= 0
    and motion.braking_tilt_direction * (braking_visual.angle or math.rad(45)) or 0

  if drift_context.release_heading then
    local released_heading = drift_context.release_heading
    local released_speed = motion.speed or 0
    motion.heading = released_heading
    motion.desired_heading = released_heading
    motion.steering_heading = released_heading
    motion.vx = math.cos(released_heading) * released_speed
    motion.vy = math.sin(released_heading) * released_speed
    motion.drift_state.release_heading = nil
  end

  local desired_heading = motion.desired_heading or motion.heading or 0
  motion.slip_angle = 0
  if input_length > 0 then
    desired_heading = math.atan2(vertical, horizontal)
    motion.desired_heading = desired_heading
    local delta = desired_heading - (motion.heading or 0)
    while delta > math.pi do delta = delta - math.pi * 2 end
    while delta < -math.pi do delta = delta + math.pi * 2 end
    motion.slip_angle = delta
  end
  motion.drift_amount = drift_context.active and math.min(1, math.abs(motion.slip_angle) / math.pi) or 0
  motion.braking = motion.braking or false

  if horizontal ~= 0 and hero.facing_enabled ~= false then
    hero.facing = horizontal > 0 and 1 or -1
  end

  local animation_name = config.animation
  if animation_name then
    if input_length > 0 then
      if not hero.animation:is_playing() or hero.animation.current_name ~= animation_name then
        local animation = hero.animation.animations[animation_name]
        assert(animation, "Configured MotoCrotte movement animation is missing: " .. animation_name)
        animation.loop = config.animation_loop == true
        hero.animation:play(animation_name)
      end
    elseif hero.animation:is_playing() and config.animation_idle ~= true then
      hero.animation:stop()
    end
  end
  hero.animation:update(dt)
  Locomotion.apply_position(hero, motion, bounds, dt)
  if dash_context.wheelie_spin_active then
    hero.position.x = dash_context.wheelie_contact_x or hero.position.x
    hero.position.ground_y = dash_context.wheelie_contact_y or hero.position.ground_y
    motion.vx = 0
    motion.vy = 0
    motion.speed = 0
    motion.turning_radius = 0
  elseif was_wheelie_spin_active and not dash_context.wheelie_spin_active then
    Drift.reanchor(motion, {
      x = hero.position.x,
      y = hero.position.ground_y
    })
  elseif drift_context.orbit_position then
    hero.position.x = math.max(bounds.left, math.min(bounds.right, drift_context.orbit_position.x))
    hero.position.ground_y = math.max(bounds.top, math.min(bounds.bottom, drift_context.orbit_position.y))
    motion.vx = drift_context.orbit_velocity_x or 0
    motion.vy = drift_context.orbit_velocity_y or 0
    motion.speed = math.sqrt(motion.vx * motion.vx + motion.vy * motion.vy)
    motion.heading = math.atan2(motion.vy, motion.vx)
    motion.turning_radius = motion.drift_orbit_radius or 0
  end
  motion.grounded = true
  motion.jump_pressed = intent.jump_pressed == true
  motion.speed = math.sqrt(motion.vx * motion.vx + motion.vy * motion.vy)
end

return Movement
