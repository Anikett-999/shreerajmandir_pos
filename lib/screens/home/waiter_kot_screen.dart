import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/order_status_utils.dart';
import '../kot/kot_details_screen.dart';

class WaiterKotScreen extends StatefulWidget {
  const WaiterKotScreen({super.key});

  @override
  State<WaiterKotScreen> createState() => _WaiterKotScreenState();
}

class _WaiterKotScreenState extends State<WaiterKotScreen> {
  String _statusFilter = 'All';

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
    final restaurantId = auth.restaurantId;

    if (restaurantId == null || restaurantId.isEmpty) {
      return const Center(child: Text('Missing restaurant info.'));
    }

    return Column(
      children: [
        _buildFilterChips(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('kots')
                .where('restaurantId', isEqualTo: restaurantId)
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Failed to load KOTs: ${snapshot.error}'),
                ));
              }
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

              // Keep all KOTs visible so every state can be tracked from the tag.
              final docs = snapshot.data!.docs
                  .where((doc) {
                    final status = _normalizeKotStatus((doc['status'] ?? 'placed').toString());
                    if (_statusFilter == 'All') return true;
                    return status == _statusFilter.toLowerCase();
                  })
                  .toList();

              if (docs.isEmpty) {
                return const Center(child: Text('No KOTs for selected status.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final tableName = (data['tableName'] ?? data['tableId'] ?? 'Unknown').toString();
                  final status = _normalizeKotStatus((data['status'] ?? 'placed').toString());
                  final items = (data['items'] as List?) ?? [];
                  final createdAt = data['createdAt'] is Timestamp
                      ? (data['createdAt'] as Timestamp).toDate()
                      : null;
                  String timeAgo = '';
                  if (createdAt != null) {
                    final diff = DateTime.now().difference(createdAt);
                    if (diff.inMinutes < 1) {
                      timeAgo = 'Just now';
                    } else if (diff.inMinutes < 60) {
                      timeAgo = '${diff.inMinutes} min ago';
                    } else {
                      timeAgo = TimeOfDay.fromDateTime(createdAt).format(context);
                    }
                  }

                  return Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.1),
                    ),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => KotDetailsScreen(kotId: docs[index].id)));
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'TABLE ${tableName.toUpperCase()}',
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: 1.1),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _statusColor(status).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: _statusColor(status), width: 1),
                                  ),
                                  child: Text(status.toUpperCase(), style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.w700, fontSize: 12)),
                                ),
                                if (timeAgo.isNotEmpty) ...[
                                  const SizedBox(width: 10),
                                  Text(timeAgo, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (items.isEmpty) const Text('No items')
                            else ...items.map((item) {
                              final qty = item['quantity'] ?? 0;
                              final name = (item['name'] ?? 'Item').toString();
                              final category = (item['category'] ?? '').toString();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Row(
                                  children: [
                                    Text(name, style: const TextStyle(fontSize: 15)),
                                    const SizedBox(width: 6),
                                    Text(
                                      category.isNotEmpty ? '[$category]' : '[Type]',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                    const Spacer(),
                                    Text('× $qty', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                  ],
                                ),
                              );
                            }),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                // Waiter authority is only prepared -> served.
                                if (status == 'prepared')
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(context).colorScheme.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () async {
                                      // Move KOT to served when food is handed to customer.
                                      await FirebaseFirestore.instance.collection('kots').doc(docs[index].id).update({'status': 'served'});
                                    },
                                    child: const Text('Mark Served'),
                                  ),
                                if (status == 'preparing')
                                  const Text(
                                    'Waiting for kitchen to mark PREPARED',
                                    style: TextStyle(fontWeight: FontWeight.w600, color: Colors.orange),
                                  ),
                                if (status == 'served')
                                  const Text('Served', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.green)),
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
    );
  }

  Widget _buildFilterChips() {
    final options = ['All', 'placed', 'preparing', 'prepared', 'served', 'closed', 'cancelled'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: options.map((status) {
            final selected = _statusFilter == status;
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ChoiceChip(
                label: Text(status.toUpperCase(), style: TextStyle(color: selected ? Colors.white : Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                selected: selected,
                selectedColor: Theme.of(context).colorScheme.primary,
                backgroundColor: Colors.white,
                shape: StadiumBorder(side: BorderSide(color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300)),
                onSelected: (_) => setState(() => _statusFilter = status),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'preparing':
        return Colors.orange;
      case 'prepared':
        return Colors.deepOrange;
      case 'served':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      case 'cancelled':
        return Colors.red;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }
}
