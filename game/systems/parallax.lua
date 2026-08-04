-- Draws optional background layers at camera-relative speeds.
local ParallaxManager = {}
ParallaxManager.__index = ParallaxManager

function ParallaxManager.new(layers)
  return setmetatable({ layers = layers or {}, camera = nil, loaded = {} }, ParallaxManager)
end

function ParallaxManager:set_camera(camera)
  self.camera = camera
end

function ParallaxManager:update(_)
  -- Layers are static images for now; camera position is read during draw.
end

function ParallaxManager:load_layer(layer)
  if self.loaded[layer.id] then
    return self.loaded[layer.id]
  end
  if not love.filesystem.getInfo(layer.image_path) then
    print("Parallax layer missing, skipped: " .. tostring(layer.image_path))
    self.loaded[layer.id] = false
    return nil
  end
  -- Load through ImageData, matching the validated runtime asset loader path.
  -- This avoids decoder differences for promoted PNGs with embedded metadata.
  local image_data = love.image.newImageData(layer.image_path)
  local image = love.graphics.newImage(image_data)
  image:setFilter("nearest", "nearest")
  image:setWrap("clamp", "clamp")
  self.loaded[layer.id] = image
  return image
end

function ParallaxManager:draw()
  if not self.camera then
    return
  end
  for _, layer in ipairs(self.layers) do
    local image = self:load_layer(layer)
    if image then
      if layer.fit == "track" then
        -- A track is a sequence of world-space tiles.  It is deliberately
        -- separate from cover backgrounds: camera motion reveals later tiles
        -- instead of re-centering one image under every viewport.
        local track = layer.track or {}
        local count = track.count or 1
        local tile_width = track.tile_width or image:getWidth()
        local origin_x = track.origin_x or 0
        local origin_y = track.origin_y or 0
        for index = 0, count - 1 do
          love.graphics.draw(image, origin_x + index * tile_width, origin_y)
        end
      elseif layer.fit == "cover" then
        -- Backgrounds are presentation layers: fit them to the camera viewport
        -- instead of leaving them anchored at world origin, where camera motion
        -- exposes empty space. Cover preserves aspect ratio and center-crops.
        local viewport_width = self.camera.width / self.camera.zoom
        local viewport_height = self.camera.height / self.camera.zoom
        local scale = math.max(viewport_width / image:getWidth(), viewport_height / image:getHeight())
        local draw_width = image:getWidth() * scale
        local draw_height = image:getHeight() * scale
        local draw_x = self.camera.x + (viewport_width - draw_width) / 2
        local draw_y = self.camera.y + (viewport_height - draw_height) / 2
        love.graphics.draw(image, draw_x, draw_y, 0, scale, scale)
      else
      local speed_x = layer.speed_x or 1
      local speed_y = layer.speed_y or 1
      local x = self.camera.x * (1 - speed_x)
      local y = self.camera.y * (1 - speed_y)
      local width = image:getWidth()
      local height = image:getHeight()
      local start_x = layer.repeat_x and x - (x % width) - width or x
      local end_x = layer.repeat_x and self.camera.x + self.camera.width + width or x
      local start_y = layer.repeat_y and y - (y % height) - height or y
      local end_y = layer.repeat_y and self.camera.y + self.camera.height + height or y
      local draw_x = start_x
      while draw_x <= end_x do
        local draw_y = start_y
        while draw_y <= end_y do
          love.graphics.draw(image, draw_x, draw_y)
          draw_y = draw_y + height
        end
        draw_x = draw_x + width
      end
      end
    end
  end
end

return ParallaxManager
