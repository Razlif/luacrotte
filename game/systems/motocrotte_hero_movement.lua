-- Orchestrates profile-driven locomotion and drift without exposing internal modules.
local Locomotion = require("game.systems.motocrotte_locomotion")
local Drift = require("game.systems.motocrotte_drift")
local Dash = require("game.systems.motocrotte_dash")
local LegacyMovement = require("game.systems.motocrotte_legacy_movement")

local Movement = {}

local function update_jump(hero, intent, definition, dt)
  local config = definition.jump or {}
  if config.enabled ~= true then return end
  local motion = hero.motocrotte_motion
  motion.jump_state = motion.jump_state or "grounded"
  motion.jump_elapsed = motion.jump_elapsed or 0
  motion.jump_landing_elapsed = motion.jump_landing_elapsed or 0
  motion.jump_visual_rotation = 0
  motion.jump_scale_x = 1
  motion.jump_scale_y = 1

  if motion.jump_state == "grounded" then
    local requested_mode = intent.jump_wheelie_pressed and "wheelie"
      or intent.jump_wave_pressed and "wave"
      or intent.jump_pressed and "wave"
    if requested_mode then
      motion.jump_state = "airborne"
      motion.jump_mode = requested_mode
      motion.jump_elapsed = 0
      motion.jump_landing_elapsed = 0
      motion.jump_start_z = hero.position.z or 0
    end
  end

  if motion.jump_state == "airborne" then
    local duration = config.duration or 0.68
    local previous = motion.jump_elapsed / duration
    motion.jump_elapsed = math.min(duration, motion.jump_elapsed + dt)
    local progress = motion.jump_elapsed / duration
    local previous_arc = math.sin(math.max(0, math.min(1, previous)) * math.pi)
    local arc = math.sin(progress * math.pi)
    local jump_height = config.height or 72
    if motion.jump_mode == "wheelie" then
      jump_height = (config.wheelie or {}).height or jump_height
    else
      jump_height = (config.wave or {}).height or jump_height
    end
    hero.position.z = (motion.jump_start_z or 0) + jump_height * arc

    if motion.jump_mode == "wheelie" then
      local wheelie = config.wheelie or {}
      local ramp = math.min(1, progress * 5)
      local settle = progress > 0.72 and math.max(0, 1 - (progress - 0.72) / 0.28) or 1
      motion.jump_visual_rotation = (wheelie.angle or -math.rad(45)) * ramp * settle
    else
      local wave = config.wave or {}
      motion.jump_visual_rotation = (wave.pitch or math.rad(12))
        * math.sin(progress * math.pi * 2 * (wave.cycles or 1.15) + (wave.phase_offset or 0))
      -- The wave is intentionally a rotation-only test.  Squash/stretch is
      -- reserved for a later effect pass after the jump shapes are tuned.
      motion.jump_scale_x = 1
      motion.jump_scale_y = 1
    end

    if progress >= 1 then
      hero.position.z = motion.jump_start_z or 0
      motion.jump_state = "landing"
      motion.jump_elapsed = 0
      motion.jump_landing_elapsed = 0
      motion.jump_visual_rotation = 0
      motion.jump_scale_x = 1.12
      motion.jump_scale_y = 0.82
    end
  elseif motion.jump_state == "landing" then
    local wave = config.wave or {}
    local landing_duration = wave.landing_duration or 0.42
    motion.jump_landing_elapsed = math.min(landing_duration, motion.jump_landing_elapsed + dt)
    local progress = motion.jump_landing_elapsed / landing_duration
    local shock_count = wave.aftershock_count or 3
    local shock = math.sin(progress * math.pi * 2 * shock_count) * math.max(0, 1 - progress)
    motion.jump_visual_rotation = (wave.aftershock_angle or math.rad(7)) * shock
    motion.jump_scale_x = 1 + 0.12 * math.max(0, 1 - progress)
    motion.jump_scale_y = 1 - 0.18 * math.max(0, 1 - progress)
    if progress >= 1 then
      motion.jump_state = "grounded"
      motion.jump_mode = nil
      motion.jump_visual_rotation = 0
      motion.jump_scale_x = 1
      motion.jump_scale_y = 1
    end
  end
