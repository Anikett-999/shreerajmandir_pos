import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/debug_logger.dart';
import '../../utils/order_status_utils.dart';
import '../../utils/table_state_sync.dart';

class KitchenDashboard extends StatelessWidget {
  const KitchenDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final restaurantId = auth.restaurantId;
    final profileIssue = auth.profileIssueMessage;
    final restaurantIds = <String>{
      if (restaurantId != null && restaurantId.isNotEmpty) restaurantId,
      kitchenFallbackRestaurantId,
    }.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kitchen KOT Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthService>().logout(),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: restaurantIds.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  profileIssue ?? 'Restaurant profile missing for this user.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('kots')
                  .where('restaurantId', whereIn: restaurantIds)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Unable to load KOT entries: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = [...snapshot.data!.docs];
                docs.sort((a, b) {
                  final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                  final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                  if (aTime == null && bTime == null) return 0;
                  if (aTime == null) return 1;
                  if (bTime == null) return -1;
                  return bTime.compareTo(aTime);
                });
                if (docs.isEmpty) {
                  return const Center(child: Text('No KOT entries found.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final status = OrderStatusUtils.normalizeStatus((data['status'] ?? '').toString());
                    final tableId = (data['tableId'] ?? data['tableName'] ?? 'N/A').toString();
                    final orderId = (data['orderId'] ?? 'N/A').toString();
                    final createdAt = _formatDateTime(data['createdAt']);
                    final items = ((data['items'] as List?) ?? const [])
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Table/Token: $tableId',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                _StatusChip(status: status),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('Order ID: $orderId'),
                            Text('Created: $createdAt'),
                            const SizedBox(height: 8),
                            const Text('Items:', style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            if (items.isEmpty)
                              const Text('- No items')
                            else
                              ...items.map((item) {
                                final name = (item['name'] ?? 'Item').toString();
                                final qty = (item['quantity'] ?? 0).toString();
                                return Text('- $name x $qty');
                              }),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                if (status == 'placed')
                                  ElevatedButton(
                                    onPressed: () => _updateKotStatus(
                                      context: context,
                                      kotId: doc.id,
                                      data: data,
                                      targetStatus: 'preparing',
                                      event: 'kot_preparing',
                                    ),
                                    child: const Text('Mark Preparing'),
                                  ),
                                if (status == 'preparing')
                                  ElevatedButton(
                                    onPressed: () => _updateKotStatus(
                                      context: context,
                                      kotId: doc.id,
                                      data: data,
                                      targetStatus: 'served',
                                      event: 'kot_served',
                                    ),
                                    child: const Text('Mark Served'),
                                  ),
                                if (status == 'served')
                                  const Text(
                                    'Served',
                                    style: TextStyle(fontWeight: FontWeight.w700, color: Colors.green),
                                  ),
                              ],
                            ),
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

  String _formatDateTime(dynamic createdAt) {
    if (createdAt is Timestamp) {
      return DateFormat('dd MMM yyyy, hh:mm a').format(createdAt.toDate());
    }
    return 'N/A';
  }

  Future<void> _updateKotStatus({
    required BuildContext context,
    required String kotId,
    required Map<String, dynamic> data,
    required String targetStatus,
    required String event,
  }) async {
    final auth = context.read<AuthService>();
    final orderId = (data['orderId'] ?? '').toString();
    final tableId = (data['tableId'] ?? data['tableName'] ?? '').toString();
    final firestore = FirebaseFirestore.instance;

    try {
      // First, gather all KOT doc ids for this order so we can validate them inside a transaction.
      final kotQuery = orderId.isNotEmpty
          ? await firestore.collection('kots').where('orderId', isEqualTo: orderId).get()
          : null;
      final kotIds = (kotQuery?.docs ?? []).map((d) => d.id).toList();

      await firestore.runTransaction((tx) async {
        final kotRef = firestore.collection('kots').doc(kotId);
        // Update this KOT's status within the transaction
        tx.update(kotRef, {'status': targetStatus, 'updatedAt': FieldValue.serverTimestamp()});

        var allReady = true;
        // Validate current statuses of all KOTs for this order inside the transaction
        for (final id in kotIds) {
          final ref = firestore.collection('kots').doc(id);
          final snap = await tx.get(ref);
          final s = (snap.data()?['status'] ?? '').toString().toLowerCase();
          // Consider the just-updated KOT as targetStatus
          final effective = (id == kotId) ? targetStatus.toLowerCase() : s;
          if (OrderStatusUtils.normalizeStatus(effective) != 'served') {
            allReady = false;
            break;
          }
        }

        if (allReady && orderId.isNotEmpty) {
          final orderRef = firestore.collection('orders').doc(orderId);
          tx.update(orderRef, {'status': 'served', 'updatedAt': FieldValue.serverTimestamp()});

          // Sync table state within the same transaction
          await TableStateSync.syncTableForOrderChange(
            firestore: firestore,
            tableId: tableId,
            orderId: orderId,
            orderState: 'served',
            auth: auth,
            transaction: tx,
          );

          DebugLogger.logEvent(
            event: 'order_marked_ready',
            data: {
              'orderId': orderId,
              'tableId': tableId,
              'triggeredBy': 'kitchen',
              'userRole': auth.role.name,
              'userId': auth.currentUser?.uid,
            },
          );
        }
      });

      // Emit the KOT-level event (separate from order_marked_ready)
      DebugLogger.logEvent(
        event: event,
        data: {
          'userRole': auth.role.name,
          'userId': auth.currentUser?.uid,
          'orderId': orderId,
          'tableId': tableId,
          'kotId': kotId,
          'lockedBy': null,
          'previousState': null,
          'newState': targetStatus,
        },
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update KOT status: $e')),
        );
      }
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;

    switch (status) {
      case 'served':
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF2E7D32);
        break;
      case 'preparing':
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFEF6C00);
        break;
      case 'placed':
        bg = const Color(0xFFE3F2FD);
        fg = const Color(0xFF1565C0);
        break;
      default:
        bg = const Color(0xFFF5F5F5);
        fg = const Color(0xFF616161);
        break;
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
