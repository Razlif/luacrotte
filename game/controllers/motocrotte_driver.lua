-- Converts named input actions into MotoCrotte movement intent.
local InputManager = require("game.systems.input_manager")

local Driver = {}

function Driver.get_intent(profile)
  local horizontal = 0
  local vertical = 0
  local steering = 0
  local throttle = 0
  local brake = false
  local drift_action = "drift"
  local schema = profile and profile.controls and profile.controls.schema or "omnidirectional_arrows"

  if schema == "gas_steering" or schema == "gas_steering_fd" or schema == "throttle_steering" then
    if InputManager.is_down("move_left") then steering = steering - 1 end
    if InputManager.is_down("move_right") then steering = steering + 1 end
    if schema == "gas_steering" then
      throttle = InputManager.is_down("gas_primary") and 1 or 0
      brake = InputManager.is_down("brake_primary")
      drift_action = "drift_primary"
    elseif schema == "gas_steering_fd" then
      throttle = InputManager.is_down("gas_fd") and 1 or 0
      brake = InputManager.is_down("brake_fd")
      drift_action = "drift_fd"
    else
      throttle = InputManager.is_down("throttle") and 1 or 0
      brake = InputManager.is_down("brake")
    end
    horizontal = steering
  else
    if InputManager.is_down("move_left") then horizontal = horizontal - 1 end
    if InputManager.is_down("move_right") then horizontal = horizontal + 1 end
    if InputManager.is_down("move_up") then vertical = vertical - 1 end
    if InputManager.is_down("move_down") then vertical = vertical + 1 end
    steering = horizontal
    throttle = math.abs(horizontal) + math.abs(vertical) > 0 and 1 or 0
  end

  local profile_slot_pressed = nil
  for slot = 1, 9 do
    if InputManager.consume_pressed("profile_slot_" .. slot) then
      profile_slot_pressed = slot
      break
    end
  end

  return {
    horizontal = horizontal,
    vertical = vertical,
    control_schema = schema,
    steering = steering,
    throttle = throttle,
    brake = brake,
    jump_pressed = InputManager.consume_pressed("jump"),
    drift_active = InputManager.is_down(drift_action) and (not profile or not profile.drift or profile.drift.enabled == true),
    cycle_drift_mode_pressed = InputManager.consume_pressed("cycle_drift_mode"),
    cycle_control_schema_pressed = InputManager.consume_pressed("cycle_control_schema"),
    toggle_sprite_policy_pressed = InputManager.consume_pressed("toggle_sprite_policy"),
    toggle_yaw_pressed = InputManager.consume_pressed("toggle_yaw"),
    cycle_movement_mode_pressed = InputManager.consume_pressed("cycle_movement_mode"),
    cycle_camera_mode_pressed = InputManager.consume_pressed("cycle_camera_mode"),
    cycle_background_pressed = InputManager.consume_pressed("cycle_background"),
    profile_slot_pressed = profile_slot_pressed,
    toggle_visual_lab_pressed = InputManager.consume_pressed("toggle_visual_lab"),
    visual_yaw_left = InputManager.is_down("visual_yaw_left"),
    visual_yaw_right = InputManager.is_down("visual_yaw_right"),
    visual_radius_decrease = InputManager.consume_pressed("visual_radius_decrease"),
    visual_radius_increase = InputManager.consume_pressed("visual_radius_increase")
  }
end

return Driver
