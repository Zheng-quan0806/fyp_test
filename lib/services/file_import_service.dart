import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';

class FileImportService {
  /// Pick a PDF or image.
  /// Returns a list of [NotePage] — one per PDF page, or one for an image.
  /// Each page has [backgroundImageBase64] set so it renders as background.
  static Future<List<NotePage>> pickAndImport(
    BuildContext context,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'gif', 'webp'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return [];

    final file = result.files.first;
    final ext = (file.extension ?? '').toLowerCase();

    if (ext == 'pdf') {
      return _renderPdfPages(file);
    } else {
      return _wrapImage(file);
    }
  }

  // ── PDF: render each page to PNG, return as NotePage list ─────────────
  static Future<List<NotePage>> _renderPdfPages(PlatformFile file) async {
    final pages = <NotePage>[];

    try {
      // Write to temp file — pdfx needs a file path
      final tmpDir = await getTemporaryDirectory();
      final tmpPath = '${tmpDir.path}/import_${file.name}';
      final tmpFile = File(tmpPath);
      await tmpFile.writeAsBytes(file.bytes!);

      final doc = await PdfDocument.openFile(tmpPath);
      final pageCount = doc.pagesCount;

      for (int i = 1; i <= pageCount; i++) {
        final page = await doc.getPage(i);

        // Render at 1.5x for sharpness
        final rendered = await page.render(
          width: page.width * 1.5,
          height: page.height * 1.5,
          format: PdfPageImageFormat.png,
          backgroundColor: '#FFFFFF',
        );
        await page.close();

        if (rendered != null) {
          final b64 = base64Encode(rendered.bytes);
          pages.add(NotePage(
            id: const Uuid().v4(),
            paperStyle: PaperStyle.blank, // no lines, PDF is the background
            backgroundImageBase64: b64,
            sourceFileName: '${file.name} — page $i',
          ));
        }
      }

      await doc.close();
      await tmpFile.delete();
    } catch (e) {
      debugPrint('PDF render error: $e');
    }

    return pages;
  }

  // ── Image: wrap as a single NotePage with background ──────────────────
  static List<NotePage> _wrapImage(PlatformFile file) {
    if (file.bytes == null) return [];
    final b64 = base64Encode(file.bytes!);
    return [
      NotePage(
        id: const Uuid().v4(),
        paperStyle: PaperStyle.blank,
        backgroundImageBase64: b64,
        sourceFileName: file.name,
      ),
    ];
  }
}