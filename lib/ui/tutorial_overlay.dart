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

class _TutorialOverlayState extends State<TutorialOverlay>
  with TickerProviderStateMixin {
  late final TutorialCoachController _coach;
  late final VoidCallback _listener;
  late final AnimationController _entranceController;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  late final AnimationController _titleController;
  late final Animation<double> _titleScale;
  TutorialCoachPhase? _lastPhase;

  @override
  void initState() {
    super.initState();
    _coach = widget.game.tutorialCoach;
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entranceController, curve: Curves.easeOut));

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeIn),
    );

    _titleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _titleScale = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _titleController, curve: Curves.elasticOut),
    );

    _lastPhase = _coach.phase;

    _listener = () {
      if (!mounted) {
        return;
      }

      if (_coach.isComplete) {
        widget.game.overlays.remove(GameConfig.tutorialOverlay);
        return;
      }

      // Play entrance when becoming active
      if (_coach.isActive && _entranceController.status != AnimationStatus.forward) {
        _entranceController.forward(from: 0);
      }

      // Trigger title pop on phase change
      if (_lastPhase != _coach.phase) {
        _titleController.forward(from: 0);
        _lastPhase = _coach.phase;
      }

      setState(() {});
    };
    _coach.addListener(_listener);

    // If the coach is already active before this overlay was created,
    // kick off the entrance and title animations so the intro is visible.
    if (_coach.isActive) {
      _entranceController.forward(from: 0);
      _titleController.forward(from: 0);
      _lastPhase = _coach.phase;
    }
  }

  @override
  void dispose() {
    _coach.removeListener(_listener);
    _entranceController.dispose();
    _titleController.dispose();
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
              child: SlideTransition(
                position: _slideAnim,
                child: FadeTransition(
                  opacity: _fadeAnim,
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
                      ScaleTransition(
                        scale: _titleScale,
                        child: Text(
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
      )
    );
  }
}
