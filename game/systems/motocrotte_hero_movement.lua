-- Orchestrates profile-driven locomotion and drift without exposing internal modules.
local Locomotion = require("game.systems.motocrotte_locomotion")
local Drift = require("game.systems.motocrotte_drift")
local LegacyMovement = require("game.systems.motocrotte_legacy_movement")

local Movement = {}

local function required_number(table_value, key, label)
  local value = table_value and table_value[key]
  assert(type(value) == "number", label .. "." .. key .. " must be configured")
  return value
end

function Movement.update(hero, intent, definition, level_definition, dt)
  assert(hero and hero.position, "MotoCrotte hero position is required")
  assert(definition and definition.movement, "MotoCrotte hero movement data is required")
  assert(level_definition and level_definition.hero_bounds, "MotoCrotte hero bounds are required")
  assert(type(dt) == "number" and dt >= 0, "Delta time must be non-negative")

  if definition.movement.solver == "legacy_direct_drift" then
    return LegacyMovement.update(hero, intent, definition, level_definition, dt)
  end

  local config = definition.movement
  required_number(config, "acceleration", "hero movement")
  required_number(config, "max_speed", "hero movement")
  assert(config.coast_deceleration or config.deceleration, "hero movement.coast_deceleration is required")
  local bounds = level_definition.hero_bounds

  hero.motocrotte_motion = hero.motocrotte_motion or {
    vx = 0, vy = 0, speed = 0, heading = 0, desired_heading = 0,
    slip_angle = 0, drift_amount = 0, visual_rotation = 0,
    drift_spin_phase = 0, drift_spin_direction = 1, drift_phase = "normal"
  }
  local motion = hero.motocrotte_motion
  local drift_context = Drift.update(motion, intent, definition, dt)
  local horizontal, vertical, input_length = Locomotion.update(motion, intent, config, drift_context, dt)

  local desired_heading = motion.desired_heading or motion.heading or 0
  motion.slip_angle = 0
  if input_length > 0 then
    desired_heading = math.atan2(vertical, horizontal)
    motion.desired_heading = desired_heading
    local delta = desired_heading - (motion.heading or 0)
    while delta > math.pi do delta = delta - math.pi * 2 end
    while delta < -math.pi do delta = delta + math.pi * 2 end
    motion.slip_angle = delta
  end
  motion.drift_amount = drift_context.active and math.min(1, math.abs(motion.slip_angle) / math.pi) or 0
  motion.braking = motion.braking or false

  if horizontal ~= 0 and hero.facing_enabled ~= false then
    hero.facing = horizontal > 0 and 1 or -1
  end

  local animation_name = config.animation
  if animation_name then
    if input_length > 0 then
      if not hero.animation:is_playing() or hero.animation.current_name ~= animation_name then
        local animation = hero.animation.animations[animation_name]
        assert(animation, "Configured MotoCrotte movement animation is missing: " .. animation_name)
        animation.loop = config.animation_loop == true
        hero.animation:play(animation_name)
      end
    elseif hero.animation:is_playing() and config.animation_idle ~= true then
      hero.animation:stop()
    end
  end
  hero.animation:update(dt)
  Locomotion.apply_position(hero, motion, bounds, dt)
  motion.grounded = true
  motion.jump_pressed = intent.jump_pressed == true
  motion.speed = math.sqrt(motion.vx * motion.vx + motion.vy * motion.vy)
end

return Movement
