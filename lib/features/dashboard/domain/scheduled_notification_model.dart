import 'package:cloud_firestore/cloud_firestore.dart';

class ScheduledNotification {
  final String id;
  final String patientId;
  final String patientName;
  final String mrNumber;
  final String phone;
  final String address;
  final String reminderNote;
  final int targetDays; // e.g. 4, 7, 14, 0 for custom
  final DateTime scheduledFor;
  final DateTime createdAt;
  final String createdBy;
  final bool isCompleted;

  ScheduledNotification({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.mrNumber,
    required this.phone,
    required this.address,
    required this.reminderNote,
    required this.targetDays,
    required this.scheduledFor,
    required this.createdAt,
    required this.createdBy,
    this.isCompleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patientId': patientId,
      'patientName': patientName,
      'mrNumber': mrNumber,
      'phone': phone,
      'address': address,
      'reminderNote': reminderNote,
      'targetDays': targetDays,
      'scheduledFor': Timestamp.fromDate(scheduledFor),
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'isCompleted': isCompleted,
    };
  }

  factory ScheduledNotification.fromMap(Map<dynamic, dynamic> map, String docId) {
    DateTime parseDate(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      if (val is num) return DateTime.fromMillisecondsSinceEpoch(val.toInt());
      if (val is Map) {
        if (val['_seconds'] != null) {
          final sec = val['_seconds'];
          if (sec is num) {
            return DateTime.fromMillisecondsSinceEpoch(sec.toInt() * 1000);
          }
        }
        if (val['seconds'] != null) {
          final sec = val['seconds'];
          if (sec is num) {
            return DateTime.fromMillisecondsSinceEpoch(sec.toInt() * 1000);
          }
        }
      }
      return DateTime.now();
    }

    final parsedId = (docId.isNotEmpty ? docId : (map['id'] ?? '')).toString();

    return ScheduledNotification(
      id: parsedId,
      patientId: (map['patientId'] ?? '').toString(),
      patientName: (map['patientName'] ?? '').toString(),
      mrNumber: (map['mrNumber'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
      reminderNote: (map['reminderNote'] ?? '').toString(),
      targetDays: map['targetDays'] != null ? (int.tryParse(map['targetDays'].toString()) ?? 0) : 0,
      scheduledFor: parseDate(map['scheduledFor']),
      createdAt: parseDate(map['createdAt']),
      createdBy: (map['createdBy'] ?? '').toString(),
      isCompleted: map['isCompleted'] == true,
    );
  }
}
