-- Owns level-defined enemy spawns, active instances, defeats, and respawns.
-- The manager deliberately knows nothing about combat response; it only
-- provides the lifecycle that the level requested.
local Character = require("game.entities.characters.character")

local EnemyManager = {}
EnemyManager.__index = EnemyManager

local function count_entries(value)
  local count = 0
  for _ in pairs(value or {}) do count = count + 1 end
  return count
end

local function copy_spawn(spawn)
  spawn = spawn or {}
  return {
    x = spawn.x or 0,
    ground_y = spawn.ground_y or spawn.y or 0,
    z = spawn.z or 0
  }
end

function EnemyManager.new(options)
  options = options or {}
  local entries = options.entries or options.spawn_points or {}
  local manager = setmetatable({
    entries = entries,
    definitions = options.definitions or {},
    content = options.content or {},
    content_by_definition = options.content_by_definition or {},
    factory = options.factory,
    spawn_template = options.spawn_template,
    physics_world = options.physics_world,
    physics_options = options.physics_options or {},
    next_spawn_index = 0,
    max_count = options.max_count or #entries,
    active = {},
    defeated = {},
    respawn_timers = {},
    queued_this_update = {},
    events = {}
  }, EnemyManager)
  return manager
end

function EnemyManager:_definition(entry)
  local definition = entry.definition
  if type(definition) == "table" then return definition end
  return assert(self.definitions[definition], "Unknown enemy definition: " .. tostring(definition))
end

function EnemyManager:_content(entry)
  local key = entry.content_key or self.content_by_definition[entry.definition] or "prop"
  return self.content[key]
end

function EnemyManager:_find_entry(id)
  for _, entry in ipairs(self.entries) do
    if entry.id == id then return entry end
  end
  return nil
end

function EnemyManager:_active_count()
  return #self.active
end

function EnemyManager:_spawn(entry)
  local definition = self:_definition(entry)
  local enemy
  if self.factory then
    enemy = self.factory(definition, entry, self:_content(entry))
  else
    enemy = Character.new(definition, self:_content(entry))
  end
  assert(enemy, "Enemy factory returned no enemy for: " .. tostring(entry.id))

  local spawn = copy_spawn(entry.spawn or definition.position)
  enemy.position.x = spawn.x
  enemy.position.ground_y = spawn.ground_y
  enemy.position.z = spawn.z
  enemy.spawn_point_id = entry.id
  enemy.spawn_definition = entry.definition
  enemy.spawn_position = spawn
  enemy.respawn_enabled = entry.respawn ~= false
  enemy.respawn_delay = entry.respawn_delay
    or (definition.combat and definition.combat.respawn_time)
    or 1.0
  enemy.enemy_manager_id = entry.id
  return enemy
end

function EnemyManager:_register_physics(enemy)
  if self.physics_world and enemy then
    self.physics_world:add_entity(enemy, self.physics_options)
    enemy.physics_registered = true
  end
end

function EnemyManager:_unregister_physics(enemy)
  if self.physics_world and enemy and enemy.physics_registered then
    self.physics_world:remove_entity(enemy)
    enemy.physics_registered = false
  end
end

