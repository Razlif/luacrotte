return {
  id = "side_view",
  version = 4,
  status = "experimental",
  label = "Side View",
  camera = {
    behavior = "smooth_follow",
    target = "hero",
    follow_x = true,
    follow_y = false,
    smoothing = 10,
    zoom = 1.35,
    center_y = 960,
    look_ahead_x = 0,
    look_ahead_y = 0
  },
  controls = { schema = "gas_steering", binding_set = "keyboard_arrows" },
  movement = {
    constraint = "side_scroll",
    bounds = { left = 325, right = 6325, top = 698, bottom = 1147 },
    allowed_axes = { x = true, y = false },
    acceleration = 1150,
    max_speed = 340,
    brake_deceleration = 400,
    coast_deceleration = 120,
    steering_response = 8,
    steering_rate = math.rad(360),
    max_turn_rate = math.rad(180)
  },
  braking_visual = { enabled = true, frame_step = math.rad(45), minimum_speed = 5 },
  dash = { enabled = false },
  drift = {
    enabled = true,
    entry_time = 0.08,
    exit_time = 0.02,
    minimum_spin = math.rad(90),
    minimum_speed = 1,
    normal_grip = 1.0,
    drift_grip = 0.36,
    drift_deceleration = 120,
    orbit_radius_default = 30,
    orbit_radius_min = 0,
    orbit_radius_max = 120,
    orbit_radius_rate = 60,
    orbit_radius_decrease_rate = 60,
    drift_turn_rate = math.rad(140),
    spin_speed = math.rad(360),
    spin_default_direction = 1,
    spin_steering_threshold = math.rad(10)
  },
  visual = { orientation = "yaw_squash", yaw_enabled = true },
  directional_animation = { variant_policy = "random_per_spin" },
  environment = {
    background_id = "motocrotte_background_01",
    projection = "flat",
    hero_scale = 1.45,
    background_track = {
      enabled = true,
      origin_x = 325,
      origin_y = 600,
      tile_width = 1200,
      count = 5
    }
  },
  world = { left = 325, right = 6325, top = 0, bottom = 1283 },
  spawn = { x = 805, ground_y = 1065, z = 0 },
  transitions = { preserve_velocity = false, preserve_yaw = true, clear_drift = true }
}
