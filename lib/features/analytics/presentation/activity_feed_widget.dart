import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../invoices/domain/invoice_model.dart';
import '../../invoices/presentation/widgets/invoice_details_dialog.dart';

class Activity {
  final String id;
  final String userName;
  final String action;
  final String description;
  final String? entityType;
  final String? entityId;
  final DateTime timestamp;

  Activity({
    required this.id,
    required this.userName,
    required this.action,
    required this.description,
    this.entityType,
    this.entityId,
    required this.timestamp,
  });
}

final _idRegex = RegExp(r'\b[A-Za-z0-9]{18,32}\b');

String _formatActivityDescription(String desc) {
  return desc.replaceAllMapped(_idRegex, (match) {
    final id = match.group(0)!;
    return '#${id.substring(0, 6)}...';
  });
}

final activitiesProvider = StreamProvider<List<Activity>>((ref) {
  return FirebaseFirestore.instance
      .collection('activities')
      .orderBy('timestamp', descending: true)
      .limit(10) // Restricted to last 10 activities for dashboard view
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            return Activity(
              id: doc.id,
              userName: data['userName'] ?? 'Unknown',
              action: data['action'] ?? '',
              description: data['description'] ?? '',
              entityType: data['entityType'] as String?,
              entityId: (data['entityId'] ?? data['invoiceId'] ?? data['patientId']) as String?,
              timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
            );
          }).toList());
});

class ActivityFeedWidget extends ConsumerWidget {
  const ActivityFeedWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activitiesAsync = ref.watch(activitiesProvider);

    return activitiesAsync.when(
      data: (activities) {
        if (activities.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text("No recent activities.")),
          );
        }
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: activities.length,
          itemBuilder: (context, index) {
            final act = activities[index];
            final isInvoice = (act.entityType == 'invoice') || act.action.contains('INVOICE');
            final timeStr = DateFormat('MMM dd, yyyy • hh:mm a').format(act.timestamp);

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  tileColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  leading: CircleAvatar(
                    backgroundColor: isInvoice ? Colors.purple.shade50 : Colors.blue.shade50,
                    radius: 18,
                    child: Icon(
                      isInvoice ? Icons.receipt_long : Icons.person_outline,
                      color: isInvoice ? Colors.purple.shade700 : Colors.blue.shade700,
                      size: 18,
                    ),
                  ),
                  title: Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Text(
                      _formatActivityDescription(act.description),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            Icon(Icons.person, size: 13, color: Colors.blue.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'By: ',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                            Text(
                              act.userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isInvoice ? Colors.purple.shade50 : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isInvoice ? Colors.purple.shade200 : Colors.blue.shade200,
                              ),
                            ),
                            child: Text(
                              act.action,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: isInvoice ? Colors.purple.shade700 : Colors.blue.shade700,
                              ),
                            ),
                          ),
                          Text(
                            timeStr,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade400),
                  onTap: () async {
                    if (isInvoice) {
                      if (act.entityId != null && act.entityId!.isNotEmpty) {
                        try {
                          final doc = await FirebaseFirestore.instance
                              .collection('invoices')
                              .doc(act.entityId)
                              .get();
                          if (doc.exists && context.mounted) {
                            final invoice = Invoice.fromMap(doc.data()!, doc.id);
                            showDialog(
                              context: context,
                              builder: (_) => InvoiceDetailsDialog(invoice: invoice),
                            );
                            return;
                          }
                        } catch (_) {}
                      }
                      if (context.mounted) {
                        context.go('/invoices');
                      }
                    } else {
                      context.go('/records');
                    }
                  },
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error loading activities: $e')),
    );
  }
}

// ─── Paginated All Logs Dialog ───
void showAllLogsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const _AllLogsDialog(),
  );
}

class _AllLogsDialog extends StatefulWidget {
  const _AllLogsDialog();

  @override
  State<_AllLogsDialog> createState() => _AllLogsDialogState();
}

