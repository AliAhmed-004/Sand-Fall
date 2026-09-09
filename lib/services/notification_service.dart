import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:sandfall/services/daily_challenge_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

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

    // Set the device's actual local timezone so notifications fire at the
    // correct local time instead of defaulting to UTC.
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      final String tzName = (tzInfo as dynamic).identifier as String;
      tz.setLocalLocation(tz.getLocation(tzName));
      debugPrint('[NotificationService] Timezone: $tzName');
    } catch (e) {
      debugPrint('[NotificationService] Timezone detection failed: $e');
    }

    const android = AndroidInitializationSettings('@mipmap/launcher_icon');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
    );

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.requestNotificationsPermission();

    final state = await DailyChallengeService.instance.loadState();

    try {
      await scheduleDailyReminder(state.streak);
      await scheduleStreakWarning(state.streak);
    } catch (e) {
      debugPrint('[NotificationService] Scheduling failed: $e');
    }

    debugPrint('[NotificationService] Initialized.');
  }

  /// Daily reminder — fires at 2:00 PM local time every day.
  Future<void> scheduleDailyReminder(int streakDays) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      await _plugin.cancel(id: _idDaily);

      final now = tz.TZDateTime.now(tz.local);
      var target = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        14,
        0, // 2:00 PM
      );
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
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('[NotificationService] scheduleDailyReminder failed: $e');
    }
  }

  /// Streak warning — fires at 3:00 PM local time if streak > 1 and not
  /// yet played today.
  Future<void> scheduleStreakWarning(int streakDays) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (streakDays < 2) return;

    try {
      await _plugin.cancel(id: _idStreak);

      final now = tz.TZDateTime.now(tz.local);
      final target = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        15,
        0, // 3:00 PM
      );
      if (target.isBefore(now)) return; // too late today, skip

      await _plugin.zonedSchedule(
        id: _idStreak,
        title: 'Streak at risk! ⚠️',
        body: '🔥 $streakDays days on the line — play today!',
        scheduledDate: target,
        notificationDetails: _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('[NotificationService] scheduleStreakWarning failed: $e');
    }
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
      icon: '@mipmap/launcher_icon',
    ),
  );
}
