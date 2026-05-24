import 'package:flutter/material.dart';

class NotificationBadge {
  static const double enterDuration = 0.45;
  static const double holdDuration = 6.0;
  static const double exitDuration = 0.45;
  static const double slideMargin = 24.0;
  static const double badgeWidth = 260.0;
  static const double badgeHeight = 100.0;

  final int milestone;
  final Color unlockedColor;
  final int nextMilestoneScore;
  final Offset targetPosition;
  final double screenWidth;

  double elapsed;

  late final TextPainter _milestonePainter;
  late final TextPainter _unlockedPainter;
  late final TextPainter _nextPainter;

  NotificationBadge({
    required this.milestone,
    required this.unlockedColor,
    required this.nextMilestoneScore,
    required this.targetPosition,
    required this.screenWidth,
  }) : elapsed = 0 {
    _milestonePainter = TextPainter(
      text: TextSpan(
        text: 'MILESTONE $milestone',
        style: const TextStyle(
          color: Color(0xFFFFD700),
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    _unlockedPainter = TextPainter(
      text: const TextSpan(
        text: 'UNLOCKED',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    _nextPainter = TextPainter(
      text: TextSpan(
        text: 'Next: ${_formatScore(nextMilestoneScore)} pts',
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  double get totalDuration => enterDuration + holdDuration + exitDuration;

  double get _enterEnd => enterDuration;

  double get _holdEnd => enterDuration + holdDuration;

  double get _offscreenRightX => screenWidth + (badgeWidth / 2) + slideMargin;

  double get _enterProgress => (elapsed / enterDuration).clamp(0.0, 1.0);

  double get _exitProgress {
    if (elapsed <= _holdEnd) {
      return 0;
    }
    return ((elapsed - _holdEnd) / exitDuration).clamp(0.0, 1.0);
  }

  Offset get currentPosition {
    if (elapsed < _enterEnd) {
      final t = Curves.easeOutCubic.transform(_enterProgress);
      return Offset(
        _offscreenRightX + (targetPosition.dx - _offscreenRightX) * t,
        targetPosition.dy,
      );
    }

    if (elapsed < _holdEnd) {
      return targetPosition;
    }

    final t = Curves.easeInCubic.transform(_exitProgress);
    return Offset(
      targetPosition.dx + (_offscreenRightX - targetPosition.dx) * t,
      targetPosition.dy,
    );
  }

  double get alpha {
    if (elapsed < _holdEnd) {
      return 1.0;
    }

    return 1.0 - Curves.easeIn.transform(_exitProgress);
  }

  double get scale => 1.0;

  bool get isExpired => elapsed >= totalDuration;

  void update(double dt) {
    elapsed += dt;
  }

  void draw(Canvas canvas) {
    if (alpha <= 0 || scale <= 0) return;

    final pos = currentPosition;
    final opacity = alpha.clamp(0.0, 1.0);

    canvas.save();
    canvas.translate(pos.dx, pos.dy);

    canvas.saveLayer(
      Rect.fromCenter(
        center: Offset.zero,
        width: badgeWidth + 60,
        height: badgeHeight + 40,
      ),
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );

    // Badge background
    final bgPaint = Paint()..color = const Color(0xE61A1A2E);
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: badgeWidth,
        height: badgeHeight,
      ),
      const Radius.circular(12),
    );
    canvas.drawRRect(bgRect, bgPaint);

    // Border
    final borderPaint = Paint()
      ..color = unlockedColor.withAlpha(204)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(bgRect, borderPaint);

    // Milestone text
    _milestonePainter.paint(canvas, Offset(-_milestonePainter.width / 2, -35));

    // Color swatch
    final swatchPaint = Paint()..color = unlockedColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(-85, 8), width: 24, height: 24),
        const Radius.circular(4),
      ),
      swatchPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(-85, 8), width: 24, height: 24),
        const Radius.circular(4),
      ),
      Paint()
        ..color = const Color(0x80FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // "UNLOCKED" label
    _unlockedPainter.paint(canvas, Offset(-55, 0));

    // Next milestone label
    _nextPainter.paint(canvas, Offset(-_nextPainter.width / 2, 30));

    canvas.restore();
    canvas.restore();
  }

  String _formatScore(int score) {
    if (score >= 1000) {
      return '${(score / 1000).toStringAsFixed(score % 1000 == 0 ? 0 : 1)}k';
    }
    return score.toString();
  }
}
