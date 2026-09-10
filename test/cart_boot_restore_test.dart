import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/models/product.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The saved cart comes back from the DEVICE, and the catalogue arrives after
/// the first frame.
///
/// These two used to be one step, and that one step was a Firestore read that
/// sat in front of the first frame - the biggest single thing between tapping
/// the app icon and seeing the app. Splitting them is only safe if the device
/// half brings the cart back whole (it cannot check against a catalogue it
/// does not have yet) and the catalogue half then puts it right. That is what
/// is pinned here.
void main() {
  /// Counts every catalogue read so a test can prove the device half made none.
  late int fetches;

  Product product(
    String id, {
    bool inStock = true,
    int stock = 50,
  }) => Product(
    id: id,
    name: 'Oyster $id',
    description: 'Fresh',
    category: 'Fresh',
    image: 'assets/products/$id.webp',
    variant: 'Fresh',
    weight: '250 g',
    price: 80,
    stock: stock,
    available: inStock,
  );

  CartRepository repoWith(
    SharedPreferences prefs,
    List<Product> catalog,
  ) {
    fetches = 0;
    return CartRepository(
      prefs,
      _CountingRepo(catalog, () => fetches++),
    );
  }

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  String savedCart(List<Map<String, Object>> lines) => jsonEncode(lines);

  setUp(() => fetches = 0);

  test('restoreFromDevice brings the saved cart back with NO catalogue read',
      () async {
    final prefs = await prefsWith({
      'mx.cart.v1': savedCart([
        {'productId': 'a', 'quantity': 2},
        {'productId': 'b', 'quantity': 1},
      ]),
      'mx.location.v1': jsonEncode({
        'latitude': 12.29,
        'longitude': 76.63,
        'label': 'Home',
      }),
    });
    final repo = repoWith(prefs, [product('a'), product('b')]);

    repo.restoreFromDevice();

    expect(fetches, 0, reason: 'the device half must never touch the network');
    expect(repo.items, {'a': 2, 'b': 1});
    expect(repo.totalQuantity, 3);
    // The saved delivery point comes back too - it is the device's own.
    expect(repo.location, isNotNull);
    expect(repo.location!.latitude, closeTo(12.29, 1e-9));
  });

  test('an empty device restores an empty cart', () async {
    final prefs = await prefsWith({});
    final repo = repoWith(prefs, [product('a')]);

    repo.restoreFromDevice();

    expect(repo.items, isEmpty);
    expect(repo.location, isNull);
    expect(fetches, 0);
  });

  test('the cart restored from the device is NOT thrown away for want of a '
      'catalogue', () async {
    final prefs = await prefsWith({
      'mx.cart.v1': savedCart([
        {'productId': 'a', 'quantity': 3},
      ]),
    });
    final repo = repoWith(prefs, [product('a')]);

    repo.restoreFromDevice();

    // The whole point: a cart checked against an empty catalogue would be
    // wiped, and the customer would find their basket empty on every launch.
    expect(repo.items, {'a': 3});
  });

  test('refreshCatalog drops a product that is no longer in the catalogue',
      () async {
    final prefs = await prefsWith({
      'mx.cart.v1': savedCart([
        {'productId': 'a', 'quantity': 2},
        {'productId': 'gone', 'quantity': 1},
      ]),
    });
    final repo = repoWith(prefs, [product('a')]);

    repo.restoreFromDevice();
    await repo.refreshCatalog();

    expect(fetches, 1);
    expect(repo.items, {'a': 2});
  });

  test('refreshCatalog drops a product that has gone out of stock', () async {
    final prefs = await prefsWith({
      'mx.cart.v1': savedCart([
        {'productId': 'a', 'quantity': 2},
        {'productId': 'sold', 'quantity': 1},
      ]),
    });
    final repo = repoWith(prefs, [
      product('a'),
      product('sold', inStock: false),
    ]);

    repo.restoreFromDevice();
    await repo.refreshCatalog();

    expect(repo.items, {'a': 2});
    expect(repo.lines.map((l) => l.product.id), ['a']);
  });

  test('refreshCatalog clamps a quantity that is no longer available',
      () async {
    final prefs = await prefsWith({
      'mx.cart.v1': savedCart([
        {'productId': 'a', 'quantity': 9},
      ]),
    });
    final repo = repoWith(prefs, [product('a', stock: 2)]);

    repo.restoreFromDevice();
    await repo.refreshCatalog();

    expect(repo.items, {'a': 2});
  });

  test('load() is still exactly the two halves, in that order', () async {
    final prefs = await prefsWith({
      'mx.cart.v1': savedCart([
        {'productId': 'a', 'quantity': 2},
        {'productId': 'gone', 'quantity': 1},
      ]),
    });
    final repo = repoWith(prefs, [product('a')]);

    await repo.load();

    expect(fetches, 1);
    expect(repo.items, {'a': 2});
    // Lines resolve because the catalogue did arrive by the end of load().
    expect(repo.lines.map((l) => l.product.id), ['a']);
  });
}

/// A catalogue that records how often it was read.
class _CountingRepo implements ProductRepository {
  _CountingRepo(this._catalog, this._onFetch);

  final List<Product> _catalog;
  final void Function() _onFetch;

  @override
  Future<List<Product>> fetchAll() async {
    _onFetch();
    return _catalog;
  }

  @override
  Future<Product?> fetchById(String id) async {
    for (final p in _catalog) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<List<Product>> fetchByCategory(String category) async =>
      _catalog.where((p) => p.category == category).toList();
}
