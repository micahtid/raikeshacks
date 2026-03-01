import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class BackendService {
  static String get _baseUrl =>
      dotenv.env['BACKEND_URL'] ?? 'https://raikeshacks-teal.vercel.app';

  /// Upload a resume file and get parsed structured data back.
  static Future<Map<String, dynamic>?> parseResume(
    Uint8List bytes,
    String filename,
  ) async {
    final uri = Uri.parse('$_baseUrl/parse-resume');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  /// Create a new student profile. Returns the full profile including uid.
  static Future<Map<String, dynamic>?> createStudent(
    Map<String, dynamic> data,
  ) async {
    final uri = Uri.parse('$_baseUrl/students');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  /// Delete a student profile by uid.
  static Future<bool> deleteStudent(String uid) async {
    final uri = Uri.parse('$_baseUrl/students/$uid');
    final response = await http.delete(uri);
    return response.statusCode >= 200 && response.statusCode < 300;
  }
}
