return {
  id = "arena_follow",
  version = 1,
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
  controls = { schema = "omnidirectional", binding_set = "keyboard_arrows_wasd" },
  movement = {
    constraint = "free",
    allowed_axes = { x = true, y = true }
  },
  drift = { enabled = true },
  visual = { orientation = "yaw_squash" },
  transitions = { preserve_velocity = true, preserve_yaw = true, clear_drift = true }
}
