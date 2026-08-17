import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/errors/app_error.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/invoice_model.dart';
import '../data/invoice_repository.dart';
import '../utils/invoice_exporter.dart';
import 'pages/invoices_page.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../patients/domain/patient_model.dart';
import '../../patients/data/patient_repository.dart';

const Map<String, double> SERVICE_PRICES = {
  "SELECT SERVICE": 0,
  "Online Doctor Consultation": 0,
  "Home Physiotherapy": 3000,
  "Home Physiotherapy Services": 3000,
  "Home Nursing Care": 3000,
  "Home Nursing Care Services": 3000,
  "Home Attendant Care": 2000,
  "Home Attendant Service": 2000,
  "Home Nurse Visit": 2000,
  "Home NG Tube Insertion": 2500,
  "Wound & Bedsores Care": 2000,
  "Wound & Bed Sore Dressing": 2000,
  "Home ICU Nurse": 3500,
  "Home ICU Nurse Setup": 3500,
  "Medical Equipment": 0,
  "Medical Equipment Rental": 0,
  "Custom Service": 0,
};

class InvoiceFormScreen extends ConsumerStatefulWidget {
  final String? patientId;
  final int defaultDays;

  const InvoiceFormScreen({
    super.key,
    this.patientId,
    this.defaultDays = 15,
  });

