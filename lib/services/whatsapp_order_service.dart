import 'dart:math';

import '../models/customer_order.dart';

/// Prepares a professional WhatsApp order message and opens the handoff.
///
/// Opening WhatsApp is only a handoff — this service NEVER claims the website
/// silently sends the message. The customer reviews and taps send in WhatsApp.
class WhatsAppOrderService {
  WhatsAppOrderService({
    required this.whatsappNumber,
    required this.deliveryFee,
  });

  final String whatsappNumber; // e.g. '916363816465'
  final double deliveryFee;

  static const _maxWhatsAppLength = 4096;

  static const _rupee = '₹';
  static const _emDash = '—';
  static const _multiply = '×';
  static const _pin = '📍';

  /// Unambiguous id alphabet — no 0/O or 1/I, so an id survives being read
  /// aloud over the phone.
  static const _idChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Generates a customer-facing order id in the format MYC-XXXXXXXX.
  ///
  /// 8 characters over a 32-symbol alphabet = 40 bits of randomness, which
  /// makes collisions negligible for a shop that starts from zero orders.
  String generateOrderId() {
    final rand = Random();
    final buf = StringBuffer('MYC-');
    for (var i = 0; i < 8; i++) {
      buf.write(_idChars[rand.nextInt(_idChars.length)]);
    }
    return buf.toString();
  }

  /// Builds the WhatsApp message in the exact plain-text layout the team
  /// reviews orders from. WhatsApp renders this verbatim — no markup.
  String buildMessage(CustomerOrder order) {
    final b = StringBuffer();

    // Header.
    b.write('MYCOSIX MUSHROOMS $_emDash NEW ORDER\n');
    b.write('Order ID: ${order.orderId}\n');

    // Customer.
    b.write('\nCUSTOMER\n');
    b.write('Name: ${order.customerName}\n');
    b.write('Phone: ${order.phone}\n');
    final email = (order.email ?? '').trim();
    if (email.isNotEmpty) b.write('Email: $email\n');

    // Order lines.
    b.write('\nORDER\n');
    var n = 1;
    for (final line in order.items) {
      final unit = line.product.weight.trim();
      final unitText = unit.isNotEmpty ? ' $unit' : '';
      b.write(
        '$n. ${line.product.name} $_emDash$unitText $_multiply '
        '${line.quantity} $_emDash $_rupee${_fmt(line.lineTotal)}\n',
      );
      n++;
    }

    // Totals.
    b.write('\nSubtotal: $_rupee${_fmt(order.subtotal)}\n');
    b.write('Delivery: $_rupee${_fmt(order.deliveryFee)}\n');
    b.write('TOTAL: $_rupee${_fmt(order.total)}\n');

    // Confirmed delivery location.
    b.write('\nDELIVERY LOCATION\n');
    b.write('$_pin Exact pinned location: ${order.location.mapsUrl}\n');

    // Optional address hints, only when the customer filled them in.
    final building = (order.building ?? '').trim();
    final apartment = (order.apartment ?? '').trim();
    final landmark = (order.landmark ?? '').trim();
    final instructions = (order.instructions ?? '').trim();
    if (building.isNotEmpty) b.write('Building/House: $building\n');
    if (apartment.isNotEmpty) b.write('Apartment/Unit: $apartment\n');
    if (landmark.isNotEmpty) b.write('Landmark: $landmark\n');
    if (instructions.isNotEmpty) {
      b.write('Delivery instructions: $instructions\n');
    }

    b.write('\nPlease confirm availability and delivery.');

    return b.toString();
  }

  /// Opens WhatsApp with the prepared message. Returns the wa.me URL used.
  String openHandoff(CustomerOrder order) {
    var text = buildMessage(order);
    if (text.length > _maxWhatsAppLength) {
      text = text.substring(0, _maxWhatsAppLength);
    }
    final uri = Uri.parse('https://wa.me/$whatsappNumber')
        .replace(queryParameters: {'text': text});
    return uri.toString();
  }

  static String _fmt(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }
}
