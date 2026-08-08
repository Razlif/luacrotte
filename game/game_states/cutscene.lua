-- Thin game-state adapter for the self-contained cutscene engine.
local CutsceneEngine = require("cutscene_engine")
local InputManager = require("game.systems.input_manager")

local CutsceneState = {}

local function states_manager()
  return require("game.states_manager")
end

function CutsceneState.enter(_context, scene_id)
  CutsceneEngine.start(scene_id, { return_state = "playground", preloaded = true })
end

function CutsceneState.get_load_requests(_context, scene_id)
  return CutsceneEngine.get_load_requests(scene_id)
end

function CutsceneState.update(dt)
  if InputManager.consume_pressed("ui_back") then
    CutsceneEngine.skip()
  else
    CutsceneEngine.update(dt)
  end
  if CutsceneEngine.is_finished() then
    CutsceneEngine.stop()
    states_manager().change("playground")
  end
end

function CutsceneState.draw()
  CutsceneEngine.draw()
end

function CutsceneState.get_debug_context()
  return CutsceneEngine.get_debug_context()
end

return CutsceneState
