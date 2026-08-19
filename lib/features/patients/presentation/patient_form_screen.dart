import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/patient_model.dart';
import '../data/patient_repository.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../core/errors/app_error.dart';
import 'widgets/healthcare_services_selector.dart';

class CnicInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (text.isEmpty) {
      return newValue.copyWith(text: '', selection: const TextSelection.collapsed(offset: 0));
    }

    final buffer = StringBuffer();
    for (int i = 0; i < text.length && i < 13; i++) {
      if (i == 5 || i == 12) {
        buffer.write('-');
      }
      buffer.write(text[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class PatientFormScreen extends ConsumerStatefulWidget {
  final Patient? existingPatient;

  const PatientFormScreen({super.key, this.existingPatient});

  @override
  ConsumerState<PatientFormScreen> createState() => _PatientFormScreenState();
}

class _PatientFormScreenState extends ConsumerState<PatientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final _nameKey = GlobalKey();
  final _cnicKey = GlobalKey();
  final _phoneKey = GlobalKey();
  final _addressKey = GlobalKey();

  final _nameFocusNode = FocusNode();
  final _cnicFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  final _addressFocusNode = FocusNode();

  late TextEditingController _nameController;
  late TextEditingController _cnicController;
  late TextEditingController _phoneController;
  late TextEditingController _mrNumberController;
  late TextEditingController _addressController;
  late TextEditingController _diagnosisController;
  late TextEditingController _doctorController;
  late TextEditingController _nurseController;
  late TextEditingController _caretakerController;
  
  // Financial fields
  late TextEditingController _patientAmountController;
  late TextEditingController _staffPaymentController;
  late TextEditingController _daysController;

  List<Map<String, dynamic>> _selectedServices = [];
  double _monthlyServiceCost = 0.0;
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existingPatient;
    _nameController = TextEditingController(text: p?.patientName ?? '');
    _cnicController = TextEditingController(text: p?.cnic ?? '');
    _phoneController = TextEditingController(text: p?.phone ?? '');
    _mrNumberController = TextEditingController(text: p?.mrNumber ?? 'Loading...');
    _addressController = TextEditingController(text: p?.address ?? '');
    _diagnosisController = TextEditingController(text: p?.diagnosis ?? '');
    _doctorController = TextEditingController(text: p?.doctor ?? '');
    _nurseController = TextEditingController(text: p?.nurse ?? '');
    _caretakerController = TextEditingController(text: p?.caretaker ?? '');
    
    _patientAmountController = TextEditingController(text: (p != null && p.patientAmount > 0) ? p.patientAmount.toString() : '');
    _staffPaymentController = TextEditingController(text: (p != null && p.staffPayment > 0) ? p.staffPayment.toString() : '');
    _daysController = TextEditingController(text: (p != null && p.days > 0) ? p.days.toString() : '');
    
    _selectedServices = p?.selectedServices ?? [];
    _monthlyServiceCost = p?.monthlyServiceCost ?? 0.0;
    
    _patientAmountController.addListener(() => setState(() {}));
    _staffPaymentController.addListener(() => setState(() {}));
    _daysController.addListener(() => setState(() {}));
    
    if (widget.existingPatient == null) {
      // Defer loading to allow context/ref to be fully available
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadNextMRNumber();
      });
    }
  }

  void _loadNextMRNumber() async {
    try {
      final repo = ref.read(patientRepositoryProvider);
      final nextMr = await repo.previewNextMRNumber();
      if (mounted) {
        setState(() {
          _mrNumberController.text = nextMr;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cnicController.dispose();
    _phoneController.dispose();
    _mrNumberController.dispose();
    _addressController.dispose();
    _diagnosisController.dispose();
    _doctorController.dispose();
    _nurseController.dispose();
    _caretakerController.dispose();
    _patientAmountController.dispose();
    _staffPaymentController.dispose();
    _daysController.dispose();
    _nameFocusNode.dispose();
    _cnicFocusNode.dispose();
    _phoneFocusNode.dispose();
    _addressFocusNode.dispose();
    super.dispose();
  }

  double get _netProfit {
    double patientAmount = double.tryParse(_patientAmountController.text) ?? 0.0;
    double staffPayment = double.tryParse(_staffPaymentController.text) ?? 0.0;
    return patientAmount - staffPayment;
  }

  void _scrollToAndFocus(GlobalKey key, FocusNode focusNode) {
    focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (key.currentContext != null) {
        Scrollable.ensureVisible(
          key.currentContext!,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
          alignment: 0.2, // Positions invalid field cleanly near the top of the viewport
        );
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      if (_nameController.text.trim().isEmpty) {
        _scrollToAndFocus(_nameKey, _nameFocusNode);
        return;
      }
      final cnicVal = _cnicController.text.trim();
      if (cnicVal.isNotEmpty && !RegExp(r'^\d{5}-\d{7}-\d{1}$').hasMatch(cnicVal)) {
        _scrollToAndFocus(_cnicKey, _cnicFocusNode);
        return;
      }
      final phoneVal = _phoneController.text.trim();
      if (phoneVal.isEmpty || !RegExp(r'^\d{1,15}$').hasMatch(phoneVal)) {
        _scrollToAndFocus(_phoneKey, _phoneFocusNode);
        return;
      }
      if (_addressController.text.trim().isEmpty) {
        _scrollToAndFocus(_addressKey, _addressFocusNode);
        return;
      }
      return;
    }
    
    setState(() => _isLoading = true);

    try {
      final repo = ref.read(patientRepositoryProvider);
      final user = ref.read(authStateProvider).value;

      if (user == null) throw Exception("User not logged in");

      final isEditing = widget.existingPatient != null;
      
      final patient = Patient(
        patientId: isEditing ? widget.existingPatient!.patientId : '',
        mrNumber: _mrNumberController.text,
        patientName: _nameController.text.trim(),
        cnic: _cnicController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        diagnosis: _diagnosisController.text.trim(),
        doctor: _doctorController.text.trim(),
        nurse: _nurseController.text.trim(),
        caretaker: _caretakerController.text.trim(),
        selectedServices: _selectedServices,
        monthlyServiceCost: _monthlyServiceCost,
        patientAmount: double.tryParse(_patientAmountController.text) ?? 0.0,
        staffPayment: double.tryParse(_staffPaymentController.text) ?? 0.0,
        profit: _netProfit,
        days: int.tryParse(_daysController.text.trim()) ?? 0,
        assignedStaffId: isEditing ? widget.existingPatient!.assignedStaffId : user.uid,
        organizationId: 'default',
        createdBy: isEditing ? widget.existingPatient!.createdBy : user.uid,
        createdAt: isEditing ? widget.existingPatient!.createdAt : DateTime.now(),
        updatedBy: user.uid,
        updatedAt: DateTime.now(),
        isDeleted: false,
      );

      final profile = ref.read(userProfileProvider).value;
      final userName = profile?['name'] ?? profile?['username'] ?? 'Staff User';

      if (isEditing) {
        await repo.updatePatient(patient);
      } else {
        final finalMrNumber = await repo.getNextMRNumber();
        final finalPatient = Patient(
          patientId: patient.patientId,
          mrNumber: finalMrNumber,
          patientName: patient.patientName,
          cnic: patient.cnic,
          phone: patient.phone,
          address: patient.address,
          diagnosis: patient.diagnosis,
          doctor: patient.doctor,
          nurse: patient.nurse,
          caretaker: patient.caretaker,
          selectedServices: patient.selectedServices,
          monthlyServiceCost: patient.monthlyServiceCost,
          patientAmount: patient.patientAmount,
          staffPayment: patient.staffPayment,
          profit: patient.profit,
          days: patient.days,
          assignedStaffId: patient.assignedStaffId,
          organizationId: patient.organizationId,
          createdBy: patient.createdBy,
          createdAt: patient.createdAt,
          updatedBy: patient.updatedBy,
          updatedAt: patient.updatedAt,
          isDeleted: patient.isDeleted,
        );
        await repo.createPatient(finalPatient, userName: userName);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing ? 'Patient updated' : 'Patient created'),
            backgroundColor: Colors.green,
          ),
        );
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          context.go('/records');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingPatient == null ? 'New Patient Registration' : 'Edit Patient'),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionCard(
                    title: '1. Patient Information',
                    children: [
                      _buildField(
                        _nameController,
                        'Full Name',
                        required: true,
                        focusNode: _nameFocusNode,
                        fieldKey: _nameKey,
                      ),
                      _buildField(
                        _cnicController, 
                        'CNIC (XXXXX-XXXXXXX-X)', 
                        required: false,
                        focusNode: _cnicFocusNode,
                        fieldKey: _cnicKey,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          CnicInputFormatter(),
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final regExp = RegExp(r'^\d{5}-\d{7}-\d{1}$');
                          if (!regExp.hasMatch(v.trim())) return 'Invalid CNIC format';
                          return null;
                        },
                      ),
                      _buildField(
                        _phoneController,
                        'Mobile Number',
                        required: true,
                        isPhone: true,
                        focusNode: _phoneFocusNode,
                        fieldKey: _phoneKey,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(15),
                        ],
                        validator: (v) {
                          final trimmed = v?.trim() ?? '';
                          if (trimmed.isEmpty) return 'Mobile Number is required';
                          if (!RegExp(r'^\d{1,15}$').hasMatch(trimmed)) {
                            return 'Mobile number must contain 1-15 digits only';
                          }
                          return null;
                        },
                      ),
                      _buildField(_mrNumberController, 'MR Number', readOnly: true),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    title: '2. Address',
                    children: [
                      _buildField(
                        _addressController,
                        'Address',
                        required: true,
                        maxLines: 3,
                        focusNode: _addressFocusNode,
                        fieldKey: _addressKey,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    title: '3. Clinical Information',
                    children: [
                      _buildField(_diagnosisController, 'Diagnosis'),
                      _buildField(_doctorController, 'Doctor'),
                      _buildField(_nurseController, 'Nurse'),
                      _buildField(_caretakerController, 'Caretaker'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    title: '4. Healthcare Services',
                    children: [
                      HealthcareServicesSelector(
                        initialSelectedServices: _selectedServices,
                        onChanged: (services, cost) {
                          setState(() {
                            _selectedServices = services;
                            _monthlyServiceCost = cost;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    title: '5. Financial Summary',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildField(
                              _patientAmountController, 
                              'Patient Amount', 
                              isNumber: true
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildField(
                              _staffPaymentController, 
                              'Staff Payment', 
                              isNumber: true
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildField(
                        _daysController,
                        'Days',
                        isNumber: true,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) {
                          if (v != null && v.trim().isNotEmpty) {
                            final n = int.tryParse(v.trim());
                            if (n == null || n <= 0) {
                              return 'Please enter a valid positive number of days';
                            }
                          }
                          return null;
                        },
                      ),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Net Profit:', style: TextStyle(fontSize: 16)),
                            Text(
                              'PKR ${_netProfit.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 18, 
                                fontWeight: FontWeight.bold,
                                color: _netProfit >= 0 ? Colors.green : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: _submit,
                      child: const Text('Save Patient', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildSectionCard({required String title, required List<Widget> children}) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller, 
    String label, {
    bool required = false, 
    int maxLines = 1,
    bool readOnly = false,
    bool isNumber = false,
    bool isPhone = false,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    FocusNode? focusNode,
    Key? fieldKey,
  }) {
    List<TextInputFormatter> formatters = inputFormatters ?? [];
    if (isNumber && inputFormatters == null) {
      formatters = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))];
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        key: fieldKey,
        focusNode: focusNode,
        controller: controller,
        maxLines: maxLines,
        readOnly: readOnly,
        inputFormatters: formatters,
        keyboardType: isNumber
            ? const TextInputType.numberWithOptions(decimal: true)
            : (isPhone ? TextInputType.phone : null),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          filled: readOnly,
          fillColor: readOnly ? Theme.of(context).colorScheme.surfaceContainerHighest : null,
        ),
        validator: validator ?? (required 
          ? (v) => (v == null || v.isEmpty) ? 'Required field' : null 
          : null),
      ),
    );
  }
}
