-- Lightweight timeline-controlled actor. It intentionally has no gameplay controller.
local AnimationManager = require("game.systems.animation_manager")
local PositionManager = require("game.systems.position_manager")

local Actor = {}
Actor.__index = Actor

function Actor.new(data, loaded_asset)
  local image = loaded_asset.image
  local anchor = data.anchor or { x = image.width / 2, y = image.height }
  return setmetatable({
    id = data.id,
    asset_id = data.asset_id,
    asset = loaded_asset,
    position = PositionManager.new(data.position),
    scale = data.scale or 1,
    anchor_x = anchor.x,
    anchor_y = anchor.y,
    facing = data.facing == "left" and -1 or 1,
    source_facing = data.source_facing or 1,
    movement = data.movement or {},
    hop_animation = data.hop_animation,
    default_animation = data.default_animation,
    default_animation_loop = data.default_animation_loop == true,
    draw_layer = data.draw_layer or 20,
    draw_order_id = data.id,
    presentation = {
      rotation = 0,
      scale_x = 1,
      scale_y = 1
    },
    animation = AnimationManager.new(loaded_asset.animations)
  }, Actor)
end

function Actor:set_presentation(values)
  values = values or {}
  self.presentation.rotation = values.rotation or 0
  self.presentation.scale_x = values.scale_x or 1
  self.presentation.scale_y = values.scale_y or 1
end

function Actor:clear_presentation()
  self:set_presentation()
end

function Actor:face(direction)
  if direction == "left" or direction == -1 then
    self.facing = -1
  elseif direction == "right" or direction == 1 then
    self.facing = 1
  end
end

function Actor:play(name, loop)
  local animation = self.animation.animations[name]
  assert(animation, "Unknown cutscene animation '" .. tostring(name) .. "' for " .. self.id)
  if loop ~= nil then
    animation.loop = loop
  end
  self.animation:play(name)
end

function Actor:get_animation_duration(name)
  local animation = self.animation.animations[name]
  assert(animation, "Unknown cutscene animation '" .. tostring(name) .. "' for " .. self.id)
  return animation.frame_count / animation.fps
end

function Actor:update(dt)
  self.animation:update(dt)
end

function Actor:idle()
  if self.default_animation then
    self.animation:play(self.default_animation)
    local animation = self.animation.animations[self.default_animation]
    animation.loop = self.default_animation_loop
  else
    self.animation:stop()
  end
end

function Actor:get_camera_focus(zoom, include_dialogue)
  local top = self.position.ground_y - self.anchor_y * self.scale
  if include_dialogue then
    local camera_zoom = zoom or 1
    top = top - (92 + 18) / camera_zoom
  end
  return {
    x = self.position.x,
    ground_y = (top + self.position.ground_y) / 2
  }
end

function Actor:draw()
  love.graphics.setColor(1, 1, 1, 1)
  local x = self.position.x
  local y = PositionManager.get_screen_y(self.position)
  local scale_x = self.scale * self.facing * self.source_facing * self.presentation.scale_x
  local scale_y = self.scale * self.presentation.scale_y
  if self.animation:is_playing() then
    self.animation:draw(x, y, scale_x, scale_y, self.anchor_x, self.anchor_y, self.presentation.rotation)
  else
    love.graphics.draw(self.asset.image.texture, x, y, self.presentation.rotation, scale_x, scale_y, self.anchor_x, self.anchor_y)
  end
end

return Actor
