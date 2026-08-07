-- Timeline command implementations for the cutscene engine.
local DialogueBox = require("game.ui.ui_elements.default_dialogue_box")
local AudioManager = require("game.systems.audio_manager")

local Commands = {}

Commands.names = {
  wait = true,
  move = true,
  ride_trick = true,
  face = true,
  play_animation = true,
  say = true,
  camera_move = true,
  camera_zoom = true,
  camera_follow = true,
  camera_shake = true,
  play_effect = true,
  play_sound = true,
  play_music = true,
  stop_music = true,
  fade = true
}

function Commands.validate(command, index)
  assert(type(command) == "table", "Cutscene command " .. tostring(index) .. " must be a table")
  local name = command.command
  assert(Commands.names[name], "Unknown cutscene command '" .. tostring(name) .. "' at index " .. tostring(index))
  if name == "say" then
    assert(command.actor or command.speaker, "say requires actor or speaker at index " .. tostring(index))
    assert(type(command.text) == "string", "say requires text at index " .. tostring(index))
    assert(not command.style or command.style == "footer" or command.style == "card", "say style must be footer or card at index " .. tostring(index))
    if command.style == "card" then
      assert(command.actor, "card dialogue requires actor at index " .. tostring(index))
    end
  elseif name == "face" or name == "play_animation" then
    assert(command.actor, name .. " requires actor at index " .. tostring(index))
  elseif name == "move" then
    assert(command.actor, "move requires actor at index " .. tostring(index))
    assert(command.x ~= nil or command.ground_y ~= nil, "move requires x or ground_y at index " .. tostring(index))
  elseif name == "ride_trick" then
    assert(command.actor, "ride_trick requires actor at index " .. tostring(index))
    assert(command.duration and command.duration > 0, "ride_trick requires positive duration at index " .. tostring(index))
    assert(command.center_x ~= nil and command.center_ground_y ~= nil, "ride_trick requires center_x and center_ground_y at index " .. tostring(index))
  elseif name == "camera_move" then
    assert(command.x ~= nil and (command.ground_y ~= nil or command.y ~= nil), "camera_move requires center x and ground_y at index " .. tostring(index))
  elseif name == "camera_zoom" then
    assert(command.zoom and command.zoom > 0, "camera_zoom requires positive zoom at index " .. tostring(index))
    local has_actor_focus = command.actor ~= nil
    local has_point_focus = command.focus_x ~= nil and command.focus_ground_y ~= nil
    assert(has_actor_focus or has_point_focus, "camera_zoom requires actor or focus_x/focus_ground_y at index " .. tostring(index))
  elseif name == "camera_follow" then
    assert(command.actor, "camera_follow requires actor at index " .. tostring(index))
  elseif name == "camera_shake" then
    assert(command.amplitude ~= nil and command.duration ~= nil, "camera_shake requires amplitude and duration at index " .. tostring(index))
  elseif name == "play_effect" then
    assert(command.asset_id, "play_effect requires asset_id at index " .. tostring(index))
  elseif name == "play_sound" then
    assert(command.sound_id, "play_sound requires sound_id at index " .. tostring(index))
    assert(command.volume == nil or (command.volume >= 0 and command.volume <= 1), "play_sound volume must be 0..1 at index " .. tostring(index))
    assert(command.pitch == nil or command.pitch > 0, "play_sound pitch must be positive at index " .. tostring(index))
  elseif name == "play_music" then
    assert(command.music_id, "play_music requires music_id at index " .. tostring(index))
    assert(command.volume == nil or (command.volume >= 0 and command.volume <= 1), "play_music volume must be 0..1 at index " .. tostring(index))
  elseif name == "stop_music" then
    assert(command.fade == nil or command.fade >= 0, "stop_music fade must be non-negative at index " .. tostring(index))
  elseif name == "fade" then
    assert(command.alpha ~= nil and command.duration ~= nil, "fade requires alpha and duration at index " .. tostring(index))
  end
end

local function actor_for(player, command)
  local actor = player.actors[command.actor]
  assert(actor, "Unknown cutscene actor: " .. tostring(command.actor))
  return actor
end

local function smoothstep(value)
  return value * value * (3 - 2 * value)
end

local function duration_for(command, fallback)
  local duration = command.duration or fallback
  assert(duration and duration >= 0, "Cutscene command duration must be non-negative")
  return duration
