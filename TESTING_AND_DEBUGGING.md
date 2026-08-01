# Testing And Debugging

## Automated Tests

Run the Python suites from the repository root:

```cmd
python -m unittest qa.asset_checks.test_asset_lab qa.game_checks.test_cutscene_engine
```

Run all Python checks:

```cmd
python -m unittest discover -s . -p "test_*.py"
```

Run the Love2D harness from `qa/love_checks`:

```cmd
cd qa/love_checks
love .
cd ../..
```

Use `python3` instead of `python` on Linux/macOS. Set `LOVE_EXECUTABLE` if
Love2D is installed outside `PATH`.

Validate a cutscene by ID:

```cmd
python cutscene_engine/tools/validate_scene.py duck_slime_date
```

Validate Asset Lab files and regenerate its browser manifest when needed:

```cmd
python asset_lab/helpers/validate_lab_assets.py
python asset_lab/helpers/export_browser_manifest.py
```

## Debug Flags

Run the game with any combination of:

```cmd
love . --debug
love . --debug-input --debug-camera --debug-state
love . --debug-masks --debug-sensors --debug-collisions
```

The flags show input, camera, state, entity, mask, sensor, and collision
information without changing gameplay responses. Collision remains report-only.

## Agent QA Driver

The file-based QA driver can run a cutscene and collect events, a final state,
and a matching screenshot:

```cmd
python qa/game_driver/drive_game.py --cutscene duck_slime_date
```

Provide a JSONL actions file for gameplay or scripted control:

```json
{"id":"move_1","command":"hold","key":"right","duration":0.8}
{"id":"view_1","command":"snapshot","name":"after_move"}
```

Then run:

```cmd
python qa/game_driver/drive_game.py --commands path/to/commands.jsonl
```

Each run is stored under `qa/runtime_logs/` with `events.jsonl`,
`results.jsonl`, snapshots, screenshots, and a final report. Runtime logs are
local QA artifacts and are ignored by Git. Use `python3` on Linux/macOS.

The modular movement and drift checks cover acceleration, coasting, drift
phase transitions, spin direction, continuous animation phase, turning radius,
momentum preservation, and randomized diagonal variants:

```cmd
python qa/game_driver/drive_game.py --commands qa/game_driver/inspect_modular_movement.jsonl --run-id modular_movement
python qa/game_driver/validate_modular_run.py qa/runtime_logs/modular_movement
python qa/game_driver/drive_game.py --commands qa/game_driver/record_modular_drift.jsonl --run-id modular_drift
python qa/video_export.py modular_drift --format gif --preview
```

The arena profile enables drift. The beat-em-up lane and side-scroller
profiles use the same schema with drift disabled. During manual testing use
arrows/WASD to move, hold Shift to drift, Q/E and K/M for the visual orbit
experiment, Tab to cycle profiles or modes, and R to reset.

To inspect the previous direct-drift behavior, use Tab twice from the default
arena profile to select `Legacy: Direct Drift`, or run:

```cmd
python qa/game_driver/drive_game.py --commands qa/game_driver/inspect_legacy_movement_mode.jsonl --run-id legacy_movement_mode
```

## Managed QA Session

Use the process manager when the user wants to keep one game session open for
manual play and agent inspection:

```cmd
python qa/run_game.py start
python qa/run_game.py status
python qa/run_game.py latest
python qa/run_game.py stop
```

The manager records the Love2D process, run ID, executable, project path,
stdout, stderr, and QA artifacts. It does not add networking; the existing
file bridge remains the game-facing command transport.

## Live Agent Bridge

Start a managed session, then expose that session to a local agent over
localhost HTTP:

```cmd
python qa/run_game.py start
python qa/run_game.py bridge start
python qa/run_game.py bridge status
python qa/run_game.py bridge stop
```

The bridge prints no continuous stream. It provides token-protected endpoints
for status, snapshots, incremental events/results, latest screenshots, and
commands. The token and port are stored in the active run's `bridge.json`.
The agent uses the existing QA command format and the game still receives
commands through `InputManager`.

This is a local collaboration tool, not a public server. It binds only to
`127.0.0.1`; do not expose it to a network. Use the run folder's `bridge.log`
and `stdout.log`/`stderr.log` when startup fails.

The dependency-free client can query it from another terminal:

```cmd
python qa/game_driver/bridge_client.py qa/runtime_logs/RUN_ID/bridge.json status
python qa/game_driver/bridge_client.py qa/runtime_logs/RUN_ID/bridge.json events
python qa/game_driver/bridge_client.py qa/runtime_logs/RUN_ID/bridge.json send "{\"id\":\"move_1\",\"command\":\"press\",\"key\":\"right\"}"
```

Available bridge operations are status, latest snapshot, incremental events,
incremental results, latest screenshot, and validated command submission. The
bridge does not directly edit entities or bypass `InputManager`.

Command submission is asynchronous: an accepted command is not complete until
its matching record appears in `results.jsonl`. Poll `results` or `events` and
carry the returned `next` cursor into the next request.

## Common Failures

- **Asset missing:** read `game_data/asset_manifest.lua`, then confirm the
  referenced file exists under `media_assets/`.
- **Manifest drift:** run `sync_manifest.py --report`; do not guess orphan
  meanings.
- **Browser is stale:** regenerate `asset_lab/manifest.js` and refresh the page.
- **Audio does not play:** check the runtime path, logical ID, file format, and
  generated audio manifest. Check attribution metadata before replacing files.
- **Wrong camera framing:** inspect entity position, camera target, bounds, and
  window dimensions with `--debug-camera`.
- **Input does not work:** use `--debug-input`; controllers should query named
  InputManager actions, not Love keyboard state directly.
- **Cutscene command fails:** validate the scene and check actor, animation,
  effect, sound, and music IDs against the runtime manifest.
- **Sprite collision looks wrong:** enable mask and sensor debugging. Sensors
  are broad prechecks; masks provide the pixel overlap report.

Keep traces, test output, and error messages attached to the change being
debugged. Do not commit API keys, local audio catalogs, previews, or save files.
