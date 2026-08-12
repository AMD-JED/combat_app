import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/constants.dart';
import '../core/secure_storage.dart';

/// Thrown when the socket closes because the access token was rejected
/// (server closes with code 4001 — see `messages.py::websocket_endpoint`).
class ChatAuthException implements Exception {
  final String message;
  ChatAuthException(this.message);
}

/// Wraps the `/messages/ws?token=<JWT>` WebSocket described in
/// `app/api/v1/endpoints/messages.py`.
///
/// Usage:
/// ```dart
/// final socket = ChatSocketService();
/// await socket.connect();
/// socket.events.listen((event) {
///   // event['event'] is one of: connected | new_message | message_read | user_typing | error
/// });
/// socket.sendMessage(conversationId: 5, content: "yo!");
/// socket.dispose();
/// ```
class ChatSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();

  /// Parsed server → client events (`WSOutgoingMessage` shape:
  /// `{ "event": "...", "data": {...} }`).
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  bool _disposed = false;

  Future<void> connect() async {
    final token = await SecureStorage.instance.getAccessToken();
    if (token == null) {
      throw ChatAuthException('لا يوجد رمز دخول محفوظ');
    }

    // http://... -> ws://...   https://... -> wss://...
    const httpBase = ApiConfig.baseUrl;
    final wsBase = httpBase.startsWith('https')
        ? httpBase.replaceFirst('https', 'wss')
        : httpBase.replaceFirst('http', 'ws');

    final uri = Uri.parse('$wsBase${ApiConfig.messagesWs}').replace(
      queryParameters: {'token': token},
    );

    _channel = WebSocketChannel.connect(uri);

    _subscription = _channel!.stream.listen(
      (raw) {
        try {
          final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
          _eventController.add(decoded);
        } catch (_) {
          // Ignore malformed frames rather than crashing the stream.
        }
      },
      onDone: () {
        // Backend closes with 4001 for an invalid/expired token.
        final closeCode = _channel?.closeCode;
        if (closeCode == 4001 && !_disposed) {
          _eventController.addError(
              ChatAuthException('انتهت صلاحية الجلسة، الرجاء إعادة الاتصال'));
        }
      },
      onError: (error) {
        if (!_disposed) _eventController.addError(error);
      },
      cancelOnError: false,
    );
  }

  void _send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  /// Mirrors `WSIncomingMessage` with `type: "send_message"`.
  void sendMessage({
    required int conversationId,
    String? content,
    String? mediaUrl,
    String? mediaType,
  }) {
    _send({
      'type': 'send_message',
      'conversation_id': conversationId,
      'content': content,
      'media_url': mediaUrl,
      'media_type': mediaType,
    });
  }

  /// Mirrors `WSIncomingMessage` with `type: "mark_read"`.
  void markRead(int conversationId) {
    _send({'type': 'mark_read', 'conversation_id': conversationId});
  }

  /// Mirrors `WSIncomingMessage` with `type: "typing"`.
  void sendTyping(int conversationId) {
    _send({'type': 'typing', 'conversation_id': conversationId});
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    await _channel?.sink.close();
    await _eventController.close();
  }
}
