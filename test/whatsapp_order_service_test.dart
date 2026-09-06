import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/services/whatsapp_order_service.dart';

void main() {
  group('WhatsAppOrderService', () {
    final service = WhatsAppOrderService(whatsappNumber: '916363816465');

    test('order id uses MYC- prefix plus 8 unambiguous chars', () {
      final id = service.generateOrderId();
      expect(id, startsWith('MYC-'));
      expect(id.length, 12); // 'MYC-' + 8
      final tail = id.substring(4);
      expect(
        RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]+$').hasMatch(tail),
        isTrue,
        reason: 'id body must only use the unambiguous alphabet',
      );
    });

    test('generated ids do not collide in practice', () {
      final seen = <String>{};
      for (var i = 0; i < 500; i++) {
        seen.add(service.generateOrderId());
      }
      expect(seen.length, 500);
    });

    test('confirmation handoff targets the business number', () {
      final url = service.confirmationHandoffUrl('MYC-8F3K2PLQ');
      expect(url, startsWith('https://wa.me/916363816465'));
      expect(url, contains('text='));
      final decoded = Uri.decodeComponent(url.split('text=')[1])
          .replaceAll('+', ' ');
      expect(
        decoded,
        'MYCOSIX order MYC-8F3K2PLQ has been confirmed. '
        'Please contact MYCOSIX if you need assistance.',
      );
    });

    test('handoff never carries order data', () {
      final url = service.confirmationHandoffUrl('MYC-8F3K2PLQ');
      final decoded = Uri.decodeComponent(url.split('text=')[1])
          .replaceAll('+', ' ');
      // Only the fixed notice: no items, prices, address, pin or totals.
      expect(decoded, isNot(contains('Fresh')));
      expect(decoded, isNot(contains('₹')));
      expect(decoded, isNot(contains('maps')));
      expect(decoded, isNot(contains('TOTAL')));
    });
  });
}
