import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GoogleAuthUser {
  final String displayName;
  final String email;
  final String? photoUrl;

  const GoogleAuthUser({
    required this.displayName,
    required this.email,
    required this.photoUrl,
  });
}

class GoogleAuthService {
  GoogleAuthService._();

  static final GoogleAuthService instance = GoogleAuthService._();

  static const String callbackUrl = 'notebooktutor://login-callback/';

  final ValueNotifier<GoogleAuthUser?> currentUser =
      ValueNotifier<GoogleAuthUser?>(null);

  StreamSubscription<AuthState>? _authSubscription;
  bool _initialized = false;

  bool get isSupported => true;

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _setUser(_client.auth.currentUser);
    _authSubscription = _client.auth.onAuthStateChange.listen(
      (state) => _setUser(state.session?.user),
    );
  }

  Future<void> signIn() async {
    await initialize();
    final opened = await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : callbackUrl,
      authScreenLaunchMode:
          kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
    if (!opened) {
      throw StateError('The Google sign-in page could not be opened.');
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    currentUser.value = null;
  }

  void _setUser(User? user) {
    if (user == null || user.isAnonymous) {
      currentUser.value = null;
      return;
    }

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final displayName =
        metadata['full_name'] as String? ?? metadata['name'] as String?;
    final photoUrl =
        metadata['avatar_url'] as String? ?? metadata['picture'] as String?;

    currentUser.value = GoogleAuthUser(
      displayName: displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : 'Google User',
      email: user.email ?? '',
      photoUrl: photoUrl,
    );
  }

  void dispose() {
    _authSubscription?.cancel();
    currentUser.dispose();
  }
}
