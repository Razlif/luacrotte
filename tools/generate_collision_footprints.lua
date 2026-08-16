-- Offline collision-footprint generator.
--
-- Run explicitly through the repository LÖVE tool mode:
--   love . --generate-collision-footprints --all
--   love . --generate-collision-footprints --asset-id motocrotte_bike_variant_01
--
-- This module is never required by gameplay. It decodes promoted sheets once,
-- writes numeric opaque-bound data, and releases ImageData before returning.
local Generator = {}

local DEFAULT_HEIGHT_RATIO = 0.10
local GROUPS = { "characters", "props", "effects", "backgrounds", "audio" }

local function round(value, places)
  local factor = 10 ^ (places or 0)
  return math.floor(value * factor + 0.5) / factor
end

local function parse_args(arguments)
  local options = { all = false, asset_id = nil }
  for index, value in ipairs(arguments or {}) do
    if value == "--all" then
      options.all = true
    elseif value == "--asset-id" then
      options.asset_id = arguments[index + 1]
    end
  end
  return options
end

local function find_manifest_entry(manifest, asset_id)
  for _, group in ipairs(GROUPS) do
    local entries = manifest[group]
    if entries and entries[asset_id] then
      return entries[asset_id], group
    end
  end
  return nil, nil
end

local function source_animation(entry, manifest)
  local animation_name = entry.source_animation
  if not animation_name then
    return nil, "missing source_animation"
  end
  local asset, group = find_manifest_entry(manifest, entry.asset_id)
  if not asset then
    return nil, "asset is missing from game_data.asset_manifest.lua"
  end
  local animation = asset.animations and asset.animations[animation_name]
  if not animation then
    return nil, "animation '" .. tostring(animation_name) .. "' is missing from " .. group
  end
  return animation
end

local function union_bounds(image_data, frame_width, frame_height, frame_count)
  local columns = math.floor(image_data:getWidth() / frame_width)
  local rows = math.floor(image_data:getHeight() / frame_height)
  local available_frames = columns * rows
  local count = math.min(frame_count, available_frames)
  local bounds = { left = frame_width, top = frame_height, right = -1, bottom = -1 }

  for frame = 0, count - 1 do
    local origin_x = (frame % columns) * frame_width
    local origin_y = math.floor(frame / columns) * frame_height
    for y = 0, frame_height - 1 do
      for x = 0, frame_width - 1 do
        local _, _, _, alpha = image_data:getPixel(origin_x + x, origin_y + y)
        if alpha > 0 then
          if x < bounds.left then bounds.left = x end
          if y < bounds.top then bounds.top = y end
          if x > bounds.right then bounds.right = x end
          if y > bounds.bottom then bounds.bottom = y end
        end
      end
    end
  end

  if bounds.right < 0 then
    return nil, "all selected frames are fully transparent"
  end
  if count < frame_count then
    return nil, string.format("sheet contains %d frames but metadata requests %d", count, frame_count)
  end
  return bounds
end

local function footprint_for(entry, manifest, root)
  local animation, animation_error = source_animation(entry, manifest)
  if not animation then return nil, animation_error end
  local frame_width = tonumber(animation.frame_width)
  local frame_height = tonumber(animation.frame_height)
  local frame_count = tonumber(animation.frame_count)
  if not frame_width or not frame_height or not frame_count
      or frame_width <= 0 or frame_height <= 0 or frame_count <= 0 then
    return nil, "invalid animation frame metadata"
  end

  if not love.filesystem.getInfo(animation.sheet_path) then
    return nil, "missing promoted sheet: " .. animation.sheet_path
  end
  local image_data = love.image.newImageData(animation.sheet_path)
  local bounds, bounds_error = union_bounds(image_data, frame_width, frame_height, frame_count)
  if image_data.release then image_data:release() end
  if not bounds then return nil, bounds_error end

  local anchor = entry.anchor or {}
  local anchor_x = tonumber(anchor.x) or frame_width * 0.5
  local anchor_y = tonumber(anchor.y) or frame_height
  local height_ratio = tonumber(entry.height_ratio) or DEFAULT_HEIGHT_RATIO
  local width_ratio = tonumber(entry.width_ratio) or 1.0
  local mask_width = bounds.right - bounds.left + 1
  local mask_height = bounds.bottom - bounds.top + 1
  local width = mask_width * width_ratio
  local height = mask_height * height_ratio
  local center_x = (bounds.left + bounds.right) * 0.5
  local offset_x = center_x - anchor_x
  local offset_y = bounds.bottom - anchor_y - height * 0.5

  return {
    source_animation = entry.source_animation,
    anchor = { x = anchor_x, y = anchor_y },
    height_ratio = height_ratio,
    width_ratio = width_ratio,
    opaque_bounds = bounds,
    mask_width = mask_width,
    mask_height = mask_height,
    width = round(width, 2),
    height = round(height, 2),
    offset_x = round(offset_x, 2),
    offset_y = round(offset_y, 2)
  }
