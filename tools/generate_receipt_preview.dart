import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// Generates a 58mm receipt preview PDF and writes to build/receipt_preview.pdf
// Run: dart run tools/generate_receipt_preview.dart

Future<Uint8List> generateReceiptPreviewPdf() async {
  final doc = pw.Document();

  final pageWidth = 58 * 2.8346456693;
  final pageFormat = PdfPageFormat(pageWidth, 100 * PdfPageFormat.cm, marginAll: 6);

  final dateStr = DateFormat('dd-MMM-yyyy HH:mm').format(DateTime.now());

  final sampleItems = [
    {'category': 'Scoops', 'name': 'Vanilla', 'quantity': 2, 'price': 40},
    {'category': 'Cone', 'name': 'Chocolate', 'quantity': 1, 'price': 40},
    {'category': 'Drinks', 'name': 'Mango', 'quantity': 1, 'price': 60},
  ];

  const int maxItemChars = 18;
  const double qtyWidth = 18;
  const double amtWidth = 40;

  doc.addPage(
    pw.MultiPage(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.all(6),
      build: (ctx) => [
        pw.Center(child: pw.Text('7947151577', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 6),
        pw.Text('Bill No: B001', style: const pw.TextStyle(fontSize: 8)),
        pw.Text('Date: $dateStr', style: const pw.TextStyle(fontSize: 8)),
        pw.SizedBox(height: 4),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Table: 1', style: const pw.TextStyle(fontSize: 8)),
          pw.Text('ANIKE', style: const pw.TextStyle(fontSize: 8)),
        ]),
        pw.SizedBox(height: 6),
        pw.Divider(),

        ...sampleItems.map((item) {
          final category = item['category']?.toString() ?? '';
          final name = item['name']?.toString() ?? '';
          final left = category.isNotEmpty ? '${category.trim()}-${name.trim()}' : name.trim();
          var leftSafe = left.replaceAll(RegExp('\s+'), ' ');
          if (leftSafe.length > maxItemChars) leftSafe = leftSafe.substring(0, maxItemChars);
          final qty = (item['quantity'] ?? 0).toString();
          final amt = (item['price'] ?? 0).toString();
          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1),
            child: pw.Row(children: [
              pw.Expanded(child: pw.Text(leftSafe, style: const pw.TextStyle(fontSize: 8), maxLines: 1, overflow: pw.TextOverflow.clip)),
              pw.SizedBox(width: qtyWidth, child: pw.Text(qty, style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right)),
              pw.SizedBox(width: amtWidth, child: pw.Text('₹$amt', style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right)),
            ]),
          );
        }).toList(),

        pw.SizedBox(height: 6),
        pw.Divider(),

        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('TOTAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.Text('₹180', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
        ]),

        pw.Divider(),
        pw.SizedBox(height: 6),
        pw.Center(child: pw.Text('Thank You Visit Again', style: const pw.TextStyle(fontSize: 8))),
        pw.Center(child: pw.Text('@rajmandir_icecream_latur', style: const pw.TextStyle(fontSize: 8))),
        pw.Center(child: pw.Text('ShreeRajmandir POS', style: const pw.TextStyle(fontSize: 7))),
      ],
    ),
  );

  return doc.save();
}

Future<void> main() async {
  final bytes = await generateReceiptPreviewPdf();
  final out = File('build/receipt_preview.pdf');
  out.createSync(recursive: true);
  out.writeAsBytesSync(bytes);
  print('Wrote build/receipt_preview.pdf');
}
