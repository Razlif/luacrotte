-- Static MotoCrotte checkpoint: promoted background plus hero image.
local asset_manifest = require("game_data.asset_manifest")
local hero_definition = require("game_data.characters.luacrotte_hero_motorcycle_direction_set_v001")
local scooter_hero_definition = require("game_data.characters.luacrote_hero_headband_scooter")
local enemy_definition = require("game_data.characters.motocrotte_bike_enemy")
local background_definition = asset_manifest.backgrounds.motocrotte_background_01
local level_definition = require("game_data.levels.playground")
local ContentManager = require("game.systems.content_manager")
local LevelManager = require("game.systems.level_manager")
local Character = require("game.entities.characters.character")
local CollisionDetection = require("game.systems.collision_detection")
local DrawOrder = require("game.systems.draw_order")
local MotocrotteDriver = require("game.controllers.motocrotte_driver")
local HeroMovement = require("game.systems.motocrotte_hero_movement")
local HeroOrientation = require("game.systems.motocrotte_hero_orientation")
local HeroRenderer = require("game.systems.motocrotte_hero_renderer")
local GameplayProfile = require("game.systems.gameplay_profile")
local PlaygroundExperiment = require("game.systems.playground_experiment")
local CameraManager = require("game.systems.camera_manager")
local ParallaxManager = require("game.systems.parallax")
local MotocrotteAudio = require("game.systems.motocrotte_audio")
local AudioManager = require("game.systems.audio_manager")
local MudHose = require("game.systems.mud_hose")
local mud_hose_definition = require("game_data.effects.mud_hose")

local function states_manager()
  return require("game.states_manager")
end

local Playground = {
  hero = nil,
  enemies = {},
  camera = nil,
  parallax = nil,
  last_collision_events = {},
  drift_mode_index = 1,
  visual_mode_index = 1,
  visual_lab_active = false,
  visual_yaw = 0,
  visual_orbit_radius = 20,
  profile_id = nil,
  profile = nil,
  base_profile = nil,
  experiment = PlaygroundExperiment.default(),
  profile_index = 1,
  hero_definition = hero_definition,
  -- Start with the canonical motorcycle hero; H still toggles between variants.
  hero_variant_index = 1,
  active_level_definition = level_definition,
  loaded_content = {}
}

local hero_definitions = { hero_definition, scooter_hero_definition }

local function selected_hero_definition()
  return hero_definitions[Playground.hero_variant_index] or hero_definition
end

local function selected_hero_content(content)
  if Playground.hero_variant_index == 2 then
    return content.scooter_character
  end
  return content.character
end

