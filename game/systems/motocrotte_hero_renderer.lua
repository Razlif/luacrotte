-- MotoCrotte-specific renderer for visual experiments and gameplay fallback.
local PositionManager = require("game.systems.position_manager")

local Renderer = {}

local function mode_index(mode, modes)
  for index, candidate in ipairs(modes or {}) do
    if candidate == mode then return index end
  end
  return 1
end

local function draw_sprite(hero, rotation, scale_x)
  local x = hero.position.x
  local y = PositionManager.get_screen_y(hero.position)
  if hero.animation:is_playing() then
    hero.animation:draw(x, y, scale_x, hero.scale, hero.anchor_x, hero.anchor_y, rotation)
  else
    love.graphics.draw(hero.asset.image.texture, x, y, rotation, scale_x, hero.scale, hero.anchor_x, hero.anchor_y)
  end
end

local function draw_direction_marker(hero, heading, label)
  local x = hero.position.x
  local y = PositionManager.get_screen_y(hero.position) - hero.anchor_y - 18
  love.graphics.setColor(1, 0.8, 0.25, 0.9)
  love.graphics.line(x, y, x + math.cos(heading) * 28, y + math.sin(heading) * 28)
  love.graphics.setColor(1, 1, 1, 1)
  if label then love.graphics.print(label, x + 34, y - 8) end
end

local function draw_visual_test(hero, definition, visual_state)
  local visual = definition.visual or {}
  local mode = visual_state.mode or visual.test_mode or "yaw_squash"
  local yaw = visual_state.yaw or 0
  local count = visual.directional_view_count or 8
  local scale_x = hero.scale * hero.source_facing
  local marker_heading = yaw

  if mode == "yaw_squash" then
    -- Faux vertical-axis rotation: keep screen rotation at zero and compress
    -- only the horizontal axis around the hero's vertical pivot.
    scale_x = scale_x * math.cos(yaw)
  elseif mode == "directional_views" then
    local step = (math.pi * 2) / count
    local slot = math.floor((yaw + step * 0.5) / step) % count
    visual_state.directional_index = slot + 1
  elseif mode == "hybrid" then
    local step = (math.pi * 2) / count
    local slot = math.floor((yaw + step * 0.5) / step) % count
    visual_state.directional_index = slot + 1
    scale_x = scale_x * math.cos(yaw - slot * step)
  end

  draw_sprite(hero, 0, scale_x)
  if mode ~= "yaw_squash" then
    draw_direction_marker(hero, marker_heading, string.format("%s  %d/%d", mode, visual_state.directional_index or 1, count))
  end
end

local function draw_gameplay_visual(hero, definition)
  local drift = definition.drift or {}
  local motion = hero.motocrotte_motion or {}
  local mode = hero.motocrotte_visual_mode or drift.visual_mode or "flat_rotate"
  local yaw = hero.visual_yaw or motion.heading or 0
  local rotation = 0
  local scale_x = hero.scale * hero.source_facing

  if mode == "yaw_squash" then
    scale_x = scale_x * math.cos(yaw)
  elseif mode == "directional_views" or mode == "hybrid" then
    local count = (drift.directional_views and drift.directional_views.count) or 8
    local step = (math.pi * 2) / count
    local slot = math.floor((yaw + step * 0.5) / step) % count
    motion.directional_index = slot + 1
    scale_x = scale_x * math.cos(yaw - slot * step)
  end

  draw_sprite(hero, rotation, scale_x)
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
