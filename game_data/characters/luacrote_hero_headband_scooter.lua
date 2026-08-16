local base = require("game_data.characters.luacrotte_hero_motorcycle_direction_set_v001")

local definition = {}
for key, value in pairs(base) do definition[key] = value end

definition.asset_id = "luacrote_hero_headband_scooter"
definition.scale = 0.42
definition.anchor = { x = 128, y = 224 }
definition.default_animation = "omnidirectional_sprites"
definition.default_animation_loop = true
definition.movement = {}
for key, value in pairs(base.movement or {}) do definition.movement[key] = value end
definition.movement.animation = "omnidirectional_sprites"
definition.movement.animation_loop = true
definition.jump = {
  enabled = true,
  duration = 0.68,
  height = 72,
  wheelie = {
    height = 144,
    angle = math.rad(-45),
    contact_anchor = { x = 128, y = 224 }
  },
  wave = {
    pitch = -math.rad(12),
    cycles = 1.15,
    phase_offset = 0,
    landing_duration = 0.42,
    aftershock_count = 3,
    aftershock_angle = math.rad(7)
  }
}
definition.drift = {}
for key, value in pairs(base.drift or {}) do definition.drift[key] = value end
definition.drift.directional_views = {}
for key, value in pairs((base.drift or {}).directional_views or {}) do
  definition.drift.directional_views[key] = value
end
definition.drift.directional_views.directional_frame_map = { 4, 3, 2, 1, 8, 7, 6, 5 }
definition.drift.directional_views.directional_pivot = {
  radius = 20,
  radius_step = 5,
  radius_min = 0,
  radius_max = 100,
  angle_offset = 0,
  facing_offset = math.pi,
  show_orbit = true,
  anchor_x = 128,
  anchor_y = 224
}
definition.directional_animation = {
  canonical_source = "omnidirectional_sprites",
  direction_count = 8,
  -- Runtime order: front, front-right, right, back-right,
  -- back, back-left, left, front-left.
    -- Resolver slots are right, down-right, down, down-left, left,
    -- up-left, up, up-right.  PixelLab's sheet is ordered down-left,
    -- front, down-right, right, up-right, rear, up-left, left.
    cardinal_frames = { [1] = 4, [3] = 2, [5] = 8, [7] = 6 },
    frame_map = { 4, 3, 2, 1, 8, 7, 6, 5 },
  variant_policy = "fixed",
  variant_sets = {}
}
definition.visual = {}
for key, value in pairs(base.visual or {}) do definition.visual[key] = value end
definition.visual.directional_view_count = 8
definition.visual.directional_frame_map = { 4, 3, 2, 1, 8, 7, 6, 5 }
definition.visual.directional_pivot = {
  radius = 20,
  radius_step = 5,
  radius_min = 0,
  radius_max = 100,
  angle_offset = 0,
  facing_offset = math.pi,
  show_orbit = true,
  anchor_x = 128,
  anchor_y = 224
}
definition.visual.modes = { "directional_views", "hybrid", "yaw_squash" }
definition.visual.test_mode = "directional_views"

definition.collision = {
  enabled = true,
  auto_sensor = true,
  sensors = {},
  base = {
    enabled = true,
    width_source = "opaque_bounds_union",
    width_ratio = 1.0,
    height_ratio = 0.10
  },
  pixel_mask = { enabled = false, cache = true }
}

return definition
