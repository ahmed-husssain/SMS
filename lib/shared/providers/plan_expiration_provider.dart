import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../features/patients/data/patient_repository.dart';
import '../../features/patients/domain/patient_model.dart';
import '../../features/invoices/data/invoice_repository.dart';
import '../../features/dashboard/domain/scheduled_notification_model.dart';
import '../../features/dashboard/data/scheduled_notification_repository.dart';
import 'auth_provider.dart';

class ExpiringPatientPlan {
  final Patient patient;
  final DateTime latestInvoiceDate;
  final DateTime expirationDate;
  final int hoursRemaining;
  final bool isExpired;
  final String category; // 'expired', 'today', 'upcoming', 'scheduled'
  final ScheduledNotification? scheduledNotification;

  ExpiringPatientPlan({
    required this.patient,
    required this.latestInvoiceDate,
    required this.expirationDate,
    required this.hoursRemaining,
    required this.isExpired,
    required this.category,
    this.scheduledNotification,
  });

  String get notificationMessage {
    if (scheduledNotification != null) {
      final note = scheduledNotification!.reminderNote.trim();
      final reason = note.isNotEmpty ? note : 'Scheduled Follow-Up';
      if (isExpired) {
        return "SCHEDULED REMINDER: ${patient.patientName} ($reason) was due on ${DateFormat('MMM d').format(expirationDate)}. Click to issue invoice.";
      } else {
        return "SCHEDULED REMINDER: ${patient.patientName} ($reason) scheduled for ${DateFormat('MMM d').format(expirationDate)}. Click to issue invoice.";
      }
    }

    if (category == 'expired') {
      final hoursAgo = hoursRemaining.abs();
      if (hoursAgo < 1) {
        return "${patient.patientName}'s plan expired just now. Click here to issue their next invoice.";
      }
      return "${patient.patientName}'s plan expired $hoursAgo hour${hoursAgo == 1 ? '' : 's'} ago. Click here to issue their next invoice.";
    } else if (category == 'today') {
      if (hoursRemaining <= 0) {
        return "${patient.patientName}'s plan expires in less than an hour. Click here to issue their next invoice.";
      }
      return "${patient.patientName}'s plan expires in $hoursRemaining hour${hoursRemaining == 1 ? '' : 's'}. Click here to issue their next invoice.";
    } else {
      final days = (hoursRemaining / 24).ceil();
      return "${patient.patientName}'s plan expires in $days day${days == 1 ? '' : 's'} on ${DateFormat('MMM d').format(expirationDate)}. Click to prepare invoice.";
    }
  }

