import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/note.dart';

class NotesService {
  static const _notesKey = 'notes_v2';
  static const _foldersKey = 'folders_v1';
  static const _deletedNotesKey = 'deleted_note_ids_v1';
  static const _deletedFoldersKey = 'deleted_folder_ids_v1';
  static const _noteDataBucket = 'note-data';

  SupabaseClient get _client => Supabase.instance.client;

  User? get _cloudUser {
    final user = _client.auth.currentUser;
    return user == null || user.isAnonymous ? null : user;
  }

  Future<List<Note>> loadNotes() async {
    final localNotes = await _loadLocalNotes();
    final user = _cloudUser;
    if (user == null) return localNotes;

    try {
      final cloud = await _loadCloudNotes(user.id);
      final localDeletedIds = await _loadDeletedIds(_deletedNotesKey);
      final deletedIds = {...cloud.deletedIds, ...localDeletedIds};
      final activeLocal =
          localNotes.where((note) => !deletedIds.contains(note.id)).toList();
      final merged = _mergeNotes(activeLocal, cloud.notes);
      await _saveLocalNotes(merged);

      final hasUnsyncedLocalChanges = activeLocal.any((local) {
        final cloudNote = _findNote(cloud.notes, local.id);
        return cloudNote == null ||
            local.updatedAt.isAfter(cloudNote.updatedAt);
      });
      if (hasUnsyncedLocalChanges || localDeletedIds.isNotEmpty) {
        await _saveCloudNotes(merged, user.id);
        await _clearDeletedIds(_deletedNotesKey);
      }
      return merged;
    } catch (error) {
      debugPrint('Could not load notes from Supabase: $error');
      return localNotes;
    }
  }

  Future<void> saveNotes(List<Note> notes) async {
    await _markChangedNotes(notes);
    await _recordDeletedNotes(notes);
    await _saveLocalNotes(notes);

    final user = _cloudUser;
    if (user == null) return;
    try {
      await _saveCloudNotes(notes, user.id);
      await _clearDeletedIds(_deletedNotesKey);
    } catch (error) {
      debugPrint('Could not save notes to Supabase: $error');
    }
  }

  Future<List<NoteFolder>> loadFolders() async {
    final localFolders = await _loadLocalFolders();
    final user = _cloudUser;
    if (user == null) return localFolders;

    try {
      final rows = await _client
          .from('notebook_folders')
          .select(
            'id, name, color_hex, parent_folder_id, created_at, updated_at, '
            'deleted_at',
          )
          .eq('user_id', user.id)
          .order('created_at');
      final cloudDeletedIds = rows
          .where((row) => row['deleted_at'] != null)
          .map((row) => row['id'] as String)
          .toSet();
      final cloudFolders = rows
          .where((row) => row['deleted_at'] == null)
          .map(
            (row) => NoteFolder(
              id: row['id'] as String,
              name: row['name'] as String,
              colorHex: row['color_hex'] as String,
              parentFolderId: row['parent_folder_id'] as String?,
              createdAt: DateTime.parse(
                row['created_at'] as String,
              ).toLocal(),
              updatedAt: DateTime.parse(
                row['updated_at'] as String,
              ).toLocal(),
            ),
          )
          .toList();
      final localDeletedIds = await _loadDeletedIds(_deletedFoldersKey);
      final deletedIds = {...cloudDeletedIds, ...localDeletedIds};
      final activeLocal = localFolders
          .where((folder) => !deletedIds.contains(folder.id))
          .toList();
      final merged = _mergeFolders(activeLocal, cloudFolders);
      await _saveLocalFolders(merged);

      final hasUnsyncedLocalChanges = activeLocal.any((local) {
        final cloud = _findFolder(cloudFolders, local.id);
        return cloud == null || local.updatedAt.isAfter(cloud.updatedAt);
      });
      if (hasUnsyncedLocalChanges || localDeletedIds.isNotEmpty) {
        await _saveCloudFolders(merged, user.id);
        await _clearDeletedIds(_deletedFoldersKey);
      }
      return merged;
    } catch (error) {
      debugPrint('Could not load folders from Supabase: $error');
      return localFolders;
    }
  }

