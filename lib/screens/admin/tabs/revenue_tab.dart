import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/auth_service.dart';
import '../../../utils/order_status_utils.dart';
import 'package:provider/provider.dart';

class RevenueTab extends StatefulWidget {
  const RevenueTab({super.key});

  @override
  State<RevenueTab> createState() => _RevenueTabState();
}

class _RevenueTabState extends State<RevenueTab> {
  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final startOfYesterday = DateTime(yesterday.year, yesterday.month, yesterday.day);

    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth < 420 ? 14.0 : 20.0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 20, horizontalPadding, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "Administration Overview",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    "Today",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          StreamBuilder<QuerySnapshot>(
            stream: firestore.collection('orders').where('restaurantId', isEqualTo: restaurantId).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(fontSize: 12)));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              double todayRevenue = 0;
              double yesterdayRevenue = 0;
              int completedOrders = 0;
              int cancelledOrders = 0;

              if (snapshot.hasData) {
                for (var doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (data['createdAt'] == null) continue;

                  final createdAt = (data['createdAt'] as Timestamp).toDate();
                  if (createdAt.isBefore(startOfYesterday)) continue;

                  final amount = (data['totalAmount'] ?? 0).toDouble();
                  final status = OrderStatusUtils.normalizeOrderStatusForRead(
                    rawStatus: data['status'] ?? 'active',
                    auth: auth,
                    orderId: doc.id,
                    tableId: data['tableId']?.toString(),
                    source: 'admin.revenue_tab',
                  );

                  if (createdAt.isAfter(startOfDay)) {
                    if (status == 'cancelled') {
                      cancelledOrders++;
                    } else {
                      todayRevenue += amount;
                      if (status == 'closed') completedOrders++;
                    }
                  } else if (createdAt.isAfter(startOfYesterday) && createdAt.isBefore(startOfDay)) {
                    if (status != 'cancelled') {
                      yesterdayRevenue += amount;
                    }
                  }
                }
              }

              String revenueTrend = "No comparison yet";
              Color trendColor = Colors.grey;
              IconData trendIcon = Icons.trending_flat_rounded;
              if (yesterdayRevenue > 0) {
                final growth = ((todayRevenue - yesterdayRevenue) / yesterdayRevenue) * 100;
                revenueTrend = "${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(1)}% vs yesterday";
                trendColor = growth >= 0 ? const Color(0xFF15803D) : const Color(0xFFB42318);
                trendIcon = growth >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded;
              }

              final orderTotal = completedOrders + cancelledOrders;
              final completionRate = orderTotal > 0 ? (completedOrders / orderTotal) : 0.0;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 170,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _buildPrimaryRevenueCard(
                          title: "Today's Sales",
                          value: "₹${todayRevenue.toStringAsFixed(2)}",
                          subtitle: revenueTrend,
                          subtitleColor: trendColor,
                          trendIcon: trendIcon,
                        ),
                        const SizedBox(width: 12),
                        _buildStripKpiCard(
                          title: "Closed Orders",
                          value: completedOrders.toString(),
                          icon: Icons.check_circle_outline_rounded,
                          color: const Color(0xFF0A84C6),
                        ),
                        const SizedBox(width: 12),
                        _buildStripKpiCard(
                          title: "Cancelled",
                          value: cancelledOrders.toString(),
                          icon: Icons.cancel_outlined,
                          color: const Color(0xFFD92D20),
                        ),
                        const SizedBox(width: 12),
                        _buildActiveTablesCard(firestore, restaurantId),
                        const SizedBox(width: 12),
                        _buildPendingKotsCard(firestore, restaurantId),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildSectionHeader("Order Activity", Icons.receipt_long_rounded, const Color(0xFF0A84C6)),
                  const SizedBox(height: 12),
                  _buildInsightPanel(
                    title: "Billing completion rate",
                    subtitle: "$completedOrders closed out of $orderTotal processed orders",
                    progress: completionRate,
                    progressColor: const Color(0xFF0A84C6),
                    trailingValue: "${(completionRate * 100).toStringAsFixed(0)}%",
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.grey[800],
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: color.withOpacity(0.24), thickness: 1.4)),
      ],
    );
  }

  Widget _buildPrimaryRevenueCard({
    required String title,
    required String value,
    required String subtitle,
    required Color subtitleColor,
    required IconData trendIcon,
  }) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF0FDF4), Color(0xFFE7F7ED)],
        ),
        border: Border.all(color: const Color(0xFFBBF7D0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF15803D).withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.currency_rupee_rounded, color: Color(0xFF15803D), size: 20),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: const Text(
                  "Primary KPI",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            title,
            style: TextStyle(color: Colors.grey[700], fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), height: 1.02),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(trendIcon, color: subtitleColor, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: subtitleColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStripKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 164,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightPanel({
    required String title,
    required String subtitle,
    required double progress,
    required Color progressColor,
    required String trailingValue,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                trailingValue,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: progressColor),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: progress,
              backgroundColor: Colors.grey[200],
              color: progressColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTablesCard(FirebaseFirestore firestore, String? restaurantId) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('tables')
          .where('restaurantId', isEqualTo: restaurantId)
          .where('status', isNotEqualTo: 'available')
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return _buildStripKpiCard(
          title: "Occupied Tables",
          value: count.toString(),
          icon: Icons.table_bar_rounded,
          color: const Color(0xFFC2410C),
        );
      },
    );
  }

  Widget _buildPendingKotsCard(FirebaseFirestore firestore, String? restaurantId) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('kots')
          .where('restaurantId', isEqualTo: restaurantId)
          .snapshots(),
      builder: (context, snapshot) {
        var count = 0;
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final normalized = OrderStatusUtils.normalizeStatus((data['status'] ?? '').toString());
            if (normalized == 'placed' || normalized == 'preparing') {
              count++;
            }
          }
        }

        return _buildStripKpiCard(
          title: "Active KOTs",
          value: count.toString(),
          icon: Icons.timer_outlined,
          color: const Color(0xFFD92D20),
        );
      },
    );
  }
}

