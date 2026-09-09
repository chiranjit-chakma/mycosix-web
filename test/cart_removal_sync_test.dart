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

/// REMOVAL PROPAGATION: a removal on one device must reach every other device
/// signed into the same account, and a stale device must never resurrect a
/// removed item.
///
/// The mechanism is the account-wide TOMBSTONE list (`removed` on the cart
/// document). [reconcileAccountCart] (pure) computes what a device may push;
/// the fake-store scenarios exercise the full sync controller on two devices
/// sharing one account document.
void main() {
  group('reconcileAccountCart (pure)', () {
    ReconcileResult reconcile({
      Map<String, int> accountItems = const {},
      List<String> accountRemoved = const [],
      Map<String, int> localItems = const {},
      Set<String> addedPending = const {},
      Set<String> removedPending = const {},
    }) {
      return reconcileAccountCart(
        accountItems: accountItems,
        accountRemoved: accountRemoved,
        localItems: localItems,
        addedPending: addedPending,
        removedPending: removedPending,
        capFor: (_) => 50, // every product available, well above test qtys
      );
    }

    test('a removal becomes a tombstone account-wide', () {
      final r = reconcile(
        accountItems: {'x': 2, 'y': 1},
        removedPending: {'x'},
      );
      expect(r.items, {'y': 1});
      expect(r.removed, ['x']);
    });

    test('an explicit re-add lifts the tombstone again', () {
      final r = reconcile(
        accountItems: {'y': 1},
        accountRemoved: ['x'],
        localItems: {'x': 1},
        addedPending: {'x'},
      );
      expect(r.items, {'y': 1, 'x': 1});
      expect(r.removed, isEmpty);
    });

    test('a stale hold never resurrects a tombstoned item', () {
      final r = reconcile(
        accountItems: {'y': 1},
        accountRemoved: ['x'],
        localItems: {'x': 3},
      );
      expect(r.items, {'y': 1});
      expect(r.removed, ['x']);
    });

    test('quantities are the top-up union - never summed, never shrunk', () {
      final r = reconcile(
        accountItems: {'x': 2, 'z': 3},
        localItems: {'x': 2, 'z': 3},
      );
      expect(r.items, {'x': 2, 'z': 3});
      final raised = reconcile(accountItems: {'x': 5}, localItems: {'x': 2});
      expect(raised.items, {'x': 5});
    });

    test('new tombstones append after the account order (newest last)', () {
      final r = reconcile(
        accountRemoved: ['a', 'b'],
        removedPending: {'c'},
      );
      expect(r.removed, ['a', 'b', 'c']);
    });

    test('remove then re-add on the same device cancels the tombstone', () {
      final r = reconcile(
        accountItems: {'x': 1},
        localItems: {'x': 1},
        addedPending: {'x'}, // removed, then re-added before the push
      );
      expect(r.items, {'x': 1});
      expect(r.removed, isEmpty);
    });

    test('a device that never carried a tombstoned line is unaffected', () {
      final r = reconcile(
        accountItems: {'y': 1},
        accountRemoved: ['x'],
        localItems: {'y': 1},
      );
      expect(r.items, {'y': 1});
      expect(r.removed, ['x']);
    });
  });

  group('two devices, one account', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'a removal on device A propagates to device B on its next snapshot',
      () async {
        final store = _FakeStore()..cart = _snap({'fresh-oyster-250': 2});
        final a = await _device(store);
        final b = await _device(store);
        a.auth.uid = 'u1';
        b.auth.uid = 'u1';
        await _settle();
        expect(a.repo.items, {'fresh-oyster-250': 2});
        expect(b.repo.items, {'fresh-oyster-250': 2});

        // Device A removes the product: the debounced push tombstones it
        // account-wide.
        a.cart.remove(_p(a.products, 'fresh-oyster-250'));
        await _settle(700);
        expect(store.cart.items, isEmpty);
        expect(store.cart.removed, ['fresh-oyster-250']);

        // Device B's live watch delivers the tombstone and the line is dropped
        // by itself - never written back, never resurrected.
        await _settle();
        expect(b.repo.items, isEmpty);
        expect(store.cart.items, isEmpty);
        expect(store.cart.removed, ['fresh-oyster-250']);
      },
    );

    test('an explicit re-add on another device lifts the tombstone again',
        () async {
      final store = _FakeStore()..cart = _snap({'fresh-oyster-250': 2});
      final a = await _device(store);
      final b = await _device(store);
      a.auth.uid = 'u1';
      b.auth.uid = 'u1';
      await _settle();

      a.cart.remove(_p(a.products, 'fresh-oyster-250'));
      await _settle(700);
      await _settle();
      expect(b.repo.items, isEmpty);

      // Device B explicitly re-adds the product: the tombstone is lifted.
      b.cart.add(_p(b.products, 'fresh-oyster-250'), quantity: 2);
      await _settle(700);
      expect(store.cart.items, {'fresh-oyster-250': 2});
      expect(store.cart.removed, isEmpty);
      // And the resurrection reaches device A too.
      await _settle();
      expect(a.repo.items, {'fresh-oyster-250': 2});
    });

    test('a device offline when the removal lands drops it on re-sign-in',
        () async {
      final store = _FakeStore();
      final a = await _device(store);
      final b = await _device(store);
      a.auth.uid = 'u1';
      b.auth.uid = 'u1';
      await _settle();
      b.cart.add(_p(b.products, 'fresh-oyster-250'), quantity: 2);
      await _settle(700);
      expect(b.repo.items, {'fresh-oyster-250': 2}); // pushed and acked

      // B goes offline (signs out, keeping the item in its local cart).
      b.auth.uid = null;
      await _settle();

      // A removes the product while B is away.
      a.cart.remove(_p(a.products, 'fresh-oyster-250'));
      await _settle(700);
      expect(store.cart.removed, ['fresh-oyster-250']);

      // B comes back: the first live snapshot tombstones the line and B drops
      // it - never pushing it back, so nothing is resurrected.
      b.auth.uid = 'u1';
      await _settle();
      await _settle(700);
      expect(b.repo.items, isEmpty);
      expect(store.cart.items, isEmpty);
      expect(store.cart.removed, ['fresh-oyster-250']);
    });

    test('a rapid remove then re-add on one device leaves no tombstone',
        () async {
      final store = _FakeStore()..cart = _snap({'fresh-oyster-250': 1});
      final a = await _device(store);
      a.auth.uid = 'u1';
      await _settle();
      final product = _p(a.products, 'fresh-oyster-250');
      a.cart.remove(product);
      a.cart.add(product);
      await _settle(700);
      // The two edits coalesced into one push: the line is intact and no
      // tombstone was ever written.
      expect(a.repo.items, {'fresh-oyster-250': 1});
      expect(store.cart.items, {'fresh-oyster-250': 1});
      expect(store.cart.removed, isEmpty);
    });

    test('a tombstone for an item this device never carried is harmless',
        () async {
      final store = _FakeStore()
        ..cart = _snap(
          {'fresh-oyster-500': 1},
          removed: ['fresh-oyster-250'],
        );
      final b = await _device(store);
      b.auth.uid = 'u1';
      await _settle();
      // The tombstone did not disturb the 500 line, and nothing was written
      // back (the account already mirrors this cart exactly).
      expect(b.repo.items, {'fresh-oyster-500': 1});
      expect(store.pushed, isEmpty);
    });
  });
}

