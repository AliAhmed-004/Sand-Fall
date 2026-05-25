import 'package:flutter/material.dart';

class FloatingFeedbackConfig {
  FloatingFeedbackConfig._();

  static const double comboPraiseYOffset = 28.0;
  static const double comboPraiseFontSize = 30.0;
  static const double comboPraiseDuration = 1.15;
  static const double comboPraiseRiseSpeed = 22.0;
  static const double comboPraiseFadeStart = 0.55;
  static const double comboPraiseScalePopDuration = 0.12;
  static const double comboPraiseScalePopAmount = 0.24;
  static const double comboPraiseMaxRotationRadians = 0.08;
  static const double comboPraiseHorizontalDrift = 10.0;
  static const double comboFeedbackLineGap = 6.0;
  static const double comboFeedbackScoreFontSize = 24.0;
  static const double comboFeedbackPraiseFontSize = 30.0;
  static const double comboFeedbackScoreLetterSpacing = 0.4;
  static const double comboFeedbackPraiseLetterSpacing = 1.6;
  static const double comboFeedbackHitStopDuration = 0.055;
  static const double comboFeedbackBounceDuration = 0.22;
  static const double comboFeedbackBounceAmount = 0.28;
  static const double comboFeedbackSparkStartRadius = 16.0;
  static const double comboFeedbackSparkMinSpeed = 65.0;
  static const double comboFeedbackSparkMaxSpeed = 145.0;
  static const double comboFeedbackSparkGravity = 55.0;
  static const double comboFeedbackSparkDrag = 0.92;
  static const double comboFeedbackSparkSize = 2.4;
  static const double comboFeedbackSparkGlowSize = 6.5;
  static const double comboFeedbackSparkLifetime = 0.48;
  static const int comboFeedbackSparkBaseCount = 7;
  static const int comboFeedbackSparkBonusPerTier = 3;
  static const double comboPraiseShadowBlurRadius = 8.0;
  static const double comboPraiseShadowOpacity = 0.45;

  static const Map<int, List<String>> comboPraiseTexts = {
    1: ['NICE', 'GOOD', 'CLEAN', 'SMOOTH'],
    2: ['AWESOME', 'WILD', 'CHAIN', 'HOT STREAK'],
    3: ['INSANE', 'UNSTOPPABLE', 'SANDSTORM', 'MONSTER COMBO'],
  };

  static const Map<int, Color> comboPraiseColors = {
    1: Color(0xFFFFC107),
    2: Color(0xFFFF7043),
    3: Color(0xFF00E5FF),
  };

  static const Color comboFeedbackScoreColor = Colors.amber;
  static const Color comboFeedbackSparkColor = Color(0xFFFFD54F);
  static const Color comboFeedbackSparkColorAlt = Color(0xFFFF8A65);
  static const Color comboFeedbackSparkColorHigh = Color(0xFF8EECFF);

  static int normalizeComboTier(int comboCount) {
    if (comboCount <= 1) {
      return 1;
    }

    if (comboCount == 2) {
      return 2;
    }

    return 3;
  }
}
