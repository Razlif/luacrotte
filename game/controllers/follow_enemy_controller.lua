-- Follows the player while keeping a configurable personal distance.
local ImpactResponse = require("game.systems.impact_response")

local FollowEnemyController = {}
FollowEnemyController.__index = FollowEnemyController

function FollowEnemyController.new()
  return setmetatable({
    state = "idle",
    hit_remaining = 0,
    defeated = false,
    impact_entity = nil,
    impact_data = nil,
    recovery_remaining = 0,
    impact_elapsed = 0,
    impact_recovery_time = 0
  }, FollowEnemyController)
end

local function zero_intent()
  return { horizontal = 0, vertical = 0, jump = false }
end

function FollowEnemyController:get_state()
  return self.state
end

function FollowEnemyController:mark_hit(duration)
  if self.defeated then return end
  self.hit_remaining = math.max(self.hit_remaining, duration or 0.25)
  if not self:is_impact_locked() then
    self.state = "hit_light"
  end
end

function FollowEnemyController:mark_defeated()
  self.defeated = true
  self.hit_remaining = 0
  self.impact_entity = nil
  self.impact_data = nil
  self.recovery_remaining = 0
  self.impact_elapsed = 0
  self.impact_recovery_time = 0
  self.state = "defeated"
end

function FollowEnemyController:begin_impact(response, character)
  if self.defeated or self:is_impact_locked() then
    return false
  end
  self.impact_entity = character or self.impact_entity
  if not self.impact_entity then
    return false
  end
  self.impact_data = ImpactResponse.apply(self.impact_entity, response or {})
  self.recovery_remaining = 0
  self.impact_elapsed = 0
  self.impact_recovery_time = response
    and response.state == "drift_orbit"
    and (response.recovery_time or response.duration or 0.35)
    or (response and response.duration or 0.35)
  self.hit_remaining = 0
  if response and (response.state == "drift_orbit"
      or math.abs(self.impact_data.yaw_speed or 0) >= math.rad(180)) then
    self.state = "hit_spinning"
  else
    self.state = "hit_light"
  end
  return true
end

function FollowEnemyController:update_impact(dt)
  if self.defeated then
    self.state = "defeated"
    return false
  end
  if self.state == "hit_light" or self.state == "hit_spinning" then
    if not self.impact_entity then
      self.hit_remaining = math.max(0, self.hit_remaining - (dt or 0))
      if self.hit_remaining > 0 then
        return true
      end
      self.recovery_remaining = 0.35
      self.state = "recovering"
      return true
    end
    if ImpactResponse.is_active(self.impact_entity) then
      self.impact_elapsed = self.impact_elapsed + (dt or 0)
      ImpactResponse.update(self.impact_entity, dt)
      self.impact_data = self.impact_entity.impact_response
      return true
    end
    self.impact_data = nil
    self.recovery_remaining = math.max(0, self.impact_recovery_time - self.impact_elapsed)
    self.state = "recovering"
    return true
  end
  if self.state == "recovering" then
    self.recovery_remaining = math.max(0, self.recovery_remaining - (dt or 0))
    if self.recovery_remaining <= 0 then
      self.impact_entity = nil
      self.impact_elapsed = 0
      self.impact_recovery_time = 0
      self.state = "pursuing"
    end
    return true
  end
  return false
end

function FollowEnemyController:is_impact_locked()
  return self.state == "hit_light"
    or self.state == "hit_spinning"
    or self.state == "recovering"
end

function FollowEnemyController:get_spin_phase()
  return self.impact_entity and self.impact_entity.impact_yaw or 0
end

function FollowEnemyController:get_impact_velocity()
  if not self.impact_entity then
    return { x = 0, y = 0 }
  end
  return {
    x = self.impact_entity.impact_velocity_x or 0,
    y = self.impact_entity.impact_velocity_y or 0
  }
end

function FollowEnemyController:get_intent(character, world, dt)
  if self.defeated then
    self.state = "defeated"
    return zero_intent()
  end

  if self:is_impact_locked() then
    return zero_intent()
  end

  if self.hit_remaining > 0 then
    self.hit_remaining = math.max(0, self.hit_remaining - (dt or 0))
    self.state = "hit_light"
    return zero_intent()
  end

  local player = world and world.player
  if not player or not player.position then
    self.state = "idle"
    return zero_intent()
  end

  local behavior = character.definition.follow or {}
  local dx = (player.position.x or 0) - (character.position.x or 0)
  local dy = (player.position.ground_y or 0) - (character.position.ground_y or 0)
  local distance = math.sqrt(dx * dx + dy * dy)
  local stop_distance = behavior.stop_distance or behavior.follow_distance or 0

  if distance <= stop_distance then
    self.state = "idle"
    return zero_intent()
  end

  self.state = "pursuing"
  local length = math.max(distance, 0.0001)
  local speed = behavior.speed or (character.definition.movement or {}).speed
    or (character.definition.movement or {}).horizontal_speed or 0
  return {
    horizontal = dx / length,
    vertical = dy / length,
    horizontal_speed = speed,
    vertical_speed = speed,
    jump = false
  }
end

return FollowEnemyController
