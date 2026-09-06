import 'dart:math';

/// The one, deliberately simple WhatsApp handoff the website offers.
///
/// The order itself is confirmed on screen and (via a trusted backend, or a
/// money-free capture when that backend is unreachable) recorded for the admin
/// workflow. WhatsApp is only an optional, NON-authoritative follow-up: it
/// opens a chat with MYCOSIX pre-filled with a short notice that carries no
/// items, prices, addresses or map links. The customer never sends the order
/// data itself through WhatsApp.
class WhatsAppOrderService {
  WhatsAppOrderService({required this.whatsappNumber});

  /// MYCOSIX business number in international form, e.g. '916363816465'.
  final String whatsappNumber;

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

  /// The confirmation-screen WhatsApp handoff: opens a chat with MYCOSIX
  /// pre-filled with the fixed notice below. Intentionally NOT an order
  /// channel — items, amounts and the delivery location are never included,
  /// so nothing here can disagree with the recorded order.
  String confirmationHandoffUrl(String orderId) {
    final text = 'MYCOSIX order $orderId has been confirmed. '
        'Please contact MYCOSIX if you need assistance.';
    return Uri.parse('https://wa.me/$whatsappNumber')
        .replace(queryParameters: {'text': text})
        .toString();
  }
}
