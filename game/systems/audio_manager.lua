-- Named music and sound-effect playback with optional source caching.
local AudioManager = {
  manifest = { music = {}, sounds = {} },
  music_sources = {},
  sound_sources = {},
  looping_sfx_sources = {},
  current_music = nil,
  current_music_id = nil,
  current_music_base_volume = 1,
  music_volume = 1,
  sfx_volume = 1,
  fading_music = nil,
  current_scope = nil,
  scopes = {},
  active_instances = {}
}

local function retain(kind, id)
  if AudioManager.current_scope then
    AudioManager.scopes[AudioManager.current_scope] = AudioManager.scopes[AudioManager.current_scope] or {}
    AudioManager.scopes[AudioManager.current_scope][kind .. ":" .. id] = true
  end
end

function AudioManager.begin_scope(name)
  AudioManager.current_scope = name
  AudioManager.scopes[name] = AudioManager.scopes[name] or {}
end

function AudioManager.end_scope(name)
  local scope = AudioManager.scopes[name]
  if scope then
    for key in pairs(scope) do
      local kind, id = key:match("([^:]+):(.+)")
      local shared = false
      for other, entries in pairs(AudioManager.scopes) do
        if other ~= name and entries[key] then shared = true break end
      end
      if not shared then
        local sources = kind == "music" and AudioManager.music_sources
          or kind == "loop" and AudioManager.looping_sfx_sources
          or AudioManager.sound_sources
        local source = sources and sources[id]
        if source then
          source:stop()
          if source.release then source:release() end
          sources[id] = nil
        end
        if AudioManager.current_music_id == id and kind == "music" then
          AudioManager.current_music = nil
          AudioManager.current_music_id = nil
          AudioManager.current_music_base_volume = 1
        end
        if AudioManager.fading_music and AudioManager.fading_music.source == source then
          AudioManager.fading_music = nil
        end
      end
    end
    for index = #AudioManager.active_instances, 1, -1 do
      local instance = AudioManager.active_instances[index]
      if instance.scope == name then
        instance.source:stop()
        if instance.source.release then instance.source:release() end
        table.remove(AudioManager.active_instances, index)
      end
    end
    AudioManager.scopes[name] = nil
  end
  if AudioManager.current_scope == name then AudioManager.current_scope = nil end
end

local function definition(group, id)
  local item = (AudioManager.manifest[group] or {})[id]
  assert(item, "Unknown audio " .. group .. " id: " .. tostring(id))
  assert(love.filesystem.getInfo(item.path), "Missing audio file: " .. item.path)
  return item
end

function AudioManager.load_manifest(manifest)
  AudioManager.manifest = manifest and manifest.audio or { music = {}, sounds = {} }
end

function AudioManager.play_music(id, options)
  options = options or {}
  local item = definition("music", id)
  local source = AudioManager.music_sources[id]
  if not source then
    source = love.audio.newSource(item.path, "stream")
    AudioManager.music_sources[id] = source
  end
  retain("music", id)
  if AudioManager.current_music then
    AudioManager.current_music:stop()
  end
  source:setLooping(options.loop ~= nil and options.loop or item.loop ~= false)
  AudioManager.current_music_base_volume = options.volume or item.volume or 1
  source:setVolume(AudioManager.current_music_base_volume * AudioManager.music_volume)
  source:play()
  AudioManager.current_music = source
  AudioManager.current_music_id = id
  return source
end

function AudioManager.stop_music(fade_seconds)
  if not AudioManager.current_music then
    return
  end
  if fade_seconds and fade_seconds > 0 then
    AudioManager.fading_music = { source = AudioManager.current_music, duration = fade_seconds, elapsed = 0 }
  else
    AudioManager.current_music:stop()
    AudioManager.current_music = nil
    AudioManager.current_music_id = nil
  end
end

function AudioManager.play_sfx(id, options)
  options = options or {}
  local item = definition("sounds", id)
  local source = AudioManager.sound_sources[id]
  if not source then
    source = love.audio.newSource(item.path, "static")
    AudioManager.sound_sources[id] = source
  end
  retain("sound", id)
  local instance = source:clone()
  instance:setVolume((options.volume or item.volume or 1) * AudioManager.sfx_volume)
  instance:setPitch(options.pitch or 1)
  instance:play()
  if AudioManager.current_scope then
    AudioManager.active_instances[#AudioManager.active_instances + 1] = {
      scope = AudioManager.current_scope,
      source = instance
    }
  end
  return instance
end

function AudioManager.play_looping_sfx(id, options)
  options = options or {}
  local item = definition("sounds", id)
  local source = AudioManager.looping_sfx_sources[id]
  if not source then
    source = love.audio.newSource(item.path, "static")
    AudioManager.looping_sfx_sources[id] = source
  end
  retain("loop", id)
  source:setLooping(options.loop ~= false)
  source:setVolume((options.volume or item.volume or 1) * AudioManager.sfx_volume)
  source:setPitch(options.pitch or 1)
  if not source:isPlaying() then
    source:play()
  end
  return source
end

function AudioManager.stop_looping_sfx(id)
  local source = AudioManager.looping_sfx_sources[id]
  if source then source:stop() end
end

function AudioManager.set_music_volume(value)
  AudioManager.music_volume = math.max(0, math.min(1, value))
  if AudioManager.current_music then
    AudioManager.current_music:setVolume(AudioManager.current_music_base_volume * AudioManager.music_volume)
  end
end

function AudioManager.set_sfx_volume(value)
  AudioManager.sfx_volume = math.max(0, math.min(1, value))
end

function AudioManager.update(dt)
  for index = #AudioManager.active_instances, 1, -1 do
    local instance = AudioManager.active_instances[index]
    if not instance.source:isPlaying() then
      if instance.source.release then instance.source:release() end
      table.remove(AudioManager.active_instances, index)
    end
  end
  local fade = AudioManager.fading_music
  if not fade then
    return
  end
  fade.elapsed = fade.elapsed + dt
  fade.source:setVolume(math.max(0, 1 - fade.elapsed / fade.duration) * AudioManager.current_music_base_volume * AudioManager.music_volume)
  if fade.elapsed >= fade.duration then
    fade.source:stop()
    AudioManager.fading_music = nil
    if AudioManager.current_music == fade.source then
      AudioManager.current_music = nil
      AudioManager.current_music_id = nil
      AudioManager.current_music_base_volume = 1
    end
  end
end

function AudioManager.stop_all()
  if AudioManager.current_music then
    AudioManager.current_music:stop()
  end
  AudioManager.current_music = nil
  AudioManager.current_music_id = nil
  AudioManager.current_music_base_volume = 1
  AudioManager.fading_music = nil
  for _, source in pairs(AudioManager.looping_sfx_sources) do source:stop() end
  for index = #AudioManager.active_instances, 1, -1 do
    local instance = AudioManager.active_instances[index]
    instance.source:stop()
    if instance.source.release then instance.source:release() end
    table.remove(AudioManager.active_instances, index)
  end
end

function AudioManager.debug_snapshot()
  return {
    music = AudioManager.current_music_id,
    music_playing = AudioManager.current_music and AudioManager.current_music:isPlaying() or false,
    looping_sfx = (function()
      local result = {}
      for id, source in pairs(AudioManager.looping_sfx_sources) do
        if source:isPlaying() then table.insert(result, id) end
      end
      return result
    end)()
  }
end

return AudioManager
