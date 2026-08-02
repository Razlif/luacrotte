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
    orbit_radius = nil,
    orbit_angle = nil,
    orbit_center_x = nil,
    orbit_center_y = nil,
    slip_angle = 0,
    variant_index = nil
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
  local current = state(motion)
  local requested = config.enabled == true and intent.drift_active == true
  local speed = motion.speed or 0
  local minimum_speed = config.minimum_speed or 1
  local phase = current.phase
  local steering_heading = desired_heading(intent, motion.heading or 0)
  motion.desired_heading = steering_heading
  if requested and phase == "normal" and speed >= minimum_speed then
    current.phase = "entering"
    current.phase_time = 0
    current.variant_index = choose_variant(definition)
    current.spin_distance = 0
    local pivot = (config.directional_views or {}).directional_pivot or {}
    current.spin_phase = (motion.heading or 0) - (pivot.facing_offset or math.pi)
    current.orbit_radius = config.orbit_radius_default or pivot.radius or 0
    current.orbit_angle = current.spin_phase
    local px = position and position.x or 0
    local py = position and position.y or 0
    current.orbit_center_x = px - math.cos(current.orbit_angle) * current.orbit_radius
    current.orbit_center_y = py - math.sin(current.orbit_angle) * current.orbit_radius
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
    if current.phase_time >= (config.exit_time or 0.02)
      and (current.spin_distance or 0) >= minimum_spin then
      -- Commit the released drift orientation as the new movement heading.
      -- Without this handoff, the renderer immediately resolves normal
      -- movement from the pre-drift heading and visually snaps the bike back.
      local pivot = (config.directional_views or {}).directional_pivot or {}
      current.release_heading = normalize_angle(current.spin_phase + (pivot.facing_offset or math.pi))
      current.phase = "normal"
      current.phase_time = 0
    end
  end

  local active = current.phase ~= "normal"
  local exit_progress = current.phase == "exiting" and clamp(
    current.phase_time / math.max(config.exit_time or 0.01, 0.01), 0, 1
  ) or 0
  local grip = active and (config.drift_grip or config.traction or 0.36) or (config.normal_grip or 1)
  if current.phase == "exiting" then
    grip = grip + ((config.normal_grip or 1) - grip) * exit_progress
  end

  local steering_input = intent.steering or 0
  local turn_rate = active and (config.spin_speed or math.rad(360)) or 0
  if active and steering_input ~= 0 then
    current.spin_direction = steering_input > 0 and 1 or -1
  end
  if active then
    local pivot = (config.directional_views or {}).directional_pivot or {}
    local minimum_radius = config.orbit_radius_min or pivot.radius_min or 0
    local maximum_radius = config.orbit_radius_max or pivot.radius_max or 100
    local radius_rate = config.orbit_radius_rate or 80
    if intent.drift_radius_increase then
      current.orbit_radius = clamp((current.orbit_radius or pivot.radius or 0) + radius_rate * dt, minimum_radius, maximum_radius)
    elseif intent.drift_radius_decrease then
      current.orbit_radius = clamp((current.orbit_radius or pivot.radius or 0) - radius_rate * dt, minimum_radius, maximum_radius)
    end
    local spin_delta = current.spin_direction * (config.spin_speed or math.rad(360)) * dt
    current.spin_phase = current.spin_phase + spin_delta
    current.spin_distance = (current.spin_distance or 0) + math.abs(spin_delta)
    local animation = definition.directional_animation or {}
    if (animation.variant_policy == "random_per_drift" or animation.variant_policy == "random_per_spin") and current.spin_distance >= math.pi * 2 then
      current.spin_distance = current.spin_distance % (math.pi * 2)
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
  motion.drift_orbit_radius = current.orbit_radius

  local orbit_position
  local orbit_velocity_x
  local orbit_velocity_y
  local orbit_active = current.phase ~= "normal" or current.release_heading ~= nil
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

  return {
    active = active,
    phase = current.phase,
    grip = grip,
    turn_rate = turn_rate,
    deceleration = config.drift_deceleration or 0,
    variant_index = current.variant_index,
    orbit_radius = current.orbit_radius,
    orbit_position = orbit_position,
    orbit_velocity_x = orbit_velocity_x,
    orbit_velocity_y = orbit_velocity_y,
    release_heading = current.release_heading
  }
end

return Drift
