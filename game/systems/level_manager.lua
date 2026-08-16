-- Resolves level data, gameplay profiles, and scene-owned content requests.
local GameplayProfile = require("game.systems.gameplay_profile")

local LevelManager = { levels = {}, active = nil }

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = copy(child) end
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

local function resolve_physics(definition, profile)
  local config = merge({
    enabled = true,
    gravity_x = 0,
    gravity_y = 0,
    fixed_timestep = 1 / 60
  }, definition.physics)
  config = merge(config, profile.physics)

  -- Existing movement bounds remain the single source of truth unless a
  -- level/profile explicitly opts out or supplies a physics rectangle.
  -- This keeps older profiles compatible while making the resolved result
  -- available to the runtime and tools as explicit physics data.
  if config.bounds == nil then
    config.bounds = require("game.systems.gameplay_profile").bounds(definition, profile)
  end
  return config
end

function LevelManager.configure(levels)
  LevelManager.levels = levels or {}
  LevelManager.active = nil
end

function LevelManager.load(level_id, profile_id)
  local definition = assert(LevelManager.levels[level_id], "Unknown level: " .. tostring(level_id))
  local profile = GameplayProfile.load(profile_id or definition.gameplay_profile_id)
  LevelManager.active = {
    id = level_id,
    definition = definition,
    profile = profile,
    physics = resolve_physics(definition, profile)
  }
  return LevelManager.active
end

function LevelManager.get_active_level() return LevelManager.active end
function LevelManager.get_spawn(entity_id)
  local active = assert(LevelManager.active, "No active level")
  if entity_id == "hero" then return active.profile.spawn or active.definition.hero_position end
  return active.definition.spawns and active.definition.spawns[entity_id]
end
function LevelManager.get_bounds(entity_id)
  local active = assert(LevelManager.active, "No active level")
  if entity_id == "hero" then return GameplayProfile.bounds(active.definition, active.profile) end
  return active.definition.bounds and active.definition.bounds[entity_id]
end
function LevelManager.get_camera_config()
  return assert(LevelManager.active, "No active level").profile.camera
end
function LevelManager.get_physics_config()
  return assert(LevelManager.active, "No active level").physics
end
function LevelManager.get_content_dependencies()
  local active = assert(LevelManager.active, "No active level")
  return active.definition.content or {}
end
function LevelManager.unload() LevelManager.active = nil end

return LevelManager
