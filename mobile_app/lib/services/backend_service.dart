import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/connection_model.dart';

class BackendService {
  static String get _baseUrl =>
      dotenv.env['BACKEND_URL'] ?? 'https://raikeshacks-teal.vercel.app';

  // ── Resume ────────────────────────────────────────────────────────────

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

  // ── Students ──────────────────────────────────────────────────────────

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

  /// Get a student profile by uid.
  static Future<Map<String, dynamic>?> getStudent(String uid) async {
    final uri = Uri.parse('$_baseUrl/students/$uid');
    try {
      final response = await http.get(uri);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[knkt] getStudent failed: $e');
    }
    return null;
  }

  /// Delete a student profile by uid.
  static Future<bool> deleteStudent(String uid) async {
    final uri = Uri.parse('$_baseUrl/students/$uid');
    final response = await http.delete(uri);
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  /// Register/update FCM token for a user.
  static Future<bool> updateFcmToken(String uid, String token) async {
    final uri = Uri.parse('$_baseUrl/students/$uid/fcm-token');
    try {
      final response = await http.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token}),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[knkt] updateFcmToken failed: $e');
      return false;
    }
  }

  // ── Connections ───────────────────────────────────────────────────────

  /// Create a new connection between two users.
  static Future<ConnectionModel?> createConnection(String uid1, String uid2) async {
    final uri = Uri.parse('$_baseUrl/connections');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uid1': uid1, 'uid2': uid2}),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ConnectionModel.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('[knkt] createConnection failed: $e');
    }
    return null;
  }

  /// Get a single connection by ID.
  static Future<ConnectionModel?> getConnection(String connectionId) async {
    final uri = Uri.parse('$_baseUrl/connections/$connectionId');
    try {
      final response = await http.get(uri);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ConnectionModel.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('[knkt] getConnection failed: $e');
    }
    return null;
  }

  /// Get all connections for a user.
  static Future<List<ConnectionModel>?> getConnectionsForUser(String uid) async {
    final uri = Uri.parse('$_baseUrl/connections/user/$uid');
    try {
      final response = await http.get(uri);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final list = data['connections'] as List;
        return list.map((j) => ConnectionModel.fromJson(j)).toList();
      }
    } catch (e) {
      debugPrint('[knkt] getConnectionsForUser failed: $e');
    }
    return null;
  }

  /// Get only mutually accepted connections for a user.
  static Future<List<ConnectionModel>?> getAcceptedConnections(String uid) async {
    final uri = Uri.parse('$_baseUrl/connections/user/$uid/accepted');
    try {
      final response = await http.get(uri);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final list = data['connections'] as List;
        return list.map((j) => ConnectionModel.fromJson(j)).toList();
      }
    } catch (e) {
      debugPrint('[knkt] getAcceptedConnections failed: $e');
    }
    return null;
  }

  /// Accept a connection.
  static Future<ConnectionModel?> acceptConnection(String connectionId, String uid) async {
    final uri = Uri.parse('$_baseUrl/connections/$connectionId/accept');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uid': uid}),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ConnectionModel.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('[knkt] acceptConnection failed: $e');
    }
    return null;
  }

  // ── Chat ──────────────────────────────────────────────────────────────

  /// Get chat messages for a room.
  static Future<Map<String, dynamic>?> getChatMessages(
    String roomId, {
    int limit = 50,
    String? before,
  }) async {
    final params = <String, String>{'limit': limit.toString()};
    if (before != null) params['before'] = before;
    final uri = Uri.parse('$_baseUrl/chat/rooms/$roomId/messages')
        .replace(queryParameters: params);
    try {
      final response = await http.get(uri);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[knkt] getChatMessages failed: $e');
    }
    return null;
  }

  /// Send a chat message.
  static Future<Map<String, dynamic>?> sendChatMessage(
    String roomId,
    String senderUid,
    String content,
  ) async {
    final uri = Uri.parse('$_baseUrl/chat/rooms/$roomId/messages');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'sender_uid': senderUid, 'content': content}),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[knkt] sendChatMessage failed: $e');
    }
    return null;
  }

  /// Create a chat room.
  static Future<Map<String, dynamic>?> createChatRoom(String uid1, String uid2) async {
    final uri = Uri.parse('$_baseUrl/chat/rooms');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'participant_uids': [uid1, uid2]}),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[knkt] createChatRoom failed: $e');
    }
    return null;
  }
}
