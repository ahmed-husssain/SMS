import 'package:cloud_firestore/cloud_firestore.dart';
import '../../dashboard/domain/scheduled_notification_model.dart';

class Patient {
  final String patientId;
  final String mrNumber;
  final String patientName;
  final String cnic;
  final String phone;
  final String address;
  final String diagnosis;
  final String doctor;
  final String nurse;
  final String caretaker;
  final List<Map<String, dynamic>> selectedServices;
  final double monthlyServiceCost;
  final double patientAmount;
  final double staffPayment;
  final double profit;
  final int days;
  final String assignedStaffId;
  final String organizationId;
  final String createdBy;
  final DateTime createdAt;
  final String updatedBy;
  final DateTime updatedAt;
  final bool isDeleted;
  final DateTime? deletedAt;
  final String? deletedBy;
  final bool isDiscontinued;
  final DateTime? discontinuedAt;
  final String? discontinuedBy;
  final DateTime? reactivatedAt;
  final String? reactivatedBy;
  final List<ScheduledNotification> scheduledReminders;

  Patient({
    required this.patientId,
    required this.mrNumber,
    required this.patientName,
    required this.cnic,
    required this.phone,
    required this.address,
    required this.diagnosis,
    required this.doctor,
    required this.nurse,
    required this.caretaker,
    required this.selectedServices,
    required this.monthlyServiceCost,
    required this.patientAmount,
    required this.staffPayment,
    required this.profit,
    this.days = 0,
    required this.assignedStaffId,
    required this.organizationId,
    required this.createdBy,
    required this.createdAt,
    required this.updatedBy,
    required this.updatedAt,
    this.isDeleted = false,
    this.deletedAt,
    this.deletedBy,
    this.isDiscontinued = false,
    this.discontinuedAt,
    this.discontinuedBy,
    this.reactivatedAt,
    this.reactivatedBy,
    this.scheduledReminders = const [],
  });

  factory Patient.fromMap(Map<String, dynamic> data, String documentId) {
    List<ScheduledNotification> reminders = [];
    if (data['scheduledReminders'] != null && data['scheduledReminders'] is List) {
      for (final item in (data['scheduledReminders'] as List)) {
        if (item is Map) {
          try {
            reminders.add(ScheduledNotification.fromMap(item, (item['id'] ?? '').toString()));
          } catch (_) {}
        }
      }
    }

    return Patient(
      patientId: documentId,
      mrNumber: data['mrNumber'] ?? '',
      patientName: data['patientName'] ?? '',
      cnic: data['cnic'] ?? '',
      phone: data['phone'] ?? '',
      address: data['address'] ?? '',
      diagnosis: data['diagnosis'] ?? '',
      doctor: data['doctor'] ?? '',
      nurse: data['nurse'] ?? '',
      caretaker: data['caretaker'] ?? '',
      selectedServices: List<Map<String, dynamic>>.from(data['selectedServices'] ?? []),
      monthlyServiceCost: (data['monthlyServiceCost'] ?? 0.0).toDouble(),
      patientAmount: (data['patientAmount'] ?? 0.0).toDouble(),
      staffPayment: (data['staffPayment'] ?? 0.0).toDouble(),
      profit: (data['profit'] ?? 0.0).toDouble(),
      days: (data['days'] is num ? (data['days'] as num).toInt() : int.tryParse(data['days']?.toString() ?? '0') ?? 0),
      assignedStaffId: data['assignedStaffId'] ?? '',
      organizationId: data['organizationId'] ?? 'default',
      createdBy: data['createdBy'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedBy: data['updatedBy'] ?? '',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isDeleted: data['isDeleted'] ?? false,
      deletedAt: (data['deletedAt'] as Timestamp?)?.toDate(),
      deletedBy: data['deletedBy'],
      isDiscontinued: data['isDiscontinued'] ?? (data['status'] == 'discontinued'),
      discontinuedAt: (data['discontinuedAt'] as Timestamp?)?.toDate(),
      discontinuedBy: data['discontinuedBy'],
      reactivatedAt: (data['reactivatedAt'] as Timestamp?)?.toDate(),
      reactivatedBy: data['reactivatedBy'],
      scheduledReminders: reminders,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'mrNumber': mrNumber,
      'patientName': patientName,
      'cnic': cnic,
      'phone': phone,
      'address': address,
      'diagnosis': diagnosis,
      'doctor': doctor,
      'nurse': nurse,
      'caretaker': caretaker,
      'selectedServices': selectedServices,
      'monthlyServiceCost': monthlyServiceCost,
      'patientAmount': patientAmount,
      'staffPayment': staffPayment,
      'profit': profit,
      'days': days,
      'assignedStaffId': assignedStaffId,
      'organizationId': organizationId,
      'createdBy': createdBy,
      'createdAt': createdAt,
      'updatedBy': updatedBy,
      'updatedAt': updatedAt,
      'isDeleted': isDeleted,
      'deletedAt': deletedAt,
      'deletedBy': deletedBy,
      'isDiscontinued': isDiscontinued,
      'discontinuedAt': discontinuedAt,
      'discontinuedBy': discontinuedBy,
      'reactivatedAt': reactivatedAt,
      'reactivatedBy': reactivatedBy,
      'scheduledReminders': scheduledReminders.map((r) => r.toMap()).toList(),
    };
  }
}
