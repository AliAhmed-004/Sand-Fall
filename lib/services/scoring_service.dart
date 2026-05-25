import 'dart:math';
import 'package:flutter/foundation.dart';

/// A service to manage the scoring system of the game.
///
/// Scoring breakdown:
/// - Block placement: base_points (10 points)
/// - Pile clearing: base_points * sqrt(pileSize)
/// - Combo multiplier: +10% for each additional pile cleared in one move (1.1x, 1.2x, 1.3x, etc.)
class ScoringService {
  // Base points awarded for placing a block or clearing a pile of sand
  final int _basePoints = 25;

  // Total score notifier
  final ValueNotifier<int> _scoreNotifier = ValueNotifier<int>(0);

  // Combo tracking for pile clears
  int _currentComboCount = 0;
  bool _isInComboSession = false;
  int _lastClearPoints = 0;

  int get currentScore => _scoreNotifier.value;
  ValueNotifier<int> get scoreNotifier => _scoreNotifier;
  int get blockPlacementPoints => _basePoints;
  int get lastClearPoints => _lastClearPoints;
  int get currentComboCount => _currentComboCount;

  // Singleton pattern
  static final ScoringService _instance = ScoringService._internal();

  factory ScoringService() {
    return _instance;
  }

  ScoringService._internal();

  static ScoringService get instance => _instance;

  /// Method to add points for placing a block
  void addBlockPlacementPoints() {
    _scoreNotifier.value += _basePoints;
  }

  /// Starts a new clear session. Call this when checking for pile clears.
  void startClearSession() {
    if (!_isInComboSession) {
      _currentComboCount = 0;
      _isInComboSession = true;
    }
  }

  /// Method to add points for clearing a pile of sand.
  /// Uses sqrt(pileSize) for multiplier and applies combo bonus.
  void addSandClearPoints(int pilesCleared, int pileSize) {
    // Use square root of pile size as multiplier for more balanced scoring
    double multiplier = pileSize > 0 ? sqrt(pileSize.toDouble()) : 1.0;

    // Combo bonus: 1.0x for first pile, 1.1x for second, 1.2x for third, etc.
    double comboBonus = 1.0 + (_currentComboCount * 0.1);

    int points = (_basePoints * multiplier * comboBonus).toInt();
    _scoreNotifier.value += points;
    _lastClearPoints = points;

    _currentComboCount++;
  }

  /// Ends the clear session if no bridges were found.
  /// Returns true if combo ended, false if combo is still active.
  bool endClearSessionIfNoBridges(bool anyBridgesCleared) {
    if (!anyBridgesCleared) {
      _isInComboSession = false;
      return true; // Combo ended
    }
    return false; // Combo continues
  }

  /// Method to reset the score, typically called when starting a new game
  void resetScore() {
    _scoreNotifier.value = 0;
    _currentComboCount = 0;
    _isInComboSession = false;
    _lastClearPoints = 0;
  }

  /// Method to set the score, typically called when loading a saved game
  void setScore(int score) {
    _scoreNotifier.value = score;
    _currentComboCount = 0;
    _isInComboSession = false;
    _lastClearPoints = 0;
  }
}
