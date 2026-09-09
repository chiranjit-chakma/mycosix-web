import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../config/mx_config.dart';
import '../firebase/fb.dart';
import '../models/fcm_registry.dart';
import '../models/order_notice.dart';
import 'order_alert_controller.dart';
import 'site_config_controller.dart';

/// Registers the browser/PWA's FCM token under the signed-in account's
/// fcmTokens/{uid} document so the notification backend can push while the app
/// is closed/backgrounded.
///
/// LIVE on the client side - imported from main(). The stack arms the moment
/// all three conditions hold: Firebase is up ([Fb.enabled]), push is enabled
/// in [MxConfig], and a web-push (VAPID) key is present. The key is read at
/// runtime from siteConfig/public `pushVapidPublicKey` (the owner pastes it in
/// Admin -> Settings; [MxConfig.pushVapidKey] is the build-time fallback), so
/// the owner never needs a rebuild - and the PRIVATE half never leaves the
/// Firebase console.
///
/// Until the key exists the keeper stays fully dormant: no permission request,
/// no network call, no change to the customer experience. It re-evaluates when
/// the settings document changes, so pasting the key starts registration on
/// the next app event without a deploy.
///
/// The SENDER side (the Cloud Functions that actually deliver pushes) is a
/// separate, undeployed piece - it stays dormant until the owner moves the
/// project to the paid plan. The open-app banner alerts do not depend on any
/// of this; they are Firestore-driven and work on the free plan today.
///
/// Rules: the owner-writable fcmTokens/{uid} allows exactly this - the signed-
/// in uid writing only its own document - and denies everyone else, so a token
/// can never be read or replaced by another account.
class FcmRegistrationKeeper {
  FcmRegistrationKeeper({
    SiteConfigController? siteConfigController,
    OrderAlertController? alertsController,
  }) : _siteConfig = siteConfigController,
       _alerts = alertsController {
    _siteConfig?.addListener(_maybeArm);
    _maybeArm();
  }

  final SiteConfigController? _siteConfig;
  final OrderAlertController? _alerts;

  FirebaseMessaging? _messaging;
  StreamSubscription<Object?>? _authSub;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;

  String? _uid; // the account the registered token belongs to
  String? _token; // this device's current token

  /// Re-evaluates whether the stack should be armed. Safe to call repeatedly:
  /// while not yet eligible nothing happens (and this fires again the moment
  /// the VAPID key arrives through the settings listener); once armed it only
  /// retries a missing registration (permission granted later in the browser,
  /// or a key that arrived after a first denied attempt).
  void _maybeArm() {
    if (!Fb.enabled) return;
    if (!MxConfig.pushNotificationsEnabled) return;
    if (_vapid().isEmpty) return;
    if (_messaging == null) {
      _arm();
      return;
    }
    final uid = _uid ?? Fb.auth.currentUser?.uid;
    if (uid != null && _token == null) {
      unawaited(_register(uid));
    }
  }

  String _vapid() {
    final live = _siteConfig?.settings.pushVapidPublicKey.trim() ?? '';
    if (live.isNotEmpty) return live;
    return MxConfig.pushVapidKey.trim();
  }

  void _arm() {
    _messaging = FirebaseMessaging.instance;
    // App-open pushes become the same banner the Firestore watchers raise,
    // deduplicated on the shared event key so an event arriving through both
    // channels still shows as exactly one banner.
    // onMessage is a static stream on the plugin; the instance is only
    // needed for getToken/requestPermission below.
    _foregroundSub = FirebaseMessaging.onMessage.listen(_onForeground);
    _authSub = Fb.auth.authStateChanges().listen((user) async {
      final uid = user?.uid;
      if (uid == _uid) return; // same account: nothing to do
      await _dropPrevious(); // sign-out or account switch: retire old token
      if (uid == null) return;
      _uid = uid;
      await _register(uid);
    });
  }

  void _onForeground(RemoteMessage message) {
    final alerts = _alerts;
    if (alerts == null) return;
    final data = message.data;
    final kind = (data['mxKind'] as String?) ?? '';
    final orderDocId = (data['orderDocId'] as String?) ?? '';
    final orderCode = (data['orderCode'] as String?) ?? orderDocId;
    final statusLabel = (data['status'] as String?) ?? '';
    final alert = orderAlertForPushMessage(
      kind: kind,
      orderDocId: orderDocId,
      orderCode: orderCode,
      statusLabel: statusLabel,
    );
    if (alert == null) return;
    alerts.presentIfFresh(
      alert,
      eventKey: pushEventKey(
        kind: kind,
        orderDocId: orderDocId,
        statusLabel: statusLabel,
      ),
    );
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
        // User declined notifications on this device. Browsers do not re-prompt
        // on requestPermission; granting later in the browser's own site
        // settings lets the next pass (VAPID change / next launch) register.
        return;
      }
      final token = await m.getToken(vapidKey: _vapid());
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
          ? (snap.data()?['tokens'] as List?)?.cast<String>() ??
                const <String>[]
          : const <String>[];
      final next = remove
          ? withoutToken(current, token)
          : upsertToken(current, token);
      await ref.set(<String, Object>{'tokens': next});
    } catch (_) {
      // Firestore unreachable (offline / not yet initialised): the device
      // keeps its local token and a later registration pass reconciles the
      // list.
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
    _siteConfig?.removeListener(_maybeArm);
    _foregroundSub?.cancel();
    _foregroundSub = null;
    unawaited(_dropPrevious());
    _authSub?.cancel();
    _authSub = null;
  }
}
