import 'package:sandfall/services/daily_challenge_service.dart';

class DailyChallengeState {
  final int dayNumber;
  final int streak;
  final int highestStreak;
  final int attemptsUsed;
  final int bestScore;
  final bool completedToday;

  // Challenge-specific fields
  final int comboTarget;
  final int bestCombo; // highest combo reached across all attempts today
  final int
  bestBlocksRemaining; // blocks left when target was first hit (0 if never hit)
  final bool challengeCompleted; // true if comboTarget was hit in any attempt

  const DailyChallengeState({
    required this.dayNumber,
    required this.streak,
    required this.highestStreak,
    required this.attemptsUsed,
    required this.bestScore,
    required this.completedToday,
    required this.comboTarget,
    required this.bestCombo,
    required this.bestBlocksRemaining,
    required this.challengeCompleted,
  });

  bool get hasAttemptsLeft => attemptsUsed < DailyChallengeService.maxAttempts;
}