class _AllLogsDialogState extends State<_AllLogsDialog> {
  final List<DocumentSnapshot> _logs = [];
  bool _isLoading = true;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _fetchInitialLogs();
  }

  Future<void> _fetchInitialLogs() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('activities')
          .orderBy('timestamp', descending: true)
          .limit(_pageSize)
          .get();

      if (mounted) {
        setState(() {
          _logs.addAll(snap.docs);
          _isLoading = false;
          if (snap.docs.length < _pageSize) {
            _hasMore = false;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMoreLogs() async {
    if (!_hasMore || _isLoadingMore || _logs.isEmpty) return;

    setState(() => _isLoadingMore = true);
    try {
      final lastDoc = _logs.last;
      final snap = await FirebaseFirestore.instance
          .collection('activities')
          .orderBy('timestamp', descending: true)
          .startAfterDocument(lastDoc)
          .limit(_pageSize)
          .get();

      if (mounted) {
        setState(() {
          _logs.addAll(snap.docs);
          _isLoadingMore = false;
          if (snap.docs.length < _pageSize) {
            _hasMore = false;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('All System Logs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _logs.isEmpty
                ? const Center(child: Text('No activity logs found.'))
                : Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                            final data = _logs[index].data() as Map<String, dynamic>;
                            final userName = data['userName'] ?? 'Unknown';
                            final action = data['action'] ?? '';
                            final description = data['description'] ?? '';
                            final entityType = data['entityType'] as String?;
                            final entityId = (data['entityId'] ?? data['invoiceId'] ?? data['patientId']) as String?;
                            final ts = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
                            final timeStr = DateFormat('MMM dd, yyyy • hh:mm a').format(ts);
                            final isInvoice = (entityType == 'invoice') || action.contains('INVOICE');

                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                clipBehavior: Clip.antiAlias,
                                child: ListTile(
                                  tileColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  leading: CircleAvatar(
                                    backgroundColor: isInvoice ? Colors.purple.shade50 : Colors.blue.shade50,
                                    radius: 18,
                                    child: Icon(
                                      isInvoice ? Icons.receipt_long : Icons.person_outline,
                                      color: isInvoice ? Colors.purple.shade700 : Colors.blue.shade700,
                                      size: 18,
                                    ),
                                  ),
                                  title: Padding(
                                    padding: const EdgeInsets.only(bottom: 4.0),
                                    child: Text(
                                      _formatActivityDescription(description),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Icon(Icons.person, size: 13, color: Colors.blue.shade700),
                                          const SizedBox(width: 4),
                                          Text(
                                            'By: ',
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                          ),
                                          Expanded(
                                            child: Text(
                                              userName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue.shade900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isInvoice ? Colors.purple.shade50 : Colors.blue.shade50,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(
                                                color: isInvoice ? Colors.purple.shade200 : Colors.blue.shade200,
                                              ),
                                            ),
                                            child: Text(
                                              action,
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.bold,
                                                color: isInvoice ? Colors.purple.shade700 : Colors.blue.shade700,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            timeStr,
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  trailing: Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade400),
                                  onTap: () async {
                                    Navigator.pop(context); // Close logs modal
                                    if (isInvoice && entityId != null && entityId.isNotEmpty) {
                                      try {
                                        final doc = await FirebaseFirestore.instance.collection('invoices').doc(entityId).get();
                                        if (doc.exists && context.mounted) {
                                          showDialog(
                                            context: context,
                                            builder: (_) => InvoiceDetailsDialog(invoice: Invoice.fromMap(doc.data()!, doc.id)),
                                          );
                                          return;
                                        }
                                      } catch (_) {}
                                      if (context.mounted) context.go('/invoices');
                                    } else {
                                      context.go('/records');
                                    }
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (_hasMore) ...[
                        const SizedBox(height: 8),
                        _isLoadingMore
                            ? const CircularProgressIndicator()
                            : SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _fetchMoreLogs,
                                  icon: const Icon(Icons.arrow_downward, size: 16),
                                  label: const Text('Load More Logs'),
                                ),
                              ),
                      ],
                    ],
                  ),
      ),
    );
  }
}
