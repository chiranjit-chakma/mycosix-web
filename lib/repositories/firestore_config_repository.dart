import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase/fb.dart';
import '../models/site_settings.dart';
import 'config_repository.dart';

/// Site configuration backed by the Firestore `siteConfig/public` document.
///
/// Values that are actually known are stored there; anything not yet supplied
/// by the business falls back to the bundled [MxConfig] defaults. Nothing is
/// invented. Admin edits to the document are authorised by Firestore rules.
class FirestoreConfigRepository extends ConfigRepository {
  FirestoreConfigRepository({this.loadTimeout = const Duration(seconds: 4)});

  final Duration loadTimeout;

  SiteSettings _settings = const SiteSettings();
  bool _loaded = false;

  @override
  SiteSettings get settings => _settings;

  @override
  Future<void> load() async {
    if (_loaded) return;
    try {
      final doc =
          await Fb.siteConfig.doc('public').get().timeout(loadTimeout);
      if (doc.exists) {
        _settings = SiteSettings.fromMap(doc.data() ?? const {});
      }
    } catch (e) {
      // Offline / rules not deployed yet: keep bundled defaults. The site
      // works exactly as before until the backend is connected.
      _loaded = true;
      return;
    }
    _loaded = true;
  }

  /// Pushes a settings patch to Firestore. Callers must have admin
  /// authorisation; the write is also gated by security rules.
  Future<void> savePatch(Map<String, Object?> patch) async {
    await Fb.siteConfig.doc('public').set(patch, SetOptions(merge: true));
  }
}
