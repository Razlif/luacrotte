-- Public facade and scene registry for the self-contained cutscene engine.
local Player = require("cutscene_engine.player")
local ContentManager = require("game.systems.content_manager")
local AudioManager = require("game.systems.audio_manager")

local CutsceneEngine = { active = nil }

local scenes = {
  duck_slime_intro = require("cutscene_engine.scenes.duck_slime_intro"),
  duck_slime_date = require("cutscene_engine.scenes.duck_slime_date"),
  luacrotte_yasuke_intro_draft = require("cutscene_engine.scenes.luacrotte_yasuke_intro_draft")
}

function CutsceneEngine.start(scene_id, options)
  if CutsceneEngine.active then CutsceneEngine.stop() end
  local scene = scenes[scene_id]
  assert(scene, "Unknown cutscene scene: " .. tostring(scene_id))
  CutsceneEngine.active = Player.new(scene, options)
  return CutsceneEngine.active
end

function CutsceneEngine.get_load_requests(scene_id)
  local scene = scenes[scene_id]
  assert(scene, "Unknown cutscene scene: " .. tostring(scene_id))
  return Player.requests_for_scene(scene), "cutscene"
end

function CutsceneEngine.update(dt)
  if CutsceneEngine.active then CutsceneEngine.active:update(dt) end
end

function CutsceneEngine.draw()
  if CutsceneEngine.active then CutsceneEngine.active:draw() end
end

function CutsceneEngine.is_finished()
  return not CutsceneEngine.active or CutsceneEngine.active:is_finished()
end

function CutsceneEngine.skip()
  if CutsceneEngine.active then CutsceneEngine.active:skip() end
end

function CutsceneEngine.stop()
  CutsceneEngine.active = nil
  ContentManager.end_scope("cutscene")
  AudioManager.end_scope("cutscene")
end

function CutsceneEngine.get_debug_context()
  return CutsceneEngine.active and CutsceneEngine.active:get_debug_context() or nil
end

function CutsceneEngine.has_scene(scene_id)
  return scenes[scene_id] ~= nil
end

return CutsceneEngine
