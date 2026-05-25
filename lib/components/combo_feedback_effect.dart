import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class ComboFeedbackEffect extends Component {
  final String scoreText;
  final String praiseText;
  final Color scoreColor;
  final Color praiseColor;
  final Offset centerPosition;
  final double duration;
  final double riseSpeed;
  final double fadeStart;
  final double scalePopDuration;
  final double scalePopAmount;
  final double maxRotationRadians;
  final double horizontalDrift;
  final double scoreFontSize;
  final double praiseFontSize;
  final double lineGap;
  final double shadowBlurRadius;
  final double shadowOpacity;
  final double praiseLetterSpacing;
  final double scoreLetterSpacing;
  final FontWeight scoreFontWeight;
  final FontWeight praiseFontWeight;
  final String fontFamily;

  final double _rotationOffset;
  final double _driftDirection;
  double _elapsed = 0;

  ComboFeedbackEffect({
    required this.scoreText,
    required this.praiseText,
    required this.scoreColor,
    required this.praiseColor,
    required this.centerPosition,
    required this.duration,
    required this.riseSpeed,
    required this.fadeStart,
    required this.scalePopDuration,
    required this.scalePopAmount,
    required this.maxRotationRadians,
    required this.horizontalDrift,
    required this.scoreFontSize,
    required this.praiseFontSize,
    required this.lineGap,
    required this.shadowBlurRadius,
    required this.shadowOpacity,
    required this.praiseLetterSpacing,
    required this.scoreLetterSpacing,
    this.scoreFontWeight = FontWeight.w900,
    this.praiseFontWeight = FontWeight.w900,
    this.fontFamily = 'monospace',
    Random? random,
  })  : _rotationOffset = ((random ?? Random()).nextDouble() * 2 - 1) * maxRotationRadians,
        _driftDirection = ((random ?? Random()).nextDouble() * 2 - 1),
        super();

  bool get isExpired => _elapsed >= duration;

  Offset get _position {
    final progress = (_elapsed / duration).clamp(0.0, 1.0);
    final drift = horizontalDrift * _driftDirection * progress;
    return Offset(centerPosition.dx + drift, centerPosition.dy - riseSpeed * _elapsed);
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

  TextPainter _buildPainter({
    required String text,
    required Color color,
    required double fontSize,
    required FontWeight fontWeight,
    required double letterSpacing,
  }) {
    final alpha = (255 * _fadeProgress.clamp(0.0, 1.0)).round();
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
    final scorePainter = _buildPainter(
      text: scoreText,
      color: scoreColor,
      fontSize: scoreFontSize,
      fontWeight: scoreFontWeight,
      letterSpacing: scoreLetterSpacing,
    );
    final praisePainter = _buildPainter(
      text: praiseText,
      color: praiseColor,
      fontSize: praiseFontSize,
      fontWeight: praiseFontWeight,
      letterSpacing: praiseLetterSpacing,
    );

    final blockWidth = max(scorePainter.width, praisePainter.width);
    final blockHeight = praisePainter.height + lineGap + scorePainter.height;
    final pos = _position;
    final topLeft = Offset(pos.dx - blockWidth / 2, pos.dy - blockHeight / 2);

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(_rotation);
    canvas.scale(_scale, _scale);
    canvas.translate(-pos.dx, -pos.dy);

    final praiseOffset = Offset(
      topLeft.dx + (blockWidth - praisePainter.width) / 2,
      topLeft.dy,
    );
    final scoreOffset = Offset(
      topLeft.dx + (blockWidth - scorePainter.width) / 2,
      topLeft.dy + praisePainter.height + lineGap,
    );

    praisePainter.paint(canvas, praiseOffset);
    scorePainter.paint(canvas, scoreOffset);

    canvas.restore();
  }
}
