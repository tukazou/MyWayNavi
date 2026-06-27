import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class GeminiException implements Exception {
  final String message;
  const GeminiException(this.message);

  @override
  String toString() => message;
}

class GeminiService {
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

  Future<String> sendMessage(String text) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw const GeminiException('GEMINI_API_KEYが設定されていません');
    }

    http.Response response;
    try {
      response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        },
        body: json.encode({
          'contents': [
            {
              'parts': [
                {'text': text}
              ]
            }
          ]
        }),
      );
    } catch (e) {
      throw const GeminiException('Geminiへの通信に失敗しました');
    }

    if (response.statusCode != 200) {
      throw GeminiException(
        'Gemini APIエラー（status: ${response.statusCode}）',
      );
    }

    final data = json.decode(response.body);
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw const GeminiException('Geminiから応答が得られませんでした');
    }

    final parts = candidates[0]['content']?['parts'] as List?;
    if (parts == null || parts.isEmpty || parts[0]['text'] == null) {
      throw const GeminiException('Geminiの応答形式が不正です');
    }

    return parts[0]['text'] as String;
  }
}
