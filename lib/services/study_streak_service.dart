import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudyStreakService extends ChangeNotifier with WidgetsBindingObserver {
  StudyStreakService._();

  static final StudyStreakService instance = StudyStreakService._();
  // Temporary testing goal. This can return to 30 * 60 later without
  // resetting streak rows that have already been earned.
  static const int dailyGoalSeconds = 5 * 60;
  static const int dailyGoalMinutes = dailyGoalSeconds ~/ 60;
  static const int recoveryGoalDays = 2;
  static const int missedDaysBeforeReset = 2;
  static const Duration idleLimit = Duration(minutes: 3);

  final Set<Object> _activeRegions = <Object>{};
  Timer? _timer;
  StreamSubscription<AuthState>? _authSubscription;
  DateTime _lastTick = DateTime.now();
  DateTime _lastInteraction = DateTime.now();
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  String _studyDate = _dateKey(DateTime.now());
  int _pendingCloudSeconds = 0;
  bool _initialized = false;
  bool _syncing = false;

  int todaySeconds = 0;
  int currentStreak = 0;
  int longestStreak = 0;
  int recoveryDays = 0;
  String status = 'active';
  String? lastCompletedDate;

  int get remainingSeconds =>
      (dailyGoalSeconds - todaySeconds).clamp(0, dailyGoalSeconds).toInt();
  double get progress => (todaySeconds / dailyGoalSeconds).clamp(0.0, 1.0);
  bool get goalComplete => todaySeconds >= dailyGoalSeconds;
  bool get isProbation => _effectiveProbation;

  String get statusLabel => isProbation
      ? 'Probation $recoveryDays/$recoveryGoalDays'
      : '$currentStreak day streak';

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    await _loadLocal();
    await _loadCloud();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) => _loadCloud(),
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void setRegionActive(Object region, bool active) {
    if (active) {
      _activeRegions.add(region);
      registerInteraction();
    } else {
      _activeRegions.remove(region);
    }
    _lastTick = DateTime.now();
  }

  void registerInteraction() {
    _lastInteraction = DateTime.now();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _lastTick = DateTime.now();
    if (state == AppLifecycleState.resumed) registerInteraction();
  }

  Future<void> _tick() async {
    final now = DateTime.now();
    final today = _dateKey(now);
    if (today != _studyDate) {
      await _flush();
      _studyDate = today;
      todaySeconds = 0;
      _pendingCloudSeconds = 0;
      await _loadCloud();
    }

    final elapsed = now.difference(_lastTick).inSeconds.clamp(0, 2).toInt();
    _lastTick = now;
    final isActive = _activeRegions.isNotEmpty &&
        _lifecycle == AppLifecycleState.resumed &&
        now.difference(_lastInteraction) <= idleLimit;
    if (!isActive || elapsed == 0) return;

    final wasComplete = goalComplete;
    todaySeconds += elapsed;
    _pendingCloudSeconds += elapsed;
    if (!wasComplete && goalComplete) _applyLocalCompletion(today);
    notifyListeners();

    if (_pendingCloudSeconds >= 60) {
      await _flush();
    } else if (todaySeconds % 10 == 0) {
      await _saveLocal();
    }
  }

  void _applyLocalCompletion(String today) {
    if (lastCompletedDate == today) return;
    _reconcileMissedDays(today);
    final previous = lastCompletedDate == null
        ? null
        : DateTime.tryParse(lastCompletedDate!);
    final current = DateTime.parse(today);
    final consecutive =
        previous != null && current.difference(previous).inDays == 1;

    if (lastCompletedDate == null) {
      status = 'active';
      currentStreak = 1;
      recoveryDays = 0;
    } else if (status == 'probation' || !consecutive) {
      status = 'probation';
      recoveryDays = consecutive ? recoveryDays + 1 : 1;
      currentStreak = 0;
      if (recoveryDays >= recoveryGoalDays) {
        status = 'active';
        currentStreak = recoveryGoalDays;
        recoveryDays = 0;
      }
    } else {
      currentStreak += 1;
    }
    if (currentStreak > longestStreak) longestStreak = currentStreak;
    lastCompletedDate = today;
  }

  bool get _effectiveProbation {
    return status == 'probation';
  }

  void _reconcileMissedDays(String date) {
    final rawLastCompleted = lastCompletedDate;
    if (rawLastCompleted == null) return;
    final last = DateTime.tryParse(rawLastCompleted);
    final current = DateTime.tryParse(date);
    if (last == null || current == null) return;

    final gap = current.difference(last).inDays;
    if (gap >= missedDaysBeforeReset + 1) {
      // Two complete calendar days were missed. The old streak can no longer
      // be recovered; the next completed goal starts a new streak at day 1.
      status = 'active';
      currentStreak = 0;
      recoveryDays = 0;
      lastCompletedDate = null;
    } else if (gap >= 2) {
      // One complete calendar day was missed. Recovery must restart and then
      // be completed on two consecutive qualifying study days.
      status = 'probation';
      currentStreak = 0;
      recoveryDays = 0;
    } else if (status == 'probation' && recoveryDays >= recoveryGoalDays) {
      // Upgrade an existing 2/3 recovery created by the previous rule.
      status = 'active';
      currentStreak = recoveryGoalDays;
      recoveryDays = 0;
    }
  }

  Future<void> _loadLocal() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('study_streak_state');
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _studyDate = data['study_date'] as String? ?? _studyDate;
      todaySeconds = data['today_seconds'] as int? ?? 0;
      currentStreak = data['current_streak'] as int? ?? 0;
      longestStreak = data['longest_streak'] as int? ?? 0;
      recoveryDays = data['recovery_days'] as int? ?? 0;
      status = data['status'] as String? ?? 'active';
      lastCompletedDate = data['last_completed_date'] as String?;
      if (_studyDate != _dateKey(DateTime.now())) {
        _studyDate = _dateKey(DateTime.now());
        todaySeconds = 0;
      }
      _reconcileMissedDays(_studyDate);
    } catch (_) {
      // Keep a clean state if old local data cannot be decoded.
    }
  }

  Future<void> _saveLocal() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'study_streak_state',
      jsonEncode({
        'study_date': _studyDate,
        'today_seconds': todaySeconds,
        'current_streak': currentStreak,
        'longest_streak': longestStreak,
        'recovery_days': recoveryDays,
        'status': status,
        'last_completed_date': lastCompletedDate,
      }),
    );
  }

  Future<void> _loadCloud() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null || user.isAnonymous) {
      notifyListeners();
      return;
    }
    try {
      final daily = await client
          .from('study_daily_progress')
          .select('active_seconds')
          .eq('user_id', user.id)
          .eq('study_date', _studyDate)
          .maybeSingle();
      final streak = await client
          .from('study_streaks')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
      if (daily != null) {
        todaySeconds =
            (daily['active_seconds'] as num?)?.toInt() ?? todaySeconds;
      }
      if (streak != null) {
        currentStreak = (streak['current_streak'] as num?)?.toInt() ?? 0;
        longestStreak = (streak['longest_streak'] as num?)?.toInt() ?? 0;
        recoveryDays = (streak['recovery_days'] as num?)?.toInt() ?? 0;
        status = streak['status'] as String? ?? 'active';
        lastCompletedDate = streak['last_completed_date'] as String?;
      }
      _reconcileMissedDays(_studyDate);
      await _saveLocal();
      notifyListeners();
    } catch (error) {
      debugPrint('Study streak cloud load skipped: $error');
    }
  }

  Future<void> _flush() async {
    await _saveLocal();
    if (_syncing || _pendingCloudSeconds <= 0) return;
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null || user.isAnonymous) return;

    _syncing = true;
    final seconds = _pendingCloudSeconds;
    try {
      final result = await client.rpc('record_study_time', params: {
        'p_seconds': seconds,
        'p_study_date': _studyDate,
        'p_timezone': _timezoneLabel(),
      });
      _pendingCloudSeconds -= seconds;
      final data = result is List && result.isNotEmpty
          ? Map<String, dynamic>.from(result.first as Map)
          : result is Map
              ? Map<String, dynamic>.from(result)
              : null;
      if (data != null) {
        todaySeconds =
            (data['active_seconds'] as num?)?.toInt() ?? todaySeconds;
        currentStreak =
            (data['current_streak'] as num?)?.toInt() ?? currentStreak;
        longestStreak =
            (data['longest_streak'] as num?)?.toInt() ?? longestStreak;
        recoveryDays = (data['recovery_days'] as num?)?.toInt() ?? recoveryDays;
        status = data['status'] as String? ?? status;
        lastCompletedDate =
            data['last_completed_date'] as String? ?? lastCompletedDate;
      }
      await _saveLocal();
      notifyListeners();
    } catch (error) {
      debugPrint('Study streak cloud sync skipped: $error');
    } finally {
      _syncing = false;
    }
  }

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _timezoneLabel() {
    final offset = DateTime.now().timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
