-- Scene-owned gravityless 2D physics service.
--
-- Phase 3 deliberately does not change gameplay movement yet. Callers provide
-- stable base-footprint dimensions and velocities; later phases will migrate
-- the hero and enemy movement systems to this service.
local Footprints = require("game_data.collision_footprints")

local PhysicsCollisionWorld = {}
PhysicsCollisionWorld.__index = PhysicsCollisionWorld

local function entity_id(entity)
  return entity and (entity.id
    or (entity.definition and entity.definition.runtime_id)
    or (entity.definition and entity.definition.asset_id)
    or entity.asset_id) or nil
end

local function numeric(value, fallback)
  value = tonumber(value)
  if value == nil then return fallback end
  return value
end

local function copy_contact_user_data(fixture)
  local data = fixture and fixture:getUserData() or nil
  if type(data) ~= "table" then
    return { id = tostring(data or "fixture") }
  end
  return {
    id = data.id,
    kind = data.kind,
    -- Keep contact events data-only. The live entity reference is available
    -- through the physics body registry and must not leak into QA JSON, where
    -- Character/Texture userdata would be non-serializable.
    entity_id = data.entity and entity_id(data.entity) or nil,
    boundary = data.boundary
  }
end

local function resolve_footprint(entity, options)
  options = options or {}
  if options.footprint then return options.footprint end
  if entity.physics_footprint then return entity.physics_footprint end
  local id = entity_id(entity)
  if entity.definition and entity.definition.asset_id then
    id = entity.definition.asset_id
  end
  return id and Footprints[id] or nil
end

local function resolve_physics_config(entity, options)
  options = options or {}
  local definition = entity.definition or {}
  local configured = definition.physics or (definition.collision and definition.collision.physics) or {}
  local bullet_requested = options.bullet ~= nil and options.bullet or configured.bullet == true
  local high_speed = options.high_speed == true
    or entity.physics_high_speed == true
    or configured.high_speed == true
  return {
    body_type = options.body_type or configured.body_type or "dynamic",
    fixed_rotation = options.fixed_rotation ~= nil and options.fixed_rotation or configured.fixed_rotation ~= false,
    -- Continuous collision is reserved for explicitly high-speed entities.
    bullet = bullet_requested == true and high_speed,
    high_speed = high_speed,
    friction = numeric(options.friction, numeric(configured.friction, 0)),
    restitution = numeric(options.restitution, numeric(configured.restitution, 0)),
    density = numeric(options.density, numeric(configured.density, 1))
  }
end

function PhysicsCollisionWorld.new(options)
  options = options or {}
  return setmetatable({
    fixed_dt = numeric(options.fixed_timestep or options.fixed_dt, 1 / 60),
    max_substeps = math.max(1, math.floor(numeric(options.max_substeps, 4))),
    gravity_x = numeric(options.gravity_x, 0),
    gravity_y = numeric(options.gravity_y, 0),
    enabled = options.enabled ~= false,
    world = nil,
    scope = nil,
    boundary_enabled = false,
    boundary_body = nil,
    boundary_fixtures = {},
    boundary_bounds = nil,
    accumulator = 0,
    dropped_time = 0,
    bodies = {},
    contacts = {},
    step_count = 0
  }, PhysicsCollisionWorld)
end

local function valid_bounds(bounds)
  return type(bounds) == "table"
    and tonumber(bounds.left) ~= nil
    and tonumber(bounds.right) ~= nil
    and tonumber(bounds.top) ~= nil
    and tonumber(bounds.bottom) ~= nil
    and tonumber(bounds.right) > tonumber(bounds.left)
    and tonumber(bounds.bottom) > tonumber(bounds.top)
end

function PhysicsCollisionWorld:_destroy_boundaries()
  if self.boundary_body then
    self.boundary_body:destroy()
  end
  self.boundary_body = nil
  self.boundary_fixtures = {}
  self.boundary_bounds = nil
end

