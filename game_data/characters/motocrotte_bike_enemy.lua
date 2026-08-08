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
  collision = { enabled = true, auto_sensor = true, sensors = {} }
}
