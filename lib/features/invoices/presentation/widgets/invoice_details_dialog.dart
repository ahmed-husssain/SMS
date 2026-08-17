import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../../core/errors/app_error.dart';
import '../../domain/invoice_model.dart';
import '../../data/invoice_repository.dart';
import '../../../patients/domain/patient_model.dart';
import '../../../../shared/providers/auth_provider.dart';

class InvoiceDetailsDialog extends ConsumerStatefulWidget {
  final Invoice invoice;

  const InvoiceDetailsDialog({super.key, required this.invoice});

  @override
  ConsumerState<InvoiceDetailsDialog> createState() => _InvoiceDetailsDialogState();
}

class _InvoiceDetailsDialogState extends ConsumerState<InvoiceDetailsDialog> {
  bool _isEditing = false;
  bool _isLoadingPatient = true;
  bool _isSaving = false;
  Patient? _patient;

  // Controllers
  late TextEditingController _invoiceNumberController;
  late TextEditingController _discountController;
  late TextEditingController _patientNameController;
  late TextEditingController _patientPhoneController;
  late TextEditingController _patientAddressController;
  late String _paymentStatus;
  String _creatorName = 'Loading...';
  String _creatorRole = '';

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _invoiceNumberController = TextEditingController(text: widget.invoice.invoiceNumber);
    _discountController = TextEditingController(text: widget.invoice.discount.toStringAsFixed(0));
    _paymentStatus = widget.invoice.paymentStatus;
    
    _patientNameController = TextEditingController();
    _patientPhoneController = TextEditingController();
    _patientAddressController = TextEditingController();

