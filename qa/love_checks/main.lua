local root = love.filesystem.getSource() .. "/../.."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local InputManager, TimerManager, PositionManager, DrawOrder, MaskCreation
local CollisionDetection, CameraManager, ParallaxManager, AudioManager, Drift, Locomotion
local Json, Menu
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
  CameraManager = require("game.systems.camera_manager")
  ParallaxManager = require("game.systems.parallax")
  AudioManager = require("game.systems.audio_manager")
  Drift = require("game.systems.motocrotte_drift")
  Locomotion = require("game.systems.motocrotte_locomotion")
  Json = require("game.systems.json")
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
  assert_equal(CollisionDetection.mask_overlaps(first, second), true, "mask overlap")
  local events = CollisionDetection.check({ first, second })
  assert_equal(#events, 2, "collision event count")
  assert_equal(events[1].source_id, "first", "collision source")
  assert_equal(events[2].sensor_id, "body", "sensor id")
  second.position.x = 20
  assert_equal(CollisionDetection.mask_overlaps(first, second), false, "mask non-overlap")
  second.position.x = 0
  second.definition.collision.enabled = false
  assert_equal(#CollisionDetection.check({ first, second }), 0, "disabled collision")

  second.definition.collision.enabled = true
  first.definition.collision.sensors = {}
  local auto_events = CollisionDetection.check({ first, second })
  assert_equal(auto_events[2].sensor_id, "auto_body", "automatic sensor")

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
