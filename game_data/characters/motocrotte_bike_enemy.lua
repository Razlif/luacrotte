-- Runtime enemy definition for the promoted side-view bike prop.
return {
  asset_id = "motocrotte_bike_variant_01",
  runtime_id = "yasuke_bike_enemy",
  controller = "follow_enemy",
  position = { x = 1100, ground_y = 1057, z = 0 },
  scale = 2.197,
  anchor = { x = 30, y = 58 },
  facing = { enabled = true, default = "left", source = "right" },
  default_animation = "traffic_cycle",
  default_animation_loop = true,
  movement = { horizontal_speed = 105, vertical_speed = 105 },
  follow = {
    follow_distance = 80,
    stop_distance = 80,
    speed = 105,
    hit_pause = 0.35
  },
  combat = {
    health = 3,
    mass = 1,
    collision_radius = 32,
    hit_cooldown = 0.35,
    recovery_time = 3.5,
    respawn_enabled = true,
    respawn_time = 1.0,
    impacts = {
      spinning_drift = {
        -- Spinning drift is a planted spin test: keep the enemy close while
        -- yaw supplies the dramatic part of the response.
        knockback = 60,
        impact_velocity_scale = 0,
        yaw_speed = math.rad(720),
        duration = 3.5
      },
      straight_drift = {
        knockback = 420,
        yaw_speed = math.rad(45),
        duration = 0.6
      },
      regular_drive = {
        knockback_scale = 1.0,
        duration = 0.35
      },
      glide = {
        knockback_scale = 0.35,
        duration = 0.2
      }
    }
  },
  collision = { enabled = true, auto_sensor = true, sensors = {} }
}
