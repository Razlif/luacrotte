-- Converts named input actions into MotoCrotte movement intent.
local InputManager = require("game.systems.input_manager")

local Driver = {}

function Driver.get_intent()
  local horizontal = 0
  if InputManager.is_down("move_left") then horizontal = horizontal - 1 end
  if InputManager.is_down("move_right") then horizontal = horizontal + 1 end

  local vertical = 0
  if InputManager.is_down("move_up") then vertical = vertical - 1 end
  if InputManager.is_down("move_down") then vertical = vertical + 1 end

  return {
    horizontal = horizontal,
    vertical = vertical,
    jump_pressed = InputManager.consume_pressed("jump"),
    drift_active = InputManager.is_down("drift"),
    cycle_drift_mode_pressed = InputManager.consume_pressed("cycle_drift_mode"),
    reset_drift_lab_pressed = InputManager.consume_pressed("reset_drift_lab"),
    toggle_visual_lab_pressed = InputManager.consume_pressed("toggle_visual_lab"),
    visual_yaw_left = InputManager.is_down("visual_yaw_left"),
    visual_yaw_right = InputManager.is_down("visual_yaw_right")
  }
end

return Driver
