import 'package:flutter/material.dart';

class NotificationBadge {
  final int milestone;
  final Color unlockedColor;
  final int nextMilestoneScore;
  final Offset targetPosition;

  double elapsed;
  static const duration = 3.0;
  static const riseSpeed = 40.0;

  late final TextPainter _milestonePainter;
  late final TextPainter _unlockedPainter;
  late final TextPainter _nextPainter;

  NotificationBadge({
    required this.milestone,
    required this.unlockedColor,
    required this.nextMilestoneScore,
    required this.targetPosition,
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
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  Offset get currentPosition {
    return Offset(
      targetPosition.dx,
      targetPosition.dy - riseSpeed * elapsed,
    );
  }

  double get alpha {
    final progress = elapsed / duration;
    if (progress > 0.7) {
      return 1.0 - ((progress - 0.7) / 0.3);
    }
    return 1.0;
  }

  double get scale {
    if (elapsed < 0.15) {
      return 0.5 + (elapsed / 0.15) * 0.5;
    }
    return 1.0;
  }

  bool get isExpired => elapsed >= duration;

  void update(double dt) {
    elapsed += dt;
  }

  void draw(Canvas canvas) {
    if (alpha <= 0 || scale <= 0) return;

    final pos = currentPosition;
    final a = alpha;
    final s = scale;

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.scale(s);
    canvas.saveLayer(
      const Rect.fromLTWH(-140, -60, 280, 140),
      Paint()..color = Colors.white.withAlpha((255 * a).toInt()),
    );

    // Badge background
    final bgPaint = Paint()
      ..color = const Color(0xE61A1A2E);
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 260, height: 100),
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
    _milestonePainter.paint(
      canvas,
      Offset(-_milestonePainter.width / 2, -35),
    );

    // Color swatch
    final swatchPaint = Paint()..color = unlockedColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(-85, 8), width: 24 * s, height: 24 * s),
        const Radius.circular(4),
      ),
      swatchPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(-85, 8), width: 24 * s, height: 24 * s),
        const Radius.circular(4),
      ),
      Paint()
        ..color = const Color(0x80FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // "UNLOCKED" label
    _unlockedPainter.paint(
      canvas,
      Offset(-55, 0),
    );

    // Next milestone label
    _nextPainter.paint(
      canvas,
      Offset(-_nextPainter.width / 2, 30),
    );

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