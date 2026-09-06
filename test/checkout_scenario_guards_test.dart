import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/config/mx_config.dart';
import 'package:mycosix/models/cart_item.dart';
import 'package:mycosix/models/customer_order.dart';
import 'package:mycosix/models/delivery_location.dart';
import 'package:mycosix/models/product.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/utils/phone.dart';
import 'package:mycosix/utils/validators.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Maps the customer-order acceptance scenarios to the single authority that
/// enforces them: the [CartRepository] (what can ever sit in a cart), the
/// form/phone validators and [CustomerOrder.isValid] (what may be submitted).
/// These are the exact rules the checkout screen's "place order" gate leans on.
void main() {
  Product product({
    required String id,
    double price = 80,
    int stock = 5,
    bool available = true,
  }) {
    return Product(
      id: id,
      name: 'Fresh Oyster Mushrooms',
      description: 'Fresh by MYCOSIX',
      category: 'Fresh',
      image: 'a.jpg',
      variant: 'Fresh',
      weight: '250 g',
      price: price,
      stock: stock,
      available: available,
    );
  }

  /// A repository that hands back exactly the products given.
  Future<CartRepository> makeCart(List<Product> catalog) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = CartRepository(prefs, _FakeRepo(catalog));
    await c.load();
    return c;
  }

  const confirmed = DeliveryLocation(
    latitude: 17.4,
    longitude: 78.4,
    mapsUrl: 'https://maps.google.com/?q=17.4,78.4',
    confirmed: true,
  );

  group('Empty cart', () {
    test('an empty cart holds no lines to submit', () async {
      final c = await makeCart([product(id: 'a')]);
      expect(c.isEmpty, isTrue);
      expect(c.lines, isEmpty);
      expect(c.totalQuantity, 0);
      // No items -> an order can never be valid, so checkout cannot fire.
      final empty = CustomerOrder(
        orderId: 'MYC-TEST0001',
        customerName: 'Neha',
        phone: '9876543210',
        location: confirmed,
        items: const <CartItem>[],
        subtotal: 0,
        deliveryFee: MxConfig.deliveryFee,
        total: 0,
      );
      expect(empty.isValid, isFalse);
    });
  });

  group('Invalid phone', () {
    // Mirrors the checkout's shared _validatePhone: strip non-digits, then the
    // same isValidIndianPhone rule gates the "place order" button.
    String? checkoutPhone(String value) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      return isValidIndianPhone(digits) ? null : 'invalid';
    }

    test('short or malformed numbers are rejected before submission', () {
      expect(checkoutPhone('98765'), isNotNull); // too short
      expect(checkoutPhone('1234567890'), isNotNull); // starts with 1
      expect(checkoutPhone('abcdefghij'), isNotNull); // no digits at all
      expect(checkoutPhone(''), isNotNull); // empty
      expect(checkoutPhone('9876543210'), isNull); // valid
      expect(checkoutPhone('+91 98765 43210'), isNull); // formatted valid
      expect(checkoutPhone('9999999999'), isNull);
    });
  });

  group('Missing name or delivery location', () {
    test('an empty name fails validation', () {
      expect(FormValidators.name(''), isNotNull);
      expect(FormValidators.name('   '), isNotNull);
      expect(FormValidators.name('Neha'), isNull);
    });

    test('a null, unconfirmed or blank-maps location invalidates the order',
        () {
      CustomerOrder order({required DeliveryLocation loc}) => CustomerOrder(
            orderId: 'MYC-TEST0001',
            customerName: 'Neha',
            phone: '9876543210',
            location: loc,
            items: [CartItem(product: product(id: 'a'), quantity: 1)],
            subtotal: 80,
            deliveryFee: MxConfig.deliveryFee,
            total: 80 + MxConfig.deliveryFee,
          );

      const unconfirmed = DeliveryLocation(
        latitude: 1,
        longitude: 2,
        mapsUrl: 'https://maps.google.com/?q=1,2',
        confirmed: false,
      );
      const noMap = DeliveryLocation(
        latitude: 1,
        longitude: 2,
        mapsUrl: '   ',
        confirmed: true,
      );

      expect(order(loc: confirmed).isValid, isTrue);
      expect(order(loc: unconfirmed).isValid, isFalse);
      expect(order(loc: noMap).isValid, isFalse);
    });
  });

  group('Unavailable / out-of-stock products', () {
    test('a product switched off (available: false) can never be added',
        () async {
      final off = product(id: 'off', available: false, stock: 5);
      final c = await makeCart([off]);
      expect(off.inStock, isFalse);
      expect(c.maxFor(off), 0);
      await c.add('off', 2);
      expect(c.isEmpty, isTrue);
    });

    test('a product with zero stock cannot be added either', () async {
      final zero = product(id: 'zero', stock: 0);
      final c = await makeCart([zero]);
      expect(zero.inStock, isFalse);
      expect(c.maxFor(zero), 0);
      await c.add('zero', 5);
      await c.setQuantity('zero', 9);
      expect(c.isEmpty, isTrue);
      expect(c.totalQuantity, 0);
    });
  });

  group('Quantity above stock', () {
    test('is clamped to the real stock, never sold above it', () async {
      // Stock (3) is below the per-line ceiling (12) so the stock clamp bites.
      final rare = product(id: 'rare', stock: 3);
      final c = await makeCart([rare]);

      expect(c.maxFor(rare), 3);
      await c.add('rare', 999);
      expect(c.items['rare'], 3);
      expect(c.items['rare'], lessThan(999));

      await c.setQuantity('rare', 99);
      expect(c.items['rare'], 3);

      // A normal amount still lands exactly as requested.
      await c.setQuantity('rare', 2);
      expect(c.items['rare'], 2);
    });
  });
}

/// Hands back exactly the given catalogue — the [CartRepository] never sees a
/// full static catalogue in these tests, only the products under test.
class _FakeRepo implements ProductRepository {
  _FakeRepo(this.catalog);

  final List<Product> catalog;

  @override
  Future<List<Product>> fetchAll() async => catalog;

  @override
  Future<Product?> fetchById(String id) async {
    for (final p in catalog) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<List<Product>> fetchByCategory(String category) async =>
      catalog.where((p) => p.category == category).toList();
}
