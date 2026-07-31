return {
  asset_id = "luacrotte_hero_motorcycle_direction_set_v001",
  position = { x = 0, ground_y = 0, z = 0 },
  scale = 1,
  anchor = { x = 32, y = 56 },
  facing = {
    enabled = false,
    default = "right",
    source = "right"
  },
  default_animation = "motorcycle_direction_set",
  default_animation_loop = true,
  movement = {
    acceleration = 900,
    deceleration = 1100,
    max_speed = 260,
    vertical_speed = 180,
    animation = "motorcycle_direction_set",
    animation_loop = true,
    animation_idle = true
  },
  drift = {
    enabled = true,
    action = "drift",
    traction = 0.36,
    rotation_response = 8,
    max_visual_angle = math.rad(28),
    drift_threshold = 0.25,
    spin_speed = math.rad(360),
    spin_default_direction = 1,
    spin_steering_threshold = math.rad(10),
    visual_mode = "directional_views",
    modes = { "directional_views", "hybrid", "yaw_squash" },
    directional_views = {
      count = 8,
      fallback_to_flat_rotation = false,
      directional_frame_map = { 3, 2, 1, 8, 7, 6, 5, 4 },
      directional_pivot = {
        radius = 20,
        radius_step = 5,
        radius_min = 0,
        radius_max = 100,
        angle_offset = 0,
        facing_offset = math.pi,
        show_orbit = true,
        anchor_x = 32,
        anchor_y = 56
      }
    }
  },
  visual = {
    test_enabled = false,
    test_mode = "directional_views",
    yaw_speed = math.rad(90),
    orientation_enabled = true,
    yaw_response = 10,
    minimum_speed_for_turn = 8,
    directional_view_count = 8,
    directional_frame_map = { 3, 2, 1, 8, 7, 6, 5, 4 },
    directional_pivot = {
      radius = 20,
      radius_step = 5,
      radius_min = 0,
      radius_max = 100,
      angle_offset = 0,
      facing_offset = math.pi,
      show_orbit = true,
      anchor_x = 32,
      anchor_y = 56
    },
    modes = { "directional_views", "hybrid", "yaw_squash" }
  },
  collision = { enabled = false, auto_sensor = true, sensors = {} }
}
