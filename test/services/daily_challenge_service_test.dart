import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sandfall/services/daily_challenge_service.dart';

import '../helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    await HiveTestHelper.setUp();
    await DailyChallengeService.instance.initialize();
  });

  tearDown(() async {
    await HiveTestHelper.tearDown();
  });

  group('DailyChallengeService — first launch', () {
    test('streak starts at 1 on first ever play', () async {
      final state = await DailyChallengeService.instance.loadState();
      expect(state.streak, 1);
    });

    test('attempts start at 0', () async {
      final state = await DailyChallengeService.instance.loadState();
      expect(state.attemptsUsed, 0);
    });

    test('best score starts at 0', () async {
      final state = await DailyChallengeService.instance.loadState();
      expect(state.bestScore, 0);
    });

    test('completedToday is false before any attempt', () async {
      final state = await DailyChallengeService.instance.loadState();
      expect(state.completedToday, false);
    });

    test('hasAttemptsLeft is true before any attempt', () async {
      final state = await DailyChallengeService.instance.loadState();
      expect(state.hasAttemptsLeft, true);
    });
  });

  group('DailyChallengeService — attempt recording', () {
    test('attempt count increments after recordAttempt', () async {
      await DailyChallengeService.instance.recordAttempt(1000);
      final state = await DailyChallengeService.instance.loadState();
      expect(state.attemptsUsed, 1);
    });

    test('best score updates when new score is higher', () async {
      await DailyChallengeService.instance.recordAttempt(1000);
      await DailyChallengeService.instance.recordAttempt(5000);
      final state = await DailyChallengeService.instance.loadState();
      expect(state.bestScore, 5000);
    });

    test('best score does not drop when new score is lower', () async {
      await DailyChallengeService.instance.recordAttempt(5000);
      await DailyChallengeService.instance.recordAttempt(1000);
      final state = await DailyChallengeService.instance.loadState();
      expect(state.bestScore, 5000);
    });

    test('completedToday is true after max attempts', () async {
      for (int i = 0; i < DailyChallengeService.maxAttempts; i++) {
        await DailyChallengeService.instance.recordAttempt(1000 * (i + 1));
      }
      final state = await DailyChallengeService.instance.loadState();
      expect(state.completedToday, true);
      expect(state.hasAttemptsLeft, false);
    });

    test('attempts do not exceed maxAttempts', () async {
      // Record more than max
      for (int i = 0; i < DailyChallengeService.maxAttempts + 5; i++) {
        await DailyChallengeService.instance.recordAttempt(1000);
      }
      final state = await DailyChallengeService.instance.loadState();
      expect(state.attemptsUsed, DailyChallengeService.maxAttempts);
    });
  });

  group('DailyChallengeService — streak logic', () {
    test('streak increments on consecutive day', () async {
      final box = Hive.box('dailyChallenge');
      final today = DailyChallengeService.todayNumber;

      // Simulate yesterday having been played
      await box.putAll({
        'lastDay': today - 1,
        'streak': 3,
        'attemptsUsed': 1,
        'bestScore': 2000,
      });

      final state = await DailyChallengeService.instance.loadState();
      expect(state.streak, 4);
    });

    test('streak resets to 1 after missing a day', () async {
      final box = Hive.box('dailyChallenge');
      final today = DailyChallengeService.todayNumber;

      // Simulate two days ago
      await box.putAll({
        'lastDay': today - 2,
        'streak': 7,
        'attemptsUsed': 2,
        'bestScore': 5000,
      });

      final state = await DailyChallengeService.instance.loadState();
      expect(state.streak, 1);
    });

    test('streak resets to 1 after missing multiple days', () async {
      final box = Hive.box('dailyChallenge');
      final today = DailyChallengeService.todayNumber;

      await box.putAll({
        'lastDay': today - 10,
        'streak': 30,
        'attemptsUsed': 3,
        'bestScore': 9000,
      });

      final state = await DailyChallengeService.instance.loadState();
      expect(state.streak, 1);
    });

    test('streak does not change when same day loaded twice', () async {
      // First load sets streak to 1
      await DailyChallengeService.instance.loadState();
      // Second load same day should not change it
      final state = await DailyChallengeService.instance.loadState();
      expect(state.streak, 1);
    });
  });

  group('DailyChallengeService — new day resets', () {
    test('attempts reset to 0 on new day', () async {
      final box = Hive.box('dailyChallenge');
      final today = DailyChallengeService.todayNumber;

      await box.putAll({
        'lastDay': today - 1,
        'streak': 1,
        'attemptsUsed': 3,
        'bestScore': 8000,
      });

      final state = await DailyChallengeService.instance.loadState();
      expect(state.attemptsUsed, 0);
    });

    test('best score resets to 0 on new day', () async {
      final box = Hive.box('dailyChallenge');
      final today = DailyChallengeService.todayNumber;

      await box.putAll({
        'lastDay': today - 1,
        'streak': 1,
        'attemptsUsed': 2,
        'bestScore': 9999,
      });

      final state = await DailyChallengeService.instance.loadState();
      expect(state.bestScore, 0);
    });
  });

  group('DailyChallengeService — block sequence', () {
    test('generates correct number of blocks', () {
      final seq = DailyChallengeService.instance.generateBlockSequence(3);
      expect(seq.length, DailyChallengeService.blockCount);
    });

    test('all color indices are within bounds', () {
      final seq = DailyChallengeService.instance.generateBlockSequence(3);
      expect(seq.every((i) => i >= 0 && i < 3), true);
    });

    test('same seed produces same sequence', () {
      final seq1 = DailyChallengeService.instance.generateBlockSequence(3);
      final seq2 = DailyChallengeService.instance.generateBlockSequence(3);
      expect(seq1, equals(seq2));
    });

    test('sequence is deterministic across color counts', () {
      // Both should produce the same raw sequence — color count only clamps
      final seq3 = DailyChallengeService.instance.generateBlockSequence(3);
      final seq6 = DailyChallengeService.instance.generateBlockSequence(6);
      expect(seq3.length, seq6.length);
    });
  });
}
