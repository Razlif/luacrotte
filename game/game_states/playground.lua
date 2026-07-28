-- Static MotoCrotte checkpoint: promoted background plus hero image.
local asset_manifest = require("game_data.asset_manifest")
local hero_definition = require("game_data.characters.motocrotte_hero_main")
local background_definition = asset_manifest.backgrounds.motocrotte_background_01
local level_definition = require("game_data.levels.playground")
local AssetLoader = require("game.systems.asset_loader")
local Character = require("game.entities.characters.character")
local MotocrotteDriver = require("game.controllers.motocrotte_driver")
local HeroMovement = require("game.systems.motocrotte_hero_movement")
local CameraManager = require("game.systems.camera_manager")
local ParallaxManager = require("game.systems.parallax")

local function states_manager()
  return require("game.states_manager")
end

local Playground = {
  hero = nil,
  camera = nil,
  parallax = nil,
  last_collision_events = {}
}

function Playground.enter()
  AssetLoader.load_manifest(asset_manifest)
  Playground.hero = Character.new(hero_definition, AssetLoader.get_character(hero_definition.asset_id))
  Playground.hero.position.x = level_definition.hero_position.x
  Playground.hero.position.ground_y = level_definition.hero_position.ground_y
  Playground.hero.position.z = level_definition.hero_position.z
  Playground.camera = CameraManager.new({
    width = level_definition.camera.width,
    height = level_definition.camera.height,
    bounds = {
      left = level_definition.world.left,
      top = level_definition.world.top,
      right = level_definition.world.right,
      bottom = level_definition.world.bottom
    },
    smoothing = level_definition.camera.smoothing,
    zoom = level_definition.camera.zoom
  })
  Playground.camera:follow(Playground.hero.position)
  Playground.parallax = ParallaxManager.new({
    {
      id = background_definition.id,
      image_path = background_definition.image.path,
      speed_x = 1,
      speed_y = 1,
      repeat_x = false,
      repeat_y = false,
      layer = 0
    }
  })
  Playground.parallax:set_camera(Playground.camera)
end

function Playground.update(dt)
  local intent = MotocrotteDriver.get_intent()
  HeroMovement.update(Playground.hero, intent, hero_definition, level_definition, dt)
  Playground.camera:follow(Playground.hero.position)
  Playground.camera:update(dt)
  Playground.parallax:update(dt)
end

function Playground.get_debug_context()
  return {
    entities = { Playground.hero },
    camera = Playground.camera,
    collision_events = Playground.last_collision_events,
    background_id = background_definition.id
  }
end

function Playground.draw()
  love.graphics.clear(0.08, 0.1, 0.14, 1)
  Playground.camera:attach()
  Playground.parallax:draw()
  Playground.hero:draw()
  Playground.camera:detach()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("MotoCrotte static asset checkpoint", 24, 24)
  love.graphics.print("Arrows/WASD: move", 24, 48)
end

return Playground