  @override
  ConsumerState<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends ConsumerState<InvoiceFormScreen> {
  final List<InvoiceItem> _items = [];
  double _discount = 0.0;
  bool _isLoading = false;
  Patient? _patient;
  String _paymentStatus = 'Unpaid';
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  String? _invoiceNumber;

  final TextEditingController _mrNumberController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _cnicController = TextEditingController();
  bool _isSearchingPatient = false;
  String? _searchStatusMessage;

  @override
  void initState() {
    super.initState();
    if (widget.patientId != null && widget.patientId!.isNotEmpty) {
      _loadPatient();
    }
    _generateInvoiceNumber();
  }

  @override
  void dispose() {
    _mrNumberController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cnicController.dispose();
    super.dispose();
  }

  Future<void> _generateInvoiceNumber() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('invoices')
          .get();

      int highest = 4999;
      for (final doc in snap.docs) {
        final data = doc.data();
        final existingNum = data['invoiceNumber'] as String? ?? '';
        final parsed = int.tryParse(existingNum.replaceAll(RegExp(r'[^0-9]'), ''));
        if (parsed != null && parsed > highest) {
          highest = parsed;
        }
      }

      int nextNumber = highest + 1;
      if (nextNumber < 5000) {
        nextNumber = 5000;
      }

      setState(() {
        _invoiceNumber = 'SHHC-$nextNumber';
      });
    } catch (_) {
      setState(() {
        _invoiceNumber = 'SHHC-5000';
      });
    }
  }

  Future<void> _loadPatient() async {
    if (widget.patientId == null || widget.patientId!.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.patientId)
          .get();
      if (doc.exists) {
        final p = Patient.fromMap(doc.data()!, doc.id);
        _populatePatientData(p, defaultDays: widget.defaultDays);
      }
    } catch (e) {
      // Silently fail
    }
  }

  Future<void> _searchPatientByMRNumber(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _isSearchingPatient = true;
      _searchStatusMessage = null;
    });

    try {
      // 1. Search by exact mrNumber
      var snap = await FirebaseFirestore.instance
          .collection('patients')
          .where('mrNumber', isEqualTo: trimmed)
          .get();

      // 2. Search by uppercase mrNumber
      if (snap.docs.isEmpty) {
        snap = await FirebaseFirestore.instance
            .collection('patients')
            .where('mrNumber', isEqualTo: trimmed.toUpperCase())
            .get();
      }

      // 3. Search by doc ID
      if (snap.docs.isEmpty) {
        final docSnap = await FirebaseFirestore.instance
            .collection('patients')
            .doc(trimmed)
            .get();
        if (docSnap.exists) {
          final p = Patient.fromMap(docSnap.data()!, docSnap.id);
          _populatePatientData(p);
          return;
        }
      }

      if (snap.docs.isNotEmpty) {
        final p = Patient.fromMap(snap.docs.first.data(), snap.docs.first.id);
        final user = ref.read(authStateProvider).value;
        final profile = ref.read(userProfileProvider).value;
        final role = profile?['role'] ?? 'staff';

        if (role == 'staff' && user != null && p.assignedStaffId != user.uid && p.createdBy != user.uid) {
          setState(() {
            _isSearchingPatient = false;
            _searchStatusMessage = 'Access Denied: Patient belongs to another staff member.';
          });
          return;
        }

        _populatePatientData(p);
      } else {
        setState(() {
          _isSearchingPatient = false;
          _searchStatusMessage = 'No patient found for MR: "$trimmed". Fill details below.';
        });
      }
    } catch (e) {
      setState(() {
        _isSearchingPatient = false;
        _searchStatusMessage = 'Lookup error: $e';
      });
    }
  }

  void _selectPatientFromList() {
    final profile = ref.read(userProfileProvider).value;
    final role = profile?['role'] ?? 'staff';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final patientsAsync = role == 'admin'
                ? ref.watch(allPatientsProvider(false))
                : ref.watch(staffPatientsProvider);

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              builder: (_, scrollController) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        role == 'admin' ? 'Select Patient' : 'Select My Patient',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: patientsAsync.when(
                          data: (patients) {
                            final activePatients = patients.where((p) => !p.isDiscontinued).toList();
                            if (activePatients.isEmpty) {
                              return const Center(child: Text('No registered active patients found.'));
                            }
                            return ListView.separated(
                              controller: scrollController,
                              itemCount: activePatients.length,
                              separatorBuilder: (_, __) => const Divider(),
                              itemBuilder: (context, index) {
                                final p = activePatients[index];
                                return ListTile(
                                  leading: const CircleAvatar(child: Icon(Icons.person)),
                                  title: Text(p.patientName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text('MR: ${p.mrNumber} • CNIC: ${p.cnic}'),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _populatePatientData(p);
                                  },
                                );
                              },
                            );
                          },
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Center(child: Text('Error: $e')),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _populatePatientData(Patient p, {int defaultDays = 15}) {
    setState(() {
      _patient = p;
      _mrNumberController.text = p.mrNumber;
      _nameController.text = p.patientName;
      _phoneController.text = p.phone;
      _addressController.text = p.address;
      _cnicController.text = p.cnic;
      _isSearchingPatient = false;

      _toDate = _fromDate.add(Duration(days: defaultDays));

      // Automatically populate invoice items with patient's registered services (15-days calculation)
      _items.clear();
      if (p.selectedServices.isNotEmpty) {
        for (final s in p.selectedServices) {
          final sName = (s['serviceName'] ?? s['name'] ?? '').toString();
          if (sName.isNotEmpty) {
            double price = 0.0;
            if (s['dailyPrice'] != null) {
              price = (s['dailyPrice'] as num).toDouble();
            } else if (s['price'] != null) {
              price = (s['price'] as num).toDouble();
            }
            if (price <= 0 && SERVICE_PRICES.containsKey(sName)) {
              price = SERVICE_PRICES[sName]!;
            }
            _items.add(InvoiceItem(
              serviceName: sName,
              price: price,
              quantity: defaultDays, // 15 days calculation
            ));
          }
        }
      }

      // If no selectedServices array exists but patientAmount is set, add fallback item
      if (_items.isEmpty && p.patientAmount > 0) {
        final dailyPrice = (p.patientAmount / defaultDays).roundToDouble();
        _items.add(InvoiceItem(
          serviceName: 'Patient Healthcare Service',
          price: dailyPrice > 0 ? dailyPrice : p.patientAmount,
          quantity: defaultDays,
        ));
      }

      // If still empty, add default blank service row
      if (_items.isEmpty) {
        _items.add(InvoiceItem(serviceName: '', price: 0, quantity: defaultDays));
      }

      _searchStatusMessage = '✓ Loaded patient ${p.patientName} & calculated for $defaultDays days (${_items.length} service(s))';
    });
  }

  void _addItem() {
    setState(() {
      _items.add(InvoiceItem(serviceName: '', price: 0, quantity: 1));
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  void _updateItem(int index, {String? name, double? price, int? qty}) {
    setState(() {
      _items[index] = InvoiceItem(
        serviceName: name ?? _items[index].serviceName,
        price: price ?? _items[index].price,
        quantity: qty ?? _items[index].quantity,
      );
    });
  }

  double get _subtotal => _items.fold(0, (sum, item) => sum + item.total);
  double get _grandTotal => _subtotal - _discount;

  Future<void> _submit(String format) async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one item')),
      );
      return;
    }

    final mrNum = _mrNumberController.text.trim();
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final address = _addressController.text.trim();

    if (mrNum.isEmpty && name.isEmpty && _patient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an MR Number or Patient Name')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(invoiceRepositoryProvider);
      final user = ref.read(authStateProvider).value;

      if (user == null) throw Exception("User not logged in");

      // Auto-create or update Patient in Firestore
      if (_patient == null) {
        final pDoc = FirebaseFirestore.instance.collection('patients').doc();
        final newPatient = Patient(
          patientId: pDoc.id,
          mrNumber: mrNum.isEmpty
              ? 'SHHC-${DateFormat('yyMMdd').format(DateTime.now())}-${(1000 + DateTime.now().millisecond)}'
              : mrNum,
          patientName: name.isEmpty ? 'Patient' : name,
          cnic: _cnicController.text.trim(),
          phone: phone,
          address: address,
          diagnosis: '',
          doctor: '',
          nurse: '',
          caretaker: '',
          selectedServices: [],
          monthlyServiceCost: 0,
          patientAmount: 0,
          staffPayment: 0,
          profit: 0,
          assignedStaffId: user.uid,
          organizationId: 'default',
          createdBy: user.uid,
          createdAt: DateTime.now(),
          updatedBy: user.uid,
          updatedAt: DateTime.now(),
          isDeleted: false,
        );
        await pDoc.set(newPatient.toMap());
        _patient = newPatient;
      } else {
        // Update patient info if edited
        _patient = Patient(
          patientId: _patient!.patientId,
          mrNumber: mrNum.isNotEmpty ? mrNum : _patient!.mrNumber,
          patientName: name.isNotEmpty ? name : _patient!.patientName,
          cnic: _cnicController.text.trim().isNotEmpty ? _cnicController.text.trim() : _patient!.cnic,
          phone: phone.isNotEmpty ? phone : _patient!.phone,
          address: address.isNotEmpty ? address : _patient!.address,
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
          updatedBy: user.uid,
          updatedAt: DateTime.now(),
          isDeleted: _patient!.isDeleted,
        );
      }

      final profile = ref.read(userProfileProvider).value;
      final userName = profile?['name'] ?? profile?['username'] ?? 'Staff User';
      final userRole = profile?['role'] ?? 'staff';

      final invoice = Invoice(
        invoiceId: '',
        invoiceNumber: _invoiceNumber ?? 'N/A',
        patientId: _patient!.patientId,
        staffId: user.uid,
        subtotal: _subtotal,
        discount: _discount,
        grandTotal: _grandTotal,
        items: _items,
        organizationId: 'default',
        createdBy: user.uid,
        createdByUid: user.uid,
        createdByName: userName,
        createdByRole: userRole,
        createdAt: DateTime.now(),
        updatedBy: user.uid,
        updatedAt: DateTime.now(),
        isDeleted: false,
        paymentStatus: _paymentStatus,
        fromDate: _fromDate,
        toDate: _toDate,
      );

      final newDocId = await repo.createInvoice(invoice, userName: userName);

      if (mounted) {
        // Highlight the newly created invoice on the Invoices page
        ref.read(recentInvoiceHighlightProvider.notifier).setHighlight(newDocId);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Invoice generated successfully! Redirecting to Invoices...'),
            backgroundColor: Color(0xFF16A34A),
            duration: Duration(seconds: 3),
          ),
        );

        // Perform export / direct file save action
        await _showExportOptions(invoice, format);

        // Redirect to Invoices screen where newly created invoice will be highlighted
        if (mounted) {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
          context.go('/invoices');
        }
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = AppError.map(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showExportOptions(Invoice invoice, String format) async {
    // Generate PDF bytes first
    final pdfBytes = await InvoiceExporter.generatePdf(
      invoice,
      patient: _patient,
      invoiceNumber: _invoiceNumber ?? 'N/A',
    );
    
    final safePatientName = (_patient?.patientName ?? 'Patient').replaceAll(' ', '_');
    final mrNumber = (_patient?.mrNumber ?? 'MR').replaceAll(' ', '_');
    final fileName = 'invoice_${safePatientName}_$mrNumber';

    if (format == 'PRINT') {
      if (mounted) {
        await Printing.layoutPdf(onLayout: (_) => pdfBytes, name: fileName);
      }
      return;
    }

    final ext = format.toLowerCase() == 'jpg' ? 'jpg' : (format.toLowerCase() == 'png' ? 'png' : 'pdf');
    final fullFileName = '$fileName.$ext';

    Uint8List exportBytes = pdfBytes;
    if (format == 'PNG' || format == 'JPG') {
      await for (final page in Printing.raster(pdfBytes, pages: [0], dpi: 300)) {
        exportBytes = await page.toPng();
        break; // Only export the first page for images
      }
    }

    if (kIsWeb) {
      await Printing.sharePdf(bytes: exportBytes, filename: fullFileName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Saved $fullFileName directly to Downloads'),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      bool isSavedToGallery = false;
      List<String> savedPaths = [];

      if (Platform.isAndroid && (ext == 'png' || ext == 'jpg')) {
        try {
          const channel = MethodChannel('com.shifa.shifa_management/media_scanner');
          await channel.invokeMethod('saveImageToGallery', {
            'bytes': Uint8List.fromList(exportBytes),
            'filename': fullFileName,
          });
          isSavedToGallery = true;
        } catch (_) {}
      }

      if (Platform.isAndroid) {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          final file = File('${downloadDir.path}/$fullFileName');
          await file.writeAsBytes(exportBytes);
          savedPaths.add(file.path);
        }
      }

      if (savedPaths.isEmpty) {
        Directory? dir;
        try {
          dir = await getDownloadsDirectory();
        } catch (_) {}
        dir ??= await getApplicationDocumentsDirectory();

        final file = File('${dir.path}/$fullFileName');
        await file.writeAsBytes(exportBytes);
        savedPaths.add(file.path);
      }

      for (final path in savedPaths) {
        try {
          const channel = MethodChannel('com.shifa.shifa_management/media_scanner');
          await channel.invokeMethod('scanFile', {'path': path});
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isSavedToGallery
                  ? '✓ Saved $fullFileName directly to Photos Gallery & Downloads'
                  : '✓ Saved $fullFileName directly to Downloads folder',
            ),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _fromDate : _toDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Generate Invoice'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // ─── Invoice Header Card ───
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // ─── Header: Logo (Left) vs Invoice Details (Right) ───
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Left Side: Logo & Tagline
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.asset(
                                      'assets/Shifa_Logo-BG.png',
                                      width: 145,
                                      height: 50,
                                      fit: BoxFit.contain,
                                      alignment: Alignment.centerLeft,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Your Health, Our Mission',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1565C0),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Right Side: INVOICE, Invoice #, Dates, Payment Status
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'INVOICE',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1565C0),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Invoice #: ',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                    Text(
                                      _invoiceNumber ?? '...',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                // FROM Date Row
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'FROM:',
                                      style: TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade900,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () => _pickDate(true),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              DateFormat(
                                                'MM / dd / yyyy',
                                              ).format(_fromDate),
                                              style: const TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Icon(
                                              Icons.calendar_today_outlined,
                                              size: 11,
                                              color: Colors.grey.shade700,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                // TO Date Row
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'TO:',
                                      style: TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade900,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () => _pickDate(false),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              DateFormat(
                                                'MM / dd / yyyy',
                                              ).format(_toDate),
                                              style: const TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Icon(
                                              Icons.calendar_today_outlined,
                                              size: 11,
                                              color: Colors.grey.shade700,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                // Payment Status Selector
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'STATUS:',
                                      style: TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade900,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _paymentStatus,
                                          isDense: true,
                                          style: const TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                          items: ['Unpaid', 'Paid']
                                              .map(
                                                (s) => DropdownMenuItem(
                                                  value: s,
                                                  child: Text(s),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (val) => setState(
                                            () => _paymentStatus =
                                                val ?? 'Unpaid',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Horizontal Light Blue Divider Accent Line
                        Container(
                          height: 1,
                          color: const Color(0xFFDBEAFE),
                        ),
                        const SizedBox(height: 20),

                        // ─── Select Patient Button (Outside Card) ───
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: _selectPatientFromList,
                            icon: const Icon(Icons.person_search, size: 16, color: Color(0xFF1565C0)),
                            label: const Text(
                              'SELECT PATIENT FROM DATABASE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // ─── Patient Info Card ───
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(
                              color: const Color(0xFF1565C0),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // MR NUMBER FIELD WITH AUTO-SEARCH
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'MR NUMBER',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1565C0),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        TextField(
                                          controller: _mrNumberController,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1565C0),
                                          ),
                                          decoration: InputDecoration(
                                            hintText: 'Paste MR Number',
                                            hintStyle: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade400,
                                              fontWeight: FontWeight.normal,
                                            ),
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            suffixIcon: _isSearchingPatient
                                                ? const Padding(
                                                    padding: EdgeInsets.all(8.0),
                                                    child: SizedBox(
                                                      width: 14,
                                                      height: 14,
                                                      child: CircularProgressIndicator(strokeWidth: 2),
                                                    ),
                                                  )
                                                : IconButton(
                                                    icon: const Icon(Icons.search, size: 18),
                                                    color: const Color(0xFF1565C0),
                                                    onPressed: () => _searchPatientByMRNumber(_mrNumberController.text),
                                                  ),
                                          ),
                                          onChanged: (val) {
                                            if (val.trim().length >= 3) {
                                              _searchPatientByMRNumber(val);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  // PATIENT NAME FIELD
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'PATIENT NAME',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1565C0),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        TextField(
                                          controller: _nameController,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: 'Patient Name',
                                            hintStyle: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade400,
                                              fontWeight: FontWeight.normal,
                                            ),
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (_searchStatusMessage != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _searchStatusMessage!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _searchStatusMessage!.startsWith('✓')
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // PHONE FIELD
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'PHONE',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1565C0),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        TextField(
                                          controller: _phoneController,
                                          keyboardType: TextInputType.phone,
                                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]'))],
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          decoration: InputDecoration(
                                            hintText: 'Phone Number',
                                            hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  // ADDRESS FIELD
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'ADDRESS',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1565C0),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        TextField(
                                          controller: _addressController,
                                          style: const TextStyle(fontSize: 12),
                                          decoration: InputDecoration(
                                            hintText: 'Address',
                                            hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ─── Services Table ───
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            children: [
                              // Table Header
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1565C0),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(7),
                                    topRight: Radius.circular(7),
                                  ),
                                ),
                                child: Row(
                                  children: const [
                                    SizedBox(
                                      width: 20,
                                      child: Text(
                                        '#',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 7,
                                      child: Text(
                                        'DESCRIPTION',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        'PRICE',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        'DAYS',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        'TOTAL',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                    SizedBox(width: 24),
                                  ],
                                ),
                              ),

                              // Table Rows
                              ..._items.asMap().entries.map((entry) {
                                final idx = entry.key;
                                final item = entry.value;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: idx.isEven
                                        ? Colors.white
                                        : Colors.grey.shade50,
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        child: Text(
                                          '${idx + 1}',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 7,
                                        child: () {
                                          final serviceKeys = <String>{
                                            "SELECT SERVICE",
                                            ...SERVICE_PRICES.keys,
                                            if (item.serviceName.isNotEmpty) item.serviceName,
                                          }.toList();

                                          final selectedVal = serviceKeys.contains(item.serviceName)
                                              ? item.serviceName
                                              : (item.serviceName.isEmpty ? "SELECT SERVICE" : serviceKeys.first);

                                          return DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: selectedVal,
                                              isExpanded: true,
                                              isDense: true,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.black87,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              items: serviceKeys
                                                  .map(
                                                    (s) => DropdownMenuItem(
                                                      value: s,
                                                      child: Text(s, overflow: TextOverflow.ellipsis),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (val) {
                                                if (val != null) {
                                                  _updateItem(
                                                    idx,
                                                    name: val,
                                                    price: SERVICE_PRICES[val] ?? item.price,
                                                  );
                                                }
                                              },
                                            ),
                                          );
                                        }(),
                                      ),
                                      Expanded(
                                        flex: 4,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4),
                                          child: Container(
                                            height: 28,
                                            padding: const EdgeInsets.symmetric(horizontal: 2),
                                            decoration: BoxDecoration(
                                              border: Border.all(color: Colors.grey.shade300),
                                              borderRadius: BorderRadius.circular(4),
                                              color: Colors.white,
                                            ),
                                            child: TextFormField(
                                              key: Key('price_${idx}_${item.serviceName}'),
                                              initialValue: item.price == 0 ? '' : item.price.toStringAsFixed(0),
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF1565C0),
                                              ),
                                              decoration: const InputDecoration(
                                                border: InputBorder.none,
                                                contentPadding: EdgeInsets.only(bottom: 15),
                                              ),
                                              onChanged: (val) {
                                                final newPrice = double.tryParse(val) ?? 0.0;
                                                _updateItem(idx, price: newPrice);
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Center(
                                          child: Container(
                                            height: 28,
                                            padding: const EdgeInsets.symmetric(horizontal: 2),
                                            decoration: BoxDecoration(
                                              border: Border.all(color: Colors.grey.shade300),
                                              borderRadius: BorderRadius.circular(4),
                                              color: Colors.white,
                                            ),
                                            child: TextFormField(
                                              key: Key('qty_${idx}_${item.serviceName}'),
                                              initialValue: item.quantity.toString(),
                                              keyboardType: TextInputType.number,
                                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                border: InputBorder.none,
                                                contentPadding: EdgeInsets.symmetric(vertical: 4),
                                                hintText: '1',
                                              ),
                                              onChanged: (val) => _updateItem(
                                                idx,
                                                qty: int.tryParse(val) ?? 1,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 4,
                                        child: Text(
                                          NumberFormat('#,###').format(item.total),
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 24,
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          icon: const Icon(
                                            Icons.close,
                                            color: Colors.red,
                                            size: 16,
                                          ),
                                          onPressed: () => _removeItem(idx),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              // Add Custom Service Row Button
                              InkWell(
                                onTap: _addItem,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF1A237E),
                                    borderRadius: BorderRadius.only(
                                      bottomLeft: Radius.circular(7),
                                      bottomRight: Radius.circular(7),
                                    ),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      '+ Add Service Row',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ─── Bank Transfer + Totals ───
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          alignment: WrapAlignment.spaceBetween,
                          children: [
                            // Bank Transfer Details
                            SizedBox(
                              width: 320,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'BANK TRANSFER DETAILS',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _bankDetailRow('Bank:', 'Meezan Bank'),
                                    _bankDetailRow('Title:', 'SHIFA HOME HEALTH CARE'),
                                    _bankDetailRow('A/C #:', '10270115184708'),
                                    _bankDetailRow('IBAN:', 'PK23MEZN0010270115184708')
                                  ],
                                ),
                              ),
                            ),
                            // Subtotal / Discount / Total / Status
                            SizedBox(
                              width: 320,
                              child: Column(
                                children: [
                                  _totalRow(
                                    'SUBTOTAL:',
                                    '${_subtotal.toStringAsFixed(0)} PKR',
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'DISCOUNT:',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 80,
                                        child: TextField(
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(fontSize: 12),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            border: InputBorder.none,
                                            hintText: '0',
                                          ),
                                          onChanged: (val) => setState(
                                            () => _discount =
                                                double.tryParse(val) ?? 0.0,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1565C0),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'TOTAL:',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          '${_grandTotal.toStringAsFixed(0)} PKR',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _paymentStatus == 'Paid'
                                          ? const Color(0xFF16A34A)
                                          : (_paymentStatus == 'Partial'
                                              ? const Color(0xFFD97706)
                                              : const Color(0xFFDC2626)),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Center(
                                      child: Text(
                                        _paymentStatus.toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // ─── Policy Notice ───
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.orange.shade300,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            color: Colors.orange.shade50,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'IMPORTANT POLICY NOTICE',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Please be advised that the payments for medical equipment rentals and purchases are non-refundable. Upon agreement, the full payment is required in advance or upon receipt of the equipment. Direct the company responsibility beyond damage caused due to mishandling or willful negligence.',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Footer tagline
                        const Center(
                          child: Text(
                            'THIS IS A COMPUTERIZED GENERATED INVOICE. NO SIGNATURE REQUIRED.',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.red,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ─── Bottom Action Buttons ───
                  Row(
                    children: [
                      _ActionButton(
                        label: 'PRINT',
                        color: const Color(0xFF1565C0),
                        icon: Icons.print,
                        onTap: () => _submit('PRINT'),
                      ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        label: 'PDF',
                        color: const Color(0xFFE53935),
                        icon: Icons.picture_as_pdf,
                        onTap: () => _submit('PDF'),
                      ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        label: 'PNG',
                        color: const Color(0xFF43A047),
                        icon: Icons.image,
                        onTap: () => _submit('PNG'),
                      ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        label: 'JPG',
                        color: const Color(0xFFFB8C00),
                        icon: Icons.photo,
                        onTap: () => _submit('JPG'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _bankDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 0,
        ),
      ),
    );
  }
}
