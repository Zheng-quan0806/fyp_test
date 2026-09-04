import 'dart:convert';
import 'dart:ui';

// ── Paper style ───────────────────────────────────────────────────────────
enum PaperStyle { blank, lined, grid, twoColumn, dotted }

extension PaperStyleExt on PaperStyle {
  String get label {
    switch (this) {
      case PaperStyle.blank:
        return 'Blank';
      case PaperStyle.lined:
        return 'Lined';
      case PaperStyle.grid:
        return 'Grid';
      case PaperStyle.twoColumn:
        return 'Two Column';
      case PaperStyle.dotted:
        return 'Dotted';
    }
  }

  String get toJson => name;
  static PaperStyle fromJson(String s) => PaperStyle.values
      .firstWhere((e) => e.name == s, orElse: () => PaperStyle.lined);
}

// ── Drawn point ───────────────────────────────────────────────────────────
class DrawnPoint {
  final Offset? point;
  final Color color;
  final double strokeWidth;

  DrawnPoint({this.point, required this.color, required this.strokeWidth});

  Map<String, dynamic> toJson() => {
        'x': point?.dx,
        'y': point?.dy,
        'color': color.toARGB32(),
        'sw': strokeWidth,
      };

  factory DrawnPoint.fromJson(Map<String, dynamic> j) => DrawnPoint(
        point: j['x'] != null ? Offset(j['x'], j['y']) : null,
        color: Color(j['color']),
        strokeWidth: (j['sw'] ?? j['strokeWidth'] ?? 3.0).toDouble(),
      );
}

// ── Single page ───────────────────────────────────────────────────────────
class NotePage {
  final String id;
  List<DrawnPoint> strokes;
  PaperStyle paperStyle;
  String? backgroundImageBase64;
  String? sourceFileName;

  NotePage({
    required this.id,
    List<DrawnPoint>? strokes,
    this.paperStyle = PaperStyle.lined,
    this.backgroundImageBase64,
    this.sourceFileName,
  }) : strokes = strokes ?? [];

  bool get hasPdfBackground => backgroundImageBase64 != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'style': paperStyle.toJson,
        'bg': backgroundImageBase64,
        'src': sourceFileName,
      };

  factory NotePage.fromJson(Map<String, dynamic> j) => NotePage(
        id: j['id'] as String,
        strokes: (j['strokes'] as List)
            .map((s) => DrawnPoint.fromJson(s as Map<String, dynamic>))
            .toList(),
        paperStyle: PaperStyleExt.fromJson(j['style'] as String? ?? 'lined'),
        backgroundImageBase64: j['bg'] as String?,
        sourceFileName: j['src'] as String?,
      );
}

// ── Notebook ──────────────────────────────────────────────────────────────
class Note {
  final String id;
  String title;
  List<NotePage> pages;
  DateTime updatedAt;
  String? folderId; // null = root level

  Note({
    required this.id,
    required this.title,
    List<NotePage>? pages,
    required this.updatedAt,
    this.folderId,
  }) : pages = pages ?? [NotePage(id: 'page-0', paperStyle: PaperStyle.lined)];

  List<DrawnPoint> get strokes => pages.first.strokes;
  set strokes(List<DrawnPoint> s) => pages.first.strokes = s;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'pages': pages.map((p) => p.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
        'folderId': folderId,
      };

  factory Note.fromJson(Map<String, dynamic> j) {
    if (j.containsKey('strokes') && !j.containsKey('pages')) {
      final old = (j['strokes'] as List)
          .map((s) => DrawnPoint.fromJson(s as Map<String, dynamic>))
          .toList();
      return Note(
        id: j['id'] as String,
        title: j['title'] as String,
        pages: [NotePage(id: 'page-0', strokes: old)],
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );
    }
    return Note(
      id: j['id'] as String,
      title: j['title'] as String,
      pages: (j['pages'] as List)
          .map((p) => NotePage.fromJson(p as Map<String, dynamic>))
          .toList(),
      updatedAt: DateTime.parse(j['updatedAt'] as String),
      folderId: j['folderId'] as String?,
    );
  }

  String toJsonString() => jsonEncode(toJson());
  factory Note.fromJsonString(String s) =>
      Note.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

// ── Folder ────────────────────────────────────────────────────────────────
class NoteFolder {
  final String id;
  String name;
  String colorHex; // e.g. '6C63FF'
  DateTime createdAt;
  DateTime updatedAt;
  String? parentFolderId; // null = root folder, otherwise inside another folder

  NoteFolder({
    required this.id,
    required this.name,
    this.colorHex = '6C63FF',
    required this.createdAt,
    DateTime? updatedAt,
    this.parentFolderId,
  }) : updatedAt = updatedAt ?? createdAt;

  Color get color => Color(int.parse('FF$colorHex', radix: 16));

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': colorHex,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'parentFolderId': parentFolderId,
      };

  factory NoteFolder.fromJson(Map<String, dynamic> j) => NoteFolder(
        id: j['id'] as String,
        name: j['name'] as String,
        colorHex: j['color'] as String? ?? '6C63FF',
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? ''),
        parentFolderId: j['parentFolderId'] as String?,
      );
}
