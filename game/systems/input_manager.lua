-- Centralizes keyboard and mouse state for controllers and game states.
local bindings = require("game_data.input_bindings")
local InputManager = {
  bindings = bindings,
  keys_down = {},
  scancodes_down = {},
  pressed = {},
  mouse_buttons_down = {},
  mouse_pressed = {}
}

local function actions_for_key(key)
  local actions = {}
  for action, keys in pairs(InputManager.bindings) do
    if keys[key] then
      actions[#actions + 1] = action
    end
  end
  return actions
end

function InputManager.keypressed(key, scancode)
  InputManager.keys_down[key] = true
  if scancode then InputManager.scancodes_down[scancode] = true end
  for _, action in ipairs(actions_for_key(key)) do
    InputManager.pressed[action] = true
  end
  -- Match the physical key as well as the layout-translated key. This keeps
  -- controls such as the mud hose's A binding consistent on Linux layouts
  -- where the same physical key may report a different logical key.
  for action, keys in pairs(InputManager.bindings) do
    if scancode and keys[scancode] then
      InputManager.pressed[action] = true
    end
  end
end

function InputManager.keyreleased(key, scancode)
  InputManager.keys_down[key] = nil
  if scancode then InputManager.scancodes_down[scancode] = nil end
end

function InputManager.mousepressed(x, y, button)
  InputManager.mouse_buttons_down[button] = { x = x, y = y }
  InputManager.mouse_pressed[button] = { x = x, y = y }
end

function InputManager.mousereleased(_, _, button)
  InputManager.mouse_buttons_down[button] = nil
end

function InputManager.is_down(action)
  for key in pairs(InputManager.bindings[action] or {}) do
    if InputManager.keys_down[key] or InputManager.scancodes_down[key] then
      return true
    end
  end
  return false
end

function InputManager.consume_pressed(action)
  local was_pressed = InputManager.pressed[action] == true
  InputManager.pressed[action] = nil
  return was_pressed
end

function InputManager.is_mouse_down(button)
  return InputManager.mouse_buttons_down[button] ~= nil
end

function InputManager.debug_snapshot()
  local keys = {}
  for key in pairs(InputManager.keys_down) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return {
    keys_down = keys,
    move_left = InputManager.is_down("move_left"),
    move_right = InputManager.is_down("move_right"),
    jump = InputManager.is_down("jump")
  }
end

function InputManager.consume_mouse_pressed(button)
  local event = InputManager.mouse_pressed[button]
  InputManager.mouse_pressed[button] = nil
  return event
end

function InputManager.end_frame()
  InputManager.pressed = {}
  InputManager.mouse_pressed = {}
end

return InputManager
