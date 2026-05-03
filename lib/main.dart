import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sandfall/config/game_config.dart';
import 'package:sandfall/game.dart';
import 'package:sandfall/services/high_score_service.dart';
import 'package:sandfall/services/save_game_service.dart';
import 'package:sandfall/theme/theme.dart';
import 'package:sandfall/ui/celebration_overlay.dart';
import 'package:sandfall/ui/game_over_overlay.dart';
import 'package:sandfall/ui/hud_overlay.dart';
import 'package:sandfall/ui/main_menu_overlay.dart';
import 'package:sandfall/ui/pause_overlay.dart';
import 'package:sandfall/ui/tutorial_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await HighScoreService.instance.initialize();
  await SaveGameService.instance.initialize();

  Flame.device.fullScreen();

  runApp(const SandCrush());
}

class SandCrush extends StatelessWidget {
  const SandCrush({super.key});

  @override
  Widget build(BuildContext context) {
    final game = SandGame();

    return MaterialApp(
      title: 'SandFall',
      theme: theme,
      home: GameWidget.controlled(
        gameFactory: () => game,
        overlayBuilderMap: {
          GameConfig.mainMenuOverlay: (context, game) =>
              MainMenuOverlay(game: game as SandGame),
          GameConfig.hudOverlay: (context, game) =>
              HudOverlay(game: game as SandGame),
          GameConfig.pauseOverlay: (context, game) =>
              PauseOverlay(game: game as SandGame),
            GameConfig.tutorialOverlay: (context, game) =>
              TutorialOverlay(game: game as SandGame),
          GameConfig.celebrationOverlay: (context, game) =>
              CelebrationOverlay(game: game as SandGame),
          GameConfig.gameOverOverlay: (context, game) =>
              GameOverOverlay(game: game as SandGame),
        },
        initialActiveOverlays: [GameConfig.mainMenuOverlay],
      ),
    );
  }
}
