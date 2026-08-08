-- Profile 5: arena-follow movement using the fenced concrete park background.
local base = require("game_data.gameplay_profiles.arena_follow")

local function clone(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = clone(child) end
  return result
end

local profile = clone(base)
profile.id = "park_arena_follow"
profile.version = 1
profile.status = "experimental"
profile.label = "Park Arena: Smooth Follow"
profile.camera.follow_y = true
profile.camera.center_y = nil
profile.camera.smoothing = 16
profile.movement.unbounded = nil
profile.movement.bounds = { left = 333, right = 2191, top = 586, bottom = 1771 }
profile.movement.acceleration = 1600
profile.movement.max_speed = 500
profile.movement.vertical_speed = 500
profile.spawn = { x = 333, ground_y = 1771, z = 0 }
profile.environment.background_id = "fenced_concrete_park_base_v001"
profile.environment.background_track = { enabled = false }
profile.environment.background_scale = 1.98
profile.environment.background_world_space = true
profile.environment.hero_scale = 1.32
profile.world_unbounded = nil
-- Camera-only padding keeps the hero and the angled park corners inside the
-- viewport while the gameplay bounds remain the exact fence coordinates.
profile.world = { left = 313, right = 2291, top = 466, bottom = 1891 }
return profile
