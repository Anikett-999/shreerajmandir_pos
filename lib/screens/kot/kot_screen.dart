import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../home/profile_details_screen.dart';
import '../../services/auth_service.dart';
import '../../services/kot_service.dart';
import '../../utils/order_status_utils.dart';
import 'kot_details_screen.dart';

class KotScreen extends StatefulWidget {
  const KotScreen({super.key});

  @override
  State<KotScreen> createState() => _KotScreenState();
}

class _KotScreenState extends State<KotScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _updatingKotIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final restaurantId = auth.restaurantId;

    if (restaurantId == null || restaurantId.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Restaurant profile missing for this user.'),
      ));
    }

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final startTs = Timestamp.fromDate(startOfDay);

    return Scaffold(
      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text('Kitchen Menu', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.restaurant_menu),
              title: const Text('KOTs'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Profile'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileDetailsScreen()));
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: const Text('Confirm Logout'),
                          content: const Text('Are you sure you want to log out?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
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
              ),
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: const Text('KOTs (Kitchen)'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by table, item or waiter',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Debug override: when diagnosing, set `showDebug` to true to
        // remove the `restaurantId` filter and inspect all KOTs in the
        // project. Leave false for normal behavior.
        stream: (() {
          const bool showDebug = true;
          if (showDebug) {
            return FirebaseFirestore.instance.collection('kots').orderBy('createdAt', descending: true).snapshots();
          }
          return FirebaseFirestore.instance
              .collection('kots')
              .where('restaurantId', isEqualTo: restaurantId)
              .orderBy('createdAt', descending: true)
              .snapshots();
        })(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error loading KOTs'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          // DEBUG: show raw snapshot info (help diagnose missing KOTs)
          const bool showDebug = true;
          final rawDocs = snapshot.data!.docs;
          if (showDebug) {
            // print to console
            try {
              print('KotScreen snapshot: total=${rawDocs.length} for restaurantId=$restaurantId');
              for (var i = 0; i < (rawDocs.length < 5 ? rawDocs.length : 5); i++) {
                final d = rawDocs[i].data() as Map<String, dynamic>;
                print('KOT[${rawDocs[i].id}] status=${d['status']} createdAt=${d['createdAt']} restaurantId=${d['restaurantId']}');
              }
            } catch (_) {}
          }

          final docs = rawDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final createdAt = data['createdAt'];
            // include docs with no createdAt yet (serverTimestamp pending)
            if (createdAt == null) {
              // treat as today
            } else if (createdAt is Timestamp) {
              if (createdAt.compareTo(startTs) < 0) return false; // older than today
            } else {
              return false;
            }
            final status = OrderStatusUtils.normalizeStatus((data['status'] ?? '').toString());
            // main screen shows only placed and preparing (kitchen queue)
            return status == 'placed' || status == 'preparing';
          }).toList();

          // if debug, show a small panel with raw doc summaries
          Widget debugPanel = const SizedBox.shrink();
          if (showDebug) {
            final examples = rawDocs.take(5).map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              final created = d['createdAt'] is Timestamp ? (d['createdAt'] as Timestamp).toDate().toString() : '${d['createdAt']}';
              return '${doc.id.substring(0,6)} status=${d['status'] ?? ''} rest=${d['restaurantId'] ?? ''} created=$created';
            }).toList();
            debugPanel = Container(
              width: double.infinity,
              color: Colors.yellow.shade50,
              padding: const EdgeInsets.all(8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('DEBUG: totalDocs=${rawDocs.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ...examples.map((e) => Text(e, style: const TextStyle(fontSize: 12))),
              ]),
            );
          }

          final query = _searchController.text.trim().toLowerCase();
          final filtered = docs.where((doc) {
            if (query.isEmpty) return true;
            final data = doc.data() as Map<String, dynamic>;
            final table = ((data['tableName'] ?? data['tableId'] ?? '')).toString().toLowerCase();
            final waiter = (data['waiterName'] ?? '').toString().toLowerCase();
            if (table.contains(query) || waiter.contains(query)) return true;
            final items = (data['items'] as List?) ?? [];
            return items.any((it) {
              final name = (it['name'] ?? '').toString().toLowerCase();
              return name.contains(query);
            });
          }).toList();

          if (filtered.isEmpty) return const Center(child: Text('No KOTs for today.'));

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final doc = filtered[index];
              final data = doc.data() as Map<String, dynamic>;
              final status = OrderStatusUtils.normalizeStatus((data['status'] ?? '').toString());
              final table = (data['tableName'] ?? data['tableId'] ?? 'N/A').toString();
              final items = ((data['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => KotDetailsScreen(kotId: doc.id)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('Table: ${table.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold))),
                            _StatusChip(status: status),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...items.take(2).map((it) {
                          final name = (it['name'] ?? 'Item').toString();
                          final qty = it['quantity'] ?? 1;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('• $name x$qty'),
                          );
                        }),
                        if (items.length > 2)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('+${items.length - 2} more items', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                          ),
                        const SizedBox(height: 8),
                        if (auth.role == UserRole.kitchen)
                          Row(
                            children: [
                              if (status == 'placed')
                                ElevatedButton(
                                  onPressed: _updatingKotIds.contains(doc.id)
                                      ? null
                                      : () async {
                                          setState(() => _updatingKotIds.add(doc.id));
                                          try {
                                            await KotService.updateStatus(doc.id, 'preparing');
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked preparing')));
                                          } catch (e) {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                          } finally {
                                            setState(() => _updatingKotIds.remove(doc.id));
                                          }
                                        },
                                  child: _updatingKotIds.contains(doc.id)
                                      ? const SizedBox(width: 110, height: 16, child: Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))))
                                      : const Text('Mark Preparing'),
                                ),
                              if (status == 'preparing')
                                ElevatedButton(
                                  onPressed: _updatingKotIds.contains(doc.id)
                                      ? null
                                      : () async {
                                          setState(() => _updatingKotIds.add(doc.id));
                                          try {
                                            await KotService.updateStatus(doc.id, 'prepared');
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked prepared')));
                                          } catch (e) {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                          } finally {
                                            setState(() => _updatingKotIds.remove(doc.id));
                                          }
                                        },
                                  child: _updatingKotIds.contains(doc.id)
                                      ? const SizedBox(width: 110, height: 16, child: Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))))
                                      : const Text('Mark Prepared'),
                                ),
                            ],
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
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (status) {
      case 'served':
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        break;
      case 'preparing':
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade800;
        break;
      case 'prepared':
        bg = Colors.deepOrange.shade50;
        fg = Colors.deepOrange.shade700;
        break;
      case 'placed':
      default:
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w700, color: fg, fontSize: 11)),
    );
  }
}
