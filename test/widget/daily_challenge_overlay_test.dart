import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:sandfall/services/daily_challenge_service.dart';
import 'package:sandfall/ui/daily_challenge_overlay.dart';

import '../helpers/hive_test_helper.dart';
import 'overlay_test_helper.dart';

void main() {
  setUp(() async {
    await HiveTestHelper.setUp();
    await DailyChallengeService.instance.initialize();
  });

  tearDown(() async {
    await HiveTestHelper.tearDown();
  });

  testWidgets('shows START CHALLENGE on first visit', (tester) async {
    await tester.pumpWidget(
      overlayTestApp(child: DailyChallengeOverlay(game: FakeSandGame())),
    );

    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('START CHALLENGE'), findsOneWidget);
  });

  testWidgets('shows TRY AGAIN after one attempt', (tester) async {
    await DailyChallengeService.instance.recordAttempt(1000);

    await tester.pumpWidget(
      overlayTestApp(child: DailyChallengeOverlay(game: FakeSandGame())),
    );
    await tester.pumpAndSettle();

    expect(find.text('TRY AGAIN'), findsOneWidget);
    expect(find.textContaining('2 attempts left'), findsOneWidget);
  });

  testWidgets('shows completed state after max attempts', (tester) async {
    for (int i = 0; i < DailyChallengeService.maxAttempts; i++) {
      await DailyChallengeService.instance.recordAttempt(1000);
    }

    await tester.pumpWidget(
      overlayTestApp(child: DailyChallengeOverlay(game: FakeSandGame())),
    );
    await tester.pumpAndSettle();

    expect(find.text('START CHALLENGE'), findsNothing);
    expect(find.text('TRY AGAIN'), findsNothing);
    expect(find.textContaining('COME BACK TOMORROW'), findsOneWidget);
  });

  testWidgets('shows streak when greater than 0', (tester) async {
    final box = await _boxWithStreak(3);

    await tester.pumpWidget(
      overlayTestApp(child: DailyChallengeOverlay(game: FakeSandGame())),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('3-day streak'), findsOneWidget);
  });

  testWidgets('shows best score when non-zero', (tester) async {
    await DailyChallengeService.instance.recordAttempt(4200);

    await tester.pumpWidget(
      overlayTestApp(child: DailyChallengeOverlay(game: FakeSandGame())),
    );
    await tester.pumpAndSettle();

    expect(find.text('4200'), findsOneWidget);
  });

  testWidgets('shows BACK button', (tester) async {
    await tester.pumpWidget(
      overlayTestApp(child: DailyChallengeOverlay(game: FakeSandGame())),
    );
    await tester.pumpAndSettle();

    expect(find.text('BACK'), findsOneWidget);
  });
}

Future<void> _boxWithStreak(int streak) async {
  final box = Hive.box('dailyChallenge');
  final today = DailyChallengeService.todayNumber;
  await box.putAll({
    'lastDay': today - 1,
    'streak': streak - 1, // will increment to streak on load
    'attemptsUsed': 0,
    'bestScore': 0,
  });
}
