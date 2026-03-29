import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../models/table_model.dart';
import '../../../services/report_service.dart';
import '../../../services/auth_service.dart';
import '../../../widgets/order_dialog.dart';

class TablesTab extends StatefulWidget {
  const TablesTab({super.key});

  @override
  State<TablesTab> createState() => _TablesTabState();
}

class _TablesTabState extends State<TablesTab> {
  final _firestore = FirebaseFirestore.instance;
  static const Color _brandMaroon = Color(0xFF8C1026);
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
        final tables = allTables.where((doc) {
          if (_selectedFilter == 'all') return true;

          final table = TableModel.fromMap(doc.id, doc.data() as Map<String, dynamic>);
          final isOccupied =
              table.status == TableStatus.occupied ||
              table.status == TableStatus.kotSent ||
              table.status == TableStatus.billRequested;

          if (_selectedFilter == 'occupied') return isOccupied;
          if (_selectedFilter == 'available') return table.status == TableStatus.available;
          return true;
        }).toList();

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

        return Column(
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
                           DropdownMenuItem(value: 'available', child: Text('Available')),
                           DropdownMenuItem(value: 'occupied', child: Text('Occupied')),
                         ],
                         onChanged: (value) {
                           if (value == null) return;
                           setState(() => _selectedFilter = value);
                         },
                       ),
                     ),
                   ),
                   ElevatedButton.icon(
                     onPressed: () => _showTableDialog(restaurantId: restaurantId),
                     icon: const Icon(Icons.add, size: 16),
                     label: const Text("Create Table", style: TextStyle(fontSize: 12)),
                     style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                     ),
                   ),
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
                      childAspectRatio: isMobile ? 0.92 : 1.0,
                    ),
                    itemCount: tables.length,
                    itemBuilder: (context, index) {
                      final table = TableModel.fromMap(tables[index].id, tables[index].data() as Map<String, dynamic>);
                      final isOccupied = table.status == TableStatus.occupied || table.status == TableStatus.kotSent || table.status == TableStatus.billRequested;
                      
                      return Container(
                        decoration: BoxDecoration(
                          color: isOccupied ? Colors.grey[100] : Colors.green[50]?.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isOccupied ? Colors.grey[400]! : Colors.green[200]!, width: 0.8),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(child: Text(table.name, style: TextStyle(fontSize: isMobile ? 12 : 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(icon: const Icon(Icons.edit, size: 10), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _showTableDialog(table: table, restaurantId: restaurantId)),
                                      const SizedBox(width: 2),
                                      IconButton(
                                        icon: const Icon(Icons.delete, size: 10, color: Colors.red),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () => _deleteTableById(table.id),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              _buildUltraMiniStatus(table.status),
                              const SizedBox(height: 4),
                              if (!isMobile) ...[
                                Text("Cap: ${table.capacity}", style: TextStyle(color: Colors.grey[600], fontSize: 8)),
                                const Spacer(),
                              ] else ...[
                                const Spacer(),
                                Text("C:${table.capacity}", style: TextStyle(color: Colors.grey[600], fontSize: 8), textAlign: TextAlign.right),
                              ],
                              
                              const SizedBox(height: 2),
                              if (isOccupied && table.status != TableStatus.billRequested)
                                _buildUltraCompactButton("BILL", Icons.receipt_long, Colors.grey, () => _showBillPrintDialog(table)),
                              
                              _buildUltraCompactButton("ORDER", Icons.add_shopping_cart, Colors.green, () {
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) => CommonOrderDialog(table: table),
                                );
                              }),

                              if (isOccupied)
                                _buildUltraCompactButton("CLR", Icons.cleaning_services, _brandMaroon, () => _showClearTableDialog(table)),
                            ],
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
      },
    );
  }

  Widget _buildUltraCompactButton(String label, IconData icon, Color color, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3.0),
      child: SizedBox(
        width: double.infinity,
        height: 22,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 8),
          label: Text(label, style: const TextStyle(fontSize: 7, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
      ),
    );
  }

  Widget _buildUltraMiniStatus(TableStatus status) {
    Color color = Colors.green;
    String text = "AV";
    IconData icon = Icons.check_circle_outline;

    if (status == TableStatus.occupied) {
      color = Colors.orange;
      text = "OCC";
      icon = Icons.people;
    } else if (status == TableStatus.kotSent) {
      color = Colors.blue;
      text = "KOT";
      icon = Icons.restaurant;
    } else if (status == TableStatus.billRequested) {
      color = Colors.red;
      text = "BILL";
      icon = Icons.receipt_long;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: color, width: 0.5)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 8),
          const SizedBox(width: 2),
          Text(text, style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.bold)),
        ],
      ),
    );
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
      await ReportService.printOrderReceipt(orderData, orderDoc.id);

      await _firestore.collection('tables').doc(table.id).update({'status': 'billRequested'});
      await _firestore.collection('orders').doc(orderId).update({'status': 'bill_requested'});

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

  Future<void> _deleteTableById(String tableId) async {
    try {
      await _firestore.collection('tables').doc(tableId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Table deleted successfully.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to delete table: $e"), backgroundColor: Colors.red),
        );
      }
    }
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

  void _processClearTable(TableModel table, {bool printBill = false}) async {
    try {
      String? orderId = table.currentOrderId;
      if (orderId != null) {
        final orderDoc = await _firestore.collection('orders').doc(orderId).get();
        if (orderDoc.exists) {
          final orderData = orderDoc.data() as Map<String, dynamic>;
          if (printBill) await ReportService.printOrderReceipt(orderData, orderDoc.id);
          await _firestore.collection('orders').doc(orderId).update({
            'status': 'billed',
            'clearedAt': FieldValue.serverTimestamp(),
            'clearedBy': 'admin',
          });
          final kots = await _firestore.collection('kots').where('orderId', isEqualTo: orderId).get();
          for (final kot in kots.docs) {
            await kot.reference.update({'status': 'Served', 'clearedAt': FieldValue.serverTimestamp()});
          }
        }
      }
      await _firestore.collection('tables').doc(table.id).update({'status': TableStatus.available.name, 'currentOrderId': null});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  void _showTableDialog({TableModel? table, String? restaurantId}) {
    final nameCtrl = TextEditingController(text: table?.name);
    final capCtrl = TextEditingController(text: table?.capacity.toString() ?? '4');

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
              child: Icon(
                table == null ? Icons.add_circle_outline : Icons.edit_outlined,
                color: _brandMaroon,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                table == null ? "Create New Table" : "Edit Table",
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: "Table Number/Name",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _brandMaroon),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: capCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Capacity",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _brandMaroon),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          if (table != null)
            TextButton(
              onPressed: () async {
                await _deleteTableById(table.id);
                if (mounted) Navigator.pop(context);
              },
              child: const Text("Delete", style: TextStyle(color: Colors.red)),
            ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty) return;

              final data = {
                'name': nameCtrl.text.trim(),
                'capacity': int.tryParse(capCtrl.text) ?? 4,
                'status': table?.status.name ?? TableStatus.available.name,
                'restaurantId': restaurantId,
              };

              try {
                if (table == null) {
                  await _firestore.collection('tables').add(data);
                } else {
                  await _firestore.collection('tables').doc(table.id).update(data);
                }

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(table == null ? "Table created successfully." : "Table updated successfully.")),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Failed to save table: $e"), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  int? _extractTableNumber(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    if (match == null) return null;
    return int.tryParse(match.group(0)!);
  }
}
