-- MotoCrotte-specific renderer for visual experiments and gameplay fallback.
local PositionManager = require("game.systems.position_manager")
local AnimationResolver = require("game.systems.directional_animation_resolver")

local Renderer = {}

local function mode_index(mode, modes)
  for index, candidate in ipairs(modes or {}) do
    if candidate == mode then return index end
  end
  return 1
end

local function draw_sprite(hero, rotation, scale_x, frame, position, anchor, animation_source, flip_x)
  local x = (position and position.x) or hero.position.x
  local y = (position and position.y) or PositionManager.get_screen_y(hero.position)
  local anchor_x = (anchor and anchor.x) or hero.anchor_x
  local anchor_y = (anchor and anchor.y) or hero.anchor_y
  if flip_x then scale_x = -scale_x end
  if hero.animation:is_playing() then
    if frame then
      hero.animation:draw_frame(frame, x, y, scale_x, hero.scale, anchor_x, anchor_y, rotation, animation_source)
    else
      hero.animation:draw(x, y, scale_x, hero.scale, anchor_x, anchor_y, rotation)
    end
  elseif hero.asset.image then
    love.graphics.draw(hero.asset.image.texture, x, y, rotation, scale_x, hero.scale, anchor_x, anchor_y)
  end
end

local function orbit_angles(visual, yaw)
  local pivot = visual.directional_pivot or {}
  local orbit_angle = yaw + (pivot.angle_offset or 0)
  local facing_angle = orbit_angle + (pivot.facing_offset or math.pi)
  return orbit_angle, facing_angle
end

local function orbit_position(hero, visual, yaw, radius_override)
  local pivot = visual.directional_pivot or {}
  local radius = radius_override
  if radius == nil then radius = pivot.radius or 0 end
  local angle = orbit_angles(visual, yaw)
  local center_x = hero.position.x + (pivot.center_offset_x or 0)
  local center_y = PositionManager.get_screen_y(hero.position) + (pivot.center_offset_y or 0)
  return {
    x = center_x + math.cos(angle) * radius,
    y = center_y + math.sin(angle) * radius
  }
end

local function orbit_anchor(hero, visual)
  local pivot = visual.directional_pivot or {}
  return {
    x = pivot.anchor_x or hero.anchor_x,
    y = pivot.anchor_y or hero.anchor_y
  }
end

local function wheelie_anchor(hero, definition, direction)
  local wheelie = (((definition or {}).dash or {}).wheelie_spin or {}).contact_anchor or {}
  local direction_anchor = wheelie[direction]
  if direction_anchor then
    return { x = direction_anchor.x, y = direction_anchor.y }
  end
  return {
    x = wheelie.x or hero.anchor_x,
    y = wheelie.y or hero.anchor_y
  }
end

local function draw_orbit_guide(hero, visual, yaw, radius_override)
  local pivot = visual.directional_pivot or {}
  local radius = radius_override
  if radius == nil then radius = pivot.radius or 0 end
  if pivot.show_orbit ~= true or radius <= 0 then
    return
  end
  local center_x = hero.position.x + (pivot.center_offset_x or 0)
  local center_y = PositionManager.get_screen_y(hero.position) + (pivot.center_offset_y or 0)
  local orbit = orbit_position(hero, visual, yaw, radius)
  love.graphics.setColor(0.4, 0.85, 1, 0.45)
  love.graphics.circle("line", center_x, center_y, radius)
  love.graphics.line(center_x, center_y, orbit.x, orbit.y)
  love.graphics.circle("fill", orbit.x, orbit.y, 2)
  love.graphics.setColor(1, 1, 1, 1)
end

local function directional_frame(visual, slot)
  local mapping = visual.directional_frame_map
  return (mapping and mapping[slot]) or slot
end

local function directional_slot(angle, count)
  local step = (math.pi * 2) / count
  return math.floor((angle + step * 0.5) / step) % count
end

local function draw_direction_marker(hero, heading, label)
  local x = hero.position.x
  local y = PositionManager.get_screen_y(hero.position) - hero.anchor_y - 18
  love.graphics.setColor(1, 0.8, 0.25, 0.9)
  love.graphics.line(x, y, x + math.cos(heading) * 28, y + math.sin(heading) * 28)
  love.graphics.setColor(1, 1, 1, 1)
  if label then love.graphics.print(label, x + 34, y - 8) end
