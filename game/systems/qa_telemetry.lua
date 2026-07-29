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
    draw_layer = entity.draw_layer or 0
  }
  if entity.motocrotte_motion then
    snapshot.motion = {
      vx = entity.motocrotte_motion.vx,
      vy = entity.motocrotte_motion.vy,
      speed = entity.motocrotte_motion.speed,
      heading = entity.motocrotte_motion.heading,
      desired_heading = entity.motocrotte_motion.desired_heading,
      slip_angle = entity.motocrotte_motion.slip_angle,
      drift_amount = entity.motocrotte_motion.drift_amount,
      drift_active = entity.motocrotte_motion.drift_active,
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
