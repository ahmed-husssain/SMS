import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../data/invoice_repository.dart';
import '../invoice_export_page.dart';
import '../invoice_form_screen.dart';
import '../../../patients/data/patient_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/invoice_details_dialog.dart';

class RecentInvoiceHighlightNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setHighlight(String? id) => state = id;
}

final recentInvoiceHighlightProvider = NotifierProvider<RecentInvoiceHighlightNotifier, String?>(
  RecentInvoiceHighlightNotifier.new,
);

class InvoiceSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query.trim();
  void clear() => state = '';
}

final invoiceSearchQueryProvider = NotifierProvider<InvoiceSearchQueryNotifier, String>(
  InvoiceSearchQueryNotifier.new,
);

class InvoicesPage extends ConsumerStatefulWidget {
  const InvoicesPage({super.key});

  @override
  ConsumerState<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends ConsumerState<InvoicesPage> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: ref.read(invoiceSearchQueryProvider));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(userProfileProvider.select((v) => v.value?['role'] ?? 'staff'));
    final highlightId = ref.watch(recentInvoiceHighlightProvider);
    final rawSearchQuery = ref.watch(invoiceSearchQueryProvider);
    final searchQuery = rawSearchQuery.toLowerCase();

    ref.listen<String>(invoiceSearchQueryProvider, (prev, next) {
      if (_searchController.text != next) {
        _searchController.text = next;
      }
    });

    if (highlightId != null) {
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && ref.read(recentInvoiceHighlightProvider) == highlightId) {
          ref.read(recentInvoiceHighlightProvider.notifier).setHighlight(null);
        }
      });
    }

    final invoicesAsync = role == 'admin'
        ? ref.watch(allInvoicesProvider(false))
        : ref.watch(staffInvoicesProvider);

    final patientsAsync = role == 'admin'
        ? ref.watch(allPatientsProvider(true))
        : ref.watch(staffPatientsProvider);

    final patientMap = {
      for (final p in (patientsAsync.value ?? [])) p.patientId: p,
    };

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'INVOICES',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                    letterSpacing: 1.5,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const InvoiceFormScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(
                    'Create Invoice',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004B93),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ─── Instant Multi-Field Invoice Search Bar ───
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: 'Search by Invoice #, MR #, Patient Name, or Status (paid/partial)...',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF1565C0), size: 22),
                  suffixIcon: rawSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            ref.read(invoiceSearchQueryProvider.notifier).clear();
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
                  ref.read(invoiceSearchQueryProvider.notifier).setQuery(val);
                },
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: invoicesAsync.when(
                data: (invoices) {
                  if (invoices.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40.0),
                        child: Text(
                          'NO INVOICES FOUND',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    );
                  }

                  final filteredInvoices = invoices.where((inv) {
                    if (searchQuery.isEmpty) return true;

                    final invNum = inv.invoiceNumber.toLowerCase();
                    final pId = inv.patientId.toLowerCase();
                    final p = patientMap[inv.patientId];
                    final mrNum = (p?.mrNumber ?? '').toLowerCase();
                    final pName = (p?.patientName ?? '').toLowerCase();
                    final status = inv.paymentStatus.toLowerCase();

                    return invNum.contains(searchQuery) ||
                        pId.contains(searchQuery) ||
                        mrNum.contains(searchQuery) ||
                        pName.contains(searchQuery) ||
                        status.contains(searchQuery);
                  }).toList();

                  if (filteredInvoices.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_off_rounded, size: 44, color: Colors.grey),
                            const SizedBox(height: 10),
                            Text(
                              'No invoices found for "$rawSearchQuery"',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF475569),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                _searchController.clear();
                                ref.read(invoiceSearchQueryProvider.notifier).clear();
                              },
                              child: const Text('Clear Search Filter'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final minTableWidth = constraints.maxWidth < 580 ? 580.0 : constraints.maxWidth;
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: minTableWidth,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.black, width: 1.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Column(
                              children: [
                                // Table Header
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFC22727),
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(2.5),
                                      topRight: Radius.circular(2.5),
                                    ),
                                  ),
                                  child: const Row(
                                    children: [
                                      Expanded(flex: 25, child: Text('INVOICE #', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.8))),
                                      Expanded(flex: 38, child: Text('MR NUMBER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.8))),
                                      Expanded(flex: 25, child: Text('GRAND TOTAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.8), textAlign: TextAlign.left)),
                                      Expanded(flex: 12, child: Text('VIEW', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.8), textAlign: TextAlign.center)),
                                    ],
                                  ),
                                ),
                                // Table Body
                                Expanded(
                                  child: ListView.separated(
                                    itemCount: filteredInvoices.length,
                                    separatorBuilder: (context, index) => const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
                                    itemBuilder: (context, index) {
                                      final inv = filteredInvoices[index];
                                      final isRecent = (highlightId != null && (inv.invoiceId == highlightId || inv.invoiceNumber == highlightId));

                                      return AnimatedContainer(
                                        duration: const Duration(milliseconds: 300),
                                        margin: isRecent ? const EdgeInsets.symmetric(vertical: 4, horizontal: 4) : EdgeInsets.zero,
                                        decoration: BoxDecoration(
                                          color: isRecent ? const Color(0xFFF1F5F9) : Colors.transparent,
                                          borderRadius: isRecent ? BorderRadius.circular(6) : BorderRadius.zero,
                                          border: isRecent
                                              ? Border.all(color: const Color(0xFF64748B), width: 1.5)
                                              : null,
                                          boxShadow: isRecent
                                              ? [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.08),
                                                    blurRadius: 8,
                                                    spreadRadius: 1,
                                                    offset: const Offset(0, 3),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (isRecent)
                                              Container(
                                                width: double.infinity,
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFF475569),
                                                  borderRadius: BorderRadius.only(
                                                    topLeft: Radius.circular(4.5),
                                                    topRight: Radius.circular(4.5),
                                                  ),
                                                ),
                                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                                                child: const Row(
                                                  children: [
                                                    Icon(Icons.history_outlined, color: Colors.white, size: 14),
                                                    SizedBox(width: 6),
                                                    Text(
                                                      'RECENT INVOICE',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 10.5,
                                                        letterSpacing: 0.8,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            InkWell(
                                              onTap: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (_) => InvoiceDetailsDialog(invoice: inv),
                                                );
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      flex: 25,
                                                      child: Text(
                                                        inv.invoiceNumber,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          color: Color(0xFF1D4ED8),
                                                          fontWeight: FontWeight.bold,
                                                          fontFamily: 'monospace',
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 38,
                                                      child: _PatientMrText(patientId: inv.patientId),
                                                    ),
                                                    Expanded(
                                                      flex: 25,
                                                      child: Wrap(
                                                        crossAxisAlignment: WrapCrossAlignment.center,
                                                        spacing: 6,
                                                        runSpacing: 4,
                                                        children: [
                                                          Text(
                                                            'Rs. ${NumberFormat('#,###').format(inv.grandTotal.toInt())}',
                                                            style: const TextStyle(
                                                              fontWeight: FontWeight.bold,
                                                              fontSize: 12,
                                                              fontFamily: 'monospace',
                                                              color: Color(0xFF14532D),
                                                            ),
                                                          ),
                                                          _buildStatusBadge(inv.paymentStatus),
                                                        ],
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 12,
                                                      child: Center(
                                                        child: IconButton(
                                                          padding: EdgeInsets.zero,
                                                          constraints: const BoxConstraints(),
                                                          icon: const Icon(
                                                            Icons.visibility_outlined,
                                                            color: Colors.black87,
                                                            size: 18,
                                                          ),
                                                          onPressed: () {
                                                            Navigator.of(context).push(MaterialPageRoute(
                                                              builder: (_) => InvoiceExportPage(invoice: inv),
                                                            ));
                                                          },
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40.0),
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                    ),
                  ),
                ),
                error: (e, _) => Center(
                  child: Text(
                    'Error: $e',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildStatusBadge(String status) {
    final cleanStatus = status.trim().toLowerCase();
    Color bg;
    Color border;
    Color textColor;

    if (cleanStatus == 'paid') {
      bg = Colors.green.shade100;
      border = Colors.green.shade400;
      textColor = Colors.green.shade900;
    } else if (cleanStatus == 'partial') {
      bg = Colors.amber.shade100;
      border = Colors.amber.shade400;
      textColor = Colors.amber.shade900;
    } else {
      bg = Colors.red.shade100;
      border = Colors.red.shade400;
      textColor = Colors.red.shade900;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: textColor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _PatientMrText extends StatefulWidget {
  final String patientId;

  const _PatientMrText({required this.patientId});

  @override
  State<_PatientMrText> createState() => _PatientMrTextState();
}

class _PatientMrTextState extends State<_PatientMrText> {
  static final Map<String, String> _cache = {};
  late Future<String> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchMrNumber();
  }

  @override
  void didUpdateWidget(_PatientMrText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patientId != widget.patientId) {
      _future = _fetchMrNumber();
    }
  }

  Future<String> _fetchMrNumber() async {
    if (widget.patientId.isEmpty) return 'N/A';
    if (_cache.containsKey(widget.patientId)) {
      return _cache[widget.patientId]!;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.patientId)
          .get();
      if (doc.exists && doc.data() != null) {
        final mr = doc.data()!['mrNumber']?.toString() ?? 'Unknown';
        _cache[widget.patientId] = mr;
        return mr;
      }
    } catch (_) {}
    return widget.patientId;
  }

  @override
  Widget build(BuildContext context) {
    if (_cache.containsKey(widget.patientId)) {
      return Text(
        _cache[widget.patientId]!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          fontFamily: 'monospace',
          color: Color(0xFF222222),
        ),
      );
    }

    return FutureBuilder<String>(
      future: _future,
      builder: (context, snapshot) {
        final text = snapshot.data ?? '...';
        return Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            color: Color(0xFF222222),
          ),
        );
      },
    );
  }
}
