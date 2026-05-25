# Sand Crush AI Agent Guide

This document is a technical handoff for coding agents working on Sand Crush. It focuses on how the game actually behaves in code, which invariants matter, and where to make changes safely.

## 1. What The Game Is

Sand Crush is a Flutter + Flame game with two coupled systems:

1. A placement game that drops the next shape onto an 80x100 grid.
2. A sand-physics simulation that moves connected clusters under gravity, fragments unstable structures, and clears same-color bridges that span left to right.

The core rule is not “clear lines” like Tetris. The clearing rule is “a connected component of one base color touches both the left and right edges.” When that happens, only that connected component is removed.

## 2. Primary Files

The most important implementation surfaces are:

- [lib/game.dart](../lib/game.dart) - main FlameGame, input handling, fixed-timestep loop, rendering orchestration, clear animation, autosave, and state transitions.
- [lib/world.dart](../lib/world.dart) - grid storage, cluster physics, bridge detection, cluster rebuild/merge logic, and save/load helpers for the world representation.
- [lib/models/game_state_dto.dart](../lib/models/game_state_dto.dart) - full and sparse persistence models.
- [lib/services/scoring_service.dart](../lib/services/scoring_service.dart) - score and combo logic.
- [lib/services/difficulty_service.dart](../lib/services/difficulty_service.dart) - unlocked color pool based on score.
- [lib/services/milestone_service.dart](../lib/services/milestone_service.dart) - milestone thresholds and unlock math.
- [lib/services/save_game_service.dart](../lib/services/save_game_service.dart) - Hive-backed sparse save/load.
- [lib/main.dart](../lib/main.dart) - app bootstrap and overlay registration.
- [lib/ui/*.dart](../lib/ui) - main menu, HUD, pause, tutorial, celebration, and game-over overlays.

## 3. High-Level State Machine

The game is easiest to understand as a small state machine controlled by `SandGame`.

### Menu and play states

- The app starts with the main menu overlay active.
- Selecting New Game clears world state, resets score, resumes the engine, and enters gameplay.
- Selecting Continue loads the last saved sparse state, reconstructs clusters, primes dirty tracking, resumes the engine, and enters gameplay.
- Pause overlays call `pauseEngine()` and `resumeEngine()` directly.
- Game over pauses the engine, deletes the save, writes high score and leaderboard data best-effort, and shows the game-over overlay.

### Simulation states inside gameplay

- A tap places the current next piece only when the board is stable, no clear animation is running, and the world is not game over.
- After a successful placement, the game marks that simulation and bridge evaluation are needed.
- Physics runs in fixed 60 Hz steps with a cap on substeps per frame.
- Bridge evaluation only happens once the board transitions back to stable.
- Clearing is animated in two phases; physics is skipped during the animation.
- Game-over evaluation happens only after all clears are finalized and the board is stable.

## 4. World Representation

`SandWorld` stores the authoritative simulation state.

### Cell model

Each occupied cell is represented by a `Cell` with:

- `x`, `y` coordinates.
- `color` for display, including slight shade variation.
- `baseColorId` for logic.

The important split is between display color and logic color:

- `gridColorBuffer` holds the actual ARGB display color for each grid cell.
- `baseColorIdBuffer` holds the color identity used for bridge matching, merging, and save/load reconstruction.

That means two cells can look slightly different but still count as the same logical color.

### Clusters

Cells are grouped into `Cluster` objects. Physics operates on clusters, not individual cells.

Key implications:

- A shape placement creates a new cluster.
- Physics moves clusters down or diagonally.
- If a cluster cannot settle but some of its cells could move as grains, the cluster is broken into 1-cell clusters.
- After the world stabilizes, adjacent same-color singleton clusters are merged back together.

This fragmentation/merge cycle is deliberate. It keeps the simulation physically plausible while reducing permanent over-fragmentation.

## 5. Physics Rules

The world update path is cluster-based gravity.

### Movement order

For each active cluster:

1. Try to move straight down by one cell.
2. If blocked, try one diagonal direction, then the other.
3. If neither cluster move works, check whether the cluster should break apart into grains.

The diagonal direction order is randomized per cluster pass.

### Break-apart rule

`_wouldAnyGrainMoveIfClusterBreaksApart()` checks whether any individual cell in a cluster would be able to fall or slide if the cluster were split. If yes, the cluster is fragmented into single-cell clusters.

This is a key performance and behavior tradeoff:

- It prevents large unsupported structures from staying frozen forever.
- It can produce many singleton clusters.
- The later `mergeAdjacentClusters()` pass is there to recover from that fragmentation when the board becomes stable.

### Stability

The world maintains `isStable`.

- `true` means no cluster movement happened in the last physics pass.
- Bridge clearing, milestone checks, autosave, and game-over evaluation all depend on stability.

Do not move those checks into the physics routine itself. The current design intentionally performs them from `SandGame` after the world stabilizes.

## 6. Placement Rules

The player does not choose an arbitrary block type. The game generates a next shape and a next color.

### Shapes

The next shape is sampled from a small set of base tetromino-like patterns, then scaled based on board size. The preview UI computes bounds so the shape can be shown in a small preview box.

### Color pool

The available color set expands as score milestones are reached.

- Start with 3 colors.
- Each 25,000-point milestone unlocks one more color.
- The pool is capped at 6 colors.

When the player taps the grid:

- The code clamps the shape origin so the full shape fits inside the board.
- Placement fails if any target cell is occupied.
- On success, the piece becomes a cluster and a fresh next piece is generated immediately.
- Placement awards points immediately.

## 7. Bridge Clearing

This is the most important mechanic to preserve.

### Definition

A color bridge clears only when a connected component of that base color touches both the left edge and the right edge of the board.

The connectedness rule uses 8-way adjacency in bridge search, so diagonal links count.

### Why the implementation is careful

The correct behavior is component-based, not seed-based across all left-edge cells at once.

- If multiple left-edge components share the same color, only the component that actually reaches the right edge should clear.
- The clearing routine therefore evaluates one left-edge connected component at a time.

### Runtime flow

After the world becomes stable:

1. Adjacent same-color singleton clusters are merged.
2. Combo tracking begins.
3. Each currently available color is tested for a spanning bridge.
4. Any cleared cells are accumulated into one combined clear animation.
5. The score service awards bridge points.
6. If no bridges were found, the combo session ends.

### Clearing animation

Clearing is delayed visually:

- First a short flash.
- Then a left-to-right wave fade.
- When the animation ends, `SandWorld.finalizeClear()` removes the cleared cells from the authoritative world state.

Do not delete cells from the world immediately when the bridge is detected. The animation and finalization are intentionally separated.

## 8. Game Over Rule

Game over is not checked during active physics or mid-clear.

The board is considered lost when any occupied cell reaches the top threshold region, which is the top 15% of rows.

Important invariant:

- Game-over evaluation happens only after clearing is complete, the world is stable, and no simulation is pending.

This prevents false positives during transient post-clear motion.

## 9. Scoring And Progression

### Score service

`ScoringService` is a singleton with a notifier-backed integer score.

Relevant behaviors:

- Placement awards a flat base amount.
- Clearing awards base points multiplied by `sqrt(pileSize)` and a combo bonus.
- Combo bonus increases by 10% per additional clear in the same session.
- `startClearSession()` begins a new combo session.
- `endClearSessionIfNoBridges(false)` ends the combo when no bridge was found in the current stable phase.

### Milestones

Milestones are every 25,000 points.

- HUD progress bar animates between the current and next milestone.
- Crossing a new milestone can trigger the celebration overlay and a badge.
- Each milestone also unlocks one more playable color.

## 10. Saving And Loading

Saving is sparse and binary.

### Save model

The project has two DTOs:

- `GameStateDTO` stores full grid and base-color arrays.
- `SparseGameStateDTO` stores only occupied runs, which is what the live save system uses.

### Sparse format

Sparse saves store:

- board dimensions,
- top occupied row,
- score,
- run count,
- per-run metadata: row, first column, run length, representative color, and base color ID.

The live save path is intentionally optimized for IO and size.

### Load flow

On load:

1. The sparse save is decoded.
2. The world grid buffers are reconstructed.
3. Clusters are rebuilt from the raw buffers.
4. Dirty tracking is primed so the next sync can detect cleared cells correctly.
5. The score is restored.
6. A new next piece is generated.

### Critical load invariant

After loading a save, call both:

- `rebuildClusters()`
- `primeDirtyTracking()`

Then call `syncGridNow()`.

Skipping those steps can leave stale pixels or break the first post-load sync.

## 11. Rendering Pipeline

Rendering is designed to avoid rebuilding the whole grid every frame.

Key ideas:

- Vertices and colors are preallocated.
- The grid is chunked into fixed tiles so only dirty chunks need to rebuild `Vertices.raw` objects.
- The background and grid lines are cached as pictures.
- The “NEXT” label is cached with a `TextPainter`.

If you are editing render code, preserve the dirty-chunk flow. A naive full-grid rebuild will make the game much more expensive on large boards.

## 12. Autosave

Autosave is debounced by placements, not by time.

- Every successful placement increments a counter.
- After 5 placements, the game marks an autosave as pending.
- The save is written only when the board is stable and no simulation is pending.
- Concurrent save calls are serialized with a small in-flight guard and pending buffer.

This means the save system is intentionally conservative and tied to stable board state.

## 13. UI Overlays

The UI is built with Flame overlays.

- Main menu: start, continue, leaderboard, tutorial.
- HUD: score, progress to next milestone, pause button.
- Pause: resume, restart, return to menu, tutorial.
- Tutorial: explains placement, gravity, bridge rules, and clearing.
- Celebration: milestone unlock acknowledgment.
- Game over: final score, best score, leaderboard, retry, menu.

The overlay names are centralized in `GameConfig`.

## 14. What To Be Careful About

These are the main invariants that should survive future edits:

1. Bridge clearing must be component-based per left-edge seed, not a blanket same-color scan from all edge cells.
2. Game-over checks must happen after clearing and stabilization, not inside the physics loop.
3. Display colors and logic colors are separate; do not use ARGB matching for gameplay rules.
4. Post-load cluster rebuilds must prime dirty tracking before the next sync.
5. Clearing animation must finalize world mutation only after the animation completes.
6. The world should remain stable before autosave, bridge evaluation, and game-over checks run.
7. Keep the fixed-timestep loop and substep cap intact unless you are intentionally changing simulation feel and performance.

## 15. Useful Test Signals

Current tests already cover a few important regressions:

- Sparse save should not merge across empty cells.
- Rebuilding clusters should treat same-base-color shades as one cluster.
- Cluster rebuild should not wrap row edges.
- Dirty tracking after load should populate dirty indices on the next sync.

If you change bridge detection, save/load, or dirty sync, add or update tests near those behaviors.

## 16. Recommended Change Strategy For Agents

When editing this project:

1. Find the controlling abstraction first, usually `SandGame` or `SandWorld`.
2. Preserve the stability-driven state transitions.
3. Prefer small changes near the current mechanic rather than broad rewrites.
4. Validate with the narrowest test that exercises the touched behavior.
5. If a change affects persistence or bridge logic, verify load/save and bridge-clearing regressions explicitly.

This codebase favors performance-aware implementations, so correctness changes that add allocations or full-grid scans should be justified carefully.
