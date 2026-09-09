import '../config/mx_config.dart';
import 'delivery_tier.dart';

/// Site-wide configuration the business controls.
///
/// Only values that are actually known are populated. Anything the business
/// has not told us stays empty/null and remains configurable — nothing here is
/// ever invented. Defaults come from [MxConfig]; a `siteConfig/public`
/// Firestore document can override them remotely.
class SiteSettings {
  const SiteSettings({
    this.businessName = MxConfig.brandFull,
    this.tagline = MxConfig.tagline,
    this.whatsappNumber = MxConfig.whatsappNumber,
    this.instagramUrl = MxConfig.instagramUrl,
    this.deliveryFee = MxConfig.deliveryFee,
    this.currency = 'INR',
    this.deliveryEnabled = true,
    this.whatsappCodeFallback = false,
    this.serviceArea = MxConfig.serviceArea,
    this.orderLeadTime = MxConfig.orderLeadTime,
    this.mapsEmbedUrl = MxConfig.mapsEmbedUrl,
    this.supportEmail,
    this.phoneNumber,
    this.shopLatitude,
    this.shopLongitude,
    this.deliveryTiers = const [],
  });

  final String businessName;
  final String tagline;
  final String whatsappNumber;
  final String instagramUrl;
  final double deliveryFee;
  final String currency;

  /// When false the site should not offer delivery (checkout stays open for
  /// pick-up only once that flow exists).
  final bool deliveryEnabled;

  /// Temporary-code fallback while real SMS codes are not available: when an
  /// admin sets this true on siteConfig/public, the checkout accepts the
  /// published temporary code (123456) and the orders rules/functions accept
  /// the phoneVerified marker as the proof. Defaults false; a doc that omits
  /// the field means fallback off.
  final bool whatsappCodeFallback;
  final String serviceArea;
  final String orderLeadTime;
  final String mapsEmbedUrl;

  /// Known business contact details. Null/empty until the business supplies
  /// them — the site never guesses these.
  final String? supportEmail;
  final String? phoneNumber;

  /// The farm/shop delivery point, and the distance bands that price
  /// delivery. Until an admin sets BOTH the shop coordinates AND at least one
  /// tier, delivery stays on the flat [deliveryFee] (the legacy behaviour);
  /// once set, every delivery charge is the fee of the first tier whose
  /// `upToKm` covers the straight-line distance from the customer's pin to
  /// the shop — and a pin beyond the last tier is outside the delivery area.
  final double? shopLatitude;
  final double? shopLongitude;
  final List<DeliveryTier> deliveryTiers;

  /// Whether distance-based delivery pricing is switched on (a shop point and
  /// at least one valid tier are configured).
  bool get hasDistancePricing =>
      shopLatitude != null &&
      shopLongitude != null &&
      deliveryTiers.any((t) => t.isValid);

  /// The furthest distance any tier covers; null when pricing is not on.
  double? get maxDeliveryKm {
    if (!hasDistancePricing) return null;
    var max = 0.0;
    for (final t in deliveryTiers) {
      if (t.isValid && t.upToKm > max) max = t.upToKm;
    }
    return max;
  }

  /// Formats a stored WhatsApp number (digits, country code first) for display.
  static String displayNumber(String digits) {
    var d = digits.replaceAll(RegExp(r'\D'), '');
    if (d.length > 10 && d.startsWith('91')) {
      d = d.substring(2);
    }
    if (d.length == 10) {
      return '+91 ${d.substring(0, 5)} ${d.substring(5)}';
    }
    return digits;
  }

