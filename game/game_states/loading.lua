-- Reusable staged-loading state. States may delegate here when they need a
-- visible loading screen instead of blocking during scope preparation.
local ContentManager = require("game.systems.content_manager")

local LoadingState = { job = nil }

function LoadingState.begin(job)
  LoadingState.job = job
  if job.scope then ContentManager.begin_scope(job.scope) end
  for _, request in ipairs(job.requests or {}) do
    ContentManager.request(request.kind, request.asset_id, request.options)
  end
end

function LoadingState.keypressed(key)
  local job = LoadingState.job
  if not job or #ContentManager.progress().errors == 0 then return end
  if key == "r" or key == "return" then
    if job.scope then ContentManager.end_scope(job.scope) end
    LoadingState.begin(job)
  elseif key == "escape" then
    LoadingState.job = nil
    if job.scope then ContentManager.end_scope(job.scope) end
    if job.on_fallback then job.on_fallback() end
  end
end

function LoadingState.update(dt)
  if not LoadingState.job then return end
  ContentManager.update(dt)
  if ContentManager.is_ready() then
    local job = LoadingState.job
    LoadingState.job = nil
    if job.on_ready then job.on_ready(ContentManager) end
  end
end

function LoadingState.draw()
  local progress = ContentManager.progress()
  love.graphics.clear(0.08, 0.1, 0.14, 1)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Loading...", 0, love.graphics.getHeight() * 0.42, love.graphics.getWidth(), "center")
  love.graphics.printf(string.format("%d / %d", progress.completed, progress.total), 0, love.graphics.getHeight() * 0.50, love.graphics.getWidth(), "center")
  if progress.errors[1] then
    love.graphics.setColor(1, 0.35, 0.35, 1)
    love.graphics.printf(tostring(progress.errors[1].error), 40, love.graphics.getHeight() * 0.58, love.graphics.getWidth() - 80, "center")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("Press R or Enter to retry    Esc to return", 0, love.graphics.getHeight() * 0.68, love.graphics.getWidth(), "center")
  end
end

function LoadingState.get_debug_context()
  local progress = ContentManager.progress()
  return {
    entities = {},
    camera = nil,
    collision_events = {},
    loading = progress
  }
end

return LoadingState
