import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../services/report_service.dart';
import '../../utils/debouncer.dart';
import 'tabs/revenue_tab.dart';
import 'tabs/users_tab.dart';
import 'tabs/menu_tab.dart';
import 'tabs/tables_tab.dart';
import 'tabs/orders_tab.dart';
import 'tabs/analytics_tab.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  bool _isExtended = true;
  final _debouncer = Debouncer(milliseconds: 1500);
  Stream<QuerySnapshot>? _todayOrdersStream;
  String? _currentRestaurantId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthService>();
    if (_currentRestaurantId != auth.restaurantId) {
      _currentRestaurantId = auth.restaurantId;
      if (_currentRestaurantId != null) {
        final today = DateTime.now();
        final startOfDay = DateTime(today.year, today.month, today.day);
        _todayOrdersStream = FirebaseFirestore.instance.collection('orders')
            .where('restaurantId', isEqualTo: _currentRestaurantId)
            .where('createdAt', isGreaterThanOrEqualTo: startOfDay)
            .snapshots();
      } else {
        _todayOrdersStream = null;
      }
    }
  }

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }

  void _showMonthSelectionDialog() {
    int selectedYear = DateTime.now().year;
    int selectedMonth = DateTime.now().month;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Download Monthly Report"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Select the month and year for the report:"),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  DropdownButton<int>(
                    value: selectedYear,
                    items: List.generate(5, (i) => DateTime.now().year - i)
                        .map((y) => DropdownMenuItem(value: y, child: Text(y.toString())))
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedYear = v!),
                  ),
                  DropdownButton<int>(
                    value: selectedMonth,
                    items: List.generate(12, (i) => i + 1)
                        .map((m) => DropdownMenuItem(value: m, child: Text(DateFormat('MMMM').format(DateTime(2022, m)))))
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedMonth = v!),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _generateMonthlyReport(selectedYear, selectedMonth);
              },
              child: const Text("Download PDF"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateMonthlyReport(int year, int month) async {
    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 0, 23, 59, 59);
    final monthName = DateFormat('MMMM yyyy').format(startOfMonth);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final restaurantId = context.read<AuthService>().restaurantId;
      final snapshot = await FirebaseFirestore.instance.collection('orders')
          .where('restaurantId', isEqualTo: restaurantId)
          .where('createdAt', isGreaterThanOrEqualTo: startOfMonth)
          .where('createdAt', isLessThanOrEqualTo: endOfMonth)
          .get();
      
      final orders = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['status'] != 'cancelled';
      }).toList();
      
      if (mounted) Navigator.pop(context);
      
      if (orders.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No records found for $monthName")));
        return;
      }

      await ReportService.generatePeriodReport("Monthly Revenue Report", "Period: $monthName", orders);
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  final List<Widget> _tabs = [
    RevenueTab(),
    AnalyticsTab(),
    UsersTab(),
    MenuTab(),
    TablesTab(),
    OrdersTab(),
  ];

  static const _navData = [
    {'icon': Icons.dashboard, 'label': 'Dashboard'},
    {'icon': Icons.analytics, 'label': 'Analytics'},
    {'icon': Icons.people, 'label': 'Staff'},
    {'icon': Icons.restaurant_menu, 'label': 'Menu'},
    {'icon': Icons.table_bar, 'label': 'Tables'},
    {'icon': Icons.receipt_long, 'label': 'Orders'},
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 768;

        if (isMobile) {
          return Scaffold(
            appBar: AppBar(
              title: Text(_navData[_selectedIndex]['label'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Colors.white,
              elevation: 0,
              iconTheme: IconThemeData(color: theme.primaryColor),
            ),
            drawer: Drawer(
              child: Column(
                children: [
                   DrawerHeader(
                    decoration: BoxDecoration(color: theme.primaryColor.withOpacity(0.1)),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.restaurant, size: 48, color: theme.primaryColor),
                          const SizedBox(height: 10),
                          Text("ShreeRajmandir", style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold, fontSize: 18)),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        ...List.generate(_navData.length, (index) {
                          final item = _navData[index];
                          final isSelected = _selectedIndex == index;
                          return ListTile(
                            leading: Icon(item['icon'] as IconData, color: isSelected ? theme.primaryColor : Colors.grey),
                            title: Text(item['label'] as String, style: TextStyle(color: isSelected ? theme.primaryColor : Colors.black, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                            selected: isSelected,
                            onTap: () {
                              setState(() => _selectedIndex = index);
                              Navigator.pop(context);
                            },
                          );
                        }),
                        const Divider(),
                        const Padding(
                          padding: EdgeInsets.only(left: 16, top: 8, bottom: 4),
                          child: Text("REPORTS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                        ),
                        StreamBuilder<QuerySnapshot>(
                          stream: _todayOrdersStream,
                          builder: (context, snapshot) {
                            return ListTile(
                              leading: const Icon(Icons.picture_as_pdf, color: Colors.blue),
                              title: const Text("Daily PDF Report"),
                              onTap: snapshot.hasData ? () {
                                Navigator.pop(context);
                                _debouncer.run(() => ReportService.generateDailyCollectionReport(DateTime.now(), snapshot.data!.docs));
                              } : null,
                            );
                          }
                        ),
                        ListTile(
                          leading: const Icon(Icons.summarize, color: Colors.orange),
                          title: const Text("Monthly Report"),
                          onTap: () {
                            Navigator.pop(context);
                            _showMonthSelectionDialog();
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.redAccent),
                    title: const Text("Logout", style: TextStyle(color: Colors.redAccent)),
                    onTap: () => context.read<AuthService>().logout(),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            body: IndexedStack(index: _selectedIndex, children: _tabs),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (idx) => setState(() => _selectedIndex = idx),
              type: BottomNavigationBarType.fixed,
              selectedItemColor: theme.primaryColor,
              unselectedItemColor: Colors.grey,
              items: _navData.map((d) => BottomNavigationBarItem(
                icon: Icon(d['icon'] as IconData), 
                label: d['label'] as String
              )).toList(),
            ),
          );
        }

        // Desktop: Custom Animated Sidebar
        return Scaffold(
          body: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                width: _isExtended ? 240 : 80,
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(2, 0))
                  ],
                ),
                child: Column(
                  children: [
                    // Header with Toggle
                    Container(
                      height: 80,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: _isExtended ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
                        children: [
                          if (_isExtended)
                            const Expanded(
                              child: Text("ShreeRajmandir", 
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF800000)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          IconButton(
                            icon: Icon(_isExtended ? Icons.menu_open : Icons.menu),
                            onPressed: () => setState(() => _isExtended = !_isExtended),
                            color: Colors.grey[700],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    // Nav Items
                    Expanded(
                      child: ListView(
                        children: [
                          ...List.generate(_navData.length, (index) {
                            final item = _navData[index];
                            final isSelected = _selectedIndex == index;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              child: InkWell(
                                onTap: () => setState(() => _selectedIndex = index),
                                borderRadius: BorderRadius.circular(12),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected ? theme.primaryColor.withOpacity(0.1) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: _isExtended ? MainAxisAlignment.start : MainAxisAlignment.center,
                                    children: [
                                      Icon(item['icon'] as IconData, color: isSelected ? theme.primaryColor : Colors.grey[600], size: 24),
                                      if (_isExtended) ...[
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            item['label'] as String,
                                            style: TextStyle(
                                              color: isSelected ? theme.primaryColor : Colors.grey[700],
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                          const Divider(),
                          if (_isExtended)
                            const Padding(
                              padding: EdgeInsets.only(left: 16, top: 16, bottom: 8),
                              child: Text("REPORTS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.1)),
                            )
                          else
                            const SizedBox(height: 16),
                          
                          // Daily Report Button
                          StreamBuilder<QuerySnapshot>(
                            stream: _todayOrdersStream,
                            builder: (context, snapshot) {
                              final hasData = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                child: InkWell(
                                  onTap: hasData ? () => _debouncer.run(() => ReportService.generateDailyCollectionReport(DateTime.now(), snapshot.data!.docs)) : null,
                                  borderRadius: BorderRadius.circular(12),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    child: Row(
                                      mainAxisAlignment: _isExtended ? MainAxisAlignment.start : MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.picture_as_pdf, color: hasData ? Colors.blue : Colors.grey[400], size: 24),
                                        if (_isExtended) ...[
                                          const SizedBox(width: 12),
                                          const Expanded(
                                            child: Text("Daily PDF", 
                                              style: TextStyle(color: Colors.black87, fontSize: 13),
                                              overflow: TextOverflow.ellipsis),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }
                          ),

                          // Monthly Report Button
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: InkWell(
                              onTap: () => _showMonthSelectionDialog(),
                              borderRadius: BorderRadius.circular(12),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                child: Row(
                                  mainAxisAlignment: _isExtended ? MainAxisAlignment.start : MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.summarize, color: Colors.orange, size: 24),
                                    if (_isExtended) ...[
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text("Monthly Report", 
                                          style: TextStyle(color: Colors.black87, fontSize: 13),
                                          overflow: TextOverflow.ellipsis),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Footer
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: InkWell(
                        onTap: () => context.read<AuthService>().logout(),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          child: Row(
                            mainAxisAlignment: _isExtended ? MainAxisAlignment.start : MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.logout, color: Colors.redAccent),
                              if (_isExtended) ...[
                                const SizedBox(width: 12),
                                const Flexible(child: Text("Logout", 
                                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                )),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  color: Colors.grey[50],
                  child: IndexedStack(index: _selectedIndex, children: _tabs),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
