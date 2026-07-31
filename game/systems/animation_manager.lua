-- Tracks and updates the active animation and frame for an entity.
local AnimationManager = {}
AnimationManager.__index = AnimationManager

function AnimationManager.new(animations)
  local manager = setmetatable({
    animations = animations or {},
    current_name = nil,
    current_frame = 1,
    elapsed = 0,
    playing = false
  }, AnimationManager)
  for _, animation in pairs(manager.animations) do
    animation.quads = {}
    for frame = 1, animation.frame_count do
      animation.quads[frame] = love.graphics.newQuad(
        (frame - 1) * animation.frame_width,
        0,
        animation.frame_width,
        animation.frame_height,
        animation.texture:getWidth(),
        animation.texture:getHeight()
      )
    end
  end
  return manager
end

function AnimationManager:play(name)
  local animation = self.animations[name]
  assert(animation, "Unknown animation: " .. tostring(name))
  self.current_name = name
  self.current_frame = 1
  self.elapsed = 0
  self.playing = true
end

function AnimationManager:stop()
  self.playing = false
  self.current_name = nil
  self.current_frame = 1
  self.elapsed = 0
end

function AnimationManager:is_playing()
  return self.playing
end

function AnimationManager:get_current_frame()
  return self.current_frame
end

function AnimationManager:get_current_mask()
  local animation = self.animations[self.current_name]
  return animation and animation.mask_frames and animation.mask_frames[self.current_frame]
end

function AnimationManager:update(dt)
  if not self.playing then
    return
  end
  local animation = self.animations[self.current_name]
  local frame_duration = 1 / animation.fps
  self.elapsed = self.elapsed + dt

  while self.elapsed >= frame_duration do
    self.elapsed = self.elapsed - frame_duration
    self.current_frame = self.current_frame + 1
    if self.current_frame > animation.frame_count then
      if animation.loop then
        self.current_frame = 1
      else
        self.current_frame = animation.frame_count
        self.playing = false
        return
      end
    end
  end
end

function AnimationManager:draw(x, y, scale_x, scale_y, anchor_x, anchor_y, rotation)
  if not self.playing then
    return
  end
  local animation = self.animations[self.current_name]
  local quad = animation.quads[self.current_frame]
  love.graphics.draw(animation.texture, quad, x, y, rotation or 0, scale_x, scale_y, anchor_x, anchor_y)
end

function AnimationManager:draw_frame(frame, x, y, scale_x, scale_y, anchor_x, anchor_y, rotation)
  if not self.current_name then
    return
  end
  local animation = self.animations[self.current_name]
  local selected_frame = math.max(1, math.min(animation.frame_count, frame or self.current_frame))
  local quad = animation.quads[selected_frame]
  love.graphics.draw(animation.texture, quad, x, y, rotation or 0, scale_x, scale_y, anchor_x, anchor_y)
end

return AnimationManager
