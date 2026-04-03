import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/kot_service.dart';
import '../../utils/order_status_utils.dart';

class KotDetailsScreen extends StatefulWidget {
  const KotDetailsScreen({
    super.key,
    required this.kotId,
  });

  final String kotId;

  @override
  State<KotDetailsScreen> createState() => _KotDetailsScreenState();
}

class _KotDetailsScreenState extends State<KotDetailsScreen> {
  bool _isUpdating = false;

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('KOT Details'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Close',
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: firestore.collection('kots').doc(widget.kotId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Unable to load KOT details: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.data!.exists || snapshot.data!.data() == null) {
            return const Center(child: Text('KOT not found.'));
          }

          final data = snapshot.data!.data()!;
          final auth = Provider.of<AuthService>(context);
          final items = (data['items'] as List?) ?? [];
          final tableLabel = (data['tableName'] ?? data['tableId'] ?? 'N/A').toString();
          final rawStatus = (data['status'] ?? '').toString();
          final status = rawStatus.toUpperCase();
          final normalized = OrderStatusUtils.normalizeStatus(rawStatus);
          final createdAt = data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null;
          String timeAgo = '';
          if (createdAt != null) {
            final diff = DateTime.now().difference(createdAt);
            if (diff.inMinutes < 1) {
              timeAgo = 'Just now';
            } else if (diff.inMinutes < 60) {
              timeAgo = '${diff.inMinutes} min ago';
            } else {
              timeAgo = TimeOfDay.fromDateTime(createdAt).format(context);
            }
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'TABLE ${tableLabel.toUpperCase()}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1),
                      ),
                      child: Text(status, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                    ),
                    if (timeAgo.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Text(timeAgo, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                if (auth.role == UserRole.kitchen)
                        Row(
                          children: [
                            if (normalized == 'placed')
                              ElevatedButton(
                                onPressed: _isUpdating
                                    ? null
                                    : () async {
                                        setState(() => _isUpdating = true);
                                        try {
                                          await KotService.updateStatus(widget.kotId, 'preparing');
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked preparing')));
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                        } finally {
                                          setState(() => _isUpdating = false);
                                        }
                                      },
                                child: _isUpdating
                                    ? const SizedBox(width: 110, height: 16, child: Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))))
                                    : const Text('Mark Preparing'),
                              ),
                            if (normalized == 'preparing')
                              ElevatedButton(
                                onPressed: _isUpdating
                                    ? null
                                    : () async {
                                        setState(() => _isUpdating = true);
                                        try {
                                          await KotService.updateStatus(widget.kotId, 'prepared');
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked prepared')));
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                        } finally {
                                          setState(() => _isUpdating = false);
                                        }
                                      },
                                child: _isUpdating
                                    ? const SizedBox(width: 110, height: 16, child: Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))))
                                    : const Text('Mark Prepared'),
                              ),
                          ],
                        ),
                const SizedBox(height: 14),
                const Text(
                  'Order Items',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('No items in this KOT.'),
                    ),
                  )
                else
                  ...items.map((item) {
                    final name = (item['name'] ?? 'Item').toString();
                    final quantity = item['quantity'] ?? 0;
                    final category = (item['category'] ?? '').toString();
                    final specialInstructions = (item['specialInstructions'] ?? '').toString();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.35)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                          child: Text(
                            '$quantity',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            Text(
                              category.isNotEmpty ? '[$category]' : '[Type]',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                        subtitle: specialInstructions.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('Note: $specialInstructions'),
                              )
                            : null,
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}
