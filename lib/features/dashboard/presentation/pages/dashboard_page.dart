import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../analytics/presentation/activity_feed_widget.dart';
import '../../../patients/data/patient_repository.dart';
import '../../../invoices/data/invoice_repository.dart';
import '../../../patients/presentation/patient_form_screen.dart';
import '../../../../shared/providers/plan_expiration_provider.dart';

// System metrics provider (for Admin)
final systemMetricsProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final patientsAsync = ref.watch(allPatientsProvider(false));
  final invoicesAsync = ref.watch(allInvoicesProvider(false));

  final patients = patientsAsync.value ?? [];
  final invoices = invoicesAsync.value ?? [];

  final totalPatients = patients.length;
  double totalRevenue = 0.0;
  double totalPayout = 0.0;

  for (final p in patients) {
    if (!p.isDiscontinued) {
      totalPayout += p.staffPayment;
    }
  }

  // Only count Paid invoices toward revenue
  for (final inv in invoices) {
    if (!inv.isDeleted && !inv.isDiscontinued && inv.paymentStatus.trim().toLowerCase() == 'paid') {
      totalRevenue += inv.grandTotal;
    }
  }

  final netProfit = totalRevenue - totalPayout;

  return FirebaseFirestore.instance
      .collection('users')
      .snapshots()
      .map((staffSnapshot) {
    final staffCount = staffSnapshot.docs.where((doc) {
      final data = doc.data();
      final isDeleted = data['isDeleted'] == true;
      final isInternalAccount = data['isInternalAccount'] == true;
      final isHidden = data['isHidden'] == true;
      final role = (data['role'] ?? '').toString().toLowerCase();

      if (isDeleted || isInternalAccount || isHidden) return false;
      return role == 'staff';
    }).length;

    return {
      'totalPatients': totalPatients,
      'totalRevenue': netProfit,
      'totalInvoices': invoices.where((i) => !i.isDeleted).length,
      'totalStaff': staffCount,
    };
  });
});

// Staff metrics provider (for Staff member's own registered patients and finances)
final staffMetricsProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final patientsAsync = ref.watch(staffPatientsProvider);
  final invoicesAsync = ref.watch(staffInvoicesProvider);

  final patients = patientsAsync.value ?? [];
  final invoices = invoicesAsync.value ?? [];

  final totalPatients = patients.length;
  double totalRevenue = 0.0;
  double totalPayout = 0.0;

  for (final p in patients) {
    if (!p.isDiscontinued) {
      totalPayout += p.staffPayment;
    }
  }

  // Only count Paid invoices toward revenue
  for (final inv in invoices) {
    if (!inv.isDeleted && !inv.isDiscontinued && inv.paymentStatus.trim().toLowerCase() == 'paid') {
      totalRevenue += inv.grandTotal;
    }
  }

  final netProfit = totalRevenue - totalPayout;

  return Stream.value({
    'totalPatients': totalPatients,
    'totalRevenue': netProfit,
    'totalInvoices': invoices.length,
  });
});

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).value;
    final role = (profile?['role'] ?? 'staff').toString().toLowerCase();
    final username = (profile?['username'] ?? '').toString().toUpperCase();

    if (role == 'admin' || username == 'SHIFA' || username == 'ADMIN001' || username == 'ADMIN' || username == 'IT') {
      return const _AdminDashboardView();
    } else {
      return const _StaffDashboardView();
    }
  }
}

// ─── Admin Dashboard View ───────────────────────────────────────────
class _AdminDashboardView extends ConsumerWidget {
  const _AdminDashboardView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(systemMetricsProvider);

