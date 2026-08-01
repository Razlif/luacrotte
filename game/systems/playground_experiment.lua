-- Temporary Playground experiment layer. It never mutates the source profile.
local Experiment = {}

Experiment.options = {
  sprite_policy = { "fixed", "random_per_spin" },
  control_schema = { "omnidirectional_arrows", "throttle_steering" },
  movement_mode = { "free", "heading_cone", "lane" },
  camera_mode = { "static", "smooth_follow", "lookahead_follow" },
  background_id = { "motocrotte_background_01", "enchanted_wizard_training_meadow" }
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

function Experiment.default()
  return {
    sprite_policy = "random_per_spin",
    yaw_enabled = true,
    control_schema = "omnidirectional_arrows",
    movement_mode = "free",
    camera_mode = "smooth_follow",
    background_id = "motocrotte_background_01",
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
    behavior = state.camera_mode,
    follow_x = state.camera_mode ~= "static",
    follow_y = state.camera_mode ~= "static"
  })
  result.directional_animation = merge(result.directional_animation, {
    variant_policy = state.sprite_policy
  })
  result.visual = merge(result.visual, {
    yaw_enabled = state.yaw_enabled,
    orientation_enabled = state.yaw_enabled
  })
  result.environment = merge(result.environment, { background_id = state.background_id })
  return result
end

return Experiment
