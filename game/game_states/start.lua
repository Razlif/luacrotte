-- Start screen for the template's disposable example game.
local asset_manifest = require("game_data.asset_manifest")
local AssetLoader = require("game.systems.asset_loader")
local AudioManager = require("game.systems.audio_manager")
local CameraManager = require("game.systems.camera_manager")
local InputManager = require("game.systems.input_manager")
local Menu = require("game.ui.ui_elements.default_menu")
local ParallaxManager = require("game.systems.parallax")
local Theme = require("game.ui.theme")
local cutscene_menu = require("game_data.cutscenes")
local GameplayProfile = require("game.systems.gameplay_profile")

local Start = {
  camera = nil,
  parallax = nil,
  menu = nil
}

local function states_manager()
  return require("game.states_manager")
end

local function menu_layout()
  local width = math.min(300, love.graphics.getWidth() - 40)
  return {
    x = (love.graphics.getWidth() - width) / 2,
    y = love.graphics.getHeight() * 0.46,
    width = width,
    spacing = 48
  }
end

function Start.enter()
  AssetLoader.load_manifest(asset_manifest)
  AudioManager.load_manifest(asset_manifest)
  AudioManager.play_music("game_ambient", { loop = true, volume = 0.65 })
  Start.camera = CameraManager.new({
    width = 960,
    height = 540,
    bounds = { left = 0, top = 0, right = 1672, bottom = 941 },
    smoothing = 8
  })
  Start.camera:set_center(836, 470)
  Start.parallax = ParallaxManager.new({
    {
      id = "start_background",
      image_path = asset_manifest.backgrounds.enchanted_wizard_training_meadow.image.path,
      speed_x = 1,
      speed_y = 1,
      repeat_x = false,
      repeat_y = false
    }
  })
  Start.parallax:set_camera(Start.camera)
  local layout = menu_layout()
  local profiles = GameplayProfile.list()
  local menu_items = {
    { label = "Playground", on_confirm = function()
      states_manager().change("playground", profiles[1].id)
    end }
  }
  for _, profile in ipairs(profiles) do
    local profile_id = profile.id
    local profile_label = profile.label
    menu_items[#menu_items + 1] = {
      label = "Playground: " .. profile_label,
      on_confirm = function()
        states_manager().change("playground", profile_id)
      end
    }
  end
  for _, scene in ipairs(cutscene_menu) do
    local scene_id = scene.id
    local scene_label = scene.label
    menu_items[#menu_items + 1] = {
      label = scene_label,
      on_confirm = function()
        states_manager().change("cutscene", scene_id)
      end
    }
  end
  Start.menu = Menu.new(menu_items, layout)
end

function Start.update(dt)
  if InputManager.consume_pressed("ui_back") then
    love.event.quit()
    return
  end
  Start.camera:update(dt)
  Start.parallax:update(dt)
  Start.menu:update(InputManager)
end

function Start.draw()
  love.graphics.clear(0.08, 0.1, 0.14, 1)
  love.graphics.setColor(1, 1, 1, 1)
  Start.camera:attach()
  Start.parallax:draw()
  Start.camera:detach()

  local theme = Theme.get()
  local width = love.graphics.getWidth()
  local height = love.graphics.getHeight()
  love.graphics.setColor(0, 0, 0, 0.32)
  love.graphics.rectangle("fill", 0, 0, width, height)
  love.graphics.setColor(theme.colors.text)
  love.graphics.printf("The Adventures of Slime and Duck", 24, height * 0.22, width - 48, "center")
  Start.menu:draw()
  love.graphics.setColor(1, 1, 1, 1)
end

function Start.get_debug_context()
  return { entities = {}, camera = Start.camera, collision_events = {} }
end

return Start
