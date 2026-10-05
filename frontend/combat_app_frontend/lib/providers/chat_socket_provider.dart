import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/chat_socket_service.dart';
import 'auth_provider.dart';

class ChatSocketState {
  final bool isConnected;
  const ChatSocketState({this.isConnected = false});
}

/// ONE `/messages/ws` connection for the whole signed-in session.
///
/// Before this, every open chat screen created its own socket, and nothing
/// listened while the conversation list was showing — so a message that
/// arrived outside an open chat only appeared after pull-to-refresh. Now the
/// conversation list, the unread badge and the open chat all consume the same
/// event stream, and the socket reconnects by itself (exponential back-off)
/// when the network or the server drops it.
class ChatSocketNotifier extends StateNotifier<ChatSocketState> {
  ChatSocketNotifier({required bool enabled}) : super(const ChatSocketState()) {
    if (enabled) _connect();
  }

  ChatSocketService? _service;
  StreamSubscription? _serviceSub;
  Timer? _retryTimer;
  int _attempt = 0;
  bool _disposed = false;

  final _events = StreamController<Map<String, dynamic>>.broadcast();

  /// Parsed server events: `{ "event": "...", "data": {...} }`.
  Stream<Map<String, dynamic>> get events => _events.stream;

  /// Emits every time the socket (re)connects — listeners use it to resync
  /// anything they may have missed while offline.
  final _reconnected = StreamController<void>.broadcast();
  Stream<void> get reconnected => _reconnected.stream;

  Future<void> _connect() async {
    if (_disposed) return;
    await _teardownService();

    final service = ChatSocketService();
    _service = service;
    try {
      await service.connect(onClosed: (_) {
        if (_disposed || _service != service) return;
        state = const ChatSocketState(isConnected: false);
        _scheduleReconnect();
      });
      if (_disposed || _service != service) return;

      _serviceSub = service.events.listen(
        (event) {
          if (!_events.isClosed) _events.add(event);
        },
        // Auth failures arrive as stream errors; the reconnect loop (which
        // re-reads the token from secure storage) already handles them.
        onError: (_) {},
      );

      final wasRetrying = _attempt > 0;
      _attempt = 0;
      state = const ChatSocketState(isConnected: true);
      if (wasRetrying && !_reconnected.isClosed) _reconnected.add(null);
    } catch (_) {
      if (_disposed || _service != service) return;
      state = const ChatSocketState(isConnected: false);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed || _retryTimer != null) return;
    _attempt++;
    // 1s, 2s, 4s, 8s, 16s, then 30s forever.
    final seconds = _attempt >= 6 ? 30 : (1 << (_attempt - 1));
    _retryTimer = Timer(Duration(seconds: seconds), () {
      _retryTimer = null;
      _connect();
    });
  }

  Future<void> _teardownService() async {
    final old = _service;
    _service = null;
    await _serviceSub?.cancel();
    _serviceSub = null;
    await old?.dispose();
  }

  // ── client → server ──────────────────────────────────────

  /// Returns false when the socket is down so the caller can fall back to REST.
  bool sendMessage({
    required int conversationId,
    String? content,
    String? mediaUrl,
    String? mediaType,
  }) {
    if (!state.isConnected || _service == null) return false;
    _service!.sendMessage(
      conversationId: conversationId,
      content: content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
    );
    return true;
  }

  void markRead(int conversationId) {
    if (state.isConnected) _service?.markRead(conversationId);
  }

  void sendTyping(int conversationId) {
    if (state.isConnected) _service?.sendTyping(conversationId);
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _serviceSub?.cancel();
    _service?.dispose();
    _events.close();
    _reconnected.close();
    super.dispose();
  }
}

/// Rebuilt (old socket closed, new one opened) whenever the signed-in user
/// changes, so logging out always closes the socket and a different login
/// never inherits the previous account's connection.
final chatSocketProvider =
    StateNotifierProvider<ChatSocketNotifier, ChatSocketState>((ref) {
  final userId = ref.watch(authProvider.select((s) => s.user?.id));
  return ChatSocketNotifier(enabled: userId != null);
});
