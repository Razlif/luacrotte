-- File-based QA command bridge. Active only when --qa is supplied.
local Json = require("game.systems.json")
local InputManager = require("game.systems.input_manager")
local Telemetry = require("game.systems.qa_telemetry")

local Bridge = {
  enabled = false,
  run_dir = nil,
  command_offset = 0,
  queued = {},
  active = nil,
  pending_capture = nil,
  pending_final = false,
  paused = false,
  seen_action_ids = {},
  recording = false,
  recording_name = nil,
  recording_fps = 30,
  recording_interval = 1 / 30,
  recording_elapsed = 0,
  recording_frame = 0,
  recording_due = false,
  recording_dir = nil
}

local function append_result(value)
  local handle = io.open(Bridge.run_dir .. "/results.jsonl", "a")
  if not handle then return end
  handle:write(Json.encode(value), "\n")
  handle:close()
end

local function safe_name(value)
  return tostring(value or "snapshot"):gsub("[^%w%._%-]", "_")
end

local function reject_command(command, message)
  append_result({
    schema_version = 1,
    run_id = Bridge.run_dir:match("([^/\\]+)$"),
    action_id = command and command.id,
    ok = false,
    error = message
  })
end

local function validate_command(command)
  if type(command) ~= "table" then return false, "command must be an object" end
  if type(command.id) ~= "string" or command.id == "" then return false, "command requires a non-empty id" end
  if Bridge.seen_action_ids[command.id] then return false, "duplicate command id: " .. command.id end
  local supported = {
    press = true, release = true, hold = true, mouse_click = true,
    wait = true, wait_until = true, snapshot = true, assert = true,
    pause = true, run_cutscene = true
    , record_start = true, record_stop = true
  }
  if not supported[command.command] then return false, "unknown command: " .. tostring(command.command) end
  if (command.command == "press" or command.command == "release" or command.command == "hold") and type(command.key) ~= "string" then
    return false, command.command .. " requires key"
  end
  if command.command == "hold" and (type(command.duration) ~= "number" or command.duration < 0) then
    return false, "hold duration must be non-negative"
  end
  if command.command == "wait" and (type(command.seconds) ~= "number" or command.seconds < 0) then
    return false, "wait seconds must be non-negative"
  end
  if command.command == "wait_until" then
    if type(command.condition) ~= "table" then return false, "wait_until requires condition" end
    if command.timeout ~= nil and (type(command.timeout) ~= "number" or command.timeout < 0) then
      return false, "wait_until timeout must be non-negative"
    end
  end
  if command.command == "assert" and type(command.condition) ~= "table" then return false, "assert requires condition" end
  if command.command == "mouse_click" and (type(command.x) ~= "number" or type(command.y) ~= "number" or type(command.button) ~= "number") then
    return false, "mouse_click coordinates and button must be numeric"
  end
  if command.command == "run_cutscene" and type(command.scene) ~= "string" then
    return false, "run_cutscene requires scene"
  end
  if command.command == "record_start" and command.fps ~= nil and (type(command.fps) ~= "number" or command.fps <= 0) then
    return false, "record_start fps must be positive"
  end
  Bridge.seen_action_ids[command.id] = true
  return true
end

local function append_recording_metadata(value)
  local handle = io.open(Bridge.recording_dir .. "/video_manifest.jsonl", "a")
  if not handle then return end
  handle:write(Json.encode(value), "\n")
  handle:close()
end

local function start_recording(command)
  Bridge.recording = true
  Bridge.recording_name = safe_name(command.name or command.id or "qa_recording")
  Bridge.recording_fps = command.fps or 30
  Bridge.recording_interval = 1 / Bridge.recording_fps
  Bridge.recording_elapsed = 0
  Bridge.recording_frame = 0
  Bridge.recording_due = true
  Bridge.recording_dir = Bridge.run_dir .. "/video"
  append_recording_metadata({
    event = "recording_started",
    name = Bridge.recording_name,
    fps = Bridge.recording_fps,
    run_id = Bridge.run_dir:match("([^/\\]+)$")
  })
