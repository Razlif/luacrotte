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
  fading_music = nil
}

local function definition(group, id)
  local item = (AudioManager.manifest[group] or {})[id]
  assert(item, "Unknown audio " .. group .. " id: " .. tostring(id))
  assert(love.filesystem.getInfo(item.path), "Missing audio file: " .. item.path)
  return item
end

function AudioManager.load_manifest(manifest)
  AudioManager.manifest = manifest and manifest.audio or { music = {}, sounds = {} }
  AudioManager.music_sources = {}
  AudioManager.sound_sources = {}
  AudioManager.looping_sfx_sources = {}
end

function AudioManager.play_music(id, options)
  options = options or {}
  local item = definition("music", id)
  local source = AudioManager.music_sources[id]
  if not source then
    source = love.audio.newSource(item.path, "stream")
    AudioManager.music_sources[id] = source
  end
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
  local instance = source:clone()
  instance:setVolume((options.volume or item.volume or 1) * AudioManager.sfx_volume)
  instance:setPitch(options.pitch or 1)
  instance:play()
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
    AudioManager.current_music:setVolume(AudioManager.current_music:getVolume() * AudioManager.music_volume)
  end
end

function AudioManager.set_sfx_volume(value)
  AudioManager.sfx_volume = math.max(0, math.min(1, value))
end

function AudioManager.update(dt)
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
