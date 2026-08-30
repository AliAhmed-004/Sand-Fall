import 'package:flutter/material.dart';
import 'package:sandfall/config/game_config.dart';
import 'package:sandfall/game.dart';
import 'package:sandfall/models/daily_challenge_state.dart';
import 'package:sandfall/services/daily_challenge_service.dart';
import 'package:sandfall/services/scoring_service.dart';
import 'package:sandfall/theme/theme.dart';
import 'package:sandfall/ui/components/menu_button.dart';
import 'package:share_plus/share_plus.dart';

class DailyResultOverlay extends StatefulWidget {
  final SandGame game;

  const DailyResultOverlay({super.key, required this.game});

  @override
  State<DailyResultOverlay> createState() => _DailyResultOverlayState();
}

class _DailyResultOverlayState extends State<DailyResultOverlay> {
  DailyChallengeState? _state;
  // Capture score at build time — ScoringService may reset later
  late final int _score;

  SandGame get _game => widget.game;

  @override
  void initState() {
    super.initState();
    _score = _game.isDailyChallengeMode
        ? _game.dailyFinalScore
        : ScoringService.instance.currentScore;
    _load();
  }

  Future<void> _load() async {
    final state = await DailyChallengeService.instance.loadState();
    if (mounted) setState(() => _state = state);
  }

  void _share() {
    final state = _state;
    if (state == null) return;

    final now = DateTime.now();
    final dateStr = '${now.day}/${now.month}/${now.year}';
    final streakLine =
        state.streak > 1 ? '\n🔥 ${state.streak}-day streak' : '';

    SharePlus.instance.share(
      ShareParams(
        text: 'Sand Fall – Daily Challenge\n'
            '📅 $dateStr$streakLine\n'
            'Score: $_score\n'
            'Can you beat me? → https://play.google.com/store/apps/details?id=com.spudbyte.sandfall',
      ),
    );
  }

  void _retry() {
    _game.overlays.remove(GameConfig.dailyResultOverlay);
    _game.overlays.add(GameConfig.dailyChallengeOverlay);
  }

  void _goToMenu() {
    _game.overlays.remove(GameConfig.dailyResultOverlay);
    _game.overlays.add(GameConfig.mainMenuOverlay);
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final isNewBest = state != null && _score >= state.bestScore;
    final attemptsLeft = state != null
        ? DailyChallengeService.maxAttempts - state.attemptsUsed
        : 0;

    return Material(
      color: SandColors.darkBg,
      child: Center(
        child: state == null
            ? const CircularProgressIndicator(color: SandColors.primaryGold)
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Spacer(flex: 2),

                    // Header
                    Text(
                      state.completedToday
                          ? 'CHALLENGE'
                          : 'ATTEMPT',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: SandColors.primaryGold.withAlpha(200),
                        letterSpacing: 8,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      state.completedToday ? 'COMPLETE' : 'DONE',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: SandColors.primaryGold.withAlpha(200),
                        letterSpacing: 8,
                        fontFamily: 'monospace',
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Score
                    Text(
                      _score.toString(),
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w300,
                        color: SandColors.primaryGold.withAlpha(200),
                        fontFamily: 'monospace',
                      ),
                    ),

                    if (isNewBest) ...[
                      const SizedBox(height: 4),
                      Text(
                        '✨ NEW BEST',
                        style: TextStyle(
                          fontSize: 13,
                          letterSpacing: 3,
                          color: SandColors.lightSand.withAlpha(180),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Streak
                    if (state.streak > 0)
                      Text(
                        '🔥 ${state.streak}-day streak',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.orangeAccent,
                          fontFamily: 'monospace',
                        ),
                      ),

                    const SizedBox(height: 32),

                    // Attempts remaining hint
                    if (!state.completedToday)
                      Text(
                        '$attemptsLeft attempt${attemptsLeft == 1 ? '' : 's'} remaining',
                        style: TextStyle(
                          fontSize: 13,
                          letterSpacing: 1,
                          color: SandColors.lightSand.withAlpha(100),
                          fontFamily: 'monospace',
                        ),
                      ),

                    if (!state.completedToday) const SizedBox(height: 16),

                    // Retry — only if attempts remain
                    if (!state.completedToday)
                      MenuButton(
                        label: 'TRY AGAIN',
                        onPressed: _retry,
                      ),

                    const SizedBox(height: 12),

                    MenuButton.secondary(
                      label: 'SHARE SCORE',
                      onPressed: _share,
                    ),

                    const SizedBox(height: 12),

                    MenuButton.secondary(
                      label: 'MAIN MENU',
                      onPressed: _goToMenu,
                    ),

                    const Spacer(flex: 2),
                  ],
                ),
              ),
      ),
    );
  }
}
