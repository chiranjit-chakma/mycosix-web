import 'dart:async';

import 'package:flutter/foundation.dart';

import '../repositories/cart_repository.dart';
import '../repositories/remote_cart_store.dart';
import 'cart_controller.dart';

/// The slice of customer auth the cart sync needs — the signed-in account id
/// plus change notifications. Implemented by [CartSyncController]'s real
/// dependency in the app; kept as an interface so the sync logic can be tested
/// against a fake without Firebase.
abstract class CartSyncAuth extends ChangeNotifier {
  String? get uid;
}

/// Keeps the account cart (`carts/{uid}`) in step with the local cart — but
/// NEVER changes the local cart on its own.
///
/// The shop rule is explicit: nothing in the cart may appear, disappear or
/// change because of a login, a logout, a session restore or a background
/// sync — only the customer's own actions change the cart. So:
///
/// * On sign-in (including a session restored at startup): the account cart is
///   fetched read-only. It is never merged in, applied or pushed, and the
///   local cart is never touched. If the account holds items that differ from
///   this cart, the cart page shows a banner offering to load them — an
///   explicit customer action ([loadAccountCart]).
/// * While signed in: every local cart change the customer makes is written
///   through (debounced, so rapid +/- taps produce one write). The write only
///   saves the customer's own edit — it never alters cart contents by itself.
/// * On sign-out: the local cart simply continues as the guest cart — nothing
///   is lost, nothing is faked, nothing is removed.
///
/// There is deliberately no live watch of the account document: a snapshot
/// arriving from another device is exactly the kind of surprise change this
/// controller must never apply. The account cart is re-read on a fresh
/// sign-in only, and the knowledge refreshes after each push, so the load
/// offer disappears once the account and this cart match again.
class CartSyncController extends ChangeNotifier {
  CartSyncController({
    required this.repository,
    required this.cart,
    required this.auth,
    RemoteCartStore? store,
    this.backendAvailable = false,
  }) : _store = store ?? const FirestoreRemoteCartStore();

  final CartRepository repository;
  final CartController cart;
  final CartSyncAuth auth;
  final bool backendAvailable;
  final RemoteCartStore _store;

  Timer? _pushDebounce;

  /// The account this controller is currently signed in with.
  String? _syncedUid;

  /// The last known account-cart item map. Read-only knowledge used only to
  /// offer the load banner — never applied to the cart on its own. It is
  /// replaced by each successful push, so the offer disappears once the
  /// account and this cart match.
  Map<String, int>? _accountCart;

  /// The account whose cart is mirrored, or null when signed out (or when the
  /// backend is dormant).
  String? get syncedUid => _syncedUid;

  /// The account cart as last read (null before the first read completes, or
  /// after sign-out).
  Map<String, int>? get accountCart => _accountCart;

  /// True when the signed-in account holds saved items that differ from the
  /// cart on this device — the cart page then offers to load them. Reading
  /// this getter never changes anything.
  bool get hasSavedCart {
    final remote = _accountCart;
    if (remote == null || remote.isEmpty || _syncedUid == null) return false;
    return !_sameItems(repository.items, remote);
  }

  /// Wires the controller to auth + cart changes. Call once after both are
  /// created and loaded. Safe to call when the backend is offline: the
  /// controller simply stays dormant and the guest cart behaves exactly as
  /// before.
  void start() {
    if (!backendAvailable) return;
    auth.addListener(_onAuthChanged);
    cart.addListener(_onCartChanged);
    // A session can already exist at startup (persisted login) — pick it up.
    final uid = auth.uid;
    if (uid != null) {
      unawaited(_signIn(uid));
    }
  }

  /// The customer asked to load the account cart (the cart-page banner
  /// button). The saved items are MERGED into the cart on this device —
  /// quantities of the same product are summed and the result re-clamped
  /// against the live catalogue — and the combined cart is written to the
  /// account through the normal debounced push. This is the only place the
  /// local cart ever absorbs the account cart, and it only happens on this
  /// explicit tap; signing in or out never does.
  Future<void> loadAccountCart() async {
    if (_syncedUid == null) return;
    final remote = _accountCart ?? const <String, int>{};
    final merged = await cart.mergeRemoteCart(remote);
    // The account now mirrors this cart, so the offer disappears at once
    // (the debounced push still writes the merged cart through).
    _accountCart = merged;
    notifyListeners();
  }

  void _onAuthChanged() {
    final uid = auth.uid;
    if (uid == null) {
      _teardown();
    } else if (uid != _syncedUid) {
      unawaited(_signIn(uid));
    }
  }

  void _onCartChanged() {
    final uid = _syncedUid;
    if (uid == null) return; // guest: local cart only, exactly as before
    _schedulePush(uid);
  }

  Future<void> _signIn(String uid) async {
    if (uid == _syncedUid) return;
    _syncedUid = uid;
    _accountCart = null;
    _cancelDebounce();
    notifyListeners();

    // Read the account cart WITHOUT touching the local cart: a login or a
    // restored session never adds, removes or changes a single item here.
    // The read only feeds the load-banner offer.
    try {
      final remote = await _store.fetch(uid);
      if (_syncedUid != uid) return; // signed out again during the fetch
      _accountCart = remote;
      notifyListeners();
    } catch (e) {
      // Offline or refused: no banner this session; a later local edit push
      // repopulates the knowledge. The guest cart is untouched either way.
      debugPrint('MYCOSIX: account cart fetch failed ($e)');
    }
  }

  void _schedulePush(String uid) {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(milliseconds: 400), () {
      _pushDebounce = null;
      final uidNow = _syncedUid;
      if (uidNow == null) return;
      final items = repository.items;
      unawaited(_pushItems(uidNow, items));
    });
  }

  Future<void> _pushItems(String uid, Map<String, int> items) async {
    try {
      await _store.push(uid, items);
      // The account now mirrors this cart; the load offer disappears.
      if (_syncedUid == uid) {
        _accountCart = Map.of(items);
        notifyListeners();
      }
    } catch (e) {
      // The cart still works locally; the next local change retries the push.
      debugPrint('MYCOSIX: account cart push failed ($e)');
    }
  }

  void _teardown() {
    _cancelDebounce();
    _syncedUid = null;
    _accountCart = null;
    notifyListeners();
  }

  void _cancelDebounce() {
    _pushDebounce?.cancel();
    _pushDebounce = null;
  }

  static bool _sameItems(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  void dispose() {
    if (backendAvailable) {
      auth.removeListener(_onAuthChanged);
      cart.removeListener(_onCartChanged);
    }
    _cancelDebounce();
    super.dispose();
  }
}
