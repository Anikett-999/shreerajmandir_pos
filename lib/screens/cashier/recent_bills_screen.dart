import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/report_service.dart';

class RecentBillsScreen extends StatefulWidget {
  const RecentBillsScreen({super.key});

  @override
  State<RecentBillsScreen> createState() => _RecentBillsScreenState();
}

class _RecentBillsScreenState extends State<RecentBillsScreen> {
  static const Color _adminAppBarColor = Color(0xFF922224);
  static const Color _adminPageTint = Color(0xFFF9F7F5);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime get _dayStart => DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
  DateTime get _nextDayStart => _dayStart.add(const Duration(days: 1));

  Query<Map<String, dynamic>> _buildBillsQuery(String? restaurantId) {
    return _firestore
        .collection('orders')
        .where('restaurantId', isEqualTo: restaurantId)
        .where('status', isEqualTo: 'closed')
        .where('billedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_dayStart))
        .where('billedAt', isLessThan: Timestamp.fromDate(_nextDayStart))
        .orderBy('billedAt', descending: true);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  bool _matchesSearch(Map<String, dynamic> data, String docId) {
    if (_searchQuery.trim().isEmpty) return true;

    final q = _searchQuery.trim().toLowerCase();
    final tableText = (data['tableName'] ?? '').toString().toLowerCase();
    final receiptNo = data['receiptNumber']?.toString() ?? '';
    final billId = receiptNo.isNotEmpty ? receiptNo.padLeft(6, '0') : docId.substring(0, 6).toUpperCase();

    return tableText.contains(q) || billId.toLowerCase().contains(q);
  }

  Future<void> _openBillPreview(Map<String, dynamic> data, String orderId) async {
    // Ensure persistent receipt number exists before printing
    try {
      final receipt = await ReportService.ensureReceiptNumberForOrder(orderId);
      data['receiptNumber'] = receipt;
    } catch (e) {
      // ignore and proceed with whatever data we have
    }

    await ReportService.printFinalBill(
      orderData: data,
      orderId: orderId,
      subtotal: (data['subtotal'] ?? data['totalAmount'] ?? 0.0).toDouble(),
      cgst: (data['cgst'] ?? 0.0).toDouble(),
      sgst: (data['sgst'] ?? 0.0).toDouble(),
      total: (data['grandTotal'] ?? data['totalAmount'] ?? 0.0).toDouble(),
      paymentMode: (data['paymentMode'] ?? 'Cash').toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();

    return Scaffold(
      backgroundColor: _adminPageTint,
      appBar: AppBar(
        backgroundColor: _adminAppBarColor,
        foregroundColor: Colors.white,
        title: const Text('Recent Bills', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(DateFormat('dd MMM yyyy').format(_selectedDate)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      hintText: 'Search by table or bill ID',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      filled: true,
                      fillColor: _adminPageTint,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _buildBillsQuery(auth.restaurantId).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Unable to load bills for selected date.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? const [];
                final filtered = docs.where((doc) => _matchesSearch(doc.data(), doc.id)).toList();

                if (filtered.isEmpty) {
                  return const Center(
                    child: Text('No bills found for selected date', style: TextStyle(fontSize: 16, color: Colors.black54)),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final doc = filtered[index];
                    final data = doc.data();

                    final billedAt = (data['billedAt'] as Timestamp?)?.toDate() ?? (data['createdAt'] as Timestamp?)?.toDate();
                    final timeText = billedAt != null ? DateFormat('h:mm a').format(billedAt) : '--:--';
                    final tableText = (data['tableName'] ?? 'N/A').toString();
                    final itemsCount = (data['items'] as List?)?.length ?? 0;
                    final total = (data['grandTotal'] ?? data['totalAmount'] ?? 0.0).toDouble();
                    final paymentMode = (data['paymentMode'] ?? '').toString();
                    final receiptNo = data['receiptNumber']?.toString() ?? '';
                    final billId = receiptNo.isNotEmpty ? receiptNo.padLeft(6, '0') : doc.id.substring(0, 6).toUpperCase();

                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _openBillPreview(data, doc.id),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF8C1026).withOpacity(0.15)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('TABLE $tableText', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                  Text(timeText, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text('₹${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF922224))),
                                  const SizedBox(width: 12),
                                  Text('$itemsCount items', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                  if (paymentMode.isNotEmpty) ...[
                                    const SizedBox(width: 12),
                                    Text(paymentMode, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Bill #$billId', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.green.shade200),
                                    ),
                                    child: const Text('Completed', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.green)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
