return {
  id = "arena_follow",
  version = 2,
  status = "production",
  label = "Arena: Smooth Follow",
  camera = {
    behavior = "static",
    target = "hero",
    follow_x = true,
    follow_y = true,
    smoothing = 8,
    zoom = 1,
    look_ahead_x = 0,
    look_ahead_y = 0
  },
  controls = { schema = "gas_steering", binding_set = "keyboard_arrows" },
  movement = {
    constraint = "free",
    allowed_axes = { x = true, y = true },
    acceleration = 1150,
    max_speed = 340,
    brake_deceleration = 400,
    cone_angle = math.rad(45),
    coast_deceleration = 120,
    steering_response = 8,
    steering_rate = math.rad(360),
    max_turn_rate = math.rad(180),
  },
  braking_visual = { enabled = true, frame_step = math.rad(45), minimum_speed = 5 },
  dash = {
    enabled = true,
    action = "dash",
    minimum_speed = 1,
    boost_speed = 600,
    boost_duration = 0.22,
    stoppie_duration = 1.0,
    recovery_duration = 0.25,
    cooldown = 0.8,
    cancels_drift = true,
    drift_combo_mode = "minimum_orbit",
    drift_combo_orbit_radius = 5,
    front_wheelie = {
      angle = math.rad(70),
      frame = 3,
      animation_source = "motorcycle_direction_full",
      raised_wheel = "back",
      pitch_sign = 1,
      -- Measured from the selected right-facing frame: the front wheel is
      -- the planted wheel, not the sprite center.
      contact_anchor = { x = 54, y = 55 }
    },
    axial_spin_speed = math.rad(540),
    wheelie_spin = {
      -- The planted front wheel is kept fixed for each yaw direction.
      -- The opposite wheel is allowed to travel around this contact point.
      contact_anchor = {
        right = { x = 48, y = 56 },
        down_right = { x = 44, y = 56 },
        down = { x = 32, y = 56 },
        down_left = { x = 20, y = 56 },
        left = { x = 16, y = 56 },
        up_left = { x = 20, y = 56 },
        up = { x = 32, y = 56 },
        up_right = { x = 44, y = 56 }
      }
    }
  },
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
  environment = { background_id = "motocrotte_background_01" },
  transitions = { preserve_velocity = true, preserve_yaw = true, clear_drift = true }
}
