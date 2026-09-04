import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';
import 'services/ai_chat_store.dart';
import 'services/calendar_reminder_service.dart';
import 'services/google_auth_service.dart';
import 'services/study_streak_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
    throw StateError(
      'Missing Supabase configuration. '
      'Run with --dart-define-from-file=supabase.json',
    );
  }

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );

  await GoogleAuthService.instance.initialize();
  await AiChatStore.instance.initialize();
  await StudyStreakService.instance.initialize();
  await CalendarReminderService.instance.initialize();
  final preferences = await SharedPreferences.getInstance();
  final initialDarkMode = preferences.getBool('dark_mode') ?? false;
  runApp(NotebookApp(initialDarkMode: initialDarkMode));
}

class NotebookApp extends StatefulWidget {
  final bool initialDarkMode;

  const NotebookApp({super.key, this.initialDarkMode = false});

  static void setDarkMode(BuildContext context, bool dark) {
    context.findAncestorStateOfType<_NotebookAppState>()?.toggleDarkMode(dark);
  }

  @override
  State<NotebookApp> createState() => _NotebookAppState();
}

class _NotebookAppState extends State<NotebookApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialDarkMode ? ThemeMode.dark : ThemeMode.light;
  }

  void toggleDarkMode(bool dark) {
    setState(() {
      _themeMode = dark ? ThemeMode.dark : ThemeMode.light;
    });
    SharedPreferences.getInstance().then(
      (preferences) => preferences.setBool('dark_mode', dark),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notebook',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F4FF),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF12121E),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