end

local function projection_state(hero, definition)
  local environment = definition.environment or {}
  local projection = environment.projection or "flat"
  local scale = environment.hero_scale or 1
  if projection ~= "perspective_ground" then
    return nil, scale
  end
  local movement = definition.movement or {}
  local depth = movement.depth_bounds or { min = 365, max = 680 }
  local range = math.max(1, depth.max - depth.min)
  local amount = math.max(0, math.min(1, (hero.position.ground_y - depth.min) / range))
  local min_scale = environment.min_scale or 0.55
  local max_scale = environment.max_scale or 1.35
  local horizon_y = environment.horizon_y or 315
  local ground_y = environment.ground_y or 690
  return {
    x = hero.position.x,
    y = horizon_y + amount * (ground_y - horizon_y)
  }, scale * (min_scale + amount * (max_scale - min_scale))
end

local function draw_visual_test(hero, definition, visual_state)
  local visual = definition.visual or {}
  local mode = visual_state.mode or visual.test_mode or "yaw_squash"
  local yaw = visual_state.yaw or 0
  local count = visual.directional_view_count or 8
  local scale_x = hero.scale * hero.source_facing
  local _, facing_angle = orbit_angles(visual, yaw)
  local marker_heading = facing_angle
  local orbit_radius = visual_state.orbit_radius

  if mode == "yaw_squash" then
    -- Faux vertical-axis rotation: keep screen rotation at zero and compress
    -- only the horizontal axis around the hero's vertical pivot.
    scale_x = scale_x * math.abs(math.cos(facing_angle))
    draw_orbit_guide(hero, visual, yaw, orbit_radius)
    local slot = directional_slot(facing_angle, count)
    draw_sprite(hero, 0, scale_x, directional_frame(visual, slot + 1), orbit_position(hero, visual, yaw, orbit_radius), orbit_anchor(hero, visual))
    return
  elseif mode == "directional_views" then
    local slot = directional_slot(facing_angle, count)
    visual_state.directional_index = slot + 1
    draw_orbit_guide(hero, visual, yaw, orbit_radius)
    draw_sprite(hero, 0, scale_x, directional_frame(visual, slot + 1), orbit_position(hero, visual, yaw, orbit_radius), orbit_anchor(hero, visual))
    draw_direction_marker(hero, marker_heading, string.format("%s  %d/%d", mode, visual_state.directional_index or 1, count))
    return
  elseif mode == "hybrid" then
    local slot = directional_slot(facing_angle, count)
    visual_state.directional_index = slot + 1
    local step = (math.pi * 2) / count
    scale_x = scale_x * math.abs(math.cos(facing_angle - slot * step))
    draw_orbit_guide(hero, visual, yaw, orbit_radius)
    draw_sprite(hero, 0, scale_x, directional_frame(visual, slot + 1), orbit_position(hero, visual, yaw, orbit_radius), orbit_anchor(hero, visual))
    draw_direction_marker(hero, marker_heading, string.format("%s  %d/%d", mode, visual_state.directional_index or 1, count))
    return
  end

  draw_sprite(hero, 0, scale_x)
  if mode ~= "yaw_squash" then
    draw_direction_marker(hero, marker_heading, string.format("%s  %d/%d", mode, visual_state.directional_index or 1, count))
  end
end

