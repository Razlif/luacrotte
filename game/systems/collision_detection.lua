-- Reports mask, sensor, and optional base-footprint overlaps. It never applies
-- gameplay responses.
local PositionManager = require("game.systems.position_manager")
local MaskCreation = require("game.systems.mask_creation")

local CollisionDetection = {}

local function entity_id(entity)
  return entity.id or entity.definition.asset_id or "entity"
end

local function active_mask(entity)
  if entity.get_collision_mask then
    return entity:get_collision_mask()
  end
  return entity.mask
end

local function screen_position(entity)
  return entity.position.x, PositionManager.get_screen_y(entity.position)
end

local function facing_of(entity)
  if entity.get_render_facing then
    return entity:get_render_facing()
  end
  return entity.render_facing or entity.facing or 1
end

local function pixel_world_position(entity, mask, x, y)
  local world_x, world_y = screen_position(entity)
  local display_x = facing_of(entity) == 1 and x or mask.width - 1 - x
  return world_x + (display_x - entity.anchor_x) * entity.scale,
    world_y + (y - entity.anchor_y) * entity.scale
end

local function world_to_pixel(entity, mask, x, y)
  local world_x, world_y = screen_position(entity)
  local display_x = math.floor((x - world_x) / entity.scale + entity.anchor_x + 0.5)
  local local_x = facing_of(entity) == 1 and display_x or mask.width - 1 - display_x
  return local_x,
    math.floor((y - world_y) / entity.scale + entity.anchor_y + 0.5)
end

local function mask_bounds(entity, mask)
  if not mask or mask.opaque_bounds.right < 0 then
    return nil
  end
  local left_x, top = pixel_world_position(entity, mask, mask.opaque_bounds.left, mask.opaque_bounds.top)
  local right_x, bottom = pixel_world_position(entity, mask, mask.opaque_bounds.right, mask.opaque_bounds.bottom)
  return math.min(left_x, right_x), top, math.max(left_x, right_x) + entity.scale, bottom + entity.scale
end

local function bounds_overlap(a_left, a_top, a_right, a_bottom, b_left, b_top, b_right, b_bottom)
  return a_left < b_right and a_right > b_left and a_top < b_bottom and a_bottom > b_top
end

local function velocity_of(entity)
  local motion = entity.motocrotte_motion
  if motion then
    return motion.vx or 0, motion.vy or 0
  end
  if entity.velocity then
    return entity.velocity.x or 0, entity.velocity.y or 0
  end
  return entity.velocity_x or 0, entity.velocity_y or 0
end

local function geometry_from_sensor(sensor)
  if sensor.shape == "circle" then
    local radius = sensor.radius or 0
    return {
      left = sensor.x - radius,
      top = sensor.y - radius,
      right = sensor.x + radius,
      bottom = sensor.y + radius,
      center_x = sensor.x,
      center_y = sensor.y
    }
  end
  local width = sensor.width or 0
  local height = sensor.height or 0
  return {
    left = sensor.x,
    top = sensor.y,
    right = sensor.x + width,
    bottom = sensor.y + height,
    center_x = sensor.x + width * 0.5,
    center_y = sensor.y + height * 0.5
  }
end

local function geometry_for(entity, preferred_sensor)
  if preferred_sensor then
    return geometry_from_sensor(preferred_sensor)
  end
  local mask = active_mask(entity)
  if mask then
    local left, top, right, bottom = mask_bounds(entity, mask)
    if left then
      return {
        left = left,
        top = top,
        right = right,
        bottom = bottom,
        center_x = (left + right) * 0.5,
        center_y = (top + bottom) * 0.5
      }
    end
  end
  local sensors = CollisionDetection.get_sensors(entity)
  if sensors[1] then
    return geometry_from_sensor(sensors[1])
  end
  local x, y = screen_position(entity)
  return { left = x, top = y, right = x, bottom = y, center_x = x, center_y = y }
end

local function collision_mode(entity)
  local definition_collision = entity.definition and entity.definition.collision
  if definition_collision and definition_collision.mode then
    return definition_collision.mode
  end
  local asset_collision = entity.asset and entity.asset.collision
  return asset_collision and asset_collision.mode or nil
