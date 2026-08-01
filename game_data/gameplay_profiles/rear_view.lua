return {
  id = "rear_view",
  version = 1,
  status = "experimental",
  label = "Rear View",
  camera = {
    behavior = "static",
    target = "road",
    follow_x = false,
    follow_y = false,
    smoothing = 8,
    zoom = 1,
    center_y = 270
  },
  controls = { schema = "gas_steering", binding_set = "keyboard_arrows" },
  movement = {
    constraint = "rear_depth",
    allowed_axes = { x = true, y = true },
    depth_bounds = { min = 698, max = 1147 },
    acceleration = 700,
    max_speed = 220,
    brake_deceleration = 650,
    coast_deceleration = 180,
    steering_response = 7,
    steering_rate = math.rad(360),
    max_turn_rate = math.rad(150)
  },
  drift = {
    enabled = true,
    entry_time = 0.08,
    exit_time = 0.35,
    minimum_speed = 1,
    normal_grip = 1.0,
    drift_grip = 0.36,
    drift_deceleration = 100,
    drift_turn_rate = math.rad(120),
    spin_speed = math.rad(360),
    spin_default_direction = 1,
    spin_steering_threshold = math.rad(10)
  },
  visual = { orientation = "yaw_squash", yaw_enabled = true },
  directional_animation = { variant_policy = "random_per_spin" },
  environment = {
    background_id = "rear_sky_horizon",
    projection = "perspective_ground",
    horizon_y = 180,
    ground_y = 475,
    min_scale = 0.55,
    max_scale = 1.35
  },
  transitions = { preserve_velocity = false, preserve_yaw = true, clear_drift = true }
}
