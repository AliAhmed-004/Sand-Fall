import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sandfall/services/scoring_service.dart';

/// -----------------------------
/// CELL MODEL
/// -----------------------------
class Cell {
  int x;
  int y;
  final Color color; // Display color (with variations)
  final int baseColorId; // Base color ID (0-5) for logic matching

  Cell(this.x, this.y, this.color, this.baseColorId);
}

/// -----------------------------
/// CLUSTER MODEL
/// -----------------------------
class Cluster {
  final int id;
  final List<Cell> cells;

  Cluster({required this.id, required this.cells});
}

/// -----------------------------
/// WORLD
/// -----------------------------
class SandWorld {
  final int cols;
  final int rows;

  /// Optimized grid for rendering: flat ABGR/ARGB color buffer (display colors with variations)
  final Uint32List gridColorBuffer;

  /// Base color ID buffer: tracks which base color (0-5) each cell belongs to
  /// Used for all color matching logic (clearing, bridges, etc.)
  final Uint8List baseColorIdBuffer;

  /// Active clusters in the world
  final Map<int, Cluster> clusters = {};

  /// Optimized lookup: index (y * cols + x) → clusterId
  /// Value of 0 means empty.
  final Int32List cellIdMap;

  // Singleton Random instance to avoid allocations in physics loop
  static final Random _random = Random();

  int _nextClusterId = 1;

  bool _isStable = true;
  bool get isStable => _isStable;

  bool _isGameOver = false;
  bool get isGameOver => _isGameOver;

  // Top 10% threshold: if sand reaches this row from the top, game is over
  late int _gameOverThresholdRow;
  int get gameOverThresholdRow => _gameOverThresholdRow;

  // Performance optimization: cached cluster list
  late List<Cluster> _cachedClusterList;
  int _lastKnownClusterCount = 0;

  // Dirty region tracking with reusable buffers to avoid per-frame Set allocations
  late Int32List _previousFrameCellIndices;
  int _previousFrameCellCount = 0;
  late Int32List _currentFrameCellIndices;
  int _currentFrameCellCount = 0;
  late Int32List _lastDirtyCellIndices;
  int _lastDirtyCellCount = 0;

  Int32List get lastDirtyCellIndices => _lastDirtyCellIndices;
  int get lastDirtyCellCount => _lastDirtyCellCount;

  // Bridge detection optimization: cache which colors touch edges
  late Set<int> _leftEdgeColors;
  late Set<int> _rightEdgeColors;

  // Reusable BFS buffers to avoid per-call allocations in bridge checks.
  late Uint32List _visitStampBuffer;
  int _visitStamp = 1;
  late Int32List _bfsQueue;
  int _bfsHead = 0;
  int _bfsTail = 0;
  late Int32List _clearIndicesBuffer;
  int _clearIndicesCount = 0;

  // Pre-allocated neighbor offsets (computed once per world) to avoid repeated allocations.
  late List<int> _eightWayNeighbors;

  /// Track recently cleared cell indices for animation purposes
  final List<int> lastClearedIndices = [];

  // Only process clusters that might move (saves huge CPU when board is mostly settled)
  final List<Cluster> _activeClusters = [];
  bool _activeListDirty = true;
  final _WorldPerfMeter _perfMeter = _WorldPerfMeter('SandWorld');

  SandWorld({required this.cols, required this.rows})
    : gridColorBuffer = Uint32List(cols * rows),
      baseColorIdBuffer = Uint8List(cols * rows),
      cellIdMap = Int32List(cols * rows) {
    _isStable = true;
    _cachedClusterList = [];
    _previousFrameCellIndices = Int32List(cols * rows);
    _currentFrameCellIndices = Int32List(cols * rows);
    _lastDirtyCellIndices = Int32List(cols * rows * 2);
    _leftEdgeColors = <int>{};
    _rightEdgeColors = <int>{};
    _visitStampBuffer = Uint32List(cols * rows);
    _bfsQueue = Int32List(cols * rows);
    _clearIndicesBuffer = Int32List(cols * rows);
    _eightWayNeighbors = [
      1,
      -1,
      cols,
      -cols,
      cols + 1,
      cols - 1,
      -cols + 1,
      -cols - 1,
    ];
    _gameOverThresholdRow = (rows * 0.1).ceil(); // Top 10% of rows
  }

  // =========================================================
  // PRIVATE HELPERS
  // =========================================================

