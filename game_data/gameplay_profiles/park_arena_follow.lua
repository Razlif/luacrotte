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
profile.movement.acceleration = 1800
profile.movement.max_speed = 500
profile.movement.vertical_speed = 500
profile.spawn = { x = 333, ground_y = 1771, z = 0 }
profile.environment.background_id = "fenced_concrete_park_base_v001"
profile.environment.background_track = { enabled = false }
profile.environment.background_scale = 1.98
profile.environment.background_world_space = true
profile.environment.hero_scale = 1.32
profile.drift.behavior = "straight_orbit"
profile.drift.straight_tilt_direction = 1
profile.drift.radius_control = "fixed"
profile.drift.orbit_radius_reference = "arena_follow"
-- Profile 5's enlarged presentation made the shared 30px orbit read as tiny.
-- Keep the Profile 1 base, compensate for hero scale, then give the arena a
-- larger physical orbit for a readable slingshot path.
profile.drift.orbit_radius_scale = profile.environment.hero_scale * 2.0
profile.drift.disable_gas_brake = true
profile.drift.max_spin_rounds = 3
profile.drift.spin_momentum_per_round = 120
profile.drift.spin_momentum_cap = 360
-- The fixed kick is intentionally smaller than the spin-earned momentum.
-- Each completed round still adds the configured per-round bonus.
profile.drift.slingshot_impulse = 450
profile.drift.slingshot_decay = 700
profile.drift.slingshot_min_speed = 4
profile.world_unbounded = nil
-- Camera-only padding keeps the hero and the angled park corners inside the
-- viewport while the gameplay bounds remain the exact fence coordinates.
profile.world = { left = 313, right = 2291, top = 466, bottom = 1891 }
return profile