  String get whatsappUrl {
    var phone = patient.phone.replaceAll(RegExp(r'[^\d+`]'), '').trim();
    if (phone.startsWith('0')) {
      phone = '92${phone.substring(1)}';
    } else if (phone.startsWith('+')) {
      phone = phone.substring(1);
    }

    final servicesList = patient.selectedServices
        .map((s) => (s['serviceName'] ?? s['name'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .join(', ');

    final serviceText = servicesList.isNotEmpty ? servicesList : 'Home Health Care Services';
    final dateText = DateFormat('EEEE, MMM d, yyyy').format(expirationDate);

    String noteText = '';
    if (scheduledNotification != null && scheduledNotification!.reminderNote.isNotEmpty) {
      noteText = "\n\nReminder Note: ${scheduledNotification!.reminderNote}";
    }

    final msg =
        "Dear ${patient.patientName},\n\n"
        "Your Shifa Home Health Care service plan for ($serviceText) is scheduled for renewal on $dateText.$noteText\n\n"
        "Please pay your bill or contact us at Shifa Home Health Care to confirm your service renewal. Thank you!";

    return 'https://wa.me/$phone?text=${Uri.encodeComponent(msg)}';
  }
}

final expiringPlansProvider = StreamProvider<List<ExpiringPatientPlan>>((ref) {
  final profile = ref.watch(userProfileProvider).value;
  final role = profile?['role'] ?? 'staff';

  final patientsAsync = role == 'admin'
      ? ref.watch(allPatientsProvider(false))
      : ref.watch(staffPatientsProvider);

  final invoicesAsync = role == 'admin'
      ? ref.watch(allInvoicesProvider(false))
      : ref.watch(staffInvoicesProvider);

  final standaloneScheduledAsync = ref.watch(activeScheduledNotificationsProvider);

  final patients = patientsAsync.value ?? [];
  final invoices = invoicesAsync.value ?? [];
  final standaloneScheduled = standaloneScheduledAsync.value ?? [];

  final List<ExpiringPatientPlan> expiringList = [];
  final now = DateTime.now();
  final Set<String> processedIds = {};

  // 1A. Process standalone scheduled_notifications collection
  for (final rem in standaloneScheduled) {
    if (rem.isCompleted) continue;
    if (rem.id.isNotEmpty) processedIds.add(rem.id);

    final patientMatches = patients.where((p) => p.patientId == rem.patientId).toList();
    final patient = patientMatches.isNotEmpty
        ? patientMatches.first
        : Patient(
            patientId: rem.patientId,
            mrNumber: rem.mrNumber,
            patientName: rem.patientName,
            cnic: '',
            phone: rem.phone,
            address: rem.address,
            diagnosis: '',
            doctor: '',
            nurse: '',
            caretaker: '',
            selectedServices: const [],
            monthlyServiceCost: 0,
            patientAmount: 0,
            staffPayment: 0,
            profit: 0,
            days: 0,
            assignedStaffId: '',
            organizationId: 'default',
            createdBy: rem.createdBy,
            createdAt: rem.createdAt,
            updatedBy: '',
            updatedAt: DateTime.now(),
          );

    final diff = rem.scheduledFor.difference(now);
    expiringList.add(ExpiringPatientPlan(
      patient: patient,
      latestInvoiceDate: rem.createdAt,
      expirationDate: rem.scheduledFor,
      hoursRemaining: diff.inHours,
      isExpired: diff.inHours < 0,
      category: 'scheduled',
      scheduledNotification: rem,
    ));
  }

  // 1B. Process patient-nested scheduledReminders as backup
  for (final patient in patients) {
    if (patient.isDiscontinued) continue;
    if (patient.scheduledReminders.isNotEmpty) {
      for (final rem in patient.scheduledReminders) {
        if (rem.isCompleted || (rem.id.isNotEmpty && processedIds.contains(rem.id))) continue;
        if (rem.id.isNotEmpty) processedIds.add(rem.id);

        final diff = rem.scheduledFor.difference(now);
        expiringList.add(ExpiringPatientPlan(
          patient: patient,
          latestInvoiceDate: rem.createdAt,
          expirationDate: rem.scheduledFor,
          hoursRemaining: diff.inHours,
          isExpired: diff.inHours < 0,
          category: 'scheduled',
          scheduledNotification: rem,
        ));
      }
    }
  }

  // 2. Process automatic 14-day plan expirations
  for (final patient in patients) {
    if (patient.isDiscontinued) continue;

    final patientInvoices = invoices.where((inv) => inv.patientId == patient.patientId).toList();
    DateTime latestDate = patient.createdAt;

    if (patientInvoices.isNotEmpty) {
      patientInvoices.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      latestDate = patientInvoices.first.createdAt;
    }

    final expirationDate = latestDate.add(const Duration(days: 14));
    final difference = expirationDate.difference(now);
    final hoursRemaining = difference.inHours;

    String category;
    if (hoursRemaining < 0) {
      category = 'expired';
    } else if (hoursRemaining <= 24) {
      category = 'today';
    } else if (hoursRemaining <= 168) { // Up to 7 days
      category = 'upcoming';
    } else {
      continue;
    }

    if (difference.inDays > -30) {
      expiringList.add(ExpiringPatientPlan(
        patient: patient,
        latestInvoiceDate: latestDate,
        expirationDate: expirationDate,
        hoursRemaining: hoursRemaining,
        isExpired: hoursRemaining < 0,
        category: category,
      ));
    }
  }

  // Sort by most urgent
  expiringList.sort((a, b) => a.hoursRemaining.compareTo(b.hoursRemaining));
  return Stream.value(expiringList);
});
