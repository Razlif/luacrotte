-- Runtime callback facade. The root main.lua forwards Love callbacks here.
local game_loop = require("game.game_loop")

local Main = {}

function Main.load(...)
  game_loop.load(...)
end

function Main.update(dt)
  game_loop.update(dt)
end

function Main.draw()
  game_loop.draw()
end

function Main.keypressed(key, scancode, isrepeat)
  game_loop.keypressed(key, scancode, isrepeat)
end

function Main.keyreleased(key, scancode)
  game_loop.keyreleased(key, scancode)
end

function Main.mousepressed(x, y, button)
  game_loop.mousepressed(x, y, button)
end

function Main.mousereleased(x, y, button)
  game_loop.mousereleased(x, y, button)
end

function Main.quit()
  game_loop.quit()
end

return Main
