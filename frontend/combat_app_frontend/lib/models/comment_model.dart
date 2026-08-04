import 'user_model.dart';

class CommentModel {
  final int id;
  final String content;
  final UserModel author;
  final DateTime createdAt;

  const CommentModel({
    required this.id,
    required this.content,
    required this.author,
    required this.createdAt,
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    return CommentModel(
      id: json['id'] as int,
      content: json['content'] as String,
      author: UserModel.fromJson(json['author'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
