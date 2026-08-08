-- Follows the player while keeping a configurable personal distance.
local FollowEnemyController = {}
FollowEnemyController.__index = FollowEnemyController

function FollowEnemyController.new()
  return setmetatable({
    state = "idle",
    hit_remaining = 0,
    defeated = false
  }, FollowEnemyController)
end

function FollowEnemyController:get_state()
  return self.state
end

function FollowEnemyController:mark_hit(duration)
  if self.defeated then return end
  self.hit_remaining = math.max(self.hit_remaining, duration or 0.25)
  self.state = "hit"
end

function FollowEnemyController:mark_defeated()
  self.defeated = true
  self.hit_remaining = 0
  self.state = "defeated"
end

function FollowEnemyController:get_intent(character, world, dt)
  if self.defeated then
    self.state = "defeated"
    return { horizontal = 0, vertical = 0, jump = false }
  end

  if self.hit_remaining > 0 then
    self.hit_remaining = math.max(0, self.hit_remaining - (dt or 0))
    self.state = "hit"
    return { horizontal = 0, vertical = 0, jump = false }
  end

  local player = world and world.player
  if not player or not player.position then
    self.state = "idle"
    return { horizontal = 0, vertical = 0, jump = false }
  end

  local behavior = character.definition.follow or {}
  local dx = (player.position.x or 0) - (character.position.x or 0)
  local dy = (player.position.ground_y or 0) - (character.position.ground_y or 0)
  local distance = math.sqrt(dx * dx + dy * dy)
  local stop_distance = behavior.stop_distance or behavior.follow_distance or 0

  if distance <= stop_distance then
    self.state = "idle"
    return { horizontal = 0, vertical = 0, jump = false }
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
