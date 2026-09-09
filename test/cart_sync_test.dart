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

/// Behaves like the Firestore document: fetch returns the account cart, watch
/// yields the current cart first and then live snapshots (exactly like the
/// document's snapshot stream), push writes through and echoes a snapshot,
/// and remoteChange delivers a snapshot from "another device". With
/// [watchShouldFail] the watch errors instead, like a stream that cannot
/// connect - the controller then keeps the load offer as its fallback.
class _FakeStore implements RemoteCartStore {
  RemoteCartSnapshot cart = const RemoteCartSnapshot(items: {});
  final _snapshots = StreamController<RemoteCartSnapshot>.broadcast();
  final List<RemoteCartSnapshot> pushed = [];
  int fetches = 0;
  bool fetchShouldFail = false;
  bool watchShouldFail = false;

  /// When set, fetch waits on this gate (a slow account read) so tests can
  /// interleave a local edit with the sign-in fetch.
  Completer<void>? fetchGate;

  @override
  Future<RemoteCartSnapshot> fetch(String uid) async {
    fetches++;
    if (fetchShouldFail) throw Exception('offline');
    final gate = fetchGate;
    if (gate != null) await gate.future;
    return RemoteCartSnapshot(
      items: Map.of(cart.items),
      removed: List.of(cart.removed),
    );
  }

