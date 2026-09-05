import '../config/mx_config.dart';

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
    this.serviceArea = MxConfig.serviceArea,
    this.orderLeadTime = MxConfig.orderLeadTime,
    this.mapsEmbedUrl = MxConfig.mapsEmbedUrl,
    this.supportEmail,
    this.phoneNumber,
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
  final String serviceArea;
  final String orderLeadTime;
  final String mapsEmbedUrl;

  /// Known business contact details. Null/empty until the business supplies
  /// them — the site never guesses these.
  final String? supportEmail;
  final String? phoneNumber;

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
    String? serviceArea,
    String? orderLeadTime,
    String? mapsEmbedUrl,
    String? supportEmail,
    String? phoneNumber,
  }) {
    return SiteSettings(
      businessName: businessName ?? this.businessName,
      tagline: tagline ?? this.tagline,
      whatsappNumber: whatsappNumber ?? this.whatsappNumber,
      instagramUrl: instagramUrl ?? this.instagramUrl,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      currency: currency ?? this.currency,
      deliveryEnabled: deliveryEnabled ?? this.deliveryEnabled,
      serviceArea: serviceArea ?? this.serviceArea,
      orderLeadTime: orderLeadTime ?? this.orderLeadTime,
      mapsEmbedUrl: mapsEmbedUrl ?? this.mapsEmbedUrl,
      supportEmail: supportEmail ?? this.supportEmail,
      phoneNumber: phoneNumber ?? this.phoneNumber,
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
        'serviceArea': serviceArea,
        'orderLeadTime': orderLeadTime,
        'mapsEmbedUrl': mapsEmbedUrl,
        'supportEmail': supportEmail,
        'phoneNumber': phoneNumber,
      };

  factory SiteSettings.fromMap(Map<String, dynamic> map) {
    String? clean(String? v) {
      final t = v?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    return SiteSettings(
      businessName:
          clean(map['businessName'] as String?) ?? MxConfig.brandFull,
      tagline: clean(map['tagline'] as String?) ?? MxConfig.tagline,
      whatsappNumber: clean(map['whatsappNumber'] as String?) ??
          MxConfig.whatsappNumber,
      instagramUrl:
          clean(map['instagramUrl'] as String?) ?? MxConfig.instagramUrl,
      deliveryFee: ((map['deliveryFee'] ?? MxConfig.deliveryFee) as num)
          .toDouble(),
      currency: clean(map['currency'] as String?) ?? 'INR',
      deliveryEnabled: map['deliveryEnabled'] as bool? ?? true,
      serviceArea: clean(map['serviceArea'] as String?) ?? MxConfig.serviceArea,
      orderLeadTime:
          clean(map['orderLeadTime'] as String?) ?? MxConfig.orderLeadTime,
      mapsEmbedUrl:
          clean(map['mapsEmbedUrl'] as String?) ?? MxConfig.mapsEmbedUrl,
      supportEmail: clean(map['supportEmail'] as String?),
      phoneNumber: clean(map['phoneNumber'] as String?),
    );
  }
}
