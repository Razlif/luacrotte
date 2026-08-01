# Agent Guidelines

These rules guide an agent working on the toolkit and on games made with it.
Keep changes small, literal, inspectable, and easy to test. Do not invent new
architecture when an existing system or folder already fits.

## Repository Boundaries

- `game/`: Love2D runtime systems, entities, controllers, and states.
- `game_data/`: editable Lua definitions and generated runtime registries.
- `media_assets/`: game-ready art and audio.
- `asset_lab/`: self-contained asset generation, intake, and inspection.
- `cutscene_engine/`: declarative cutscene playback and scene tools.
- `game_lore/`: story and world context.
- `qa/`: automated checks and Love2D harnesses.
- `dev_tools/`: future export and packaging tools.

When Love2D API behavior is uncertain, query the local reference before
guessing:

```cmd
python dev_tools/love_docs/love_docs.py search camera
python dev_tools/love_docs/love_docs.py lookup love.graphics.captureScreenshot
```

The reference is pinned to Love2D 11.5 and is for agent/developer context;
the game does not load it at runtime.

The repository root is the Love2D source root. Keep root `main.lua` and
`conf.lua` small; route runtime behavior through `game/main.lua` and the state
manager.

## Runtime Rules

- Love callbacks are entry points, not places for game-specific logic.
- Reusable behavior belongs in `game/systems/`; reusable objects belong in
  `game/entities/`; screens belong in `game/game_states/`.
- Use the template's `x`, `ground_y`, and `z` position model for 2.5D.
- Draw order uses ground/bottom Y.
- Collision is mask/sensor overlap reporting only. Game logic decides the
  response; do not add Love2D physics to the MVP.
- Cutscene actors reuse rendering systems but never gameplay controllers, AI,
  or gameplay collision responses.

## Available Runtime Systems

Use these existing systems before adding a new one:

- `states_manager`: title, playground, pause overlay, and cutscene transitions.
- `asset_loader`: loads promoted files through `game_data/asset_manifest.lua`.
- `animation_manager`: sprite-sheet playback driven by `dt`.
- `input_manager`: named held and one-shot actions for gameplay and UI.
- `movement_manager` and `position_manager`: shared controller intent and 2.5D `x`, `ground_y`, `z` movement.
- `draw_order`: stable layer and ground-position sorting.
- `camera_manager` and `parallax`: camera following, bounds, shake, and layered backgrounds.
- `timer_manager`: deterministic delays, repeats, and cooldowns.
- `mask_creation` and `collision_detection`: cached mask/sensor overlap reports only.
- `audio_manager`: named music and sound playback from the generated manifest.
- `ui/`: theme, text, buttons, menus, dialogue cards, and pause UI.
- `save_manager`: versioned local JSON saves, not yet connected to a save menu.
- `qa_telemetry` and `qa_bridge`: event logs, snapshots, screenshots, and validated QA commands.

The current duck, slime, bomb, background, and cutscene are integration
examples. They are disposable demo content, not required game content.

## MotoCrotte Drift Lab

The Playground includes a data-driven visual experiment for the MotoCrotte
hero. Configure drift values and the default mode in
`game_data/characters/motocrotte_hero_main.lua`; configure controls in
`game_data/input_bindings.lua`. The available modes are:

- `flat_rotate`: uses the current hero art and smoothly rotates it through the
  movement heading, with drift rotation layered on top.
- `directional_views`: selects one of the configured directional slots. It
  currently falls back to the existing sprite while the directional artwork
  is unavailable.
- `hybrid`: combines snapped directional slots with a reduced smooth drift
  rotation.

In the Playground, normal movement starts enabled. Press V to enter the
Visual Lab. Inside it, use Q/E to change yaw, Tab to cycle visual modes, and R
to reset. Visual Lab mode bypasses movement and drift mechanics; it tests only
 the sprite's visual orientation. Outside the Visual Lab, use Shift to drift and the
 arrow/WASD controls to move; Space remains available for jump. The modular
 movement solver provides acceleration, coasting, braking by opposite input,
 and profile-owned turning. Drift uses normal/entering/holding/exiting phases,
 preserves momentum on release, derives physical turning radius from speed and
 turn rate, and records its phase, spin direction, radius, and selected diagonal
