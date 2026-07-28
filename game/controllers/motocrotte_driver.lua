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
    jump_pressed = InputManager.consume_pressed("jump")
  }
end

return Driver