    return metricsAsync.when(
      data: (metrics) {
        final totalPatients = metrics['totalPatients'] ?? 0;
        final totalRevenue = (metrics['totalRevenue'] ?? 0).toDouble();
        final careProviders = metrics['totalStaff'] ?? 0;

        final profile = ref.watch(userProfileProvider).value;
        final name = profile?['name'] ?? 'Administrator';

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hi, $name',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Dashboard Overview',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),
              const _PlanHealthOverviewCard(),
              const SizedBox(height: 20),
              _DashboardImageMetricCard(
                title: 'TOTAL PATIENTS',
                value: '$totalPatients',
                icon: Icons.people_alt,
                accentColor: const Color(0xFF0056B3),
                iconBgColor: const Color(0xFFEFF6FF),
              ),
              const SizedBox(height: 14),
              _DashboardImageMetricCard(
                title: 'NET PROFIT',
                value: 'Rs. ${NumberFormat('#,##0').format(totalRevenue.toInt())}',
                icon: Icons.account_balance_wallet_rounded,
                accentColor: const Color(0xFF16A34A),
                iconBgColor: const Color(0xFFF0FDF4),
              ),
              const SizedBox(height: 14),
              _DashboardImageMetricCard(
                title: 'USERS',
                value: '$careProviders',
                icon: Icons.person_pin_rounded,
                accentColor: const Color(0xFF7C3AED),
                iconBgColor: const Color(0xFFF5F3FF),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Recent System Activity',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => showAllLogsDialog(context),
                    icon: const Icon(Icons.list_alt, size: 18),
                    label: const Text(
                      'See All Logs',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const ActivityFeedWidget(),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

// ─── Staff Dashboard View ───────────────────────────────────────────
class _StaffDashboardView extends ConsumerWidget {
  const _StaffDashboardView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(staffMetricsProvider);

    return metricsAsync.when(
      data: (metrics) {
        final totalPatients = metrics['totalPatients'] ?? 0;
        final totalRevenue = (metrics['totalRevenue'] ?? 0.0).toDouble();
        final totalInvoices = metrics['totalInvoices'] ?? 0;

        final profile = ref.watch(userProfileProvider).value;
        final name = profile?['name'] ?? 'Staff Member';

        return Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Hi, $name',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Dashboard Overview',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 16),
                const _PlanHealthOverviewCard(),
                const SizedBox(height: 20),
                // Metrics Cards
                _DashboardImageMetricCard(
                  title: 'MY REGISTERED PATIENTS',
                  value: '$totalPatients',
                  icon: Icons.people,
                  accentColor: Colors.blueAccent,
                  iconBgColor: Colors.blue.shade50,
                ),
                const SizedBox(height: 12),
                _DashboardImageMetricCard(
                  title: 'MY NET PROFIT',
                  value: 'Rs. ${NumberFormat('#,##0').format(totalRevenue.toInt())}',
                  icon: Icons.account_balance_wallet,
                  accentColor: Colors.green,
                  iconBgColor: Colors.green.shade50,
                ),
                const SizedBox(height: 12),
                _DashboardImageMetricCard(
                  title: 'MY INVOICES',
                  value: '$totalInvoices',
                  icon: Icons.receipt_long_rounded,
                  accentColor: Colors.purpleAccent,
                  iconBgColor: Colors.purple.shade50,
                ),
                const SizedBox(height: 32),
                // Action Buttons
                _DashboardActionCard(
                  title: 'Register Patient',
                  icon: Icons.person_add_alt_1,
                  iconBgColor: Colors.blue.shade100,
                  iconColor: Colors.blue.shade700,
                  buttonText: 'REGISTER NOW',
                  buttonColor: Colors.blue.shade700,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const PatientFormScreen()));
                  },
                ),
                const SizedBox(height: 16),
                _DashboardActionCard(
                  title: 'Manage Database',
                  icon: Icons.search,
                  iconBgColor: Colors.green.shade100,
                  iconColor: Colors.green.shade700,
                  buttonText: 'VIEW RECORDS',
                  buttonColor: Colors.green.shade600,
                  onTap: () => context.go('/records'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _DashboardImageMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color accentColor;
  final Color iconBgColor;

  const _DashboardImageMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.accentColor,
    required this.iconBgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000), // Colors.black.withOpacity(0.05)
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Left Accent Border
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: iconBgColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: accentColor, size: 28),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardActionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconBgColor;
  final Color iconColor;
  final String buttonText;
  final Color buttonColor;
  final VoidCallback onTap;

  const _DashboardActionCard({
    required this.title,
    required this.icon,
    required this.iconBgColor,
    required this.iconColor,
    required this.buttonText,
    required this.buttonColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000), // Colors.black.withOpacity(0.03)
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: iconColor, size: 36),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: Text(
                buttonText,
                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanHealthOverviewCard extends ConsumerWidget {
  const _PlanHealthOverviewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expiringPlansAsync = ref.watch(expiringPlansProvider);

    return expiringPlansAsync.when(
      data: (plans) {
        final expiredCount = plans.where((p) => p.category == 'expired' || (p.category == 'scheduled' && p.hoursRemaining < 0)).length;
        final todayCount = plans.where((p) => p.category == 'today' || (p.category == 'scheduled' && p.hoursRemaining >= 0 && p.hoursRemaining <= 24)).length;
        final activeCount = plans.where((p) => p.category == 'upcoming' || (p.category == 'scheduled' && p.hoursRemaining > 24)).length;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0x0A000000),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.health_and_safety_rounded, size: 18, color: Color(0xFF1565C0)),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'PLAN HEALTH OVERVIEW',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '14-Day Cycle',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildHealthPill(
                      label: 'Active Plans',
                      count: activeCount,
                      color: Colors.green.shade700,
                      bgColor: Colors.green.shade50,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildHealthPill(
                      label: 'Due in 24h',
                      count: todayCount,
                      color: Colors.orange.shade800,
                      bgColor: Colors.orange.shade50,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildHealthPill(
                      label: 'Expired',
                      count: expiredCount,
                      color: Colors.red.shade700,
                      bgColor: Colors.red.shade50,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildHealthPill({
    required String label,
    required int count,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