    _loadPatientData();
    _loadCreatorInfo();
  }

  Future<void> _loadCreatorInfo() async {
    if (widget.invoice.createdByName != null && widget.invoice.createdByName!.isNotEmpty) {
      if (mounted) {
        setState(() {
          _creatorName = widget.invoice.createdByName!;
          _creatorRole = widget.invoice.createdByRole ?? 'Staff';
        });
      }
      return;
    }

    final creatorUid = widget.invoice.createdByUid ?? 
                       (widget.invoice.createdBy.isNotEmpty ? widget.invoice.createdBy : widget.invoice.staffId);

    if (creatorUid.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(creatorUid).get();
        if (doc.exists && mounted) {
          final data = doc.data()!;
          setState(() {
            _creatorName = data['name'] ?? data['username'] ?? data['email'] ?? 'Unknown';
            _creatorRole = data['role'] ?? 'Staff';
          });
          return;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _creatorName = 'Unknown';
        _creatorRole = 'N/A';
      });
    }
  }

  Future<void> _loadPatientData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.invoice.patientId)
          .get();
      if (doc.exists && mounted) {
        final p = Patient.fromMap(doc.data()!, doc.id);
        setState(() {
          _patient = p;
          _patientNameController.text = p.patientName;
          _patientPhoneController.text = p.phone;
          _patientAddressController.text = p.address;
          _isLoadingPatient = false;
        });
      } else if (mounted) {
        setState(() {
          _isLoadingPatient = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingPatient = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _discountController.dispose();
    _patientNameController.dispose();
    _patientPhoneController.dispose();
    _patientAddressController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final repo = ref.read(invoiceRepositoryProvider);
      
      // 1. Update Patient details in Firestore if loaded
      if (_patient != null) {
        final updatedPatient = Patient(
          patientId: _patient!.patientId,
          mrNumber: _patient!.mrNumber,
          patientName: _patientNameController.text.trim(),
          cnic: _patient!.cnic,
          phone: _patientPhoneController.text.trim(),
          address: _patientAddressController.text.trim(),
          diagnosis: _patient!.diagnosis,
          doctor: _patient!.doctor,
          nurse: _patient!.nurse,
          caretaker: _patient!.caretaker,
          selectedServices: _patient!.selectedServices,
          monthlyServiceCost: _patient!.monthlyServiceCost,
          patientAmount: _patient!.patientAmount,
          staffPayment: _patient!.staffPayment,
          profit: _patient!.profit,
          assignedStaffId: _patient!.assignedStaffId,
          organizationId: _patient!.organizationId,
          createdBy: _patient!.createdBy,
          createdAt: _patient!.createdAt,
          updatedBy: _patient!.updatedBy,
          updatedAt: DateTime.now(),
          isDeleted: _patient!.isDeleted,
          deletedAt: _patient!.deletedAt,
          deletedBy: _patient!.deletedBy,
        );
        await FirebaseFirestore.instance
            .collection('patients')
            .doc(_patient!.patientId)
            .update(updatedPatient.toMap());
      }

      // 2. Recalculate totals
      final discount = double.tryParse(_discountController.text) ?? 0.0;
      final grandTotal = widget.invoice.subtotal - discount;

      // 3. Update Invoice in Firestore
      final updatedInvoice = Invoice(
        invoiceId: widget.invoice.invoiceId,
        invoiceNumber: _invoiceNumberController.text.trim(),
        patientId: widget.invoice.patientId,
        staffId: widget.invoice.staffId,
        subtotal: widget.invoice.subtotal,
        discount: discount,
        grandTotal: grandTotal,
        items: widget.invoice.items,
        organizationId: widget.invoice.organizationId,
        createdBy: widget.invoice.createdBy,
        createdAt: widget.invoice.createdAt,
        updatedBy: widget.invoice.updatedBy,
        updatedAt: DateTime.now(),
        isDeleted: widget.invoice.isDeleted,
        deletedAt: widget.invoice.deletedAt,
        deletedBy: widget.invoice.deletedBy,
        paymentStatus: _paymentStatus,
        fromDate: widget.invoice.fromDate,
        toDate: widget.invoice.toDate,
        createdByName: widget.invoice.createdByName,
        createdByRole: widget.invoice.createdByRole,
        createdByUid: widget.invoice.createdByUid,
      );

      await repo.updateInvoice(updatedInvoice, previousPaymentStatus: widget.invoice.paymentStatus);

      // Invalidate providers to refresh Invoices List page
      ref.invalidate(staffInvoicesProvider);
      ref.invalidate(allInvoicesProvider(false));
      ref.invalidate(allInvoicesProvider(true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice updated successfully')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = AppError.map(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteInvoice() async {
    final profile = ref.read(userProfileProvider).value;
    final role = profile?['role'] ?? 'staff';
    if (role != 'admin') return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Invoice'),
        content: const Text('Are you sure you want to delete this invoice?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isSaving = true);
      try {
        final repo = ref.read(invoiceRepositoryProvider);
        await repo.deleteInvoice(widget.invoice.invoiceId);

        // Invalidate providers to refresh Invoices List page
        ref.invalidate(staffInvoicesProvider);
        ref.invalidate(allInvoicesProvider(false));
        ref.invalidate(allInvoicesProvider(true));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invoice deleted successfully')),
          );
          Navigator.of(context).pop(); // Close details modal
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPatient) {
      return const AlertDialog(
        content: Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final profile = ref.watch(userProfileProvider).value;
    final role = profile?['role'] ?? 'staff';

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _isEditing ? 'Edit Invoice Details' : 'Invoice Details',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (!_isEditing && role == 'admin')
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete Invoice',
              onPressed: _deleteInvoice,
            ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.85,
        child: SingleChildScrollView(
          child: _isEditing ? _buildEditForm() : _buildDetailsView(),
        ),
      ),
      actions: _isSaving
          ? [const CircularProgressIndicator()]
          : [
              if (_isEditing) ...[
                TextButton(
                  onPressed: () => setState(() => _isEditing = false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save'),
                ),
              ] else ...[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _isEditing = true),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                  ),
                ),
              ]
            ],
    );
  }

  Widget _buildDetailsView() {
    final dateStr = DateFormat('dd/MM/yyyy hh:mm a').format(widget.invoice.createdAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Metadata ---
        _buildSectionTitle('Invoice Metadata'),
        _buildInfoRow('Grand Total', 'Rs. ${NumberFormat('#,###').format(widget.invoice.grandTotal.toInt())}'),
        _buildInfoRow('Date & Time', dateStr),
        if (widget.invoice.fromDate != null)
          _buildInfoRow('Service From', DateFormat('dd/MM/yyyy').format(widget.invoice.fromDate!)),
        if (widget.invoice.toDate != null)
          _buildInfoRow('Service To', DateFormat('dd/MM/yyyy').format(widget.invoice.toDate!)),
        _buildInfoRow('Payment Status', widget.invoice.paymentStatus.toUpperCase(), 
          valueColor: widget.invoice.paymentStatus.trim().toLowerCase() == 'paid' ? Colors.green.shade700 : Colors.red.shade700),
        _buildInfoRow('Created By', _creatorName),
        if (_creatorRole.isNotEmpty && _creatorRole != 'N/A')
          _buildInfoRow('Role', _creatorRole.toUpperCase()),
        const SizedBox(height: 16),

        // --- Patient ---
        _buildSectionTitle('Patient Information'),
        _buildInfoRow('Patient Name', _patient?.patientName ?? 'N/A'),
        _buildInfoRow('MR Number', _patient?.mrNumber ?? 'N/A'),
        _buildInfoRow('Phone Number', _patient?.phone ?? 'N/A'),
        _buildInfoRow('Address', _patient?.address ?? 'N/A'),
        const SizedBox(height: 16),

        // --- Service Details ---
        _buildSectionTitle('Service Details'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Header
              Container(
                color: const Color(0xFF1E293B),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        'Service',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Rate',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        'Qty',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Total',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
              // Service Items
              ...widget.invoice.items.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                final isEven = idx % 2 == 0;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isEven ? Colors.white : const Color(0xFFF8FAFC),
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          item.serviceName,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Rs. ${NumberFormat('#,###').format(item.price.toInt())}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          '${item.quantity}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF334155),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Rs. ${NumberFormat('#,###').format(item.total.toInt())}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E40AF),
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Summary Breakdown Box
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Subtotal', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  Text(
                    'Rs. ${NumberFormat('#,###').format(widget.invoice.subtotal.toInt())}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                  ),
                ],
              ),
              if (widget.invoice.discount > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Discount', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    Text(
                      '- Rs. ${NumberFormat('#,###').format(widget.invoice.discount.toInt())}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red.shade700),
                    ),
                  ],
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6.0),
                child: Divider(height: 1, color: Color(0xFFCBD5E1)),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Grand Total', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  Text(
                    'Rs. ${NumberFormat('#,###').format(widget.invoice.grandTotal.toInt())}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Invoice Details'),
          TextFormField(
            controller: _discountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Discount Amount (PKR)', border: OutlineInputBorder()),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (double.tryParse(v) == null) return 'Must be a valid number';
              return null;
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _paymentStatus,
            decoration: const InputDecoration(labelText: 'Payment Status', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'Paid', child: Text('Paid')),
              DropdownMenuItem(value: 'Unpaid', child: Text('Unpaid')),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() => _paymentStatus = val);
              }
            },
          ),
          const SizedBox(height: 16),
          _buildSectionTitle('Patient Information'),
          TextFormField(
            controller: _patientNameController,
            decoration: const InputDecoration(labelText: 'Patient Name', border: OutlineInputBorder()),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _patientPhoneController,
            decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder()),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _patientAddressController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder()),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1565C0)),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    final displayValue = value.isEmpty ? 'N/A' : value;
    final isCopyable = (label.contains('MR') ||
        label.contains('Name') ||
        label.contains('Phone') ||
        label.contains('Address') ||
        label.contains('Invoice'));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isCopyable ? FontWeight.bold : FontWeight.normal,
                color: isCopyable ? const Color(0xFF1565C0) : Colors.grey.shade600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () {
                if (isCopyable && displayValue != 'N/A') {
                  Clipboard.setData(ClipboardData(text: displayValue));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓ Copied $label: $displayValue'),
                      duration: const Duration(seconds: 2),
                      backgroundColor: const Color(0xFF004B93),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: SelectableText(
                        displayValue,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: displayValue == 'N/A' ? Colors.grey : valueColor,
                        ),
                      ),
                    ),
                    if (isCopyable && displayValue != 'N/A') ...[
                      const SizedBox(width: 4),
                      Icon(Icons.copy_rounded, size: 13, color: Colors.blue.shade700),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
