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
profile.combat = {
  separation_distance = 2,
  maximum_knockback = 1200,
  impact_cooldown = 0.35,
  spinning_drift_multiplier = 1.0,
  straight_drift_multiplier = 1.0,
  recovery_duration = 3.5,
  responses = {
    drift_orbit = {
      knockback = 900,
      impact_velocity_scale = 0.35,
      yaw_speed = math.rad(720),
      duration = 3.5,
      hit_pause = 3.5
    },
    straight_drift = {
      knockback = 420,
      impact_velocity_scale = 0.2,
      yaw_speed = math.rad(45),
      duration = 0.6,
      hit_pause = 0.6
    },
    regular_drive = { knockback_scale = 1.0, duration = 0.35, hit_pause = 0.35 },
    glide = { knockback_scale = 0.35, duration = 0.2, hit_pause = 0.2 },
    stationary = { knockback_scale = 0.15, duration = 0.15, hit_pause = 0.15 }
  }
}
profile.world_unbounded = nil
-- Profile 5 starts as an empty combat sandbox. G adds instances from this
-- template at runtime; the level's default enemy remains available to the
-- other profiles.
profile.enemies = {}
profile.enemy_spawning = {
  enabled = true,
  max_count = 32,
  template = {
    id = "yasuke_bike_enemy",
    definition = "motocrotte_bike_enemy",
    respawn = true,
    respawn_delay = 3.5
  }
}
-- Camera-only padding keeps the hero and the angled park corners inside the
-- viewport while the gameplay bounds remain the exact fence coordinates.
profile.world = { left = 313, right = 2291, top = 466, bottom = 1891 }
return profile
