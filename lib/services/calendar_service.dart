import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/calendar_task.dart';

class CalendarService {
  static const _tasksKey = 'calendar_tasks_v1';
  static const _deletedIdsKey = 'deleted_calendar_task_ids_v1';

  SupabaseClient get _client => Supabase.instance.client;

  User? get _cloudUser {
    final user = _client.auth.currentUser;
    return user == null || user.isAnonymous ? null : user;
  }

  bool get cloudSyncEnabled => _cloudUser != null;

  Future<List<CalendarTask>> loadTasks() async {
    final local = await _loadLocalTasks();
    final user = _cloudUser;
    if (user == null) return _sort(local);

    try {
      final deletedIds = await _loadDeletedIds();
      if (deletedIds.isNotEmpty) {
        await _client
            .from('calendar_tasks')
            .delete()
            .eq('user_id', user.id)
            .inFilter('id', deletedIds.toList());
        await _clearDeletedIds();
      }

      final rows = await _client
          .from('calendar_tasks')
          .select(
            'id, title, details, task_date, task_time, is_completed, '
            'created_at, updated_at',
          )
          .eq('user_id', user.id)
          .order('task_date')
          .order('task_time');
      final cloud = rows.map(_fromCloudRow).toList();
      final cloudById = <String, CalendarTask>{
        for (final task in cloud) task.id: task,
      };
      final merged = <String, CalendarTask>{
        for (final task in cloud) task.id: task,
      };
      for (final task in local) {
        final cloudTask = merged[task.id];
        if (cloudTask == null || task.updatedAt.isAfter(cloudTask.updatedAt)) {
          merged[task.id] = task;
        }
      }

      final tasks = _sort(merged.values.toList());
      await _saveLocalTasks(tasks);
      final unsynced = tasks.where((task) {
        final cloudTask = cloudById[task.id];
        return cloudTask == null || task.updatedAt.isAfter(cloudTask.updatedAt);
      }).toList();
      if (unsynced.isNotEmpty) await _upsertCloudTasks(unsynced, user.id);
      return tasks;
    } catch (error) {
      debugPrint('Could not load calendar tasks from Supabase: $error');
      return _sort(local);
    }
  }

  Future<void> saveTask(CalendarTask task) async {
    final tasks = await _loadLocalTasks();
    final index = tasks.indexWhere((item) => item.id == task.id);
    if (index < 0) {
      tasks.add(task);
    } else {
      tasks[index] = task;
    }
    await _saveLocalTasks(_sort(tasks));

    final user = _cloudUser;
    if (user == null) return;
    try {
      await _upsertCloudTasks([task], user.id);
    } catch (error) {
      debugPrint('Could not sync calendar task to Supabase: $error');
    }
  }

  Future<void> deleteTask(String taskId) async {
    final tasks = await _loadLocalTasks();
    tasks.removeWhere((task) => task.id == taskId);
    await _saveLocalTasks(tasks);

    final preferences = await SharedPreferences.getInstance();
    final deletedIds = (preferences.getStringList(_deletedIdsKey) ?? [])
      ..remove(taskId)
      ..add(taskId);
    await preferences.setStringList(_deletedIdsKey, deletedIds);

    final user = _cloudUser;
    if (user == null) return;
    try {
      await _client
          .from('calendar_tasks')
          .delete()
          .eq('id', taskId)
          .eq('user_id', user.id);
      final remaining = await _loadDeletedIds();
      remaining.remove(taskId);
      await preferences.setStringList(_deletedIdsKey, remaining.toList());
    } catch (error) {
      debugPrint('Could not delete calendar task from Supabase: $error');
    }
  }

  Future<List<CalendarTask>> _loadLocalTasks() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_tasksKey);
    if (raw == null || raw.isEmpty) return <CalendarTask>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (item) => CalendarTask.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } catch (error) {
      debugPrint('Could not read local calendar tasks: $error');
      return <CalendarTask>[];
    }
  }

  Future<void> _saveLocalTasks(List<CalendarTask> tasks) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _tasksKey,
      jsonEncode(tasks.map((task) => task.toJson()).toList()),
    );
    if (!saved) throw StateError('The device rejected the calendar data.');
  }

  Future<Set<String>> _loadDeletedIds() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_deletedIdsKey) ?? const <String>[])
        .toSet();
  }

  Future<void> _clearDeletedIds() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_deletedIdsKey);
  }

  Future<void> _upsertCloudTasks(
    List<CalendarTask> tasks,
    String userId,
  ) async {
    await _client.from('calendar_tasks').upsert(
          tasks.map((task) => _toCloudRow(task, userId)).toList(),
        );
  }

  Map<String, Object?> _toCloudRow(CalendarTask task, String userId) => {
        'id': task.id,
        'user_id': userId,
        'title': task.title,
        'details': task.details,
        'task_date': CalendarTask.dateKey(task.date),
        'task_time': task.minutesSinceMidnight == null
            ? null
            : _timeForDatabase(task.minutesSinceMidnight!),
        'is_completed': task.isCompleted,
        'created_at': task.createdAt.toUtc().toIso8601String(),
        'updated_at': task.updatedAt.toUtc().toIso8601String(),
      };

  CalendarTask _fromCloudRow(Map<String, dynamic> row) {
    return CalendarTask(
      id: row['id'] as String,
      title: row['title'] as String,
      details: row['details'] as String? ?? '',
      date: DateTime.parse(row['task_date'] as String),
      minutesSinceMidnight: _minutesFromDatabase(row['task_time'] as String?),
      isCompleted: row['is_completed'] as bool? ?? false,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
    );
  }

  int? _minutesFromDatabase(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  String _timeForDatabase(int minutes) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute:00';
  }

  List<CalendarTask> _sort(List<CalendarTask> tasks) {
    tasks.sort((a, b) {
      final dateResult = a.date.compareTo(b.date);
      if (dateResult != 0) return dateResult;
      final aTime = a.minutesSinceMidnight ?? -1;
      final bTime = b.minutesSinceMidnight ?? -1;
      final timeResult = aTime.compareTo(bTime);
      if (timeResult != 0) return timeResult;
      return a.createdAt.compareTo(b.createdAt);
    });
    return tasks;
  }
}
