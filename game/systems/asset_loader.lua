-- Compatibility facade over the scene-aware lazy content cache.
local CollisionDataManager = require("game.systems.collision_data_manager")

local AssetLoader = {
  manifest = nil,
  cache = { characters = {}, effects = {}, props = {}, backgrounds = {} },
  scopes = {},
  active_scope = nil,
  loaded = false
}

local function copy_table(source)
  local result = {}
  for key, value in pairs(source or {}) do result[key] = value end
  return result
end

local function load_image(path, label)
  assert(love.filesystem.getInfo(path), "Missing runtime asset: " .. path)
  local image_data = love.image.newImageData(path)
  local image = love.graphics.newImage(image_data)
  image:setFilter("nearest", "nearest")
  image:setWrap("clamp", "clamp")
  assert(image:getWidth() > 0 and image:getHeight() > 0, "Invalid image: " .. label)
  return image, image_data
end

local function group_for(kind)
  local groups = { character = "characters", effect = "effects", prop = "props", background = "backgrounds" }
  return groups[kind] or kind
end

local function retain(kind, asset_id)
  local scope = AssetLoader.active_scope
  if not scope then return end
  AssetLoader.scopes[scope] = AssetLoader.scopes[scope] or {}
  AssetLoader.scopes[scope][group_for(kind) .. ":" .. asset_id] = { kind = kind, asset_id = asset_id }
end

local function selected_animation(selection, name)
  if selection == nil then return true end
  if type(selection) == "string" then return selection == name end
  if #selection > 0 then
    for _, candidate in ipairs(selection) do
      if candidate == name then return true end
    end
    return false
  end
  return selection[name] == true
end

local function options_key(options)
  options = options or {}
  local animations = options.animations
  local animation_key = "*"
  if type(animations) == "string" then
    animation_key = animations
  elseif type(animations) == "table" then
    local names = {}
    for name, value in pairs(animations) do
      names[#names + 1] = type(name) == "number" and tostring(value) or (tostring(name) .. "=" .. tostring(value))
    end
    table.sort(names)
    animation_key = table.concat(names, ",")
  end
  return table.concat({ tostring(options.include_image ~= false), animation_key, tostring(options.pixel_mask == true), tostring(options.keep_image_data == true) }, "|")
end

local function load_definition(kind, asset_id, options)
  options = options or {}
  local group = group_for(kind)
  local destination = AssetLoader.cache[group]
  local cache_id = asset_id .. ":" .. options_key(options)
  if destination[cache_id] then
    retain(kind, asset_id)
    return destination[cache_id]
  end
  local definition = assert(AssetLoader.manifest[group] and AssetLoader.manifest[group][asset_id],
    "Unknown " .. kind .. " asset: " .. tostring(asset_id))
  local loaded = copy_table(definition)
  loaded.image = copy_table(definition.image)
  local include_image = options.include_image ~= false or options.pixel_mask == true
  if include_image then
    loaded.image.texture, loaded.image.image_data = load_image(definition.image.path, asset_id .. ":image")
    if not options.keep_image_data and not options.pixel_mask then
      loaded.image.image_data = nil
    end
  end
  loaded.animations = {}
  loaded.collision = CollisionDataManager.definition(definition, loaded.image.texture)

  for name, animation in pairs(definition.animations or {}) do
    if not selected_animation(options.animations, name) then
      goto continue_animation
    end
    local loaded_animation = copy_table(animation)
    loaded_animation.texture, loaded_animation.image_data = load_image(animation.sheet_path, asset_id .. ":" .. name)
    assert(loaded_animation.frame_width > 0 and loaded_animation.frame_height > 0, "Invalid frame size: " .. name)
    assert(loaded_animation.frame_count > 0, "Invalid frame count: " .. name)
    loaded_animation.mask_frames = nil
    if not options.keep_image_data and not options.pixel_mask then
      loaded_animation.image_data = nil
    end
    loaded.animations[name] = loaded_animation
    ::continue_animation::
  end
  CollisionDataManager.release_shape_image_data(loaded, loaded.collision)
  destination[cache_id] = loaded
  retain(kind, asset_id)
  return loaded
end

function AssetLoader.load_manifest(manifest)
  assert(manifest, "Asset manifest is required")
  AssetLoader.manifest = manifest
  AssetLoader.loaded = true
end

function AssetLoader.begin_scope(name)
  assert(type(name) == "string" and name ~= "", "Asset scope name is required")
  AssetLoader.active_scope = name
  AssetLoader.scopes[name] = AssetLoader.scopes[name] or {}
end

function AssetLoader.end_scope(name)
  local scope = AssetLoader.scopes[name]
  if scope then
    for cache_key, entry in pairs(scope) do
      local shared = false
      for other_name, other_scope in pairs(AssetLoader.scopes) do
        if other_name ~= name and other_scope[cache_key] then shared = true break end
      end
      if not shared then
        local group, asset_id = cache_key:match("([^:]+):(.+)")
        local asset_group = AssetLoader.cache[group] or {}
        for cache_id, asset in pairs(asset_group) do
          if cache_id:sub(1, #asset_id + 1) == asset_id .. ":" then
            if asset.image and asset.image.texture and asset.image.texture.release then asset.image.texture:release() end
            for _, animation in pairs(asset.animations or {}) do
              if animation.texture and animation.texture.release then animation.texture:release() end
            end
            asset_group[cache_id] = nil
          end
        end
      end
    end
    AssetLoader.scopes[name] = nil
  end
  if AssetLoader.active_scope == name then AssetLoader.active_scope = nil end
end

function AssetLoader.get(kind, asset_id, options)
  assert(AssetLoader.loaded, "AssetLoader.load_manifest must run first")
  local asset = load_definition(kind, asset_id, options)
  if options and options.pixel_mask then
    CollisionDataManager.attach_pixel_masks(asset, asset)
  end
  return asset
end

function AssetLoader.get_character(asset_id, options) return AssetLoader.get("character", asset_id, options) end
function AssetLoader.get_effect(asset_id, options) return AssetLoader.get("effect", asset_id, options) end
function AssetLoader.get_prop(asset_id, options) return AssetLoader.get("prop", asset_id, options) end
function AssetLoader.get_background(asset_id, options) return AssetLoader.get("background", asset_id, options) end

function AssetLoader.reset_cache()
  AssetLoader.cache = { characters = {}, effects = {}, props = {}, backgrounds = {} }
  AssetLoader.scopes = {}
  AssetLoader.active_scope = nil
end

function AssetLoader.stats()
  local result = { cache_hits = 0, loaded = 0, scopes = 0 }
  for _, group in pairs(AssetLoader.cache) do
    for _ in pairs(group) do result.loaded = result.loaded + 1 end
  end
  for _ in pairs(AssetLoader.scopes) do result.scopes = result.scopes + 1 end
  return result
end

return AssetLoader
