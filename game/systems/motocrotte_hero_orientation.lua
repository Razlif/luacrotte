-- Smooth visual yaw driven by movement velocity, independent of drifting.
local Orientation = {}

local function normalize_angle(angle)
  while angle > math.pi do angle = angle - math.pi * 2 end
  while angle < -math.pi do angle = angle + math.pi * 2 end
  return angle
end

function Orientation.update(hero, definition, dt)
  assert(hero and hero.motocrotte_motion, "MotoCrotte motion is required for orientation")
  assert(definition and definition.visual, "MotoCrotte visual orientation data is required")
  assert(type(dt) == "number" and dt >= 0, "Delta time must be non-negative")

  local config = definition.visual
  hero.visual_yaw = hero.visual_yaw or 0
  if config.yaw_mode ~= "all_movement" or config.orientation_enabled == false then
    return
  end

  local motion = hero.motocrotte_motion
  if motion.braking then
    return
  end
  local minimum_speed = config.minimum_speed_for_turn or 0
  if (motion.speed or 0) <= minimum_speed then
    return
  end

  local schema = definition.controls and definition.controls.schema
  local target = (schema == "gas_steering" or schema == "gas_steering_fd" or schema == "throttle_steering")
    and (motion.steering_heading or motion.heading)
    or motion.heading
  target = target or hero.visual_yaw
  local difference = normalize_angle(target - hero.visual_yaw)
  local response = config.yaw_response or 10
  local blend = math.min(1, response * dt)
  hero.visual_yaw = normalize_angle(hero.visual_yaw + difference * blend)
end

return Orientation
