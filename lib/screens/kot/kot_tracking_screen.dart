import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/order_status_utils.dart';
import 'kot_details_screen.dart';

class KotTrackingScreen extends StatefulWidget {
  const KotTrackingScreen({super.key, this.profileIssueMessage});

  final String? profileIssueMessage;

  @override
  State<KotTrackingScreen> createState() => _KotTrackingScreenState();
}

class _KotTrackingScreenState extends State<KotTrackingScreen> {
  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;
    final auth = context.watch<AuthService>();
    final restaurantId = auth.restaurantId;

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
      stream: firestore
          .collection('kots')
          .where('restaurantId', isEqualTo: restaurantId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Unable to load KOTs: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final kots = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final normalized = OrderStatusUtils.normalizeStatus((data['status'] ?? 'placed').toString());
          return normalized != 'served' && normalized != 'closed' && normalized != 'cancelled';
        }).toList();

        if (kots.isEmpty) return const Center(child: Text('All KOTs are clear!'));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: kots.length,
          itemBuilder: (context, index) {
            final data = kots[index].data() as Map<String, dynamic>;
            final items = (data['items'] as List?) ?? [];
            final tableLabel = (data['tableName'] ?? data['tableId'] ?? 'N/A').toString();
            final kotTime = _formatKotTime(data['createdAt']);
            final status = OrderStatusUtils.normalizeStatus((data['status'] ?? 'placed').toString());
            final primary = Theme.of(context).colorScheme.primary;
            final (chipBg, chipFg) = _chipColors(status, primary);
            final waiterName = (data['waiterName'] ?? '').toString().trim();
            final showExpandArrow = items.length > 2;
            final previewItems = items.take(2).toList();

            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => KotDetailsScreen(kotId: kots[index].id)),
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4ECEB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: primary.withOpacity(0.2)),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: const BoxDecoration(
                        color: Color(0xFFDDEAF6),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'TABLE: ${tableLabel.toUpperCase()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            kotTime.toUpperCase(),
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (previewItems.isEmpty)
                            const Text('• No items')
                          else
                            ...previewItems.map((item) {
                              final qty = item['quantity'] ?? 0;
                              final name = (item['name'] ?? 'Item').toString();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  '• $name x $qty',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }),
                          if (items.length > previewItems.length)
                            Text(
                              '+${items.length - previewItems.length} more items',
                              style: TextStyle(
                                color: primary.withOpacity(0.8),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'By: ${waiterName.isEmpty ? '-' : waiterName}',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (showExpandArrow)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: primary.withOpacity(0.80),
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: chipBg,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                color: chipFg,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
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
    );
  }

  String _formatKotTime(dynamic createdAt) {
    if (createdAt is! Timestamp) return '--:--';
    final dateTime = createdAt.toDate();
    final hour12 = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final suffix = dateTime.hour >= 12 ? 'pm' : 'am';
    return '$hour12:$minute $suffix';
  }

  (Color, Color) _chipColors(String status, Color primary) {
    switch (status) {
      case 'served':
        return (const Color(0xFFE8F5E9), const Color(0xFF2E7D32));
      case 'preparing':
        return (const Color(0xFFFFF3E0), const Color(0xFFEF6C00));
      case 'placed':
      default:
        return (primary.withOpacity(0.14), primary);
    }
  }
}
