
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/order_status_utils.dart';

class KitchenDashboard extends StatelessWidget {
  const KitchenDashboard({super.key});

  String _normalizeKotStatus(String rawStatus) {
    final normalized = rawStatus.trim().toLowerCase();
    switch (normalized) {
      case 'pending':
      case 'active':
      case 'open':
        return 'placed';
      case 'placed':
      case 'preparing':
      case 'prepared':
      case 'served':
      case 'closed':
      case 'cancelled':
        return normalized;
      case 'ready':
      case 'done':
      case 'bill_requested':
      case 'bill-requested':
        return 'served';
      case 'billed':
        return 'closed';
      default:
        return OrderStatusUtils.normalizeStatus(normalized);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final allowedRoles = ['kitchen', 'admin'];
    final canEditStatus = allowedRoles.contains(auth.role.name);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kitchen KOTs'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('kots').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading KOTs'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('No KOTs found.'));
          }
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final status = _normalizeKotStatus((data['status'] ?? '').toString());
              final table = (data['tableName'] ?? data['tableId'] ?? 'N/A').toString();
              final items = ((data['items'] as List?) ?? const [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Table: $table', style: const TextStyle(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          _StatusChip(status: status),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...items.map((item) {
                        final name = (item['name'] ?? 'Item').toString();
                        final qty = item['quantity'] ?? 1;
                        final category = (item['category'] ?? '').toString().trim();
                        final notes = (item['notes'] ?? item['specialInstructions'] ?? '').toString().trim();

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    if (category.isNotEmpty)
                                      Text(
                                        'Category: $category',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    if (notes.isNotEmpty)
                                      Text(
                                        'Note: $notes',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                'x$qty',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (items.isEmpty)
                        const Text('No items.'),
                      const SizedBox(height: 10),
                      if (canEditStatus)
                        Row(
                          children: [
                            if (status == 'placed')
                              ElevatedButton(
                                onPressed: () => _updateStatus(context, docs[index].id, 'preparing'),
                                child: const Text('Mark Preparing'),
                              ),
                            if (status == 'preparing')
                              ElevatedButton(
                                onPressed: () => _updateStatus(context, docs[index].id, 'prepared'),
                                child: const Text('Mark Prepared'),
                              ),
                            if (status == 'prepared')
                              const Text('Prepared', style: TextStyle(color: Colors.orange)),
                            if (status == 'served')
                              const Text('Served', style: TextStyle(color: Colors.green)),
                          ],
                        ),
                      if (!canEditStatus)
                        Text('You do not have permission to update status.', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _updateStatus(BuildContext context, String kotId, String targetStatus) async {
    try {
      await FirebaseFirestore.instance.collection('kots').doc(kotId).update({
        'status': targetStatus,
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status updated to $targetStatus')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (status) {
      case 'served':
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        break;
      case 'preparing':
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade800;
        break;
      case 'prepared':
        bg = Colors.deepOrange.shade50;
        fg = Colors.deepOrange.shade700;
        break;
      case 'placed':
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade800;
        break;
      case 'closed':
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
        break;
      case 'cancelled':
        bg = Colors.red.shade50;
        fg = Colors.red.shade700;
        break;
      default:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.w700, color: fg, fontSize: 11),
      ),
    );
  }
}
