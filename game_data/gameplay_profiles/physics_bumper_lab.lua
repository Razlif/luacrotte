-- Playground 7: the real gameplay physics world rendered as simple rectangles.
-- This profile deliberately has no sprite, animation, background, or mask
-- dependency. It is a visual diagnostic of the same gravityless physics layer.
return {
  id = "physics_bumper_lab",
  version = 1,
  label = "Physics Bumper Lab",
  projection = "rectangles",
  controls = { schema = "omnidirectional_arrows" },
  movement = {
    constraint = "free",
    acceleration = 900,
    deceleration = 700,
    coast_deceleration = 700,
    max_speed = 360,
    vertical_speed = 360,
    steering_response = 8,
    max_turn_rate = math.rad(360),
    bounds = { left = 80, right = 1520, top = 80, bottom = 820 }
  },
  camera = {
    behavior = "static",
    follow_x = false,
    follow_y = false,
    smoothing = 8,
    zoom = 1,
    center_y = 450
  },
  visual = { orientation = "yaw_squash", yaw_mode = "off" },
  drift = { enabled = false },
  environment = {},
  spawn = { x = 800, ground_y = 450, z = 0 },
  physics = {
    enabled = true,
    gravity_x = 0,
    gravity_y = 0,
    fixed_timestep = 1 / 60,
    bounds = { left = 80, right = 1520, top = 80, bottom = 820 }
  },
  bumper_lab = {
    bounds = { left = 80, right = 1520, top = 80, bottom = 820 },
    hero = {
      id = "bumper_hero",
      width = 84,
      height = 28,
      color = { 0.20, 0.85, 1.00, 0.85 }
    },
    enemies = {
      { id = "bumper_enemy_01", x = 1060, y = 450, width = 70, height = 26, color = { 1.00, 0.35, 0.35, 0.85 } },
      { id = "bumper_enemy_02", x = 1060, y = 570, width = 70, height = 26, color = { 1.00, 0.70, 0.25, 0.85 } },
      { id = "bumper_enemy_03", x = 520, y = 450, width = 70, height = 26, color = { 0.75, 0.45, 1.00, 0.85 } }
    }
  }
}
