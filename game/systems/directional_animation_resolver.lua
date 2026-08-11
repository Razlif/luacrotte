-- Converts movement/drift angles into stable directional animation choices.
local Resolver = {}

local DIRECTION_NAMES = {
  "right",
  "down_right",
  "down",
  "down_left",
  "left",
  "up_left",
  "up",
  "up_right"
}

local function directional_slot(angle, count)
  local step = (math.pi * 2) / count
  return math.floor((angle + step * 0.5) / step) % count
end

local function frame_from_map(mapping, slot)
  return (mapping and mapping[slot + 1]) or (slot + 1)
end

local function normalize_angle(angle)
  while angle > math.pi do angle = angle - math.pi * 2 end
  while angle < -math.pi do angle = angle + math.pi * 2 end
  return angle
end

local function resolve_yaw_card(animation, angle)
  local card = animation.yaw_card
  local step = (math.pi * 2) / 8
  local slot = math.floor((angle + step * 0.5) / step) % 8
  local mapping = card.frame_map or { card.front_tilt_frame, card.front_tilt_frame, card.front_frame, card.front_tilt_frame, card.front_tilt_frame, card.back_tilt_frame, card.back_frame, card.back_tilt_frame }
  local flips = card.flip_map or { false, false, false, true, true, false, false, true }
  local frame = mapping[slot + 1]
  return {
    animation_source = card.animation_source or animation.canonical_source,
    frame = frame,
    slot = slot + 1,
    direction = DIRECTION_NAMES[slot + 1] or ("slot_" .. tostring(slot + 1)),
    flip_x = flips[slot + 1] == true
  }
end

local function resolve_slot(definition, slot, variant_index)
  local animation = definition.directional_animation or {}
  local count = animation.direction_count or 8
  local variant = animation.variant_sets and animation.variant_sets[variant_index or 1]
  local frame_map = variant and variant.frame_map or animation.frame_map or (definition.visual or {}).directional_frame_map
  local cardinal_frame = animation.cardinal_frames and animation.cardinal_frames[slot + 1]
  return {
    animation_source = (variant and variant.animation_source) or animation.canonical_source,
    frame = cardinal_frame or frame_from_map(frame_map, slot),
    slot = slot + 1,
    direction = DIRECTION_NAMES[slot + 1] or ("slot_" .. tostring(slot + 1)),
    variant_index = variant_index,
    count = count
  }
end

function Resolver.update_visual_state(hero, definition, angle, dt)
  local animation = definition.directional_animation or {}
  local config = animation.visual_smoothing or {}
  if config.enabled == false then return nil end
  local count = animation.direction_count or 8
  local step = (math.pi * 2) / count
  local state = hero.directional_visual_state or {}
  local slot = state.slot
  if slot == nil then
    slot = directional_slot(angle, count)
    state.slot = slot
    state.previous_slot = slot
    state.transition_elapsed = config.transition_time or 0
  end
  local center = slot * step
  local margin = config.boundary_margin or 0
  if math.abs(normalize_angle(angle - center)) > step * 0.5 + margin then
    local next_slot = directional_slot(angle, count)
    if next_slot ~= slot then
      state.previous_slot = slot
      state.slot = next_slot
      state.transition_elapsed = 0
      slot = next_slot
    end
  end
  local duration = math.max(0, config.transition_time or 0)
  state.transition_elapsed = math.min(duration, (state.transition_elapsed or duration) + (dt or 0))
  state.transition_duration = duration
  hero.directional_visual_state = state
  return state
end

function Resolver.resolve(definition, state)
  local animation = definition.directional_animation or {}
  local count = animation.direction_count or (definition.drift and definition.drift.directional_views and definition.drift.directional_views.count) or 8
  local angle = state.movement_heading or 0
  if state.drift_active then
    angle = state.drift_spin_phase or angle
  end
  if animation.yaw_card then
    local result = resolve_yaw_card(animation, angle)
    result.variant_index = state.variant_index
    return result
  end
  local visual_state = state.visual_state
  local slot = visual_state and visual_state.slot or directional_slot(angle, count)
  local variant_index = state.variant_index
  local result = resolve_slot(definition, slot, variant_index)
  local duration = visual_state and visual_state.transition_duration or 0
  local elapsed = visual_state and visual_state.transition_elapsed or duration
  if visual_state and visual_state.previous_slot ~= slot and duration > 0 and elapsed < duration then
    result.previous = resolve_slot(definition, visual_state.previous_slot, variant_index)
    result.transition_alpha = elapsed / duration
  end
  return result
end

return Resolver
