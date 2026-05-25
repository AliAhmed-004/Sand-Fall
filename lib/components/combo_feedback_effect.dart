import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'package:sandfall/config/floating_feedback_config.dart';

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
  final int comboTier;

  final double _rotationOffset;
  final double _driftDirection;
  final int _sparkCount;
  final List<_ComboSpark> _sparks;
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
    required this.comboTier,
    this.scoreFontWeight = FontWeight.w900,
    this.praiseFontWeight = FontWeight.w900,
    this.fontFamily = 'monospace',
    Random? random,
  })  : _rotationOffset = ((random ?? Random()).nextDouble() * 2 - 1) * maxRotationRadians,
        _driftDirection = ((random ?? Random()).nextDouble() * 2 - 1),
        _sparkCount = FloatingFeedbackConfig.comboFeedbackSparkBaseCount +
            ((comboTier - 1).clamp(0, 2) * FloatingFeedbackConfig.comboFeedbackSparkBonusPerTier),
        _sparks = [],
        super() {
    _buildSparks(random ?? Random());
  }

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

  double get _rotation {
    final settleProgress = (_elapsed / duration).clamp(0.0, 1.0);
    final bounceWave = sin(min(settleProgress / 0.22, 1.0) * pi);
    return _rotationOffset * (1.0 - (settleProgress * 0.35)) + bounceWave * 0.025;
  }

  double get _scaleBounce {
    final hitStop = FloatingFeedbackConfig.comboFeedbackHitStopDuration;
    if (_elapsed <= hitStop) {
      return 0.9;
    }

    final bounceProgress = ((_elapsed - hitStop) / FloatingFeedbackConfig.comboFeedbackBounceDuration)
        .clamp(0.0, 1.0);
    final bounceWave = sin(bounceProgress * pi);
    return 1.0 + FloatingFeedbackConfig.comboFeedbackBounceAmount * bounceWave;
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

  void _buildSparks(Random random) {
    for (int i = 0; i < _sparkCount; i++) {
      final angle = random.nextDouble() * pi * 2;
      final speed = FloatingFeedbackConfig.comboFeedbackSparkMinSpeed +
          random.nextDouble() * (FloatingFeedbackConfig.comboFeedbackSparkMaxSpeed - FloatingFeedbackConfig.comboFeedbackSparkMinSpeed);
      final colorChoice = i % 3 == 0
          ? FloatingFeedbackConfig.comboFeedbackSparkColorHigh
          : (i % 2 == 0
              ? FloatingFeedbackConfig.comboFeedbackSparkColorAlt
              : FloatingFeedbackConfig.comboFeedbackSparkColor);
      _sparks.add(
        _ComboSpark(
          offset: Offset(
            cos(angle) * FloatingFeedbackConfig.comboFeedbackSparkStartRadius,
            sin(angle) * FloatingFeedbackConfig.comboFeedbackSparkStartRadius,
          ),
          velocity: Offset(cos(angle) * speed, sin(angle) * speed * 0.8),
          color: colorChoice,
          seedRotation: random.nextDouble() * pi * 2,
        ),
      );
    }
  }

  @override
  void update(double dt) {
    _elapsed += dt;
    for (final spark in _sparks) {
      spark.update(dt);
    }
    _sparks.removeWhere((spark) => spark.isExpired);
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
    canvas.scale(_scaleBounce, _scaleBounce);
    canvas.translate(-pos.dx, -pos.dy);

    _renderSparks(canvas, pos, blockWidth, blockHeight);

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

  void _renderSparks(Canvas canvas, Offset center, double blockWidth, double blockHeight) {
    final centerOffset = Offset(center.dx, center.dy - blockHeight * 0.06);
    for (final spark in _sparks) {
      final sparkProgress = (spark.elapsed / FloatingFeedbackConfig.comboFeedbackSparkLifetime)
          .clamp(0.0, 1.0);
      final eased = Curves.easeOut.transform(sparkProgress);
      final local = spark.position;
      final drawPos = centerOffset + local;
      final opacity = (1.0 - eased).clamp(0.0, 1.0);
      final twinkle = 0.85 + 0.15 * sin((spark.elapsed * 18.0) + spark.seedRotation);
      final glowPaint = Paint()
        ..color = spark.color.withAlpha((255 * opacity * 0.35 * twinkle).round())
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      final corePaint = Paint()
        ..color = spark.color.withAlpha((255 * opacity * twinkle).round())
        ..style = PaintingStyle.fill;

      canvas.drawCircle(drawPos, FloatingFeedbackConfig.comboFeedbackSparkGlowSize * (1.0 - eased * 0.35) * twinkle, glowPaint);
      canvas.drawCircle(drawPos, FloatingFeedbackConfig.comboFeedbackSparkSize * (1.0 - eased * 0.2) * twinkle, corePaint);
    }
  }
}

class _ComboSpark {
  Offset offset;
  Offset velocity;
  final Color color;
  final double seedRotation;
  double elapsed = 0;

  _ComboSpark({
    required this.offset,
    required this.velocity,
    required this.color,
    required this.seedRotation,
  });

  bool get isExpired => elapsed >= FloatingFeedbackConfig.comboFeedbackSparkLifetime;

  Offset get position => offset;

  void update(double dt) {
    elapsed += dt;
    final drag = pow(FloatingFeedbackConfig.comboFeedbackSparkDrag, dt * 60.0).toDouble();
    velocity = Offset(
      velocity.dx * drag,
      velocity.dy * drag + FloatingFeedbackConfig.comboFeedbackSparkGravity * dt,
    );
    offset += velocity * dt;
  }
}
