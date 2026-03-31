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

              final docs = snapshot.data!.docs
                  .where((doc) {
                    final status = OrderStatusUtils.normalizeStatus((doc['status'] ?? 'placed').toString());
                    if (_statusFilter == 'All') return true;
                    return status == _statusFilter.toLowerCase();
                  })
                  .toList();

              if (docs.isEmpty) {
                return const Center(child: Text('No KOTs for selected status.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final tableName = (data['tableName'] ?? data['tableId'] ?? 'Unknown').toString();
                  final status = OrderStatusUtils.normalizeStatus((data['status'] ?? 'placed').toString());
                  final items = (data['items'] as List?) ?? [];

                  return Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => KotDetailsScreen(kotId: docs[index].id)));
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Table: $tableName', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _statusColor(status).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(status.toUpperCase(), style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (items.isEmpty) const Text('No items')
                            else ...items.take(3).map((item) {
                              final qty = item['quantity'] ?? 0;
                              final name = (item['name'] ?? 'Item').toString();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text('• $name x $qty', style: const TextStyle(fontSize: 15)),
                              );
                            }),
                            if (items.length > 3)
                              Text('+${items.length - 3} more', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12)),
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
    final options = ['All', 'placed', 'preparing', 'served', 'closed'];
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
                label: Text(status.toUpperCase()),
                selected: selected,
                selectedColor: Theme.of(context).colorScheme.primary,
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
      case 'served':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }
}