end

local function collision_config(entity)
  local definition_collision = entity.definition and entity.definition.collision
  if definition_collision and definition_collision.base then
    return definition_collision
  end
  return entity.asset and entity.asset.collision or definition_collision
end

local function base_config(entity)
  local collision = collision_config(entity)
  return collision and collision.base or nil
end

local function base_enabled(entity)
  local base = base_config(entity)
  return base and base.enabled ~= false
end

-- The full sprite mask remains useful for visual telemetry, but character
-- contact is resolved against this smaller footprint at the bottom of the
-- mask. This keeps upper-body pixels free to overlap in a 2.5D scene.
local function base_geometry(entity)
  if not base_enabled(entity) then
    return nil
  end
  local full = geometry_for(entity)
  local width = math.max(0, full.right - full.left)
  local height = math.max(0, full.bottom - full.top)
  if width <= 0 or height <= 0 then
    return nil
  end
  local base = base_config(entity)
  local height_ratio = math.max(0, math.min(1, base.height_ratio or 0.20))
  local horizontal_inset = math.max(0, math.min(0.49, base.horizontal_inset or 0))
  local inset = width * horizontal_inset
  local left = full.left + inset
  local right = full.right - inset
  local top = full.bottom - height * height_ratio
  return {
    left = left,
    top = top,
    right = right,
    bottom = full.bottom,
    center_x = (left + right) * 0.5,
    center_y = (top + full.bottom) * 0.5
  }
end

local function base_contact(first, second)
  local first_geometry = base_geometry(first)
  local second_geometry = base_geometry(second)
  if not first_geometry or not second_geometry then
    return nil
  end
  local overlap_x = math.min(first_geometry.right, second_geometry.right)
    - math.max(first_geometry.left, second_geometry.left)
  local overlap_y = math.min(first_geometry.bottom, second_geometry.bottom)
    - math.max(first_geometry.top, second_geometry.top)
  if overlap_x <= 0 or overlap_y <= 0 then
    return nil
  end

  local dx = second_geometry.center_x - first_geometry.center_x
  local normal_x
  if math.abs(dx) > 0.0001 then
    normal_x = dx < 0 and -1 or 1
  else
    local first_velocity_x = velocity_of(first)
    local second_velocity_x = velocity_of(second)
    normal_x = first_velocity_x - second_velocity_x < 0 and -1 or 1
  end
  local first_velocity_x, first_velocity_y = velocity_of(first)
  local second_velocity_x, second_velocity_y = velocity_of(second)
  return {
    collision_type = "base",
    normal = { x = normal_x, y = 0 },
    penetration = overlap_x,
    relative_velocity = {
      x = first_velocity_x - second_velocity_x,
      y = first_velocity_y - second_velocity_y
    },
    first_center = { x = first_geometry.center_x, y = first_geometry.center_y },
    second_center = { x = second_geometry.center_x, y = second_geometry.center_y },
    first_base = first_geometry,
    second_base = second_geometry
  }
end

function CollisionDetection.base_overlaps(first, second)
  return base_contact(first, second) ~= nil
end

function CollisionDetection.base_contact_details(first, second)
  return base_contact(first, second)
end

local function contact_normal(first_geometry, second_geometry, overlap_x, overlap_y)
  local dx = second_geometry.center_x - first_geometry.center_x
  local dy = second_geometry.center_y - first_geometry.center_y
  if math.abs(dx) < 0.0001 and math.abs(dy) < 0.0001 then
    local relative_x, relative_y = 0, 0
    if overlap_x <= overlap_y then
      relative_x = 1
    else
      relative_y = 1
    end
    return relative_x, relative_y
  end
  if overlap_x <= overlap_y then
    return dx < 0 and -1 or 1, 0
  end
  return 0, dy < 0 and -1 or 1
end

