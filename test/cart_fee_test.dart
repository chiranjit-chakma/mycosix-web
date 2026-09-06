import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/config/mx_config.dart';
import 'package:mycosix/models/product.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/state/cart_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The delivery fee a customer sees must come from the runtime site config
/// (the same value the trusted backend reads when it prices a real order),
/// never from a second, static source that can drift. CartController takes
/// that fee at construction and only ever applies it to a non-empty cart.
void main() {
  late Product seed;

  setUp(() async {
    final productsRepo = LocalProductRepository();
    seed = (await productsRepo.fetchAll()).first;
  });

  Future<CartController> build({double fee = MxConfig.deliveryFee, int qty = 0}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final productsRepo = LocalProductRepository();
    final cartRepo = CartRepository(prefs, productsRepo);
    await cartRepo.load();
    if (qty > 0) await cartRepo.add(seed.id, qty);
    return CartController(cartRepo, siteDeliveryFee: fee);
  }

  group('CartController delivery fee', () {
    test('empty cart never charges a delivery fee', () async {
      final cart = await build();
      expect(cart.subtotal, 0);
      expect(cart.deliveryFee, 0);
      expect(cart.total, 0);
    });

    test('a non-empty cart is quoted the configured fee exactly', () async {
      final cart = await build(qty: 2);
      expect(cart.subtotal, greaterThan(0));
      expect(cart.deliveryFee, MxConfig.deliveryFee);
      expect(cart.siteDeliveryFee, MxConfig.deliveryFee);
      expect(cart.total, cart.subtotal + MxConfig.deliveryFee);
    });

    test('honors the runtime site-config fee in cart and total', () async {
      final cart = await build(fee: 49, qty: 2);
      expect(cart.deliveryFee, 49);
      expect(cart.total, cart.subtotal + 49);
    });

    test('honors a free-delivery (0) override exactly like the backend would',
        () async {
      final cart = await build(fee: 0, qty: 2);
      expect(cart.deliveryFee, 0);
      expect(cart.total, cart.subtotal);
    });
  });
}
