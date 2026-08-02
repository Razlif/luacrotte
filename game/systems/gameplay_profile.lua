-- Loads, validates, resolves, and applies gameplay profile data.
local registry = require("game_data.gameplay_profiles.index")

local Profile = {}

local allowed = {
  controls = { omnidirectional = true, omnidirectional_arrows = true, gas_steering = true, gas_steering_fd = true, throttle_steering = true, beat_em_up = true, side_scroller = true },
  movement = { free = true, heading_cone = true, lane = true, horizontal_only = true, side_scroll = true, rear_depth = true },
  camera = { static = true, smooth_follow = true, follow_x_only = true, follow_x_lookahead = true, lookahead_follow = true },
  visual = { yaw_squash = true }
}

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item) end
  return result
end

local function merge(base, override)
  local result = copy(base or {})
  for key, value in pairs(override or {}) do
    if type(value) == "table" and type(result[key]) == "table" then
      result[key] = merge(result[key], value)
    else
      result[key] = copy(value)
    end
  end
  return result
end

function Profile.validate(profile)
  assert(type(profile) == "table", "Gameplay profile must be a table")
  assert(type(profile.id) == "string" and profile.id ~= "", "Gameplay profile id is required")
  assert(type(profile.version) == "number", "Gameplay profile version is required")
  assert(allowed.controls[profile.controls and profile.controls.schema], "Unknown gameplay control schema")
  assert(allowed.movement[profile.movement and profile.movement.constraint], "Unknown gameplay movement constraint")
  assert(allowed.camera[profile.camera and profile.camera.behavior], "Unknown gameplay camera behavior")
  assert(allowed.visual[profile.visual and profile.visual.orientation], "Unknown gameplay visual orientation")
  return profile
end

function Profile.list()
  local result = {}
  for id, profile in pairs(registry) do
    Profile.validate(profile)
    result[#result + 1] = profile
  end
  table.sort(result, function(left, right) return left.id < right.id end)
  return result
end

function Profile.load(id)
  local profile = registry[id]
  assert(profile, "Unknown gameplay profile: " .. tostring(id))
  return Profile.validate(copy(profile))
end

function Profile.resolve_hero_definition(hero_definition, profile)
  local resolved = copy(hero_definition)
  resolved.movement = merge(hero_definition.movement, profile.movement)
  resolved.drift = merge(hero_definition.drift, profile.drift)
  resolved.visual = merge(hero_definition.visual, profile.visual)
  resolved.braking_visual = merge(hero_definition.braking_visual, profile.braking_visual)
  resolved.dash = merge(hero_definition.dash, profile.dash)
  resolved.directional_animation = merge(hero_definition.directional_animation, profile.directional_animation)
  resolved.controls = merge(hero_definition.controls, profile.controls)
  resolved.environment = merge(hero_definition.environment, profile.environment)
  return resolved
end

function Profile.prepare_intent(intent, profile)
  local result = copy(intent)
  local schema = profile.controls.schema
  if schema == "side_scroller" or schema == "throttle_steering" or schema == "gas_steering" or schema == "gas_steering_fd" or profile.movement.constraint == "side_scroll" then
    result.vertical = 0
  elseif schema == "beat_em_up" then
    result.horizontal = result.horizontal or 0
    result.vertical = result.vertical or 0
  end
  if not profile.drift.enabled then
    result.drift_active = false
  end
  return result
end

function Profile.bounds(level_definition, profile)
  local bounds = copy(level_definition.hero_bounds)
  local movement = profile.movement
  if movement.constraint == "horizontal_only" then
    bounds.top = level_definition.hero_position.ground_y
    bounds.bottom = level_definition.hero_position.ground_y
  elseif movement.constraint == "rear_depth" and movement.depth_bounds then
    bounds.top = movement.depth_bounds.min
    bounds.bottom = movement.depth_bounds.max
  elseif movement.constraint == "lane" and movement.lane_depth then
    bounds.top = movement.lane_depth.min
    bounds.bottom = movement.lane_depth.max
  end
  return bounds
end

return Profile
