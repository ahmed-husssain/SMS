import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../patients/data/patient_repository.dart';
import '../../../patients/presentation/patient_form_screen.dart';
import '../../../patients/domain/patient_model.dart';
import '../../../invoices/presentation/invoice_form_screen.dart';
import '../../../invoices/presentation/pages/invoices_page.dart';
import '../../../dashboard/presentation/widgets/schedule_notification_modal.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class RecordsPage extends ConsumerStatefulWidget {
  const RecordsPage({super.key});

  @override
  ConsumerState<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends ConsumerState<RecordsPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';

  String _statusFilter = 'active'; // 'active', 'discontinued', 'all'

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final role = profile?['role'] ?? 'staff';

    // Admin gets all patients, staff gets only their assigned patients
    final patientsAsync = role == 'admin'
        ? ref.watch(allPatientsProvider(false))
        : ref.watch(staffPatientsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Patient Records',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).push(MaterialPageRoute(builder: (_) => const PatientFormScreen()));
                  },
                  icon: const Icon(Icons.person_add, size: 18),
                  label: const Text(
                    'Add Patient',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ─── Instant Multi-Field Search Bar ───
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x0A000000),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: 'Search by MR #, Name, Phone, Address, or Status (active/discontinue)...',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF1565C0), size: 22),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  isDense: true,
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                  _scrollToTop();
                },
              ),
            ),
            const SizedBox(height: 10),

            // ─── Status Filter Chips ───
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('Active Patients', 'active'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Discontinued', 'discontinued'),
                  const SizedBox(width: 8),
                  _buildFilterChip('All Records', 'all'),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ─── Patient List Content ───
            Expanded(
              child: patientsAsync.when(
                data: (patients) {
                  if (patients.isEmpty) {
                    return Center(
                      child: Text(
                        role == 'admin'
                            ? 'No patients registered yet.'
                            : 'No patients assigned to you yet.',
                      ),
                    );
                  }

                  // Instant In-Memory Filter
                  final query = _searchQuery.trim().toLowerCase();
                  final isSearchingDiscontinued = query.contains('discontinue') || query.contains('discontinued');
                  final isSearchingActive = query == 'active';

                  final filteredPatients = patients.where((p) {
                    if (isSearchingDiscontinued) {
                      if (!p.isDiscontinued) return false;
                    } else if (isSearchingActive) {
                      if (p.isDiscontinued) return false;
                    } else if (_statusFilter == 'active') {
                      if (p.isDiscontinued) return false;
                    } else if (_statusFilter == 'discontinued') {
                      if (!p.isDiscontinued) return false;
                    }

                    if (query.isEmpty || isSearchingDiscontinued || isSearchingActive) return true;

                    final mr = p.mrNumber.toLowerCase();
                    final name = p.patientName.toLowerCase();
                    final phone = p.phone.toLowerCase();
                    final address = p.address.toLowerCase();
                    return mr.contains(query) ||
                        name.contains(query) ||
                        phone.contains(query) ||
                        address.contains(query);
                  }).toList();

                  return Column(
                    children: [
                      // Stats counter chip
                      if (_searchQuery.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Found ${filteredPatients.length} matching record${filteredPatients.length == 1 ? '' : 's'}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ),
                        ),

                      Expanded(
                        child: filteredPatients.isEmpty
                            ? Center(
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No patients found matching "$_searchQuery"',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextButton.icon(
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                        icon: const Icon(Icons.clear, size: 16),
                                        label: const Text('Clear Search'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0x0A000000),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    // Table Header
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(12),
                                          topRight: Radius.circular(12),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: Text(
                                              'MR NUMBER',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.grey.shade500,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            flex: 4,
                                            child: Text(
                                              'PATIENT DETAILS',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.grey.shade500,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            flex: 3,
                                            child: Text(
                                              'NET PROFIT',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.grey.shade500,
                                                letterSpacing: 0.5,
                                              ),
                                              textAlign: TextAlign.right,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: Color(0xFFEEEEEE),
                                    ),
                                    // Table Body
                                    Expanded(
                                      child: ListView.separated(
                                        controller: _scrollController,
                                        itemCount: filteredPatients.length,
                                        separatorBuilder: (_, __) => const Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: Color(0xFFF5F5F5),
                                        ),
                                        itemBuilder: (context, index) {
                                          final p = filteredPatients[index];
                                          return InkWell(
                                            onTap: () => _showPatientDetails(context, p, role),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 20,
                                                vertical: 14,
                                              ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    flex: 3,
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      alignment: Alignment.centerLeft,
                                                      child: Text(
                                                        p.mrNumber,
                                                        style: const TextStyle(
                                                          color: Color(0xFF1565C0),
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    flex: 4,
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Wrap(
                                                          crossAxisAlignment: WrapCrossAlignment.center,
                                                          spacing: 8,
                                                          runSpacing: 4,
                                                          children: [
                                                            Text(
                                                              p.patientName.toUpperCase(),
                                                              style: TextStyle(
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 13,
                                                                color: p.isDiscontinued ? Colors.grey.shade700 : Colors.black87,
                                                              ),
                                                            ),
                                                            if (p.isDiscontinued)
                                                              Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                                decoration: BoxDecoration(
                                                                  color: Colors.orange.shade100,
                                                                  borderRadius: BorderRadius.circular(4),
                                                                  border: Border.all(color: Colors.orange.shade400),
                                                                ),
                                                                child: Text(
                                                                  'DISCONTINUED',
                                                                  style: TextStyle(
                                                                    fontSize: 9,
                                                                    fontWeight: FontWeight.bold,
                                                                    color: Colors.orange.shade900,
                                                                  ),
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                        if (p.phone.isNotEmpty || p.address.isNotEmpty) ...[
                                                          const SizedBox(height: 2),
                                                          Text(
                                                            [p.phone, p.address].where((s) => s.isNotEmpty).join(' • '),
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: Colors.grey.shade600,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    flex: 3,
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      alignment: Alignment.centerRight,
                                                      child: Text(
                                                        'Rs. ${NumberFormat('#,###').format(p.profit.toInt())}',
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 13,
                                                          color: Color(0xFFE53935),
                                                        ),
                                                        textAlign: TextAlign.right,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _statusFilter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : const Color(0xFF1565C0),
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF1565C0),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: isSelected ? const Color(0xFF1565C0) : Colors.grey.shade300,
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _statusFilter = value;
          });
        }
      },
    );
  }

  void _showPatientDetails(BuildContext context, Patient p, String role) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, controller) =>
              _PatientDetailsModal(patient: p, scrollController: controller, role: role),
        );
      },
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  const _ActionIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6.0),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

class _PatientDetailsModal extends ConsumerWidget {
  final Patient patient;
  final ScrollController scrollController;
  final String role;

  const _PatientDetailsModal({
    required this.patient,
    required this.scrollController,
    required this.role,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateStr = DateFormat(
      'EEEE, MMM d, yyyy \'at\' h:mm a',
    ).format(patient.createdAt);

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Patient Details',
                  style: Theme.of(context).textTheme.headlineSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                children: [
                  _ActionIconButton(
                    icon: Icons.manage_search_rounded,
                    color: const Color(0xFF004B93),
                    tooltip: 'Search Invoices',
                    onPressed: () {
                      ref.read(invoiceSearchQueryProvider.notifier).setQuery(
                            patient.mrNumber.isNotEmpty ? patient.mrNumber : patient.patientId,
                          );
                      Navigator.pop(context);
                      context.go('/invoices');
                    },
                  ),
                  _ActionIconButton(
                    icon: Icons.description_outlined,
                    color: Colors.orange.shade600,
                    tooltip: 'Generate Invoice',
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => InvoiceFormScreen(patientId: patient.patientId),
                        ),
                      );
                    },
                  ),
                  _ActionIconButton(
                    icon: Icons.edit_outlined,
                    color: Colors.blue.shade600,
                    tooltip: 'Edit Patient',
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PatientFormScreen(existingPatient: patient),
                        ),
                      );
                    },
                  ),
                  if (patient.isDiscontinued)
                    _ActionIconButton(
                      icon: Icons.play_circle_outline,
                      color: Colors.green.shade600,
                      tooltip: 'Activate Patient',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Activate Patient?'),
                            content: Text(
                              'Are you sure you want to reactivate ${patient.patientName}? This will restore the patient and all associated invoices & financial records back to active views.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text(
                                  'Activate',
                                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          final user = ref.read(authStateProvider).value;
                          await ref.read(patientRepositoryProvider).reactivatePatient(
                                patientId: patient.patientId,
                                patientName: patient.patientName,
                                userId: user!.uid,
                                organizationId: patient.organizationId,
                              );
                          if (context.mounted) Navigator.pop(context);
                        }
                      },
                    )
                  else
                    _ActionIconButton(
                      icon: Icons.pause_circle_outline,
                      color: Colors.orange.shade800,
                      tooltip: 'Discontinue Patient',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Discontinue Patient?'),
                            content: Text(
                              'Are you sure you want to discontinue ${patient.patientName}? This will hide the patient and all associated invoices & financial records from the app UI while preserving full database history.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text(
                                  'Discontinue',
                                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          final user = ref.read(authStateProvider).value;
                          await ref.read(patientRepositoryProvider).discontinuePatient(
                                patientId: patient.patientId,
                                patientName: patient.patientName,
                                userId: user!.uid,
                                organizationId: patient.organizationId,
                              );
                          if (context.mounted) Navigator.pop(context);
                        }
                      },
                    ),
                  _ActionIconButton(
                    icon: Icons.add_alarm_rounded,
                    color: const Color(0xFF1565C0),
                    tooltip: 'Schedule Reminder',
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        useRootNavigator: true,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => ScheduleNotificationModal(preSelectedPatient: patient),
                      );
                    },
                  ),
                  if (role == 'admin')
                    _ActionIconButton(
                      icon: Icons.delete_outline,
                      color: Colors.red.shade600,
                      tooltip: 'Delete Patient',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Patient?'),
                            content: Text(
                              'Are you sure you want to delete ${patient.patientName}? This can be restored later.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          final user = ref.read(authStateProvider).value;
                          await ref.read(patientRepositoryProvider).softDeletePatient(
                                patientId: patient.patientId,
                                patientName: patient.patientName,
                                userId: user!.uid,
                                organizationId: patient.organizationId,
                              );
                          if (context.mounted) Navigator.pop(context);
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
          const Divider(),
          _buildDetailRow(context, 'Name', patient.patientName),
          _buildDetailRow(context, 'MR Number', patient.mrNumber),
          _buildDetailRow(context, 'CNIC', patient.cnic),
          _buildDetailRow(context, 'Phone', patient.phone),
          _buildDetailRow(context, 'Address', patient.address),
          const SizedBox(height: 16),
          Text(
            'Clinical Information',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Divider(),
          _buildDetailRow(context, 'Diagnosis', patient.diagnosis),
          _buildDetailRow(context, 'Doctor', patient.doctor),
          _buildDetailRow(context, 'Nurse', patient.nurse),
          _buildDetailRow(context, 'Caretaker', patient.caretaker),
          const SizedBox(height: 16),
          Text(
            'Registration Info',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Divider(),
          _buildDetailRow(context, 'Registered On', dateStr),
          FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(patient.createdBy)
                .get(),
            builder: (context, snapshot) {
              String creatorName = 'Loading...';
              if (snapshot.hasError) creatorName = 'Error loading creator';
              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>;
                creatorName = data['name'] ?? 'Unknown User';
              } else if (snapshot.connectionState == ConnectionState.done) {
                creatorName = 'Unknown (ID: ${patient.createdBy})';
              }
              return _buildDetailRow(context, 'Created By', creatorName);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    final displayValue = value.isEmpty ? 'N/A' : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () {
                if (displayValue != 'N/A') {
                  Clipboard.setData(ClipboardData(text: displayValue));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓ Copied $label ($displayValue) to clipboard'),
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
                  children: [
                    Expanded(
                      child: SelectableText(
                        displayValue,
                        style: TextStyle(
                          color: displayValue == 'N/A' ? Colors.grey : Colors.black87,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (displayValue != 'N/A') ...[
                      const SizedBox(width: 6),
                      Icon(Icons.copy_rounded, size: 14, color: Colors.blue.shade700),
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