end

local function movement_speed(actor, axis)
  local movement = actor.movement or {}
  if axis == "x" then
    return movement.horizontal_speed or movement.speed or 0
  end
  return movement.vertical_speed or movement.speed or 0
end

local function move_duration(actor, start_x, start_y, target_x, target_y)
  local x_duration = movement_speed(actor, "x") > 0 and math.abs(target_x - start_x) / movement_speed(actor, "x") or 0
  local y_duration = movement_speed(actor, "y") > 0 and math.abs(target_y - start_y) / movement_speed(actor, "y") or 0
  return math.max(x_duration, y_duration)
end

function Commands.begin(player, command)
  local name = command.command
  if name == "wait" then
    return { duration = duration_for(command, 0), elapsed = 0 }
  elseif name == "move" then
    local actor = actor_for(player, command)
    local target_x = command.x or actor.position.x
    if target_x ~= actor.position.x then
      actor:face(target_x > actor.position.x and "right" or "left")
    end
    if command.animation then
      actor:play(command.animation, command.loop)
    end
    local target_y = command.ground_y or actor.position.ground_y
    local uses_game_movement = command.movement == "game"
    local speed_actor = {
      movement = {
        speed = command.speed or command.speed_x or movement_speed(actor, "x"),
        vertical_speed = command.speed or command.speed_y or movement_speed(actor, "y")
      }
    }
    local default_duration = move_duration(speed_actor, actor.position.x, actor.position.ground_y, target_x, target_y)
    return {
      actor = actor,
      start_x = actor.position.x,
      start_y = actor.position.ground_y,
      target_x = target_x,
      target_y = target_y,
      duration = duration_for(command, default_duration > 0 and default_duration or 1),
      elapsed = 0,
      speed_x = command.speed or command.speed_x or movement_speed(actor, "x"),
      speed_y = command.speed or command.speed_y or movement_speed(actor, "y")
    }
  elseif name == "ride_trick" then
    local actor = actor_for(player, command)
    if command.animation then actor:play(command.animation, command.loop ~= false) end
    return {
      actor = actor,
      center_x = command.center_x,
      center_y = command.center_ground_y,
      radius_x = command.radius_x or 0,
      radius_y = command.radius_y or 0,
      turns = command.turns or 1,
      direction = command.direction == "counterclockwise" and -1 or 1,
      start_angle = command.start_angle or 0,
      hop_height = command.hop_height or 0,
      lean = math.rad(command.lean_degrees or 0),
      duration = command.duration,
      elapsed = 0
    }
  elseif name == "face" then
    actor_for(player, command):face(command.direction)
    return { duration = command.duration or 0.2, elapsed = 0 }
  elseif name == "play_animation" then
    local actor = actor_for(player, command)
    local duration = command.duration or actor:get_animation_duration(command.name)
    actor:play(command.name, command.loop)
    return { duration = duration, elapsed = 0 }
  elseif name == "say" then
    local actor = command.actor and actor_for(player, command)
    player.dialogue = DialogueBox.new({
      speaker = command.speaker or (actor and actor.id) or "",
      text = command.text or "",
      actor = actor,
      style = command.style or "footer",
      reveal_speed = command.reveal_speed or 30
    })
    return {
      duration = duration_for(command, math.max(1.5, #(command.text or "") / 18)),
      elapsed = 0
    }
  elseif name == "camera_move" then
    player.camera.target = nil
    local center_x, center_y = player.camera:get_center()
    return {
      start_x = center_x,
      start_y = center_y,
      target_x = command.x or center_x,
      target_y = command.ground_y or command.y or center_y,
      duration = duration_for(command, 1),
      elapsed = 0
    }
  elseif name == "camera_zoom" then
    player.camera.target = nil
    local center_x, center_y = player.camera:get_center()
    return {
      start_zoom = player.camera.zoom,
      target_zoom = command.zoom or 1,
      focus_actor = command.actor and actor_for(player, command) or nil,
      focus_x = command.focus_x,
      focus_ground_y = command.focus_ground_y,
      center_x = center_x,
      center_y = center_y,
      duration = duration_for(command, 1),
      elapsed = 0
    }
  elseif name == "camera_follow" then
    player.camera:follow(actor_for(player, command))
    return { done = true }
  elseif name == "camera_shake" then
    player.camera:shake(command.amplitude or 0, command.duration or 0.1)
    return { done = true }
  elseif name == "play_effect" then
    player:spawn_effect(command)
    return { done = true }
  elseif name == "play_sound" then
    AudioManager.play_sfx(command.sound_id, { volume = command.volume, pitch = command.pitch })
    return { done = true }
  elseif name == "play_music" then
    AudioManager.play_music(command.music_id, { loop = command.loop, volume = command.volume })
    return { done = true }
  elseif name == "stop_music" then
    AudioManager.stop_music(command.fade)
    return { done = true }
  elseif name == "fade" then
    return {
      start_alpha = player.fade.alpha,
      target_alpha = command.alpha == nil and 1 or command.alpha,
      color = command.color or { 0, 0, 0 },
      duration = duration_for(command, 1),
      elapsed = 0
    }
  end
  error("Unknown cutscene command: " .. tostring(name))
end

function Commands.update(player, command, active, dt)
  if active.done then
    return true
  end
  active.elapsed = active.elapsed + dt
  local progress = active.duration == 0 and 1 or math.min(1, active.elapsed / active.duration)
  local eased = smoothstep(progress)

  if command.command == "move" then
    if active.uses_game_movement then
      local step_x = active.speed_x * dt
      local step_y = active.speed_y * dt
      if active.target_x < active.actor.position.x then step_x = -step_x end
      if active.target_y < active.actor.position.ground_y then step_y = -step_y end
      active.actor.position.x = math.abs(active.target_x - active.actor.position.x) <= math.abs(step_x)
        and active.target_x or active.actor.position.x + step_x
      active.actor.position.ground_y = math.abs(active.target_y - active.actor.position.ground_y) <= math.abs(step_y)
        and active.target_y or active.actor.position.ground_y + step_y
      return active.actor.position.x == active.target_x and active.actor.position.ground_y == active.target_y
    end
    active.actor.position.x = active.start_x + (active.target_x - active.start_x) * eased
    active.actor.position.ground_y = active.start_y + (active.target_y - active.start_y) * eased
  elseif command.command == "ride_trick" then
    -- Presentation-only choreography: it is deterministic and does not invoke
    -- gameplay movement, physics, AI, or collision systems.
    local angle = active.start_angle + active.direction * progress * active.turns * math.pi * 2
    active.actor.position.x = active.center_x + math.cos(angle) * active.radius_x
    active.actor.position.ground_y = active.center_y + math.sin(angle) * active.radius_y
    active.actor.position.z = math.abs(math.sin(angle * 2)) * active.hop_height
    local yaw_enabled = active.actor.trick_presentation.yaw_enabled == true
    if yaw_enabled then
      -- Side-view prop bikes have only right-facing art. A full turn is shown
      -- as a faux vertical-axis yaw: side-on at 0/180°, edge-on at 90/270°.
      -- Flip only after passing edge-on; never pretend the asset has a front
      -- or rear directional frame.
      local yaw_scale = math.abs(math.cos(angle))
      active.actor:face(math.cos(angle) >= 0 and "right" or "left")
      active.actor:set_presentation({ scale_x = yaw_scale, rotation = 0 })
    else
      active.actor:set_presentation({ rotation = math.sin(angle * 2) * active.lean })
    end
  elseif command.command == "camera_move" then
    player.camera:set_center(
      active.start_x + (active.target_x - active.start_x) * eased,
      active.start_y + (active.target_y - active.start_y) * eased
    )
  elseif command.command == "camera_zoom" then
    player.camera:set_zoom(active.start_zoom + (active.target_zoom - active.start_zoom) * eased)
    if active.focus_actor then
      local focus = active.focus_actor:get_camera_focus(player.camera.zoom, true)
      player.camera:set_center(focus.x, focus.ground_y)
    elseif active.focus_x then
      player.camera:set_center(active.focus_x, active.focus_ground_y or 0)
    else
      player.camera:set_center(active.center_x, active.center_y)
    end
  elseif command.command == "say" then
    player.dialogue:update(dt)
  elseif command.command == "fade" then
    player.fade.alpha = active.start_alpha + (active.target_alpha - active.start_alpha) * eased
    player.fade.color = active.color
  end

  return progress >= 1
end

return Commands
