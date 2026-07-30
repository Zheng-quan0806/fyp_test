import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';

class NotesService {
  static const _notesKey   = 'notes_v2';
  static const _foldersKey = 'folders_v1';

  // ── Notes ─────────────────────────────────────────────────────────────
  Future<List<Note>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_notesKey);
    if (raw == null) return [];
    final List decoded = jsonDecode(raw);
    return decoded.map((e) => Note.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveNotes(List<Note> notes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _notesKey, jsonEncode(notes.map((n) => n.toJson()).toList()));
  }

  // ── Folders ───────────────────────────────────────────────────────────
  Future<List<NoteFolder>> loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_foldersKey);
    if (raw == null) return [];
    final List decoded = jsonDecode(raw);
    return decoded
        .map((e) => NoteFolder.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveFolders(List<NoteFolder> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _foldersKey, jsonEncode(folders.map((f) => f.toJson()).toList()));
  }
}