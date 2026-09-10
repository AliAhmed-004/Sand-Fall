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
  late final int _score;
  late final int _longestCombo;
  late final bool _targetHit;
  late final int _blocksRemaining;

  SandGame get _game => widget.game;

  @override
  void initState() {
    super.initState();
    // Capture all attempt stats before anything resets
    _score          = _game.dailyFinalScore;
    _longestCombo   = ScoringService.instance.longestCombo;
    _targetHit      = _game.dailyChallengeTargetHit;
    _blocksRemaining = _game.dailyBlocksRemainingAtHit;
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
    final streakLine = state.streak > 1 ? '\n🔥 ${state.streak}-day streak' : '';

    final resultLine = _targetHit
        ? '🎯 Hit a ${state.comboTarget}-combo with $_blocksRemaining blocks to spare!'
        : '🎯 Best combo: $_longestCombo/${state.comboTarget}';

    SharePlus.instance.share(
      ShareParams(
        text: 'Sand Fall – Daily Challenge\n'
            '📅 $dateStr$streakLine\n'
            '$resultLine\n'
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

                    // Pass / fail header
                    Text(
                      _targetHit ? 'CHALLENGE' : 'ATTEMPT',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: _targetHit
                            ? SandColors.warmAccent.withAlpha(220)
                            : SandColors.primaryGold.withAlpha(200),
                        letterSpacing: 8,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      _targetHit ? 'COMPLETE!' : 'DONE',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: _targetHit
                            ? SandColors.warmAccent.withAlpha(220)
                            : SandColors.primaryGold.withAlpha(200),
                        letterSpacing: 8,
                        fontFamily: 'monospace',
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Combo result
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        color: (_targetHit
                                ? SandColors.warmAccent
                                : SandColors.lightSand)
                            .withAlpha(20),
                        border: Border.all(
                          color: (_targetHit
                                  ? SandColors.warmAccent
                                  : SandColors.lightSand)
                              .withAlpha(80),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _targetHit
                                ? '🎯 ${state.comboTarget}-combo achieved!'
                                : '🎯 Best combo: $_longestCombo / ${state.comboTarget}',
                            style: TextStyle(
                              fontSize: 18,
                              color: _targetHit
                                  ? SandColors.warmAccent
                                  : SandColors.lightSand.withAlpha(200),
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_targetHit) ...[
                            const SizedBox(height: 8),
                            Text(
                              '$_blocksRemaining blocks remaining',
                              style: TextStyle(
                                fontSize: 14,
                                color: SandColors.lightSand.withAlpha(160),
                                fontFamily: 'monospace',
                              ),
                            ),
                            if (state.bestBlocksRemaining > _blocksRemaining) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Personal best: ${state.bestBlocksRemaining}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: SandColors.primaryGold.withAlpha(180),
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 4),
                              Text(
                                '✨ New best!',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: SandColors.primaryGold.withAlpha(200),
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

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

                    const SizedBox(height: 24),

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

                    if (!state.completedToday)
                      MenuButton(
                        label: 'TRY AGAIN',
                        onPressed: _retry,
                      ),

                    const SizedBox(height: 12),

                    MenuButton.secondary(
                      label: 'SHARE RESULT',
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
