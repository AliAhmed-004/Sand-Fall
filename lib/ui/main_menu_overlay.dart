import 'dart:math';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sandfall/config/game_config.dart';
import 'package:sandfall/game.dart';
import 'package:sandfall/services/high_score_service.dart';
import 'package:sandfall/services/save_game_service.dart';
import 'package:sandfall/services/scoring_service.dart';
import 'package:sandfall/theme/theme.dart';
import 'package:sandfall/ui/components/menu_button.dart';

class MainMenuOverlay extends StatelessWidget {
  final SandGame game;

  const MainMenuOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final highScore = HighScoreService.instance.getHighScore();
    final hasSavedGame = SaveGameService.instance.hasSavedGame();
    final savedScore = SaveGameService.instance.getSavedScore();

    return Material(
      color: SandColors.darkBg,
      child: Stack(
        children: [
          const Positioned.fill(child: _FallingTetrominoBackground()),
          Center(
            child: Container(
              decoration: BoxDecoration(
                color: SandColors.darkBg.withAlpha(200),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Spacer(flex: 3),

                  const _GameTitle(),

                  const SizedBox(height: 48),

                  _HighScoreCard(score: highScore),

                  const SizedBox(height: 48),

                  if (hasSavedGame) ...[
                    MenuButton(
                      label: 'CONTINUE',
                      sublabel: 'Score: $savedScore',
                      onPressed: () {
                        game.loadSavedGame();
                        game.isGameStarted = true;
                        game.resumeEngine();
                        game.overlays.remove(GameConfig.mainMenuOverlay);
                        game.overlays.add(GameConfig.hudOverlay);
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  MenuButton(
                    label: 'NEW GAME',
                    onPressed: () {
                      SaveGameService.instance.deleteSavedGame();
                      game.resetGameState();
                      ScoringService.instance.resetScore();
                      game.isGameStarted = true;
                      game.resumeEngine();

                      game.overlays.remove(GameConfig.mainMenuOverlay);

                      game.overlays.add(GameConfig.hudOverlay);
                    },
                  ),

                  const Spacer(flex: 3),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FallingTetrominoBackground extends StatefulWidget {
  const _FallingTetrominoBackground();

  @override
  State<_FallingTetrominoBackground> createState() =>
      _FallingTetrominoBackgroundState();
}

class _FallingTetrominoBackgroundState
    extends State<_FallingTetrominoBackground>
    with SingleTickerProviderStateMixin {
  static const Duration _cycleDuration = Duration(milliseconds: 5000);
  late AnimationController _controller;
  final Random _random = Random();

  // Tetromino cell coordinates (relative positions)
  static const List<List<List<int>>> _shapes = [
    [
      [0, 0],
      [1, 0],
      [2, 0],
      [3, 0],
    ], // I
    [
      [0, 0],
      [1, 0],
      [0, 1],
      [1, 1],
    ], // O
    [
      [0, 0],
      [1, 0],
      [2, 0],
      [1, 1],
    ], // T
    [
      [1, 0],
      [2, 0],
      [0, 1],
      [1, 1],
    ], // S
    [
      [0, 0],
      [1, 0],
      [1, 1],
      [2, 1],
    ], // Z
    [
      [0, 0],
      [0, 1],
      [1, 1],
      [2, 1],
    ], // J
    [
      [2, 0],
      [0, 1],
      [1, 1],
      [2, 1],
    ], // L
  ];

  static const double _cellSize = 20.0;

  int _currentShapeIndex = 0;
  List<List<int>> _currentCells = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _cycleDuration,
      // Keep this background animation time-based even if OS-level
      // "disable animations" is enabled.
      animationBehavior: AnimationBehavior.preserve,
    );
    _selectNewShape();
    _controller.addStatusListener(_onAnimationStatus);
    _controller.forward();
  }

  void _selectNewShape() {
    _currentShapeIndex = _random.nextInt(_shapes.length);
    _currentCells = _shapes[_currentShapeIndex]
        .map((c) => List<int>.from(c))
        .toList();
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(_selectNewShape);
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _TetrominoPainter(
            cells: _currentCells,
            progress: _controller.value,
            cellSize: _cellSize,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _TetrominoPainter extends CustomPainter {
  static const double _fallPhaseEnd = 0.82;
  static const double _scatterDistance = 16.0;

  final List<List<int>> cells;
  final double progress;
  final double cellSize;

  _TetrominoPainter({
    required this.cells,
    required this.progress,
    required this.cellSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fall phase: 0.0 - 0.82 (~1.0s)
    // Scatter phase: 0.82 - 1.0 (~0.2s)
    final double fallProgress = (progress / _fallPhaseEnd).clamp(0.0, 1.0);
    final double scatterProgress =
        ((progress - _fallPhaseEnd) / (1.0 - _fallPhaseEnd))
        .clamp(0.0, 1.0);
    final double easedScatterProgress = Curves.easeInOut.transform(
      scatterProgress,
    );

    // Calculate starting Y so piece falls from above screen to bottom
    final double pieceWidth =
        (cells.map((c) => c[0]).reduce(max) + 1) * cellSize;
    final double pieceHeight =
        (cells.map((c) => c[1]).reduce(max) + 1) * cellSize;
    final double startY = -pieceHeight - 50;
    final double endY = size.height - pieceHeight;
    final double currentY =
      startY + (endY - startY) * Curves.linear.transform(fallProgress);

    // Center the piece horizontally
    final double startX = (size.width - pieceWidth) / 2;

    final double alpha = progress < _fallPhaseEnd
        ? 120.0
      : 120.0 * (1.0 - easedScatterProgress);
    final paint = Paint()
      ..color = SandColors.primaryGold.withAlpha(alpha.round())
      ..style = PaintingStyle.fill;

    for (final cell in cells) {
      double x = startX + cell[0] * cellSize;
      double y = currentY + cell[1] * cellSize;

      // Apply scatter after landing
      if (scatterProgress > 0) {
        final double angle = _randomForCell(cell) * 2 * math.pi;
        final double distance =
            easedScatterProgress * _scatterDistance * _randomForCell2(cell);
        x += cos(angle) * distance;
        y += sin(angle) * distance;
      }

      canvas.drawRect(Rect.fromLTWH(x, y, cellSize - 2, cellSize - 2), paint);
    }
  }

  double _randomForCell(List<int> cell) {
    return ((cell[0] * 7 + cell[1] * 13) % 100) / 100.0;
  }

  double _randomForCell2(List<int> cell) {
    return ((cell[0] * 11 + cell[1] * 17) % 100) / 100.0;
  }

  @override
  bool shouldRepaint(_TetrominoPainter old) {
    return old.progress != progress || old.cells != cells;
  }
}

class _GameTitle extends StatelessWidget {
  const _GameTitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'SAND',
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: SandColors.primaryGold.withAlpha(200),
            letterSpacing: 8,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          'FALL',
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: SandColors.primaryGold.withAlpha(200),
            letterSpacing: 8,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class _HighScoreCard extends StatelessWidget {
  final int score;

  const _HighScoreCard({required this.score});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'HIGH SCORE',
          style: TextStyle(
            fontSize: 16,
            letterSpacing: 3,
            color: SandColors.lightSand.withAlpha(120),
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 6),
        Text(
          score.toString(),
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w300,
            color: SandColors.primaryGold.withAlpha(180),
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
