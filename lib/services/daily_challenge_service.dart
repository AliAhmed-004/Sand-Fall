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

  // ─── Date helpers ─────────────────────────────────────────────────────────

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

  // ─── State ────────────────────────────────────────────────────────────────

  /// Reads the current challenge state.
  ///
  /// On a new day, resets attempts and best score so the player gets a fresh
  /// challenge — but does NOT increment the streak. The streak only moves in
  /// [recordAttempt], when the player actually plays.
  Future<DailyChallengeState> loadState() async {
    final lastDay = _box.get(_keyLastDay, defaultValue: 0) as int;
    final today = todayNumber;
    final streak = _box.get(_keyStreak, defaultValue: 0) as int;
    int attempts = _box.get(_keyAttempts, defaultValue: 0) as int;
    int best = _box.get(_keyBestScore, defaultValue: 0) as int;

    if (lastDay != today) {
      // New day — wipe today's progress so the challenge resets.
      // Do NOT write lastDay or touch streak here; that happens in
      // recordAttempt() so the streak only counts actual play.
      attempts = 0;
      best = 0;
      await _box.putAll({_keyAttempts: attempts, _keyBestScore: best});
    }

    return DailyChallengeState(
      dayNumber: today,
      streak: streak,
      attemptsUsed: attempts,
      bestScore: best,
      completedToday: attempts >= maxAttempts,
    );
  }

  /// Records a completed attempt (play-through or abandon) and updates the
  /// streak. This is the only place that writes [_keyLastDay] and [_keyStreak].
  Future<DailyChallengeState> recordAttempt(int score) async {
    final lastDay = _box.get(_keyLastDay, defaultValue: 0) as int;
    final today = todayNumber;

    int streak = _box.get(_keyStreak, defaultValue: 0) as int;
    int attempts = _box.get(_keyAttempts, defaultValue: 0) as int;
    int best = _box.get(_keyBestScore, defaultValue: 0) as int;

    // Only update the streak on the very first attempt of a new day.
    if (lastDay != today) {
      if (lastDay == 0) {
        streak = 1; // first time ever playing
      } else if (lastDay == today - 1) {
        streak++; // played yesterday — keep the streak going
      } else {
        streak = 1; // missed one or more days — streak broken
      }
    }
    // If lastDay == today the streak doesn't change (already counted today).

    final newAttempts = (attempts + 1).clamp(0, maxAttempts);
    final newBest = max(best, score);

    await _box.putAll({
      _keyLastDay: today, // mark that the player has played today
      _keyStreak: streak,
      _keyAttempts: newAttempts,
      _keyBestScore: newBest,
    });

    return DailyChallengeState(
      dayNumber: today,
      streak: streak,
      attemptsUsed: newAttempts,
      bestScore: newBest,
      completedToday: newAttempts >= maxAttempts,
    );
  }
}
