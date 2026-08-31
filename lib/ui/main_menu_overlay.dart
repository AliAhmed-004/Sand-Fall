import 'dart:math';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sandfall/config/game_config.dart';
import 'package:sandfall/game.dart';
import 'package:sandfall/services/daily_challenge_service.dart';
import 'package:sandfall/services/high_score_service.dart';
import 'package:sandfall/services/play_games_service.dart';
import 'package:sandfall/services/save_game_service.dart';
import 'package:sandfall/services/update_service.dart';
import 'package:sandfall/theme/theme.dart';
import 'package:sandfall/ui/confirmation_dialog.dart';
import 'package:sandfall/ui/components/menu_button.dart';

class MainMenuOverlay extends StatefulWidget {
  final SandGame game;

  const MainMenuOverlay({super.key, required this.game});

  @override
  State<MainMenuOverlay> createState() => _MainMenuOverlayState();
}

class _MainMenuOverlayState extends State<MainMenuOverlay>
    with SingleTickerProviderStateMixin {
  static const Duration _launchAnimationDuration = Duration(milliseconds: 280);

  late final AnimationController _launchController;
  late final Animation<double> _cardFade;
  late final Animation<Offset> _cardSlide;
  late final Animation<double> _cardScale;

  bool _isLaunching = false;
  Future<void> Function()? _pendingLaunch;

  int _dailyStreak = 0;
  bool _dailyPlayedToday = false;

  SandGame get _game => widget.game;

  @override
  void initState() {
    super.initState();
    _launchController = AnimationController(
      vsync: this,
      duration: _launchAnimationDuration,
      animationBehavior: AnimationBehavior.preserve,
    );

    final easing = CurvedAnimation(
      parent: _launchController,
      curve: Curves.easeOutCubic,
    );

    _cardFade = Tween<double>(begin: 1.0, end: 0.0).animate(easing);
    _cardSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -0.06),
    ).animate(easing);
    _cardScale = Tween<double>(begin: 1.0, end: 0.975).animate(easing);

    _launchController.addStatusListener(_onLaunchAnimationStatus);

    // Check for app updates when main menu is shown
    _checkForAppUpdate();

    // Load daily challenge state for streak display
    _loadDailyChallengeState();
  }

  Future<void> _loadDailyChallengeState() async {
    final state = await DailyChallengeService.instance.loadState();
    if (mounted) {
      setState(() {
        _dailyStreak = state.streak;
        _dailyPlayedToday = state.completedToday;
      });
    }
  }

  Future<void> _checkForAppUpdate() async {
    await UpdateService.instance.checkForUpdate();
    // Show update prompt if available
    if (mounted && UpdateService.instance.updateAvailable) {
      await UpdateService.instance.showUpdatePromptIfAvailable(context);
    }
  }

  @override
  void dispose() {
    _launchController.removeStatusListener(_onLaunchAnimationStatus);
    _launchController.dispose();
    super.dispose();
  }

  void _onLaunchAnimationStatus(AnimationStatus status) async {
    if (status != AnimationStatus.completed || _pendingLaunch == null) {
      return;
    }

    final launchAction = _pendingLaunch;
    _pendingLaunch = null;

    await launchAction?.call();

    if (!mounted) {
      return;
    }

    _game.overlays.remove(GameConfig.mainMenuOverlay);
  }

  void _launchIntoGame(Future<void> Function() action) {
    if (_isLaunching) {
      return;
    }

    setState(() {
      _isLaunching = true;
      _pendingLaunch = action;
    });

    _launchController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final highScore = HighScoreService.instance.getHighScore();
    final hasSavedGame = SaveGameService.instance.hasRegularGame();
    final savedScore = SaveGameService.instance.getSavedRegularScore();

    return Material(
      color: SandColors.darkBg,
      child: Stack(
        children: [
          const Positioned.fill(child: _FallingTetrominoBackground()),
          IgnorePointer(
            ignoring: _isLaunching,
            child: Center(
              child: FadeTransition(
                opacity: _cardFade,
                child: SlideTransition(
                  position: _cardSlide,
                  child: ScaleTransition(
                    scale: _cardScale,
                    child: Container(
                      decoration: BoxDecoration(
                        color: SandColors.darkBg.withAlpha(80),
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

                          AnimatedBuilder(
                            animation: PlayGamesService.instance,
                            builder: (context, child) {
                              return MenuButton.secondary(
                                label:
                                    PlayGamesService.instance.leaderboardsLabel,
                                onPressed: () async {
                                  final opened = await PlayGamesService.instance
                                      .showLeaderboards();

                                  if (!context.mounted) {
                                    return;
                                  }

                                  if (!opened) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Play Games leaderboards are not available yet.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              );
                            },
                          ),

                          const SizedBox(height: 12),

                          if (hasSavedGame) ...[
                            MenuButton(
                              label: 'CONTINUE',
                              sublabel: 'Score: $savedScore',
                              onPressed: () {
                                _launchIntoGame(() async {
                                  _game.continueSavedGame();
                                  _game.overlays.add(GameConfig.hudOverlay);
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                          ],

                          MenuButton(
                            label: 'NEW GAME',
                            onPressed: () async {
                              final shouldStartNewGame = hasSavedGame
                                  ? await showConfirmationDialog(
                                      context,
                                      title: 'START NEW GAME?',
                                      message:
                                          'Your saved game will be deleted and a new game will start.',
                                    )
                                  : true;

                              if (!context.mounted || !shouldStartNewGame) {
                                return;
                              }

                              await SaveGameService.instance.deleteRegularGame();
                              if (!context.mounted) {
                                return;
                              }

                              _launchIntoGame(() async {
                                _game.startNewGame();
                                _game.overlays.add(GameConfig.hudOverlay);
                              });
                            },
                          ),

                          Divider(
                            height: 32,
                            thickness: 1,
                            color: SandColors.lightSand.withAlpha(100),
                          ),

                          const SizedBox(height: 10),

                          MenuButton(
                            label: 'DAILY CHALLENGE',
                            sublabel: _dailyStreak > 1
                                ? '🔥 $_dailyStreak-day streak'
                                : _dailyPlayedToday
                                    ? 'Completed today ✓'
                                    : 'New challenge available!',
                            onPressed: () {
                              _game.overlays.remove(GameConfig.mainMenuOverlay);
                              _game.overlays.add(
                                GameConfig.dailyChallengeOverlay,
                              );
                            },
                          ),

                          const SizedBox(height: 12),

                          MenuButton.secondary(
                            label: 'PLAY TUTORIAL',
                            onPressed: () async {
                              final shouldStart = hasSavedGame
                                  ? await showConfirmationDialog(
                                      context,
                                      title: 'START TUTORIAL?',
                                      message:
                                          'Your saved game will be deleted and a new tutorial run will start.',
                                    )
                                  : true;

                              if (!context.mounted || !shouldStart) {
                                return;
                              }

                              if (hasSavedGame) {
                                await SaveGameService.instance
                                    .deleteRegularGame();
                                if (!context.mounted) {
                                  return;
                                }
                              }

                              _launchIntoGame(() async {
                                _game.startTutorialGame();
                                _game.overlays.add(GameConfig.hudOverlay);
                                _game.overlays.add(GameConfig.tutorialOverlay);
                              });
                            },
                          ),

                          const Spacer(flex: 3),
                        ],
                      ),
                    ),
                  ),
                ),
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
        ((progress - _fallPhaseEnd) / (1.0 - _fallPhaseEnd)).clamp(0.0, 1.0);
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
