return {
  id = "rear_view_yaw_card",
  version = 4,
  status = "experimental",
  label = "Rear View: Front/Back Yaw Card",
  camera = {
    behavior = "static",
    target = "road",
    follow_x = false,
    follow_y = false,
    smoothing = 8,
    zoom = 1,
    center_y = 360
  },
  controls = { schema = "gas_steering", binding_set = "keyboard_arrows" },
  movement = {
    constraint = "rear_depth",
    allowed_axes = { x = true, y = true },
    depth_bounds = { min = 1000, max = 1147 },
    acceleration = 600,
    max_speed = 170,
    brake_deceleration = 260,
    coast_deceleration = 75,
    steering_response = 7,
    steering_rate = math.rad(360),
    max_turn_rate = math.rad(150),
    initial_heading = -math.pi / 2,
    animation = "motorcycle_direction_full",
    animation_loop = true,
    animation_idle = true,
    perspective_cone = {
      center_x = 480,
      far_y = 1000,
      near_y = 1147,
      far_half_width = 48,
      near_half_width = 360
    }
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
    drift_deceleration = 100,
    orbit_radius_default = 30,
    orbit_radius_min = 0,
    orbit_radius_max = 120,
    orbit_radius_rate = 60,
    orbit_radius_decrease_rate = 60,
    drift_turn_rate = math.rad(120),
    spin_speed = math.rad(360),
    spin_default_direction = 1,
    spin_steering_threshold = math.rad(10)
  },
  visual = {
    orientation = "yaw_squash",
    yaw_enabled = true,
    yaw_mode = "all_movement",
    yaw_axis = math.pi / 2
  },
  directional_animation = {
    canonical_source = "motorcycle_direction_full",
    direction_count = 8,
    variant_policy = "fixed",
    yaw_card = {
      animation_source = "motorcycle_direction_full",
      front_frame = 1,
      front_tilt_frame = 9,
      back_frame = 5,
      back_tilt_frame = 13,
      frame_map = { 9, 9, 1, 9, 9, 13, 5, 13 },
      flip_map = { false, false, false, true, true, false, false, true }
    }
  },
  environment = {
    background_id = "rear_sky_horizon",
    projection = "perspective_ground",
    horizon_y = 180,
    ground_y = 475,
    min_scale = 1.0,
    max_scale = 3.2
  },
  spawn = { x = 442, ground_y = 1147, z = 0 },
  transitions = { preserve_velocity = false, preserve_yaw = false, clear_drift = true }
}
