import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'ai_service.dart';

class ClipboardImageService {
  const ClipboardImageService._();

  static const int maxImageBytes = 6 * 1024 * 1024;

  static Future<AiImageAttachment?> readImage() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return null;

    final reader = await clipboard.read();
    const formats = <({FileFormat format, String mimeType})>[
      (format: Formats.png, mimeType: 'image/png'),
      (format: Formats.jpeg, mimeType: 'image/jpeg'),
      (format: Formats.webp, mimeType: 'image/webp'),
      (format: Formats.gif, mimeType: 'image/gif'),
    ];

    Object? lastReadError;
    for (final item in reader.items) {
      for (final candidate in formats) {
        if (!item.canProvide(candidate.format)) continue;
        try {
          final bytes = await _readFile(item, candidate.format);
          if (bytes != null && bytes.isNotEmpty) {
            return AiImageAttachment(
              bytes: bytes,
              mimeType: candidate.mimeType,
            );
          }
        } catch (error) {
          // Windows applications can advertise several image formats even when
          // one of those formats cannot actually be decoded. Keep trying the
          // other available formats instead of failing on the first one.
          lastReadError = error;
        }
      }
    }

    if (lastReadError != null) {
      throw ClipboardImageException(lastReadError.toString());
    }
    return null;
  }

  static Future<AiImageAttachment?> pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const ClipboardImageException(
          'The selected image could not be read.');
    }

    final extension = file.extension?.toLowerCase();
    final mimeType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/png',
    };
    return AiImageAttachment(bytes: bytes, mimeType: mimeType);
  }

  static Future<void> writePngImage(Uint8List bytes) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      throw const ClipboardImageException(
        'Image clipboard is not available on this device.',
      );
    }
    final item = DataWriterItem(suggestedName: 'notebook-selection.png');
    item.add(Formats.png(bytes));
    await clipboard.write([item]);
  }

  static Future<void> pastePlainText(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pastedText = data?.text;
    if (pastedText == null || pastedText.isEmpty) return;

    final oldText = controller.text;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : oldText.length;
    final end = selection.isValid ? selection.end : oldText.length;
    final newText = oldText.replaceRange(start, end, pastedText);

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + pastedText.length),
    );
  }

  static Future<Uint8List?> _readFile(
    DataReader reader,
    FileFormat format,
  ) {
    final completer = Completer<Uint8List?>();
    final progress = reader.getFile(
      format,
      (file) async {
        try {
          final bytes = await file.readAll();
          if (!completer.isCompleted) completer.complete(bytes);
        } catch (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        }
      },
      onError: (error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
    );

    if (progress == null && !completer.isCompleted) completer.complete(null);
    return completer.future.timeout(const Duration(seconds: 10));
  }
}

class ClipboardImageException implements Exception {
  final String message;

  const ClipboardImageException(this.message);

  @override
  String toString() => message;
}
