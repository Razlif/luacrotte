-- Rectangle-only diagnostic renderer for the shared zero-gravity physics world.
-- It reads bodies, contacts, and synchronized positions; it never changes them.
local Renderer = {}

local function body_position(entity)
  if entity.physics_body then
    return entity.physics_body:getPosition()
  end
  return entity.position.x, entity.position.ground_y
end

local function box(entity)
  local footprint = entity.physics_footprint
  local scale = entity.scale or 1
  local width = footprint.width * scale
  local height = footprint.height * scale
  local x, y = body_position(entity)
  return { x = x - width * 0.5, y = y - height * 0.5, width = width, height = height, center_x = x, center_y = y }
end

local function separation(first, second)
  local a = box(first)
  local b = box(second)
  local dx = math.abs(a.center_x - b.center_x) - (a.width + b.width) * 0.5
  local dy = math.abs(a.center_y - b.center_y) - (a.height + b.height) * 0.5
  if dx <= 0 and dy <= 0 then return math.max(dx, dy) end
  return math.sqrt(math.max(0, dx) ^ 2 + math.max(0, dy) ^ 2)
end

local function velocity(entity)
  if entity.physics_body then
    return entity.physics_body:getLinearVelocity()
  end
  return 0, 0
end

local function entity_map(lab)
  local result = { [lab.hero.id] = lab.hero }
  for _, enemy in ipairs(lab.enemies) do result[enemy.id] = enemy end
  return result
end

function Renderer.draw(lab, bounds, contacts)
  if not lab or not lab.hero then return end
  local entities = { lab.hero }
  for _, enemy in ipairs(lab.enemies) do entities[#entities + 1] = enemy end

  if bounds then
    love.graphics.setColor(0.45, 0.85, 0.95, 0.75)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", bounds.left, bounds.top, bounds.right - bounds.left, bounds.bottom - bounds.top)
  end

  for _, entity in ipairs(entities) do
    local footprint = entity.physics_footprint
    local rectangle = box(entity)
    local color = entity.lab_color or { 1, 1, 1, 0.85 }
    local vx, vy = velocity(entity)
    love.graphics.setColor(color[1], color[2], color[3], color[4] or 0.85)
    love.graphics.rectangle("fill", rectangle.x, rectangle.y, rectangle.width, rectangle.height)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", rectangle.x, rectangle.y, rectangle.width, rectangle.height)
    love.graphics.line(rectangle.center_x, rectangle.center_y,
      rectangle.center_x + vx * 0.18, rectangle.center_y + vy * 0.18)
    love.graphics.print(string.format("body:%s", entity.id), rectangle.x, rectangle.y - 18)
    love.graphics.print(string.format("v %.0f,%.0f  base %.0fx%.0f", vx, vy, footprint.width, footprint.height),
      rectangle.x, rectangle.y + rectangle.height + 4)
  end

  local by_id = entity_map(lab)
  for _, event in ipairs(contacts or {}) do
    -- LÖVE does not guarantee a useful normal during an end-contact
    -- callback. Keep the diagnostic normal tied to active contacts only.
    local first = event.phase ~= "end" and by_id[event.source_id] or nil
    local second = event.phase ~= "end" and by_id[event.target_id] or nil
    if first and second then
      local a = box(first)
      local b = box(second)
      local midpoint_x = (a.center_x + b.center_x) * 0.5
      local midpoint_y = (a.center_y + b.center_y) * 0.5
      local normal = event.normal or (event.contact and event.contact.normal) or { x = 0, y = 0 }
      love.graphics.setColor(1, 1, 0.25, 1)
      love.graphics.setLineWidth(4)
      love.graphics.line(midpoint_x, midpoint_y,
        midpoint_x + (normal.x or 0) * 48, midpoint_y + (normal.y or 0) * 48)
      love.graphics.print(string.format("normal %.2f,%.2f  separation %.1f",
        normal.x or 0, normal.y or 0, separation(first, second)), midpoint_x + 8, midpoint_y - 18)
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
  local contact_count = #(contacts or {})
  local header_x = (bounds and bounds.left or 0) + 220
  local header_y = (bounds and bounds.top or 0) + 100
  love.graphics.print("PLAYGROUND 7  |  PHYSICS BUMPER LAB", header_x, header_y)
  love.graphics.print("Arrow keys: move the cyan body    Contacts: " .. tostring(contact_count),
    header_x, header_y + 22)
end

return Renderer
