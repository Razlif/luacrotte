local ContentManager = require("game.systems.content_manager")
local LevelManager = require("game.systems.level_manager")
local InputManager = require("game.systems.input_manager")
local AudioManager = require("game.systems.audio_manager")
local QATelemetry = require("game.systems.qa_telemetry")
local PhysicsCollisionWorld = require("game.systems.physics_collision_world")
local Config = require("game.conf")

return {
  content = ContentManager,
  levels = LevelManager,
  input = InputManager,
  audio = AudioManager,
  telemetry = QATelemetry,
  physics = PhysicsCollisionWorld.new(),
  config = Config
}
