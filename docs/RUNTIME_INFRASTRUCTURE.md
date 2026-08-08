# Runtime infrastructure

The toolkit uses a small, reusable runtime context for every state:

```lua
context.content -- ContentManager
context.levels  -- LevelManager
context.audio   -- AudioManager
context.input   -- InputManager
context.telemetry
```

## State transitions

States may expose `get_load_requests(context, ...)`. `StatesManager` releases the
current state, enters the staged `loading` state, and then calls the destination
state only after all requested resources are ready. The loader processes one
resource per update so the loading screen remains drawable and responsive.

Menu startup preloads only its menu background. Playground and cutscenes declare
their own dependencies and are loaded into explicit `menu`, `playground`, or
`cutscene` scopes. Scope exit releases resources that are not shared by another
active scope.

## Content requests

```lua
ContentManager.begin_scope("playground")
ContentManager.request("character", "luacrotte_hero_motorcycle_direction_set_v001")
ContentManager.update(dt)
local hero = ContentManager.get("character", "luacrotte_hero_motorcycle_direction_set_v001")
ContentManager.end_scope("playground")
```

`AssetLoader` remains as a compatibility facade, but manifest registration is
lazy: it does not decode every image. Repeated requests use the shared cache.
The debug snapshot reports scope ownership, progress, cache hits/misses, and
per-resource load timing.

## Collision data

Shape collision is the default and is available without ImageData decoding:

```lua
collision = {
  mode = "shape",
  shape = "rectangle",
  width = 48,
  height = 48
}
```

Use pixel masks only for an asset that explicitly needs them:

```lua
collision = { mode = "pixel_mask", cache = true }
```

`CollisionDataManager` owns mask creation and caching. `CollisionDetection`
only reports overlaps; gameplay systems own impact responses.

## Levels and backgrounds

`LevelManager` owns level composition: active profile, spawn, movement bounds,
camera configuration, background layers, and content dependencies. Profiles own
behavior tuning; levels own spatial composition. Backgrounds are loaded through
`ContentManager` and rendered in world space unless a layer explicitly opts into
camera-locked rendering.

For a new level, add a definition under `game_data/levels`, register it in
`GameLoop`, and declare its content dependencies. Do not add a manifest-wide
load call to a gameplay state.
