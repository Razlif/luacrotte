-- Root Love2D entry point. Runtime code lives under game/.
local game = require("game.main")
local DebugConfig = require("game.debug_config")
local debug_config = DebugConfig.from_args(arg)

function love.load(...)
  game.load(debug_config, ...)
end

function love.update(dt)
  game.update(dt)
end

function love.draw()
  game.draw()
end

function love.keypressed(key, scancode, isrepeat)
  game.keypressed(key, scancode, isrepeat)
end

function love.keyreleased(key, scancode)
  game.keyreleased(key, scancode)
end

function love.mousepressed(x, y, button)
  game.mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
  game.mousereleased(x, y, button)
end

function love.quit()
  game.quit()
  -- In LÖVE, returning true aborts the quit event.  Return false so the
  -- window close request is allowed to terminate the process.
  return false
end
