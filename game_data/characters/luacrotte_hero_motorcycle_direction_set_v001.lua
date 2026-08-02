local function make_variant(down_right, down_left, up_left, up_right)
  return {
    animation_source = "motorcycle_direction_full",
    frame_map = { 3, down_right, 1, down_left, 7, up_left, 5, up_right }
  }
end

local diagonal_variants = {}
-- Full-atlas runtime frame numbers, in row-major order from the reviewed 4x4
-- source grid. The four cardinal frames are fixed; only these diagonal lists
-- participate in per-drift randomization.
local down_right_frames = { 2, 8, 15, 16 }
local down_left_frames = { 10, 11 }
local up_left_frames = { 4, 13, 14 }
local up_right_frames = { 6, 12 }
for _, down_right in ipairs(down_right_frames) do
  for _, down_left in ipairs(down_left_frames) do
    for _, up_left in ipairs(up_left_frames) do
      for _, up_right in ipairs(up_right_frames) do
        diagonal_variants[#diagonal_variants + 1] = make_variant(down_right, down_left, up_left, up_right)
      end
    end
  end
end

return {
  asset_id = "luacrotte_hero_motorcycle_direction_set_v001",
  position = { x = 0, ground_y = 0, z = 0 },
  scale = 1,
  anchor = { x = 32, y = 56 },
  facing = {
    enabled = false,
    default = "right",
    source = "right"
  },
  default_animation = "motorcycle_direction_set",
  default_animation_loop = true,
  movement = {
    acceleration = 1150,
    deceleration = 1100,
    coast_deceleration = 120,
    steering_response = 8,
    max_turn_rate = math.rad(180),
    max_speed = 340,
    vertical_speed = 180,
    animation = "motorcycle_direction_set",
    animation_loop = true,
    animation_idle = true
  },
  braking_visual = { enabled = true, angle = math.rad(45), minimum_speed = 5 },
  drift = {
    enabled = true,
    action = "drift",
    traction = 0.36,
    normal_grip = 1.0,
    drift_grip = 0.36,
    entry_time = 0.08,
    exit_time = 0.02,
    minimum_spin = math.rad(90),
    minimum_speed = 1,
    drift_deceleration = 120,
    orbit_radius_default = 15,
    orbit_radius_min = 0,
    orbit_radius_max = 60,
    orbit_radius_rate = 15,
    drift_turn_rate = math.rad(140),
    rotation_response = 8,
    max_visual_angle = math.rad(28),
    drift_threshold = 0.25,
    spin_speed = math.rad(360),
    spin_default_direction = 1,
    spin_steering_threshold = math.rad(10),
    visual_mode = "directional_views",
    modes = { "directional_views", "hybrid", "yaw_squash" },
    directional_views = {
      count = 8,
      fallback_to_flat_rotation = false,
      directional_frame_map = { 3, 2, 1, 8, 7, 6, 5, 4 },
      directional_pivot = {
        radius = 20,
        radius_step = 5,
        radius_min = 0,
        radius_max = 100,
        angle_offset = 0,
        facing_offset = math.pi,
        show_orbit = true,
        anchor_x = 32,
        anchor_y = 56
      }
    }
  },
  visual = {
    test_enabled = false,
    test_mode = "directional_views",
    yaw_speed = math.rad(90),
    orientation_enabled = true,
    yaw_response = 10,
    minimum_speed_for_turn = 8,
    directional_view_count = 8,
    directional_frame_map = { 3, 2, 1, 8, 7, 6, 5, 4 },
    directional_pivot = {
      radius = 20,
      radius_step = 5,
      radius_min = 0,
      radius_max = 100,
      angle_offset = 0,
      facing_offset = math.pi,
      show_orbit = true,
      anchor_x = 32,
      anchor_y = 56
    },
    modes = { "directional_views", "hybrid", "yaw_squash" }
  },
  directional_animation = {
    canonical_source = "motorcycle_direction_full",
    direction_count = 8,
    cardinal_frames = { [1] = 3, [3] = 1, [5] = 7, [7] = 5 },
    frame_map = { 3, 2, 1, 10, 7, 4, 5, 6 },
    variant_policy = "random_per_drift",
    variant_sets = diagonal_variants
  },
  collision = { enabled = false, auto_sensor = true, sensors = {} }
}
