import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'debug_logger.dart';

enum ReportGranularity { daily, monthly, yearly }

class ReportService {
  // In-memory guard to prevent concurrent duplicate print jobs for the same order.
  // This only prevents duplicate prints within the same app instance (process).
  static final Set<String> _printingOrderIds = <String>{};
  static const _thermalFormat = PdfPageFormat(226.77, 100 * PdfPageFormat.cm, marginAll: 6);
  static const _mm58Format = PdfPageFormat(58 * 2.8346456693, 100 * PdfPageFormat.cm, marginAll: 6);

  static pw.Widget _dash() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text('- ' * 24, style: pw.TextStyle(fontSize: 6, letterSpacing: 0)),
      );

  static pw.Widget _thickDash() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text('= ' * 24, style: pw.TextStyle(fontSize: 6, letterSpacing: 0)),
      );

  // Period report (A4)
  static Future<void> generatePeriodReport(String title, String periodInfo, List<QueryDocumentSnapshot> orders, {String restaurantName = 'ShreeRajmandir'}) async {
    final pdf = pw.Document();
    final theme = pw.ThemeData();
    final total = orders.fold<double>(0, (sum, doc) => sum + (doc['totalAmount'] ?? 0));

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      build: (pw.Context context) {
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Header(level: 0, child: pw.Text('$restaurantName - $title')),
          pw.SizedBox(height: 10),
          pw.Text(periodInfo),
          pw.Text('Total Orders: ${orders.length}'),
          pw.Text('Total Net Revenue: INR ${total.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
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
        ]);
      },
    ));

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  // KOT / order / final bill shims that delegate to printReceipt58
  static Future<void> printKOTReceipt(Map<String, dynamic> data, String orderId) async => await printKOT(data, orderId);

  static Future<void> printKOT(Map<String, dynamic> data, String orderId) async {
    DebugLogger.logEvent(event: 'printKOT_enter', data: {'orderId': orderId});
    await printReceipt58(orderData: data, orderId: orderId, isKOT: true);
    DebugLogger.logEvent(event: 'printKOT_complete', data: {'orderId': orderId});
  }

  static Future<void> printOrderReceipt(Map<String, dynamic> data, String orderId, {String restaurantName = 'ShreeRajmandir'}) async {
    await printReceipt58(orderData: data, orderId: orderId, restaurantName: restaurantName);
  }

  static Future<void> printFinalBill({
    required Map<String, dynamic> orderData,
    required String orderId,
    required double subtotal,
    required double cgst,
    required double sgst,
    required double total,
    required String paymentMode,
    String hotelName = 'ShreeRajmandir',
    String address = 'Adarsh Colony, Ausa Rd, Latur, Maharashtra 413512',
    String gstin = 'GSTIN: 27AAAAA0000A1Z5',
  }) async {
    await printReceipt58(orderData: orderData, orderId: orderId, totalOverride: total, paymentMode: paymentMode, restaurantName: hotelName);
  }

  static Future<void> generateOperationalReport({
    required String title,
    required String periodLabel,
    required DateTime start,
    required DateTime end,
    required String restaurantId,
    required ReportGranularity granularity,
    required String restaurantName,
  }) async {
    final query = FirebaseFirestore.instance
        .collection('orders')
        .where('restaurantId', isEqualTo: restaurantId)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end));

    final snapshot = await query.get();
    await generatePeriodReport(title, periodLabel, snapshot.docs, restaurantName: restaurantName);
  }

  // Receipt numbering helpers
  static String _formatReceiptNumber(int count) => 'B' + count.toString().padLeft(3, '0');

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static Future<String> ensureReceiptNumberForOrder(String orderId) async {
    final firestore = FirebaseFirestore.instance;
    final orderRef = firestore.collection('orders').doc(orderId);

    final receipt = await firestore.runTransaction((tx) async {
      final orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) throw Exception('Order document not found: $orderId');

      final existing = orderSnap.data()?['receiptNumber'];
      if (existing != null && existing.toString().trim().isNotEmpty) return existing.toString();

      final todayId = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final counterRef = firestore.collection('daily_counters').doc(todayId);
      final counterSnap = await tx.get(counterRef);

      int next = 1;
      if (counterSnap.exists) {
        final current = _toInt(counterSnap.data()?['count']);
        next = current + 1;
        tx.update(counterRef, {'count': next});
      } else {
        tx.set(counterRef, {'count': 1});
        next = 1;
      }

      final receiptStr = _formatReceiptNumber(next);
      tx.update(orderRef, {'receiptNumber': receiptStr});
      return receiptStr;
    });

    return receipt;
  }

  // PDF font availability flag. Set when we successfully load embedded fonts.
  static bool _pdfFontAvailable = false;

  // Formatting helpers
  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static String _formatStewardNameLocal(String? raw) {
    if (raw == null) return '';
    final cleaned = raw.replaceAll(RegExp(r'\s+'), '');
    final up = cleaned.toUpperCase();
    return up.length > 5 ? up.substring(0, 5) : up;
  }

  static String _formatDateForPrint(DateTime d) => DateFormat('dd-MMM-yyyy HH:mm').format(d);

  static String _formatAmountNoSymbol(double v) {
    if ((v - v.truncate()).abs() < 0.0001) return v.truncate().toString();
    return v.toStringAsFixed(2);
  }

  static String _formatAmount(double v) => (_pdfFontAvailable ? '₹' : 'Rs ') + _formatAmountNoSymbol(v);

  // Unified 58mm renderer
  static Future<void> printReceipt58({
    required Map<String, dynamic> orderData,
    required String orderId,
    bool isKOT = false,
    double? totalOverride,
    String? paymentMode,
    String? restaurantName,
  }) async {
    // Prevent duplicate concurrent prints for the same order within this app process.
    if (_printingOrderIds.contains(orderId)) {
      DebugLogger.logEvent(event: 'printReceipt58_skipped_duplicate', data: {'orderId': orderId});
      return;
    }
    _printingOrderIds.add(orderId);
    try {
      final itemsRaw = orderData['items'];
      final itemsList = (itemsRaw is List) ? itemsRaw : <dynamic>[];

      String receiptNumber = orderData['receiptNumber']?.toString() ?? '';
      if (receiptNumber.isEmpty) {
        try {
          receiptNumber = await ensureReceiptNumberForOrder(orderId);
        } catch (e) {
          receiptNumber = orderId.length >= 6 ? orderId.substring(0, 6) : orderId;
        }
      }

      final date = (orderData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      final dateStr = _formatDateForPrint(date);
      final steward = _formatStewardNameLocal(orderData['printerName']?.toString() ?? orderData['waiterName']?.toString() ?? orderData['steward']?.toString());
      final table = orderData['tableName']?.toString() ?? '';

      Uint8List? logoBytes;
      try {
        final logoFile = File(r'C:\Users\anike\Downloads\ShreeRajmandir\assets\branding\splash_logo.png');
        if (logoFile.existsSync()) logoBytes = logoFile.readAsBytesSync();
      } catch (_) {
        logoBytes = null;
      }

      // Attempt to load Noto Sans fonts from assets for rupee glyph support.
      pw.ThemeData theme;
      try {
        ByteData regBd;
        ByteData boldBd;
        try {
          // Preferred: load via rootBundle (works in Flutter runtime)
          regBd = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
          boldBd = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
        } catch (_) {
          // Fallback: read from filesystem (works for Dart CLI preview generator)
          final regBytes = File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync();
          final boldBytes = File('assets/fonts/NotoSans-Bold.ttf').readAsBytesSync();
          regBd = ByteData.view(regBytes.buffer);
          boldBd = ByteData.view(boldBytes.buffer);
        }

        final baseFont = pw.Font.ttf(regBd);
        final boldFont = pw.Font.ttf(boldBd);
        theme = pw.ThemeData.withFont(base: baseFont, bold: boldFont);
        _pdfFontAvailable = true;
      } catch (e) {
        DebugLogger.logEvent(event: 'printReceipt58_font_load_failed', data: {'error': e.toString()});
        theme = pw.ThemeData();
        _pdfFontAvailable = false;
      }

      final pdf = pw.Document();

      const int maxItemChars = 20;
      const double qtyWidth = 18;
      const double amtWidth = 36;

      pdf.addPage(pw.MultiPage(
        pageFormat: _mm58Format,
        theme: theme,
        margin: const pw.EdgeInsets.all(6),
        build: (pw.Context ctx) => [
          if (logoBytes != null) pw.Center(child: pw.Image(pw.MemoryImage(logoBytes), width: (_mm58Format.width - 12) * 0.6)),
          pw.SizedBox(height: 4),
          pw.Center(child: pw.Text('7947151577', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 6),

          pw.Text('Bill No: $receiptNumber', style: const pw.TextStyle(fontSize: 8)),
          pw.Text('Date: $dateStr', style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 4),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Table: $table', style: const pw.TextStyle(fontSize: 8)), pw.Text(steward, style: const pw.TextStyle(fontSize: 8))]),
          pw.SizedBox(height: 6),
          pw.Divider(),

          ...itemsList.map((rawItem) {
            final item = (rawItem is Map) ? Map<String, dynamic>.from(rawItem) : <String, dynamic>{};
            final qty = _toInt(item['quantity'] ?? item['qty']).toString();
            final category = (item['category'] ?? item['cat'])?.toString() ?? '';
            final name = (item['name'] ?? item['itemName'] ?? '').toString();
            final left = (category.isNotEmpty) ? '${category.trim()}-${name.trim()}' : name.trim();
            var leftSafe = left.replaceAll(RegExp(r'\s+'), ' ');
            if (leftSafe.length > maxItemChars) leftSafe = leftSafe.substring(0, maxItemChars);
            final price = _toDouble(item['price']);
            final lineAmount = price * _toDouble(item['quantity'] ?? item['qty'] ?? 0);

            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1),
              child: pw.Row(children: [
                pw.Expanded(child: pw.Text(leftSafe, style: const pw.TextStyle(fontSize: 8), maxLines: 1, overflow: pw.TextOverflow.clip)),
                pw.SizedBox(width: qtyWidth, child: pw.Text(qty, style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right)),
                pw.SizedBox(width: amtWidth, child: pw.Text(_formatAmount(lineAmount), style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right)),
              ]),
            );
          }).toList(),

          pw.SizedBox(height: 6),
          pw.Divider(),

          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('TOTAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)), pw.Text(_formatAmount(totalOverride ?? itemsList.fold<double>(0.0, (s, it) { final m = (it is Map) ? it : <String,dynamic>{}; return s + (_toDouble((m as Map)['price']) * _toDouble((m)['quantity'] ?? (m)['qty'] ?? 0)); })), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))]),

          pw.Divider(),

          if (!isKOT) ...[
            pw.SizedBox(height: 6),
            pw.Center(child: pw.Text('Thank You Visit Again', style: const pw.TextStyle(fontSize: 8))),
            pw.Center(child: pw.Text('@rajmandir_icecream_latur', style: const pw.TextStyle(fontSize: 8))),
            pw.Center(child: pw.Text('ShreeRajmandir POS', style: const pw.TextStyle(fontSize: 7))),
            pw.SizedBox(height: 6),
          ],
        ],
      ));

      DebugLogger.logEvent(event: 'printReceipt58_before_layout', data: {'orderId': orderId, 'receiptNumber': receiptNumber, 'isKOT': isKOT});
      await Printing.layoutPdf(onLayout: (_) async => pdf.save(), format: _mm58Format);
      DebugLogger.logEvent(event: 'printReceipt58_complete', data: {'orderId': orderId, 'receiptNumber': receiptNumber, 'isKOT': isKOT});
    } finally {
      _printingOrderIds.remove(orderId);
    }
  }

  static pw.Widget _amountRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(label, style: const pw.TextStyle(fontSize: 8)), pw.Text(value, style: const pw.TextStyle(fontSize: 8))]),
      );
}
