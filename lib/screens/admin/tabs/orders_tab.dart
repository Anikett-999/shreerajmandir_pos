import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../services/auth_service.dart';
import '../../../models/menu_item.dart';
import '../../../models/table_model.dart';
import '../../../providers/cart_provider.dart';
import '../../../services/report_service.dart';

class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key});

  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> {
  final _firestore = FirebaseFirestore.instance;
  DateTime filterDate = DateTime.now();
  String? filterStatus;

  @override
  Widget build(BuildContext context) {
    final startOfDay = DateTime(filterDate.year, filterDate.month, filterDate.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Order Oversight"),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: filterDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (date != null) setState(() => filterDate = date);
            },
          ),
          const SizedBox(width: 8),
          if (MediaQuery.of(context).size.width < 768)
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.blueGrey),
              onPressed: () => context.read<AuthService>().logout(),
              tooltip: "Logout",
            ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewOrderDialog(),
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text("New Order"),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('orders')
            .where('restaurantId', isEqualTo: context.read<AuthService>().restaurantId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(fontSize: 12)));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final startOfDay = DateTime(filterDate.year, filterDate.month, filterDate.day);
          final endOfDay = startOfDay.add(const Duration(days: 1));

          final orders = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['createdAt'] == null) return false;
            final createdAt = (data['createdAt'] as Timestamp).toDate();
            
            final matchesDate = createdAt.isAfter(startOfDay) && createdAt.isBefore(endOfDay);
            final matchesStatus = filterStatus == null || data['status'] == filterStatus;
            
            return matchesDate && matchesStatus;
          }).toList();

          if (orders.isEmpty) return const Center(child: Text("No orders found for this selection", style: TextStyle(color: Colors.grey)));

          // Sort by creation time descending
          orders.sort((a, b) {
            final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            return (bTime ?? Timestamp.now()).compareTo(aTime ?? Timestamp.now());
          });

          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;
              final date = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

              return Card(
                child: InkWell(
                  onTap: () => _showOrderDetails(doc.id, data),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: _getStatusColor(data['status']),
                          child: const Icon(Icons.receipt, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Order #${doc.id.substring(0, 6)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text("${data['tableName']} • ${data['waiterName']}", style: TextStyle(fontSize: 12, color: Colors.grey[700]), overflow: TextOverflow.ellipsis),
                              Text(DateFormat('hh:mm a').format(date), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text("₹${data['totalAmount']}", 
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF800000))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: _getStatusColor(data['status']).withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                              child: Text(data['status'].toString().toUpperCase(), style: TextStyle(fontSize: 9, color: _getStatusColor(data['status']), fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(width: 4),
                        // Actions — compact icon buttons
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 20),
                            onSelected: (value) {
                              if (value == 'print') ReportService.printOrderReceipt(data, doc.id);
                              else if (value == 'cancel') _confirmCancelOrder(doc.id, data);
                              else if (value == 'delete') _confirmDeleteOrder(doc.id);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'print', child: Row(children: [Icon(Icons.print, color: Colors.blue, size: 18), SizedBox(width: 8), Text("Print Bill")])),
                              const PopupMenuItem(value: 'cancel', child: Row(children: [Icon(Icons.block, color: Colors.orange, size: 18), SizedBox(width: 8), Text("Cancel Order")])),
                              const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, color: Colors.red, size: 18), SizedBox(width: 8), Text("Delete")])),
                            ],
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
      ),
    );
  }

  void _confirmCancelOrder(String orderId, Map<String, dynamic> data) {
    if (data['status'] == 'cancelled' || data['status'] == 'billed') {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Order is already finalized/cancelled!")));
       return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancel Order?"),
        content: const Text("This will mark the order as CANCELLED and free up the table. The record will be kept for history."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("No")),
          ElevatedButton(
            onPressed: () async {
              await _firestore.collection('orders').doc(orderId).update({'status': 'cancelled'});
              if (data['tableId'] != null) {
                await _firestore.collection('tables').doc(data['tableId']).update({
                  'status': 'available',
                  'currentOrderId': null,
                });
              }
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Order cancelled and table freed!"), backgroundColor: Colors.orange));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text("CANCEL ORDER"),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteOrder(String orderId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Order?"),
        content: const Text("This will permanently remove the order record from Firestore. This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              await _firestore.collection('orders').doc(orderId).delete();
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Order deleted!"), backgroundColor: Colors.red));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("DELETE"),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'billed': return Colors.green;
      case 'open': return Colors.blue;
      case 'kotSent': return Colors.orange;
      case 'cancelled': return Colors.grey;
      default: return Colors.grey;
    }
  }

  void _showOrderDetails(String orderId, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Expanded(
              child: Text("Order Detail #${orderId.substring(0,6)}", 
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
            ),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ],
        ),
        content: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9),
          width: 500, // Still acts as a 'preferred' width on large screens
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Status: ${data['status'].toString().toUpperCase()}", style: TextStyle(fontWeight: FontWeight.bold, color: _getStatusColor(data['status']))),
              const Divider(),
              ...(data['items'] as List).map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text("${item['quantity']}x ${item['name']}", 
                        overflow: TextOverflow.ellipsis, maxLines: 1),
                    ),
                    const SizedBox(width: 12),
                    Text("₹${(item['price'] ?? 0) * (item['quantity'] ?? 1)}", 
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  ],
                ),
              )),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Total Amount", style: TextStyle(fontWeight: FontWeight.bold)),
                  Text("₹${data['totalAmount']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => ReportService.printOrderReceipt(data, orderId),
                  icon: const Icon(Icons.print),
                  label: const Text("PRINT RECEIPT"),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
                ),
              ),
              const SizedBox(height: 12),
              if (data['status'] == 'open' || data['status'] == 'billed')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                    onPressed: () => _confirmCancel(orderId),
                    child: const Text("CANCEL ORDER & VOID BILL"),
                  ),
                ),
              if (data['status'] == 'cancelled' || data['status'] == 'billed')
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _reopenOrder(orderId),
                      child: const Text("REOPEN ORDER"),
                    ),
                  ),
                )
            ],
          ),
        ),
        ),
      ),
    );
  }

  void _confirmCancel(String id) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Cancel Order?"),
      content: const Text("This action will mark the bill as void and restore table availability if occupied. Proceed?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Back")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () {
            _firestore.collection('orders').doc(id).update({'status': 'cancelled'});
            Navigator.pop(ctx);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Order Cancelled"), backgroundColor: Colors.red));
          }, 
          child: const Text("Confirm Cancellation", style: TextStyle(color: Colors.white))
        ),
      ],
    ));
  }

  void _reopenOrder(String id) async {
    await _firestore.collection('orders').doc(id).update({'status': 'open'});
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Order Reopened"), backgroundColor: Colors.orange));
    }
  }

  void _showNewOrderDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AdminOrderDialog(restaurantId: context.read<AuthService>().restaurantId),
    );
  }
}

