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

/// Keeps the account cart (`carts/{uid}`) in step with the local cart.
///
/// * On sign-in: the guest cart and the account cart are merged (quantities
///   summed, then re-clamped against the live catalogue — unavailable or
///   unknown products are dropped), the merged cart is applied locally,
///   written to the account, and the account document is watched so changes
///   made on another device (or in the installed app) arrive live.
/// * While signed in: every local cart change is written through (debounced,
///   so rapid +/- taps produce one write).
/// * On sign-out: the watch stops and the local cart simply continues as the
///   guest cart — nothing is lost, nothing is faked.
///
/// Conflict policy: if a remote snapshot arrives while a local change is still
/// pending its write-through, the local (newer) edit wins; otherwise the
/// remote snapshot is applied. Echoes of our own writes are ignored. This is a
/// last-writer-wins mirror, which is correct for a cart of one owner.
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

  StreamSubscription<Map<String, int>>? _watch;
  Timer? _pushDebounce;

  /// True while a sign-in merge is in flight (used to suppress echo pushes).
  bool _merging = false;

  /// True while a remote snapshot is being applied locally (suppresses the
  /// write-through that would otherwise echo it straight back).
  bool _applyingRemote = false;

  /// The account this controller is currently synced to.
  String? _syncedUid;

  /// The item map last written (or about to be written) to the account.
  Map<String, int>? _lastPushed;

  /// True while the sign-in merge is running (UI may show a subtle spinner).
  bool get syncing => _merging;

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

  void _onAuthChanged() {
    final uid = auth.uid;
    if (uid == null) {
      _teardown();
    } else if (uid != _syncedUid) {
      unawaited(_signIn(uid));
    }
  }

  void _onCartChanged() {
    if (_applyingRemote || _merging) return;
    final uid = _syncedUid;
    if (uid == null) return; // guest: local cart only, exactly as before
    _schedulePush(uid);
  }

  Future<void> _signIn(String uid) async {
    if (_merging && uid == _syncedUid) return;
    _merging = true;
    _syncedUid = uid;
    _cancelWatch();
    _cancelDebounce();
    notifyListeners();

    // Fetch the account cart. Offline or refused: merge with an empty
    // account cart and keep the guest cart intact.
    Map<String, int> remote = const {};
    try {
      remote = await _store.fetch(uid);
    } catch (e) {
      debugPrint('MYCOSIX: account cart fetch failed ($e)');
    }
    if (_syncedUid != uid) return; // signed out again during the fetch

    // Sum + re-clamp against the live catalogue, apply locally, then push the
    // merged cart so the account reflects this device's guest items.
    try {
      final merged = await cart.mergeRemoteCart(remote);
      _lastPushed = merged;
      await _store.push(uid, merged);
    } catch (e) {
      // The cart still works locally; the next local change retries the push.
      debugPrint('MYCOSIX: account cart push failed ($e)');
    }

    if (_syncedUid == uid) {
      _merging = false;
      _startWatch(uid);
      notifyListeners();
    }
  }

  void _startWatch(String uid) {
    _cancelWatch();
    _watch = _store.watch(uid).listen(
      (remote) {
        if (_syncedUid != uid) return;
        // A local edit is still waiting to be written — local (newer) wins.
        if (_pushDebounce != null) return;
        final local = repository.items;
        if (_sameItems(local, remote)) return; // echo of our own write
        if (_lastPushed != null && _sameItems(_lastPushed!, remote)) return;
        _applyingRemote = true;
        cart
            .applyRemoteCart(remote)
            .whenComplete(() => _applyingRemote = false);
        _lastPushed = remote;
      },
      onError: (Object e) {
        // Transient stream error (offline); Firestore re-delivers when the
        // connection returns. Nothing is faked or retried manually.
        debugPrint('MYCOSIX: account cart watch failed ($e)');
      },
    );
  }

  void _schedulePush(String uid) {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(milliseconds: 400), () {
      _pushDebounce = null;
      final uidNow = _syncedUid;
      if (uidNow == null) return;
      final items = repository.items;
      _lastPushed = items;
      _store.push(uidNow, items).catchError((Object e) {
        debugPrint('MYCOSIX: account cart push failed ($e)');
      });
    });
  }

  void _teardown() {
    _cancelWatch();
    _cancelDebounce();
    _syncedUid = null;
    _lastPushed = null;
    _merging = false;
    notifyListeners();
  }

  void _cancelWatch() {
    _watch?.cancel();
    _watch = null;
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
    _cancelWatch();
    _cancelDebounce();
    super.dispose();
  }
}
