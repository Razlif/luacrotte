-- Creates controller instances selected by character data.
local PlayerController = require("game.controllers.player_controller")
local BasicEnemyController = require("game.controllers.basic_enemy_controller")
local PatrolController = require("game.controllers.patrol_controller")
local FollowEnemyController = require("game.controllers.follow_enemy_controller")

local ControllerFactory = {}

function ControllerFactory.create(name)
  if not name then
    return nil
  end
  if name == "player" then
    return PlayerController.new()
  end
  if name == "basic_enemy" then
    return BasicEnemyController.new()
  end
  if name == "patrol" then
    return PatrolController.new()
  end
  if name == "follow_enemy" then
    return FollowEnemyController.new()
  end
  error("Unknown controller: " .. tostring(name))
end

return ControllerFactory
