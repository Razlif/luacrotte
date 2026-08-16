-- Returns a stable 2.5D draw order without mutating the scene's entity list.
--
-- ground_y is the depth authority.  Sprite dimensions, masks, visual yaw,
-- squash, and draw layers must never change which entity is in front.  The
-- layer/id values below are deterministic tie-breakers for equal ground_y.
local DrawOrder = {}

local function layer_of(drawable)
  return drawable.draw_layer or 20
end

function DrawOrder.sort(drawables)
  local decorated = {}
  for index, drawable in ipairs(drawables) do
    decorated[index] = { drawable = drawable, index = index }
  end

  table.sort(decorated, function(first, second)
    local a = first.drawable
    local b = second.drawable
    local a_y = a.position and a.position.ground_y or 0
    local b_y = b.position and b.position.ground_y or 0
    if a_y ~= b_y then
      return a_y < b_y
    end
    if layer_of(a) ~= layer_of(b) then
      return layer_of(a) < layer_of(b)
    end
    local a_id = a.draw_order_id or first.index
    local b_id = b.draw_order_id or second.index
    return tostring(a_id) < tostring(b_id)
  end)

  local result = {}
  for index, item in ipairs(decorated) do
    result[index] = item.drawable
  end
  return result
end

return DrawOrder
