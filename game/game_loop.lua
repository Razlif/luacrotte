-- Whole-game flow coordinator.
local states_manager = require("game.states_manager")
local InputManager = require("game.systems.input_manager")
local AudioManager = require("game.systems.audio_manager")
local DebugOverlay = require("game.systems.debug_overlay")
local QABridge = require("game.systems.qa_bridge")
local QATelemetry = require("game.systems.qa_telemetry")
local RuntimeContext = require("game.runtime_context")
local ContentManager = RuntimeContext.content
local LevelManager = RuntimeContext.levels
local asset_manifest = require("game_data.asset_manifest")
local playground_level = require("game_data.levels.playground")

local GameLoop = {}

function GameLoop.load(debug_config, ...)
  DebugOverlay.configure(debug_config)
  local qa_run_dir = debug_config and debug_config.qa_run_dir
  if debug_config and debug_config.qa and not qa_run_dir then
    love.filesystem.createDirectory("qa_runtime/snapshots")
    love.filesystem.createDirectory("qa_runtime/screenshots")
    qa_run_dir = love.filesystem.getSaveDirectory() .. "/qa_runtime"
  end
  QATelemetry.configure({ enabled = debug_config and debug_config.qa, run_dir = qa_run_dir })
  QABridge.configure({ enabled = debug_config and debug_config.qa, run_dir = qa_run_dir })
  ContentManager.configure(asset_manifest)
  LevelManager.configure({ playground = playground_level })
  RuntimeContext.states = states_manager
  states_manager.load({ cutscene_id = debug_config and debug_config.cutscene_id }, RuntimeContext, ...)
end

function GameLoop.update(dt)
  QATelemetry.begin_frame(dt)
  QABridge.before_update()
  AudioManager.update(dt)
  DebugOverlay.update()
  if not QABridge.is_paused() then
    states_manager.update(dt)
  end
  QABridge.after_update(dt, states_manager)
  DebugOverlay.report_input()
  DebugOverlay.report_state(states_manager.get_debug_context(), dt)
  InputManager.end_frame()
end

function GameLoop.draw()
  states_manager.draw()
  DebugOverlay.draw(states_manager.get_debug_context())
  QABridge.draw(states_manager)
end

function GameLoop.keypressed(key, scancode, isrepeat)
  InputManager.keypressed(key, scancode, isrepeat)
end

function GameLoop.keyreleased(key, scancode)
  InputManager.keyreleased(key, scancode)
end

function GameLoop.mousepressed(x, y, button)
  InputManager.mousepressed(x, y, button)
end

function GameLoop.mousereleased(x, y, button)
  InputManager.mousereleased(x, y, button)
end

function GameLoop.quit()
  require("game.systems.motocrotte_audio").reset()
  AudioManager.stop_all()
  ContentManager.end_scope("menu")
  ContentManager.end_scope("playground")
end

return GameLoop
