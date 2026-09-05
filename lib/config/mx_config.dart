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
  static const serviceArea = 'Hyderabad';
}
