# Luacrotte To-Do

This is the living, deliberately small backlog for the game. Add items only
when they are actually requested or discovered during QA. Move an item to
**Done** only with a verification note or a commit reference.

## Immediate next

- [ ] Audition the six staged music and motorcycle/drift sound candidates in
  Asset Lab; choose the first music loop and the first engine/skid set to keep.
- [ ] Promote only the approved audio, wire it through the audio manifest, and
  run a gameplay QA pass that verifies event triggering and volume balance.
- [ ] Add the selected base music track and driving sound effects to the
  Playground.
- [ ] Define and validate the usable screen bounds for each background/profile.
- [ ] Add the wheelie gameplay state.
- [ ] Fix the dash behavior.
- [ ] Review the current `experiment/drift-dash-wheelie` branch as a coherent
  playable baseline, then decide whether it should fast-forward into `main`.

## Next: playground and movement lab

- [ ] Run a focused visual QA pass for gameplay profiles 1-4 after the current
  branch review: spawn visibility, camera framing, background coverage, bounds,
  and profile switching.
- [ ] Decide which of the playground profiles are retained as game-facing
  profiles and which remain experiments.
- [ ] Tune the retained profile's acceleration, coasting, braking frame state,
  drift radius, and dash transition from recorded QA runs.
- [ ] Return to the drift-plus-dash entry glitch only after the retained
  baseline is protected; it remains an experiment, not a blocker.
- [ ] Add the first shooting gameplay loop.
- [ ] Add and validate one enemy against the shooting loop.
- [ ] Experiment with tiles for a larger Playground space.

## Later: game content foundation

- [ ] Finish the source-faithful lore inventory: characters, places, props,
  plot beats, checkpoints, and scene hooks - without filling gaps in the source.
- [ ] Create a game-lore wiki from the reviewed source-faithful inventory.
- [ ] Choose a first small playable level built around one retained gameplay
  profile.
- [ ] Add level composition/background rules and only the collision responses
  needed by that first level.
- [ ] Define traffic/enemy encounters after movement, bounds, and camera feel
  are accepted.
- [ ] Build the first game-facing cutscene from the lore inventory and validate
  it with the existing cutscene QA recording workflow.

## Later: product readiness

- [ ] Connect versioned saves to a player-facing save flow.
- [ ] Add settings, including audio controls.
- [ ] Add packaging/export workflow and release QA.

## Parking lot / open design questions

- [ ] Decide whether diagonal directional variants should remain random during
  drift in the final game, or use a deterministic/seeded policy.
- [ ] Decide whether gameplay profiles can change within a level, or are
  selected only per level/scene.
- [ ] Define the final role of rear-view profile 4 after more environment art
  exists.

## Done

- [x] Asset Lab supports reviewed image/animation intake, audio candidate
  search/import, previews, and promotion.
- [x] MotoCrotte media has been mapped and staged into Asset Lab by domain.
- [x] The Playground has data-driven movement, camera, control, animation, and
  background experiment controls.
- [x] Gameplay profiles 1-4 exist as playable experiments with QA recipes.
- [x] QA can capture screenshots and GIF recordings.
- [x] First vetted audio audition set staged in Asset Lab (CC0/CC-BY metadata
  retained; not promoted).
