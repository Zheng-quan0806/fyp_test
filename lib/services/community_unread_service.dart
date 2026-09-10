import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'calendar_reminder_service.dart';
import 'community_chat_service.dart';

/// Tracks unread community messages for this device.
///
/// The latest read message ID is stored per user. This keeps the unread dot
/// accurate after a restart without requiring an additional database table.
class CommunityUnreadService {
  CommunityUnreadService._();

  static final CommunityUnreadService instance = CommunityUnreadService._();

  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);
  final Set<Object> _visibleChatViews = <Object>{};

  StreamSubscription<List<CommunityMessage>>? _messagesSubscription;
  StreamSubscription<AuthState>? _authSubscription;
  Future<void>? _initializing;
  String? _userId;
  int _latestMessageId = 0;
  int _lastReadMessageId = 0;
  int _highestObservedMessageId = 0;
  bool _hasReceivedInitialSnapshot = false;

  bool get isChatVisible => _visibleChatViews.isNotEmpty;

  Future<void> initialize() {
    final current = _initializing;
    if (current != null) return current;
    final operation = _initialize();
    _initializing = operation;
    return operation;
  }

  Future<void> _initialize() async {
    try {
      await _startForCurrentUser();
      _authSubscription ??=
          Supabase.instance.client.auth.onAuthStateChange.listen((event) {
        final nextUserId = event.session?.user.id;
        if (nextUserId != null && nextUserId != _userId) {
          unawaited(_startForCurrentUser());
        }
      });
    } catch (error) {
      debugPrint('Could not initialize community unread messages: $error');
      _initializing = null;
    }
  }

  Future<void> _startForCurrentUser() async {
    final identity = await CommunityChatService.instance.ensureSignedIn();
    await _messagesSubscription?.cancel();

    _userId = identity.userId;
    _latestMessageId = 0;
    _highestObservedMessageId = 0;
    _hasReceivedInitialSnapshot = false;

    final preferences = await SharedPreferences.getInstance();
    final preferenceKey = _preferenceKey(identity.userId);
    final savedLastRead = preferences.getInt(preferenceKey);
    _lastReadMessageId = savedLastRead ?? 0;

    _messagesSubscription =
        CommunityChatService.instance.watchRecentMessages().listen(
      (messages) => _handleMessages(
        messages,
        hasSavedReadPosition: savedLastRead != null,
      ),
      onError: (Object error) {
        debugPrint('Could not watch community unread messages: $error');
      },
    );
  }

  void _handleMessages(
    List<CommunityMessage> messages, {
    required bool hasSavedReadPosition,
  }) {
    if (messages.isEmpty) {
      _hasReceivedInitialSnapshot = true;
      return;
    }

    final latestId = messages.fold<int>(
      0,
      (current, message) => message.id > current ? message.id : current,
    );
    _latestMessageId = latestId;

    if (!_hasReceivedInitialSnapshot) {
      _hasReceivedInitialSnapshot = true;
      _highestObservedMessageId = latestId;

      if (!hasSavedReadPosition) {
        _lastReadMessageId = latestId;
        unawaited(_saveLastRead());
      }

      if (isChatVisible) {
        unawaited(markAllRead());
      } else {
        _updateUnreadCount(messages);
      }
      return;
    }

    final newMessages = messages
        .where((message) => message.id > _highestObservedMessageId)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    _highestObservedMessageId = latestId > _highestObservedMessageId
        ? latestId
        : _highestObservedMessageId;

    if (isChatVisible) {
      unawaited(markAllRead());
      return;
    }

    _updateUnreadCount(messages);
    final myUserId = _userId;
    for (final message in newMessages) {
      if (message.senderId == myUserId) continue;
      unawaited(
        CalendarReminderService.instance.showCommunityMessage(
          messageId: message.id,
          body: message.body,
        ),
      );
    }
  }

  void _updateUnreadCount(List<CommunityMessage> messages) {
    final myUserId = _userId;
    unreadCount.value = messages
        .where(
          (message) =>
              message.id > _lastReadMessageId && message.senderId != myUserId,
        )
        .length;
  }

  void setChatVisible(Object viewToken, bool visible) {
    if (visible) {
      _visibleChatViews.add(viewToken);
      unawaited(markAllRead());
    } else {
      _visibleChatViews.remove(viewToken);
    }
  }

  Future<void> markAllRead() async {
    if (_latestMessageId > _lastReadMessageId) {
      _lastReadMessageId = _latestMessageId;
      await _saveLastRead();
    }
    unreadCount.value = 0;
  }

  Future<void> _saveLastRead() async {
    final userId = _userId;
    if (userId == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(
      _preferenceKey(userId),
      _lastReadMessageId,
    );
  }

  String _preferenceKey(String userId) =>
      'community_last_read_message_id_$userId';
}
