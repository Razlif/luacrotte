-- Collision data is deliberately separate from texture loading.
local CollisionDataManager = {}
local MaskCreation = require("game.systems.mask_creation")

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = copy(child) end
  return result
end

function CollisionDataManager.definition(asset_definition, image)
  local collision = copy(asset_definition.collision or {})
  local pixel_mask = collision.pixel_mask or {}
  if collision.mode == nil and pixel_mask.enabled == true then
    collision.mode = "pixel_mask"
  end
  if collision.mode == nil then collision.mode = "shape" end
  if collision.mode == "shape" and (not collision.sensors or #collision.sensors == 0) then
    collision.sensors = {
      {
        id = "default_body",
        shape = collision.shape or "rectangle",
        offset_x = collision.offset_x or 0,
        offset_y = collision.offset_y or 0,
        width = collision.width or 48,
        height = collision.height or 48,
        radius = collision.radius
      }
    }
  end
  return collision
end

-- Shape collisions never inspect pixels.  Drop CPU-side image buffers as soon
-- as the collision definition is known; the GPU texture remains available for
-- rendering. Pixel-mask assets intentionally retain their buffers until mask
-- generation has completed.
function CollisionDataManager.release_shape_image_data(asset, collision)
  if not asset or not collision or collision.mode ~= "shape" then return end
  if asset.image then asset.image.image_data = nil end
  for _, animation in pairs(asset.animations or {}) do
    animation.image_data = nil
  end
end

function CollisionDataManager.attach_pixel_masks(asset, asset_definition)
  local collision = asset_definition.collision or {}
  local pixel_mask = collision.pixel_mask or {}
  if collision.mode ~= "pixel_mask" and pixel_mask.enabled ~= true then return asset end
  if collision.cache == false then return asset end
  if pixel_mask.cache == false then return asset end
  asset.image.mask = MaskCreation.from_image(asset.image.texture, asset.image.image_data)
  for name, animation in pairs(asset.animations or {}) do
    animation.mask_frames = MaskCreation.from_animation(animation)
  end
  return asset
end

function CollisionDataManager.release(asset)
  if not asset then return end
  asset.image = asset.image or {}
  asset.image.mask = nil
  for _, animation in pairs(asset.animations or {}) do
    animation.mask_frames = nil
  end
end

return CollisionDataManager
