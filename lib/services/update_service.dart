import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:sandfall/config/game_config.dart';

class UpdateService extends ChangeNotifier {
  static final UpdateService _instance = UpdateService._internal();

  factory UpdateService() {
    return _instance;
  }

  UpdateService._internal();

  static UpdateService get instance => _instance;

  bool _isSupportedPlatform = false;
  bool _isInitialized = false;
  bool _updateAvailable = false;
  bool _isCheckingForUpdate = false;
  late Box _prefsBox;
  AppUpdateInfo? _appUpdateInfo;
  DateTime? _lastCheckTime;
  static const Duration _checkCooldown = Duration(hours: 24);

  bool get isSupportedPlatform => _isSupportedPlatform;
  bool get updateAvailable => _updateAvailable;
  bool get isCheckingForUpdate => _isCheckingForUpdate;
  AppUpdateInfo? get appUpdateInfo => _appUpdateInfo;

  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('[UpdateService] Already initialized, skipping.');
      return;
    }

    _prefsBox = await Hive.openBox(GameConfig.updatePrefsBox);
    _isSupportedPlatform = _supportsInAppUpdate();
    _isInitialized = true;
    debugPrint('[UpdateService] Initializing... (supported: $_isSupportedPlatform)');

    if (!_isSupportedPlatform) {
      debugPrint('[UpdateService] Platform not supported, skipping update checks.');
      notifyListeners();
      return;
    }

    // Check for update on app start if enough time has passed
    await _checkForUpdateIfNeeded();
  }

  /// Checks for app update if cooldown period has passed
  Future<void> _checkForUpdateIfNeeded() async {
    final lastCheck = _prefsBox.get(GameConfig.lastUpdateCheckKey);
    if (lastCheck != null) {
      final lastCheckTime = DateTime.fromMillisecondsSinceEpoch(lastCheck);
      final now = DateTime.now();
      if (now.difference(lastCheckTime) < _checkCooldown) {
        debugPrint('[UpdateService] Update check skipped (cooldown active).');
        return;
      }
    }

    await checkForUpdate();
  }

  /// Checks for available app updates
  Future<void> checkForUpdate({bool force = false}) async {
    if (!_isSupportedPlatform) {
      debugPrint('[UpdateService] Platform not supported for in-app updates.');
      return;
    }

    if (_isCheckingForUpdate && !force) {
      debugPrint('[UpdateService] Update check already in progress.');
      return;
    }

    _isCheckingForUpdate = true;
    notifyListeners();

    try {
      debugPrint('[UpdateService] Checking for app update...');
      _appUpdateInfo = await InAppUpdate.checkForUpdate();
      _updateAvailable = _appUpdateInfo?.updateAvailability ==
          UpdateAvailability.updateAvailable;

      if (_updateAvailable) {
        debugPrint(
            '[UpdateService] Update available! Immediate: ${_appUpdateInfo?.immediateUpdateAllowed}, Flexible: ${_appUpdateInfo?.flexibleUpdateAllowed}');
      } else {
        debugPrint('[UpdateService] No update available.');
      }
    } catch (e) {
      debugPrint('[UpdateService] Error checking for update: $e');
      _updateAvailable = false;
      _appUpdateInfo = null;
    } finally {
      _isCheckingForUpdate = false;
      _lastCheckTime = DateTime.now();
      await _prefsBox.put(
          GameConfig.lastUpdateCheckKey, _lastCheckTime!.millisecondsSinceEpoch);
      notifyListeners();
    }
  }

  /// Starts the in-app update flow
  Future<AppUpdateResult?> startUpdate() async {
    if (!_updateAvailable || _appUpdateInfo == null) {
      debugPrint('[UpdateService] No update available to start.');
      return null;
    }

    if (!_isSupportedPlatform) {
      debugPrint('[UpdateService] Platform not supported for in-app updates.');
      return null;
    }

    try {
      debugPrint('[UpdateService] Starting in-app update flow...');
      
      // Choose between immediate and flexible update
      final bool useImmediate = _appUpdateInfo!.immediateUpdateAllowed &&
          !_appUpdateInfo!.flexibleUpdateAllowed;
      
      AppUpdateResult result;
      if (useImmediate) {
        result = await InAppUpdate.performImmediateUpdate();
      } else if (_appUpdateInfo!.flexibleUpdateAllowed) {
        result = await InAppUpdate.startFlexibleUpdate();
        if (result == AppUpdateResult.success) {
          // For flexible update, we need to complete it
          await InAppUpdate.completeFlexibleUpdate();
        }
      } else {
        debugPrint('[UpdateService] No update type allowed.');
        return null;
      }

      debugPrint('[UpdateService] Update flow completed with result: $result');

      // Reset update available state after attempting update
      _updateAvailable = false;
      _appUpdateInfo = null;
      notifyListeners();

      return result;
    } catch (e) {
      debugPrint('[UpdateService] Error starting update: $e');
      return null;
    }
  }

  /// Shows update prompt dialog if update is available
  Future<void> showUpdatePromptIfAvailable(BuildContext context) async {
    if (!_updateAvailable || _appUpdateInfo == null) {
      return;
    }

    // Don't show if already showing or if we're in a game
    // This could be enhanced to check game state
    final shouldUpdate = await _showUpdateDialog(context);
    if (shouldUpdate) {
      await startUpdate();
    }
  }

  Future<bool> _showUpdateDialog(BuildContext context) async {
    final bool canFlexible = _appUpdateInfo!.flexibleUpdateAllowed;

    return await showDialog<bool>(
          context: context,
          barrierDismissible: canFlexible, // Immediate updates can't be dismissed
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text(
              'Update Available',
              style: TextStyle(
                color: Color(0xFFFFD700),
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 2,
              ),
            ),
            content: Text(
              canFlexible
                  ? 'A new version of SandFall is available. Would you like to update now? You can continue playing while it downloads.'
                  : 'A required update is available. The app must be updated to continue.',
              style: const TextStyle(
                color: Colors.white70,
                fontFamily: 'monospace',
              ),
            ),
            actions: [
              if (canFlexible)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'LATER',
                    style: TextStyle(
                      color: Colors.white54,
                      fontFamily: 'monospace',
                      letterSpacing: 1,
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                ),
                child: Text(
                  canFlexible ? 'UPDATE' : 'UPDATE NOW',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  bool _supportsInAppUpdate() {
    if (kIsWeb) {
      debugPrint('[UpdateService] Web platform detected, in-app update not supported.');
      return false;
    }

    final supported = switch (defaultTargetPlatform) {
      TargetPlatform.android => true,
      TargetPlatform.iOS => true,
      TargetPlatform.macOS => true,
      _ => false,
    };
    debugPrint(
        '[UpdateService] Platform: $defaultTargetPlatform, supported: $supported');
    return supported;
  }
}