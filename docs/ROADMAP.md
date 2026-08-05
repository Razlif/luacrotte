# Luacrotte Mini Roadmap

This roadmap describes known sequencing, not promises or invented content.
It is driven by the living [to-do list](TODO.md).

## 1. Lock a playable driving baseline

**Goal:** one reviewed playground profile that feels intentional and can become
the foundation of the first level.

**Inputs already available:** modular movement/drift systems, directional
motorcycle frames, four profile experiments, fixed-camera options, QA
screenshots/GIFs.

**Exit condition:** a chosen profile has accepted camera framing, bounds,
movement, braking, drift, and dash behavior in a recorded QA run.

## 2. Establish the sound identity

**Goal:** a small, licensed audio set for the driving baseline.

**Inputs already available:** Asset Lab audio audition candidates, provenance
and license metadata, audio promotion tooling, runtime audio manager.

**Exit condition:** selected music, engine, and drift/skid sounds are promoted,
credited where required, wired to the appropriate game events, and checked in
runtime QA.

## 3. Build one vertical slice

**Goal:** a short, repeatable playable sequence - not a full game world.

**Work:** source-faithful lore inventory -> first level choice -> environment
and encounter rules -> minimal collision/response -> start/end condition.

**Exit condition:** a player can enter, drive through, encounter the intended
content, and finish or fail the slice; screenshots/GIF QA document the run.

## 4. Add story presentation

**Goal:** connect the vertical slice to the existing story material without
inventing lore before the source inventory is complete.

**Work:** one cutscene or narrative beat using the cutscene engine, scene
assets, dialogue, and audio cues.

**Exit condition:** scene validation and a cutscene QA recording both pass.

## 5. Expand deliberately

**Goal:** add profiles, levels, enemies, assets, and progression only after the
vertical slice gives us a stable production pattern.

**Work:** profile-specific levels, additional audio/visual assets, progression,
saves/settings, packaging.

**Exit condition:** each added feature has a clear gameplay reason, data-owned
configuration, and a matching QA scenario.

## Current constraints

- The active work is on `experiment/drift-dash-wheelie`; review before merging
  because the branch includes desired profile work and an unfinished
  drift-plus-dash experiment.
- Legacy MotoCrotte audio has unknown licensing. Use only vetted CC0/CC-BY
  assets unless provenance is established.
- Collision response, generic level loading, save UI, settings UI, and
  packaging are intentionally not current foundation work.
