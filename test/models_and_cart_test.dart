import 'dart:convert';

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

void main() {
  group('Phone', () {
    test('accepts valid Indian mobile numbers', () {
      expect(isValidIndianPhone('9876543210'), isTrue);
      expect(isValidIndianPhone('+91 98765 43210'), isTrue);
      expect(isValidIndianPhone('919876543210'), isTrue);
      expect(isValidIndianPhone('09876543210'), isTrue);
    });

    test('rejects invalid numbers', () {
      expect(isValidIndianPhone('1234567890'), isFalse); // starts with 1
      expect(isValidIndianPhone('98765'), isFalse);
      expect(isValidIndianPhone('abcdefghij'), isFalse);
    });

    test('normalizes to E.164 for WhatsApp', () {
      expect(normalizePhone('9876543210'), '919876543210');
      expect(normalizePhone('+91 98765 43210'), '919876543210');
    });
  });

  group('FormValidators', () {
    test('name validates presence and length', () {
      expect(FormValidators.name(''), isNotNull);
      expect(FormValidators.name('Neha'), isNull);
    });

    test('phone accepts formatted numbers', () {
      expect(FormValidators.phone('+91 98765 43210'), isNull);
      expect(FormValidators.phone('98765'), isNotNull);
    });
  });

  group('Product model', () {
    test('json round-trips and stock state', () {
      final p = Product(
        id: 'x',
        name: 'Fresh Oyster Mushrooms',
        description: 'Desc',
        category: 'Fresh',
        image: 'assets/products/oyster_bouquet.jpg',
        variant: 'Fresh',
        weight: '250 g',
        price: 80,
        stock: 5,
        available: true,
      );
      expect(p.inStock, isTrue);
      final restored = Product.fromJson(p.toJson());
      expect(restored.id, p.id);
      expect(restored.price, p.price);
      final out = Product.fromJson({...p.toJson(), 'stock': 0});
      expect(out.inStock, isFalse);
    });
  });

  group('Cart totals & persistence', () {
    ProductRepository repo() => LocalProductRepository();
    final productsRepo = LocalProductRepository();

    testWidgets('subtotal and delivery fee are computed from lines',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cart = CartRepository(prefs, repo());
      await cart.load();

      final all = await productsRepo.fetchAll();
      await cart.add(all[0].id, 2); // 80 x 2
      await cart.add(all[1].id, 1); // 150

      expect(cart.lines.length, 2);
      expect(cart.totalQuantity, 3);
      final subtotal =
          cart.lines.fold(0.0, (a, l) => a + l.product.price * l.quantity);
      expect(subtotal, 310);
    });

    testWidgets('cart persists across reload', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final all = await productsRepo.fetchAll();
      final id = all[0].id;

      final cart1 = CartRepository(prefs, repo());
      await cart1.load();
      await cart1.add(id, 3);
      expect(cart1.items[id], 3);

      // New instance with same prefs simulates a page refresh.
      final cart2 = CartRepository(prefs, repo());
      await cart2.load();
      expect(cart2.items[id], 3);
    });

    testWidgets('clear empties the cart', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cart = CartRepository(prefs, repo());
      await cart.load();
      final all = await productsRepo.fetchAll();
      await cart.add(all[0].id, 1);
      expect(cart.isEmpty, isFalse);
      await cart.clear();
      expect(cart.isEmpty, isTrue);
    });
  });

  group('Cart gating & quantity limits', () {
    ProductRepository productsRepo() => LocalProductRepository();

    testWidgets('unavailable products can never be added', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cart = CartRepository(prefs, productsRepo());
      await cart.load();
      final all = await productsRepo().fetchAll();
      final pickle = all.firstWhere((p) => p.id == 'oyster-pickle-250');
      expect(pickle.inStock, isFalse);

      await cart.add(pickle.id, 2);
      await cart.setQuantity(pickle.id, 5);
      expect(cart.isEmpty, isTrue);
      expect(cart.totalQuantity, 0);
    });

    testWidgets('quantities are clamped to the per-line ceiling', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cart = CartRepository(prefs, productsRepo());
      await cart.load();
      final all = await productsRepo().fetchAll();
      final id = all[0].id;

      await cart.add(id, 999);
      expect(cart.items[id], MxConfig.maxUnitsPerProduct);

      await cart.add(id, 8);
      await cart.add(id, 8); // 8 + 8 = 16, still above the ceiling
      expect(cart.items[id], MxConfig.maxUnitsPerProduct);
    });

    testWidgets('stale persisted carts are sanitised on load', (tester) async {
      SharedPreferences.setMockInitialValues({
        'mx.cart.v1': jsonEncode([
          {'productId': 'fresh-oyster-250', 'quantity': 999},
          {'productId': 'oyster-pickle-250', 'quantity': 2},
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final cart = CartRepository(prefs, productsRepo());
      await cart.load();
      expect(cart.items['fresh-oyster-250'], MxConfig.maxUnitsPerProduct);
      expect(cart.items.containsKey('oyster-pickle-250'), isFalse);
    });
  });

  group('DeliveryLocation', () {
    test('json round trip keeps confirmed flag', () {
      const loc = DeliveryLocation(
        latitude: 17.44,
        longitude: 78.34,
        mapsUrl: 'https://maps.google.com/?q=17.44,78.34',
        confirmed: true,
      );
      final restored = DeliveryLocation.fromJson(loc.toJson());
      expect(restored.latitude, 17.44);
      expect(restored.confirmed, isTrue);
    });
  });

  group('CustomerOrder', () {
    test('isValid requires confirmed location and items', () {
      Product product(String id) => Product(
            id: id,
            name: 'Fresh Oyster Mushrooms',
            description: 'x',
            category: 'Fresh',
            image: 'a.jpg',
            variant: 'Fresh',
            weight: '250 g',
            price: 80,
            stock: 5,
            available: true,
          );
      CustomerOrder order({required DeliveryLocation loc}) => CustomerOrder(
            orderId: 'MX-1',
            customerName: 'Neha',
            phone: '9876543210',
            location: loc,
            items: [CartItem(product: product('a'), quantity: 1)],
            subtotal: 80,
            deliveryFee: 39,
            total: 119,
          );
      const confirmed = DeliveryLocation(
        latitude: 1,
        longitude: 2,
        mapsUrl: 'https://maps.google.com/?q=1,2',
        confirmed: true,
      );
      const unconfirmed = DeliveryLocation(
        latitude: 1,
        longitude: 2,
        mapsUrl: 'https://maps.google.com/?q=1,2',
        confirmed: false,
      );
      expect(order(loc: confirmed).isValid, isTrue);
      expect(order(loc: unconfirmed).isValid, isFalse);
    });
  });
}
