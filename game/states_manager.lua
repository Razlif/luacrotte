-- Tracks the active game state and handles transitions between states.
local StatesManager = {
  current = nil,
  current_name = nil,
  overlay = nil,
  overlay_name = nil,
  context = nil
}

local Telemetry = require("game.systems.qa_telemetry")
local unpack_args = table.unpack or unpack

local states = {
  start = require("game.game_states.start"),
  loading = require("game.game_states.loading"),
  playground = require("game.game_states.playground"),
  cutscene = require("game.game_states.cutscene")
}

local overlays = {
  pause = require("game.game_states.pause")
}

local function activate(name, ...)
  local next_state = states[name]
  StatesManager.current = next_state
  StatesManager.current_name = name
  Telemetry.emit("state_changed", { state = name })
  if next_state.enter then next_state.enter(StatesManager.context, ...) end
end

function StatesManager.change(name, ...)
  local next_state = states[name]
  assert(next_state, "Unknown game state: " .. tostring(name))
  if StatesManager.current and StatesManager.current.exit then
    StatesManager.current.exit(...)
  end
  local args = { ... }
  if name ~= "loading" and next_state.get_load_requests then
    local requests, scope = next_state.get_load_requests(StatesManager.context, unpack_args(args))
    if requests then
      local loading = states.loading
      StatesManager.current = loading
      StatesManager.current_name = "loading"
      Telemetry.emit("state_changed", { state = "loading", destination = name })
      loading.begin({
        scope = scope,
        requests = requests,
        on_ready = function()
          activate(name, unpack_args(args))
        end,
        on_fallback = function()
          activate("start")
        end
      })
      return
    end
  end
  activate(name, unpack_args(args))
end

function StatesManager.load(options, ...)
  local context = select(1, ...)
  if context and context.content then StatesManager.context = context end
  if options and options.cutscene_id then
    StatesManager.change("cutscene", options.cutscene_id)
  else
    -- Enter the menu through the same staged loading path as gameplay and
    -- cutscenes, so the first visible frame can show progress.
    StatesManager.change("start", ...)
  end
end

function StatesManager.update(dt)
  if StatesManager.overlay then
    if StatesManager.overlay.update then StatesManager.overlay.update(dt) end
    return
  end
  if StatesManager.current and StatesManager.current.update then
    StatesManager.current.update(dt)
  end
end

function StatesManager.draw()
  if StatesManager.current and StatesManager.current.draw then
    StatesManager.current.draw()
  end
  if StatesManager.overlay and StatesManager.overlay.draw then
    StatesManager.overlay.draw()
  end
end

function StatesManager.push_overlay(name, ...)
  assert(not StatesManager.overlay, "An overlay is already active")
  local overlay = overlays[name]
  assert(overlay, "Unknown overlay: " .. tostring(name))
  StatesManager.overlay = overlay
  StatesManager.overlay_name = name
  if overlay.enter then overlay.enter(...) end
end

function StatesManager.pop_overlay(...)
  if not StatesManager.overlay then return end
  if StatesManager.overlay.exit then StatesManager.overlay.exit(...) end
  StatesManager.overlay = nil
  StatesManager.overlay_name = nil
end

function StatesManager.get_debug_context()
  if StatesManager.current and StatesManager.current.get_debug_context then
    return StatesManager.current.get_debug_context()
  end
  return nil
end

function StatesManager.keypressed(key, scancode, isrepeat)
  if StatesManager.current and StatesManager.current.keypressed then
    StatesManager.current.keypressed(key, scancode, isrepeat)
  end
end

return StatesManager
