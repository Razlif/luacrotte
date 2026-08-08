-- Love2D configuration kept with the rest of the game code.
local Config = {}

function Config.configure(t)
  t.identity = "love2d_toolkit"
  t.version = "11.5"
  t.window.title = "Love2D Toolkit Playground"
  t.window.width = 1280
  t.window.height = 720
  t.window.resizable = true
  t.window.vsync = 1
end

return Config
