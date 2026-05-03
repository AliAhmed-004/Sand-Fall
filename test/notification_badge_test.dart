import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandfall/models/notification_badge.dart';

void main() {
  test('NotificationBadge slides in, holds, and exits to the right', () {
    const screenWidth = 600.0;
    const target = Offset(300, 120);

    final badge = NotificationBadge(
      milestone: 3,
      unlockedColor: const Color(0xFF33CC66),
      nextMilestoneScore: 2500,
      targetPosition: target,
      screenWidth: screenWidth,
    );

    expect(badge.currentPosition.dx, greaterThan(target.dx));
    expect(badge.alpha, closeTo(1.0, 0.01));

    badge.update(NotificationBadge.enterDuration / 2);
    expect(badge.currentPosition.dx, greaterThan(target.dx));
    expect(badge.currentPosition.dx, lessThan(screenWidth + 1));
    expect(badge.alpha, closeTo(1.0, 0.01));

    badge.update(
      NotificationBadge.enterDuration / 2 + NotificationBadge.holdDuration / 2,
    );
    expect(badge.currentPosition.dx, closeTo(target.dx, 0.01));
    expect(badge.currentPosition.dy, closeTo(target.dy, 0.01));
    expect(badge.alpha, closeTo(1.0, 0.01));

    badge.update(
      NotificationBadge.holdDuration / 2 + NotificationBadge.exitDuration / 2,
    );
    expect(badge.currentPosition.dx, greaterThan(target.dx));
    expect(badge.isExpired, isFalse);

    badge.update(
      NotificationBadge.holdDuration / 2 + NotificationBadge.exitDuration / 2,
    );
    expect(badge.isExpired, isTrue);
    expect(badge.currentPosition.dx, greaterThan(target.dx));
  });
}
