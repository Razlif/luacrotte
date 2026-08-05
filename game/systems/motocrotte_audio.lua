-- Maps MotoCrotte driving state to named runtime audio without coupling it to movement.
local AudioManager = require("game.systems.audio_manager")

local MotocrotteAudio = {
  was_braking = false,
  was_drifting = false,
  active_loop = nil
}

local function select_loop(id)
  if MotocrotteAudio.active_loop == id then return end
  if MotocrotteAudio.active_loop then
    AudioManager.stop_looping_sfx(MotocrotteAudio.active_loop)
  end
  AudioManager.play_looping_sfx(id)
  MotocrotteAudio.active_loop = id
end

function MotocrotteAudio.update(intent, motion)
  local throttle_held = (intent.throttle or 0) > 0
  local braking = intent.brake == true
  local drifting = motion.drift_active == true

  select_loop(throttle_held and "motocrotte_running" or "motocrotte_idle")
  if (braking and not MotocrotteAudio.was_braking) or (drifting and not MotocrotteAudio.was_drifting) then
    AudioManager.play_sfx("motocrotte_break", { volume = 0.35 })
  end
  MotocrotteAudio.was_braking = braking
  MotocrotteAudio.was_drifting = drifting
end

function MotocrotteAudio.reset()
  if MotocrotteAudio.active_loop then
    AudioManager.stop_looping_sfx(MotocrotteAudio.active_loop)
  end
  MotocrotteAudio.active_loop = nil
  MotocrotteAudio.was_braking = false
  MotocrotteAudio.was_drifting = false
end

return MotocrotteAudio
