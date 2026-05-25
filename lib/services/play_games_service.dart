import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:games_services/games_services.dart';
import 'package:sandfall/config/game_config.dart';

class PlayGamesService extends ChangeNotifier {
  static final PlayGamesService _instance = PlayGamesService._internal();

  factory PlayGamesService() {
    return _instance;
  }

  PlayGamesService._internal();

  static PlayGamesService get instance => _instance;

  bool _isSupportedPlatform = false;
  bool _isSignedIn = false;
  bool _isInitialized = false;
  bool _autoSignInDisabled = false;
  late Box _prefsBox;

  bool get isSupportedPlatform => _isSupportedPlatform;
  bool get isSignedIn => _isSignedIn;
  bool get autoSignInDisabled => _autoSignInDisabled;
  String get leaderboardsLabel =>
      _isSignedIn ? 'LEADERBOARDS' : 'SIGN IN TO JOIN GLOBAL LEADERBOARDS';
  bool get isConfigured =>
      GameConfig.playGamesAndroidLeaderboardId.isNotEmpty ||
      GameConfig.playGamesIOSLeaderboardId.isNotEmpty;

  Future<void> initialize() async {
    if (_isInitialized) {
      print('[PlayGames] Already initialized, skipping.');
      return;
    }

    _prefsBox = await Hive.openBox(GameConfig.playGamesPrefsBox);
    _autoSignInDisabled =
        _prefsBox.get(
              GameConfig.playGamesAutoSignInDisabledKey,
              defaultValue: false,
            )
            as bool;

    _isSupportedPlatform = _supportsPlayGames();
    _isInitialized = true;
    print('[PlayGames] Initializing... (supported: $_isSupportedPlatform)');

    if (!_isSupportedPlatform) {
      print('[PlayGames] Platform not supported, skipping auth.');
      notifyListeners();
      return;
    }

    await _refreshAuthState();
    print('[PlayGames] Auth state refreshed: signed in = $_isSignedIn');

    if (_isSignedIn) {
      await _setAutoSignInDisabled(false);
      notifyListeners();
      return;
    }

    if (!_autoSignInDisabled) {
      print('[PlayGames] Not signed in, attempting automatic sign-in...');
      await _attemptSignIn(rememberDismissal: true);
    }

    notifyListeners();
  }

  Future<void> submitScore(int score) async {
    print('[PlayGames] Attempting to submit score: $score');
    if (!await _ensureReadyForAction(promptForSignIn: false)) {
      print('[PlayGames] Not ready for score submission (not signed in).');
      return;
    }

    final leaderboard = _buildScore(score);
    if (leaderboard == null) {
      print('[PlayGames] No leaderboard ID configured, skipping submission.');
      return;
    }

    try {
      print('[PlayGames] Submitting score to leaderboard...');
      await Leaderboards.submitScore(score: leaderboard);
      print('[PlayGames] Score submitted successfully.');
    } catch (e) {
      print('[PlayGames] Error submitting score: $e');
      _isSignedIn = false;
    }
  }

  Future<bool> showLeaderboards() async {
    print('[PlayGames] Attempting to show leaderboards...');
    if (!await _ensureReadyForAction(promptForSignIn: true)) {
      print('[PlayGames] Not ready to show leaderboards (not signed in).');
      return false;
    }

    try {
      print('[PlayGames] Opening leaderboards UI...');
      await Leaderboards.showLeaderboards(
        androidLeaderboardID: GameConfig.playGamesAndroidLeaderboardId,
        iOSLeaderboardID: GameConfig.playGamesIOSLeaderboardId,
      );
      print('[PlayGames] Leaderboards UI closed.');
      return true;
    } catch (e) {
      print('[PlayGames] Error showing leaderboards: $e');
      _isSignedIn = false;
      return false;
    }
  }

  Future<bool> _ensureReadyForAction({required bool promptForSignIn}) async {
    print(
      '[PlayGames] Ensuring ready for action (promptForSignIn: $promptForSignIn)...',
    );
    if (!_supportsPlayGames()) {
      print('[PlayGames] Platform not supported.');
      return false;
    }

    if (!_isInitialized) {
      print('[PlayGames] Not yet initialized, initializing now...');
      await initialize();
    }

    if (_isSignedIn) {
      print('[PlayGames] Already signed in.');
      return true;
    }

    print('[PlayGames] Refreshing auth state...');
    await _refreshAuthState();
    if (_isSignedIn) {
      print('[PlayGames] Now signed in after refresh.');
      return true;
    }

    if (!promptForSignIn) {
      print('[PlayGames] Sign-in prompt disabled, returning false.');
      return false;
    }

    print('[PlayGames] Prompting for sign-in...');
    await _attemptSignIn(rememberDismissal: false);
    print('[PlayGames] Sign-in attempt complete. Signed in: $_isSignedIn');
    return _isSignedIn;
  }

  Future<void> _refreshAuthState() async {
    try {
      _isSignedIn = await GameAuth.isSignedIn;
      print('[PlayGames] Auth state refreshed: $_isSignedIn');
    } catch (e) {
      print('[PlayGames] Error checking auth state: $e');
      _isSignedIn = false;
    }
  }

  Future<void> _attemptSignIn({required bool rememberDismissal}) async {
    try {
      debugPrint('[PlayGames] Calling GameAuth.signIn()...');
      await GameAuth.signIn();
      debugPrint('[PlayGames] Sign-in call completed.');
    } catch (e) {
      debugPrint('[PlayGames] Sign-in failed: $e');
      // Leave Play Games disabled for this session if sign-in is unavailable.
    }

    await _refreshAuthState();

    if (_isSignedIn) {
      await _setAutoSignInDisabled(false);
    } else if (rememberDismissal) {
      await _setAutoSignInDisabled(true);
    }

    notifyListeners();
  }

  Future<void> _setAutoSignInDisabled(bool value) async {
    if (_autoSignInDisabled == value) {
      return;
    }

    _autoSignInDisabled = value;
    await _prefsBox.put(GameConfig.playGamesAutoSignInDisabledKey, value);
  }

  Score? _buildScore(int score) {
    final androidId = GameConfig.playGamesAndroidLeaderboardId;
    final iosId = GameConfig.playGamesIOSLeaderboardId;

    if (androidId.isEmpty && iosId.isEmpty) {
      print('[PlayGames] No leaderboard IDs configured.');
      return null;
    }

    print(
      '[PlayGames] Building score object: android="$androidId", ios="$iosId", value=$score',
    );
    return Score(
      androidLeaderboardID: androidId.isEmpty ? null : androidId,
      iOSLeaderboardID: iosId.isEmpty ? null : iosId,
      value: score,
    );
  }

  bool _supportsPlayGames() {
    if (kIsWeb) {
      print('[PlayGames] Web platform detected, Play Games not supported.');
      return false;
    }

    final supported = switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS => true,
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.windows => false,
    };
    print(
      '[PlayGames] Platform: $defaultTargetPlatform, supported: $supported',
    );
    return supported;
  }
}
