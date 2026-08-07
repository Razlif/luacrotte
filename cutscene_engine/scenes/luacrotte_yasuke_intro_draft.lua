-- First-act opening draft: Luacrotte performs first, then Yasuke answers.
-- The shared rear-view horizon matches Playground profile 3's environment.
return {
  id = "luacrotte_yasuke_intro_draft",

  background = {
    asset_id = "rear_sky_horizon"
  },

  camera = {
    position = { x = 480, ground_y = 270 },
    zoom = 1
  },

  actors = {
    luacrotte = {
      asset_id = "luacrotte_hero_motorcycle_direction_set_v001",
      position = { x = 310, ground_y = 435, z = 0 },
      scale = 1.55,
      default_animation = "motorcycle_direction_set",
      default_animation_loop = true
    },
    yasuke = {
      asset_id = "motocrotte_bike_variant_01",
      asset_type = "prop",
      trick_presentation = { yaw_enabled = true },
      position = { x = 650, ground_y = 435, z = 0 },
      scale = 1.65,
      default_animation = "traffic_cycle",
      default_animation_loop = true
    }
  },

  timeline = {
    { command = "play_music", music_id = "luacrotte_main_music", loop = true, volume = 0.35 },
    {
      command = "ride_trick",
      actor = "luacrotte",
      center_x = 380,
      center_ground_y = 430,
      radius_x = 145,
      radius_y = 42,
      turns = 1.25,
      direction = "clockwise",
      hop_height = 18,
      lean_degrees = 12,
      animation = "motorcycle_direction_set",
      duration = 5
    },
    {
      command = "ride_trick",
      actor = "yasuke",
      center_x = 600,
      center_ground_y = 430,
      radius_x = 145,
      radius_y = 42,
      turns = 1.25,
      direction = "counterclockwise",
      hop_height = 16,
      lean_degrees = 10,
      animation = "traffic_cycle",
      duration = 5
    },
    { command = "wait", duration = 0.5 },
    { command = "stop_music", fade = 0.5 }
  }
}
