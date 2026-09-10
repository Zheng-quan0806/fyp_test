import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai_service.dart';

class AiChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime time;
  final AiImageAttachment? image;

  const AiChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.time,
    this.image,
  });
}

class AiChatThread {
  final String id;
  String title;
  final List<AiChatMessage> messages;
  DateTime updatedAt;

  AiChatThread({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
  });
}

class AiChatStore extends ChangeNotifier {
  AiChatStore._();

  static final AiChatStore instance = AiChatStore._();
  static const _legacyStorageKey = 'ai_chat_store_v1';
  static const _oldStorageKeyPrefix = 'ai_chat_store_v2';
  static const _uploadsBucket = 'gpt-uploads';

  final List<AiChatThread> threads = [];
  String? _selectedThreadId;
  bool _thinking = false;
  AiImageAttachment? _pendingImage;
  String _draft = '';
  bool _initialized = false;
  Future<void> _saveQueue = Future<void>.value();
  Future<void> _authSwitchQueue = Future<void>.value();
  Future<void> _cloudSyncQueue = Future<void>.value();
  StreamSubscription<AuthState>? _authSubscription;
  String? _activeUserId;
  int _accountGeneration = 0;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _removeOldLocalHistory();
    _activeUserId = _cloudUser?.id;

    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        _authSwitchQueue = _authSwitchQueue
            .then((_) => _switchAccount(state.session?.user))
            .catchError((Object error) {
          debugPrint('Could not switch GPT chat account: $error');
        });
      },
    );

    await syncFromCloud();
  }

  String? _accountId(User? user) =>
      user == null || user.isAnonymous ? null : user.id;

  Future<void> _removeOldLocalHistory() async {
    final preferences = await SharedPreferences.getInstance();
    final oldKeys = preferences.getKeys().where(
          (key) =>
              key == _legacyStorageKey || key.startsWith(_oldStorageKeyPrefix),
        );
    for (final key in oldKeys.toList()) {
      await preferences.remove(key);
    }
  }

  Future<void> _switchAccount(User? user) async {
    final nextUserId = _accountId(user);
    if (nextUserId == _activeUserId) return;

    // Finish writes for the previous account before replacing the in-memory
    // conversation list. Cloud writes also verify the current Supabase user.
    await _saveQueue;

    _activeUserId = nextUserId;
    _accountGeneration++;
    _thinking = false;
    _pendingImage = null;
    _draft = '';
    threads.clear();
    _selectedThreadId = null;
    notifyListeners();

    if (nextUserId != null) {
      await syncFromCloud();
    }
  }

  Future<void> syncFromCloud() async {
    final user = _cloudUser;
    if (user == null || user.id != _activeUserId) return;

    final userId = user.id;
    _cloudSyncQueue = _cloudSyncQueue.then(
      (_) => _syncFromCloudFor(userId),
    );
    await _cloudSyncQueue;
  }

  Future<void> _syncFromCloudFor(String userId) async {
    if (_activeUserId != userId || _cloudUser?.id != userId) return;

    try {
      final cloudThreads = await _loadCloudThreads(userId);
      if (_activeUserId != userId || _cloudUser?.id != userId) return;

      threads
        ..clear()
        ..addAll(cloudThreads);

      if (_selectedThreadId == null && threads.isNotEmpty) {
        _selectedThreadId = threads.first.id;
      }
      threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      notifyListeners();

      await _saveToCloud(userId);
    } catch (error) {
      debugPrint('Could not synchronize GPT chats with Supabase: $error');
    }
  }

  User? get _cloudUser {
    final user = Supabase.instance.client.auth.currentUser;
    return user == null || user.isAnonymous ? null : user;
  }

  AiChatThread? get selectedThread {
    final selectedId = _selectedThreadId;
    if (selectedId == null) return null;
    for (final thread in threads) {
      if (thread.id == selectedId) return thread;
    }
    return null;
  }

  List<AiChatMessage> get messages =>
      selectedThread?.messages ?? const <AiChatMessage>[];

  bool get thinking => _thinking;
  AiImageAttachment? get pendingImage => _pendingImage;
  String get draft => _draft;

  void newChat() {
    final now = DateTime.now();
    final thread = AiChatThread(
      id: now.microsecondsSinceEpoch.toString(),
      title: 'New chat',
      updatedAt: now,
      messages: [],
    );
    threads.insert(0, thread);
    _selectedThreadId = thread.id;
    _pendingImage = null;
    _draft = '';
    notifyListeners();
    _queueSave();
  }

  void selectThread(AiChatThread thread) {
    if (_selectedThreadId == thread.id) return;
    _selectedThreadId = thread.id;
    _pendingImage = null;
    _draft = '';
    notifyListeners();
    _queueSave(syncCloud: false);
  }

  Future<void> deleteThread(AiChatThread thread) async {
    final index = threads.indexWhere((item) => item.id == thread.id);
    if (index < 0) return;

    // Wait for older queued saves first. Otherwise an older upsert could recreate
    // the conversation immediately after it is deleted from Supabase.
    await _saveQueue;

    final user = _cloudUser;
    if (user != null && user.id == _activeUserId) {
      final client = Supabase.instance.client;
      await client
          .from('gpt_chat_threads')
          .delete()
          .eq('id', thread.id)
          .eq('user_id', user.id);

      final imagePaths = thread.messages
          .map((message) => message.image?.storagePath)
          .whereType<String>()
          .toSet()
          .toList();
      if (imagePaths.isNotEmpty) {
        try {
          await client.storage.from(_uploadsBucket).remove(imagePaths);
        } catch (error) {
          // The conversation is already deleted. An orphaned image should not
          // make the history reappear or make deletion look unsuccessful.
          debugPrint('Could not remove deleted GPT images: $error');
        }
      }
    }

    final deletingSelectedThread = _selectedThreadId == thread.id;
    threads.removeAt(index);
    if (deletingSelectedThread) {
      _selectedThreadId = threads.isEmpty ? null : threads.first.id;
      _pendingImage = null;
      _draft = '';
    }
    notifyListeners();
  }

  void updateDraft(String value) {
    if (_draft == value) return;
    _draft = value;
    notifyListeners();
  }

  void attachImage(AiImageAttachment image) {
    _pendingImage = image;
    notifyListeners();
  }

  void removePendingImage() {
    if (_pendingImage == null) return;
    _pendingImage = null;
    notifyListeners();
  }

  Future<void> send(String rawText) async {
    final thread = selectedThread;
    final image = _pendingImage;
    final text = rawText.trim();
    if ((text.isEmpty && image == null) || thread == null || _thinking) return;

    final prompt = text.isEmpty ? 'Please explain this image.' : text;
    final accountGeneration = _accountGeneration;
    final now = DateTime.now();
    thread.messages.add(
      AiChatMessage(
        id: 'u-${now.microsecondsSinceEpoch}',
        text: prompt,
        isUser: true,
        time: now,
        image: image,
      ),
    );
    thread.updatedAt = now;
    if (thread.title == 'New chat') {
      thread.title = _titleFromPrompt(prompt);
    }
    _pendingImage = null;
    _draft = '';
    _thinking = true;
    notifyListeners();
    _queueSave();

    String replyText;
    try {
      replyText = await AiService.instance.sendMessages(
        thread.messages.map(
          (message) => AiRequestMessage(
            role: message.isUser ? 'user' : 'assistant',
            content: message.text,
            image: message.image,
          ),
        ),
      );
    } on AiServiceException catch (error) {
      replyText = 'Sorry, ${error.message}';
    }

    // Do not place a reply from an old session into a newly selected account.
    if (accountGeneration != _accountGeneration) return;

    final replyTime = DateTime.now();
    thread.messages.add(
      AiChatMessage(
        id: 'a-${replyTime.microsecondsSinceEpoch}',
        text: replyText,
        isUser: false,
        time: replyTime,
      ),
    );
    thread.updatedAt = replyTime;
    _thinking = false;
    threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notifyListeners();
    _queueSave();
  }

  void _queueSave({bool syncCloud = true}) {
    if (!_initialized) return;
    final targetUserId = _activeUserId;
    if (!syncCloud || targetUserId == null) return;

    _saveQueue = _saveQueue.then((_) async {
      if (targetUserId != _activeUserId) return;
      await _saveToCloud(targetUserId);
    }).catchError((Object error) {
      debugPrint('Could not save GPT chats: $error');
    });
  }

  Future<void> flushCloudWrites() => _saveQueue;

  Future<void> _saveToCloud(String userId) async {
    final currentUser = _cloudUser;
    if (currentUser?.id != userId ||
        _activeUserId != userId ||
        threads.isEmpty) {
      return;
    }

    final client = Supabase.instance.client;
    final threadRows = <Map<String, Object?>>[];
    final messageRows = <Map<String, Object?>>[];

    for (final thread in threads) {
      threadRows.add({
        'id': thread.id,
        'user_id': userId,
        'title': thread.title,
        'updated_at': thread.updatedAt.toUtc().toIso8601String(),
      });

      for (final message in thread.messages) {
        final image = message.image;
        if (image != null && image.storagePath == null) {
          final extension = _extensionForMimeType(image.mimeType);
          final path = '$userId/${thread.id}/${message.id}.$extension';
          await client.storage.from(_uploadsBucket).uploadBinary(
                path,
                image.bytes,
                fileOptions: FileOptions(
                  contentType: image.mimeType,
                  upsert: true,
                ),
              );
          image.storagePath = path;
        }

        messageRows.add({
          'id': message.id,
          'thread_id': thread.id,
          'user_id': userId,
          'content': message.text,
          'is_user': message.isUser,
          'created_at': message.time.toUtc().toIso8601String(),
          'image_path': image?.storagePath,
          'image_mime_type': image?.mimeType,
        });
      }
    }

    await client.from('gpt_chat_threads').upsert(threadRows);
    if (messageRows.isNotEmpty) {
      await client.from('gpt_chat_messages').upsert(messageRows);
    }
  }

  Future<List<AiChatThread>> _loadCloudThreads(String userId) async {
    final client = Supabase.instance.client;
    final rawThreads = await client
        .from('gpt_chat_threads')
        .select('id, title, updated_at')
        .eq('user_id', userId)
        .order('updated_at', ascending: false);
    final rawMessages = await client
        .from('gpt_chat_messages')
        .select(
          'id, thread_id, content, is_user, created_at, '
          'image_path, image_mime_type',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: true);

    final messagesByThread = <String, List<AiChatMessage>>{};
    for (final row in rawMessages) {
      final threadId = row['thread_id'] as String?;
      final id = row['id'] as String?;
      final text = row['content'] as String?;
      final isUser = row['is_user'] as bool?;
      final time = DateTime.tryParse(row['created_at']?.toString() ?? '');
      if (threadId == null ||
          id == null ||
          text == null ||
          isUser == null ||
          time == null) {
        continue;
      }

      AiImageAttachment? image;
      final imagePath = row['image_path'] as String?;
      final mimeType = row['image_mime_type'] as String?;
      if (imagePath != null && mimeType != null) {
        try {
          final bytes =
              await client.storage.from(_uploadsBucket).download(imagePath);
          image = AiImageAttachment(
            bytes: bytes,
            mimeType: mimeType,
            storagePath: imagePath,
          );
        } catch (error) {
          debugPrint('Could not download GPT image $imagePath: $error');
        }
      }

      messagesByThread.putIfAbsent(threadId, () => []).add(
            AiChatMessage(
              id: id,
              text: text,
              isUser: isUser,
              time: time.toLocal(),
              image: image,
            ),
          );
    }

    return rawThreads.map((row) {
      final id = row['id'] as String;
      final updatedAt = DateTime.parse(row['updated_at'] as String).toLocal();
      return AiChatThread(
        id: id,
        title: row['title'] as String,
        messages: messagesByThread[id] ?? <AiChatMessage>[],
        updatedAt: updatedAt,
      );
    }).toList();
  }

  String _extensionForMimeType(String mimeType) => switch (mimeType) {
        'image/jpeg' => 'jpg',
        'image/webp' => 'webp',
        'image/gif' => 'gif',
        _ => 'png',
      };

  String _titleFromPrompt(String text) {
    final words = text
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .take(4)
        .toList();
    return words.isEmpty ? 'New chat' : words.join(' ');
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
