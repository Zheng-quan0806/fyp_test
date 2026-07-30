import 'package:flutter/material.dart';
import '../main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoSave = true;
  bool _cloudSync = false;
  String _defaultPaper = 'Lined';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Settings',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _section('Appearance', [
            // ── Dark Mode: reads live ThemeMode, calls toggleDarkMode ──
            SwitchListTile(
              secondary: const Icon(Icons.dark_mode_outlined,
                  color: Color(0xFF6C63FF)),
              title: const Text('Dark Mode'),
              value: isDark,
              activeColor: const Color(0xFF6C63FF),
              onChanged: (v) =>
                  NotebookApp.of(context)?.toggleDarkMode(v),
            ),
          ]),
          _section('Editor', [
            _toggle('Auto Save', Icons.save_outlined,
                _autoSave, (v) => setState(() => _autoSave = v)),
            _picker('Default Paper', Icons.article_outlined, _defaultPaper,
                ['Blank', 'Lined', 'Grid', 'Two Column', 'Dotted'],
                (v) => setState(() => _defaultPaper = v)),
          ]),
          _section('Sync', [
            _toggle('Cloud Sync', Icons.cloud_outlined,
                _cloudSync, (v) => setState(() => _cloudSync = v)),
          ]),
          _section('About', [
            _info('Version', '1.0.0'),
            _info('Developer', 'FYP Project — UTAR'),
          ]),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> items) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 16),
        child: Text(title,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: Color(0xFF6C63FF))),
      ),
      Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(children: items),
      ),
    ]);
  }

  Widget _toggle(String label, IconData icon, bool value,
      ValueChanged<bool> onChanged) {
    return SwitchListTile(
      secondary: Icon(icon, color: const Color(0xFF6C63FF)),
      title: Text(label),
      value: value,
      activeColor: const Color(0xFF6C63FF),
      onChanged: onChanged,
    );
  }

  Widget _picker(String label, IconData icon, String current,
      List<String> options, ValueChanged<String> onChanged) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF6C63FF)),
      title: Text(label),
      trailing: DropdownButton<String>(
        value: current,
        underline: const SizedBox(),
        items: options
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
      ),
    );
  }

  Widget _info(String label, String value) {
    return ListTile(
      title: Text(label),
      trailing: Text(value, style: TextStyle(color: Colors.grey.shade500)),
    );
  }
}