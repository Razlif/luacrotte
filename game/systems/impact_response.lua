-- Owns temporary physical responses after a detected impact.
--
-- CombatSystem decides whether a contact should cause a response and builds
-- the response data. This module applies that data without coupling visual yaw
-- to world movement: translation uses impact velocity, while yaw is advanced
-- independently and never changes the entity's planted world position.
local MovementManager = require("game.systems.movement_manager")

local ImpactResponse = {}

local function magnitude(x, y)
  return math.sqrt(x * x + y * y)
end

local function normalize(x, y)
  local length = magnitude(x, y)
  if length <= 0.000001 then
    return 0, 0
  end
  return x / length, y / length
end

local function mass_of(entity, fallback)
  local combat = entity.definition and entity.definition.combat or {}
  if combat.mass then
    return combat.mass
  end
  local collision = entity.definition and entity.definition.collision or {}
  return collision.mass or fallback
end

-- Separate two overlapping bodies along the supplied contact normal. The
-- normal points from first toward second. No velocity or gameplay state is
-- changed here; the resolver can calculate impact from the original contact.
function ImpactResponse.separate(first, second, contact, options)
  if not first or not second or not first.position or not second.position then
    return 0
  end
  contact = contact or {}
  options = options or {}
  local normal = contact.normal or { x = 0, y = 0 }
  local normal_x, normal_y = normalize(normal.x or 0, normal.y or 0)
  if normal_x == 0 and normal_y == 0 then
    return 0
  end
  local correction = math.max(0, contact.penetration or 0) + (options.padding or 0)
  if correction <= 0 then
    return 0
  end
  local first_mass = math.max(0.001, mass_of(first, 1.5))
  local second_mass = math.max(0.001, mass_of(second, 1))
  local first_inverse = 1 / first_mass
  local second_inverse = 1 / second_mass
  local inverse_total = first_inverse + second_inverse
  local first_share = first_inverse / inverse_total
  local second_share = second_inverse / inverse_total

  -- A physics body is already separated by the active Box2D world. Never
  -- write its position here; only the non-physics compatibility participant
  -- receives a direct positional correction.
  if not first.physics_body then
    first.position.x = first.position.x - normal_x * correction * first_share
    first.position.ground_y = first.position.ground_y - normal_y * correction * first_share
  end
  if not second.physics_body then
    second.position.x = second.position.x + normal_x * correction * second_share
    second.position.ground_y = second.position.ground_y + normal_y * correction * second_share
  end
  return correction
end

local function sync_legacy_fields(entity, state)
  entity.impact_velocity_x = state.velocity_x
  entity.impact_velocity_y = state.velocity_y
  entity.impact_yaw = state.yaw
  entity.impact_yaw_speed = state.yaw_speed
  entity.impact_remaining = state.remaining
  entity.impact_duration = state.duration
  entity.impact_mode = state.mode
  entity.impact_direction_x = state.direction_x
  entity.impact_direction_y = state.direction_y
end

local function apply_motion_channel(entity, state, dt)
  -- PhysicsCollisionWorld consumes the intent velocity before its fixed-step
  -- update. A physics-enabled entity must never be translated directly by
  -- the impact layer.
  if entity.physics_body then
    MovementManager.set_velocity(entity, state.velocity_x, state.velocity_y)
    return
  end
  MovementManager.move_by(entity, state.velocity_x * dt, state.velocity_y * dt,
    entity.definition and entity.definition.movement or {}, dt)
end

-- Begin a temporary response on an entity. Translation and yaw are deliberately
-- stored as separate channels so a spinning visual cannot move the entity.
function ImpactResponse.apply(entity, response)
  local duration = math.max(0.001, response.duration or 0.25)
  local state = {
    velocity_x = response.velocity_x or 0,
    velocity_y = response.velocity_y or 0,
    yaw = response.yaw or entity.impact_yaw or 0,
    yaw_speed = response.yaw_speed or 0,
    duration = duration,
    remaining = duration,
    decay = response.decay or 1,
    source_id = response.source_id,
    combat_state = response.state or "hit",
    mode = response.mode or (math.abs(response.yaw_speed or 0) > 0 and "yaw_spin" or "knockback"),
    direction_x = response.direction and response.direction.x or response.direction_x or 0,
    direction_y = response.direction and response.direction.y or response.direction_y or 0
  }
  entity.impact_response = state
  entity.combat_state = state.combat_state
  entity.combat_source = state.source_id
  -- Preserve the last contact summary for QA after the temporary response has
  -- expired. The active response remains the source of live values.
  entity.last_impact_source = response.source_id
  entity.last_impact_target = response.target_id
  entity.last_impact_state = response.state or "hit"
  entity.last_impact_direction_x = state.direction_x
  entity.last_impact_direction_y = state.direction_y
  entity.last_impact_yaw_speed = state.yaw_speed
  entity.impact_speed = response.impact_speed or magnitude(state.velocity_x, state.velocity_y)
  entity.knockback_speed = response.knockback_speed
    or magnitude(state.velocity_x, state.velocity_y)
  entity.impact_yaw_speed = state.yaw_speed
  entity.separation_distance = response.separation or 0
  apply_motion_channel(entity, state, 1 / 60)
  sync_legacy_fields(entity, state)
  return state
end

function ImpactResponse.is_active(entity)
  return entity
    and entity.impact_response ~= nil
    and entity.impact_response.remaining > 0
end

-- Advance the response by one frame. Yaw is visual-only: it changes the
-- entity's impact_yaw but never changes x, ground_y, or z. The translational
-- channel is the only channel that moves the entity.
function ImpactResponse.update(entity, dt)
  local state = entity and entity.impact_response
  if not state or state.remaining <= 0 then
    return false
  end
  dt = math.max(0, dt or 0)
  apply_motion_channel(entity, state, dt)
  state.yaw = state.yaw + state.yaw_speed * dt
  local decay = math.max(0, 1 - (state.decay * dt) / state.duration)
  state.velocity_x = state.velocity_x * decay
  state.velocity_y = state.velocity_y * decay
  state.remaining = math.max(0, state.remaining - dt)
  if state.remaining <= 0 then
    state.velocity_x = 0
    state.velocity_y = 0
    state.yaw_speed = 0
    entity.impact_response = nil
    entity.combat_state = nil
    entity.combat_source = nil
    entity.impact_mode = nil
    entity.impact_direction_x = nil
    entity.impact_direction_y = nil
    MovementManager.set_velocity(entity, 0, 0)
  end
  sync_legacy_fields(entity, state)
  if not entity.impact_response then
    entity.impact_mode = nil
  end
  return true
end

function ImpactResponse.snapshot(entity)
  local state = entity and entity.impact_response
  if not state then
    return nil
  end
  return {
    velocity_x = state.velocity_x,
    velocity_y = state.velocity_y,
    yaw = state.yaw,
    yaw_speed = state.yaw_speed,
    duration = state.duration,
    remaining = state.remaining,
    source_id = state.source_id,
    combat_state = state.combat_state,
    mode = state.mode,
    direction_x = state.direction_x,
    direction_y = state.direction_y
  }
end

return ImpactResponse
