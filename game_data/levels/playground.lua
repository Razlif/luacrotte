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
  camera = {
    width = 1280,
    height = 720,
    smoothing = 8,
    zoom = 1
  },
  content = {
    characters = { "luacrotte_hero_motorcycle_direction_set_v001" },
    props = { "motocrotte_bike_variant_01" },
    effects = { "mud_hose_blobs" },
    audio = { "luacrotte_main_music", "motocrotte_idle", "motocrotte_running" }
  }
}
