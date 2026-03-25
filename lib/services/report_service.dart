import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
