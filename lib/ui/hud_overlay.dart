import 'package:flutter/material.dart';
import 'package:sandfall/config/game_config.dart';
import 'package:sandfall/game.dart';
import 'package:sandfall/services/milestone_service.dart';
import 'package:sandfall/services/scoring_service.dart';
import 'package:sandfall/theme/theme.dart';

/// HUD overlay for the Sand Crush game, showing score, progress, and pause button.
///
/// Horizontal layout: Score (left) • Progress Bar (center) • Pause Button (right)
class HudOverlay extends StatefulWidget {
  final SandGame game;

  const HudOverlay({super.key, required this.game});

  @override
  State<HudOverlay> createState() => _HudOverlayState();
}

class _HudOverlayState extends State<HudOverlay>
  with TickerProviderStateMixin {
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;
  late AnimationController _entranceController;
  late Animation<double> _entranceOpacity;
  late Animation<Offset> _entranceOffset;

  int _lastMilestone = 0;
  int _milestoneStart = 0;
  int _milestoneEnd = 25000;

  bool _isAnimatingMilestone = false;
  int? _pendingScore;

  @override
  void initState() {
    super.initState();

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      animationBehavior: AnimationBehavior.preserve,
    );

    final entranceCurve = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );

    _entranceOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _entranceOffset = Tween<Offset>(
      begin: const Offset(0, -0.06),
      end: Offset.zero,
    ).animate(entranceCurve);

    _progressAnimation = AlwaysStoppedAnimation(0.0);

    final initialScore = ScoringService.instance.currentScore;

    _lastMilestone = MilestoneService.instance.getCurrentMilestone(
      initialScore,
    );
    _milestoneStart = MilestoneService.instance.getMilestoneScore(
      _lastMilestone,
    );
    _milestoneEnd = MilestoneService.instance.getNextMilestoneScore(
      initialScore,
    );

    ScoringService.instance.scoreNotifier.addListener(_onScoreChanged);

    _entranceController.forward();
  }

  @override
  void dispose() {
    ScoringService.instance.scoreNotifier.removeListener(_onScoreChanged);
    _entranceController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  void _onScoreChanged() {
    final score = ScoringService.instance.currentScore;
    final newMilestone = MilestoneService.instance.getCurrentMilestone(score);

    if (_isAnimatingMilestone) {
      _pendingScore = score;
      return;
    }

    if (newMilestone > _lastMilestone) {
      _handleMilestoneCross(score, newMilestone);
      return;
    }

    final progress =
        ((score - _milestoneStart) / (_milestoneEnd - _milestoneStart)).clamp(
          0.0,
          1.0,
        );

    _animateTo(progress);
  }

  Future<void> _handleMilestoneCross(int score, int newMilestone) async {
    _isAnimatingMilestone = true;

    final currentProgress = _progressAnimation.value;
    await _animateTo(1.0, from: currentProgress);
    await Future.delayed(const Duration(milliseconds: 120));

    _progressController.reset();
    _progressAnimation = AlwaysStoppedAnimation(0.0);

    _lastMilestone = newMilestone;
    _milestoneStart = MilestoneService.instance.getMilestoneScore(
      _lastMilestone,
    );
    _milestoneEnd = MilestoneService.instance.getNextMilestoneScore(score);

    setState(() {});

    final overflowProgress =
        ((score - _milestoneStart) / (_milestoneEnd - _milestoneStart)).clamp(
          0.0,
          1.0,
        );

    await _animateTo(overflowProgress, from: 0.0);

    _isAnimatingMilestone = false;

    if (_pendingScore != null) {
      _pendingScore = null;
      _onScoreChanged();
    }
  }

  Future<void> _animateTo(double target, {double? from}) async {
    _progressAnimation =
        Tween<double>(
          begin: from ?? _progressAnimation.value,
          end: target,
        ).animate(
          CurvedAnimation(parent: _progressController, curve: Curves.easeOut),
        );

    setState(() {});

    await _progressController.forward(from: 0);
  }

  /// Formats score: full number if < 10,000, otherwise K notation
  String _formatScore(int score) {
    if (score < 10000) {
      return score.toString();
    }
    final k = score / 1000;
    return '${k.toStringAsFixed(1)}K';
  }

  void _togglePause() {
    widget.game.overlays.add(GameConfig.pauseOverlay);
  }

  @override
  Widget build(BuildContext context) {
    final score = ScoringService.instance.currentScore;
    final formattedScore = _formatScore(score);

    return Positioned(
      top: 50,
      left: 20,
      right: 20,
      child: FadeTransition(
        opacity: _entranceOpacity,
        child: SlideTransition(
          position: _entranceOffset,
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: SandColors.darkBg.withAlpha(217), // Slightly more opaque
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SandColors.deepSand, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: SandColors.primaryGold.withAlpha(51), // 20% opacity
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Score (left)
                  Text(
                    formattedScore,
                    style: const TextStyle(
                      color: SandColors.primaryGold,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(width: 20),

                  // Progress Bar (center - flexible)
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _progressController,
                      builder: (context, child) {
                        final progress = _progressAnimation.value;

                        return ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            height: 20,
                            decoration: BoxDecoration(
                              color: SandColors.sandyBeige.withAlpha(
                                51,
                              ), // 20% opacity
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: SandColors.deepSand,
                                width: 1,
                              ),
                            ),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.transparent,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color.lerp(
                                  SandColors.lightSand,
                                  SandColors.warmAccent,
                                  progress,
                                )!,
                              ),
                              minHeight: 20,
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(width: 20),

                  // Pause Button (right)
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _togglePause,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: SandColors.warmAccent.withAlpha(
                              51,
                            ), // 20% opacity
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: SandColors.primaryGold,
                              width: 2,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.pause,
                              color: SandColors.primaryGold,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
