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
/// remoteChange delivers a snapshot from "another device" (the controller no
/// longer listens - nothing may auto-apply, so these must never land in the
/// local cart).
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

/// Waits out the sign-in fetch and the 400ms push debounce.
Future<void> _settle([int ms = 120]) =>
    Future<void>.delayed(Duration(milliseconds: ms));
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'sign-in only READS the account cart - the local cart never changes',
    () async {
      final (repo, cart, _) = await _loadedCart();
      await repo.add('fresh-oyster-250', 2); // guest items on this device
      final auth = _FakeAuth();
      final store = _FakeStore()
        ..cart = {
          'fresh-oyster-250': 1,
          'fresh-oyster-500': 4, // account holds MORE of another line
        };
      final sync = CartSyncController(
        repository: repo,
        cart: cart,
        auth: auth,
        store: store,
        backendAvailable: true,
      )..start();

      auth.uid = 'u1';
      await _settle();

      // Not a single item changed: no merge, no sum, no apply, no removal.
      expect(repo.items, {'fresh-oyster-250': 2});
      expect(cart.lines.map((l) => l.quantity), [2]);
      // And nothing was pushed either - signing in never writes the account.
      expect(store.pushed, isEmpty);
      expect(store.fetches, 1);
      // The account knowledge is available so the cart page can OFFER a load.
      expect(sync.hasSavedCart, isTrue);
      sync.dispose();
    },
  );

  test(
    'a session restored at startup also never touches the local cart',
    () async {
      final (repo, cart, _) = await _loadedCart();
      await repo.add('fresh-oyster-250', 1);
      final auth = _FakeAuth()..uid = 'u-persisted';
      final store = _FakeStore()..cart = {'fresh-oyster-500': 3};
      final sync = CartSyncController(
        repository: repo,
        cart: cart,
        auth: auth,
        store: store,
        backendAvailable: true,
      )..start();
      await _settle();

      expect(store.fetches, 1);
      expect(repo.items, {'fresh-oyster-250': 1});
      expect(store.pushed, isEmpty);
      expect(sync.hasSavedCart, isTrue);
      sync.dispose();
    },
  );

  test(
    'offline account cart leaves the guest cart untouched, no offer',
    () async {
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
      await _settle();

      expect(repo.items, {'fresh-oyster-250': 2});
      expect(store.fetches, 1);
      expect(sync.hasSavedCart, isFalse);
      sync.dispose();
    },
  );
  test(
    'a local change is written through (debounced) while signed in',
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
      await _settle();
      expect(repo.items, <String, int>{}); // sign-in added nothing

      cart.add(_p(products, 'fresh-oyster-250'), quantity: 2);
      await _settle(700);

      // Exactly one push - the customer's own edit - and no echo loop.
      expect(store.pushed, [
        {'fresh-oyster-250': 2},
      ]);
      sync.dispose();
    },
  );

  test('a change from ANOTHER DEVICE never touches the local cart', () async {
    final (repo, cart, _) = await _loadedCart();
    await repo.add('fresh-oyster-250', 2);
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
    await _settle();
    expect(sync.hasSavedCart, isFalse); // account matches this cart

    // Another device changes the account cart while signed in.
    store.remoteChange({'fresh-oyster-250': 5, 'fresh-oyster-500': 1});
    await _settle();

    // The local cart is completely untouched - no watch, no auto-apply.
    expect(repo.items, {'fresh-oyster-250': 2});
    // The offer is not even re-armed mid-session (knowledge refreshes only
    // on a fresh sign-in or after a push).
    expect(sync.hasSavedCart, isFalse);
    sync.dispose();
  });

  test('load merges account items into the cart on the explicit tap', () async {
    final (repo, cart, _) = await _loadedCart();
    await repo.add('fresh-oyster-250', 2);
    final auth = _FakeAuth();
    final store = _FakeStore()
      ..cart = {'fresh-oyster-250': 1, 'fresh-oyster-500': 2};
    final sync = CartSyncController(
      repository: repo,
      cart: cart,
      auth: auth,
      store: store,
      backendAvailable: true,
    )..start();
    auth.uid = 'u1';
    await _settle();
    expect(sync.hasSavedCart, isTrue);

    await sync.loadAccountCart();
    await _settle(700);

    // The saved items were merged in: 2 + 1 summed, the other line added.
    expect(repo.items, {'fresh-oyster-250': 3, 'fresh-oyster-500': 2});
    // The merged cart was written through to the account once.
    expect(store.pushed, [
      {'fresh-oyster-250': 3, 'fresh-oyster-500': 2},
    ]);
    expect(sync.hasSavedCart, isFalse); // offer disappears
    sync.dispose();
  });

  test('loadAccountCart is a no-op when signed out (no stale merge)', () async {
    final (repo, cart, _) = await _loadedCart();
    await repo.add('fresh-oyster-250', 1);
    final auth = _FakeAuth();
    final store = _FakeStore()..cart = {'fresh-oyster-500': 2};
    final sync = CartSyncController(
      repository: repo,
      cart: cart,
      auth: auth,
      store: store,
      backendAvailable: true,
    )..start();
    await sync.loadAccountCart(); // never signed in
    expect(repo.items, {'fresh-oyster-250': 1});
    expect(store.pushed, isEmpty);
    sync.dispose();
  });
  test(
    'sign-out keeps the local cart and drops the saved-cart offer',
    () async {
      final (repo, cart, _) = await _loadedCart();
      final auth = _FakeAuth();
      final store = _FakeStore()..cart = {'fresh-oyster-500': 2};
      final sync = CartSyncController(
        repository: repo,
        cart: cart,
        auth: auth,
        store: store,
        backendAvailable: true,
      )..start();
      auth.uid = 'u1';
      await _settle();
      expect(sync.hasSavedCart, isTrue);

      auth.uid = null;
      await _settle();

      // The guest cart keeps exactly what was there - nothing removed, nothing
      // reverted, nothing merged in at the last moment.
      expect(repo.items, <String, int>{});
      expect(store.pushed, isEmpty);
      expect(sync.hasSavedCart, isFalse);
      expect(sync.syncedUid, isNull);
      sync.dispose();
    },
  );

  test(
    'a dormant controller (backend offline) never touches the store',
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
      await _settle();

      expect(store.fetches, 0);
      expect(store.pushed, isEmpty);
      expect(repo.items, {'fresh-oyster-250': 1});
      expect(sync.hasSavedCart, isFalse);
      sync.dispose();
    },
  );
}
