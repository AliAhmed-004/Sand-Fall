import 'dart:math';
import 'dart:ui';
import 'dart:ui' as ui;
import 'dart:async';

import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sandfall/components/combo_feedback_effect.dart';
import 'package:sandfall/config/floating_feedback_config.dart';
import 'package:sandfall/config/game_config.dart';
import 'package:sandfall/models/confetti_particle.dart';
import 'package:sandfall/models/floating_score.dart';
import 'package:sandfall/models/game_state_dto.dart';
import 'package:sandfall/models/notification_badge.dart';
import 'package:sandfall/services/difficulty_service.dart';
import 'package:sandfall/services/high_score_service.dart';
import 'package:sandfall/services/milestone_service.dart';
import 'package:sandfall/services/play_games_service.dart';
import 'package:sandfall/services/save_game_service.dart';
import 'package:sandfall/services/scoring_service.dart';
import 'package:sandfall/theme/theme.dart';
import 'package:sandfall/tutorial/tutorial_coach.dart';
import 'package:sandfall/world.dart';
import 'package:sandfall/utils/combo_praise_helper.dart';

class SandGame extends FlameGame with TapCallbacks {
  // Temporary performance-first profile: keep mechanics, disable costly visuals.
  static const bool _enableClearAnimation = true;
  static const bool _enableFloatingScores = true;
  static const bool _enableScreenShake = true;
  static const bool _enableConfetti = false;
  static const bool _enableMilestoneBadge = true;

  late SandWorld sandWorld;

  final double topUIRatio = 0.2;
  final double bottomUIRatio = 0.2;
  final double horizontalPadding = 20.0;

  double cellSize = 1;
  late Offset gridOffset;

  final int cols = 80;
  final int rows = 100;

  // All colors available at max difficulty
  static final List<Color> colors = [
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.purple,
  ];

  // Singleton Random instance to avoid allocations
  static final Random _random = Random();

  // Batched rendering buffers (full grid; chunk buffers mirror these for partial GPU uploads)
  late Float32List _vertices;
  late Int32List _colors;

  /// Spatial chunks for partial `Vertices.raw` rebuilds (e.g. 8×10 tiles for 80×100).
  static const int _chunkCellW = 10;
  static const int _chunkCellH = 10;
  late final int _chunksX;
  late final int _chunksY;
  late final int _chunkCount;
  late final List<Float32List> _chunkVertices;
  late final List<Int32List> _chunkColors;
  late final List<Vertices?> _cachedChunkVertices;
  late final Uint8List _chunkDirty;

  // Fixed timestep accumulator
  double _accumulator = 0;
  static const double _step = 1 / 60;
  static const double _maxFrameDt = 0.05;
  static const int _maxSubStepsPerFrame = 2;
  static const double _targetFrameMs = 16.67;

  // Track stability to trigger bridge checks only when the board transitions from unstable to stable
  bool _wasStableLastFrame = true;
  bool _needsSimulation = false;
  bool _needsBridgeEvaluation = false;
  double _avgFrameMs = _targetFrameMs;
  int _consecutiveSlowFrames = 0;

  // Debounced save frequency: save game state only after every N successful placements
  static const int _saveInterval = 5;
  int _placementsSinceLastSave = 0;
  bool _hasPendingAutosave = false;
  bool _isAutosaveInFlight = false;

  // Next piece preview
  late List<Point<int>> nextShape;
  late Color nextColor;
  int _nextShapeMinX = 0;
  int _nextShapeMaxX = 0;
  int _nextShapeMinY = 0;
  int _nextShapeMaxY = 0;

  // Preview UI settings
  double previewSize = 120.0; // size of the preview box in pixels
  final int previewGridSize = 6; // small grid (e.g. 6x6) for preview

  // Next-preview pop animation
  double _nextPreviewPopElapsed = 999.0;
  static const double _nextPreviewPopDuration = 0.25;

  bool _isLoaded = false;

  final TutorialCoachController tutorialCoach = TutorialCoachController();

  // Performance optimization: cached NEXT TextPainter
  late TextPainter _nextTextPainter;

  // Performance optimization: cached background as Picture
  ui.Picture? _backgroundPicture;
  double _lastBackgroundWidth = -1;
  double _lastBackgroundHeight = -1;

  // Track milestone for celebration overlay
  int _previousMilestone = 0;

  bool isGameStarted = false;
  bool _isGameOverDetected = false;
  bool _isGameOverSweepActive = false;
  bool _isGameOverFinalized = false;
  double _gameOverSweepElapsed = 0;
  double _gameOverSweepY = 0;
  int _gameOverSweepLastClearedRow = -1;
  double _thresholdWarningElapsed = 0;
  static const int _thresholdWarningWindowRows = 18;
  static const double _gameOverBreachHoldDuration = 0.24;
  static const double _gameOverSweepFlashDuration = 0.11;
  static const double _gameOverSweepMoveDuration = 0.75;
  static const double _gameOverBreachTextFadeDuration = 0.45;

  // Clearing animation tracking
  static const double _clearFlashDuration = 0.05; // 50ms glow flash
  static const double _clearWaveDuration = 0.3; // 300ms wave effect
  static const double _invClearWaveDuration = 1.0 / _clearWaveDuration;
  static const int _unsetAnimatedColor = -1;
  double _clearingElapsedTime = 0;
  late Float32List _clearingCellAnimations; // cell index -> wave start time
  List<int> _cellsToClears = []; // indices of cells that need to clear
  late Uint8List _clearMask;
  late Int32List _lastAnimatedCellColors;
  late Int32List _pendingColorIndices;
  late Int32List _pendingColorValues;
  int _pendingColorCount = 0;

  final Paint _verticesPaint = Paint();

  // Floating score popup (single instance, reused)
  FloatingScore? _activeFloatingScore;
  TextPainter? _floatingScoreTextPainter;
  int _floatingScorePainterValue = -1;
  FloatingScoreType? _floatingScorePainterType;
  ComboFeedbackEffect? _activeComboFeedback;

  // Screen shake
  double _shakeIntensity = 0;
  double _shakeElapsed = 0;
  static const double _shakeDuration = 0.15;
  Offset _shakeOffset = Offset.zero;

  // Confetti burst emitter
  final ConfettiEmitter _confettiEmitter = ConfettiEmitter();

  // Notification badge for milestone celebrations
  NotificationBadge? _activeBadge;

  final Paint _playAreaBorderPaint = Paint()
    ..color = Colors.white24
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  final Paint _gameOverThresholdPaint = Paint()
    ..color = Colors.red.withAlpha(204)
    ..strokeWidth = 3
    ..style = PaintingStyle.stroke;
  final Paint _gameOverSweepLinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _gameOverSweepGlowPaint = Paint()..style = PaintingStyle.fill;
  bool _needsGameOverEvaluation = false;
  final _PerfMeter _perfMeter = _PerfMeter('SandGame');

