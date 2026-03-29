import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../home/profile_details_screen.dart';
import 'reports_screen.dart';
import 'tabs/revenue_tab.dart';
import 'tabs/users_tab.dart';
import 'tabs/menu_tab.dart';
import 'tabs/tables_tab.dart';
import 'tabs/analytics_tab.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  bool _isExtended = true;

  void _openReportsScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReportsScreen()),
    );
  }

  final List<Widget> _tabs = [
    RevenueTab(),
    AnalyticsTab(),
    UsersTab(),
    MenuTab(),
    TablesTab(),
  ];

  static const _navData = [
    {'icon': Icons.dashboard, 'label': 'Dashboard'},
    {'icon': Icons.analytics, 'label': 'Analytics'},
    {'icon': Icons.people, 'label': 'Staff'},
    {'icon': Icons.restaurant_menu, 'label': 'Menu'},
    {'icon': Icons.table_bar, 'label': 'Tables'},
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthService>();
    final email = auth.currentUser?.email;
    final role = auth.role.name;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 768;

        if (isMobile) {
          return Scaffold(
            appBar: AppBar(
              title: Text(_navData[_selectedIndex]['label'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            drawer: Drawer(
              child: Column(
                children: [
                  DrawerHeader(
                    decoration: BoxDecoration(color: theme.primaryColor.withOpacity(0.1)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: theme.primaryColor,
                              child: Text(
                                _initials(email),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "ShreeRajmandir",
                                    style: TextStyle(
                                      color: theme.primaryColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    role.toUpperCase(),
                                    style: TextStyle(
                                      color: theme.primaryColor.withOpacity(0.75),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ProfileDetailsScreen(),
                              ),
                            );
                          },
                          icon: Icon(Icons.person_outline, color: theme.primaryColor, size: 18),
                          label: Text(
                            "View Profile Details",
                            style: TextStyle(
                              color: theme.primaryColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: theme.primaryColor,
                            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            minimumSize: Size.zero,
                          ),
                        ),
                      ],
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
                        ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: const Text("Reports"),
                          onTap: () {
                            Navigator.pop(context);
                            _openReportsScreen();
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
            bottomNavigationBar: NavigationBarTheme(
              data: NavigationBarThemeData(
                height: 72,
                indicatorColor: theme.primaryColor.withOpacity(0.12),
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? theme.primaryColor : Colors.grey[700],
                  );
                }),
              ),
              child: NavigationBar(
                backgroundColor: Colors.white,
                selectedIndex: _selectedIndex,
                onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
                destinations: _navData.map((d) {
                  final icon = d['icon'] as IconData;
                  final label = d['label'] as String;
                  return NavigationDestination(
                    icon: Icon(icon, color: Colors.grey[600], size: 22),
                    selectedIcon: Icon(icon, color: theme.primaryColor, size: 22),
                    label: label,
                  );
                }).toList(),
              ),
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

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: InkWell(
                              onTap: _openReportsScreen,
                              borderRadius: BorderRadius.circular(12),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                child: Row(
                                  mainAxisAlignment: _isExtended ? MainAxisAlignment.start : MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.description_outlined, color: Colors.black54, size: 24),
                                    if (_isExtended) ...[
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text("Reports", 
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

  String _initials(String? email) {
    if (email == null || email.trim().isEmpty) return 'SR';
    return email.trim().substring(0, 1).toUpperCase();
  }
}
