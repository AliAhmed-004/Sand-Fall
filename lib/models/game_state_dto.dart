import 'package:flutter/material.dart';
import 'package:sandfall/world.dart';

/// Data Transfer Object for the game state, used for saving and loading the game.
class GameStateDTO {
  final int cols;
  final int rows;
  final List<int> grid; // flattened ARGB values (display colors)
  final List<int> baseColorIds; // base color IDs for matching logic

  GameStateDTO({
    required this.cols,
    required this.rows,
    required this.grid,
    required this.baseColorIds,
  });

  factory GameStateDTO.fromWorld(SandWorld world) {
    return GameStateDTO(
      cols: world.cols,
      rows: world.rows,
      grid: world.gridColorBuffer.toList(growable: false),
      baseColorIds: world.baseColorIdBuffer.toList(growable: false),
    );
  }
}

/// Sparse representation of the game state for efficient saving.
/// Stores runs of same-baseColorId cells with one representative color.
/// Color variations are regenerated deterministically on load using the
/// same variation algorithm used during placement.
class SparseGameStateDTO {
  final int cols;
  final int rows;
  final int topRow;
  final List<SparseCellRun> runs;

  SparseGameStateDTO({
    required this.cols,
    required this.rows,
    required this.topRow,
    required this.runs,
  });

  /// Collects sparse runs from the world, scanning bottom-up and stopping
  /// when a fully empty row is found.
  factory SparseGameStateDTO.fromWorld(SandWorld world) {
    final runs = <SparseCellRun>[];
    final cols = world.cols;
    final rows = world.rows;
    final grid = world.gridColorBuffer;
    final baseIds = world.baseColorIdBuffer;

    // Scan from bottom to top, stop when we hit a fully empty row
    for (int y = rows - 1; y >= 0; y--) {
      bool hasContent = false;

      // Scan row to find runs of same baseColorId
      int x = 0;
      while (x < cols) {
        final idx = y * cols + x;
        if (grid[idx] != 0) {
          hasContent = true;
          final baseColorId = baseIds[idx];
          final startX = x;
          final color = grid[idx]; // Use first cell's color as run reference

          // Count run length: consecutive cells with same baseColorId
          int runLength = 1;
          while (x + runLength < cols) {
            final nextIdx = idx + runLength;
            if (grid[nextIdx] == 0) break;
            if (baseIds[nextIdx] != baseColorId) break;
            runLength++;
          }

          runs.add(
            SparseCellRun(
              row: y,
              firstCol: startX,
              runLength: runLength,
              color: color,
              baseColorId: baseColorId,
            ),
          );

          x += runLength;
        } else {
          x++;
        }
      }

      // Stop early if we hit a fully empty row (optimization)
      if (!hasContent) break;
    }

    // Determine topRow from the first (highest y index, i.e., lowest row) run
    final topRow = runs.isEmpty ? 0 : runs.last.row;

    return SparseGameStateDTO(
      cols: cols,
      rows: rows,
      topRow: topRow,
      runs: runs,
    );
  }

  /// Reconstructs a full grid from sparse runs into the world.
  /// Color variations are regenerated deterministically using the same
  /// variation algorithm as during placement.
  void applyToWorld(SandWorld world) {
    // Clear grid first
    world.gridColorBuffer.fillRange(0, world.gridColorBuffer.length, 0);
    world.baseColorIdBuffer.fillRange(0, world.baseColorIdBuffer.length, 0);

    // Get base colors for regeneration
    final baseColors = [
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.blue,
      Colors.purple,
    ];

    // Fill in runs, regenerating color variations deterministically
    for (final run in runs) {
      final baseColor = baseColors[run.baseColorId];
      final baseIdx = run.row * cols + run.firstCol;

      for (int i = 0; i < run.runLength; i++) {
        final idx = baseIdx + i;
        world.baseColorIdBuffer[idx] = run.baseColorId;

        // Regenerate color variation using same algorithm as _varyColor
        // Uses cell position as seed for deterministic variation
        final cellX = run.firstCol + i;
        final cellY = run.row;
        final variedColor = _varyColorDeterministic(baseColor, cellX, cellY);
        world.gridColorBuffer[idx] = variedColor.toARGB32();
      }
    }
  }

  /// Regenerates a color variation deterministically based on cell position.
  /// Uses position-based seeding so the same cell always gets the same shade.
  Color _varyColorDeterministic(Color baseColor, int x, int y) {
    // Simple deterministic pseudo-random using position
    final seed = x * 374761393 + y * 1234567891;

    // Vary hue slightly (±2 degrees for subtle variation)
    final hueVariation = ((seed % 100) - 50) / 25; // -2 to +2
    final hsv = HSVColor.fromColor(baseColor);
    final newHue = (hsv.hue + hueVariation) % 360;

    // Vary saturation slightly (±5%)
    final satVariation = ((seed >> 8) % 20 - 10) / 200; // -0.05 to +0.05
    final newSaturation = (hsv.saturation + satVariation).clamp(0.0, 1.0);

    // Vary value slightly (±8%)
    final valueVariation = ((seed >> 16) % 32 - 16) / 200; // -0.08 to +0.08
    final newValue = (hsv.value + valueVariation).clamp(0.0, 1.0);

    return HSVColor.fromAHSV(
      hsv.alpha,
      newHue,
      newSaturation,
      newValue,
    ).toColor();
  }
}

/// A run of consecutive same-baseColorId cells in a single row.
class SparseCellRun {
  final int row;
  final int firstCol;
  final int runLength;
  final int color; // ARGB value (representative color, used as reference)
  final int baseColorId;

  SparseCellRun({
    required this.row,
    required this.firstCol,
    required this.runLength,
    required this.color,
    required this.baseColorId,
  });
}
