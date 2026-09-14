import 'package:flutter/material.dart';
import 'package:sandfall/config/game_config.dart';
import 'package:sandfall/game.dart';
import 'package:sandfall/models/daily_challenge_state.dart';
import 'package:sandfall/services/daily_challenge_service.dart';
import 'package:sandfall/theme/theme.dart';
import 'package:sandfall/ui/components/menu_button.dart';

class DailyChallengeOverlay extends StatefulWidget {
  final SandGame game;

  const DailyChallengeOverlay({super.key, required this.game});

  @override
  State<DailyChallengeOverlay> createState() => _DailyChallengeOverlayState();
}

class _DailyChallengeOverlayState extends State<DailyChallengeOverlay> {
  DailyChallengeState? _state;

  SandGame get _game => widget.game;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await DailyChallengeService.instance.loadState();
    if (mounted) setState(() => _state = state);
  }

  String get _dateLabel {
    final now = DateTime.now();
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[now.month]} ${now.day}, ${now.year}';
  }

  Future<void> _startChallenge() async {
    _game.overlays.remove(GameConfig.dailyChallengeOverlay);
    _game.overlays.add(GameConfig.hudOverlay);
    _game.startDailyChallenge();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;

    return Material(
      color: SandColors.darkBg,
      child: SafeArea(
        child: Center(
          child: state == null
              ? const CircularProgressIndicator(color: SandColors.primaryGold)
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 40,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Date
                      Text(
                        _dateLabel,
                        style: TextStyle(
                          fontSize: 13,
                          letterSpacing: 2,
                          color: SandColors.lightSand.withAlpha(100),
                          fontFamily: 'monospace',
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Title
                      Text(
                        'DAILY CHALLENGE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: SandColors.primaryGold.withAlpha(200),
                          letterSpacing: 6,
                          fontFamily: 'monospace',
                        ),
                      ),

                      // Streak — emotional hook right under the title
                      if (state.streak > 0) ...[
                        const SizedBox(height: 12),
                        Text(
                          '🔥 ${state.streak}-day streak',
                          style: const TextStyle(
                            fontSize: 17,
                            color: Colors.orangeAccent,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],

                      const SizedBox(height: 32),

                      // Goal — the single most important piece of info
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 20,
                        ),
                        decoration: BoxDecoration(
                          color: SandColors.warmAccent.withAlpha(25),
                          border: Border.all(
                            color: SandColors.warmAccent.withAlpha(100),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Hit a ${DailyChallengeService.getDailyComboTarget()}-combo chain',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                color: SandColors.warmAccent,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Place ${DailyChallengeService.blockCount} blocks · 3 attempts',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: SandColors.lightSand.withAlpha(120),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Stats — flat rows, no extra box
                      _StatRow(
                        label: 'Attempts used',
                        value:
                            '${state.attemptsUsed} / ${DailyChallengeService.maxAttempts}',
                      ),

                      if (state.bestCombo > 0) ...[
                        const SizedBox(height: 12),
                        _StatRow(
                          label: 'Best combo today',
                          value: '${state.bestCombo} / ${state.comboTarget}',
                          highlight: state.challengeCompleted,
                        ),
                      ],

                      if (state.challengeCompleted) ...[
                        const SizedBox(height: 12),
                        _StatRow(
                          label: 'Best efficiency',
                          value: '${state.bestBlocksRemaining} blocks left',
                          highlight: true,
                        ),
                      ],

                      const SizedBox(height: 40),

                      // Primary action
                      if (state.completedToday) ...[
                        Text(
                          'Come back tomorrow',
                          style: TextStyle(
                            fontSize: 15,
                            color: SandColors.lightSand.withAlpha(120),
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'All ${DailyChallengeService.maxAttempts} attempts used',
                          style: TextStyle(
                            fontSize: 12,
                            color: SandColors.lightSand.withAlpha(60),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ] else
                        MenuButton(
                          label: state.attemptsUsed == 0
                              ? 'START CHALLENGE'
                              : 'TRY AGAIN',
                          sublabel: state.attemptsUsed > 0
                              ? '${DailyChallengeService.maxAttempts - state.attemptsUsed} attempts left'
                              : null,
                          onPressed: _startChallenge,
                        ),

                      const SizedBox(height: 20),

                      // Back — text link, low visual weight
                      TextButton(
                        onPressed: () {
                          _game.overlays.remove(
                            GameConfig.dailyChallengeOverlay,
                          );
                          _game.overlays.add(GameConfig.mainMenuOverlay);
                        },
                        child: Text(
                          'Back',
                          style: TextStyle(
                            fontSize: 14,
                            color: SandColors.lightSand.withAlpha(120),
                            fontFamily: 'monospace',
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _StatRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: SandColors.lightSand.withAlpha(140),
            fontFamily: 'monospace',
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: highlight
                ? SandColors.warmAccent.withAlpha(220)
                : SandColors.lightSand.withAlpha(200),
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
