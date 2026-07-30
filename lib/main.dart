import 'package:flutter/material.dart';
import 'services/google_auth_service.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GoogleAuthService.instance.initialize();
  runApp(const NotebookApp());
}

class NotebookApp extends StatefulWidget {
  const NotebookApp({super.key});

  static _NotebookAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_NotebookAppState>();

  @override
  State<NotebookApp> createState() => _NotebookAppState();
}

class _NotebookAppState extends State<NotebookApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void toggleDarkMode(bool dark) =>
      setState(() => _themeMode = dark ? ThemeMode.dark : ThemeMode.light);

  bool get isDark => _themeMode == ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notebook',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6C63FF), brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF5F4FF),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6C63FF), brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF12121E),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
