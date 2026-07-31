return {
  id = "side_scroller",
  version = 1,
  status = "production",
  label = "Side-Scroller",
  camera = {
    behavior = "follow_x_lookahead",
    target = "hero",
    follow_x = true,
    follow_y = false,
    smoothing = 12,
    zoom = 1,
    look_ahead_x = 120,
    look_ahead_y = 0
  },
  controls = { schema = "side_scroller", binding_set = "keyboard_arrows_wasd" },
  movement = {
    constraint = "horizontal_only",
    allowed_axes = { x = true, y = false }
  },
  drift = { enabled = false },
  visual = { orientation = "yaw_squash" },
  transitions = { preserve_velocity = false, preserve_yaw = true, clear_drift = true }
}
