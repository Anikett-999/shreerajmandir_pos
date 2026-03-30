import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../models/table_model.dart';
import '../../services/auth_service.dart';
import '../auth/unauthorized_screen.dart';
import '../../services/debug_logger.dart';
import '../../services/kot_notification_service.dart';
import '../../utils/table_sort_utils.dart';
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
    if (auth.role == UserRole.kitchen) {
      return const UnauthorizedScreen();
    }
    final restaurantId = auth.restaurantId;
    final profileIssue = auth.profileIssueMessage;
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
        children: [
          TablesGridTab(
            restaurantId: restaurantId,
            profileIssueMessage: profileIssue,
          ),
          KotTrackingScreen(profileIssueMessage: profileIssue),
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
  const TablesGridTab({
    super.key,
    required this.restaurantId,
    this.profileIssueMessage,
  });

  final String? restaurantId;
  final String? profileIssueMessage;

  @override
  State<TablesGridTab> createState() => _TablesGridTabState();
}

class _TablesGridTabState extends State<TablesGridTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  DateTime? _lastCleanup;
  bool _cleanupInProgress = false;
  static const Duration _cleanupInterval = Duration(minutes: 1);
  static const Duration _staleThreshold = Duration(minutes: 10);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[50],
      child: _buildGrid(),
    );
  }

  @override
  void initState() {
    super.initState();
    // Run a cleanup once when the tables grid is first shown.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cleanupStaleLocks();
    });
  }

  Widget _buildGrid() {
    final restaurantId = widget.restaurantId;
    if (restaurantId == null || restaurantId.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            widget.profileIssueMessage ?? 'Restaurant profile missing for this user.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('tables').where('restaurantId', isEqualTo: restaurantId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final tables = sortTableModelsByNumber(snapshot.data!.docs.map((doc) {
          return TableModel.fromMap(doc.id, doc.data() as Map<String, dynamic>);
        }));

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
    _attemptTableAccess(table);
  }

  Future<void> _attemptTableAccess(TableModel table) async {
    final auth = context.read<AuthService>();
    final userId = auth.currentUser?.uid;
    final role = auth.role;
    // Run cleanup before attempting access, but debounce to avoid running on every tap.
    final shouldRunCleanup = !_cleanupInProgress && (_lastCleanup == null || DateTime.now().difference(_lastCleanup!) > _cleanupInterval);
    if (shouldRunCleanup) await _cleanupStaleLocks();
    final tableRef = _firestore.collection('tables').doc(table.id);

    // perform read-check-write in a transaction to avoid races
    try {
      final result = await _firestore.runTransaction<Map<String, dynamic>>((tx) async {
        final snap = await tx.get(tableRef);
        final data = snap.data() as Map<String, dynamic>?;
        String? lockedBy = data?['lockedBy'] as String?;
        final Timestamp? lockedAtTs = data?['lockedAt'] as Timestamp?;
        DateTime? lockedAt = lockedAtTs?.toDate();

        final now = DateTime.now();
        final takeoverThreshold = now.subtract(const Duration(minutes: 10));

        // Decide action inside transaction
        // For cashier/admin: allow access (bypass) and only claim lock if it's null or expired
        if (role == UserRole.cashier || role == UserRole.admin) {
          if (lockedBy == null) {
            tx.update(tableRef, {'lockedBy': userId, 'lockedAt': FieldValue.serverTimestamp()});
            return {'action': 'claimed', 'previous': null};
          }
          if (lockedAt != null && lockedAt.isBefore(takeoverThreshold)) {
            tx.update(tableRef, {'lockedBy': userId, 'lockedAt': FieldValue.serverTimestamp()});
            return {'action': 'override', 'previous': lockedBy};
          }
          // bypass without stealing ownership
          return {'action': 'bypass', 'previous': lockedBy};
        }

        // Waiter logic: must acquire or takeover within transaction
        if (lockedBy == null) {
          tx.update(tableRef, {'lockedBy': userId, 'lockedAt': FieldValue.serverTimestamp()});
          return {'action': 'claimed', 'previous': null};
        }

        if (lockedBy == userId) {
          return {'action': 'owned', 'previous': userId};
        }

        if (lockedAt != null && lockedAt.isBefore(takeoverThreshold)) {
          tx.update(tableRef, {'lockedBy': userId, 'lockedAt': FieldValue.serverTimestamp()});
          return {'action': 'override', 'previous': lockedBy};
        }

        // abort: still owned by someone else and not expired
        throw FirebaseException(
          plugin: 'firestore',
          message: 'locked',
          code: 'aborted',
        );
      });

      // transaction committed, interpret result and act accordingly
      final action = result['action'] as String?;
      final previous = result['previous'] as String?;

      // Logging helper
      void logLockEvent(String event, String? previousLockedBy, String? newLockedBy) {
        DebugLogger.logEvent(
          event: event,
          data: {
            'userRole': role.name,
            'userId': userId,
            'tableId': table.id,
            'previousLockedBy': previousLockedBy,
            'newLockedBy': newLockedBy,
          },
        );
      }

      if (action == 'claimed') {
        logLockEvent('table_locked', null, userId);
      } else if (action == 'owned') {
        // nothing changed, user already owner
      } else if (action == 'override') {
        logLockEvent('table_lock_override', previous, userId);
      } else if (action == 'bypass') {
        logLockEvent('table_access_bypass', previous, userId);
      }

      _proceedToTable(table);
    } on FirebaseException catch (e) {
      // treat aborted/locked as blocked
      DebugLogger.logEvent(
        event: 'table_lock_blocked',
        data: {
          'userRole': role.name,
          'userId': userId,
          'tableId': table.id,
        },
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Table is currently being used by another staff member')));
    } catch (e) {
      // unexpected error
      DebugLogger.logEvent(event: 'table_lock_error', data: {'error': e.toString(), 'tableId': table.id});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to access table. Please try again.')));
    }
  }

  Future<void> _cleanupStaleLocks() async {
    if (_cleanupInProgress) return;
    _cleanupInProgress = true;
    try {
      final now = DateTime.now();
      final threshold = now.subtract(_staleThreshold);

      // Query tables that have a lockedBy (limit to avoid huge workloads)
      final query = _firestore.collection('tables').where('lockedBy', isNotEqualTo: null).limit(100);
      final snap = await query.get();
      if (snap.docs.isEmpty) {
        _lastCleanup = DateTime.now();
        return;
      }

      final batch = _firestore.batch();
      int ops = 0;
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;
        final ts = data['lockedAt'] as Timestamp?;
        final lockedAt = ts?.toDate();
        if (lockedAt == null) continue;
        // Double-check timestamp is older than threshold before releasing
        if (lockedAt.isBefore(threshold)) {
          batch.update(doc.reference, {'lockedBy': null, 'lockedAt': null});
          DebugLogger.logEvent(
            event: 'table_lock_released_auto',
            data: {
              'tableId': doc.id,
              'previousLockedAt': lockedAt.toIso8601String(),
            },
          );
          ops++;
        }
      }

      if (ops > 0) {
        await batch.commit();
      }

      _lastCleanup = DateTime.now();
    } catch (e) {
      DebugLogger.logEvent(event: 'table_lock_cleanup_error', data: {'error': e.toString()});
    } finally {
      _cleanupInProgress = false;
    }
  }

  void _proceedToTable(TableModel table) {
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
