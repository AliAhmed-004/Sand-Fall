import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../models/daily_challenge_state.dart';

class DailyChallengeService {
  DailyChallengeService._();
  static final instance = DailyChallengeService._();

  static const int maxAttempts = 3;
  static const int blockCount = 30;

  static const _boxName = 'dailyChallenge';
  static const _keyLastDay = 'lastDay';
  static const _keyStreak = 'streak';
  static const _keyAttempts = 'attemptsUsed';
  static const _keyBestScore = 'bestScore';

  late Box _box;

  Future<void> initialize() async {
    _box = await Hive.openBox(_boxName);
    debugPrint('[DailyChallengeService] Initialized.');
  }

  // ─── Date helpers ────────────────────────────────────────────────────────

  static int get todayNumber {
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(1970)).inDays;
  }

  static int get todaySeed => todayNumber * 1000003;

  List<int> generateBlockSequence(int colorCount) {
    final rng = Random(todaySeed);
    return List.generate(blockCount, (_) => rng.nextInt(colorCount));
  }

  // ─── State ───────────────────────────────────────────────────────────────

  Future<DailyChallengeState> loadState() async {
    final lastDay = _box.get(_keyLastDay, defaultValue: 0) as int;
    final today = todayNumber;

    int streak = _box.get(_keyStreak, defaultValue: 0) as int;
    int attempts = _box.get(_keyAttempts, defaultValue: 0) as int;
    int best = _box.get(_keyBestScore, defaultValue: 0) as int;

    if (lastDay != today) {
      attempts = 0;
      best = 0;

      if (lastDay == 0) {
        streak = 1; // first time ever
      } else if (lastDay == today - 1) {
        streak++; // consecutive day
      } else {
        streak = 1; // missed one or more days
      }

      await _box.putAll({
        _keyLastDay: today,
        _keyStreak: streak,
        _keyAttempts: attempts,
        _keyBestScore: best,
      });
    }

    return DailyChallengeState(
      dayNumber: today,
      streak: streak,
      attemptsUsed: attempts,
      bestScore: best,
      completedToday: attempts >= maxAttempts,
    );
  }

  Future<DailyChallengeState> recordAttempt(int score) async {
    final state = await loadState();
    final newAttempts = (state.attemptsUsed + 1).clamp(0, maxAttempts);
    final newBest = max(state.bestScore, score);

    await _box.putAll({_keyAttempts: newAttempts, _keyBestScore: newBest});

    return DailyChallengeState(
      dayNumber: state.dayNumber,
      streak: state.streak,
      attemptsUsed: newAttempts,
      bestScore: newBest,
      completedToday: newAttempts >= maxAttempts,
    );
  }
}
