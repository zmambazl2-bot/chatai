import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/message_reaction_model.dart';

/// خدمة إدارة التفاعلات على الرسائل
class MessageReactionsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// إضافة أو إزالة تفاعل على رسالة
  /// إذا كان المستخدم قد أضاف هذا التفاعل بالفعل، سيتم حذفه
  /// إذا أضاف emoji آخر، سيتم استبداله
  static DocumentReference<Map<String, dynamic>> _messageRef({
    required String consultationId,
    required String messageId,
    String rootCollection = 'consultations',
  }) {
    if (rootCollection == 'group_consultations') {
      return _firestore.collection('group_consultations').doc(messageId);
    }

    return _firestore
        .collection(rootCollection)
        .doc(consultationId)
        .collection('messages')
        .doc(messageId);
  }

  static Future<void> toggleReaction({
    required String consultationId,
    required String messageId,
    required String emoji,
    String rootCollection = 'consultations',
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('المستخدم غير مسجل دخول');
    if (!ReactionEmojis.isValid(emoji)) throw Exception('تفاعل غير صحيح');

    final messageRef = _messageRef(
      consultationId: consultationId,
      messageId: messageId,
      rootCollection: rootCollection,
    );

    await _firestore.runTransaction((transaction) async {
      final messageDoc = await transaction.get(messageRef);
      if (!messageDoc.exists) throw Exception('الرسالة غير موجودة');

      final messageData = messageDoc.data() as Map<String, dynamic>? ?? {};
      final currentReactions = Map<String, dynamic>.from(
        messageData['reactions'] as Map<String, dynamic>? ?? {},
      );
      final updatedReactions = <String, dynamic>{};

      currentReactions.forEach((key, value) {
        updatedReactions[key] = Map<String, dynamic>.from(value as Map);
      });

      String? previousEmoji;
      for (final entry in updatedReactions.entries) {
        final userIds = List<String>.from(entry.value['userIds'] as List? ?? []);
        if (userIds.contains(user.uid)) {
          previousEmoji = entry.key;
          break;
        }
      }

      if (previousEmoji != null) {
        final previous = Map<String, dynamic>.from(updatedReactions[previousEmoji] as Map);
        final previousUserIds = List<String>.from(previous['userIds'] as List? ?? []);
        previousUserIds.removeWhere((id) => id == user.uid);
        if (previousUserIds.isEmpty) {
          updatedReactions.remove(previousEmoji);
        } else {
          previous['userIds'] = previousUserIds.toSet().toList();
          previous['updatedAt'] = FieldValue.serverTimestamp();
          updatedReactions[previousEmoji] = previous;
        }
      }

      if (previousEmoji != emoji) {
        final next = Map<String, dynamic>.from(
          updatedReactions[emoji] as Map? ?? {
            'emoji': emoji,
            'userIds': <String>[],
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
        final nextUserIds = List<String>.from(next['userIds'] as List? ?? []);
        nextUserIds.add(user.uid);
        next['emoji'] = emoji;
        next['userIds'] = nextUserIds.toSet().toList();
        next['updatedAt'] = FieldValue.serverTimestamp();
        updatedReactions[emoji] = next;
      }

      transaction.update(messageRef, {'reactions': updatedReactions});
    });
  }

  static Stream<List<MessageReaction>> reactionsStream({
    required String consultationId,
    required String messageId,
    String rootCollection = 'consultations',
  }) {
    return _messageRef(
      consultationId: consultationId,
      messageId: messageId,
      rootCollection: rootCollection,
    ).snapshots()
        .map((doc) {
      final data = doc.data();
      final reactions = data?['reactions'] as Map<String, dynamic>? ?? {};
      return reactions.entries
          .map((e) => MessageReaction.fromMap(Map<String, dynamic>.from(e.value as Map)))
          .where((reaction) => reaction.count > 0)
          .toList();
    });
  }

  /// جلب جميع التفاعلات على رسالة معينة
  static Future<List<MessageReaction>> getReactions({
    required String consultationId,
    required String messageId,
    String rootCollection = 'consultations',
  }) async {
    try {
      final messageDoc = await _messageRef(
        consultationId: consultationId,
        messageId: messageId,
        rootCollection: rootCollection,
      ).get();

      if (!messageDoc.exists) {
        return [];
      }

      final data = messageDoc.data() as Map<String, dynamic>?;
      final reactions = data?['reactions'] as Map<String, dynamic>? ?? {};

      return reactions.entries
          .map((e) => MessageReaction.fromMap(Map<String, dynamic>.from(e.value as Map)))
          .toList();
    } catch (e) {
      print('❌ خطأ في جلب التفاعلات: $e');
      return [];
    }
  }

  /// حذف جميع التفاعلات على رسالة (بواسطة المسؤول فقط)
  static Future<void> clearAllReactions({
    required String consultationId,
    required String messageId,
    String rootCollection = 'consultations',
  }) async {
    try {
      await _messageRef(
        consultationId: consultationId,
        messageId: messageId,
        rootCollection: rootCollection,
      ).update({'reactions': {}});

      print('✅ تم حذف جميع التفاعلات');
    } catch (e) {
      print('❌ خطأ في حذف التفاعلات: $e');
      rethrow;
    }
  }

  /// جلب التفاعل الحالي للمستخدم على رسالة معينة
  static Future<String?> getUserReaction({
    required String consultationId,
    required String messageId,
    String rootCollection = 'consultations',
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final reactions = await getReactions(
        consultationId: consultationId,
        messageId: messageId,
        rootCollection: rootCollection,
      );

      // البحث عن التفاعل الذي أضافه المستخدم
      for (var reaction in reactions) {
        if (reaction.hasUserReacted(user.uid)) {
          return reaction.emoji;
        }
      }

      return null;
    } catch (e) {
      print('❌ خطأ في جلب تفاعل المستخدم: $e');
      return null;
    }
  }
}