variant in QA telemetry. Do not add collision response, traffic, or world-scroll
logic to this experiment until the visual and movement behavior is accepted.
The current Playground uses the promoted `motorcycle_direction_full` 16-frame
row-major atlas. The original 8-frame `motorcycle_direction_set` animation is
kept in the same asset for comparison and rollback. Cardinal frame selection
is fixed; diagonal drift variants select from the reviewed source-cell groups.
Use `qa/game_driver/record_visual_*.jsonl` for orientation GIFs,
`qa/game_driver/inspect_motocrotte_orientation.jsonl` for cardinal-heading
checks, `qa/game_driver/record_drift_*.jsonl` for movement/drift GIFs, and
`qa/game_driver/inspect_modular_movement.jsonl` plus
`qa/game_driver/validate_modular_run.py` for modular movement assertions.
Press Tab in the Playground to compare the production `arena_follow` mode
with the experimental `legacy_direct_drift` mode. The legacy mode is an
isolated compatibility experiment and must not replace the modular solver.

## Gameplay Profiles

Gameplay profiles are first-class runtime configuration. Production profiles
live under `game_data/gameplay_profiles/`; experimental profiles may be
developed under `game_data/experiments/gameplay_profiles/` before promotion.
Profiles configure camera behavior, control schema, movement constraints, drift
availability, visual orientation, and transition policy. Levels reference a
profile with `gameplay_profile_id`; the Playground can also receive a profile
ID from the menu or cycle profiles with Tab during normal movement.

The shared systems remain responsible for behavior. Do not create a separate
movement or camera implementation per profile. Add a validated profile option
or adapter when a new experiment needs a capability that the shared system
does not yet expose. QA snapshots should include the active profile ID and
version so runs remain comparable.

## Asset Lab Workflow

1. Read `asset_lab/manifest.json` before an operation.
2. Run `python asset_lab/helpers/validate_lab_assets.py`.
3. If drift exists, inspect with `python asset_lab/helpers/sync_manifest.py --report`.
4. Use `--apply` only to record missing files and orphan files; never guess an
   orphan's meaning.
5. Use dry runs before provider calls.
6. Use exact manifest paths and literal names; never guess a source path.

Asset organization is manifest-driven. Keep physical asset folders stable as
`asset_lab/lab_assets/<type>/<asset_id>/`; do not create arbitrary taxonomy
directories on disk. Use canonical virtual groups for dynamic organization:

```json
"groups": ["vehicles/cars/XL"]
```

Groups may be any safe nested path, may be repeated for multiple collections,
and are created automatically by the browser. New assets must be assigned
groups during creation with repeatable `--group` flags. Legacy
`domain`/`subcategory`/`size_class` metadata is compatibility-only; new
mappings should use `groups`.

Example:

```cmd
python asset_lab/helpers/create_lab_asset.py create-new --type prop --provider self --name dog --prompt "..." --group animals/dogs
```

After intake or creation, run the validator and regenerate `manifest.js`:

```cmd
python asset_lab/helpers/validate_lab_assets.py
python asset_lab/helpers/export_browser_manifest.py
```

AutoSprite is a provider-backed animation route. Upload a reviewed source image
with `prepare-provider-character`, then use `create-spritesheets` for custom
animations. The helper stores provider character, job, and spritesheet IDs,
downloads the sheet and atlas, and creates the Asset Lab GIF preview. Keep
`AUTOSPRITE_API_KEY` in the ignored root `.env`; never copy it into manifests,
traces, prompts, or committed files. Use `--video-tier turbo`, two seconds,
and 16 frames for the first motorcycle test. AutoSprite generation is
asynchronous, so allow the helper to poll until completion.

Creation modes are explicit:

- `brand_new`: text-only creation.
- `with_reference`: creation based on a selected existing image version.
- `create-animation`: animation based on a selected image version.

