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
  static const _keyHighestStreak = 'highestStreak';
  static const _keyAttempts = 'attemptsUsed';
  static const _keyBestScore = 'bestScore';
  static const _keyBestCombo = 'bestCombo';
  static const _keyBestBlocks = 'bestBlocksRemaining';
  static const _keyChallengeCompleted = 'challengeCompleted';

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

  /// Today's target combo length — seeded from the date so it's the same
  /// for every player. Range: 4–8 combos.
  static int getDailyComboTarget() {
    final rng = Random(
      todaySeed + 7,
    ); // offset seed so it differs from sequence
    return 4 + rng.nextInt(5); // 4, 5, 6, 7, or 8
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
    final highestStreak = _box.get(_keyHighestStreak, defaultValue: 0) as int;
    int attempts = _box.get(_keyAttempts, defaultValue: 0) as int;
    int best = _box.get(_keyBestScore, defaultValue: 0) as int;
    int bestCombo = _box.get(_keyBestCombo, defaultValue: 0) as int;
    int bestBlocks = _box.get(_keyBestBlocks, defaultValue: 0) as int;
    bool completed =
        _box.get(_keyChallengeCompleted, defaultValue: false) as bool;

    if (lastDay != today) {
      attempts = 0;
      best = 0;
      bestCombo = 0;
      bestBlocks = 0;
      completed = false;
      await _box.putAll({
        _keyAttempts: attempts,
        _keyBestScore: best,
        _keyBestCombo: bestCombo,
        _keyBestBlocks: bestBlocks,
        _keyChallengeCompleted: completed,
      });
    }

    return DailyChallengeState(
      dayNumber: today,
      streak: streak,
      highestStreak: highestStreak,
      attemptsUsed: attempts,
      bestScore: best,
      completedToday: attempts >= maxAttempts,
      comboTarget: getDailyComboTarget(),
      bestCombo: bestCombo,
      bestBlocksRemaining: bestBlocks,
      challengeCompleted: completed,
    );
  }

  /// Records a completed attempt and updates the streak.
  /// [longestCombo] — peak combo reached this attempt.
  /// [blocksRemaining] — blocks left when target was hit (0 if never hit).
  Future<DailyChallengeState> recordAttempt([
    int? legacyScore,
    int longestCombo = 0,
    int blocksRemaining = 0,
  ]) async {
    final lastDay = _box.get(_keyLastDay, defaultValue: 0) as int;
    final today = todayNumber;

    int streak = _box.get(_keyStreak, defaultValue: 0) as int;
    int highestStreak = _box.get(_keyHighestStreak, defaultValue: 0) as int;
    int attempts = _box.get(_keyAttempts, defaultValue: 0) as int;
    int best = _box.get(_keyBestScore, defaultValue: 0) as int;
    int bestCombo = _box.get(_keyBestCombo, defaultValue: 0) as int;
    int bestBlocks = _box.get(_keyBestBlocks, defaultValue: 0) as int;
    bool completed =
        _box.get(_keyChallengeCompleted, defaultValue: false) as bool;

    // Streak — only update on first attempt of a new day
    if (lastDay != today) {
      if (lastDay == 0) {
        streak = 1;
      } else if (lastDay == today - 1) {
        streak++;
      } else {
        streak = 1;
      }
    }

    final attemptScore = legacyScore ?? 0;
    final newAttempts = (attempts + 1).clamp(0, maxAttempts);
    final newBest = max(best, attemptScore);
    final newBestCombo = max(bestCombo, longestCombo);
    highestStreak = max(highestStreak, streak);

    // Best blocks remaining: higher is better (more blocks left = more efficient)
    // Only update if the target was actually hit this attempt
    final target = getDailyComboTarget();
    final hitTarget = longestCombo >= target;
    final newCompleted = completed || hitTarget;
    final newBestBlocks = hitTarget
        ? max(bestBlocks, blocksRemaining)
        : bestBlocks;

    await _box.putAll({
      _keyLastDay: today,
      _keyStreak: streak,
      _keyHighestStreak: highestStreak,
      _keyAttempts: newAttempts,
      _keyBestScore: newBest,
      _keyBestCombo: newBestCombo,
      _keyBestBlocks: newBestBlocks,
      _keyChallengeCompleted: newCompleted,
    });

    return DailyChallengeState(
      dayNumber: today,
      streak: streak,
      highestStreak: highestStreak,
      attemptsUsed: newAttempts,
      bestScore: newBest,
      completedToday: newAttempts >= maxAttempts,
      comboTarget: target,
      bestCombo: newBestCombo,
      bestBlocksRemaining: newBestBlocks,
      challengeCompleted: newCompleted,
    );
  }
}
