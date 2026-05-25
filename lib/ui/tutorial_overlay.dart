import 'package:flutter/material.dart';
import 'package:sandfall/config/game_config.dart';
import 'package:sandfall/game.dart';
import 'package:sandfall/theme/theme.dart';
import 'package:sandfall/tutorial/tutorial_coach.dart';

class TutorialOverlay extends StatefulWidget {
  final SandGame game;

  const TutorialOverlay({super.key, required this.game});

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  late final TutorialCoachController _coach;
  late final VoidCallback _listener;

  @override
  void initState() {
    super.initState();
    _coach = widget.game.tutorialCoach;
    _listener = () {
      if (!mounted) {
        return;
      }

      if (_coach.isComplete) {
        widget.game.overlays.remove(GameConfig.tutorialOverlay);
        return;
      }

      setState(() {});
    };
    _coach.addListener(_listener);
  }

  @override
  void dispose() {
    _coach.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_coach.isActive) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 118, left: 18, right: 18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: SandColors.darkBg.withAlpha(226),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: SandColors.primaryGold.withAlpha(160),
                      width: 1.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x55000000),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _coach.title,
                        style: const TextStyle(
                          color: SandColors.primaryGold,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          fontFamily: 'monospace',
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _coach.message,
                        style: const TextStyle(
                          color: SandColors.lightSand,
                          fontSize: 14,
                          height: 1.45,
                          decoration: TextDecoration.none,
                        ),
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
