-- Reports mask and sensor overlaps. It never applies gameplay responses.
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
        if second_collision and (second_collision.enabled or options and options.debug) and CollisionDetection.mask_overlaps(first, second) then
          events[#events + 1] = {
            kind = "mask_overlap",
            source_id = entity_id(first),
            target_id = entity_id(second),
            frame = first.animation and first.animation.current_frame or 1
          }
        end
        if second_collision and (second_collision.enabled or options and options.debug) then
          for _, sensor_definition in ipairs(sensors_for(first)) do
            local sensor = world_sensor(first, sensor_definition)
            if CollisionDetection.sensor_overlaps(sensor, second) then
              events[#events + 1] = {
                kind = "sensor_overlap",
                source_id = entity_id(first),
                target_id = entity_id(second),
                sensor_id = sensor_definition.id,
                frame = second.animation and second.animation.current_frame or 1
              }
            end
          end
        end
      end
    end
  end
  return events
end

return CollisionDetection
