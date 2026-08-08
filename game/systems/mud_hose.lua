-- V1 ballistic mud stream: flying blobs become temporary ground traces.
local PositionManager = require("game.systems.position_manager")

local MudHose = {}
MudHose.__index = MudHose

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local FACING_ANGLES = {
  right = 0,
  down_right = math.pi / 4,
  down = math.pi / 2,
  down_left = math.pi * 3 / 4,
  left = math.pi,
  up_left = -math.pi * 3 / 4,
  up = -math.pi / 2,
  up_right = -math.pi / 4
}

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
    last_launch = nil,
    last_impact = nil,
    last_enemy_impact = false,
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
  self.last_impact = nil
  self.last_enemy_impact = false
end

function MudHose:spawn(hero)
  if #self.projectiles >= self.definition.max_projectiles then return end
  local motion = hero.motocrotte_motion or {}
  -- Follow the rendered eight-direction animation, not travel velocity. This
  -- remains correct while braking, drifting, or spinning in place.
  local facing_name = motion.directional_direction
  local heading = FACING_ANGLES[facing_name] or hero.visual_yaw or motion.heading or 0
  local speed = self.definition.launch_speed
  local planar_speed = speed * math.cos(self.definition.elevation)
  local inheritance = self.definition.inherit_velocity_factor or 0
  local inherited_vx = (motion.vx or 0) * inheritance
  local inherited_vy = (motion.vy or 0) * inheritance
  local frame = self.next_frame
  self.next_frame = self.next_frame % self.animation.frame_count + 1
  self.projectiles[#self.projectiles + 1] = {
    x = hero.position.x,
    ground_y = hero.position.ground_y,
    z = self.definition.muzzle_height,
    vx = inherited_vx + math.cos(heading) * planar_speed,
    vy = inherited_vy + math.sin(heading) * planar_speed,
    vz = speed * math.sin(self.definition.elevation),
    frame = frame,
    age = 0,
    facing = facing_name or "unknown"
  }
  self.last_launch = {
    facing = facing_name or "unknown",
    heading = heading,
    inherited_vx = inherited_vx,
    inherited_vy = inherited_vy,
    vx = inherited_vx + math.cos(heading) * planar_speed,
    vy = inherited_vy + math.sin(heading) * planar_speed
  }
end

function MudHose:impact(projectile, target)
  self.last_impact = target and "enemy" or "ground"
  if target then self.last_enemy_impact = true end
  if #self.residues >= self.definition.max_residues then table.remove(self.residues, 1) end
  self.residues[#self.residues + 1] = {
    x = projectile.x,
    ground_y = projectile.ground_y,
    frame = projectile.frame,
    age = 0,
    impact_kind = target and "enemy" or "ground"
  }
  if target and target.begin_defeat then
    target:begin_defeat(self.definition.enemy_hit_delay, self.definition.enemy_fade_time)
  end
end

function MudHose:projectile_hits_target(projectile, target)
  if target.defeat_elapsed or target.behavior_state == "defeated" then return false end
  local dx = projectile.x - target.position.x
  local dy = projectile.ground_y - target.position.ground_y
  local radius = self.definition.enemy_hit_radius * (target.scale or 1)
  return dx * dx + dy * dy <= radius * radius
    and projectile.z <= self.definition.enemy_hit_height * (target.scale or 1)
end

function MudHose:update(hero, firing, dt, targets)
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
    local target = nil
    for _, candidate in ipairs(targets or {}) do
      if self:projectile_hits_target(projectile, candidate) then
        target = candidate
        break
      end
    end
    if target or projectile.z <= 0 or projectile.age >= self.definition.projectile_lifetime then
      projectile.z = 0
      self:impact(projectile, target)
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
    firing = self.was_firing,
    last_launch = self.last_launch,
    last_impact = self.last_impact,
    enemy_hit = self.last_enemy_impact
  }
end

return MudHose