function EnemyManager:spawn_entry(entry, suppress_event)
  assert(entry and entry.id, "Enemy spawn entry requires an id")
  if self:_active_count() >= self.max_count then return nil end
  if self.defeated[entry.id] and not self.respawn_timers[entry.id] then return nil end
  for _, enemy in ipairs(self.active) do
    if enemy.enemy_manager_id == entry.id then return enemy end
  end
  local enemy = self:_spawn(entry)
  self.active[#self.active + 1] = enemy
  self:_register_physics(enemy)
  if not suppress_event then
    self.events[#self.events + 1] = { type = "enemy_spawned", enemy_id = enemy.id, spawn_id = entry.id }
  end
  return enemy
end

function EnemyManager:spawn_all()
  for _, entry in ipairs(self.entries) do
    if self:_active_count() >= self.max_count then break end
    self:spawn_entry(entry)
  end
  return self.active
end

function EnemyManager:spawn_next(spawn)
  if not self.spawn_template or self:_active_count() >= self.max_count then
    return nil
  end
  self.next_spawn_index = self.next_spawn_index + 1
  local template = self.spawn_template
  local entry = {}
  for key, value in pairs(template) do entry[key] = value end
  entry.id = string.format("%s_%02d", template.id or template.definition or "enemy", self.next_spawn_index)
  entry.spawn = copy_spawn(spawn or template.spawn)
  self.entries[#self.entries + 1] = entry
  return self:spawn_entry(entry)
end

function EnemyManager:_queue_respawn(enemy)
  local entry_id = enemy.enemy_manager_id
  local entry = self:_find_entry(entry_id)
  if not entry or enemy.respawn_enabled == false or entry.respawn == false then
    self.defeated[entry_id] = { enemy = enemy, entry = entry, respawn = false }
    self.events[#self.events + 1] = { type = "enemy_defeated", enemy_id = enemy.id, respawn = false }
    return
  end
  local delay = enemy.respawn_delay or entry.respawn_delay or 1.0
  self.defeated[entry_id] = { enemy = enemy, entry = entry, respawn = true, defeated_at = 0 }
  self.respawn_timers[entry_id] = delay
  self.queued_this_update[entry_id] = true
  self.events[#self.events + 1] = {
    type = "enemy_respawn_queued", enemy_id = enemy.id, spawn_id = entry_id, delay = delay
  }
end

function EnemyManager:_remove_defeated()
  for index = #self.active, 1, -1 do
    local enemy = self.active[index]
    -- Remove the body as soon as the defeat/fade state begins. The visual
    -- entity remains in the active list until its fade completes so the
    -- renderer can finish the defeat presentation.
    if (enemy.defeat_elapsed ~= nil or enemy.behavior_state == "defeated")
        and enemy.physics_registered then
      self:_unregister_physics(enemy)
    end
    if enemy:is_defeat_complete() then
      table.remove(self.active, index)
      self:_queue_respawn(enemy)
    end
  end
end

function EnemyManager:_update_respawns(dt)
  for entry_id, remaining in pairs(self.respawn_timers) do
    if self.queued_this_update[entry_id] then
      self.queued_this_update[entry_id] = nil
    else
      remaining = math.max(0, remaining - dt)
    end
    self.respawn_timers[entry_id] = remaining
    if remaining <= 0 and self:_active_count() < self.max_count then
      local record = self.defeated[entry_id]
      local entry = record and record.entry or self:_find_entry(entry_id)
      if entry then
        local enemy = self:spawn_entry(entry, true)
        if enemy then
          self.defeated[entry_id] = nil
          self.respawn_timers[entry_id] = nil
          self.events[#self.events + 1] = {
            type = "enemy_respawned", enemy_id = enemy.id, spawn_id = entry_id
          }
        end
      end
    end
  end
end

function EnemyManager:update(dt, world)
  self.events = {}
  self.queued_this_update = {}
  dt = dt or 0
  for _, enemy in ipairs(self.active) do
    if enemy.update then enemy:update(dt, world) end
  end
  self:_remove_defeated()
  self:_update_respawns(dt)
  return self.active
end

function EnemyManager:get_active()
  return self.active
end

function EnemyManager:get_events()
  return self.events
end

function EnemyManager:get_respawn_snapshot()
  local timers = {}
  local next_timer = nil
  for id, remaining in pairs(self.respawn_timers) do
    timers[id] = remaining
    if next_timer == nil or remaining < next_timer then next_timer = remaining end
  end
  return {
    active_count = #self.active,
    defeated_count = count_entries(self.defeated),
    max_count = self.max_count,
    respawn_timer = next_timer,
    timers = timers
  }
end

function EnemyManager:clear()
  for _, enemy in ipairs(self.active) do self:_unregister_physics(enemy) end
  for _, record in pairs(self.defeated) do
    if record.enemy then self:_unregister_physics(record.enemy) end
  end
  self.active = {}
  self.defeated = {}
  self.respawn_timers = {}
  self.queued_this_update = {}
  self.events = {}
end

return EnemyManager
