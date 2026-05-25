import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandfall/tutorial/tutorial_coach.dart';

void main() {
  group('TutorialCoachController', () {
    test('starts in intro with a forced tutorial color', () {
      final coach = TutorialCoachController();
      const forcedColor = Color(0xFF336699);

      coach.start(forcedColor: forcedColor);

      expect(coach.phase, TutorialCoachPhase.intro);
      expect(coach.isActive, isTrue);
      expect(coach.forcedColor, forcedColor);
      expect(coach.title, isNotEmpty);
      expect(coach.message, contains('Tap to place blocks'));
    });

    test('bridge clear advances through reminder and completion phases', () {
      final coach = TutorialCoachController();
      coach.start(forcedColor: const Color(0xFF123456));

      coach.markBridgeCleared();

      expect(coach.phase, TutorialCoachPhase.bridgeCleared);
      expect(coach.forcedColor, isNull);
      expect(coach.message, 'Clearing a bridge awards bonus points.');

      coach.update(4.5);
      expect(coach.phase, TutorialCoachPhase.milestoneReminder);
      expect(coach.message, 'Reach the next milestone for new colors and more difficulty.');
      coach.update(5.5);
      expect(coach.phase, TutorialCoachPhase.gameOverReminder);
      expect(coach.message, 'If the pile reaches the top threshold, the game ends.');
      coach.update(5.5);
      expect(coach.phase, TutorialCoachPhase.complete);
      expect(coach.isActive, isFalse);
      expect(coach.message, isEmpty);
    });

    test('reset returns the coach to idle', () {
      final coach = TutorialCoachController();
      coach.start();

      coach.reset();

      expect(coach.phase, TutorialCoachPhase.idle);
      expect(coach.isActive, isFalse);
      expect(coach.forcedColor, isNull);
      expect(coach.title, isEmpty);
    });
  });
}
