import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/scheduled_notification_model.dart';

import '../../../shared/providers/auth_provider.dart';

final scheduledNotificationRepositoryProvider = Provider<ScheduledNotificationRepository>((ref) {
  return ScheduledNotificationRepository(FirebaseFirestore.instance);
});

final activeScheduledNotificationsProvider = StreamProvider<List<ScheduledNotification>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    return Stream.value(<ScheduledNotification>[]);
  }

  return FirebaseFirestore.instance
      .collection('scheduled_notifications')
      .snapshots()
      .map((snapshot) {
    return snapshot.docs
        .map((doc) => ScheduledNotification.fromMap(doc.data(), doc.id))
        .where((n) => !n.isCompleted)
        .toList();
  }).handleError((err) {
    return <ScheduledNotification>[];
  });
});

class ScheduledNotificationRepository {
  final FirebaseFirestore _firestore;

  ScheduledNotificationRepository(this._firestore);

  Future<void> addScheduledNotification(ScheduledNotification notification) async {
    final docRef = _firestore.collection('scheduled_notifications').doc();
    final idStr = docRef.id;

    final reminderMap = {
      'id': idStr,
      'patientId': notification.patientId,
      'patientName': notification.patientName,
      'mrNumber': notification.mrNumber,
      'phone': notification.phone,
      'address': notification.address,
      'reminderNote': notification.reminderNote,
      'targetDays': notification.targetDays,
      'scheduledFor': Timestamp.fromDate(notification.scheduledFor),
      'createdAt': Timestamp.fromDate(notification.createdAt),
      'createdBy': notification.createdBy,
      'isCompleted': false,
    };

    // Save directly in standalone scheduled_notifications collection in Firestore
    await docRef.set(reminderMap);
  }

  Future<void> markAsCompleted(String patientId, String reminderId) async {
    try {
      await _firestore.collection('scheduled_notifications').doc(reminderId).update({
        'isCompleted': true,
      });
    } catch (_) {}
  }

  Future<void> deleteScheduledNotification(String patientId, String reminderId) async {
    try {
      await _firestore.collection('scheduled_notifications').doc(reminderId).delete();
    } catch (_) {}
  }
}
