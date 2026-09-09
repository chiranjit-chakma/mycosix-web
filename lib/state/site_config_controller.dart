import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../firebase/fb.dart';
import '../models/site_settings.dart';

/// Live site settings for widgets that render admin-editable lines (contact
/// number, Instagram, delivery area, tagline...). In the running app the
/// controller is always provided above the whole tree, so this returns the
/// live value and rebuilds when an admin saves Settings. When the controller
/// is absent (a widget test building just one page) it falls back to the
/// bundled defaults so the widget is harmless to render in isolation.
SiteSettings liveSiteSettings(BuildContext context) {
  try {
    return context.watch<SiteConfigController>().settings;
  } on ProviderNotFoundException {
    return const SiteSettings();
  }
}

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

  /// True only while the owner's temporary-code fallback is switched on in
  /// Settings (siteConfig/public whatsappCodeFallback). While true the
  /// checkout shows the temporary code path; absent/false means real codes.
  bool get whatsappCodeFallback => _settings.whatsappCodeFallback;

  /// Whether the Admin entry is shown in the site navigation (the toggle
  /// beside Logout in the admin area). The entry is a doorway to the admin
  /// gate, which still demands a server-verified administrator, so it is
  /// never an authorisation signal on its own.
  bool get adminNavShortcutEnabled => _settings.adminNavShortcutEnabled;

  /// The public web-push (VAPID) key the owner pasted into Settings, or ''
  /// until they do. An empty key keeps FCM token registration dormant.
  String get pushVapidPublicKey => _settings.pushVapidPublicKey;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  /// Opens the live subscription to the public settings document. Called once
  /// when the app provides this controller.
  void start() {
    if (!Fb.enabled || _sub != null) return;
    _sub = Fb.siteConfig
        .doc('public')
        .snapshots()
        .listen(
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