  bool _wouldAnyGrainMoveIfClusterBreaksApart(Cluster cluster) {
    // If the cluster is a single cell, it's already a grain.
    if (cluster.cells.length <= 1) return false;

    for (final cell in cluster.cells) {
      final x = cell.x;
      final y = cell.y;

      // Falling straight down.
      final belowY = y + 1;
      if (belowY < rows) {
        final belowIdx = belowY * cols + x;
        if (cellIdMap[belowIdx] == 0) {
          return true;
        }
      }

      // Diagonal slide (only relevant if straight-down is blocked).
      if (belowY >= rows) continue;
      final belowIdx = belowY * cols + x;
      if (cellIdMap[belowIdx] == 0) continue;

      final twoBelowY = y + 2;

      // Down-left.
      final leftX = x - 1;
      if (leftX >= 0) {
        final downLeftIdx = belowY * cols + leftX;
        if (cellIdMap[downLeftIdx] == 0) {
          if (twoBelowY >= rows) {
            return true;
          }
          final supportIdx = twoBelowY * cols + leftX;
          if (cellIdMap[supportIdx] != 0) {
            return true;
          }
        }
      }

      // Down-right.
      final rightX = x + 1;
      if (rightX < cols) {
        final downRightIdx = belowY * cols + rightX;
        if (cellIdMap[downRightIdx] == 0) {
          if (twoBelowY >= rows) {
            return true;
          }
          final supportIdx = twoBelowY * cols + rightX;
          if (cellIdMap[supportIdx] != 0) {
            return true;
          }
        }
      }
    }

    return false;
  }

