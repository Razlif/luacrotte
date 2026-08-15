-- Low-noise, structured telemetry for deterministic QA runs.
local Json = require("game.systems.json")
local AudioManager = require("game.systems.audio_manager")

local Telemetry = {
  schema_version = 1,
  enabled = false,
  run_dir = nil,
  frame = 0,
  sim_time = 0,
  next_event_id = 1,
  final_scene = nil
}

local function run_id()
  if not Telemetry.run_dir then return nil end
  return Telemetry.run_dir:match("([^/\\]+)$")
end

local function write_line(name, value)
  if not Telemetry.enabled then return end
  local handle = io.open(Telemetry.run_dir .. "/" .. name, "a")
  if not handle then return end
  handle:write(Json.encode(value), "\n")
  handle:close()
end

function Telemetry.configure(config)
  Telemetry.enabled = config and config.enabled == true and config.run_dir ~= nil
  Telemetry.run_dir = config and config.run_dir or nil
  Telemetry.frame = 0
  Telemetry.sim_time = 0
  Telemetry.next_event_id = 1
  Telemetry.final_scene = nil
  if Telemetry.enabled then
    write_line("events.jsonl", { schema_version = Telemetry.schema_version, run_id = run_id(), type = "qa_started", frame = 0, sim_time = 0 })
  end
end

function Telemetry.is_enabled()
  return Telemetry.enabled
end

function Telemetry.begin_frame(dt)
  if not Telemetry.enabled then return end
  Telemetry.frame = Telemetry.frame + 1
  Telemetry.sim_time = Telemetry.sim_time + (dt or 0)
end

function Telemetry.emit(event_type, data)
  if not Telemetry.enabled then return end
  local event = data or {}
  event.schema_version = Telemetry.schema_version
  event.run_id = run_id()
  event.type = event_type
  event.event_id = Telemetry.next_event_id
  event.frame = Telemetry.frame
  event.sim_time = Telemetry.sim_time
  Telemetry.next_event_id = Telemetry.next_event_id + 1
  write_line("events.jsonl", event)
  if event_type == "scene_finished" then
    Telemetry.final_scene = event
  end
end

