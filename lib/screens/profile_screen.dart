import 'package:flutter/material.dart';
import '../services/google_auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final GoogleAuthService _auth = GoogleAuthService.instance;
  bool _busy = false;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      await _auth.signIn();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google sign-in failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await _auth.signOut();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign out failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Container(
          height: 64,
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: const Row(
            children: [
              Text(
                'Profile',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
        Expanded(
          child: ValueListenableBuilder<GoogleAuthUser?>(
            valueListenable: _auth.currentUser,
            builder: (context, user, _) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: const Color(0xFFEEEDFE),
                          backgroundImage:
                              user?.photoUrl != null ? NetworkImage(user!.photoUrl!) : null,
                          child: user?.photoUrl == null
                              ? const Icon(
                                  Icons.person,
                                  size: 56,
                                  color: Color(0xFF6C63FF),
                                )
                              : null,
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Color(0xFF6C63FF),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            user == null ? Icons.login : Icons.verified,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user?.displayName ?? 'Guest User',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? 'Sign in with your Google account',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: 260,
                      child: user == null
                          ? FilledButton.icon(
                              onPressed: _busy ? null : _signIn,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.g_mobiledata, size: 24),
                              label: Text(_busy
                                  ? 'Signing in...'
                                  : 'Continue with Google'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF6C63FF),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            )
                          : OutlinedButton.icon(
                              onPressed: _busy ? null : _signOut,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.logout),
                              label: Text(_busy ? 'Signing out...' : 'Sign Out'),
                            ),
                    ),
                    const SizedBox(height: 32),
                    _menuItem(Icons.person_outline, 'Edit Profile', () {}),
                    _menuItem(Icons.notifications_outlined, 'Notifications', () {}),
                    _menuItem(Icons.cloud_outlined, 'Cloud Sync', () {}),
                    _menuItem(Icons.help_outline, 'Help & Support', () {}),
                    _menuItem(
                      user == null ? Icons.lock_outline : Icons.verified_user_outlined,
                      user == null ? 'Login required for synced features' : 'Google account connected',
                      () {},
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _menuItem(IconData icon, String label, VoidCallback onTap,
      {Color? color}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: Icon(icon, color: color ?? const Color(0xFF6C63FF)),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: color ?? Colors.black87,
          ),
        ),
        trailing: color == null
            ? Icon(Icons.chevron_right, color: Colors.grey.shade400)
            : null,
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
