-- Scene-aware facade over the lazy AssetLoader and AudioManager caches.
local AssetLoader = require("game.systems.asset_loader")
local Telemetry = require("game.systems.qa_telemetry")

local ContentManager = {
  manifest = nil,
  current_scope = nil,
  queue = {},
  resources = {},
  errors = {},
  completed = 0,
  total = 0,
  cache_hits = 0,
  cache_misses = 0,
  load_timings = {}
}

local function options_key(options)
  options = options or {}
  local animations = options.animations
  local animation_key = "*"
  if type(animations) == "string" then
    animation_key = animations
  elseif type(animations) == "table" then
    local names = {}
    for name, value in pairs(animations) do
      names[#names + 1] = type(name) == "number" and tostring(value) or (tostring(name) .. "=" .. tostring(value))
    end
    table.sort(names)
    animation_key = table.concat(names, ",")
  end
  return table.concat({ tostring(options.include_image ~= false), animation_key, tostring(options.pixel_mask == true), tostring(options.keep_image_data == true) }, "|")
end

local function key(kind, asset_id, options)
  return kind .. ":" .. asset_id .. ":" .. options_key(options)
end

function ContentManager.configure(manifest)
  ContentManager.manifest = manifest
  ContentManager.queue = {}
  ContentManager.resources = {}
  ContentManager.errors = {}
  ContentManager.completed = 0
  ContentManager.total = 0
  ContentManager.cache_hits = 0
  ContentManager.cache_misses = 0
  ContentManager.load_timings = {}
  AssetLoader.load_manifest(manifest)
end

function ContentManager.begin_scope(name)
  ContentManager.current_scope = name
  AssetLoader.begin_scope(name)
  ContentManager.queue = {}
  ContentManager.completed = 0
  ContentManager.total = 0
  ContentManager.errors = {}
  ContentManager.cache_hits = 0
  ContentManager.cache_misses = 0
  ContentManager.load_timings = {}
end

function ContentManager.request(kind, asset_id, options)
  local id = key(kind, asset_id, options)
  local existing = ContentManager.resources[id]
  if existing then
    ContentManager.cache_hits = ContentManager.cache_hits + 1
    if ContentManager.current_scope then existing.scopes[ContentManager.current_scope] = true end
    ContentManager.total = ContentManager.total + 1
    if existing.state == "ready" or existing.state == "failed" then
      ContentManager.completed = ContentManager.completed + 1
      if existing.state == "failed" then
        ContentManager.errors[#ContentManager.errors + 1] = existing
      end
    end
    return existing
  end
  local resource = {
    kind = kind,
    asset_id = asset_id,
    options = options or {},
    state = "queued",
    value = nil,
    scopes = {}
  }
  if ContentManager.current_scope then resource.scopes[ContentManager.current_scope] = true end
  ContentManager.resources[id] = resource
  ContentManager.cache_misses = ContentManager.cache_misses + 1
  ContentManager.queue[#ContentManager.queue + 1] = resource
  ContentManager.total = ContentManager.total + 1
  return resource
end

function ContentManager.update(_dt)
  local resource = table.remove(ContentManager.queue, 1)
  if not resource then return end
  resource.state = "loading"
  local started_at = love.timer.getTime()
  local ok, value = pcall(function()
    return AssetLoader.get(resource.kind, resource.asset_id, resource.options)
  end)
  if ok then
    resource.value = value
    resource.state = "ready"
    local duration_ms = (love.timer.getTime() - started_at) * 1000
    local image = value and value.image and value.image.texture
    local path = value and value.image and value.image.path
    local info = path and love.filesystem.getInfo(path) or nil
    resource.duration_ms = duration_ms
    resource.bytes = info and info.size or 0
    resource.dimensions = image and { width = image:getWidth(), height = image:getHeight() } or nil
    ContentManager.load_timings[#ContentManager.load_timings + 1] = {
      asset_id = resource.asset_id,
      category = resource.kind,
      duration_ms = duration_ms,
      bytes = resource.bytes,
      dimensions = resource.dimensions
    }
    Telemetry.emit("content_loaded", {
      phase = "texture_decode",
      asset_id = resource.asset_id,
      category = resource.kind,
      duration_ms = duration_ms,
      bytes = resource.bytes,
      dimensions = resource.dimensions
    })
  else
    resource.state = "failed"
    resource.error = value
    ContentManager.errors[#ContentManager.errors + 1] = resource
    Telemetry.emit("content_failed", {
      asset_id = resource.asset_id,
      category = resource.kind,
      error = tostring(value)
    })
  end
  ContentManager.completed = ContentManager.completed + 1
end

function ContentManager.load_scope(name, requests)
  ContentManager.begin_scope(name)
  for _, request in ipairs(requests or {}) do
    ContentManager.request(request.kind, request.asset_id, request.options)
  end
  while #ContentManager.queue > 0 do ContentManager.update(0) end
  assert(ContentManager:is_ready(), "Content scope failed to load: " .. tostring(name))
end

function ContentManager.is_ready()
  return #ContentManager.queue == 0 and ContentManager.completed >= ContentManager.total and #ContentManager.errors == 0
end

function ContentManager.get(kind, asset_id, options)
  local resource = ContentManager.resources[key(kind, asset_id, options)]
  if not resource then
    for _, candidate in pairs(ContentManager.resources) do
      if candidate.kind == kind and candidate.asset_id == asset_id then
        resource = candidate
        break
      end
    end
  end
  assert(resource and resource.state == "ready", "Content is not ready: " .. kind .. ":" .. asset_id)
  return resource.value
end

function ContentManager.progress()
  return {
    completed = ContentManager.completed,
    total = ContentManager.total,
    fraction = ContentManager.total == 0 and 1 or ContentManager.completed / ContentManager.total,
    current = ContentManager.queue[1],
    errors = ContentManager.errors
  }
end

function ContentManager.end_scope(name)
  AssetLoader.end_scope(name)
  for id, resource in pairs(ContentManager.resources) do
    if resource.scopes[name] then
      resource.scopes[name] = nil
      local shared = false
      for _ in pairs(resource.scopes) do shared = true break end
      if not shared then ContentManager.resources[id] = nil end
    end
  end
  if ContentManager.current_scope == name then ContentManager.current_scope = nil end
end

function ContentManager.debug_snapshot()
  local ready, queued, failed = 0, 0, 0
  for _, resource in pairs(ContentManager.resources) do
    if resource.state == "ready" then ready = ready + 1
    elseif resource.state == "queued" or resource.state == "loading" then queued = queued + 1
    elseif resource.state == "failed" then failed = failed + 1 end
  end
  return {
    scope = ContentManager.current_scope,
    ready = ready,
    queued = queued,
    failed = failed,
    cache_hits = ContentManager.cache_hits,
    cache_misses = ContentManager.cache_misses,
    load_timings = ContentManager.load_timings,
    progress = ContentManager.progress()
  }
end

return ContentManager
