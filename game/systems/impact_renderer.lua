-- Presentation-only transform for temporary character impacts.
-- It never changes entity.position; it only returns draw parameters.
local ImpactRenderer = {}

local function active_state(entity)
  if entity and entity.impact_response and entity.impact_response.remaining > 0 then
    return entity.impact_response
  end
  if entity and entity.impact_remaining and entity.impact_remaining > 0 then
    return {
      yaw = entity.impact_yaw or 0,
      mode = entity.impact_mode,
      direction_x = entity.impact_direction_x or 0
    }
  end
  return nil
end

local function facing_for(entity, state)
  local direction_x = state and state.direction_x or 0
  if math.abs(direction_x) > 0.0001 then
    local source_facing = entity.source_facing or 1
    return (direction_x > 0 and 1 or -1) * source_facing
  end
  if entity.get_render_facing then
    return entity:get_render_facing()
  end
  return entity.render_facing or entity.facing or 1
end

function ImpactRenderer.get_transform(entity)
  local scale = entity.scale or 1
  local state = active_state(entity)
  local render_facing = facing_for(entity, state)
  if not state then
    return {
      scale_x = scale * render_facing,
      scale_y = scale,
      yaw = 0,
      spinning = false
    }
  end

  local spinning = state.mode == "yaw_spin"
    or entity.combat_state == "drift_orbit"
    or (entity.controller and entity.controller.get_state
      and entity.controller:get_state() == "hit_spinning")
  if not spinning then
    return {
      scale_x = scale * render_facing,
      scale_y = scale,
      yaw = 0,
      spinning = false
    }
  end

  -- A side-view sprite has no true depth axis. Compressing its horizontal
  -- scale with cosine gives a stable edge-on moment without changing assets.
  local horizontal_squash = math.max(0.05, math.abs(math.cos(state.yaw or 0)))
  return {
    scale_x = scale * render_facing * horizontal_squash,
    scale_y = scale,
    yaw = state.yaw or 0,
    spinning = true
  }
end

return ImpactRenderer
