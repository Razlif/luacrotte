-- Minimal deterministic left/right patrol controller.
local PatrolController = {}
PatrolController.__index = PatrolController

function PatrolController.new()
  return setmetatable({ direction = -1 }, PatrolController)
end

function PatrolController:get_intent(character)
  local patrol = character.definition.patrol or {}
  local left = patrol.left or 0
  local right = patrol.right or left
  if character.position.x <= left then self.direction = 1 end
  if character.position.x >= right then self.direction = -1 end
  return { horizontal = self.direction, vertical = 0, jump = false }
end

return PatrolController