  @override
  Stream<RemoteCartSnapshot> watch(String uid) async* {
    if (watchShouldFail) {
      yield* Stream<RemoteCartSnapshot>.error(Exception('watch offline'));
      return;
    }
    // Like a Firestore snapshot stream: the current document first, then
    // live changes.
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
    )); // snapshot echo, like Firestore
  }

  void remoteChange(RemoteCartSnapshot snapshot) {
    cart = snapshot;
    _snapshots.add(snapshot);
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

/// Waits out the sign-in fetch, the first live snapshot and the 400ms push
/// debounce.
Future<void> _settle([int ms = 120]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// A cart snapshot holding [items] (no tombstones).
RemoteCartSnapshot _snap(Map<String, int> items) =>
    RemoteCartSnapshot(items: items);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'sign-in tops the cart up to the account when the account holds more',
    () async {
      final (repo, cart, _) = await _loadedCart();
      await repo.add('fresh-oyster-250', 2); // guest items on this device
      final auth = _FakeAuth();
      final store = _FakeStore()
        ..cart = _snap({
          'fresh-oyster-250': 1,
          'fresh-oyster-500': 4, // account holds MORE of another line
        });
      final sync = CartSyncController(
        repository: repo,
        cart: cart,
        auth: auth,
        store: store,
        backendAvailable: true,
      )..start();

      auth.uid = 'u1';
      await _settle();

      // The live sync topped this cart up to the union - never summed (250
      // stays at 2, not 3) and nothing removed.
      expect(repo.items, {'fresh-oyster-250': 2, 'fresh-oyster-500': 4});
      expect(cart.lines.map((l) => l.quantity), [2, 4]);
      // The union was mirrored back to the account immediately, so the other
      // device converges too.
      expect(store.pushed, [
        _snap({'fresh-oyster-250': 2, 'fresh-oyster-500': 4}),
      ]);
      expect(store.fetches, 1);
      // Account and cart now match - no offer left standing.
      expect(sync.hasSavedCart, isFalse);
      expect(sync.savedOfferVisible, isFalse);
      sync.dispose();
    },
  );

  test(
    'a session restored at startup tops the cart up too',
    () async {
      final (repo, cart, _) = await _loadedCart();
      await repo.add('fresh-oyster-250', 1);
      final auth = _FakeAuth()..uid = 'u-persisted';
      final store = _FakeStore()..cart = _snap({'fresh-oyster-500': 3});
      final sync = CartSyncController(
        repository: repo,
        cart: cart,
        auth: auth,
        store: store,
        backendAvailable: true,
      )..start();
      await _settle();

      expect(store.fetches, 1);
      expect(repo.items, {'fresh-oyster-250': 1, 'fresh-oyster-500': 3});
      expect(store.pushed, [
        _snap({'fresh-oyster-250': 1, 'fresh-oyster-500': 3}),
      ]);
      expect(sync.hasSavedCart, isFalse);
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
      final store = _FakeStore()..cart = _snap({'fresh-oyster-500': 1});
      final sync = CartSyncController(
        repository: repo,
        cart: cart,
        auth: auth,
        store: store,
        backendAvailable: true,
      )..start();
      auth.uid = 'u1';
      await _settle();
      // The live sync merged the account's line in (the account already held
      // exactly that union, so no write was needed).
      expect(repo.items, {'fresh-oyster-500': 1});

      cart.add(_p(products, 'fresh-oyster-250'), quantity: 2);
      await _settle(700);

      // Exactly one debounced push carrying the customer's own edit - and no
      // echo loop beyond it.
      expect(store.pushed, [
        _snap({'fresh-oyster-500': 1, 'fresh-oyster-250': 2}),
      ]);
      sync.dispose();
    },
  );

  test(
    'a change from ANOTHER DEVICE tops this cart up to the union on its own',
    () async {
      final (repo, cart, _) = await _loadedCart();
      await repo.add('fresh-oyster-250', 2);
      final auth = _FakeAuth();
      final store = _FakeStore()..cart = _snap({'fresh-oyster-250': 2});
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

      // Another device raises a line and adds a new one while signed in.
      store.remoteChange(_snap({'fresh-oyster-250': 5, 'fresh-oyster-500': 1}));
      await _settle();

      // This cart is topped up to the union on its own - no banner, no tap.
      expect(repo.items, {'fresh-oyster-250': 5, 'fresh-oyster-500': 1});
      // The snapshot ALREADY held the union, so no write-back was needed: the
      // other device is already converged.
      expect(store.pushed, isEmpty);
      // The echoed union holds nothing more - the merge loop ends here.
      store.remoteChange(_snap({'fresh-oyster-250': 5, 'fresh-oyster-500': 1}));
      await _settle();
      expect(store.pushed, isEmpty);
      sync.dispose();
    },
  );

  test(
    'a remote snapshot never shrinks the cart (an emptier account is ignored)',
    () async {
      final (repo, cart, _) = await _loadedCart();
      await repo.add('fresh-oyster-250', 5);
      final auth = _FakeAuth();
      final store = _FakeStore()..cart = _snap({'fresh-oyster-250': 5});
      final sync = CartSyncController(
        repository: repo,
        cart: cart,
        auth: auth,
        store: store,
        backendAvailable: true,
      )..start();
      auth.uid = 'u1';
      await _settle();
      expect(repo.items, {'fresh-oyster-250': 5});

      // Another device lowers the line (or removes it): this cart never
      // shrinks, and the union (5) is mirrored back so the account is raised
      // again - devices converge on the union, never on the lower copy.
      store.remoteChange(_snap({'fresh-oyster-250': 2}));
      await _settle();
      expect(repo.items, {'fresh-oyster-250': 5});
      expect(store.pushed, [
        _snap({'fresh-oyster-250': 5}),
      ]);

      // A snapshot holding MORE of a DIFFERENT line still merges, but only
      // tops up the 500 line - the 250 line is never reduced to the account's
      // lower copy, and the union (not the snapshot) is what reaches the
      // account.
      store.remoteChange(_snap({'fresh-oyster-250': 1, 'fresh-oyster-500': 3}));
      await _settle();
      expect(repo.items, {'fresh-oyster-250': 5, 'fresh-oyster-500': 3});
      expect(store.pushed, [
        _snap({'fresh-oyster-250': 5}),
        _snap({'fresh-oyster-250': 5, 'fresh-oyster-500': 3}),
      ]);
      sync.dispose();
    },
  );

  test(
    'when the live watch fails, the offer is the fallback and Load tops up',
    () async {
      final (repo, cart, _) = await _loadedCart();
      await repo.add('fresh-oyster-250', 2);
      final auth = _FakeAuth();
      final store = _FakeStore()
        ..cart = _snap({'fresh-oyster-250': 1, 'fresh-oyster-500': 2})
        ..watchShouldFail = true;
      final sync = CartSyncController(
        repository: repo,
        cart: cart,
        auth: auth,
        store: store,
        backendAvailable: true,
      )..start();
      auth.uid = 'u1';
      await _settle();
      // The watch could not connect: the account knowledge from the read is
      // still offered, so nothing is stranded.
      expect(sync.savedOfferVisible, isTrue);
      expect(sync.hasSavedCart, isTrue);

      await sync.loadAccountCart();
      // Topped up, not summed: 250 stays at 2 (the account's 1 is this
      // cart's own mirror), and the account's 500 line is added at 2.
      expect(repo.items, {'fresh-oyster-250': 2, 'fresh-oyster-500': 2});
      // The merged cart reached the account INSIDE the load call - there is
      // no debounce window left to lose it in.
      expect(store.pushed, [
        _snap({'fresh-oyster-250': 2, 'fresh-oyster-500': 2}),
      ]);
      expect(sync.savedOfferVisible, isFalse); // offer disappears
      expect(sync.hasSavedCart, isFalse);
      // And the load itself triggered no duplicate debounced write.
      await _settle(700);
      expect(store.pushed, hasLength(1));
      sync.dispose();
    },
  );

  test(
    'the same-device mirror echo can never inflate a quantity',
    () async {
      // Session 1 signed in: 2 units were mirrored to the account, then the
      // customer signed out and the cart kept them as the guest cart.
      final (repo, cart, products) = await _loadedCart();
      await repo.add('fresh-oyster-250', 2);
      final auth = _FakeAuth();
      final store = _FakeStore()..cart = _snap({'fresh-oyster-250': 2});
      final sync = CartSyncController(
        repository: repo,
        cart: cart,
        auth: auth,
        store: store,
        backendAvailable: true,
      )..start();
      auth.uid = 'u1';
      await _settle();
      // Account and cart match - nothing is even offered.
      expect(sync.hasSavedCart, isFalse);

      // Guest edits do not reach the account while signed out: one more unit
      // is added, then the customer logs back in.
      auth.uid = null;
      await _settle();
      cart.add(_p(products, 'fresh-oyster-250'));
      auth.uid = 'u1';
      await _settle();

      // The account's 2 is this cart's own mirror; the cart now holds 3, so
      // there is nothing to load and the account is topped up to the union
      // (3) - never summed, so no quantity can be inflated.
      expect(repo.items, {'fresh-oyster-250': 3});
      expect(sync.hasSavedCart, isFalse);
      expect(store.pushed, [
        _snap({'fresh-oyster-250': 3}),
      ]);
      sync.dispose();
    },
  );

  test(
    'signing out right after the live-sync merge cannot lose the merge',
    () async {
      final (repo, cart, _) = await _loadedCart();
      await repo.add('fresh-oyster-250', 1);
      final auth = _FakeAuth();
      final store = _FakeStore()..cart = _snap({'fresh-oyster-500': 2});
      final sync = CartSyncController(
        repository: repo,
        cart: cart,
        auth: auth,
        store: store,
        backendAvailable: true,
      )..start();
      auth.uid = 'u1';
      await _settle();
      // The live sync already merged the account's items and mirrored the
      // union back - there is no debounce window left to lose anything in.
      expect(store.pushed, hasLength(1));
      expect(repo.items, {'fresh-oyster-250': 1, 'fresh-oyster-500': 2});

      // An immediate logout (which cancels the debounce and the watch)
      // loses nothing.
      auth.uid = null;
      await _settle();
      expect(store.cart.items, {'fresh-oyster-250': 1, 'fresh-oyster-500': 2});
      expect(repo.items, {'fresh-oyster-250': 1, 'fresh-oyster-500': 2});

      // The next login reads the merged cart: nothing to offer, and a stray
      // load is a no-op - the same saved cart can never be counted twice.
      auth.uid = 'u1';
      await _settle();
      expect(sync.hasSavedCart, isFalse);
      final before = Map.of(repo.items);
      await sync.loadAccountCart();
      expect(repo.items, before);
      expect(store.pushed, hasLength(1));
      sync.dispose();
    },
  );

  test(
    'edits during the sign-in read are never clobbered - live sync brings the '
    'unseen items in',
    () async {
      final (repo, cart, products) = await _loadedCart();
      final auth = _FakeAuth();
      final store = _FakeStore()
        ..cart = _snap({'fresh-oyster-500': 4})
        ..fetchGate = Completer<void>();
      final sync = CartSyncController(
        repository: repo,
        cart: cart,
        auth: auth,
        store: store,
        backendAvailable: true,
      )..start();
      auth.uid = 'u1';
      await _settle();
      // The account read is still settling; the customer edits the cart.
      cart.add(_p(products, 'fresh-oyster-250'), quantity: 2);
      await _settle();
      expect(store.pushed, isEmpty); // no write over the unread account cart

      store.fetchGate!.complete();
      await _settle(700);
      // The unseen account items were not clobbered and were NOT lost either:
      // the live watch tops them in (never summed - 250 stays at 2, the
      // account's 4 is added) and mirrors the union back.
      expect(repo.items, {'fresh-oyster-250': 2, 'fresh-oyster-500': 4});
      expect(store.pushed, [
        _snap({'fresh-oyster-250': 2, 'fresh-oyster-500': 4}),
      ]);
      expect(sync.hasSavedCart, isFalse);
      sync.dispose();
    },
  );

  test(
    'an edit during the read is mirrored when the account holds nothing '
    'unseen',
    () async {
      final (repo, cart, products) = await _loadedCart();
      final auth = _FakeAuth();
      final store = _FakeStore()
        ..cart = _snap({'fresh-oyster-250': 1})
        ..fetchGate = Completer<void>();
      final sync = CartSyncController(
        repository: repo,
        cart: cart,
        auth: auth,
        store: store,
        backendAvailable: true,
      )..start();
      auth.uid = 'u1';
      await _settle();
      cart.add(_p(products, 'fresh-oyster-250'), quantity: 2);
      store.fetchGate!.complete();
      await _settle(700);
      // The account's 1 holds nothing this cart (2) lacks, so the customer's
      // edit mirrors through once the account read settles.
      expect(store.pushed, [
        _snap({'fresh-oyster-250': 2}),
      ]);
      expect(sync.hasSavedCart, isFalse);
      sync.dispose();
    },
  );

  test('loadAccountCart is a no-op when signed out (no stale merge)', () async {
    final (repo, cart, _) = await _loadedCart();
    await repo.add('fresh-oyster-250', 1);
    final auth = _FakeAuth();
    final store = _FakeStore()..cart = _snap({'fresh-oyster-500': 2});
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
    'sign-out keeps the live-synced cart and stops the watch',
    () async {
      final (repo, cart, _) = await _loadedCart();
      final auth = _FakeAuth();
      final store = _FakeStore()..cart = _snap({'fresh-oyster-500': 2});
      final sync = CartSyncController(
        repository: repo,
        cart: cart,
        auth: auth,
        store: store,
        backendAvailable: true,
      )..start();
      auth.uid = 'u1';
      await _settle();
      // The live sync topped the cart up while signed in.
      expect(repo.items, {'fresh-oyster-500': 2});

      auth.uid = null;
      await _settle();

      // The guest cart keeps exactly what was there - the synced items are
      // not reverted or removed on sign-out.
      expect(repo.items, {'fresh-oyster-500': 2});
      expect(sync.hasSavedCart, isFalse);
      expect(sync.savedOfferVisible, isFalse);
      expect(sync.syncedUid, isNull);

      // The watch is stopped: a remote change after sign-out never merges in.
      store.remoteChange(_snap({'fresh-oyster-500': 9}));
      await _settle();
      expect(repo.items, {'fresh-oyster-500': 2});
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
