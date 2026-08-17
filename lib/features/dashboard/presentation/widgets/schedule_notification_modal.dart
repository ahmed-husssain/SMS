import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../patients/domain/patient_model.dart';
import '../../../patients/data/patient_repository.dart';
import '../../domain/scheduled_notification_model.dart';
import '../../data/scheduled_notification_repository.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/plan_expiration_provider.dart';

class ScheduleNotificationModal extends ConsumerStatefulWidget {
  final Patient? preSelectedPatient;

  const ScheduleNotificationModal({super.key, this.preSelectedPatient});

  @override
  ConsumerState<ScheduleNotificationModal> createState() => _ScheduleNotificationModalState();
}

class _ScheduleNotificationModalState extends ConsumerState<ScheduleNotificationModal> {
  String? _selectedPatientId;
  int _selectedDays = 4; // Default: 4 days
  DateTime _scheduledDate = DateTime.now().add(const Duration(days: 4));
  final TextEditingController _noteController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedPatientId = widget.preSelectedPatient?.patientId;
  }

  void _updateDays(int days) {
    setState(() {
      _selectedDays = days;
      _scheduledDate = DateTime.now().add(Duration(days: days));
    });
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDays = 0; // Custom
        _scheduledDate = DateTime(picked.year, picked.month, picked.day, 12, 0);
      });
    }
  }

  Future<void> _saveNotification() async {
    final patientsAsync = ref.read(allPatientsProvider(false));
    final patients = (patientsAsync.value ?? []).where((p) => !p.isDiscontinued).toList();

    Patient? selectedPatient = widget.preSelectedPatient;
    if (selectedPatient == null && _selectedPatientId != null) {
      final matches = patients.where((p) => p.patientId == _selectedPatientId).toList();
      if (matches.isNotEmpty) selectedPatient = matches.first;
    }

    if (selectedPatient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a patient first.')),
      );
      return;
    }

    final note = _noteController.text.trim();
    if (note.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a reminder note / reason before scheduling.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final authUser = ref.read(authStateProvider).value;
      final userProfile = ref.read(userProfileProvider).value;
      final userName = userProfile?['name'] ?? authUser?.displayName ?? 'Staff';

      final notification = ScheduledNotification(
        id: '',
        patientId: selectedPatient.patientId,
        patientName: selectedPatient.patientName,
        mrNumber: selectedPatient.mrNumber,
        phone: selectedPatient.phone,
        address: selectedPatient.address,
        reminderNote: note,
        targetDays: _selectedDays,
        scheduledFor: _scheduledDate,
        createdAt: DateTime.now(),
        createdBy: userName,
      );

      await ref.read(scheduledNotificationRepositoryProvider).addScheduledNotification(notification);

      if (mounted) {
        ref.invalidate(allPatientsProvider(false));
        ref.invalidate(staffPatientsProvider);
        ref.invalidate(expiringPlansProvider);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ Reminder scheduled for ${selectedPatient.patientName} on ${DateFormat('EEE, MMM d').format(_scheduledDate)}!',
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scheduling notification: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(allPatientsProvider(false));
    final patients = (patientsAsync.value ?? []).where((p) => !p.isDiscontinued).toList();

    final preSelected = widget.preSelectedPatient;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.edit_notifications_rounded, color: Color(0xFF1565C0), size: 24),
                      SizedBox(width: 8),
                      Text(
                        'SCHEDULE REMINDER',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 10),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    // Patient Selector (if not pre-selected)
                    const Text(
                      'PATIENT',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
                    ),
                    const SizedBox(height: 6),
                    if (preSelected != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Text(
                          '${preSelected.patientName} (${preSelected.mrNumber})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        value: (patients.any((p) => p.patientId == _selectedPatientId))
                            ? _selectedPatientId
                            : null,
                        hint: const Text('Select Patient'),
                        isExpanded: true,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: patients
                            .map((p) => DropdownMenuItem<String>(
                                  value: p.patientId,
                                  child: Text('${p.patientName} (${p.mrNumber})', overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (id) => setState(() => _selectedPatientId = id),
                      ),
                    const SizedBox(height: 18),

                    // Preset Duration Chips
                    const Text(
                      'SCHEDULE REMINDER FOR',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildPresetChip('4 Days', 4),
                          const SizedBox(width: 8),
                          _buildPresetChip('7 Days', 7),
                          const SizedBox(width: 8),
                          _buildPresetChip('14 Days', 14),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Row(
                              children: [
                                const Icon(Icons.calendar_today_rounded, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  _selectedDays == 0 ? DateFormat('MMM d').format(_scheduledDate) : 'Custom Date',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: _selectedDays == 0 ? FontWeight.bold : FontWeight.normal,
                                    color: _selectedDays == 0 ? Colors.white : Colors.blue.shade800,
                                  ),
                                ),
                              ],
                            ),
                            selected: _selectedDays == 0,
                            selectedColor: const Color(0xFF1565C0),
                            backgroundColor: Colors.white,
                            side: BorderSide(color: _selectedDays == 0 ? const Color(0xFF1565C0) : Colors.grey.shade300),
                            onSelected: (_) => _pickCustomDate(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Reminder Date: ${DateFormat('EEEE, MMMM d, yyyy').format(_scheduledDate)}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 18),

                    // Reminder Note TextField (Required)
                    const Text(
                      'REMINDER NOTE / REASON * (REQUIRED)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _noteController,
                      maxLines: 3,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'e.g., 4-day medication review, payment follow-up, oxygen cylinder renewal...',
                        hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _saveNotification,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: _isSubmitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.check_circle_rounded, size: 20),
                        label: Text(
                          _isSubmitting ? 'SCHEDULING...' : 'SAVE SCHEDULED REMINDER',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPresetChip(String label, int days) {
    final isSelected = _selectedDays == days;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : const Color(0xFF1565C0),
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF1565C0),
      backgroundColor: Colors.white,
      side: BorderSide(color: isSelected ? const Color(0xFF1565C0) : Colors.grey.shade300),
      onSelected: (selected) {
        if (selected) _updateDays(days);
      },
    );
  }
}
