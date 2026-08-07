-- Shared runtime character behavior.
local AnimationManager = require("game.systems.animation_manager")
local ControllerFactory = require("game.controllers.controller_factory")
local MovementManager = require("game.systems.movement_manager")
local PositionManager = require("game.systems.position_manager")
local TimerManager = require("game.systems.timer_manager")

local Character = {}
Character.__index = Character

function Character.new(definition, loaded_asset)
  local character = setmetatable({
    id = definition.runtime_id or definition.asset_id,
    definition = definition,
    asset = loaded_asset,
    controller = ControllerFactory.create(definition.controller),
    position = PositionManager.new(definition.position),
    scale = definition.scale or 1,
    anchor_x = definition.anchor.x,
    anchor_y = definition.anchor.y,
    facing_enabled = not definition.facing or definition.facing.enabled ~= false,
    facing = (definition.facing and definition.facing.default == "left") and -1 or 1,
    source_facing = (definition.facing and definition.facing.source == "right") and 1 or -1,
    draw_layer = definition.draw_layer or 20,
    draw_order_id = definition.draw_order_id or definition.asset_id,
    default_animation = definition.default_animation,
    hop_animation = definition.hop_animation,
    hop_on_press = definition.hop_on_press == true,
    hopping = false,
    hop_elapsed = 0,
    hop_duration = 0,
    hop_dx = 0,
    hop_dground_y = 0,
    movement_was_active = false,
    animation = AnimationManager.new(loaded_asset.animations),
    timer = TimerManager.new(),
    flash_remaining = 0,
    flash_elapsed = 0
  }, Character)

  if character.default_animation then
    local default_animation = character.animation.animations[character.default_animation]
    if character.definition.default_animation_loop and default_animation then
      default_animation.loop = true
    end
    character.animation:play(character.default_animation)
  end

  return character
end

function Character:play(name)
  self.animation:play(name)
end

function Character:get_render_facing()
  return self.facing * self.source_facing
end

function Character:hit_flash(duration)
  self.flash_remaining = math.max(self.flash_remaining, duration or 0.25)
  self.flash_elapsed = 0
end

local function movement_direction(intent)
  local horizontal = intent.horizontal or 0
  local vertical = intent.vertical or 0
  local length = math.sqrt(horizontal * horizontal + vertical * vertical)
  if length == 0 then
    return 0, 0
  end
  return horizontal / length, vertical / length
end

function Character:begin_hop(intent)
  if self.hopping or not self.hop_animation then
    return false
  end
  local animation = self.animation.animations[self.hop_animation]
  if not animation then
    return false
  end

  local direction_x, direction_y = movement_direction(intent)
  local movement = self.definition.movement or {}
  local horizontal_speed = movement.hop_horizontal_speed or movement.horizontal_speed or movement.speed or 0
  local vertical_speed = movement.hop_vertical_speed or movement.vertical_speed or movement.speed or 0
  self.hopping = true
  self.hop_elapsed = 0
  self.hop_duration = animation.frame_count / animation.fps
  self.hop_dx = direction_x * horizontal_speed * self.hop_duration
  self.hop_dground_y = direction_y * vertical_speed * self.hop_duration
  self.animation:play(self.hop_animation)
  return true
end

function Character:update_hop(dt)
  if not self.hopping then
    return
  end
  local previous_progress = math.min(1, self.hop_elapsed / self.hop_duration)
  self.hop_elapsed = math.min(self.hop_duration, self.hop_elapsed + dt)
  local progress = self.hop_elapsed / self.hop_duration
  local eased_previous = previous_progress * previous_progress * (3 - 2 * previous_progress)
  local eased_progress = progress * progress * (3 - 2 * progress)
  local movement = self.definition.movement or {}
  MovementManager.move_by(
    self,
    self.hop_dx * (eased_progress - eased_previous),
    self.hop_dground_y * (eased_progress - eased_previous),
    movement
  )
  if progress >= 1 then
    self.hopping = false
  end
end

function Character:update(dt, world)
  local intent = { horizontal = 0, vertical = 0, jump = false }
  if self.controller then
    intent = self.controller:get_intent(self, world, dt)
  end

  self.timer:update(dt)
  if self.flash_remaining > 0 then
    self.flash_remaining = math.max(0, self.flash_remaining - dt)
    self.flash_elapsed = self.flash_elapsed + dt
  end
  if self.facing_enabled and intent.horizontal ~= 0 then
    self.facing = intent.horizontal > 0 and 1 or -1
  end

  local movement_active = (intent.horizontal or 0) ~= 0 or (intent.vertical or 0) ~= 0
  if self.hop_animation then
    local should_hop = intent.jump or (movement_active and (not self.hop_on_press or not self.movement_was_active))
    if should_hop then
      self:begin_hop(intent)
    end
    self:update_hop(dt)
  else
    MovementManager.update(self, intent, self.definition.movement, dt)
  end
  self.animation:update(dt)
  self.movement_was_active = movement_active
end

function Character:get_collision_mask()
  if self.animation:is_playing() then
    return self.animation:get_current_mask()
  end
  return self.asset.image.mask
end

function Character:draw()
  local flashing = self.flash_remaining > 0 and math.floor(self.flash_elapsed * 24) % 2 == 0
  if self.collision_active then
    love.graphics.setColor(1, 0.2, 0.2, 1)
  elseif flashing then
    love.graphics.setColor(1, 0.35, 0.35, 1)
  else
    love.graphics.setColor(1, 1, 1, 1)
  end
  if self.animation:is_playing() then
    self.animation:draw(self.position.x, PositionManager.get_screen_y(self.position), self.scale * self:get_render_facing(), self.scale, self.anchor_x, self.anchor_y)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  love.graphics.draw(self.asset.image.texture, self.position.x, PositionManager.get_screen_y(self.position), 0, self.scale * self:get_render_facing(), self.scale, self.anchor_x, self.anchor_y)
  love.graphics.setColor(1, 1, 1, 1)
end

return Character