local function entity_snapshot(entity, camera)
  local position = entity.position or { x = 0, ground_y = 0, z = 0 }
  local screen_x, screen_y = position.x, position.ground_y - (position.z or 0)
  if camera and camera.world_to_screen then
    screen_x, screen_y = camera:world_to_screen(screen_x, screen_y)
  end
  local animation = entity.animation
  local snapshot = {
    id = entity.id,
    type = entity.qa_type or "entity",
    visible = entity.active ~= false,
    world = { x = position.x, ground_y = position.ground_y, z = position.z or 0 },
    screen = { x = screen_x, y = screen_y },
    animation = animation and animation.current_name or nil,
    frame = animation and animation.current_frame or 1,
    facing = entity.facing,
    visual_yaw = entity.visual_yaw,
    draw_layer = entity.draw_layer or 0,
    combat_state = entity.combat_state,
    combat_source = entity.combat_source,
    impact_remaining = entity.impact_remaining or 0,
    impact_mode = entity.impact_mode,
    impact_direction = {
      x = entity.impact_direction_x or entity.last_impact_direction_x,
      y = entity.impact_direction_y or entity.last_impact_direction_y
    },
    last_impact_source = entity.last_impact_source,
    last_impact_target = entity.last_impact_target,
    last_impact_state = entity.last_impact_state,
    impact_speed = entity.impact_speed or 0,
    knockback_speed = entity.knockback_speed or 0,
    impact_yaw_speed = entity.impact_yaw_speed ~= 0
      and entity.impact_yaw_speed or (entity.last_impact_yaw_speed or 0),
    separation_distance = entity.separation_distance or 0,
    respawn_timer = entity.respawn_timer,
    impact_yaw = entity.impact_yaw or 0,
    impact_velocity = {
      x = entity.impact_velocity_x or 0,
      y = entity.impact_velocity_y or 0
    }
  }
  if entity.motocrotte_motion then
    snapshot.motion = {
      vx = entity.motocrotte_motion.vx,
      vy = entity.motocrotte_motion.vy,
      speed = entity.motocrotte_motion.speed,
      heading = entity.motocrotte_motion.heading,
      desired_heading = entity.motocrotte_motion.desired_heading,
      steering_heading = entity.motocrotte_motion.steering_heading,
      slip_angle = entity.motocrotte_motion.slip_angle,
      drift_amount = entity.motocrotte_motion.drift_amount,
      drift_active = entity.motocrotte_motion.drift_active,
      drift_spin_phase = entity.motocrotte_motion.drift_spin_phase,
      drift_yaw_phase = entity.motocrotte_motion.drift_yaw_phase,
      visual_yaw_phase = entity.motocrotte_motion.visual_yaw_phase,
      drift_spin_direction = entity.motocrotte_motion.drift_spin_direction,
      drift_phase = entity.motocrotte_motion.drift_phase,
      drift_mode = entity.motocrotte_motion.drift_mode,
      drift_straight_tilt_direction = entity.motocrotte_motion.drift_straight_tilt_direction,
      drift_variant_index = entity.motocrotte_motion.drift_variant_index,
      drift_spin_distance = entity.motocrotte_motion.drift_state and entity.motocrotte_motion.drift_state.spin_distance or nil,
      drift_spin_rounds = entity.motocrotte_motion.drift_spin_rounds,
      drift_spin_momentum = entity.motocrotte_motion.drift_spin_momentum,
      drift_orbit_radius = entity.motocrotte_motion.drift_orbit_radius,
      drift_orbit_radius_base = entity.motocrotte_motion.drift_orbit_radius_base,
      drift_orbit_radius_scale = entity.motocrotte_motion.drift_orbit_radius_scale,
      drift_gas_brake_disabled = entity.motocrotte_motion.drift_gas_brake_disabled,
      drift_control_active = entity.motocrotte_motion.drift_control_active,
      locomotion_state = entity.motocrotte_motion.locomotion_state,
      drift_slingshot_active = entity.motocrotte_motion.drift_slingshot_active,
      drift_slingshot_speed = entity.motocrotte_motion.drift_slingshot_speed,
      drift_slingshot = entity.motocrotte_motion.drift_slingshot,
      drift_last_slingshot = entity.motocrotte_motion.drift_last_slingshot,
      turning_radius = entity.motocrotte_motion.turning_radius,
      braking = entity.motocrotte_motion.braking,
      braking_tilt_direction = entity.motocrotte_motion.braking_tilt_direction,
      braking_tilt_angle = entity.motocrotte_motion.braking_tilt_angle,
      dash_active = entity.motocrotte_motion.dash_active,
      dash_phase = entity.motocrotte_motion.dash_phase,
      dash_visual_angle = entity.motocrotte_motion.dash_visual_angle,
      dash_axial_spin_active = entity.motocrotte_motion.dash_axial_spin_active,
      dash_axial_spin_phase = entity.motocrotte_motion.dash_axial_spin_phase,
      wheelie_spin_active = entity.motocrotte_motion.wheelie_spin_active,
      wheelie_contact_x = entity.motocrotte_motion.wheelie_contact_x,
      wheelie_contact_y = entity.motocrotte_motion.wheelie_contact_y,
      drift_state = entity.motocrotte_motion.drift_state,
      visual_rotation = entity.motocrotte_motion.visual_rotation,
      directional_index = entity.motocrotte_motion.directional_index,
      grounded = entity.motocrotte_motion.grounded,
      jump_pressed = entity.motocrotte_motion.jump_pressed
    }
  end
  return snapshot
end

function Telemetry.snapshot(state_name, context, extra)
  local snapshot = {
    schema_version = Telemetry.schema_version,
    run_id = run_id(),
    frame = Telemetry.frame,
    sim_time = Telemetry.sim_time,
    state = state_name,
    visible_entities = {},
    camera = nil,
    collisions = context and context.collision_events or {},
    audio = AudioManager.debug_snapshot(),
    errors = {}
  }
  if context then
    snapshot.camera = context.camera and {
      x = context.camera.x,
      y = context.camera.y,
      zoom = context.camera.zoom,
      width = context.camera.width,
      height = context.camera.height
    } or nil
    for _, entity in ipairs(context.entities or {}) do
      if entity.active ~= false then
        snapshot.visible_entities[#snapshot.visible_entities + 1] = entity_snapshot(entity, context.camera)
      end
    end
    for key, value in pairs(context) do
      if key ~= "entities" and key ~= "camera" and key ~= "collision_events" then
        snapshot[key] = value
      end
    end
    snapshot.respawn_timer = context.respawn
      and context.respawn.manager
      and context.respawn.manager.respawn_timer or nil
  end
  for key, value in pairs(extra or {}) do snapshot[key] = value end
  return snapshot
end

function Telemetry.write_snapshot(path, state_name, context, extra)
  local snapshot = Telemetry.snapshot(state_name, context, extra)
  if Telemetry.enabled then
    local handle = io.open(path, "w")
    if handle then
      handle:write(Json.encode(snapshot), "\n")
      handle:close()
    end
  end
  return snapshot
end

function Telemetry.consume_final_scene()
  local scene = Telemetry.final_scene
  Telemetry.final_scene = nil
  return scene
end

return Telemetry
