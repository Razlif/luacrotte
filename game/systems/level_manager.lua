-- Resolves level data, gameplay profiles, and scene-owned content requests.
local GameplayProfile = require("game.systems.gameplay_profile")

local LevelManager = { levels = {}, active = nil }

function LevelManager.configure(levels)
  LevelManager.levels = levels or {}
  LevelManager.active = nil
end

function LevelManager.load(level_id, profile_id)
  local definition = assert(LevelManager.levels[level_id], "Unknown level: " .. tostring(level_id))
  local profile = GameplayProfile.load(profile_id or definition.gameplay_profile_id)
  LevelManager.active = { id = level_id, definition = definition, profile = profile }
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
function LevelManager.get_content_dependencies()
  local active = assert(LevelManager.active, "No active level")
  return active.definition.content or {}
end
function LevelManager.unload() LevelManager.active = nil end

return LevelManager
