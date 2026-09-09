/// MYCOSIX site configuration — values the business can change.
///
/// Everything here is plain data, read at startup and injected through
/// [AppDependencies]. A future ConfigRepository (Firebase remote config or a
/// hosted JSON) can replace these defaults.
class MxConfig {
  MxConfig._();

  static const brandName = 'MYCOSIX';
  static const brandFull = 'MYCOSIX MUSHROOMS';
  static const tagline = 'Fresh by Us. Naturally Good.';
  static const heroStatement = 'GROWN DIFFERENT.';
  static const heroSub = 'Fresh by Us. Naturally Good.';

  static const instagramHandle = 'mycosix_mushroom';
  static const instagramUrl = 'https://instagram.com/mycosix_mushroom';

  static const whatsappNumber = '916363816465'; // +91 63638 16465
  static const whatsappDisplay = '+91 63638 16465';

  /// Map embedding / deep links. `{lat}` and `{lng}` are replaced at runtime.
  static const mapsEmbedUrl =
      'https://www.google.com/maps?q={lat},{lng}&z=16&output=embed';

  static const teamMembers = <String>[
    'Chandan',
    'Hruday',
    'Preetham',
    'Jashwanth',
    'Neha',
    'Varshini',
  ];

  static const deliveryFee = 39.0;

  /// Hard per-line ceiling (copies of one product in a single order). Real
  /// stock is the tighter binder — this only stops an accidental 99+ and keeps
  /// the WhatsApp order message legible. Bulk / catering orders go through
  /// WhatsApp directly, so raise here when the business wants larger carts.
  static const maxUnitsPerProduct = 12;

  /// Orders are confirmed on WhatsApp; delivery is arranged there.
  static const orderLeadTime = 'Same day or next morning';

  /// Delivery service area shown in site copy (footer, product pages). This is
  /// the business's call — edit here when the delivery footprint changes.
  static const serviceArea = 'Mysore, Karnataka';

  /// Where the delivery map first centres when a customer has no saved pin
  /// yet (the business's home city). The customer can drag the pin anywhere
  /// in the world from here; it is only a starting view, never a restriction.
  static const defaultLatitude = 12.2958;
  static const defaultLongitude = 76.6394;

  /// Closed-app / background push notifications: the CLIENT stack is LIVE.
  ///
  /// On: the FCM registration keeper runs, asks for notification permission
  /// and registers the device's push token under the signed-in account's
  /// fcmTokens/{uid} document so the backend can later deliver. It stays fully
  /// dormant until a web-push (VAPID) key is present: the keeper reads the
  /// PUBLIC half at runtime from siteConfig/public `pushVapidPublicKey` (the
  /// owner pastes it in Admin -> Settings, or fills [pushVapidKey] below) -
  /// the PRIVATE half lives only in the Firebase console under Project
  /// settings -> Cloud Messaging. The automated SENDER (the notification
  /// Cloud Functions in `functions/notify_core.js`) is still gated behind the
  /// paid (Blaze) plan and stays undeployed until the owner approves it; the
  /// open-app banner alerts do NOT depend on any of this - they work today on
  /// the free plan.
  static const pushNotificationsEnabled = true;

  /// Build-time fallback for the PUBLIC web-push key. The live source is
  /// siteConfig/public `pushVapidPublicKey` (set in Admin -> Settings); this
  /// constant is used only when that runtime value is blank. An empty key
  /// keeps the registration keeper dormant.
  static const pushVapidKey = '';
}
