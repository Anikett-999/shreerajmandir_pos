import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../models/table_model.dart';
import '../../services/auth_service.dart';
import '../../services/report_service.dart';
import '../../utils/order_status_utils.dart';
import '../../widgets/order_dialog.dart';

/// CashierTablesTab — a restricted copy of Admin's TablesTab UI for Cashiers.
/// Matches Admin visual style but removes Create/Edit/Delete actions.
class CashierTablesTab extends StatefulWidget {
  const CashierTablesTab({super.key});

  @override
  State<CashierTablesTab> createState() => _CashierTablesTabState();
}

class _CashierTablesTabState extends State<CashierTablesTab> {
  final _firestore = FirebaseFirestore.instance;
  static const Color _brandMaroon = Color(0xFF8C1026);
  static const Color _cardBackground = Color(0xFFF5E8E8);
  static const Color _pageTint = Color(0xFFF9F7F5);
  String _selectedFilter = 'all';

  @override
  Widget build(BuildContext context) {
    return _buildTablesView();
  }

  Widget _buildTablesView() {
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('tables').where('restaurantId', isEqualTo: restaurantId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final allTables = snapshot.data!.docs;
        final tables = allTables.toList();

        tables.sort((a, b) {
          final aName = (a.data() as Map<String, dynamic>)['name']?.toString() ?? '';
          final bName = (b.data() as Map<String, dynamic>)['name']?.toString() ?? '';

          final aNumber = _extractTableNumber(aName);
          final bNumber = _extractTableNumber(bName);

          if (aNumber != null && bNumber != null) {
            final numberCompare = aNumber.compareTo(bNumber);
            if (numberCompare != 0) return numberCompare;
          } else if (aNumber != null) {
            return -1;
          } else if (bNumber != null) {
            return 1;
          }

          return aName.toLowerCase().compareTo(bName.toLowerCase());
        });

        return Container(
          color: _pageTint,
          child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  DropdownButtonHideUnderline(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: _brandMaroon.withOpacity(0.35)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButton<String>(
                        value: _selectedFilter,
                        icon: const Icon(Icons.arrow_drop_down),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All')),
                          DropdownMenuItem(value: 'placed', child: Text('Placed')),
                          DropdownMenuItem(value: 'prepared', child: Text('Prepared')),
                          DropdownMenuItem(value: 'preparing', child: Text('Preparing')),
                          DropdownMenuItem(value: 'served', child: Text('Served')),
                          DropdownMenuItem(value: 'closed', child: Text('Closed')),
                          DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _selectedFilter = value);
                        },
                      ),
                    ),
                  ),
                  // Note: Create table button intentionally removed for Cashier role
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final gridWidth = constraints.maxWidth;
                  final isMobile = gridWidth < 600;
                  final crossAxis = isMobile ? 2 : (gridWidth < 900 ? 4 : 6);

