import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket client for real-time events from the server.
class WebSocketService {
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  String? _uid;
  String? _baseUrl;
  bool _disposed = false;

  /// Callbacks for different event types.
  void Function(Map<String, dynamic>)? onMatchFound;
  void Function(Map<String, dynamic>)? onConnectionAccepted;
  void Function(Map<String, dynamic>)? onConnectionComplete;

  void connect(String uid, String baseUrl) {
    _uid = uid;
    _baseUrl = baseUrl;
    _doConnect();
  }

  void _doConnect() {
    if (_disposed || _uid == null || _baseUrl == null) return;

    final wsUrl = _baseUrl!
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final uri = Uri.parse('$wsUrl/ws/$_uid');

    try {
      _channel = WebSocketChannel.connect(uri);
      debugPrint('[knkt] WebSocket connecting to $uri');

      _channel!.stream.listen(
        (data) {
          try {
            final event = jsonDecode(data as String) as Map<String, dynamic>;
            _handleEvent(event);
          } catch (e) {
            debugPrint('[knkt] WebSocket parse error: $e');
          }
        },
        onDone: () {
          debugPrint('[knkt] WebSocket closed, scheduling reconnect');
          _scheduleReconnect();
        },
        onError: (error) {
          debugPrint('[knkt] WebSocket error: $error');
          _scheduleReconnect();
        },
      );
    } catch (e) {
      debugPrint('[knkt] WebSocket connect failed: $e');
      _scheduleReconnect();
    }
  }

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    debugPrint('[knkt] WebSocket event: $type');
    switch (type) {
      case 'match_found':
        onMatchFound?.call(event);
      case 'connection_accepted':
        onConnectionAccepted?.call(event);
      case 'connection_complete':
        onConnectionComplete?.call(event);
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), _doConnect);
  }

  void disconnect() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
  }
}
