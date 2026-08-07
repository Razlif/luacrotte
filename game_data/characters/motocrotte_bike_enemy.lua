-- Runtime enemy definition for the promoted side-view bike prop.
return {
  asset_id = "motocrotte_bike_variant_01",
  runtime_id = "yasuke_bike_enemy",
  controller = "patrol",
  position = { x = 1100, ground_y = 1057, z = 0 },
  scale = 1.3,
  anchor = { x = 30, y = 58 },
  facing = { enabled = true, default = "left", source = "right" },
  default_animation = "traffic_cycle",
  default_animation_loop = true,
  movement = { horizontal_speed = 105, vertical_speed = 0 },
  patrol = { left = 500, right = 1250 },
  collision = { enabled = true, auto_sensor = true, sensors = {} }
}