                  return GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxis,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                      childAspectRatio: isMobile ? 0.80 : 1.0,
                    ),
                    itemCount: tables.length,
                    itemBuilder: (context, index) {
                      final table = TableModel.fromMap(tables[index].id, tables[index].data() as Map<String, dynamic>);
                      final isOccupied = table.status == TableStatus.occupied || table.status == TableStatus.kotSent || table.status == TableStatus.billRequested;
                      final String? orderId = table.currentOrderId;

                      return _buildCashierTableCard(table, isOccupied, orderId ?? '', isMobile, restaurantId);
                    },
                  );
                },
              ),
            ),
          ],
          ),
        );
      },
    );
  }

  Widget _buildCashierTableCard(TableModel table, bool isOccupied, String orderId, bool isMobile, String? restaurantId) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _brandMaroon.withOpacity(0.25), width: 1),
        boxShadow: [BoxShadow(color: _brandMaroon.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    table.name,
                    style: TextStyle(fontSize: isMobile ? 12 : 14, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Edit/Delete icons removed for Cashier
                const SizedBox(width: 4),
              ],
            ),
            const SizedBox(height: 6),
            if (isOccupied && orderId.isNotEmpty)
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _firestore.collection('orders').doc(orderId).snapshots(),
                builder: (context, snapshot) {
                  final rawStatus = snapshot.data?.data()?['status']?.toString() ?? 'placed';
                  final normalizedStatus = OrderStatusUtils.normalizeStatus(rawStatus);
                  _applyFilterIfNeeded(normalizedStatus);
                  return _buildOrderStatusTag(normalizedStatus);
                },
              )
            else
              _buildTableStatusTag(table.status),
            const SizedBox(height: 4),
            if (!isMobile)
              Text("Cap: ${table.capacity}", style: TextStyle(color: Colors.grey[600], fontSize: 8))
            else
              Text("C:${table.capacity}", style: TextStyle(color: Colors.grey[600], fontSize: 8), textAlign: TextAlign.right),
            const Spacer(),
            const SizedBox(height: 4),
            _buildTableActionArea(table, isOccupied),
          ],
        ),
      ),
    );
  }

  void _applyFilterIfNeeded(String orderStatus) {}

  Widget _buildOrderStatusTag(String status) {
    // reuse admin visuals
    Color bgColor;
    Color fgColor;
    IconData icon;

    switch (status) {
      case 'placed':
        bgColor = Colors.yellow[100]!;
        fgColor = Colors.yellow[900]!;
        icon = Icons.shopping_cart;
        break;
      case 'prepared':
        bgColor = Colors.orange[100]!;
        fgColor = Colors.orange[900]!;
        icon = Icons.check_circle;
        break;
      case 'preparing':
        bgColor = Colors.orange[50]!;
        fgColor = Colors.orange[800]!;
        icon = Icons.local_fire_department;
        break;
      case 'served':
        bgColor = Colors.green[100]!;
        fgColor = Colors.green[900]!;
        icon = Icons.room_service;
        break;
      case 'closed':
        bgColor = Colors.grey[200]!;
        fgColor = Colors.grey[800]!;
        icon = Icons.done_all;
        break;
      case 'cancelled':
        bgColor = Colors.red[100]!;
        fgColor = Colors.red[900]!;
        icon = Icons.cancel;
        break;
      default:
        bgColor = Colors.grey[100]!;
        fgColor = Colors.grey[800]!;
        icon = Icons.help;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6), border: Border.all(color: fgColor.withOpacity(0.3), width: 0.8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, color: fgColor, size: 10), const SizedBox(width: 4), Text(status.toUpperCase(), style: TextStyle(color: fgColor, fontSize: 9, fontWeight: FontWeight.w700))],
      ),
    );
  }

  Widget _buildTableStatusTag(TableStatus status) {
    Color bgColor;
    Color fgColor;
    IconData icon;
    String text;

    switch (status) {
      case TableStatus.available:
        bgColor = Colors.green[100]!;
        fgColor = Colors.green[900]!;
        icon = Icons.check_circle_outline;
        text = 'AVAILABLE';
        break;
      case TableStatus.occupied:
        bgColor = Colors.orange[100]!;
        fgColor = Colors.orange[900]!;
        icon = Icons.people;
        text = 'OCCUPIED';
        break;
      case TableStatus.kotSent:
        bgColor = Colors.blue[100]!;
        fgColor = Colors.blue[900]!;
        icon = Icons.restaurant;
        text = 'KOT SENT';
        break;
      case TableStatus.billRequested:
        bgColor = Colors.red[100]!;
        fgColor = Colors.red[900]!;
        icon = Icons.receipt_long;
        text = 'BILL';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6), border: Border.all(color: fgColor.withOpacity(0.3), width: 0.8)),
      child: Row(children: [Icon(icon, color: fgColor, size: 10), const SizedBox(width: 4), Text(text, style: TextStyle(color: fgColor, fontSize: 9, fontWeight: FontWeight.w700))]),
    );
  }

  Widget _buildUltraCompactButton(String label, IconData icon, Color color, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0),
      child: SizedBox(
        width: double.infinity,
        height: 20,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 8),
          label: Text(label, style: const TextStyle(fontSize: 7, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: EdgeInsets.zero, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
        ),
      ),
    );
  }

  Widget _buildTableActionArea(TableModel table, bool isOccupied) {
    final orderId = table.currentOrderId;

    if (!isOccupied || orderId == null) {
      return _buildUltraCompactButton("ORDER", Icons.add_shopping_cart, Colors.green, () {
        showDialog(context: context, barrierDismissible: false, builder: (context) => CommonOrderDialog(table: table));
      });
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('orders').doc(orderId).snapshots(),
      builder: (context, snapshot) {
        final rawStatus = snapshot.data?.data()?['status']?.toString() ?? 'placed';
        final normalizedStatus = OrderStatusUtils.normalizeStatus(rawStatus);
        final actions = <Widget>[];

        if (normalizedStatus == 'placed') {
          actions.add(_buildUltraCompactButton("PREPARED", Icons.play_arrow, Colors.orange, () => _transitionOrderStatus(orderId: orderId, targetStatus: 'prepared')));
        } else if (normalizedStatus == 'preparing' || normalizedStatus == 'prepared') {
          actions.add(_buildUltraCompactButton("SERVE", Icons.room_service, Colors.blue, () => _transitionOrderStatus(orderId: orderId, targetStatus: 'served')));
        } else if (normalizedStatus == 'served') {
          actions.add(_buildUltraCompactButton("BILL", Icons.receipt_long, Colors.grey, () => _showBillPrintDialog(table)));
        }

        actions.add(_buildUltraCompactButton("ORDER", Icons.add_shopping_cart, Colors.green, () {
          showDialog(context: context, barrierDismissible: false, builder: (context) => CommonOrderDialog(table: table));
        }));

        if (normalizedStatus == 'served' || normalizedStatus == 'closed') {
          actions.add(_buildUltraCompactButton("CLR", Icons.cleaning_services, _brandMaroon, () => _showClearTableDialog(table)));
        }

        return Column(children: actions);
      },
    );
  }

  Future<void> _transitionOrderStatus({required String orderId, required String targetStatus}) async {
    try {
      final auth = context.read<AuthService>();
      final ok = await OrderStatusUtils.updateOrderStatus(orderId: orderId, targetStatus: targetStatus, role: auth.role.name, auth: auth);

      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid status transition."), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to update status: $e"), backgroundColor: Colors.red));
    }
  }

  void _showBillPrintDialog(TableModel table) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _brandMaroon.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.receipt_long, color: _brandMaroon),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Generate Bill - ${table.name}",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: const Text(
            "Click Print to generate the bill for this table.",
            style: TextStyle(fontSize: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _printTableBill(table);
            },
            icon: const Icon(Icons.print),
            label: const Text("Print"),
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandMaroon,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearTableDialog(TableModel table) {
    if (table.currentOrderId == null) {
      _processClearTable(table);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _brandMaroon.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.cleaning_services_outlined, color: _brandMaroon),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Clear Table ${table.name}",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber[300]!),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Would you like to print the final bill before clearing this table?",
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Table: ${table.name}",
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _processClearTable(table, printBill: false);
            },
            icon: const Icon(Icons.clear_all),
            label: const Text("Clear Only"),
            style: OutlinedButton.styleFrom(
              foregroundColor: _brandMaroon,
              side: const BorderSide(color: _brandMaroon),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _processClearTable(table, printBill: true);
            },
            icon: const Icon(Icons.print),
            label: const Text("Print & Clear"),
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandMaroon,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printTableBill(TableModel table) async {
    try {
      final orderId = table.currentOrderId;
      if (orderId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No active order found for this table.")),
          );
        }
        return;
      }

      final orderDoc = await _firestore.collection('orders').doc(orderId).get();
      if (!orderDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Order not found for this table.")),
          );
        }
        return;
      }

      final orderData = orderDoc.data() as Map<String, dynamic>;
      final orderStatus = OrderStatusUtils.normalizeStatus((orderData['status'] ?? 'placed').toString());
      if (orderStatus != 'served' && orderStatus != 'closed') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Order must be served before billing."), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      try {
        final receipt = await ReportService.ensureReceiptNumberForOrder(orderDoc.id);
        orderData['receiptNumber'] = receipt;
      } catch (e) {}
      await ReportService.printOrderReceipt(orderData, orderDoc.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Bill printed successfully.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to print bill: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _processClearTable(TableModel table, {bool printBill = false}) async {
    try {
      final orderId = table.currentOrderId;
      if (orderId != null) {
        final orderDoc = await _firestore.collection('orders').doc(orderId).get();
        if (orderDoc.exists) {
          final orderData = orderDoc.data() as Map<String, dynamic>;
          final currentStatus = OrderStatusUtils.normalizeStatus((orderData['status'] ?? 'placed').toString());

          if (currentStatus != 'served' && currentStatus != 'closed') {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Only served orders can be closed from cashier."),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return;
          }

            if (printBill) {
              try {
                final receipt = await ReportService.ensureReceiptNumberForOrder(orderDoc.id);
                orderData['receiptNumber'] = receipt;
              } catch (e) {}
              await ReportService.printOrderReceipt(orderData, orderDoc.id);
            }

          if (currentStatus == 'served') {
            final auth = context.read<AuthService>();
            final closed = await OrderStatusUtils.updateOrderStatus(
              orderId: orderId,
              targetStatus: 'closed',
              role: auth.role.name,
              auth: auth,
            );

            if (!closed) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Unable to close order due to invalid transition."), backgroundColor: Colors.red),
                );
              }
              return;
            }
          }

          await _firestore.collection('orders').doc(orderId).update({
            'clearedAt': FieldValue.serverTimestamp(),
            'clearedBy': 'cashier',
          });

          final kots = await _firestore.collection('kots').where('orderId', isEqualTo: orderId).get();
          for (final kot in kots.docs) {
            await kot.reference.update({
              'status': 'closed',
              'clearedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      }

      await _firestore.collection('tables').doc(table.id).update({
        'status': TableStatus.available.name,
        'currentOrderId': null,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${table.name} cleared successfully.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  int? _extractTableNumber(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    if (match == null) return null;
    return int.tryParse(match.group(0)!);
  }
}
