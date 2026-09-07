import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/repositories/wishlist_store.dart';
import 'package:mycosix/state/cart_sync_controller.dart';
import 'package:mycosix/state/wishlist_controller.dart';

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
class _FakeStore implements WishlistStore {
  List<String> list = [];
  final _snapshots = StreamController<List<String>>.broadcast();
  final List<List<String>> pushed = [];
  int fetches = 0;
  bool fetchShouldFail = false;

  @override
  Future<List<String>> fetch(String uid) async {
    fetches++;
    if (fetchShouldFail) throw Exception('offline');
    return List.of(list);
  }

  @override
  Stream<List<String>> watch(String uid) => _snapshots.stream;

  @override
  Future<void> write(String uid, List<String> items) async {
    pushed.add(List.of(items));
    list = List.of(items);
    _snapshots.add(List.of(items)); // snapshot echo, like Firestore
  }

  void remoteChange(List<String> items) {
    list = List.of(items);
    _snapshots.add(List.of(items));
  }
}

void main() {
  test('gate follows the account state', () {
    final auth = _FakeAuth();
    final store = _FakeStore();

    // Backend offline: nothing can be saved, ever.
    final offline = WishlistController(
      auth: auth,
      store: store,
      backendAvailable: false,
    );
    expect(offline.gate, WishlistGate.offline);

    // Signed out: hearts prompt a sign-in.
    final signedOut = WishlistController(
      auth: auth,
      store: store,
      backendAvailable: true,
    );
    expect(signedOut.gate, WishlistGate.needsSignIn);

    // Signed in: hearts toggle immediately.
    auth.uid = 'u1';
    expect(signedOut.gate, WishlistGate.toggled);

    signedOut.dispose();
    offline.dispose();
  });

  test('sign-in loads the remote wishlist most-recently-first', () async {
    final auth = _FakeAuth();
    final store = _FakeStore()..list = ['p2', 'p1'];
    final w = WishlistController(
      auth: auth,
      store: store,
      backendAvailable: true,
    )..start();

    expect(w.ready, isFalse);
    auth.uid = 'u1';
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(w.ready, isTrue);
    expect(w.ids, ['p2', 'p1']);
    expect(store.fetches, 1);
    w.dispose();
  });

  test('toggle adds at the front and removes again', () async {
    final auth = _FakeAuth()..uid = 'u1';
    final store = _FakeStore()..list = ['p2'];
    final w = WishlistController(
      auth: auth,
      store: store,
      backendAvailable: true,
    )..start();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(w.toggle('p1'), WishlistGate.toggled);
    expect(w.ids, ['p1', 'p2']);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(store.pushed.last, ['p1', 'p2']);

    expect(w.toggle('p1'), WishlistGate.toggled);
    expect(w.ids, ['p2']);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(store.pushed.last, ['p2']);
    w.dispose();
  });

  test('toggle never grows past the 120-entry bound', () async {
    final auth = _FakeAuth()..uid = 'u1';
    final store = _FakeStore();
    final w = WishlistController(
      auth: auth,
      store: store,
      backendAvailable: true,
    )..start();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    for (var i = 0; i < 130; i++) {
      expect(w.toggle('prod-$i'), WishlistGate.toggled);
    }
    expect(w.ids.length, 120);
    // Newest stays at the front; the oldest 10 were dropped.
    expect(w.ids.first, 'prod-129');
    expect(w.ids.last, 'prod-10');
    expect(w.ids, isNot(contains('prod-9')));
    w.dispose();
  });

  test('a product hearted as a guest is saved on first sign-in', () async {
    final auth = _FakeAuth();
    final store = _FakeStore()..list = ['p2'];
    final w = WishlistController(
      auth: auth,
      store: store,
      backendAvailable: true,
    )..start();

    expect(w.rememberPendingSave('p1'), WishlistGate.needsSignIn);
    expect(w.ids, isEmpty); // still a guest: nothing saved yet

    auth.uid = 'u1';
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(w.ids, ['p1', 'p2']);
    expect(store.pushed.last, ['p1', 'p2']);
    w.dispose();
  });

  test('a remote change from another device is applied live', () async {
    final auth = _FakeAuth()..uid = 'u1';
    final store = _FakeStore()..list = ['p1'];
    final w = WishlistController(
      auth: auth,
      store: store,
      backendAvailable: true,
    )..start();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(w.ids, ['p1']);

    store.remoteChange(['p3', 'p1']);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(w.ids, ['p3', 'p1']);
    w.dispose();
  });

  test('an echo of our own write never loops back', () async {
    final auth = _FakeAuth()..uid = 'u1';
    final store = _FakeStore()..list = ['p1'];
    final w = WishlistController(
      auth: auth,
      store: store,
      backendAvailable: true,
    )..start();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    w.toggle('p2');
    await Future<void>.delayed(const Duration(milliseconds: 700));

    // Exactly one debounced push (plus the sign-in load push), not a loop.
    expect(store.pushed.length, 2);
    expect(w.ids, ['p2', 'p1']);
    w.dispose();
  });

  test('sign-out clears the wishlist and stops remote updates', () async {
    final auth = _FakeAuth()..uid = 'u1';
    final store = _FakeStore()..list = ['p1', 'p2'];
    final w = WishlistController(
      auth: auth,
      store: store,
      backendAvailable: true,
    )..start();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(w.ids, ['p1', 'p2']);

    auth.uid = null;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(w.ids, isEmpty);
    expect(w.ready, isFalse);
    expect(w.gate, WishlistGate.needsSignIn);

    // Another device's change no longer reaches this session.
    store.remoteChange(['p9']);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(w.ids, isEmpty);
    w.dispose();
  });

  test('a dormant controller (backend offline) never touches the store',
      () async {
    final auth = _FakeAuth()..uid = 'u1';
    final store = _FakeStore()..list = ['p1'];
    final w = WishlistController(
      auth: auth,
      store: store,
      backendAvailable: false,
    )..start();

    expect(w.toggle('p2'), WishlistGate.offline);
    auth.uid = 'u2';
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(store.fetches, 0);
    expect(store.pushed, isEmpty);
    expect(w.ids, isEmpty);
    w.dispose();
  });

  group('FirestoreWishlistStore.sanitize', () {
    test('never trusts anything that is not a clean list of strings', () {
      expect(FirestoreWishlistStore.sanitize(null), isEmpty);
      expect(FirestoreWishlistStore.sanitize('nope'), isEmpty);
      expect(FirestoreWishlistStore.sanitize({'a': 1}), isEmpty);
    });

    test('keeps order, drops empty, oversized and non-string entries',
        () {
      final long = 'x' * 101;
      final out = FirestoreWishlistStore.sanitize([
        'b',
        '',
        'a',
        42,
        'c',
        long,
        'a', // duplicate
        'b', // duplicate
      ]);
      expect(out, ['b', 'a', 'c']);
    });

    test('caps at 120 entries, newest kept', () {
      final out = FirestoreWishlistStore.sanitize([
        for (var i = 0; i < 130; i++) 'p-$i',
      ]);
      expect(out.length, 120);
      expect(out.first, 'p-0');
      expect(out.last, 'p-119');
    });
  });
}
