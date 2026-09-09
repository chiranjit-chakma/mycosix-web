import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../config/mx_config.dart';
import '../firebase/fb.dart';
import '../models/fcm_registry.dart';

/// Registers the browser/PWA's FCM token under the signed-in account's
/// fcmTokens/{uid} document so the notification backend can push while the app
/// is closed/backgrounded.
///
/// DORMANT BY DESIGN - nothing here runs today:
///  - [MxConfig.pushNotificationsEnabled] is `false` (the free plan cannot run
///    the sending Cloud Functions, which is the owner's paid-plan decision);
///  - the web-push (VAPID) key is empty until the owner adds one in the
///    Firebase console and pastes its public half into
///    [MxConfig.pushVapidKey] (the private half stays in the console).
/// This class is NOT imported from main() on purpose, so the live bundle is
/// byte-identical to a build without it. Enabling push is a small, documented
/// owner step: flip the config flag, fill the VAPID key, add the
/// `firebase-messaging-sw.js` service worker for web, and import this keeper
/// in main(). Because that sequence cannot run on the current free plan, it is
/// NOT VERIFIED against a live Firebase project - the pure token-list logic in
/// fcm_registry.dart, which this relies on, IS unit-tested.
///
/// Rules: the owner-writable fcmTokens/{uid} allows exactly this - the signed-
/// in uid writing only its own document - and denies everyone else.
class FcmRegistrationKeeper {
  FcmRegistrationKeeper() {
    if (!Fb.enabled) return;
    if (!MxConfig.pushNotificationsEnabled) return;
    if (MxConfig.pushVapidKey.trim().isEmpty) return;
    _arm();
  }

  FirebaseMessaging? _messaging;
  StreamSubscription<Object?>? _authSub;
  StreamSubscription<String>? _refreshSub;

  String? _uid; // the account the registered token belongs to
  String? _token; // this device's current token

  void _arm() {
    _messaging = FirebaseMessaging.instance;
    _authSub = Fb.auth.authStateChanges().listen((user) async {
      final uid = user?.uid;
      if (uid == _uid) return; // same account: nothing to do
      await _dropPrevious(); // sign-out or account switch: retire old token
      if (uid == null) return;
      _uid = uid;
      await _register(uid);
    });
  }

  Future<void> _register(String uid) async {
    try {
      final m = _messaging;
      if (m == null) return;
      final settings = await m.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return; // user declined notifications on this device - never retry here
      }
      final token = await m.getToken(vapidKey: MxConfig.pushVapidKey);
      if (token == null || token.isEmpty) return;
      _token = token;
      _refreshSub ??= m.onTokenRefresh.listen((fresh) {
        final old = _token;
        _token = fresh;
        if (_uid != null) {
          _persist(_uid!, fresh);
          if (old != null && old != fresh) _persist(_uid!, old, remove: true);
        }
      });
      await _persist(uid, token);
    } catch (_) {
      // Firebase messaging may be unconfigured for this web project (no
      // service worker / VAPID): stay silent and leave push off rather than
      // disturb the customer.
    }
  }

  /// Writes (or removes) one token on the signed-in user's own token doc.
  Future<void> _persist(String uid, String token, {bool remove = false}) async {
    try {
      final ref = Fb.db.collection('fcmTokens').doc(uid);
      final snap = await ref.get();
      final current = snap.exists
          ? (snap.data()?['tokens'] as List?)?.cast<String>() ?? const <String>[]
          : const <String>[];
      final next =
          remove ? withoutToken(current, token) : upsertToken(current, token);
      await ref.set(<String, Object>{'tokens': next});
    } catch (_) {
      // Firestore unreachable (offline / not yet initialised): the device keeps
      // its local token and a later registration pass reconciles the list.
    }
  }

  /// Removes this device's token when the account signs out or switches.
  Future<void> _dropPrevious() async {
    final uid = _uid;
    final token = _token;
    _uid = null;
    _token = null;
    await _refreshSub?.cancel();
    _refreshSub = null;
    if (uid != null && token != null) await _persist(uid, token, remove: true);
  }

  /// Drop this device's push registration before signing out. A call site
  /// that signs the user out should await this first, because after sign-out
  /// there is no longer an authenticated uid allowed to write fcmTokens.
  Future<void> unregister() => _dropPrevious();

  void dispose() {
    _dropPrevious();
    _authSub?.cancel();
    _authSub = null;
  }
}