  @override
  Future<void> onLoad() async {
    pauseEngine();
    sandWorld = SandWorld(cols: cols, rows: rows);
    _generateNextPiece();

    // Pre-allocate buffers for vertices (2 triangles per cell = 6 vertices, each with x,y)
    _vertices = Float32List(cols * rows * 12);
    _colors = Int32List(cols * rows * 6);

    _chunksX = (cols + _chunkCellW - 1) ~/ _chunkCellW;
    _chunksY = (rows + _chunkCellH - 1) ~/ _chunkCellH;
    _chunkCount = _chunksX * _chunksY;
    final cellsPerChunk = _chunkCellW * _chunkCellH;
    final vPerChunk = cellsPerChunk * 12;
    final cPerChunk = cellsPerChunk * 6;
    _chunkVertices = List<Float32List>.generate(
      _chunkCount,
      (_) => Float32List(vPerChunk),
      growable: false,
    );
    _chunkColors = List<Int32List>.generate(
      _chunkCount,
      (_) => Int32List(cPerChunk),
      growable: false,
    );
    _cachedChunkVertices = List<Vertices?>.filled(_chunkCount, null);
    _chunkDirty = Uint8List(_chunkCount);

    _clearMask = Uint8List(cols * rows);
    _clearingCellAnimations = Float32List(cols * rows);
    _lastAnimatedCellColors = Int32List(cols * rows);
    _lastAnimatedCellColors.fillRange(
      0,
      _lastAnimatedCellColors.length,
      _unsetAnimatedColor,
    );
    _pendingColorIndices = Int32List(cols * rows);
    _pendingColorValues = Int32List(cols * rows);

    // Initialize and layout NEXT TextPainter once
    _nextTextPainter = TextPainter(
      text: const TextSpan(
        text: "NEXT",
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    _nextTextPainter.layout();

    // Initialize milestone tracking
    _previousMilestone = MilestoneService.instance.getCurrentMilestone(
      ScoringService.instance.currentScore,
    );

    _isLoaded = true;

    // Run initial update if resize happened already
    _updateVertexPositions();
  }

  void _generateNextPiece() {
    nextShape = _randomShape();

    if (nextShape.isNotEmpty) {
      int minX = nextShape.first.x;
      int maxX = nextShape.first.x;
      int minY = nextShape.first.y;
      int maxY = nextShape.first.y;

      for (final p in nextShape) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
      }

      _nextShapeMinX = minX;
      _nextShapeMaxX = maxX;
      _nextShapeMinY = minY;
      _nextShapeMaxY = maxY;
    }

    final forcedTutorialColor = tutorialCoach.forcedColor;
    if (forcedTutorialColor != null) {
      nextColor = forcedTutorialColor;
      // Trigger preview pop animation
      _nextPreviewPopElapsed = 0.0;
      return;
    }

    // Get available colors based on current difficulty
    final currentScore = ScoringService.instance.currentScore;
    final availableColors = DifficultyService.instance.getAvailableColors(
      currentScore,
    );
    nextColor = availableColors[_random.nextInt(availableColors.length)];
    _nextPreviewPopElapsed = 0.0;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);

    final topUIHeight = size.y * topUIRatio;
    final bottomUIHeight = size.y * bottomUIRatio;

    final playableHeight = size.y - topUIHeight - bottomUIHeight;
    final playableWidth = size.x - 2 * horizontalPadding;

    final cellWidth = playableWidth / cols;
    final cellHeight = playableHeight / rows;

    cellSize = cellWidth < cellHeight ? cellWidth : cellHeight;

    final gridWidth = cols * cellSize;
    final gridHeight = rows * cellSize;

    gridOffset = Offset(
      horizontalPadding + (playableWidth - gridWidth) / 2,
      topUIHeight + (playableHeight - gridHeight) / 2,
    );

    final gridBottom = gridOffset.dy + gridHeight;
    final maxPreviewByWidth = size.x * 0.34;
    final maxPreviewByHeight = size.y - gridBottom - 24.0;
    previewSize = max(
      72.0,
      min(120.0, min(maxPreviewByWidth, maxPreviewByHeight)),
    );

    // Recompute static vertex positions if buffers are ready
    if (_isLoaded) {
      _updateVertexPositions();
      // Invalidate cached background picture when size changes
      _lastBackgroundWidth = -1;
      _lastBackgroundHeight = -1;
      _backgroundPicture = null;
      _invalidateChunkVertexCaches();
    }
  }

  void _invalidateChunkVertexCaches() {
    for (int i = 0; i < _chunkCount; i++) {
      _cachedChunkVertices[i] = null;
      _chunkDirty[i] = 1;
    }
  }

  void _copyFullGridGeometryAndColorsToChunks() {
    for (int cy = 0; cy < _chunksY; cy++) {
      for (int cx = 0; cx < _chunksX; cx++) {
        final cid = cy * _chunksX + cx;
        final cv = _chunkVertices[cid];
        final cc = _chunkColors[cid];
        final x0 = cx * _chunkCellW;
        final y0 = cy * _chunkCellH;
        int vi = 0;
        int ci = 0;
        for (int yy = 0; yy < _chunkCellH; yy++) {
          for (int xx = 0; xx < _chunkCellW; xx++) {
            final x = x0 + xx;
            final y = y0 + yy;
            final idx = y * cols + x;
            final vb = idx * 12;
            final cb = idx * 6;
            for (int k = 0; k < 12; k++) {
              cv[vi++] = _vertices[vb + k];
            }
            for (int k = 0; k < 6; k++) {
              cc[ci++] = _colors[cb + k];
            }
          }
        }
      }
    }
  }

