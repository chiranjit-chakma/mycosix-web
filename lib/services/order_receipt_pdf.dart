import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/customer_order.dart';
import '../utils/money.dart';

/// Brand colours mirrored from the app so the receipt matches the site.
/// Plain values — the pdf package renders these, not the Flutter palette.
class _PdfBrand {
  static const forest = PdfColor.fromInt(0xFF1D2717);
  static const moss = PdfColor.fromInt(0xFF4E6B36);
  static const mossDeep = PdfColor.fromInt(0xFF3A5228);
  static const mossSoft = PdfColor.fromInt(0xFFDDE6C9);
  static const charcoal = PdfColor.fromInt(0xFF1D201A);
  static const stone = PdfColor.fromInt(0xFF6E7268);
  static const line = PdfColor.fromInt(0xFFE2D9C4);
  static const creamLine = PdfColor.fromInt(0xFFFBF7EE);
}

/// Short-hand for the body-text style builder used by the section helpers.
typedef _Txt =
    pw.TextStyle Function(
      double size,
      PdfColor color, {
      pw.Font? font,
      pw.FontWeight? weight,
    });

/// Typography + logo needed to draw a MYCOSIX receipt.
class ReceiptAssets {
  const ReceiptAssets({
    required this.manrope,
    required this.fraunces,
    required this.logoPng,
  });

  /// Manrope variable TTF (body).
  final ByteData manrope;

  /// Fraunces variable TTF (display / wordmark).
  final ByteData fraunces;

  /// The MYCOSIX brand mark, as PNG bytes.
  final Uint8List logoPng;

  /// Loads the bundled fonts + logo through the Flutter asset bundle.
  static Future<ReceiptAssets> fromAssets() async {
    Future<ByteData> font(String path) async {
      final data = await rootBundle.load(path);
      return ByteData.sublistView(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    }

    final logoData = await rootBundle.load('assets/brand/mycosix-logo.png');
    return ReceiptAssets(
      manrope: await font('assets/fonts/Manrope-Variable.ttf'),
      fraunces: await font('assets/fonts/Fraunces-Variable.ttf'),
      logoPng: logoData.buffer.asUint8List(
        logoData.offsetInBytes,
        logoData.lengthInBytes,
      ),
    );
  }
}

/// Generates the professional MYCOSIX ORDER RECEIPT as a PDF byte stream,
/// entirely in the browser — no paid service, no account, no network upload.
///
/// The values are the same [CustomerOrder] the checkout screen confirmed, so
/// the receipt can never disagree with the website. It is a receipt for the
/// customer, not a tax invoice (the identifiers a real tax invoice requires
/// do not exist yet).
Future<Uint8List> buildOrderReceiptPdf(
  CustomerOrder order, {
  required ReceiptAssets assets,
}) async {
  final doc = pw.Document(
    title: 'MYCOSIX Order Receipt ${order.orderId}',
    author: 'MYCOSIX MUSHROOMS',
    subject: 'Order receipt ${order.orderId}',
  );

  final body = pw.Font.ttf(assets.manrope);
  final display = pw.Font.ttf(assets.fraunces);

  pw.TextStyle txt(double size, PdfColor color,
          {pw.Font? font, pw.FontWeight? weight}) =>
      pw.TextStyle(
        font: font ?? body,
        fontSize: size,
        color: color,
        fontWeight: weight,
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 34, 40, 30),
      build: (context) => [
        // Header: brand mark + wordmark.
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Image(pw.MemoryImage(assets.logoPng), width: 62, height: 62),
            pw.SizedBox(width: 14),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'MYCOSIX MUSHROOMS',
                  style: pw.TextStyle(
                    font: display,
                    fontSize: 19,
                    color: _PdfBrand.forest,
                  ),
                ),
                pw.Text(
                  'FRESH BY US. NATURALLY GOOD.',
                  style: pw.TextStyle(
                    font: body,
                    fontSize: 8.5,
                    letterSpacing: 1.1,
                    color: _PdfBrand.mossDeep,
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Container(height: 1.4, color: _PdfBrand.moss),
        pw.SizedBox(height: 20),

        // Title row: ORDER RECEIPT + Order ID + placed timestamp.
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'ORDER RECEIPT',
              style: pw.TextStyle(
                font: display,
                fontSize: 23,
                color: _PdfBrand.forest,
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Order ID   ${order.orderId}',
                  style: txt(12.5, _PdfBrand.charcoal,
                      weight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Placed ${_stamp(order.createdAt ?? DateTime.now())}',
                  style: txt(9.5, _PdfBrand.stone),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 24),

        // Customer.
        _sectionTitle('CUSTOMER', txt),
        pw.SizedBox(height: 6),
        _kvRow('Name', order.customerName, txt),
        _kvRow('Phone', order.phone, txt),
        _kvRow('Email', order.email, txt),
        pw.SizedBox(height: 20),

        // Order details.
        _sectionTitle('ORDER DETAILS', txt),
        pw.SizedBox(height: 8),
        _itemsTable(order, txt),
        pw.SizedBox(height: 10),
        pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _moneyLine('Subtotal', order.subtotal, txt, bold: false),
              _moneyLine('Delivery fee', order.deliveryFee, txt, bold: false),
              pw.Container(
                height: 1,
                color: _PdfBrand.line,
                margin: const pw.EdgeInsets.symmetric(vertical: 4),
              ),
              _moneyLine('Total', order.total, txt, bold: true),
            ],
          ),
        ),
        pw.SizedBox(height: 24),

        // Delivery.
        _sectionTitle('DELIVERY DETAILS', txt),
        pw.SizedBox(height: 6),
        _kvRow('Building / House', order.building, txt),
        _kvRow('Apartment / Unit', order.apartment, txt),
        _kvRow('Landmark', order.landmark, txt),
        _kvRow('Delivery instructions', order.instructions, txt),
        _kvRow('Confirmed delivery location', order.location.mapsUrl, txt),
        pw.SizedBox(height: 22),

        // Payment.
        _sectionTitle('PAYMENT', txt),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: _PdfBrand.mossSoft,
            border: pw.Border.all(color: _PdfBrand.moss),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Payment method:  CASH ON DELIVERY',
                style: pw.TextStyle(
                  font: body,
                  fontSize: 11.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _PdfBrand.mossDeep,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                'Online payment is currently unavailable. Please pay in cash '
                'at the time of delivery.',
                style: txt(9.5, _PdfBrand.charcoal),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 26),

        // Footer strip.
        pw.Container(
          padding: const pw.EdgeInsets.only(top: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _PdfBrand.line)),
          ),
          child: pw.Text(
            'MYCOSIX MUSHROOMS  ·  FRESH BY US. NATURALLY GOOD.',
            style: txt(7.5, _PdfBrand.stone),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'This is an order receipt, not a tax invoice. For help with this '
          'order, message MYCOSIX on WhatsApp and quote ${order.orderId}.',
          style: txt(7.5, _PdfBrand.stone),
        ),
      ],
    ),
  );

  return doc.save();
}

