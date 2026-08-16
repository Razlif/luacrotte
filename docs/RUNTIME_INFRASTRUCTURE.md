# Runtime infrastructure

The toolkit uses a small, reusable runtime context for every state:

```lua
context.content -- ContentManager
context.levels  -- LevelManager
context.audio   -- AudioManager
context.input   -- InputManager
context.telemetry
context.physics -- gravityless PhysicsCollisionWorld
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

## Physics integration

Migrated gameplay states may own a named gravityless physics scope. Level and
profile data resolve the physics configuration before the scope starts:

```lua
context.physics:begin_scope("playground", {
  enabled = true,
  gravity_x = 0,
  gravity_y = 0,
  fixed_timestep = 1 / 60,
  bounds = { left = 0, right = 2400, top = 586, bottom = 1771 }
})
context.physics:add_entity(hero, { bullet = true, high_speed = true })
context.physics:add_entity(enemy, { bullet = true, high_speed = true })
context.physics:capture_entity_velocities(dt)
context.physics:step(dt)
local contacts = context.physics:consume_contacts()
context.physics:end_scope("playground")
```

The current Playground is the first integration. Its legacy movement systems
still calculate desired entity positions; the physics service converts those
displacements into velocities, resolves base-footprint contacts, and writes
the authoritative positions back to the entities. EnemyManager owns enemy
body registration across spawn, defeat, respawn, and removal.

Rectangular bounds are represented by four static edge fixtures in the physics
world. This makes physics bodies authoritative for ordinary boundary
enforcement instead of clamping each entity after every step. A profile or
level can set `physics.bounds = false` for a deliberately unbounded experiment.
Perspective-cone movement keeps its additional cone-specific compatibility
clamp because it is not represented by a simple rectangle.

## Physics loading and runtime cost

Ordinary gameplay collision uses numeric footprint metadata from
`game_data/collision_footprints.lua`. It does not decode `ImageData`, inspect
pixels, or rebuild a fixture when an animation frame changes. Only active
entities are registered with the physics scope, and each registration creates
one body, rectangle shape, and fixture for that entity. Defeated enemies are
unregistered immediately; scope exit destroys all remaining bodies, fixtures,
and static boundaries together.

Continuous/bullet collision is explicitly restricted to entities marked
`high_speed = true`; generic physics bodies remain on the cheaper broad-phase
path. Pixel-mask collision stays opt-in:

```lua
pixel_mask = { enabled = true, cache = true }
```

Reserve that path for precise bullets, irregular mud impacts, special hit
zones, or debug inspection. It is not part of the ordinary movement or
animation loop.

## Visual/physics boundary

Physics is the sole authority for synchronized entity positions and base
footprints. The directional animation resolver, character renderer, impact
renderer, draw-order service, and camera manager are presentation services:
they read the synchronized `position.x`, `position.ground_y`, and visual state,
but never move physics bodies, resolve contacts, or change collision data.

Draw order is determined by `entity.position.ground_y`. Sprite bounds,
transparent padding, scale, yaw/squash, and visual overlap do not participate
in collision or depth ordering. This allows a sprite's upper body to overlap
another sprite while the two small base rectangles remain separated by the
physics world.

## Levels and backgrounds

`LevelManager` owns level composition: active profile, spawn, movement bounds,
camera configuration, background layers, and content dependencies. Profiles own
behavior tuning; levels own spatial composition. Backgrounds are loaded through
`ContentManager` and rendered in world space unless a layer explicitly opts into
camera-locked rendering.

For a new level, add a definition under `game_data/levels`, register it in
`GameLoop`, and declare its content dependencies. Do not add a manifest-wide
load call to a gameplay state.

## Rectangle projection / Playground 7

`physics_bumper_lab` selects `projection = "rectangles"`. It opens the same
gravityless `PhysicsCollisionWorld`, but its load request list is empty: no
sprites, animations, backgrounds, audio assets, or masks are needed. Playground
creates one cyan hero rectangle and several colored enemy rectangles using
explicit base footprints, then renders body IDs, velocity vectors, base bounds,
contact normals, and current separation. Arrow keys drive the cyan body. This
is a visualization of the actual gameplay physics scope, not a parallel
collision simulator.
