import 'package:flutter/material.dart';
import 'package:sandfall/game.dart';
import 'package:sandfall/theme/theme.dart';

/// Wraps a widget in MaterialApp with Sand Fall's theme for widget tests
Widget overlayTestApp({required Widget child}) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(body: child),
  );
}

/// A minimal SandGame stand-in for widget tests.
/// Overrides only what the overlays actually call.
class FakeSandGame extends SandGame {
  final List<String> addedOverlays = [];
  final List<String> removedOverlays = [];

  @override
  int get dailyFinalScore => 4200;

  @override
  bool get isDailyChallengeMode => true;

  @override
  void startDailyChallenge() {}
}
