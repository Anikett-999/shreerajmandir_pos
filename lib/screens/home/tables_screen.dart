import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../models/table_model.dart';
import '../../services/auth_service.dart';
import '../../services/kot_notification_service.dart';
import '../../utils/debouncer.dart';
import '../../utils/order_status_utils.dart';
import 'profile_details_screen.dart';
import 'waiter_kot_screen.dart';
import '../order/order_summary_screen.dart';
import '../order/menu_screen.dart';

class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  int _currentIndex = 0;
  final KotNotificationService _kotService = KotNotificationService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final restaurantId = context.read<AuthService>().restaurantId;
      _kotService.startListening(restaurantId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'Tables' : 'KOTs'),
        backgroundColor: const Color(0xFF922224), // new maroon shade
        foregroundColor: Colors.white,
      ),
      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF922224)), // new maroon shade
              child: const Align(
                alignment: Alignment.bottomLeft,
                child: Text('Waiter Menu', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.table_restaurant),
              title: const Text('Tables'),
              selected: _currentIndex == 0,
              onTap: () => setState(() {
                _currentIndex = 0;
                Navigator.pop(context);
              }),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('KOTs'),
              selected: _currentIndex == 1,
              onTap: () => setState(() {
                _currentIndex = 1;
                Navigator.pop(context);
              }),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Profile'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileDetailsScreen()));
              },
            ),
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.white)),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('Confirm Logout'),
                      content: const Text('Are you sure you want to log out?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF922224)),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Logout'),
                        ),
                      ],
                    );
                  },
                );
                if (confirm == true) {
                  Navigator.pop(context);
                  context.read<AuthService>().logout();
                }
              },
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          TablesGridTab(),
          WaiterKotScreen(),
        ],
      ),
    );
  }
}

class TablesGridTab extends StatefulWidget {
  const TablesGridTab({super.key});

  @override
  State<TablesGridTab> createState() => _TablesGridTabState();
}

