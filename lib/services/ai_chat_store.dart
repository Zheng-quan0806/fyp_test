import 'dart:async';
import 'dart:convert';

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
  static const _storageKey = 'ai_chat_store_v1';
  static const _uploadsBucket = 'gpt-uploads';

  final List<AiChatThread> threads = [];
  String? _selectedThreadId;
  bool _thinking = false;
  AiImageAttachment? _pendingImage;
  String _draft = '';
  bool _initialized = false;
  Future<void> _saveQueue = Future<void>.value();
  StreamSubscription<AuthState>? _authSubscription;
  String? _loadedCloudUserId;
  bool _cloudLoadInProgress = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _restoreLocal();

    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        final user = state.session?.user;
        if (user == null || user.isAnonymous) {
          _loadedCloudUserId = null;
          return;
        }
        if (_loadedCloudUserId != user.id) {
          unawaited(syncFromCloud());
        }
      },
    );

    await syncFromCloud();
  }

  Future<void> _restoreLocal() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final restoredThreads = decoded['threads'];
      if (restoredThreads is List) {
        threads
          ..clear()
          ..addAll(
            restoredThreads
                .whereType<Map>()
                .map(_threadFromJson)
                .whereType<AiChatThread>(),
          );
      }

      final restoredSelection = decoded['selectedThreadId'];
      if (restoredSelection is String &&
          threads.any((thread) => thread.id == restoredSelection)) {
        _selectedThreadId = restoredSelection;
      } else if (threads.isNotEmpty) {
        _selectedThreadId = threads.first.id;
      }

      threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (error) {
      debugPrint('Could not restore GPT chats: $error');
      threads.clear();
      _selectedThreadId = null;
    }
  }

  Future<void> syncFromCloud() async {
    final user = _cloudUser;
    if (user == null || _cloudLoadInProgress) return;

    _cloudLoadInProgress = true;
    try {
      final cloudThreads = await _loadCloudThreads(user.id);
      _mergeCloudThreads(cloudThreads);
      _loadedCloudUserId = user.id;

      if (_selectedThreadId == null && threads.isNotEmpty) {
        _selectedThreadId = threads.first.id;
      }
      threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      notifyListeners();

      await _saveLocal();
      await _saveToCloud();
    } catch (error) {
      debugPrint('Could not synchronize GPT chats with Supabase: $error');
    } finally {
      _cloudLoadInProgress = false;
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
    if (user != null) {
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
    await _saveLocal();
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
    _saveQueue = _saveQueue.then((_) async {
      await _saveLocal();
      if (syncCloud) await _saveToCloud();
    }).catchError((Object error) {
      debugPrint('Could not save GPT chats: $error');
    });
  }

  Future<void> _saveLocal() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode({
        'selectedThreadId': _selectedThreadId,
        'threads': threads.map(_threadToJson).toList(),
      }),
    );
  }

  Future<void> _saveToCloud() async {
    final user = _cloudUser;
    if (user == null || threads.isEmpty) return;

    final client = Supabase.instance.client;
    final threadRows = <Map<String, Object?>>[];
    final messageRows = <Map<String, Object?>>[];

    for (final thread in threads) {
      threadRows.add({
        'id': thread.id,
        'user_id': user.id,
        'title': thread.title,
        'updated_at': thread.updatedAt.toUtc().toIso8601String(),
      });

      for (final message in thread.messages) {
        final image = message.image;
        if (image != null && image.storagePath == null) {
          final extension = _extensionForMimeType(image.mimeType);
          final path = '${user.id}/${thread.id}/${message.id}.$extension';
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
          'user_id': user.id,
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

    // Persist any Storage paths that were assigned during this upload.
    await _saveLocal();
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
        .order('created_at');

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

  void _mergeCloudThreads(List<AiChatThread> cloudThreads) {
    for (final cloudThread in cloudThreads) {
      AiChatThread? localThread;
      for (final thread in threads) {
        if (thread.id == cloudThread.id) {
          localThread = thread;
          break;
        }
      }

      if (localThread == null) {
        threads.add(cloudThread);
        continue;
      }

      final messagesById = <String, AiChatMessage>{
        for (final message in localThread.messages) message.id: message,
      };
      for (final cloudMessage in cloudThread.messages) {
        final localMessage = messagesById[cloudMessage.id];
        if (localMessage == null ||
            (localMessage.image?.storagePath == null &&
                cloudMessage.image?.storagePath != null)) {
          messagesById[cloudMessage.id] = cloudMessage;
        }
      }
      localThread.messages
        ..clear()
        ..addAll(messagesById.values)
        ..sort((a, b) => a.time.compareTo(b.time));

      if (cloudThread.updatedAt.isAfter(localThread.updatedAt)) {
        localThread.title = cloudThread.title;
        localThread.updatedAt = cloudThread.updatedAt;
      }
    }
  }

  String _extensionForMimeType(String mimeType) => switch (mimeType) {
        'image/jpeg' => 'jpg',
        'image/webp' => 'webp',
        'image/gif' => 'gif',
        _ => 'png',
      };

  Map<String, Object?> _threadToJson(AiChatThread thread) => {
        'id': thread.id,
        'title': thread.title,
        'updatedAt': thread.updatedAt.toIso8601String(),
        'messages': thread.messages.map(_messageToJson).toList(),
      };

  Map<String, Object?> _messageToJson(AiChatMessage message) => {
        'id': message.id,
        'text': message.text,
        'isUser': message.isUser,
        'time': message.time.toIso8601String(),
        if (message.image != null) 'image': message.image!.toJson(),
      };

  AiChatThread? _threadFromJson(Map<dynamic, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
    final rawMessages = json['messages'];
    if (id is! String || title is! String || updatedAt == null) return null;

    final messages = rawMessages is List
        ? rawMessages
            .whereType<Map>()
            .map(_messageFromJson)
            .whereType<AiChatMessage>()
            .toList()
        : <AiChatMessage>[];

    return AiChatThread(
      id: id,
      title: title,
      messages: messages,
      updatedAt: updatedAt,
    );
  }

  AiChatMessage? _messageFromJson(Map<dynamic, dynamic> json) {
    final id = json['id'];
    final text = json['text'];
    final isUser = json['isUser'];
    final time = DateTime.tryParse(json['time']?.toString() ?? '');
    if (id is! String || text is! String || isUser is! bool || time == null) {
      return null;
    }

    AiImageAttachment? image;
    final rawImage = json['image'];
    if (rawImage is Map) {
      final mimeType = rawImage['mimeType'];
      final data = rawImage['data'];
      final storagePath = rawImage['storagePath'];
      if (mimeType is String && data is String) {
        try {
          image = AiImageAttachment(
            bytes: base64Decode(data),
            mimeType: mimeType,
            storagePath: storagePath is String ? storagePath : null,
          );
        } on FormatException {
          image = null;
        }
      }
    }

    return AiChatMessage(
      id: id,
      text: text,
      isUser: isUser,
      time: time,
      image: image,
    );
  }

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