  /// Maps a base Color to its color ID (0-5)
  int _getColorId(Color color) {
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.blue,
      Colors.purple,
    ];
    final colorVal = color.toARGB32();
    return colors.indexWhere((c) => c.toARGB32() == colorVal);
  }

  /// Attempts to match an ARGB value to a base color ID by finding the closest match
  /// Used when reconstructing from saved games that might have color variations
  int _getColorIdFromValue(int colorValue) {
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.blue,
      Colors.purple,
    ];

    // If exact match, use it
    for (int i = 0; i < colors.length; i++) {
      if (colors[i].toARGB32() == colorValue) return i;
    }

    // Otherwise find closest by RGB distance
    // Extract RGB components from ARGB value
    final targetR = (colorValue >> 16) & 0xFF;
    final targetG = (colorValue >> 8) & 0xFF;
    final targetB = colorValue & 0xFF;

    int closestIdx = 0;
    double closestDistance = double.maxFinite;

    for (int i = 0; i < colors.length; i++) {
      final c = colors[i];
      final cVal = c.toARGB32();
      final cR = (cVal >> 16) & 0xFF;
      final cG = (cVal >> 8) & 0xFF;
      final cB = cVal & 0xFF;

      final dr = (cR - targetR).toDouble();
      final dg = (cG - targetG).toDouble();
      final db = (cB - targetB).toDouble();
      final distance = dr * dr + dg * dg + db * db;

      if (distance < closestDistance) {
        closestDistance = distance;
        closestIdx = i;
      }
    }

    return closestIdx;
  }

  /// Varies the color slightly to add visual depth. Creates subtle shade variations
  /// of the same hue so cells have slightly different tones.
  Color _varyColor(Color baseColor) {
    final hsv = HSVColor.fromColor(baseColor);

    // Vary hue slightly (±2 degrees for subtle variation)
    final hueVariation = (_random.nextDouble() - 0.5) * 4;
    final newHue = (hsv.hue + hueVariation) % 360;

    // Vary saturation slightly (±5% for subtle depth)
    final satVariation = (_random.nextDouble() - 0.5) * 0.1;
    final newSaturation = (hsv.saturation + satVariation).clamp(0.0, 1.0);

    // Vary value (brightness) slightly (±8% for tonal variation)
    final valueVariation = (_random.nextDouble() - 0.5) * 0.16;
    final newValue = (hsv.value + valueVariation).clamp(0.0, 1.0);

    return HSVColor.fromAHSV(
      hsv.alpha,
      newHue,
      newSaturation,
      newValue,
    ).toColor();
  }

  // =========================================================
  // PUBLIC API
  // =========================================================

  /// Checks if a shape can be placed at the given position without overlapping.
  /// Position will be adjusted to fit within bounds. Returns true if all cells are empty.
  bool canPlace(List<Point<int>> offsets, int originX, int originY) {
    if (offsets.isEmpty) return false;

    int minX = 0, maxX = 0, minY = 0, maxY = 0;
    for (final o in offsets) {
      if (o.x < minX) minX = o.x;
      if (o.x > maxX) maxX = o.x;
      if (o.y < minY) minY = o.y;
      if (o.y > maxY) maxY = o.y;
    }

    final adjustedX = originX.clamp(-minX, cols - 1 - maxX);
    final adjustedY = originY.clamp(-minY, rows - 1 - maxY);

    // Check if all cells are empty
    for (final o in offsets) {
      final x = adjustedX + o.x;
      final y = adjustedY + o.y;

      if (!isInside(x, y)) return false;
      if (cellIdMap[y * cols + x] != 0) return false; // Cell already occupied
    }

    return true;
  }

  /// Checks if a single cell can be placed at the given position.
  bool canPlaceCell(int x, int y) {
    if (!isInside(x, y)) return false;
    return cellIdMap[y * cols + x] == 0;
  }

  void placeCell(int x, int y, Color color) {
    if (!canPlaceCell(x, y)) return;
    final colorId = _getColorId(color);
    _createCluster([Cell(x, y, _varyColor(color), colorId)]);
  }

  /// Attempts to place a shape. Returns true if successful, false otherwise.
  bool placeShape(
    List<Point<int>> offsets,
    int originX,
    int originY,
    Color color,
  ) {
    if (!canPlace(offsets, originX, originY)) return false;

    // add placement points for each cell placed
    ScoringService.instance.addBlockPlacementPoints();

    // Adjust position to fit within bounds
    int minX = 0, maxX = 0, minY = 0, maxY = 0;
    for (final o in offsets) {
      if (o.x < minX) minX = o.x;
      if (o.x > maxX) maxX = o.x;
      if (o.y < minY) minY = o.y;
      if (o.y > maxY) maxY = o.y;
    }

    // Clamp origin to ensure shape fits within bounds
    final adjustedX = originX.clamp(-minX, cols - 1 - maxX);
    final adjustedY = originY.clamp(-minY, rows - 1 - maxY);

    // Create cells for the shape with color variations
    final colorId = _getColorId(color);
    final cells = offsets.map((o) {
      return Cell(adjustedX + o.x, adjustedY + o.y, _varyColor(color), colorId);
    }).toList();

    _createCluster(cells);
    return true;
  }

  void update(double dt) {
    final didMutateGrid = _perfMeter.measure('apply_cluster_physics', _applyClusterPhysics);
    if (didMutateGrid) {
      _perfMeter.measure('sync_grid_from_clusters', _syncGridFromClusters);
    } else {
      _lastDirtyCellCount = 0;
    }
    _perfMeter.tick();
  }

  /// Immediately syncs cluster data into render buffers.
  /// Useful for showing newly placed blocks without waiting for a sim tick.
  void syncGridNow() {
    _syncGridFromClusters();
  }

  /// Merges adjacent same-color 1-cell clusters to reduce fragmentation.
  /// Call this after the board stabilizes (isStable == true).
  void mergeAdjacentClusters() {
    final mergeSw = _perfMeter.start();
    if (!_isStable || clusters.isEmpty) return;

    bool mergedAny = false;
    _visitStamp++;
    if (_visitStamp == 0) {
      _visitStamp = 1;
      _visitStampBuffer.fillRange(0, _visitStampBuffer.length, 0);
    }

    final singletonSeeds = clusters.values
        .where((c) => c.cells.length == 1)
        .toList(growable: false);

    for (final seed in singletonSeeds) {
      if (!clusters.containsKey(seed.id) || seed.cells.length != 1) continue;

      final seedCell = seed.cells.first;
      final seedIdx = seedCell.y * cols + seedCell.x;
      if (_visitStampBuffer[seedIdx] == _visitStamp) continue;

      final targetColorId = seedCell.baseColorId;
      _bfsHead = 0;
      _bfsTail = 0;
      _bfsQueue[_bfsTail++] = seedIdx;

      final componentIndices = <int>[];
      final componentClusterIds = <int>[];

      while (_bfsHead < _bfsTail) {
        final idx = _bfsQueue[_bfsHead++];
        if (_visitStampBuffer[idx] == _visitStamp) continue;

        final clusterId = cellIdMap[idx];
        if (clusterId == 0) continue;

        final cluster = clusters[clusterId];
        if (cluster == null || cluster.cells.length != 1) continue;

        final cell = cluster.cells.first;
        if (cell.baseColorId != targetColorId) continue;

        _visitStampBuffer[idx] = _visitStamp;
        componentIndices.add(idx);
        componentClusterIds.add(clusterId);

        final x = idx % cols;
        final y = idx ~/ cols;
        if (x > 0) _bfsQueue[_bfsTail++] = idx - 1;
        if (x < cols - 1) _bfsQueue[_bfsTail++] = idx + 1;
        if (y > 0) _bfsQueue[_bfsTail++] = idx - cols;
        if (y < rows - 1) _bfsQueue[_bfsTail++] = idx + cols;
      }

      if (componentClusterIds.length <= 1) continue;

      final mergedCells = <Cell>[];
      for (final clusterId in componentClusterIds) {
        final existing = clusters.remove(clusterId);
        if (existing == null || existing.cells.isEmpty) continue;
        mergedCells.add(existing.cells.first);
      }

      if (mergedCells.length <= 1) continue;

      final mergedId = _nextClusterId++;
      clusters[mergedId] = Cluster(id: mergedId, cells: mergedCells);
      for (final idx in componentIndices) {
        cellIdMap[idx] = mergedId;
      }
      mergedAny = true;
    }

    if (mergedAny) {
      _activeListDirty = true;
      _cachedClusterList = clusters.values.toList(growable: false);
      _lastKnownClusterCount = clusters.length;
    }
    _perfMeter.end('merge_adjacent_clusters', mergeSw);
  }

  bool isInside(int x, int y) {
    return x >= 0 && x < cols && y >= 0 && y < rows;
  }

  /// Resets the game-over state. Called when starting a new game.
  void resetGameOverState() {
    _isGameOver = false;
  }

  // =========================================================
  // CLUSTER CREATION
  // =========================================================

  void _createCluster(List<Cell> cells) {
    final id = _nextClusterId++;
    final cluster = Cluster(id: id, cells: cells);
    clusters[id] = cluster;

    for (final c in cells) {
      if (!isInside(c.x, c.y)) continue;
      cellIdMap[c.y * cols + c.x] = id;
    }
  }

  // =========================================================
  // PHYSICS (CLUSTER-BASED GRAVITY)
  // =========================================================

  bool _applyClusterPhysics() {
    if (_activeListDirty || clusters.length != _lastKnownClusterCount) {
      _cachedClusterList = clusters.values.toList();
      _lastKnownClusterCount = clusters.length;
      _activeListDirty = false;
    }

    bool anyMovement = false;
    _activeClusters.clear();

    for (final cluster in _cachedClusterList) {
      if (!clusters.containsKey(cluster.id)) continue;

      // Quick reject: single-cell clusters at bottom can't move
      if (cluster.cells.length == 1) {
        final cell = cluster.cells.first;
        if (cell.y >= rows - 1) continue;
      }

      _activeClusters.add(cluster); // only these will run full physics
    }

    for (final cluster in _activeClusters) {
      if (!clusters.containsKey(cluster.id)) continue;

      if (_tryMoveCluster(cluster, 0, 1)) {
        anyMovement = true;
        continue;
      }

      final leftFirst = _random.nextBool();
      bool moved = false;

      if (leftFirst) {
        if (_isClusterSupportedAfterMove(cluster, -1, 1) &&
            _tryMoveCluster(cluster, -1, 1)) {
          moved = true;
        } else if (_isClusterSupportedAfterMove(cluster, 1, 1) &&
            _tryMoveCluster(cluster, 1, 1)) {
          moved = true;
        }
      } else {
        if (_isClusterSupportedAfterMove(cluster, 1, 1) &&
            _tryMoveCluster(cluster, 1, 1)) {
          moved = true;
        } else if (_isClusterSupportedAfterMove(cluster, -1, 1) &&
            _tryMoveCluster(cluster, -1, 1)) {
          moved = true;
        }
      }
      if (moved) {
        anyMovement = true;
        continue;
      }

      if (cluster.cells.length > 1) {
        final willMoveAsGrains = _wouldAnyGrainMoveIfClusterBreaksApart(
          cluster,
        );
        // Avoid fragmenting stable structures into thousands of singletons.
        if (willMoveAsGrains) {
          _breakApartCluster(cluster);
          anyMovement = true;
          _activeListDirty = true; // breaking apart creates new singles
        }
        continue;
      }
    }

    _isStable = !anyMovement;

    if (_isStable) {
      _activeListDirty = true; // force rebuild next time
    }

    return anyMovement;
  }

  /// Checks if sand has reached the top threshold (top 10% of grid).
  /// Call this only after clear resolution and post-clear stabilization.
  void evaluateGameOverCondition() {
    if (_isGameOver) return; // Already game over, no need to check again

    for (int y = 0; y < _gameOverThresholdRow; y++) {
      for (int x = 0; x < cols; x++) {
        if (gridColorBuffer[y * cols + x] != 0) {
          _isGameOver = true;
          return;
        }
      }
    }
  }

  void _breakApartCluster(Cluster cluster) {
    if (cluster.cells.isEmpty) {
      clusters.remove(cluster.id);
      return;
    }

    clusters.remove(cluster.id);

    for (final cell in cluster.cells) {
      cellIdMap[cell.y * cols + cell.x] = 0;
    }

    for (final cell in cluster.cells) {
      if (!isInside(cell.x, cell.y)) continue;
      _createCluster([Cell(cell.x, cell.y, cell.color, cell.baseColorId)]);
    }
  }

  bool _tryMoveCluster(Cluster cluster, int dx, int dy) {
    for (final cell in cluster.cells) {
      final nx = cell.x + dx;
      final ny = cell.y + dy;

      if (!isInside(nx, ny)) return false;

      final existingId = cellIdMap[ny * cols + nx];
      if (existingId != 0 && existingId != cluster.id) {
        return false;
      }
    }

    for (final cell in cluster.cells) {
      cellIdMap[cell.y * cols + cell.x] = 0;
    }

    for (final cell in cluster.cells) {
      cell.x += dx;
      cell.y += dy;
    }

    for (final cell in cluster.cells) {
      cellIdMap[cell.y * cols + cell.x] = cluster.id;
    }

    return true;
  }

  // =========================================================
  // GRID SYNC (With Dirty Region Tracking)
  // =========================================================

  void _syncGridFromClusters() {
    _lastDirtyCellCount = 0;

    // Cell-level dirty tracking: clear only cells that were occupied in previous frame
    // This is much more efficient than clearing the entire 8000-cell buffer every frame
    for (int i = 0; i < _previousFrameCellCount; i++) {
      final cellIndex = _previousFrameCellIndices[i];
      // Only clear if cell is actually occupied to avoid unnecessary writes
      if (gridColorBuffer[cellIndex] != 0 || baseColorIdBuffer[cellIndex] != 0) {
        gridColorBuffer[cellIndex] = 0;
        baseColorIdBuffer[cellIndex] = 0;
        _lastDirtyCellIndices[_lastDirtyCellCount++] = cellIndex;
      }
    }

    // Collect current frame cell indices and edge colors for bridge detection optimization
    _currentFrameCellCount = 0;
    _leftEdgeColors.clear();
    _rightEdgeColors.clear();

    // Update grid with current cluster cells
    for (final cluster in clusters.values) {
      for (final cell in cluster.cells) {
        if (isInside(cell.x, cell.y)) {
          final cellIndex = cell.y * cols + cell.x;
          final colorVal = cell.color.toARGB32();

          // Only update if values actually changed to avoid unnecessary writes
          if (gridColorBuffer[cellIndex] != colorVal ||
              baseColorIdBuffer[cellIndex] != cell.baseColorId) {
            gridColorBuffer[cellIndex] = colorVal;
            baseColorIdBuffer[cellIndex] = cell.baseColorId;
            _currentFrameCellIndices[_currentFrameCellCount++] = cellIndex;
            _lastDirtyCellIndices[_lastDirtyCellCount++] = cellIndex;
          }

          // Track which color IDs touch the edges for bridge detection optimization
          if (cell.x == 0) {
            _leftEdgeColors.add(cell.baseColorId);
          }
          if (cell.x == cols - 1) {
            _rightEdgeColors.add(cell.baseColorId);
          }
        }
      }
    }

    // Swap tracking buffers for next frame
    final prevBuffer = _previousFrameCellIndices;
    _previousFrameCellIndices = _currentFrameCellIndices;
    _currentFrameCellIndices = prevBuffer;
    _previousFrameCellCount = _currentFrameCellCount;
    _currentFrameCellCount = 0;
  }

  bool doesColorSpanLeftToRight(Color color) {
    if (!_isStable) return false;

    final colorId = _getColorId(color);
    if (colorId == -1) return false; // Color not found

    // Quick reject: use cached edge color info instead of scanning edges
    // This saves O(rows * 2) operations per color check
    if (!_leftEdgeColors.contains(colorId) ||
        !_rightEdgeColors.contains(colorId)) {
      return false;
    }

    bool touchesLeft = false;
    bool touchesRight = false;
    for (int y = 0; y < rows; y++) {
      final leftIdx = y * cols;
      if (gridColorBuffer[leftIdx] != 0 &&
          baseColorIdBuffer[leftIdx] == colorId) {
        touchesLeft = true;
      }

      final rightIdx = y * cols + (cols - 1);
      if (gridColorBuffer[rightIdx] != 0 &&
          baseColorIdBuffer[rightIdx] == colorId) {
        touchesRight = true;
      }
    }
    if (!touchesLeft || !touchesRight) return false;

    // Reuse pre-allocated buffers to avoid memory allocations
    _visitStamp++;
    if (_visitStamp == 0) {
      _visitStamp = 1;
      _visitStampBuffer.fillRange(0, _visitStampBuffer.length, 0);
    }

    _bfsHead = 0;
    _bfsTail = 0;

    for (int y = 0; y < rows; y++) {
      final idx = y * cols;
      if (gridColorBuffer[idx] != 0 && baseColorIdBuffer[idx] == colorId) {
        _visitStampBuffer[idx] = _visitStamp;
        _bfsQueue[_bfsTail++] = idx;
      }
    }

    // Use pre-allocated neighbor array to avoid recreation
    final neighbors = _eightWayNeighbors;

    while (_bfsHead < _bfsTail) {
      final currIdx = _bfsQueue[_bfsHead++];
      final cx = currIdx % cols;

      if (cx == cols - 1) {
        return true;
      }

      for (final offset in neighbors) {
        final nextIdx = currIdx + offset;
        if (nextIdx < 0 || nextIdx >= rows * cols) continue;

        final nx = nextIdx % cols;
        if ((cx == 0 && (nx == cols - 1)) || (cx == cols - 1 && (nx == 0))) {
          continue;
        }

        if (_visitStampBuffer[nextIdx] != _visitStamp &&
            gridColorBuffer[nextIdx] != 0 &&
            baseColorIdBuffer[nextIdx] == colorId) {
          _visitStampBuffer[nextIdx] = _visitStamp;
          _bfsQueue[_bfsTail++] = nextIdx;
        }
      }
    }

    return false;
  }

  bool clearSpanningBridge(Color color) {
    final clearSw = _perfMeter.start();
    if (!_isStable) return false;

    final colorId = _getColorId(color);
    if (colorId == -1) return false; // Color not found

    // Quick reject: use cached edge color info instead of scanning edges
    // This saves O(rows * 2) operations per color check
    if (!_leftEdgeColors.contains(colorId) ||
        !_rightEdgeColors.contains(colorId)) {
      _perfMeter.end('clear_spanning_bridge', clearSw);
      return false;
    }

    // BFS to find all connected cells of the color starting from the left edge.
    // Reuse world buffers to keep this path allocation-free.
    _visitStamp++;
    if (_visitStamp == 0) {
      _visitStamp = 1;
      _visitStampBuffer.fillRange(0, _visitStampBuffer.length, 0);
    }

    // Reset buffer indices
    _bfsHead = 0;
    _bfsTail = 0;
    _clearIndicesCount = 0;

    // Pre-allocate neighbor array as class member to avoid repeated allocations
    // 8-directional neighbors to ensure we clear diagonally connected bridges as well
    final neighbors = _eightWayNeighbors;

    // Evaluate one connected component at a time from left-edge seeds.
    // Only clear the component that actually reaches the right edge.
    for (int y = 0; y < rows; y++) {
      final seedIdx = y * cols;
      if (gridColorBuffer[seedIdx] == 0 || baseColorIdBuffer[seedIdx] != colorId) {
        continue;
      }
      if (_visitStampBuffer[seedIdx] == _visitStamp) continue;

      // Reset counters for this component
      _bfsHead = 0;
      _bfsTail = 0;
      _clearIndicesCount = 0;
      bool touchesRight = false;

      _visitStampBuffer[seedIdx] = _visitStamp;
      _bfsQueue[_bfsTail++] = seedIdx;
      _clearIndicesBuffer[_clearIndicesCount++] = seedIdx;

      while (_bfsHead < _bfsTail) {
        final currIdx = _bfsQueue[_bfsHead++];
        final cx = currIdx % cols;

        if (cx == cols - 1) {
          touchesRight = true;
        }

        for (final offset in neighbors) {
          final nextIdx = currIdx + offset;
          if (nextIdx < 0 || nextIdx >= rows * cols) continue;

          final nx = nextIdx % cols;
          // Simplified wraparound check for better performance
          if (nx == 0 && cx == cols - 1) continue;
          if (nx == cols - 1 && cx == 0) continue;

          if (_visitStampBuffer[nextIdx] != _visitStamp &&
              gridColorBuffer[nextIdx] != 0 &&
              baseColorIdBuffer[nextIdx] == colorId) {
            _visitStampBuffer[nextIdx] = _visitStamp;
            _bfsQueue[_bfsTail++] = nextIdx;
            _clearIndicesBuffer[_clearIndicesCount++] = nextIdx;
          }
        }
      }

      if (touchesRight) {
        lastClearedIndices.clear();
        for (int i = 0; i < _clearIndicesCount; i++) {
          lastClearedIndices.add(_clearIndicesBuffer[i]);
        }
        ScoringService.instance.addSandClearPoints(1, _clearIndicesCount);
        _perfMeter.end('clear_spanning_bridge', clearSw);
        return true;
      }
    }

    _perfMeter.end('clear_spanning_bridge', clearSw);
    return false;
  }

  /// Called by the game after clear animation completes to finalize the clearing
  void finalizeClear(List<int> indices) {
    final cleanupSw = _perfMeter.start();
    final affectedClusterIds = <int>{};

    for (final idx in indices) {
      final clusterId = cellIdMap[idx];
      if (clusterId != 0) {
        affectedClusterIds.add(clusterId);
      }
      gridColorBuffer[idx] = 0;
      baseColorIdBuffer[idx] = 0;
      cellIdMap[idx] = 0;
    }

    _cleanupStaleClusters(affectedClusterIds);
    _perfMeter.end('finalize_clear_cleanup', cleanupSw);
  }

  /// After clearing cells directly in the grid, some clusters may have lost all their cells or become invalid.
  /// This method scans through existing clusters and removes any that no longer have valid cells in the grid.
  void _cleanupStaleClusters([Set<int>? candidateClusterIds]) {
    final idsToCheck = candidateClusterIds ?? clusters.keys.toSet();
    final idsToRemove = <int>[];
    for (final clusterId in idsToCheck) {
      final cluster = clusters[clusterId];
      if (cluster == null) continue;

      cluster.cells.removeWhere((cell) {
        if (!isInside(cell.x, cell.y)) return true;
        return cellIdMap[cell.y * cols + cell.x] != clusterId;
      });

      if (cluster.cells.isEmpty) {
        idsToRemove.add(clusterId);
      }
    }

    if (idsToRemove.isNotEmpty) {
      for (final id in idsToRemove) {
        clusters.remove(id);
      }
      _lastKnownClusterCount = clusters.length;
    }

    _activeListDirty = true;
  }

  bool _isClusterSupportedAfterMove(Cluster cluster, int dx, int dy) {
    for (final cell in cluster.cells) {
      final nx = cell.x + dx;
      final ny = cell.y + dy;

      if (!isInside(nx, ny)) return false;

      final belowX = nx;
      final belowY = ny + 1;

      if (belowY >= rows) continue;

      final belowIdx = belowY * cols + belowX;
      final occupantId = cellIdMap[belowIdx];

      if (occupantId != 0 && occupantId != cluster.id) continue;

      return false;
    }
    return true;
  }

  // Rebuild cluster from saved game
  void rebuildClusters(SandWorld world) {
    world.clusters.clear();
    world.cellIdMap.fillRange(0, world.cellIdMap.length, 0);
    world._nextClusterId = 1;

    // Clear dirty tracking and edge colors to get fresh state after rebuild
    world._previousFrameCellCount = 0;
    world._currentFrameCellCount = 0;
    world._lastDirtyCellCount = 0;
    world._leftEdgeColors.clear();
    world._rightEdgeColors.clear();

    final visited = <int>{};
    final cols = world.cols;

    for (int i = 0; i < world.gridColorBuffer.length; i++) {
      if (world.gridColorBuffer[i] == 0 || visited.contains(i)) continue;

      final seedColor = world.gridColorBuffer[i];
      final seedBaseColorId = world.baseColorIdBuffer[i];
      final colorId = seedBaseColorId < 6
        ? seedBaseColorId
        : world._getColorIdFromValue(seedColor);

      final queue = [i];
      final cells = <Cell>[];

      visited.add(i);

      while (queue.isNotEmpty) {
        final idx = queue.removeLast();
        final x = idx % cols;
        final y = idx ~/ cols;
        final cellColor = world.gridColorBuffer[idx];

        cells.add(Cell(x, y, Color(cellColor), colorId));

        void enqueueIfConnected(int nx, int ny) {
          if (!world.isInside(nx, ny)) return;

          final neighborIdx = ny * cols + nx;
          if (visited.contains(neighborIdx)) return;
          if (world.gridColorBuffer[neighborIdx] == 0) return;

          final neighborBaseColorId = world.baseColorIdBuffer[neighborIdx];
          final neighborColorId = neighborBaseColorId < 6
              ? neighborBaseColorId
              : world._getColorIdFromValue(world.gridColorBuffer[neighborIdx]);

          if (neighborColorId != colorId) return;

          visited.add(neighborIdx);
          queue.add(neighborIdx);
        }

        enqueueIfConnected(x - 1, y);
        enqueueIfConnected(x + 1, y);
        enqueueIfConnected(x, y - 1);
        enqueueIfConnected(x, y + 1);
      }

      world._createCluster(cells);
    }
  }

  /// Primes the previous-frame dirty tracking buffer with current occupied
  /// cell indices. Call this after loading or rebuilding the world so the
  /// next `_syncGridFromClusters()` call can correctly detect cleared cells
  /// and populate `_lastDirtyCellIndices`.
  void primeDirtyTracking() {
    int count = 0;
    final len = gridColorBuffer.length;
    for (int i = 0; i < len; i++) {
      if (gridColorBuffer[i] != 0) {
        _previousFrameCellIndices[count++] = i;
      }
    }
    _previousFrameCellCount = count;
  }
}

