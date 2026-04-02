import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

// Generates a sample KOT PDF and writes to build/kot_preview.pdf
// Run: dart run tools/generate_kot_preview.dart

void main() async {
  final outputPath = 'build/kot_preview.pdf';
  final doc = pw.Document();

  // Sample data per your request
  final data = {
    'tableName': '1',
    'waiterName': 'ANIKE',
    'createdAt': DateTime.now(),
    'items': [
      {'category': 'Scoops', 'name': 'Vanilla', 'quantity': 2},
      {'category': 'Cone', 'name': 'Chocolate', 'quantity': 1},
      {'category': 'Drinks', 'name': 'Mango Juice', 'quantity': 1},
    ],
  };

  // 58 mm in points
  final pageWidth = 58 * 2.8346456693;
  final pageFormat = PdfPageFormat(pageWidth, 100 * PdfPageFormat.cm, marginAll: 6);

  String formatSteward(String raw) {
    final t = raw.trim();
    if (t.length > 5) return t.substring(0, 5).toUpperCase();
    return t.toUpperCase();
  }

  final steward = formatSteward(data['waiterName']?.toString() ?? '');
  final date = data['createdAt'] as DateTime;
  final dateStr = DateFormat('dd-MMM-yyyy HH:mm:ss').format(date);

  doc.addPage(
    pw.MultiPage(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.all(6),
      build: (ctx) => [
        pw.Center(
            child: pw.Text('KOT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 22))),
        pw.SizedBox(height: 6),
        pw.Center(child: pw.Text(dateStr, style: const pw.TextStyle(fontSize: 9))),
        pw.SizedBox(height: 8),
        pw.Center(child: pw.Text('TABLE ${data['tableName']}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12))),
        pw.SizedBox(height: 4),
        pw.Center(child: pw.Text('Steward: $steward', style: const pw.TextStyle(fontSize: 9))),
        pw.SizedBox(height: 6),
        pw.Text('-' * 32, style: const pw.TextStyle(fontSize: 8)),
        pw.SizedBox(height: 6),

        // Header row
        pw.Row(children: [
          pw.Expanded(child: pw.Text('Item', style: const pw.TextStyle(fontSize: 9))),
          pw.Text('Qty', style: const pw.TextStyle(fontSize: 9)),
        ]),
        pw.SizedBox(height: 4),
        pw.Text('-' * 32, style: const pw.TextStyle(fontSize: 8)),
        pw.SizedBox(height: 6),

        // Items
        ...((data['items'] as List).map((item) {
          final category = (item['category'] ?? '').toString();
          final name = (item['name'] ?? '').toString();
          final qty = (item['quantity'] ?? 0).toString();
          final left = category.isNotEmpty ? '$category - $name' : name;
          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(child: pw.Text(left, style: const pw.TextStyle(fontSize: 9))),
                pw.SizedBox(width: 28, child: pw.Text(qty, textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 9))),
              ],
            ),
          );
        })),

        pw.SizedBox(height: 6),
        pw.Text('-' * 32, style: const pw.TextStyle(fontSize: 8)),
        pw.SizedBox(height: 8),
        pw.Center(child: pw.Text('ShreeRajmandir POS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
        pw.SizedBox(height: 8),
      ],
    ),
  );

  final bytes = await doc.save();
  final outFile = File(outputPath);
  await outFile.create(recursive: true);
  await outFile.writeAsBytes(bytes);
  print('Wrote KOT preview to: $outputPath');
}
