import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/fb.dart';
import '../models/site_settings.dart';

/// Live site configuration the customer side watches.
///
/// [ConfigRepository] is loaded once at startup, so it can never reflect an
/// admin saving a change mid-session. This controller subscribes to the
/// `siteConfig/public` document instead and updates the moment an admin saves —
/// so switching "Delivery enabled" off in admin Settings stops customers
/// placing orders immediately, with no reload. When Firebase is off, or a
/// config read fails, it keeps the last good settings (which default to
/// delivery enabled), so a transient read problem never blocks a customer from
/// ordering — the site behaves exactly as before until a live update arrives.
class SiteConfigController extends ChangeNotifier {
  SiteConfigController({SiteSettings initial = const SiteSettings()})
      : _settings = initial;

  SiteSettings _settings;

  SiteSettings get settings => _settings;

  /// False only when an admin has explicitly turned delivery off in Settings.
  bool get deliveryEnabled => _settings.deliveryEnabled;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  /// Opens the live subscription to the public settings document. Called once
  /// when the app provides this controller.
  void start() {
    if (!Fb.enabled || _sub != null) return;
    _sub = Fb.siteConfig.doc('public').snapshots().listen(
          _applySnapshot,
          onError: (_) {
            // A transient config read error must never block ordering; keep the
            // last known settings.
          },
        );
  }

  void _applySnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists) return;
    final next = SiteSettings.fromMap(snap.data() ?? const {});
    if (_same(_settings, next)) return;
    _settings = next;
    notifyListeners();
  }

  static bool _same(SiteSettings a, SiteSettings b) {
    final am = a.toMap();
    final bm = b.toMap();
    if (am.length != bm.length) return false;
    for (final e in am.entries) {
      if (bm[e.key] != e.value) return false;
    }
    return true;
  }

  /// Test hook: applies new settings exactly as a live snapshot would, so
  /// widget tests can assert the site reacts without a reload.
  @visibleForTesting
  void applySettings(SiteSettings next) {
    if (_same(_settings, next)) return;
    _settings = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