end

local function stop_recording()
  if not Bridge.recording then return end
  append_recording_metadata({
    event = "recording_stopped",
    name = Bridge.recording_name,
    frame_count = Bridge.recording_frame,
    fps = Bridge.recording_fps
  })
  Bridge.recording = false
  Bridge.recording_due = false
end

local function write_png(image_data, path)
  if not image_data then return false end
  local ok, file_data = pcall(function()
    return image_data:encode("png")
  end)
  if not ok or not file_data then return false end
  local handle = io.open(path, "wb")
  if not handle then return false end
  handle:write(file_data:getString())
  handle:close()
  return true
end

local function read_commands()
  local handle = io.open(Bridge.run_dir .. "/commands.jsonl", "r")
  if not handle then return end
  handle:seek("set", Bridge.command_offset)
  for line in handle:lines() do
    Bridge.command_offset = handle:seek()
    if line ~= "" then
      local ok, command = pcall(Json.decode, line)
      if ok and command then
        local valid, message = validate_command(command)
        if valid then
          Bridge.queued[#Bridge.queued + 1] = command
        else
          reject_command(command, message)
        end
      else
        reject_command(nil, "Invalid command JSON")
      end
    end
  end
  handle:close()
end

local function condition_matches(condition, states_manager)
  local context = states_manager.get_debug_context() or {}
  if condition.state_is then return states_manager.current_name == condition.state_is end
  if condition.scene_finished then return states_manager.current_name == "playground" end
  if condition.entity == "hero" and context.hero_motion then
    local motion = context.hero_motion
    if condition.drift_active ~= nil and motion.drift_active ~= condition.drift_active then return false end
    if condition.drift_phase and motion.drift_phase ~= condition.drift_phase then return false end
    if condition.drift_spin_direction and motion.drift_spin_direction ~= condition.drift_spin_direction then return false end
    if condition.min_speed and (motion.speed or 0) < condition.min_speed then return false end
    if condition.max_speed and (motion.speed or 0) > condition.max_speed then return false end
    if condition.min_turning_radius and (motion.turning_radius or 0) < condition.min_turning_radius then return false end
    if condition.max_turning_radius and (motion.turning_radius or 0) > condition.max_turning_radius then return false end
    return true
  end
  for _, entity in ipairs(context.entities or {}) do
    local entity_id = entity.id or (entity.definition and entity.definition.asset_id)
    if condition.entity and (condition.entity == "hero" or entity_id == condition.entity) then
      if condition.entity_visible ~= nil and (entity.active ~= false) ~= condition.entity_visible then return false end
      if condition.animation and (not entity.animation or entity.animation.current_name ~= condition.animation) then return false end
      if condition.x ~= nil and math.abs((entity.position.x or 0) - condition.x) > (condition.tolerance or 1) then return false end
      if condition.ground_y ~= nil and math.abs((entity.position.ground_y or 0) - condition.ground_y) > (condition.tolerance or 1) then return false end
      local motion = entity.motocrotte_motion or {}
      if condition.drift_active ~= nil and motion.drift_active ~= condition.drift_active then return false end
      if condition.drift_phase and motion.drift_phase ~= condition.drift_phase then return false end
      if condition.drift_spin_direction and motion.drift_spin_direction ~= condition.drift_spin_direction then return false end
      if condition.min_speed and (motion.speed or 0) < condition.min_speed then return false end
      if condition.max_speed and (motion.speed or 0) > condition.max_speed then return false end
      if condition.min_turning_radius and (motion.turning_radius or 0) < condition.min_turning_radius then return false end
      if condition.max_turning_radius and (motion.turning_radius or 0) > condition.max_turning_radius then return false end
      return true
    end
  end
  return false
end

local function request_capture(action, name, ok, error_message)
  Bridge.pending_capture = {
    action_id = action and action.id,
    name = name or (action and action.id) or "snapshot",
    ok = ok ~= false,
    error_message = error_message
  }
end

local function start_command(command, states_manager)
  local name = command.command
  Telemetry.emit("command_started", { action_id = command.id, command = name })
  if name == "press" then
    InputManager.keypressed(command.key)
    request_capture(command)
  elseif name == "release" then
    InputManager.keyreleased(command.key)
    request_capture(command)
  elseif name == "hold" then
    InputManager.keypressed(command.key)
    Bridge.active = { command = command, remaining = command.duration, release = true }
  elseif name == "mouse_click" then
    InputManager.mousepressed(command.x, command.y, command.button)
    InputManager.mousereleased(command.x, command.y, command.button)
    request_capture(command)
  elseif name == "wait" then
    Bridge.active = { command = command, remaining = command.seconds }
  elseif name == "wait_until" then
    Bridge.active = { command = command, remaining = command.timeout or 0, condition = command.condition }
  elseif name == "snapshot" then
    request_capture(command, command.name)
  elseif name == "assert" then
    local passed = condition_matches(command.condition or {}, states_manager)
    request_capture(command, command.name, passed, passed and nil or "assertion failed")
  elseif name == "pause" then
    Bridge.paused = command.value ~= false
    request_capture(command)
  elseif name == "run_cutscene" then
    states_manager.change("cutscene", command.scene)
    Bridge.active = { command = command, wait_for_scene = true }
  elseif name == "record_start" then
    start_recording(command)
    request_capture(command, command.name or command.id)
  elseif name == "record_stop" then
    stop_recording()
    request_capture(command, command.name or command.id)
  else
    request_capture(command, nil, false, "unsupported command: " .. tostring(name))
  end
end

function Bridge.configure(config)
  Bridge.enabled = config and config.enabled == true and config.run_dir ~= nil
  Bridge.run_dir = config and config.run_dir or nil
  Bridge.command_offset = 0
  Bridge.queued = {}
  Bridge.active = nil
  Bridge.pending_capture = nil
  Bridge.pending_final = false
  Bridge.paused = false
  Bridge.seen_action_ids = {}
  Bridge.recording = false
  Bridge.recording_name = nil
  Bridge.recording_fps = 30
  Bridge.recording_interval = 1 / 30
  Bridge.recording_elapsed = 0
  Bridge.recording_frame = 0
  Bridge.recording_due = false
  Bridge.recording_dir = nil
  if Bridge.enabled then
    local handle = io.open(Bridge.run_dir .. "/ready.json", "w")
    if handle then handle:write(Json.encode({ ready = true }), "\n"); handle:close() end
  end
end

function Bridge.is_enabled() return Bridge.enabled end
function Bridge.is_paused() return Bridge.paused end

function Bridge.before_update()
  if not Bridge.enabled then return end
  read_commands()
  if not Bridge.active and #Bridge.queued > 0 then
    start_command(table.remove(Bridge.queued, 1), require("game.states_manager"))
  end
end

function Bridge.after_update(dt, states_manager)
  if Bridge.recording then
    Bridge.recording_elapsed = Bridge.recording_elapsed + (dt or 0)
    if Bridge.recording_elapsed >= Bridge.recording_interval then
      Bridge.recording_elapsed = Bridge.recording_elapsed - Bridge.recording_interval
      Bridge.recording_due = true
    end
  end
  if not Bridge.enabled or not Bridge.active then return end
  local active = Bridge.active
  if active.wait_for_scene then
    if states_manager.current_name == "playground" then
      request_capture(active.command)
    end
    return
  end
  active.remaining = active.remaining - (dt or 0)
  if active.command.command == "wait_until" and condition_matches(active.condition, states_manager) then
    request_capture(active.command)
  elseif active.remaining <= 0 then
    if active.release then InputManager.keyreleased(active.command.key) end
    local timed_out = active.command.command == "wait_until"
    request_capture(active.command, nil, not timed_out, timed_out and "condition timed out" or nil)
  end
end

function Bridge.draw(states_manager)
  if not Bridge.enabled then return end
  local final_scene = Telemetry.consume_final_scene()
  if final_scene then
    if Bridge.pending_capture or Bridge.active then
      -- Let the active command finish first; its frame is also the final scene frame.
      Bridge.pending_final = true
    else
      Bridge.pending_capture = { final = true, name = "final", ok = true }
    end
  end
  local capture = Bridge.pending_capture
  local recording_capture = not capture and Bridge.recording and Bridge.recording_due
  if not capture and not recording_capture then return end
  local state_name = states_manager.current_name
  local context = states_manager.get_debug_context()
  local capture_name = safe_name(capture and capture.name or Bridge.recording_name)
  local screenshot_path = Bridge.run_dir .. "/screenshots/" .. capture_name .. "_frame_" .. Telemetry.frame .. ".png"
  local snapshot_path = Bridge.run_dir .. "/snapshots/" .. capture_name .. "_frame_" .. Telemetry.frame .. ".json"
  local function finish(image_data)
    if recording_capture then
      Bridge.recording_due = false
      Bridge.recording_frame = Bridge.recording_frame + 1
      local frame_name = string.format("frame_%06d.png", Bridge.recording_frame)
      local frame_path = Bridge.recording_dir .. "/frames/" .. frame_name
      local frame_saved = write_png(image_data, frame_path)
      local snapshot = Telemetry.snapshot(state_name, context, {})
      append_recording_metadata({
        event = "frame",
        frame = Bridge.recording_frame,
        file = "frames/" .. frame_name,
        saved = frame_saved,
        sim_time = Telemetry.sim_time,
        state = state_name,
        snapshot = snapshot
      })
      return
    end
    local screenshot_saved = write_png(image_data, screenshot_path)
    local snapshot = Telemetry.write_snapshot(snapshot_path, state_name, context, {})
    local final = capture.final == true or Bridge.pending_final
    local final_screenshot_path = Bridge.run_dir .. "/screenshots/final_frame_" .. Telemetry.frame .. ".png"
    local final_snapshot_path = Bridge.run_dir .. "/snapshots/final_frame_" .. Telemetry.frame .. ".json"
    if final and image_data and not capture.final then
      write_png(image_data, final_screenshot_path)
      Telemetry.write_snapshot(final_snapshot_path, state_name, context, {})
    end
    local result = {
      schema_version = 1,
      run_id = Bridge.run_dir:match("([^/\\]+)$"),
      action_id = capture.action_id,
      ok = capture.ok,
      frame = Telemetry.frame,
      sim_time = Telemetry.sim_time,
      state = state_name,
      screenshot = screenshot_path,
      snapshot = snapshot_path,
      error = capture.error_message,
      screenshot_saved = screenshot_saved,
      final = final
    }
    append_result(result)
    if final then
      local report_handle = io.open(Bridge.run_dir .. "/final_report.json", "w")
      if report_handle then
        report_handle:write(Json.encode({
          status = capture.ok and "completed" or "failed",
          state = state_name,
          frame = Telemetry.frame,
          sim_time = Telemetry.sim_time,
          screenshot = capture.final and screenshot_path or final_screenshot_path,
          snapshot = capture.final and snapshot_path or final_snapshot_path,
          error = capture.error_message
        }), "\n")
        report_handle:close()
      end
    end
    if capture.action_id then Telemetry.emit("command_finished", { action_id = capture.action_id, ok = capture.ok }) end
    Bridge.pending_capture = nil
    Bridge.pending_final = false
    Bridge.active = nil
  end
  if love.graphics.captureScreenshot then
    love.graphics.captureScreenshot(finish)
  else
    finish(nil)
  end
end

return Bridge
