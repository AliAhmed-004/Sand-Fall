# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Sand Crush is a sand-physics puzzle game built with Flutter and Flame. Players place sand chunks onto an 80x100 grid, where they fall under cluster-based gravity and can fragment. The goal is to create same-color bridges spanning left-to-right to clear them and score points.

## Build & Run Commands

```bash
flutter pub get          # Fetch dependencies
flutter run              # Run on connected device/emulator
flutter run -d chrome    # Run on specific platform
flutter analyze          # Static analysis
flutter test             # Run tests
```

## Architecture

### Core Files

- `lib/main.dart` — App bootstrap, Hive initialization, Flame `GameWidget` with overlay routing
- `lib/game.dart` (`SandGame`) — Main FlameGame subclass. Handles input (tap-to-place), fixed-timestep physics loop, batched vertex rendering, clearing animations, and save/load orchestration
- `lib/world.dart` (`SandWorld`) — Grid buffers, cluster physics, bridge detection, game-over threshold. Uses two buffers for the grid: `gridColorBuffer` (display colors with variations) and `baseColorIdBuffer` (0–5 for logic matching)
- `lib/config/game_config.dart` — Overlay name constants and Hive box/key names
- `lib/models/game_state_dto.dart` — `GameStateDTO` (full grid) and `SparseGameStateDTO` (run-length encoded for efficient saving)

### Services (`lib/services/`)

| Service | Responsibility |
|---------|----------------|
| `ScoringService` | Singleton score tracking, combo multiplier |
| `SaveGameService` | Debounced autosave (every 5 placements), binary sparse encoding via Hive |
| `HighScoreService` | Persists high score across sessions |
| `MilestoneService` / `DifficultyService` | Unlock colors at score milestones |

### UI Overlays (`lib/ui/`)

Managed by Flame overlays system. Each is a `StatelessWidget` that receives the `SandGame` instance:
- `MainMenuOverlay` — Start / Continue
- `HudOverlay` — Score display
- `PauseOverlay` — Pause / resume / restart
- `CelebrationOverlay` — Triggered on milestone unlock
- `GameOverOverlay` — Final score and restart

### Rendering Pipeline (in `SandGame`)

The game uses a highly optimized batched rendering approach:

1. `Float32List _vertices` and `Int32List _colors` are pre-allocated once and updated incrementally
2. `_cachedVertices` is rebuilt only when `_needsVertexUpdate` is true
3. `canvas.drawVertices()` draws all 8000 cells in a single call
4. Grid lines and background are cached as `ui.Picture` and replayed with `canvas.drawPicture()`

### Physics Model (`SandWorld`)

- **Cluster-based gravity**: Cells are grouped into `Cluster` objects. Physics runs on clusters, not individual cells
- **Fragmentation**: When a cluster can't settle, `_breakApartCluster` splits it into 1-cell clusters
- **Active list optimization**: Only clusters that might move are processed each sub-step
- **Post-stability merging**: After the board stabilizes, `mergeAdjacentClusters()` combines same-color singleton clusters to reduce fragmentation
- **Fixed timestep**: 60 Hz physics with max 2 sub-steps per frame to prevent spiral-of-death

### Bridge Clearing

- `doesColorSpanLeftToRight(color)` / `clearSpanningBridge(color)` use BFS from the left edge
- Edge color sets (`_leftEdgeColors`, `_rightEdgeColors`) are maintained during grid sync for O(1) quick-reject before BFS
- Clearing is animated in two phases: a 50ms global flash, then a 300ms left-to-right wave fade

### Save System

- Uses `SparseGameStateDTO`: stores runs of consecutive same-color cells, not the full 8000-cell grid
- On load, color variations are regenerated deterministically from cell position (same algorithm as `_varyColor`)
- Debounced: autosave triggers only after 5 successful placements and only when the board is stable