-- Returns contact information without moving either entity or applying a
-- gameplay response. The normal points from `first` toward `second`.
function CollisionDetection.contact_details(first, second, collision_type, first_sensor)
  local first_geometry = geometry_for(first, first_sensor)
  local second_geometry = geometry_for(second)
  local overlap_x = math.min(first_geometry.right, second_geometry.right)
    - math.max(first_geometry.left, second_geometry.left)
  local overlap_y = math.min(first_geometry.bottom, second_geometry.bottom)
    - math.max(first_geometry.top, second_geometry.top)
  local normal_x, normal_y = contact_normal(first_geometry, second_geometry, overlap_x, overlap_y)
  local first_velocity_x, first_velocity_y = velocity_of(first)
  local second_velocity_x, second_velocity_y = velocity_of(second)
  return {
    collision_type = collision_type or "shape",
    normal = { x = normal_x, y = normal_y },
    penetration = math.max(0, math.min(overlap_x, overlap_y)),
    relative_velocity = {
      x = first_velocity_x - second_velocity_x,
      y = first_velocity_y - second_velocity_y
    },
    first_center = { x = first_geometry.center_x, y = first_geometry.center_y },
    second_center = { x = second_geometry.center_x, y = second_geometry.center_y }
  }
end

function CollisionDetection.mask_overlaps(first, second)
  local first_mask = active_mask(first)
  local second_mask = active_mask(second)
  if not first_mask or not second_mask then
    return false
  end
  local first_bounds = { mask_bounds(first, first_mask) }
  local second_bounds = { mask_bounds(second, second_mask) }
  if not first_bounds[1] or not bounds_overlap(first_bounds[1], first_bounds[2], first_bounds[3], first_bounds[4], second_bounds[1], second_bounds[2], second_bounds[3], second_bounds[4]) then
    return false
  end

  for _, pixel in ipairs(first_mask.opaque_pixels or {}) do
    local world_x, world_y = pixel_world_position(first, first_mask, pixel.x, pixel.y)
    local second_x, second_y = world_to_pixel(second, second_mask, world_x, world_y)
    if MaskCreation.get_pixel(second_mask, second_x, second_y) then
      return true
    end
  end
  return false
end

local function each_opaque_pixel(mask, callback)
  if mask.opaque_pixels then
    for _, pixel in ipairs(mask.opaque_pixels) do
      callback(pixel.x, pixel.y)
    end
    return
  end
  for y = mask.opaque_bounds.top, mask.opaque_bounds.bottom do
    for x = mask.opaque_bounds.left, mask.opaque_bounds.right do
      if MaskCreation.get_pixel(mask, x, y) then
        callback(x, y)
      end
    end
  end
end

local function point_in_sensor(sensor, x, y)
  if sensor.shape == "circle" then
    local dx = x - sensor.x
    local dy = y - sensor.y
    return dx * dx + dy * dy <= sensor.radius * sensor.radius
  end
  return x >= sensor.x and x <= sensor.x + sensor.width and y >= sensor.y and y <= sensor.y + sensor.height
end

function CollisionDetection.sensor_overlaps(sensor, entity)
  local mask = active_mask(entity)
  if not mask then
    for _, other_sensor in ipairs(CollisionDetection.get_sensors(entity)) do
      if sensor.shape == "circle" and other_sensor.shape == "circle" then
        local dx, dy = sensor.x - other_sensor.x, sensor.y - other_sensor.y
        local radius = (sensor.radius or 0) + (other_sensor.radius or 0)
        if dx * dx + dy * dy <= radius * radius then return true end
      else
        local a = sensor.shape == "circle" and sensor or other_sensor
        local b = a == sensor and other_sensor or sensor
        if a.shape == "circle" then
          local nx = math.max(b.x, math.min(a.x, b.x + b.width))
          local ny = math.max(b.y, math.min(a.y, b.y + b.height))
          local dx, dy = a.x - nx, a.y - ny
          if dx * dx + dy * dy <= (a.radius or 0) ^ 2 then return true end
        elseif bounds_overlap(a.x, a.y, a.x + a.width, a.y + a.height,
          b.x, b.y, b.x + b.width, b.y + b.height) then
          return true
        end
      end
    end
    return false
  end
  local overlaps = false
  each_opaque_pixel(mask, function(x, y)
    if overlaps then return end
    local world_x, world_y = pixel_world_position(entity, mask, x, y)
    if point_in_sensor(sensor, world_x, world_y) then
      overlaps = true
    end
  end)
  return overlaps
