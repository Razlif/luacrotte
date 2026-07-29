-- Static MotoCrotte checkpoint: promoted background plus hero image.
local asset_manifest = require("game_data.asset_manifest")
local hero_definition = require("game_data.characters.motocrotte_hero_main")
local background_definition = asset_manifest.backgrounds.motocrotte_background_01
local level_definition = require("game_data.levels.playground")
local AssetLoader = require("game.systems.asset_loader")
local Character = require("game.entities.characters.character")
local MotocrotteDriver = require("game.controllers.motocrotte_driver")
local HeroMovement = require("game.systems.motocrotte_hero_movement")
local HeroOrientation = require("game.systems.motocrotte_hero_orientation")
local HeroRenderer = require("game.systems.motocrotte_hero_renderer")
local CameraManager = require("game.systems.camera_manager")
local ParallaxManager = require("game.systems.parallax")

local function states_manager()
  return require("game.states_manager")
end

local Playground = {
  hero = nil,
  camera = nil,
  parallax = nil,
  last_collision_events = {},
  drift_mode_index = 1,
  visual_mode_index = 1,
  visual_lab_active = false,
  visual_yaw = 0
}

local function visual_modes()
  return (hero_definition.visual and hero_definition.visual.modes) or { "yaw_squash" }
end

function Playground.set_visual_mode(index)
  local modes = visual_modes()
  Playground.visual_mode_index = ((index - 1) % #modes) + 1
  if Playground.hero then
    Playground.hero.motocrotte_visual_mode = modes[Playground.visual_mode_index]
  end
end

function Playground.reset_visual_lab()
  Playground.visual_yaw = 0
  Playground.hero.position.x = level_definition.hero_position.x
  Playground.hero.position.ground_y = level_definition.hero_position.ground_y
  Playground.hero.motocrotte_motion = {
    vx = 0, vy = 0, speed = 0, heading = 0, desired_heading = 0,
    slip_angle = 0, drift_amount = 0, visual_rotation = 0,
    drift_active = false, grounded = true, jump_pressed = false
  }
  Playground.hero.visual_yaw = 0
  local animation_name = hero_definition.movement and hero_definition.movement.animation
  if animation_name then
    local animation = Playground.hero.animation.animations[animation_name]
    if animation then
      animation.loop = true
      Playground.hero.animation:play(animation_name)
    end
  end
end

function Playground.enter()
  AssetLoader.load_manifest(asset_manifest)
  Playground.hero = Character.new(hero_definition, AssetLoader.get_character(hero_definition.asset_id))
  Playground.hero.position.x = level_definition.hero_position.x
  Playground.hero.position.ground_y = level_definition.hero_position.ground_y
  Playground.hero.position.z = level_definition.hero_position.z
  Playground.visual_lab_active = hero_definition.visual and hero_definition.visual.test_enabled == true
  Playground.set_visual_mode(HeroRenderer.mode_index(hero_definition.visual.test_mode, hero_definition))
  Playground.reset_visual_lab()
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
  if intent.toggle_visual_lab_pressed then
    Playground.visual_lab_active = not Playground.visual_lab_active
    if Playground.visual_lab_active then
      Playground.reset_visual_lab()
    else
      Playground.hero.animation:stop()
    end
  end
  if Playground.visual_lab_active then
    if intent.cycle_drift_mode_pressed then
      Playground.set_visual_mode(Playground.visual_mode_index + 1)
    end
    if intent.reset_drift_lab_pressed then
      Playground.reset_visual_lab()
    end
    local visual = hero_definition.visual or {}
    local yaw_direction = 0
    if intent.visual_yaw_left then yaw_direction = yaw_direction - 1 end
    if intent.visual_yaw_right then yaw_direction = yaw_direction + 1 end
    Playground.visual_yaw = Playground.visual_yaw + yaw_direction * (visual.yaw_speed or math.rad(90)) * dt
    Playground.hero.visual_yaw = Playground.visual_yaw
    Playground.hero.animation:update(dt)
  else
    HeroMovement.update(Playground.hero, intent, hero_definition, level_definition, dt)
    HeroOrientation.update(Playground.hero, hero_definition, dt)
  end
  Playground.camera:follow(Playground.hero.position)
  Playground.camera:update(dt)
  Playground.parallax:update(dt)
end

function Playground.get_debug_context()
  return {
    entities = { Playground.hero },
    camera = Playground.camera,
    collision_events = Playground.last_collision_events,
    background_id = background_definition.id,
    visual_lab = {
      active = Playground.visual_lab_active,
      mode = Playground.hero and Playground.hero.motocrotte_visual_mode or nil,
      mode_index = Playground.visual_mode_index,
      modes = visual_modes(),
      yaw = Playground.visual_yaw,
      horizontal_scale = math.cos(Playground.visual_yaw),
      movement_yaw = Playground.hero and Playground.hero.visual_yaw or 0
    },
    drift_lab = {
      mode = Playground.hero and Playground.hero.motocrotte_visual_mode or nil,
      mode_index = Playground.drift_mode_index,
      modes = hero_definition.drift and hero_definition.drift.modes or {},
      motion = Playground.hero and Playground.hero.motocrotte_motion or nil
    }
  }
end

function Playground.draw()
  love.graphics.clear(0.08, 0.1, 0.14, 1)
  Playground.camera:attach()
  Playground.parallax:draw()
  HeroRenderer.draw(Playground.hero, hero_definition, {
    active = Playground.visual_lab_active,
    mode = Playground.hero.motocrotte_visual_mode,
    yaw = Playground.visual_yaw
  })
  Playground.camera:detach()
  love.graphics.setColor(1, 1, 1, 1)
  local mode = Playground.hero.motocrotte_visual_mode or "unknown"
  if Playground.visual_lab_active then
    love.graphics.print("MotoCrotte Visual Lab", 24, 24)
    love.graphics.print("Q/E: yaw   Tab: visual mode   V: exit visual lab   R: reset", 24, 48)
    love.graphics.print(string.format("Mode: %s   Yaw: %.0f°   Horizontal scale: %.2f", mode, math.deg(Playground.visual_yaw), math.cos(Playground.visual_yaw)), 24, 72)
  else
    local motion = Playground.hero.motocrotte_motion or {}
    love.graphics.print("MotoCrotte Drift Lab", 24, 24)
    love.graphics.print("Arrows/WASD: move   Shift/Space: drift   Tab: gameplay mode   V: visual lab", 24, 48)
    love.graphics.print(string.format("Mode: %s   Speed: %.0f   Heading: %.0f°   Yaw: %.0f°   Slip: %.0f°", mode, motion.speed or 0, math.deg(motion.heading or 0), math.deg(Playground.hero.visual_yaw or 0), math.deg(motion.slip_angle or 0)), 24, 72)
  end
end

return Playground