class _TablesGridTabState extends State<TablesGridTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _debouncer = Debouncer(milliseconds: 1000);
  String _selectedStatus = 'All';

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          _buildFilters(),
          Expanded(child: _buildGrid()),
        ],
      ),
    );
  }

  String _mapTableStatusToOrderStatus(TableModel table) {
    switch (table.status) {
      case TableStatus.available:
        return 'available';
      case TableStatus.occupied:
        return 'placed';
      case TableStatus.kotSent:
        return 'preparing';
      case TableStatus.billRequested:
        return 'served';
    }
  }

  Widget _buildFilters() {
    final filterOptions = ['All', 'placed', 'prepared', 'preparing', 'served', 'closed', 'cancelled'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          DropdownButton<String>(
            value: _selectedStatus,
            items: filterOptions.map((option) {
              return DropdownMenuItem<String>(
                value: option,
                child: Text(option),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) setState(() => _selectedStatus = value);
            },
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
            underline: Container(height: 2, color: Color(0xFF922224)),
            borderRadius: BorderRadius.circular(10),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('tables').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        List<TableModel> tables = snapshot.data!.docs
            .map((doc) => TableModel.fromMap(doc.id, doc.data() as Map<String, dynamic>))
            .toList();

        // Apply status filter
        if (_selectedStatus != 'All') {
          // For filter to work, we need to check each table's order status
          // This will be done during grid building in a separate check
        }

        // Sort tables by table number (parsed from table.name)
        tables.sort((a, b) {
          int parseTableNo(String name) {
            final match = RegExp(r'\d+').firstMatch(name);
            return match != null ? int.tryParse(match.group(0)!) ?? 0 : 0;
          }
          return parseTableNo(a.name).compareTo(parseTableNo(b.name));
        });

        if (tables.isEmpty) {
          return const Center(child: Text('No tables found.'));
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            int crossAxisCount = 2;
            if (constraints.maxWidth > 1200) {
              crossAxisCount = 6;
            } else if (constraints.maxWidth > 900) {
              crossAxisCount = 4;
            } else if (constraints.maxWidth > 600) {
              crossAxisCount = 3;
            }

            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.2,
              ),
              itemCount: tables.length,
              itemBuilder: (context, index) {
                return _buildFilteredTableCard(tables[index]);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildFilteredTableCard(TableModel table) {
    if (_selectedStatus == 'All') {
      return _buildTableCard(table);
    }

    // Apply order status filter
    if (table.status == TableStatus.available) {
      // Available tables don't have orders, only show if filter is "All"
      return const SizedBox.shrink();
    }

    if (table.currentOrderId == null) {
      return const SizedBox.shrink();
    }

    // Check order status for filter
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('orders').doc(table.currentOrderId!).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final rawStatus = snapshot.data?.data()?['status']?.toString() ?? 'placed';
        final normalizedStatus = OrderStatusUtils.normalizeStatus(rawStatus);

        // Use normalized status for comparison
        if (normalizedStatus.toLowerCase() == _selectedStatus.toLowerCase()) {
          return _buildTableCard(table);
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildTableCard(TableModel table) {
    // Use a dimmed maroon color for all table card backgrounds
    const Color cardBackground = Color(0xFFF5E8E8); // Light maroon tint
    const Color borderColor = Color(0x66922224); // #922224 with 40% opacity
    
    return InkWell(
      onTap: () {
        _debouncer.run(() => _handleTableTap(table));
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: borderColor.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4)
            )
          ]
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(table.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            // Show order status if occupied
            if (table.status != TableStatus.available && table.currentOrderId != null)
              _buildOrderStatusBadge(table.currentOrderId!, table.status)
            else
              _buildTableStatusBadge(table.status),
          ],
        ),
      ),
    );
  }

  String _fallbackOrderStatusFromTable(TableStatus tableStatus) {
    switch (tableStatus) {
      case TableStatus.available:
        return 'closed';
      case TableStatus.occupied:
        return 'placed';
      case TableStatus.kotSent:
        return 'preparing';
      case TableStatus.billRequested:
        return 'served';
    }
  }

  Widget _buildOrderStatusVisual(String normalizedStatus) {
    final displayStatus = normalizedStatus.toUpperCase();
    Color bgColor = Colors.grey[200]!;
    Color fgColor = Colors.grey[800]!;
    IconData icon = Icons.help;

    switch (normalizedStatus) {
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
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fgColor.withOpacity(0.3), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fgColor, size: 14),
          const SizedBox(width: 6),
          Text(
            displayStatus,
            style: TextStyle(color: fgColor, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderStatusBadge(String orderId, TableStatus tableStatus) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('orders').doc(orderId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data?.exists == true) {
          final rawStatus = snapshot.data?.data()?['status']?.toString() ?? 'placed';
          final normalizedStatus = OrderStatusUtils.normalizeStatus(rawStatus);
          return _buildOrderStatusVisual(normalizedStatus);
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _firestore
              .collection('kots')
              .where('orderId', isEqualTo: orderId)
              .snapshots(),
          builder: (context, kotSnapshot) {
            if (kotSnapshot.hasData && kotSnapshot.data!.docs.isNotEmpty) {
              final kotDocs = kotSnapshot.data!.docs;
              QueryDocumentSnapshot<Map<String, dynamic>> latestKot = kotDocs.first;
              for (final doc in kotDocs.skip(1)) {
                final currentTs = doc.data()['createdAt'];
                final latestTs = latestKot.data()['createdAt'];
                if (currentTs is Timestamp && latestTs is Timestamp && currentTs.compareTo(latestTs) > 0) {
                  latestKot = doc;
                }
              }
              final rawKotStatus = latestKot.data()['status']?.toString() ?? '';
              final normalizedKotStatus = OrderStatusUtils.normalizeStatus(rawKotStatus);
              return _buildOrderStatusVisual(normalizedKotStatus);
            }

            final fallbackStatus = _fallbackOrderStatusFromTable(tableStatus);
            return _buildOrderStatusVisual(fallbackStatus);
          },
        );
      },
    );
  }

  Widget _buildTableStatusBadge(TableStatus status) {
    Color bgColor;
    Color fgColor;
    IconData icon;
    String statusStr;

    switch (status) {
      case TableStatus.available:
        bgColor = Colors.green[100]!;
        fgColor = Colors.green[900]!;
        icon = Icons.check_circle_outline;
        statusStr = 'AVAILABLE';
        break;
      case TableStatus.occupied:
        bgColor = Colors.orange[100]!;
        fgColor = Colors.orange[900]!;
        icon = Icons.people;
        statusStr = 'OCCUPIED';
        break;
      case TableStatus.kotSent:
        bgColor = Colors.blue[100]!;
        fgColor = Colors.blue[900]!;
        icon = Icons.restaurant;
        statusStr = 'KOT SENT';
        break;
      case TableStatus.billRequested:
        bgColor = Colors.red[100]!;
        fgColor = Colors.red[900]!;
        icon = Icons.receipt_long;
        statusStr = 'BILL';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fgColor.withOpacity(0.3), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fgColor, size: 14),
          const SizedBox(width: 6),
          Text(
            statusStr,
            style: TextStyle(color: fgColor, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _handleTableTap(TableModel table) {
    if (table.status == TableStatus.available) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Start order for ${table.name}?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text('Cancel')
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => MenuScreen(table: table)));
              }, 
              child: const Text('Confirm')
            ),
          ]
        )
      );
    } else {
      if (table.currentOrderId != null) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => OrderSummaryScreen(table: table, orderId: table.currentOrderId!)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: No active order found on this table')));
      }
    }
  }
}
