-- Root Love2D entry point. Runtime code lives under game/.
-- Explicit maintenance tools are selected before the gameplay module is
-- loaded, so offline asset analysis never initializes the game runtime.
local generator_mode = false
for _, value in ipairs(arg or {}) do
  if value == "--generate-collision-footprints" then
    generator_mode = true
    break
  end
end

local game
local generator
local debug_config
if generator_mode then
  generator = require("tools.generate_collision_footprints")
else
  game = require("game.main")
  local DebugConfig = require("game.debug_config")
  debug_config = DebugConfig.from_args(arg)
end

function love.load(...)
  if generator_mode then
    local ok, error_message = generator.run(arg)
    if not ok then error(error_message) end
    love.event.quit()
    return
  end
  game.load(debug_config, ...)
end

function love.update(dt)
  if generator_mode then return end
  game.update(dt)
end

function love.draw()
  if generator_mode then return end
  game.draw()
end

function love.keypressed(key, scancode, isrepeat)
  if generator_mode then return end
  game.keypressed(key, scancode, isrepeat)
end

function love.keyreleased(key, scancode)
  if generator_mode then return end
  game.keyreleased(key, scancode)
end

function love.mousepressed(x, y, button)
  if generator_mode then return end
  game.mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
  if generator_mode then return end
  game.mousereleased(x, y, button)
end

function love.quit()
  if generator_mode then return false end
  game.quit()
  -- In LÖVE, returning true aborts the quit event.  Return false so the
  -- window close request is allowed to terminate the process.
  return false
end
