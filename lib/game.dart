import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:sandfall/config/game_config.dart';
import 'package:sandfall/models/confetti_particle.dart';
import 'package:sandfall/models/floating_score.dart';
import 'package:sandfall/models/game_state_dto.dart';
import 'package:sandfall/models/notification_badge.dart';
import 'package:sandfall/services/difficulty_service.dart';
import 'package:sandfall/services/high_score_service.dart';
import 'package:sandfall/services/milestone_service.dart';
import 'package:sandfall/services/save_game_service.dart';
import 'package:sandfall/services/scoring_service.dart';
import 'package:sandfall/theme/theme.dart';
import 'package:sandfall/world.dart';

class SandGame extends FlameGame with TapCallbacks {
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

  // Batched rendering buffers
  late Float32List _vertices;
  late Int32List _colors;

  // Fixed timestep accumulator
  double _accumulator = 0;
  static const double _step = 1 / 60;
  static const double _maxFrameDt = 0.05;
  static const int _maxSubStepsPerFrame = 2;

  // Track stability to trigger bridge checks only when the board transitions from unstable to stable
  bool _wasStableLastFrame = true;
  bool _needsSimulation = false;

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
  final double previewSize = 120.0; // size of the preview box in pixels
  final int previewGridSize = 6; // small grid (e.g. 6x6) for preview

  bool _isLoaded = false;

  // Performance optimization: cached NEXT TextPainter
  late TextPainter _nextTextPainter;

  // Performance optimization: cached grid lines as Picture
  late ui.Picture _gridLinesPicture;
  double _lastGridLinesOffsetX = -1;
  double _lastGridLinesOffsetY = -1;
  double _lastGridLinesScale = -1;

  // Performance optimization: cached background as Picture
  ui.Picture? _backgroundPicture;
  double _lastBackgroundWidth = -1;
  double _lastBackgroundHeight = -1;

  // Track milestone for celebration overlay
  int _previousMilestone = 0;

  bool isGameStarted = false;
  bool _isGameOverDetected = false;

  // Clearing animation tracking
  static const double _clearFlashDuration = 0.05; // 50ms glow flash
  static const double _clearWaveDuration = 0.3; // 300ms wave effect
  double _clearingElapsedTime = 0;
  final Map<int, double> _clearingCellAnimations =
      {}; // cell index → wave start time
  List<int> _cellsToClears = []; // indices of cells that need to clear
  late Uint8List _clearMask;

  // Cached Vertices for massive render speedup
  Vertices? _cachedVertices;
  bool _needsVertexUpdate = true;
  final Paint _verticesPaint = Paint();

  // Floating score popup (single instance, reused)
  FloatingScore? _activeFloatingScore;

  // Screen shake
  double _shakeIntensity = 0;
  double _shakeElapsed = 0;
  static const double _shakeDuration = 0.15;
  Offset _shakeOffset = Offset.zero;

  // Confetti burst emitter
  final ConfettiEmitter _confettiEmitter = ConfettiEmitter();

  // Notification badge for milestone celebrations
  NotificationBadge? _activeBadge;