  SiteSettings copyWith({
    String? businessName,
    String? tagline,
    String? whatsappNumber,
    String? instagramUrl,
    double? deliveryFee,
    String? currency,
    bool? deliveryEnabled,
    bool? whatsappCodeFallback,
    String? serviceArea,
    String? orderLeadTime,
    String? mapsEmbedUrl,
    String? supportEmail,
    String? phoneNumber,
    double? shopLatitude,
    double? shopLongitude,
    List<DeliveryTier>? deliveryTiers,
  }) {
    return SiteSettings(
      businessName: businessName ?? this.businessName,
      tagline: tagline ?? this.tagline,
      whatsappNumber: whatsappNumber ?? this.whatsappNumber,
      instagramUrl: instagramUrl ?? this.instagramUrl,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      currency: currency ?? this.currency,
      deliveryEnabled: deliveryEnabled ?? this.deliveryEnabled,
      whatsappCodeFallback: whatsappCodeFallback ?? this.whatsappCodeFallback,
      serviceArea: serviceArea ?? this.serviceArea,
      orderLeadTime: orderLeadTime ?? this.orderLeadTime,
      mapsEmbedUrl: mapsEmbedUrl ?? this.mapsEmbedUrl,
      supportEmail: supportEmail ?? this.supportEmail,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      shopLatitude: shopLatitude ?? this.shopLatitude,
      shopLongitude: shopLongitude ?? this.shopLongitude,
      deliveryTiers: deliveryTiers ?? this.deliveryTiers,
    );
  }

  /// Maps for storage. Known values are always written; unknown optional
  /// values are omitted (or null) so "unset" is distinguishable from empty.
  Map<String, Object?> toMap() => {
    'businessName': businessName,
    'tagline': tagline,
    'whatsappNumber': whatsappNumber,
    'instagramUrl': instagramUrl,
    'deliveryFee': deliveryFee,
    'currency': currency,
    'deliveryEnabled': deliveryEnabled,
    'whatsappCodeFallback': whatsappCodeFallback,
    'serviceArea': serviceArea,
    'orderLeadTime': orderLeadTime,
    'mapsEmbedUrl': mapsEmbedUrl,
    'supportEmail': supportEmail,
    'phoneNumber': phoneNumber,
    if (shopLatitude != null) 'shopLatitude': shopLatitude,
    if (shopLongitude != null) 'shopLongitude': shopLongitude,
    if (deliveryTiers.isNotEmpty)
      'deliveryTiers': [for (final t in deliveryTiers) t.toMap()],
  };

  factory SiteSettings.fromMap(Map<String, dynamic> map) {
    String? clean(String? v) {
      final t = v?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    return SiteSettings(
      businessName: clean(map['businessName'] as String?) ?? MxConfig.brandFull,
      tagline: clean(map['tagline'] as String?) ?? MxConfig.tagline,
      whatsappNumber:
          clean(map['whatsappNumber'] as String?) ?? MxConfig.whatsappNumber,
      instagramUrl:
          clean(map['instagramUrl'] as String?) ?? MxConfig.instagramUrl,
      deliveryFee: ((map['deliveryFee'] ?? MxConfig.deliveryFee) as num)
          .toDouble(),
      currency: clean(map['currency'] as String?) ?? 'INR',
      deliveryEnabled: map['deliveryEnabled'] as bool? ?? true,
      whatsappCodeFallback: map['whatsappCodeFallback'] as bool? ?? false,
      serviceArea: clean(map['serviceArea'] as String?) ?? MxConfig.serviceArea,
      orderLeadTime:
          clean(map['orderLeadTime'] as String?) ?? MxConfig.orderLeadTime,
      mapsEmbedUrl:
          clean(map['mapsEmbedUrl'] as String?) ?? MxConfig.mapsEmbedUrl,
      supportEmail: clean(map['supportEmail'] as String?),
      phoneNumber: clean(map['phoneNumber'] as String?),
      shopLatitude: map['shopLatitude'] == null
          ? null
          : (map['shopLatitude'] as num).toDouble(),
      shopLongitude: map['shopLongitude'] == null
          ? null
          : (map['shopLongitude'] as num).toDouble(),
      deliveryTiers: _tiersFrom(map['deliveryTiers']),
    );
  }

  /// Reads the stored tier list defensively: invalid or non-map entries are
  /// dropped, valid tiers are kept and sorted by distance ascending (the
  /// pricing walk relies on that order). Anything unreadable reads as no
  /// tiers — which simply means flat-fee delivery, never a crash.
  static List<DeliveryTier> _tiersFrom(Object? raw) {
    if (raw is! List) return const [];
    final tiers = <DeliveryTier>[];
    for (final entry in raw) {
      final t = DeliveryTier.fromMap(entry);
      if (t.isValid) tiers.add(t);
    }
    tiers.sort((a, b) => a.upToKm.compareTo(b.upToKm));
    return tiers;
  }
}
