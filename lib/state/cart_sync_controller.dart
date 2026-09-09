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

/// Keeps the account cart (`carts/{uid}`) in step with the local cart. While
/// signed in, the account cart is LIVE-SYNCED: this controller listens to the
/// account document, so a cart change made on another device (or another tab
/// of this device) reaches this cart on its own.
///
/// The local cart is always the instant UI source, and a live snapshot never
/// REMOVES or LOWERS a quantity on its own: it tops every product up to the
/// HIGHER of the two quantities - never summed (so the same cart can never be
/// counted twice) and never shrunk (so a stale or emptier account can never
/// delete a customer's items). The topped-up union is mirrored back to the
/// account immediately (awaited, not left on the debounce), so every device
/// converges to the same union and the snapshot echoing that union back is a
/// no-op - there is no merge loop.
///
/// REMOVALS DO PROPAGATE, through tombstones. Each cart document carries a
/// bounded `removed` list (the account-wide tombstones, newest appended last).
/// A removal on one device tombstones the product account-wide: every other
/// device holding that line drops it on its next snapshot, and a stale device
/// can never resurrect it (its push never re-adds an account-tombstoned line
/// unless the customer explicitly re-added it on that device, which lifts the
/// tombstone again). The tombstone list is bounded to the newest 100, so the
/// account doc can never grow without bound.
///
/// * On sign-in (including a session restored at startup): the account cart is
///   read first, then live-watched. If the account already holds more than
///   this cart, the first snapshot tops this cart up on its own - the same
///   merge a Load would have done. Any cart actions this device is still
///   owed by the account (added before signing in, or during the read) are
///   written through as soon as the read settles.
/// * While signed in: every local cart change is written through (debounced,
///   so rapid +/- taps produce one write), and every account snapshot that
///   holds more - or carries a tombstone for a line this cart still holds -
///   is merged in and mirrored back.
/// * The "saved items" offer is now the OFFLINE FALLBACK: it appears only when
///   the live watch cannot deliver the account cart (a watch failure, or no
///   snapshot has arrived), so a customer can still pull the account's items
///   in by tapping [loadAccountCart]. While the watch is delivering, account
///   items arrive by themselves and the offer stays hidden.
/// * On sign-out: the watch stops and the local cart simply continues as the
///   guest cart - nothing is lost, nothing is removed. A snapshot that lands
///   after sign-out is ignored. Un-acknowledged actions stay pending in the
///   repository and are written to whichever account is next signed in (the
///   guest cart itself becomes that account's cart, so this is consistent).
///
/// Honest limits: a removal propagates only to a device that is signed in and
/// connected (the watch delivers it); a device that is offline when the
/// tombstone lands drops the line on its next snapshot. A quantity race is
/// last-write-wins between devices. And a removal on a device that is not yet
/// signed in travels with the cart when it signs in.
///
/// Two ordering guards keep knowledge honest: while the first account read of
/// a session is still settling, local edits are recorded but never written
/// through (a write must not replace an account cart that has not been read
/// yet); and only the newest write may refresh the account knowledge, so a
/// slow older write can never resurrect a stale offer.
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

  /// The last known account-cart snapshot. It feeds the live-sync merge and,
  /// when the watch cannot deliver, the load offer. It is replaced by each
  /// successful write-through, so the offer disappears once the account and
  /// this cart match again.
  RemoteCartSnapshot? _accountCart;

  /// True between sign-in and the first account-cart read resolving. While it
  /// is pending, local edits are only recorded (never written through): a
  /// write must never replace the account cart before the saved items in it
  /// have been read.
  bool _fetchPending = false;

  /// A local cart change arrived while [_fetchPending]; it is mirrored (or
  /// handed to the load offer) once the account read settles.
  bool _changeDuringFetch = false;

  /// Monotonic write-through sequence. Only the push that STARTED last may
  /// refresh the account knowledge on completion, so a slow older write can
  /// never overwrite newer knowledge with a stale offer.
  int _writeSeq = 0;

  /// Live subscription to the account document. Its first emission is the
  /// current account cart, exactly like the Firestore document it mirrors;
  /// later emissions come from other devices (or other tabs).
  StreamSubscription<RemoteCartSnapshot>? _watchSub;

  /// True while the live account watch is (or is expected to be) delivering.
  /// Set optimistically when the watch starts so the load offer never flashes
  /// over an account that is about to sync by itself; cleared on a watch
  /// failure or sign-out so the offer can act as the offline fallback.
  bool _watchActive = false;

  /// The account whose cart is mirrored, or null when signed out (or when the
  /// backend is dormant).
  String? get syncedUid => _syncedUid;

  /// The account cart as last read (null before the first read completes, or
  /// after sign-out).
  RemoteCartSnapshot? get accountCart => _accountCart;

  /// How many account items this cart does not yet carry at that quantity -
  /// exactly what a load would bring in. 0 means there is nothing to load.
  /// Lines this device removed (pending tombstones) and lines the account
  /// itself tombstoned are never offered: loading must not resurrect them.
  int get loadableCount {
    final remote = _accountCart;
    if (remote == null || remote.isEmpty) return 0;
    final local = repository.items;
    final pending = repository.pendingActions;
    final tombstoned = remote.removed.toSet();
    var n = 0;
    for (final entry in remote.items.entries) {
      if (tombstoned.contains(entry.key)) continue;
      if (pending.removed.contains(entry.key)) continue;
      final have = local[entry.key] ?? 0;
      if (entry.value > have) n += entry.value - have;
    }
    return n;
  }

  /// True when the signed-in account holds items this cart does not yet carry
  /// at that quantity - the account may need bringing in. Reading this getter
  /// never changes anything.
  bool get hasSavedCart => loadableCount > 0;

  /// Whether the cart page should OFFER the account items for a manual load.
  /// This is the offline fallback: the offer is hidden while the live watch is
  /// delivering (account items arrive by themselves), and shown only when the
  /// watch cannot - so a customer can still pull items in with a tap.
  bool get savedOfferVisible => hasSavedCart && !_watchActive;

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

  /// Pulls the account cart in by hand (the offline-fallback button). Every
  /// product the account holds at a HIGHER quantity is topped up to that
  /// quantity - never summed, so the same saved cart can be loaded twice, or
  /// again after a re-login, without ever doubling a line. Lines the account
  /// tombstoned are dropped here first (never resurrected), and lines this
  /// device removed itself are not pulled back. The topped-up cart is written
  /// to the account immediately (awaited here, not left on the cancellable
  /// debounce) so a fast logout or app close after a load cannot leave the
  /// account behind and re-offer the same items. This is the manual twin of
  /// the automatic live-sync merge ([_applyRemoteCart]).
  Future<void> loadAccountCart() async {
    final uid = _syncedUid;
    final remote = _accountCart;
    if (uid == null || remote == null) return;
    if (loadableCount == 0) return; // already carried - never re-sum
    try {
      await cart.applyRemoteRemovals(remote.removed.toSet());
      await cart.mergeRemoteCart(_effectiveRemoteItems(remote));
      _cancelDebounce();
      await _pushToAccount(uid);
    } catch (e) {
      // The local cart already holds the merged items; the account copy is
      // retried on the debounce. Even if the write never lands, a later load
      // of the same saved cart is a no-op - merging tops up, never doubles.
      debugPrint('MYCOSIX: account cart load/sync failed ($e)');
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
    _watchActive = false;
    _cancelWatch();
    _syncedUid = uid;
    _accountCart = null;
    _cancelDebounce();
    _fetchPending = true;
    _changeDuringFetch = false;
    notifyListeners();

    // Read the account cart WITHOUT touching the local cart: the read feeds
    // the load offer until the live watch takes over (its first snapshot
    // carries the same document).
    try {
      final remote = await _store.fetch(uid);
      if (_syncedUid != uid) return; // signed out again during the fetch
      _fetchPending = false;
      _accountCart = remote;
      notifyListeners();
    } catch (e) {
      if (_syncedUid != uid) return;
      _fetchPending = false;
      // Offline or refused: no knowledge this session; a later local edit
      // push repopulates it, and the live watch will deliver once connected.
      // The guest cart is untouched either way.
      debugPrint('MYCOSIX: account cart fetch failed ($e)');
      notifyListeners();
    }
    _mirrorDeferredEdits(uid);
    _startWatch(uid);
  }

  /// Starts listening to the account document. The first snapshot is the
  /// account cart as it stands - if it holds more than this cart, the merge
  /// in [_onRemoteCart] just tops this cart up and mirrors the union back.
  void _startWatch(String uid) {
    // Optimistically mark the watch live so the load offer never flashes over
    // an account that is about to sync by itself. A watch failure clears it,
    // turning the offer back on as the offline fallback.
    _watchActive = true;
    _watchSub = _store.watch(uid).listen(
      (remote) => _onRemoteCart(uid, remote),
      onError: (Object e) {
        _watchActive = false;
        debugPrint('MYCOSIX: account cart watch failed ($e)');
      },
    );
  }

  void _onRemoteCart(String uid, RemoteCartSnapshot remote) {
    if (_syncedUid != uid) return; // signed out again - ignore stale snapshots
    _watchActive = true;
    _accountCart = remote; // keep the fallback knowledge fresh
    if (!_remoteNeedsApplication(remote)) return;
    unawaited(_applyRemoteCart(uid, remote));
  }

  /// True when a snapshot must be applied: the account holds a TOMBSTONE for
  /// a line this cart still carries (not re-added), or holds an item at a
  /// quantity this cart has not reached, or this device still owes the
  /// account actions (its last push has not been acknowledged). Checking
  /// against the LIVE local cart (never a stale copy) is what stops the
  /// mirror echo: once the union has been merged and pushed and the pending
  /// actions acknowledged, the echoed snapshot holds nothing to do, so it is
  /// a no-op and the loop ends.
  bool _remoteNeedsApplication(RemoteCartSnapshot remote) {
    final local = repository.items;
    final pending = repository.pendingActions;
    for (final id in remote.removed) {
      if (local.containsKey(id) && !pending.added.contains(id)) return true;
    }
    for (final entry in remote.items.entries) {
      if (pending.removed.contains(entry.key)) continue; // we removed it
      if (entry.value > (local[entry.key] ?? 0)) return true;
    }
    return pending.added.isNotEmpty || pending.removed.isNotEmpty;
  }

  /// Applies a live snapshot: drops the lines the account tombstoned, tops
  /// this cart up to the union (never summing, never shrinking), then
  /// reconciles and mirrors the result back to the account right away
  /// (awaited, not debounced) so every other device converges too.
  Future<void> _applyRemoteCart(String uid, RemoteCartSnapshot remote) async {
    try {
      await cart.applyRemoteRemovals(remote.removed.toSet());
      final effective = _effectiveRemoteItems(remote);
      await cart.mergeRemoteCart(effective);
      _cancelDebounce();
      final ok = await _pushToAccount(uid);
      if (!ok && _syncedUid == uid) _schedulePush(uid);
    } catch (e) {
      // The local cart already holds the topped-up items; the union is
      // retried on the next local change or debounce. The cart still works.
      debugPrint('MYCOSIX: account cart live sync failed ($e)');
      if (_syncedUid == uid) _schedulePush(uid);
    }
  }

  /// The account items this device may merge in: the account's items minus
  /// anything the account itself tombstoned, minus anything THIS device
  /// removed (its pending tombstones) - so a merge can never resurrect a line
  /// that was removed, on either side.
  Map<String, int> _effectiveRemoteItems(RemoteCartSnapshot remote) {
    final tombstoned = remote.removed.toSet();
    final pending = repository.pendingActions;
    final out = <String, int>{};
    for (final entry in remote.items.entries) {
      if (tombstoned.contains(entry.key)) continue;
      if (pending.removed.contains(entry.key)) continue;
      out[entry.key] = entry.value;
    }
    return out;
  }

  /// Writes through any cart action this device owes the account that the
  /// account read was settling for: local changes that arrived during the
  /// fetch, plus actions taken earlier as a guest. The push itself is a no-op
  /// when the account already mirrors this cart exactly.
  void _mirrorDeferredEdits(String uid) {
    if (_syncedUid != uid) return;
    final pending = repository.pendingActions;
    final owes = _changeDuringFetch ||
        pending.added.isNotEmpty ||
        pending.removed.isNotEmpty;
    _changeDuringFetch = false;
    if (owes) _schedulePush(uid);
  }

  void _schedulePush(String uid) {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(milliseconds: 400), () {
      _pushDebounce = null;
      final uidNow = _syncedUid;
      if (uidNow == null) return;
      unawaited(_pushToAccount(uidNow));
    });
  }

  /// Reconciles this device's cart against the account knowledge and writes
  /// the account document, unless it already mirrors this cart exactly (the
  /// echo case - returns true without writing). True when the account now
  /// mirrors this cart; false when the write failed (the pending actions are
  /// kept and retried on the next event).
  Future<bool> _pushToAccount(String uid) async {
    final remote = _accountCart;
    final pending = repository.pendingActions;
    final reconciled = reconcileAccountCart(
      accountItems: remote?.items ?? const {},
      accountRemoved: remote?.removed ?? const [],
      localItems: repository.items,
      addedPending: pending.added,
      removedPending: pending.removed,
      capFor: repository.capForId,
    );
    if (remote != null &&
        _sameItems(remote.items, reconciled.items) &&
        _sameRemoved(remote.removed, reconciled.removed)) {
      return true; // account already mirrors this cart - no write, no ack
    }
    final seq = ++_writeSeq;
    try {
      await _store.push(
        uid,
        RemoteCartSnapshot(items: reconciled.items, removed: reconciled.removed),
      );
    } catch (e) {
      // The cart still works locally; the pending actions stay and the next
      // event (local change, snapshot, or debounce) retries the push.
      debugPrint('MYCOSIX: account cart push failed ($e)');
      return false;
    }
    // The account now mirrors this cart; the pending actions it carried are
    // cleared, and the load offer disappears. Only the newest write-through
    // may refresh the knowledge, so a slow older write cannot resurrect a
    // stale offer.
    if (_syncedUid == uid && seq == _writeSeq) {
      repository.ackPush(
        added: reconciled.items.keys.toSet(),
        removed: reconciled.removed,
      );
      _accountCart = RemoteCartSnapshot(
        items: Map.of(reconciled.items),
        removed: List.of(reconciled.removed),
      );
      notifyListeners();
    }
    return true;
  }

  void _teardown() {
    _cancelDebounce();
    _cancelWatch();
    _watchActive = false;
    _syncedUid = null;
    _accountCart = null;
    _fetchPending = false;
    _changeDuringFetch = false;
    notifyListeners();
  }

  void _cancelWatch() {
    _watchSub?.cancel();
    _watchSub = null;
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

  static bool _sameRemoved(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
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
    _cancelWatch();
    super.dispose();
  }
}
