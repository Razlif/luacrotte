-- Profile-driven arcade locomotion solver.
local Locomotion = {}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function approach(value, target, amount)
  if value < target then return math.min(value + amount, target) end
  if value > target then return math.max(value - amount, target) end
  return target
end

local function normalize_angle(angle)
  while angle > math.pi do angle = angle - math.pi * 2 end
  while angle < -math.pi do angle = angle + math.pi * 2 end
  return angle
end

local function approach_angle(value, target, amount)
  local delta = normalize_angle(target - value)
  if math.abs(delta) <= amount then return target end
  return value + (delta > 0 and amount or -amount)
end

function Locomotion.input_vector(intent)
  local x = intent.horizontal or 0
  local y = intent.vertical or 0
  local length = math.sqrt(x * x + y * y)
  if length > 1 then
    x = x / length
    y = y / length
  end
  return x, y, length
end

function Locomotion.update(motion, intent, config, drift_context, dt)
  local horizontal, vertical, input_length = Locomotion.input_vector(intent)
  local drift_control_active = drift_context
    and drift_context.control_active ~= false
    and drift_context.active
  local drift_input_suppressed = drift_context
    and drift_control_active
    and drift_context.disable_gas_brake == true
  if drift_input_suppressed then
    horizontal = 0
    vertical = 0
    input_length = 0
  end
  local acceleration = config.acceleration
  local coast_deceleration = (not drift_input_suppressed and intent.brake)
    and (config.brake_deceleration or config.deceleration)
    or (config.coast_deceleration or config.deceleration)
  local max_speed = config.max_speed
  local vertical_speed = config.vertical_speed or max_speed
  local acceleration_step = acceleration * dt
  local coast_step = coast_deceleration * dt

  local target_vx = horizontal * max_speed
  local target_vy = vertical * vertical_speed
  local drift_coast_step = drift_context and drift_context.active and (drift_context.deceleration or 0) * dt or 0
  local step = input_length > 0 and acceleration_step or math.max(coast_step, drift_coast_step)
  local speed = math.sqrt((motion.vx or 0) * (motion.vx or 0) + (motion.vy or 0) * (motion.vy or 0))
  local desired_heading = motion.desired_heading or motion.heading or 0
  if input_length > 0 then
    desired_heading = math.atan2(vertical, horizontal)
  end

  local current_heading = motion.heading or 0
  if speed > 0.001 then
    current_heading = math.atan2(motion.vy, motion.vx)
  end

  if drift_context and drift_control_active then
    if drift_input_suppressed then
      speed = approach(speed, 0, drift_coast_step)
    else
      local target_speed = input_length > 0 and max_speed or speed
      speed = approach(speed, target_speed, step)
    end
    if input_length > 0 and speed > 0.001 then
      local turn_rate = drift_context.turn_rate or config.max_turn_rate or math.rad(180)
      current_heading = approach_angle(current_heading, desired_heading, turn_rate * dt)
    end
    motion.vx = math.cos(current_heading) * speed
    motion.vy = math.sin(current_heading) * speed
  else
    local grip = drift_context and drift_context.grip or 1
    motion.vx = approach(motion.vx or 0, target_vx, step * grip)
    motion.vy = approach(motion.vy or 0, target_vy, step * grip)
    speed = math.sqrt(motion.vx * motion.vx + motion.vy * motion.vy)
    if speed > 0.001 then
      current_heading = math.atan2(motion.vy, motion.vx)
    end
    local steering_only = input_length == 0
      and intent.steering ~= nil
      and intent.steering ~= 0
      and (intent.control_schema == "gas_steering"
        or intent.control_schema == "gas_steering_fd"
        or intent.control_schema == "throttle_steering")
    if steering_only and speed > 0.001 then
      local steering_heading = motion.steering_heading or current_heading
      current_heading = approach_angle(
        current_heading,
        steering_heading,
        (config.steering_rate or config.max_turn_rate or math.rad(180)) * dt
      )
      motion.vx = math.cos(current_heading) * speed
      motion.vy = math.sin(current_heading) * speed
    end
  end

  motion.heading = current_heading
  motion.desired_heading = desired_heading
  motion.speed = math.sqrt(motion.vx * motion.vx + motion.vy * motion.vy)
  motion.braking = input_length > 0 and (
    (motion.vx ~= 0 and target_vx ~= 0 and motion.vx * target_vx < 0) or
    (motion.vy ~= 0 and target_vy ~= 0 and motion.vy * target_vy < 0)
  ) or false
  motion.input_length = input_length
  motion.turn_rate = drift_context and drift_control_active and (drift_context.turn_rate or 0) or 0
  if motion.turn_rate > 0.001 then
    motion.turning_radius = motion.speed / motion.turn_rate
  else
    motion.turning_radius = 0
  end
  if drift_control_active then
    motion.locomotion_state = "drift"
  elseif input_length > 0 then
    motion.locomotion_state = "regular_drive"
  elseif intent.brake then
    motion.locomotion_state = "braking"
  else
    motion.locomotion_state = "glide"
  end

  return horizontal, vertical, input_length
end

function Locomotion.apply_position(hero, motion, bounds, dt)
  if not bounds then
    hero.position.x = hero.position.x + motion.vx * dt
    hero.position.ground_y = hero.position.ground_y + motion.vy * dt
    return
  end
  hero.position.x = clamp(hero.position.x + motion.vx * dt, bounds.left, bounds.right)
  hero.position.ground_y = clamp(hero.position.ground_y + motion.vy * dt, bounds.top, bounds.bottom)
  local cone = bounds.perspective_cone
  if cone then
    local far_y = cone.far_y or bounds.top
    local near_y = cone.near_y or bounds.bottom
    local range = math.max(1, near_y - far_y)
    local amount = clamp((hero.position.ground_y - far_y) / range, 0, 1)
    local half_width = (cone.far_half_width or 0)
      + amount * ((cone.near_half_width or 0) - (cone.far_half_width or 0))
    local center_x = cone.center_x or (bounds.left + bounds.right) * 0.5
    hero.position.x = clamp(hero.position.x, center_x - half_width, center_x + half_width)
  end
end

return Locomotion
