import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/models/product.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/repositories/remote_cart_store.dart';
import 'package:mycosix/state/cart_controller.dart';
import 'package:mycosix/state/cart_sync_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuth extends ChangeNotifier implements CartSyncAuth {
  String? _uid;

  @override
  String? get uid => _uid;

  set uid(String? value) {
    _uid = value;
    notifyListeners();
  }
}

/// Behaves like the Firestore document: push writes and echoes a snapshot,
/// remoteChange delivers a snapshot from "another device".
class _FakeStore implements RemoteCartStore {
  Map<String, int> cart = {};
  final _snapshots = StreamController<Map<String, int>>.broadcast();
  final List<Map<String, int>> pushed = [];
  int fetches = 0;
  bool fetchShouldFail = false;

  @override
  Future<Map<String, int>> fetch(String uid) async {
    fetches++;
    if (fetchShouldFail) throw Exception('offline');
    return Map.of(cart);
  }

  @override
  Stream<Map<String, int>> watch(String uid) => _snapshots.stream;

  @override
  Future<void> push(String uid, Map<String, int> items) async {
    pushed.add(Map.of(items));
    cart = Map.of(items);
    _snapshots.add(Map.of(items)); // snapshot echo, like Firestore
  }

  void remoteChange(Map<String, int> items) {
    cart = Map.of(items);
    _snapshots.add(Map.of(items));
  }
}

Future<(CartRepository, CartController, List<Product>)> _loadedCart() async {
  final prefs = await SharedPreferences.getInstance();
  final products = LocalProductRepository();
  final repo = CartRepository(prefs, products);
  await repo.load();
  final cart = CartController(repo, siteDeliveryFee: 39);
  final all = await products.fetchAll();
  return (repo, cart, all);
}

Product _p(List<Product> products, String id) =>
    products.firstWhere((p) => p.id == id);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('sign-in merges guest and account carts, clamped, then pushes',
      () async {
    final (repo, cart, _) = await _loadedCart();
    await repo.add('fresh-oyster-250', 2); // guest items on this device
    final auth = _FakeAuth();
    final store = _FakeStore()
      ..cart = {
        'fresh-oyster-250': 1,
        'oyster-pickle-250': 3, // unavailable -> dropped
        'not-a-product': 9, // unknown -> dropped
      };
    final sync = CartSyncController(
      repository: repo,
      cart: cart,
      auth: auth,
      store: store,
      backendAvailable: true,
    )..start();

    auth.uid = 'u1';
    await Future<void>.delayed(const Duration(milliseconds: 80));

    // 2 (guest) + 1 (account) = 3, within the cap; nothing else survived.
    expect(repo.items, {'fresh-oyster-250': 3});
    expect(cart.lines.map((l) => l.quantity), [3]);
    // The merged cart was pushed to the account.
    expect(store.pushed, [
      {'fresh-oyster-250': 3}
    ]);
    sync.dispose();
  });

  test('offline account cart leaves the guest cart untouched', () async {
    final (repo, cart, _) = await _loadedCart();
    await repo.add('fresh-oyster-250', 2);
    final auth = _FakeAuth();
    final store = _FakeStore()..fetchShouldFail = true;
    final sync = CartSyncController(
      repository: repo,
      cart: cart,
      auth: auth,
      store: store,
      backendAvailable: true,
    )..start();

    auth.uid = 'u1';
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(repo.items, {'fresh-oyster-250': 2});
    expect(store.fetches, 1);
    sync.dispose();
  });

  test('a local change is written through (debounced), echo ignored',
      () async {
    final (repo, cart, products) = await _loadedCart();
    final auth = _FakeAuth();
    final store = _FakeStore()..cart = {'fresh-oyster-500': 1};
    final sync = CartSyncController(
      repository: repo,
      cart: cart,
      auth: auth,
      store: store,
      backendAvailable: true,
    )..start();
    auth.uid = 'u1';
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(repo.items, {'fresh-oyster-500': 1});

    cart.add(_p(products, 'fresh-oyster-250'), quantity: 2);
    await Future<void>.delayed(const Duration(milliseconds: 700));

    // One merge push + one write-through push; no echo loop in between.
    expect(store.pushed.last, {
      'fresh-oyster-500': 1,
      'fresh-oyster-250': 2,
    });
    expect(store.pushed.length, 2);
    sync.dispose();
  });

  test('a remote change from another device is applied locally', () async {
    final (repo, cart, _) = await _loadedCart();
    final auth = _FakeAuth();
    final store = _FakeStore()..cart = {'fresh-oyster-250': 2};
    final sync = CartSyncController(
      repository: repo,
      cart: cart,
      auth: auth,
      store: store,
      backendAvailable: true,
    )..start();
    auth.uid = 'u1';
    await Future<void>.delayed(const Duration(milliseconds: 80));

    store.remoteChange({'fresh-oyster-250': 5, 'fresh-oyster-500': 1});
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(repo.items, {'fresh-oyster-250': 5, 'fresh-oyster-500': 1});
    sync.dispose();
  });

  test('a pending local edit wins over a racing remote snapshot', () async {
    final (repo, cart, products) = await _loadedCart();
    final auth = _FakeAuth();
    final store = _FakeStore()..cart = {'fresh-oyster-250': 3};
    final sync = CartSyncController(
      repository: repo,
      cart: cart,
      auth: auth,
      store: store,
      backendAvailable: true,
    )..start();
    auth.uid = 'u1';
    await Future<void>.delayed(const Duration(milliseconds: 80));

    // Local edit starts its debounced write; a remote snapshot races it.
    cart.increment(_p(products, 'fresh-oyster-250')); // 3 -> 4, push pending
    store.remoteChange({'fresh-oyster-250': 9}); // stale other-device edit
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(repo.items, {'fresh-oyster-250': 4});
    expect(store.cart, {'fresh-oyster-250': 4});
    sync.dispose();
  });

  test('sign-out stops the account watch and keeps the local cart', () async {
    final (repo, cart, _) = await _loadedCart();
    final auth = _FakeAuth();
    final store = _FakeStore()..cart = {'fresh-oyster-250': 2};
    final sync = CartSyncController(
      repository: repo,
      cart: cart,
      auth: auth,
      store: store,
      backendAvailable: true,
    )..start();
    auth.uid = 'u1';
    await Future<void>.delayed(const Duration(milliseconds: 80));

    auth.uid = null;
    await Future<void>.delayed(const Duration(milliseconds: 60));

    // The guest session keeps exactly what was in the cart.
    expect(repo.items, {'fresh-oyster-250': 2});

    // Changes from "another device" no longer touch this device.
    store.remoteChange({'fresh-oyster-250': 7});
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(repo.items, {'fresh-oyster-250': 2});
    sync.dispose();
  });

  test('a dormant controller (backend offline) never touches the store',
      () async {
    final (repo, cart, _) = await _loadedCart();
    await repo.add('fresh-oyster-250', 1);
    final auth = _FakeAuth();
    final store = _FakeStore();
    final sync = CartSyncController(
      repository: repo,
      cart: cart,
      auth: auth,
      store: store,
      backendAvailable: false,
    )..start();

    auth.uid = 'u1';
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(store.fetches, 0);
    expect(store.pushed, isEmpty);
    expect(repo.items, {'fresh-oyster-250': 1});
    sync.dispose();
  });
}
