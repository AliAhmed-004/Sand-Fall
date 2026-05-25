import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sandfall/config/floating_feedback_config.dart';

class ComboPraiseSelection {
  final int tier;
  final String text;
  final Color color;

  const ComboPraiseSelection({
    required this.tier,
    required this.text,
    required this.color,
  });
}

class ComboPraiseHelper {
  ComboPraiseHelper._();

  static final Random _random = Random();

  static ComboPraiseSelection selectPraise(int comboCount) {
    final tier = FloatingFeedbackConfig.normalizeComboTier(comboCount);
    final texts = FloatingFeedbackConfig.comboPraiseTexts[tier] ?? const ['NICE'];
    final text = texts[_random.nextInt(texts.length)];
    final color = FloatingFeedbackConfig.comboPraiseColors[tier] ?? Colors.white;

    return ComboPraiseSelection(tier: tier, text: text, color: color);
  }
}