Promotion is an agent-controlled operation and does not require a separate
approval step. Use `--dry-run` first when the operation is unfamiliar.

```cmd
python asset_lab/helpers/promote_lab_asset.py --operation promote-new --type character --asset-id NAME --image-version 1 --animation jump=1
python asset_lab/helpers/promote_lab_asset.py --operation promote-update --type character --asset-id NAME --image-version 2
```

Promotion updates `media_assets/`, `game_data/promoted_assets.json`, and the
generated `game_data/asset_manifest.lua`. GIF previews stay in Asset Lab.

## Audio Rules

Use `audio_search.py` for metadata-first searches and `audio_import.py` only
for selected candidates. Allowed licenses are CC0 and CC BY. Always preserve
creator, source URL, source ID, license, and attribution text, including for
CC0 assets. API keys stay in `.env`; local catalogs and previews stay ignored.

Promote selected audio with `promote_audio_asset.py`, then regenerate the
runtime manifest. Do not scrape curated sites.

For legacy project audio whose license is unknown, use the dedicated intake:

```cmd
python asset_lab/helpers/import_legacy_audio.py --mapping asset_lab/legacy_mappings/motocrotte/audio_index.json --asset-id ASSET_ID --execute
```

This preserves source provenance and records `license: unknown`; do not claim
that legacy audio is CC0 or CC-BY without evidence. Fonts are staged separately
with `import_legacy_font.py` under `asset_lab/font_library/`. Love2D supports
OTF and TTF through `love.graphics.newFont`, but agents must verify the actual
filename before using it. The MotoCrotte source requests `Ghoust_Solid.otf`,
while the available file is `Ghoust_Outline.otf`.

## Cutscene Rules

Scene files live in `cutscene_engine/scenes/`. Validate before previewing:

```cmd
python cutscene_engine/tools/validate_scene.py duck_slime_date
love . --cutscene duck_slime_date
```

Keep dialogue, movement, camera, effects, music, and sound cues in the scene
timeline. Use literal command names and valid asset IDs.

## Debugging

Useful launch flags are `--debug`, `--debug-masks`, `--debug-sensors`,
`--debug-collisions`, `--debug-entities`, `--debug-camera`, `--debug-input`,
and `--debug-state`.

For a persistent user-and-agent QA session, use:

```cmd
python qa/run_game.py start
python qa/run_game.py status
python qa/run_game.py latest
python qa/run_game.py stop
```

Inspect stable results with `python qa/game_driver/logs.py inspect RUN_ID`
and compare runs with `python qa/game_driver/compare_runs.py OLD_ID NEW_ID`.

For collaborative live inspection, start the managed game and local bridge:

```cmd
python qa/run_game.py start
python qa/run_game.py bridge start
```

Read the run's `bridge.json` for the localhost port and bearer token. Use the
bridge for status, snapshots, incremental events/results, screenshots, and
validated input commands. Never mutate game entities directly and never bind
the bridge beyond `127.0.0.1`.

Bridge command submission is asynchronous. A `202` response means the command
was accepted; wait for its matching result in `results.jsonl` or through the
bridge result endpoint before judging the outcome.

For visual QA recordings, use `record_start` and `record_stop` commands in a
game-driver JSONL recipe. Frames are written under the run's `video/frames/`
folder with telemetry in `video_manifest.jsonl`. Export a shareable GIF with:

```cmd
python qa/video_export.py RUN_ID --format gif
```

MP4 export additionally requires `ffmpeg`. Recordings are visual-only for
now; Love2D QA does not capture system audio.

## Current Status

- Rendering, animation, input, movement, camera, audio, UI, masks, sensors, and report-only collision are wired.
- The playground and one cutscene provide working integration examples.
- Asset Lab supports image, animation, audio search/import, previews, and promotion.
- QA supports scripted runs, persistent sessions, stable logs, screenshots, snapshots, and local agent inspection.
- Physics responses, generic level loading, save menus, settings screens, packaging, and AutoSprite generation remain future work.