function PhysicsCollisionWorld:_create_boundaries(bounds)
  self:_destroy_boundaries()
  if not self.world or not self.boundary_enabled or not valid_bounds(bounds) then return false end

  local left = tonumber(bounds.left)
  local right = tonumber(bounds.right)
  local top = tonumber(bounds.top)
  local bottom = tonumber(bounds.bottom)
  local body = love.physics.newBody(self.world, 0, 0, "static")
  body:setUserData({ id = "physics_boundary", kind = "physics_boundary" })
  local edges = {
    { id = "top", x1 = left, y1 = top, x2 = right, y2 = top },
    { id = "bottom", x1 = left, y1 = bottom, x2 = right, y2 = bottom },
    { id = "left", x1 = left, y1 = top, x2 = left, y2 = bottom },
    { id = "right", x1 = right, y1 = top, x2 = right, y2 = bottom }
  }
  for _, edge in ipairs(edges) do
    local shape = love.physics.newEdgeShape(edge.x1, edge.y1, edge.x2, edge.y2)
    local fixture = love.physics.newFixture(body, shape, 1)
    fixture:setFriction(0)
    fixture:setRestitution(0)
    fixture:setUserData({
      id = "physics_boundary:" .. edge.id,
      kind = "physics_boundary",
      boundary = edge.id
    })
    self.boundary_fixtures[#self.boundary_fixtures + 1] = fixture
  end
  self.boundary_body = body
  self.boundary_bounds = {
    left = left, right = right, top = top, bottom = bottom
  }
  return true
end

-- Replace the active static boundary set when a Playground experiment changes
-- its movement envelope. Entity-level bounds remain available as a fallback
-- for perspective cones and compatibility callers.
function PhysicsCollisionWorld:set_boundaries(bounds)
  if not self.world then return false end
  if bounds == false then
    self:_destroy_boundaries()
    return true
  end
  return self:_create_boundaries(bounds)
end

function PhysicsCollisionWorld:_queue_contact(phase, fixture_a, fixture_b, contact, impulses)
  local data_a = copy_contact_user_data(fixture_a)
  local data_b = copy_contact_user_data(fixture_b)
  local normal_x, normal_y = 0, 0
  if contact and contact.getNormal then
    normal_x, normal_y = contact:getNormal()
  end
  local velocity_a_x, velocity_a_y = 0, 0
  local velocity_b_x, velocity_b_y = 0, 0
  if fixture_a and fixture_a.getBody then
    velocity_a_x, velocity_a_y = fixture_a:getBody():getLinearVelocity()
  end
  if fixture_b and fixture_b.getBody then
    velocity_b_x, velocity_b_y = fixture_b:getBody():getLinearVelocity()
  end
  local relative_velocity = {
    x = velocity_a_x - velocity_b_x,
    y = velocity_a_y - velocity_b_y
  }
  local boundary_contact = data_a.kind == "physics_boundary" or data_b.kind == "physics_boundary"
  self.contacts[#self.contacts + 1] = {
    phase = phase,
    kind = "physics_base",
    source_id = data_a.id,
    target_id = data_b.id,
    source = data_a,
    target = data_b,
    collision_type = boundary_contact and "boundary" or "physics_base",
    blocking = phase ~= "end",
    normal = { x = normal_x, y = normal_y },
    normal_impulse = impulses and impulses.normal or 0,
    tangent_impulse = impulses and impulses.tangent or 0,
    step = self.step_count,
    contact = {
      collision_type = boundary_contact and "boundary" or "base",
      normal = { x = normal_x, y = normal_y },
      penetration = 0,
      relative_velocity = relative_velocity
    }
  }
end

function PhysicsCollisionWorld:begin_scope(name, options)
  assert(type(name) == "string" and name ~= "", "Physics scope name is required")
  if self.world then self:end_scope(self.scope) end
  options = options or {}
  local physics = options.physics or options
  self.scope = name
  self.enabled = physics.enabled ~= false
  self.fixed_dt = numeric(physics.fixed_timestep or physics.fixed_dt, self.fixed_dt)
  self.max_substeps = math.max(1, math.floor(numeric(physics.max_substeps, self.max_substeps)))
  self.gravity_x = numeric(physics.gravity_x, self.gravity_x)
  self.gravity_y = numeric(physics.gravity_y, self.gravity_y)
  self.boundary_enabled = self.enabled and physics.bounds ~= false
  self.accumulator = 0
  self.dropped_time = 0
  self.step_count = 0
  self.bodies = {}
  self.contacts = {}
  self.boundary_body = nil
  self.boundary_fixtures = {}
  self.boundary_bounds = nil
  self.world = love.physics.newWorld(self.gravity_x, self.gravity_y, true)
  self.world:setCallbacks(
    function(fixture_a, fixture_b, contact)
      self:_queue_contact("begin", fixture_a, fixture_b, contact)
    end,
    function(fixture_a, fixture_b, contact)
      self:_queue_contact("end", fixture_a, fixture_b, contact)
    end,
    nil,
    function(fixture_a, fixture_b, contact, normal_impulse, tangent_impulse)
      self:_queue_contact("post_solve", fixture_a, fixture_b, contact, {
        normal = normal_impulse or 0,
        tangent = tangent_impulse or 0
      })
    end
  )
  if self.boundary_enabled then
    self:_create_boundaries(physics.bounds)
  end
end

function PhysicsCollisionWorld:add_entity(entity, options)
  assert(self.world, "Physics world is not active")
  assert(entity and entity.position, "Physics entity and position are required")
  options = options or {}
  local id = entity_id(entity)
  assert(id, "Physics entity id is required")
  local footprint = resolve_footprint(entity, options)
  assert(footprint and footprint.width and footprint.height,
    "Physics footprint is required for " .. tostring(id))
  if self.bodies[id] then self:remove_entity(id) end

  local config = resolve_physics_config(entity, options)
  local scale = numeric(options.scale, numeric(entity.scale, 1))
  local width = numeric(footprint.width, 0) * scale
  local height = numeric(footprint.height, 0) * scale
  assert(width > 0 and height > 0, "Physics footprint must have positive dimensions for " .. tostring(id))
  local offset_x = numeric(footprint.offset_x, 0) * scale
  local offset_y = numeric(footprint.offset_y, 0) * scale
  local body = love.physics.newBody(
    self.world,
    numeric(entity.position.x, 0) + offset_x,
    numeric(entity.position.ground_y, 0) + offset_y,
    config.body_type
  )
  body:setUserData({ id = id, entity = entity })
  body:setFixedRotation(config.fixed_rotation)
  body:setBullet(config.bullet)
  local shape = love.physics.newRectangleShape(width, height)
  local fixture = love.physics.newFixture(body, shape, config.density)
  fixture:setFriction(config.friction)
  fixture:setRestitution(config.restitution)
  fixture:setUserData({ id = id, entity = entity, kind = "base_footprint" })
  self.bodies[id] = {
    id = id,
    entity = entity,
    body = body,
    fixture = fixture,
    shape = shape,
    footprint = footprint,
    scale = scale,
    width = width,
    height = height,
    offset_x = offset_x,
    offset_y = offset_y,
    bullet = config.bullet,
    high_speed = config.high_speed,
    bounds = options.bounds
  }
  entity.physics_body = body
  entity.physics_fixture = fixture
  return body, fixture
end

function PhysicsCollisionWorld:set_bounds(entity_or_id, bounds)
  local id = type(entity_or_id) == "table" and entity_id(entity_or_id) or entity_or_id
  local record = id and self.bodies[id]
  if not record then return false end
  record.bounds = bounds
  return true
end

function PhysicsCollisionWorld:get_body(entity_or_id)
  local id = type(entity_or_id) == "table" and entity_id(entity_or_id) or entity_or_id
  local record = id and self.bodies[id]
  return record and record.body or nil
end

function PhysicsCollisionWorld:set_velocity(entity_or_id, velocity_x, velocity_y)
  local id = type(entity_or_id) == "table" and entity_id(entity_or_id) or entity_or_id
  local record = id and self.bodies[id]
  if not record then return false end
  record.body:setLinearVelocity(velocity_x or 0, velocity_y or 0)
  return true
end

function PhysicsCollisionWorld:apply_velocities(commands)
  for entity_or_id, velocity in pairs(commands or {}) do
    self:set_velocity(entity_or_id, velocity.x or velocity.vx or 0, velocity.y or velocity.vy or 0)
  end
end

function PhysicsCollisionWorld:sync_entity(entity_or_id)
  local id = type(entity_or_id) == "table" and entity_id(entity_or_id) or entity_or_id
  local record = id and self.bodies[id]
  if not record or not record.entity or not record.entity.position then return false end
  local x, y = record.body:getPosition()
  record.entity.position.x = x - record.offset_x
  record.entity.position.ground_y = y - record.offset_y
  return true
end

function PhysicsCollisionWorld:sync_entities()
  for id in pairs(self.bodies) do self:sync_entity(id) end
end

function PhysicsCollisionWorld:sync_bodies_to_entities(reset_velocity)
  if not self.world then return 0 end
  local count = 0
  for _, record in pairs(self.bodies) do
    local entity = record.entity
    if entity and entity.position then
      record.body:setPosition(
        numeric(entity.position.x, 0) + record.offset_x,
        numeric(entity.position.ground_y, 0) + record.offset_y
      )
      if reset_velocity then record.body:setLinearVelocity(0, 0) end
      count = count + 1
    end
  end
  return count
end

-- Legacy movement systems still calculate the next entity position directly.
-- Convert that displacement into a desired body velocity before stepping so
-- the physics world becomes the authority for the final position without
-- forcing every controller to migrate in the same phase.
function PhysicsCollisionWorld:capture_entity_velocities(dt)
  if not self.world then return 0 end
  dt = numeric(dt, 0)
  if dt <= 0 then
    self:apply_velocities({})
    return 0
  end
  local count = 0
  for id, record in pairs(self.bodies) do
    local entity = record.entity
    if entity and entity.position then
      local desired = entity.physics_intent_velocity
      if desired then
        record.body:setLinearVelocity(desired.x or 0, desired.y or 0)
      elseif entity.motocrotte_motion then
        record.body:setLinearVelocity(
          entity.motocrotte_motion.vx or 0,
          entity.motocrotte_motion.vy or 0
        )
      else
        local body_x, body_y = record.body:getPosition()
        local target_x = numeric(entity.position.x, 0) + record.offset_x
        local target_y = numeric(entity.position.ground_y, 0) + record.offset_y
        record.body:setLinearVelocity((target_x - body_x) / dt, (target_y - body_y) / dt)
      end
      count = count + 1
    end
  end
  return count
end

function PhysicsCollisionWorld:step(dt)
  if not self.world then return 0 end
  dt = math.max(0, math.min(numeric(dt, 0), 0.25))
  self.accumulator = self.accumulator + dt
  local steps = 0
  while self.accumulator >= self.fixed_dt and steps < self.max_substeps do
    self.step_count = self.step_count + 1
    self.world:update(self.fixed_dt)
    for _, record in pairs(self.bodies) do
      local bounds = record.bounds
      if bounds then
        local body_x, body_y = record.body:getPosition()
        local x = body_x - record.offset_x
        local y = body_y - record.offset_y
        local clamped_x = math.max(bounds.left, math.min(bounds.right, x))
        local clamped_y = math.max(bounds.top, math.min(bounds.bottom, y))
        local cone = bounds.perspective_cone
        if cone then
          local far_y = cone.far_y or bounds.top
          local near_y = cone.near_y or bounds.bottom
          local amount = math.max(0, math.min(1, (clamped_y - far_y) / math.max(1, near_y - far_y)))
          local half_width = (cone.far_half_width or 0)
            + amount * ((cone.near_half_width or 0) - (cone.far_half_width or 0))
          local center_x = cone.center_x or (bounds.left + bounds.right) * 0.5
          clamped_x = math.max(center_x - half_width, math.min(center_x + half_width, clamped_x))
        end
        -- Static edge fixtures are authoritative for ordinary rectangular
        -- bounds. Keep this compatibility clamp only for special bounds such
        -- as the rear-view perspective cone, or when no static boundary set
        -- is active.
        local requires_compatibility_clamp = not self.boundary_body or bounds.perspective_cone ~= nil
        if requires_compatibility_clamp and (clamped_x ~= x or clamped_y ~= y) then
          record.body:setPosition(clamped_x + record.offset_x, clamped_y + record.offset_y)
          local velocity_x, velocity_y = record.body:getLinearVelocity()
          if clamped_x ~= x and ((clamped_x == bounds.left and velocity_x < 0)
              or (clamped_x == bounds.right and velocity_x > 0)) then
            velocity_x = 0
          end
          if clamped_y ~= y and ((clamped_y == bounds.top and velocity_y < 0)
              or (clamped_y == bounds.bottom and velocity_y > 0)) then
            velocity_y = 0
          end
          record.body:setLinearVelocity(velocity_x, velocity_y)
        end
      end
    end
    self.accumulator = self.accumulator - self.fixed_dt
    steps = steps + 1
  end
  if self.accumulator >= self.fixed_dt then
    self.dropped_time = self.dropped_time + self.accumulator
    self.accumulator = 0
  end
  self:sync_entities()
  return steps
end

function PhysicsCollisionWorld:consume_contacts()
  local contacts = self.contacts
  self.contacts = {}
  return contacts
end

function PhysicsCollisionWorld:remove_entity(entity_or_id)
  local id = type(entity_or_id) == "table" and entity_id(entity_or_id) or entity_or_id
  local record = id and self.bodies[id]
  if not record then return false end
  if record.entity then
    record.entity.physics_body = nil
    record.entity.physics_fixture = nil
  end
  -- The record is removed immediately below, so this path is idempotent at
  -- the service level. Avoid relying on an optional `isDestroyed()` helper;
  -- the LÖVE 11.5 Body API guarantees `destroy()` for a live body.
  if record.body then record.body:destroy() end
  self.bodies[id] = nil
  return true
end

function PhysicsCollisionWorld:end_scope(name)
  if not self.world then return end
  assert(name == nil or name == self.scope, "Physics scope mismatch")
  local ids = {}
  for id in pairs(self.bodies) do ids[#ids + 1] = id end
  for _, id in ipairs(ids) do self:remove_entity(id) end
  self.contacts = {}
  self.bodies = {}
  self:_destroy_boundaries()
  self.world:destroy()
  self.world = nil
  self.scope = nil
  self.accumulator = 0
end

function PhysicsCollisionWorld:debug_snapshot()
  local count, bullet_count = 0, 0
  for _, record in pairs(self.bodies) do
    count = count + 1
    if record.bullet then bullet_count = bullet_count + 1 end
  end
  local boundary_bounds = nil
  if type(self.boundary_bounds) == "table" then
    boundary_bounds = {
      left = tonumber(self.boundary_bounds.left),
      right = tonumber(self.boundary_bounds.right),
      top = tonumber(self.boundary_bounds.top),
      bottom = tonumber(self.boundary_bounds.bottom)
    }
  end
  return {
    scope = self.scope,
    active = self.world ~= nil,
    body_count = count,
    bullet_body_count = bullet_count,
    contact_count = #self.contacts,
    fixed_dt = self.fixed_dt,
    accumulator = self.accumulator,
    dropped_time = self.dropped_time,
    step_count = self.step_count,
    boundary_count = #self.boundary_fixtures,
    boundary_bounds = boundary_bounds,
    boundary_enabled = self.boundary_enabled
  }
end

return PhysicsCollisionWorld
