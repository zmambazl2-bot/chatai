import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../consultations/models/message_reaction_model.dart';
import '../../../consultations/services/message_reactions_service.dart';

/// Widget يعرض التفاعلات على الرسالة
class MessageReactionsWidget extends StatefulWidget {
  final String consultationId;
  final String messageId;
  final VoidCallback? onReactionAdded;
  final bool showAddButton;
  final String rootCollection;

  const MessageReactionsWidget({
    Key? key,
    required this.consultationId,
    required this.messageId,
    this.onReactionAdded,
    this.showAddButton = true,
    this.rootCollection = 'consultations',
  }) : super(key: key);

  @override
  State<MessageReactionsWidget> createState() => _MessageReactionsWidgetState();
}

class _MessageReactionsWidgetState extends State<MessageReactionsWidget> {
  bool _isUpdating = false;

  /// عرض قائمة التفاعلات للاختيار
  void _showReactionPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ReactionEmojis.available.map((emoji) {
              return GestureDetector(
                onTap: () {
                  _addReaction(emoji);
                  Navigator.pop(context);
                },
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      emoji,
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  /// إضافة تفاعل
  Future<void> _addReaction(String emoji) async {
    if (_isUpdating) return;
    setState(() => _isUpdating = true);
    try {
      await MessageReactionsService.toggleReaction(
        consultationId: widget.consultationId,
        messageId: widget.messageId,
        emoji: emoji,
        rootCollection: widget.rootCollection,
      );

      widget.onReactionAdded?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في إضافة التفاعل: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MessageReaction>>(
      stream: MessageReactionsService.reactionsStream(
        consultationId: widget.consultationId,
        messageId: widget.messageId,
        rootCollection: widget.rootCollection,
      ),
      builder: (context, snapshot) {
        final reactions = snapshot.data ?? <MessageReaction>[];
        if (reactions.isEmpty && !widget.showAddButton) {
          return const SizedBox.shrink();
        }
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // عرض التفاعلات الموجودة
              ...reactions.map((reaction) {
                final hasCurrentUserReacted =
                    currentUserId != null && reaction.hasUserReacted(currentUserId);

                return GestureDetector(
                  onTap: () => _addReaction(reaction.emoji),
                  child: Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: hasCurrentUserReacted
                          ? Colors.blue.withOpacity(0.2)
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: hasCurrentUserReacted
                            ? Colors.blue.withOpacity(0.5)
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          reaction.emoji,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          reaction.count.toString(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: hasCurrentUserReacted
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
              // زر إضافة تفاعل جديد
              if (widget.showAddButton)
                GestureDetector(
                  onTap: () => _showReactionPicker(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '+',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