local function switch_hero()
  Playground.hero_variant_index = (Playground.hero_variant_index % #hero_definitions) + 1
  local definition = selected_hero_definition()
  local content = Playground.hero_variant_index == 2 and Playground.loaded_content.scooter_character or Playground.loaded_content.character
  local position = Playground.hero and Playground.hero.position or { x = 0, ground_y = 0, z = 0 }
  Playground.hero_definition = GameplayProfile.resolve_hero_definition(definition, Playground.profile)
  local replacement = Character.new(Playground.hero_definition, content)
  -- Character construction owns its initial position, but switching variants
  -- must explicitly carry over the live world position.  Do this as a fresh
  -- table assignment so no movement frame can observe a partially replaced
  -- character or a missing position object.
  replacement.position = {
    x = position.x or 0,
    ground_y = position.ground_y or position.y or 0,
    z = position.z or 0
  }
  Playground.hero = replacement
  Playground.set_visual_mode(HeroRenderer.mode_index(Playground.hero_definition.visual.test_mode, Playground.hero_definition))
  Playground.reset_visual_lab()
end

local function background_registry()
  return {
    motocrotte_background_01 = asset_manifest.backgrounds.motocrotte_background_01,
    enchanted_wizard_training_meadow = asset_manifest.backgrounds.enchanted_wizard_training_meadow,
    rear_sky_horizon = asset_manifest.backgrounds.rear_sky_horizon,
    fenced_concrete_park_base_v001 = asset_manifest.backgrounds.fenced_concrete_park_base_v001
  }
end

local function background_definition_for(id)
  return background_registry()[id] or background_definition
end

local function rebuild_parallax()
  if not Playground.camera then return end
  local selected = background_definition_for(Playground.experiment.background_id)
  local environment = Playground.profile and Playground.profile.environment or {}
  local track = environment.background_track
  local use_track = track and track.enabled == true and selected.id == environment.background_id
  Playground.parallax = ParallaxManager.new({
    {
      id = selected.id,
      image_path = selected.image.path,
      image = Playground.loaded_content.background and Playground.loaded_content.background.image.texture,
      speed_x = 1,
      speed_y = 1,
      repeat_x = false,
      repeat_y = false,
      fit = use_track and "track" or "cover",
      scale = environment.background_scale or 1,
      world_space = environment.background_world_space == true,
      world_x = environment.background_world_x or 0,
      world_y = environment.background_world_y or 0,
      track = use_track and track or nil,
      layer = 0
    }
  })
  Playground.parallax:set_camera(Playground.camera)
end

local function visual_modes()
  local definition = Playground.hero_definition or hero_definition
  return (definition.visual and definition.visual.modes) or { "yaw_squash" }
end

local function profile_list()
  return GameplayProfile.list()
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function Playground.set_profile(index_or_id)
  local profiles = profile_list()
  local selected = nil
  local selected_index = nil
  if type(index_or_id) == "number" then
    selected_index = ((index_or_id - 1) % #profiles) + 1
    selected = profiles[selected_index]
  else
    for index, profile in ipairs(profiles) do
      if profile.id == index_or_id then
        selected = profile
        selected_index = index
        break
      end
    end
  end
  assert(selected, "Unknown gameplay profile: " .. tostring(index_or_id))
  Playground.base_profile = GameplayProfile.load(selected.id)
  Playground.profile = Playground.base_profile
  Playground.profile_id = Playground.profile.id
  Playground.profile_index = selected_index
  Playground.hero_definition = GameplayProfile.resolve_hero_definition(selected_hero_definition(), Playground.profile)
  Playground.active_level_definition = {}
  for key, value in pairs(level_definition) do Playground.active_level_definition[key] = value end
  Playground.active_level_definition.hero_bounds = GameplayProfile.bounds(level_definition, Playground.profile)
  Playground.active_level_definition.world = GameplayProfile.world_bounds(level_definition, Playground.profile)
  if Playground.hero then
    local spawn = GameplayProfile.spawn(level_definition, Playground.profile)
    Playground.hero.definition = Playground.hero_definition
    Playground.hero.position.x = spawn.x
    Playground.hero.position.ground_y = spawn.ground_y
    Playground.hero.position.z = spawn.z
    local bounds = Playground.active_level_definition.hero_bounds
    if bounds then
      Playground.hero.position.x = clamp(Playground.hero.position.x, bounds.left, bounds.right)
      Playground.hero.position.ground_y = clamp(Playground.hero.position.ground_y, bounds.top, bounds.bottom)
    end
  end
  Playground.set_visual_mode(HeroRenderer.mode_index(Playground.hero_definition.visual.test_mode, Playground.hero_definition))
  if Playground.camera then
    Playground.camera:set_bounds(Playground.active_level_definition.world)
    Playground.camera:set_policy(Playground.profile.camera)
    if Playground.profile.camera.behavior == "static" then
      Playground.camera:follow(nil)
    else
      Playground.camera:follow(Playground.hero.position)
    end
  end
  if Playground.hero then
    local motion = Playground.hero.motocrotte_motion
    motion.vx = 0
    motion.vy = 0
    motion.speed = 0
    local initial_heading = (Playground.profile.movement and Playground.profile.movement.initial_heading) or 0
    motion.heading = initial_heading
    motion.desired_heading = initial_heading
    motion.steering_heading = initial_heading
    motion.drift_active = false
    motion.drift_phase = "normal"
    motion.drift_spin_phase = motion.heading or 0
    motion.steering_heading = motion.heading or 0
    motion.drift_spin_direction = 1
    motion.drift_variant_index = nil
    motion.drift_mode = "straight"
    motion.drift_straight_tilt_direction = 0
    motion.drift_state = { phase = "normal", phase_time = 0, spin_phase = motion.drift_spin_phase, spin_direction = 1, mode = "straight", straight_tilt_direction = 1, slip_angle = 0 }
    motion._legacy_was_drifting = false
  end
  if Playground.hero then
    Playground.hero.visual_yaw = (Playground.profile.movement and Playground.profile.movement.initial_heading) or 0
  end
end

function Playground.apply_experiment(rebuild_background)
  local base = Playground.base_profile or GameplayProfile.load(Playground.profile_id or "arena_follow")
  local effective = PlaygroundExperiment.resolve(base, Playground.experiment)
  GameplayProfile.validate(effective)
  Playground.profile = effective
  Playground.hero_definition = GameplayProfile.resolve_hero_definition(selected_hero_definition(), effective)
  Playground.active_level_definition.hero_bounds = GameplayProfile.bounds(level_definition, effective)
  Playground.active_level_definition.world = GameplayProfile.world_bounds(level_definition, effective)

  if Playground.hero then
    Playground.hero.definition = Playground.hero_definition
    local bounds = Playground.active_level_definition.hero_bounds
    if bounds then
      Playground.hero.position.x = clamp(Playground.hero.position.x, bounds.left, bounds.right)
      Playground.hero.position.ground_y = clamp(Playground.hero.position.ground_y, bounds.top, bounds.bottom)
    end
  end
  if Playground.camera then
    Playground.camera:set_bounds(Playground.active_level_definition.world)
    Playground.camera:set_policy(effective.camera)
    if effective.camera.behavior == "static" then
      Playground.camera:follow(nil)
      Playground.camera:set_center(
        Playground.hero.position.x,
        effective.camera.center_y or Playground.hero.position.ground_y
      )
    else
      Playground.camera:set_center(
        Playground.hero.position.x,
        effective.camera.center_y or Playground.hero.position.ground_y
      )
      Playground.camera:follow(Playground.hero.position)
    end
  end
  if rebuild_background then rebuild_parallax() end
end

function Playground.reset_experiment()
  Playground.experiment = PlaygroundExperiment.default(Playground.base_profile)
  Playground.apply_experiment()
end

function Playground.load_slot(slot)
  local profiles = { [1] = "arena_follow", [2] = "side_view", [3] = "rear_view", [4] = "rear_view_yaw_card", [5] = "park_arena_follow" }
  local profile_id = profiles[slot]
  if profile_id then
    local requested_profile = GameplayProfile.load(profile_id)
    -- A profile change is a scene replacement, not an additional request into
    -- the existing Playground scope. Release the old ownership first so its
    -- background and profile-specific resources can be collected, while any
    -- resources still owned by another scope remain cached.
    ContentManager.end_scope("playground")
    ContentManager.load_scope("playground", {
      { kind = "character", asset_id = hero_definition.asset_id, options = { include_image = false, animations = { "motorcycle_direction_set", "motorcycle_direction_full" } } },
      { kind = "character", asset_id = scooter_hero_definition.asset_id, options = { include_image = false, animations = { "omnidirectional_sprites" } } },
      { kind = "prop", asset_id = enemy_definition.asset_id, options = { include_image = false, animations = { "traffic_cycle" } } },
      { kind = "effect", asset_id = mud_hose_definition.asset_id, options = { include_image = false, animations = { "blob_variants" } } },
      { kind = "background", asset_id = requested_profile.environment.background_id }
    })
    -- Rebind entities to the replacement scope. The previous scope's
    -- textures may have been released, so retaining old Character/Effect
    -- instances would leave them pointing at invalid GPU resources.
    Playground.loaded_content = {
      character = ContentManager.get("character", hero_definition.asset_id),
      scooter_character = ContentManager.get("character", scooter_hero_definition.asset_id),
      prop = ContentManager.get("prop", enemy_definition.asset_id),
      effect = ContentManager.get("effect", mud_hose_definition.asset_id),
      background = ContentManager.get("background", requested_profile.environment.background_id)
    }
    Playground.hero = Character.new(Playground.hero_definition, selected_hero_content(Playground.loaded_content))
    Playground.enemies = { Character.new(enemy_definition, Playground.loaded_content.prop) }
    Playground.mud_hose = MudHose.new(mud_hose_definition, Playground.loaded_content.effect)
    Playground.set_profile(profile_id)
    local spawn = GameplayProfile.spawn(level_definition, Playground.profile)
    Playground.hero.position.x = spawn.x
    Playground.hero.position.ground_y = spawn.ground_y
    Playground.hero.position.z = spawn.z
    Playground.experiment = PlaygroundExperiment.default(Playground.base_profile)
    Playground.experiment.profile_slot = slot
    Playground.apply_experiment(true)
    return true
  end
  return false
end

function Playground.get_save_data()
  return {
    level_id = "playground",
    segment_id = Playground.segment_id,
    gameplay_profile_id = Playground.profile_id,
    gameplay_profile_version = Playground.profile and Playground.profile.version or nil
  }
end

function Playground.restore_save_data(data)
  assert(type(data) == "table", "Gameplay profile save data must be a table")
  if data.gameplay_profile_id then
    local profile = GameplayProfile.load(data.gameplay_profile_id)
    if data.gameplay_profile_version then
      assert(profile.version == data.gameplay_profile_version, "Unsupported gameplay profile version: " .. tostring(data.gameplay_profile_id))
    end
    Playground.set_profile(profile.id)
  end
end

function Playground.set_visual_mode(index)
  local modes = visual_modes()
  Playground.visual_mode_index = ((index - 1) % #modes) + 1
  if Playground.hero then
    Playground.hero.motocrotte_visual_mode = modes[Playground.visual_mode_index]
  end
end

function Playground.reset_visual_lab()
  Playground.visual_yaw = 0
  local pivot = (Playground.hero_definition.visual or {}).directional_pivot or {}
  Playground.visual_orbit_radius = pivot.radius or 0
  Playground.hero.motocrotte_motion = {
    vx = 0, vy = 0, speed = 0, heading = 0, desired_heading = 0,
    slip_angle = 0, drift_amount = 0, visual_rotation = 0,
    drift_spin_phase = 0, drift_spin_direction = 1,
    drift_phase = "normal", drift_variant_index = nil,
    drift_mode = "straight", drift_straight_tilt_direction = 0,
    drift_state = { phase = "normal", phase_time = 0, spin_phase = 0, spin_direction = 1, mode = "straight", straight_tilt_direction = 1, slip_angle = 0 },
    grounded = true, jump_pressed = false
  }
  Playground.hero.visual_yaw = 0
  local animation_name = Playground.hero_definition.movement and Playground.hero_definition.movement.animation
  if (Playground.visual_lab_active or Playground.hero_definition.default_animation) and animation_name then
    local animation = Playground.hero.animation.animations[animation_name]
    if animation then
      animation.loop = true
      Playground.hero.animation:play(animation_name)
    end
  else
    Playground.hero.animation:stop()
  end
end

function Playground.profile_id_for_slot(slot)
  return ({ [1] = "arena_follow", [2] = "side_view", [3] = "rear_view", [4] = "rear_view_yaw_card", [5] = "park_arena_follow" })[slot]
end

function Playground.get_load_requests(_context, profile_id)
  local requested_profile = GameplayProfile.load(profile_id or level_definition.gameplay_profile_id or "arena_follow")
  return {
    { kind = "character", asset_id = hero_definition.asset_id, options = { include_image = false, animations = { "motorcycle_direction_set", "motorcycle_direction_full" } } },
    { kind = "character", asset_id = scooter_hero_definition.asset_id, options = { include_image = false, animations = { "omnidirectional_sprites" } } },
    { kind = "prop", asset_id = enemy_definition.asset_id, options = { include_image = false, animations = { "traffic_cycle" } } },
    { kind = "effect", asset_id = mud_hose_definition.asset_id, options = { include_image = false, animations = { "blob_variants" } } },
    { kind = "background", asset_id = requested_profile.environment.background_id }
  }, "playground"
end

function Playground.enter(context, profile_id)
  context = context or require("game.runtime_context")
  AudioManager.begin_scope("playground")
  LevelManager.load("playground", profile_id or level_definition.gameplay_profile_id or "arena_follow")
  AudioManager.load_manifest(asset_manifest)
  local requested_profile = GameplayProfile.load(profile_id or level_definition.gameplay_profile_id or "arena_follow")
  Playground.loaded_content = {
    character = context.content.get("character", hero_definition.asset_id),
    scooter_character = context.content.get("character", scooter_hero_definition.asset_id),
    prop = context.content.get("prop", enemy_definition.asset_id),
    effect = context.content.get("effect", mud_hose_definition.asset_id),
    background = context.content.get("background", requested_profile.environment.background_id)
  }
  Playground.set_profile(profile_id or level_definition.gameplay_profile_id or "arena_follow")
  Playground.experiment = PlaygroundExperiment.default(Playground.base_profile)
  Playground.hero = Character.new(Playground.hero_definition, selected_hero_content(Playground.loaded_content))
  Playground.enemies = {
    Character.new(enemy_definition, Playground.loaded_content.prop)
  }
  Playground.mud_hose = MudHose.new(mud_hose_definition, Playground.loaded_content.effect)
  local spawn = GameplayProfile.spawn(level_definition, Playground.profile)
  Playground.hero.position.x = spawn.x
  Playground.hero.position.ground_y = spawn.ground_y
  Playground.hero.position.z = spawn.z
  Playground.visual_lab_active = Playground.hero_definition.visual and Playground.hero_definition.visual.test_enabled == true
  Playground.set_visual_mode(HeroRenderer.mode_index(Playground.hero_definition.visual.test_mode, Playground.hero_definition))
  Playground.reset_visual_lab()
  local initial_heading = (Playground.profile.movement and Playground.profile.movement.initial_heading) or 0
  Playground.hero.motocrotte_motion.heading = initial_heading
  Playground.hero.motocrotte_motion.desired_heading = initial_heading
  Playground.hero.motocrotte_motion.steering_heading = initial_heading
  Playground.hero.visual_yaw = initial_heading
  Playground.camera = CameraManager.new({
    width = level_definition.camera.width,
    height = level_definition.camera.height,
    bounds = {
      left = level_definition.world.left,
      top = level_definition.world.top,
      right = level_definition.world.right,
      bottom = level_definition.world.bottom
    },
    smoothing = Playground.profile.camera.smoothing,
    zoom = Playground.profile.camera.zoom,
    behavior = Playground.profile.camera.behavior,
    follow_x = Playground.profile.camera.follow_x,
    follow_y = Playground.profile.camera.follow_y,
    look_ahead_x = Playground.profile.camera.look_ahead_x,
    look_ahead_y = Playground.profile.camera.look_ahead_y
  })
  if Playground.profile.camera.behavior ~= "static" then
    Playground.camera:follow(Playground.hero.position)
  end
  -- Start framed on the hero; smoothing applies only after the initial view.
  Playground.camera:set_center(
    Playground.hero.position.x,
    Playground.profile.camera.center_y or Playground.hero.position.ground_y
  )
  -- Use the profile-owned environment on initial entry. The experiment layer
  -- is applied immediately afterward and may still contain its base defaults.
  local selected_background = background_definition_for(
    Playground.profile.environment.background_id or Playground.experiment.background_id
  )
  Playground.apply_experiment(true)
  AudioManager.play_music(level_definition.music_id, { loop = true })
end

function Playground.exit()
  MotocrotteAudio.reset()
  if Playground.mud_hose then Playground.mud_hose:reset() end
  Playground.enemies = {}
  if Playground.parallax then
    Playground.parallax:clear()
    Playground.parallax = nil
  end
  Playground.camera = nil
  Playground.hero = nil
  ContentManager.end_scope("playground")
  AudioManager.end_scope("playground")
  LevelManager.unload()
  Playground.loaded_content = {}
end

function Playground.update(dt)
  local intent = MotocrotteDriver.get_intent(Playground.profile)
  if intent.cycle_hero_pressed then
    switch_hero()
  end
  if intent.toggle_visual_lab_pressed then
    Playground.visual_lab_active = not Playground.visual_lab_active
    if Playground.visual_lab_active then
      Playground.reset_visual_lab()
    else
      Playground.hero.animation:stop()
    end
    MotocrotteAudio.reset()
  end
  if Playground.visual_lab_active then
    if intent.cycle_drift_mode_pressed then
      Playground.set_visual_mode(Playground.visual_mode_index + 1)
    end
    if intent.reset_drift_lab_pressed then
      Playground.reset_visual_lab()
    end
    local visual = hero_definition.visual or {}
    local pivot = visual.directional_pivot or {}
    local radius_step = pivot.radius_step or 5
    local radius_min = pivot.radius_min or 0
    local radius_max = pivot.radius_max or 100
    if intent.visual_radius_decrease then
      Playground.visual_orbit_radius = clamp(Playground.visual_orbit_radius - radius_step, radius_min, radius_max)
    elseif intent.visual_radius_increase then
      Playground.visual_orbit_radius = clamp(Playground.visual_orbit_radius + radius_step, radius_min, radius_max)
    end
    local yaw_direction = 0
    if intent.visual_yaw_left then yaw_direction = yaw_direction - 1 end
    if intent.visual_yaw_right then yaw_direction = yaw_direction + 1 end
    Playground.visual_yaw = Playground.visual_yaw + yaw_direction * (visual.yaw_speed or math.rad(90)) * dt
    Playground.hero.visual_yaw = Playground.visual_yaw
    Playground.hero.animation:update(dt)
  else
    local changed = false
    if intent.toggle_sprite_policy_pressed then
      PlaygroundExperiment.cycle(Playground.experiment, "sprite_policy")
      changed = true
    end
    if intent.toggle_yaw_pressed then
      PlaygroundExperiment.cycle(Playground.experiment, "yaw_mode")
      changed = true
    end
    if intent.cycle_control_schema_pressed then
      PlaygroundExperiment.cycle(Playground.experiment, "control_schema")
      changed = true
    end
    if intent.cycle_movement_mode_pressed then
      PlaygroundExperiment.cycle(Playground.experiment, "movement_mode")
      changed = true
    end
    if intent.cycle_camera_mode_pressed then
      PlaygroundExperiment.cycle(Playground.experiment, "camera_mode")
      changed = true
    end
    if intent.cycle_background_pressed then
      PlaygroundExperiment.cycle(Playground.experiment, "background_id")
      changed = true
    end
    if intent.profile_slot_pressed then
      local profile_id = Playground.profile_id_for_slot(intent.profile_slot_pressed)
      if profile_id then
        states_manager().change("playground", profile_id)
        -- The transition exits this Playground immediately and starts the
        -- loading state. Do not continue this update using the old state's
        -- cleared hero reference.
        return
      end
    end
    if changed then
      Playground.apply_experiment(intent.cycle_background_pressed == true)
    end
    if not Playground.hero or not Playground.hero.position then
      return
    end
    intent = GameplayProfile.prepare_intent(intent, Playground.profile)
    HeroMovement.update(Playground.hero, intent, Playground.hero_definition, Playground.active_level_definition, dt)
    HeroOrientation.update(Playground.hero, Playground.hero_definition, dt)
    MotocrotteAudio.update(intent, Playground.hero.motocrotte_motion)
    Playground.mud_hose:update(Playground.hero, intent.fire_mud_hose, dt, Playground.enemies)
  end
  local world = { player = Playground.hero }
  for _, enemy in ipairs(Playground.enemies) do
    enemy:update(dt, world)
  end
  for index = #Playground.enemies, 1, -1 do
    if Playground.enemies[index]:is_defeat_complete() then
      table.remove(Playground.enemies, index)
    end
  end
  local collision_entities = { Playground.hero }
  for _, enemy in ipairs(Playground.enemies) do
    collision_entities[#collision_entities + 1] = enemy
  end
  Playground.last_collision_events = CollisionDetection.check(collision_entities)
  Playground.hero.collision_active = false
  for _, enemy in ipairs(Playground.enemies) do enemy.collision_active = false end
  local collision_entities_by_id = { [Playground.hero.id] = Playground.hero }
  for _, enemy in ipairs(Playground.enemies) do collision_entities_by_id[enemy.id] = enemy end
  for _, event in ipairs(Playground.last_collision_events) do
    if collision_entities_by_id[event.source_id] then collision_entities_by_id[event.source_id].collision_active = true end
    if collision_entities_by_id[event.target_id] then collision_entities_by_id[event.target_id].collision_active = true end
    local source = collision_entities_by_id[event.source_id]
    local target = collision_entities_by_id[event.target_id]
    if source and source ~= Playground.hero and source.mark_hit then
      source:mark_hit((source.definition.follow or {}).hit_pause or 0.35)
    end
    if target and target ~= Playground.hero and target.mark_hit then
      target:mark_hit((target.definition.follow or {}).hit_pause or 0.35)
    end
  end
  if Playground.profile.camera.behavior == "static" then
    Playground.camera:follow(nil)
  else
    Playground.camera:follow(Playground.hero.position)
  end
  Playground.camera:update(dt)
  Playground.parallax:update(dt)
end

function Playground.get_debug_context()
  return {
    entities = (function()
      local entities = { Playground.hero }
      for _, enemy in ipairs(Playground.enemies) do entities[#entities + 1] = enemy end
      return entities
    end)(),
    hero_motion = Playground.hero and Playground.hero.motocrotte_motion or nil,
    camera = Playground.camera,
    collision_events = Playground.last_collision_events,
    background_id = Playground.experiment.background_id,
    background_path = Playground.parallax and Playground.parallax.layers[1] and Playground.parallax.layers[1].image_path or nil,
    movement_bounds = Playground.active_level_definition and Playground.active_level_definition.hero_bounds or nil,
    content = ContentManager.debug_snapshot(),
    experiment = {
      sprite_policy = Playground.experiment.sprite_policy,
      yaw_mode = Playground.experiment.yaw_mode,
      yaw_enabled = Playground.experiment.yaw_mode ~= "off",
      control_schema = Playground.experiment.control_schema,
      movement_mode = Playground.experiment.movement_mode,
      camera_mode = Playground.experiment.camera_mode,
      background_id = Playground.experiment.background_id,
      profile_slot = Playground.experiment.profile_slot
    },
    visual_lab = {
      active = Playground.visual_lab_active,
      mode = Playground.hero and Playground.hero.motocrotte_visual_mode or nil,
      mode_index = Playground.visual_mode_index,
      modes = visual_modes(),
      yaw = Playground.visual_yaw,
      horizontal_scale = math.cos(Playground.visual_yaw),
      movement_yaw = Playground.hero and Playground.hero.visual_yaw or 0,
      orbit_radius = Playground.visual_orbit_radius
    },
    gameplay_profile = {
      id = Playground.profile_id,
      version = Playground.profile and Playground.profile.version or nil,
      label = Playground.profile and Playground.profile.label or nil,
      controls = Playground.profile and Playground.profile.controls.schema or nil,
      movement = Playground.profile and Playground.profile.movement.constraint or nil,
      camera = Playground.profile and Playground.profile.camera.behavior or nil,
      drift_enabled = Playground.profile and Playground.profile.drift.enabled or false
    },
    enemies = (function()
      local result = {}
      for _, enemy in ipairs(Playground.enemies) do
        result[#result + 1] = {
          id = enemy.id,
          state = enemy.behavior_state,
          position = { x = enemy.position.x, ground_y = enemy.position.ground_y },
          collision_active = enemy.collision_active == true
        }
      end
      return result
    end)(),
    drift_lab = {
      mode = Playground.hero and Playground.hero.motocrotte_visual_mode or nil,
      mode_index = Playground.drift_mode_index,
      modes = hero_definition.drift and hero_definition.drift.modes or {},
      motion = Playground.hero and Playground.hero.motocrotte_motion or nil
    },
    mud_hose = Playground.mud_hose and Playground.mud_hose:debug_snapshot() or nil
  }
end

function Playground.draw()
  love.graphics.clear(0.08, 0.1, 0.14, 1)
  if not Playground.camera or not Playground.parallax or not Playground.hero then
    return
  end
  Playground.camera:attach()
  Playground.parallax:draw()
  Playground.mud_hose:draw_residues()
  local drawables = { Playground.hero }
  for _, enemy in ipairs(Playground.enemies) do drawables[#drawables + 1] = enemy end
  for _, drawable in ipairs(DrawOrder.sort(drawables)) do
    if drawable == Playground.hero then
      HeroRenderer.draw(Playground.hero, Playground.hero_definition, {
        active = Playground.visual_lab_active,
        mode = Playground.hero.motocrotte_visual_mode,
        yaw = Playground.visual_yaw,
        orbit_radius = Playground.visual_orbit_radius
      })
    else
      drawable:draw()
    end
  end
  Playground.mud_hose:draw_projectiles()
  Playground.camera:detach()
  love.graphics.setColor(1, 1, 1, 1)
  local mode = Playground.hero.motocrotte_visual_mode or "unknown"
  if Playground.visual_lab_active then
    love.graphics.print("MotoCrotte Visual Lab", 24, 24)
    love.graphics.print("Q/E: orbit   K: smaller   M: larger   Tab: visual mode   V: exit", 24, 48)
    love.graphics.print(string.format("Mode: %s   Yaw: %.0f°   Radius: %.0f   Horizontal scale: %.2f", mode, math.deg(Playground.visual_yaw), Playground.visual_orbit_radius, math.cos(Playground.visual_yaw)), 24, 72)
  else
    local motion = Playground.hero.motocrotte_motion or {}
    love.graphics.print("MotoCrotte Gameplay Profile", 24, 24)
    local control_hint = Playground.experiment.control_schema == "gas_steering"
      and "Up: gas   Down: brake   Left/Right: steer"
      or Playground.experiment.control_schema == "gas_steering_fd"
        and "F: gas   D: brake   Left/Right: steer"
        or Playground.experiment.control_schema == "throttle_steering"
          and "Left/Right: steer   T: accelerate   X: brake"
          or "Arrows: move"
    local drift_hint = Playground.experiment.control_schema == "gas_steering_fd" and "S: drift" or "Shift: drift"
    local dash_hint = Playground.profile_id == "arena_follow" and "D: dash" or ""
    love.graphics.print(control_hint .. "   " .. drift_hint .. "   " .. dash_hint .. "   A: mud hose   Space: jump   V: visual lab", 24, 48)
    love.graphics.print("R: sprites   Y: yaw   Tab: controls   M: movement   C: camera   B: background   5: straight-orbit drift profile", 24, 72)
    love.graphics.print(string.format("Profile: %s   Controls: %s   Movement: %s   Camera: %s", Playground.profile.label, Playground.experiment.control_schema, Playground.experiment.movement_mode, Playground.experiment.camera_mode), 24, 96)
    love.graphics.print(string.format("Sprites: %s   Yaw: %s   Background: %s   Slot: %d", Playground.experiment.sprite_policy, Playground.experiment.yaw_mode, Playground.experiment.background_id, Playground.experiment.profile_slot), 24, 120)
    local radius = motion.turning_radius or math.huge
    local radius_text = radius <= 0 and "∞" or string.format("%.0f", radius)
    love.graphics.print(string.format("Speed: %.0f   Heading: %.0f°   Yaw: %.0f°   Slip: %.0f°   State: %s   Drift: %s   Mode: %s   Phase: %s   Dash: %s", motion.speed or 0, math.deg(motion.heading or 0), math.deg(Playground.hero.visual_yaw or 0), math.deg(motion.slip_angle or 0), motion.locomotion_state or "unknown", motion.drift_active and (motion.drift_spin_direction == 1 and "CW" or "CCW") or "off", motion.drift_mode or "normal", motion.drift_phase or "normal", motion.dash_phase or "normal"), 24, 144)
    love.graphics.print(string.format("Turn radius: %s   Drift orbit: %.0f (base %.0f x%.2f)   Spins: %d/3   Boost: %.0f   Gas/brake: %s", radius_text, motion.drift_orbit_radius or 0, motion.drift_orbit_radius_base or 0, motion.drift_orbit_radius_scale or 1, motion.drift_spin_rounds or 0, motion.drift_spin_momentum or 0, motion.drift_gas_brake_disabled and "off" or "on"), 24, 168)
    love.graphics.print(string.format("Variant: %s   Braking: %s   Brake frame: %s", tostring(motion.drift_variant_index or "canonical"), motion.braking and "yes" or "no", tostring(motion.directional_direction or "canonical")), 24, 192)
     local position = Playground.hero.position or {}
     local screen_x, screen_y = Playground.camera:world_to_screen(position.x or 0, position.ground_y or 0)
     local bounds = Playground.active_level_definition.hero_bounds or {}
    love.graphics.print(string.format("Hero world: X %.0f   Y %.0f   Screen: X %.0f   Y %.0f", position.x or 0, position.ground_y or 0, screen_x, screen_y), 24, 216)
    love.graphics.print(string.format("Bounds world: X %.0f-%.0f   Y %.0f-%.0f", bounds.left or 0, bounds.right or 0, bounds.top or 0, bounds.bottom or 0), 24, 240)
    love.graphics.print("Collision: " .. ((#Playground.last_collision_events > 0) and "CONTACT" or "clear"), 24, 264)
    local enemy_states = {}
    for _, enemy in ipairs(Playground.enemies) do
      enemy_states[#enemy_states + 1] = string.format("%s: %s", enemy.id, enemy.behavior_state or "unknown")
    end
    love.graphics.print("Enemies: " .. (#enemy_states > 0 and table.concat(enemy_states, "   ") or "none"), 24, 288)
  end
end

return Playground
