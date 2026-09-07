import 'dart:async';

import 'package:flutter/foundation.dart';

import '../repositories/wishlist_store.dart';
import 'cart_sync_controller.dart' show CartSyncAuth;

/// The slice of customer auth the wishlist needs — the signed-in account id
/// plus change notifications (the same interface cart sync uses).
///
/// `CartSyncAuth` is a ChangeNotifier, so a fake account in tests behaves
/// exactly like the real [CartSyncAuth]-implementing auth controller.
typedef WishlistAccount = CartSyncAuth;

/// What tapping a wishlist heart should do, decided from the account state.
enum WishlistGate {
  /// A signed-in customer: the heart toggles the saved product immediately.
  toggled,

  /// A guest tapped the heart: they must sign in (or create an account)
  /// first. The product is remembered and saved the moment they do.
  needsSignIn,

  /// The sign-in backend is unreachable: nothing can be saved right now.
  offline,
}

/// The account's saved-product list, kept in step with `wishlists/{uid}`.
///
/// * Signed out: the list is empty and the gate says sign-in is needed.
/// * On sign-in: the saved ids are fetched and watched, so a change made on
///   another device (or in the installed app) arrives live.
/// * While signed in: every toggle writes through (debounced), last writer
///   wins. Echoes of our own writes are ignored.
/// * A product a guest hearts while signed out is remembered and saved the
///   first time that customer signs in (pending-save intent).
class WishlistController extends ChangeNotifier {
  WishlistController({
    this._auth,
    this._store = const FirestoreWishlistStore(),
    this.backendAvailable = false,
  });

  final WishlistAccount? _auth;
  final WishlistStore _store;
  final bool backendAvailable;

  /// Saved product ids, most-recently-added first.
  List<String> _ids = const [];
  List<String> get ids => _ids;

  /// True once this session has loaded the account wishlist (so the UI can
  /// tell "empty wishlist" from "still loading").
  bool _ready = false;
  bool get ready => _ready;

  /// The account the wishlist is currently synced to (null when signed out).
  String? _syncedUid;

  /// Product the guest hearted before signing in; applied on first sign-in.
  String? _pendingSave;

  StreamSubscription<List<String>>? _watch;
  Timer? _pushDebounce;
  List<String>? _lastPushed;
  bool _pushing = false;

  /// Wires the controller to auth changes. Call once after construction.
  /// Safe when the backend is offline: the controller simply stays dormant.
  void start() {
    if (!backendAvailable) return;
    _auth?.addListener(_onAuthChanged);
    final uid = _auth?.uid;
    if (uid != null) {
      unawaited(_load(uid));
    }
  }

  /// Decision for one heart tap, and the gate used by widgets everywhere.
  WishlistGate get gate {
    if (!backendAvailable) return WishlistGate.offline;
    final uid = _auth?.uid;
    if (uid == null) return WishlistGate.needsSignIn;
    return WishlistGate.toggled;
  }

  bool isFavorite(String productId) => _ids.contains(productId);

  /// Remembers the product a guest wants so it is saved on first sign-in.
  /// Returns the gate decision the caller should act on.
  WishlistGate rememberPendingSave(String productId) {
    if (!backendAvailable) return WishlistGate.offline;
    if (_auth?.uid == null) {
      _pendingSave = productId;
      notifyListeners();
      return WishlistGate.needsSignIn;
    }
    return WishlistGate.toggled;
  }

  /// Adds or removes one product. Only effective while signed in; guests and
  /// offline sessions get the gate answer instead.
  WishlistGate toggle(String productId) {
    if (!backendAvailable) return WishlistGate.offline;
    final uid = _auth?.uid;
    if (uid == null) return WishlistGate.needsSignIn;

    if (_ids.contains(productId)) {
      _ids = [..._ids.where((id) => id != productId)];
    } else {
      _ids = [productId, ..._ids];
      if (_ids.length > 120) _ids = _ids.sublist(0, 120);
    }
    notifyListeners();
    _schedulePush(uid);
    return WishlistGate.toggled;
  }

  void _onAuthChanged() {
    final uid = _auth?.uid;
    if (uid == null) {
      _teardown();
    } else if (uid != _syncedUid) {
      unawaited(_load(uid));
    }
  }

  Future<void> _load(String uid) async {
    _cancelWatch();
    _cancelDebounce();
    _syncedUid = uid;
    _pushing = true;
    notifyListeners();

    List<String> remote = const [];
    try {
      remote = await _store.fetch(uid);
    } catch (e) {
      debugPrint('MYCOSIX: wishlist fetch failed ($e)');
    }
    if (_syncedUid != uid) return; // signed out again during the fetch

    var merged = remote;
    final pending = _pendingSave;
    if (pending != null) {
      _pendingSave = null;
      if (!merged.contains(pending)) {
        merged = [pending, ...merged];
        if (merged.length > 120) merged = merged.sublist(0, 120);
      }
    }
    _applyList(merged);
    try {
      await _store.write(uid, merged);
    } catch (e) {
      debugPrint('MYCOSIX: wishlist push failed ($e)');
    }
    _lastPushed = merged;

    if (_syncedUid == uid) {
      _pushing = false;
      _ready = true;
      _startWatch(uid);
      notifyListeners();
    }
  }

  void _schedulePush(String uid) {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(milliseconds: 250), () {
      _pushDebounce = null;
      if (_syncedUid != uid) return;
      final list = List<String>.from(_ids);
      _lastPushed = list;
      _store.write(uid, list).catchError((Object e) {
        debugPrint('MYCOSIX: wishlist push failed ($e)');
      });
    });
  }

  void _startWatch(String uid) {
    _cancelWatch();
    _watch = _store.watch(uid).listen(
      (remote) {
        if (_syncedUid != uid) return;
        if (_pushing) return; // a local write is still in flight
        if (_lastPushed != null && _sameList(_lastPushed!, remote)) return;
        if (_sameList(_ids, remote)) return; // echo of our own write
        _applyList(remote);
        _lastPushed = remote;
      },
      onError: (Object e) {
        // Transient stream error (offline); Firestore re-delivers when the
        // connection returns. Nothing is faked or retried manually.
        debugPrint('MYCOSIX: wishlist watch failed ($e)');
      },
    );
  }

  void _applyList(List<String> list) {
    _ids = List.unmodifiable(list);
    notifyListeners();
  }

  void _teardown() {
    _cancelWatch();
    _cancelDebounce();
    _syncedUid = null;
    _ids = const [];
    _ready = false;
    _lastPushed = null;
    _pushing = false;
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

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    if (backendAvailable) _auth?.removeListener(_onAuthChanged);
    _cancelWatch();
    _cancelDebounce();
    super.dispose();
  }
}
