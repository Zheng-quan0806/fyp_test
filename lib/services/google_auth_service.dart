import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final ValueNotifier<GoogleAuthUser?> currentUser =
      ValueNotifier<GoogleAuthUser?>(null);

  bool _initialized = false;

  static const String _iosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );
  static const String _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await _googleSignIn.initialize(
        clientId: _iosClientId.isEmpty ? null : _iosClientId,
        serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
      );
      final dynamic account =
          await _googleSignIn.attemptLightweightAuthentication();
      _setUserFromAccount(account);
    } catch (_) {
      currentUser.value = null;
    }
  }

  Future<void> signIn() async {
    await initialize();
    final dynamic account = await _googleSignIn.authenticate();
    _setUserFromAccount(account);
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    currentUser.value = null;
  }

  void _setUserFromAccount(dynamic account) {
    if (account == null) {
      currentUser.value = null;
      return;
    }

    currentUser.value = GoogleAuthUser(
      displayName: (account.displayName as String?) ?? 'Google User',
      email: (account.email as String?) ?? '',
      photoUrl: account.photoUrl as String?,
    );
  }
}
