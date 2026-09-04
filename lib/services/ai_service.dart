import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class AiImageAttachment {
  final Uint8List bytes;
  final String mimeType;
  String? storagePath;

  AiImageAttachment({
    required this.bytes,
    required this.mimeType,
    this.storagePath,
  });

  Map<String, String> toJson() => {
        'mimeType': mimeType,
        'data': base64Encode(bytes),
        if (storagePath != null) 'storagePath': storagePath!,
      };
}

class AiRequestMessage {
  final String role;
  final String content;
  final AiImageAttachment? image;

  const AiRequestMessage({
    required this.role,
    required this.content,
    this.image,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        if (image != null) 'image': image!.toJson(),
      };
}

class AiServiceException implements Exception {
  final String message;

  const AiServiceException(this.message);

  @override
  String toString() => message;
}

class AiService {
  AiService._();

  static final AiService instance = AiService._();

  Future<String> sendMessages(Iterable<AiRequestMessage> messages) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'clever-endpoint',
        body: {
          'messages': messages.map((message) => message.toJson()).toList(),
        },
      );

      final data = response.data;
      if (data is Map) {
        final reply = data['reply'];
        if (reply is String && reply.trim().isNotEmpty) {
          return reply.trim();
        }
      }

      throw const AiServiceException('Gemini returned an invalid response.');
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] is String) {
        throw AiServiceException(details['error'] as String);
      }
      throw AiServiceException(
        'The AI service returned error ${error.status}.',
      );
    } on AiServiceException {
      rethrow;
    } catch (_) {
      throw const AiServiceException(
        'Could not reach Gemini. Check your internet connection and try again.',
      );
    }
  }
}
