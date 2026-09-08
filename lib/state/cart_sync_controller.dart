import 'dart:async';

import 'package:flutter/foundation.dart';

import '../repositories/cart_repository.dart';
import '../repositories/remote_cart_store.dart';
import 'cart_controller.dart';

/// The slice of customer auth the cart sync needs - the signed-in account id
/// plus change notifications. Implemented by [CartSyncController]'s real
/// dependency in the app; kept as an interface so the sync logic can be tested
/// against a fake without Firebase.
abstract class CartSyncAuth extends ChangeNotifier {
  String? get uid;
}

/// Keeps the account cart (`carts/{uid}`) in step with the local cart - but
/// NEVER changes the local cart on its own.
///
/// The shop rule is explicit: nothing in the cart may appear, disappear or
/// change because of a login, a logout, a session restore or a background
/// sync - only the customer's own actions change the cart. So:
///
/// * On sign-in (including a session restored at startup): the account cart is
///   fetched read-only. It is never merged in, applied or pushed, and the
///   local cart is never touched. If the account holds items this cart does
///   not yet carry at the same quantity, the cart page shows a banner
///   offering to load them - an explicit customer action
///   ([loadAccountCart]).
/// * While signed in: every local cart change the customer makes is written
///   through (debounced, so rapid +/- taps produce one write). The write only
///   saves the customer's own edit - it never alters cart contents by itself.
/// * On sign-out: the local cart simply continues as the guest cart - nothing
///   is lost, nothing is faked, nothing is removed.
///
/// The account cart is a MIRROR of this cart, not an independent second list,
/// so a load TOPS the local cart up to the account quantities - every product
/// ends at the higher of the two quantities, never at their sum. The same
/// saved cart can therefore be offered and loaded any number of times (a
/// re-login, a second tap, a reload after a failed write) without ever
/// counting a line twice. [loadAccountCart] writes the topped-up result to
/// the account immediately - awaited inside the call, not left on the
/// cancellable debounce - so logging out or closing the app right after a
/// load cannot leave the account behind and re-offer the same items next
/// login.
///
/// Two ordering guards keep knowledge honest: while the first account read of
/// a session is still settling, local edits are recorded but never written
/// through (a write must not replace an account cart that has not been read
/// and offered yet); and only the newest write-through may refresh the
/// account knowledge, so a slow older write can never resurrect a stale
/// "saved items" offer.
///
/// There is deliberately no live watch of the account document: a snapshot
/// arriving from another device is exactly the kind of surprise change this
/// controller must never apply. The account cart is re-read on a fresh
/// sign-in only, and the knowledge refreshes after each write-through, so the
/// load offer disappears once the account and this cart match again.
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
  /// offer the load banner - never applied to the cart on its own. It is
  /// replaced by each successful write-through, so the offer disappears once
  /// the account and this cart match again.
  Map<String, int>? _accountCart;

  /// True between sign-in and the first account-cart read resolving. While it
  /// is pending, local edits are only recorded (never written through): a
  /// write must never replace the account cart before the saved items in it
  /// have been read and offered.
  bool _fetchPending = false;

  /// A local cart change arrived while [_fetchPending]; it is mirrored (or
  /// handed to the load offer) once the account read settles.
  bool _changeDuringFetch = false;

  /// Monotonic write-through sequence. Only the push that STARTED last may
  /// refresh the account knowledge on completion, so a slow older write can
  /// never overwrite newer knowledge with a stale offer.
  int _writeSeq = 0;

  /// The account whose cart is mirrored, or null when signed out (or when the
  /// backend is dormant).
  String? get syncedUid => _syncedUid;

  /// The account cart as last read (null before the first read completes, or
  /// after sign-out).
  Map<String, int>? get accountCart => _accountCart;

  /// How many account items this cart does not yet carry at that quantity -
  /// exactly what a load would bring in. 0 means there is nothing to load.
  int get loadableCount {
    final remote = _accountCart;
    if (remote == null || remote.isEmpty) return 0;
    final local = repository.items;
    var n = 0;
    for (final entry in remote.entries) {
      final have = local[entry.key] ?? 0;
      if (entry.value > have) n += entry.value - have;
    }
    return n;
  }

  /// True when the signed-in account holds items this cart does not yet carry
  /// at that quantity - the cart page then offers to load them. Reading this
  /// getter never changes anything.
  bool get hasSavedCart => loadableCount > 0;

  /// Wires the controller to auth + cart changes. Call once after both are
  /// created and loaded. Safe to call when the backend is offline: the
  /// controller simply stays dormant and the guest cart behaves exactly as
  /// before.
  void start() {
    if (!backendAvailable) return;
    auth.addListener(_onAuthChanged);
    cart.addListener(_onCartChanged);
    // A session can already exist at startup (persisted login) - pick it up.
    final uid = auth.uid;
    if (uid != null) {
      unawaited(_signIn(uid));
    }
  }

  /// The customer asked to load the account cart (the cart-page banner
  /// button). Every product the account holds at a HIGHER quantity is topped
  /// up to that quantity - never summed, so the same saved cart can be loaded
  /// twice, or again after a re-login, without ever doubling a line. The
  /// topped-up cart is written to the account immediately (awaited here, not
  /// left on the cancellable debounce) so a fast logout or app close after a
  /// load cannot leave the account behind and re-offer the same items. This
  /// is the only place the local cart ever absorbs the account cart, and it
  /// only happens on this explicit tap; signing in or out never does.
  Future<void> loadAccountCart() async {
    final uid = _syncedUid;
    final remote = _accountCart;
    if (uid == null || remote == null) return;
    if (loadableCount == 0) return; // already carried - never re-sum
    final merged = await cart.mergeRemoteCart(remote);
    // The account now mirrors this cart, so the offer disappears at once.
    _accountCart = merged;
    notifyListeners();
    // Advance the account copy NOW. Any pending debounce is dropped: this
    // write carries the whole cart state, including those earlier edits.
    _cancelDebounce();
    final seq = ++_writeSeq;
    try {
      await _store.push(uid, merged);
      if (_syncedUid == uid && seq == _writeSeq) {
        _accountCart = Map.of(merged);
        notifyListeners();
      }
    } catch (e) {
      // The local cart already holds the merged items; the account copy is
      // retried on the debounce. Even if the write never lands, a later load
      // of the same saved cart is a no-op - merging tops up, never doubles.
      debugPrint('MYCOSIX: account cart push failed after load ($e)');
      if (_syncedUid == uid) _schedulePush(uid);
    }
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
    if (_fetchPending) {
      // The account read is still settling: record the change and mirror it
      // once the saved items are known, so this write can never clobber an
      // account cart that has not been read yet.
      _changeDuringFetch = true;
      return;
    }
    _schedulePush(uid);
  }

  Future<void> _signIn(String uid) async {
    if (uid == _syncedUid) return;
    _syncedUid = uid;
    _accountCart = null;
    _cancelDebounce();
    _fetchPending = true;
    _changeDuringFetch = false;
    notifyListeners();

    // Read the account cart WITHOUT touching the local cart: a login or a
    // restored session never adds, removes or changes a single item here.
    // The read only feeds the load-banner offer.
    try {
      final remote = await _store.fetch(uid);
      if (_syncedUid != uid) return; // signed out again during the fetch
      _fetchPending = false;
      _accountCart = remote;
      notifyListeners();
    } catch (e) {
      if (_syncedUid != uid) return;
      _fetchPending = false;
      // Offline or refused: no banner this session; a later local edit push
      // repopulates the knowledge. The guest cart is untouched either way.
      debugPrint('MYCOSIX: account cart fetch failed ($e)');
      notifyListeners();
    }
    _mirrorDeferredEdits(uid);
  }

  /// Mirrors a local change that arrived while the account read was pending -
  /// but only when the account holds nothing this cart lacks, so an account
  /// cart that has never been offered is not silently overwritten. Otherwise
  /// the load banner decides (its load writes the topped-up union through).
  void _mirrorDeferredEdits(String uid) {
    if (!_changeDuringFetch || _syncedUid != uid) return;
    _changeDuringFetch = false;
    if (loadableCount > 0) return; // the load offer takes over
    final items = repository.items;
    final known = _accountCart;
    if (known == null || !_sameItems(known, items)) {
      _schedulePush(uid);
    }
  }

  void _schedulePush(String uid) {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(milliseconds: 400), () {
      _pushDebounce = null;
      final uidNow = _syncedUid;
      if (uidNow == null) return;
      final items = repository.items;
      final seq = ++_writeSeq;
      unawaited(_pushItems(uidNow, items, seq));
    });
  }

  Future<void> _pushItems(String uid, Map<String, int> items, int seq) async {
    try {
      await _store.push(uid, items);
      // The account now mirrors this cart; the load offer disappears. Only
      // the newest write-through may refresh the knowledge, so a slow older
      // write cannot resurrect a stale offer.
      if (_syncedUid == uid && seq == _writeSeq) {
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
    _fetchPending = false;
    _changeDuringFetch = false;
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
