-- Loads approved runtime assets from the repository-root media_assets folder.
local MaskCreation = require("game.systems.mask_creation")
local AssetLoader = {
  characters = {},
  effects = {},
  props = {},
  loaded = false
}

local function load_image(path, label)
  assert(love.filesystem.getInfo(path), "Missing runtime asset: " .. path)
  local image_data = love.image.newImageData(path)
  local image = love.graphics.newImage(image_data)
  image:setFilter("nearest", "nearest")
  image:setWrap("clamp", "clamp")
  assert(image:getWidth() > 0 and image:getHeight() > 0, "Invalid image: " .. label)
  return image, image_data
end

local function copy_table(source)
  local result = {}
  for key, value in pairs(source) do
    result[key] = value
  end
  return result
end

function AssetLoader.load_manifest(manifest)
  assert(manifest, "Asset manifest is required")
  AssetLoader.characters = {}
  AssetLoader.effects = {}
  AssetLoader.props = {}

  local function load_group(definitions, destination)
    for asset_id, definition in pairs(definitions or {}) do
      local loaded = copy_table(definition)
      loaded.image = copy_table(definition.image)
      loaded.image.texture, loaded.image.image_data = load_image(definition.image.path, asset_id .. ":image")
      loaded.image.mask = MaskCreation.from_image(loaded.image.texture, loaded.image.image_data)
      loaded.animations = {}

      for name, animation in pairs(definition.animations or {}) do
        local loaded_animation = copy_table(animation)
        loaded_animation.texture, loaded_animation.image_data = load_image(animation.sheet_path, asset_id .. ":" .. name)
        assert(loaded_animation.frame_width > 0 and loaded_animation.frame_height > 0, "Invalid frame size: " .. name)
        assert(loaded_animation.frame_count > 0, "Invalid frame count: " .. name)
        assert(loaded_animation.frame_count * loaded_animation.frame_width <= loaded_animation.texture:getWidth(), "Sprite sheet is too narrow: " .. animation.sheet_path)
        assert(loaded_animation.frame_height <= loaded_animation.texture:getHeight(), "Sprite sheet is too short: " .. animation.sheet_path)
        loaded_animation.mask_frames = MaskCreation.from_animation(loaded_animation)
        loaded.animations[name] = loaded_animation
      end

      destination[asset_id] = loaded
    end
  end

  load_group(manifest.characters, AssetLoader.characters)
  load_group(manifest.effects, AssetLoader.effects)
  load_group(manifest.props, AssetLoader.props)

  AssetLoader.loaded = true
end

function AssetLoader.get_character(asset_id)
  assert(AssetLoader.loaded, "AssetLoader.load_manifest must run first")
  local asset = AssetLoader.characters[asset_id]
  assert(asset, "Unknown character asset: " .. tostring(asset_id))
  return asset
end

function AssetLoader.get_effect(asset_id)
  assert(AssetLoader.loaded, "AssetLoader.load_manifest must run first")
  local asset = AssetLoader.effects[asset_id]
  assert(asset, "Unknown effect asset: " .. tostring(asset_id))
  return asset
end

function AssetLoader.get_prop(asset_id)
  assert(AssetLoader.loaded, "AssetLoader.load_manifest must run first")
  local asset = AssetLoader.props[asset_id]
  assert(asset, "Unknown prop asset: " .. tostring(asset_id))
  return asset
end

return AssetLoader