  void _updateVertexPositions() {
    int vIdx = 0;
    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        final left = gridOffset.dx + x * cellSize;
        final top = gridOffset.dy + y * cellSize;
        final right = left + cellSize;
        final bottom = top + cellSize;

        // Triangle 1
        _vertices[vIdx++] = left;
        _vertices[vIdx++] = top;
        _vertices[vIdx++] = right;
        _vertices[vIdx++] = top;
        _vertices[vIdx++] = left;
        _vertices[vIdx++] = bottom;

        // Triangle 2
        _vertices[vIdx++] = right;
        _vertices[vIdx++] = top;
        _vertices[vIdx++] = right;
        _vertices[vIdx++] = bottom;
        _vertices[vIdx++] = left;
        _vertices[vIdx++] = bottom;
      }
    }

    _copyFullGridGeometryAndColorsToChunks();
    _invalidateChunkVertexCaches();
  }

  /// Writes display color for one cell into global and chunk buffers; marks the chunk dirty.
  void _writeCellColor(int cellIndex, int color) {
    if (cellIndex < 0 || cellIndex >= cols * rows) return;

    final colorBase = cellIndex * 6;
    if (_colors[colorBase] == color) return;

    _colors[colorBase] = color;
    _colors[colorBase + 1] = color;
    _colors[colorBase + 2] = color;
    _colors[colorBase + 3] = color;
    _colors[colorBase + 4] = color;
    _colors[colorBase + 5] = color;

    final x = cellIndex % cols;
    final y = cellIndex ~/ cols;
    final cid = (y ~/ _chunkCellH) * _chunksX + (x ~/ _chunkCellW);
    final ox = x - (x ~/ _chunkCellW) * _chunkCellW;
    final oy = y - (y ~/ _chunkCellH) * _chunkCellH;
    final li = oy * _chunkCellW + ox;
    final localBase = li * 6;
    final chunkCol = _chunkColors[cid];
    chunkCol[localBase] = color;
    chunkCol[localBase + 1] = color;
    chunkCol[localBase + 2] = color;
    chunkCol[localBase + 3] = color;
    chunkCol[localBase + 4] = color;
    chunkCol[localBase + 5] = color;

    _chunkDirty[cid] = 1;
  }

  void _setCellColorInVertexBuffer(int cellIndex, int color) {
    _writeCellColor(cellIndex, color);
  }

  /// Sets colors for multiple cells at once to reduce vertex update overhead
  void _setMultipleCellColorsInVertexBuffer(List<int> cellIndices, int color) {
    for (final cellIndex in cellIndices) {
      _writeCellColor(cellIndex, color);
    }
  }

  /// Applies a per-cell color list in one pass and flips the vertex dirty flag once.
  void _setMultipleCellColorsWithValuesInVertexBuffer(
    Int32List cellIndices,
    Int32List colors,
    int count,
  ) {
    for (int i = 0; i < count; i++) {
      _writeCellColor(cellIndices[i], colors[i]);
    }
  }

  void _applyWorldDirtyCellColors() {
    final dirty = sandWorld.lastDirtyCellIndices;
    final dirtyCount = sandWorld.lastDirtyCellCount;
    final gridColorBuffer = sandWorld.gridColorBuffer;

    for (int i = 0; i < dirtyCount; i++) {
      final cellIndex = dirty[i];
      _setCellColorInVertexBuffer(cellIndex, gridColorBuffer[cellIndex]);
    }
  }

  void _syncAllCellColorsFromWorld() {
    final gridColorBuffer = sandWorld.gridColorBuffer;
    for (int i = 0; i < gridColorBuffer.length; i++) {
      _setCellColorInVertexBuffer(i, gridColorBuffer[i]);
    }
  }

  // =========================================================
  // INPUT
  // =========================================================

  @override
  void onTapDown(TapDownEvent event) {
    if (_cellsToClears.isNotEmpty) return;
    if (_isGameOverSweepActive) return;
    if (!sandWorld.isStable) return;
    if (sandWorld.isGameOver) return;

    final pos = event.localPosition;
    final gridX = ((pos.x - gridOffset.dx) / cellSize).floor();
    final gridY = ((pos.y - gridOffset.dy) / cellSize).floor();

    if (!sandWorld.isInside(gridX, gridY)) return;

    // Only generate next piece if placement was successful
    if (sandWorld.placeShape(nextShape, gridX, gridY, nextColor)) {
      _generateNextPiece();
      _needsSimulation = true;
      _needsBridgeEvaluation = true;
      _needsGameOverEvaluation = true;
      // Show placement immediately instead of waiting for the next fixed step.
      sandWorld.syncGridNow();
      _applyWorldDirtyCellColors();

      if (_enableFloatingScores) {
        // Show floating score popup at tap position.
        final screenX = gridOffset.dx + gridX * cellSize + cellSize / 2;
        final screenY = gridOffset.dy + gridY * cellSize;
        _activeFloatingScore = FloatingScore(
          value: ScoringService.instance.blockPlacementPoints,
          startPosition: Offset(screenX, screenY),
          type: FloatingScoreType.tap,
        );
        _invalidateFloatingScorePainter();
      }

      // Debounced save: only save every N placements
      _placementsSinceLastSave++;
      if (_placementsSinceLastSave >= _saveInterval) {
        _placementsSinceLastSave = 0;
        _hasPendingAutosave = true;
      }
    }
  }

  List<Point<int>> _randomShape() {
    final shapes = [
      [Point(-1, -1), Point(0, -1), Point(-1, 0), Point(0, 0)],
      [Point(-2, 0), Point(-1, 0), Point(0, 0), Point(1, 0)],
      [Point(-1, -1), Point(-1, 0), Point(-1, 1), Point(0, 1)],
    ];

    final baseShape = shapes[_random.nextInt(shapes.length)];
    int scale = cols ~/ 15;
    if (scale < 1) scale = 1;

    return _scaleShape(baseShape, scale);
  }

  List<Point<int>> _scaleShape(List<Point<int>> base, int scale) {
    final scaled = <Point<int>>[];
    for (final p in base) {
      for (int dy = 0; dy < scale; dy++) {
        for (int dx = 0; dx < scale; dx++) {
          scaled.add(Point(p.x * scale + dx, p.y * scale + dy));
        }
      }
    }
    return scaled;
  }

  // =========================================================
  // UPDATE LOOP
  // =========================================================

  @override
  void update(double dt) {
    final updateFrameSw = _perfMeter.startFrame();
    final frameMs = dt * 1000.0;
    _avgFrameMs = (_avgFrameMs * 0.9) + (frameMs * 0.1);
    if (frameMs > _targetFrameMs) {
      _consecutiveSlowFrames++;
    } else {
      _consecutiveSlowFrames = 0;
    }

    super.update(dt);

    tutorialCoach.update(dt);

    // Update next-preview pop timer
    if (_nextPreviewPopElapsed < _nextPreviewPopDuration) {
      _nextPreviewPopElapsed += dt;
      if (_nextPreviewPopElapsed > _nextPreviewPopDuration) {
        _nextPreviewPopElapsed = _nextPreviewPopDuration;
      }
    }

    _thresholdWarningElapsed += dt;

    // Update clearing animation if in progress
    if (_cellsToClears.isNotEmpty) {
      _clearingElapsedTime += dt;

      // After animation completes, finalize the clearing
      if (_clearingElapsedTime >= _clearFlashDuration + _clearWaveDuration) {
        sandWorld.finalizeClear(_cellsToClears);

        _setMultipleCellColorsInVertexBuffer(_cellsToClears, 0);
        for (final idx in _cellsToClears) {
          if (idx >= 0 && idx < _clearMask.length) {
            _clearMask[idx] = 0;
          }
          if (idx >= 0 && idx < _lastAnimatedCellColors.length) {
            _lastAnimatedCellColors[idx] = _unsetAnimatedColor;
          }
        }
        _cellsToClears.clear();
        _clearingElapsedTime = 0;
        _needsGameOverEvaluation = true;
        _needsSimulation = true;
      }

      // Skip physics during clearing animation
      _wasStableLastFrame = sandWorld.isStable;
      _perfMeter.endFrame(updateFrameSw, 'update_total');
      return;
    }

    // Run the game-over sweep transition before showing the overlay.
    if (_isGameOverSweepActive) {
      _updateGameOverSweep(dt);
      _wasStableLastFrame = sandWorld.isStable;
      _perfMeter.endFrame(updateFrameSw, 'update_total');
      return;
    }

    // Pause game on game over
    if (sandWorld.isGameOver) {
      if (!_isGameOverDetected) {
        _isGameOverDetected = true;
        _startGameOverSweep();
      }
      _perfMeter.endFrame(updateFrameSw, 'update_total');
      return;
    }

    final shouldSimulate = _needsSimulation || !sandWorld.isStable;
    if (shouldSimulate) {
      final frameDt = dt > _maxFrameDt ? _maxFrameDt : dt;
      _accumulator += frameDt;

      // Adaptive sub-step throttling: when recent frames are slow, cap at 1 step
      // to avoid long red-frame bursts from compounding CPU work.
      final adaptiveMaxSubSteps =
          (_consecutiveSlowFrames >= 2 || _avgFrameMs > 18.0)
          ? 1
          : _maxSubStepsPerFrame;

      int subSteps = 0;
      while (_accumulator >= _step && subSteps < adaptiveMaxSubSteps) {
        _perfMeter.measure('world_update', () => sandWorld.update(_step));
        _perfMeter.measure('apply_dirty_colors', _applyWorldDirtyCellColors);
        _accumulator -= _step;
        subSteps++;
      }

      if (subSteps == adaptiveMaxSubSteps) {
        _accumulator = 0;
      }

      if (subSteps > 0 && sandWorld.isStable) {
        _needsSimulation = false;
      }
    } else {
      _accumulator = 0;
    }

    // Check for milestone changes
    final currentScore = ScoringService.instance.currentScore;
    final currentMilestone = MilestoneService.instance.getCurrentMilestone(
      currentScore,
    );
    if (currentMilestone > _previousMilestone && isGameStarted) {
      _previousMilestone = currentMilestone;

      final unlockedColorIndex =
          MilestoneService.instance.getUnlockedColorCount(currentScore, 3) - 1;
      final unlockedColor =
          SandGame.colors[unlockedColorIndex
              .clamp(0, SandGame.colors.length - 1)
              .toInt()];

      if (_enableConfetti) {
        // Emit confetti from progress bar area (top portion of game).
        final progressBarY = size.y * topUIRatio / 2;
        final progressBarCenter = Offset(size.x / 2, progressBarY);
        _confettiEmitter.emit(
          origin: progressBarCenter,
          baseColor: unlockedColor,
          count: 30,
          spread: 250,
          upwardVelocity: -300,
        );
      }

      if (_enableMilestoneBadge) {
        // Show notification badge between HUD and grid.
        final badgeY = size.y * topUIRatio + 30;
        _activeBadge = NotificationBadge(
          milestone: currentMilestone,
          unlockedColor: unlockedColor,
          nextMilestoneScore: MilestoneService.instance.getNextMilestoneScore(
            currentScore,
          ),
          targetPosition: Offset(size.x / 2, badgeY),
          screenWidth: size.x,
        );
      }
    }

    final shouldEvaluateBridges =
        sandWorld.isStable && (!_wasStableLastFrame || _needsBridgeEvaluation);

    if (shouldEvaluateBridges) {
      _needsBridgeEvaluation = false;

      // Merge adjacent same-color clusters to reduce fragmentation
      _perfMeter.measure(
        'merge_adjacent_clusters',
        sandWorld.mergeAdjacentClusters,
      );

      // Start a clear session to track combo bonuses
      ScoringService.instance.startClearSession();

      // Get available colors based on current difficulty
      final availableColors = DifficultyService.instance.getAvailableColors(
        currentScore,
      );

      bool anyBridgesCleared = false;
      final indicesToClear = <int>{};
      _perfMeter.measure('bridge_detection_and_clear', () {
        for (final c in availableColors) {
          if (sandWorld.clearSpanningBridge(c)) {
            anyBridgesCleared = true;
            indicesToClear.addAll(sandWorld.lastClearedIndices);
          }
        }
      });

      if (anyBridgesCleared) {
        tutorialCoach.markBridgeCleared();
      }

      // Start one clear animation for all cleared bridges.
      if (indicesToClear.isNotEmpty) {
        final clearList = indicesToClear.toList(growable: false);
        if (_enableClearAnimation) {
          _startClearingAnimation(clearList);
        } else {
          _perfMeter.measure(
            'finalize_clear',
            () => sandWorld.finalizeClear(clearList),
          );
          _setMultipleCellColorsInVertexBuffer(clearList, 0);
          _needsSimulation = true;
          _needsGameOverEvaluation = true;
        }

        if (_enableFloatingScores) {
          final screenX = gridOffset.dx + (cols * cellSize) / 2;
          final screenY = gridOffset.dy + (rows * cellSize) / 3;
          final praise = ComboPraiseHelper.selectPraise(
            ScoringService.instance.currentComboCount,
          );
          _activeComboFeedback = ComboFeedbackEffect(
            scoreText: '+${ScoringService.instance.lastClearPoints}',
            praiseText: praise.text,
            scoreColor: FloatingFeedbackConfig.comboFeedbackScoreColor,
            praiseColor: praise.color,
            centerPosition: Offset(screenX, screenY),
            duration: FloatingFeedbackConfig.comboPraiseDuration,
            riseSpeed: FloatingFeedbackConfig.comboPraiseRiseSpeed,
            fadeStart: FloatingFeedbackConfig.comboPraiseFadeStart,
            scalePopDuration:
                FloatingFeedbackConfig.comboPraiseScalePopDuration,
            scalePopAmount: FloatingFeedbackConfig.comboPraiseScalePopAmount,
            maxRotationRadians:
                FloatingFeedbackConfig.comboPraiseMaxRotationRadians,
            horizontalDrift: FloatingFeedbackConfig.comboPraiseHorizontalDrift,
            scoreFontSize: FloatingFeedbackConfig.comboFeedbackScoreFontSize,
            praiseFontSize: FloatingFeedbackConfig.comboFeedbackPraiseFontSize,
            lineGap: FloatingFeedbackConfig.comboFeedbackLineGap,
            shadowBlurRadius:
                FloatingFeedbackConfig.comboPraiseShadowBlurRadius,
            shadowOpacity: FloatingFeedbackConfig.comboPraiseShadowOpacity,
            praiseLetterSpacing:
                FloatingFeedbackConfig.comboFeedbackPraiseLetterSpacing,
            scoreLetterSpacing:
                FloatingFeedbackConfig.comboFeedbackScoreLetterSpacing,
            comboTier: praise.tier,
          );
        }

        if (_enableScreenShake) {
          _shakeIntensity = 4;
          _shakeElapsed = 0;
        }
      }

      // Only end combo if no bridges were found
      // If bridges were found, the board will be unstable again and combo continues
      ScoringService.instance.endClearSessionIfNoBridges(anyBridgesCleared);

      // Only evaluate game over after all bridge clears have been resolved.
      if (!anyBridgesCleared && _cellsToClears.isEmpty && sandWorld.isStable) {
        _needsGameOverEvaluation = true;
      }
    }

    if (_needsGameOverEvaluation &&
        _cellsToClears.isEmpty &&
        sandWorld.isStable &&
        !_needsSimulation) {
      sandWorld.evaluateGameOverCondition();
      _needsGameOverEvaluation = false;
    }

    if (_hasPendingAutosave && sandWorld.isStable && !_needsSimulation) {
      _triggerAutosave();
    }

    // Update floating score popup
    if (_enableFloatingScores && _activeFloatingScore != null) {
      _activeFloatingScore!.update(dt);
      if (_activeFloatingScore!.isExpired) {
        _activeFloatingScore = null;
      }
    } else if (!_enableFloatingScores) {
      _activeFloatingScore = null;
    }

    if (_activeComboFeedback != null) {
      _activeComboFeedback!.update(dt);
      if (_activeComboFeedback!.isExpired) {
        _activeComboFeedback = null;
      }
    }

    // Update screen shake
    if (_enableScreenShake && _shakeIntensity > 0) {
      _shakeElapsed += dt;
      if (_shakeElapsed >= _shakeDuration) {
        _shakeIntensity = 0;
        _shakeElapsed = 0;
        _shakeOffset = Offset.zero;
      } else {
        final progress = _shakeElapsed / _shakeDuration;
        final currentIntensity = _shakeIntensity * (1.0 - progress);
        _shakeOffset = Offset(
          (_random.nextDouble() * 2 - 1) * currentIntensity,
          (_random.nextDouble() * 2 - 1) * currentIntensity,
        );
      }
    } else if (!_enableScreenShake) {
      _shakeIntensity = 0;
      _shakeElapsed = 0;
      _shakeOffset = Offset.zero;
    }

    // Update confetti particles
    if (_enableConfetti) {
      _confettiEmitter.update(dt);
    }

    // Update notification badge
    if (_enableMilestoneBadge && _activeBadge != null) {
      _activeBadge!.update(dt);
      if (_activeBadge!.isExpired) {
        _activeBadge = null;
      }
    } else if (!_enableMilestoneBadge) {
      _activeBadge = null;
    }

    _wasStableLastFrame = sandWorld.isStable;
    _perfMeter.endFrame(updateFrameSw, 'update_total');
  }

  void _triggerAutosave() {
    if (_isAutosaveInFlight) return;

    _isAutosaveInFlight = true;
    _hasPendingAutosave = false;

    final sparseState = _perfMeter.measure(
      'autosave_snapshot_encode',
      () => SparseGameStateDTO.fromWorld(sandWorld),
    );

    SaveGameService.instance
        .saveGame(sparseState, ScoringService.instance.currentScore)
        .whenComplete(() {
          _isAutosaveInFlight = false;
        });
  }

  void _invalidateFloatingScorePainter() {
    _floatingScoreTextPainter = null;
    _floatingScorePainterValue = -1;
    _floatingScorePainterType = null;
  }

  // =========================================================
  // RENDERING
  // =========================================================

  @override
  void render(Canvas canvas) {
    final renderFrameSw = _perfMeter.startFrame();
    super.render(canvas);

    // Apply screen shake
    canvas.save();
    if (_enableScreenShake) {
      canvas.translate(_shakeOffset.dx, _shakeOffset.dy);
    }

    _drawBackground(canvas);

    // Animate only currently clearing cells
    if (_enableClearAnimation && _cellsToClears.isNotEmpty) {
      _updateClearingAnimationVertexColors();
    }

    _perfMeter.measure('vertices_rebuild', () {
      for (int i = 0; i < _chunkCount; i++) {
        if (_chunkDirty[i] != 0 || _cachedChunkVertices[i] == null) {
          _cachedChunkVertices[i] = Vertices.raw(
            VertexMode.triangles,
            _chunkVertices[i],
            colors: _chunkColors[i],
          );
          _chunkDirty[i] = 0;
        }
      }
    });

    _perfMeter.measure('draw_vertices', () {
      for (int i = 0; i < _chunkCount; i++) {
        final v = _cachedChunkVertices[i];
        if (v != null) {
          canvas.drawVertices(v, BlendMode.src, _verticesPaint);
        }
      }
    });

    _drawPlayAreaBorder(canvas);

    _drawGameOverThreshold(canvas);

    _drawNextPiecePreview(canvas);

    // Draw floating score popup
    if (_enableFloatingScores && _activeFloatingScore != null) {
      _drawFloatingScore(canvas);
    }

    if (_activeComboFeedback != null) {
      _activeComboFeedback!.render(canvas);
    }

    canvas.restore();

    // Draw confetti (outside shake transform)
    if (_enableConfetti) {
      _confettiEmitter.draw(canvas);
    }

    // Draw notification badge (outside shake transform)
    if (_enableMilestoneBadge && _activeBadge != null) {
      _activeBadge!.draw(canvas);
    }

    _perfMeter.endFrame(renderFrameSw, 'render_total');
  }

  void _startClearingAnimation(List<int> cellIndices) {
    for (final idx in _cellsToClears) {
      if (idx >= 0 && idx < _clearMask.length) {
        _clearMask[idx] = 0;
      }
    }

    _cellsToClears = List.from(cellIndices);
    _clearingElapsedTime = 0;

    // Pre-calculate when each cell's wave will reach it (based on x position)
    for (final idx in cellIndices) {
      final x = idx % cols;
      // Wave travels left to right, starting after flash duration
      final cellDelayFraction = x / cols; // 0 at left, 1 at right
      final waveStartTime =
          _clearFlashDuration + (cellDelayFraction * _clearWaveDuration);
      _clearingCellAnimations[idx] = waveStartTime;
      _lastAnimatedCellColors[idx] = _unsetAnimatedColor;
      if (idx >= 0 && idx < _clearMask.length) {
        _clearMask[idx] = 1;
      }
    }
  }

  void _updateClearingAnimationVertexColors() {
    final gridColorBuffer = sandWorld.gridColorBuffer;
    _pendingColorCount = 0;

    if (_clearingElapsedTime < _clearFlashDuration) {
      // Flash multiplier is frame-global; compute once and reuse for all cells.
      final flashProgress = _clearingElapsedTime / _clearFlashDuration;
      final brightnessMultiplier = 1.0 + (0.4 * flashProgress);

      for (final cellIndex in _cellsToClears) {
        final originalColor = gridColorBuffer[cellIndex];
        final animatedColor = _applyFlashColor(
          originalColor,
          brightnessMultiplier,
        );
        _queueAnimatedColorIfChanged(cellIndex, animatedColor);
      }
    } else {
      for (final cellIndex in _cellsToClears) {
        final originalColor = gridColorBuffer[cellIndex];
        final waveStartTime = _clearingCellAnimations[cellIndex];
        final timeSinceWaveStart = _clearingElapsedTime - waveStartTime;
        final animatedColor = _applyWaveFadeColor(
          originalColor,
          timeSinceWaveStart,
        );
        _queueAnimatedColorIfChanged(cellIndex, animatedColor);
      }
    }

    if (_pendingColorCount > 0) {
      _setMultipleCellColorsWithValuesInVertexBuffer(
        _pendingColorIndices,
        _pendingColorValues,
        _pendingColorCount,
      );
    }
  }

  void _queueAnimatedColorIfChanged(int cellIndex, int animatedColor) {
    if (_lastAnimatedCellColors[cellIndex] == animatedColor) {
      return;
    }

    _lastAnimatedCellColors[cellIndex] = animatedColor;
    _pendingColorIndices[_pendingColorCount] = cellIndex;
    _pendingColorValues[_pendingColorCount] = animatedColor;
    _pendingColorCount++;
  }

  int _applyFlashColor(int originalColor, double brightnessMultiplier) {
    final alpha = (originalColor >> 24) & 0xFF;
    final red = (originalColor >> 16) & 0xFF;
    final green = (originalColor >> 8) & 0xFF;
    final blue = originalColor & 0xFF;

    final newRed = (red * brightnessMultiplier).toInt().clamp(0, 255);
    final newGreen = (green * brightnessMultiplier).toInt().clamp(0, 255);
    final newBlue = (blue * brightnessMultiplier).toInt().clamp(0, 255);

    return (alpha << 24) | (newRed << 16) | (newGreen << 8) | newBlue;
  }

  int _applyWaveFadeColor(int originalColor, double timeSinceWaveStart) {
    if (timeSinceWaveStart <= 0) {
      return originalColor;
    }

    final alpha = (originalColor >> 24) & 0xFF;
    final red = (originalColor >> 16) & 0xFF;
    final green = (originalColor >> 8) & 0xFF;
    final blue = originalColor & 0xFF;

    double fadeProgress = timeSinceWaveStart * _invClearWaveDuration;
    if (fadeProgress > 1.0) {
      fadeProgress = 1.0;
    }

    final newAlpha = (alpha * (1.0 - fadeProgress)).toInt();
    return (newAlpha << 24) | (red << 16) | (green << 8) | blue;
  }

  void _drawBackground(Canvas canvas) {
    if (_backgroundPicture == null ||
        _lastBackgroundWidth != size.x ||
        _lastBackgroundHeight != size.y) {
      final recorder = ui.PictureRecorder();
      final recordingCanvas = Canvas(recorder);
      final backgroundRect = Rect.fromLTWH(0, 0, size.x, size.y);
      final backgroundPaint = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(0, size.y),
          [SandColors.deepSand, SandColors.darkBg],
          [0.0, 1.0],
        );

      recordingCanvas.drawRect(backgroundRect, backgroundPaint);
      _backgroundPicture = recorder.endRecording();
      _lastBackgroundWidth = size.x;
      _lastBackgroundHeight = size.y;
    }

    canvas.drawPicture(_backgroundPicture!);
  }

  void _drawGameOverThreshold(Canvas canvas) {
    if (_isGameOverSweepActive) {
      final isFlashing = _gameOverSweepElapsed < _gameOverSweepFlashDuration;
      final flashProgress =
          (_gameOverSweepElapsed / _gameOverSweepFlashDuration).clamp(0.0, 1.0);
      final pulse = 0.5 + 0.5 * sin(_gameOverSweepElapsed * 50.0);

      final glowAlpha = isFlashing
          ? (150 + (80 * (1.0 - flashProgress) * pulse)).toInt().clamp(0, 255)
          : 95;
      final glowHalfHeight = isFlashing
          ? cellSize * (1.1 + 0.35 * (1.0 - flashProgress))
          : cellSize * 0.8;

      _gameOverSweepGlowPaint.color = SandColors.warmAccent.withAlpha(
        glowAlpha,
      );
      canvas.drawRect(
        Rect.fromLTRB(
          gridOffset.dx,
          _gameOverSweepY - glowHalfHeight,
          gridOffset.dx + cols * cellSize,
          _gameOverSweepY + glowHalfHeight,
        ),
        _gameOverSweepGlowPaint,
      );

      final lineAlpha = isFlashing
          ? (210 + (45 * pulse)).toInt().clamp(0, 255)
          : 225;
      _gameOverSweepLinePaint
        ..color = Colors.redAccent.withAlpha(lineAlpha)
        ..strokeWidth = isFlashing ? (4.0 + 3.0 * (1.0 - flashProgress)) : 4.0;

      canvas.drawLine(
        Offset(gridOffset.dx, _gameOverSweepY),
        Offset(gridOffset.dx + cols * cellSize, _gameOverSweepY),
        _gameOverSweepLinePaint,
      );

      final textFadeStart =
          _gameOverBreachHoldDuration + _gameOverSweepMoveDuration;
      double textOpacity = 1.0;
      if (_gameOverSweepElapsed > textFadeStart) {
        final fadeProgress =
            ((_gameOverSweepElapsed - textFadeStart) /
                    _gameOverBreachTextFadeDuration)
                .clamp(0.0, 1.0);
        textOpacity = 1.0 - fadeProgress;
      }

      if (textOpacity > 0.01) {
        final sweepProgress =
            ((_gameOverSweepElapsed - _gameOverBreachHoldDuration) /
                    _gameOverSweepMoveDuration)
                .clamp(0.0, 1.0);
        final textPainter = TextPainter(
          text: TextSpan(
            text: 'THRESHOLD BREACHED',
            style: TextStyle(
              color: Colors.white.withAlpha((235 * textOpacity).toInt()),
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              fontFamily: 'monospace',
              shadows: const [
                Shadow(
                  color: Colors.black87,
                  blurRadius: 6,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final textX = gridOffset.dx + (cols * cellSize - textPainter.width) / 2;
        final textY = _gameOverSweepY - 30 - 8 * sweepProgress;
        textPainter.paint(canvas, Offset(textX, textY));
      }

      return;
    }

    final thresholdY =
        gridOffset.dy + sandWorld.gameOverThresholdRow * cellSize;
    final warningStrength = _computeThresholdWarningStrength();

    if (warningStrength > 0) {
      final pulseHz = 0.35 + (0.8 * warningStrength);
      final pulse =
          0.5 + 0.5 * sin(2 * pi * pulseHz * _thresholdWarningElapsed);
      final pulseMix = 0.45 + (0.55 * pulse);

      final dynamicAlpha = (140 + (85 * warningStrength * pulseMix))
          .toInt()
          .clamp(0, 255);
      _gameOverThresholdPaint
        ..color = Colors.redAccent.withAlpha(dynamicAlpha)
        ..strokeWidth = 3.0 + (1.8 * warningStrength * pulseMix);
    } else {
      _gameOverThresholdPaint
        ..color = Colors.red.withAlpha(204)
        ..strokeWidth = 3;
    }

    canvas.drawLine(
      Offset(gridOffset.dx, thresholdY),
      Offset(gridOffset.dx + cols * cellSize, thresholdY),
      _gameOverThresholdPaint,
    );
  }

  double _computeThresholdWarningStrength() {
    final topRow = _findTopOccupiedRow();
    if (topRow == null) {
      return 0.0;
    }

    final thresholdRow = sandWorld.gameOverThresholdRow;
    final distanceRows = thresholdRow - topRow;
    final normalized = 1.0 - (distanceRows / _thresholdWarningWindowRows);
    return normalized.clamp(0.0, 1.0);
  }

  int? _findTopOccupiedRow() {
    final buffer = sandWorld.gridColorBuffer;
    for (int y = 0; y < rows; y++) {
      final rowBase = y * cols;
      for (int x = 0; x < cols; x++) {
        if (buffer[rowBase + x] != 0) {
          return y;
        }
      }
    }
    return null;
  }

  void _startGameOverSweep() {
    final thresholdY =
        gridOffset.dy + sandWorld.gameOverThresholdRow * cellSize;
    _isGameOverSweepActive = true;
    _isGameOverFinalized = false;
    _gameOverSweepElapsed = 0;
    _gameOverSweepY = thresholdY;
    _gameOverSweepLastClearedRow = -1;

    if (_enableScreenShake) {
      _shakeIntensity = 5;
      _shakeElapsed = 0;
    }
  }

  void _updateGameOverSweep(double dt) {
    _gameOverSweepElapsed += dt;

    final sweepStartY =
        gridOffset.dy + sandWorld.gameOverThresholdRow * cellSize;
    final sweepEndY = gridOffset.dy + rows * cellSize;
    final textFadeStart =
        _gameOverBreachHoldDuration + _gameOverSweepMoveDuration;
    final totalSweepDuration = textFadeStart + _gameOverBreachTextFadeDuration;

    if (_gameOverSweepElapsed <= _gameOverBreachHoldDuration) {
      _gameOverSweepY = sweepStartY;
      return;
    }

    final moveProgress =
        ((_gameOverSweepElapsed - _gameOverBreachHoldDuration) /
                _gameOverSweepMoveDuration)
            .clamp(0.0, 1.0);
    final eased = moveProgress * moveProgress * moveProgress;
    _gameOverSweepY = lerpDouble(sweepStartY, sweepEndY, eased) ?? sweepEndY;

    _clearRowsBehindGameOverSweepLine();

    if (_gameOverSweepElapsed >= totalSweepDuration) {
      _finalizeGameOverTransition();
    }
  }

  void _clearRowsBehindGameOverSweepLine() {
    final rowBoundary = ((_gameOverSweepY - gridOffset.dy) / cellSize)
        .floor()
        .clamp(0, rows);
    final clearUntilRow = rowBoundary - 1;

    if (clearUntilRow <= _gameOverSweepLastClearedRow) {
      return;
    }

    final startRow = _gameOverSweepLastClearedRow + 1;
    for (int y = startRow; y <= clearUntilRow; y++) {
      final rowBase = y * cols;
      for (int x = 0; x < cols; x++) {
        _writeCellColor(rowBase + x, 0);
      }
    }

    _gameOverSweepLastClearedRow = clearUntilRow;
  }

  void _finalizeGameOverTransition() {
    if (_isGameOverFinalized) {
      return;
    }
    _isGameOverFinalized = true;
    _isGameOverSweepActive = false;

    final allCellCount = cols * rows;
    for (int i = 0; i < allCellCount; i++) {
      _writeCellColor(i, 0);
    }

    final finalScore = ScoringService.instance.currentScore;
    print('[Game] Game over detected! Final score: $finalScore');

    unawaited(() async {
      try {
        print('[Game] Saving high score...');
        await HighScoreService.instance.saveHighScoreIfHigher(finalScore);
        print('[Game] High score saved. Submitting to Play Games...');
        await PlayGamesService.instance.submitScore(finalScore);
      } catch (_) {
        // Local persistence and Play Games submission are best-effort.
      }
    }());

    SaveGameService.instance.deleteSavedGame();
    pauseEngine();
    overlays.add(GameConfig.gameOverOverlay);
  }

  void _drawPlayAreaBorder(Canvas canvas) {
    final borderRect = Rect.fromLTWH(
      gridOffset.dx,
      gridOffset.dy,
      cols * cellSize,
      rows * cellSize,
    );

    canvas.drawRect(borderRect, _playAreaBorderPaint);
  }

  void _drawNextPiecePreview(Canvas canvas) {
    final gridBottom = gridOffset.dy + rows * cellSize;
    final previewX = (size.x - previewSize) / 2;
    final previewY = max(gridBottom + 16, size.y - previewSize - 32);

    final centerX = previewX + previewSize / 2;
    final centerY = previewY + previewSize / 2;

    canvas.save();
    canvas.translate(centerX, centerY);

    final bgRect = Rect.fromLTWH(
      -previewSize / 2,
      -previewSize / 2,
      previewSize,
      previewSize,
    );

    canvas.drawRect(bgRect, Paint()..color = SandColors.previewBoxDark);

    canvas.drawRect(
      bgRect,
      Paint()
        ..color = SandColors.sandyBeige
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Use cached NEXT TextPainter instead of creating new one every frame
    final textX = -previewSize / 2 + (previewSize - _nextTextPainter.width) / 2;
    final textY = -previewSize / 2 - 28;
    _nextTextPainter.paint(canvas, Offset(textX, textY));

    if (nextShape.isEmpty) {
      canvas.restore();
      return;
    }

    final shapeWidth = _nextShapeMaxX - _nextShapeMinX + 1;
    final shapeHeight = _nextShapeMaxY - _nextShapeMinY + 1;
    final inset = previewSize * 0.18;
    final availableWidth = previewSize - inset * 2;
    final availableHeight = previewSize - inset * 2;
    final previewCellSize = max(
      2.0,
      min(
        cellSize,
        min(availableWidth / shapeWidth, availableHeight / shapeHeight),
      ),
    );

    final totalShapeWidth = shapeWidth * previewCellSize;
    final totalShapeHeight = shapeHeight * previewCellSize;

    final offsetX =
        previewX +
        (previewSize - totalShapeWidth) / 2 -
        _nextShapeMinX * previewCellSize;
    final offsetY =
        previewY +
        (previewSize - totalShapeHeight) / 2 -
        _nextShapeMinY * previewCellSize;

    final paint = Paint()..color = nextColor;

    for (final p in nextShape) {
      final drawX = offsetX + p.x * previewCellSize;
      final drawY = offsetY + p.y * previewCellSize;

      final rect = Rect.fromLTWH(
        drawX - centerX,
        drawY - centerY,
        previewCellSize,
        previewCellSize,
      );
      canvas.drawRect(rect, paint);
    }

    canvas.restore();
  }

  void _drawFloatingScore(Canvas canvas) {
    final fs = _activeFloatingScore!;
    final pos = fs.currentPosition;
    final scale = fs.scale;

    if (_floatingScoreTextPainter == null ||
        _floatingScorePainterValue != fs.value ||
        _floatingScorePainterType != fs.type) {
      final color = fs.type == FloatingScoreType.tap
          ? Colors.white
          : Colors.amber;
      _floatingScoreTextPainter = TextPainter(
        text: TextSpan(
          text: '+${fs.value}',
          style: TextStyle(
            color: color,
            fontSize: fs.fontSize,
            fontWeight: FontWeight.bold,
            shadows: const [
              Shadow(
                color: Colors.black54,
                blurRadius: 4,
                offset: Offset(1, 1),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _floatingScorePainterValue = fs.value;
      _floatingScorePainterType = fs.type;
    }

    final tp = _floatingScoreTextPainter!;
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.scale(scale, scale);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  /// Resets game state for a new game. Clears the board and resets all game flags.
  void resetGameState({bool regenerateNextPiece = true}) {
    sandWorld = SandWorld(cols: cols, rows: rows);
    ScoringService.instance.resetScore();
    _isGameOverDetected = false;
    _previousMilestone = 0;
    _wasStableLastFrame = true;
    _needsSimulation = false;
    _needsBridgeEvaluation = false;
    _accumulator = 0;
    _placementsSinceLastSave = 0;
    _hasPendingAutosave = false;
    _isAutosaveInFlight = false;
    _isGameOverSweepActive = false;
    _isGameOverFinalized = false;
    _gameOverSweepElapsed = 0;
    _gameOverSweepY = 0;
    _gameOverSweepLastClearedRow = -1;
    _thresholdWarningElapsed = 0;
    _cellsToClears.clear();
    _clearingCellAnimations.fillRange(0, _clearingCellAnimations.length, 0);
    _clearingElapsedTime = 0;
    _clearMask.fillRange(0, _clearMask.length, 0);
    _lastAnimatedCellColors.fillRange(
      0,
      _lastAnimatedCellColors.length,
      _unsetAnimatedColor,
    );
    _colors.fillRange(0, _colors.length, 0);
    _updateVertexPositions();

    _invalidateChunkVertexCaches();
    _activeFloatingScore = null;
    _invalidateFloatingScorePainter();
    _activeComboFeedback = null;
    _shakeIntensity = 0;
    _shakeElapsed = 0;
    _shakeOffset = Offset.zero;
    _confettiEmitter.particles.clear();
    _activeBadge = null;
    tutorialCoach.reset();

    if (regenerateNextPiece) {
      _generateNextPiece();
    }
  }

  void startNewGame() {
    resetGameState(regenerateNextPiece: false);
    _generateNextPiece();
    isGameStarted = true;
    resumeEngine();
  }

  void startTutorialGame() {
    resetGameState(regenerateNextPiece: false);
    tutorialCoach.start(forcedColor: _tutorialForceColor());
    _generateNextPiece();
    isGameStarted = true;
    resumeEngine();
  }

  void continueSavedGame() {
    loadSavedGame();
    isGameStarted = true;
    resumeEngine();
  }

  Color _tutorialForceColor() {
    final availableColors = DifficultyService.instance.getAvailableColors(
      ScoringService.instance.currentScore,
    );
    return availableColors.first;
  }

  /// Loads a saved game state and rebuilds the world from the saved sparse grid.
  void loadSavedGame() {
    final savedData = SaveGameService.instance.loadGame();

    if (savedData == null) {
      return;
    }

    try {
      final sparseState = savedData['state'] as SparseGameStateDTO;
      final score = savedData['score'] as int;

      // Reset world with correct dimensions
      sandWorld = SandWorld(cols: cols, rows: rows);
      if (_clearMask.length != cols * rows) {
        _clearMask = Uint8List(cols * rows);
      }

      // Apply sparse state to world (reconstructs full grid)
      sparseState.applyToWorld(sandWorld);

      // Rebuild clusters from the restored grid
      sandWorld.rebuildClusters(sandWorld);

      // Prime dirty-tracking so subsequent syncs can detect cleared cells
      // and populate `lastDirtyCellIndices` correctly.
      sandWorld.primeDirtyTracking();

      // Prime world dirty tracking and edge caches from rebuilt clusters.
      // Without this, the first post-load movement can leave stale pixels
      // because previous-frame occupied indices are still empty.
      sandWorld.syncGridNow();

      // Restore score
      ScoringService.instance.setScore(score);

      // Generate next piece and reset flags
      _generateNextPiece();
      _isGameOverDetected = false;
      _previousMilestone = MilestoneService.instance.getCurrentMilestone(score);
      _wasStableLastFrame = true;
      _needsSimulation = false;
      _needsBridgeEvaluation = false;
      _accumulator = 0;
      _placementsSinceLastSave = 0;
      _hasPendingAutosave = false;
      _isAutosaveInFlight = false;
      _isGameOverSweepActive = false;
      _isGameOverFinalized = false;
      _gameOverSweepElapsed = 0;
      _gameOverSweepY = 0;
      _gameOverSweepLastClearedRow = -1;
      _thresholdWarningElapsed = 0;
      _cellsToClears.clear();
      _clearingCellAnimations.fillRange(0, _clearingCellAnimations.length, 0);
      _clearingElapsedTime = 0;
      _clearMask.fillRange(0, _clearMask.length, 0);
      _lastAnimatedCellColors.fillRange(
        0,
        _lastAnimatedCellColors.length,
        _unsetAnimatedColor,
      );
      _syncAllCellColorsFromWorld();
      _updateVertexPositions();
      _needsGameOverEvaluation = true;
      _invalidateFloatingScorePainter();
      _activeComboFeedback = null;
      tutorialCoach.reset();
      overlays.remove(GameConfig.tutorialOverlay);
    } catch (e) {
      // Silently fail if load is corrupted
    }
  }
}

class _PerfMeter {
  static const bool _enabled = kDebugMode || kProfileMode;

  final String name;
  final Map<String, int> _totalsUs = <String, int>{};
  final Map<String, int> _maxUs = <String, int>{};
  final Map<String, int> _counts = <String, int>{};
  int _samples = 0;

  _PerfMeter(this.name);

  Stopwatch? startFrame() {
    if (!_enabled) return null;
    return Stopwatch()..start();
  }

  void endFrame(Stopwatch? stopwatch, String section) {
    if (!_enabled || stopwatch == null) return;
    stopwatch.stop();
    _record(section, stopwatch.elapsedMicroseconds);
    _samples++;

    if (_samples >= 240) {
      _flush();
    }
  }

  T measure<T>(String section, T Function() work) {
    if (!_enabled) return work();
    final sw = Stopwatch()..start();
    final result = work();
    sw.stop();
    _record(section, sw.elapsedMicroseconds);
    return result;
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
      metrics.add(
        '$section avg=${avgMs.toStringAsFixed(2)}ms max=${maxMs.toStringAsFixed(2)}ms',
      );
    }

    _totalsUs.clear();
    _maxUs.clear();
    _counts.clear();
    _samples = 0;
  }
}
