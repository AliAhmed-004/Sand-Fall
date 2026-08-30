import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sandfall/services/daily_challenge_service.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  static const _channelId = 'sand_fall_daily';
  static const _channelName = 'Daily Challenge';
  static const _idDaily = 1;
  static const _idStreak = 2;

  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      debugPrint('[NotificationService] Platform not supported, skipping.');
      return;
    }

    tz_data.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
    );

    // Missing '<' before AndroidFlutterLocalNotificationsPlugin was the culprit
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.requestNotificationsPermission();

    final state = await DailyChallengeService.instance.loadState();
    await scheduleDailyReminder(state.streak);
    await scheduleStreakWarning(state.streak);

    debugPrint('[NotificationService] Initialized.');
  }

  Future<void> scheduleDailyReminder(int streakDays) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _plugin.cancel(id: _idDaily);

    final now = tz.TZDateTime.now(tz.local);
    var target = tz.TZDateTime(tz.local, now.year, now.month, now.day, 18, 0);
    if (target.isBefore(now)) target = target.add(const Duration(days: 1));

    final body = streakDays > 1
        ? "🔥 Don't break your $streakDays-day streak!"
        : "🏖️ Today's sand challenge is waiting!";

    await _plugin.zonedSchedule(
      id: _idDaily,
      title: 'Daily Challenge is Live!',
      body: body,
      scheduledDate: target,
      notificationDetails: _details(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> scheduleStreakWarning(int streakDays) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (streakDays < 2) return;
    await _plugin.cancel(id: _idStreak);

    final now = tz.TZDateTime.now(tz.local);
    final target = tz.TZDateTime(tz.local, now.year, now.month, now.day, 21, 0);
    if (target.isBefore(now)) return;

    await _plugin.zonedSchedule(
      id: _idStreak,
      title: 'Streak at risk! ⚠️',
      body: '🔥 $streakDays days on the line — play before midnight!',
      scheduledDate: target,
      notificationDetails: _details(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancelStreakWarning() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _plugin.cancel(id: _idStreak);
  }

  NotificationDetails _details() => const NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    ),
  );
}
