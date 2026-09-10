import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/calendar_task.dart';
import '../services/calendar_reminder_service.dart';
import '../services/calendar_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const _months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _weekdays = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  final CalendarService _service = CalendarService();
  final CalendarReminderService _reminders = CalendarReminderService.instance;
  final List<CalendarTask> _tasks = <CalendarTask>[];
  StreamSubscription<AuthState>? _authSubscription;
  late DateTime _selectedDate;
  late DateTime _visibleMonth;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    _selectedDate = today;
    _visibleMonth = DateTime(today.year, today.month);
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) => unawaited(_load()),
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final tasks = await _service.loadTasks();
    if (!mounted) return;
    setState(() {
      _tasks
        ..clear()
        ..addAll(tasks);
      _loading = false;
    });
    unawaited(_reminders.rescheduleAll(tasks));
  }

  List<CalendarTask> _tasksFor(DateTime date) =>
      _tasks.where((task) => _sameDay(task.date, date)).toList()
        ..sort(_compareTasks);

  Future<void> _openTaskEditor([CalendarTask? existing]) async {
    final task = await _showTaskDialog(existing);
    if (task == null || !mounted) return;
    setState(() {
      final index = _tasks.indexWhere((item) => item.id == task.id);
      if (index < 0) {
        _tasks.add(task);
      } else {
        _tasks[index] = task;
      }
      _selectedDate = task.date;
      _visibleMonth = DateTime(task.date.year, task.date.month);
    });
    try {
      await _service.saveTask(task);
      final reminderSet = await _reminders.scheduleTask(task);
      if (!mounted || task.isCompleted) return;
      final reminderTime = _reminders.reminderDateFor(task.date);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final eventDay = DateTime(task.date.year, task.date.month, task.date.day);
      final reminderWasLate =
          !reminderTime.isAfter(now) && eventDay.isAfter(today);
      final taskStart = _reminders.taskStartDateFor(task);
      final tenMinuteReminder = _reminders.tenMinuteReminderDateFor(task);
      final tenMinuteReminderWasLate = taskStart?.isAfter(now) == true &&
          tenMinuteReminder?.isAfter(now) == false;
      final message = reminderSet
          ? tenMinuteReminderWasLate
              ? 'The 10-minute reminder had passed, so it was shown now.'
              : tenMinuteReminder?.isAfter(now) == true
                  ? 'Reminder set for ${_fullDate(tenMinuteReminder!)} at '
                      '${_formatMinutes(tenMinuteReminder.hour * 60 + tenMinuteReminder.minute)} '
                      '(10 minutes before the task).'
                  : reminderWasLate
                      ? 'The 8:00 AM reminder had passed, so it was shown now.'
                      : 'Reminder set for ${_fullDate(reminderTime)} at 8:00 AM.'
          : reminderTime.isAfter(DateTime.now())
              ? 'Task saved. Allow notifications to receive its reminder.'
              : 'Task saved. Its reminder time has already passed.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save task: $error')),
      );
    }
  }

  Future<CalendarTask?> _showTaskDialog(CalendarTask? existing) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final details = TextEditingController(text: existing?.details ?? '');
    var date = existing?.date ?? _selectedDate;
    var allDay = existing?.minutesSinceMidnight == null;
    var time = existing?.minutesSinceMidnight == null
        ? const TimeOfDay(hour: 9, minute: 0)
        : _timeOfDay(existing!.minutesSinceMidnight!);

    final result = await showDialog<CalendarTask>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: Text(existing == null ? 'New task' : 'Edit task'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    autofocus: true,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Task title',
                      prefixIcon: Icon(Icons.task_alt),
                    ),
                    onChanged: (_) => updateDialog(() {}),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: details,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Details (optional)',
                      prefixIcon: Icon(Icons.notes),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('All-day task'),
                    value: allDay,
                    onChanged: (value) => updateDialog(() => allDay = value),
                  ),
                  if (!allDay)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule),
                      title: const Text('Time'),
                      subtitle: Text(time.format(dialogContext)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: dialogContext,
                          initialTime: time,
                          initialEntryMode: TimePickerEntryMode.inputOnly,
                        );
                        if (picked != null) updateDialog(() => time = picked);
                      },
                    ),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.notifications_active_outlined,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            allDay
                                ? 'Reminder: one day before at 8:00 AM'
                                : 'Reminders: one day before at 8:00 AM and 10 minutes before the task',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: title.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                        dialogContext,
                        _makeTask(existing, title.text, details.text, date,
                            allDay ? null : time),
                      ),
              child: Text(existing == null ? 'Add task' : 'Save'),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    details.dispose();
    return result;
  }

  CalendarTask _makeTask(
    CalendarTask? old,
    String title,
    String details,
    DateTime date,
    TimeOfDay? time,
  ) {
    final now = DateTime.now();
    return CalendarTask(
      id: old?.id ?? const Uuid().v4(),
      title: title.trim(),
      details: details.trim(),
      date: _dateOnly(date),
      minutesSinceMidnight: time == null ? null : time.hour * 60 + time.minute,
      isCompleted: old?.isCompleted ?? false,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> _toggleTask(CalendarTask task, bool completed) async {
    final changed = task.copyWith(
      isCompleted: completed,
      updatedAt: DateTime.now(),
    );
    setState(() {
      _tasks[_tasks.indexWhere((item) => item.id == task.id)] = changed;
    });
    await _service.saveTask(changed);
    if (completed) {
      await _reminders.cancelTask(task.id);
    } else {
      await _reminders.scheduleTask(changed);
    }
  }

  Future<void> _confirmDelete(CalendarTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('“${task.title}” will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _tasks.removeWhere((item) => item.id == task.id));
    await _service.deleteTask(task.id);
    await _reminders.cancelTask(task.id);
  }

  void _changeMonth(int offset) {
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month + offset,
      );
      _selectedDate = _visibleMonth;
    });
  }

  void _goToday() {
    final today = _dateOnly(DateTime.now());
    setState(() {
      _selectedDate = today;
      _visibleMonth = DateTime(today.year, today.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          _header(theme),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 900;
                      if (wide) {
                        return Row(
                          children: [
                            Expanded(flex: 3, child: _monthCard(theme)),
                            Expanded(flex: 2, child: _agendaCard(theme, false)),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          SizedBox(height: 410, child: _monthCard(theme)),
                          Expanded(child: _agendaCard(theme, true)),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        return Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          color: theme.colorScheme.surface,
          child: Row(
            children: [
              Icon(Icons.calendar_month, color: theme.colorScheme.primary),
              const SizedBox(width: 9),
              const Text('Calendar',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(width: 9),
              Tooltip(
                message: _service.cloudSyncEnabled
                    ? 'Synced with Supabase'
                    : 'Saved on this device until you sign in',
                child: Icon(
                  _service.cloudSyncEnabled
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  size: 18,
                  color: Colors.grey,
                ),
              ),
              const Spacer(),
              if (compact) ...[
                IconButton(
                  tooltip: 'Today',
                  onPressed: _goToday,
                  icon: const Icon(Icons.today),
                ),
                IconButton.filled(
                  tooltip: 'New task',
                  onPressed: _openTaskEditor,
                  icon: const Icon(Icons.add),
                ),
              ] else ...[
                OutlinedButton(onPressed: _goToday, child: const Text('Today')),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _openTaskEditor,
                  icon: const Icon(Icons.add),
                  label: const Text('New task'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _monthCard(ThemeData theme) {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final today = _dateOnly(DateTime.now());

    return Card(
      elevation: 0,
      margin: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${_months[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: _weekdays
                  .map(
                    (day) => Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 42,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1.15,
                ),
                itemBuilder: (context, index) {
                  final date = gridStart.add(Duration(days: index));
                  final selected = _sameDay(date, _selectedDate);
                  final isToday = _sameDay(date, today);
                  final inMonth = date.month == _visibleMonth.month;
                  final count = _tasksFor(date).length;
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _selectedDate = date),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        border: isToday && !selected
                            ? Border.all(color: theme.colorScheme.primary)
                            : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${date.day}',
                            style: TextStyle(
                              fontWeight:
                                  selected || isToday ? FontWeight.w700 : null,
                              color: selected
                                  ? theme.colorScheme.onPrimary
                                  : inMonth
                                      ? null
                                      : theme.disabledColor,
                            ),
                          ),
                          if (count > 0) ...[
                            const SizedBox(height: 3),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: selected
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.tertiary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _agendaCard(ThemeData theme, bool compact) {
    final tasks = _tasksFor(_selectedDate);
    return Card(
      elevation: 0,
      margin: compact
          ? const EdgeInsets.fromLTRB(16, 0, 16, 16)
          : const EdgeInsets.fromLTRB(0, 16, 16, 16),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fullDate(_selectedDate),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        tasks.isEmpty
                            ? 'Nothing planned'
                            : '${tasks.length} ${tasks.length == 1 ? 'task' : 'tasks'}',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Add task on this date',
                  onPressed: _openTaskEditor,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: tasks.isEmpty
                ? _emptyAgenda(theme)
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: tasks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) => _taskTile(tasks[index], theme),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyAgenda(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_available_outlined,
              size: 48,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your day is clear',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Add a study task or reminder for this date.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _openTaskEditor,
              icon: const Icon(Icons.add),
              label: const Text('Add task'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskTile(CalendarTask task, ThemeData theme) {
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openTaskEditor(task),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: task.isCompleted,
                onChanged: (value) => _toggleTask(task, value ?? false),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          decoration: task.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: task.isCompleted
                              ? theme.colorScheme.onSurfaceVariant
                              : null,
                        ),
                      ),
                      if (task.minutesSinceMidnight != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          _formatMinutes(task.minutesSinceMidnight!),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (task.details.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          task.details,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Task actions',
                onSelected: (action) {
                  if (action == 'edit') _openTaskEditor(task);
                  if (action == 'delete') _confirmDelete(task);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _compareTasks(CalendarTask a, CalendarTask b) {
    final time =
        (a.minutesSinceMidnight ?? -1).compareTo(b.minutesSinceMidnight ?? -1);
    return time != 0 ? time : a.createdAt.compareTo(b.createdAt);
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static TimeOfDay _timeOfDay(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  String _fullDate(DateTime date) =>
      '${_weekdays[date.weekday - 1]}, ${date.day} '
      '${_months[date.month - 1]} ${date.year}';

  String _formatMinutes(int minutes) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }
}
