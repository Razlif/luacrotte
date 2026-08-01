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

function Drift.update(motion, intent, definition, dt)
  local config = definition.drift or {}
  local current = state(motion)
  local requested = config.enabled == true and intent.drift_active == true
  local speed = motion.speed or 0
  local minimum_speed = config.minimum_speed or 1
  local phase = current.phase
  local steering_heading = desired_heading(intent, motion.heading or 0)
  motion.desired_heading = steering_heading
  local input_x = intent.horizontal or 0
  local input_y = intent.vertical or 0
  local input_length = math.sqrt(input_x * input_x + input_y * input_y)

  if requested and phase == "normal" and speed >= minimum_speed then
    current.phase = "entering"
    current.phase_time = 0
    current.variant_index = choose_variant(definition)
    current.spin_distance = 0
    local pivot = (config.directional_views or {}).directional_pivot or {}
    current.spin_phase = (motion.heading or 0) - (pivot.facing_offset or math.pi)
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
    if current.phase_time >= (config.exit_time or 0) then
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

  local steering_delta = normalize_angle(steering_heading - (motion.heading or 0))
  local steering_strength = math.min(1, math.abs(steering_delta) / math.pi)
  local turn_rate = active and input_length > 0 and (config.drift_turn_rate or config.max_turn_rate or math.rad(180)) * steering_strength or 0
  if active and math.abs(steering_delta) >= (config.spin_steering_threshold or math.rad(10)) then
    current.spin_direction = steering_delta >= 0 and 1 or -1
  end
  if active then
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

  return {
    active = active,
    phase = current.phase,
    grip = grip,
    turn_rate = turn_rate,
    deceleration = config.drift_deceleration or 0,
    variant_index = current.variant_index
  }
end

return Drift
