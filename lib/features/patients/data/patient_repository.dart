import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/patient_model.dart';
import '../../../shared/providers/auth_provider.dart';

final patientRepositoryProvider = Provider<PatientRepository>((ref) {
  return PatientRepository(
    firestore: ref.watch(firestoreProvider),
  );
});

class PatientRepository {
  final FirebaseFirestore _firestore;

  PatientRepository({required this._firestore});

  // Stream patients for a specific staff member (excluding deleted)
  Stream<List<Patient>> watchStaffPatients(String staffId) {
    return _firestore
        .collection('patients')
        .where('isDeleted', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => Patient.fromMap(doc.data(), doc.id))
          .where((p) => p.createdBy == staffId || p.assignedStaffId == staffId)
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  // Stream all patients (for Admin)
  Stream<List<Patient>> watchAllPatients({bool includeDeleted = false}) {
    Query<Map<String, dynamic>> query = _firestore.collection('patients');
    
    if (!includeDeleted) {
      query = query.where('isDeleted', isEqualTo: false);
    }
    
    return query.snapshots().map((snapshot) {
      final list = snapshot.docs.map((doc) => Patient.fromMap(doc.data(), doc.id)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<void> createPatient(Patient patient, {String? userName}) async {
    final docRef = _firestore.collection('patients').doc();
    
    final batch = _firestore.batch();
    batch.set(docRef, patient.toMap());

    // Log activity client-side
    final activityRef = _firestore.collection('activities').doc();
    batch.set(activityRef, {
      'userId': patient.createdBy,
      'userName': (userName != null && userName.isNotEmpty) ? userName : 'Staff User',
      'role': 'staff',
      'action': 'PATIENT_CREATED',
      'entityType': 'patient',
      'entityId': docRef.id,
      'description': 'Registered patient ${patient.patientName}',
      'organizationId': patient.organizationId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Update system metrics client-side (replaces Cloud Function trigger)
    final metricsRef = _firestore.collection('system_metrics').doc('stats_${patient.organizationId}');
    batch.set(metricsRef, {
      'totalPatients': FieldValue.increment(1),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> updatePatient(Patient patient) async {
    await _firestore.collection('patients').doc(patient.patientId).update(patient.toMap());
  }

  /// Soft-delete a patient and all their associated invoices
  Future<void> softDeletePatient({
    required String patientId,
    required String patientName,
    required String userId,
    required String organizationId,
  }) async {
    final batch = _firestore.batch();

    batch.update(_firestore.collection('patients').doc(patientId), {
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': userId,
    });

    // Soft-delete all associated invoices
    final invoicesSnap = await _firestore
        .collection('invoices')
        .where('patientId', isEqualTo: patientId)
        .get();

    for (final doc in invoicesSnap.docs) {
      batch.update(doc.reference, {
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedBy': userId,
      });
    }

    // Update system metrics
    final metricsRef = _firestore.collection('system_metrics').doc('stats_$organizationId');
    batch.set(metricsRef, {
      'totalPatients': FieldValue.increment(-1),
      'totalInvoices': FieldValue.increment(-invoicesSnap.docs.length),
    }, SetOptions(merge: true));

    // Log activity
    final activityRef = _firestore.collection('activities').doc();
    batch.set(activityRef, {
      'userId': userId,
      'userName': 'User',
      'action': 'PATIENT_DELETED',
      'entityType': 'patient',
      'entityId': patientId,
      'description': 'Soft-deleted patient $patientName and ${invoicesSnap.docs.length} associated invoice(s)',
      'organizationId': organizationId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Recalculate system_metrics from live database records and sync stats document
  Future<void> syncSystemMetrics({String organizationId = 'default'}) async {
    final patientsSnap = await _firestore
        .collection('patients')
        .where('isDeleted', isEqualTo: false)
        .get();

    final invoicesSnap = await _firestore
        .collection('invoices')
        .where('isDeleted', isEqualTo: false)
        .get();

    int patientCount = patientsSnap.docs.length;
    int invoiceCount = invoicesSnap.docs.length;
    double totalInvoiceRev = 0.0;
    double totalPayout = 0.0;

    final patientPayoutMap = <String, double>{};
    final patientDaysMap = <String, int>{};
    for (final doc in patientsSnap.docs) {
      final data = doc.data();
      patientPayoutMap[doc.id] = (data['staffPayment'] ?? 0.0).toDouble();
      patientDaysMap[doc.id] = (data['days'] is num ? (data['days'] as num).toInt() : 0);
    }

    for (final doc in invoicesSnap.docs) {
      final data = doc.data();
      final isDiscontinued = data['isDiscontinued'] == true;
      if (!isDiscontinued) {
        // Both Paid and Unpaid valid invoices contribute to Revenue
        totalInvoiceRev += (data['grandTotal'] ?? 0.0).toDouble();

        final patientId = data['patientId'] ?? '';
        final totalStaffPayment = patientPayoutMap[patientId] ?? (data['staffPayment'] ?? 0.0).toDouble();
        final pDays = patientDaysMap[patientId] ?? 0;
        final staffDailyRate = totalStaffPayment > 0 ? (totalStaffPayment / (pDays > 0 ? pDays : 30)) : 0.0;
        
        int invoiceDays = 0;
        if (data['days'] is num) {
          invoiceDays = (data['days'] as num).toInt();
        } else if (data['items'] is List && (data['items'] as List).isNotEmpty) {
          final firstItem = (data['items'] as List).first;
          if (firstItem is Map && firstItem['quantity'] != null) {
            invoiceDays = (firstItem['quantity'] as num).toInt();
          }
        }
        if (invoiceDays <= 0) invoiceDays = 1;

        totalPayout += invoiceDays * staffDailyRate;
      }
    }

    double netProfit = totalInvoiceRev - totalPayout;

    final metricsRef = _firestore.collection('system_metrics').doc('stats_$organizationId');
    await metricsRef.set({
      'totalPatients': patientCount,
      'totalInvoices': invoiceCount,
      'totalRevenue': netProfit,
      'lastSyncedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Restore a soft-deleted patient and all their associated invoices (Admin only, replaces restorePatient Cloud Function)
  Future<void> restorePatient({
    required String patientId,
    required String patientName,
    required String userId,
    required String organizationId,
  }) async {
    final batch = _firestore.batch();

    batch.update(_firestore.collection('patients').doc(patientId), {
      'isDeleted': false,
      'deletedAt': FieldValue.delete(),
      'deletedBy': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': userId,
    });

    // Restore associated invoices
    final invoicesSnap = await _firestore
        .collection('invoices')
        .where('patientId', isEqualTo: patientId)
        .get();

    for (final doc in invoicesSnap.docs) {
      batch.update(doc.reference, {
        'isDeleted': false,
        'deletedAt': FieldValue.delete(),
        'deletedBy': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': userId,
      });
    }

    // Log activity
    final activityRef = _firestore.collection('activities').doc();
    batch.set(activityRef, {
      'userId': userId,
      'userName': 'Admin',
      'action': 'PATIENT_RESTORED',
      'entityType': 'patient',
      'entityId': patientId,
      'description': 'Restored patient $patientName and associated invoices',
      'organizationId': organizationId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Discontinue a patient and lock all their associated invoices
  Future<void> discontinuePatient({
    required String patientId,
    required String patientName,
    required String userId,
    required String organizationId,
    String? userName,
  }) async {
    final batch = _firestore.batch();

    batch.update(_firestore.collection('patients').doc(patientId), {
      'isDiscontinued': true,
      'status': 'discontinued',
      'discontinuedAt': FieldValue.serverTimestamp(),
      'discontinuedBy': userId,
    });

    // Update all associated invoices
    final invoicesSnap = await _firestore
        .collection('invoices')
        .where('patientId', isEqualTo: patientId)
        .get();

    for (final doc in invoicesSnap.docs) {
      batch.update(doc.reference, {
        'isDiscontinued': true,
        'discontinuedAt': FieldValue.serverTimestamp(),
        'discontinuedBy': userId,
      });
    }

    // Log activity
    final activityRef = _firestore.collection('activities').doc();
    batch.set(activityRef, {
      'userId': userId,
      'userName': (userName != null && userName.isNotEmpty) ? userName : 'User',
      'action': 'PATIENT_DISCONTINUED',
      'entityType': 'patient',
      'entityId': patientId,
      'description': 'Discontinued patient $patientName and locked associated records',
      'organizationId': organizationId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Reactivate a discontinued patient and restore their associated invoices
  Future<void> reactivatePatient({
    required String patientId,
    required String patientName,
    required String userId,
    required String organizationId,
    String? userName,
  }) async {
    final batch = _firestore.batch();

    batch.update(_firestore.collection('patients').doc(patientId), {
      'isDiscontinued': false,
      'status': 'active',
      'reactivatedAt': FieldValue.serverTimestamp(),
      'reactivatedBy': userId,
    });

    // Restore all associated invoices
    final invoicesSnap = await _firestore
        .collection('invoices')
        .where('patientId', isEqualTo: patientId)
        .get();

    for (final doc in invoicesSnap.docs) {
      batch.update(doc.reference, {
        'isDiscontinued': false,
        'reactivatedAt': FieldValue.serverTimestamp(),
        'reactivatedBy': userId,
      });
    }

    // Log activity
    final activityRef = _firestore.collection('activities').doc();
    batch.set(activityRef, {
      'userId': userId,
      'userName': (userName != null && userName.isNotEmpty) ? userName : 'User',
      'action': 'PATIENT_REACTIVATED',
      'entityType': 'patient',
      'entityId': patientId,
      'description': 'Reactivated patient $patientName and restored associated records',
      'organizationId': organizationId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }
  
  /// Read-only preview of next MR Number (does NOT increment database counter)
  Future<String> previewNextMRNumber() async {
    final docRef = _firestore.collection('system_metrics').doc('mr_counter');
    final snapshot = await docRef.get();
    int current = 4000;
    if (snapshot.exists) {
      current = snapshot.data()?['current'] ?? 4000;
    }
    final nextCount = current + 1;
    final now = DateTime.now();
    final dateStr = '${now.year.toString().substring(2)}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'SHHC-$dateStr-$nextCount';
  }

  Future<String> getNextMRNumber() async {
    final docRef = _firestore.collection('system_metrics').doc('mr_counter');
    
    final int nextCount = await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) {
        transaction.set(docRef, {'current': 4000});
        return 4000;
      } else {
        int current = snapshot.data()?['current'] ?? 4000;
        int next = current + 1;
        transaction.update(docRef, {'current': next});
        return next;
      }
    });
    
    final now = DateTime.now();
    final dateStr = '${now.year.toString().substring(2)}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'SHHC-$dateStr-$nextCount';
  }
}

// Providers for UI consumption
final staffPatientsProvider = StreamProvider<List<Patient>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value([]);
  return ref.watch(patientRepositoryProvider).watchStaffPatients(user.uid);
});

final allPatientsProvider = StreamProvider.family<List<Patient>, bool>((ref, includeDeleted) {
  return ref.watch(patientRepositoryProvider).watchAllPatients(includeDeleted: includeDeleted);
});
