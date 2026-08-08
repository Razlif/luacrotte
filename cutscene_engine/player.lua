-- Deterministic timeline player for declarative cutscene scenes.
local asset_manifest = require("game_data.asset_manifest")
local ContentManager = require("game.systems.content_manager")
local AssetActor = require("cutscene_engine.actor")
local Commands = require("cutscene_engine.commands")
local CameraManager = require("game.systems.camera_manager")
local DrawOrder = require("game.systems.draw_order")
local Effect = require("game.entities.effects.effect")
local ParallaxManager = require("game.systems.parallax")
local AudioManager = require("game.systems.audio_manager")
local Telemetry = require("game.systems.qa_telemetry")

local Player = {}
Player.__index = Player

function Player.requests_for_scene(scene)
  local requests, seen = {}, {}
  local actor_animations = {}
  for id, data in pairs(scene.actors or {}) do
    actor_animations[id] = {}
    if data.default_animation then actor_animations[id][data.default_animation] = true end
  end
  for _, command in ipairs(scene.timeline or {}) do
    if command.actor and actor_animations[command.actor] then
      if command.animation then actor_animations[command.actor][command.animation] = true end
      if command.command == "play_animation" and command.name then
        actor_animations[command.actor][command.name] = true
      end
    end
  end
  local function request(kind, asset_id, options)
    local id = kind .. ":" .. asset_id
    if not seen[id] then
      seen[id] = true
      requests[#requests + 1] = { kind = kind, asset_id = asset_id, options = options }
    end
  end
  for id, data in pairs(scene.actors or {}) do
    local animations = actor_animations[id]
    request(data.asset_type or "character", data.asset_id, {
      include_image = data.default_animation == nil,
      animations = animations
    })
  end
  if scene.background and scene.background.asset_id then
    request("background", scene.background.asset_id, { include_image = true, animations = {} })
  end
  for _, command in ipairs(scene.timeline or {}) do
    if command.command == "play_effect" and command.asset_id then
      request("effect", command.asset_id, { include_image = false, animations = command.animation })
    end
  end
  return requests
end

local function sorted_keys(table_value)
  local keys = {}
  for key in pairs(table_value or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

function Player.new(scene, options)
  options = options or {}
  AudioManager.begin_scope("cutscene")
  AudioManager.load_manifest(asset_manifest)
  if not options.preloaded then
    ContentManager.load_scope("cutscene", Player.requests_for_scene(scene))
  end
  local player = setmetatable({
    scene = scene,
    actors = {},
    actor_order = {},
    effects = {},
    dialogue = nil,
    timeline_index = 1,
    active_command = nil,
    finished = false,
    return_state = options.return_state or "playground",
    fade = { alpha = 0, color = { 0, 0, 0 } }
  }, Player)
  Telemetry.emit("scene_started", { scene = scene.id })

  for id, data in pairs(scene.actors or {}) do
    data.id = id
    local asset_type = data.asset_type or "character"
    if asset_type == "character" then
      local gameplay_definition = require("game_data.characters." .. data.asset_id)
      data.movement = data.movement or gameplay_definition.movement
      data.hop_animation = data.hop_animation or gameplay_definition.hop_animation
      data.default_animation = data.default_animation or gameplay_definition.default_animation
      data.default_animation_loop = data.default_animation_loop or gameplay_definition.default_animation_loop
    else
      assert(asset_type == "prop", "Unsupported cutscene actor asset type: " .. tostring(asset_type))
    end
    local asset = ContentManager.get(asset_type, data.asset_id)
    player.actors[id] = AssetActor.new(data, asset)
  end
  player.actor_order = sorted_keys(player.actors)

  local camera_data = scene.camera or {}
  player.camera = CameraManager.new({
    width = camera_data.width or 960,
    height = camera_data.height or 540,
    bounds = camera_data.bounds,
    smoothing = camera_data.smoothing or 8,
    zoom = camera_data.zoom or 1
  })
  local camera_position = camera_data.position
  if camera_position then
    player.camera:set_center(camera_position.x, camera_position.ground_y)
  end

  local background = scene.background and asset_manifest.backgrounds[scene.background.asset_id]
  local background_asset = scene.background and ContentManager.get("background", scene.background.asset_id)
  player.parallax = ParallaxManager.new(background and {
    {
      id = background.id,
      image_path = background.image.path,
      image = background_asset and background_asset.image.texture,
      speed_x = 1,
      speed_y = 1,
      repeat_x = false,
      repeat_y = false
    }
  } or {})
  player.parallax:set_camera(player.camera)
  return player
end

function Player:spawn_effect(command)
  local manifest_definition = asset_manifest.effects[command.asset_id]
  assert(manifest_definition, "Unknown cutscene effect: " .. tostring(command.asset_id))
  local animation_name = command.animation
  if not animation_name then
    for name in pairs(manifest_definition.animations or {}) do animation_name = name break end
  end
  local definition = {
    asset_id = command.asset_id,
    position = command.position or { x = 0, ground_y = 0, z = 0 },
    scale = command.scale or 1,
    anchor = command.anchor or { x = 32, y = 32 },
    animation = animation_name,
    draw_layer = command.draw_layer or 30,
    flicker = command.flicker
  }
    local effect = Effect.new(definition, ContentManager.get("effect", command.asset_id))
  effect:trigger()
  self.effects[#self.effects + 1] = effect
end

function Player:start_next_command()
  local command = self.scene.timeline[self.timeline_index]
  if not command then
    self.finished = true
    Telemetry.emit("scene_finished", { scene = self.scene.id, completed = true })
    return
  end
  Commands.validate(command, self.timeline_index)
  self.timeline_index = self.timeline_index + 1
  self.active_command = Commands.begin(self, command)
  Telemetry.emit("command_started", { scene = self.scene.id, index = self.timeline_index - 1, command = command.command })
  if self.active_command.done then
    self.active_command = nil
    Telemetry.emit("command_completed", { scene = self.scene.id, index = self.timeline_index - 1, command = command.command })
    self:start_next_command()
  end
end

function Player:update(dt)
  if self.finished then return end
  for _, id in ipairs(self.actor_order) do self.actors[id]:update(dt) end
  for index = #self.effects, 1, -1 do
    local effect = self.effects[index]
    effect:update(dt)
    if effect:is_finished() then table.remove(self.effects, index) end
  end

  if not self.active_command then self:start_next_command() end
  if self.active_command then
    local command = self.scene.timeline[self.timeline_index - 1]
    if Commands.update(self, command, self.active_command, dt) then
      if command.command == "say" then self.dialogue = nil end
      if command.command == "move" or command.command == "ride_trick" then
        self.actors[command.actor]:clear_presentation()
        self.actors[command.actor]:idle()
      end
      Telemetry.emit("command_completed", { scene = self.scene.id, index = self.timeline_index - 1, command = command.command })
      self.active_command = nil
    end
  end
  self.camera:update(dt)
  self.parallax:update(dt)
end

function Player:draw()
  love.graphics.clear(0.08, 0.1, 0.14, 1)
  love.graphics.setColor(1, 1, 1, 1)
  self.camera:attach()
  self.parallax:draw()
  local drawables = {}
  for _, id in ipairs(self.actor_order) do drawables[#drawables + 1] = self.actors[id] end
  for _, effect in ipairs(self.effects) do drawables[#drawables + 1] = effect end
  for _, drawable in ipairs(DrawOrder.sort(drawables)) do drawable:draw() end
  self.camera:detach()
  if self.dialogue then self.dialogue:draw(self.camera) end
  if self.fade.alpha > 0 then
    love.graphics.setColor(self.fade.color[1], self.fade.color[2], self.fade.color[3], self.fade.alpha)
    love.graphics.rectangle("fill", 0, 0, self.camera.width, self.camera.height)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Player:skip()
  self.finished = true
  self.dialogue = nil
  Telemetry.emit("scene_skipped", { scene = self.scene.id })
  Telemetry.emit("scene_finished", { scene = self.scene.id, completed = false, skipped = true })
end

function Player:is_finished()
  return self.finished
end

function Player:get_debug_context()
  local entities = {}
  for _, id in ipairs(self.actor_order) do entities[#entities + 1] = self.actors[id] end
  for _, effect in ipairs(self.effects) do entities[#entities + 1] = effect end
  return {
    entities = entities,
    camera = self.camera,
    collision_events = {},
    scene = self.scene.id,
    timeline_index = self.timeline_index,
    active_command = self.active_command and self.scene.timeline[self.timeline_index - 1].command or nil,
    dialogue = self.dialogue and { text = self.dialogue.text, speaker = self.dialogue.speaker } or nil,
    finished = self.finished
  }
end

return Player
