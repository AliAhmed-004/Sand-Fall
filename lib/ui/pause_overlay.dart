import 'package:flutter/material.dart';
import 'package:sandfall/config/game_config.dart';
import 'package:sandfall/game.dart';
import 'package:sandfall/theme/theme.dart';
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

class _PauseOverlayState extends State<PauseOverlay> {
  // bool _soundEnabled = true;
  // bool _hapticEnabled = true;

  @override
  void initState() {
    super.initState();
    widget.game.pauseEngine();
  }

  void _resume() {
    widget.game.resumeEngine();
    widget.game.overlays.remove(GameConfig.pauseOverlay);
  }

  void _restart() {
    // SaveGameService.instance.deleteSavedGame();
    widget.game.resetGameState();
    widget.game.resumeEngine();
    widget.game.overlays.remove(GameConfig.pauseOverlay);
  }

  void _mainMenu() {
    widget.game.resetGameState();
    widget.game.overlays.remove(GameConfig.pauseOverlay);
    widget.game.overlays.remove(GameConfig.hudOverlay);
    widget.game.overlays.add(GameConfig.mainMenuOverlay);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withAlpha(160),
      child: Center(
        child: Container(
          width: 320,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
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

              Divider(color: SandColors.deepSand.withAlpha(100), height: 1),

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
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: SandColors.lightSand.withAlpha(180),
              fontSize: 13,
              letterSpacing: 1.5,
              fontFamily: 'monospace',
            ),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: SandColors.primaryGold,
          activeTrackColor: SandColors.deepSand.withAlpha(150),
        ),
      ],
    );
  }
}
