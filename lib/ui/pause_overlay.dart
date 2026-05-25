import 'package:flutter/material.dart';
import 'package:sandfall/config/game_config.dart';
import 'package:sandfall/game.dart';
import 'package:sandfall/theme/theme.dart';
import 'package:sandfall/ui/confirmation_dialog.dart';
import 'package:sandfall/ui/components/menu_button.dart';

/// Pause overlay for the Sand Crush game.
///
/// Shows options to resume, restart, return to menu, and toggle sound/haptics.
class PauseOverlay extends StatefulWidget {
  final SandGame game;

  const PauseOverlay({super.key, required this.game});

  @override
  State<PauseOverlay> createState() => _PauseOverlayState();
}

class _PauseOverlayState extends State<PauseOverlay>
    with SingleTickerProviderStateMixin {
  // bool _soundEnabled = true;
  // bool _hapticEnabled = true;

  static const Duration _leaveAnimationDuration = Duration(milliseconds: 260);

  late final AnimationController _leaveController;
  late final Animation<double> _leaveFade;
  late final Animation<Offset> _leaveSlide;
  late final Animation<double> _leaveScale;

  bool _isLeaving = false;

  @override
  void initState() {
    super.initState();
    widget.game.pauseEngine();

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

    _leaveController.value = 1.0;
    _leaveController.reverse();
  }

  @override
  void dispose() {
    _leaveController.dispose();
    super.dispose();
  }

  Future<void> _leaveToMainMenu() async {
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

    widget.game.resetGameState();
    widget.game.overlays.remove(GameConfig.pauseOverlay);
    widget.game.overlays.remove(GameConfig.hudOverlay);
    widget.game.overlays.add(GameConfig.mainMenuOverlay);
  }

  void _resume() {
    widget.game.resumeEngine();
    widget.game.overlays.remove(GameConfig.pauseOverlay);
  }

  void _restart() {
    widget.game.startNewGame();
    widget.game.overlays.remove(GameConfig.pauseOverlay);
  }

  void _mainMenu() {
    _leaveToMainMenu();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withAlpha(160),
      child: Stack(
        children: [
          IgnorePointer(
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 28,
                      ),
                      decoration: BoxDecoration(
                        color: SandColors.darkBg.withAlpha(240),
                        border: Border.all(color: SandColors.deepSand, width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'PAUSED',
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

                          MenuButton(label: 'RESUME', onPressed: _resume),
                          const SizedBox(height: 10),

                          MenuButton(label: 'RESTART', onPressed: _restart),
                          const SizedBox(height: 10),

                          MenuButton(label: 'MAIN MENU', onPressed: _mainMenu),

                          const SizedBox(height: 24),

                          Divider(
                            color: SandColors.deepSand.withAlpha(100),
                            height: 1,
                          ),

                          const SizedBox(height: 16),

                          MenuButton.secondary(
                            label: 'PLAY TUTORIAL',
                            onPressed: () async {
                              final shouldStart = await showConfirmationDialog(
                                context,
                                title: 'REPLACE CURRENT RUN?',
                                message:
                                    'Your current run will be replaced and a new tutorial game will start.',
                              );

                              if (!context.mounted || !shouldStart) {
                                return;
                              }

                              widget.game.startTutorialGame();
                              widget.game.overlays.remove(GameConfig.pauseOverlay);
                              widget.game.overlays.add(GameConfig.tutorialOverlay);
                            },
                          ),

                          // const SizedBox(height: 18),
                          //
                          // _SettingRow(
                          //   label: 'Sound',
                          //   value: _soundEnabled,
                          //   onChanged: (value) {
                          //     setState(() {
                          //       _soundEnabled = value;
                          //     });
                          //   },
                          // ),
                          //
                          // const SizedBox(height: 10),
                          //
                          // _SettingRow(
                          //   label: 'Haptics',
                          //   value: _hapticEnabled,
                          //   onChanged: (value) {
                          //     setState(() {
                          //       _hapticEnabled = value;
                          //     });
                          //   },
                          // ),
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

