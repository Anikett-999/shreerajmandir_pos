import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../models/table_model.dart';
import '../../services/auth_service.dart';
import '../../services/kot_notification_service.dart';
import '../../utils/debouncer.dart';
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
    _kotService.startListening();
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
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
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
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
    final filterOptions = ['All', 'Available', 'placed', 'preparing', 'served'];
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

        final tables = snapshot.data!.docs
            .map((doc) => TableModel.fromMap(doc.id, doc.data() as Map<String, dynamic>))
            .where((t) {
              final tableStatus = _mapTableStatusToOrderStatus(t);
              return _selectedStatus == 'All' || tableStatus == _selectedStatus.toLowerCase();
            })
            .toList();

        // Sort tables by table number (parsed from table.name)
        tables.sort((a, b) {
          int parseTableNo(String name) {
            final match = RegExp(r'\d+').firstMatch(name);
            return match != null ? int.tryParse(match.group(0)!) ?? 0 : 0;
          }
          return parseTableNo(a.name).compareTo(parseTableNo(b.name));
        });

        if (tables.isEmpty) {
          return const Center(child: Text('No tables found for selected status.'));
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
                return _buildTableCard(tables[index]);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTableCard(TableModel table) {
    Color statusColor;
    String statusStr;
    switch (table.status) {
      case TableStatus.available:
        statusColor = Colors.green;
        statusStr = 'Available';
        break;
      case TableStatus.occupied:
        statusColor = Colors.orange;
        statusStr = 'Occupied';
        break;
      case TableStatus.kotSent:
        statusColor = Colors.blue;
        statusStr = 'KOT Sent';
        break;
      case TableStatus.billRequested:
        statusColor = Colors.red;
        statusStr = 'Bill Requested';
        break;
    }

    // Use a dimmed maroon color for all table card borders
    const Color borderColor = Color(0x66922224); // #922224 with 40% opacity
    return InkWell(
      onTap: () {
        _debouncer.run(() => _handleTableTap(table));
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
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
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusStr,
                style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            // Removed pax/capacity row
          ],
        ),
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
