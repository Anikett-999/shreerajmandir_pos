import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/debug_logger.dart';
import '../../models/table_model.dart';
import '../../utils/order_status_utils.dart';
import '../../utils/debouncer.dart';
import 'menu_screen.dart';

class OrderSummaryScreen extends StatefulWidget {
  final TableModel table;
  final String orderId;

  const OrderSummaryScreen({super.key, required this.table, required this.orderId});

  @override
  State<OrderSummaryScreen> createState() => _OrderSummaryScreenState();
}

class _OrderSummaryScreenState extends State<OrderSummaryScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _debouncer = Debouncer(milliseconds: 1000);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('Table ${widget.table.name} Order'),
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: _firestore.collection('orders').doc(widget.orderId).snapshots(),
            builder: (context, snapshot) {
              final rawStatus = snapshot.hasData && snapshot.data!.exists 
                  ? (snapshot.data!.data() as Map<String, dynamic>)['status'] ?? 'placed'
                  : 'placed';
              final status = OrderStatusUtils.normalizeStatus(rawStatus.toString());

              if (rawStatus.toString().toLowerCase() == 'bill_requested' || rawStatus.toString().toLowerCase() == 'bill-requested') {
                return const Padding(
                  padding: EdgeInsets.only(right: 16.0),
                  child: Center(child: Text('Bill Requested', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                );
              }

              return TextButton.icon(
                onPressed: () => _debouncer.run(() => _requestBill(context)),
                icon: const Icon(Icons.receipt_long, color: Colors.white),
                label: const Text('Request Bill', style: TextStyle(color: Colors.white)),
              );
            }
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('orders').doc(widget.orderId)
            .collection('items')
            .where('restaurantId', isEqualTo: context.read<AuthService>().restaurantId)
            .orderBy('status').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Unable to load order items: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final items = snapshot.data!.docs;
          if (items.isEmpty) return const Center(child: Text('No items yet'));

          double totalAmount = 0;
          for (var doc in items) {
            totalAmount += ((doc.data() as Map<String,dynamic>)['totalPrice'] ?? 0).toDouble();
          }

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final data = items[index].data() as Map<String, dynamic>;
                    return _buildOrderItemCard(data);
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))]
                ),
                child: SafeArea(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total:', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      Text('₹${totalAmount.toStringAsFixed(2)}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                    ],
                  ),
                ),
              )
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => MenuScreen(table: widget.table)));
        },
        icon: const Icon(Icons.add),
        label: const Text('Add More'),
      ),
    );
  }

  Widget _buildOrderItemCard(Map<String, dynamic> data) {
    final rawStatus = (data['status'] ?? 'placed').toString();
    final status = OrderStatusUtils.normalizeStatus(rawStatus);
    Color statusColor;
    switch (status) {
      case 'preparing':
        statusColor = Colors.orange;
        break;
      case 'served':
        statusColor = Colors.green;
        break;
      case 'cancelled':
      case 'closed':
        statusColor = Colors.grey;
        break;
      default: // placed
        statusColor = Colors.blue;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Row(
          children: [
            Text('${data['quantity']}x', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary, fontSize: 16)),
            const SizedBox(width: 12),
            Expanded(child: Text(data['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          ],
        ),
        subtitle: data['specialInstructions'] != null && data['specialInstructions'].toString().isNotEmpty
            ? Text('Note: ${data['specialInstructions']}', style: const TextStyle(color: Colors.redAccent))
            : null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('₹${data['totalPrice'].toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(OrderStatusUtils.getDisplayLabel(status), style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _requestBill(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request Bill?'),
        content: const Text('This will notify the cashier and lock the order from adding new items.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      )
    );

    if (confirm == true) {
      final auth = context.read<AuthService>();
      final orderSnapshot = await _firestore.collection('orders').doc(widget.orderId).get();
      final previousState = orderSnapshot.exists
          ? ((orderSnapshot.data() as Map<String, dynamic>)['status'] ?? 'unknown').toString()
          : 'unknown';

      await OrderStatusUtils.updateOrderStatus(
        orderId: widget.orderId,
        targetStatus: 'served',
        role: auth.role.name,
        auth: auth,
      );

      DebugLogger.logEvent(
        event: 'bill_requested',
        data: {
          'userRole': auth.role.name,
          'userId': auth.currentUser?.uid,
          'tableId': widget.table.id,
          'orderId': widget.orderId,
          'lockedBy': null,
          'previousState': previousState,
          'newState': 'served',
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bill requested successfully.')));
      }
    }
  }
}
