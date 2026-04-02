import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

// Generates a KOT preview PDF and writes to build/kot_preview.pdf
// Run: dart run tools/generate_kot_preview.dart

Future<Uint8List> generateKotPreviewPdf({
  required String kotNumber,
  required String tableNumber,
  required String stewardRaw,
  required List<Map<String, dynamic>> items,
}) async {
  final doc = pw.Document();

  // Steward cleaning
  String steward = stewardRaw.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  if (steward.length > 5) steward = steward.substring(0, 5);

  // 58 mm in points
  final pageWidth = 58 * 2.8346456693;
  final pageFormat = PdfPageFormat(pageWidth, 100 * PdfPageFormat.cm, marginAll: 6);

  final pw.TextStyle headerBold8 = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
  final pw.TextStyle text8 = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.normal);
  final pw.TextStyle footerBold6 = pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold);

  final dateStr = DateFormat('dd-MMM-yyyy HH:mm:ss').format(DateTime.now());

  doc.addPage(
    pw.MultiPage(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.all(6),
      build: (ctx) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(children: [pw.Text('KOT: ', style: headerBold8), pw.Text(kotNumber, style: headerBold8)]),
            pw.Row(children: [pw.Text('TABLE: ', style: headerBold8), pw.Text(tableNumber, style: headerBold8)]),
          ],
        ),

        pw.SizedBox(height: 4),
        pw.Text(List.filled(48, '-').join(), style: text8),
        pw.SizedBox(height: 4),

        if (items.isEmpty)
          pw.Text('No items', style: text8)
        else
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: items.map((item) {
              final name = (item['name'] ?? '').toString();
              final qty = (item['qty'] ?? item['quantity'] ?? 0).toString();
              final note = (item['note'] ?? '').toString();
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(child: pw.Text(name, style: text8, maxLines: 2, overflow: pw.TextOverflow.clip)),
                        pw.SizedBox(width: 6),
                        pw.Text(qty, style: text8),
                      ],
                    ),
                    if (note.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: pw.Text(note, style: text8)),
                  ],
                ),
              );
            }).toList(),
          ),

        pw.SizedBox(height: 6),
        pw.Text(List.filled(48, '-').join(), style: text8),

        pw.Spacer(),

        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Stew: $steward', style: footerBold6),
            pw.Text(dateStr, style: footerBold6),
          ],
        ),
      ],
    ),
  );

  return doc.save();
}

// CLI runner
Future<void> main() async {
  final sample = [
    {'name': 'Paneer Butter Masala', 'qty': 2},
    {'name': 'Garlic Naan (butter)', 'qty': 4},
    {'name': 'Jeera Rice', 'qty': 1},
  ];

  final bytes = await generateKotPreviewPdf(kotNumber: '000123', tableNumber: 'T12', stewardRaw: 'John Doe', items: sample);
  final out = File('build/kot_preview.pdf');
  out.createSync(recursive: true);
  out.writeAsBytesSync(bytes);
  print('Wrote build/kot_preview.pdf');
}
