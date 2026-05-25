import 'package:flutter/material.dart';
import 'package:sandfall/config/game_config.dart';
import 'package:sandfall/game.dart';
import 'package:sandfall/services/high_score_service.dart';
import 'package:sandfall/services/play_games_service.dart';
import 'package:sandfall/services/scoring_service.dart';
import 'package:sandfall/theme/theme.dart';
import 'package:sandfall/ui/components/menu_button.dart';

class GameOverOverlay extends StatefulWidget {
  final SandGame game;

  const GameOverOverlay({super.key, required this.game});

  @override
  State<GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<GameOverOverlay>
    with SingleTickerProviderStateMixin {
  static const Duration _leaveAnimationDuration = Duration(milliseconds: 260);

  late final AnimationController _leaveController;
  late final Animation<double> _leaveFade;
  late final Animation<Offset> _leaveSlide;
  late final Animation<double> _leaveScale;

  bool _isLeaving = false;

  SandGame get game => widget.game;

  @override
  void initState() {
    super.initState();
    _leaveController = AnimationController(
      vsync: this,
      duration: _leaveAnimationDuration,
      animationBehavior: AnimationBehavior.preserve,
    );

    final easing = CurvedAnimation(
      parent: _leaveController,
      curve: Curves.easeOutCubic,
    );

    _leaveFade = Tween<double>(begin: 1.0, end: 0.0).animate(easing);
    _leaveSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -0.05),
    ).animate(easing);
    _leaveScale = Tween<double>(begin: 1.0, end: 0.98).animate(easing);
  }

  @override
  void dispose() {
    _leaveController.dispose();
    super.dispose();
  }

  Future<void> _returnToMenu() async {
    if (_isLeaving) {
      return;
    }

    setState(() {
      _isLeaving = true;
    });

    await _leaveController.forward(from: 0);

    if (!mounted) {
      return;
    }

    game.overlays.remove(GameConfig.gameOverOverlay);
    game.overlays.add(GameConfig.mainMenuOverlay);
  }

  @override
  Widget build(BuildContext context) {
    final finalScore = ScoringService.instance.currentScore;

    final highScore = HighScoreService.instance.getHighScore();

    final isNewRecord = finalScore >= highScore;

    return Material(
      color: Colors.black.withAlpha(160),
      child: IgnorePointer(
        ignoring: _isLeaving,
        child: Center(
          child: FadeTransition(
            opacity: _leaveFade,
            child: SlideTransition(
              position: _leaveSlide,
              child: ScaleTransition(
                scale: _leaveScale,
                child: Container(
                  width: 320,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  decoration: BoxDecoration(
                    color: SandColors.darkBg.withAlpha(240),
                    border: Border.all(color: SandColors.deepSand, width: 2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'GAME OVER',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: SandColors.primaryGold,
                          letterSpacing: 3,
                          fontFamily: 'monospace',
                        ),
                      ),

                      const SizedBox(height: 24),

                      if (isNewRecord) ...[
                        Text(
                          'NEW RECORD',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: SandColors.warmAccent,
                            letterSpacing: 2,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],

                      _ScoreRow(label: 'SCORE', value: finalScore),

                      const SizedBox(height: 10),

                      _ScoreRow(label: 'BEST', value: highScore),

                      const SizedBox(height: 24),

                      AnimatedBuilder(
                        animation: PlayGamesService.instance,
                        builder: (context, child) {
                          return MenuButton.secondary(
                            label: PlayGamesService.instance.leaderboardsLabel,
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

                      Divider(color: SandColors.deepSand.withAlpha(100), height: 1),

                      const SizedBox(height: 18),

                      MenuButton(
                        label: 'RETURN TO MENU',
                        onPressed: _returnToMenu,
                      ),

                      SizedBox(height: 12),

                      MenuButton(
                        label: "TRY AGAIN",
                        onPressed: () {
                          game.overlays.remove(GameConfig.gameOverOverlay);
                          game.startNewGame();

                          game.overlays.add(GameConfig.hudOverlay);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final String label;
  final int value;

  const _ScoreRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        border: Border.all(color: SandColors.deepSand, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: SandColors.lightSand.withAlpha(180),
                letterSpacing: 1.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: SandColors.primaryGold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