  Future<void> saveFolders(List<NoteFolder> folders) async {
    await _markChangedFolders(folders);
    await _recordDeletedFolders(folders);
    await _saveLocalFolders(folders);

    final user = _cloudUser;
    if (user == null) return;
    try {
      await _saveCloudFolders(folders, user.id);
      await _clearDeletedIds(_deletedFoldersKey);
    } catch (error) {
      debugPrint('Could not save folders to Supabase: $error');
    }
  }

  Future<List<Note>> _loadLocalNotes() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_notesKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => Note.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveLocalNotes(List<Note> notes) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _notesKey,
      jsonEncode(notes.map((note) => note.toJson()).toList()),
    );
    if (!saved) {
      throw StateError('The device rejected the note data.');
    }
  }

  Future<List<NoteFolder>> _loadLocalFolders() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_foldersKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => NoteFolder.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveLocalFolders(List<NoteFolder> folders) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _foldersKey,
      jsonEncode(folders.map((folder) => folder.toJson()).toList()),
    );
  }

  Future<({List<Note> notes, Set<String> deletedIds})> _loadCloudNotes(
    String userId,
  ) async {
    final rows = await _client
        .from('notebook_notes')
        .select('id, data_path, deleted_at')
        .eq('user_id', userId)
        .order('updated_at', ascending: false);
    final notes = <Note>[];
    final deletedIds = <String>{};

    for (final row in rows) {
      if (row['deleted_at'] != null) {
        deletedIds.add(row['id'] as String);
        continue;
      }
      final path = row['data_path'] as String;
      final bytes = await _client.storage.from(_noteDataBucket).download(path);
      notes.add(Note.fromJsonString(utf8.decode(bytes)));
    }
    return (notes: notes, deletedIds: deletedIds);
  }

  Future<void> _saveCloudNotes(List<Note> notes, String userId) async {
    final rows = <Map<String, Object?>>[];
    for (final note in notes) {
      final path = '$userId/${note.id}.json';
      final bytes = Uint8List.fromList(utf8.encode(note.toJsonString()));
      await _client.storage.from(_noteDataBucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/json',
              upsert: true,
            ),
          );
      rows.add({
        'id': note.id,
        'user_id': userId,
        'title': note.title,
        'folder_id': note.folderId,
        'data_path': path,
        'updated_at': note.updatedAt.toUtc().toIso8601String(),
        'deleted_at': null,
      });
    }

    if (rows.isNotEmpty) {
      await _client.from('notebook_notes').upsert(rows);
    }

    final remoteRows = await _client
        .from('notebook_notes')
        .select('id, data_path, deleted_at')
        .eq('user_id', userId);
    final currentIds = notes.map((note) => note.id).toSet();
    for (final row in remoteRows) {
      final id = row['id'] as String;
      if (currentIds.contains(id)) continue;
      if (row['deleted_at'] == null) {
        await _client.from('notebook_notes').update({
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', id);
        await _client.storage
            .from(_noteDataBucket)
            .remove([row['data_path'] as String]);
      }
    }
  }

  Future<void> _saveCloudFolders(
    List<NoteFolder> folders,
    String userId,
  ) async {
    final rows = folders
        .map(
          (folder) => <String, Object?>{
            'id': folder.id,
            'user_id': userId,
            'name': folder.name,
            'color_hex': folder.colorHex,
            'parent_folder_id': folder.parentFolderId,
            'created_at': folder.createdAt.toUtc().toIso8601String(),
            'updated_at': folder.updatedAt.toUtc().toIso8601String(),
            'deleted_at': null,
          },
        )
        .toList();
    if (rows.isNotEmpty) {
      await _client.from('notebook_folders').upsert(rows);
    }

    final remoteRows = await _client
        .from('notebook_folders')
        .select('id, deleted_at')
        .eq('user_id', userId);
    final currentIds = folders.map((folder) => folder.id).toSet();
    for (final row in remoteRows) {
      final id = row['id'] as String;
      if (!currentIds.contains(id) && row['deleted_at'] == null) {
        await _client.from('notebook_folders').update({
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', id);
      }
    }
  }

  Future<void> _markChangedNotes(List<Note> notes) async {
    final existing = {
      for (final note in await _loadLocalNotes()) note.id: note
    };
    final now = DateTime.now();
    for (final note in notes) {
      final old = existing[note.id];
      if (old == null) continue;
      final oldData = old.toJson()..remove('updatedAt');
      final newData = note.toJson()..remove('updatedAt');
      if (jsonEncode(oldData) != jsonEncode(newData) &&
          !note.updatedAt.isAfter(old.updatedAt)) {
        note.updatedAt = now;
      }
    }
  }

  Future<void> _markChangedFolders(List<NoteFolder> folders) async {
    final existing = {
      for (final folder in await _loadLocalFolders()) folder.id: folder,
    };
    final now = DateTime.now();
    for (final folder in folders) {
      final old = existing[folder.id];
      if (old == null) continue;
      final oldData = old.toJson()..remove('updatedAt');
      final newData = folder.toJson()..remove('updatedAt');
      if (jsonEncode(oldData) != jsonEncode(newData) &&
          !folder.updatedAt.isAfter(old.updatedAt)) {
        folder.updatedAt = now;
      }
    }
  }

  Future<void> _recordDeletedNotes(List<Note> notes) async {
    final previousIds =
        (await _loadLocalNotes()).map((note) => note.id).toSet();
    final currentIds = notes.map((note) => note.id).toSet();
    await _recordDeletedIds(
      _deletedNotesKey,
      previousIds.difference(currentIds),
      currentIds,
    );
  }

  Future<void> _recordDeletedFolders(List<NoteFolder> folders) async {
    final previousIds =
        (await _loadLocalFolders()).map((folder) => folder.id).toSet();
    final currentIds = folders.map((folder) => folder.id).toSet();
    await _recordDeletedIds(
      _deletedFoldersKey,
      previousIds.difference(currentIds),
      currentIds,
    );
  }

  Future<Set<String>> _loadDeletedIds(String key) async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(key) ?? const <String>[]).toSet();
  }

  Future<void> _recordDeletedIds(
    String key,
    Set<String> newlyDeleted,
    Set<String> currentIds,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final deleted = (preferences.getStringList(key) ?? const <String>[]).toSet()
      ..addAll(newlyDeleted)
      ..removeAll(currentIds);
    await preferences.setStringList(key, deleted.toList());
  }

  Future<void> _clearDeletedIds(String key) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(key);
  }

  List<Note> _mergeNotes(List<Note> local, List<Note> cloud) {
    final merged = <String, Note>{for (final note in cloud) note.id: note};
    for (final note in local) {
      final cloudNote = merged[note.id];
      if (cloudNote == null || note.updatedAt.isAfter(cloudNote.updatedAt)) {
        merged[note.id] = note;
      }
    }
    final result = merged.values.toList();
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  List<NoteFolder> _mergeFolders(
    List<NoteFolder> local,
    List<NoteFolder> cloud,
  ) {
    final merged = <String, NoteFolder>{
      for (final folder in cloud) folder.id: folder,
    };
    for (final folder in local) {
      final cloudFolder = merged[folder.id];
      if (cloudFolder == null ||
          folder.updatedAt.isAfter(cloudFolder.updatedAt)) {
        merged[folder.id] = folder;
      }
    }
    final result = merged.values.toList();
    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  Note? _findNote(List<Note> notes, String id) {
    for (final note in notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  NoteFolder? _findFolder(List<NoteFolder> folders, String id) {
    for (final folder in folders) {
      if (folder.id == id) return folder;
    }
    return null;
  }
}
