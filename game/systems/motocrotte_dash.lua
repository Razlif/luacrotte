-- Short forward dash followed by a front-wheel stoppie presentation.
local Dash = {}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function state(motion)
  motion.dash_state = motion.dash_state or {
    phase = "normal",
    phase_time = 0,
    cooldown_time = 0,
    heading = 0,
    visual_angle = 0,
    axial_spin_phase = 0,
    axial_spin_direction = 1,
    axial_spin_active = false,
    wheelie_contact_x = nil,
    wheelie_contact_y = nil
  }
  return motion.dash_state
end

function Dash.update(motion, intent, definition, dt, position)
  local config = definition.dash or {}
  local current = state(motion)
  current.cooldown_time = math.max(0, (current.cooldown_time or 0) - dt)
  local phase = current.phase
  local speed = motion.speed or 0
  local minimum_speed = config.minimum_speed or 1
  local request = config.enabled == true and intent.dash_pressed == true

  if request and phase == "normal" and current.cooldown_time <= 0 and speed >= minimum_speed then
    current.phase = "boosting"
    current.phase_time = 0
    current.heading = motion.heading or 0
  end

  -- Keep the combined spin alive through the drift exit phase. A short Shift
  -- press must still visibly combine with an already-active dash.
  local combined_spin = current.phase ~= "normal"
    and (intent.drift_active == true or motion.drift_active == true)
  if combined_spin and not current.axial_spin_active then
    current.axial_spin_phase = motion.drift_spin_phase or motion.heading or 0
    current.wheelie_contact_x = position and position.x or current.wheelie_contact_x
    current.wheelie_contact_y = position and position.y or current.wheelie_contact_y
  end
  if combined_spin then
    local steering = intent.steering or 0
    if steering ~= 0 then
      current.axial_spin_direction = steering > 0 and 1 or -1
    elseif motion.drift_spin_direction then
      current.axial_spin_direction = motion.drift_spin_direction
    end
    current.axial_spin_phase = current.axial_spin_phase
      + current.axial_spin_direction * (config.axial_spin_speed or math.rad(540)) * dt
  end
  current.axial_spin_active = combined_spin

  if current.phase == "boosting" then
    current.phase_time = current.phase_time + dt
    if current.phase_time >= (config.boost_duration or 0.22) then
      current.phase = "stoppie"
      current.phase_time = 0
    end
  elseif current.phase == "stoppie" then
    current.phase_time = current.phase_time + dt
    if current.phase_time >= (config.stoppie_duration or 1.0) then
      current.phase = "recovery"
      current.phase_time = 0
    end
  elseif current.phase == "recovery" then
    current.phase_time = current.phase_time + dt
    if current.phase_time >= (config.recovery_duration or 0.25) then
      current.phase = "normal"
      current.phase_time = 0
      current.cooldown_time = config.cooldown or 0.8
    end
  end

  -- Re-evaluate after phase progression so the final recovery frame cannot
  -- leave a stale planted-wheel flag for one extra frame.
  local still_combined = current.phase ~= "normal"
    and (intent.drift_active == true or motion.drift_active == true)
  current.axial_spin_active = still_combined

  local boost_speed = config.boost_speed or 600
  local velocity_x
  local velocity_y
  if current.phase == "boosting" then
    velocity_x = math.cos(current.heading) * math.max(speed, boost_speed)
    velocity_y = math.sin(current.heading) * math.max(speed, boost_speed)
  end

  local angle = 0
  local wheelie = config.front_wheelie or {}
  if current.phase == "boosting" then
    angle = (wheelie.angle or math.rad(22)) * clamp(
      current.phase_time / math.max(config.boost_duration or 0.22, 0.001), 0, 1
    )
  elseif current.phase == "stoppie" then
    angle = wheelie.angle or math.rad(22)
  elseif current.phase == "recovery" then
    angle = (wheelie.angle or math.rad(22)) * (1 - clamp(
      current.phase_time / math.max(config.recovery_duration or 0.25, 0.001), 0, 1
    ))
  end
  current.visual_angle = angle

  motion.dash_phase = current.phase
  motion.dash_active = current.phase ~= "normal"
  motion.dash_visual_angle = angle
  motion.dash_axial_spin_phase = current.axial_spin_phase
  motion.dash_axial_spin_direction = current.axial_spin_direction
  motion.dash_axial_spin_active = current.axial_spin_active
  motion.wheelie_spin_active = current.axial_spin_active
  motion.wheelie_contact_x = current.wheelie_contact_x
  motion.wheelie_contact_y = current.wheelie_contact_y

  return {
    active = current.phase ~= "normal",
    phase = current.phase,
    heading = current.heading,
    velocity_x = velocity_x,
    velocity_y = velocity_y,
    visual_angle = angle,
    axial_spin_phase = current.axial_spin_phase,
    axial_spin_active = current.axial_spin_active,
    wheelie_spin_active = current.axial_spin_active,
    wheelie_contact_x = current.wheelie_contact_x,
    wheelie_contact_y = current.wheelie_contact_y
  }
end

return Dash
