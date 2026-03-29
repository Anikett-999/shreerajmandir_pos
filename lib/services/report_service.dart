import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum ReportGranularity { daily, monthly, yearly }

class ReportService {
  // ── Shared thermal page format: 80 mm wide, auto height ──────────────────
  static const _thermalFormat = PdfPageFormat(
    226.77, // 80 mm in points (1 pt = 0.352 mm)
    100 * PdfPageFormat.cm, // 1 meter max height per page (standard for rolls)
    marginAll: 6,
  );

  // Light dashed separator
  static pw.Widget _dash() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text(
          '- ' * 24,
          style: pw.TextStyle(fontSize: 6, letterSpacing: 0),
        ),
      );

  // Heavy "=" separator
  static pw.Widget _thickDash() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text(
          '= ' * 24,
          style: pw.TextStyle(fontSize: 6, letterSpacing: 0),
        ),
      );

  // ── DAILY COLLECTION REPORT (A4) ─────────────────────────────────────────
  static Future<void> generateDailyCollectionReport(
      DateTime date, List<QueryDocumentSnapshot> orders, {String restaurantName = "ShreeRajmandir"}) async {
    final dateStr = DateFormat('dd MMM yyyy').format(date);
    await generatePeriodReport("Daily Collection Report", "Date: $dateStr", orders, restaurantName: restaurantName);
  }

  // ── OPERATIONAL BUSINESS REPORT (A4) ─────────────────────────────────────
  static Future<void> generateOperationalReport({
    required String title,
    required String periodLabel,
    required DateTime start,
    required DateTime end,
    required String restaurantId,
    required ReportGranularity granularity,
    String restaurantName = "ShreeRajmandir",
  }) async {
    final firestore = FirebaseFirestore.instance;

    final totalStopwatch = Stopwatch()..start();
    final queryStopwatch = Stopwatch()..start();

    final currentOrdersQuery = firestore
        .collection('orders')
        .where('restaurantId', isEqualTo: restaurantId)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end));

    final previousRange = _previousRange(start: start, end: end, granularity: granularity);
    final prevStart = previousRange.$1;
    final prevEnd = previousRange.$2;
    final previousOrdersQuery = firestore
        .collection('orders')
        .where('restaurantId', isEqualTo: restaurantId)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(prevStart))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(prevEnd));

    final tablesQuery = firestore
        .collection('tables')
        .where('restaurantId', isEqualTo: restaurantId);

    final periodKotsQuery = firestore
        .collection('kots')
        .where('restaurantId', isEqualTo: restaurantId)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end));

    final results = await Future.wait<dynamic>([
      currentOrdersQuery.get().timeout(const Duration(seconds: 25)),
      previousOrdersQuery.get().timeout(const Duration(seconds: 25)),
      tablesQuery.count().get().timeout(const Duration(seconds: 15)),
      periodKotsQuery
          .where('status', whereIn: ['Pending', 'Preparing', 'pending', 'preparing'])
          .count()
          .get()
          .timeout(const Duration(seconds: 15)),
      periodKotsQuery
          .where('status', whereIn: ['Completed', 'Served', 'completed', 'served'])
          .count()
          .get()
          .timeout(const Duration(seconds: 15)),
    ]);

    queryStopwatch.stop();

    final currentOrdersSnap = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final previousOrdersSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final tablesAgg = results[2] as AggregateQuerySnapshot;
    final pendingKotsAgg = results[3] as AggregateQuerySnapshot;
    final completedKotsAgg = results[4] as AggregateQuerySnapshot;

    final currentExtracted = _extractOrderFacts(currentOrdersSnap.docs, 'current-period');
    final previousExtracted = _extractOrderFacts(previousOrdersSnap.docs, 'previous-period');
    final currentOrders = currentExtracted.facts;
    final previousOrders = previousExtracted.facts;

    if (currentExtracted.missingTableNameCount > 0 || currentExtracted.invalidTimestampCount > 0) {
      debugPrint(
        'Reports anomaly[current]: missingTableName=${currentExtracted.missingTableNameCount}, invalidTimestamp=${currentExtracted.invalidTimestampCount}',
      );
    }
    if (previousExtracted.invalidTimestampCount > 0) {
      debugPrint('Reports anomaly[previous]: invalidTimestamp=${previousExtracted.invalidTimestampCount}');
    }

    final summary = _buildSummary(currentOrders);
    final previousSummary = _buildSummary(previousOrders);

    final totalTables = tablesAgg.count ?? 0;
    final occupancyRate = _calculatePeriodOccupancyRate(currentOrders, totalTables);

    final pendingKots = pendingKotsAgg.count ?? 0;
    final completedKots = completedKotsAgg.count ?? 0;

    final breakdown = _buildBreakdown(currentOrders, granularity, start);
    final insights = _buildInsights(
      current: summary,
      previous: previousSummary,
      occupancyRate: occupancyRate,
      pendingKots: pendingKots,
      completedKots: completedKots,
      granularity: granularity,
    );

    final pdf = pw.Document();
    final roboto = await PdfGoogleFonts.robotoRegular();
    final robotoBold = await PdfGoogleFonts.robotoBold();
    final theme = pw.ThemeData.withFont(base: roboto, bold: robotoBold);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        margin: const pw.EdgeInsets.all(28),
        build: (context) {
          return [
            pw.Text(
              restaurantName,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18),
            ),
            pw.SizedBox(height: 2),
            pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15)),
            pw.Text(periodLabel, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 14),

            _sectionTitle("1) Summary"),
            pw.SizedBox(height: 8),
            pw.Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _metricBox("Total Sales", "INR ${summary.totalSales.toStringAsFixed(2)}"),
                _metricBox("Total Orders", summary.totalOrders.toString()),
                _metricBox("Cancelled Orders", summary.cancelledOrders.toString()),
                _metricBox("Peak Hour", summary.peakHourLabel),
                _metricBox("Table Occupancy (Period)", "${occupancyRate.toStringAsFixed(1)}%"),
                _metricBox("Pending KOTs", pendingKots.toString()),
              ],
            ),
            pw.SizedBox(height: 16),

            _sectionTitle("2) Insights"),
            pw.SizedBox(height: 6),
            if (insights.isEmpty)
              pw.Text("No major insights available for this period.", style: const pw.TextStyle(fontSize: 10))
            else
              ...insights.map(_insightBullet),
            pw.SizedBox(height: 16),

            _sectionTitle("3) Breakdown"),
            pw.SizedBox(height: 8),
            if (breakdown.rows.isEmpty)
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(
                  "No data found for the selected period.",
                  style: const pw.TextStyle(fontSize: 10),
                ),
              )
            else
              pw.TableHelper.fromTextArray(
                context: context,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignment: pw.Alignment.centerLeft,
                headers: breakdown.headers,
                data: breakdown.rows,
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
              ),
            pw.SizedBox(height: 14),

            _sectionTitle("4) Operational Snapshot"),
            pw.SizedBox(height: 6),
            pw.Text(
              "Billed: ${summary.billedOrders} | Cancelled: ${summary.cancelledOrders} | KOT Completed: $completedKots | KOT Pending: $pendingKots",
              style: const pw.TextStyle(fontSize: 10),
            ),
          ];
        },
      ),
    );

    totalStopwatch.stop();
    debugPrint(
      'Reports performance: queryMs=${queryStopwatch.elapsedMilliseconds}, totalMs=${totalStopwatch.elapsedMilliseconds}, currentOrders=${currentOrders.length}, previousOrders=${previousOrders.length}',
    );

    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  // ── GENERAL PERIOD REPORT (A4) ───────────────────────────────────────────
  static Future<void> generatePeriodReport(
      String title, String periodInfo, List<QueryDocumentSnapshot> orders, {String restaurantName = "ShreeRajmandir"}) async {
    final pdf = pw.Document();
    final total =
        orders.fold<double>(0, (sum, doc) => sum + (doc['totalAmount'] ?? 0));

    final roboto = await PdfGoogleFonts.robotoRegular();
    final robotoBold = await PdfGoogleFonts.robotoBold();
    final theme = pw.ThemeData.withFont(base: roboto, bold: robotoBold);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                  level: 0,
                  child: pw.Text("$restaurantName - $title")),
              pw.SizedBox(height: 10),
              pw.Text(periodInfo),
              pw.Text("Total Orders: ${orders.length}"),
              pw.Text(
                  "Total Net Revenue: INR ${total.toStringAsFixed(2)}",
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 18)),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                context: context,
                data: <List<String>>[
                  <String>['Order ID', 'Date', 'Table', 'Waiter', 'Amount', 'Status'],
                  ...orders.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                    return [
                      doc.id.substring(0, 8),
                      DateFormat('dd-MM-yy').format(createdAt),
                      data['tableName'].toString(),
                      data['waiterName'].toString(),
                      data['totalAmount'].toString(),
                      data['status'].toString().toUpperCase(),
                    ];
                  })
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save());
  }

  static _SummaryData _buildSummary(List<_OrderFact> orders) {
    double totalSales = 0;
    int billedOrders = 0;
    int cancelledOrders = 0;
    final hourlyOrderCount = <int, int>{};

    for (final order in orders) {
      if (order.status == 'cancelled') {
        cancelledOrders++;
      } else {
        totalSales += order.amount;
        if (order.status == 'billed') billedOrders++;
        if (order.createdAt != null) {
          final hour = order.createdAt!.hour;
          hourlyOrderCount[hour] = (hourlyOrderCount[hour] ?? 0) + 1;
        }
      }
    }

    int peakHour = 0;
    int peakCount = 0;
    hourlyOrderCount.forEach((hour, count) {
      if (count > peakCount) {
        peakCount = count;
        peakHour = hour;
      }
    });

    final peakLabel = peakCount == 0 ? "N/A" : "${peakHour.toString().padLeft(2, '0')}:00-${(peakHour + 1).toString().padLeft(2, '0')}:00";

    return _SummaryData(
      totalSales: totalSales,
      totalOrders: orders.length,
      billedOrders: billedOrders,
      cancelledOrders: cancelledOrders,
      peakHourLabel: peakLabel,
    );
  }

  static _BreakdownData _buildBreakdown(List<_OrderFact> orders, ReportGranularity granularity, DateTime periodStart) {
    if (granularity == ReportGranularity.daily) {
      final hourly = <int, _Bucket>{for (int i = 0; i < 24; i++) i: _Bucket()};
      for (final order in orders) {
        final createdAt = order.createdAt;
        if (createdAt == null) continue;
        final hour = createdAt.hour;
        final b = hourly[hour]!;
        b.orders += 1;
        if (order.status == 'cancelled') {
          b.cancelled += 1;
        } else {
          b.sales += order.amount;
        }
      }

      return _BreakdownData(
        headers: const ["Hour", "Orders", "Cancelled", "Sales (INR)"],
        rows: hourly.entries
            .where((e) => e.value.orders > 0)
            .map((e) => [
                  "${e.key.toString().padLeft(2, '0')}:00",
                  e.value.orders.toString(),
                  e.value.cancelled.toString(),
                  e.value.sales.toStringAsFixed(2),
                ])
            .toList(),
      );
    }

    if (granularity == ReportGranularity.monthly) {
      final weekly = <int, _Bucket>{for (int i = 1; i <= 5; i++) i: _Bucket()};
      for (final order in orders) {
        final createdAt = order.createdAt;
        if (createdAt == null) continue;
        final week = ((createdAt.day - 1) / 7).floor() + 1;
        final safeWeek = week > 5 ? 5 : week;
        final b = weekly[safeWeek]!;
        b.orders += 1;
        if (order.status == 'cancelled') {
          b.cancelled += 1;
        } else {
          b.sales += order.amount;
        }
      }

      return _BreakdownData(
        headers: const ["Week", "Orders", "Cancelled", "Sales (INR)"],
        rows: weekly.entries
            .where((e) => e.value.orders > 0)
            .map((e) => [
                  "Week ${e.key}",
                  e.value.orders.toString(),
                  e.value.cancelled.toString(),
                  e.value.sales.toStringAsFixed(2),
                ])
            .toList(),
      );
    }

    final monthly = <int, _Bucket>{for (int i = 1; i <= 12; i++) i: _Bucket()};
    for (final order in orders) {
      final createdAt = order.createdAt;
      if (createdAt == null) continue;
      final month = createdAt.month;
      final b = monthly[month]!;
      b.orders += 1;
      if (order.status == 'cancelled') {
        b.cancelled += 1;
      } else {
        b.sales += order.amount;
      }
    }

    return _BreakdownData(
      headers: const ["Month", "Orders", "Cancelled", "Sales (INR)"],
      rows: monthly.entries
          .where((e) => e.value.orders > 0)
          .map((e) => [
                DateFormat('MMM').format(DateTime(periodStart.year, e.key)),
                e.value.orders.toString(),
                e.value.cancelled.toString(),
                e.value.sales.toStringAsFixed(2),
              ])
          .toList(),
    );
  }

  static List<String> _buildInsights({
    required _SummaryData current,
    required _SummaryData previous,
    required double occupancyRate,
    required int pendingKots,
    required int completedKots,
    required ReportGranularity granularity,
  }) {
    final insights = <String>[];

    if (previous.totalSales > 0) {
      final delta = ((current.totalSales - previous.totalSales) / previous.totalSales) * 100;
      if (delta >= 0) {
        insights.add("Sales increased by ${delta.toStringAsFixed(1)}% compared to the previous period.");
      } else {
        insights.add("Sales decreased by ${delta.abs().toStringAsFixed(1)}% compared to the previous period.");
      }
    }

    if (current.peakHourLabel != "N/A") {
      insights.add("Best performing time slot was ${current.peakHourLabel} based on order volume.");
    }

    final cancelRate = current.totalOrders > 0 ? (current.cancelledOrders / current.totalOrders) * 100 : 0.0;
    if (cancelRate >= 15) {
      insights.add("Cancellation rate is high at ${cancelRate.toStringAsFixed(1)}%; review order handling or stock availability.");
    } else {
      insights.add("Cancellation rate is controlled at ${cancelRate.toStringAsFixed(1)}%.");
    }

    if (occupancyRate < 35) {
      insights.add("Table occupancy is low (${occupancyRate.toStringAsFixed(1)}%), indicating underutilized seating capacity.");
    } else if (occupancyRate > 80) {
      insights.add("Table occupancy is high (${occupancyRate.toStringAsFixed(1)}%); consider throughput optimization.");
    }

    final totalKotConsidered = pendingKots + completedKots;
    if (totalKotConsidered > 0) {
      final pendingRate = (pendingKots / totalKotConsidered) * 100;
      if (pendingRate > 35) {
        insights.add("Pending KOT share is ${pendingRate.toStringAsFixed(1)}%, suggesting kitchen backlog.");
      }
    }

    if (granularity == ReportGranularity.daily) {
      insights.add("Daily breakdown highlights hourly sales and cancellation concentration.");
    } else if (granularity == ReportGranularity.monthly) {
      insights.add("Weekly breakdown shows how performance shifts across the month.");
    } else {
      insights.add("Monthly breakdown highlights seasonal movement through the year.");
    }

    return insights;
  }

  static (DateTime, DateTime) _previousRange({
    required DateTime start,
    required DateTime end,
    required ReportGranularity granularity,
  }) {
    if (granularity == ReportGranularity.monthly) {
      final prevMonthStart = DateTime(start.year, start.month - 1, 1);
      final prevMonthEnd = DateTime(start.year, start.month, 1).subtract(const Duration(seconds: 1));
      return (prevMonthStart, prevMonthEnd);
    }
    if (granularity == ReportGranularity.yearly) {
      final prevYearStart = DateTime(start.year - 1, 1, 1);
      final prevYearEnd = DateTime(start.year, 1, 1).subtract(const Duration(seconds: 1));
      return (prevYearStart, prevYearEnd);
    }

    final periodDuration = end.difference(start);
    final prevEnd = start.subtract(const Duration(seconds: 1));
    final prevStart = prevEnd.subtract(periodDuration);
    return (prevStart, prevEnd);
  }

  static _ExtractedOrders _extractOrderFacts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String source,
  ) {
    final facts = <_OrderFact>[];
    var missingTableNameCount = 0;
    var invalidTimestampCount = 0;

    for (final doc in docs) {
      final data = doc.data();
      final createdAt = _asDateTime(data['createdAt']);
      if (data['createdAt'] != null && createdAt == null) {
        invalidTimestampCount++;
      }

      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      final tableName = (data['tableName'] ?? '').toString().trim();
      if (tableName.isEmpty) {
        missingTableNameCount++;
      }

      facts.add(
        _OrderFact(
          id: doc.id,
          status: status,
          amount: _toDouble(data['totalAmount']),
          tableName: tableName,
          createdAt: createdAt,
          source: source,
        ),
      );
    }

    return _ExtractedOrders(
      facts: facts,
      missingTableNameCount: missingTableNameCount,
      invalidTimestampCount: invalidTimestampCount,
    );
  }

  static DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static double _calculatePeriodOccupancyRate(List<_OrderFact> orders, int totalTables) {
    if (totalTables <= 0) return 0.0;
    final usedTables = <String>{};
    for (final order in orders) {
      if (order.status == 'cancelled') continue;
      final tableName = order.tableName;
      if (tableName.isNotEmpty) {
        usedTables.add(tableName);
      }
    }
    return (usedTables.length / totalTables) * 100;
  }

  static double _toDouble(dynamic value) {
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static pw.Widget _sectionTitle(String title) => pw.Text(
        title,
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
      );

  static pw.Widget _metricBox(String label, String value) {
    return pw.Container(
      width: 160,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }

  static pw.Widget _insightBullet(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text("• ", style: const pw.TextStyle(fontSize: 11)),
          pw.Expanded(child: pw.Text(text, style: const pw.TextStyle(fontSize: 10))),
        ],
      ),
    );
  }

  // ── KOT RECEIPT ─────────────────────────────────────────────────────────
  static Future<void> printKOTReceipt(
      Map<String, dynamic> data, String orderId) async {
    final pdf = pw.Document();
    final items = data['items'] as List;

    final roboto = await PdfGoogleFonts.robotoRegular();
    final robotoBold = await PdfGoogleFonts.robotoBold();
    final theme = pw.ThemeData.withFont(base: roboto, bold: robotoBold);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: _thermalFormat,
        margin: const pw.EdgeInsets.all(6),
        theme: theme,
        build: (pw.Context context) => [
          pw.Center(
            child: pw.Text("KOT",
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 22)),
          ),
          _thickDash(),
          pw.Text("TABLE: ${data['tableName']}",
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 16)),
          pw.Text("Order #: ${orderId.substring(0, 8)}",
              style: const pw.TextStyle(fontSize: 8)),
          _thickDash(),
          ...items.map((item) {
            final quantity = (item['quantity'] ?? 0).toInt();
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text("${quantity}x  ${item['name']}",
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
            );
          }),
          _thickDash(),
          pw.Center(
            child: pw.Text(
                DateFormat('dd MMM yyyy  hh:mm a').format(DateTime.now()),
                style: const pw.TextStyle(fontSize: 7)),
          ),
          pw.SizedBox(height: 8),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      format: _thermalFormat,
    );
  }

  // ── ORDER RECEIPT (waiter copy) ──────────────────────────────────────────
  static Future<void> printOrderReceipt(
      Map<String, dynamic> data, String orderId, {String restaurantName = "ShreeRajmandir"}) async {
    final pdf = pw.Document();
    final items = data['items'] as List;
    final date =
        (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(date);

    final roboto = await PdfGoogleFonts.robotoRegular();
    final robotoBold = await PdfGoogleFonts.robotoBold();
    final theme = pw.ThemeData.withFont(base: roboto, bold: robotoBold);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: _thermalFormat,
        margin: const pw.EdgeInsets.all(6),
        theme: theme,
        build: (pw.Context context) => [
          pw.Center(
              child: pw.Text(restaurantName,
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 14))),
          pw.Center(
              child: pw.Text("RESTAURANT RECEIPT",
                  style: const pw.TextStyle(fontSize: 8))),
          _thickDash(),
          pw.Text("Order #: ${orderId.substring(0, 8)}",
              style: const pw.TextStyle(fontSize: 8)),
          pw.Text("Table: ${data['tableName']}",
              style:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.Text("Waiter: ${data['waiterName']}",
              style: const pw.TextStyle(fontSize: 8)),
          pw.Text("Date: $dateStr", style: const pw.TextStyle(fontSize: 8)),
          _dash(),
          pw.Row(children: [
            pw.Expanded(
                child: pw.Text("Item",
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 8))),
            pw.Text("Amt",
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 8)),
          ]),
          _dash(),
          ...items.map((item) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                        child: pw.Text(
                            "${item['quantity']}x ${item['name']}",
                            style: const pw.TextStyle(fontSize: 8))),
                    pw.Text(
                        "₹${(item['price'] * item['quantity']).toStringAsFixed(2)}",
                        style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              )),
          _thickDash(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text("GRAND TOTAL",
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.Text("₹${data['totalAmount']}",
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 11)),
            ],
          ),
          _thickDash(),
          pw.SizedBox(height: 4),
          pw.Center(
              child: pw.Text("Thank you for dining with us!",
                  style: pw.TextStyle(
                      fontStyle: pw.FontStyle.italic, fontSize: 7))),
          pw.SizedBox(height: 8),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      format: _thermalFormat,
    );
  }

  // ── FINAL BILL ───────────────────────────────────────────────────────────
  static Future<void> printFinalBill({
    required Map<String, dynamic> orderData,
    required String orderId,
    required double subtotal,
    required double cgst,
    required double sgst,
    required double total,
    required String paymentMode,
    String hotelName = "ShreeRajmandir",
    String address = "Adarsh Colony, Ausa Rd, Latur, Maharashtra 413512",
    String gstin = "GSTIN: 27AAAAA0000A1Z5",
  }) async {
    final pdf = pw.Document();
    final items = orderData['items'] as List;
    final date = DateTime.now();
    final dateStr = DateFormat('dd-MM-yyyy  hh:mm a').format(date);

    final roboto = await PdfGoogleFonts.robotoRegular();
    final robotoBold = await PdfGoogleFonts.robotoBold();
    final theme = pw.ThemeData.withFont(base: roboto, bold: robotoBold);

    final receiptNum =
        orderData['receiptNumber'] ?? orderId.substring(0, 6);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: _thermalFormat,
        margin: const pw.EdgeInsets.all(6),
        theme: theme,
        build: (pw.Context context) => [
          // ── Header ─────────────────────────────────────────
          pw.Center(
              child: pw.Text(hotelName,
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 13))),
          pw.Center(
              child: pw.Text(address,
                  style: const pw.TextStyle(fontSize: 7))),
          pw.Center(
              child:
                  pw.Text(gstin, style: const pw.TextStyle(fontSize: 7))),
          _thickDash(),
          pw.Center(
              child: pw.Text("TAX INVOICE",
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 9))),
          _dash(),
          pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Bill #: $receiptNum",
                    style: const pw.TextStyle(fontSize: 8)),
                pw.Text("Table: ${orderData['tableName']}",
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 9)),
              ]),
          pw.Text("Date: $dateStr",
              style: const pw.TextStyle(fontSize: 7)),
          pw.Text("Waiter: ${orderData['waiterName']}",
              style: const pw.TextStyle(fontSize: 7)),
          _dash(),

          // ── Column headers ──────────────────────────────────
          pw.Row(children: [
            pw.Expanded(
                child: pw.Text("Item",
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 8))),
            pw.SizedBox(
                width: 14,
                child: pw.Text("Qty",
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 8))),
            pw.SizedBox(
                width: 28,
                child: pw.Text("Rate",
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 8),
                    textAlign: pw.TextAlign.right)),
            pw.SizedBox(
                width: 34,
                child: pw.Text("Amt",
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 8),
                    textAlign: pw.TextAlign.right)),
          ]),
          _dash(),

          // ── Items ───────────────────────────────────────────
          ...items.map((item) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                child: pw.Row(children: [
                  pw.Expanded(
                      child: pw.Text(item['name'],
                          style: const pw.TextStyle(fontSize: 8))),
                  pw.SizedBox(
                      width: 14,
                      child: pw.Text("${item['quantity']}",
                          style: const pw.TextStyle(fontSize: 8))),
                  pw.SizedBox(
                      width: 28,
                      child: pw.Text("${item['price']}",
                          style: const pw.TextStyle(fontSize: 8),
                          textAlign: pw.TextAlign.right)),
                  pw.SizedBox(
                      width: 34,
                      child: pw.Text(
                          "₹${(item['price'] * item['quantity']).toStringAsFixed(2)}",
                          style: const pw.TextStyle(fontSize: 8),
                          textAlign: pw.TextAlign.right)),
                ]),
              )),
          _dash(),

          // ── Totals ──────────────────────────────────────────
          _amountRow("Subtotal", "₹${subtotal.toStringAsFixed(2)}"),
          _amountRow("CGST (2.5%)", "₹${cgst.toStringAsFixed(2)}"),
          _amountRow("SGST (2.5%)", "₹${sgst.toStringAsFixed(2)}"),
          _thickDash(),
          pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("GRAND TOTAL",
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.Text("₹${total.toStringAsFixed(2)}",
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 12)),
              ]),
          _thickDash(),

          // ── Footer ──────────────────────────────────────────
          pw.Text("Payment: $paymentMode",
              style:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
          pw.SizedBox(height: 6),
          pw.Center(
              child: pw.Text("Thank you! Visit Again",
                  style: pw.TextStyle(
                      fontStyle: pw.FontStyle.italic, fontSize: 7))),
          pw.Center(
              child: pw.Text("Powered by ShreeRajmandir",
                  style: const pw.TextStyle(fontSize: 6))),
          pw.SizedBox(height: 10),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      format: _thermalFormat,
    );
  }

  // ── Helper: amount row ───────────────────────────────────────────────────
  static pw.Widget _amountRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
            pw.Text(value, style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      );
}

class _SummaryData {
  final double totalSales;
  final int totalOrders;
  final int billedOrders;
  final int cancelledOrders;
  final String peakHourLabel;

  const _SummaryData({
    required this.totalSales,
    required this.totalOrders,
    required this.billedOrders,
    required this.cancelledOrders,
    required this.peakHourLabel,
  });
}

class _OrderFact {
  final String id;
  final String status;
  final double amount;
  final String tableName;
  final DateTime? createdAt;
  final String source;

  const _OrderFact({
    required this.id,
    required this.status,
    required this.amount,
    required this.tableName,
    required this.createdAt,
    required this.source,
  });
}

class _ExtractedOrders {
  final List<_OrderFact> facts;
  final int missingTableNameCount;
  final int invalidTimestampCount;

  const _ExtractedOrders({
    required this.facts,
    required this.missingTableNameCount,
    required this.invalidTimestampCount,
  });
}

class _BreakdownData {
  final List<String> headers;
  final List<List<String>> rows;

  const _BreakdownData({required this.headers, required this.rows});
}

class _Bucket {
  int orders = 0;
  int cancelled = 0;
  double sales = 0;
}
