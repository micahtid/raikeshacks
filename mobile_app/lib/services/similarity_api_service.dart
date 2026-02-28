import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Fires a silent HTTP POST to the Vercel backend whenever two users
/// successfully exchange payloads via Nearby Connections.
class SimilarityApiService {
  /// Replace with your real Vercel endpoint.
  static const String _baseUrl =
      'https://httpbin.org/post';

  /// POST the encounter to the backend so it can kick off a similarity check.
  ///
  /// [myUserId]   – this device's display name / user identifier.
  /// [peerUserId] – the encountered peer's display name / user identifier.
  /// [secretWord] – the secret word received from the peer (optional context).
  static Future<bool> postEncounter({
    required String myUserId,
    required String peerUserId,
    String? secretWord,
  }) async {
    final body = jsonEncode({
      'my_user_id': myUserId,
      'peer_user_id': peerUserId,
      'secret_word': secretWord,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      final ok = response.statusCode >= 200 && response.statusCode < 300;
      debugPrint(
        '[SimilarityAPI] POST ${ok ? 'succeeded' : 'failed'} '
        '(${response.statusCode}): ${response.body}',
      );
      return ok;
    } catch (e) {
      debugPrint('[SimilarityAPI] POST failed with exception: $e');
      return false;
    }
  }
}
