return {
  id = "legacy_direct_drift",
  version = 1,
  status = "experiment",
  label = "Legacy: Direct Drift",
  physics = {
    enabled = true,
    gravity_x = 0,
    gravity_y = 0,
    fixed_timestep = 1 / 60,
    bounds = { left = 0, right = 1285, top = 284, bottom = 1147 }
  },
  camera = {
    behavior = "smooth_follow", target = "hero", follow_x = true, follow_y = true,
    smoothing = 8, zoom = 1, look_ahead_x = 0, look_ahead_y = 0
  },
  controls = { schema = "omnidirectional", binding_set = "keyboard_arrows_wasd" },
  movement = {
    solver = "legacy_direct_drift", constraint = "free",
    allowed_axes = { x = true, y = true },
    acceleration = 900, deceleration = 1100, max_speed = 260, vertical_speed = 260
  },
  drift = {
    enabled = true, traction = 0.36, spin_speed = math.rad(360),
    spin_default_direction = 1, spin_steering_threshold = math.rad(10)
  },
  visual = { orientation = "yaw_squash" },
  directional_animation = { variant_policy = "fixed" },
  transitions = { preserve_velocity = true, preserve_yaw = true, clear_drift = true }
}
