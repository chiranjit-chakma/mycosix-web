import '../models/site_settings.dart';

/// Runtime site configuration.
///
/// Bundled defaults come from [SiteSettings]/MxConfig; a Firestore
/// `siteConfig/public` document can override them remotely. The UI reads brand
/// copy from MxConfig for display; the economics that matter to orders
/// (whatsapp number, delivery fee) are threaded through here.
abstract class ConfigRepository {
  SiteSettings get settings;

  String get whatsappNumber => settings.whatsappNumber;

  String get instagramUrl => settings.instagramUrl;

  double get deliveryFee => settings.deliveryFee;

  /// Preloads remote configuration, falling back to defaults on any failure.
  /// Called once at startup.
  Future<void> load() async {}
}

/// Default configuration — the bundled, known MYCOSIX values.
class LocalConfigRepository extends ConfigRepository {
  @override
  SiteSettings get settings => const SiteSettings();
}
