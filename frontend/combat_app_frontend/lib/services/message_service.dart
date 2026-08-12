import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/constants.dart';
import '../models/message_model.dart';

/// Talks to `app/api/v1/endpoints/messages.py` (REST part only —
/// see `core/chat_socket_service.dart` for the WebSocket part).
class MessageService {
  final Dio _dio = ApiClient.instance.dio;

  /// GET /messages/conversations
  Future<List<ConversationModel>> getConversations() async {
    try {
      final response = await _dio.get(ApiConfig.conversations);
      return (response.data as List)
          .map((e) => ConversationModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /messages/conversations/{user_id} → { conversation_id, created }
  Future<int> openConversation(int userId) async {
    try {
      final response = await _dio.post(ApiConfig.openConversation(userId));
      return response.data['conversation_id'] as int;
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// GET /messages/conversations/{id}/messages?skip=&limit=
  /// NOTE: backend returns NEWEST first — this method reverses the list so
  /// callers get chronological (oldest → newest) order, ready for a normal
  /// (non-reversed) ListView, or reverse again yourself for a reversed one.
  Future<List<MessageModel>> getMessages(
    int conversationId, {
    int skip = 0,
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get(
        ApiConfig.conversationMessages(conversationId),
        queryParameters: {'skip': skip, 'limit': limit},
      );
      final messages = (response.data as List)
          .map((e) => MessageModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return messages.reversed.toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /messages/conversations/{id}/read → { marked_read }
  Future<int> markRead(int conversationId) async {
    try {
      final response = await _dio.post(ApiConfig.markConversationRead(conversationId));
      return response.data['marked_read'] as int;
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// DELETE /messages/{message_id} → 204 No Content
  Future<void> deleteMessage(int messageId) async {
    try {
      await _dio.delete(ApiConfig.deleteMessage(messageId));
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
