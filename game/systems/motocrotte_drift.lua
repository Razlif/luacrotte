-- Drift state machine and continuous presentation phase.
local Drift = {}

local function normalize_angle(angle)
  while angle > math.pi do angle = angle - math.pi * 2 end
  while angle < -math.pi do angle = angle + math.pi * 2 end
  return angle
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function configured_radius(config, pivot)
  local base = config.orbit_radius_default or pivot.radius or 0
  local scale = config.orbit_radius_scale or 1
  return base, base * scale
end

local function tangent_velocity(current, config, extra_speed)
  local angle = current.spin_phase or current.orbit_angle or 0
  local direction = current.spin_direction or 1
  local radius = current.orbit_radius or 0
  local spin_speed = config.spin_speed or math.rad(360)
  local base_speed = math.abs(spin_speed * radius)
  local speed = base_speed + (extra_speed or 0)
  local tangent_x = -math.sin(angle) * direction
  local tangent_y = math.cos(angle) * direction
  return tangent_x * speed, tangent_y * speed, speed, math.atan2(tangent_y, tangent_x)
end

local function desired_heading(intent, fallback)
  local x = intent.horizontal or 0
  local y = intent.vertical or 0
  if x == 0 and y == 0 then return fallback end
  return math.atan2(y, x)
end

local function state(motion)
  motion.drift_state = motion.drift_state or {
    phase = "normal",
    phase_time = 0,
    spin_phase = motion.drift_spin_phase or 0,
    spin_direction = motion.drift_spin_direction or 1,
    spin_distance = 0,
    variant_spin_distance = 0,
    spin_rounds = 0,
    spin_momentum = 0,
    steering_input = 0,
    mode = "straight",
    straight_tilt_direction = 1,
    orbit_radius = nil,
    orbit_angle = nil,
    orbit_center_x = nil,
    orbit_center_y = nil,
    slip_angle = 0,
    variant_index = nil,
    slingshot_velocity_x = nil,
    slingshot_velocity_y = nil,
    slingshot_heading = nil
  }
  return motion.drift_state
end