local function draw_gameplay_visual(hero, definition)
  local drift = definition.drift or {}
  local motion = hero.motocrotte_motion or {}
  local visual = definition.visual or {}
  local mode = hero.motocrotte_visual_mode or drift.visual_mode or "flat_rotate"
  local schema = definition.controls and definition.controls.schema
  local steering_heading = (schema == "gas_steering" or schema == "gas_steering_fd" or schema == "throttle_steering")
    and (motion.steering_heading or motion.heading)
    or motion.heading
  local yaw_mode = visual.yaw_mode or (visual.yaw_enabled == false and "off" or "all_movement")
  local yaw = yaw_mode == "all_movement" and (hero.visual_yaw or steering_heading or 0) or (steering_heading or 0)
  local yaw_axis = visual.yaw_axis or 0
  local braking_visual = definition.braking_visual or {}
  local rotation = braking_visual.enabled ~= false and (motion.braking_tilt_angle or 0) or 0
  if motion.dash_active then
    rotation = motion.dash_visual_angle or 0
  end
  local projected_position, projection_scale = projection_state(hero, definition)
  local scale_x = hero.scale * projection_scale * hero.source_facing
  local count = (drift.directional_views and drift.directional_views.count) or 8
  local slot = directional_slot(yaw, count)

  if motion.drift_active and motion.drift_spin_phase then
    local spin_phase = motion.dash_axial_spin_active and motion.dash_axial_spin_phase
      or motion.drift_spin_phase
    local pivot = visual.directional_pivot or {}
    local radius = motion.drift_orbit_radius
    if radius == nil then radius = pivot.radius or 0 end
    -- The spin phase describes the bike's position around the visual orbit.
    -- Directional frame selection has its own facing offset: the promoted
    -- motorcycle sheet's canonical front is opposite the orbit's zero angle.
    -- Keep these angles separate so the bike rotates in the same direction as
    -- the orbit without choosing the opposite sprite.
    local facing_phase = spin_phase + (pivot.angle_offset or 0) + (pivot.facing_offset or math.pi)
    local resolved = AnimationResolver.resolve(definition, {
      movement_heading = yaw,
      drift_active = true,
      drift_spin_phase = facing_phase,
      variant_index = motion.drift_variant_index
    })
    local wheelie = ((definition.dash or {}).front_wheelie or {})
    if motion.dash_axial_spin_active then
      -- A combined wheelie spin uses one stable side silhouette. Directional
      -- frames would redefine the front/rear wheel and allow them to swap.
      resolved.frame = wheelie.frame or 3
      resolved.animation_source = wheelie.animation_source or "motorcycle_direction_full"
      resolved.flip_x = wheelie.flip_x == true
      resolved.direction = "front_wheelie"
    end
    motion.directional_index = resolved.slot
    motion.directional_direction = resolved.direction
    motion.directional_frame = resolved.frame
    if yaw_mode ~= "off" then
      local yaw_phase = motion.dash_axial_spin_active and motion.dash_axial_spin_phase
        or motion.drift_yaw_phase or facing_phase
      scale_x = scale_x * math.abs(math.cos(yaw_phase - yaw_axis))
      motion.visual_yaw_phase = yaw_phase
    end
    local position = projected_position or {
      x = hero.position.x,
      y = PositionManager.get_screen_y(hero.position)
    }
    local draw_rotation = motion.dash_active and (motion.dash_visual_angle or 0) or 0
    local draw_anchor
    if motion.dash_axial_spin_active then
      local contact = wheelie.contact_anchor or { x = 48, y = 56 }
      draw_anchor = { x = contact.x, y = contact.y }
    else
      draw_anchor = orbit_anchor(hero, visual)
    end
    draw_sprite(hero, draw_rotation, scale_x, resolved.frame, position, draw_anchor, resolved.animation_source, resolved.flip_x)
    return
  end

  if yaw_mode == "all_movement" then
    scale_x = scale_x * math.abs(math.cos(yaw - yaw_axis))
  end

  if mode == "directional_views" or mode == "hybrid" then
    local directional = drift.directional_views or {}
    count = directional.count or 8
    slot = directional_slot(yaw, count)
    motion.directional_index = slot + 1
    visual = directional
  end

  local resolved = AnimationResolver.resolve(definition, {
    movement_heading = yaw,
    drift_active = false,
    variant_index = nil
  })
  motion.directional_index = resolved.slot
  motion.directional_direction = resolved.direction
  motion.directional_frame = resolved.frame
  draw_sprite(hero, rotation, scale_x, resolved.frame, projected_position, nil, resolved.animation_source, resolved.flip_x)
end

function Renderer.draw(hero, definition, visual_state)
  if visual_state and visual_state.active then
    draw_visual_test(hero, definition, visual_state)
  else
    draw_gameplay_visual(hero, definition)
  end
end

function Renderer.mode_index(mode, definition)
  local modes = definition.visual and definition.visual.modes or definition.drift and definition.drift.modes
  return mode_index(mode, modes)
end

return Renderer
