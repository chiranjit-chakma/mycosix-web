import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Stored stand-in for "nobody is signed in on the shop side". A real uid is
/// never this string, so one value covers both cases in a single field.
const String kAdminBindingNobody = '-';

/// The shop-side session a uid belongs to, as it is stored.
String shopKeyOf(String? uid) =>
    (uid == null || uid.isEmpty) ? kAdminBindingNobody : uid;

/// What to do about the admin session, given the state of the shop session.
enum AdminSessionVerdict {
  /// The shop session has not been read yet. Decide nothing: acting before it
  /// is known would sign the admin out on every single launch.
  wait,

  /// Nothing has changed, or nobody is signed in on the admin side. Leave it.
  keep,

  /// A fresh admin sign-in: remember which shop session it belongs to.
  bind,

  /// The shop session is no longer the one this admin session was opened
  /// under. End the admin session.
  end,
}

/// Decides whether an open admin session may continue.
///
/// The admin area signs in through its own Firebase app, so its session is
/// stored separately from the shop session and would otherwise outlive it.
/// That is the hole this closes: the admin area is a locked room behind the
/// shop account, so when the shop account changes - a sign-out, or a different
/// account signing in - the room locks and the next visit needs the admin's
/// own email + password and their own secret code again.
///
/// [shopUid] is the shop-side account right now (null = nobody signed in), and
/// [boundShopUid] is the shop session the admin session was opened under
/// (null = nothing recorded, i.e. this is a fresh admin sign-in).
///
/// [endPending] is set once the admin session has been told to end but its
/// sign-out has not come back yet. While it is set the answer stays [end], so
/// a sign-out that did not take is retried rather than quietly forgotten - and
/// a slow sign-out cannot be mistaken for a fresh sign-in and re-bound.
AdminSessionVerdict judgeAdminSession({
  required bool shopResolved,
  required String? shopUid,
  required bool adminSignedIn,
  required String? boundShopUid,
  bool endPending = false,
}) {
  if (!shopResolved) return AdminSessionVerdict.wait;
  if (!adminSignedIn) return AdminSessionVerdict.keep;
  if (endPending) return AdminSessionVerdict.end;
  if (boundShopUid == null) return AdminSessionVerdict.bind;
  if (boundShopUid == shopKeyOf(shopUid)) return AdminSessionVerdict.keep;
  return AdminSessionVerdict.end;
}

/// Keeps the admin session tied to the shop session it was opened under.
///
/// Both sides are watched as streams of uids so this is driven by Firebase's
/// own auth state - never by a flag the page keeps, and never by anything the
/// visitor can set. The binding is remembered on the device as well, so it
/// survives a refresh, a PWA relaunch and a browser restart: an admin session
/// restored on a device whose shop account has since changed is ended before
/// the admin area is ever shown, rather than being handed to whoever is there
/// now.
///
/// This is session lifetime, not authorisation. Whether the signed-in uid is
/// an administrator at all is decided by Firestore security rules on every
/// request, from `admins/{uid}` - nothing here can grant access, and a client
/// that skipped this file entirely would still be refused by the server.
class AdminSessionBinding {
  AdminSessionBinding({
    required this._prefs,
    required this._shopUids,
    required this._adminUids,
    required this._endAdminSession,
  });

  /// Where the shop session an admin session belongs to is remembered.
  static const String storageKey = 'mx.admin.boundShopUid';

  final SharedPreferences _prefs;
  final Stream<String?> _shopUids;
  final Stream<String?> _adminUids;
  final Future<void> Function() _endAdminSession;

  StreamSubscription<String?>? _shopSub;
  StreamSubscription<String?>? _adminSub;

  bool _shopResolved = false;
  String? _shopUid;
  bool _adminSignedIn = false;
  bool _endPending = false;
  String? _bound;
  bool _boundLoaded = false;

  /// How many times an admin session has been ended for this reason. Used by
  /// tests and by anyone reading a debug log.
  int endedCount = 0;

  /// The shop session the current admin session belongs to, or null when there
  /// is none recorded.
  String? get boundShopUid => _bound;

  void start() {
    _bound = _prefs.getString(storageKey);
    _boundLoaded = true;
    _shopSub = _shopUids.listen(_onShop, onError: (Object _) {});
    _adminSub = _adminUids.listen(_onAdmin, onError: (Object _) {});
  }

  void _onShop(String? uid) {
    // The first value IS the restored session, not a change: it is the
    // baseline everything after it is compared against.
    if (!_shopResolved) {
      _shopResolved = true;
      _shopUid = uid;
      _apply();
      return;
    }
    _shopUid = uid;
    _apply();
  }

  void _onAdmin(String? uid) {
    final signedIn = uid != null && uid.isNotEmpty;
    if (!signedIn) {
      // Nothing to bind and nothing to end: drop the record so the next admin
      // sign-in is treated as a fresh one and bound to whoever is signed into
      // the shop at that moment.
      _endPending = false;
      _bound = null;
      unawaited(_prefs.remove(storageKey));
    }
    _adminSignedIn = signedIn;
    _apply();
  }

  void _apply() {
    if (!_boundLoaded) return;
    switch (judgeAdminSession(
      shopResolved: _shopResolved,
      shopUid: _shopUid,
      adminSignedIn: _adminSignedIn,
      boundShopUid: _bound,
      endPending: _endPending,
    )) {
      case AdminSessionVerdict.wait:
      case AdminSessionVerdict.keep:
        return;
      case AdminSessionVerdict.bind:
        _bound = shopKeyOf(_shopUid);
        unawaited(_prefs.setString(storageKey, _bound!));
      case AdminSessionVerdict.end:
        _endPending = true;
        endedCount++;
        _bound = null;
        unawaited(_prefs.remove(storageKey));
        unawaited(_endAdminSession());
    }
  }

  void dispose() {
    _shopSub?.cancel();
    _adminSub?.cancel();
  }
}
