import 'package:flutter/material.dart';

import '../main.dart';
import '../services/google_auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final GoogleAuthService _auth = GoogleAuthService.instance;
  bool _autoSave = true;
  bool _accountBusy = false;
  String _defaultPaper = 'Lined';

  Future<void> _signIn() async {
    setState(() => _accountBusy = true);
    try {
      await _auth.signIn();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google sign-in failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _accountBusy = true);
    try {
      await _auth.signOut();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign out failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

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
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ValueListenableBuilder<GoogleAuthUser?>(
            valueListenable: _auth.currentUser,
            builder: (context, user, _) => _accountSection(user),
          ),
          _section('Theme', [
            SwitchListTile(
              secondary: const Icon(
                Icons.dark_mode_outlined,
                color: Color(0xFF6C63FF),
              ),
              title: const Text('Dark Mode'),
              subtitle: const Text('Remembered on this device'),
              value: isDark,
              activeThumbColor: const Color(0xFF6C63FF),
              onChanged: (value) => NotebookApp.setDarkMode(context, value),
            ),
          ]),
          _section('Editor', [
            _toggle(
              'Auto Save',
              Icons.save_outlined,
              _autoSave,
              (value) => setState(() => _autoSave = value),
            ),
            _picker(
              'Default Paper',
              Icons.article_outlined,
              _defaultPaper,
              ['Blank', 'Lined', 'Grid', 'Two Column', 'Dotted'],
              (value) => setState(() => _defaultPaper = value),
            ),
          ]),
          _section('About', [
            _info('Version', '1.0.0'),
          ]),
        ],
      ),
    );
  }

  Widget _accountSection(GoogleAuthUser? user) {
    return _section('Account', [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 27,
              backgroundColor: const Color(0xFFEEEDFE),
              backgroundImage:
                  user?.photoUrl == null ? null : NetworkImage(user!.photoUrl!),
              child: user?.photoUrl == null
                  ? const Icon(
                      Icons.person,
                      color: Color(0xFF6C63FF),
                      size: 30,
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.displayName ?? 'Guest User',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user?.email ?? 'Sign in to sync between your devices',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  if (user != null) ...[
                    const SizedBox(height: 3),
                    const Text(
                      'Supabase sync is automatic',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF10A37F),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (_accountBusy)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (user == null)
              FilledButton.icon(
                onPressed: _signIn,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Sign in'),
              )
            else
              OutlinedButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Sign out'),
              ),
          ],
        ),
      ),
    ]);
  }

  Widget _section(String title, List<Widget> items) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8, top: 16),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6C63FF),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.grey.shade200,
            ),
          ),
          child: Column(children: items),
        ),
      ],
    );
  }

  Widget _toggle(
    String label,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      secondary: Icon(icon, color: const Color(0xFF6C63FF)),
      title: Text(label),
      value: value,
      activeThumbColor: const Color(0xFF6C63FF),
      onChanged: onChanged,
    );
  }

  Widget _picker(
    String label,
    IconData icon,
    String current,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF6C63FF)),
      title: Text(label),
      trailing: DropdownButton<String>(
        value: current,
        underline: const SizedBox(),
        items: options
            .map((option) => DropdownMenuItem(
                  value: option,
                  child: Text(option),
                ))
            .toList(),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }

  Widget _info(String label, String value) {
    return ListTile(
      title: Text(label),
      trailing: Text(
        value,
        style: TextStyle(color: Colors.grey.shade500),
      ),
    );
  }
}
