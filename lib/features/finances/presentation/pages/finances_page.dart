import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../patients/data/patient_repository.dart';
import '../../../patients/domain/patient_model.dart';
import '../../../invoices/data/invoice_repository.dart';

class FinancesPage extends ConsumerWidget {
  const FinancesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: profileAsync.when(
        data: (profile) {
          final role = profile?['role'] ?? 'staff';
          if (role == 'admin') {
            return _buildAdminFinanceView(context, ref);
          } else {
            return _buildStaffFinanceView(context, ref, profile?['uid'] ?? '');
          }
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0056B3)),
          ),
        ),
        error: (err, stack) => Center(
          child: Text(
            'Error: $err',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFFDC2626),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdminFinanceView(BuildContext context, WidgetRef ref) {
    final patientsAsync = ref.watch(allPatientsProvider(false));
    final invoicesAsync = ref.watch(allInvoicesProvider(false));

    return patientsAsync.when(
      data: (patients) {
        final activePatients = patients.where((p) => !p.isDiscontinued).toList();
        final invoices = invoicesAsync.value ?? [];
        double totalRevenue = 0;
        double totalPayout = 0;
        double totalProfit = 0;

        for (final p in activePatients) {
          totalPayout += p.staffPayment;
        }

        // Add revenue strictly from Paid invoices (includes both staff- and admin-created)
        for (final inv in invoices) {
          if (!inv.isDiscontinued && !inv.isDeleted && inv.paymentStatus.trim().toLowerCase() == 'paid') {
            totalRevenue += inv.grandTotal;
          }
        }

        totalProfit = totalRevenue - totalPayout;

        final formatter = NumberFormat('#,###');

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Page Title
              const Text(
                'FINANCIAL PERFORMANCE',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 20),

              // Metric Cards Stack (Matching Image 100%)
              _buildMetricCard(
                label: 'TOTAL REVENUE (PATIENT INTAKE)',
                value: 'Rs. ${formatter.format(totalRevenue.toInt())}',
                accentColor: const Color(0xFF2563EB),
              ),
              const SizedBox(height: 14),
              _buildMetricCard(
                label: 'STAFF EXPENDITURE (PAYOUTS)',
                value: 'Rs. ${formatter.format(totalPayout.toInt())}',
                accentColor: const Color(0xFFDC2626),
              ),
              const SizedBox(height: 14),
              _buildMetricCard(
                label: 'NET OPERATIONAL MARGIN',
                value: 'Rs. ${formatter.format(totalProfit.toInt())}',
                accentColor: const Color(0xFF16A34A),
              ),
              const SizedBox(height: 28),

              // Table Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.table_chart_rounded, size: 18, color: Colors.blue.shade700),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'DETAILED REVENUE BREAKDOWN',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Enhanced Table View
              if (activePatients.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Center(
                    child: Text(
                      'No financial records available.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                  ),
                )
              else
                _buildTable(activePatients, formatter, isAdmin: true),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error loading financial data: $err')),
    );
  }

  Widget _buildStaffFinanceView(BuildContext context, WidgetRef ref, String staffId) {
    final patientsAsync = ref.watch(staffPatientsProvider);
    final invoicesAsync = ref.watch(staffInvoicesProvider);

    return patientsAsync.when(
      data: (patients) {
        final activePatients = patients.where((p) => !p.isDiscontinued).toList();
        final invoices = invoicesAsync.value ?? [];
        double totalRevenue = 0;
        double totalPayout = 0;
        double totalProfit = 0;

        for (final p in activePatients) {
          totalPayout += p.staffPayment;
        }

        // Add revenue strictly from this staff member's Paid invoices
        for (final inv in invoices) {
          if (!inv.isDiscontinued && !inv.isDeleted && inv.paymentStatus.trim().toLowerCase() == 'paid') {
            totalRevenue += inv.grandTotal;
          }
        }

        totalProfit = totalRevenue - totalPayout;

        final formatter = NumberFormat('#,###');

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Page Title
              const Text(
                'FINANCIAL PERFORMANCE',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 20),

              // Metric Cards Stack
              _buildMetricCard(
                label: 'TOTAL REVENUE (PATIENT INTAKE)',
                value: 'Rs. ${formatter.format(totalRevenue.toInt())}',
                accentColor: const Color(0xFF2563EB),
              ),
              const SizedBox(height: 14),
              _buildMetricCard(
                label: 'STAFF EXPENDITURE (PAYOUTS)',
                value: 'Rs. ${formatter.format(totalPayout.toInt())}',
                accentColor: const Color(0xFFDC2626),
              ),
              const SizedBox(height: 14),
              _buildMetricCard(
                label: 'NET OPERATIONAL MARGIN',
                value: 'Rs. ${formatter.format(totalProfit.toInt())}',
                accentColor: const Color(0xFF16A34A),
              ),
              const SizedBox(height: 28),

              // Table Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.table_chart_rounded, size: 18, color: Colors.blue.shade700),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'MANAGED PATIENTS BREAKDOWN',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Enhanced Table View
              if (activePatients.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Center(
                    child: Text(
                      'No financial records found for your managed patients.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                  ),
                )
              else
                _buildTable(activePatients, formatter, isAdmin: false),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error loading financial data: $err')),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required Color accentColor,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Accent Border Line
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(List<Patient> patients, NumberFormat formatter, {required bool isAdmin}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 480),
            child: DataTable(
              columnSpacing: 24,
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
              headingRowHeight: 48,
              dataRowMinHeight: 52,
              dataRowMaxHeight: 56,
              columns: [
                DataColumn(
                  label: Text(
                    'PATIENT NAME',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'REVENUE (IN)',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    isAdmin ? 'PAYOUT (OUT)' : 'EARNINGS (OUT)',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'NET YIELD',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
              rows: patients.map((p) {
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        p.patientName.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        'Rs. ${formatter.format(p.patientAmount.toInt())}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        'Rs. ${formatter.format(p.staffPayment.toInt())}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        'Rs. ${formatter.format(p.profit.toInt())}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
