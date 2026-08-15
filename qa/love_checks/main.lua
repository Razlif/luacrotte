local root = love.filesystem.getSource() .. "/../.."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local InputManager, TimerManager, PositionManager, DrawOrder, MaskCreation
local CollisionDetection, CombatSystem, ImpactResponse, CameraManager, ParallaxManager, AudioManager, Drift, Locomotion
local EnemyManager
local MotocrotteDriver
local Json, Menu, Character, FollowEnemyController, ImpactRenderer, EnemyDefinition, ParkProfile, PlaygroundLevel, Telemetry
local DebugConfig

local function assert_equal(actual, expected, message)
  assert(actual == expected, string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
end

local function run()
  InputManager = require("game.systems.input_manager")
  TimerManager = require("game.systems.timer_manager")
  PositionManager = require("game.systems.position_manager")
  DrawOrder = require("game.systems.draw_order")
  MaskCreation = require("game.systems.mask_creation")
  CollisionDetection = require("game.systems.collision_detection")
  CombatSystem = require("game.systems.combat_system")
  EnemyManager = require("game.systems.enemy_manager")
  MotocrotteDriver = require("game.controllers.motocrotte_driver")
  ImpactResponse = require("game.systems.impact_response")
  CameraManager = require("game.systems.camera_manager")
  ParallaxManager = require("game.systems.parallax")
  AudioManager = require("game.systems.audio_manager")
  Drift = require("game.systems.motocrotte_drift")
  Locomotion = require("game.systems.motocrotte_locomotion")
  Json = require("game.systems.json")
  Character = require("game.entities.characters.character")
  FollowEnemyController = require("game.controllers.follow_enemy_controller")
  ImpactRenderer = require("game.systems.impact_renderer")
  EnemyDefinition = require("game_data.characters.motocrotte_bike_enemy")
  ParkProfile = require("game_data.gameplay_profiles.park_arena_follow")
  PlaygroundLevel = require("game_data.levels.playground")
  Telemetry = require("game.systems.qa_telemetry")
  Menu = require("game.ui.ui_elements.default_menu")
  DebugConfig = require("game.debug_config")

  local debug_config = DebugConfig.from_args({ "--debug" })
  assert_equal(debug_config.enabled, true, "debug flag enabled")
  assert_equal(debug_config.masks, true, "debug masks enabled")
  local partial_config = DebugConfig.from_args({ "--debug-sensors" })
  assert_equal(partial_config.enabled, true, "partial debug enabled")
  assert_equal(partial_config.sensors, true, "partial sensor flag")
  assert_equal(partial_config.masks, false, "partial debug isolation")
  InputManager.keypressed("left")
  assert_equal(InputManager.is_down("move_left"), true, "held input")
  assert_equal(InputManager.consume_pressed("move_left"), true, "pressed input")
  InputManager.keyreleased("left")
  assert_equal(InputManager.is_down("move_left"), false, "released input")

  local timer = TimerManager.new()
  timer:after("once", 0.5)
  assert_equal(#timer:update(0.25), 0, "timer waits")
  assert_equal(#timer:update(0.25), 1, "timer fires")
  assert_equal(timer:is_active("once"), false, "one-shot timer clears")
  timer:every("repeat", 0.25)
  assert_equal(#timer:update(0.6), 1, "repeating timer fires")
  timer:cancel("repeat")

  local position = PositionManager.new({ x = 10, ground_y = 20, z = 4 })
  PositionManager.move(position, 5, 2, 3)
  assert_equal(position.x, 15, "position x")
  assert_equal(PositionManager.get_screen_y(position), 15, "screen y")

  local back = { position = { ground_y = 10 }, draw_layer = 20, draw_order_id = "back" }
  local front = { position = { ground_y = 20 }, draw_layer = 20, draw_order_id = "front" }
  assert_equal(DrawOrder.sort({ front, back })[1], back, "draw ordering")

  local image_data = love.image.newImageData(4, 4)
  image_data:setPixel(1, 1, 1, 1, 1, 1)
  local mask = MaskCreation.from_image(image_data)
  assert_equal(MaskCreation.get_pixel(mask, 1, 1), true, "mask opaque pixel")
  assert_equal(MaskCreation.get_pixel(mask, 0, 0), false, "mask transparent pixel")

  local function entity(id, x, enabled, sensors)
    return {
      id = id,
      position = { x = x, ground_y = 20, z = 0 },
      scale = 1,
      anchor_x = 0,
      anchor_y = 0,
      mask = mask,
      definition = { collision = { enabled = enabled, sensors = sensors or {} } }
    }
  end

  local first = entity("first", 0, true, {
    { id = "body", shape = "rectangle", offset_x = 0, offset_y = 0, width = 4, height = 4 }
  })
  local second = entity("second", 0, true)
  first.motocrotte_motion = { vx = 10, vy = 2 }
  second.motocrotte_motion = { vx = 4, vy = -1 }
  assert_equal(CollisionDetection.mask_overlaps(first, second), true, "mask overlap")
  local events = CollisionDetection.check({ first, second })
  assert_equal(#events, 2, "collision event count")
  assert_equal(events[1].source_id, "first", "collision source")
  assert_equal(events[1].collision_type, "mask", "mask collision type")
  assert(events[1].contact.penetration > 0, "mask penetration")
  assert(events[1].contact.normal.x ~= 0 or events[1].contact.normal.y ~= 0, "mask contact normal")
  assert_equal(events[1].contact.relative_velocity.x, 6, "relative velocity x")
  assert_equal(events[1].contact.relative_velocity.y, 3, "relative velocity y")
  assert_equal(events[2].sensor_id, "body", "sensor id")
  assert_equal(events[2].collision_type, "sensor", "sensor collision type")
  second.position.x = 20
  assert_equal(CollisionDetection.mask_overlaps(first, second), false, "mask non-overlap")
  second.position.x = 0
  second.definition.collision.enabled = false
  assert_equal(#CollisionDetection.check({ first, second }), 0, "disabled collision")

  second.definition.collision.enabled = true
  first.definition.collision.sensors = {}
  local auto_events = CollisionDetection.check({ first, second })
  assert_equal(auto_events[2].sensor_id, "auto_body", "automatic sensor")
  first.definition.collision.mode = "shape"
  local shape_events = CollisionDetection.check({ first, second })
  assert_equal(shape_events[2].collision_type, "shape", "shape collision type")

  local combat_hero = {
    id = "combat_hero",
    position = { x = 0, ground_y = 20, z = 0 },
    definition = { collision = { mass = 1.5 } },
    motocrotte_motion = {
      vx = 300, vy = 0, speed = 300,
      drift_active = true, drift_mode = "orbit",
      locomotion_state = "drift"
    }
  }
  local hit_calls = 0
  local combat_enemy = {
    id = "combat_enemy",
    position = { x = 4, ground_y = 20, z = 0 },
    definition = { collision = { mass = 1 } },
    apply_combat_impact = function(self, response)
      hit_calls = hit_calls + 1
      self.last_response = response
    end
  }
  local combat_event = {
    kind = "mask_overlap",
    source_id = "combat_hero",
    target_id = "combat_enemy",
    collision_type = "mask",
    contact = {
      collision_type = "mask",
      normal = { x = 1, y = 0 },
      penetration = 4,
      relative_velocity = { x = 300, y = 0 }
    }
  }
  local impacts = CombatSystem.resolve({ combat_event, combat_event }, {
    hero = combat_hero,
    enemies = { combat_enemy },
    dt = 0
  })
  assert_equal(#impacts, 1, "combat deduplicates same-frame contact")
  assert_equal(CombatSystem.classify_hero(combat_hero), "drift_orbit", "combat drift state")
  assert_equal(hit_calls, 1, "combat dispatches one impact")
  assert_equal(combat_enemy.last_response.state, "drift_orbit", "combat response state")
  assert(combat_enemy.last_response.strength > 900, "orbit impact has configured force")
  assert(combat_hero.position.x < 0 and combat_enemy.position.x > 4, "combat separates bodies")
  local combat_json_ok = pcall(function() Json.encode(impacts) end)
  assert_equal(combat_json_ok, true, "combat telemetry is serializable")
  local cooldown_impacts = CombatSystem.resolve({ combat_event }, {
    hero = combat_hero,
    enemies = { combat_enemy },
    dt = 0.1
  })
  assert_equal(#cooldown_impacts, 0, "combat cooldown prevents repeated impact")
  combat_hero.motocrotte_motion.drift_active = false
  combat_hero.motocrotte_motion.locomotion_state = "glide"
  assert_equal(CombatSystem.classify_hero(combat_hero), "glide", "combat glide state")
  combat_hero.motocrotte_motion.speed = 0
  combat_hero.motocrotte_motion.vx = 0
  combat_hero.motocrotte_motion.locomotion_state = nil
  assert_equal(CombatSystem.classify_hero(combat_hero), "stationary", "combat stationary state")
  assert(type(Character.apply_combat_impact) == "function", "character exposes combat impact response")

  local regular_hero = {
    id = "regular_hero",
    position = { x = 0, ground_y = 20, z = 0 },
    definition = { collision = { mass = 1.5 } },
    motocrotte_motion = { vx = 300, vy = 0, speed = 300, locomotion_state = "regular_drive" }
  }
  local regular_enemy = {
    id = "regular_enemy",
    position = { x = 4, ground_y = 20, z = 0 },
    definition = { collision = { mass = 1 } },
    apply_combat_impact = function(self, response) self.last_response = response end
  }
  local regular_impacts = CombatSystem.resolve({
    {
      source_id = "regular_hero",
      target_id = "regular_enemy",
      collision_type = "shape",
      contact = {
        normal = { x = 1, y = 0 },
        penetration = 4,
        relative_velocity = { x = 300, y = 0 }
      }
    }
  }, { hero = regular_hero, enemies = { regular_enemy }, dt = 0 })
  assert_equal(#regular_impacts, 1, "regular drive impact is dispatched")
  assert_equal(regular_enemy.last_response.state, "regular_drive", "regular drive impact state")
  assert_equal(regular_hero.motocrotte_motion.vx, 0, "regular drive blocks hero at contact")

  local enemy_a = { id = "enemy_a", position = { x = 0, ground_y = 20, z = 0 }, definition = { collision = { mass = 1 } } }
  local enemy_b = { id = "enemy_b", position = { x = 4, ground_y = 20, z = 0 }, definition = { collision = { mass = 1 } } }
  CombatSystem.resolve({
    {
      source_id = "enemy_a",
      target_id = "enemy_b",
      collision_type = "shape",
      contact = { normal = { x = 1, y = 0 }, penetration = 8 }
    }
  }, {
    hero = { id = "far_hero", position = { x = 100, ground_y = 20, z = 0 }, motocrotte_motion = {} },
    enemies = { enemy_a, enemy_b },
    dt = 0
  })
  assert(enemy_a.position.x < 0 and enemy_b.position.x > 4, "enemy bodies separate from each other")

  local planted = {
    id = "planted",
    position = { x = 40, ground_y = 60, z = 0 },
    definition = { movement = {} }
  }
  ImpactResponse.apply(planted, {
    duration = 1,
    yaw_speed = 2,
    state = "drift_orbit",
    source_id = "hero",
    target_id = "enemy",
    impact_speed = 842,
    knockback_speed = 842,
    velocity_x = 0,
    direction = { x = 1, y = 0 },
    separation = 2
  })
  assert_equal(planted.last_impact_source, "hero", "last impact source")
  assert_equal(planted.last_impact_target, "enemy", "last impact target")
  assert_equal(planted.impact_speed, 842, "impact speed telemetry")
  assert_equal(planted.knockback_speed, 842, "knockback speed telemetry")
  assert_equal(planted.separation_distance, 2, "separation telemetry")
  ImpactResponse.update(planted, 0.25)
  assert_equal(planted.position.x, 40, "visual yaw does not move planted x")
  assert_equal(planted.position.ground_y, 60, "visual yaw does not move planted y")
  assert_equal(planted.impact_mode, "yaw_spin", "generic impact mode is exposed")
  assert(planted.impact_yaw > 0, "visual yaw advances independently")
  ImpactResponse.update(planted, 1)
  assert_equal(planted.impact_mode, nil, "generic impact mode clears after recovery")
  local telemetry_snapshot = Telemetry.snapshot("playground", {
    entities = { planted },
    respawn = { manager = { respawn_timer = 2.8, timers = { enemy = 2.8 } } }
  })
  local planted_snapshot = telemetry_snapshot.visible_entities[1]
  assert_equal(planted_snapshot.last_impact_source, "hero", "telemetry last impact source")
  assert_equal(planted_snapshot.impact_speed, 842, "telemetry impact speed")
  assert_equal(planted_snapshot.knockback_speed, 842, "telemetry knockback speed")
  assert_equal(planted_snapshot.impact_yaw_speed, 2, "telemetry yaw speed")
  assert_equal(planted_snapshot.separation_distance, 2, "telemetry separation")
  assert_equal(telemetry_snapshot.respawn_timer, 2.8, "telemetry respawn timer")

  local visual_spin = {
    scale = 2,
    source_facing = 1,
    facing = 1,
    get_render_facing = function(self) return self.facing * self.source_facing end,
    impact_response = {
      remaining = 1,
      yaw = math.pi * 0.5,
      mode = "yaw_spin",
      direction_x = -1
    }
  }
  local transform = ImpactRenderer.get_transform(visual_spin)
  assert(transform.spinning, "impact renderer activates yaw squash")
  assert(transform.scale_x < 0, "impact renderer flips toward impact direction")
  assert(math.abs(transform.scale_x) < 0.2, "impact renderer reaches edge-on squash")
  assert_equal(transform.scale_y, 2, "impact renderer preserves vertical scale")

  assert_equal(EnemyDefinition.combat.health, 3, "enemy combat health")
  assert_equal(EnemyDefinition.combat.mass, 1, "enemy combat mass")
  assert_equal(EnemyDefinition.combat.collision_radius, 32, "enemy combat radius")
  assert_equal(EnemyDefinition.combat.respawn_enabled, true, "enemy respawn enabled")
  assert_equal(EnemyDefinition.combat.respawn_time, 1.0, "enemy respawn time")
  assert_equal(EnemyDefinition.combat.impacts.spinning_drift.knockback, 60, "enemy spin knockback")
  assert_equal(EnemyDefinition.combat.impacts.spinning_drift.impact_velocity_scale, 0, "enemy spin speed inheritance")
  assert_equal(EnemyDefinition.combat.impacts.straight_drift.duration, 0.6, "enemy straight drift duration")
  assert_equal(ParkProfile.combat.separation_distance, 2, "profile combat separation")
  assert_equal(ParkProfile.combat.maximum_knockback, 1200, "profile combat knockback cap")
  assert_equal(ParkProfile.combat.impact_cooldown, 0.35, "profile combat cooldown")
  assert_equal(ParkProfile.combat.recovery_duration, 3.5, "profile combat recovery")
  assert_equal(PlaygroundLevel.max_enemies, 1, "level enemy maximum")
  assert_equal(PlaygroundLevel.enemies[1].id, "yasuke_bike_enemy_01", "level enemy spawn id")
  assert_equal(PlaygroundLevel.enemies[1].spawn.x, 1100, "level enemy spawn x")
  assert_equal(PlaygroundLevel.enemies[1].spawn.ground_y, 1057, "level enemy spawn ground y")
  assert_equal(PlaygroundLevel.enemies[1].respawn_delay, 3.5, "level enemy respawn delay")
  assert_equal(#ParkProfile.enemies, 0, "profile 5 starts without enemies")
  assert_equal(ParkProfile.enemy_spawning.enabled, true, "profile 5 enemy spawning enabled")
  assert_equal(ParkProfile.enemy_spawning.max_count, 32, "profile 5 enemy spawn limit")

  local fake_spawn = {
    id = "test_enemy_01",
    definition = "test_enemy",
    spawn = { x = 1100, ground_y = 1057 },
    respawn = true,
    respawn_delay = 3.5
  }
  local fake_enemy
  local enemy_manager = EnemyManager.new({
    entries = { fake_spawn },
    max_count = 1,
    definitions = { test_enemy = {} },
    factory = function(_, entry)
      fake_enemy = {
        id = entry.id,
        position = { x = 0, ground_y = 0, z = 0 },
        defeated = false,
        updates = 0
      }
      function fake_enemy:update() self.updates = self.updates + 1 end
      function fake_enemy:is_defeat_complete() return self.defeated end
      return fake_enemy
    end
  })
  enemy_manager:spawn_all()
  assert_equal(#enemy_manager:get_active(), 1, "enemy manager initial spawn")
  assert_equal(fake_enemy.position.x, 1100, "enemy manager spawn x")
  assert_equal(fake_enemy.position.ground_y, 1057, "enemy manager spawn ground y")
  enemy_manager:update(0.1, {})
  assert_equal(fake_enemy.updates, 1, "enemy manager updates active enemy")
  fake_enemy.defeated = true
  enemy_manager:update(0.1, {})
  assert_equal(#enemy_manager:get_active(), 0, "enemy manager removes defeated enemy")
  assert_equal(enemy_manager:get_respawn_snapshot().timers.test_enemy_01, 3.5, "enemy manager uses level respawn delay")
  assert_equal(enemy_manager:get_respawn_snapshot().respawn_timer, 3.5, "enemy manager exposes respawn timer")
  assert_equal(enemy_manager:get_events()[1].type, "enemy_respawn_queued", "enemy manager queues respawn")
  enemy_manager:update(3.5, {})
  assert_equal(#enemy_manager:get_active(), 1, "enemy manager respawns enemy")
  assert_equal(enemy_manager:get_events()[1].type, "enemy_respawned", "enemy manager reports respawn")
  assert_equal(enemy_manager:get_respawn_snapshot().defeated_count, 0, "enemy manager clears defeated record")

  local manual_manager = EnemyManager.new({
    entries = {},
    max_count = 2,
    definitions = { test_enemy = {} },
    spawn_template = { id = "generated_enemy", definition = "test_enemy", respawn = true },
    factory = function(_, entry)
      local generated = {
        id = entry.id,
        position = { x = 0, ground_y = 0, z = 0 },
        defeated = false
      }
      function generated:is_defeat_complete() return self.defeated end
      return generated
    end
  })
  local generated = manual_manager:spawn_next({ x = 12, ground_y = 34 })
  assert_equal(generated.id, "generated_enemy_01", "manual enemy id")
  assert_equal(generated.position.x, 12, "manual enemy x")
  assert_equal(generated.position.ground_y, 34, "manual enemy ground y")

  InputManager.keypressed("g")
  local spawn_intent = MotocrotteDriver.get_intent(ParkProfile)
  assert_equal(spawn_intent.spawn_enemy_pressed, true, "spawn enemy input")
  InputManager.keyreleased("g")

  local enemy_controller = FollowEnemyController.new()
  local controller_entity = {
    position = { x = 10, ground_y = 20, z = 0 },
    definition = { movement = {} }
  }
  enemy_controller:begin_impact({
    velocity_x = 80,
    velocity_y = 0,
    yaw_speed = 4,
    duration = 0.2,
    state = "drift_orbit"
  }, controller_entity)
  assert_equal(enemy_controller:get_state(), "hit_spinning", "enemy enters spinning impact")
  assert_equal(enemy_controller:is_impact_locked(), true, "enemy impact locks pursuit")
  enemy_controller:update_impact(0.1)
  assert(enemy_controller:get_spin_phase() > 0, "enemy spin phase advances")
  assert(enemy_controller:get_impact_velocity().x < 80, "enemy impact velocity decays")
  enemy_controller:update_impact(0.2)
  enemy_controller:update_impact(0.01)
  assert_equal(enemy_controller:get_state(), "recovering", "enemy enters recovery")
  enemy_controller:update_impact(0.35)
  assert_equal(enemy_controller:get_state(), "pursuing", "enemy returns to pursuit")

  local drift_definition = {
    drift = {
      enabled = true,
      behavior = "straight_orbit",
      entry_time = 0,
      exit_time = 0.01,
      minimum_speed = 1,
      straight_tilt_direction = 1,
      radius_control = "fixed",
      orbit_radius_default = 30,
      orbit_radius_scale = 2.64,
      orbit_radius_min = 0,
      orbit_radius_max = 120,
      orbit_radius_growth = 60,
      orbit_radius_shrink_rate = 60,
      spin_speed = math.rad(360),
      disable_gas_brake = true,
      max_spin_rounds = 3,
      spin_momentum_per_round = 120,
      spin_momentum_cap = 360,
      slingshot_impulse = 650,
      slingshot_decay = 700,
      slingshot_min_speed = 4
    },
    directional_animation = { variant_policy = "fixed" }
  }
  local drift_motion = { vx = 100, vy = 0, speed = 100, heading = 0, desired_heading = 0 }
  local straight = Drift.update(drift_motion, {
    drift_active = true, steering = 0, horizontal = 0, vertical = 0,
    gas_pressed = true, drift_radius_increase = true
  }, drift_definition, 0.016, { x = 100, y = 100 })
  assert_equal(straight.mode, "straight", "drift without steering stays straight")
  assert_equal(straight.orbit_position, nil, "straight drift has no orbit")
  assert_equal(straight.straight_tilt_direction, 1, "straight drift applies tilt")

  local orbit = Drift.update(drift_motion, {
    drift_active = true, steering = 1, horizontal = 1, vertical = 0,
    gas_pressed = true, drift_radius_increase = true
  }, drift_definition, 0.016, { x = 100, y = 100 })
  assert_equal(orbit.mode, "orbit", "steering enters orbit drift")
  assert(orbit.orbit_position ~= nil, "orbit drift produces an orbit position")
  assert_equal(orbit.orbit_radius_base, 30, "hybrid drift keeps canonical base radius")
  assert(math.abs(orbit.orbit_radius_effective - 79.2) < 0.001, "hybrid drift scales radius for hero presentation")
  local grown_radius = orbit.orbit_radius
  local fixed_radius = Drift.update(drift_motion, {
    drift_active = true, steering = 1, horizontal = 1, vertical = 0,
    gas_pressed = true, drift_radius_increase = true
  }, drift_definition, 1, { x = 100, y = 100 })
  assert_equal(fixed_radius.orbit_radius, grown_radius, "fixed hybrid drift ignores gas radius growth")
  local shrunk = Drift.update(drift_motion, {
    drift_active = true, steering = 1, horizontal = 1, vertical = 0,
    gas_pressed = false, drift_radius_increase = false
  }, drift_definition, 0.016, { x = 100, y = 100 })
  assert_equal(shrunk.orbit_radius, grown_radius, "fixed hybrid drift keeps its orbit radius")

  local straight_again = Drift.update(drift_motion, {
    drift_active = true, steering = 0, horizontal = 0, vertical = 0,
    gas_pressed = false, drift_radius_increase = false
  }, drift_definition, 0.016, { x = 100, y = 100 })
  assert_equal(straight_again.mode, "straight", "releasing steering returns to straight drift")
  assert_equal(straight_again.orbit_position, nil, "straight drift stops orbit movement")
  assert(straight_again.slingshot ~= nil, "releasing steering creates a slingshot")
  assert(straight_again.slingshot.speed > grown_radius * drift_definition.drift.spin_speed, "slingshot includes spin momentum")
  local slingshot_speed = straight_again.slingshot_speed
  local decaying_slingshot = Drift.update(drift_motion, {
    drift_active = true, steering = 0, horizontal = 0, vertical = 0
  }, drift_definition, 0.5, { x = 100, y = 100 })
  assert(decaying_slingshot.slingshot_active, "slingshot remains active during its short kick")
  assert(decaying_slingshot.slingshot_speed < slingshot_speed, "slingshot decays quickly")

  local spin_motion = { vx = 100, vy = 0, speed = 100, heading = 0, desired_heading = 0 }
  local spin_intent = {
    drift_active = true, steering = 1, horizontal = 1, vertical = 0,
    gas_pressed = true, brake = true, drift_radius_increase = true
  }
  Drift.update(spin_motion, spin_intent, drift_definition, 0.016, { x = 100, y = 100 })
  local capped_rounds
  for _ = 1, 3 do
    capped_rounds = Drift.update(spin_motion, spin_intent, drift_definition, 1, { x = 100, y = 100 })
  end
  assert_equal(capped_rounds.spin_rounds, 3, "spin momentum caps at three rounds")
  assert_equal(capped_rounds.spin_momentum, 360, "three rounds add configured momentum")
  local still_capped = Drift.update(spin_motion, spin_intent, drift_definition, 1, { x = 100, y = 100 })
  assert_equal(still_capped.spin_rounds, 3, "additional rounds do not increase spin count")
  assert_equal(still_capped.spin_momentum, 360, "additional rounds do not increase momentum")

  local coast_motion = { vx = 100, vy = 0, speed = 100, heading = 0, desired_heading = 0 }
  local _, _, coast_input = Locomotion.update(coast_motion, {
    horizontal = 1, vertical = 0, brake = true
  }, { acceleration = 100, max_speed = 400, coast_deceleration = 20, brake_deceleration = 200 }, {
    active = true, disable_gas_brake = true, deceleration = 20, turn_rate = 0
  }, 0.1)
  assert_equal(coast_input, 0, "drift suppresses gas and brake input")
  assert(coast_motion.speed < 100, "straight drift naturally coasts down")

  local released = Drift.update(drift_motion, {
    drift_active = false, steering = 0, horizontal = 0, vertical = 0
  }, drift_definition, 0.02, { x = 100, y = 100 })
  assert_equal(released.phase, "normal", "drift exits without a minimum spin")

  local camera = CameraManager.new({ width = 100, height = 50, responsive = false, bounds = { left = 0, top = 0, right = 500, bottom = 300 }, smoothing = 20 })
  local target = { x = 250, ground_y = 150 }
  camera:follow(target)
  camera:update(1)
  assert_equal(camera.x, 200, "camera follow")
  assert_equal(camera.y, 125, "camera vertical follow")
  camera:shake(4, 0.5)
  camera:update(0.25)
  assert(camera.shake_x ~= 0 or camera.shake_y ~= 0, "camera shake active")
  camera:update(0.25)
  assert_equal(camera.shake_x, 0, "camera shake expires")
  camera:set_zoom(2)
  camera:set_center(250, 150)
  local centered_x, centered_y = camera:world_to_screen(250, 150)
  assert_equal(centered_x, 50, "zoomed camera horizontal center")
  assert_equal(centered_y, 25, "zoomed camera vertical center")
  camera:set_zoom(1)
  camera:follow({
    get_camera_focus = function()
      return { x = 250, ground_y = 100 }
    end
  })
  camera:update(1)
  assert_equal(camera.x, 200, "camera follows visual focus x")
  assert_equal(camera.y, 75, "camera follows visual focus y")
  ParallaxManager.new({}):set_camera(camera)

  AudioManager.load_manifest({})
  local missing_audio_ok = pcall(function() AudioManager.play_music("missing") end)
  assert_equal(missing_audio_ok, false, "missing audio rejected")

  local decoded = Json.decode(Json.encode({ message = "hello", count = 2, enabled = true, values = { 1, 2 } }))
  assert_equal(decoded.message, "hello", "json string")
  assert_equal(decoded.values[2], 2, "json array")

  local confirmed = false
  local menu = Menu.new({ { label = "Test", on_confirm = function() confirmed = true end } })
  InputManager.keypressed("return")
  menu:update(InputManager)
  assert_equal(confirmed, true, "menu confirmation")
  InputManager.keyreleased("return")
end

local checks_passed = false

function love.load()
  love.filesystem.setIdentity("love2d_toolkit_test")
  love.filesystem.write("core_system_status.txt", "running")
  local ok, message = pcall(run)
  if not ok then
    love.filesystem.write("core_system_status.txt", "error: " .. tostring(message))
    print(message)
    os.exit(1)
  end
  love.filesystem.write("core_system_status.txt", "passed")
  checks_passed = true
end

function love.update()
  if checks_passed then
    love.event.quit(0)
  end
end
