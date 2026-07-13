import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:digl/features/consultations/presentation/pages/consultation_screen.dart';
import 'package:digl/features/medications/presentation/pages/medication_details_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  Future<void> _markAsRead(String docId) async {
    await FirebaseFirestore.instance.collection('notifications').doc(docId).update({
      'isRead': true,
      'isViewed': true,
      'viewedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deleteNotification(String docId, BuildContext context) async {
    await FirebaseFirestore.instance.collection('notifications').doc(docId).delete();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف الإشعار')),
    );
  }

  Future<void> _deleteAllNotifications(BuildContext context) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    final collection = FirebaseFirestore.instance.collection('notifications');
    final snapshots = await collection.where('userId', isEqualTo: currentUserId).get();

    for (var doc in snapshots.docs) {
      await doc.reference.delete();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف جميع الإشعارات')),
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} - ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'message':
        return Icons.chat_bubble_rounded;
      case 'call':
        return Icons.call_rounded;
      case 'medication':
      case 'medication_schedule':
      case 'medication_cancel':
        return Icons.medication_rounded;
      case 'appointment':
      case 'appointment_schedule':
        return Icons.calendar_month_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _typeColor(BuildContext context, String type) {
    final scheme = Theme.of(context).colorScheme;
    switch (type) {
      case 'message':
        return scheme.primary;
      case 'call':
        return scheme.secondary;
      case 'medication':
      case 'medication_schedule':
      case 'medication_cancel':
        return scheme.tertiary;
      case 'appointment':
      case 'appointment_schedule':
        return scheme.inversePrimary;
      default:
        return scheme.outline;
    }
  }

  Future<void> _openNotificationTarget(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final type = (data['type'] ?? 'general').toString();
    final payload = data['payload'] is Map
        ? Map<String, dynamic>.from(data['payload'] as Map)
        : <String, dynamic>{};

    if (type.startsWith('medication')) {
      final medicationId = (payload['medicationId'] ?? data['medicationId'])?.toString();
      if (medicationId != null && medicationId.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MedicationDetailsScreen(medicationId: medicationId),
          ),
        );
      }
      return;
    }

    if (type == 'message') {
      final consultationId =
          (payload['consultationId'] ?? data['consultationId'])?.toString();
      if (consultationId == null || consultationId.isEmpty) return;

      final doc = await FirebaseFirestore.instance
          .collection('consultations')
          .doc(consultationId)
          .get();
      final consultation = doc.data();
      if (consultation == null) return;

      final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
      final isDoctor = consultation['doctorId'] == userId;

      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ConsultationScreen(
            consultationId: consultationId,
            doctorUid: consultation['doctorId'] ?? '',
            patientUid: consultation['userId'] ?? '',
            doctorName: consultation['doctorName'] ?? '',
            patientName: consultation['userName'] ?? '',
            doctorImage: (consultation['doctorImage'] ?? '').toString(),
            userImage: (consultation['userImage'] ?? '').toString(),
            isDoctor: isDoctor,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (currentUserId == null) {
      return const Scaffold(
        body: Center(child: Text('يرجى تسجيل الدخول لعرض الإشعارات')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        title: const Text('الإشعارات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: 'حذف جميع الإشعارات',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('تأكيد الحذف'),
                  content: const Text('هل أنت متأكد من حذف جميع الإشعارات؟'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('إلغاء'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('حذف'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await _deleteAllNotifications(context);
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: currentUserId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('حدث خطأ في تحميل الإشعارات'));
          }
          if (!snapshot.hasData) {
            return Center(
              child: Card(
                elevation: 0,
                color: colorScheme.surfaceVariant.withOpacity(.35),
                child: const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
            );
          }

          var docs = snapshot.data!.docs;
          docs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aCreatedAt = (aData['createdAt'] ?? aData['createdAtClient']) as Timestamp?;
            final bCreatedAt = (bData['createdAt'] ?? bData['createdAtClient']) as Timestamp?;
            return (bCreatedAt?.toDate() ?? DateTime(1970))
                .compareTo(aCreatedAt?.toDate() ?? DateTime(1970));
          });

          if (docs.isEmpty) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.notifications_off_outlined, size: 72, color: colorScheme.outline), const SizedBox(height: 16), Text('لا توجد إشعارات', style: theme.textTheme.titleMedium), const SizedBox(height: 6), Text('ستظهر التنبيهات المهمة هنا عند وصولها', style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant))]));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final isRead = data['isRead'] ?? false;
              final type = (data['type'] ?? 'general').toString();
              final color = _typeColor(context, type);

              return Card(
                elevation: 0,
                color: isRead ? theme.cardColor : color.withOpacity(0.08),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: isRead ? theme.dividerColor.withOpacity(.18) : color.withOpacity(.22)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () async {
                    await _markAsRead(doc.id);
                    if (!context.mounted) return;
                    await _openNotificationTarget(context, data);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: color.withOpacity(0.14),
                          child: Icon(_typeIcon(type), color: color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text((data['title'] ?? '').toString(), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              Text((data['body'] ?? '').toString(), style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 10),
                              Text(
                                _formatTimestamp((data['createdAt'] ?? data['createdAtClient']) as Timestamp?),
                                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
                          tooltip: 'حذف الإشعار',
                          onPressed: () => _deleteNotification(doc.id, context),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