end

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
  assert(level_definition, "MotoCrotte level definition is required")
  assert(type(dt) == "number" and dt >= 0, "Delta time must be non-negative")

  if definition.movement.solver == "legacy_direct_drift" then
    return LegacyMovement.update(hero, intent, definition, level_definition, dt)
  end

  local config = definition.movement
  required_number(config, "acceleration", "hero movement")
  required_number(config, "max_speed", "hero movement")
  assert(config.coast_deceleration or config.deceleration, "hero movement.coast_deceleration is required")
  -- Temporary unbounded playground profiles intentionally omit hero_bounds.
  -- Keep finite fallbacks for drift/orbit math while leaving normal movement
  -- unclamped.
  local bounds = level_definition.hero_bounds or {
    left = -1000000000, right = 1000000000,
    top = -1000000000, bottom = 1000000000
  }

  hero.motocrotte_motion = hero.motocrotte_motion or {
    vx = 0, vy = 0, speed = 0, heading = 0, desired_heading = 0,
    slip_angle = 0, drift_amount = 0, visual_rotation = 0,
    drift_spin_phase = 0, drift_spin_direction = 1, drift_phase = "normal",
    drift_mode = "straight", drift_straight_tilt_direction = 0,
    drift_orbit_radius_base = 0, drift_orbit_radius_scale = 1,
    drift_spin_rounds = 0, drift_spin_momentum = 0,
    drift_gas_brake_disabled = false, drift_control_active = false,
    drift_slingshot_active = false, drift_slingshot_speed = 0
  }
  local motion = hero.motocrotte_motion
  prepare_control_intent(intent, motion, config, definition.controls, dt)
  local was_wheelie_spin_active = motion.wheelie_spin_active == true
  local dash_context = Dash.update(motion, intent, definition, dt, {
    x = hero.position.x,
    y = hero.position.ground_y
  })
  local dash_config = definition.dash or {}
  local minimum_orbit_combo = dash_context.wheelie_spin_active
    and dash_config.drift_combo_mode == "minimum_orbit"
  local orbit_radius_override = minimum_orbit_combo
    and (dash_config.drift_combo_orbit_radius or 5)
    or nil
  local drift_context = Drift.update(motion, intent, definition, dt, {
    x = hero.position.x,
    y = hero.position.ground_y,
    orbit_radius_override = orbit_radius_override
  })
  local horizontal, vertical, input_length = Locomotion.update(motion, intent, config, drift_context, dt)
  update_jump(hero, intent, definition, dt)

  -- Once Shift is released, normal movement owns the next frame immediately.
  -- The drift release velocity is only a fallback for an uncommanded glide;
  -- it must never overwrite fresh gas, brake, or steering input.
  local player_has_control = input_length > 0
    or (intent.steering ~= nil and intent.steering ~= 0)
    or intent.brake == true

  if dash_context.velocity_x and not drift_context.active then
    motion.vx = dash_context.velocity_x
    motion.vy = dash_context.velocity_y
    motion.speed = math.sqrt(motion.vx * motion.vx + motion.vy * motion.vy)
    motion.heading = dash_context.heading
    motion.desired_heading = dash_context.heading
  end

  local steering_input = intent.steering or 0
  local was_braking = motion.braking == true
  -- The brake key owns this presentation state for its entire hold, including
  -- the final stopped frame. This makes a held brake + steer a stable skid.
  motion.braking = intent.brake == true
  if motion.braking and not was_braking then
    -- Braking is a planted skid. Preserve travel-facing; steering chooses
    -- only the 45-degree lean rather than rotating the bike in place.
    motion.braking_heading = motion.heading or motion.desired_heading or 0
  elseif not motion.braking then
    motion.braking_heading = nil
  end
  -- The neighboring directional frame belongs to drift now. Braking only
  -- affects velocity and keeps the current facing/animation presentation.
  motion.braking_tilt_direction = 0
  motion.braking_tilt_angle = 0

  local slingshot_can_hold_course = drift_context.slingshot_active
    and not player_has_control
  if drift_context.slingshot_active
      and (drift_context.control_active or slingshot_can_hold_course) then
    motion.vx = drift_context.slingshot_velocity_x or motion.vx
    motion.vy = drift_context.slingshot_velocity_y or motion.vy
    motion.speed = math.sqrt(motion.vx * motion.vx + motion.vy * motion.vy)
    motion.heading = math.atan2(motion.vy, motion.vx)
    motion.desired_heading = motion.heading
    motion.steering_heading = motion.heading
  elseif drift_context.slingshot then
    local slingshot = drift_context.slingshot
    motion.vx = slingshot.velocity_x or motion.vx
    motion.vy = slingshot.velocity_y or motion.vy
    motion.speed = math.sqrt(motion.vx * motion.vx + motion.vy * motion.vy)
    motion.heading = slingshot.heading or math.atan2(motion.vy, motion.vx)
    motion.desired_heading = motion.heading
    motion.steering_heading = motion.heading
  elseif drift_context.release_velocity_x ~= nil and not player_has_control then
    motion.vx = drift_context.release_velocity_x
    motion.vy = drift_context.release_velocity_y or 0
    motion.speed = math.sqrt(motion.vx * motion.vx + motion.vy * motion.vy)
    motion.heading = drift_context.release_heading or math.atan2(motion.vy, motion.vx)
    motion.desired_heading = motion.heading
    motion.steering_heading = motion.heading
    motion.drift_state.release_velocity_x = nil
    motion.drift_state.release_velocity_y = nil
    motion.drift_state.release_speed = nil
    motion.drift_state.release_reason = nil
    motion.drift_state.release_heading = nil
  elseif drift_context.release_velocity_x ~= nil and player_has_control then
    -- Consume the one-shot release handoff without applying it. Locomotion
    -- already resolved the user's current gas/brake/steering input above.
    motion.drift_state.release_velocity_x = nil
    motion.drift_state.release_velocity_y = nil
    motion.drift_state.release_speed = nil
    motion.drift_state.release_reason = nil
    motion.drift_state.release_heading = nil
  elseif drift_context.release_heading and not player_has_control then
    local released_heading = drift_context.release_heading
    local released_speed = motion.speed or 0
    motion.heading = released_heading
    motion.desired_heading = released_heading
    motion.steering_heading = released_heading
    motion.vx = math.cos(released_heading) * released_speed
    motion.vy = math.sin(released_heading) * released_speed
    motion.drift_state.release_heading = nil
  elseif drift_context.release_heading and player_has_control then
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
  Locomotion.constrain_velocity(hero, motion, bounds)
  if dash_context.wheelie_spin_active and not minimum_orbit_combo then
    motion.vx = 0
    motion.vy = 0
    motion.speed = 0
    motion.turning_radius = 0
  elseif was_wheelie_spin_active and not dash_context.wheelie_spin_active and not minimum_orbit_combo then
    Drift.reanchor(motion, {
      x = hero.position.x,
      y = hero.position.ground_y
    })
  elseif drift_context.orbit_position then
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
