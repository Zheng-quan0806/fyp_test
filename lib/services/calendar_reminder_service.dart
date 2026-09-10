import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/calendar_task.dart';

class CalendarReminderService {
  CalendarReminderService._();

  static final CalendarReminderService instance = CalendarReminderService._();

  static const int reminderHour = 8;
  static const int reminderDaysBefore = 1;
  static const String _channelId = 'calendar_reminders';
  static const String _channelName = 'Calendar reminders';
  static const String _communityChannelId = 'community_messages';
  static const String _communityChannelName = 'Community messages';
  static const NotificationDetails _notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Reminders for upcoming calendar tasks',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );
  static const NotificationDetails _communityNotificationDetails =
      NotificationDetails(
    android: AndroidNotificationDetails(
      _communityChannelId,
      _communityChannelName,
      channelDescription: 'Notifications for new community chat messages',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _permissionsChecked = false;
  AndroidScheduleMode _androidScheduleMode =
      AndroidScheduleMode.inexactAllowWhileIdle;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    try {
      tz_data.initializeTimeZones();
      try {
        final timezone = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(timezone.identifier));
      } catch (error) {
        debugPrint('Could not determine local timezone: $error');
      }

      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: IOSInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        linux: LinuxInitializationSettings(
          defaultActionName: 'Open Notebook Tutor',
        ),
        windows: WindowsInitializationSettings(
          appName: 'Notebook Tutor',
          appUserModelId: 'NotebookTutor.Calendar',
          guid: '67f85718-6600-4f3f-af35-6fd2a88bd79c',
        ),
      );
      await _notifications.initialize(settings: settings);
      _initialized = true;
    } catch (error) {
      debugPrint('Could not initialize calendar notifications: $error');
    }
  }

  Future<bool> scheduleTask(
    CalendarTask task, {
    bool notifyImmediatelyIfLate = true,
  }) async {
    await initialize();
    if (!_initialized || kIsWeb) return false;

    await cancelTask(task.id);
    if (task.isCompleted) return false;

    final now = DateTime.now();
    final dayReminder = reminderDateFor(task.date);
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(task.date.year, task.date.month, task.date.day);
    final showLateDayReminder = notifyImmediatelyIfLate &&
        !dayReminder.isAfter(now) &&
        eventDay.isAfter(today);
    final taskStart = taskStartDateFor(task);
    final tenMinuteReminder = tenMinuteReminderDateFor(task);
    final showLateTenMinuteReminder = notifyImmediatelyIfLate &&
        tenMinuteReminder != null &&
        !tenMinuteReminder.isAfter(now) &&
        taskStart!.isAfter(now);
    final hasFutureDayReminder = dayReminder.isAfter(now);
    final hasFutureTenMinuteReminder = tenMinuteReminder?.isAfter(now) == true;

    if (!hasFutureDayReminder &&
        !showLateDayReminder &&
        !hasFutureTenMinuteReminder &&
        !showLateTenMinuteReminder) {
      return false;
    }
    if (!await _ensurePermissions()) return false;

    var reminderCreated = false;
    if (hasFutureDayReminder) {
      try {
        await _notifications.zonedSchedule(
          id: _notificationId(task.id),
          title: 'Tomorrow: ${task.title}',
          body: task.details.isEmpty
              ? 'You have a calendar task tomorrow.'
              : task.details,
          scheduledDate: tz.TZDateTime.from(dayReminder, tz.local),
          notificationDetails: _notificationDetails,
          androidScheduleMode: _androidScheduleMode,
          payload: 'calendar:${task.id}',
        );
        reminderCreated = true;
      } catch (error) {
        debugPrint('Could not schedule calendar reminder: $error');
      }
    } else if (showLateDayReminder) {
      try {
        await _notifications.show(
          id: _notificationId(task.id),
          title: 'Upcoming: ${task.title}',
          body: task.details.isEmpty
              ? 'You have a calendar task tomorrow.'
              : task.details,
          notificationDetails: _notificationDetails,
          payload: 'calendar:${task.id}',
        );
        reminderCreated = true;
      } catch (error) {
        debugPrint('Could not show late calendar reminder: $error');
      }
    }

    if (hasFutureTenMinuteReminder) {
      try {
        await _notifications.zonedSchedule(
          id: _tenMinuteNotificationId(task.id),
          title: 'Starting soon: ${task.title}',
          body: task.details.isEmpty
              ? 'This task starts in 10 minutes.'
              : task.details,
          scheduledDate: tz.TZDateTime.from(tenMinuteReminder!, tz.local),
          notificationDetails: _notificationDetails,
          androidScheduleMode: _androidScheduleMode,
          payload: 'calendar:${task.id}',
        );
        reminderCreated = true;
      } catch (error) {
        debugPrint('Could not schedule 10-minute task reminder: $error');
      }
    } else if (showLateTenMinuteReminder) {
      try {
        await _notifications.show(
          id: _tenMinuteNotificationId(task.id),
          title: 'Starting soon: ${task.title}',
          body: task.details.isEmpty
              ? 'This task starts in less than 10 minutes.'
              : task.details,
          notificationDetails: _notificationDetails,
          payload: 'calendar:${task.id}',
        );
        reminderCreated = true;
      } catch (error) {
        debugPrint('Could not show late 10-minute task reminder: $error');
      }
    }

    return reminderCreated;
  }

  Future<void> rescheduleAll(Iterable<CalendarTask> tasks) async {
    await initialize();
    if (!_initialized || kIsWeb) return;
    for (final task in tasks) {
      if (task.isCompleted) {
        await cancelTask(task.id);
      } else {
        await scheduleTask(task, notifyImmediatelyIfLate: false);
      }
    }
  }

  Future<void> showCommunityMessage({
    required int messageId,
    required String body,
  }) async {
    await initialize();
    if (!_initialized || kIsWeb || !await _ensurePermissions()) return;

    final normalizedBody = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final preview = normalizedBody.isEmpty
        ? 'A file was shared with you.'
        : normalizedBody.length > 140
            ? '${normalizedBody.substring(0, 137)}...'
            : normalizedBody;
    try {
      await _notifications.show(
        id: 1000000000 + (messageId % 1000000000),
        title: 'New community message',
        body: preview,
        notificationDetails: _communityNotificationDetails,
        payload: 'community:$messageId',
      );
    } catch (error) {
      debugPrint('Could not show community message notification: $error');
    }
  }

  Future<void> cancelTask(String taskId) async {
    await initialize();
    if (!_initialized || kIsWeb) return;
    try {
      await _notifications.cancel(id: _notificationId(taskId));
      await _notifications.cancel(id: _tenMinuteNotificationId(taskId));
    } catch (error) {
      debugPrint('Could not cancel calendar reminder: $error');
    }
  }

  DateTime reminderDateFor(DateTime eventDate) {
    final previousDay = DateTime(
      eventDate.year,
      eventDate.month,
      eventDate.day,
    ).subtract(const Duration(days: reminderDaysBefore));
    return DateTime(
      previousDay.year,
      previousDay.month,
      previousDay.day,
      reminderHour,
    );
  }

  DateTime? taskStartDateFor(CalendarTask task) {
    final minutes = task.minutesSinceMidnight;
    if (minutes == null) return null;
    return DateTime(
      task.date.year,
      task.date.month,
      task.date.day,
      minutes ~/ 60,
      minutes % 60,
    );
  }

  DateTime? tenMinuteReminderDateFor(CalendarTask task) =>
      taskStartDateFor(task)?.subtract(const Duration(minutes: 10));

  Future<bool> _ensurePermissions() async {
    if (_permissionsChecked) return true;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final notificationsAllowed =
          await android?.requestNotificationsPermission();
      if (notificationsAllowed == false) return false;

      var exactAllowed = await android?.canScheduleExactNotifications();
      if (exactAllowed != true) {
        exactAllowed = await android?.requestExactAlarmsPermission();
      }
      _androidScheduleMode = exactAllowed == true
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final allowed = await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      if (allowed == false) return false;
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      final allowed = await _notifications
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      if (allowed == false) return false;
    }

    _permissionsChecked = true;
    return true;
  }

  int _notificationId(String taskId) {
    var hash = 17;
    for (final value in taskId.codeUnits) {
      hash = ((hash * 31) + value) & 0x7fffffff;
    }
    return hash;
  }

  int _tenMinuteNotificationId(String taskId) =>
      _notificationId('$taskId:ten-minute');
}
