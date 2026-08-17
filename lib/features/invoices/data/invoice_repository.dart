import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/invoice_model.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../patients/data/patient_repository.dart';

final invoiceRepositoryProvider = Provider<InvoiceRepository>((ref) {
  return InvoiceRepository(
    firestore: ref.watch(firestoreProvider),
  );
});

class InvoiceRepository {
  final FirebaseFirestore _firestore;

  InvoiceRepository({required this._firestore});

  Stream<List<Invoice>> watchStaffInvoices(String staffId, {Set<String>? staffPatientIds, int limit = 500}) {
    return _firestore
        .collection('invoices')
        .where('isDeleted', isEqualTo: false)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => Invoice.fromMap(doc.data(), doc.id))
          .where((inv) {
            if (inv.isDiscontinued) return false;
            final isForStaffPatient = staffPatientIds != null && staffPatientIds.contains(inv.patientId);
            final isCreatedByStaff = inv.createdBy == staffId || inv.staffId == staffId;
            return isForStaffPatient || isCreatedByStaff;
          })
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Stream<List<Invoice>> watchAllInvoices({bool includeDeleted = false, int limit = 500}) {
    Query<Map<String, dynamic>> query = _firestore.collection('invoices');
    
    if (!includeDeleted) {
      query = query.where('isDeleted', isEqualTo: false);
    }
    
    return query.limit(limit).snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => Invoice.fromMap(doc.data(), doc.id))
          .where((inv) => !inv.isDiscontinued)
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<String> createInvoice(Invoice invoice, {String? userName}) async {
    final docRef = _firestore.collection('invoices').doc();
    
    final batch = _firestore.batch();
    batch.set(docRef, invoice.toMap());

    // Log the activity client-side
    final activityRef = _firestore.collection('activities').doc();
    batch.set(activityRef, {
      'userId': invoice.createdBy,
      'userName': (userName != null && userName.isNotEmpty) ? userName : 'Staff User',
      'role': 'staff',
      'action': 'INVOICE_CREATED',
      'entityType': 'invoice',
      'entityId': docRef.id,
      'description': 'Created an invoice for patient ${invoice.patientId} for ${invoice.grandTotal}',
      'organizationId': invoice.organizationId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Update invoice count in system_metrics (totalRevenue is computed dynamically from streams)
    final metricsRef = _firestore.collection('system_metrics').doc('stats_${invoice.organizationId}');
    batch.set(metricsRef, {
      'totalInvoices': FieldValue.increment(1),
    }, SetOptions(merge: true));

    await batch.commit();
    return docRef.id;
  }

  /// Updates an invoice. [previousPaymentStatus] is accepted for API clarity
  /// but totalRevenue is computed dynamically from streams — no metrics write needed.
  Future<void> updateInvoice(Invoice invoice, {String? previousPaymentStatus}) async {
    await _firestore.collection('invoices').doc(invoice.invoiceId).update(invoice.toMap());
  }

  Future<void> deleteInvoice(String invoiceId) async {
    final docRef = _firestore.collection('invoices').doc(invoiceId);
    final snap = await docRef.get();
    if (snap.exists) {
      final inv = Invoice.fromMap(snap.data()!, invoiceId);
      final batch = _firestore.batch();
      batch.update(docRef, {'isDeleted': true});

      // Decrement invoice count only — totalRevenue is computed dynamically from streams
      final metricsRef = _firestore.collection('system_metrics').doc('stats_${inv.organizationId}');
      batch.set(metricsRef, {
        'totalInvoices': FieldValue.increment(-1),
      }, SetOptions(merge: true));

      await batch.commit();
    }
  }
}

final staffInvoicesProvider = StreamProvider<List<Invoice>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value([]);

  final staffPatientsAsync = ref.watch(staffPatientsProvider);
  final allInvoicesAsync = ref.watch(allInvoicesProvider(false));

  final staffPatients = staffPatientsAsync.value ?? [];
  final allInvoices = allInvoicesAsync.value ?? [];

  final staffPatientIds = staffPatients.map((p) => p.patientId).toSet();

  final list = allInvoices.where((inv) {
    if (inv.isDeleted || inv.isDiscontinued) return false;
    final isForStaffPatient = staffPatientIds.contains(inv.patientId);
    final isCreatedByStaff = inv.createdBy == user.uid || inv.staffId == user.uid;
    return isForStaffPatient || isCreatedByStaff;
  }).toList();

  list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return Stream.value(list);
});

final allInvoicesProvider = StreamProvider.family<List<Invoice>, bool>((ref, includeDeleted) {
  return ref.watch(invoiceRepositoryProvider).watchAllInvoices(includeDeleted: includeDeleted);
});
