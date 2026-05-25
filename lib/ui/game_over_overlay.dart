import 'package:flutter/material.dart';
import 'package:sandfall/config/game_config.dart';
import 'package:sandfall/game.dart';
import 'package:sandfall/services/high_score_service.dart';
import 'package:sandfall/services/play_games_service.dart';
import 'package:sandfall/services/scoring_service.dart';
import 'package:sandfall/theme/theme.dart';
import 'package:sandfall/ui/components/menu_button.dart';

class GameOverOverlay extends StatelessWidget {
  final SandGame game;

  const GameOverOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final finalScore = ScoringService.instance.currentScore;

    final highScore = HighScoreService.instance.getHighScore();

    final isNewRecord = finalScore >= highScore;

    return Material(
      color: Colors.black.withAlpha(160),
      child: Center(
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

              MenuButton.secondary(
                label: 'LEADERBOARDS',
                onPressed: () async {
                  final opened =
                      await PlayGamesService.instance.showLeaderboards();

                  if (!context.mounted) {
                    return;
                  }

                  if (!opened) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Play Games leaderboards are not available yet.'),
                      ),
                    );
                  }
                },
              ),

              const SizedBox(height: 12),

              Divider(color: SandColors.deepSand.withAlpha(100), height: 1),

              const SizedBox(height: 18),

              MenuButton(
                label: 'RETURN TO MENU',
                onPressed: () {
                  game.overlays.remove(GameConfig.gameOverOverlay);

                  game.overlays.add(GameConfig.mainMenuOverlay);
                },
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