end

local function world_sensor(entity, definition)
  local world_x, world_y = screen_position(entity)
  local sensor = {
    id = definition.id,
    shape = definition.shape,
    x = world_x + (definition.offset_x or 0) * entity.scale,
    y = world_y + (definition.offset_y or 0) * entity.scale,
    width = (definition.width or 0) * entity.scale,
    height = (definition.height or 0) * entity.scale,
    radius = (definition.radius or 0) * entity.scale
  }
  if facing_of(entity) == -1 then
    if sensor.shape == "circle" then
      sensor.x = world_x - (definition.offset_x or 0) * entity.scale
    else
      sensor.x = world_x - ((definition.offset_x or 0) + (definition.width or 0)) * entity.scale
    end
  end
  return sensor
end

local function sensors_for(entity)
  local collision = (entity.definition and entity.definition.collision) or {}
  if (not collision.sensors or #collision.sensors == 0) and entity.asset and entity.asset.collision then
    collision = entity.asset.collision
  end
  if collision.sensors and #collision.sensors > 0 then
    return collision.sensors
  end
  if collision.auto_sensor == false then
    return {}
  end
  local generated = MaskCreation.sensor_from_mask(active_mask(entity), entity.anchor_x, entity.anchor_y)
  return generated and { generated } or {}
end

function CollisionDetection.get_sensors(entity)
  local definitions = sensors_for(entity)
  local sensors = {}
  for _, definition in ipairs(definitions) do
    local sensor = world_sensor(entity, definition)
    sensor.generated = definition.generated
    sensors[#sensors + 1] = sensor
  end
  return sensors
end

function CollisionDetection.check(entities, options)
  local events = {}
  for index, first in ipairs(entities) do
    local first_collision = first.definition and first.definition.collision
    if first_collision and (first_collision.enabled or options and options.debug) then
      for second_index = index + 1, #entities do
        local second = entities[second_index]
        local second_collision = second.definition and second.definition.collision
        local blocking_base_pair = base_enabled(first) and base_enabled(second)
        if second_collision and (second_collision.enabled or options and options.debug) and CollisionDetection.mask_overlaps(first, second) then
          local contact = CollisionDetection.contact_details(first, second, "mask")
          events[#events + 1] = {
            kind = "mask_overlap",
            source_id = entity_id(first),
            target_id = entity_id(second),
            frame = first.animation and first.animation.current_frame or 1,
            collision_type = contact.collision_type,
            blocking = not blocking_base_pair,
            contact = contact
          }
        end
        if second_collision and (second_collision.enabled or options and options.debug) then
          for _, sensor_definition in ipairs(sensors_for(first)) do
            local sensor = world_sensor(first, sensor_definition)
            if CollisionDetection.sensor_overlaps(sensor, second) then
              local collision_type = collision_mode(first) == "shape" and "shape" or "sensor"
              local contact = CollisionDetection.contact_details(first, second, collision_type, sensor)
              events[#events + 1] = {
                kind = "sensor_overlap",
                source_id = entity_id(first),
                target_id = entity_id(second),
                sensor_id = sensor_definition.id,
                frame = second.animation and second.animation.current_frame or 1,
                collision_type = contact.collision_type,
                blocking = not blocking_base_pair,
                contact = contact
              }
            end
          end
        end
        if second_collision and (second_collision.enabled or options and options.debug) and blocking_base_pair then
          local contact = base_contact(first, second)
          if contact then
            events[#events + 1] = {
              kind = "base_overlap",
              source_id = entity_id(first),
              target_id = entity_id(second),
              frame = first.animation and first.animation.current_frame or 1,
              collision_type = "base",
              blocking = true,
              contact = contact
            }
          end
        end
      end
    end
  end
  return events
end

return CollisionDetection
