import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../services/debug_logger.dart';
import '../auth/unauthorized_screen.dart';
import '../../models/table_model.dart';
import '../../services/report_service.dart';
import '../../models/menu_item.dart';
import '../../providers/cart_provider.dart';
import '../../utils/debouncer.dart';
import '../../utils/order_status_utils.dart';
import '../../utils/table_state_sync.dart';
import '../../widgets/order_dialog.dart';

class CashierDashboard extends StatefulWidget {
  const CashierDashboard({super.key});

  @override
  State<CashierDashboard> createState() => _CashierDashboardState();
}

class _CashierDashboardState extends State<CashierDashboard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _selectedTableId;
  Map<String, dynamic>? _selectedOrderData;
  bool _hasCreatedTempTable = false; // Requirement 4.6

  // Provide a convenient auth getter to avoid forward-reference issues
  AuthService get auth => context.read<AuthService>();


  @override
  Widget build(BuildContext context) {
    final restaurantId = auth.restaurantId;
    if (auth.role == UserRole.kitchen) {
      return const UnauthorizedScreen();
    }
    final restaurantName = auth.restaurantName ?? "ShreeRajmandir";
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(restaurantName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(width: 8),
            StreamBuilder<void>(
              stream: FirebaseFirestore.instance.snapshotsInSync(),
              builder: (context, _) => FutureBuilder<QuerySnapshot>(
                future: FirebaseFirestore.instance.collection('tables')
                    .where('restaurantId', isEqualTo: restaurantId)
                    .limit(1).get(const GetOptions(source: Source.server)),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
                  if (snapshot.hasError) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.red[100], borderRadius: BorderRadius.circular(4)),
                      child: const Text("OFFLINE", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
        actions: isMobile
          ? [
               IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(() {}), tooltip: "Refresh Data"),
            ]
          : [
              IconButton(icon: const Icon(Icons.receipt_long), onPressed: () => _showOrderOversightDialog(), tooltip: "Recent Bills / Reprint"),
              IconButton(icon: const Icon(Icons.history), onPressed: () => _showSessionHistory(), tooltip: "Session History"),
              IconButton(icon: const Icon(Icons.settings), onPressed: () => _showManagementMenu(), tooltip: "Menu/Table Setup"),
              IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(() {}), tooltip: "Refresh Data"),
              const SizedBox(width: 8),
                    IconButton(icon: const Icon(Icons.logout), onPressed: () => auth.logout(), tooltip: "Logout"),
              const SizedBox(width: 16),
            ],
      ),
      drawer: isMobile ? Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: const Color(0xFF800000)),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.point_of_sale, size: 48, color: Colors.white),
                    const SizedBox(height: 10),
                    Text(restaurantName.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                    const Text("CASHIER PANEL", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Recent Bills'),
              onTap: () {
                Navigator.pop(context);
                _showOrderOversightDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Session History'),
              onTap: () {
                Navigator.pop(context);
                _showSessionHistory();
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Menu/Table Setup'),
              onTap: () {
                Navigator.pop(context);
                _showManagementMenu();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: () => auth.logout(),
            ),
          ],
        ),
      ) : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 800;

          // Sub-header stats bar (shown in all layouts)
          final statsBar = Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildCollectionCounter(),
            ),
          );

          if (isWide) {
            // Wide/Desktop: side-by-side layout
            return Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      statsBar,
                      _buildMidnightResetBanner(restaurantId),
                      Expanded(child: _buildTableGrid(restaurantId)),
                    ],
                  ),
                ),
                Container(
                  width: 400,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(left: BorderSide(color: Colors.grey[200]!)),
                  ),
                  child: _buildLiveKotFeed(restaurantId),
                ),
              ],
            );
          } else {
            // Mobile: Tab layout
            return DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  statsBar,
                  _buildMidnightResetBanner(restaurantId),
                  Container(
                    color: Colors.white,
                    child: TabBar(
                      labelColor: const Color(0xFF800000),
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: const Color(0xFF800000),
                      tabs: const [
                        Tab(icon: Icon(Icons.table_bar), text: "Tables"),
                        Tab(icon: Icon(Icons.kitchen), text: "KOT Feed"),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildTableGrid(restaurantId),
                        _buildLiveKotFeed(restaurantId),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildCollectionCounter() {
    final restaurantId = auth.restaurantId;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final docId = "${restaurantId}_$today";
    
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('daily_collections').doc(docId).snapshots(),
      builder: (context, snapshot) {
        double net = 0;
        double gross = 0;
        double refunds = 0;
        int bills = 0;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          net = (data['netCollection'] ?? 0).toDouble();
          gross = (data['grossCollection'] ?? 0).toDouble();
          refunds = (data['refundTotal'] ?? 0).toDouble();
          bills = data['billCount'] ?? 0;
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatChip("Net: ₹${net.toStringAsFixed(0)}", Colors.green),
              _buildStatChip("Gross: ₹${gross.toStringAsFixed(0)}", Colors.blue),
              _buildStatChip("Refunds: ₹${refunds.toStringAsFixed(0)}", Colors.red),
              _buildStatChip("Bills: $bills", Colors.orange),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatChip(String label, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTableGrid(String? restaurantId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('tables')
          .where('restaurantId', isEqualTo: restaurantId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final tables = snapshot.data!.docs.map((doc) => TableModel.fromMap(doc.id, doc.data() as Map<String, dynamic>)).toList();
        
        return LayoutBuilder(
          builder: (context, constraints) {
            final gridWidth = constraints.maxWidth;
            final isMobile = gridWidth < 600;
            // REQ: 4 cards on mobile
            final crossAxis = isMobile ? 4 : (gridWidth < 900 ? 5 : 8);
            final spacing = isMobile ? 6.0 : 12.0;
            final aspectRatio = isMobile ? 0.68 : 1.0;

            return GridView.builder(
              padding: EdgeInsets.all(isMobile ? 8 : 24),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxis,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: aspectRatio,
              ),
              itemCount: tables.length,
              itemBuilder: (context, index) {
                return _buildTableCard(tables[index]);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTableCard(TableModel table) {
    final isOccupied = table.status != TableStatus.available;
    final gridWidth = MediaQuery.of(context).size.width;
    final isMobile = gridWidth < 600;

    return Container(
      decoration: BoxDecoration(
        color: isOccupied ? Colors.orange[50] : Colors.green[50]?.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isOccupied ? Colors.orange[200]! : Colors.green[200]!, width: 0.8),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: InkWell(
          onTap: () {
          DebugLogger.logEvent(
            event: 'table_selected',
            data: {
              'userRole': auth.role.name,
              'userId': auth.currentUser?.uid,
              'tableId': table.id,
              'orderId': table.currentOrderId,
              'lockedBy': null,
              'previousState': table.status.name,
              'newState': table.status.name,
            },
          );

          if (table.currentOrderId != null) {
            _showOrderDetailPanel(table);
          } else {
             showDialog(
               context: context,
               barrierDismissible: false,
               builder: (context) => CommonOrderDialog(table: table),
             );
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: 100, // Fixed width for scaling reference
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(table.name, 
                    style: TextStyle(fontSize: isMobile ? 12 : 14, fontWeight: FontWeight.bold), 
                    overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 1),
                  _buildUltraMiniStatus(table.status),
                  const SizedBox(height: 1),
                  if (!isMobile) ...[
                    Text("Cap: ${table.capacity}", style: TextStyle(color: Colors.grey[600], fontSize: 8)),
                    const SizedBox(height: 4),
                  ] else ...[
                    Text("C:${table.capacity}", style: TextStyle(color: Colors.grey[600], fontSize: 7), textAlign: TextAlign.right),
                  ],
                  
                  const SizedBox(height: 1),
                  if (isOccupied && table.status != TableStatus.billRequested)
                      _buildUltraCompactButton("BILL", Icons.receipt_long, Colors.red, () async {
                       final orderSnapshot = table.currentOrderId != null
                           ? await _firestore.collection('orders').doc(table.currentOrderId).get()
                           : null;
                       final previousState = orderSnapshot != null && orderSnapshot.exists
                           ? ((orderSnapshot.data() as Map<String, dynamic>)['status'] ?? 'unknown').toString()
                           : null;

                       final batch = _firestore.batch();
                       if (table.currentOrderId != null) {
                         final orderRef = _firestore.collection('orders').doc(table.currentOrderId);
                         batch.update(orderRef, {'status': 'bill_requested'});
                       }
                       await TableStateSync.syncTableForOrderChange(
                         firestore: _firestore,
                         tableId: table.id,
                         orderId: table.currentOrderId ?? '',
                         orderState: 'bill_requested',
                         auth: auth,
                         batch: batch,
                       );
                       await batch.commit();

                       DebugLogger.logEvent(
                         event: 'bill_requested',
                         data: {
                           'userRole': auth.role.name,
                           'userId': auth.currentUser?.uid,
                           'tableId': table.id,
                           'orderId': table.currentOrderId,
                           'lockedBy': null,
                           'previousState': previousState,
                           'newState': 'bill_requested',
                         },
                       );
                    }),
                  
                  _buildUltraCompactButton(isOccupied ? "KOT" : "ORDER", isOccupied ? Icons.restaurant_menu : Icons.add_shopping_cart, isOccupied ? Colors.orange : const Color(0xFF800000), () {
                    if (isOccupied && table.currentOrderId != null) {
                      _showOrderDetailPanel(table);
                    } else {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => CommonOrderDialog(table: table),
                      );
                    }
                  }),
    
                  if (isOccupied)
                    _buildUltraCompactButton("CLR", Icons.cleaning_services, Colors.grey, () => _confirmClearTable(table)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditTableDialog(TableModel table) {
     // Generic implementation
     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Edit Table functionality coming soon!")));
  }

  void _confirmDeleteTable(TableModel table) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Table?"),
        content: Text("Are you sure you want to delete ${table.name}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              await _firestore.collection('tables').doc(table.id).delete();
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("DELETE"),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveKotFeed(String? restaurantId) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blueGrey[900],
          child: const Row(
            children: [
              Icon(Icons.kitchen, color: Colors.white),
              SizedBox(width: 12),
              Text("LIVE KOT FEED", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('kots')
                .where('restaurantId', isEqualTo: restaurantId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text("No active KOTs", style: TextStyle(color: Colors.grey)));
              }
              
              // Filter and Sort in memory to avoid needing a complex composite index
              final kots = snapshot.data!.docs.where((doc) {
                final status = (doc.data() as Map<String, dynamic>)['status'] ?? 'Pending';
                return status != 'Served';
              }).toList();

              // Sort by createdAt descending
              kots.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                final aTime = aData['createdAt'] as Timestamp?;
                final bTime = bData['createdAt'] as Timestamp?;
                
                if (aTime == null && bTime == null) return 0;
                if (aTime == null) return 1;
                if (bTime == null) return -1;
                return bTime.compareTo(aTime);
              });

              if (kots.isEmpty) {
                return const Center(child: Text("No active KOTs", style: TextStyle(color: Colors.grey)));
              }
              
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: kots.length,
                itemBuilder: (context, index) {
                  final kot = kots[index];
                  final data = kot.data() as Map<String, dynamic>;
                  return _buildKotCard(kot.id, data);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildKotCard(String id, Map<String, dynamic> data) {
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final timeStr = DateFormat('hh:mm a').format(createdAt);
    final status = data['status'] ?? 'Pending';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: status == 'Preparing' ? Colors.orange[50] : Colors.blue[50],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("TABLE: ${data['tableName']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(timeStr, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...(data['items'] as List).map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text("• ${item['name']} x ${item['quantity']}", style: const TextStyle(fontSize: 14)),
                )),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text("By: ${data['waiterName']}", style: TextStyle(color: Colors.grey[600], fontSize: 11, fontStyle: FontStyle.italic), overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        String nextStatus = status;
                        if (status == 'Pending') nextStatus = 'Preparing';
                        else if (status == 'Preparing') nextStatus = 'Done';
                        
                        if (nextStatus != status) {
                          FirebaseFirestore.instance.collection('kots').doc(id).update({'status': nextStatus});
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: status == 'Pending' ? Colors.blue : (status == 'Preparing' ? Colors.orange : Colors.green),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(status.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMidnightResetBanner(String? restaurantId) {
    if (restaurantId == null) return const SizedBox();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final docId = "${restaurantId}_$today";
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('daily_collections').doc(docId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.exists) return const SizedBox();
        return Container(
          width: double.infinity,
          color: Colors.orange[100],
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.warning, color: Colors.orange),
              const SizedBox(width: 12),
              const Expanded(child: Text("New day detected. Please refresh to start a new collection session.")),
              TextButton(onPressed: () => setState(() {}), child: const Text("REFRESH")),
            ],
          ),
        );
      },
    );
  }

  void _showSessionHistory() {
    final restaurantId = auth.restaurantId;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Daily Collection History"),
        content: SizedBox(
          width: 500,
          height: 400,
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('daily_collections')
                .where('restaurantId', isEqualTo: restaurantId)
                .orderBy('lastUpdatedAt', descending: true)
                .limit(30).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              if (snapshot.data!.docs.isEmpty) return const Center(child: Text("No history available"));

              return ListView.builder(
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  final doc = snapshot.data!.docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return ListTile(
                    title: Text("Date: ${doc.id}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("Bills: ${data['billCount'] ?? 0} | Gross: ₹${(data['grossCollection'] ?? 0).toStringAsFixed(2)}"),
                    trailing: Text("Net: ₹${(data['netCollection'] ?? 0).toStringAsFixed(2)}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  );
                },
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))],
      ),
    );
  }

  void _showManagementMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text("CASHIER MANAGEMENT", style: TextStyle(fontWeight: FontWeight.bold))),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.fastfood, color: Colors.blue),
            title: const Text("Add New Menu Item"),
            onTap: () {
              Navigator.pop(context);
              // I'll link to the Admin Menu Tab logic or a simple form
              _showAddMenuItemDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.table_bar, color: Colors.orange),
            title: const Text("Create Temporary Table"),
            enabled: !_hasCreatedTempTable,
            onTap: () {
              Navigator.pop(context);
              _showAddTableDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long, color: Colors.green),
            title: const Text("Order Oversight (History)"),
            onTap: () {
              Navigator.pop(context);
              _showOrderOversightDialog();
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showAddMenuItemDialog() {
     // Simplifying for Cashier: Minimal fields
     final nameCtrl = TextEditingController();
     final priceCtrl = TextEditingController();
     String? selectedCategory;

     showDialog(
       context: context,
       builder: (context) => AlertDialog(
         title: const Text("New Menu Item"),
         content: Column(
           mainAxisSize: MainAxisSize.min,
           children: [
             TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Item Name")),
             TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: "Price"), keyboardType: TextInputType.number),
             StreamBuilder<QuerySnapshot>(
                 stream: _firestore.collection('categories')
                   .where('restaurantId', isEqualTo: auth.restaurantId)
                   .snapshots(),
               builder: (context, snap) {
                 if (!snap.hasData) return const SizedBox();
                 return DropdownButtonFormField<String>(
                   hint: const Text("Select Category"),
                   items: snap.data!.docs.map((d) => DropdownMenuItem(value: d['name'].toString(), child: Text(d['name']))).toList(),
                   onChanged: (v) => selectedCategory = v,
                 );
               },
             ),
           ],
         ),
         actions: [
           TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
           ElevatedButton(
             onPressed: () async {
               if (nameCtrl.text.isNotEmpty && priceCtrl.text.isNotEmpty && selectedCategory != null) {
                  await _firestore.collection('items').add({
                    'name': nameCtrl.text.trim(),
                    'price': double.tryParse(priceCtrl.text) ?? 0.0,
                    'category': selectedCategory,
                    'isAvailable': true,
                  });
                  if (mounted) Navigator.pop(context);
               }
             }, 
             child: const Text("Save")
           ),
         ],
       ),
     );
  }

  void _showAddTableDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Create Temp Table"),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Table Number/Name")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
                 if (nameCtrl.text.isNotEmpty) {
                 final docRef = await _firestore.collection('tables').add({
                   'name': nameCtrl.text.trim(),
                   'capacity': 4,
                   'restaurantId': auth.restaurantId,
                 });
                 // Ensure table state is applied via TableStateSync
                 await TableStateSync.syncTableForOrderChange(
                   firestore: _firestore,
                   tableId: docRef.id,
                   orderId: '',
                   orderState: 'billed', // maps to available
                   auth: auth,
                 );
                 setState(() => _hasCreatedTempTable = true);
                 if (mounted) Navigator.pop(context);
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  void _showOrderOversightDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Expanded(
              child: Text("Order Oversight", 
                style: TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showNewOrderDialog();
              },
              icon: const Icon(Icons.add_shopping_cart, size: 18),
              label: const Text("New Order", style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700], 
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 800,
          height: 600,
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('orders')
              .where('restaurantId', isEqualTo: auth.restaurantId)
                .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)))
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              if (snapshot.data!.docs.isEmpty) return const Center(child: Text("No orders found today"));

              return ListView.separated(
                itemCount: snapshot.data!.docs.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final doc = snapshot.data!.docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                  final normalizedStatus = OrderStatusUtils.normalizeOrderStatusForRead(
                    rawStatus: data['status'] ?? 'unknown',
                    auth: auth,
                    orderId: doc.id,
                    tableId: data['tableId']?.toString(),
                    source: 'cashier.order_oversight',
                  );

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: normalizedStatus == 'active' ? Colors.blue : (normalizedStatus == 'billed' ? Colors.green : Colors.grey),
                      child: const Icon(Icons.receipt, color: Colors.white, size: 20),
                    ),
                    title: Text(
                      "Bill #${data.containsKey('receiptNumber') ? data['receiptNumber'].toString().padLeft(6, '0') : doc.id.substring(0, 6).toUpperCase()} • Table: ${data['tableName'] ?? 'N/A'}", 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      "₹${data['totalAmount'] ?? 0} • ${DateFormat('hh:mm a').format(createdAt)} • ${normalizedStatus.toUpperCase()}",
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (normalizedStatus == 'billed')
                          IconButton(
                            icon: const Icon(Icons.print, color: Colors.blue),
                            onPressed: () => _reprintBill(doc.id, data),
                            tooltip: "Reprint Bill",
                          ),
                        if (normalizedStatus == 'active')
                          IconButton(
                            icon: const Icon(Icons.open_in_new, color: Colors.green),
                            onPressed: () async {
                              Navigator.pop(context);
                              // Find the table object to show its panel
                              final tableSnap = await _firestore.collection('tables').doc(data['tableId']).get();
                              if (tableSnap.exists) {
                                _showOrderDetailPanel(TableModel.fromMap(tableSnap.id, tableSnap.data()!));
                              }
                            },
                            tooltip: "View Details",
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))],
      ),
    );
  }

  void _reprintBill(String orderId, Map<String, dynamic> data) {
    String billNo = orderId.substring(0, 6).toUpperCase();
    if (data.containsKey('receiptNumber')) {
      billNo = data['receiptNumber'].toString().padLeft(6, '0');
      data['receiptNumber'] = data['receiptNumber']; // Ensure it's available in data for the template if needed
    }

    ReportService.printFinalBill(
      orderData: data,
      orderId: billNo,
      subtotal: (data['subtotal'] ?? 0.0).toDouble(),
      cgst: (data['cgst'] ?? 0.0).toDouble(),
      sgst: (data['sgst'] ?? 0.0).toDouble(),
      total: (data['grandTotal'] ?? 0.0).toDouble(),
      paymentMode: data['paymentMode'] ?? 'Cash',
    );
  }

  void _showNewOrderDialog() {
     showDialog(
       context: context,
       builder: (context) => AlertDialog(
         title: const Text("Start New Order"),
         content: const Text("To place a new order, please select an available (green) table from the dashboard grid."),
         actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
       ),
     );
  }

  void _showOrderDetailPanel(TableModel table) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return StreamBuilder<DocumentSnapshot>(
            stream: _firestore.collection('orders').doc(table.currentOrderId).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const Center(child: Text("Order not found"));
              }
              final orderData = snapshot.data!.data() as Map<String, dynamic>;
              final items = orderData['items'] as List;
              final total = orderData['totalAmount'] ?? 0.0;

              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("TABLE: ${table.name}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text("ADD ITEM"),
                              onPressed: () => _showAddItemDialog(table.currentOrderId!, orderData),
                            ),
                            const SizedBox(width: 8),
                            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _buildOrderItemRow(table.currentOrderId!, orderData, item, index);
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -5))],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Total Amount", style: TextStyle(fontSize: 18, color: Colors.grey)),
                            Text("₹${total.toStringAsFixed(2)}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                             Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.block, color: Colors.red),
                                label: const Text("CANCEL", style: TextStyle(color: Colors.red, fontSize: 12)),
                                onPressed: () => _confirmCancelOrder(table, orderData),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.cleaning_services, color: Colors.orange),
                                label: const Text("CLEAR", style: TextStyle(color: Colors.orange, fontSize: 12)),
                                onPressed: () => _confirmClearTable(table),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: () => _showBillingDialog(table, orderData),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: const Text("GENERATE BILL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildOrderItemRow(String orderId, Map<String, dynamic> orderData, Map<String, dynamic> item, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text("₹${item['price']} x ${item['quantity']}", style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          ),
          Text("₹${(item['price'] * item['quantity']).toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 16),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                onPressed: () => _updateItemQuantity(orderId, orderData, index, -1),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                onPressed: () => _updateItemQuantity(orderId, orderData, index, 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _updateItemQuantity(String orderId, Map<String, dynamic> orderData, int index, int change) async {
    
    final orderSnapshot = await _firestore.collection('orders').doc(orderId).get();
    final previousState = orderSnapshot.exists
        ? ((orderSnapshot.data() as Map<String, dynamic>)['status'] ?? 'unknown').toString()
        : null;
    if (previousState == 'bill_requested') {
      DebugLogger.logEvent(
        event: 'blocked_action_bill_requested',
        data: {
          'userRole': auth.role.name,
          'userId': auth.currentUser?.uid,
          'tableId': orderData['tableId'],
          'orderId': orderId,
          'lockedBy': null,
          'attemptedAction': change > 0 ? 'add_item' : 'update_quantity',
          'previousState': previousState,
          'newState': previousState,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order is locked for billing')),
        );
      }
      return;
    }

    final items = List<Map<String, dynamic>>.from(orderData['items']);
    final item = Map<String, dynamic>.from(items[index]);
    
    int newQty = (item['quantity'] ?? 0) + change;
    if (newQty <= 0) {
      items.removeAt(index);
    } else {
      item['quantity'] = newQty;
      items[index] = item;
    }

    double newTotal = items.fold(0, (sum, i) => sum + (i['price'] * i['quantity']));
    
    await _firestore.collection('orders').doc(orderId).update({
      'items': items,
      'totalAmount': newTotal,
    });

    if (change > 0) {
      DebugLogger.logEvent(
        event: 'items_added',
        data: {
          'userRole': auth.role.name,
          'userId': auth.currentUser?.uid,
          'tableId': orderData['tableId'],
          'orderId': orderId,
          'lockedBy': null,
          'previousState': previousState,
          'newState': previousState,
          'itemName': item['name'],
          'quantityDelta': change,
        },
      );

      // Logic from 4.3.2: "Any modification auto-generates a new KOT for the added items"
      final restaurantId = auth.restaurantId;
      final restaurantName = auth.restaurantName ?? "ShreeRajmandir";
      
      final kotData = {
        'tableName': orderData['tableName'],
        'items': [{
          'name': item['name'],
          'quantity': change,
          'price': item['price'],
        }],
      };
      await ReportService.printKOTReceipt(kotData, orderId);

      await _firestore.collection('kots').add({
        'tableId': orderData['tableId'],
        'tableName': orderData['tableName'],
        'orderId': orderId,
        'restaurantId': restaurantId,
        'items': [{
          'name': item['name'],
          'quantity': change,
        }],
        'waiterName': 'Cashier Overlay',
        'status': 'Pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      DebugLogger.logEvent(
        event: 'kot_sent',
        data: {
          'userRole': auth.role.name,
          'userId': auth.currentUser?.uid,
          'tableId': orderData['tableId'],
          'orderId': orderId,
          'lockedBy': null,
          'previousState': previousState,
          'newState': previousState,
          'orderProgress': 'kot_sent',
        },
      );
    }
  }

  void _confirmCancelOrder(TableModel table, Map<String, dynamic> orderData) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancel Order?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Please specify a reason for cancellation:"),
            TextField(controller: reasonController, decoration: const InputDecoration(hintText: "Reason")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
          ElevatedButton(
            onPressed: () async {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reason is required")));
                return;
              }
              
              final batch = _firestore.batch();
              final orderRef = _firestore.collection('orders').doc(table.currentOrderId);
              final tableRef = _firestore.collection('tables').doc(table.id);

              batch.update(orderRef, {
                'status': 'cancelled',
                'cancelReason': reasonController.text.trim(),
                'cancelledAt': FieldValue.serverTimestamp(),
              });

              // Sync table to available as part of cancel flow
              await TableStateSync.syncTableForOrderChange(
                firestore: _firestore,
                tableId: table.id,
                orderId: table.currentOrderId ?? '',
                orderState: 'cancelled',
                auth: auth,
                batch: batch,
              );

              if (table.currentOrderId != null) {
                final kotsSnap = await _firestore.collection('kots').where('orderId', isEqualTo: table.currentOrderId).get();
                for (var doc in kotsSnap.docs) {
                  batch.delete(doc.reference);
                }
              }

              await batch.commit();
              DebugLogger.logEvent(
                event: 'table_cleared',
                data: {
                  'userRole': auth.role.name,
                  'userId': auth.currentUser?.uid,
                  'tableId': table.id,
                  'orderId': table.currentOrderId,
                  'lockedBy': null,
                  'previousState': null,
                  'newState': 'available',
                },
              );

              if (mounted) {
                Navigator.pop(context); // Dialog
                Navigator.pop(context); // Panel
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Order cancelled and table cleared.")));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("CONFIRM CANCEL"),
          ),
        ],
      ),
    );
  }

  void _confirmClearTable(TableModel table) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear Table?"),
        content: Text("Do you want to generate the final bill with amounts before clearing ${table.name}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          OutlinedButton(
            onPressed: () async {
              final batch = _firestore.batch();
              // Sync table to available as part of manual clear
              await TableStateSync.syncTableForOrderChange(
                firestore: _firestore,
                tableId: table.id,
                orderId: table.currentOrderId ?? '',
                orderState: 'billed',
                auth: auth,
                batch: batch,
              );

              if (table.currentOrderId != null) {
                final kotsSnap = await _firestore.collection('kots').where('orderId', isEqualTo: table.currentOrderId).get();
                for (var doc in kotsSnap.docs) {
                  batch.update(doc.reference, {'status': 'Served'});
                }
              }

              await batch.commit();

              DebugLogger.logEvent(
                event: 'table_cleared',
                data: {
                  'userRole': auth.role.name,
                  'userId': auth.currentUser?.uid,
                  'tableId': table.id,
                  'orderId': table.currentOrderId,
                  'lockedBy': null,
                  'previousState': null,
                  'newState': 'available',
                },
              );

              DebugLogger.logEvent(
                event: 'table_lock_released',
                data: {
                  'userRole': auth.role.name,
                  'userId': auth.currentUser?.uid,
                  'tableId': table.id,
                  'orderId': table.currentOrderId,
                },
              );

              if (mounted) {
                Navigator.pop(context); // Dialog
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Table cleared manually.")));
              }
            },
            child: const Text("CLEAR ONLY"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // Close this dialog
              
              // Fetch latest order data and show billing dialog
              final orderSnap = await _firestore.collection('orders').doc(table.currentOrderId).get();
              if (orderSnap.exists) {
                final orderData = orderSnap.data() as Map<String, dynamic>;
                _showBillingDialog(table, orderData);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text("FINISH & PRINT BILL"),
          ),
        ],
      ),
    );
  }

  void _showBillingDialog(TableModel table, Map<String, dynamic> orderData) {
    String selectedPaymentMode = 'Cash';
    final subtotal = orderData['totalAmount'] ?? 0.0;
    final cgst = subtotal * 0.025;
    final sgst = subtotal * 0.025;
    final grandTotal = subtotal + cgst + sgst;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Generate Final Bill"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBillSummaryRow("Subtotal", subtotal),
              _buildBillSummaryRow("CGST (2.5%)", cgst),
              _buildBillSummaryRow("SGST (2.5%)", sgst),
              const Divider(),
              _buildBillSummaryRow("GRAND TOTAL", grandTotal, isBold: true),
              const SizedBox(height: 24),
              const Text("Payment Mode:", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['Cash', 'Card', 'UPI'].map((mode) => ChoiceChip(
                  label: Text(mode),
                  selected: selectedPaymentMode == mode,
                  onSelected: (selected) {
                    if (selected) setDialogState(() => selectedPaymentMode = mode);
                  },
                )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
            ElevatedButton(
              onPressed: () => _processBilling(table, orderData, subtotal, cgst, sgst, grandTotal, selectedPaymentMode),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              child: const Text("CONFIRM & PRINT"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBillSummaryRow(String label, double amount, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: isBold ? 18 : 14)),
          Text("₹${amount.toStringAsFixed(2)}", style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: isBold ? 18 : 14)),
        ],
      ),
    );
  }

  Future<void> _processBilling(TableModel table, Map<String, dynamic> orderData, double subtotal, double cgst, double sgst, double total, String paymentMode) async {
    try {
      final restaurantId = auth.restaurantId;
      final restaurantName = auth.restaurantName ?? "ShreeRajmandir";
        final previousOrderSnapshot = await _firestore.collection('orders').doc(table.currentOrderId).get();
        final previousOrderState = previousOrderSnapshot.exists
          ? ((previousOrderSnapshot.data() as Map<String, dynamic>)['status'] ?? 'unknown').toString()
          : null;
      final previousTableState = table.status.name;
      
      final orderRef = _firestore.collection('orders').doc(table.currentOrderId);
      final tableRef = _firestore.collection('tables').doc(table.id);
      final collectionId = "${restaurantId}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}";
      final collectionRef = _firestore.collection('daily_collections').doc(collectionId);
      final counterRef = _firestore.collection('receipt_counters').doc(restaurantId);

      // Pre-fetch KOTs since queries inside transactions are tricky
      final kotsSnap = await _firestore.collection('kots').where('orderId', isEqualTo: table.currentOrderId).get();

      int assignedReceiptNo = 0;

      // Perform Atomic Transaction to ensure sequential receipt tracking
      await _firestore.runTransaction((transaction) async {
        final counterSnap = await transaction.get(counterRef);
        assignedReceiptNo = counterSnap.exists ? (counterSnap.data()!['lastReceiptNo'] ?? 0) + 1 : 1;

        transaction.update(orderRef, {
          'status': 'billed',
          'subtotal': subtotal,
          'cgst': cgst,
          'sgst': sgst,
          'grandTotal': total,
          'paymentMode': paymentMode,
          'receiptNumber': assignedReceiptNo,
          'billedAt': FieldValue.serverTimestamp(),
        });

        // Sync table state based on order state (billed -> available)
        await TableStateSync.syncTableForOrderChange(
          firestore: _firestore,
          tableId: table.id,
          orderId: table.currentOrderId ?? '',
          orderState: 'billed',
          auth: auth,
          transaction: transaction,
        );

        // Daily Collection Update logic
        transaction.set(collectionRef, {
          'netCollection': FieldValue.increment(total),
          'grossCollection': FieldValue.increment(subtotal),
          'billCount': FieldValue.increment(1),
          'restaurantId': restaurantId,
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Update global counter
        transaction.set(counterRef, {
          'lastReceiptNo': assignedReceiptNo,
        }, SetOptions(merge: true));

        // Update KOTs
        for (var doc in kotsSnap.docs) {
          transaction.update(doc.reference, {'status': 'Served'});
        }
      });

      DebugLogger.logEvent(
        event: 'billing_completed',
        data: {
          'userRole': auth.role.name,
          'userId': auth.currentUser?.uid,
          'tableId': table.id,
          'orderId': table.currentOrderId,
          'lockedBy': null,
          'previousState': previousOrderState,
          'newState': 'billed',
          'paymentMode': paymentMode,
        },
      );

      DebugLogger.logEvent(
        event: 'table_cleared',
        data: {
          'userRole': auth.role.name,
          'userId': auth.currentUser?.uid,
          'tableId': table.id,
          'orderId': table.currentOrderId,
          'lockedBy': null,
          'previousState': previousTableState,
          'newState': 'available',
        },
      );

      DebugLogger.logEvent(
        event: 'table_lock_released',
        data: {
          'userRole': auth.role.name,
          'userId': auth.currentUser?.uid,
          'tableId': table.id,
          'orderId': table.currentOrderId,
        },
      );

      // Generate PDF & Print using the new proper Sequential Receipt Number
      final strReceiptNo = assignedReceiptNo.toString().padLeft(6, '0');
      orderData['receiptNumber'] = assignedReceiptNo;

      await ReportService.printFinalBill(
        orderData: orderData,
        orderId: strReceiptNo, // Use the generated string here!
        subtotal: subtotal,
        cgst: cgst,
        sgst: sgst,
        total: total,
        paymentMode: paymentMode,
        hotelName: restaurantName,
      );

      if (mounted) {
        Navigator.pop(context); // Close dialog
        Navigator.pop(context); // Close panel
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Bill #$strReceiptNo generated and table cleared!")));
      }
    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }
  void _showAddItemDialog(String orderId, Map<String, dynamic> orderData) {
    String searchQuery = '';
    final searchController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Add Item to Order"),
          content: SizedBox(
            width: 500,
            height: 600,
            child: Column(
              children: [
                // Search Bar
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search items...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              searchController.clear();
                              setDialogState(() => searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (value) => setDialogState(() => searchQuery = value.toLowerCase()),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('menu_categories')
                         .where('restaurantId', isEqualTo: auth.restaurantId)
                        .snapshots(),
                    builder: (context, categorySnapshot) {
                      if (!categorySnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final visibleCategories = categorySnapshot.data!.docs
                          .map((doc) => doc.data() as Map<String, dynamic>)
                          .where((data) => data['isVisible'] != false)
                          .map((data) => (data['name'] ?? '').toString())
                          .where((name) => name.isNotEmpty)
                          .toSet();

                      return StreamBuilder<QuerySnapshot>(
                        stream: _firestore
                          .collection('menu_items')
                          .where('restaurantId', isEqualTo: auth.restaurantId)
                            .where('isAvailable', isEqualTo: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                          final allItems = snapshot.data!.docs.where((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final category = (data['category'] ?? '').toString();
                            return visibleCategories.contains(category);
                          }).toList();

                          final items = searchQuery.isEmpty
                              ? allItems
                              : allItems.where((doc) {
                                  final name = (doc.data() as Map<String, dynamic>)['name']?.toString().toLowerCase() ?? '';
                                  return name.contains(searchQuery);
                                }).toList();

                          if (items.isEmpty) {
                            return const Center(child: Text('No items found', style: TextStyle(color: Colors.grey)));
                          }

                          return ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final data = item.data() as Map<String, dynamic>;
                              return ListTile(
                                leading: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8)),
                                  child: Icon(Icons.fastfood, color: Colors.orange[400], size: 22),
                                ),
                                title: Text(data['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('₹${data['price']}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.add_circle, color: Colors.green, size: 28),
                                  onPressed: () async {
                                    final orderSnapshot = await _firestore.collection('orders').doc(orderId).get();
                                    final status = orderSnapshot.exists
                                        ? ((orderSnapshot.data() as Map<String, dynamic>)['status'] ?? 'unknown').toString()
                                        : null;
                                    if (status == 'bill_requested') {
                                      DebugLogger.logEvent(
                                        event: 'blocked_action_bill_requested',
                                        data: {
                                          'userRole': auth.role.name,
                                          'userId': auth.currentUser?.uid,
                                          'tableId': orderData['tableId'],
                                          'orderId': orderId,
                                          'lockedBy': null,
                                          'attemptedAction': 'add_item',
                                          'previousState': status,
                                          'newState': status,
                                        },
                                      );
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Order is locked for billing')),
                                        );
                                      }
                                      return;
                                    }

                                    final currentItems = List<Map<String, dynamic>>.from(orderData['items']);
                                    final newItem = {
                                      'name': data['name'],
                                      'price': (data['price'] as num).toDouble(),
                                      'quantity': 1,
                                    };

                                    int existingIdx = currentItems.indexWhere((i) => i['name'] == data['name']);
                                    if (existingIdx != -1) {
                                      currentItems[existingIdx]['quantity'] += 1;
                                    } else {
                                      currentItems.add(newItem);
                                    }

                                    double newTotal = currentItems.fold(0, (sum, i) => sum + ((i['price'] as num) * (i['quantity'] as num)));

                                    await _firestore.collection('orders').doc(orderId).update({
                                      'items': currentItems,
                                      'totalAmount': newTotal,
                                    });

                                    DebugLogger.logEvent(
                                      event: 'items_added',
                                      data: {
                                        'userRole': auth.role.name,
                                        'userId': auth.currentUser?.uid,
                                        'tableId': orderData['tableId'],
                                        'orderId': orderId,
                                        'lockedBy': null,
                                        'previousState': null,
                                        'newState': null,
                                        'itemName': data['name'],
                                        'quantityDelta': 1,
                                      },
                                    );

                                    final kotData = {
                                      'tableName': orderData['tableName'],
                                      'items': [
                                        {
                                          'name': data['name'],
                                          'quantity': 1,
                                          'price': (data['price'] as num).toDouble(),
                                        }
                                      ],
                                    };
                                    await ReportService.printKOTReceipt(kotData, orderId);

                                    await _firestore.collection('kots').add({
                                      'tableId': orderData['tableId'],
                                      'tableName': orderData['tableName'],
                                      'orderId': orderId,
                                      'restaurantId': auth.restaurantId,
                                      'items': [
                                        {'name': data['name'], 'quantity': 1}
                                      ],
                                      'waiterName': 'Cashier',
                                      'status': 'Pending',
                                      'createdAt': FieldValue.serverTimestamp(),
                                    });

                                    DebugLogger.logEvent(
                                      event: 'kot_sent',
                                      data: {
                                        'userRole': auth.role.name,
                                        'userId': auth.currentUser?.uid,
                                        'tableId': orderData['tableId'],
                                        'orderId': orderId,
                                        'lockedBy': null,
                                        'previousState': null,
                                        'newState': null,
                                        'orderProgress': 'kot_sent',
                                      },
                                    );

                                    if (mounted) Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Added ${data['name']}')),
                                    );
                                  },
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))],
        ),
      ),
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
    String text = "LIV";
    IconData icon = Icons.check_circle;

    switch (status) {
      case TableStatus.available:
        color = Colors.green;
        text = "LIV";
        icon = Icons.check_circle;
        break;
      case TableStatus.occupied:
        color = Colors.orange;
        text = "OCC";
        icon = Icons.restaurant;
        break;
      case TableStatus.kotSent:
        color = Colors.blue;
        text = "KOT";
        icon = Icons.kitchen;
        break;
      case TableStatus.billRequested:
        color = Colors.red;
        text = "BIL";
        icon = Icons.receipt_long;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.5), width: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 7, color: color),
          const SizedBox(width: 2),
          Text(text, style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