local function choose_variant(config)
  local animation = config.directional_animation or {}
  if animation.variant_policy ~= "random_per_drift" and animation.variant_policy ~= "random_per_spin" then return nil end
  local variants = animation.variant_sets or {}
  if #variants == 0 then return nil end
  return math.random(#variants)
end

function Drift.update(motion, intent, definition, dt, position)
  local config = definition.drift or {}
  local straight_orbit_model = config.behavior == "straight_orbit"
  local current = state(motion)
  local previous_steering = current.steering_input or 0
  local slingshot = nil
  motion.drift_slingshot = nil
  if current.slingshot_velocity_x ~= nil then
    local boost_speed = math.sqrt(
      current.slingshot_velocity_x * current.slingshot_velocity_x
        + current.slingshot_velocity_y * current.slingshot_velocity_y
    )
    boost_speed = math.max(0, boost_speed - (config.slingshot_decay or 700) * dt)
    if boost_speed <= (config.slingshot_min_speed or 1) then
      current.slingshot_velocity_x = nil
      current.slingshot_velocity_y = nil
      current.slingshot_heading = nil
    else
      local heading = current.slingshot_heading
        or math.atan2(current.slingshot_velocity_y, current.slingshot_velocity_x)
      current.slingshot_heading = heading
      current.slingshot_velocity_x = math.cos(heading) * boost_speed
      current.slingshot_velocity_y = math.sin(heading) * boost_speed
    end
  end
  current.mode = current.mode or (straight_orbit_model and "straight" or "orbit")
  current.straight_tilt_direction = current.straight_tilt_direction or config.straight_tilt_direction or 1
  local requested = config.enabled == true and intent.drift_active == true
  local speed = motion.speed or 0
  local minimum_speed = config.minimum_speed or 1
  local phase = current.phase
  local steering_heading = desired_heading(intent, motion.heading or 0)
  motion.desired_heading = steering_heading
  if requested and phase == "normal" and speed >= minimum_speed then
    current.phase = "entering"
    current.phase_time = 0
    current.mode = straight_orbit_model and "straight" or "orbit"
    current.straight_tilt_direction = config.straight_tilt_direction or 1
    current.variant_index = choose_variant(definition)
    current.spin_distance = 0
    current.variant_spin_distance = 0
    current.spin_rounds = 0
    current.spin_momentum = 0
    current.steering_input = 0
    current.slingshot_velocity_x = nil
    current.slingshot_velocity_y = nil
    current.slingshot_heading = nil
    local pivot = (config.directional_views or {}).directional_pivot or {}
    current.spin_phase = (motion.heading or 0) - (pivot.facing_offset or math.pi)
    if current.mode == "orbit" then
      local _, effective_radius = configured_radius(config, pivot)
      current.orbit_radius = effective_radius
      current.orbit_angle = current.spin_phase
      local px = position and position.x or 0
      local py = position and position.y or 0
      current.orbit_center_x = px - math.cos(current.orbit_angle) * current.orbit_radius
      current.orbit_center_y = py - math.sin(current.orbit_angle) * current.orbit_radius
    else
      current.orbit_radius = nil
      current.orbit_angle = nil
      current.orbit_center_x = nil
      current.orbit_center_y = nil
    end
  elseif not requested and (phase == "entering" or phase == "holding") then
    current.phase = "exiting"
    current.phase_time = 0
  end

  if current.phase == "entering" then
    current.phase_time = current.phase_time + dt
    if current.phase_time >= (config.entry_time or 0) then
      current.phase = "holding"
      current.phase_time = 0
    end
  elseif current.phase == "exiting" then
    current.phase_time = current.phase_time + dt
    local minimum_spin = config.minimum_spin or math.rad(90)
    local exit_ready = current.phase_time >= (config.exit_time or 0.02)
      and (straight_orbit_model or (current.spin_distance or 0) >= minimum_spin)
    if exit_ready then
      -- Commit the released drift orientation as the new movement heading.
      -- Without this handoff, the renderer immediately resolves normal
      -- movement from the pre-drift heading and visually snaps the bike back.
      if current.mode == "orbit" then
        local vx, vy, speed, heading = tangent_velocity(current, config, current.spin_momentum)
        current.release_velocity_x = vx
        current.release_velocity_y = vy
        current.release_speed = speed
        current.release_heading = heading
      else
        current.release_velocity_x = math.cos(motion.heading or 0) * (motion.speed or 0)
        current.release_velocity_y = math.sin(motion.heading or 0) * (motion.speed or 0)
        current.release_speed = motion.speed or 0
        current.release_heading = normalize_angle(motion.heading or 0)
      end
      current.release_reason = "drift_release"
      current.phase = "normal"
      current.phase_time = 0
      current.mode = "straight"
    end
  end

  local active = current.phase ~= "normal"
  local control_active = requested and active
  local override_radius = position and position.orbit_radius_override
  if active and override_radius ~= nil and not (straight_orbit_model and current.mode == "straight") then
    if current.forced_orbit_radius ~= override_radius then
      current.orbit_radius = override_radius
      current.orbit_angle = current.spin_phase
      local px = position.x or 0
      local py = position.y or 0
      current.orbit_center_x = px - math.cos(current.orbit_angle) * override_radius
      current.orbit_center_y = py - math.sin(current.orbit_angle) * override_radius
      current.forced_orbit_radius = override_radius
    end
  else
    current.forced_orbit_radius = nil
  end
  local exit_progress = current.phase == "exiting" and clamp(
    current.phase_time / math.max(config.exit_time or 0.01, 0.01), 0, 1
  ) or 0
  local grip = active and (config.drift_grip or config.traction or 0.36) or (config.normal_grip or 1)
  if current.phase == "exiting" then
    grip = grip + ((config.normal_grip or 1) - grip) * exit_progress
  end

  local steering_input = intent.steering or 0
  if straight_orbit_model and active then
    if current.mode == "orbit" and steering_input == 0 then
      if previous_steering ~= 0 then
        local vx, vy, base_speed, heading = tangent_velocity(current, config, current.spin_momentum)
        local impulse = config.slingshot_impulse or 0
        local full_speed = base_speed + impulse
        local tangent_x = math.cos(heading)
        local tangent_y = math.sin(heading)
        vx = tangent_x * full_speed
        vy = tangent_y * full_speed
        current.slingshot_velocity_x = vx
        current.slingshot_velocity_y = vy
        current.slingshot_heading = heading
        slingshot = {
          velocity_x = vx,
          velocity_y = vy,
          speed = full_speed,
          base_speed = base_speed,
          impulse = impulse,
          decay = config.slingshot_decay or 700,
          heading = heading,
          reason = "steering_release",
          spin_rounds = current.spin_rounds or 0,
          spin_momentum = current.spin_momentum or 0
        }
      end
      -- Releasing steering returns to straight drift immediately. Keep the
      -- radius stored for the next steering entry, but stop orbit movement.
      current.mode = "straight"
      current.straight_tilt_direction = 0
      current.orbit_angle = nil
      current.orbit_center_x = nil
      current.orbit_center_y = nil
    elseif current.mode == "straight" and steering_input ~= 0 then
      current.slingshot_velocity_x = nil
      current.slingshot_velocity_y = nil
      current.slingshot_heading = nil
      current.mode = "orbit"
      local pivot = (config.directional_views or {}).directional_pivot or {}
      local _, effective_radius = configured_radius(config, pivot)
      if current.orbit_radius == nil or config.radius_control == "fixed" then
        current.orbit_radius = effective_radius
      end
      if current.straight_tilt_direction ~= 0 then
        local step = (math.pi * 2) / (config.directional_views and config.directional_views.count or 8)
        current.spin_phase = current.spin_phase + current.straight_tilt_direction * step
        current.straight_tilt_direction = 0
      end
      current.orbit_angle = current.spin_phase
      local px = position and position.x or 0
      local py = position and position.y or 0
      current.orbit_center_x = px - math.cos(current.orbit_angle) * current.orbit_radius
      current.orbit_center_y = py - math.sin(current.orbit_angle) * current.orbit_radius
    end
  end
  current.steering_input = steering_input
  local turn_rate = active and (config.spin_speed or math.rad(360)) or 0
  if active and steering_input ~= 0 then
    current.spin_direction = steering_input > 0 and 1 or -1
  end
  if active and (not straight_orbit_model or current.mode == "orbit") then
    local pivot = (config.directional_views or {}).directional_pivot or {}
    local minimum_radius = config.orbit_radius_min or pivot.radius_min or 0
    local radius_control = config.radius_control or "gas"
    if radius_control == "gas" then
      local maximum_radius = config.orbit_radius_unbounded
        and math.huge
        or (config.orbit_radius_max or pivot.radius_max or 100)
      local increase_rate = config.orbit_radius_growth or config.orbit_radius_rate or 80
      local decrease_rate = config.orbit_radius_shrink_rate or config.orbit_radius_decrease_rate or increase_rate
      if current.forced_orbit_radius == nil and intent.drift_radius_increase then
        current.orbit_radius = clamp((current.orbit_radius or config.orbit_radius_start or pivot.radius or 0) + increase_rate * dt, minimum_radius, maximum_radius)
      elseif current.forced_orbit_radius == nil and intent.drift_radius_decrease then
        current.orbit_radius = clamp((current.orbit_radius or pivot.radius or 0) - decrease_rate * dt, minimum_radius, maximum_radius)
      end
    end
    local spin_delta = current.spin_direction * (config.spin_speed or math.rad(360)) * dt
    current.spin_phase = current.spin_phase + spin_delta
    current.spin_distance = (current.spin_distance or 0) + math.abs(spin_delta)
    current.variant_spin_distance = (current.variant_spin_distance or 0) + math.abs(spin_delta)
    local completed_rounds = math.floor(current.spin_distance / (math.pi * 2))
    local max_spin_rounds = config.max_spin_rounds or 3
    local awarded_rounds = math.min(completed_rounds, max_spin_rounds)
    if awarded_rounds > (current.spin_rounds or 0) then
      local new_rounds = awarded_rounds - (current.spin_rounds or 0)
      local per_round = config.spin_momentum_per_round or 0
      local momentum_cap = config.spin_momentum_cap or math.huge
      current.spin_momentum = math.min(
        momentum_cap,
        (current.spin_momentum or 0) + new_rounds * per_round
      )
      current.spin_rounds = awarded_rounds
    end
    local animation = definition.directional_animation or {}
    if (animation.variant_policy == "random_per_drift" or animation.variant_policy == "random_per_spin") and current.variant_spin_distance >= math.pi * 2 then
      current.variant_spin_distance = current.variant_spin_distance % (math.pi * 2)
      current.variant_index = choose_variant(definition)
    end
  end

  current.slip_angle = normalize_angle((motion.heading or 0) - (motion.desired_heading or motion.heading or 0))
  motion.drift_spin_phase = current.spin_phase
  motion.drift_yaw_phase = current.spin_phase
  motion.drift_spin_direction = current.spin_direction
  motion.drift_active = active
  motion.drift_amount = active and math.min(1, math.abs(current.slip_angle) / math.pi) or 0
  motion.drift_phase = current.phase
  motion.drift_variant_index = current.variant_index
  motion.drift_orbit_radius = current.mode == "orbit" and current.orbit_radius or nil
  local pivot = (config.directional_views or {}).directional_pivot or {}
  local base_radius, effective_radius = configured_radius(config, pivot)
  motion.drift_orbit_radius_base = base_radius
  motion.drift_orbit_radius_scale = config.orbit_radius_scale or 1
  motion.drift_spin_rounds = current.spin_rounds or 0
  motion.drift_spin_momentum = current.spin_momentum or 0
  motion.drift_control_active = control_active
  motion.drift_gas_brake_disabled = control_active and config.disable_gas_brake == true or false
  local slingshot_active = current.slingshot_velocity_x ~= nil
  local slingshot_speed = slingshot_active and math.sqrt(
    current.slingshot_velocity_x * current.slingshot_velocity_x
      + current.slingshot_velocity_y * current.slingshot_velocity_y
  ) or 0
  motion.drift_slingshot_active = slingshot_active
  motion.drift_slingshot_speed = slingshot_speed
  motion.drift_mode = current.mode
  motion.drift_straight_tilt_direction = active and current.mode == "straight"
    and current.straight_tilt_direction or 0

  local orbit_position
  local orbit_velocity_x
  local orbit_velocity_y
  local orbit_active = current.phase ~= "normal"
    and (not straight_orbit_model or current.mode == "orbit")
    or current.release_heading ~= nil and current.mode == "orbit"
  if orbit_active and current.orbit_angle and current.orbit_center_x and current.orbit_center_y then
    current.orbit_angle = current.spin_phase
    local radius = current.orbit_radius or 0
    local spin_speed = config.spin_speed or math.rad(360)
    orbit_position = {
      x = current.orbit_center_x + math.cos(current.orbit_angle) * radius,
      y = current.orbit_center_y + math.sin(current.orbit_angle) * radius
    }
    orbit_velocity_x = -math.sin(current.orbit_angle) * spin_speed * radius * current.spin_direction
    orbit_velocity_y = math.cos(current.orbit_angle) * spin_speed * radius * current.spin_direction
  end

  if slingshot then
    motion.drift_slingshot = slingshot
    motion.drift_last_slingshot = slingshot
  end

  return {
    active = active,
    phase = current.phase,
    mode = current.mode,
    straight_tilt_direction = motion.drift_straight_tilt_direction,
    grip = grip,
    turn_rate = turn_rate,
    deceleration = config.drift_deceleration or 0,
    variant_index = current.variant_index,
    orbit_radius = current.orbit_radius,
    orbit_radius_base = base_radius,
    orbit_radius_effective = effective_radius,
    orbit_position = orbit_position,
    orbit_velocity_x = orbit_velocity_x,
    orbit_velocity_y = orbit_velocity_y,
    release_heading = current.release_heading,
    release_velocity_x = current.release_velocity_x,
    release_velocity_y = current.release_velocity_y,
    release_speed = current.release_speed,
    release_reason = current.release_reason,
    slingshot = slingshot,
    spin_rounds = current.spin_rounds or 0,
    spin_momentum = current.spin_momentum or 0,
    disable_gas_brake = control_active and config.disable_gas_brake == true or false,
    control_active = control_active,
    slingshot_active = slingshot_active,
    slingshot_velocity_x = current.slingshot_velocity_x,
    slingshot_velocity_y = current.slingshot_velocity_y,
    slingshot_speed = slingshot_speed
  }
end

function Drift.reanchor(motion, position)
  local current = motion.drift_state
  if not current or not current.orbit_angle or not position then return end
  local radius = current.orbit_radius or 0
  current.orbit_center_x = position.x - math.cos(current.orbit_angle) * radius
  current.orbit_center_y = position.y - math.sin(current.orbit_angle) * radius
end

return Drift
