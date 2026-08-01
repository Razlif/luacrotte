-- Temporary Playground experiment layer. It never mutates the source profile.
local Experiment = {}

Experiment.options = {
  sprite_policy = { "fixed", "random_per_spin" },
  yaw_mode = { "drift_only", "all_movement", "off" },
  control_schema = { "gas_steering", "gas_steering_fd", "omnidirectional_arrows" },
  movement_mode = { "free", "heading_cone", "lane" },
  camera_mode = { "static", "smooth_follow", "follow_x_lookahead" },
  background_id = { "motocrotte_background_01", "enchanted_wizard_training_meadow", "rear_sky_horizon" }
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

function Experiment.default(profile)
  profile = profile or {}
  local controls = profile.controls or {}
  local movement = profile.movement or {}
  local camera = profile.camera or {}
  local environment = profile.environment or {}
  return {
    sprite_policy = "random_per_spin",
    yaw_mode = "drift_only",
    yaw_enabled = true,
    control_schema = controls.schema or "omnidirectional_arrows",
    movement_mode = movement.constraint or "free",
    camera_mode = camera.behavior or "smooth_follow",
    background_id = environment.background_id or "motocrotte_background_01",
    profile_slot = 1
  }
end

function Experiment.cycle(state, field, direction)
  local values = assert(Experiment.options[field], "Unknown Playground experiment field: " .. tostring(field))
  local current = state[field]
  local index = 1
  for candidate_index, candidate in ipairs(values) do
    if candidate == current then index = candidate_index break end
  end
  index = ((index - 1 + (direction or 1)) % #values) + 1
  state[field] = values[index]
  return state[field]
end

function Experiment.resolve(profile, state)
  local result = copy(profile)
  result.controls = merge(result.controls, { schema = state.control_schema })
  result.movement = merge(result.movement, { constraint = state.movement_mode })
  result.camera = merge(result.camera, {
    behavior = state.camera_mode
  })
  result.directional_animation = merge(result.directional_animation, {
    variant_policy = state.sprite_policy
  })
  result.visual = merge(result.visual, {
    yaw_mode = state.yaw_mode,
    yaw_enabled = state.yaw_mode ~= "off",
    orientation_enabled = state.yaw_mode == "all_movement"
  })
  result.environment = merge(result.environment, { background_id = state.background_id })
  return result
end

return Experiment
