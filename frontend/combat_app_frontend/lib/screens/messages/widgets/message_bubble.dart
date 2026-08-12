import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../models/message_model.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final VoidCallback? onLongPressDelete;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.onLongPressDelete,
  });

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMine ? AppTheme.primaryRed : AppTheme.surface;
    // NOTE: within an RTL Directionality, "centerLeft"/"centerRight" below are
    // intentionally swapped relative to LTR intuition so that "my" bubbles
    // still visually land on the leading (right, in RTL) side. Adjust if
    // you flip the app to LTR.

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: isMine && !message.isDeleted ? onLongPressDelete : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.displayContent,
                style: TextStyle(
                  color: Colors.white,
                  fontStyle: message.isDeleted ? FontStyle.italic : FontStyle.normal,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_formatTime(message.createdAt),
                      style: const TextStyle(fontSize: 10, color: Colors.white70)),
                  if (isMine && !message.isDeleted) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.isRead ? Icons.done_all : Icons.done,
                      size: 14,
                      color: message.isRead ? AppTheme.gold : Colors.white70,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