/// Trims and normalises an optional free-text value; null when blank.
String? _clean(String? v) {
  final t = v?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// Absolute local timestamp, e.g. "6 Sep 2026, 09:14".
String _stamp(DateTime t) {
  const months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String two(int v) => v.toString().padLeft(2, '0');
  final l = t.toLocal();
  return '${l.day} ${months[l.month - 1]} ${l.year}, ${two(l.hour)}:${two(l.minute)}';
}

pw.Widget _sectionTitle(String title, _Txt txt) {
  return pw.Text(
    title,
    style: txt(10.5, _PdfBrand.mossDeep, weight: pw.FontWeight.bold),
  );
}

/// A label/value row. Blank optional values render as nothing.
pw.Widget _kvRow(String label, String? rawValue, _Txt txt) {
  final value = _clean(rawValue);
  if (value == null) return pw.SizedBox.shrink();
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 150,
          child: pw.Text(label, style: txt(10, _PdfBrand.stone)),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: txt(10, _PdfBrand.charcoal),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _moneyLine(String label, double amount, _Txt txt,
    {required bool bold}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1),
    child: pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          label,
          style: txt(10.5, _PdfBrand.charcoal,
              weight: bold ? pw.FontWeight.bold : null),
        ),
        pw.SizedBox(width: 18),
        pw.SizedBox(
          width: 86,
          child: pw.Text(
            formatRupees(amount),
            textAlign: pw.TextAlign.right,
            style: txt(bold ? 12 : 10.5,
                bold ? _PdfBrand.forest : _PdfBrand.charcoal,
                weight: bold ? pw.FontWeight.bold : null),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _itemsTable(CustomerOrder order, _Txt txt) {
  final header = txt(9.5, _PdfBrand.mossDeep, weight: pw.FontWeight.bold);

  return pw.TableHelper.fromTextArray(
    headers: ['Product', 'Qty', 'Unit price', 'Amount'],
    headerStyle: header,
    headerDecoration: const pw.BoxDecoration(color: _PdfBrand.mossSoft),
    headerPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    cellStyle: txt(10, _PdfBrand.charcoal),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    columnWidths: {
      0: const pw.FlexColumnWidth(5),
      1: const pw.FlexColumnWidth(1),
      2: const pw.FlexColumnWidth(2),
      3: const pw.FlexColumnWidth(2),
    },
    cellAlignments: {
      1: pw.Alignment.center,
      2: pw.Alignment.centerRight,
      3: pw.Alignment.centerRight,
    },
    oddRowDecoration: const pw.BoxDecoration(color: _PdfBrand.creamLine),
    border: pw.TableBorder.all(color: _PdfBrand.line, width: 0.6),
    data: <List<String>>[
      for (final line in order.items)
        [
          _productCell(
              line.product.name, line.product.weight, line.product.variant),
          '${line.quantity}',
          formatRupees(line.product.price),
          formatRupees(line.lineTotal),
        ],
    ],
  );
}

/// "Pink Oyster Mushroom — 250 g · Fresh" style product cell.
String _productCell(String name, String weight, String variant) {
  final parts = <String>[
    if (weight.trim().isNotEmpty) weight.trim(),
    if (variant.trim().isNotEmpty && variant.trim() != weight.trim())
      variant.trim(),
  ];
  return parts.isEmpty ? name : '$name — ${parts.join(' · ')}';
}
