import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class FloatingTextEffect extends Component {
  final String text;
  final Offset startPosition;
  final Color color;
  final double fontSize;
  final double duration;
  final double riseSpeed;
  final double fadeStart;
  final double scalePopDuration;
  final double scalePopAmount;
  final double maxRotationRadians;
  final double horizontalDrift;
  final double shadowBlurRadius;
  final double shadowOpacity;
  final double letterSpacing;
  final FontWeight fontWeight;
  final String fontFamily;

  final double _rotationOffset;
  final double _driftDirection;
  double _elapsed = 0;

  FloatingTextEffect({
    required this.text,
    required this.startPosition,
    required this.color,
    required this.fontSize,
    required this.duration,
    required this.riseSpeed,
    required this.fadeStart,
    required this.scalePopDuration,
    required this.scalePopAmount,
    required this.maxRotationRadians,
    required this.horizontalDrift,
    required this.shadowBlurRadius,
    required this.shadowOpacity,
    required this.letterSpacing,
    this.fontWeight = FontWeight.w900,
    this.fontFamily = 'monospace',
    Random? random,
  })  : _rotationOffset = ((random ?? Random()).nextDouble() * 2 - 1) * maxRotationRadians,
        _driftDirection = ((random ?? Random()).nextDouble() * 2 - 1),
        super();

  bool get isExpired => _elapsed >= duration;

  Offset get currentPosition {
    final progress = (_elapsed / duration).clamp(0.0, 1.0);
    final drift = horizontalDrift * _driftDirection * progress;
    return Offset(startPosition.dx + drift, startPosition.dy - riseSpeed * _elapsed);
  }

  double get _fadeProgress {
    final progress = (_elapsed / duration).clamp(0.0, 1.0);
    if (progress <= fadeStart) {
      return 1.0;
    }

    final fadeWindow = (1.0 - fadeStart).clamp(0.0001, 1.0);
    return 1.0 - ((progress - fadeStart) / fadeWindow).clamp(0.0, 1.0);
  }

  double get _scale {
    final popProgress = (_elapsed / scalePopDuration).clamp(0.0, 1.0);
    final scalePop = 1.0 + scalePopAmount * (1.0 - popProgress);
    return _elapsed < scalePopDuration ? scalePop : 1.0;
  }

  double get _rotation {
    final settleProgress = (_elapsed / duration).clamp(0.0, 1.0);
    return _rotationOffset * (1.0 - (settleProgress * 0.35));
  }

  TextPainter _buildPainter(double opacity) {
    final alpha = (255 * opacity.clamp(0.0, 1.0)).round();
    final textColor = color.withAlpha(alpha);
    final shadowAlpha = (alpha * shadowOpacity).round();
    final glowColor = color.withAlpha((alpha * (shadowOpacity * 0.75)).round());

    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
          fontFamily: fontFamily,
          shadows: [
            Shadow(
              color: Colors.black.withAlpha(shadowAlpha),
              blurRadius: shadowBlurRadius,
              offset: const Offset(1.5, 2),
            ),
            Shadow(
              color: glowColor,
              blurRadius: shadowBlurRadius * 1.25,
              offset: Offset.zero,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void update(double dt) {
    _elapsed += dt;
  }

  @override
  void render(Canvas canvas) {
    final painter = _buildPainter(_fadeProgress);
    final pos = currentPosition;

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(_rotation);
    canvas.scale(_scale, _scale);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }
}
