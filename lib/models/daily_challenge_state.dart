import 'package:sandfall/services/daily_challenge_service.dart';

class DailyChallengeState {
  final int dayNumber;
  final int streak;
  final int attemptsUsed;
  final int bestScore;
  final bool completedToday;

  const DailyChallengeState({
    required this.dayNumber,
    required this.streak,
    required this.attemptsUsed,
    required this.bestScore,
    required this.completedToday,
  });

  bool get hasAttemptsLeft => attemptsUsed < DailyChallengeService.maxAttempts;
}
