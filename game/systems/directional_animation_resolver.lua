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
  local slot = directional_slot(angle, count)
  local variant_index = state.variant_index
  local variant = animation.variant_sets and animation.variant_sets[variant_index or 1]
  local frame_map = variant and variant.frame_map or animation.frame_map or (definition.visual or {}).directional_frame_map
  local cardinal_frame = animation.cardinal_frames and animation.cardinal_frames[slot + 1]
  local frame = cardinal_frame or frame_from_map(frame_map, slot)
  return {
    animation_source = (variant and variant.animation_source) or animation.canonical_source,
    frame = frame,
    slot = slot + 1,
    direction = DIRECTION_NAMES[slot + 1] or ("slot_" .. tostring(slot + 1)),
    variant_index = variant_index
  }
end

return Resolver
