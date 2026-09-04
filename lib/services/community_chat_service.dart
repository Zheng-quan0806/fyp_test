import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class CommunityIdentity {
  final String userId;
  final String displayName;
  final String username;

  const CommunityIdentity({
    required this.userId,
    required this.displayName,
    required this.username,
  });
}

class CommunityProfile {
  final String id;
  final String displayName;
  final String username;

  const CommunityProfile({
    required this.id,
    required this.displayName,
    required this.username,
  });

  factory CommunityProfile.fromJson(Map<String, dynamic> json) {
    return CommunityProfile(
      id: json['id'] as String,
      displayName: json['display_name'] as String,
      username: json['username'] as String,
    );
  }
}

class CommunityFriendship {
  final String id;
  final String requesterId;
  final String addresseeId;
  final String status;
  final DateTime createdAt;

  const CommunityFriendship({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    required this.status,
    required this.createdAt,
  });

  factory CommunityFriendship.fromJson(Map<String, dynamic> json) {
    return CommunityFriendship(
      id: json['id'] as String,
      requesterId: json['requester_id'] as String,
      addresseeId: json['addressee_id'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  bool involves(String userId) =>
      requesterId == userId || addresseeId == userId;

  String otherUserId(String userId) =>
      requesterId == userId ? addresseeId : requesterId;
}

class CommunityRoom {
  final String id;
  final String name;
  final String type;
  final String? createdBy;
  final List<String> memberIds;

  const CommunityRoom({
    required this.id,
    required this.name,
    required this.type,
    required this.createdBy,
    required this.memberIds,
  });

  factory CommunityRoom.fromJson(
    Map<String, dynamic> json, {
    List<String> memberIds = const [],
  }) {
    return CommunityRoom(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['room_type'] as String? ?? 'public',
      createdBy: json['created_by'] as String?,
      memberIds: memberIds,
    );
  }

  bool get isDirect => type == 'direct';
  bool get isGroup => type == 'group';
}

class CommunityMessage {
  final int id;
  final String roomId;
  final String senderId;
  final String body;
  final DateTime createdAt;
  final String? attachmentPath;
  final String? attachmentName;
  final String? attachmentMimeType;

  const CommunityMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.attachmentPath,
    this.attachmentName,
    this.attachmentMimeType,
  });

  factory CommunityMessage.fromJson(Map<String, dynamic> json) {
    return CommunityMessage(
      id: json['id'] as int,
      roomId: json['room_id'] as String,
      senderId: json['sender_id'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      attachmentPath: json['attachment_path'] as String?,
      attachmentName: json['attachment_name'] as String?,
      attachmentMimeType: json['attachment_mime_type'] as String?,
    );
  }

  bool get hasAttachment =>
      attachmentPath != null && attachmentPath!.trim().isNotEmpty;
}

class CommunityUpload {
  final String path;
  final String name;
  final String mimeType;

  const CommunityUpload({
    required this.path,
    required this.name,
    required this.mimeType,
  });
}

class CommunityChatService {
  CommunityChatService._();

  static final CommunityChatService instance = CommunityChatService._();
  static const String uploadsBucket = 'community-uploads';

  SupabaseClient get _client => Supabase.instance.client;
  Future<CommunityIdentity>? _initializing;

  Future<CommunityIdentity> ensureSignedIn() async {
    final currentAttempt = _initializing;
    if (currentAttempt != null) {
      final identity = await currentAttempt;
      if (_client.auth.currentUser?.id == identity.userId) return identity;
      _initializing = null;
    }

    final attempt = _ensureSignedIn();
    _initializing = attempt;
    try {
      return await attempt;
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  Future<CommunityIdentity> _ensureSignedIn() async {
    if (_client.auth.currentSession == null) {
      await _client.auth.signInAnonymously();
    }

    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Supabase could not create a community user.');
    }

    final existing = await _client
        .from('community_profiles')
        .select('display_name, username')
        .eq('id', user.id)
        .maybeSingle();

    var displayName = existing?['display_name'] as String?;
    var username = existing?['username'] as String?;
    if (displayName == null || displayName.trim().isEmpty) {
      final metadata = user.userMetadata ?? const <String, dynamic>{};
      final accountName =
          metadata['full_name'] as String? ?? metadata['name'] as String?;
      displayName = accountName?.trim().isNotEmpty == true
          ? accountName!.trim()
          : 'Guest-${user.id.substring(0, 4).toUpperCase()}';
    }

    username = username?.trim().isNotEmpty == true
        ? username!.trim().toLowerCase()
        : 'user_${user.id.replaceAll('-', '').substring(0, 8)}';
    await _client.from('community_profiles').upsert({
      'id': user.id,
      'display_name': displayName,
      'username': username,
    });

    return CommunityIdentity(
      userId: user.id,
      displayName: displayName,
      username: username,
    );
  }

  Future<List<CommunityRoom>> loadRooms() async {
    final identity = await ensureSignedIn();
    final roomRows = await _client
        .from('community_rooms')
        .select('id, name, room_type, created_by, created_at')
        .order('created_at', ascending: false);
    var hiddenRoomIds = <String>{};
    try {
      final hiddenRows = await _client
          .from('community_hidden_rooms')
          .select('room_id')
          .eq('user_id', identity.userId);
      hiddenRoomIds = hiddenRows.map((row) => row['room_id'] as String).toSet();
    } on PostgrestException catch (error) {
      if (!_isMissingHiddenRoomsTable(error)) rethrow;
    }
    final memberRows =
        await _client.from('community_room_members').select('room_id, user_id');
    final membersByRoom = <String, List<String>>{};
    for (final row in memberRows) {
      final roomId = row['room_id'] as String;
      membersByRoom.putIfAbsent(roomId, () => []).add(
            row['user_id'] as String,
          );
    }
    return roomRows
        .where((row) => !hiddenRoomIds.contains(row['id']))
        .map(
          (row) => CommunityRoom.fromJson(
            row,
            memberIds: membersByRoom[row['id']] ?? const <String>[],
          ),
        )
        .toList();
  }

  Future<CommunityRoom> createDirectChat(String otherUserId) async {
    final identity = await ensureSignedIn();
    if (otherUserId == identity.userId) {
      throw ArgumentError('Choose another person for a private chat.');
    }
    final result = await _client.rpc(
      'create_direct_chat',
      params: {'other_user_id': otherUserId},
    );
    final roomId = result.toString();
    await _unhideRoom(roomId, identity.userId);
    final rooms = await loadRooms();
    return rooms.firstWhere((room) => room.id == roomId);
  }

  Future<CommunityRoom> createGroupChat({
    required String name,
    required List<String> memberIds,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw ArgumentError('Enter a group name.');
    if (memberIds.isEmpty) {
      throw ArgumentError('Select at least one group member.');
    }
    await ensureSignedIn();
    final result = await _client.rpc(
      'create_group_chat',
      params: {
        'group_name': trimmedName,
        'member_ids': memberIds,
      },
    );
    final roomId = result.toString();
    final rooms = await loadRooms();
    return rooms.firstWhere((room) => room.id == roomId);
  }

  Future<void> hideRoom(String roomId) async {
    final identity = await ensureSignedIn();
    try {
      await _client.from('community_hidden_rooms').upsert({
        'user_id': identity.userId,
        'room_id': roomId,
        'hidden_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on PostgrestException catch (error) {
      if (!_isMissingHiddenRoomsTable(error)) rethrow;
      throw StateError(
        'Run supabase/community_chat_deletion.sql in the Supabase SQL Editor first.',
      );
    }
  }

  Future<void> _unhideRoom(String roomId, String userId) async {
    try {
      await _client
          .from('community_hidden_rooms')
          .delete()
          .eq('user_id', userId)
          .eq('room_id', roomId);
    } on PostgrestException catch (error) {
      if (!_isMissingHiddenRoomsTable(error)) rethrow;
    }
  }

  bool _isMissingHiddenRoomsTable(PostgrestException error) =>
      error.code == '42P01' || error.code == 'PGRST205';

  Stream<List<CommunityProfile>> watchProfiles() {
    return _client
        .from('community_profiles')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map((rows) => rows.map(CommunityProfile.fromJson).toList());
  }

  Future<List<CommunityFriendship>> loadFriendships() async {
    await ensureSignedIn();
    final rows = await _client
        .from('community_friendships')
        .select()
        .order('created_at', ascending: false);
    return rows.map(CommunityFriendship.fromJson).toList();
  }

  Stream<List<CommunityFriendship>> watchFriendships() {
    return _client
        .from('community_friendships')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(CommunityFriendship.fromJson).toList());
  }

  Future<List<CommunityProfile>> searchProfiles(String query) async {
    await ensureSignedIn();
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <CommunityProfile>[];
    final rows = await _client.rpc(
      'search_community_profiles',
      params: {'search_text': trimmed},
    );
    return (rows as List)
        .map((row) => CommunityProfile.fromJson(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList();
  }

  Future<void> sendFriendRequest(String userId) async {
    await ensureSignedIn();
    await _client.rpc(
      'send_community_friend_request',
      params: {'other_user_id': userId},
    );
  }

  Future<void> respondToFriendRequest({
    required String friendshipId,
    required bool accept,
  }) async {
    await ensureSignedIn();
    await _client.rpc(
      'respond_community_friend_request',
      params: {'friendship_id': friendshipId, 'accept_request': accept},
    );
  }

  Future<void> removeFriendship(String friendshipId) async {
    await ensureSignedIn();
    await _client.rpc(
      'remove_community_friendship',
      params: {'friendship_id': friendshipId},
    );
  }

  Future<String> updateUsername(String value) async {
    await ensureSignedIn();
    final result = await _client.rpc(
      'set_community_username',
      params: {'new_username': value.trim().toLowerCase()},
    );
    _initializing = null;
    return result.toString();
  }

  Stream<List<CommunityMessage>> watchMessages(String roomId) {
    return _client
        .from('community_messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('created_at', ascending: true)
        .limit(200)
        .map((rows) {
          final messages = rows.map(CommunityMessage.fromJson).toList();
          messages.sort((a, b) {
            final timeResult = a.createdAt.compareTo(b.createdAt);
            return timeResult != 0 ? timeResult : a.id.compareTo(b.id);
          });
          return messages;
        });
  }

  Future<void> sendMessage({
    required String roomId,
    required String body,
    CommunityUpload? attachment,
  }) async {
    var text = body.trim();
    if (text.isEmpty && attachment == null) return;
    if (text.isEmpty) text = 'Shared an image.';

    await ensureSignedIn();
    await _client.from('community_messages').insert({
      'room_id': roomId,
      'body': text,
      if (attachment != null) ...{
        'attachment_path': attachment.path,
        'attachment_name': attachment.name,
        'attachment_mime_type': attachment.mimeType,
      },
    });
  }

  Future<CommunityUpload> uploadImage({
    required String roomId,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final identity = await ensureSignedIn();
    final extension = switch (mimeType) {
      'image/jpeg' => 'jpg',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      _ => 'png',
    };
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final name = 'community-image-$stamp.$extension';
    final path = '${identity.userId}/$roomId/$name';

    await _client.storage.from(uploadsBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: mimeType,
            upsert: false,
          ),
        );

    return CommunityUpload(path: path, name: name, mimeType: mimeType);
  }

  Future<String> createAttachmentUrl(String path) {
    return _client.storage.from(uploadsBucket).createSignedUrl(path, 3600);
  }

  Future<void> deleteUpload(String path) async {
    await _client.storage.from(uploadsBucket).remove([path]);
  }
}