class AdminOrderDialog extends StatefulWidget {
  final String? restaurantId;
  const AdminOrderDialog({super.key, this.restaurantId});

  @override
  State<AdminOrderDialog> createState() => _AdminOrderDialogState();
}

class _AdminOrderDialogState extends State<AdminOrderDialog> {
  TableModel? _selectedTable;
  String _selectedCategory = "All";
  String _searchQuery = "";
  final List<CartItem> _selectedItems = [];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Place New Order", style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(),
            Expanded(
              child: _selectedTable == null 
                ? _buildTableSelection()
                : _buildOrderingView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableSelection() {
    return SizedBox(
      height: 450,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('tables')
            .where('restaurantId', isEqualTo: widget.restaurantId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final tables = snapshot.data!.docs;
          return LayoutBuilder(
            builder: (context, constraints) {
              final gridWidth = constraints.maxWidth;
              // Responsive columns: 3 on mobile-sized containers, 5+ on desktop
              final crossAxis = gridWidth < 400 ? 3 : (gridWidth < 600 ? 4 : 5);
              
              return GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxis, 
                  crossAxisSpacing: 10, 
                  mainAxisSpacing: 10,
                  childAspectRatio: gridWidth < 400 ? 0.75 : 1.1, // Even taller on small screens
                ),
                itemCount: tables.length,
                itemBuilder: (context, index) {
                  final table = TableModel.fromMap(tables[index].id, tables[index].data() as Map<String, dynamic>);
                  final isSelected = _selectedTable?.id == table.id;
                  final isOccupied = table.status != TableStatus.available;

                  return InkWell(
                    onTap: isOccupied ? null : () => setState(() {
                      _selectedTable = table;
                    }),
                    child: Card(
                      elevation: isSelected ? 4 : 1,
                      margin: EdgeInsets.zero, // Remove any default margin
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: isSelected ? Colors.blue : Colors.transparent, width: 2),
                      ),
                      color: isOccupied ? Colors.grey[100] : (isSelected ? Colors.blue[50] : Colors.white),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min, // Tell Column to take minimum space
                        children: [
                          Icon(Icons.table_bar, color: isOccupied ? Colors.grey[400] : (isSelected ? Colors.blue : Colors.black87), size: 24),
                          const SizedBox(height: 4),
                          Flexible(child: Text(table.name, 
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            overflow: TextOverflow.ellipsis)),
                          Flexible(child: Text(isOccupied ? "Occupied" : "Available", 
                            style: TextStyle(fontSize: 9, color: isOccupied ? Colors.red : Colors.green, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildOrderingView() {
    return Column(
      children: [
        // Header with Table Info and Back
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              const Icon(Icons.table_bar, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Table: ${_selectedTable?.name}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                    Text("Capacity: ${_selectedTable?.capacity}", style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _selectedTable = null),
                icon: const Icon(Icons.swap_horiz, size: 20, color: Colors.blue),
                tooltip: "Change Table",
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(child: _buildSearchAndAdd()),
      ],
    );
  }

  Widget _buildSearchAndAdd() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 650;
        
        final menuPanel = Column(
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: "Search items...",
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('menu_items')
                    .where('restaurantId', isEqualTo: widget.restaurantId)
                    .where('isAvailable', isEqualTo: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final items = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return _searchQuery.isEmpty || data['name'].toString().toLowerCase().contains(_searchQuery);
                  }).toList();

                  if (items.isEmpty) return const Center(child: Text("No items found", style: TextStyle(color: Colors.grey)));

                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isMobile ? 3 : 4,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.7,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final itemDoc = items[index];
                      final data = itemDoc.data() as Map<String, dynamic>;
                      final item = MenuItem.fromMap(itemDoc.id, data);
                      return InkWell(
                        onTap: () => setState(() {
                          final existing = _selectedItems.indexWhere((i) => i.item.id == item.id);
                          if (existing >= 0) _selectedItems[existing].quantity++;
                          else _selectedItems.add(CartItem(item: item));
                        }),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                                  child: data['imageUrl'] != null 
                                    ? Image.network(data['imageUrl'], fit: BoxFit.cover)
                                    : Container(color: Colors.grey[50], child: const Icon(Icons.fastfood, size: 20, color: Colors.grey)),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text("₹${item.price}", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 8)),
                                  ],
                                ),
                              ),
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

        final cartPanel = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Order", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (_selectedItems.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _selectedItems.clear()),
                    child: const Text("Clear", style: TextStyle(color: Colors.red, fontSize: 11)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _selectedItems.isEmpty 
                ? const Center(child: Text("Cart is empty", style: TextStyle(color: Colors.grey, fontSize: 12)))
                : ListView.separated(
                    itemCount: _selectedItems.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final i = _selectedItems[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(i.item.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                        subtitle: Text("₹${i.item.price} x ${i.quantity}", style: const TextStyle(fontSize: 10)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, size: 16, color: Colors.grey),
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                              onPressed: () => setState(() {
                                if (_selectedItems[index].quantity > 1) _selectedItems[index].quantity--;
                                else _selectedItems.removeAt(index);
                              }),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, size: 16, color: Colors.blue),
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                              onPressed: () => setState(() => _selectedItems[index].quantity++),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            ),
            const Divider(thickness: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Total:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                Text("₹${_selectedItems.fold<double>(0, (sum, i) => sum + (i.item.price * i.quantity)).toStringAsFixed(0)}", 
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedItems.isEmpty ? null : _submitOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text("PLACE ORDER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ],
        );

        if (isMobile) {
          return Column(
            children: [
              Expanded(flex: 3, child: menuPanel),
              const Divider(height: 24),
              Expanded(flex: 2, child: cartPanel),
            ],
          );
        }

        return Row(
          children: [
            Expanded(flex: 3, child: menuPanel),
            const VerticalDivider(width: 24),
            SizedBox(width: 280, child: cartPanel),
          ],
        );
      },
    );
  }

  void _submitOrder() async {
     final auth = context.read<AuthService>();
    final adminName = auth.role == UserRole.admin ? "Admin (${auth.currentUser?.email ?? 'Unknown'})" : "Admin";
     final total = _selectedItems.fold<double>(0, (sum, i) => sum + (i.item.price * i.quantity));

     final firestore = FirebaseFirestore.instance;
     final batch = firestore.batch();
     final orderRef = firestore.collection('orders').doc();
     
     batch.set(orderRef, {
        'restaurantId': widget.restaurantId,
        'tableId': _selectedTable!.id,
        'tableName': _selectedTable!.name,
        'waiterName': adminName,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
        'totalAmount': total,
        // Also keep a summary of items in the main doc for quick listing
        'items': _selectedItems.map((i) => {
           'id': i.item.id,
           'name': i.item.name,
           'price': i.item.price,
           'quantity': i.quantity,
           'category': i.item.category,
        }).toList(),
     });

     // Add items to subcollection for consistency with waiter flow
     final itemsRef = orderRef.collection('items');
     for (var i in _selectedItems) {
        batch.set(itemsRef.doc(), {
           'restaurantId': widget.restaurantId,
           'menuItemId': i.item.id,
           'name': i.item.name,
           'price': i.item.price,
           'quantity': i.quantity,
           'totalPrice': i.item.price * i.quantity,
           'category': i.item.category,
           'status': 'Pending',
           'createdAt': FieldValue.serverTimestamp(),
        });
     }

     final kotRef = firestore.collection('kots').doc();
     batch.set(kotRef, {
        'restaurantId': widget.restaurantId,
        'orderId': orderRef.id,
        'tableName': _selectedTable!.name,
        'status': 'Pending',
        'createdAt': FieldValue.serverTimestamp(),
        'items': _selectedItems.map((i) => {
           'name': i.item.name,
           'quantity': i.quantity,
        }).toList(),
     });

     final tableRef = firestore.collection('tables').doc(_selectedTable!.id);
     batch.update(tableRef, {
        'status': TableStatus.occupied.name,
        'currentOrderId': orderRef.id,
     });

     await batch.commit();

     // Prepare simple KOT data (only Table and Items) for printing
     final kotData = {
        'tableName': _selectedTable!.name,
        'items': _selectedItems.map((i) => {
           'name': i.item.name,
           'quantity': i.quantity,
           'price': i.item.price,
        }).toList(),
     };
     
     // Trigger Auto-Print
     await ReportService.printKOTReceipt(kotData, orderRef.id);

     if (mounted) {
       Navigator.pop(context);
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Order placed! KOT printed."), backgroundColor: Colors.green));
     }
  }
}