RemoteCartSnapshot _snap(
  Map<String, int> items, {
  List<String> removed = const [],
}) =>
    RemoteCartSnapshot(items: items, removed: removed);

class _FakeAuth extends ChangeNotifier implements CartSyncAuth {
  String? _uid;

  @override
  String? get uid => _uid;

  set uid(String? value) {
    _uid = value;
    notifyListeners();
  }
}

/// One account document shared by both devices, exactly like Firestore:
/// fetch returns the current cart, watch yields it first then live changes,
/// and push writes through and echoes a snapshot to every watcher.
class _FakeStore implements RemoteCartStore {
  RemoteCartSnapshot cart = const RemoteCartSnapshot(items: {});
  final List<RemoteCartSnapshot> pushed = [];
  final _snapshots = StreamController<RemoteCartSnapshot>.broadcast();

  @override
  Future<RemoteCartSnapshot> fetch(String uid) async => RemoteCartSnapshot(
        items: Map.of(cart.items),
        removed: List.of(cart.removed),
      );

  @override
  Stream<RemoteCartSnapshot> watch(String uid) async* {
    yield RemoteCartSnapshot(
      items: Map.of(cart.items),
      removed: List.of(cart.removed),
    );
    yield* _snapshots.stream;
  }

  @override
  Future<void> push(String uid, RemoteCartSnapshot snapshot) async {
    pushed.add(RemoteCartSnapshot(
      items: Map.of(snapshot.items),
      removed: List.of(snapshot.removed),
    ));
    cart = RemoteCartSnapshot(
      items: Map.of(snapshot.items),
      removed: List.of(snapshot.removed),
    );
    _snapshots.add(RemoteCartSnapshot(
      items: Map.of(snapshot.items),
      removed: List.of(snapshot.removed),
    )); // snapshot echo to every device, like Firestore
  }
}

class _Device {
  _Device(this.repo, this.cart, this.sync, this.auth, this.products);

  final CartRepository repo;
  final CartController cart;
  final CartSyncController sync;
  final _FakeAuth auth;
  final List<Product> products;
}

/// A fresh signed-out device: its own local cart storage, sharing only the
/// [store] account document with other devices.
Future<_Device> _device(_FakeStore store) async {
  // Fresh local storage per device (the previous device's persisted cart must
  // not leak into this one).
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final products = LocalProductRepository();
  final repo = CartRepository(prefs, products);
  await repo.load();
  final cart = CartController(repo, siteDeliveryFee: 39);
  final auth = _FakeAuth();
  final sync = CartSyncController(
    repository: repo,
    cart: cart,
    auth: auth,
    store: store,
    backendAvailable: true,
  )..start();
  return _Device(repo, cart, sync, auth, await products.fetchAll());
}

Product _p(List<Product> products, String id) =>
    products.firstWhere((p) => p.id == id);

/// Waits out the sign-in fetch, the first live snapshot and the 400ms push
/// debounce.
Future<void> _settle([int ms = 120]) =>
    Future<void>.delayed(Duration(milliseconds: ms));
