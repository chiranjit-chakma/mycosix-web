import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/models/cart_item.dart';
import 'package:mycosix/models/customer_order.dart';
import 'package:mycosix/models/delivery_location.dart';
import 'package:mycosix/models/product.dart';
import 'package:mycosix/services/whatsapp_order_service.dart';

Product _product({String id = 'p1', double price = 80}) => Product(
  id: id,
  name: 'Fresh Oyster Mushrooms',
  description: 'Test pack',
  category: 'Fresh',
  image: 'assets/products/oyster_bouquet.jpg',
  variant: 'Fresh',
  weight: '250 g',
  price: price,
  stock: 10,
  available: true,
);

void main() {
  group('WhatsAppOrderService', () {
    final service = WhatsAppOrderService(
      whatsappNumber: '916363816465',
      deliveryFee: 39,
    );

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

    test('message follows the exact order-review layout', () {
      final order = CustomerOrder(
        orderId: 'MYC-8F3K2PLQ',
        customerName: 'Neha',
        phone: '+91 98765 43210',
        location: const DeliveryLocation(
          latitude: 17.4401,
          longitude: 78.3489,
          mapsUrl: 'https://www.google.com/maps?q=17.440080,78.348900&z=16',
          confirmed: true,
        ),
        items: [
          CartItem(product: _product(id: 'a', price: 80), quantity: 2),
          CartItem(product: _product(id: 'b', price: 150), quantity: 1),
        ],
        subtotal: 310,
        deliveryFee: 39,
        total: 349,
        building: 'Plot 21',
        instructions: 'Ring the bell',
      );

      final msg = service.buildMessage(order);
      expect(msg, startsWith('MYCOSIX MUSHROOMS — NEW ORDER\n'));
      expect(msg, contains('Order ID: MYC-8F3K2PLQ\n'));
      expect(msg, contains('\nCUSTOMER\n'));
      expect(msg, contains('Name: Neha\n'));
      expect(msg, contains('Phone: +91 98765 43210\n'));
      expect(msg, contains('\nORDER\n'));
      expect(msg, contains('1. Fresh Oyster Mushrooms — 250 g × 2 — ₹160'));
      expect(msg, contains('\nSubtotal: ₹310\n'));
      expect(msg, contains('\nDelivery: ₹39\n'));
      expect(msg, contains('\nTOTAL: ₹349\n'));
      expect(msg, contains('\nDELIVERY LOCATION\n'));
      expect(
        msg,
        contains(
          'Exact pinned location: '
          'https://www.google.com/maps?q=17.440080,78.348900&z=16',
        ),
      );
      expect(msg, contains('Building/House: Plot 21\n'));
      expect(msg, contains('Delivery instructions: Ring the bell\n'));
      expect(msg, endsWith('Please confirm availability and delivery.'));
      expect(msg, isNot(contains('*Subtotal*'))); // no WhatsApp bold markup
    });

    test('handoff url is wa.me with the business number', () {
      final order = CustomerOrder(
        orderId: 'MYC-8F3K2PLQ',
        customerName: 'A',
        phone: '9876543210',
        location: const DeliveryLocation(
          latitude: 17.44,
          longitude: 78.34,
          mapsUrl: 'https://www.google.com/maps?q=17.44,78.34&z=16',
          confirmed: true,
        ),
        items: [CartItem(product: _product(), quantity: 1)],
        subtotal: 80,
        deliveryFee: 39,
        total: 119,
      );
      final url = service.openHandoff(order);
      expect(url, startsWith('https://wa.me/916363816465'));
      expect(url, contains('text='));
      // Decode and confirm the totals + order id made it into the handoff.
      final decoded = Uri.decodeComponent(url.split('text=')[1])
          .replaceAll('+', ' ');
      expect(decoded, contains('Order ID: MYC-8F3K2PLQ'));
      expect(decoded, contains('TOTAL: ₹119'));
    });

    test('email and optional details are omitted when absent', () {
      final order = CustomerOrder(
        orderId: 'MYC-8F3K2PLQ',
        customerName: 'A',
        phone: '9876543210',
        location: const DeliveryLocation(
          latitude: 17.44,
          longitude: 78.34,
          mapsUrl: 'https://www.google.com/maps?q=17.44,78.34&z=16',
          confirmed: true,
        ),
        items: [CartItem(product: _product(), quantity: 1)],
        subtotal: 80,
        deliveryFee: 39,
        total: 119,
      );
      final msg = service.buildMessage(order);
      expect(msg, isNot(contains('Email:')));
      expect(msg, isNot(contains('Building/House:')));
      expect(msg, isNot(contains('Delivery instructions:')));
    });
  });
}
