return {
  id = "arena_follow",
  version = 2,
  status = "production",
  label = "Arena: Smooth Follow",
  camera = {
    behavior = "smooth_follow",
    target = "hero",
    follow_x = true,
    follow_y = true,
    smoothing = 8,
    zoom = 1,
    look_ahead_x = 0,
    look_ahead_y = 0
  },
  controls = { schema = "omnidirectional_arrows", binding_set = "keyboard_arrows" },
  movement = {
    constraint = "free",
    allowed_axes = { x = true, y = true },
    acceleration = 900,
    max_speed = 260,
    brake_deceleration = 700,
    cone_angle = math.rad(45),
    coast_deceleration = 250,
    steering_response = 8,
    max_turn_rate = math.rad(180)
  },
  drift = {
    enabled = true,
    entry_time = 0.08,
    exit_time = 0.35,
    minimum_speed = 1,
    normal_grip = 1.0,
    drift_grip = 0.36,
    drift_deceleration = 120,
    drift_turn_rate = math.rad(140),
    spin_speed = math.rad(360),
    spin_default_direction = 1,
    spin_steering_threshold = math.rad(10)
  },
  visual = { orientation = "yaw_squash", yaw_enabled = true },
  directional_animation = { variant_policy = "random_per_spin" },
  environment = { background_id = "motocrotte_background_01" },
  transitions = { preserve_velocity = true, preserve_yaw = true, clear_drift = true }
}
