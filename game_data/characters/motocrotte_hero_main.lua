-- Gameplay configuration scaffold generated during promotion.
return {
  asset_id = "motocrotte_hero_main",
  position = { x = 0, ground_y = 0, z = 0 },
  scale = 1,
  anchor = { x = 30, y = 60 },
  facing = {
    enabled = true,
    default = "right",
    source = "right"
  },
  default_animation = nil,
  movement = {
    acceleration = 900,
    deceleration = 1100,
    max_speed = 260,
    vertical_speed = 180,
    animation = "hero_main_cycle",
    animation_loop = true
  },
  drift = {
    enabled = true,
    action = "drift",
    traction = 0.36,
    rotation_response = 8,
    max_visual_angle = math.rad(28),
    drift_threshold = 0.25,
    visual_mode = "flat_rotate",
    modes = { "flat_rotate", "directional_views", "hybrid" },
    directional_views = {
      count = 8,
      fallback_to_flat_rotation = true
    }
  },
  visual = {
    test_enabled = true,
    test_mode = "yaw_squash",
    yaw_speed = math.rad(90),
    orientation_enabled = true,
    yaw_response = 10,
    minimum_speed_for_turn = 8,
    directional_view_count = 8,
    modes = { "yaw_squash", "directional_views", "hybrid" }
  },
  collision = { enabled = false, auto_sensor = true, sensors = {} }
}