class _WorldPerfMeter {
  static const bool _enabled = kDebugMode || kProfileMode;

  final String name;
  final Map<String, int> _totalsUs = <String, int>{};
  final Map<String, int> _maxUs = <String, int>{};
  final Map<String, int> _counts = <String, int>{};
  int _ticks = 0;

  _WorldPerfMeter(this.name);

  Stopwatch? start() {
    if (!_enabled) return null;
    return Stopwatch()..start();
  }

  void end(String section, Stopwatch? stopwatch) {
    if (!_enabled || stopwatch == null) return;
    stopwatch.stop();
    _record(section, stopwatch.elapsedMicroseconds);
  }

  T measure<T>(String section, T Function() work) {
    if (!_enabled) return work();
    final sw = Stopwatch()..start();
    final result = work();
    sw.stop();
    _record(section, sw.elapsedMicroseconds);
    return result;
  }

  void tick() {
    if (!_enabled) return;
    _ticks++;
    if (_ticks >= 240) {
      _flush();
    }
  }

  void _record(String section, int elapsedUs) {
    _totalsUs[section] = (_totalsUs[section] ?? 0) + elapsedUs;
    _counts[section] = (_counts[section] ?? 0) + 1;
    final previousMax = _maxUs[section] ?? 0;
    if (elapsedUs > previousMax) {
      _maxUs[section] = elapsedUs;
    }
  }

  void _flush() {
    final sections = _totalsUs.keys.toList(growable: false)..sort();
    final metrics = <String>[];
    for (final section in sections) {
      final count = _counts[section] ?? 1;
      final avgMs = (_totalsUs[section]! / count) / 1000.0;
      final maxMs = (_maxUs[section]! / 1000.0);
      metrics.add('$section avg=${avgMs.toStringAsFixed(2)}ms max=${maxMs.toStringAsFixed(2)}ms');
    }

    _totalsUs.clear();
    _maxUs.clear();
    _counts.clear();
    _ticks = 0;
  }
}
