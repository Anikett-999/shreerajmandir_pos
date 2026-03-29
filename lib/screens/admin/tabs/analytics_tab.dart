import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../services/auth_service.dart';
import 'package:provider/provider.dart';

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  int _chartPageIndex = 0;

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;
    final today = DateTime.now();
    final startOfThisMonth = DateTime(today.year, today.month, 1);
    final startOfLastMonth = DateTime(today.year, today.month - 1, 1);
    final startOfYear = DateTime(today.year, 1, 1);

    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),

          // ── MONTHLY PERFORMANCE ──────────────────────────────────────────
          _buildSectionHeader("Monthly Performance", Icons.bar_chart, const Color(0xFF800000)),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: firestore.collection('orders')
                .where('restaurantId', isEqualTo: restaurantId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(fontSize: 12)));
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

              double thisMonthRevenue = 0;
              double lastMonthRevenue = 0;
              int thisMonthOrders = 0;

              if (snapshot.hasData) {
                for (var doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (data['status'] == 'cancelled') continue;
                  if (data['createdAt'] == null) continue;
                  
                  final createdAt = (data['createdAt'] as Timestamp).toDate();
                  // In-memory filter for Last Month onwards
                  if (createdAt.isBefore(startOfLastMonth)) continue;
                  
                  final amount = (data['totalAmount'] ?? 0).toDouble();

                  if (createdAt.isAfter(startOfThisMonth)) {
                    thisMonthRevenue += amount;
                    thisMonthOrders++;
                  } else if (createdAt.isAfter(startOfLastMonth) && createdAt.isBefore(startOfThisMonth)) {
                    lastMonthRevenue += amount;
                  }
                }
              }

              String monthTrend = "";
              Color trendColor = Colors.grey;
              if (lastMonthRevenue > 0) {
                final growth = ((thisMonthRevenue - lastMonthRevenue) / lastMonthRevenue) * 100;
                monthTrend = "${growth >= 0 ? '▲' : '▼'} ${growth.abs().toStringAsFixed(1)}% vs last month";
                trendColor = growth >= 0 ? Colors.green : Colors.red;
              }

              return Column(
                children: [
                  _buildKpiCarousel(
                    context,
                    thisMonthTitle: "This Month (${DateFormat('MMMM').format(today)})",
                    thisMonthRevenue: "₹${thisMonthRevenue.toStringAsFixed(0)}",
                    lastMonthTitle: "Last Month (${DateFormat('MMMM').format(startOfLastMonth)})",
                    lastMonthRevenue: "₹${lastMonthRevenue.toStringAsFixed(0)}",
                    monthlyOrders: thisMonthOrders.toString(),
                    monthTrend: monthTrend,
                    trendColor: trendColor,
                  ),
                  const SizedBox(height: 24),
                  _buildChartCarousel(firestore, startOfYear, restaurantId),
                ],
              );
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildKpiCarousel(
    BuildContext context, {
    required String thisMonthTitle,
    required String thisMonthRevenue,
    required String lastMonthTitle,
    required String lastMonthRevenue,
    required String monthlyOrders,
    required String monthTrend,
    required Color trendColor,
  }) {
    final cards = <Widget>[
      _buildKpiCard(
        title: thisMonthTitle,
        value: thisMonthRevenue,
        icon: Icons.calendar_month,
        color: const Color(0xFF800000),
      ),
      _buildKpiCard(
        title: lastMonthTitle,
        value: lastMonthRevenue,
        icon: Icons.calendar_today,
        color: Colors.indigo,
      ),
      _buildKpiCard(
        title: "Monthly Orders",
        value: monthlyOrders,
        icon: Icons.receipt,
        color: Colors.teal,
      ),
      _buildKpiCard(
        title: "Growth vs Last Month",
        value: monthTrend.isEmpty ? "No comparison yet" : monthTrend,
        icon: monthTrend.startsWith('▼') ? Icons.trending_down : Icons.trending_up,
        color: monthTrend.isEmpty ? Colors.grey : trendColor,
      ),
    ];

    return Column(
      children: List.generate(cards.length, (index) {
        return Padding(
          padding: EdgeInsets.only(bottom: index == cards.length - 1 ? 0 : 12),
          child: cards[index],
        );
      }),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                  softWrap: true,
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                  softWrap: true,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildChartCarousel(FirebaseFirestore firestore, DateTime startOfYear, String? restaurantId) {
    final chartBuilders = <Widget Function()>[
      () => _buildMonthlyBarChart(firestore, startOfYear, restaurantId),
      () => _buildCategoryPieChart(firestore, restaurantId),
      () => _buildWeeklyLineChart(firestore, restaurantId),
    ];

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: _chartPageIndex > 0 ? () => _changeChartPage(_chartPageIndex - 1) : null,
              icon: const Icon(Icons.chevron_left_rounded),
              tooltip: 'Previous chart',
            ),
            Text(
              'Chart ${_chartPageIndex + 1} / ${chartBuilders.length}',
              style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600),
            ),
            IconButton(
              onPressed: _chartPageIndex < chartBuilders.length - 1 ? () => _changeChartPage(_chartPageIndex + 1) : null,
              icon: const Icon(Icons.chevron_right_rounded),
              tooltip: 'Next chart',
            ),
          ],
        ),
        SizedBox(
          height: 360,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) {
              final delta = details.delta.dx;
              if (delta < -8 && _chartPageIndex < chartBuilders.length - 1) {
                _changeChartPage(_chartPageIndex + 1);
              } else if (delta > 8 && _chartPageIndex > 0) {
                _changeChartPage(_chartPageIndex - 1);
              }
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: KeyedSubtree(
                key: ValueKey<int>(_chartPageIndex),
                child: chartBuilders[_chartPageIndex](),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(chartBuilders.length, (index) {
            final selected = index == _chartPageIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: selected ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF8C1026) : Colors.grey[300],
                borderRadius: BorderRadius.circular(99),
              ),
            );
          }),
        ),
      ],
    );
  }

  void _changeChartPage(int newIndex) {
    if (newIndex < 0 || newIndex > 2 || newIndex == _chartPageIndex) return;
    setState(() => _chartPageIndex = newIndex);
  }

  Widget _buildMonthlyBarChart(FirebaseFirestore firestore, DateTime startOfYear, String? restaurantId) {
    final now = DateTime.now();
    final monthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('orders')
          .where('restaurantId', isEqualTo: restaurantId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(fontSize: 10, color: Colors.red)));
        }
        
        final Map<int, double> monthlyRevenue = { for (int i = 0; i < 12; i++) i: 0 };

        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['status'] == 'cancelled') continue;
            if (data['createdAt'] == null) continue;
            
            final createdAt = (data['createdAt'] as Timestamp).toDate();
            // In-memory filter for this year
            if (createdAt.year == now.year) {
              final m = createdAt.month - 1;
              monthlyRevenue[m] = (monthlyRevenue[m] ?? 0) + (data['totalAmount'] ?? 0).toDouble();
            }
          }
        }

        final maxRevenue = monthlyRevenue.values.fold<double>(0, (a, b) => a > b ? a : b);

        return Container(
          height: 300,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[100]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bar_chart, color: Colors.deepPurple, size: 20),
                  const SizedBox(width: 8),
                  Text("${now.year} Revenue Column Chart", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: BarChart(
                        BarChartData(
                          barTouchData: BarTouchData(enabled: false),
                          maxY: maxRevenue > 0 ? maxRevenue * 1.2 : 100,
                          barGroups: List.generate(12, (i) {
                            final isCurrent = i == now.month - 1;
                            final isPast = i < now.month - 1;
                            return BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: monthlyRevenue[i] ?? 0,
                                  width: 14,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                  color: isCurrent ? Colors.deepPurple : (isPast ? Colors.deepPurple.withOpacity(0.4) : Colors.grey[200]),
                                ),
                              ],
                            );
                          }),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                getTitlesWidget: (v, meta) {
                                  if (v == meta.max) return const SizedBox.shrink();
                                  if (v >= 1000) return Text('₹${(v / 1000).toStringAsFixed(0)}k', style: const TextStyle(fontSize: 9, color: Colors.grey));
                                  return Text('₹${v.toStringAsFixed(0)}', style: const TextStyle(fontSize: 9, color: Colors.grey));
                                },
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (v, meta) {
                                  final i = v.toInt();
                                  if (i < 0 || i >= 12) return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(monthNames[i], style: const TextStyle(fontSize: 9, color: Colors.grey)),
                                  );
                                },
                              ),
                            ),
                          ),
                          gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: maxRevenue > 0 ? maxRevenue / 4 : 25),
                          borderData: FlBorderData(show: false),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryPieChart(FirebaseFirestore firestore, String? restaurantId) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('orders').where('restaurantId', isEqualTo: restaurantId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return SizedBox(height: MediaQuery.of(context).size.width < 600 ? 280 : 350, child: const Center(child: CircularProgressIndicator()));
        Map<String, double> catRevenue = {};
        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['status'] == 'cancelled') continue;
          final items = data['items'] as List? ?? [];
          for (var it in items) {
             final cat = it['category'] ?? 'General';
             catRevenue[cat] = (catRevenue[cat] ?? 0) + ((it['price'] ?? 0) * (it['quantity'] ?? 1));
          }
        }
        double total = catRevenue.values.fold(0, (sum, v) => sum + v);
        if (total == 0) return const Center(child: Text("No data available"));

        return Container(
          height: MediaQuery.of(context).size.width < 600 ? 280 : 350,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[100]!)),
          child: Column(
            children: [
              const Text("Category Distribution (%)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              Expanded(
                child: PieChart(
                  PieChartData(
                    pieTouchData: PieTouchData(enabled: false),
                    sectionsSpace: 2,
                    centerSpaceRadius: 40,
                    sections: catRevenue.entries.map((e) {
                      final percentage = (e.value / total) * 100;
                      final index = catRevenue.keys.toList().indexOf(e.key);
                      return PieChartSectionData(
                        value: e.value, 
                        title: "${percentage.toStringAsFixed(0)}%", 
                        radius: 60, 
                        color: Colors.primaries[index % Colors.primaries.length],
                        titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                      );
                    }).toList()
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: catRevenue.keys.map((cat) {
                  final index = catRevenue.keys.toList().indexOf(cat);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 8, height: 8, color: Colors.primaries[index % Colors.primaries.length]),
                      const SizedBox(width: 4),
                      Text(cat, style: const TextStyle(fontSize: 10)),
                    ],
                  );
                }).toList(),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildWeeklyLineChart(FirebaseFirestore firestore, String? restaurantId) {
    final twelveWeeksAgo = DateTime.now().subtract(const Duration(days: 84));
    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('orders')
          .where('restaurantId', isEqualTo: restaurantId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(height: MediaQuery.of(context).size.width < 600 ? 280 : 350, child: const Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(fontSize: 10, color: Colors.red)));
        }
        
        Map<int, double> weeklyRevenue = { for (int i = 0; i < 12; i++) i: 0 };
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['status'] == 'cancelled') continue;
            if (data['createdAt'] == null) continue;
            
            final date = (data['createdAt'] as Timestamp).toDate();
            // In-memory filter for twelve weeks ago
            if (date.isBefore(twelveWeeksAgo)) continue;
            
            final daysDiff = DateTime.now().difference(date).inDays;
            final weekIndex = 11 - (daysDiff / 7).floor();
            if (weekIndex >= 0 && weekIndex < 12) {
              weeklyRevenue[weekIndex] = (weeklyRevenue[weekIndex] ?? 0) + (data['totalAmount'] ?? 0);
            }
          }
        }
        return Container(
          height: MediaQuery.of(context).size.width < 600 ? 280 : 350,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[100]!)),
          child: Column(
            children: [
              const Text("Weekly Revenue Trend", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 24),
              Expanded(
                child: LineChart(
                  LineChartData(
                    lineTouchData: LineTouchData(enabled: false),
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(
                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22)),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: weeklyRevenue.entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                        isCurved: true,
                        color: Colors.blue,
                        barWidth: 3,
                        belowBarData: BarAreaData(show: true, color: Colors.blue.withOpacity(0.1)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: color.withOpacity(0.2), thickness: 1.5)),
      ],
    );
  }

}
