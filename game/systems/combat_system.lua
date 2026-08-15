-- Resolves gameplay consequences of detected contacts.
-- CollisionDetection remains detection-only; this module classifies impacts
-- and dispatches them, while ImpactResponse owns physical separation and the
-- temporary movement/visual response.
local ImpactResponse = require("game.systems.impact_response")
local CombatSystem = {}

local DEFAULTS = {
  separation_padding = 2,
  impact_cooldown = 0.35,
  responses = {
    drift_orbit = {
      knockback = 900,
      impact_velocity_scale = 0.35,
      yaw_speed = math.rad(720),
      duration = 3.5,
      hit_pause = 3.5
    },
    straight_drift = {
      knockback = 420,
      impact_velocity_scale = 0.2,
      yaw_speed = math.rad(45),
      duration = 0.6,
      hit_pause = 0.6
    },
    regular_drive = {
      knockback_scale = 1.0,
      yaw_speed = 0,
      duration = 0.35,
      hit_pause = 0.35
    },
    glide = {
      knockback_scale = 0.35,
      yaw_speed = 0,
      duration = 0.2,
      hit_pause = 0.2
    },
    stationary = {
      knockback_scale = 0.15,
      yaw_speed = 0,
      duration = 0.15,
      hit_pause = 0.15
    }
  }
}

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

local function copy_response(default_response, configured_response)
  local response = {}
  for key, value in pairs(default_response or {}) do
    response[key] = value
  end
  for key, value in pairs(configured_response or {}) do
    response[key] = value
  end
  return response
end

local function configuration(options, enemy)
  local profile_combat = options and options.profile and options.profile.combat or {}
  local enemy_combat = enemy and enemy.definition and enemy.definition.combat or {}
  return {
    separation_padding = profile_combat.separation_distance
      or profile_combat.separation_padding
      or DEFAULTS.separation_padding,
    maximum_knockback = profile_combat.maximum_knockback,
    spinning_drift_multiplier = profile_combat.spinning_drift_multiplier or 1,
    straight_drift_multiplier = profile_combat.straight_drift_multiplier or 1,
    impact_cooldown = profile_combat.impact_cooldown
      or enemy_combat.hit_cooldown
      or DEFAULTS.impact_cooldown,
    responses = profile_combat.responses or DEFAULTS.responses,
    impacts = enemy_combat.impacts,
    recovery_time = profile_combat.recovery_duration or enemy_combat.recovery_time
  }
end

local function motion_of(entity)
  return entity and entity.motocrotte_motion or {}
end

local function hero_speed(hero)
  local motion = motion_of(hero)
  return motion.speed or magnitude(motion.vx or 0, motion.vy or 0)
end

function CombatSystem.classify_hero(hero)
  local motion = motion_of(hero)
  if motion.drift_active then
    if motion.drift_mode == "orbit" then
      return "drift_orbit"
    end
    return "straight_drift"
  end
  if motion.locomotion_state == "regular_drive"
      or motion.locomotion_state == "braking"
      or motion.input_active then
    return "regular_drive"
  end
  if motion.locomotion_state == "glide" or hero_speed(hero) > 0.5 then
    return "glide"
  end
  return "stationary"
end

local function entity_id(entity)
  return entity and (entity.id or (entity.definition and entity.definition.runtime_id)) or nil
end

local function pair_key(first_id, second_id)
  if tostring(first_id) < tostring(second_id) then
    return tostring(first_id) .. "::" .. tostring(second_id)
  end
  return tostring(second_id) .. "::" .. tostring(first_id)
end

local function cooldowns_for(hero)
  hero.combat_cooldowns = hero.combat_cooldowns or {}
  return hero.combat_cooldowns
end

local function update_cooldowns(hero, dt)
  local cooldowns = cooldowns_for(hero)
  for key, remaining in pairs(cooldowns) do
    remaining = remaining - (dt or 0)
    if remaining <= 0 then
      cooldowns[key] = nil
    else
      cooldowns[key] = remaining
    end
  end
end

local function contact_for(event)
  return event.contact or {
    collision_type = event.collision_type or "shape",
    normal = { x = 0, y = 0 },
    penetration = 0,
    relative_velocity = { x = 0, y = 0 }
  }
end

local function hero_to_enemy_contact(event, hero_id)
  local contact = contact_for(event)
  local normal_x = contact.normal and contact.normal.x or 0
  local normal_y = contact.normal and contact.normal.y or 0
  local relative_x = contact.relative_velocity and contact.relative_velocity.x or 0
  local relative_y = contact.relative_velocity and contact.relative_velocity.y or 0
  if event.target_id == hero_id then
    normal_x, normal_y = -normal_x, -normal_y
    relative_x, relative_y = -relative_x, -relative_y
  end
  return contact, normal_x, normal_y, relative_x, relative_y
end

local function impact_direction(hero, normal_x, normal_y, relative_x, relative_y)
  local direction_x, direction_y = normalize(normal_x, normal_y)
  if direction_x == 0 and direction_y == 0 then
    direction_x, direction_y = normalize(relative_x, relative_y)
  end
  if direction_x == 0 and direction_y == 0 then
    local motion = motion_of(hero)
    direction_x, direction_y = normalize(motion.vx or 0, motion.vy or 0)
  end
  return direction_x, direction_y
end

