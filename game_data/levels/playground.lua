-- Static MotoCrotte asset checkpoint.
return {
  id = "playground",
  music_id = "luacrotte_main_music",
  background_id = "motocrotte_background_01",
  gameplay_profile_id = "arena_follow",
  world = {
    left = 0,
    top = 0,
    right = 1672,
    bottom = 1200
  },
  ground_y = 700,
  hero_position = { x = 203, ground_y = 974, z = 0 },
  hero_bounds = {
    left = 0,
    right = 1285,
    top = 284,
    bottom = 1147
  },
  physics = {
    enabled = true,
    gravity_x = 0,
    gravity_y = 0,
    fixed_timestep = 1 / 60,
    bounds = {
      left = 0,
      right = 1285,
      top = 284,
      bottom = 1147
    }
  },
  camera = {
    width = 1280,
    height = 720,
    smoothing = 8,
    zoom = 1
  },
  max_enemies = 1,
  enemies = {
    {
      id = "yasuke_bike_enemy_01",
      definition = "motocrotte_bike_enemy",
      spawn = { x = 1100, ground_y = 1057 },
      respawn = true,
      respawn_delay = 3.5
    }
  },
  content = {
    characters = { "luacrotte_hero_motorcycle_direction_set_v001" },
    props = { "motocrotte_bike_variant_01" },
    effects = { "mud_hose_blobs" },
    audio = { "luacrotte_main_music", "motocrotte_idle", "motocrotte_running" }
  }
}