end

local function lua_number(value)
  local result = string.format("%.2f", value):gsub("%.?0+$", "")
  return result
end

local function lua_table(value, indent)
  indent = indent or "  "
  local next_indent = indent .. "  "
  local lines = { "{" }
  if value.source_animation then
    lines[#lines + 1] = next_indent .. "source_animation = " .. string.format("%q", value.source_animation) .. ","
  end
  if value.anchor then
    lines[#lines + 1] = next_indent .. string.format("anchor = { x = %s, y = %s },", lua_number(value.anchor.x), lua_number(value.anchor.y))
  end
  lines[#lines + 1] = next_indent .. "height_ratio = " .. lua_number(value.height_ratio or DEFAULT_HEIGHT_RATIO) .. ","
  lines[#lines + 1] = next_indent .. "width_ratio = " .. lua_number(value.width_ratio or 1.0) .. ","
  local bounds = value.opaque_bounds
  lines[#lines + 1] = next_indent .. string.format("opaque_bounds = { left = %d, top = %d, right = %d, bottom = %d },", bounds.left, bounds.top, bounds.right, bounds.bottom)
  lines[#lines + 1] = next_indent .. "mask_width = " .. tostring(value.mask_width) .. ","
  lines[#lines + 1] = next_indent .. "mask_height = " .. tostring(value.mask_height) .. ","
  lines[#lines + 1] = next_indent .. "width = " .. lua_number(value.width) .. ","
  lines[#lines + 1] = next_indent .. "height = " .. lua_number(value.height) .. ","
  lines[#lines + 1] = next_indent .. "offset_x = " .. lua_number(value.offset_x) .. ","
  lines[#lines + 1] = next_indent .. "offset_y = " .. lua_number(value.offset_y)
  lines[#lines + 1] = indent .. "}"
  return table.concat(lines, "\n")
end

local function sorted_keys(values)
  local keys = {}
  for key in pairs(values) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

local function write_output(root, footprints)
  local output_path = root .. "/game_data/collision_footprints.lua"
  local file, error_message = io.open(output_path, "w")
  if not file then return nil, "cannot write " .. output_path .. ": " .. tostring(error_message) end
  file:write("-- Generated by tools/generate_collision_footprints.lua. Do not edit by hand.\n")
  file:write("-- Source dimensions are derived from promoted opaque animation bounds.\n")
  file:write("return {\n")
  local keys = sorted_keys(footprints)
  for index, asset_id in ipairs(keys) do
    file:write("  [" .. string.format("%q", asset_id) .. "] = ")
    file:write(lua_table(footprints[asset_id], "  "))
    file:write(index == #keys and "\n" or ",\n")
  end
  file:write("}\n")
  file:close()
  return true
end

function Generator.run(arguments)
  local root = love.filesystem.getSource()
  local manifest = require("game_data.asset_manifest")
  local existing = require("game_data.collision_footprints")
  local options = parse_args(arguments)
  if not options.all and not options.asset_id then
    return nil, "specify --all or --asset-id <id>"
  end

  local selected = {}
  if options.asset_id then
    if not existing[options.asset_id] then
      return nil, "asset has no footprint source entry: " .. options.asset_id
    end
    selected[options.asset_id] = existing[options.asset_id]
  else
    for asset_id, entry in pairs(existing) do selected[asset_id] = entry end
  end

  local generated = {}
  for asset_id, entry in pairs(existing) do
    generated[asset_id] = entry
  end
  local errors = {}
  for _, asset_id in ipairs(sorted_keys(selected)) do
    local entry = selected[asset_id]
    entry.asset_id = asset_id
    local footprint, error_message = footprint_for(entry, manifest, root)
    if footprint then
      generated[asset_id] = footprint
      print(string.format("[collision-footprints] %s: %dx%d mask, %sx%s base", asset_id, footprint.mask_width, footprint.mask_height, lua_number(footprint.width), lua_number(footprint.height)))
    else
      errors[#errors + 1] = asset_id .. ": " .. tostring(error_message)
    end
  end

  if #errors > 0 then
    for _, error_message in ipairs(errors) do print("[collision-footprints] ERROR " .. error_message) end
    return nil, string.format("footprint generation failed for %d asset(s)", #errors)
  end

  local ok, write_error = write_output(root, generated)
  if not ok then return nil, write_error end
  print("[collision-footprints] wrote " .. tostring(#sorted_keys(generated)) .. " footprint(s)")
  return true
end

return Generator
