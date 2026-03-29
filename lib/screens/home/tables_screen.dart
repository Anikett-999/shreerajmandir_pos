import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../models/table_model.dart';
import '../../services/auth_service.dart';
import '../../services/kot_notification_service.dart';
import 'profile_details_screen.dart';
import '../kot/kot_tracking_screen.dart';
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
  void dispose() {
    _kotService.stopListening();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _kotService.startListening();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: Text(_currentIndex == 0 ? 'ShreeRajmandir' : 'Kitchen Orders'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileDetailsScreen()),
                );
              },
              icon: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white,
                child: Text(
                  _initials(auth.currentUser?.email),
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      drawer: _buildDrawer(context, auth),
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          TablesGridTab(),
          KotTrackingScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (val) => setState(() => _currentIndex = val),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.table_restaurant), label: 'Tables'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt), label: 'KOTs'),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, AuthService auth) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: primaryColor,
              child: const Text(
                'Rajmandir Waiter Panel',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.table_restaurant),
              title: const Text('Tables'),
              selected: _currentIndex == 0,
              onTap: () {
                setState(() => _currentIndex = 0);
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('KOT Section'),
              selected: _currentIndex == 1,
              onTap: () {
                setState(() => _currentIndex = 1);
                Navigator.of(context).pop();
              },
            ),
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () async {
                Navigator.of(context).pop();
                await auth.logout();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String? email) {
    if (email == null || email.trim().isEmpty) return 'SR';
    return email.trim().substring(0, 1).toUpperCase();
  }
}

class TablesGridTab extends StatefulWidget {
  const TablesGridTab({super.key});

  @override
  State<TablesGridTab> createState() => _TablesGridTabState();
}

class _TablesGridTabState extends State<TablesGridTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[50],
      child: _buildGrid(),
    );
  }

  Widget _buildGrid() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('tables').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final tables = snapshot.data!.docs.map((doc) {
          return TableModel.fromMap(doc.id, doc.data() as Map<String, dynamic>);
        }).toList();

        if (tables.isEmpty) {
          return const Center(child: Text('No tables found'));
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
                childAspectRatio: constraints.maxWidth <= 420 ? 0.95 : 1.1,
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
    String statusStr;
    switch (table.status) {
      case TableStatus.available:
        statusStr = 'Available';
        break;
      case TableStatus.occupied:
        statusStr = 'Occupied';
        break;
      case TableStatus.kotSent:
        statusStr = 'KOT Sent';
        break;
      case TableStatus.billRequested:
        statusStr = 'Bill Requested';
        break;
    }

    final primary = Theme.of(context).colorScheme.primary;
    final cardColor = Color.alphaBlend(primary.withOpacity(0.06), Colors.white);
    final borderColor = primary.withOpacity(0.25);
    final chipBg = primary.withOpacity(0.12);

    return InkWell(
      onTap: () {
        _handleTableTap(table);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.6),
          boxShadow: [
            BoxShadow(
              color: primary.withOpacity(0.10),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ]
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                table.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: chipBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusStr,
                style: TextStyle(color: primary, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 16, color: primary.withOpacity(0.75)),
                const SizedBox(width: 4),
                Text(
                  '${table.capacity} pax',
                  style: TextStyle(color: primary.withOpacity(0.80), fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            )
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
