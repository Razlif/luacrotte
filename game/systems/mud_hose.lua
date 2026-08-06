-- V1 ballistic mud stream: flying blobs become temporary ground traces.
local PositionManager = require("game.systems.position_manager")

local MudHose = {}
MudHose.__index = MudHose

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function MudHose.new(definition, asset)
  local animation = assert(asset.animations[definition.animation], "Mud hose animation is missing")
  local self = setmetatable({
    definition = definition,
    asset = asset,
    animation = animation,
    projectiles = {},
    residues = {},
    emission_distance = definition.emission_spacing,
    next_frame = 1,
    was_firing = false,
    quads = {}
  }, MudHose)
  for frame = 1, animation.frame_count do
    self.quads[frame] = love.graphics.newQuad(
      (frame - 1) * animation.frame_width, 0,
      animation.frame_width, animation.frame_height,
      animation.texture:getWidth(), animation.texture:getHeight()
    )
  end
  return self
end

function MudHose:reset()
  self.projectiles = {}
  self.residues = {}
  self.emission_distance = self.definition.emission_spacing
  self.next_frame = 1
  self.was_firing = false
end

function MudHose:spawn(hero)
  if #self.projectiles >= self.definition.max_projectiles then return end
  local motion = hero.motocrotte_motion or {}
  local heading = motion.heading or hero.visual_yaw or 0
  local speed = self.definition.launch_speed
  local planar_speed = speed * math.cos(self.definition.elevation)
  local frame = self.next_frame
  self.next_frame = self.next_frame % self.animation.frame_count + 1
  self.projectiles[#self.projectiles + 1] = {
    x = hero.position.x,
    ground_y = hero.position.ground_y,
    z = self.definition.muzzle_height,
    vx = math.cos(heading) * planar_speed,
    vy = math.sin(heading) * planar_speed,
    vz = speed * math.sin(self.definition.elevation),
    frame = frame,
    age = 0
  }
end

function MudHose:impact(projectile)
  if #self.residues >= self.definition.max_residues then table.remove(self.residues, 1) end
  self.residues[#self.residues + 1] = {
    x = projectile.x,
    ground_y = projectile.ground_y,
    frame = projectile.frame,
    age = 0
  }
end

function MudHose:update(hero, firing, dt)
  if not self.definition.enabled then return end
  if firing and not self.was_firing then self.emission_distance = self.definition.emission_spacing end
  if firing then
    self.emission_distance = self.emission_distance + self.definition.launch_speed * dt
    while self.emission_distance >= self.definition.emission_spacing do
      self.emission_distance = self.emission_distance - self.definition.emission_spacing
      self:spawn(hero)
    end
  end
  self.was_firing = firing

  for index = #self.projectiles, 1, -1 do
    local projectile = self.projectiles[index]
    projectile.age = projectile.age + dt
    projectile.x = projectile.x + projectile.vx * dt
    projectile.ground_y = projectile.ground_y + projectile.vy * dt
    projectile.z = projectile.z + projectile.vz * dt
    projectile.vz = projectile.vz - self.definition.gravity * dt
    if projectile.z <= 0 or projectile.age >= self.definition.projectile_lifetime then
      projectile.z = 0
      self:impact(projectile)
      table.remove(self.projectiles, index)
    end
  end

  local residue_lifetime = self.definition.residue_hold_time + self.definition.residue_fade_time
  for index = #self.residues, 1, -1 do
    local residue = self.residues[index]
    residue.age = residue.age + dt
    if residue.age >= residue_lifetime then table.remove(self.residues, index) end
  end
end

function MudHose:draw_residues()
  for _, residue in ipairs(self.residues) do
    local fade_age = residue.age - self.definition.residue_hold_time
    local alpha = fade_age <= 0 and 1 or 1 - fade_age / self.definition.residue_fade_time
    local scale = self.definition.residue_scale
    love.graphics.setColor(1, 1, 1, clamp(alpha, 0, 1))
    love.graphics.draw(self.animation.texture, self.quads[residue.frame], residue.x, residue.ground_y, 0, scale, scale, self.animation.frame_width / 2, self.animation.frame_height / 2)
  end
  -- Love2D draw color is global state. Restore it before the hero renderer so
  -- a fading trace never makes unrelated gameplay art transparent.
  love.graphics.setColor(1, 1, 1, 1)
end

function MudHose:draw_projectiles()
  local scale = self.definition.projectile_scale
  love.graphics.setColor(1, 1, 1, 1)
  for _, projectile in ipairs(self.projectiles) do
    love.graphics.draw(self.animation.texture, self.quads[projectile.frame], projectile.x, projectile.ground_y - projectile.z, 0, scale, scale, self.animation.frame_width / 2, self.animation.frame_height / 2)
  end
end

function MudHose:debug_snapshot()
  return {
    projectiles = #self.projectiles,
    residues = #self.residues,
    next_frame = self.next_frame,
    firing = self.was_firing
  }
end

return MudHose