  @override
  Future<void> onLoad() async {
    pauseEngine();
    sandWorld = SandWorld(cols: cols, rows: rows);
    _generateNextPiece();

    // Pre-allocate buffers for vertices (2 triangles per cell = 6 vertices, each with x,y)
    _vertices = Float32List(cols * rows * 12);
    _colors = Int32List(cols * rows * 6);
    _clearMask = Uint8List(cols * rows);

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

    // Get available colors based on current difficulty
    final currentScore = ScoringService.instance.currentScore;
    final availableColors = DifficultyService.instance.getAvailableColors(
      currentScore,
    );
    nextColor = availableColors[_random.nextInt(availableColors.length)];
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

    // Recompute static vertex positions if buffers are ready
    if (_isLoaded) {
      _updateVertexPositions();
      // Invalidate cached background picture when size changes
      _lastBackgroundWidth = -1;
      _lastBackgroundHeight = -1;
      _backgroundPicture = null;
      // Invalidate cached grid lines picture when size changes
      _lastGridLinesOffsetX = -1;
      _lastGridLinesOffsetY = -1;
      _lastGridLinesScale = -1;
      _needsVertexUpdate = true;
      _cachedVertices = null;
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

    _needsVertexUpdate = true;
    _cachedVertices = null; // force full rebuild
  }

  void _setCellColorInVertexBuffer(int cellIndex, int color) {
    if (cellIndex < 0 || cellIndex >= cols * rows) return;

    final colorBase = cellIndex * 6;
    for (int j = 0; j < 6; j++) {
      _colors[colorBase + j] = color;
    }

    _needsVertexUpdate = true;
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
      // Show placement immediately instead of waiting for the next fixed step.
      sandWorld.syncGridNow();
      _applyWorldDirtyCellColors();

      // Show floating score popup at tap position
      final screenX = gridOffset.dx + gridX * cellSize + cellSize / 2;
      final screenY = gridOffset.dy + gridY * cellSize;
      _activeFloatingScore = FloatingScore(
        value: ScoringService.instance.blockPlacementPoints,
        startPosition: Offset(screenX, screenY),
        type: FloatingScoreType.tap,
      );

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
    super.update(dt);

    // Update clearing animation if in progress
    if (_cellsToClears.isNotEmpty) {
      _clearingElapsedTime += dt;

      // After animation completes, finalize the clearing
      if (_clearingElapsedTime >= _clearFlashDuration + _clearWaveDuration) {
        sandWorld.finalizeClear(_cellsToClears);
        for (final idx in _cellsToClears) {
          if (idx >= 0 && idx < _clearMask.length) {
            _clearMask[idx] = 0;
          }
          _setCellColorInVertexBuffer(idx, 0);
        }
        _cellsToClears.clear();
        _clearingElapsedTime = 0;
        _clearingCellAnimations.clear();
        _needsSimulation = true;
      }

      // Skip physics during clearing animation
      _wasStableLastFrame = sandWorld.isStable;
      return;
    }

    // Pause game on game over
    if (sandWorld.isGameOver) {
      if (!_isGameOverDetected) {
        _isGameOverDetected = true;

        // Save high score if current score is higher
        HighScoreService.instance.saveHighScoreIfHigher(
          ScoringService.instance.currentScore,
        );

        // Delete saved game
        SaveGameService.instance.deleteSavedGame();

        // Pause the Engine
        pauseEngine();

        // Show game over overlay
        overlays.add(GameConfig.gameOverOverlay);
      }
      return;
    }

    final shouldSimulate = _needsSimulation || !sandWorld.isStable;
    if (shouldSimulate) {
      final frameDt = dt > _maxFrameDt ? _maxFrameDt : dt;
      _accumulator += frameDt;

      int subSteps = 0;
      while (_accumulator >= _step && subSteps < _maxSubStepsPerFrame) {
        sandWorld.update(_step);
        _applyWorldDirtyCellColors();
        _accumulator -= _step;
        subSteps++;
      }

      if (subSteps == _maxSubStepsPerFrame) {
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

      // Emit confetti from progress bar area (top portion of game)
      final progressBarY = size.y * topUIRatio / 2;
      final progressBarCenter = Offset(size.x / 2, progressBarY);
      final unlockedColor = SandGame
          .colors[(currentMilestone - 1).clamp(0, SandGame.colors.length - 1)];

      _confettiEmitter.emit(
        origin: progressBarCenter,
        baseColor: unlockedColor,
        count: 30,
        spread: 250,
        upwardVelocity: -300,
      );

      // Show notification badge between HUD and grid
      final badgeY = size.y * topUIRatio + 30;
      _activeBadge = NotificationBadge(
        milestone: currentMilestone,
        unlockedColor: unlockedColor,
        nextMilestoneScore: MilestoneService.instance.getNextMilestoneScore(
          currentScore,
        ),
        targetPosition: Offset(size.x / 2, badgeY),
      );
    }

    if (sandWorld.isStable && !_wasStableLastFrame) {
      // Merge adjacent same-color clusters to reduce fragmentation
      sandWorld.mergeAdjacentClusters();

      // Start a clear session to track combo bonuses
      ScoringService.instance.startClearSession();

      // Get available colors based on current difficulty
      final availableColors = DifficultyService.instance.getAvailableColors(
        currentScore,
      );

      bool anyBridgesCleared = false;
      final indicesToClear = <int>{};
      for (final c in availableColors) {
        if (sandWorld.clearSpanningBridge(c)) {
          anyBridgesCleared = true;
          indicesToClear.addAll(sandWorld.lastClearedIndices);
        }
      }

      // Start one clear animation for all cleared bridges.
      if (indicesToClear.isNotEmpty) {
        _startClearingAnimation(indicesToClear.toList());

        // Show combo floating score and trigger screen shake
        final screenX = gridOffset.dx + (cols * cellSize) / 2;
        final screenY = gridOffset.dy + (rows * cellSize) / 3;
        _activeFloatingScore = FloatingScore(
          value: ScoringService.instance.lastClearPoints,
          startPosition: Offset(screenX, screenY),
          type: FloatingScoreType.combo,
        );
        _shakeIntensity = 4;
        _shakeElapsed = 0;
      }

      // Only end combo if no bridges were found
      // If bridges were found, the board will be unstable again and combo continues
      ScoringService.instance.endClearSessionIfNoBridges(anyBridgesCleared);

      // Only evaluate game over after all bridge clears have been resolved.
      if (!anyBridgesCleared && _cellsToClears.isEmpty && sandWorld.isStable) {
        sandWorld.evaluateGameOverCondition();
      }
    }

    // Catch stable frames where no transition happened this update.
    if (_cellsToClears.isEmpty && sandWorld.isStable && !_needsSimulation) {
      sandWorld.evaluateGameOverCondition();
    }

    if (_hasPendingAutosave && sandWorld.isStable && !_needsSimulation) {
      _triggerAutosave();
    }

    // Update floating score popup
    if (_activeFloatingScore != null) {
      _activeFloatingScore!.update(dt);
      if (_activeFloatingScore!.isExpired) {
        _activeFloatingScore = null;
      }
    }

    // Update screen shake
    if (_shakeIntensity > 0) {
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
    }

    // Update confetti particles
    _confettiEmitter.update(dt);

    // Update notification badge
    if (_activeBadge != null) {
      _activeBadge!.update(dt);
      if (_activeBadge!.isExpired) {
        _activeBadge = null;
      }
    }

    _wasStableLastFrame = sandWorld.isStable;
  }

  void _triggerAutosave() {
    if (_isAutosaveInFlight) return;

    _isAutosaveInFlight = true;
    _hasPendingAutosave = false;

    final sparseState = SparseGameStateDTO.fromWorld(sandWorld);

    SaveGameService.instance
        .saveGame(sparseState, ScoringService.instance.currentScore)
        .whenComplete(() {
          _isAutosaveInFlight = false;
        });
  }

  // =========================================================
  // RENDERING
  // =========================================================

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Apply screen shake
    canvas.save();
    canvas.translate(_shakeOffset.dx, _shakeOffset.dy);

    _drawBackground(canvas);

    // Animate only currently clearing cells
    if (_cellsToClears.isNotEmpty) {
      final gridColorBuffer = sandWorld.gridColorBuffer;
      for (final cellIndex in _cellsToClears) {
        final animatedColor = _getAnimatedCellColor(
          cellIndex,
          gridColorBuffer[cellIndex],
        );
        _setCellColorInVertexBuffer(cellIndex, animatedColor);
      }
      // _needsVertexUpdate is already set by _setCellColorInVertexBuffer
    }

    // ←←← THIS IS THE KEY OPTIMIZATION ←←←
    if (_needsVertexUpdate || _cachedVertices == null) {
      _cachedVertices = Vertices.raw(
        VertexMode.triangles,
        _vertices,
        colors: _colors,
      );
      _needsVertexUpdate = false;
    }

    canvas.drawVertices(_cachedVertices!, BlendMode.src, _verticesPaint);

    // Canvas is cleared every frame, so cached static elements must still be
    // drawn every frame even if their picture generation is memoized.
    _drawGridLines(canvas);
    _drawGameOverThreshold(canvas);

    _drawNextPiecePreview(canvas);

    // Draw floating score popup
    if (_activeFloatingScore != null) {
      _drawFloatingScore(canvas);
    }

    canvas.restore();

    // Draw confetti (outside shake transform)
    _confettiEmitter.draw(canvas);

    // Draw notification badge (outside shake transform)
    if (_activeBadge != null) {
      _activeBadge!.draw(canvas);
    }
  }

  void _startClearingAnimation(List<int> cellIndices) {
    for (final idx in _cellsToClears) {
      if (idx >= 0 && idx < _clearMask.length) {
        _clearMask[idx] = 0;
      }
    }

    _cellsToClears = List.from(cellIndices);
    _clearingElapsedTime = 0;
    _clearingCellAnimations.clear();

    // Pre-calculate when each cell's wave will reach it (based on x position)
    for (final idx in cellIndices) {
      final x = idx % cols;
      // Wave travels left to right, starting after flash duration
      final cellDelayFraction = x / cols; // 0 at left, 1 at right
      final waveStartTime =
          _clearFlashDuration + (cellDelayFraction * _clearWaveDuration);
      _clearingCellAnimations[idx] = waveStartTime;
      if (idx >= 0 && idx < _clearMask.length) {
        _clearMask[idx] = 1;
      }
    }
  }

  int _getAnimatedCellColor(int cellIndex, int originalColor) {
    // Extract ARGB components
    final alpha = (originalColor >> 24) & 0xFF;
    final red = (originalColor >> 16) & 0xFF;
    final green = (originalColor >> 8) & 0xFF;
    final blue = originalColor & 0xFF;

    // Glow flash phase (0 to _clearFlashDuration)
    if (_clearingElapsedTime < _clearFlashDuration) {
      // Brighten all cells during flash
      final flashProgress = _clearingElapsedTime / _clearFlashDuration;
      final brightnessFactor =
          1.0 + (0.4 * flashProgress); // Brighten by up to 40%

      final newRed = ((red * brightnessFactor).clamp(0, 255)).toInt();
      final newGreen = ((green * brightnessFactor).clamp(0, 255)).toInt();
      final newBlue = ((blue * brightnessFactor).clamp(0, 255)).toInt();

      return (alpha << 24) | (newRed << 16) | (newGreen << 8) | newBlue;
    }

    // Wave fade phase
    final waveStartTime =
        _clearingCellAnimations[cellIndex] ?? _clearFlashDuration;
    final timeSinceWaveStart = _clearingElapsedTime - waveStartTime;

    // Cell hasn't been reached by wave yet - keep original color
    if (timeSinceWaveStart < 0) {
      return originalColor;
    }

    // Cell is being cleared by wave - fade to transparent
    final cellFadeProgress = (timeSinceWaveStart / _clearWaveDuration).clamp(
      0.0,
      1.0,
    );

    // Fade opacity from 255 to 0
    final newAlpha = (alpha * (1.0 - cellFadeProgress)).toInt();

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
    final thresholdY =
        gridOffset.dy + sandWorld.gameOverThresholdRow * cellSize;

    canvas.drawLine(
      Offset(gridOffset.dx, thresholdY),
      Offset(gridOffset.dx + cols * cellSize, thresholdY),
      Paint()
        ..color = Colors.red
            .withAlpha(204) // 80% opacity red
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawGridLines(Canvas canvas) {
    // Regenerate grid lines picture only if offset or scale changed
    if (_lastGridLinesOffsetX != gridOffset.dx ||
        _lastGridLinesOffsetY != gridOffset.dy ||
        _lastGridLinesScale != cellSize) {
      final recorder = ui.PictureRecorder();
      final recordingCanvas = Canvas(recorder);

      final paint = Paint()
        ..color = Colors.white12
        ..style = PaintingStyle.stroke;

      for (int x = 0; x <= cols; x++) {
        final dx = gridOffset.dx + x * cellSize;
        recordingCanvas.drawLine(
          Offset(dx, gridOffset.dy),
          Offset(dx, gridOffset.dy + rows * cellSize),
          paint,
        );
      }

      for (int y = 0; y <= rows; y++) {
        final dy = gridOffset.dy + y * cellSize;
        recordingCanvas.drawLine(
          Offset(gridOffset.dx, dy),
          Offset(gridOffset.dx + cols * cellSize, dy),
          paint,
        );
      }

      _gridLinesPicture = recorder.endRecording();
      _lastGridLinesOffsetX = gridOffset.dx;
      _lastGridLinesOffsetY = gridOffset.dy;
      _lastGridLinesScale = cellSize;
    }

    // Draw the cached grid lines picture
    canvas.drawPicture(_gridLinesPicture);

    // Draw grid border
    final borderRect = Rect.fromLTWH(
      gridOffset.dx,
      gridOffset.dy,
      cols * cellSize,
      rows * cellSize,
    );

    canvas.drawRect(
      borderRect,
      Paint()
        ..color = Colors.white38
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    // Optional: inner shadow effect with a slightly darker line
    canvas.drawRect(
      borderRect.inflate(-2),
      Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawNextPiecePreview(Canvas canvas) {
    final previewX = (size.x - previewSize) / 2;
    final previewY = size.y - previewSize - 40;

    final bgRect = Rect.fromLTWH(previewX, previewY, previewSize, previewSize);

    // Draw muted earth-tone gradient for preview box
    final gradientPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(previewX, previewY),
        Offset(previewX, previewY + previewSize),
        [SandColors.previewBoxDark, SandColors.previewBoxLight],
        [0.0, 1.0],
      );
    canvas.drawRect(bgRect, gradientPaint);

    canvas.drawRect(
      bgRect,
      Paint()
        ..color = SandColors.sandyBeige
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Use cached NEXT TextPainter instead of creating new one every frame
    _nextTextPainter.paint(
      canvas,
      Offset(
        previewX + (previewSize - _nextTextPainter.width) / 2,
        previewY - 28,
      ),
    );

    if (nextShape.isEmpty) return;

    final previewCellSize = cellSize;

    final shapeWidth = _nextShapeMaxX - _nextShapeMinX + 1;
    final shapeHeight = _nextShapeMaxY - _nextShapeMinY + 1;

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
        drawX,
        drawY,
        previewCellSize,
        previewCellSize,
      );
      canvas.drawRect(rect, paint);
    }
  }

  void _drawFloatingScore(Canvas canvas) {
    final fs = _activeFloatingScore!;
    final pos = fs.currentPosition;
    final alpha = fs.alpha;
    final scale = fs.scale;

    // Color: white for tap, gold for combo
    final color = fs.type == FloatingScoreType.tap
        ? Colors.white.withAlpha((255 * alpha).toInt())
        : Colors.amber.withAlpha((255 * alpha).toInt());

    final textPainter = TextPainter(
      text: TextSpan(
        text: '+${fs.value}',
        style: TextStyle(
          color: color,
          fontSize: fs.fontSize * scale,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black.withAlpha((128 * alpha).toInt()),
              blurRadius: 4,
              offset: const Offset(1, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    textPainter.paint(
      canvas,
      Offset(pos.dx - textPainter.width / 2, pos.dy - textPainter.height / 2),
    );
  }

  /// Resets game state for a new game. Clears the board and resets all game flags.
  void resetGameState() {
    sandWorld = SandWorld(cols: cols, rows: rows);
    _generateNextPiece();
    ScoringService.instance.resetScore();
    _isGameOverDetected = false;
    _previousMilestone = 0;
    _wasStableLastFrame = true;
    _needsSimulation = false;
    _accumulator = 0;
    _placementsSinceLastSave = 0;
    _hasPendingAutosave = false;
    _isAutosaveInFlight = false;
    _cellsToClears.clear();
    _clearingCellAnimations.clear();
    _clearingElapsedTime = 0;
    _clearMask.fillRange(0, _clearMask.length, 0);
    _colors.fillRange(0, _colors.length, 0);
    _updateVertexPositions();

    _needsVertexUpdate = true;
    _cachedVertices = null;
    _activeFloatingScore = null;
    _shakeIntensity = 0;
    _shakeElapsed = 0;
    _shakeOffset = Offset.zero;
    _confettiEmitter.particles.clear();
    _activeBadge = null;
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

      // Restore score
      ScoringService.instance.setScore(score);

      // Generate next piece and reset flags
      _generateNextPiece();
      _isGameOverDetected = false;
      _previousMilestone = MilestoneService.instance.getCurrentMilestone(score);
      _wasStableLastFrame = true;
      _needsSimulation = false;
      _accumulator = 0;
      _placementsSinceLastSave = 0;
      _hasPendingAutosave = false;
      _isAutosaveInFlight = false;
      _cellsToClears.clear();
      _clearingCellAnimations.clear();
      _clearingElapsedTime = 0;
      _clearMask.fillRange(0, _clearMask.length, 0);
      _syncAllCellColorsFromWorld();
      _updateVertexPositions();
    } catch (e) {
      // Silently fail if load is corrupted
    }
  }
}