local function impact_speed(hero, normal_x, normal_y, relative_x, relative_y)
  local approaching = relative_x * normal_x + relative_y * normal_y
  if approaching > 0 then
    return approaching
  end
  return math.max(0, magnitude(relative_x, relative_y) * 0.35, hero_speed(hero) * 0.35)
end

local function response_for(settings, state)
  local impact_key = state == "drift_orbit" and "spinning_drift" or state
  local configured = settings.impacts and settings.impacts[impact_key]
    or settings.responses[impact_key]
    or settings.responses[state]
  return copy_response(DEFAULTS.responses[state] or DEFAULTS.responses.stationary, configured)
end

local function build_response(hero, enemy, state, settings, direction_x, direction_y, speed, event, separated)
  local response = response_for(settings, state)
  local strength
  if response.knockback then
    strength = response.knockback + speed * (response.impact_velocity_scale or 0)
  else
    strength = speed * (response.knockback_scale or 0)
  end
  if state == "drift_orbit" then
    strength = strength * settings.spinning_drift_multiplier
  elseif state == "straight_drift" then
    strength = strength * settings.straight_drift_multiplier
  end
  if settings.maximum_knockback then
    strength = math.min(strength, settings.maximum_knockback)
  end
  return {
    source_id = entity_id(hero),
    target_id = entity_id(enemy),
    state = state,
    collision_type = event.collision_type or (event.contact and event.contact.collision_type) or "shape",
    impact_speed = speed,
    knockback_speed = strength,
    direction = { x = direction_x, y = direction_y },
    strength = strength,
    velocity_x = direction_x * strength,
    velocity_y = direction_y * strength,
    yaw_speed = response.yaw_speed or 0,
    duration = response.duration or 0.25,
    hit_pause = response.hit_pause or response.duration or 0.25,
    recovery_time = response.recovery_time or settings.recovery_time,
    penetration = event.contact and event.contact.penetration or 0,
    separation = separated,
    timestamp = event.frame
  }
end

local function dispatch(enemy, response)
  if enemy.apply_combat_impact then
    enemy:apply_combat_impact(response)
  else
    ImpactResponse.apply(enemy, response)
    if enemy.mark_hit then
      enemy:mark_hit(response.hit_pause)
    end
  end
end

local function block_hero_motion(hero, normal_x, normal_y, state)
  if state ~= "regular_drive" and state ~= "glide" and state ~= "stationary" then
    return
  end
  local motion = motion_of(hero)
  local velocity_x, velocity_y = motion.vx or 0, motion.vy or 0
  local closing_speed = velocity_x * normal_x + velocity_y * normal_y
  if closing_speed <= 0 then return end
  motion.vx = velocity_x - normal_x * closing_speed
  motion.vy = velocity_y - normal_y * closing_speed
  motion.speed = magnitude(motion.vx, motion.vy)
end

-- Resolve hero/enemy contacts. This function is intentionally side-effect-free
-- with respect to collision detection itself: it only consumes event data and
-- mutates the gameplay entities that own the response.
function CombatSystem.resolve(events, options)
  options = options or {}
  local hero = options.hero
  if not hero then
    return {}
  end
  local by_id = {}
  for _, enemy in ipairs(options.enemies or {}) do
    by_id[entity_id(enemy)] = enemy
  end
  by_id[entity_id(hero)] = hero
  update_cooldowns(hero, options.dt or 0)
  local cooldowns = cooldowns_for(hero)
  local handled = {}
  local separated_pairs = {}
  local impacts = {}
  local hero_id = entity_id(hero)

  for _, event in ipairs(events or {}) do
    local source = by_id[event.source_id]
    local target = by_id[event.target_id]
    if source and target and source ~= hero and target ~= hero then
      local enemy_pair = pair_key(entity_id(source), entity_id(target))
      if not separated_pairs[enemy_pair] then
        local profile_combat = options.profile and options.profile.combat or {}
        ImpactResponse.separate(source, target, contact_for(event), {
          padding = profile_combat.separation_distance or DEFAULTS.separation_padding
        })
        separated_pairs[enemy_pair] = true
      end
    end
    local enemy = source == hero and target or target == hero and source or nil
    local enemy_impact_locked = enemy
      and enemy.controller
      and enemy.controller.is_impact_locked
      and enemy.controller:is_impact_locked()
    if enemy and enemy ~= hero then
      local key = pair_key(hero_id, entity_id(enemy))
      local settings = configuration(options, enemy)
      local contact, normal_x, normal_y, relative_x, relative_y = hero_to_enemy_contact(event, hero_id)
      local separated = 0
      if not separated_pairs[key] then
        separated = ImpactResponse.separate(hero, enemy, {
          normal = { x = normal_x, y = normal_y },
          penetration = contact.penetration
        }, { padding = settings.separation_padding })
        separated_pairs[key] = true
      end
      local state = CombatSystem.classify_hero(hero)
      block_hero_motion(hero, normal_x, normal_y, state)
      if not enemy_impact_locked and not handled[key] and not cooldowns[key] then
        handled[key] = true
        local direction_x, direction_y = impact_direction(hero, normal_x, normal_y, relative_x, relative_y)
        local speed = impact_speed(hero, normal_x, normal_y, relative_x, relative_y)
        local response = build_response(hero, enemy, state, settings, direction_x, direction_y, speed, event, separated)
        dispatch(enemy, response)
        cooldowns[key] = settings.impact_cooldown
        impacts[#impacts + 1] = response
      end
    end
  end
  return impacts
end

return CombatSystem
