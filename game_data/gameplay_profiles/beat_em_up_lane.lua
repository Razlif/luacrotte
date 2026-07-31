return {
  id = "beat_em_up_lane",
  version = 1,
  status = "production",
  label = "Beat-em-Up: Lane",
  camera = {
    behavior = "follow_x_only",
    target = "hero",
    follow_x = true,
    follow_y = false,
    smoothing = 10,
    zoom = 1,
    look_ahead_x = 80,
    look_ahead_y = 0
  },
  controls = { schema = "beat_em_up", binding_set = "keyboard_arrows_wasd" },
  movement = {
    constraint = "lane",
    allowed_axes = { x = true, y = true },
    lane_depth = { min = 560, max = 700 }
  },
  drift = { enabled = false },
  visual = { orientation = "yaw_squash" },
  transitions = { preserve_velocity = false, preserve_yaw = true, clear_drift = true }
}
