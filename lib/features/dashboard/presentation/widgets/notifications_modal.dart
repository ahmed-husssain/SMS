import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../shared/providers/plan_expiration_provider.dart';
import '../../../invoices/presentation/invoice_form_screen.dart';
import '../../data/scheduled_notification_repository.dart';
import 'schedule_notification_modal.dart';

class NotificationsModal extends ConsumerStatefulWidget {
  const NotificationsModal({super.key});

  @override
  ConsumerState<NotificationsModal> createState() => _NotificationsModalState();
}

class _NotificationsModalState extends ConsumerState<NotificationsModal> {
  String _selectedFilter = 'all'; // 'all', 'expired', 'today', 'upcoming', 'scheduled'

  Future<void> _launchWhatsApp(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opening WhatsApp: $e')),
        );
      }
    }
  }

  void _openScheduleModal() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ScheduleNotificationModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expiringPlansAsync = ref.watch(expiringPlansProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Drag Handle
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

              // Modal Title & + Schedule Reminder Action
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.notifications_active_rounded, color: Color(0xFF1565C0), size: 22),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'PLAN NOTIFICATIONS',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _openScheduleModal,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.add_alarm_rounded, size: 14),
                        label: const Text(
                          '+ Schedule',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Content & Filter Logic
              Expanded(
                child: expiringPlansAsync.when(
                  data: (allPlans) {
                    final expiredCount = allPlans.where((p) => p.category == 'expired' || (p.category == 'scheduled' && p.hoursRemaining < 0)).length;
                    final todayCount = allPlans.where((p) => p.category == 'today' || (p.category == 'scheduled' && p.hoursRemaining >= 0 && p.hoursRemaining <= 24)).length;
                    final upcomingCount = allPlans.where((p) => p.category == 'upcoming' || (p.category == 'scheduled' && p.hoursRemaining >= 0 && p.hoursRemaining <= 168)).length;
                    final scheduledCount = allPlans.where((p) => p.category == 'scheduled').length;

                    // Filter list based on selected tab
                    final filteredPlans = allPlans.where((p) {
                      if (_selectedFilter == 'expired') {
                        return p.category == 'expired' || (p.category == 'scheduled' && p.hoursRemaining < 0);
                      }
                      if (_selectedFilter == 'today') {
                        return p.category == 'today' || (p.category == 'scheduled' && p.hoursRemaining >= 0 && p.hoursRemaining <= 24);
                      }
                      if (_selectedFilter == 'upcoming') {
                        return p.category == 'upcoming' || (p.category == 'scheduled' && p.hoursRemaining >= 0 && p.hoursRemaining <= 168);
                      }
                      if (_selectedFilter == 'scheduled') {
                        return p.category == 'scheduled';
                      }
                      return true;
                    }).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Interactive Urgency & Scheduled Filter Chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildUrgencyChip('All', 'all', allPlans.length, Colors.blue.shade700),
                              const SizedBox(width: 8),
                              _buildUrgencyChip('📌 Scheduled', 'scheduled', scheduledCount, Colors.indigo.shade700),
                              const SizedBox(width: 8),
                              _buildUrgencyChip('🔴 Expired', 'expired', expiredCount, Colors.red.shade700),
                              const SizedBox(width: 8),
                              _buildUrgencyChip('🟡 Expiring Today', 'today', todayCount, Colors.orange.shade800),
                              const SizedBox(width: 8),
                              _buildUrgencyChip('🔵 Upcoming (7 Days)', 'upcoming', upcomingCount, Colors.teal.shade700),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        Expanded(
                          child: filteredPlans.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.green.shade400),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'No notifications in this category.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  controller: scrollController,
                                  itemCount: filteredPlans.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final item = filteredPlans[index];
                                    final p = item.patient;
                                    final isScheduled = item.category == 'scheduled';

                                    Color accentColor;
                                    Color bgColor;
                                    String tagText;

                                    if (isScheduled) {
                                      accentColor = Colors.indigo.shade700;
                                      bgColor = Colors.indigo.shade50;
                                      tagText = item.scheduledNotification != null && item.scheduledNotification!.targetDays > 0
                                          ? '${item.scheduledNotification!.targetDays}-DAY REMINDER'
                                          : 'SCHEDULED';
                                    } else if (item.category == 'expired') {
                                      accentColor = Colors.red.shade700;
                                      bgColor = Colors.red.shade50;
                                      tagText = 'EXPIRED';
                                    } else if (item.category == 'today') {
                                      accentColor = Colors.orange.shade800;
                                      bgColor = Colors.amber.shade50;
                                      tagText = 'EXPIRES IN ${item.hoursRemaining}H';
                                    } else {
                                      accentColor = Colors.teal.shade700;
                                      bgColor = Colors.teal.shade50;
                                      tagText = 'DUE ON ${DateFormat('MMM d').format(item.expirationDate)}';
                                    }

                                    final careTeam = [
                                      if (p.doctor.isNotEmpty) 'Doc: ${p.doctor}',
                                      if (p.nurse.isNotEmpty) 'Nurse: ${p.nurse}',
                                      if (p.caretaker.isNotEmpty) 'Care: ${p.caretaker}',
                                    ].join(' • ');

                                    return Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: accentColor.withOpacity(0.3)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: accentColor.withOpacity(0.06),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      padding: const EdgeInsets.all(14.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Notification Header
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: bgColor,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  isScheduled
                                                      ? Icons.event_available_rounded
                                                      : (item.category == 'expired'
                                                          ? Icons.warning_amber_rounded
                                                          : (item.category == 'today'
                                                              ? Icons.timer_outlined
                                                              : Icons.calendar_today_rounded)),
                                                  color: accentColor,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item.notificationMessage,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                        color: Color(0xFF0F172A),
                                                        height: 1.3,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Wrap(
                                                      spacing: 8,
                                                      runSpacing: 4,
                                                      children: [
                                                        Text(
                                                          'MR: ${p.mrNumber}',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                            color: Colors.grey.shade600,
                                                          ),
                                                        ),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: bgColor,
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: Text(
                                                            tagText,
                                                            style: TextStyle(
                                                              fontSize: 9,
                                                              fontWeight: FontWeight.bold,
                                                              color: accentColor,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),

                                          // Patient Context & Care Team Details
                                          if (careTeam.isNotEmpty || p.phone.isNotEmpty) ...[
                                            const SizedBox(height: 10),
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade50,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.grey.shade200),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  if (p.phone.isNotEmpty || p.address.isNotEmpty)
                                                    Text(
                                                      [p.phone, p.address].where((s) => s.isNotEmpty).join(' • '),
                                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.black87),
                                                    ),
                                                  if (careTeam.isNotEmpty) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      careTeam,
                                                      style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 12),

                                          // Action Buttons: Responsive Wrap Layout
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              // 1-Click WhatsApp Button
                                              OutlinedButton.icon(
                                                onPressed: () => _launchWhatsApp(item.whatsappUrl),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: const Color(0xFF25D366),
                                                  side: const BorderSide(color: Color(0xFF25D366), width: 1.5),
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                ),
                                                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
                                                label: const Text(
                                                  'WhatsApp 📲',
                                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              // Issue Next Invoice Button (defaults to 15 days or targetDays)
                                              ElevatedButton.icon(
                                                onPressed: () {
                                                  final daysToUse = isScheduled && item.scheduledNotification != null && item.scheduledNotification!.targetDays > 0
                                                      ? item.scheduledNotification!.targetDays
                                                      : 15;
                                                  Navigator.pop(context);
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) => InvoiceFormScreen(patientId: p.patientId, defaultDays: daysToUse),
                                                    ),
                                                  );
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF1565C0),
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                ),
                                                icon: const Icon(Icons.receipt_long_rounded, size: 14),
                                                label: const Text(
                                                  'Issue Invoice ➔',
                                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              // Mark Complete & Delete Buttons (for Scheduled Items)
                                              if (isScheduled && item.scheduledNotification != null) ...[
                                                IconButton(
                                                  tooltip: 'Mark Complete & Dismiss',
                                                  icon: const Icon(Icons.check_circle_outline, color: Colors.green, size: 22),
                                                  onPressed: () async {
                                                    await ref
                                                        .read(scheduledNotificationRepositoryProvider)
                                                        .markAsCompleted(p.patientId, item.scheduledNotification!.id);
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(content: Text('✓ Scheduled reminder marked as completed!')),
                                                      );
                                                    }
                                                  },
                                                ),
                                                IconButton(
                                                  tooltip: 'Delete Notification',
                                                  icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade600, size: 22),
                                                  onPressed: () async {
                                                    await ref
                                                        .read(scheduledNotificationRepositoryProvider)
                                                        .deleteScheduledNotification(p.patientId, item.scheduledNotification!.id);
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(content: Text('✓ Scheduled reminder deleted!')),
                                                      );
                                                    }
                                                  },
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error loading notifications: $e')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUrgencyChip(String label, String value, int count, Color color) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(
        '$label ($count)',
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : color,
        ),
      ),
      selected: isSelected,
      selectedColor: color,
      backgroundColor: Colors.white,
      side: BorderSide(color: isSelected ? color : Colors.grey.shade300),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedFilter = value;
          });
        }
      },
    );
  }
}
