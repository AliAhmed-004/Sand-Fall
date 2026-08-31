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
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[now.month]} ${now.day}, ${now.year}';
  }

  Future<void> _startChallenge() async {
    // Daily challenge has its own save slot — never touches the regular save.
    // No warning needed.
    _game.overlays.remove(GameConfig.dailyChallengeOverlay);
    _game.overlays.add(GameConfig.hudOverlay);
    _game.startDailyChallenge();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;

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

                    // Date
                    Text(
                      _dateLabel,
                      style: TextStyle(
                        fontSize: 14,
                        letterSpacing: 2,
                        color: SandColors.lightSand.withAlpha(120),
                        fontFamily: 'monospace',
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Title
                    Text(
                      'DAILY',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: SandColors.primaryGold.withAlpha(200),
                        letterSpacing: 8,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      'CHALLENGE',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: SandColors.primaryGold.withAlpha(200),
                        letterSpacing: 8,
                        fontFamily: 'monospace',
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Streak
                    if (state.streak > 0) ...[
                      Text(
                        '🔥 ${state.streak}-day streak',
                        style: const TextStyle(
                          fontSize: 20,
                          color: Colors.orangeAccent,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Stats card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        color: SandColors.darkBg.withAlpha(160),
                        border: Border.all(
                          color: SandColors.lightSand.withAlpha(60),
                        ),
                      ),
                      child: Column(
                        children: [
                          _StatRow(
                            label: 'ATTEMPTS',
                            value:
                                '${state.attemptsUsed} / ${DailyChallengeService.maxAttempts}',
                          ),
                          if (state.bestScore > 0) ...[
                            const SizedBox(height: 8),
                            _StatRow(
                              label: 'BEST TODAY',
                              value: state.bestScore.toString(),
                              highlight: true,
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Action
                    if (state.completedToday) ...[
                      Text(
                        'COME BACK TOMORROW',
                        style: TextStyle(
                          fontSize: 14,
                          letterSpacing: 2,
                          color: SandColors.lightSand.withAlpha(100),
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 4),
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

                    const SizedBox(height: 12),

                    MenuButton.secondary(
                      label: 'BACK',
                      onPressed: () {
                        _game.overlays.remove(GameConfig.dailyChallengeOverlay);
                        _game.overlays.add(GameConfig.mainMenuOverlay);
                      },
                    ),

                    const Spacer(flex: 2),
                  ],
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
            fontSize: 13,
            letterSpacing: 2,
            color: SandColors.lightSand.withAlpha(120),
            fontFamily: 'monospace',
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w300,
            color: highlight
                ? SandColors.primaryGold.withAlpha(200)
                : SandColors.lightSand.withAlpha(180),
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
