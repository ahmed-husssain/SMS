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

    // 1. Save directly in standalone scheduled_notifications collection in Firestore
    try {
      await docRef.set(reminderMap);
    } catch (e) {
      print('Error saving to scheduled_notifications collection: $e');
    }

    // 2. Also save in patient document array for backup sync
    if (notification.patientId.isNotEmpty) {
      try {
        await _firestore.collection('patients').doc(notification.patientId).set({
          'scheduledReminders': FieldValue.arrayUnion([reminderMap]),
        }, SetOptions(merge: true));
      } catch (e) {
        print('Error updating patient scheduledReminders: $e');
      }
    }
  }

  Future<void> markAsCompleted(String patientId, String reminderId) async {
    // 1. Update standalone scheduled_notifications collection
    try {
      await _firestore.collection('scheduled_notifications').doc(reminderId).update({
        'isCompleted': true,
      });
    } catch (_) {}

    // 2. Update patient document array
    if (patientId.isNotEmpty) {
      try {
        final docRef = _firestore.collection('patients').doc(patientId);
        final doc = await docRef.get();
        if (doc.exists) {
          final data = doc.data();
          if (data != null && data['scheduledReminders'] is List) {
            final list = List<Map<String, dynamic>>.from(
              (data['scheduledReminders'] as List).map((x) => Map<String, dynamic>.from(x as Map)),
            );
            for (final item in list) {
              if ((item['id'] ?? '').toString() == reminderId) {
                item['isCompleted'] = true;
              }
            }
            await docRef.set({'scheduledReminders': list}, SetOptions(merge: true));
          }
        }
      } catch (_) {}
    }
  }

  Future<void> deleteScheduledNotification(String patientId, String reminderId) async {
    // 1. Delete from standalone scheduled_notifications collection
    try {
      await _firestore.collection('scheduled_notifications').doc(reminderId).delete();
    } catch (_) {}

    // 2. Remove from patient document array
    if (patientId.isNotEmpty) {
      try {
        final docRef = _firestore.collection('patients').doc(patientId);
        final doc = await docRef.get();
        if (doc.exists) {
          final data = doc.data();
          if (data != null && data['scheduledReminders'] is List) {
            final list = List<Map<String, dynamic>>.from(
              (data['scheduledReminders'] as List).map((x) => Map<String, dynamic>.from(x as Map)),
            );
            list.removeWhere((item) => (item['id'] ?? '').toString() == reminderId);
            await docRef.set({'scheduledReminders': list}, SetOptions(merge: true));
          }
        }
      } catch (_) {}
    }
  }
}
