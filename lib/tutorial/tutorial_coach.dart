import 'package:flutter/material.dart';

enum TutorialCoachPhase {
  idle,
  intro,
  bridgeCleared,
  milestoneReminder,
  gameOverReminder,
  complete,
}

class TutorialCoachController extends ChangeNotifier {
  static const Duration _bridgeClearedDuration = Duration(milliseconds: 5000);
  static const Duration _milestoneReminderDuration = Duration(milliseconds: 5000);
  static const Duration _gameOverReminderDuration = Duration(milliseconds: 5000);

  TutorialCoachPhase _phase = TutorialCoachPhase.idle;
  double _phaseElapsed = 0;
  Color? _forcedColor;

  TutorialCoachPhase get phase => _phase;
  bool get isActive =>
      _phase != TutorialCoachPhase.idle && _phase != TutorialCoachPhase.complete;
  bool get isComplete => _phase == TutorialCoachPhase.complete;
  Color? get forcedColor => _forcedColor;

  String get title {
    switch (_phase) {
      case TutorialCoachPhase.idle:
      case TutorialCoachPhase.complete:
        return '';
      case TutorialCoachPhase.intro:
        return 'PLAY TUTORIAL';
      case TutorialCoachPhase.bridgeCleared:
        return 'NICE';
      case TutorialCoachPhase.milestoneReminder:
        return 'KEEP GOING';
      case TutorialCoachPhase.gameOverReminder:
        return 'WATCH THE TOP';
    }
  }

  String get message {
    switch (_phase) {
      case TutorialCoachPhase.idle:
      case TutorialCoachPhase.complete:
        return '';
      case TutorialCoachPhase.intro:
        return 'Tap to place blocks. Keep building with the same color until you connect both walls.';
      case TutorialCoachPhase.bridgeCleared:
        return 'Clearing a bridge awards bonus points.';
      case TutorialCoachPhase.milestoneReminder:
        return 'Reach the next milestone for new colors and more difficulty.';
      case TutorialCoachPhase.gameOverReminder:
        return 'If the pile reaches the top threshold, the game ends.';
    }
  }

  void start({Color? forcedColor}) {
    _phase = TutorialCoachPhase.intro;
    _phaseElapsed = 0;
    _forcedColor = forcedColor;
    notifyListeners();
  }

  void reset() {
    _phase = TutorialCoachPhase.idle;
    _phaseElapsed = 0;
    _forcedColor = null;
    notifyListeners();
  }

  void markBridgeCleared() {
    if (_phase != TutorialCoachPhase.intro) {
      return;
    }

    _phase = TutorialCoachPhase.bridgeCleared;
    _phaseElapsed = 0;
    _forcedColor = null;
    notifyListeners();
  }

  void update(double dt) {
    if (!isActive) {
      return;
    }

    _phaseElapsed += dt;

    if (_phase == TutorialCoachPhase.bridgeCleared &&
        _phaseElapsed >= _bridgeClearedDuration.inMicroseconds / 1000000.0) {
      _phase = TutorialCoachPhase.milestoneReminder;
      _phaseElapsed = 0;
      notifyListeners();
      return;
    }

    if (_phase == TutorialCoachPhase.milestoneReminder &&
        _phaseElapsed >= _milestoneReminderDuration.inMicroseconds / 1000000.0) {
      _phase = TutorialCoachPhase.gameOverReminder;
      _phaseElapsed = 0;
      notifyListeners();
      return;
    }

    if (_phase == TutorialCoachPhase.gameOverReminder &&
        _phaseElapsed >= _gameOverReminderDuration.inMicroseconds / 1000000.0) {
      _phase = TutorialCoachPhase.complete;
      _phaseElapsed = 0;
      notifyListeners();
    }
  }
}