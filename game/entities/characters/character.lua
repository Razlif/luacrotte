-- Shared runtime character behavior.
local AnimationManager = require("game.systems.animation_manager")
local ControllerFactory = require("game.controllers.controller_factory")
local MovementManager = require("game.systems.movement_manager")
local PositionManager = require("game.systems.position_manager")
local TimerManager = require("game.systems.timer_manager")
local ImpactResponse = require("game.systems.impact_response")
local ImpactRenderer = require("game.systems.impact_renderer")

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
    flash_elapsed = 0,
    defeat_elapsed = nil,
    defeat_delay = 0,
    defeat_fade_time = 0,
    impact_velocity_x = 0,
    impact_velocity_y = 0,
    impact_yaw = 0,
    impact_yaw_speed = 0,
    impact_remaining = 0,
    impact_duration = 0,
    impact_mode = nil,
    impact_direction_x = nil,
    impact_direction_y = nil,
    last_impact_source = nil,
    last_impact_target = nil,
    last_impact_state = nil,
    last_impact_direction_x = nil,
    last_impact_direction_y = nil,
    last_impact_yaw_speed = 0,
    impact_speed = 0,
    knockback_speed = 0,
    separation_distance = 0,
    combat_state = nil,
    combat_source = nil
  }, Character)

  character.behavior_state = character.controller and character.controller.get_state
    and character.controller:get_state() or nil

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
  if self.defeat_elapsed then
    self.defeat_elapsed = self.defeat_elapsed + dt
    if self.defeat_elapsed >= self.defeat_delay and self.behavior_state ~= "defeated" then
      self:mark_defeated()
    end
    self.animation:update(dt)
    return
  end

  self.timer:update(dt)
  if self.flash_remaining > 0 then
    self.flash_remaining = math.max(0, self.flash_remaining - dt)
    self.flash_elapsed = self.flash_elapsed + dt
  end

  local intent = { horizontal = 0, vertical = 0, jump = false }
  if self.controller then
    intent = self.controller:get_intent(self, world, dt)
    if self.controller.get_state then
      self.behavior_state = self.controller:get_state()
    end
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

  -- Generic impact is deliberately applied after normal movement. Enemy
  -- controllers return zero intent while locked, while future hero impacts
  -- can reuse this same pipeline without replacing the controller contract.
  if self.controller and self.controller.is_impact_locked and self.controller:is_impact_locked() then
    self.controller:update_impact(dt)
    self.behavior_state = self.controller.get_state and self.controller:get_state() or "hit_light"
  elseif ImpactResponse.is_active(self) then
    ImpactResponse.update(self, dt)
    self.behavior_state = "hit_light"
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
  if self:is_defeat_complete() then
    return
  end
  local defeat_alpha = 1
  local defeat_flicker = false
  if self.defeat_elapsed then
    defeat_flicker = math.floor(self.defeat_elapsed * 28) % 2 == 0
    if self.defeat_elapsed > self.defeat_delay then
      defeat_alpha = 1 - (self.defeat_elapsed - self.defeat_delay) / math.max(0.001, self.defeat_fade_time)
    end
  end
  local flashing = self.flash_remaining > 0 and math.floor(self.flash_elapsed * 24) % 2 == 0
  if self.collision_active then
    love.graphics.setColor(1, 0.2, 0.2, 1)
  elseif flashing or defeat_flicker then
    love.graphics.setColor(1, 0.35, 0.35, 1)
  else
    love.graphics.setColor(1, 1, 1, defeat_alpha)
  end
  local transform = ImpactRenderer.get_transform(self)
  if self.animation:is_playing() then
    self.animation:draw(self.position.x, PositionManager.get_screen_y(self.position), transform.scale_x, transform.scale_y, self.anchor_x, self.anchor_y)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  love.graphics.draw(self.asset.image.texture, self.position.x, PositionManager.get_screen_y(self.position), 0, transform.scale_x, transform.scale_y, self.anchor_x, self.anchor_y)
  love.graphics.setColor(1, 1, 1, 1)
end

function Character:apply_combat_impact(response)
  local controller_started = false
  if self.controller and self.controller.begin_impact then
    controller_started = self.controller:begin_impact(response, self)
  else
    ImpactResponse.apply(self, response)
  end
  self:hit_flash(response.hit_pause or response.duration or 0.25)
  self.behavior_state = controller_started and self.controller:get_state() or "hit_light"
end

function Character:mark_hit(duration)
  if self.controller and self.controller.mark_hit then
    self.controller:mark_hit(duration)
  end
  self:hit_flash(duration)
  self.behavior_state = self.controller and self.controller.get_state
    and self.controller:get_state() or "hit"
end

function Character:mark_defeated()
  if self.controller and self.controller.mark_defeated then
    self.controller:mark_defeated()
  end
  self.behavior_state = "defeated"
end

function Character:begin_defeat(delay, fade_time)
  if self.defeat_elapsed then return end
  self.defeat_elapsed = 0
  self.defeat_delay = delay or 0.25
  self.defeat_fade_time = fade_time or 0.8
  if self.controller and self.controller.mark_hit then
    self.controller:mark_hit(self.defeat_delay)
  end
  self.behavior_state = "hit"
end

function Character:is_defeat_complete()
  return self.defeat_elapsed ~= nil
    and self.defeat_elapsed >= self.defeat_delay + self.defeat_fade_time
end

return Character
